#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantMap>
#include <thread>

class AdblockInterceptor;

// Brave's adblock engine (adblock/, Rust) loaded with uBlock Origin's lists and scriptlets.
// Data comes from tools/update-lists: <dataDir>/lists/*.txt and <dataDir>/resources.json.
class Adblock : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY listsChanged)
    // Settings > Ad blocking (PLAN.md 3.15): the lists the engine was built from, { file (its name without .txt),
    // title, version, modified (ms) }. The files a list pulls in with !#include (inc-*) are part of it, not listed.
    Q_PROPERTY(QVariantList lists READ lists NOTIFY listsChanged)
    Q_PROPERTY(bool updating READ updating NOTIFY updatingChanged)
    // tools/update-lists beside the build; only --check-engine sets another
    Q_PROPERTY(QString updateScript READ updateScript WRITE setUpdateScript NOTIFY updatingChanged)
public:
    explicit Adblock(const QString &dataDir, QObject *parent = nullptr);
    ~Adblock() override;

    static inline bool checkMode = false;
    // CEF with uBlock Origin Lite loaded (main.cpp): it blocks, and this neither refuses requests nor gives pages cosmetics
    static inline bool extensionBlocks = false;

    bool ready() const { return m_engine != nullptr; }
    // Installs a request interceptor on a WebEngineProfile, one of its own for each profile: a private window's
    // (PLAN.md 3.14) has its own counts and Allowed sites, which go with that profile. `profile` below is one given
    // here; null is the first, the main profile.
    Q_INVOKABLE void attach(QObject *profile);
    // {css, script} for a page URL: element-hiding CSS, and scriptlets for the page's main world.
    Q_INVOKABLE QVariantMap cosmetic(const QString &url, QObject *profile = nullptr) const;
    Q_INVOKABLE QString stats() const;
    // The site panel's switch (PLAN.md 3.9): hosts whose pages get no ad blocking, neither refused requests
    // nor element hiding and scriptlets.
    Q_INVOKABLE void setAllowed(const QStringList &hosts, QObject *profile = nullptr);
    // What the interceptor saw for the page at `url` since that address last loaded: { blocked (requests
    // refused), insecureImages (an image, audio or video fetched over plain http for an https page) }. The
    // engine names a request's page only by its address (firstPartyUrl), so two pages at one address share it.
    Q_INVOKABLE QVariantMap seen(const QString &url, QObject *profile = nullptr) const;

    QVariantList lists() const { return m_lists; }
    bool updating() const { return m_updating; }
    QString updateScript() const { return m_script; }
    void setUpdateScript(const QString &path);
    // Runs the update script (Update now); once it has written the lists, the engine is built again from them off the
    // UI thread and takes over from the old one, and updated() answers.
    Q_INVOKABLE void update();

signals:
    void listsChanged();
    void updatingChanged();
    // `failure`: "" once the new lists are in use, else the script's last line of complaint (or why it did not run)
    void updated(const QString &failure);

private:
    AdblockInterceptor *interceptorOf(QObject *profile) const;
    void finishUpdate(void *engine, const QVariantList &lists);

    QString m_dataDir;
    QString m_script;
    void *m_engine = nullptr;
    QVariantList m_lists;
    bool m_updating = false;
    std::thread m_builder;
    AdblockInterceptor *m_first = nullptr;
    QHash<QObject *, AdblockInterceptor *> m_interceptors;
};
