#pragma once

#include <QLocalServer>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>

class QLocalSocket;

// Ctrl+L in the notch (PLAN.md 3.19, ~/book4-edge/ctrll-notch-plan.md): the shell draws the address sheet and asks the
// browser for what goes in it, over the main profile's socket $XDG_RUNTIME_DIR/browser-notch-<profile>.sock, one JSON
// object a line (NotchAddress.qml speaks it). `call` asks the shell to open the sheet; the island then connects and says
// hello. One island at a time: a new connection replaces the one before. A sign-in popup in the notch
// (~/book4-edge/signin-notch-plan.md, NotchSignin.qml) speaks the same way over a second socket, browser-signin-<profile>,
// whose call is the island's `signin`.
class Notch : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(bool listening READ listening NOTIFY listeningChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // what `call` runs, with the socket, the monitor and the mode after it; the engine checks give a stand-in
    Q_PROPERTY(QStringList command MEMBER m_command)
    // what the last call ran, for the checks
    Q_PROPERTY(QStringList lastCall READ lastCall)
    // the window whose Ctrl+L the island answers (its NotchAddress); the others leave the messages alone
    Q_PROPERTY(QObject *owner MEMBER m_owner NOTIFY ownerChanged)
public:
    // `function`: the island's IPC function `call` runs ("address", "signin")
    explicit Notch(const QString &path, const QString &function = QStringLiteral("address"), QObject *parent = nullptr);
    QString path() const { return m_path; }
    bool listening() const { return m_server.isListening(); }
    bool connected() const { return m_socket != nullptr; }
    QStringList lastCall() const { return m_lastCall; }

    // Listens on the socket, replacing a file left by a browser that did not quit cleanly (the profile's lock is held).
    Q_INVOKABLE bool listen();
    Q_INVOKABLE void close();
    // Runs `command` with the socket, `monitor` and `mode`; `called` answers once it exits.
    Q_INVOKABLE void call(const QString &monitor, const QString &mode);
    // One line (JSON) to the island, if one is connected.
    Q_INVOKABLE void send(const QString &line);
    // Closes the island's connection, with no hungUp.
    Q_INVOKABLE void hangUp();

signals:
    void listeningChanged();
    void connectedChanged();
    void ownerChanged();
    // ok: the command exited 0 and did not print "off" (the shell's notch is off, or on no screen of that name)
    void called(bool ok);
    void message(const QString &line);
    // the island closed its connection
    void hungUp();

private:
    void read(QLocalSocket *socket);

    QString m_path;
    QLocalServer m_server;
    QPointer<QLocalSocket> m_socket;
    QStringList m_command;
    QStringList m_lastCall;
    QPointer<QObject> m_owner;
    int m_calls = 0;
};
