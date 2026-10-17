#pragma once

#include <QNetworkCookie>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QSet>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QTimer>
#include <QVariantMap>
#include <memory>
#include <qqmlintegration.h>
#include <sys/resource.h>

// Import from Zen (PLAN.md 3.4, 3.15): the profile the Zen install uses, its bookmarks and history read from a copy
// of places.sqlite (Zen may be running and holds it), and its saved passwords decrypted through NSS on a copy of
// logins.json and key4.db. NSS runs in a helper process, this executable started with `--zen-nss`: Chromium's NSS is
// initialised in this one, and a second NSS database opened beside it would not be the internal key slot the
// decryption uses. The passwords go from the helper's pipe straight into the keyring (Passwords), never to QML.
// Its signed-in sessions are cookies.sqlite's cookies, set into the cookie store of the profile the import runs in
// (never read out to QML), and its open tabs are read from the session store (mozlz4) for Main to open.
class QWebEngineCookieStore;
class Zen : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // { name, path } of the profile the chosen browser's install uses; {} when there is none
    Q_PROPERTY(QVariantMap profile READ profile NOTIFY profileChanged)
    // The Firefox family found (Zen, Firefox, LibreWolf, Floorp, Waterfox; native, Flatpak or Snap), each with the profile its
    // install uses: [{ browser, icon (a file: URL, "" for none), name, path, counts: { passwords, bookmarks, sites, tabs },
    // -1 each until scanned }]. The import (and `profile`, `sites`, `tabs`) is the chosen one's: Zen's unless choose() says.
    Q_PROPERTY(QVariantList browsers READ browsers NOTIFY profileChanged)
    // the chosen browser's name ("Zen"), "" when none is found
    Q_PROPERTY(QString browser READ browser NOTIFY profileChanged)
    // "" at rest, "reading" (copying and reading the profile), "password" (waiting for Zen's primary password),
    // "saving" (decrypting the passwords and saving them in the keyring)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    // in "password": the primary password given last did not open the passwords
    Q_PROPERTY(bool wrong READ wrong NOTIFY stateChanged)
    // the logins in Zen's logins.json, once read
    Q_PROPERTY(int logins READ logins NOTIFY stateChanged)
    // what scan() found in Zen's profile: the sites it holds cookies for and the tabs it has open; -1 until scanned
    Q_PROPERTY(int sites READ sites NOTIFY scanned)
    Q_PROPERTY(int tabs READ tabs NOTIFY scanned)
public:
    explicit Zen(QObject *parent = nullptr);
    ~Zen() override;

    // --shots and --check-engine: never the user's own Zen folder (the checks make one up, useRoot; shots fake one)
    static inline bool noUserProfile = false;
    // `browser --zen-nss probe|decrypt|encrypt <dir>`, before anything else starts (main.cpp); see zen.cpp
    static int nssHelper(int argc, char *argv[]);
    // Firefox's install hash (CityHash64 1.0 of the install folder's path in UTF-16), as [Install<hash>] names it
    static QString installHash(const QString &folder);

    QVariantMap profile() const { return m_profile; }
    QVariantList browsers() const { return m_browsers; }
    QString browser() const { return m_browser; }
    QString state() const { return m_state; }
    bool wrong() const { return m_wrong; }
    int logins() const { return m_logins; }
    int sites() const { return m_sites; }
    int tabs() const { return m_tabs; }

    // --check-engine: a Zen folder (as ~/.config/zen) made up in the throwaway data dir, looked in from now on
    Q_INVOKABLE void useRoot(const QString &root);
    // browsers[index] for the import from now on; nothing while one runs
    Q_INVOKABLE void choose(int index);
    // --check-engine: the family looked for under this made-up home from now on (useRoot's folder no more)
    Q_INVOKABLE void useHome(const QString &home);
    // --shots: a made-up profile, with no Zen behind it
    Q_INVOKABLE void fake(const QVariantMap &profile);
    // Counts the sites with cookies and the open tabs in a copy of the profile's files, off the UI thread; answers with scanned()
    Q_INVOKABLE void scan();
    // Copies the profile's files and reads them off the UI thread; answers with read(). `want`: { cookies, tabs } (both
    // off when left out). The cookies go into `profile`'s cookie store, a QQuickWebEngineProfile, and into no other.
    // False when it cannot start.
    Q_INVOKABLE bool start(const QVariantMap &want = {}, QObject *profile = nullptr);
    // The passwords with Zen's primary password (state "password"); answers with saved()
    Q_INVOKABLE void unlock(const QString &primary);
    // The passwords left out (state "password"); answers with saved({ skipped: "not given" })
    Q_INVOKABLE void skip();

signals:
    void profileChanged();
    void stateChanged();
    // { bookmarks: [{ url, title, folder, added }], history: [{ url, title, visits, last }], logins, primary, failure }
    // `tabs` ([{ url, title, space }], pinned and essential first) only when wanted
    void read(const QVariantMap &found);
    void scanned();
    // { added, kept (already in the store), rejected (the engine refused them), skipped (partitioned or in a container),
    // expired, sites } or { failure }; before the passwords go on
    void cookiesDone(const QVariantMap &result);
    // { added, kept, skipped: "" | "not given" | "none" (no keyring) | "locked" (it stayed locked) | "failed", left (the
    // logins not stored after the keyring failed), unopened (the logins NSS could not open) }
    void saved(const QVariantMap &result);

private:
    void find();
    void setState(const QString &state, bool wrong = false);
    void decrypt(const QString &primary);
    void finish(const QVariantMap &result);
    void guard(bool on);
    void afterRead();
    void carryOn();
    void importCookies();
    void post();
    void doneCookies();

    QString m_root;
    QString m_home;         // where the family is looked for: the user's home, or the checks' (useHome)
    QVariantMap m_profile;
    QVariantList m_browsers;
    QString m_browser;
    int m_chosen = 0;
    QString m_state;
    bool m_wrong = false;
    bool m_fake = false;
    int m_logins = 0;
    int m_sites = -1;
    int m_tabs = -1;
    bool m_scanning = false;
    // the cookies read for this import, held until the store has them (guard(): no core dump meanwhile)
    QList<QNetworkCookie> m_jar;
    QVariantMap m_jarCounts;
    QPointer<QObject> m_target;     // the profile the cookies go into
    QPointer<QWebEngineCookieStore> m_store;
    QList<QNetworkCookie> m_todo;   // the cookies the store does not hold yet, posted in batches
    qsizetype m_at = 0;
    QSet<QString> m_waiting;        // the cookies posted that the store has not reported yet
    QMetaObject::Connection m_added;
    QTimer *m_quiet = nullptr;      // nothing reported for a while: the rest were refused
    int m_accepted = 0, m_kept = 0;
    std::unique_ptr<QTemporaryDir> m_copy;
    std::unique_ptr<QProcess> m_helper;
    QThreadPool m_reader;       // copies and reads the profile, one import at a time
    bool m_guarded = false;     // guard(): no core dump while secrets are held
    int m_dumpable = 1;
    struct rlimit m_core {};
};
