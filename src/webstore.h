#pragma once

#include "storefetch.h"

#include <QHash>
#include <QObject>
#include <QProcessEnvironment>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlintegration.h>

// "Add to Thyris" for the Chrome Web Store, and keeping what was added up to date. Everything about a file is decided here,
// in C++: the page offers an id, Google's update service the file, and nothing is unpacked until the file's signature, its key
// and its id agree (src/crx.*). The ask the person answers is drawn by Thyris itself (qml/Asks.js, kind "extension"); no web
// page can draw or press it.
//
// A job runs in steps: fromStore(id) or fromFile(path) -> prepared(ticket, info) or refused(ticket, why); the person answers the
// ask; add(ticket) puts it in the list of added extensions (src/extensions.*), or discard(ticket) throws it away.
// The engine loads extensions only as it starts, so an addition, an update or a removal takes effect at the next start;
// relaunch() starts Thyris again for that, once the QML has told this one to quit (Main.qml reopenNow).
class WebStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit WebStore(QObject *parent = nullptr);

    // --check-engine and tests: the network is a stand-in, Chrome's version is given, and relaunch() only counts
    static inline StoreFetch::Transport transportOverride;
    static inline QString prodVersionOverride;
    static inline bool dryRun = false;
    static inline int relaunched = 0;
    // a stand-in for Google that serves files from `dir` (checks and tests): the update service's redirect and answer, and the
    // files they name, as <id>.crx, <id>.xml (the update check's answer) and any <name>.crx the answer points to
    static void useFixtures(const QString &dir);
    static inline QStringList requested;

    // before the engine starts (main): updates that were agreed to, or that asked for nothing new, replace the old versions;
    // what an interrupted job left behind goes
    static void startUp();

    static constexpr qint64 maxFile = 64ll << 20;

    // the extension a store page is, or "": only the store's item pages
    Q_INVOKABLE QString itemId(const QUrl &page) const;
    Q_INVOKABLE bool added(const QString &id) const;
    // added since this Thyris started: the engine loads extensions only at its start, so it runs from the next one
    Q_INVOKABLE bool waiting(const QString &id) const { return addedNow.contains(id); }
    static inline QStringList addedNow;
    // checks: the addresses asked of the stand-in (useFixtures), and starting that list afresh
    Q_INVOKABLE QStringList requests() const { return requested; }
    Q_INVOKABLE void forgetRequests() const { requested.clear(); }
    // checks: how many times Reopen now started Thyris again (dryRun)
    Q_INVOKABLE int relaunches() const { return relaunched; }
    // checks: the data folder the new start would be given
    Q_INVOKABLE QString relaunchData() const { return relaunchEnvironment().value(QStringLiteral("XDG_DATA_HOME")); }
    static QProcessEnvironment relaunchEnvironment();

    // the ticket comes back at once; the answer comes as `prepared` or `refused`
    Q_INVOKABLE int fromStore(const QString &id);
    Q_INVOKABLE int fromFile(const QString &path);
    Q_INVOKABLE QVariantMap add(int ticket);        // { ok, name, id, problem }
    Q_INVOKABLE void discard(int ticket);
    // Thyris starts again, to take the extensions up; the QML has already told this one to quit
    Q_INVOKABLE void relaunch();

    // Each store extension's newest version is asked of Google: at start and then once a day, never more (`force`: a check
    // asked for by a test).
    Q_INVOKABLE void startUpdates();
    Q_INVOKABLE void checkUpdates(bool force = false);
    // updates that ask for more than the old version could: [{ id, name, version, words }]; each is returned once per run
    Q_INVOKABLE QVariantList updateAsks();
    Q_INVOKABLE void answerUpdate(const QString &id, bool yes);

signals:
    void prepared(int ticket, const QVariantMap &info);
    void refused(int ticket, const QString &problem);
    void updatesToAsk();
    void checked();

private:
    struct Job {
        QString source;             // "store" or "file"
        QString id;                 // the store's id
        QString key;                // base64 of the public key, store only
        QString root;               // the folder holding manifest.json
        QString scratch;            // Thyris's own folder, deleted with the job; "" for a folder the person chose
        bool ready = false;
    };
    QString prodVersion() const;
    StoreFetch::Transport transport() const;
    int newTicket();
    void refuse(int ticket, const QString &problem);
    // unpacked zip -> a prepared job; false with `problem`
    bool stage(const QByteArray &zip, const QString &scratch, bool wrapped, const QByteArray &key, QString *root, QString *problem);
    void describe(int ticket, const QString &source, const QString &id, const QString &key, const QString &scratch, const QString &root);
    QVariantList askable(bool mark);
    void nextCheck(int index);
    void gotUpdate(const QString &id, const QByteArray &file, const QString &sha256);

    QHash<int, Job> m_jobs;
    int m_last = 0;
    QTimer m_daily;
    QStringList m_ids;
    bool m_checking = false;
    bool m_started = false;
    QStringList m_asked;
};
