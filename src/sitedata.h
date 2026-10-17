#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QNetworkCookie>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <qqmlintegration.h>

class QWebEngineCookieStore;

// The cookie store's cookies for the site panel (PLAN.md 3.9): counted and cleared per host. Qt WebEngine
// reports cookies only as they are added and removed, so the list is kept here from the profile's start.
class SiteData : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int revision READ revision NOTIFY changed)
public:
    explicit SiteData(QObject *parent = nullptr);

    int revision() const { return m_revision; }
    Q_INVOKABLE void attach(QObject *profile);
    // the store it is attached to, and whether it holds a cookie of that name, domain and path (Import from Zen)
    QWebEngineCookieStore *store() const;
    bool holds(const QNetworkCookie &cookie) const;
    // a cookie as the store reports it, { secure, httpOnly, sameSite (the engine's: 0 unspecified, 1 None, 2 Lax, 3 Strict),
    // expires (ms, 0 for a session cookie) }; {} when it holds none: for the checks, which never read a value
    Q_INVOKABLE QVariantMap attributes(const QString &name, const QString &domain, const QString &path) const;
    // The cookies of another profile, a private window's (PLAN.md 3.14): a SiteData of its own, attached to it, which
    // goes with it. The singleton is the main profile's.
    Q_INVOKABLE QObject *forProfile(QObject *profile);
    // the cookies the store would send to `host`: its own and those of the domains above it
    Q_INVOKABLE int cookies(const QString &host) const;
    // deletes them from the store; how many went
    Q_INVOKABLE int clearCookies(const QString &host);
    // every site's cookies (Settings > Privacy, PLAN.md 3.15): how many there are, and deleting them all
    Q_INVOKABLE int allCookies() const;
    Q_INVOKABLE void clearAllCookies();
    // Third-party cookies (Settings > Privacy): refused, or let through as the engine does by default. A frame of
    // another site neither reads nor sets its cookies while they are refused.
    Q_INVOKABLE void refuseThirdParty(bool refuse);

signals:
    void changed();

private:
    static bool sentTo(const QNetworkCookie &cookie, const QString &host);
    // CEF tells no changes (src/cef/cookies.h): the store is listed again when read, and the list replaced when it comes
    void reread() const;
    QPointer<QObject> m_profile;
    QElapsedTimer m_listed;
    bool m_listing = false;
    bool m_again = false;     // asked to list again while a listing was under way
    int m_epoch = 0;          // a clear's count: a listing begun before the last clear is dropped
    static QString key(const QNetworkCookie &cookie);
    void set(const QString &key, const QNetworkCookie &cookie, bool present);
    void settle();

    struct Kept {
        QNetworkCookie cookie;
        bool present = false;
    };
    QPointer<QWebEngineCookieStore> m_store;
    QHash<QString, Kept> m_cookies;
    // removals waiting to be told from a cookie set again (key -> when the removal came, ms)
    QHash<QString, qint64> m_removals;
    QElapsedTimer m_clock;
    QTimer m_settle;
    int m_revision = 0;
};
