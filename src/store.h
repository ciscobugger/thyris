#pragma once

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

private:
    QString m_dataDir;
};
