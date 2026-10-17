#include "facts.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInformation>
#include <QProcess>
#include <QRegularExpression>
#include <QSslCertificate>
#include <QSslCipher>
#include <QSslSocket>
#include <QTimer>
#include <memory>

static QString named(QNetworkInformation::Reachability r) {
    switch (r) {
    case QNetworkInformation::Reachability::Disconnected: return QStringLiteral("none");
    case QNetworkInformation::Reachability::Local:
    case QNetworkInformation::Reachability::Site: return QStringLiteral("local");
    case QNetworkInformation::Reachability::Online: return QStringLiteral("online");
    default: return QStringLiteral("unknown");
    }
}

Facts::Facts(QObject *parent) : QObject(parent) {
    if (dryRun) {
        m_watching = true;
        return;
    }
    if (!QNetworkInformation::loadBackendByFeatures(QNetworkInformation::Feature::Reachability))
        return;
    QNetworkInformation *info = QNetworkInformation::instance();
    m_watching = true;
    m_reachability = named(info->reachability());
    connect(info, &QNetworkInformation::reachabilityChanged, this, [this](QNetworkInformation::Reachability r) {
        const QString now = named(r);
        if (now == m_reachability)
            return;
        m_reachability = now;
        emit reachabilityChanged();
    });
}

void Facts::fakeReachability(const QString &reachability) {
    if (!dryRun || reachability == m_reachability)
        return;
    m_reachability = reachability;
    emit reachabilityChanged();
}

#ifdef BROWSER_CEF
QVariantMap Facts::certificate(QObject *error) const {
    return error ? certificateFacts(error->property("certificateDer").toByteArray()) : QVariantMap();
}
#else
QVariantMap Facts::certificate(const QWebEngineCertificateError &error) const {
    const QList<QSslCertificate> chain = error.certificateChain();
    return chain.isEmpty() ? QVariantMap() : certificateFacts(chain.first().toDer());
}
#endif

QVariantMap Facts::certificateFacts(const QByteArray &der) {
    const QSslCertificate leaf(der, QSsl::Der);
    if (leaf.isNull())
        return {};
    QStringList names = leaf.subjectAlternativeNames().values(QSsl::AlternativeNameEntryType::DnsEntry);
    const QString common = leaf.subjectInfo(QSslCertificate::CommonName).value(0);
    if (names.isEmpty() && !common.isEmpty())
        names.append(common);
    QString issuer = leaf.issuerInfo(QSslCertificate::CommonName).value(0);
    if (issuer.isEmpty())
        issuer = leaf.issuerInfo(QSslCertificate::Organization).value(0);
    return {
        {QStringLiteral("names"), names},
        {QStringLiteral("subject"), common.isEmpty() ? names.value(0) : common},
        {QStringLiteral("issuer"), issuer},
        {QStringLiteral("from"), double(leaf.effectiveDate().toMSecsSinceEpoch())},
        {QStringLiteral("until"), double(leaf.expiryDate().toMSecsSinceEpoch())},
        {QStringLiteral("sha256"), QString::fromLatin1(leaf.digest(QCryptographicHash::Sha256).toHex(':'))},
    };
}

QVariantMap Facts::memory(qint64 pid) const {
    // status, not smaps: a sandboxed renderer is not dumpable, so only its world-readable files open. A
    // /proc file has size 0, so it is read whole (atEnd() is true before the first line).
    QFile status(QStringLiteral("/proc/%1/status").arg(pid));
    if (pid <= 0 || !status.open(QIODevice::ReadOnly))
        return {};
    qint64 kb = -1;
    for (const QByteArray &line : status.readAll().split('\n'))
        if (line.startsWith("VmRSS:"))
            kb = line.mid(6).trimmed().split(' ').value(0).toLongLong();
    if (kb < 0)
        return {};
    QFile cgroup(QStringLiteral("/proc/%1/cgroup").arg(pid));
    QString path;
    if (cgroup.open(QIODevice::ReadOnly))
        path = QString::fromUtf8(cgroup.readAll()).section(u'\n', 0, 0).trimmed().section(u':', 2);
    return {{QStringLiteral("bytes"), double(kb) * 1024}, {QStringLiteral("cgroup"), path}};
}

