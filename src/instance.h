#pragma once

#include <QLocalServer>
#include <QLockFile>
#include <QObject>
#include <QString>
#include <QUrl>
#include <memory>

class QLocalSocket;

// One browser per profile (PLAN.md 4, 8 phase 3): the first `browser` holds a lock and listens on a socket in
// $XDG_RUNTIME_DIR named after its data dir, readable by this user only; a later `browser [--from <app>] [<address>]`
// hands its link to it and exits. What arrives comes out of `opened` (an empty url: the window was asked for), with the
// caller's context for the task the link joins (Main.openLink).
class Instance : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(bool listening READ listening)
public:
    enum Start { Listening, HandedOff, NoAnswer, Failed, Queued };
    Q_ENUM(Start)

    explicit Instance(const QString &dataDir, QObject *parent = nullptr);
    QString path() const { return m_path; }
    bool listening() const { return m_server.isListening(); }
    // With no browser running on this profile, takes the lock and listens (Listening; Failed when it cannot listen,
    // and the lock still keeps later starts from making a second browser on the profile). Otherwise hands `url`,
    // `from` and `context` to the one running: HandedOff once it took them; Queued when it holds the link unanswered
    // after 5 s (busy: it opens it once its event loop runs). One that is quitting takes no link (close()), so this
    // tries again, and takes the lock itself once that browser has gone; NoAnswer after 10 s of that.
    Q_INVOKABLE int start(const QUrl &url = QUrl(), const QString &from = QString(), const QString &context = QString());
    // Another browser holds this profile now (its lock), without taking the lock: the CEF build asks before it starts
    // an engine of its own (main).
    bool running();
    // Stops taking links: the socket file goes, and a link not answered yet is dropped unanswered, so its sender tries
    // again. The lock stays.
    Q_INVOKABLE void close();
    // The lock, for main() to let go after Chromium has shut down (in ~QGuiApplication), not with this object.
    std::unique_ptr<QLockFile> takeLock() { return std::move(m_lock); }
    // The app a link came from when its caller does not say (--from): the window class of the nearest process above
    // this one that owns a window as Hyprland lists them (j/clients), a reverse-DNS class by its last part
    // (org.quickshell: quickshell). "" outside Hyprland or when no such process has one. Offscreen the list is
    // $BROWSER_CHECK_CLIENTS (engine checks). `title`: that window's title (a Claude session's, a shell's).
    static QString caller(QString *title = nullptr);
    // What the caller was doing, for the task a link joins: this process's working directory, which it has from the shell
    // that ran it (as ~/... under the home; left out for the home itself and /), and the caller window's `title`.
    static QString context(const QString &title);
    // $XDG_RUNTIME_DIR/browser-<kind><12 hex of the data dir's SHA-1>.sock: this socket (kind ""), the notch's ("notch-")
    static QString socketPath(const QString &dataDir, const QString &kind = QString());

signals:
    void opened(const QUrl &url, const QString &from, const QString &context);

private:
    enum HandOver { Taken, Held, Refused };
    HandOver handOver(const QByteArray &line) const;
    void read(QLocalSocket *socket);

    QString m_path;
    std::unique_ptr<QLockFile> m_lock;
    QLocalServer m_server;
};
