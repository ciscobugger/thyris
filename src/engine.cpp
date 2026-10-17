#include "engine.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QFileInfo>
#include <QImage>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickTextureFactory>
#include <QUrl>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QLibraryInfo>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#ifdef BROWSER_CEF
#include "cef/pageitem.h"
#include "include/cef_version.h"
#include "include/cef_scheme.h"
#include "include/cef_stream.h"
#include "include/wrapper/cef_stream_resource_handler.h"
#include <QUrl>
#else
#include <QtWebEngineCore/QWebEngineSettings>
#include <QtWebEngineCore/QWebEngineUrlRequestJob>
#include <QtWebEngineCore/QWebEngineUrlScheme>
#include <QtWebEngineCore/QWebEngineUrlSchemeHandler>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#include <QtWebEngineQuick/private/qquickwebenginesettings_p.h>
#endif

// The profile's settings object is private in Qt Quick (QQuickWebEngineProfile::settings()), and so is the
// QWebEngineSettings inside it, which alone has the font families and sizes. Both are reached as the standard allows
// for private members, through an explicit instantiation. Recheck after a Qt update, as for Windows.restore.
namespace {
#ifndef BROWSER_CEF
template <typename Tag, typename Tag::type Member>
struct Grant {
    friend typename Tag::type reach(Tag) { return Member; }
};
struct ProfileSettings {
    using type = QQuickWebEngineSettings *(QQuickWebEngineProfile::*)() const;
    friend type reach(ProfileSettings);
};
template struct Grant<ProfileSettings, &QQuickWebEngineProfile::settings>;
struct CoreSettings {
    using type = QScopedPointer<QWebEngineSettings> QQuickWebEngineSettings::*;
    friend type reach(CoreSettings);
};
template struct Grant<CoreSettings, &QQuickWebEngineSettings::d_ptr>;
#endif

QLoggingCategory::CategoryFilter otherFilter = nullptr;
void channelFilter(QLoggingCategory *category) {
    if (otherFilter)
        otherFilter(category);
    if (Engine::channelQuiet && qstrcmp(category->categoryName(), "qt.webengine.webchanneltransport") == 0) {
        category->setEnabled(QtDebugMsg, false);
        category->setEnabled(QtInfoMsg, false);
    }
}

#ifndef BROWSER_CEF
QWebEngineSettings *coreSettings(QObject *profile) {
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    QQuickWebEngineSettings *s = p ? (p->*reach(ProfileSettings{}))() : nullptr;
    return s ? (s->*reach(CoreSettings{})).data() : nullptr;
}

const struct {
    const char *key;
    QWebEngineSettings::FontFamily family;
} familyKeys[] = {
    {"standard", QWebEngineSettings::StandardFont},
    {"serif", QWebEngineSettings::SerifFont},
    {"sansSerif", QWebEngineSettings::SansSerifFont},
    {"fixed", QWebEngineSettings::FixedFont},
};
const struct {
    const char *key;
    QWebEngineSettings::FontSize size;
} sizeKeys[] = {
    {"size", QWebEngineSettings::DefaultFontSize},
    {"fixedSize", QWebEngineSettings::DefaultFixedFontSize},
    {"minimum", QWebEngineSettings::MinimumFontSize},
};

// The page each browser:// address stands for: an empty document with the page's name as its title. Main draws the
// page itself over the view; the document only gives it an entry in the view's history, a title and a load.
class OwnPages : public QWebEngineUrlSchemeHandler {
public:
    using QWebEngineUrlSchemeHandler::QWebEngineUrlSchemeHandler;
    void requestStarted(QWebEngineUrlRequestJob *job) override {
        const QByteArray title = Engine::ownTitle(job->requestUrl().host()).toUtf8();
        if (title.isEmpty() || job->requestMethod() != "GET") {
            job->fail(QWebEngineUrlRequestJob::UrlNotFound);
            return;
        }
        auto *body = new QBuffer(job);
        body->setData("<!doctype html><meta charset=utf-8><title>" + title + "</title>");
        body->open(QIODevice::ReadOnly);
        job->reply("text/html", body);
    }
};
#endif
}

