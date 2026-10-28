#pragma once

#include <QLocalSocket>
#include <QMimeData>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>
#include <memory>

struct sqlite3;

// `browser --check-engine`: runs Main with real web views offscreen on fixture pages and checks what
// needs the engine: the key classes of PLAN.md 5 and the lifecycle (EngineCheck.qml holds the steps).
// Keys go in as the window system delivers them, so Qt's shortcut matching and Qt WebEngine's
// unhandled-key hand-back both run.
class EngineCheck : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    ~EngineCheck() override;

    // Check mode, before the engine starts (main.cpp): what this process and the engine's processes write to stdout and
    // stderr still goes there, each through a pipe that keeps a copy for outputHolding().
    static void captureOutput();
    // whether this run's stdout or stderr so far holds `text`; how many times
    Q_INVOKABLE bool outputHolding(const QString &text) const;
    Q_INVOKABLE int outputCount(const QString &text) const;
    // Qt WebEngine's web channel log (qt.webengine.webchanneltransport) asked for at debug level, as QT_LOGGING_RULES
    // would (`on`), with the browser's quieting of it (Engine::quietChannel) or without
    Q_INVOKABLE void channelLog(bool on, bool quiet);
    // A throwaway Secret Service for the passwords checks (PLAN.md 7): a D-Bus bus of its own that activates nothing
    // (no service files) with gnome-keyring on it, its login keyring made with `password` in the throwaway data dir. The
    // desktop's session bus and keyring are never reached. Returns the bus's address, "" when either would not start.
    Q_INVOKABLE QString startKeyring(const QString &password);
    // Locks its default collection, or unlocks it with the password it was made with, as the login does.
    Q_INVOKABLE bool lockKeyring(bool lock);
    // Whether it holds an item of the browser's for `origin` and `user` whose secret is `secret` (any, for "").
    Q_INVOKABLE bool keyringHolds(const QString &origin, const QString &user, const QString &secret) const;

    // A press and release of `key` with `modifiers` into the focused window.
    Q_INVOKABLE void press(int key, int modifiers, const QString &text = QString());
    // The mouse at `x`, `y` in the window with `buttons` held (entering first if it was outside); a
    // change in `buttons` is a press or release there, with keyboard `modifiers` held (Shift-click).
    Q_INVOKABLE void pointer(qreal x, qreal y, int buttons = 0, int modifiers = 0);
    // a touchpad's two-finger scroll at (x, y): Begin, `steps` Updates of dy/steps px `stepMs` apart (by the events'
    // timestamps), End, as Hyprland sends it (no momentum phase)
    Q_INVOKABLE void swipe(qreal x, qreal y, int dy, int steps, int stepMs, int dx = 0);
    // one notch of a mouse wheel: angle delta only, no pixels, no phase
    Q_INVOKABLE void wheel(qreal x, qreal y, int angleDy);
    // The mouse leaves the window.
    Q_INVOKABLE void leave();
    // The file at `path` dragged in from another app and dropped at `x`, `y`.
    Q_INVOKABLE void drop(qreal x, qreal y, const QString &path);
    // `text` under the type `mime` dragged over `window` (a Window of the app) to `x`, `y`, as another of the app's
    // windows drags a rail row (Rail.carryOut), and dropped there when `release`; else it stays over the window.
    Q_INVOKABLE void dragData(QObject *window, qreal x, qreal y, const QString &mime, const QString &text, bool release);
    // An HTTP server on 127.0.0.1 for the loading checks; returns its port. `pages` maps a path to the
    // HTML it answers with at once, or to { body, auth: "user:password" } for a page behind HTTP sign-in
    // (401 until the request carries that Basic authorization), or { body, type } for a body of another
    // Content-Type (a PDF); /slow never answers; anything else is a
    // 404. A TLS hello (an https attempt) gets the connection closed, and one for silent.test no answer at
    // all. main.cpp maps every *.test host to 127.0.0.1. /file/<name>?size=<bytes>&delay=<ms per kB>&cut=<bytes>
    // answers as an attachment named <name>, 1 kB at a time; with `cut` the connection drops there and a
    // resume (a Range request) gets a 503 until allowResume(true).
    Q_INVOKABLE int serve(const QVariantMap &pages);
    Q_INVOKABLE void allowResume(bool allow) { m_resume = allow; }
    // The user.* extended attributes of the file at `path`.
    Q_INVOKABLE QVariantMap attributes(const QString &path) const;
    // What the throwaway data dir holds of `text` (its profile, the session files, the cache, Downloads), for the private
    // window's checks: { files, bytes: how many were read, holding: the paths whose bytes hold it, as UTF-8 or UTF-16 }.
    // Symbolic links (the user's fonts) are not followed.
    Q_INVOKABLE QVariantMap filesHolding(const QString &text) const;
    // The same pages over TLS, with a self-signed certificate for cert.test made in the throwaway data dir
    // (openssl); returns its port, 0 if it could not start. The TLS handshake succeeds only once the page
    // continues past the certificate.
    Q_INVOKABLE int serveTls();
    // A port on 127.0.0.1 nothing listens on, so a load there is refused.
    Q_INVOKABLE int closedPort();
    // Sends `signal` to process `pid` (a page process of this check's own engine).
    Q_INVOKABLE bool sendSignal(qint64 pid, int signal);
    // An app named `name` as the default for links of `scheme`, in the throwaway data dir's applications.
    Q_INVOKABLE bool fakeApp(const QString &scheme, const QString &name);
    // A file named `name` (a relative path, its folders made) holding `text` in the throwaway data dir, for a file
    // input; its path.
    Q_INVOKABLE QString fixtureFile(const QString &name, const QString &text);
    // removes a file in the check's own cache (XDG_CACHE_HOME under the temp folder); false for any other path
    Q_INVOKABLE bool removeCached(const QString &url);
    // A folder at the relative `path` in the throwaway data dir, for a launch's working directory; its path.
    Q_INVOKABLE QString fixtureDir(const QString &path);
    // Import from Zen (PLAN.md 3.4, 3.15): a Zen folder (as ~/.config/zen) named `name` made up in the throwaway data dir.
    // profiles.ini and installs.ini list a profile marked Default=1 (another install's) and the profile of the install a
    // desktop entry there starts (a folder of its own beside it), whose places.sqlite holds `spec.bookmarks` ([{ folder:
    // "toolbar/Kernel", url, title, separator, wal }]) and `spec.history` ([{ url, title, visits, hidden, last (ms), wal }]);
    // those with `wal` only in its write-ahead log, which a connection kept open holds exclusively, as a running Zen holds
    // it. Its logins.json and key4.db come from the NSS helper (`spec.logins`: [{ hostname, username, password, realm,
    // des3 }], under `spec.primary`). Returns { root, profile, decoy (the Default=1 profile), locked (a reader of its own
    // was refused while it is held) }, {} when it could not be made.
    Q_INVOKABLE QVariantMap zenProfile(const QString &name, const QVariantMap &spec);
    // A Chrome-family home for ChromeImport.useHome, under the throwaway data dir: `spec` { dir (".config/google-chrome"),
    // secret (its Safe Storage secret: v11 is sealed with it), profiles: [{ dir, name, email, active, logins, accountLogins:
    // [{ origin, user, password, tag "v10" | "v11", never (the site's never-save) }], bookmarks: [{ url, title, folder
    // ("bar", "bar/Kernel", "other") }], history: [{ url, title, visits, last (ms) , hidden }], cookies: [{ host, name,
    // value, path, secure, httpOnly, sameSite (Chromium's), expires (ms, 0: a session cookie), partition (a top-level site),
    // plain (in the clear, as an old profile has it) }], tabs, oldTabs: [{ url, title, back: [addresses before it], window
    // (1 when none), popup (its window a popup), index (its place, else in order), group (a tab group's title), closed }]
    // }] }; cookies as Chromium writes version 24 (the value after its host's SHA-256, sealed v11), tabs as its session
    // file (Sessions/Session_<time>, oldTabs in an older one). The home, "" for none.
    Q_INVOKABLE QString chromeHome(const QVariantMap &spec);
    // An item in the throwaway keyring with these attributes and this secret, as a browser files its own key
    Q_INVOKABLE bool keyringPut(const QVariantMap &attributes, const QString &secret);
    // Zen's cookies.sqlite and session file in the profile folder `profile` (zenProfile's `profile`): `spec.cookies` ([{ name,
    // value, host, path, expiry (as Zen writes it: seconds or milliseconds), secure, httpOnly, sameSite, attributes }]) and
    // `spec.session` (the session store's JSON, written as mozlz4 to sessionstore.jsonlz4, or to `spec.sessionFile`).
    Q_INVOKABLE bool zenSession(const QString &profile, const QVariantMap &spec);
    // For every host with a cookie in the copy of Zen's cookies.sqlite in `profile` (read, never written; a copy is made in the data dir) that Import takes (unexpired, in no
    // partition or container): how many of them a request to that host would send, { host: count }; counts only
    Q_INVOKABLE QVariantMap zenCookieCounts(const QString &profile) const;
    // The value of an environment variable of this process
    Q_INVOKABLE QString env(const QString &name) const { return qEnvironmentVariable(name.toUtf8().constData()); }
    // The NSS helper's probe of the Zen profile at `dir`: { logins, primary }
    Q_INVOKABLE QVariantMap zenProbe(const QString &dir) const;
    // The NSS helper's decrypt run by hand on `dir`, no primary password given: { state, logins (how many came out) };
    // what came out is dropped unread
    Q_INVOKABLE QVariantMap zenDecrypt(const QString &dir) const;
    // The files under `dir`, each with its size and time, one line each: to tell that nothing there was written
    Q_INVOKABLE QString folderStamp(const QString &dir) const;
    // The names of what `dir` holds (the temp dir: no copy of a Zen profile left there)
    Q_INVOKABLE QStringList entries(const QString &dir) const;
    // With BROWSER_CHECK_GRABS set to a folder, `window` (a Window of the app) as it is drawn now, saved there as
    // <name>.png, to look at what the real engine drew (the reader view, the print card's preview); else nothing.
    Q_INVOKABLE void grab(QObject *window, const QString &name) const;
    // With BROWSER_CHECK_GRABS set, a copy of the file at `path` kept there as `name` (a PDF printed); else nothing.
    Q_INVOKABLE void keep(const QString &path, const QString &name) const;
    // QDir::tempPath(): where Printing keeps the previews
    Q_INVOKABLE QString tempDir() const;
    // A saved page of tests/fixtures (built in), by its path there ("reader/lwn.html"); "" when there is none.
    Q_INVOKABLE QString savedPage(const QString &name) const;
    // What the PDF at `path` holds (print, PLAN.md 3.16): { pages, width, height (the first page, in points), text (its
    // text), left, top (where that text starts, in points) }; { pages: 0 } when it does not open.
    Q_INVOKABLE QVariantMap pdf(const QString &path) const;
    // The colour ("#rrggbb") of the first page of the PDF at `path`, rendered at 72 dpi, at the fractions `fx`, `fy` of it.
    Q_INVOKABLE QString pdfColor(const QString &path, qreal fx, qreal fy) const;
    // The app loses the focus to another app's window (Files, for a pick); gets it back in `window` (a
    // Window of the app), or in the main window.
    Q_INVOKABLE void away();
    Q_INVOKABLE void back(QObject *window = nullptr);
    // A second `browser <args>`, as another app runs it: through `sh -c` when `viaShell` (a process between this one
    // and it), in this process's environment (the throwaway dirs) with `env` added, in the working directory `dir`
    // when given. launched() says how it went: { code: its exit code, -1 while it runs, ms, output }. One still
    // running after 10 s is killed (code -2).
    Q_INVOKABLE void launch(const QStringList &args, const QVariantMap &env = {}, bool viaShell = false, const QString &dir = QString());
    Q_INVOKABLE QVariantMap launched() const { return m_launched; }
    Q_INVOKABLE qint64 pid() const;
    // A socket file at `path` that nothing listens on, as a browser that did not quit cleanly leaves one.
    Q_INVOKABLE bool staleSocket(const QString &path);
    // `object`'s property `name`, a dynamic one (QObject::setProperty) too, which QML cannot read: Windows.showAs's appId.
    Q_INVOKABLE QVariant propertyOf(QObject *object, const QString &name) const { return object ? object->property(name.toUtf8()) : QVariant(); }
    // QDesktopServices hands the check's schemes here (main.cpp) instead of to the desktop.
    Q_INVOKABLE void qtLaunched(const QUrl &url) { m_qtLaunches.append(url.toString()); }
    Q_INVOKABLE QStringList qtLaunches() const { return m_qtLaunches; }
    // A stand-in for the shell's island (Ctrl+L in the notch, src/notch.*): connects to the browser's notch socket at
    // `path`, says `line` (one JSON object), and keeps what the browser answers, each line parsed, in order.
    Q_INVOKABLE bool islandConnect(const QString &path);
    Q_INVOKABLE void islandSay(const QString &line);
    Q_INVOKABLE QVariantList islandHeard() const { return m_islandHeard; }
    Q_INVOKABLE bool islandConnected() const;
    Q_INVOKABLE void islandHangUp();
    Q_INVOKABLE void report(const QString &line);
    Q_INVOKABLE void finish(int failures);

private:
    void answer(class QTcpSocket *socket);
    void sendFile(class QTcpSocket *socket, const QByteArray &head, const QString &path);

    std::unique_ptr<QMimeData> m_dragged;
    std::unique_ptr<QProcess> m_keyringBus, m_keyring;
    QList<sqlite3 *> m_zenPlaces;   // the made-up Zen profiles' databases, held as a running Zen holds them
    QString m_keyringAddress, m_keyringPassword;
    QVariantMap m_pages;
    QVariantMap m_launched;
    QStringList m_qtLaunches;
    bool m_inside = false;
    int m_buttons = 0;
    bool m_resume = false;
    std::unique_ptr<QLocalSocket> m_island;
    QVariantList m_islandHeard;
};
