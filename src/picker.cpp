#include "picker.h"
#include "shell.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QStandardPaths>

static const QByteArray marker = "browser-picked ";

// The relay: Files' Choose calls `picked` on it, and it prints the list as JSON on a line of its own. The
// list can arrive as JSON text, one path or lines of paths, as the Claude app's receiver (claude.qml) takes it.
static const char relayShell[] = R"(import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "browser"
        function picked(json: string): void {
            let paths;
            try { paths = JSON.parse(json); } catch (e) { paths = json; }
            if (typeof paths === "string") paths = paths.split("\n");
            console.log("browser-picked " + JSON.stringify(paths));
        }
    }
}
)";

Picker::Picker(QObject *parent) : QObject(parent) {
    m_grace.setSingleShot(true);
    m_grace.setInterval(1000);
    connect(&m_grace, &QTimer::timeout, this, [this] { end({}); });
    m_watch.setSingleShot(true);
    m_watch.setInterval(5000);
    connect(&m_watch, &QTimer::timeout, this, [this] { if (!m_away) end({}); });
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (!m_busy)
            return;
        if (state != Qt::ApplicationActive) {
            m_away = true;
            m_grace.stop();
        } else if (m_away) {
            m_grace.start();
        }
    });
}

bool Picker::pick(const QString &label) {
    if (m_busy)
        return false;
    m_busy = true;
    const int serial = ++m_serial;
    m_label = label;
    m_away = QGuiApplication::applicationState() != Qt::ApplicationActive;
    m_watch.start();
    emit busyChanged();
    if (dryRun)
        return true;

    QString dir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (dir.isEmpty())
        dir = QDir::tempPath();
    dir += QStringLiteral("/browser");
    QDir().mkpath(dir);
    const QString shell = dir + QStringLiteral("/pick-relay.qml");
    QFile file(shell);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) || file.write(relayShell) < 0) {
        end({});
        return true;
    }
    file.close();

    m_relay = new QProcess(this);
    m_relay->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_relay, &QProcess::readyReadStandardOutput, this, &Picker::readRelay);
    m_relay->start(QStringLiteral("qs"), {QStringLiteral("-p"), shell});

    auto *call = new QProcess(this);
    // no shell to open Files in: the pick is over (unless a later one has begun)
    connect(call, &QProcess::finished, this, [this, call, serial](int code, QProcess::ExitStatus status) {
        call->deleteLater();
        if ((code != 0 || status != QProcess::NormalExit) && serial == m_serial)
            end({});
    });
    connect(call, &QProcess::errorOccurred, this, [this, call, serial](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        call->deleteLater();
        if (serial == m_serial)
            end({});
    });
    call->start(QStringLiteral("qs"), shellIpc() + QStringList{QStringLiteral("files"), QStringLiteral("pick"), QDir::homePath(), shell,
                                                              QStringLiteral("browser"), label});
    return true;
}

void Picker::answer(const QStringList &paths) {
    if (m_busy && dryRun)
        end(paths);
}

void Picker::readRelay() {
    while (m_relay && m_relay->canReadLine()) {
        const QByteArray line = m_relay->readLine();
        const qsizetype at = line.indexOf(marker);
        if (at < 0)
            continue;
        // the log line may carry colour codes after the list
        const QByteArray rest = line.mid(at + marker.size());
        const QJsonArray list = QJsonDocument::fromJson(rest.left(rest.lastIndexOf(']') + 1)).array();
        QStringList paths;
        for (const auto &v : list)
            if (v.isString() && !v.toString().trimmed().isEmpty())
                paths.append(v.toString().trimmed());
        end(paths);
        return;
    }
}

void Picker::end(const QStringList &paths) {
    if (!m_busy)
        return;
    m_busy = false;
    m_grace.stop();
    m_watch.stop();
    if (m_relay) {
        QProcess *relay = m_relay;
        m_relay = nullptr;
        relay->disconnect(this);
        if (relay->state() == QProcess::NotRunning) {
            relay->deleteLater();
        } else {
            connect(relay, &QProcess::finished, relay, &QObject::deleteLater);
            relay->terminate();
        }
    }
    emit busyChanged();
    emit finished(paths);
}
