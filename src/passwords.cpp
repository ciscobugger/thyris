#include "passwords.h"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <memory>

namespace {
const QString service = QStringLiteral("org.freedesktop.secrets");
const QString servicePath = QStringLiteral("/org/freedesktop/secrets");
const QString serviceInterface = QStringLiteral("org.freedesktop.Secret.Service");
const QString collectionInterface = QStringLiteral("org.freedesktop.Secret.Collection");
const QString itemInterface = QStringLiteral("org.freedesktop.Secret.Item");
const QString promptInterface = QStringLiteral("org.freedesktop.Secret.Prompt");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");
// libsecret's convention, so the keyring's own tools (secret-tool, Seahorse) tell these items apart
const QString schema = QStringLiteral("browser.Password");

void answer(const QJSValue &done, const QJSValueList &args) {
    if (done.isCallable())
        QJSValue(done).call(args);
}
QString hostOf(const QString &origin) {
    const QString host = QUrl(origin).host();
    return host.isEmpty() ? origin : host;
}
}

QDBusArgument &operator<<(QDBusArgument &argument, const SecretValue &secret) {
    argument.beginStructure();
    argument << secret.session << secret.parameters << secret.value << secret.contentType;
    argument.endStructure();
    return argument;
}
const QDBusArgument &operator>>(const QDBusArgument &argument, SecretValue &secret) {
    argument.beginStructure();
    argument >> secret.session >> secret.parameters >> secret.value >> secret.contentType;
    argument.endStructure();
    return argument;
}

Passwords::Passwords(QObject *parent)
    : QObject(parent),
      m_bus(noSessionBus ? QDBusConnection(QStringLiteral("browser-no-bus")) : QDBusConnection::sessionBus()) {
    qDBusRegisterMetaType<SecretValue>();
    qDBusRegisterMetaType<SecretAttributes>();
    m_tick.setInterval(1000);
    connect(&m_tick, &QTimer::timeout, this, [this] {
        QStringList due;
        for (auto it = m_removing.begin(); it != m_removing.end(); ++it)
            if (--it.value() <= 0)
                due << it.key();
        for (const QString &id : due) {
            m_removing.remove(id);
            remove(id);
        }
        if (m_removing.isEmpty())
            m_tick.stop();
        emit removingChanged();
    });
    watch();
    QMetaObject::invokeMethod(this, &Passwords::refresh, Qt::QueuedConnection);
}

// A Delete still waiting on its Undo happens at the quit, as it would have 6 s on, unlocked first as then. An item whose
// unlock needs the keyring's prompt stays: no prompt can show at a quit.
Passwords::~Passwords() {
    for (auto it = m_removing.cbegin(); it != m_removing.cend(); ++it) {
        QDBusMessage unlock = QDBusMessage::createMethodCall(service, servicePath, serviceInterface, QStringLiteral("Unlock"));
        unlock.setArguments({QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(it.key())})});
        const QDBusMessage reply = m_bus.call(unlock, QDBus::Block, 3000);
        if (reply.type() == QDBusMessage::ErrorMessage)
            continue;
        if (qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(0)).isEmpty()) {
            const QString promptPath = qdbus_cast<QDBusObjectPath>(reply.arguments().value(1)).path();
            if (!promptPath.isEmpty() && promptPath != u"/")
                m_bus.call(QDBusMessage::createMethodCall(service, promptPath, promptInterface, QStringLiteral("Dismiss")), QDBus::Block, 3000);
            continue;
        }
        m_bus.call(QDBusMessage::createMethodCall(service, it.key(), itemInterface, QStringLiteral("Delete")), QDBus::Block, 3000);
    }
}

// An item of the list: only those the browser saved (xdg:schema browser.Password, as refresh() lists them) are read,
// changed or deleted, whatever path is passed
bool Passwords::known(const QString &id) const {
    return std::any_of(m_entries.cbegin(), m_entries.cend(), [&](const QVariant &e) { return e.toMap().value(QStringLiteral("id")).toString() == id; });
}

QVariantMap Passwords::removing() const {
    QVariantMap out;
    for (auto it = m_removing.cbegin(); it != m_removing.cend(); ++it)
        out.insert(it.key(), it.value());
    return out;
}

void Passwords::setState(const QString &state) {
    m_state = state;
    emit changed();
}

