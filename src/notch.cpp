#include "notch.h"
#include "shell.h"

#include <QLocalSocket>
#include <QProcess>

Notch::Notch(const QString &path, const QString &function, QObject *parent)
    : QObject(parent), m_path(path),
      m_command(QStringList{QStringLiteral("qs")} + shellIpc() + QStringList{QStringLiteral("island"), function}) {
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *socket = m_server.nextPendingConnection()) {
            // the newest island is the one on screen
            if (QLocalSocket *old = m_socket) {
                m_socket = nullptr;
                old->disconnectFromServer();
            }
            m_socket = socket;
            connect(socket, &QLocalSocket::readyRead, this, [this, socket] { read(socket); });
            connect(socket, &QLocalSocket::disconnected, this, [this, socket] {
                socket->deleteLater();
                if (m_socket != socket)
                    return;
                m_socket = nullptr;
                emit connectedChanged();
                emit hungUp();
            });
            emit connectedChanged();
        }
    });
}

bool Notch::listen() {
    if (m_server.isListening())
        return true;
    QLocalServer::removeServer(m_path);
    const bool ok = m_server.listen(m_path);
    emit listeningChanged();
    return ok;
}

void Notch::close() {
    hangUp();
    m_server.close();
    emit listeningChanged();
}

void Notch::call(const QString &monitor, const QString &mode) {
    if (m_command.isEmpty()) {
        emit called(false);
        return;
    }
    m_lastCall = m_command + QStringList{m_path, monitor, mode};
    const int serial = ++m_calls;
    auto *process = new QProcess(this);
    process->setStandardErrorFile(QProcess::nullDevice());
    connect(process, &QProcess::finished, this, [this, process, serial](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        const bool off = process->readAllStandardOutput().trimmed() == "off";
        if (serial == m_calls)
            emit called(status == QProcess::NormalExit && code == 0 && !off);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, serial](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        if (serial == m_calls)
            emit called(false);
    });
    process->start(m_lastCall.first(), m_lastCall.mid(1));
}

void Notch::send(const QString &line) {
    if (!m_socket)
        return;
    m_socket->write(line.toUtf8() + '\n');
    m_socket->flush();
}

void Notch::hangUp() {
    if (QLocalSocket *socket = m_socket) {
        m_socket = nullptr;
        socket->disconnectFromServer();
        emit connectedChanged();
    }
}

void Notch::read(QLocalSocket *socket) {
    while (socket->canReadLine()) {
        const QString line = QString::fromUtf8(socket->readLine()).trimmed();
        // a reply to an island that was replaced goes nowhere
        if (socket == m_socket && !line.isEmpty())
            emit message(line);
    }
    // a message is one line; this much without one is not the island
    if (socket->bytesAvailable() > 1 << 20)
        socket->abort();
}