QString Engine::ownTitle(const QString &host) {
    return host == u"settings" ? QStringLiteral("Settings") : host == u"pages" ? QStringLiteral("Pages and memory") : QString();
}

#ifdef BROWSER_CEF
namespace {
// browser:// on CEF (the scheme registered in src/cef/runtime.cpp and pageprocess.cpp): the same empty documents as
// OwnPages; no handler for any other address, so its load fails as Qt's does
class OwnPagesCef : public CefSchemeHandlerFactory {
public:
    CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString &, CefRefPtr<CefRequest> request) override {
        const QString title = Engine::ownTitle(QUrl(QString::fromStdString(request->GetURL().ToString())).host());
        if (title.isEmpty() || request->GetMethod().ToString() != "GET")
            return nullptr;
        const std::string body = "<!doctype html><meta charset=utf-8><title>" + title.toStdString() + "</title>";
        return new CefStreamResourceHandler("text/html", CefStreamReader::CreateForData(const_cast<char *>(body.data()), body.size()));
    }
private:
    IMPLEMENT_REFCOUNTING(OwnPagesCef);
};
}

Engine::Engine(QObject *parent) : QObject(parent) {}
#else
Engine::Engine(QObject *parent) : QObject(parent), m_handler(new OwnPages(this)) {}
#endif

static const QString faviconScheme = QStringLiteral("image://favicon/");

// one file per icon address, in the cache (the check's own under --check-engine)
QString Engine::iconFile(const QString &address) const {
    const QByteArray key = QCryptographicHash::hash(address.mid(faviconScheme.size()).toUtf8(), QCryptographicHash::Sha1).toHex();
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/icons/") + QString::fromLatin1(key)
           + QStringLiteral(".png");
}

QString Engine::keptIcon(const QString &address) {
    if (!address.startsWith(faviconScheme))
        return address;
    const QString file = iconFile(address);
    if (QFileInfo::exists(file))
        return QUrl::fromLocalFile(file).toString();
    // asked once the binding that wants it is done; iconRevision brings it back
    QMetaObject::invokeMethod(this, [this, address] { keepIcon(address); }, Qt::QueuedConnection);
    return QString();
}

void Engine::iconUnloaded(const QString &address, bool unloaded) {
    if (!address.startsWith(faviconScheme))
        return;
    const int n = m_unloaded.value(address) + (unloaded ? 1 : -1);
    if (n > 0)
        m_unloaded.insert(address, n);
    else
        m_unloaded.remove(address);
}

void Engine::keepIcon(const QString &address) {
    if (!address.startsWith(faviconScheme) || m_keeping.contains(address) || m_unanswered.contains(address)
        || m_unloaded.contains(address))
        return;
    const QString file = iconFile(address);
    if (QFileInfo::exists(file)) {
        QMetaObject::invokeMethod(this, [this, address, file] { ++m_iconRevision; emit iconKept(address, QUrl::fromLocalFile(file).toString()); },
                                  Qt::QueuedConnection);
        return;
    }
    // asked while the view that has the icon is live (BrowserView's iconChanged): the provider answers from it
    QQmlEngine *engine = qmlEngine(this);
    auto *provider = engine ? dynamic_cast<QQuickAsyncImageProvider *>(engine->imageProvider(QStringLiteral("favicon"))) : nullptr;
    if (!provider)
        return;
    m_keeping.insert(address);
    QQuickImageResponse *response = provider->requestImageResponse(address.mid(faviconScheme.size()), QSize(32, 32));
    connect(response, &QQuickImageResponse::finished, this, [this, response, address, file] {
        m_keeping.remove(address);
        QQuickTextureFactory *factory = response->textureFactory();
        const QImage image = factory ? factory->image() : QImage();
        delete factory;
        response->deleteLater();
        if (image.isNull() || !QDir().mkpath(QFileInfo(file).path()) || !image.save(file, "PNG")) {
            m_unanswered.insert(address);
            return;
        }
        ++m_iconRevision;
        emit iconKept(address, QUrl::fromLocalFile(file).toString());
    });
}