// The keyring coming or going (gnome-keyring started by D-Bus, a restart): its sessions end with it.
void Passwords::watch() {
    delete m_watcher;
    auto *watcher = new QDBusServiceWatcher(service, m_bus, QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this);
    m_watcher = watcher;
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
        m_session = QDBusObjectPath();
        refresh();
    });
    connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        m_session = QDBusObjectPath();
        ++m_generation;
        m_entries.clear();
        m_listed = false;
        setState(QStringLiteral("none"));
    });
}

void Passwords::useBus(const QString &address) {
    // a name of its own each time: connectToBus hands back a connection of that name already made, whatever its address
    static int connections = 0;
    m_bus = QDBusConnection::connectToBus(address, QStringLiteral("browser-check-keyring-%1").arg(++connections));
    m_session = QDBusObjectPath();
    ++m_generation;
    watch();
    refresh();
}

void Passwords::fake(const QVariantList &entries) {
    if (m_bus.isConnected())
        return;
    m_fake = true;
    m_entries = entries;
    m_listed = true;
    setState(QStringLiteral("ready"));
}

void Passwords::call(const QString &path, const QString &interface, const QString &method, const QVariantList &args,
                     std::function<void(const QDBusMessage &)> then) {
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);
    message.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, then = std::move(then)] {
        watcher->deleteLater();
        then(watcher->reply());
    });
}

// "none" when nothing answers for the Secret Service, else "failed"; "" for a reply that is no error
QString Passwords::failureOf(const QDBusMessage &reply) {
    if (reply.type() != QDBusMessage::ErrorMessage)
        return QString();
    const QString name = reply.errorName();
    for (const char *gone : {"org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner",
                             "org.freedesktop.DBus.Error.NoReply", "org.freedesktop.DBus.Error.Disconnected"})
        if (name == QLatin1String(gone))
            return QStringLiteral("none");
    return QStringLiteral("failed");
}

void Passwords::refresh() {
    const int serial = ++m_refreshes, generation = m_generation;
    if (!m_bus.isConnected()) {
        if (m_fake)
            return;
        m_entries.clear();
        m_listed = false;
        setState(QStringLiteral("none"));
        return;
    }
    call(servicePath, serviceInterface, QStringLiteral("SearchItems"), {QVariant::fromValue(SecretAttributes{{QStringLiteral("xdg:schema"), schema}})},
         [this, serial, generation](const QDBusMessage &reply) {
        if (serial != m_refreshes || generation != m_generation)
            return;
        if (reply.type() == QDBusMessage::ErrorMessage) {
            m_entries.clear();
            m_listed = false;
            setState(failureOf(reply) == u"none" ? QStringLiteral("none") : QStringLiteral("ready"));
            return;
        }
        // gnome-keyring reads a locked item's attributes out too
        const QList<QDBusObjectPath> paths = qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(0))
            + qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(1));
        if (paths.isEmpty()) {
            m_entries.clear();
            m_listed = true;
            setState(QStringLiteral("ready"));
            return;
        }
        auto found = std::make_shared<QVariantList>();
        auto left = std::make_shared<qsizetype>(paths.size());
        for (const QDBusObjectPath &path : paths)
            call(path.path(), propertiesInterface, QStringLiteral("Get"), {itemInterface, QStringLiteral("Attributes")},
                 [this, serial, generation, found, left, id = path.path()](const QDBusMessage &got) {
                if (serial != m_refreshes || generation != m_generation)
                    return;
                if (got.type() != QDBusMessage::ErrorMessage) {
                    const auto a = qdbus_cast<SecretAttributes>(got.arguments().value(0).value<QDBusVariant>().variant());
                    if (a.value(QStringLiteral("xdg:schema")) == schema && !a.value(QStringLiteral("origin")).isEmpty())
                        found->append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("origin"), a.value(QStringLiteral("origin"))},
                                                  {QStringLiteral("user"), a.value(QStringLiteral("user"))}});
                }
                if (--*left > 0)
                    return;
                std::sort(found->begin(), found->end(), [](const QVariant &x, const QVariant &y) {
                    const QVariantMap a = x.toMap(), b = y.toMap();
                    const QString ha = hostOf(a.value(QStringLiteral("origin")).toString()), hb = hostOf(b.value(QStringLiteral("origin")).toString());
                    return ha != hb ? ha < hb : a.value(QStringLiteral("user")).toString() < b.value(QStringLiteral("user")).toString();
                });
                m_entries = *found;
                m_listed = true;
                setState(QStringLiteral("ready"));
            });
    });
}

