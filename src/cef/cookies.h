#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <functional>

// A profile's cookies on CEF, for SiteData (book4-edge/opsis-cef-port-plan.md, slice 3). The profile's store is its
// request context's (the global one for the main profile, a private window's own: pageitem.cpp, contextOf). CEF lists
// cookies when asked and tells no changes, so SiteData asks again when it is read.
namespace CefCookies {
struct Cookie {
    QString name, domain, path;
    bool secure = false;
    bool httpOnly = false;
    int sameSite = 0;       // Chromium's: 0 unspecified, 1 None, 2 Lax, 3 Strict
    qint64 expires = 0;     // ms since the epoch, 0 for a session cookie
};
// every cookie in the store, to `done` on Qt's thread while `receiver` lives
void list(QObject *profile, QObject *receiver, std::function<void(const QList<Cookie> &)> done);
// A cookie to set (another browser's, brought over): `domain` with a leading dot for a domain cookie, the host's own
// without; `value` as the site set it.
struct Set {
    QString name, domain, path;
    QByteArray value;
    bool secure = false;
    bool httpOnly = false;
    int sameSite = 0;       // as Cookie's
    qint64 expires = 0;     // ms since the epoch, 0 for a session cookie
};
// sets them in the profile's store (written to disk once all are in); `done(set, refused)` on Qt's thread while
// `receiver` lives, refused: Chromium would not take one (a malformed name, an address it would not set it for)
void set(QObject *profile, const QList<Set> &cookies, QObject *receiver, std::function<void(int, int)> done);
// deletes the cookies `url` would be sent with that name; both empty: every cookie
void remove(QObject *profile, const QString &url, const QString &name);
// third-party cookies refused (a frame of another site reads and sets none), or let through as Chromium does by default
void refuseThirdParty(QObject *profile, bool refuse);
// `call` (on Qt's thread, while `owner` lives) when cookies may have changed: a page's main frame finished a load
void onTouched(QObject *owner, std::function<void()> call);
}
