#include "webstore.h"

#include "crx.h"
#include "extensions.h"
#include "storerules.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUuid>
#ifdef BROWSER_CEF
#include "include/cef_version_info.h"
#endif

namespace {

constexpr qint64 dayMs = 24ll * 3600 * 1000;

QString storeDir() { return Extensions::store(); }
QString stateFile() { return storeDir() + QStringLiteral("/webstore.json"); }

QJsonObject readState() {
    QFile f(stateFile());
    return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object() : QJsonObject();
}
void writeState(const QJsonObject &o) {
    QDir().mkpath(storeDir());
    QSaveFile f(stateFile());
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(o).toJson(QJsonDocument::Compact));
        f.commit();
    }
}

qsizetype indexOf(const QJsonArray &list, const QString &id) {
    for (qsizetype i = 0; i < list.size(); ++i)
        if (list.at(i).toObject().value(QStringLiteral("id")).toString() == id)
            return i;
    return -1;
}

QString newScratch(const char *kind) {
    return storeDir() + u'/' + QLatin1String(kind) + QUuid::createUuid().toString(QUuid::Id128).left(10);
}

// The manifest as the engine will read it: with the store's public key in it, so an unpacked folder gets the id the store
// gave the extension (without it the engine makes an id from the folder's path, and the extension would be another one:
// its own pages' addresses, its saved settings and sign-ins through it would not carry over a move or an update).
bool writeKey(const QString &root, const QByteArray &key, QString *problem) {
    QJsonObject manifest = Extensions::manifestOf(root);
    if (manifest.isEmpty()) {
        *problem = QObject::tr("The extension's description can't be read, so nothing was added.");
        return false;
    }
    if (manifest.value(QStringLiteral("manifest_version")).toInt() != 3) {
        *problem = QObject::tr("That extension is built for an older version of Chrome, which Thyris can't run, so nothing was added. A newer or \"Lite\" version of it may work.");
        return false;
    }
    manifest.insert(QStringLiteral("key"), QString::fromLatin1(key.toBase64()));
    QSaveFile f(root + QStringLiteral("/manifest.json"));
    if (!f.open(QIODevice::WriteOnly) || f.write(QJsonDocument(manifest).toJson(QJsonDocument::Compact)) < 0 || !f.commit()) {
        *problem = QObject::tr("The extension couldn't be unpacked, so nothing was added.");
        return false;
    }
    return true;
}

// the extension's icon as a data address: the biggest PNG its manifest names, inside its own folder
QString iconOf(const QString &root, const QJsonObject &manifest) {
    QStringList paths;
    const auto fromObject = [&paths](const QJsonObject &icons) {
        QList<int> sizes;
        for (auto it = icons.begin(); it != icons.end(); ++it)
            sizes << it.key().toInt();
        std::sort(sizes.begin(), sizes.end(), std::greater<int>());
        for (int s : sizes)
            if (s <= 256 && icons.value(QString::number(s)).isString())
                paths << icons.value(QString::number(s)).toString();
    };
    fromObject(manifest.value(QStringLiteral("icons")).toObject());
    const QJsonValue action = manifest.value(QStringLiteral("action")).toObject().value(QStringLiteral("default_icon"));
    if (action.isObject())
        fromObject(action.toObject());
    else if (action.isString())
        paths << action.toString();
    const QString base = QDir::cleanPath(root);
    for (const QString &rel : std::as_const(paths)) {
        const QString path = QDir::cleanPath(base + u'/' + rel);
        if (!path.startsWith(base + u'/') || !rel.endsWith(u".png", Qt::CaseInsensitive))
            continue;
        QFile f(path);
        if (QFileInfo(path).isSymLink() || QFileInfo(path).size() > (1 << 20) || !f.open(QIODevice::ReadOnly))
            continue;
        const QByteArray data = f.readAll();
        if (data.startsWith("\x89PNG\r\n\x1a\n"))
            return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(data.toBase64());
    }
    return {};
}

