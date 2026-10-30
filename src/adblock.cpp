#include "adblock.h"

#include <QDir>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QProcess>
#ifdef BROWSER_CEF
#include "cef/requests.h"
#include <QMutex>
#else
#include <QtWebEngineCore/QWebEngineUrlRequestInfo>
#include <QtWebEngineCore/QWebEngineUrlRequestInterceptor>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#endif

Q_LOGGING_CATEGORY(lcAdblock, "browser.adblock", QtInfoMsg)

extern "C" {
void *ab_new(const char *trusted, const char *other, const char *resources_json);
int ab_decide(const void *engine, const char *url, const char *source, const char *kind, char **out);
char *ab_cosmetic(const void *engine, const char *url);
void ab_free(char *p);
void ab_drop(void *engine);
}

// A page's address as the interceptor keys it: firstPartyUrl is the top document's full address (the
// request's own for a main-frame load), and a fragment never reaches the network.
static QString pageKey(const QUrl &url) {
    return url.adjusted(QUrl::RemoveFragment).toString();
}

// The engine's whole decision on a request (ab_decide): 0 allow, 1 block, 2 block with `*out` in its place (a data: URL),
// 3 load `*out` instead (the address without the parameters a removeparam filter strips)
static int decideRequest(const void *engine, const QByteArray &url, const QByteArray &source, const char *kind, QByteArray *out) {
    char *given = nullptr;
    const int decision = ab_decide(engine, url.constData(), source.constData(), kind, &given);
    if (given) {
        *out = QByteArray(given);
        ab_free(given);
    }
    return decision;
}

// This machine's addresses: an http request to them is no mixed content (Chromium counts them secure).
static bool loopback(const QString &host) {
    return host == u"localhost" || host.endsWith(u".localhost") || QHostAddress(host).isLoopback();
}

// The engine is single-threaded (adblock-rust's default single-thread feature). On CEF it is asked on the IO thread for
// requests and on the UI thread for a page's cosmetics, so every use holds this; Qt WebEngine asks only on the UI thread.
struct EngineLock {
#ifdef BROWSER_CEF
    static inline QMutex mutex;
    QMutexLocker<QMutex> locked{&mutex};
#else
    EngineLock() {}
#endif
};

#ifdef BROWSER_CEF
// CEF: the profile's filter (src/cef/requests.h), asked on the IO thread. What it writes there (the pages' counts) and what
// the UI thread writes (the allowed hosts) is kept under its handle's lock (SeenLock).
class AdblockInterceptor : public QObject, public RequestFilter {
public:
    AdblockInterceptor(const void *engine, QObject *parent) : QObject(parent), m_engine(engine) { m_handle->filter = this; }
    ~AdblockInterceptor() override {
        QMutexLocker locked(&m_handle->lock);
        m_handle->filter = nullptr;
    }
    RequestFilterRef handle() const { return m_handle; }

    // as interceptRequest below
    RequestDecision decide(const QUrl &request, const QUrl &first, const char *kind) override {
        const QString page = pageKey(first);
        if (qstrcmp(kind, "main_frame") == 0)
            m_seen.remove(page);
        Seen &seen = entry(page);
        if ((qstrcmp(kind, "image") == 0 || qstrcmp(kind, "media") == 0)
                && first.scheme() == u"https" && request.scheme() == u"http" && !loopback(request.host()))
            seen.insecureImages = true;
        RequestDecision decision;
        if (allowed.contains(first.host().toLower()))
            return decision;
        QElapsedTimer t;
        t.start();
        const QByteArray url = request.toEncoded();
        const QByteArray source = first.toEncoded();
        QByteArray given;
        int verdict;
        {
            EngineLock lock;
            if (!m_engine)
                return decision;
            verdict = decideRequest(m_engine, url, source, kind, &given);
        }
        m_nanos += t.nsecsElapsed();
        ++m_checked;
        if (verdict == 1 || verdict == 2) {
            ++m_blocked;
            ++seen.blocked;
            qCDebug(lcAdblock) << (verdict == 2 ? "stood in for" : "blocked") << url;
        }
        // a stand-in comes as data:<mime>;base64,<content>
        const qsizetype comma = given.indexOf(',');
        if (verdict == 2 && given.startsWith("data:") && comma > 0 && given.left(comma).endsWith(";base64")) {
            decision.action = RequestDecision::Serve;
            decision.mime = given.mid(5, comma - 5 - 7);
            decision.body = QByteArray::fromBase64(given.mid(comma + 1));
        } else if (verdict == 1 || verdict == 2) {
            decision.action = RequestDecision::Block;
        } else if (verdict == 3) {
            decision.action = RequestDecision::Load;
            decision.url = QUrl::fromEncoded(given);
        }
        return decision;
    }
#else
class AdblockInterceptor : public QWebEngineUrlRequestInterceptor {
public:
    AdblockInterceptor(const void *engine, QObject *parent) : QWebEngineUrlRequestInterceptor(parent), m_engine(engine) {}
#endif