void Passwords::withSession(std::function<void(bool)> then) {
    if (!m_session.path().isEmpty()) {
        then(true);
        return;
    }
    const int generation = m_generation;
    call(servicePath, serviceInterface, QStringLiteral("OpenSession"), {QStringLiteral("plain"), QVariant::fromValue(QDBusVariant(QString()))},
         [this, generation, then = std::move(then)](const QDBusMessage &reply) {
        if (generation != m_generation || reply.type() == QDBusMessage::ErrorMessage) {
            then(false);
            return;
        }
        m_session = qdbus_cast<QDBusObjectPath>(reply.arguments().value(1));
        then(true);
    });
}

// Unlock never prompts by itself: it hands back a prompt, which shows the keyring's own dialog only when run.
void Passwords::unlock(const QString &path, bool quiet, std::function<void(bool)> then) {
    call(servicePath, serviceInterface, QStringLiteral("Unlock"), {QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(path)})},
         [this, quiet, then = std::move(then)](const QDBusMessage &reply) {
        if (reply.type() == QDBusMessage::ErrorMessage) {
            then(false);
            return;
        }
        const QString promptPath = qdbus_cast<QDBusObjectPath>(reply.arguments().value(1)).path();
        if (promptPath.isEmpty() || promptPath == u"/") {
            then(!qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(0)).isEmpty());
            return;
        }
        if (quiet) {
            call(promptPath, promptInterface, QStringLiteral("Dismiss"), {}, [](const QDBusMessage &) {});
            then(false);
            return;
        }
        prompt(promptPath, then);
    });
}

void Passwords::prompt(const QString &path, std::function<void(bool)> then) {
    m_prompts.insert(path, std::move(then));
    m_bus.connect(service, path, promptInterface, QStringLiteral("Completed"), this, SLOT(promptCompleted(QDBusMessage)));
    // no window to hang the keyring's dialog on (Wayland has no window id to give)
    call(path, promptInterface, QStringLiteral("Prompt"), {QString()}, [this, path](const QDBusMessage &reply) {
        if (reply.type() == QDBusMessage::ErrorMessage)
            finishPrompt(path, false);
    });
}

void Passwords::promptCompleted(const QDBusMessage &message) {
    finishPrompt(message.path(), !message.arguments().value(0).toBool());
}

void Passwords::finishPrompt(const QString &path, bool completed) {
    auto then = m_prompts.take(path);
    if (!then)
        return;
    m_bus.disconnect(service, path, promptInterface, QStringLiteral("Completed"), this, SLOT(promptCompleted(QDBusMessage)));
    then(completed);
}

bool Passwords::plainKeyring(const QString &collection) {
    static const QString prefix = QStringLiteral("/org/freedesktop/secrets/collection/");
    if (!collection.startsWith(prefix))
        return false;
    // the object path writes the file's name with _xx for each byte a path cannot hold (Default_keyring: Default_5fkeyring)
    const QByteArray id = collection.mid(prefix.size()).toLatin1();
    QByteArray name;
    for (qsizetype i = 0; i < id.size(); ++i) {
        bool hex = false;
        const int byte = i + 2 < id.size() && id[i] == '_' ? id.mid(i + 1, 2).toInt(&hex, 16) : 0;
        if (hex) {
            name += char(byte);
            i += 2;
        } else {
            name += id[i];
        }
    }
    QFile file(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/keyrings/")
               + QString::fromUtf8(name) + QStringLiteral(".keyring"));
    if (!file.open(QIODevice::ReadOnly))
        return false;
    static const QByteArray magic("GnomeKeyring\n\r\0\n", 16);
    return !file.read(magic.size()).startsWith(magic);
}

