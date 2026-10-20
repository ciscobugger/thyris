#include "apps.h"
#include "shell.h"

#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

// The Name= of a desktop file's [Desktop Entry], or "" if it has none.
static QString desktopName(const QString &id) {
    QFile file(QStandardPaths::locate(QStandardPaths::ApplicationsLocation, id));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    bool entry = false;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.startsWith(u'['))
            entry = line == QLatin1String("[Desktop Entry]");
        else if (entry && line.startsWith(QLatin1String("Name=")))
            return line.mid(5).trimmed();
    }
    return {};
}

void Apps::lookUp(const QString &scheme) {
    static const QRegularExpression valid(QStringLiteral("^[a-z][a-z0-9+.-]*$"));
    if (!valid.match(scheme).hasMatch()) {
        emit found(scheme, QString());
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, scheme] {
        const QString id = QString::fromUtf8(process->readAllStandardOutput()).section(u'\n', 0, 0).trimmed();
        process->deleteLater();
        if (id.isEmpty()) {
            emit found(scheme, QString());
            return;
        }
        const QString name = desktopName(id);
        emit found(scheme, name.isEmpty() ? QString(id).remove(QRegularExpression(QStringLiteral("\\.desktop$"))) : name);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, scheme](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        emit found(scheme, QString());
    });
    process->start(QStringLiteral("xdg-mime"), {QStringLiteral("query"), QStringLiteral("default"), QStringLiteral("x-scheme-handler/") + scheme});
}

void Apps::open(const QString &url) {
    m_lastOpened = url;
    emit opened();
    if (!dryRun)
        QProcess::startDetached(QStringLiteral("xdg-open"), {url});
}

void Apps::reveal(const QString &path) {
    m_lastRevealed = path;
    emit revealed();
    if (dryRun)
        return;
    auto *call = new QProcess(this);
    const QString folder = QFileInfo(path).absolutePath();
    connect(call, &QProcess::finished, this, [call, folder](int code, QProcess::ExitStatus status) {
        call->deleteLater();
        if (code != 0 || status != QProcess::NormalExit)
            QProcess::startDetached(QStringLiteral("xdg-open"), {folder});
    });
    connect(call, &QProcess::errorOccurred, this, [call, folder](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        call->deleteLater();
        QProcess::startDetached(QStringLiteral("xdg-open"), {folder});
    });
    call->start(QStringLiteral("qs"), shellIpc() + QStringList{QStringLiteral("files"), QStringLiteral("reveal"), path});
}

static const QStringList webTypes{QStringLiteral("x-scheme-handler/http"), QStringLiteral("x-scheme-handler/https"), QStringLiteral("text/html")};
// The desktop file this build runs from: the CEF build's own launcher, not the Qt WebEngine build's browser.desktop
// (2026-10-11: Make default on the CEF build sent links to the Qt WebEngine build)
#ifdef BROWSER_CEF
static const QString desktopId = QStringLiteral("opsis-new-engine.desktop");
#else
static const QString desktopId = QStringLiteral("browser.desktop");
#endif

void Apps::lookUpDefault() {
    // check mode knows only what makeDefault() did: it never asks the desktop's own mimeapps.list
    if (dryRun) {
        m_default = m_lastDefaulted.isEmpty() ? QStringLiteral("no") : QStringLiteral("yes");
        emit defaultFound();
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process] {
        const QStringList ids = QString::fromUtf8(process->readAllStandardOutput()).split(u'\n', Qt::SkipEmptyParts);
        process->deleteLater();
        m_default = ids.size() == 2 && ids.at(0).trimmed() == desktopId && ids.at(1).trimmed() == desktopId
            ? QStringLiteral("yes") : QStringLiteral("no");
        emit defaultFound();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_default = QStringLiteral("no");
        emit defaultFound();
    });
    // one query per type, in one shell: xdg-mime answers for one type at a time
    process->start(QStringLiteral("sh"), {QStringLiteral("-c"), QStringLiteral("xdg-mime query default x-scheme-handler/http; xdg-mime query default x-scheme-handler/https")});
}

void Apps::makeDefault() {
    if (dryRun) {
        m_lastDefaulted = QStringLiteral("xdg-mime default ") + desktopId + u' ' + webTypes.join(u' ');
        lookUpDefault();
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process] {
        process->deleteLater();
        lookUpDefault();
    });
    connect(process, &QProcess::errorOccurred, this, [process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            process->deleteLater();
    });
    process->start(QStringLiteral("xdg-mime"), QStringList{QStringLiteral("default"), desktopId} + webTypes);
}
