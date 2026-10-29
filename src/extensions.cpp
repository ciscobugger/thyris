#include "extensions.h"

#include "crx.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>

QString Extensions::store() {
    return !storeOverride.isEmpty() ? storeOverride
        : QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/browser/extensions/added");
}

QJsonArray Extensions::read() {
    QFile file(store() + QStringLiteral("/added.json"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).array();
}

bool Extensions::save(const QJsonArray &list) {
    QDir().mkpath(store());
    QSaveFile file(store() + QStringLiteral("/added.json"));
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(list).toJson(QJsonDocument::Compact));
    return file.commit();
}

QStringList Extensions::loadPaths() {
    QStringList paths;
    for (const QJsonValue &v : read()) {
        const QJsonObject e = v.toObject();
        const QString dir = store() + u'/' + e.value(QStringLiteral("id")).toString();
        if (e.value(QStringLiteral("enabled")).toBool() && QFile::exists(dir + QStringLiteral("/manifest.json")))
            paths << dir;
    }
    return paths;
}

Extensions::Extensions(QObject *parent) : QObject(parent) { s_self = this; }

void Extensions::announce() {
    s_restart = true;
    if (s_self)
        emit s_self->changed();
}

QVariantList Extensions::extensions() const {
    QVariantList out;
    for (const QJsonValue &v : read()) {
        const QJsonObject e = v.toObject();
        out << QVariantMap{{QStringLiteral("id"), e.value(QStringLiteral("id")).toString()},
                           {QStringLiteral("name"), e.value(QStringLiteral("name")).toString()},
                           {QStringLiteral("isInstalled"), true},
                           {QStringLiteral("isEnabled"), e.value(QStringLiteral("enabled")).toBool()},
                           {QStringLiteral("error"), QString()},
                           {QStringLiteral("source"), e.value(QStringLiteral("source")).toString(QStringLiteral("file"))},
                           {QStringLiteral("version"), e.value(QStringLiteral("version")).toString()},
                           {QStringLiteral("added"), e.value(QStringLiteral("added")).toDouble()},
                           {QStringLiteral("updated"), e.value(QStringLiteral("updated")).toDouble()},
                           {QStringLiteral("waiting"), e.value(QStringLiteral("pending")).toObject().value(QStringLiteral("approved")).toBool()}};
    }
    return out;
}

QString Extensions::idOf(const QVariant &info) {
    // only ids this class or WebStore made name a folder: no path in one is ever followed
    const QString id = info.toMap().value(QStringLiteral("id")).toString();
    static const QRegularExpression plain(QStringLiteral("^([0-9a-f]{12}|[a-p]{32})$"));
    return plain.match(id).hasMatch() ? id : QString();
}

void Extensions::fail(const QString &why) {
    m_problem = why;
    m_busy = false;
    emit changed();
}

QJsonObject Extensions::manifestOf(const QString &dir) {
    QFile file(dir + QStringLiteral("/manifest.json"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QJsonParseError parse;
    const QJsonObject manifest = QJsonDocument::fromJson(file.readAll(), &parse).object();
    return parse.error == QJsonParseError::NoError ? manifest : QJsonObject();
}

// The name a manifest shows: its own, or a locale's message when the name is a "__MSG_x__" key
QString Extensions::nameOf(const QString &dir, const QJsonObject &manifest) {
    QString name = manifest.value(QStringLiteral("name")).toString();
    if (name.startsWith(QLatin1String("__MSG_")) && name.endsWith(QLatin1String("__"))) {
        const QString key = name.mid(6, name.size() - 8);
        const QString locale = manifest.value(QStringLiteral("default_locale")).toString();
        QFile file(dir + QStringLiteral("/_locales/") + locale + QStringLiteral("/messages.json"));
        name.clear();
        if (!locale.isEmpty() && !locale.contains(u'/') && file.open(QIODevice::ReadOnly)) {
            const QJsonObject messages = QJsonDocument::fromJson(file.readAll()).object();
            for (auto it = messages.begin(); it != messages.end(); ++it)
                if (it.key().compare(key, Qt::CaseInsensitive) == 0)
                    name = it.value().toObject().value(QStringLiteral("message")).toString();
        }
    }
    return name.trimmed();
}

// A symlink in an added folder could lead the engine out of it: none is kept
static void dropLinks(const QString &dir) {
    QDirIterator it(dir, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System | QDir::Hidden, QDirIterator::Subdirectories);
    QStringList links;
    while (it.hasNext())
        if (QFileInfo(it.next()).isSymLink())
            links << it.filePath();
    for (const QString &l : std::as_const(links))
        QFile::remove(l);
}

static bool copyTree(const QString &from, const QString &to) {
    if (!QDir().mkpath(to))
        return false;
    const QFileInfoList entries = QDir(from).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    for (const QFileInfo &e : entries) {
        if (e.isSymLink())
            continue;
        if (e.isDir() ? !copyTree(e.filePath(), to + u'/' + e.fileName()) : !QFile::copy(e.filePath(), to + u'/' + e.fileName()))
            return false;
    }
    return true;
}

bool Extensions::commit(const QString &from, bool move, const Added &meta, QString *problem, QVariantMap *info) {
    const auto fail = [problem](const QString &why) {
        if (problem)
            *problem = why;
        return false;
    };
    const QJsonObject manifest = manifestOf(from);
    if (manifest.isEmpty())
        return fail(QFile::exists(from + QStringLiteral("/manifest.json")) ? tr("The extension's description can't be read.")
                                                                           : tr("That isn't an extension. Choose the extension's own folder, or its .zip."));
    if (manifest.value(QStringLiteral("manifest_version")).toInt() != 3)
        return fail(tr("That extension is built for an older version of Chrome, which Thyris can't run. A newer or \"Lite\" version of it may work."));
    const QString name = nameOf(from, manifest);
    if (name.isEmpty())
        return fail(tr("The extension has no name."));
    QJsonArray list = read();
    const bool fromStore = meta.source == u"store";
    for (const QJsonValue &v : std::as_const(list)) {
        const QJsonObject e = v.toObject();
        if (e.value(QStringLiteral("name")).toString() == name || (fromStore && e.value(QStringLiteral("id")).toString() == meta.id))
            return fail(tr("%1 is already added.").arg(name));
    }

    const QString id = fromStore ? meta.id : QUuid::createUuid().toString(QUuid::Id128).left(12);
    const QString to = store() + u'/' + id;
    QDir().mkpath(store());
    // a folder already there is not ours to replace
    if (QFileInfo::exists(to))
        return fail(tr("%1 is already added.").arg(name));
    if (move ? !QDir().rename(from, to) : !copyTree(from, to)) {
        QDir(to).removeRecursively();
        return fail(tr("%1 couldn't be copied into Thyris.").arg(name));
    }
    dropLinks(to);
    // A file's own "key" would give it a store extension's id (the keys are public); only the store path writes one.
    if (!fromStore && manifest.contains(QStringLiteral("key"))) {
        QJsonObject clean = manifest;
        clean.remove(QStringLiteral("key"));
        QFile f(to + QStringLiteral("/manifest.json"));
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate) || f.write(QJsonDocument(clean).toJson(QJsonDocument::Compact)) < 0) {
            QDir(to).removeRecursively();
            return fail(tr("%1 couldn't be copied into Thyris.").arg(name));
        }
    }
    const double now = double(QDateTime::currentMSecsSinceEpoch());
    QJsonObject entry{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("enabled"), true},
                      {QStringLiteral("source"), meta.source}, {QStringLiteral("version"), manifest.value(QStringLiteral("version")).toString()},
                      {QStringLiteral("added"), now}, {QStringLiteral("updated"), now}};
    if (fromStore)
        entry.insert(QStringLiteral("key"), meta.key);
    list.append(entry);
    if (!save(list)) {
        QDir(to).removeRecursively();
        return fail(tr("The list of extensions couldn't be saved."));
    }
    if (info)
        *info = QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("isInstalled"), true},
                            {QStringLiteral("isEnabled"), true}, {QStringLiteral("error"), QString()}};
    return true;
}

