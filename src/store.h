#pragma once

#include <QHash>
#include <QMutex>
#include <QObject>
#include <QVariant>
#include <qqmlintegration.h>

// JSON files under ~/.local/share/browser, written atomically so a crash never leaves half a file.
class Store : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)
public:
    explicit Store(QObject *parent = nullptr);

    QString dataDir() const { return m_dataDir; }
    Q_INVOKABLE QVariant load(const QString &name) const;
    Q_INVOKABLE bool save(const QString &name, const QVariant &value) const;
    // save() written on a worker thread: the file is serialised and fsynced off the UI thread. A later save of the same
    // name, either kind, replaces one still waiting; save() waits for a write under way, so the last call wins on disk.
    Q_INVOKABLE void saveLater(const QString &name, const QVariant &value);
    ~Store() override;

private:
    bool write(const QString &name, const QVariant &plainValue) const;
    QString m_dataDir;
    mutable QMutex m_genLock;               // guards m_gen
    mutable QHash<QString, quint64> m_gen;  // per name: the latest save asked for
    mutable QMutex m_writeLock;             // one file write at a time
};