void Engine::quietChannel() {
    if (!otherFilter)
        otherFilter = QLoggingCategory::installFilter(channelFilter);
}

void Engine::prepare() {
#ifndef BROWSER_CEF
    QWebEngineUrlScheme scheme("browser");
    scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
    // Secure: no "Not secure" and no mixed-content rules; Local: a web page cannot load or open these addresses,
    // as it cannot open file: ones
    scheme.setFlags(QWebEngineUrlScheme::SecureScheme | QWebEngineUrlScheme::LocalScheme | QWebEngineUrlScheme::LocalAccessAllowed);
    QWebEngineUrlScheme::registerScheme(scheme);
#endif
    if (qEnvironmentVariableIsSet("QTWEBENGINE_DICTIONARIES_PATH"))
        return;
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/browser/dictionaries");
    QDir().mkpath(folder);
    qputenv("QTWEBENGINE_DICTIONARIES_PATH", QFile::encodeName(folder));
}

void Engine::attach(QObject *profile) {
#ifdef BROWSER_CEF
    // browser:// pages, once for the engine (CEF has one profile so far, slice 3)
    Q_UNUSED(profile)
    static const bool own = CefRegisterSchemeHandlerFactory("browser", "", new OwnPagesCef());
    Q_UNUSED(own)
#else
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (p && !p->urlSchemeHandler("browser"))
        p->installUrlSchemeHandler("browser", m_handler);
    // Chromium's name without the engine's own word: sites took "QtWebEngine/6.11.2" for an unknown browser (YouTube
    // started each video 1-1.5 s later than under Chrome's name, 2026-10-02). The Chrome version stays the real one.
    if (p)
        p->setHttpUserAgent(p->httpUserAgent().remove(QRegularExpression(QStringLiteral("QtWebEngine/\\S+ "))));
#endif
}

#ifdef BROWSER_CEF
// Settings' fonts as Chromium's preferences (the same that Chrome's Customize fonts sets): every script's family under
// Zyyy, the sizes in CSS px. Chromium hands them to the open pages at once.
const struct {
    const char *key;
    const char *pref;
} cefFontKeys[] = {
    {"standard", "webkit.webprefs.fonts.standard.Zyyy"}, {"serif", "webkit.webprefs.fonts.serif.Zyyy"},
    {"sansSerif", "webkit.webprefs.fonts.sansserif.Zyyy"}, {"fixed", "webkit.webprefs.fonts.fixed.Zyyy"},
    {"size", "webkit.webprefs.default_font_size"}, {"fixedSize", "webkit.webprefs.default_fixed_font_size"},
    {"minimum", "webkit.webprefs.minimum_font_size"},
};
#endif

void Engine::setFonts(QObject *profile, const QVariantMap &fonts) {
#ifdef BROWSER_CEF
    for (const auto &f : cefFontKeys) {
        const QVariant v = fonts.value(QLatin1String(f.key));
        const bool size = QByteArray(f.pref).endsWith("_size");
        // a family left empty or a size of 0: Chromium's own again
        const bool unset = size ? v.toInt() <= 0 : v.toString().trimmed().isEmpty();
        CefProfiles::get()->setPreference(profile, QLatin1String(f.pref),
                                          unset ? QVariant() : size ? QVariant(v.toInt()) : QVariant(v.toString().trimmed()));
    }
#else
    QWebEngineSettings *s = coreSettings(profile);
    if (!s)
        return;
    for (const auto &f : familyKeys) {
        const QString family = fonts.value(QLatin1String(f.key)).toString().trimmed();
        if (family.isEmpty())
            s->resetFontFamily(f.family);
        else
            s->setFontFamily(f.family, family);
    }
    for (const auto &f : sizeKeys) {
        const int px = fonts.value(QLatin1String(f.key)).toInt();
        if (px <= 0)
            s->resetFontSize(f.size);
        else
            s->setFontSize(f.size, px);
    }
#endif
}