    struct Seen {
        int blocked = 0;
        bool insecureImages = false;
        quint64 used = 0;
    };
    QSet<QString> allowed;

#ifndef BROWSER_CEF
    void interceptRequest(QWebEngineUrlRequestInfo &info) override {
        using R = QWebEngineUrlRequestInfo;
        const QUrl first = info.firstPartyUrl(), request = info.requestUrl();
        const QString page = pageKey(first);
        // a page loading afresh starts its counts again
        if (info.resourceType() == R::ResourceTypeMainFrame)
            m_seen.remove(page);
        Seen &seen = entry(page);
        // Chromium upgrades most of these to https before they get here; one that stays http is what the site
        // panel reports
        if ((info.resourceType() == R::ResourceTypeImage || info.resourceType() == R::ResourceTypeMedia)
                && first.scheme() == u"https" && request.scheme() == u"http" && !loopback(request.host()))
            seen.insecureImages = true;
        if (!m_engine || allowed.contains(first.host().toLower()))
            return;
        QElapsedTimer t;
        t.start();
        const QByteArray url = request.toEncoded();
        const QByteArray source = first.toEncoded();
        QByteArray given;
        const int verdict = decideRequest(m_engine, url, source, kind(info.resourceType()), &given);
        m_nanos += t.nsecsElapsed();
        ++m_checked;
        // a stand-in (2) is refused here like a block: Qt's interceptor cannot give the page a body
        if (verdict == 1 || verdict == 2) {
            info.block(true);
            ++m_blocked;
            ++seen.blocked;
            qCDebug(lcAdblock) << "blocked" << url;
        } else if (verdict == 3) {
            info.redirect(QUrl::fromEncoded(given));
        }
    }
#endif

    Seen seenOn(const QString &page) const { return m_seen.value(page); }
    void setEngine(const void *engine) { m_engine = engine; }

    QString stats() const {
        return QStringLiteral("checked %1, blocked %2, avg %3 us").arg(m_checked).arg(m_blocked)
            .arg(m_checked ? double(m_nanos) / double(m_checked) / 1000.0 : 0.0, 0, 'f', 1);
    }

private:
#ifndef BROWSER_CEF
    static const char *kind(QWebEngineUrlRequestInfo::ResourceType type) {
        using R = QWebEngineUrlRequestInfo;
        switch (type) {
        case R::ResourceTypeMainFrame:
        case R::ResourceTypeNavigationPreloadMainFrame: return "main_frame";
        case R::ResourceTypeSubFrame:
        case R::ResourceTypeNavigationPreloadSubFrame: return "sub_frame";
        case R::ResourceTypeStylesheet: return "stylesheet";
        case R::ResourceTypeScript:
        case R::ResourceTypeWorker:
        case R::ResourceTypeSharedWorker:
        case R::ResourceTypeServiceWorker: return "script";
        case R::ResourceTypeImage:
        case R::ResourceTypeFavicon: return "image";
        case R::ResourceTypeFontResource: return "font";
        case R::ResourceTypeObject:
        case R::ResourceTypePluginResource: return "object";
        case R::ResourceTypeMedia: return "media";
        case R::ResourceTypeXhr: return "xmlhttprequest";
        case R::ResourceTypePing: return "ping";
        case R::ResourceTypeCspReport: return "csp_report";
        case R::ResourceTypeWebSocket: return "websocket";
        default: return "other";
        }
    }
#endif

    // The page's counts; the 256 pages seen last are kept.
    Seen &entry(const QString &page) {
        auto it = m_seen.find(page);
        if (it == m_seen.end()) {
            if (m_seen.size() >= 256) {
                auto oldest = m_seen.begin();
                for (auto i = m_seen.begin(); i != m_seen.end(); ++i)
                    if (i->used < oldest->used)
                        oldest = i;
                m_seen.erase(oldest);
            }
            it = m_seen.insert(page, {});
        }
        it->used = ++m_tick;
        return *it;
    }

