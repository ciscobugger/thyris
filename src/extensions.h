#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
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
    // [{ id, name, isInstalled, isEnabled, error, source ("store" or "file"), version, added, updated (ms), waiting (an update
    // waits for the next start) }], the ones added here
    Q_PROPERTY(QVariantList extensions READ extensions NOTIFY changed)
    // why the last Add failed, in words; empty after one that worked
    Q_PROPERTY(QString problem READ problem NOTIFY changed)
    // something was added, removed or switched since this start: the engine still runs the list it started with
    Q_PROPERTY(bool restartNeeded READ restartNeeded NOTIFY changed)
public:
    explicit Extensions(QObject *parent = nullptr);
    ~Extensions() override { s_self = nullptr; }

    // the folders of the turned-on extensions, for --load-extension at the start
    Q_INVOKABLE static QStringList loadPaths();
    // Extensions come from the Chrome Web Store (src/webstore.*) or from a folder or .zip. The list and its folder are shared:
    static QString store();
    static QJsonArray read();
    static bool save(const QJsonArray &list);
    // `from` (holding manifest.json) becomes an added extension: moved or copied into the store, listed and on. `source` is
    // "store" (`id` is its 32-letter id and `key` its public key in base64, both checked by the caller) or "file" (`id` empty:
    // a name of Thyris's own). false with `problem` set when it is not added.
    struct Added {
        QString source = QStringLiteral("file");
        QString id;
        QString key;
    };
    static bool commit(const QString &from, bool move, const Added &meta, QString *problem, QVariantMap *info = nullptr);
    // the manifest of a folder, empty when it cannot be read; the name a manifest shows (its own, or a locale's message)
    static QJsonObject manifestOf(const QString &dir);
    static QString nameOf(const QString &dir, const QJsonObject &manifest);
    // something was added, removed or switched from outside this class (WebStore): the lists redraw
    static void announce();
    // --check-engine and tests: where the extensions are kept (default: the data folder's browser/extensions/added)
    static inline QString storeOverride;

    QVariantList extensions() const;
    QString problem() const { return m_problem; }
    bool restartNeeded() const { return s_restart; }

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
    void fail(const QString &why);
    void add(const QString &from, bool move);
    static QString idOf(const QVariant &info);
    static inline Extensions *s_self = nullptr;
    static inline bool s_restart = false;

    QString m_problem;
    bool m_busy = false;
};