void sweepScratch() {
    const QDir dir(storeDir());
    for (const QString &name : dir.entryList(QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot)) {
        if (name.startsWith(QLatin1String(".staged-")) || name.startsWith(QLatin1String(".incoming-")))
            QDir(dir.filePath(name)).removeRecursively();
        else if (name.startsWith(QLatin1String(".old-"))) {
            // an update that stopped between its two steps: the old version goes back if the new one did not arrive
            const QString id = name.mid(5);
            if (!QFileInfo::exists(dir.filePath(id)))
                QDir().rename(dir.filePath(name), dir.filePath(id));
            else
                QDir(dir.filePath(name)).removeRecursively();
        }
    }
}

}

WebStore::WebStore(QObject *parent) : QObject(parent) {
    m_daily.setInterval(6 * 3600 * 1000);
    connect(&m_daily, &QTimer::timeout, this, [this] { checkUpdates(); });
}

void WebStore::useFixtures(const QString &dir) {
    transportOverride = [dir](const QUrl &url, qint64, std::function<void(StoreFetch::Reply)> done) {
        requested << url.toString(QUrl::FullyEncoded);
        StoreFetch::Reply r;
        const QString host = url.host();
        const QString query = url.query(QUrl::FullyDecoded);
        QRegularExpressionMatch m = QRegularExpression(QStringLiteral("id=([a-p]{32})")).match(query);
        if (host == u"clients2.google.com" && url.path() == u"/service/update2/crx" && m.hasMatch()) {
            const QString id = m.captured(1);
            if (query.contains(u"response=redirect")) {
                r.status = 302;
                r.location = QStringLiteral("https://clients2.googleusercontent.com/crx/blobs/fixture/%1.crx").arg(id);
            } else {
                QFile f(dir + u'/' + id + QStringLiteral(".xml"));
                r.status = 200;
                r.body = f.open(QIODevice::ReadOnly) ? f.readAll()
                    : QStringLiteral("<?xml version='1.0'?><gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'><app appid='%1' status='ok'>"
                                     "<updatecheck status='noupdate'/></app></gupdate>").arg(id).toUtf8();
            }
        } else if (host == u"clients2.googleusercontent.com" && url.path().startsWith(u"/crx/blobs/fixture/")) {
            const QString name = url.path().mid(19);
            QFile f(dir + u'/' + name);
            if (QRegularExpression(QStringLiteral("^[a-z0-9._-]+$")).match(name).hasMatch() && f.open(QIODevice::ReadOnly)) {
                r.status = 200;
                r.body = f.readAll();
            } else {
                r.status = 404;
            }
        } else {
            r.failed = true;
        }
        done(r);
    };
}

void WebStore::startUp() {
    if (!QFileInfo::exists(storeDir()))
        return;
    sweepScratch();
    QJsonArray list = Extensions::read();
    bool changed = false;
    for (qsizetype i = 0; i < list.size(); ++i) {
        QJsonObject e = list.at(i).toObject();
        const QJsonObject pending = e.value(QStringLiteral("pending")).toObject();
        if (pending.isEmpty() || !pending.value(QStringLiteral("approved")).toBool())
            continue;
        const QString id = e.value(QStringLiteral("id")).toString();
        const QString live = storeDir() + u'/' + id, fresh = storeDir() + QStringLiteral("/.update-") + id, old = storeDir() + QStringLiteral("/.old-") + id;
        const QJsonObject manifest = Extensions::manifestOf(fresh);
        if (manifest.isEmpty() || manifest.value(QStringLiteral("version")).toString() != pending.value(QStringLiteral("version")).toString()) {
            e.remove(QStringLiteral("pending"));
            list.replace(i, e);
            changed = true;
            QDir(fresh).removeRecursively();
            continue;
        }
        QDir(old).removeRecursively();
        if (!QDir().rename(live, old))
            continue;
        if (!QDir().rename(fresh, live)) {
            QDir().rename(old, live);
            continue;
        }
        QDir(old).removeRecursively();
        e.remove(QStringLiteral("pending"));
        e.insert(QStringLiteral("version"), manifest.value(QStringLiteral("version")).toString());
        e.insert(QStringLiteral("updated"), double(QDateTime::currentMSecsSinceEpoch()));
        const QString name = Extensions::nameOf(live, manifest);
        if (!name.isEmpty())
            e.insert(QStringLiteral("name"), name);
        list.replace(i, e);
        changed = true;
    }
    if (changed)
        Extensions::save(list);
}

