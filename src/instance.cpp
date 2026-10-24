#include "instance.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDeadlineTimer>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QGuiApplication>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QThread>
#include <csignal>

// One per profile: a throwaway data dir (shots, engine checks) never meets the real browser's socket.
QString Instance::socketPath(const QString &dataDir, const QString &kind) {
    const QByteArray profile = QCryptographicHash::hash(dataDir.toUtf8(), QCryptographicHash::Sha1).toHex().left(12);
    return QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/browser-") + kind
           + QString::fromLatin1(profile) + QStringLiteral(".sock");
}

Instance::Instance(const QString &dataDir, QObject *parent)
    : QObject(parent), m_path(socketPath(dataDir)), m_lock(std::make_unique<QLockFile>(m_path + QStringLiteral(".lock"))) {
    // held for the browser's life: only a lock whose process is gone (a crash, a kill) is stale, never an old one
    m_lock->setStaleLockTime(0);
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *socket = m_server.nextPendingConnection()) {
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QLocalSocket::readyRead, this, [this, socket] { read(socket); });
        }
    });
}

// The pid in the lock of a browser that has not answered, if that process runs this very executable (Chromium's
// IsChromeProcess check, process_singleton_posix.cc): a lock left by something else is never a reason to kill it.
// /proc/<pid>/exe of a binary replaced by an update reads "<path> (deleted)". SIGTERM, 3 s to go, then SIGKILL.
static bool endHolder(QLockFile &lock) {
    qint64 pid = 0;
    QString host, app;
    if (!lock.getLockInfo(&pid, &host, &app) || pid <= 1 || pid == QCoreApplication::applicationPid())
        return false;
    const QString link = QStringLiteral("/proc/%1/exe").arg(pid);
    QString exe = QFile::symLinkTarget(link);
    if (exe.endsWith(u" (deleted)"))
        exe.chop(10);
    if (exe.isEmpty() || exe != QFileInfo(QCoreApplication::applicationFilePath()).canonicalFilePath())
        return false;
    // a zombie keeps its pid but has no exe
    const auto gone = [&link] { return QFile::symLinkTarget(link).isEmpty(); };
    ::kill(pid_t(pid), SIGTERM);
    for (QDeadlineTimer deadline(3000); !gone() && !deadline.hasExpired();)
        QThread::msleep(50);
    if (!gone()) {
        ::kill(pid_t(pid), SIGKILL);
        for (QDeadlineTimer deadline(1000); !gone() && !deadline.hasExpired();)
            QThread::msleep(50);
    }
    return gone();
}

int Instance::start(const QUrl &url, const QString &from, const QString &context) {
    QJsonObject message{{QStringLiteral("url"), url.toString(QUrl::FullyEncoded)}, {QStringLiteral("from"), from},
                        {QStringLiteral("context"), context}};
    // the launcher's Wayland activation token, so the compositor lets the running browser take the focus
    const QString token = qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    if (!token.isEmpty())
        message.insert(QStringLiteral("token"), token);
    const QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';
    // One still starting listens moments after taking the lock; one quitting keeps it, listening no more, until its
    // Chromium has shut down, and then this one is the browser.
    for (QDeadlineTimer deadline(10000);;) {
        // No browser on this profile (a lock that cannot be written at all counts so too): this one is it. The socket
        // file of one that did not quit cleanly goes first.
        if (m_lock->isLocked() || m_lock->tryLock(0) || m_lock->error() != QLockFile::LockFailedError) {
            QLocalServer::removeServer(m_path);
            return m_server.listen(m_path) ? Listening : Failed;
        }
        const HandOver result = handOver(line);
        if (result == Taken)
            return HandedOff;
        if (result == Held || deadline.hasExpired()) {
            // The browser holds the profile and does not answer (2026-10-24: hung, and a new start did nothing). As
            // Chromium's second process does, end it and start normally; this process opens the link it was given.
            if (endHolder(*m_lock)) {
                if (!m_lock->tryLock(0)) {
                    m_lock->removeStaleLockFile();
                    m_lock->tryLock(0);
                }
                QLocalServer::removeServer(m_path);
                QProcess::startDetached(QStringLiteral("qs"), {QStringLiteral("-c"), QStringLiteral("tacit"), QStringLiteral("ipc"),
                                                              QStringLiteral("call"), QStringLiteral("island"), QStringLiteral("note"),
                                                              QStringLiteral("error"), QStringLiteral("Thyris wasn't answering · restarted")});
                return m_server.listen(m_path) ? Listening : Failed;
            }
            return result == Held ? Queued : NoAnswer;
        }
        QThread::msleep(100);
    }
}

bool Instance::running() {
    if (m_lock->tryLock(0)) {
        m_lock->unlock();
        return false;
    }
    return m_lock->error() == QLockFile::LockFailedError;
}

