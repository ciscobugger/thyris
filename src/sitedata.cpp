#include "sitedata.h"

#include <QQmlEngine>
#ifdef BROWSER_CEF
#include <QDateTime>
#include "cef/cookies.h"
#else
#include <QtWebEngineCore/QWebEngineCookieStore>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#endif
#include <algorithm>

// Qt reports every change but INSERTED as a removal, and Chromium reports a cookie set again unchanged as
// the old one's OVERWRITE and the new one's INSERTED_NO_CHANGE_OVERWRITE: two removals of a cookie that is
// still there. A change of value comes as a removal and an addition. So a removal counts only when no second
// report for that cookie follows within 50 ms.
static constexpr int settleMs = 50;

SiteData::SiteData(QObject *parent) : QObject(parent) {
    m_clock.start();
    m_settle.setSingleShot(true);
    m_settle.setInterval(settleMs);
    connect(&m_settle, &QTimer::timeout, this, &SiteData::settle);
}

void SiteData::attach(QObject *profile) {
#ifdef BROWSER_CEF
    if (!profile || m_profile)
        return;
    m_profile = profile;
    reread();
    // a page finished a load: list again 150 ms later (one listing for a burst of loads)
    auto *soon = new QTimer(this);
    soon->setSingleShot(true);
    soon->setInterval(150);
    connect(soon, &QTimer::timeout, this, [this] {
        m_listed.invalidate();
        reread();
    });
    CefCookies::onTouched(this, [soon] { soon->start(); });
#else
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!p || m_store)
        return;
    m_store = p->cookieStore();
    connect(m_store, &QWebEngineCookieStore::cookieAdded, this, [this](const QNetworkCookie &cookie) {
        const QString k = key(cookie);
        m_removals.remove(k);
        set(k, cookie, true);
    });
    connect(m_store, &QWebEngineCookieStore::cookieRemoved, this, [this](const QNetworkCookie &cookie) {
        const QString k = key(cookie);
        // the second of a pair: the cookie was set again
        if (m_removals.remove(k) > 0)
            return;
        m_removals.insert(k, m_clock.elapsed());
        if (!m_settle.isActive())
            m_settle.start();
    });
    // the cookies kept from earlier runs arrive as cookieAdded
    m_store->loadAllCookies();
#endif
}

QObject *SiteData::forProfile(QObject *profile) {
#ifdef BROWSER_CEF
    if (!profile)
        return nullptr;
    auto *own = new SiteData(profile);
    QQmlEngine::setObjectOwnership(own, QQmlEngine::CppOwnership);
    own->attach(profile);
    return own;
#else
    if (!qobject_cast<QQuickWebEngineProfile *>(profile))
        return nullptr;
    auto *own = new SiteData(profile);
    QQmlEngine::setObjectOwnership(own, QQmlEngine::CppOwnership);
    own->attach(profile);
    return own;
#endif
}

QString SiteData::key(const QNetworkCookie &cookie) {
    return QString::fromUtf8(cookie.name()) + u'\n' + cookie.domain() + u'\n' + cookie.path();
}

QWebEngineCookieStore *SiteData::store() const {
#ifdef BROWSER_CEF
    return nullptr;
#else
    return m_store;
#endif
}

bool SiteData::holds(const QNetworkCookie &cookie) const {
    const auto kept = m_cookies.constFind(key(cookie));
    return kept != m_cookies.cend() && kept->present;
}

QVariantMap SiteData::attributes(const QString &name, const QString &domain, const QString &path) const {
    const auto kept = m_cookies.constFind(name + u'\n' + domain + u'\n' + path);
    if (kept == m_cookies.cend() || !kept->present)
        return {};
    const QNetworkCookie &c = kept->cookie;
    return {{QStringLiteral("secure"), c.isSecure()}, {QStringLiteral("httpOnly"), c.isHttpOnly()},
            {QStringLiteral("sameSite"), int(c.sameSitePolicy())}, {QStringLiteral("expires"), c.isSessionCookie() ? 0 : c.expirationDate().toMSecsSinceEpoch()}};
}

void SiteData::set(const QString &key, const QNetworkCookie &cookie, bool present) {
    Kept &kept = m_cookies[key];
    const bool was = kept.present;
    if (present)
        kept.cookie = cookie;
    kept.present = present;
    if (was != present) {
        ++m_revision;
        emit changed();
    }
}

void SiteData::settle() {
    const qint64 now = m_clock.elapsed();
    for (auto it = m_removals.begin(); it != m_removals.end();) {
        if (now - it.value() < settleMs) {
            ++it;
            continue;
        }
        const auto kept = m_cookies.constFind(it.key());
        if (kept != m_cookies.cend())
            set(it.key(), kept->cookie, false);
        it = m_removals.erase(it);
    }
    if (!m_removals.isEmpty())
        m_settle.start();
}