QString WebStore::itemId(const QUrl &page) const { return StoreRules::itemId(page); }

bool WebStore::added(const QString &id) const { return indexOf(Extensions::read(), id) >= 0; }

QString WebStore::prodVersion() const {
    if (!prodVersionOverride.isEmpty())
        return prodVersionOverride;
#ifdef BROWSER_CEF
    // the engine that runs, not the one this was built against
    return QStringLiteral("%1.%2.%3.%4").arg(cef_version_info(4)).arg(cef_version_info(5)).arg(cef_version_info(6)).arg(cef_version_info(7));
#else
    return QStringLiteral("154.0.0.0");
#endif
}

StoreFetch::Transport WebStore::transport() const {
    static const StoreFetch::Transport real = StoreFetch::network();
    return transportOverride ? transportOverride : real;
}

int WebStore::newTicket() {
    const int t = ++m_last;
    m_jobs.insert(t, Job());
    return t;
}

void WebStore::refuse(int ticket, const QString &problem) {
    const Job job = m_jobs.take(ticket);
    if (!job.scratch.isEmpty())
        QDir(job.scratch).removeRecursively();
    emit refused(ticket, problem);
}

// `zip` was verified (store) or chosen (file). It is unpacked into `scratch`; `wrapped`: a folder holding the extension's folder
// is fine too (a .zip of a folder). `key`: the store's public key, written into the manifest; empty for a file.
bool WebStore::stage(const QByteArray &zip, const QString &scratch, bool wrapped, const QByteArray &key, QString *root, QString *problem) {
    QDir().mkpath(scratch);
    *problem = Zip::extract(zip, scratch);
    if (!problem->isEmpty())
        return false;
    *root = scratch;
    if (wrapped && !QFile::exists(scratch + QStringLiteral("/manifest.json"))) {
        const QStringList dirs = QDir(scratch).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        if (dirs.size() == 1)
            *root = scratch + u'/' + dirs.first();
    }
    if (!QFile::exists(*root + QStringLiteral("/manifest.json"))) {
        *problem = wrapped ? tr("That isn't an extension. Choose the extension's own folder, or its .zip.")
                           : tr("That isn't an extension, so nothing was added.");
        return false;
    }
    if (!key.isEmpty())
        return writeKey(*root, key, problem);
    return true;
}

void WebStore::describe(int ticket, const QString &source, const QString &id, const QString &key, const QString &scratch, const QString &root) {
    if (!m_jobs.contains(ticket)) {
        if (!scratch.isEmpty())
            QDir(scratch).removeRecursively();
        return;
    }
    Job &job = m_jobs[ticket];
    job.source = source;
    job.id = id;
    job.key = key;
    job.root = root;
    job.scratch = scratch;
    const QJsonObject manifest = Extensions::manifestOf(root);
    const QString name = Extensions::nameOf(root, manifest);
    if (!QFile::exists(root + QStringLiteral("/manifest.json")))
        return refuse(ticket, tr("That isn't an extension. Choose the extension's own folder, or its .zip."));
    if (manifest.isEmpty())
        return refuse(ticket, tr("The extension's description can't be read."));
    if (manifest.value(QStringLiteral("manifest_version")).toInt() != 3)
        return refuse(ticket, tr("That extension is built for an older version of Chrome, which Thyris can't run. A newer or \"Lite\" version of it may work."));
    if (name.isEmpty())
        return refuse(ticket, tr("The extension has no name."));
    const QJsonArray list = Extensions::read();
    for (const QJsonValue &v : list) {
        const QJsonObject e = v.toObject();
        if (e.value(QStringLiteral("name")).toString() == name || (source == u"store" && e.value(QStringLiteral("id")).toString() == id))
            return refuse(ticket, tr("%1 is already added.").arg(name));
    }
    job.ready = true;
    emit prepared(ticket, QVariantMap{{QStringLiteral("ticket"), ticket}, {QStringLiteral("id"), id}, {QStringLiteral("name"), name},
                                      {QStringLiteral("version"), manifest.value(QStringLiteral("version")).toString()},
                                      {QStringLiteral("icon"), iconOf(root, manifest)},
                                      {QStringLiteral("words"), StoreRules::permissionWords(manifest)},
                                      {QStringLiteral("source"), source}});
}