QVariantMap Engine::fonts(QObject *profile) const {
#ifdef BROWSER_CEF
    QStringList prefs;
    for (const auto &f : cefFontKeys)
        prefs.append(QLatin1String(f.pref));
    const QVariantMap values = CefProfiles::get()->preferences(profile, prefs);
    QVariantMap out;
    for (const auto &f : cefFontKeys)
        if (values.contains(QLatin1String(f.pref)))
            out.insert(QLatin1String(f.key), values.value(QLatin1String(f.pref)));
    return out;
#else
    QWebEngineSettings *s = coreSettings(profile);
    QVariantMap out;
    if (!s)
        return out;
    for (const auto &f : familyKeys)
        out.insert(QLatin1String(f.key), s->fontFamily(f.family));
    for (const auto &f : sizeKeys)
        out.insert(QLatin1String(f.key), s->fontSize(f.size));
    return out;
#endif
}

QStringList Engine::families(bool fixed) const {
    QStringList out;
    for (const QString &family : QFontDatabase::families())
        if (!QFontDatabase::isPrivateFamily(family) && (!fixed || QFontDatabase::isFixedPitch(family)))
            out.append(family);
    return out;
}

QString Engine::dictionaryFolder() const {
    return qEnvironmentVariable("QTWEBENGINE_DICTIONARIES_PATH");
}

static QString hunspellFolder() {
    return Engine::hunspellOverride.isEmpty() ? QStringLiteral("/usr/share/hunspell") : Engine::hunspellOverride;
}

// a language as Chromium names it ("en-GB"): the only names a dictionary's path is made from
static bool validLanguage(const QString &language) {
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"));
    return valid.match(language).hasMatch();
}

QVariantMap Engine::dictionaries(const QStringList &languages) const {
    QVariantMap out;
    const QString folder = dictionaryFolder();
    for (const QString &language : languages) {
        if (!validLanguage(language))
            continue;
        const QString hunspell = hunspellFolder() + u'/' + QString(language).replace(u'-', u'_');
        if (!folder.isEmpty() && QFile::exists(folder + u'/' + language + QStringLiteral(".bdic")))
            out.insert(language, QStringLiteral("ready"));
        else if (QFile::exists(hunspell + QStringLiteral(".dic")) && QFile::exists(hunspell + QStringLiteral(".aff")))
            out.insert(language, QStringLiteral("hunspell"));
        else
            out.insert(language, QString());
    }
    return out;
}

void Engine::convert(const QStringList &languages) {
    const QVariantMap now = dictionaries(languages);
    QStringList left;
    for (const QString &language : languages)
        if (now.value(language).toString() == u"hunspell")
            left.append(language);
    convertNext(left, languages);
}

#ifdef BROWSER_CEF
// Chromium's spell checker reads <user data>/Dictionaries/<region><version>.bdic and downloads one it does not find there
// (components/spellcheck/common/spellcheck_common.cc): the dictionaries converted from hunspell's go there under its
// names, so nothing is fetched (154 reads the English ones as -10-2: it fetched en-GB-10-2.bdic when it had none).
static void placeForChromium(const QString &folder, const QStringList &languages) {
    static const QHash<QString, QString> regions = {
        {"af", "af-ZA"}, {"bg", "bg-BG"}, {"ca", "ca-ES"}, {"cs", "cs-CZ"}, {"cy", "cy-GB"}, {"da", "da-DK"}, {"de", "de-DE"},
        {"el", "el-GR"}, {"en", "en-US"}, {"es", "es-ES"}, {"es-419", "es-ES"}, {"es-AR", "es-ES"}, {"es-MX", "es-ES"},
        {"es-US", "es-ES"}, {"et", "et-EE"}, {"fa", "fa-IR"}, {"fo", "fo-FO"}, {"fr", "fr-FR"}, {"he", "he-IL"}, {"hi", "hi-IN"},
        {"hr", "hr-HR"}, {"hu", "hu-HU"}, {"id", "id-ID"}, {"it", "it-IT"}, {"lt", "lt-LT"}, {"lv", "lv-LV"}, {"nb", "nb-NO"},
        {"nl", "nl-NL"}, {"pl", "pl-PL"}, {"pt", "pt-BR"}, {"ro", "ro-RO"}, {"ru", "ru-RU"}, {"sk", "sk-SK"}, {"sl", "sl-SI"},
        {"sv", "sv-SE"}, {"ta", "ta-IN"}, {"tg", "tg-TG"}, {"tr", "tr-TR"}, {"uk", "uk-UA"}, {"vi", "vi-VN"},
    };
    static const QHash<QString, QStringList> versions = {
        {"tr-TR", {"-4-0"}}, {"tg-TG", {"-5-0"}}, {"cy-GB", {"-1-0"}}, {"hy", {"-1-0"}}, {"sh", {"-4-0"}}, {"sr", {"-4-0"}},
        {"fa-IR", {"-9-0"}}, {"uk-UA", {"-5-0"}}, {"gl", {"-1-0"}}, {"en-AU", {"-10-2"}}, {"en-CA", {"-10-2"}},
        {"en-GB", {"-10-2"}}, {"en-GB-oxendict", {"-10-2"}}, {"en-US", {"-10-2"}},
    };
    const QString data = CefProfiles::get()->dataPath();
    if (data.isEmpty())
        return;
    const QString target = data + QStringLiteral("/Dictionaries");
    QDir().mkpath(target);
    for (const QString &language : languages) {
        const QString source = folder + u'/' + language + QStringLiteral(".bdic");
        if (!QFile::exists(source))
            continue;
        const QString region = regions.value(language, language);
        for (const QString &version : versions.value(region, {QStringLiteral("-3-0")})) {
            // replaced: one Chromium fetched before spell check was off is not ours
            const QString name = target + u'/' + region + version + QStringLiteral(".bdic");
            QFile::remove(name);
            QFile::copy(source, name);
        }
    }
}
#endif