// Into the default collection, replacing the item of the same origin and user name; `then(item, failure)`.
void Passwords::store(const QString &origin, const QString &user, const QByteArray &password, std::function<void(QString, QString)> then) {
    withSession([this, origin, user, password, then = std::move(then)](bool open) {
        if (!open) {
            then(QString(), m_state == u"none" ? QStringLiteral("none") : QStringLiteral("failed"));
            return;
        }
        call(servicePath, serviceInterface, QStringLiteral("ReadAlias"), {QStringLiteral("default")},
             [this, origin, user, password, then](const QDBusMessage &alias) {
            const QString collection = alias.type() == QDBusMessage::ErrorMessage ? QString() : qdbus_cast<QDBusObjectPath>(alias.arguments().value(0)).path();
            if (collection.isEmpty() || collection == u"/") {
                then(QString(), alias.type() == QDBusMessage::ErrorMessage ? failureOf(alias) : QStringLiteral("failed"));
                return;
            }
            if (plainKeyring(collection)) {
                then(QString(), QStringLiteral("unencrypted"));
                return;
            }
            unlock(collection, false, [this, collection, origin, user, password, then](bool unlocked) {
                if (!unlocked) {
                    then(QString(), QStringLiteral("locked"));
                    return;
                }
                const QVariantMap properties{
                    {QStringLiteral("org.freedesktop.Secret.Item.Label"), hostOf(origin)},
                    {QStringLiteral("org.freedesktop.Secret.Item.Attributes"),
                     QVariant::fromValue(SecretAttributes{{QStringLiteral("xdg:schema"), schema}, {QStringLiteral("origin"), origin}, {QStringLiteral("user"), user}})},
                };
                const SecretValue secret{m_session, QByteArray(), password, QStringLiteral("text/plain")};
                call(collection, collectionInterface, QStringLiteral("CreateItem"), {properties, QVariant::fromValue(secret), true},
                     [this, then](const QDBusMessage &made) {
                    if (made.type() == QDBusMessage::ErrorMessage) {
                        then(QString(), failureOf(made));
                        return;
                    }
                    const QString item = qdbus_cast<QDBusObjectPath>(made.arguments().value(0)).path();
                    const QString promptPath = qdbus_cast<QDBusObjectPath>(made.arguments().value(1)).path();
                    if (promptPath.isEmpty() || promptPath == u"/")
                        then(item, QString());
                    else
                        prompt(promptPath, [then](bool completed) { then(QString(), completed ? QString() : QStringLiteral("locked")); });
                });
            });
        });
    });
}

void Passwords::save(const QString &origin, const QString &user, const QString &password, const QJSValue &done) {
    if (m_state != u"ready") {
        answer(done, {false, QStringLiteral("none")});
        return;
    }
    store(origin, user, password.toUtf8(), [this, done](const QString &, const QString &failure) {
        refresh();
        answer(done, {failure.isEmpty(), failure});
    });
}

// The secret of item `id`, unlocked first; `then(value, failure)`.
void Passwords::read(const QString &id, bool quiet, std::function<void(QByteArray, QString)> then) {
    withSession([this, id, quiet, then = std::move(then)](bool open) {
        if (!open) {
            then(QByteArray(), QStringLiteral("failed"));
            return;
        }
        unlock(id, quiet, [this, id, then](bool unlocked) {
            if (!unlocked) {
                then(QByteArray(), QStringLiteral("locked"));
                return;
            }
            call(id, itemInterface, QStringLiteral("GetSecret"), {QVariant::fromValue(m_session)}, [this, then](const QDBusMessage &reply) {
                if (reply.type() == QDBusMessage::ErrorMessage)
                    then(QByteArray(), failureOf(reply));
                else
                    then(qdbus_cast<SecretValue>(reply.arguments().value(0)).value, QString());
            });
        });
    });
}

void Passwords::secretMatching(const SecretAttributes &attributes, bool quiet, std::function<void(QByteArray, QString)> then) {
    if (!m_bus.isConnected()) {
        then(QByteArray(), QStringLiteral("none"));
        return;
    }
    call(servicePath, serviceInterface, QStringLiteral("SearchItems"), {QVariant::fromValue(attributes)},
         [this, quiet, then = std::move(then)](const QDBusMessage &reply) {
        if (reply.type() == QDBusMessage::ErrorMessage) {
            then(QByteArray(), failureOf(reply));
            return;
        }
        const QList<QDBusObjectPath> unlocked = qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(0));
        const QList<QDBusObjectPath> locked = qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(1));
        if (unlocked.isEmpty() && locked.isEmpty()) {
            then(QByteArray(), QStringLiteral("missing"));
            return;
        }
        read((unlocked.isEmpty() ? locked : unlocked).first().path(), quiet, then);
    });
}

void Passwords::secret(const QString &id, bool quiet, const QJSValue &done) {
    if (m_state != u"ready" || !known(id)) {
        answer(done, {QJSValue(QJSValue::UndefinedValue), m_state != u"ready" ? QStringLiteral("none") : QStringLiteral("failed")});
        return;
    }
    read(id, quiet, [done](const QByteArray &value, const QString &failure) {
        answer(done, {failure.isEmpty() ? QJSValue(QString::fromUtf8(value)) : QJSValue(QJSValue::UndefinedValue), failure});
    });
}