int WebStore::fromStore(const QString &id) {
    const int ticket = newTicket();
    if (!StoreRules::validId(id)) {
        QTimer::singleShot(0, this, [this, ticket] { refuse(ticket, tr("That isn't an extension's address in the store.")); });
        return ticket;
    }
    if (added(id)) {
        QTimer::singleShot(0, this, [this, ticket] { refuse(ticket, tr("That extension is already added.")); });
        return ticket;
    }
    // the answer always comes on a later turn of the event loop, after the caller has the ticket and is listening
    QTimer::singleShot(0, this, [this, ticket, id] {
    StoreFetch::get(transport(), StoreRules::fileUrl(id, prodVersion()), maxFile, [this, ticket, id](const QByteArray &body, const QString &problem) {
        if (!m_jobs.contains(ticket))
            return;                     // the person gave up meanwhile
        if (!problem.isEmpty())
            return refuse(ticket, problem);
        const Crx::Result r = Crx::verify(body, id);
        if (!r.ok)
            return refuse(ticket, r.problem);
        const QString scratch = newScratch(".staged-");
        QString root, why;
        if (!stage(r.zip, scratch, false, r.key, &root, &why)) {
            QDir(scratch).removeRecursively();
            return refuse(ticket, why);
        }
        describe(ticket, QStringLiteral("store"), id, QString::fromLatin1(r.key.toBase64()), scratch, root);
    });
    });
    return ticket;
}

int WebStore::fromFile(const QString &path) {
    const int ticket = newTicket();
    QTimer::singleShot(0, this, [this, ticket, path] {
        if (!m_jobs.contains(ticket))
            return;
        const QFileInfo info(path);
        if (info.isDir())
            return describe(ticket, QStringLiteral("file"), QString(), QString(), QString(), info.absoluteFilePath());
        QFile zip(info.absoluteFilePath());
        if (!info.isFile() || info.suffix().compare(QLatin1String("zip"), Qt::CaseInsensitive) != 0)
            return refuse(ticket, tr("Choose an extension's folder or a .zip file."));
        if (info.size() > maxFile || !zip.open(QIODevice::ReadOnly))
            return refuse(ticket, tr("The .zip couldn't be opened."));
        const QString scratch = newScratch(".staged-");
        QString root, why;
        if (!stage(zip.readAll(), scratch, true, QByteArray(), &root, &why)) {
            QDir(scratch).removeRecursively();
            return refuse(ticket, why);
        }
        describe(ticket, QStringLiteral("file"), QString(), QString(), scratch, root);
    });
    return ticket;
}

QVariantMap WebStore::add(int ticket) {
    const Job job = m_jobs.take(ticket);
    QString problem = tr("That has already been dealt with.");
    QVariantMap info;
    if (job.ready) {
        Extensions::Added meta;
        meta.source = job.source;
        meta.id = job.id;
        meta.key = job.key;
        // Thyris's own scratch folder moves into place; a folder the person chose is copied
        if (Extensions::commit(job.root, !job.scratch.isEmpty(), meta, &problem, &info)) {
            if (!job.scratch.isEmpty())
                QDir(job.scratch).removeRecursively();
            Extensions::announce();
            return QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("id"), info.value(QStringLiteral("id"))},
                               {QStringLiteral("name"), info.value(QStringLiteral("name"))}, {QStringLiteral("problem"), QString()}};
        }
    }
    if (!job.scratch.isEmpty())
        QDir(job.scratch).removeRecursively();
    return QVariantMap{{QStringLiteral("ok"), false}, {QStringLiteral("id"), QString()}, {QStringLiteral("name"), QString()}, {QStringLiteral("problem"), problem}};
}

void WebStore::discard(int ticket) {
    const Job job = m_jobs.take(ticket);
    if (!job.scratch.isEmpty())
        QDir(job.scratch).removeRecursively();
}