QVariantMap Facts::systemMemory() const {
    QFile meminfo(QStringLiteral("/proc/meminfo"));
    if (!meminfo.open(QIODevice::ReadOnly))
        return {};
    qint64 total = -1, available = -1;
    for (const QByteArray &line : meminfo.readAll().split('\n')) {
        if (line.startsWith("MemTotal:"))
            total = line.mid(9).trimmed().split(' ').value(0).toLongLong();
        else if (line.startsWith("MemAvailable:"))
            available = line.mid(13).trimmed().split(' ').value(0).toLongLong();
    }
    if (total < 0 || available < 0)
        return {};
    const double bytes = dryRun ? (m_fakeAvailable >= 0 ? m_fakeAvailable : double(total) * 1024) : double(available) * 1024;
    return {{QStringLiteral("available"), bytes}, {QStringLiteral("total"), double(total) * 1024}};
}

void Facts::fakeAvailable(double bytes) {
    if (dryRun)
        m_fakeAvailable = bytes;
}

QVariantList Facts::processes() const {
    struct Proc {
        qint64 parent = 0;
        qint64 kb = -1;
    };
    QHash<qint64, Proc> all;
    for (const QString &name : QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool number = false;
        const qint64 pid = name.toLongLong(&number);
        if (!number)
            continue;
        // status is readable for a sandboxed renderer too (memory() above)
        QFile status(QStringLiteral("/proc/%1/status").arg(pid));
        if (!status.open(QIODevice::ReadOnly))
            continue;
        Proc p;
        for (const QByteArray &line : status.readAll().split('\n')) {
            if (line.startsWith("PPid:"))
                p.parent = line.mid(5).trimmed().toLongLong();
            else if (line.startsWith("VmRSS:"))
                p.kb = line.mid(6).trimmed().split(' ').value(0).toLongLong();
        }
        all.insert(pid, p);
    }
    const qint64 self = QCoreApplication::applicationPid();
    // this process's descendants, parents before children
    QList<qint64> order{self};
    for (qsizetype i = 0; i < order.size(); ++i)
        for (auto it = all.cbegin(); it != all.cend(); ++it)
            if (it->parent == order.at(i) && !order.contains(it.key()))
                order.append(it.key());
    QVariantList out;
    for (const qint64 pid : std::as_const(order)) {
        const Proc p = all.value(pid);
        if (p.kb < 0)
            continue;
        QString type, service, name;
        QFile cmdline(QStringLiteral("/proc/%1/cmdline").arg(pid));
        if (pid != self && cmdline.open(QIODevice::ReadOnly))
            for (const QByteArray &arg : cmdline.readAll().split('\0')) {
                if (arg.startsWith("--type="))
                    type = QString::fromUtf8(arg.mid(7));
                else if (arg.startsWith("--utility-sub-type="))
                    service = QString::fromUtf8(arg.mid(19));
            }
        QFile comm(QStringLiteral("/proc/%1/comm").arg(pid));
        if (pid != self && type.isEmpty() && comm.open(QIODevice::ReadOnly))
            name = QString::fromUtf8(comm.readAll()).trimmed();
        out.append(QVariantMap{{QStringLiteral("pid"), pid}, {QStringLiteral("parent"), pid == self ? 0 : p.parent},
                               {QStringLiteral("type"), type}, {QStringLiteral("service"), service}, {QStringLiteral("name"), name},
                               {QStringLiteral("bytes"), double(p.kb) * 1024}});
    }
    return out;
}

bool Facts::isFile(const QString &path) const {
    const QFileInfo info(path);
    return info.isAbsolute() && info.isFile();
}

bool Facts::isFolder(const QString &path) const {
    const QFileInfo info(path);
    return info.isAbsolute() && info.isDir() && info.isWritable();
}