// Taken once the running browser answers "ok"; Held while it keeps the connection open with no answer for 4 s (the
// line waits in its socket); Refused when nothing listens or the connection closes unanswered.
Instance::HandOver Instance::handOver(const QByteArray &line) const {
    QLocalSocket socket;
    socket.connectToServer(m_path);
    if (!socket.waitForConnected(1000))
        return Refused;
    socket.write(line);
    socket.waitForBytesWritten(1000);
    for (QDeadlineTimer answer(4000); !socket.canReadLine() && !answer.hasExpired();)
        if (!socket.waitForReadyRead(int(answer.remainingTime())))
            break;
    if (socket.canReadLine())
        return socket.readLine() == "ok\n" ? Taken : Refused;
    return socket.state() == QLocalSocket::ConnectedState ? Held : Refused;
}

void Instance::close() {
    m_server.close();
    for (QLocalSocket *socket : m_server.findChildren<QLocalSocket *>(Qt::FindDirectChildrenOnly))
        if (!socket->property("answered").toBool())
            socket->abort();
}

void Instance::read(QLocalSocket *socket) {
    if (!socket->canReadLine()) {
        // a link is one line; this much without one is not a browser handing a link over
        if (socket->bytesAvailable() > 8 << 20)
            socket->abort();
        return;
    }
    const QJsonObject message = QJsonDocument::fromJson(socket->readLine()).object();
    const QString token = message.value(QStringLiteral("token")).toString();
    // Qt's Wayland plugin hands XDG_ACTIVATION_TOKEN to the compositor on the next requestActivate
    if (!token.isEmpty())
        qputenv("XDG_ACTIVATION_TOKEN", token.toUtf8());
    emit opened(QUrl(message.value(QStringLiteral("url")).toString()), message.value(QStringLiteral("from")).toString(),
                message.value(QStringLiteral("context")).toString());
    socket->write("ok\n");
    socket->setProperty("answered", true);
    socket->disconnectFromServer();
}

// The parent of process `pid` from /proc/<pid>/stat (read whole: a /proc file reports atEnd at 0), 0 if unknown.
// The name field can hold spaces and parentheses, so the fields are counted from its last ')'.
static qint64 parentOf(qint64 pid) {
    QFile stat(QStringLiteral("/proc/%1/stat").arg(pid));
    if (!stat.open(QIODevice::ReadOnly))
        return 0;
    const QByteArray line = stat.readAll();
    return line.mid(line.lastIndexOf(')') + 2).split(' ').value(1).toLongLong();
}

QString Instance::caller(QString *title) {
    QByteArray clients;
    // before the window system (the CEF build's hand-off runs ahead of it, main.cpp) the platform Qt would take
    const QString platform = QGuiApplication::platformName().isEmpty() ? qEnvironmentVariable("QT_QPA_PLATFORM") : QGuiApplication::platformName();
    if (platform == u"offscreen") {
        clients = qgetenv("BROWSER_CHECK_CLIENTS");
    } else {
        const QString signature = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
        if (signature.isEmpty())
            return {};
        QLocalSocket hyprland;
        hyprland.connectToServer(qEnvironmentVariable("XDG_RUNTIME_DIR") + u"/hypr/" + signature + u"/.socket.sock");
        if (!hyprland.waitForConnected(300))
            return {};
        // Hyprland's main loop waits for the request once it has accepted (src/backdrop.cpp): written at once. It
        // closes the connection when it has answered.
        hyprland.write("j/clients");
        hyprland.flush();
        while (hyprland.waitForReadyRead(500))
            clients += hyprland.readAll();
        clients += hyprland.readAll();
    }
    QHash<qint64, QJsonObject> windows;
    for (const QJsonValue &client : QJsonDocument::fromJson(clients).array())
        windows.insert(client[u"pid"].toInteger(), client.toObject());
    if (windows.isEmpty())
        return {};
    qint64 pid = parentOf(QCoreApplication::applicationPid());
    for (int steps = 0; pid > 1 && steps < 64; ++steps, pid = parentOf(pid))
        if (windows.contains(pid)) {
            if (title)
                *title = windows.value(pid).value(u"title").toString();
            return windows.value(pid).value(u"class").toString().section(u'.', -1);
        }
    return {};
}

QString Instance::context(const QString &title) {
    QString dir = QDir::currentPath();
    const QString home = QDir::homePath();
    if (dir == home || dir == u"/")
        dir.clear();
    else if (dir.startsWith(home + u'/'))
        dir = u'~' + dir.mid(home.size());
    return QStringList{dir, title}.filter(QRegularExpression(QStringLiteral("\\S"))).join(u' ');
}