void Passwords::edit(const QString &id, const QString &user, const QString &password, const QJSValue &done) {
    const auto at = std::find_if(m_entries.cbegin(), m_entries.cend(), [&](const QVariant &e) { return e.toMap().value(QStringLiteral("id")) == id; });
    if (at == m_entries.cend() || m_state != u"ready") {
        answer(done, {false, m_state == u"ready" ? QStringLiteral("failed") : QStringLiteral("none")});
        return;
    }
    const QVariantMap entry = at->toMap();
    const QString origin = entry.value(QStringLiteral("origin")).toString();
    // a user name another login of the site has: saving would replace that one's item (CreateItem with replace)
    if (user != entry.value(QStringLiteral("user")).toString()
        && std::any_of(m_entries.cbegin(), m_entries.cend(), [&](const QVariant &e) {
               return e.toMap().value(QStringLiteral("origin")).toString() == origin && e.toMap().value(QStringLiteral("user")).toString() == user; })) {
        answer(done, {false, QStringLiteral("exists")});
        return;
    }
    const auto replace = [this, id, origin, user, done](const QByteArray &password) {
        store(origin, user, password, [this, id, done](const QString &item, const QString &failure) {
            // a new user name is a new item: the old one goes
            if (failure.isEmpty() && item != id)
                remove(id);
            else
                refresh();
            answer(done, {failure.isEmpty(), failure});
        });
    };
    if (!password.isEmpty()) {
        replace(password.toUtf8());
        return;
    }
    // the password kept: read it first
    read(id, false, [replace, done](const QByteArray &value, const QString &failure) {
        if (failure.isEmpty())
            replace(value);
        else
            answer(done, {false, failure});
    });
}

void Passwords::remove(const QString &id) {
    if (m_fake) {
        m_entries.erase(std::remove_if(m_entries.begin(), m_entries.end(), [&](const QVariant &e) { return e.toMap().value(QStringLiteral("id")).toString() == id; }),
                        m_entries.end());
        emit changed();
        return;
    }
    unlock(id, false, [this, id](bool unlocked) {
        if (!unlocked) {
            refresh();
            return;
        }
        call(id, itemInterface, QStringLiteral("Delete"), {}, [this](const QDBusMessage &reply) {
            const QString promptPath = reply.type() == QDBusMessage::ErrorMessage ? QString() : qdbus_cast<QDBusObjectPath>(reply.arguments().value(0)).path();
            if (!promptPath.isEmpty() && promptPath != u"/")
                prompt(promptPath, [this](bool) { refresh(); });
            else
                refresh();
        });
    });
}

void Passwords::removeLater(const QString &id) {
    if (!known(id))
        return;
    m_removing.insert(id, undoSeconds);
    if (!m_tick.isActive())
        m_tick.start();
    emit removingChanged();
}

void Passwords::keep(const QString &id) {
    if (m_removing.remove(id) == 0)
        return;
    if (m_removing.isEmpty())
        m_tick.stop();
    emit removingChanged();
}

void Passwords::importLogins(QList<Login> logins, std::function<void(int, int, int, QString)> then, std::function<void(int)> step) {
    if (m_state != u"ready" || !m_listed) {
        then(0, 0, int(logins.size()), m_state == u"none" || m_state.isEmpty() ? QStringLiteral("none") : QStringLiteral("failed"));
        return;
    }
    QSet<QString> have;
    for (const QVariant &e : std::as_const(m_entries))
        have.insert(e.toMap().value(QStringLiteral("origin")).toString() + u'\n' + e.toMap().value(QStringLiteral("user")).toString());
    auto run = std::make_shared<ImportRun>();
    run->then = std::move(then);
    run->step = std::move(step);
    for (Login &l : logins) {
        const QString key = l.origin + u'\n' + l.user;
        if (have.contains(key)) {
            ++run->kept;
            continue;
        }
        have.insert(key);
        run->left.append(std::move(l));
    }
    importNext(run);
}

// one at a time, as the keyring may ask to unlock at the first
void Passwords::importNext(std::shared_ptr<ImportRun> run) {
    if (run->left.isEmpty()) {
        refresh();
        run->then(run->added, run->kept, 0, QString());
        return;
    }
    const Login l = run->left.takeFirst();
    store(l.origin, l.user, l.password, [this, run](const QString &, const QString &failure) {
        if (!failure.isEmpty()) {
            // this one and the rest
            const int left = int(run->left.size()) + 1;
            run->left.clear();
            refresh();
            run->then(run->added, run->kept, left, failure);
            return;
        }
        ++run->added;
        if (run->step)
            run->step(run->added + run->kept);
        importNext(run);
    });
}
