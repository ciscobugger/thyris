#pragma once

#include <QByteArray>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QHash>
#include <QJSValue>
#include <QMap>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <functional>
#include <memory>
#include <qqmlintegration.h>

// A secret as the Secret Service API passes it, (oayays): its session, the session's parameters (none for the "plain"
// session), the value and its content type.
struct SecretValue {
    QDBusObjectPath session;
    QByteArray parameters;
    QByteArray value;
    QString contentType;
};
Q_DECLARE_METATYPE(SecretValue)
QDBusArgument &operator<<(QDBusArgument &argument, const SecretValue &secret);
const QDBusArgument &operator>>(const QDBusArgument &argument, SecretValue &secret);
using SecretAttributes = QMap<QString, QString>;

// Saved passwords (PLAN.md 7, 3.15) in the system keyring over the Secret Service API (org.freedesktop.Secret, QtDBus):
// one item per origin and user name in the default collection, labelled with the host, with the attributes
// xdg:schema = browser.Password, origin and user. The secret is the keyring's alone: the browser holds it in memory only
// while it saves, fills or shows it, and never writes it to the profile, the session or a log. The session is "plain":
// the secret crosses the session bus as it is, which any process of this user can read the keyring over anyway.
class Passwords : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // "" while the keyring is first asked, "ready", or "none": no Secret Service answers
    Q_PROPERTY(QString state READ state NOTIFY changed)
    // the saved logins, by host then user name: [{ id (the item's object path), origin, user }], no secrets
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    // Delete in Settings waits for Undo: { id: seconds left }
    Q_PROPERTY(QVariantMap removing READ removing NOTIFY removingChanged)
public:
    explicit Passwords(QObject *parent = nullptr);
    ~Passwords() override;

    // --shots and --check-engine: never the desktop's session bus, whose keyring holds the user's own logins
    static inline bool noSessionBus = false;
    // seconds Delete waits for Undo (Site.undoSeconds, the site panel's)
    static constexpr int undoSeconds = 6;

    QString state() const { return m_state; }
    QVariantList entries() const { return m_entries; }
    QVariantMap removing() const;

    Q_INVOKABLE void refresh();
    // Saves (or replaces) the login; `done(ok, failure)`, failure "none" (no keyring), "locked" (its unlock was refused),
    // "unencrypted" (the keyring has no password: plainKeyring) or "failed"
    Q_INVOKABLE void save(const QString &origin, const QString &user, const QString &password, const QJSValue &done = QJSValue());
    // `done(secret, failure)`, secret undefined on a failure. A locked item is unlocked first, which may show the
    // keyring's prompt; `quiet` never prompts and fails as "locked" instead.
    Q_INVOKABLE void secret(const QString &id, bool quiet, const QJSValue &done);
    // The login `id` with another user name or password (an empty one keeps what was there); `done(ok, failure)`
    Q_INVOKABLE void edit(const QString &id, const QString &user, const QString &password, const QJSValue &done = QJSValue());
    // Delete: gone from the keyring once `undoSeconds` are over, or at a quit before that; keep() is the Undo
    Q_INVOKABLE void removeLater(const QString &id);
    Q_INVOKABLE void keep(const QString &id);
    // --check-engine: a throwaway Secret Service on the bus at `address`
    Q_INVOKABLE void useBus(const QString &address);
    // --shots: made-up logins in the lists, with no keyring behind them (only while no bus is connected)
    Q_INVOKABLE void fake(const QVariantList &entries);

    // Import from Zen (src/zen.*), in C++ only, so no password reaches QML: each login saved unless the keyring holds
    // its origin and user name already (importing again adds none, and a password saved here is not replaced by Zen's
    // older one); `then(added, kept, left, failure)`, failure "" or as save()'s, `left` the logins a failure left out. A
    // keyring whose list did not come (SearchItems refused) takes none, as it cannot say which it holds. `step(done)`,
    // when given, after each login saved or kept.
    struct Login {
        QString origin, user;
        QByteArray password;
    };
    void importLogins(QList<Login> logins, std::function<void(int, int, int, QString)> then, std::function<void(int)> step = {});
    // Another program's secret in the keyring, the first item with these attributes (an unlocked one before a locked
    // one, which is unlocked first, asking unless `quiet`): Chrome's "Safe Storage" key for its import (ChromeImport).
    // `then(secret, failure)`: failure "" , "missing" (no such item), "locked", "none" or "failed".
    void secretMatching(const SecretAttributes &attributes, bool quiet, std::function<void(QByteArray, QString)> then);
    // Whether gnome-keyring keeps the collection at this object path in plain text: a keyring whose password is empty is a
    // text file under $XDG_DATA_HOME/keyrings, the others carry the encrypted format's magic. False where there is no
    // such file (another Secret Service, the in-memory session collection): nothing says it is plain. No password is
    // saved into a plain one.
    static bool plainKeyring(const QString &collection);

signals:
    void changed();
    void removingChanged();

private slots:
    void promptCompleted(const QDBusMessage &message);

private:
    void setState(const QString &state);
    void watch();
    void call(const QString &path, const QString &interface, const QString &method, const QVariantList &args,
              std::function<void(const QDBusMessage &)> then);
    void withSession(std::function<void(bool)> then);
    void unlock(const QString &path, bool quiet, std::function<void(bool)> then);
    void prompt(const QString &path, std::function<void(bool)> then);
    void finishPrompt(const QString &path, bool completed);
    void store(const QString &origin, const QString &user, const QByteArray &password, std::function<void(QString, QString)> then);
    void read(const QString &id, bool quiet, std::function<void(QByteArray, QString)> then);
    void remove(const QString &id);
    QString failureOf(const QDBusMessage &reply);
    struct ImportRun {
        QList<Login> left;
        int added = 0, kept = 0;
        std::function<void(int, int, int, QString)> then;
        std::function<void(int)> step;
    };
    bool known(const QString &id) const;
    void importNext(std::shared_ptr<ImportRun> run);

    QDBusConnection m_bus;
    QString m_state;
    QVariantList m_entries;
    QDBusObjectPath m_session;
    bool m_fake = false;
    bool m_listed = false;      // the last SearchItems answered: m_entries is what the keyring holds
    int m_refreshes = 0;
    int m_generation = 0;
    QHash<QString, std::function<void(bool)>> m_prompts;
    QHash<QString, int> m_removing;
    QTimer m_tick;
    QObject *m_watcher = nullptr;
};
