#include "disk.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <sys/xattr.h>

QString Disk::downloads() const {
    const QString folder = folderOverride.isEmpty() ? QStandardPaths::writableLocation(QStandardPaths::DownloadLocation) : folderOverride;
    QDir().mkpath(folder);
    return folder;
}

bool Disk::mark(const QString &path, const QVariantMap &attributes) const {
    const QByteArray file = QFile::encodeName(path);
    bool all = true;
    for (auto it = attributes.cbegin(); it != attributes.cend(); ++it) {
        const QByteArray value = it.value().toString().toUtf8();
        if (!it.key().startsWith(QLatin1String("user.")) || value.isEmpty())
            continue;
        all = ::setxattr(file.constData(), it.key().toUtf8().constData(), value.constData(), size_t(value.size()), 0) == 0 && all;
    }
    return all;
}

bool Disk::remove(const QString &path) const {
    const QFileInfo info(path);
    return info.isFile() && QFile::remove(path);
}

QString Disk::unique(const QString &folder, const QString &name) const {
    const QDir dir(folder);
    const qsizetype dot = name.lastIndexOf(u'.');
    const QString base = dot > 0 ? name.left(dot) : name, extension = dot > 0 ? name.mid(dot) : QString();
    QString path = dir.filePath(name);
    for (int n = 1; QFileInfo::exists(path) || QFileInfo::exists(path + QStringLiteral(".download")); ++n)
        path = dir.filePath(base + QStringLiteral(" (%1)").arg(n) + extension);
    return path;
}