    const void *m_engine;
#ifdef BROWSER_CEF
    RequestFilterRef m_handle = std::make_shared<RequestFilterHandle>();
#endif
    qint64 m_nanos = 0, m_checked = 0, m_blocked = 0;
    QHash<QString, Seen> m_seen;
    quint64 m_tick = 0;
};

// CEF: holds the interceptor's handle lock while the UI thread reads or writes what refuse() writes on the IO thread
struct SeenLock {
#ifdef BROWSER_CEF
    explicit SeenLock(const AdblockInterceptor *interceptor) : locked(interceptor ? &interceptor->handle()->lock : nullptr) {}
    QMutexLocker<QMutex> locked;
#else
    explicit SeenLock(const AdblockInterceptor *) {}
#endif
};

// The engine from the lists and resources under `dataDir`, or null with no lists; and what each list says of itself.
// uBlock Origin's own lists (ubo-*, and the inc-* files their !#include pulls in) may use trusted scriptlets, as in uBO
// itself; third-party lists may not. Runs on the UI thread at start and on a worker thread after an update. `build` false
// only reads what the lists say of themselves (the engine would never be asked).
static void *buildEngine(const QString &dataDir, QVariantList *lists, bool build = true) {
    QElapsedTimer t;
    t.start();
    QByteArray trusted, other;
    const QString listsDir = dataDir + QStringLiteral("/lists");
    for (const QString &name : QDir(listsDir).entryList({QStringLiteral("*.txt")}, QDir::Files)) {
        QFile file(listsDir + u'/' + name);
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QByteArray text = file.readAll();
        (name.startsWith(u"ubo-") || name.startsWith(u"inc-") ? trusted : other) += text + '\n';
        if (name.startsWith(u"inc-"))
            continue;
        // "! Title: EasyList", "! Version: 202609281234" in the list's first lines
        QVariantMap list{{QStringLiteral("file"), name.chopped(4)},
                         {QStringLiteral("modified"), double(QFileInfo(file).lastModified().toMSecsSinceEpoch())}};
        for (const QByteArray &line : text.left(4096).split('\n')) {
            const QByteArray l = line.trimmed();
            if (l.startsWith("! Title:"))
                list.insert(QStringLiteral("title"), QString::fromUtf8(l.mid(8).trimmed()));
            else if (l.startsWith("! Version:"))
                list.insert(QStringLiteral("version"), QString::fromUtf8(l.mid(10).trimmed()));
        }
        lists->append(list);
    }
    if (trusted.isEmpty() && other.isEmpty()) {
        qCWarning(lcAdblock) << "no filter lists in" << listsDir << "- run tools/update-lists; ad blocking is off";
        return nullptr;
    }
    if (!build)
        return nullptr;
    QFile resources(dataDir + QStringLiteral("/resources.json"));
    const QByteArray resourcesJson = resources.open(QIODevice::ReadOnly) ? resources.readAll() : QByteArray("[]");
    void *engine = ab_new(trusted.constData(), other.constData(), resourcesJson.constData());
    qCInfo(lcAdblock) << "engine built from" << (trusted.size() + other.size()) << "bytes of filters in" << t.elapsed() << "ms";
    return engine;
}

Adblock::Adblock(const QString &dataDir, QObject *parent) : QObject(parent), m_dataDir(dataDir) {
    m_script = QCoreApplication::applicationDirPath() + QStringLiteral("/../tools/update-lists");
    // with uBlock Origin Lite blocking nothing asks the engine (requestFilter unset, cosmetic() empty)
    m_engine = buildEngine(dataDir, &m_lists, !extensionBlocks);
}

Adblock::~Adblock() {
    if (m_builder.joinable())
        m_builder.join();
    EngineLock lock;
    for (AdblockInterceptor *interceptor : std::as_const(m_interceptors))
        interceptor->setEngine(nullptr);
    ab_drop(m_engine);
}

void Adblock::setUpdateScript(const QString &path) {
    if (!checkMode || path == m_script)
        return;
    m_script = path;
    emit updatingChanged();
}

void Adblock::update() {
    if (m_updating)
        return;
    const QString script = QFileInfo(m_script).canonicalFilePath();
    if (script.isEmpty()) {
        emit updated(QStringLiteral("The update script is not at ") + QDir::cleanPath(m_script));
        return;
    }
    m_updating = true;
    emit updatingChanged();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (code != 0 || status != QProcess::NormalExit) {
            // curl and the script say what went wrong on their last line
            const QList<QByteArray> said = process->readAllStandardError().trimmed().split('\n');
            m_updating = false;
            emit updatingChanged();
            emit updated(said.isEmpty() || said.last().trimmed().isEmpty() ? QStringLiteral("The update stopped with code %1").arg(code)
                                                                           : QString::fromUtf8(said.last().trimmed()));
            return;
        }
        if (m_builder.joinable())
            m_builder.join();
        // a quit waits for it (~Adblock); the call back is dropped with this object
        m_builder = std::thread([this, dir = m_dataDir] {
            QVariantList lists;
            void *engine = buildEngine(dir, &lists);
            QMetaObject::invokeMethod(this, [this, engine, lists] { finishUpdate(engine, lists); }, Qt::QueuedConnection);
        });
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_updating = false;
        emit updatingChanged();
        emit updated(QStringLiteral("The update script did not start: ") + process->errorString());
    });
    // tools/update-lists is POSIX sh; through sh, a copy without its executable bit runs too
    process->start(QStringLiteral("sh"), {script});
}