void Facts::lookUpStop(qint64 pid, const QString &cgroup, double since) {
    if (dryRun || pid <= 0)
        return;
    // the kernel's record reaches the journal a moment after the kill
    QTimer::singleShot(1500, this, [this, pid, cgroup, since] {
        auto *process = new QProcess(this);
        connect(process, &QProcess::finished, this, [this, process, pid, cgroup] {
            static const QRegularExpression oomd(QStringLiteral("^Killed (\\S+) due to"));
            const QString killed = QStringLiteral("Killed process %1 ").arg(pid);
            for (const QByteArray &line : process->readAllStandardOutput().split('\n')) {
                const QJsonObject entry = QJsonDocument::fromJson(line).object();
                const QString message = entry.value(QStringLiteral("MESSAGE")).toString();
                const double at = entry.value(QStringLiteral("__REALTIME_TIMESTAMP")).toString().toDouble() / 1000;
                QString source;
                if (entry.value(QStringLiteral("_TRANSPORT")).toString() == QLatin1String("kernel") && message.contains(killed)) {
                    source = QStringLiteral("kernel");
                } else if (entry.value(QStringLiteral("SYSLOG_IDENTIFIER")).toString() == QLatin1String("systemd-oomd") && !cgroup.isEmpty()) {
                    const QString path = oomd.match(message).captured(1);
                    if (!path.isEmpty() && (cgroup == path || cgroup.startsWith(path + u'/')))
                        source = QStringLiteral("systemd-oomd");
                }
                if (!source.isEmpty()) {
                    emit stopFound(pid, source, at);
                    break;
                }
            }
            process->deleteLater();
        });
        connect(process, &QProcess::errorOccurred, process, [process](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart)
                process->deleteLater();
        });
        process->start(QStringLiteral("journalctl"), {QStringLiteral("-q"), QStringLiteral("--no-pager"), QStringLiteral("-o"), QStringLiteral("json"),
                                                      QStringLiteral("-S"), QStringLiteral("@%1").arg(qint64(since / 1000)), QStringLiteral("-g"), QStringLiteral("Killed"),
                                                      QStringLiteral("_TRANSPORT=kernel"), QStringLiteral("+"), QStringLiteral("SYSLOG_IDENTIFIER=systemd-oomd")});
    });
}

void Facts::lookUpTls(const QString &host, int port) {
    // check mode: its *.test hosts are this machine (as main.cpp maps them for the engine), and no other is asked
    const bool check = dryRun && host.endsWith(u".test");
    if (dryRun && !check) {
        QTimer::singleShot(0, this, [this, host, port] { emit tlsFound(host, port, {}); });
        return;
    }
    auto *socket = new QSslSocket(this);
    auto done = std::make_shared<bool>(false);
    const auto answer = [this, socket, host, port, done](const QVariantMap &tls) {
        if (*done)
            return;
        *done = true;
        emit tlsFound(host, port, tls);
        socket->abort();
        socket->deleteLater();
    };
    // only reads what the host presents, whatever the verdict
    connect(socket, &QSslSocket::sslErrors, socket, [socket] { socket->ignoreSslErrors(); });
    connect(socket, &QSslSocket::encrypted, socket, [socket, answer] {
        const QList<QSslCertificate> chain = socket->peerCertificateChain();
        if (chain.isEmpty()) {
            answer({});
            return;
        }
        const QSslCertificate &leaf = chain.first();
        const QString common = leaf.subjectInfo(QSslCertificate::CommonName).value(0);
        const QString issuerName = leaf.issuerInfo(QSslCertificate::CommonName).value(0);
        const QString issuerOrg = leaf.issuerInfo(QSslCertificate::Organization).value(0);
        QString issuer = issuerName;
        if (!issuerOrg.isEmpty() && issuerOrg != issuerName)
            issuer = issuer.isEmpty() ? issuerOrg : issuer + QStringLiteral(" · ") + issuerOrg;
        const QSsl::SslProtocol protocol = socket->sessionProtocol();
        answer({
            {QStringLiteral("protocol"), protocol == QSsl::TlsV1_3 ? QStringLiteral("TLS 1.3") : protocol == QSsl::TlsV1_2 ? QStringLiteral("TLS 1.2") : QString()},
            {QStringLiteral("cipher"), socket->sessionCipher().name()},
            {QStringLiteral("subject"), common.isEmpty() ? leaf.subjectAlternativeNames().value(QSsl::AlternativeNameEntryType::DnsEntry) : common},
            {QStringLiteral("issuer"), issuer},
            {QStringLiteral("from"), double(leaf.effectiveDate().toMSecsSinceEpoch())},
            {QStringLiteral("until"), double(leaf.expiryDate().toMSecsSinceEpoch())},
            {QStringLiteral("sha256"), QString::fromLatin1(leaf.digest(QCryptographicHash::Sha256).toHex(':'))},
            {QStringLiteral("pem"), QString::fromLatin1(leaf.toPem())},
        });
    });
    connect(socket, &QAbstractSocket::errorOccurred, socket, [answer] { answer({}); });
    QTimer::singleShot(5000, socket, [answer] { answer({}); });
    socket->connectToHostEncrypted(check ? QStringLiteral("127.0.0.1") : host, quint16(port), host);
}
