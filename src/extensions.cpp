#include "extensions.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
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

Extensions::Extensions(QObject *parent) : QObject(parent) {}

QVariantList Extensions::extensions() const {
    QVariantList out;
    for (const QJsonValue &v : read()) {
        const QJsonObject e = v.toObject();
        out << QVariantMap{{QStringLiteral("id"), e.value(QStringLiteral("id")).toString()},
                           {QStringLiteral("name"), e.value(QStringLiteral("name")).toString()},
                           {QStringLiteral("isInstalled"), true},
                           {QStringLiteral("isEnabled"), e.value(QStringLiteral("enabled")).toBool()},
                           {QStringLiteral("error"), QString()}};
    }
    return out;
}

QString Extensions::idOf(const QVariant &info) {
    // only ids this class made name a folder: no path in one is ever followed
    const QString id = info.toMap().value(QStringLiteral("id")).toString();
    static const QRegularExpression plain(QStringLiteral("^[0-9a-f]{12}$"));
    return plain.match(id).hasMatch() ? id : QString();
}

void Extensions::fail(const QString &why) {
    m_problem = why;
    m_busy = false;
    emit changed();
}

// The name a manifest shows: its own, or a locale's message when the name is a "__MSG_x__" key
static QString nameOf(const QString &dir, const QJsonObject &manifest) {
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

// `from` holds manifest.json (the folder chosen, or what a .zip held); `move`: it is Thyris's own scratch folder
void Extensions::add(const QString &from, bool move) {
    QFile file(from + QStringLiteral("/manifest.json"));
    if (!file.open(QIODevice::ReadOnly))
        return fail(tr("That has no manifest.json. Choose the extension's own folder, or its .zip."));
    QJsonParseError parse;
    const QJsonObject manifest = QJsonDocument::fromJson(file.readAll(), &parse).object();
    if (parse.error != QJsonParseError::NoError || manifest.isEmpty())
        return fail(tr("The extension's manifest.json can't be read."));
    if (manifest.value(QStringLiteral("manifest_version")).toInt() != 3)
        return fail(tr("That extension is an older kind (Manifest 2), which Thyris can't run."));
    const QString name = nameOf(from, manifest);
    if (name.isEmpty())
        return fail(tr("The extension has no name."));
    QJsonArray list = read();
    for (const QJsonValue &v : std::as_const(list))
        if (v.toObject().value(QStringLiteral("name")).toString() == name)
            return fail(tr("%1 is already added.").arg(name));

    const QString id = QUuid::createUuid().toString(QUuid::Id128).left(12);
    const QString to = store() + u'/' + id;
    QDir().mkpath(store());
    if (move ? !QDir().rename(from, to) : !copyTree(from, to)) {
        QDir(to).removeRecursively();
        return fail(tr("%1 couldn't be copied into Thyris.").arg(name));
    }
    dropLinks(to);
    list.append(QJsonObject{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("enabled"), true}});
    if (!save(list)) {
        QDir(to).removeRecursively();
        return fail(tr("The list of extensions couldn't be saved."));
    }
    m_problem.clear();
    m_restart = true;
    m_busy = false;
    emit changed();
    emit installFinished(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("isInstalled"), true},
                                     {QStringLiteral("isEnabled"), true}, {QStringLiteral("error"), QString()}});
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
    // bsdtar (libarchive) reads a .zip and refuses paths that climb out of the folder it extracts into
    const QString scratch = store() + QStringLiteral("/.incoming-") + QUuid::createUuid().toString(QUuid::Id128).left(8);
    QDir().mkpath(scratch);
    m_busy = true;
    auto *tar = new QProcess(this);
    connect(tar, &QProcess::errorOccurred, this, [this, tar, scratch](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        QDir(scratch).removeRecursively();
        tar->deleteLater();
        fail(tr("The .zip couldn't be opened."));
    });
    connect(tar, &QProcess::finished, this, [this, tar, scratch](int code, QProcess::ExitStatus status) {
        tar->deleteLater();
        if (code != 0 || status != QProcess::NormalExit) {
            QDir(scratch).removeRecursively();
            return fail(tr("The .zip couldn't be opened."));
        }
        dropLinks(scratch);
        // the manifest at the top, or in the one folder a zip of a folder holds
        QString root = scratch;
        if (!QFile::exists(root + QStringLiteral("/manifest.json"))) {
            const QStringList dirs = QDir(scratch).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
            if (dirs.size() == 1)
                root = scratch + u'/' + dirs.first();
        }
        add(root, true);
        QDir(scratch).removeRecursively();
    });
    tar->start(QStringLiteral("bsdtar"), {QStringLiteral("-xf"), info.absoluteFilePath(), QStringLiteral("-C"), scratch});
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
    m_restart = true;
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
    m_restart = true;
    emit changed();
    if (enabled)
        emit loadFinished();
    else
        emit unloadFinished();
}
