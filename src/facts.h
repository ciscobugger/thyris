#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#ifndef BROWSER_CEF
#include <QWebEngineCertificateError>
#endif
#include <qqmlintegration.h>

// What the browser's own failure pages (PLAN.md 3.8 8f-8h) state that QML cannot read itself: whether the
// network is reachable (QNetworkInformation), the certificate behind a certificate error, a page process's
// memory from /proc, and the journal's record of what stopped a page process. Also the machine's free memory, for
// the memory net (PLAN.md 3.12). Also whether a typed path
// names a file (PLAN.md 3.3), and the TLS and certificate of an https site for the site panel (3.9).
class Facts : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // "none" (no network connection), "local" (a network, not the internet), "online", or "unknown"
    Q_PROPERTY(QString reachability READ reachability NOTIFY reachabilityChanged)
    // a backend reports reachability, so a page may say it loads again when the network is back
    Q_PROPERTY(bool watching READ watching CONSTANT)
public:
    explicit Facts(QObject *parent = nullptr);

    // --check-engine: no network backend (the check sets reachability) and no journal
    static inline bool dryRun = false;

    QString reachability() const { return m_reachability; }
    bool watching() const { return m_watching; }
    Q_INVOKABLE void fakeReachability(const QString &reachability);

    // { names, subject, issuer, from, until (ms since the epoch), sha256 } of the leaf certificate; {} without one
#ifdef BROWSER_CEF
    // CEF: the page view's certificate error (CertificateError, src/cef/requests.h) carries these itself
    Q_INVOKABLE QVariantMap certificate(QObject *error) const;
#else
    Q_INVOKABLE QVariantMap certificate(const QWebEngineCertificateError &error) const;
#endif
    // the same of a certificate in DER, for both engines
    static QVariantMap certificateFacts(const QByteArray &der);
    // { bytes (resident), cgroup } of a running process; {} once it is gone or unreadable
    Q_INVOKABLE QVariantMap memory(qint64 pid) const;
    // The machine's memory for the memory net (Lifecycle.low): /proc/meminfo's MemAvailable and MemTotal as
    // { available, total } in bytes; {} when unreadable. Check mode reads MemAvailable from fakeAvailable alone (all of
    // MemTotal until one is set), so the check machine's own memory never unloads a page.
    Q_INVOKABLE QVariantMap systemMemory() const;
    // --check-engine: the MemAvailable systemMemory gives, in bytes; below 0, none
    Q_INVOKABLE void fakeAvailable(double bytes);
    // The browser's processes for Pages and memory (PLAN.md 3.15): this one and every process under it, as
    // { pid, parent, type, service, name, bytes (resident) }. `type` is Chromium's --type= ("" for the browser itself:
    // renderer, gpu-process, utility, zygote), `service` a utility's --utility-sub-type= (network.mojom.NetworkService),
    // `name` what /proc/<pid>/comm says for a process under it that is not Chromium's (sh, curl, the Files relay).
    Q_INVOKABLE QVariantList processes() const;
    // Looks in the journal, from `since` (ms) on, for the kernel's OOM kill of `pid` or systemd-oomd's kill of
    // its cgroup (or one above it); answers with stopFound only when there is one.
    Q_INVOKABLE void lookUpStop(qint64 pid, const QString &cgroup, double since);
    // an existing file (not a folder) at the absolute `path`
    Q_INVOKABLE bool isFile(const QString &path) const;
    // an existing folder at the absolute `path` that the browser may write into (Settings > Downloads)
    Q_INVOKABLE bool isFolder(const QString &path) const;
    // Qt WebEngine reports no certificate or TLS for a page that loaded, so the site panel asks a TLS handshake
    // of the browser's own with `host`:`port`; answers with tlsFound: { protocol ("TLS 1.3"), cipher, subject,
    // issuer, from, until (ms since the epoch), sha256, pem } of what the host presents now, or {} when the
    // handshake failed. Nothing is sent after it, and the chain is not judged here: the engine did for the page.
    Q_INVOKABLE void lookUpTls(const QString &host, int port);

signals:
    void reachabilityChanged();
    void stopFound(qint64 pid, const QString &source, double at);
    void tlsFound(const QString &host, int port, const QVariantMap &tls);

private:
    QString m_reachability = QStringLiteral("unknown");
    bool m_watching = false;
    double m_fakeAvailable = -1;
};
