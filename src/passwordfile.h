#pragma once

#include <QObject>
#include <QVariantMap>
#include <qqmlintegration.h>

#include "passwords.h"

// A password manager's export (book4-edge/thyris-migration-plan.md): the CSV file Google Password Manager, Apple
// Passwords, Bitwarden, 1Password, Proton Pass, KeePassXC, LastPass, Dashlane or Firefox saves, its columns recognised
// by their header. In C++ only, as Zen's import is: read() keeps the logins here and tells QML how many there are and
// what it left out, never a password; bring() hands them to the keyring (Passwords::importLogins: a site and user name
// the keyring has already are kept as they are). The logins are wiped from memory once brought or forgotten.
class PasswordFile : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // "" at rest, "read" (a file's logins held, not brought yet), "saving" (going into the keyring)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
public:
    explicit PasswordFile(QObject *parent = nullptr);
    ~PasswordFile() override;

    QString state() const { return m_state; }

    // The file at `path`: { service ("Bitwarden", or "" when the header names none), logins, skipped: [{ what, why }],
    // failure ("" or why it is not a password file) }. Holds its logins for bring().
    Q_INVOKABLE QVariantMap read(const QString &path);
    // The logins read into the keyring; saved() says how it went. False with nothing read or while saving.
    Q_INVOKABLE bool bring();
    // Deletes the file read last (its passwords are in plain text); false when it could not.
    Q_INVOKABLE bool removeFile();
    // Drops the logins held, unbrought.
    Q_INVOKABLE void forget();

    // the parsing alone, for read() and the checks: one login per row and web origin, the rows it skipped by reason
    struct Parsed {
        QString service, failure;
        QList<Passwords::Login> logins;
        QMap<QString, int> skipped;     // reason -> rows
    };
    static Parsed parse(const QByteArray &text);
    // an address as the keyring files logins (scheme://host[:port], as Logins.js sends origin), "" for none; `app` is set
    // for an app's login (android://, iosapp://), which has no web address. ChromeImport files its logins the same way.
    static QString originOf(QString address, bool *app);

signals:
    void stateChanged();
    // { added, kept (the keyring had that site and user name), left (a failure left out), failure ("" or Passwords') }
    void saved(const QVariantMap &result);
    // while saving: how many of the logins have gone in
    void progress(int done, int total);

private:
    void setState(const QString &state);
    void wipe();

    QString m_state;
    QString m_path;
    QList<Passwords::Login> m_logins;
};
