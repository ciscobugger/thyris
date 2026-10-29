#pragma once

#include <QJsonArray>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <qqmlintegration.h>

class QProcess;

// The extensions a person adds in Settings > Extensions. The engine (CEF 154) has no extension manager: it loads the
// unpacked folders named in --load-extension at its start and runs them (a declarativeNetRequest rule and a content
// script both worked, 2026-10-29). So Thyris keeps a copy of each added extension under
// <data>/browser/extensions/added/<id>, a list of them in added.json, and main.cpp hands the turned-on ones to the engine
// at the next start. The members are those of Qt WebEngine's ExtensionManager that SettingsPage uses.
class Extensions : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{ id, name, isInstalled, isEnabled, error }], the ones added here
    Q_PROPERTY(QVariantList extensions READ extensions NOTIFY changed)
    // why the last Add failed, in words; empty after one that worked
    Q_PROPERTY(QString problem READ problem NOTIFY changed)
    // something was added, removed or switched since this start: the engine still runs the list it started with
    Q_PROPERTY(bool restartNeeded READ restartNeeded NOTIFY changed)
public:
    explicit Extensions(QObject *parent = nullptr);

    // the folders of the turned-on extensions, for --load-extension at the start
    Q_INVOKABLE static QStringList loadPaths();
    // --check-engine and tests: where the extensions are kept (default: the data folder's browser/extensions/added)
    static inline QString storeOverride;

    QVariantList extensions() const;
    QString problem() const { return m_problem; }
    bool restartNeeded() const { return m_restart; }

    // `path`: an unpacked extension's folder, or a .zip of one
    Q_INVOKABLE void installExtension(const QString &path);
    // `info` is one of `extensions`
    Q_INVOKABLE void uninstallExtension(const QVariant &info);
    Q_INVOKABLE void setExtensionEnabled(const QVariant &info, bool enabled);

signals:
    void changed();
    void installFinished(const QVariantMap &extension);
    void uninstallFinished();
    void loadFinished();
    void unloadFinished();

private:
    static QString store();
    static QJsonArray read();
    bool save(const QJsonArray &list);
    void fail(const QString &why);
    void add(const QString &from, bool move);
    static QString idOf(const QVariant &info);

    QString m_problem;
    bool m_restart = false;
    bool m_busy = false;
};