void WebStore::relaunch() {
    if (dryRun) {
        ++relaunched;
        return;
    }
    QProcess again;
    again.setProgram(QCoreApplication::applicationFilePath());
    again.setProcessEnvironment(relaunchEnvironment());
    again.startDetached();
}

// main.cpp points XDG_DATA_HOME and XDG_CACHE_HOME at opsis-cef; a start made with those would nest a second opsis-cef in it,
// an empty profile with no pages and none of the added extensions (VM, 2026-10-29). The new start gets the outer ones back.
QProcessEnvironment WebStore::relaunchEnvironment() {
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    for (const char *name : {"DATA", "CACHE"}) {
        const QString outer = env.value(QStringLiteral("THYRIS_OUTER_XDG_") + QLatin1String(name) + QStringLiteral("_HOME"));
        if (!outer.isEmpty())
            env.insert(QStringLiteral("XDG_") + QLatin1String(name) + QStringLiteral("_HOME"), outer);
    }
    return env;
}

void WebStore::startUpdates() {
    if (m_started)
        return;
    m_started = true;
    m_daily.start();
    // a short wait after the start, so the start itself is not slowed by it
    QTimer::singleShot(20000, this, [this] { checkUpdates(); });
}

void WebStore::checkUpdates(bool force) {
    if (m_checking)
        return;
    QJsonObject state = readState();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!force && now - qint64(state.value(QStringLiteral("lastCheck")).toDouble()) < 20 * 3600 * 1000)
        return;
    m_ids.clear();
    for (const QJsonValue &v : Extensions::read()) {
        const QJsonObject e = v.toObject();
        if (e.value(QStringLiteral("source")).toString() == u"store" && QFileInfo::exists(storeDir() + u'/' + e.value(QStringLiteral("id")).toString()))
            m_ids << e.value(QStringLiteral("id")).toString();
    }
    if (m_ids.isEmpty())
        return;
    m_checking = true;
    nextCheck(0);
}

void WebStore::nextCheck(int index) {
    if (index >= m_ids.size()) {
        m_checking = false;
        emit checked();
        if (!askable(false).isEmpty())
            emit updatesToAsk();
        return;
    }
    const QString id = m_ids.at(index);
    const QJsonArray list = Extensions::read();
    const qsizetype at = indexOf(list, id);
    if (at < 0)
        return nextCheck(index + 1);
    const QJsonObject entry = list.at(at).toObject();
    const QString have = entry.value(QStringLiteral("version")).toString();
    const QUrl url = StoreRules::updateCheckUrl(id, prodVersion(), have);
    if (url.isEmpty())
        return nextCheck(index + 1);
    StoreFetch::get(transport(), url, 64 << 10, [this, index, id, have](const QByteArray &body, const QString &problem) {
        if (!problem.isEmpty())
            return nextCheck(index + 1);
        const StoreRules::UpdateAnswer answer = StoreRules::parseUpdateCheck(body, id, have);
        if (!answer.ok)
            return nextCheck(index + 1);
        // Google answered: today's check is done, whatever it said
        QJsonObject state = readState();
        state.insert(QStringLiteral("lastCheck"), double(QDateTime::currentMSecsSinceEpoch()));
        writeState(state);
        const QJsonArray list = Extensions::read();
        const QJsonObject entry = list.at(qMax<qsizetype>(0, indexOf(list, id))).toObject();
        if (!answer.newer || entry.value(QStringLiteral("pending")).toObject().value(QStringLiteral("version")).toString() == answer.version
            || entry.value(QStringLiteral("declined")).toString() == answer.version)
            return nextCheck(index + 1);
        StoreFetch::get(transport(), answer.file, maxFile, [this, index, id, answer](const QByteArray &file, const QString &why) {
            if (why.isEmpty())
                gotUpdate(id, file, answer.sha256);
            nextCheck(index + 1);
        });
    });
}