// On the UI thread, where the interceptors and cosmetic() read the engine: the new one takes over, the old one goes.
void Adblock::finishUpdate(void *engine, const QVariantList &lists) {
    m_updating = false;
    if (!engine) {
        emit updatingChanged();
        emit updated(QStringLiteral("The update left no filter lists"));
        return;
    }
    void *old = m_engine;
    {
        EngineLock lock;
        m_engine = engine;
        for (AdblockInterceptor *interceptor : std::as_const(m_interceptors))
            interceptor->setEngine(engine);
        ab_drop(old);
    }
    m_lists = lists;
    emit listsChanged();
    emit updatingChanged();
    emit updated(QString());
}

// Installed without filter lists too: the site panel's mixed-content line comes from it. A private window's
// interceptor goes once its profile has: the interceptor runs on the UI thread, and the profile keeps only a
// guarded pointer to it.
void Adblock::attach(QObject *profile) {
#ifdef BROWSER_CEF
    QObject *p = profile;
#else
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
#endif
    if (!p || m_interceptors.contains(p))
        return;
    auto *interceptor = new AdblockInterceptor(m_engine, this);
    m_interceptors.insert(p, interceptor);
    if (!m_first)
        m_first = interceptor;
    connect(p, &QObject::destroyed, this, [this, p] {
        AdblockInterceptor *gone = m_interceptors.take(p);
        if (gone == m_first)
            m_first = nullptr;
        if (gone)
            gone->deleteLater();
    });
#ifdef BROWSER_CEF
    // the profile's pages ask it on CEF's IO thread (PageItem::setProfile); with uBlock Origin Lite they ask nothing
    if (!extensionBlocks)
        p->setProperty("requestFilter", QVariant::fromValue(interceptor->handle()));
#else
    p->setUrlRequestInterceptor(interceptor);
#endif
}

AdblockInterceptor *Adblock::interceptorOf(QObject *profile) const {
    return profile ? m_interceptors.value(profile) : m_first;
}

void Adblock::setAllowed(const QStringList &hosts, QObject *profile) {
    AdblockInterceptor *interceptor = interceptorOf(profile);
    if (!interceptor)
        return;
    SeenLock lock(interceptor);
    interceptor->allowed.clear();
    for (const QString &host : hosts)
        interceptor->allowed.insert(host.toLower());
}

QVariantMap Adblock::seen(const QString &url, QObject *profile) const {
    const AdblockInterceptor *interceptor = interceptorOf(profile);
    SeenLock lock(interceptor);
    const AdblockInterceptor::Seen s = interceptor ? interceptor->seenOn(pageKey(QUrl(url))) : AdblockInterceptor::Seen();
    return {{QStringLiteral("blocked"), s.blocked}, {QStringLiteral("insecureImages"), s.insecureImages}};
}

QVariantMap Adblock::cosmetic(const QString &url, QObject *profile) const {
    if (extensionBlocks)
        return {};
    const AdblockInterceptor *interceptor = interceptorOf(profile);
    {
        SeenLock lock(interceptor);
        if (!m_engine || (interceptor && interceptor->allowed.contains(QUrl(url).host().toLower())))
            return {};
    }
    char *raw;
    {
        EngineLock lock;
        raw = ab_cosmetic(m_engine, url.toUtf8().constData());
    }
    const QJsonObject result = QJsonDocument::fromJson(raw).object();
    ab_free(raw);
    // One rule per selector: a single selector the page's CSS engine rejects would drop a combined rule.
    QString css;
    for (const QJsonValue &selector : result.value(u"hide").toArray())
        css += selector.toString() + QStringLiteral(" { display: none !important; }\n");
    // uBlock Origin's scriptlets share `scriptletGlobals`, which uBO declares around them; adblock-rust leaves that to the
    // embedder. Without it every scriptlet threw at its first line (2026-10-08) and no list's scriptlets ever ran.
    QString script = result.value(u"script").toString();
    if (!script.isEmpty())
        script = QStringLiteral("(() => {\nconst scriptletGlobals = {};\n") + script + QStringLiteral("\n})();");
    return {{QStringLiteral("css"), css}, {QStringLiteral("script"), script}};
}

QString Adblock::stats() const {
    SeenLock lock(m_first);
    return m_first ? m_first->stats() : QString();
}