void Engine::convertNext(QStringList left, QStringList asked) {
    if (left.isEmpty() || dictionaryFolder().isEmpty()) {
#ifdef BROWSER_CEF
        placeForChromium(dictionaryFolder(), asked);
#endif
        emit converted(dictionaries(asked));
        return;
    }
    const QString language = left.takeFirst();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, left, asked] {
        process->deleteLater();
        convertNext(left, asked);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, left, asked](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        convertNext(left, asked);
    });
    process->start(QLibraryInfo::path(QLibraryInfo::LibraryExecutablesPath) + QStringLiteral("/qwebengine_convert_dict"),
                   {hunspellFolder() + u'/' + QString(language).replace(u'-', u'_') + QStringLiteral(".dic"),
                    dictionaryFolder() + u'/' + language + QStringLiteral(".bdic")});
}

QVariantMap Engine::versions() const {
#ifdef BROWSER_CEF
    return {
        {QStringLiteral("opsis"), QStringLiteral(OPSIS_VERSION)},
        {QStringLiteral("qt"), QString::fromLatin1(qVersion())},
        {QStringLiteral("webEngine"), QStringLiteral("CEF " CEF_VERSION)},
        {QStringLiteral("chromium"), QStringLiteral("%1.%2.%3.%4").arg(CHROME_VERSION_MAJOR).arg(CHROME_VERSION_MINOR)
                                         .arg(CHROME_VERSION_BUILD).arg(CHROME_VERSION_PATCH)},
        {QStringLiteral("security"), QString()},
    };
#else
    return {
        {QStringLiteral("opsis"), QStringLiteral(OPSIS_VERSION)},
        {QStringLiteral("qt"), QString::fromLatin1(qVersion())},
        {QStringLiteral("webEngine"), QString::fromLatin1(qWebEngineVersion())},
        {QStringLiteral("chromium"), QString::fromLatin1(qWebEngineChromiumVersion())},
        {QStringLiteral("security"), QString::fromLatin1(qWebEngineChromiumSecurityPatchVersion())},
    };
#endif
}

QString Engine::home() const {
    return QDir::homePath();
}

bool Engine::praxisHere() const {
    return !QStandardPaths::findExecutable(QStringLiteral("claude-hand")).isEmpty();
}

bool Engine::askPraxis(const QString &prompt) {
    const QString hand = QStandardPaths::findExecutable(QStringLiteral("claude-hand"));
    return !hand.isEmpty() && QProcess::startDetached(hand, {QStringLiteral("new"), QDir::homePath(), prompt});
}