bool SiteData::sentTo(const QNetworkCookie &cookie, const QString &host) {
    const QString domain = cookie.domain().toLower();
    // a leading dot: a domain cookie, sent to that domain and the hosts under it; else the host's own
    if (domain.startsWith(u'.'))
        return host == domain.mid(1) || host.endsWith(domain);
    return host == domain;
}

void SiteData::reread() const {
#ifdef BROWSER_CEF
    // at most every 500 ms, one listing at a time; a read meanwhile counts the list it has, and a listing asked for
    // (m_listed invalidated) while one is under way follows it
    auto *self = const_cast<SiteData *>(this);
    if (m_listing && !m_listed.isValid())
        self->m_again = true;
    if (!m_profile || m_listing || (m_listed.isValid() && m_listed.elapsed() < 500))
        return;
    self->m_listing = true;
    const int epoch = m_epoch;
    CefCookies::list(m_profile, self, [self, epoch](const QList<CefCookies::Cookie> &list) {
        self->m_listing = false;
        // begun before a clear: the store as it was then, so the cleared cookies would come back; listed again
        if (epoch != self->m_epoch) {
            self->m_listed.invalidate();
            self->reread();
            return;
        }
        self->m_listed.start();
        QHash<QString, Kept> now;
        for (const CefCookies::Cookie &c : list) {
            QNetworkCookie k(c.name.toUtf8());
            k.setDomain(c.domain);
            k.setPath(c.path);
            k.setSecure(c.secure);
            k.setHttpOnly(c.httpOnly);
            k.setSameSitePolicy(QNetworkCookie::SameSite(c.sameSite));    // the same numbers as Chromium's
            if (c.expires > 0)
                k.setExpirationDate(QDateTime::fromMSecsSinceEpoch(c.expires));
            now.insert(key(k), Kept{k, true});
        }
        bool differs = now.size() != self->allCookies();
        for (auto it = now.cbegin(); !differs && it != now.cend(); ++it)
            differs = !self->m_cookies.value(it.key()).present;
        self->m_cookies = now;
        if (differs) {
            ++self->m_revision;
            emit self->changed();
        }
        if (std::exchange(self->m_again, false)) {
            self->m_listed.invalidate();
            self->reread();
        }
    });
#endif
}

int SiteData::cookies(const QString &host) const {
    reread();
    const QString h = host.toLower();
    return int(std::count_if(m_cookies.cbegin(), m_cookies.cend(), [&h](const Kept &k) { return k.present && sentTo(k.cookie, h); }));
}

int SiteData::clearCookies(const QString &host) {
#ifdef BROWSER_CEF
    const QString h = host.toLower();
    int n = 0;
    for (auto it = m_cookies.begin(); it != m_cookies.end(); ++it)
        if (it->present && sentTo(it->cookie, h)) {
            const QNetworkCookie &c = it->cookie;
            const QString site = c.domain().startsWith(u'.') ? c.domain().mid(1) : c.domain();
            CefCookies::remove(m_profile, (c.isSecure() ? QStringLiteral("https://") : QStringLiteral("http://")) + site + c.path(),
                               QString::fromUtf8(c.name()));
            it->present = false;
            ++n;
        }
    if (n > 0) {
        ++m_epoch;
        m_listed.invalidate();
        ++m_revision;
        emit changed();
    }
    return n;
#else
    if (!m_store)
        return 0;
    const QString h = host.toLower();
    int n = 0;
    for (const Kept &k : std::as_const(m_cookies))
        if (k.present && sentTo(k.cookie, h)) {
            m_store->deleteCookie(k.cookie);
            ++n;
        }
    return n;
#endif
}

int SiteData::allCookies() const {
    reread();
    return int(std::count_if(m_cookies.cbegin(), m_cookies.cend(), [](const Kept &k) { return k.present; }));
}

void SiteData::clearAllCookies() {
#ifdef BROWSER_CEF
    CefCookies::remove(m_profile, QString(), QString());
    ++m_epoch;
    m_listed.invalidate();
    if (!m_cookies.isEmpty()) {
        m_cookies.clear();
        ++m_revision;
        emit changed();
    }
#else
    if (m_store)
        m_store->deleteAllCookies();
#endif
}

void SiteData::refuseThirdParty(bool refuse) {
#ifdef BROWSER_CEF
    CefCookies::refuseThirdParty(m_profile, refuse);
#else
    if (!m_store)
        return;
    if (refuse)
        m_store->setCookieFilter([](const QWebEngineCookieStore::FilterRequest &request) { return !request.thirdParty; });
    else
        m_store->setCookieFilter(nullptr);
#endif
}
