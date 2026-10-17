#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <qqmlintegration.h>

// Downloaded files (PLAN.md 3.8 8d): the folder they go to, the origin written on each as extended
// attributes so Files can show it later, and deleting one ("Runs as a program. Keep · Delete").
class Disk : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // ~/Downloads (the XDG download dir); --shots and --check-engine: their throwaway data dir's Downloads
    Q_PROPERTY(QString downloads READ downloads CONSTANT)
public:
    using QObject::QObject;

    static inline QString folderOverride;

    QString downloads() const;
    // Each `attributes` key (user.xdg.origin.url, user.xdg.referrer.url, user.browser.thread) set on the
    // file at `path` to its value; false if the file or its file system takes none.
    Q_INVOKABLE bool mark(const QString &path, const QVariantMap &attributes) const;
    // Deletes the regular file at `path`; false if there is none or it stays.
    Q_INVOKABLE bool remove(const QString &path) const;
    // `folder`/`name`, or with " (1)", " (2)" … before the extension while that is taken, as Chromium names a download
    // (a printed PDF, PLAN.md 3.16)
    Q_INVOKABLE QString unique(const QString &folder, const QString &name) const;
};
