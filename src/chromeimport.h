#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantMap>
#include <qqmlintegration.h>

#include "passwords.h"

// Import from the Chrome family (book4-edge/thyris-migration-plan.md): Google Chrome, Chromium, Brave, Microsoft Edge,
// Vivaldi, Opera and Thorium, native or Flatpak, every profile their Local State names, most recently used first.
// scan() counts what each profile holds from copies of its Login Data (and Login Data For Account), Bookmarks and History,
// as the browser may be running and holds them. start() reads one profile's bookmarks and history for Main (read) and
// decrypts its passwords as Chromium does on Linux, straight into the keyring (Passwords::importLogins), never to QML:
// v11 is AES-128-CBC under a key PBKDF2-HMAC-SHA1'd (salt "saltysalt", one round) from the browser's own secret in the
// keyring (attribute application = chrome, chromium, brave...), the IV sixteen spaces; v10 the same from "peanuts". Its
// open tabs come from its session file (tabsOf), as Main opens Zen's: pages in a task of their own, none loaded.
class ChromeImport : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{ browser, icon (a file: URL, "" for none), root, dir, name, email, active, counts: { passwords, bookmarks, history, sites,
    // tabs } }] (sites: those it holds cookies for, unexpired and unpartitioned, by registrable domain; tabs: open in its
    // normal windows)
    Q_PROPERTY(QVariantList found READ found NOTIFY foundChanged)
    // "" at rest, "scanning", "reading", "keyring" (waiting for the browser's key, perhaps on an unlock), "saving"
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
public:
    explicit ChromeImport(QObject *parent = nullptr);

    // --shots and --check-engine: never the user's own browsers (the checks make some up, useHome)
    static inline bool noUserProfile = false;

    QVariantList found() const { return m_found; }
    QString state() const { return m_state; }

    // --check-engine: look for browsers under this home from now on
    Q_INVOKABLE void useHome(const QString &home);
    Q_INVOKABLE void scan();
    // an app's icon from the icon theme as a file: URL ("" for none), for Welcome's rows (the Firefox family's too)
    Q_INVOKABLE QString icon(const QString &name) const { return themeIcon(name); }
    static QString themeIcon(const QString &name);
    // found[index]'s things; `want` { passwords, bookmarks, history, sites, tabs }, each on unless false; its cookies go into the
    // cookie store of `profile` (this window's), so you stay signed in. False while busy or for none.
    Q_INVOKABLE bool start(int index, const QVariantMap &want = {}, QObject *profile = nullptr);

    // whether a cookie is Google's sign-in (SID, __Secure-1PSID on google.com): brought over, Google may email about a new
    // sign-in on Linux, which Welcome's done page says; Zen's import asks it too
    static bool googleSignIn(const QString &host, const QString &name);
    // v10 or v11 data as Chromium writes it (`tag` "v10": the key from "peanuts"), for the checks' made-up profiles
    static QByteArray encrypt(const QByteArray &plain, const QByteArray &secret, const char *tag);
    // the plain value, or a null QByteArray when it does not open (another key, another scheme)
    static QByteArray decrypt(const QByteArray &data, const QByteArray &secret);

signals:
    void foundChanged();
    void stateChanged();
    // { browser, bookmarks: [{ url, title, folder: [names], added }], history: [{ url, title, visits, last }], tabs: [{ url,
    // title, group (its tab group's title, "" for none) }], failure }
    void read(const QVariantMap &found);
    // the passwords going into the keyring
    void progress(int done, int total);
    // the cookies set: { added, kept (the store had them), refused (Chromium would not take them), left (sealed with a key
    // the keyring did not give), sites, google (Google's sign-in among those set or kept) }, or { failure: "profile" } where
    // there is no cookie store to set them in
    void cookiesDone(const QVariantMap &result);
    // { added, kept, left, total, failure }: failure "" or "no key" (v11 data and no secret of the browser's to open it,
    // the logins it holds left out), "locked", or Passwords'
    void saved(const QVariantMap &result);

private:
    struct Read;
    void setState(const QString &state);
    void afterRead(std::shared_ptr<Read> read);
    void withKey(std::shared_ptr<Read> read, int app);
    void bring(std::shared_ptr<Read> read, QByteArray secret);     // by value: overwritten once used

    QPointer<QObject> m_profile;
    QString m_home;
    QVariantList m_found;
    QString m_state;
    int m_scans = 0;
};