// `from` holds manifest.json (the folder chosen, or what a .zip held); `move`: it is Thyris's own scratch folder
void Extensions::add(const QString &from, bool move) {
    QString problem;
    QVariantMap info;
    if (!commit(from, move, Added(), &problem, &info))
        return fail(problem);
    m_problem.clear();
    s_restart = true;
    m_busy = false;
    emit changed();
    emit installFinished(info);
    emit loadFinished();
}

void Extensions::installExtension(const QString &path) {
    if (m_busy)
        return;
    const QFileInfo info(path);
    if (info.isDir()) {
        m_busy = true;
        add(info.absoluteFilePath(), false);
        return;
    }
    if (!info.isFile() || info.suffix().compare(QLatin1String("zip"), Qt::CaseInsensitive) != 0)
        return fail(tr("Choose an extension's folder or a .zip file."));
    QFile zip(info.absoluteFilePath());
    if (info.size() > (64 << 20) || !zip.open(QIODevice::ReadOnly))
        return fail(tr("The .zip couldn't be opened."));
    const QString scratch = store() + QStringLiteral("/.incoming-") + QUuid::createUuid().toString(QUuid::Id128).left(8);
    QDir().mkpath(scratch);
    m_busy = true;
    const QString why = Zip::extract(zip.readAll(), scratch);
    if (!why.isEmpty()) {
        QDir(scratch).removeRecursively();
        return fail(why);
    }
    // the manifest at the top, or in the one folder a zip of a folder holds
    QString root = scratch;
    if (!QFile::exists(root + QStringLiteral("/manifest.json"))) {
        const QStringList dirs = QDir(scratch).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        if (dirs.size() == 1)
            root = scratch + u'/' + dirs.first();
    }
    add(root, true);
    QDir(scratch).removeRecursively();
}

void Extensions::uninstallExtension(const QVariant &info) {
    const QString id = idOf(info);
    if (id.isEmpty())
        return;
    QJsonArray list = read(), kept;
    for (const QJsonValue &v : std::as_const(list))
        if (v.toObject().value(QStringLiteral("id")).toString() != id)
            kept.append(v);
    if (kept.size() == list.size() || !save(kept))
        return;
    QDir(store() + u'/' + id).removeRecursively();
    QDir(store() + QStringLiteral("/.update-") + id).removeRecursively();
    s_restart = true;
    emit changed();
    emit uninstallFinished();
}

void Extensions::setExtensionEnabled(const QVariant &info, bool enabled) {
    const QString id = idOf(info);
    if (id.isEmpty())
        return;
    QJsonArray list = read();
    bool found = false;
    for (qsizetype i = 0; i < list.size(); ++i) {
        QJsonObject e = list.at(i).toObject();
        if (e.value(QStringLiteral("id")).toString() == id) {
            e.insert(QStringLiteral("enabled"), enabled);
            list.replace(i, e);
            found = true;
        }
    }
    if (!found || !save(list))
        return;
    s_restart = true;
    emit changed();
    if (enabled)
        emit loadFinished();
    else
        emit unloadFinished();
}