// the newest version's file: checked as a first addition is, and the same key; then kept beside the old version
void WebStore::gotUpdate(const QString &id, const QByteArray &file, const QString &sha256) {
    if (!sha256.isEmpty() && QString::fromLatin1(QCryptographicHash::hash(file, QCryptographicHash::Sha256).toHex()) != sha256)
        return;
    const Crx::Result r = Crx::verify(file, id);
    if (!r.ok)
        return;
    QJsonArray list = Extensions::read();
    const qsizetype at = indexOf(list, id);
    if (at < 0)
        return;
    QJsonObject entry = list.at(at).toObject();
    if (entry.value(QStringLiteral("key")).toString() != QString::fromLatin1(r.key.toBase64()))
        return;
    const QString scratch = newScratch(".staged-");
    QString root, why;
    if (!stage(r.zip, scratch, false, r.key, &root, &why)) {
        QDir(scratch).removeRecursively();
        return;
    }
    const QJsonObject fresh = Extensions::manifestOf(root);
    const QJsonObject old = Extensions::manifestOf(storeDir() + u'/' + id);
    const QString version = fresh.value(QStringLiteral("version")).toString();
    if (fresh.value(QStringLiteral("manifest_version")).toInt() != 3 || !StoreRules::versionNewer(version, old.value(QStringLiteral("version")).toString())) {
        QDir(scratch).removeRecursively();
        return;
    }
    const QStringList words = StoreRules::addedWords(old, fresh);
    const QString dest = storeDir() + QStringLiteral("/.update-") + id;
    QDir(dest).removeRecursively();
    if (!QDir().rename(scratch, dest)) {
        QDir(scratch).removeRecursively();
        return;
    }
    entry.insert(QStringLiteral("pending"), QJsonObject{{QStringLiteral("version"), version}, {QStringLiteral("approved"), words.isEmpty()},
                                                          {QStringLiteral("words"), QJsonArray::fromStringList(words)},
                                                          {QStringLiteral("name"), Extensions::nameOf(dest, fresh)}});
    list.replace(at, entry);
    Extensions::save(list);
    // nothing new asked for: it takes the old one's place at the next start
    if (words.isEmpty())
        Extensions::announce();
}

QVariantList WebStore::updateAsks() { return askable(true); }

QVariantList WebStore::askable(bool mark) {
    QVariantList out;
    for (const QJsonValue &v : Extensions::read()) {
        const QJsonObject e = v.toObject();
        const QJsonObject p = e.value(QStringLiteral("pending")).toObject();
        const QString id = e.value(QStringLiteral("id")).toString();
        if (p.isEmpty() || p.value(QStringLiteral("approved")).toBool() || m_asked.contains(id + u'@' + p.value(QStringLiteral("version")).toString()))
            continue;
        if (mark)
            m_asked << id + u'@' + p.value(QStringLiteral("version")).toString();
        out << QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), p.value(QStringLiteral("name")).toString(e.value(QStringLiteral("name")).toString())},
                           {QStringLiteral("version"), p.value(QStringLiteral("version")).toString()},
                           {QStringLiteral("words"), p.value(QStringLiteral("words")).toArray().toVariantList()},
                           {QStringLiteral("source"), QStringLiteral("store")}, {QStringLiteral("update"), true},
                           {QStringLiteral("icon"), iconOf(storeDir() + QStringLiteral("/.update-") + id, Extensions::manifestOf(storeDir() + QStringLiteral("/.update-") + id))}};
    }
    return out;
}

void WebStore::answerUpdate(const QString &id, bool yes) {
    QJsonArray list = Extensions::read();
    const qsizetype at = indexOf(list, id);
    if (at < 0)
        return;
    QJsonObject e = list.at(at).toObject();
    QJsonObject p = e.value(QStringLiteral("pending")).toObject();
    if (p.isEmpty())
        return;
    if (yes) {
        p.insert(QStringLiteral("approved"), true);
        e.insert(QStringLiteral("pending"), p);
    } else {
        // this version is not asked about again; a newer one is
        e.insert(QStringLiteral("declined"), p.value(QStringLiteral("version")));
        e.remove(QStringLiteral("pending"));
        QDir(storeDir() + QStringLiteral("/.update-") + id).removeRecursively();
    }
    list.replace(at, e);
    Extensions::save(list);
    if (yes)
        Extensions::announce();
}
