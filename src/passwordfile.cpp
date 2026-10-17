#include "passwordfile.h"

#include <QFile>
#include <QPointer>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QSet>
#include <QUrl>
#include <memory>

using namespace Qt::StringLiterals;

namespace {
// RFC 4180 records: a field in double quotes may hold the delimiter, line breaks and "" for a quote; \r\n or \n ends
// a record. A UTF-8 byte order mark first is dropped.
QList<QStringList> records(const QString &text, QChar delimiter) {
    QList<QStringList> out;
    QStringList record;
    QString field;
    bool quoted = false, any = false;
    const qsizetype n = text.size();
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = text.at(i);
        if (quoted) {
            if (c == u'"') {
                if (i + 1 < n && text.at(i + 1) == u'"') {
                    field += u'"';
                    ++i;
                } else {
                    quoted = false;
                }
            } else {
                field += c;
            }
            continue;
        }
        if (c == u'"' && field.isEmpty()) {
            quoted = true;
            any = true;
        } else if (c == delimiter) {
            record.append(field);
            field.clear();
            any = true;
        } else if (c == u'\n' || c == u'\r') {
            if (c == u'\r' && i + 1 < n && text.at(i + 1) == u'\n')
                ++i;
            if (any || !field.isEmpty()) {
                record.append(field);
                out.append(record);
            }
            record.clear();
            field.clear();
            any = false;
        } else {
            field += c;
            any = true;
        }
    }
    if (any || !field.isEmpty()) {
        record.append(field);
        out.append(record);
    }
    return out;
}

// the header's delimiter: the one of , ; and tab used most outside quotes on the first line
QChar delimiterOf(const QString &text) {
    int comma = 0, semicolon = 0, tab = 0;
    bool quoted = false;
    for (const QChar c : text) {
        if (c == u'"')
            quoted = !quoted;
        else if (!quoted && (c == u'\n' || c == u'\r'))
            break;
        else if (!quoted && c == u',')
            ++comma;
        else if (!quoted && c == u';')
            ++semicolon;
        else if (!quoted && c == u'\t')
            ++tab;
    }
    return semicolon > comma && semicolon >= tab ? u';' : tab > comma ? u'\t' : u',';
}

// which service saved a file with these (lower-cased) columns, "" when they name none
QString serviceOf(const QSet<QString> &h) {
    if (h.contains(u"login_uri"_s) && h.contains(u"login_password"_s))
        return QStringLiteral("Bitwarden");
    if (h.contains(u"httprealm"_s) || h.contains(u"formactionorigin"_s))
        return QStringLiteral("Firefox");
    if (h.contains(u"vault"_s) && (h.contains(u"createtime"_s) || h.contains(u"modifytime"_s)))
        return QStringLiteral("Proton Pass");
    if (h.contains(u"grouping"_s) && h.contains(u"extra"_s))
        return QStringLiteral("LastPass");
    if (h.contains(u"username2"_s) || (h.contains(u"category"_s) && h.contains(u"otpsecret"_s)))
        return QStringLiteral("Dashlane");
    if (h.contains(u"otpauth"_s) && h.contains(u"archived"_s))
        return QStringLiteral("1Password");
    if (h.contains(u"otpauth"_s) && h.contains(u"title"_s))
        return QStringLiteral("Apple Passwords");
    if (h.contains(u"group"_s) && h.contains(u"title"_s))
        return QStringLiteral("KeePassXC");
    if (h.contains(u"name"_s) && h.contains(u"url"_s) && h.contains(u"username"_s) && h.contains(u"password"_s))
        return QStringLiteral("Google Password Manager");
    return {};
}

}

QString PasswordFile::originOf(QString address, bool *app) {
    address = address.trimmed();
    if (address.isEmpty())
        return {};
    if (address.startsWith(u"android://"_s, Qt::CaseInsensitive) || address.startsWith(u"iosapp://"_s, Qt::CaseInsensitive)) {
        *app = true;
        return {};
    }
    if (!address.contains(u"://"_s))
        address.prepend(u"https://"_s);
    const QUrl url(address);
    const QString scheme = url.scheme().toLower();
    if (!url.isValid() || url.host().isEmpty() || (scheme != u"https" && scheme != u"http"))
        return {};
    const int port = url.port();
    const bool usual = port == -1 || (scheme == u"https" && port == 443) || (scheme == u"http" && port == 80);
    return scheme + u"://"_s + url.host().toLower() + (usual ? QString() : u':' + QString::number(port));
}

namespace {
// the first of `names` the header has, -1 for none
int column(const QStringList &header, std::initializer_list<const char16_t *> names) {
    for (const char16_t *name : names) {
        const int at = int(header.indexOf(QString::fromUtf16(name)));
        if (at >= 0)
            return at;
    }
    return -1;
}
}

PasswordFile::PasswordFile(QObject *parent) : QObject(parent) {}

PasswordFile::~PasswordFile() { wipe(); }

void PasswordFile::setState(const QString &state) {
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

// what this process holds of the passwords, overwritten before it goes (the file's own bytes are wiped in read)
void PasswordFile::wipe() {
    for (Passwords::Login &l : m_logins)
        l.password.fill('\0');
    m_logins.clear();
}

PasswordFile::Parsed PasswordFile::parse(const QByteArray &bytes) {
    Parsed out;
    QString text = QString::fromUtf8(bytes);
    if (text.startsWith(QChar(0xfeff)))
        text.remove(0, 1);
    const QList<QStringList> rows = records(text, delimiterOf(text));
    text.fill(u'\0');
    if (rows.isEmpty()) {
        out.failure = QStringLiteral("The file is empty.");
        return out;
    }
    QStringList header;
    for (const QString &h : rows.first())
        header.append(h.trimmed().toLower());
    out.service = serviceOf(QSet<QString>(header.begin(), header.end()));
    const int password = column(header, {u"password", u"login_password", u"pass"});
    const int address = column(header, {u"url", u"login_uri", u"website", u"web site", u"login url", u"uri", u"address", u"hostname"});
    const int type = column(header, {u"type"});
    // a user name where the file has one, else its e-mail (Proton Pass keeps both, many logins only the e-mail)
    const int user = column(header, {u"username", u"login_username", u"user name", u"user", u"login"});
    const int email = column(header, {u"email", u"e-mail"});
    if (password < 0 || address < 0) {
        out.failure = password < 0 ? QStringLiteral("It has no password column, so it isn't a password export.")
                                   : QStringLiteral("It has no column of web addresses, so Thyris can't tell which site each password is for.");
        return out;
    }
    QSet<QString> seen;
    for (qsizetype r = 1; r < rows.size(); ++r) {
        const QStringList &f = rows.at(r);
        const auto at = [&f](int i) { return i >= 0 && i < f.size() ? f.at(i) : QString(); };
        bool blank = true;
        for (const QString &v : f)
            blank = blank && v.trimmed().isEmpty();
        if (blank)
            continue;
        const QString kind = at(type).trimmed().toLower();
        if (!kind.isEmpty() && kind != u"login") {
            ++out.skipped[QStringLiteral("not a login (a note, a card or an identity)")];
            continue;
        }
        if (at(password).isEmpty()) {
            ++out.skipped[QStringLiteral("no password")];
            continue;
        }
        const QString name = at(user).trimmed().isEmpty() ? at(email).trimmed() : at(user).trimmed();
        // Bitwarden may list several addresses for one login, a comma or a line apart
        bool app = false, anyOrigin = false, addedHere = false;
        for (const QString &part : at(address).split(QRegularExpression(QStringLiteral("[,\\n]")), Qt::SkipEmptyParts)) {
            const QString origin = originOf(part, &app);
            if (origin.isEmpty())
                continue;
            anyOrigin = true;
            if (seen.contains(origin + u'\n' + name))
                continue;
            seen.insert(origin + u'\n' + name);
            out.logins.append({origin, name, at(password).toUtf8()});
            addedHere = true;
        }
        if (!anyOrigin)
            ++out.skipped[app ? QStringLiteral("an app's, with no web address") : QStringLiteral("no web address")];
        else if (!addedHere)
            ++out.skipped[QStringLiteral("the same site and user name as another entry")];
    }
    if (out.logins.isEmpty() && out.skipped.isEmpty())
        out.failure = QStringLiteral("It holds no logins.");
    return out;
}

QVariantMap PasswordFile::read(const QString &path) {
    wipe();
    m_path.clear();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        setState(QString());
        return {{QStringLiteral("failure"), QStringLiteral("Thyris can't open that file.")}};
    }
    // a password export is small; anything near this is not one
    if (file.size() > 64 << 20) {
        setState(QString());
        return {{QStringLiteral("failure"), QStringLiteral("It is too large to be a password export.")}};
    }
    QByteArray bytes = file.readAll();
    Parsed p = parse(bytes);
    bytes.fill('\0');
    QVariantList skipped;
    for (auto it = p.skipped.cbegin(); it != p.skipped.cend(); ++it)
        skipped.append(QVariantMap{{QStringLiteral("what"), it.value() == 1 ? QStringLiteral("1 entry") : QString::number(it.value()) + u" entries"_s},
                                   {QStringLiteral("why"), it.key()}});
    const QVariantMap out{{QStringLiteral("service"), p.service}, {QStringLiteral("logins"), int(p.logins.size())},
                          {QStringLiteral("skipped"), skipped}, {QStringLiteral("failure"), p.failure}};
    if (!p.failure.isEmpty()) {
        for (Passwords::Login &l : p.logins)
            l.password.fill('\0');
        setState(QString());
        return out;
    }
    m_logins = std::move(p.logins);
    m_path = path;
    setState(QStringLiteral("read"));
    return out;
}

bool PasswordFile::bring() {
    auto *keyring = qmlEngine(this) ? qmlEngine(this)->singletonInstance<Passwords *>("Browser", "Passwords") : nullptr;
    if (!keyring || m_state != u"read" || m_logins.isEmpty())
        return false;
    setState(QStringLiteral("saving"));
    const int total = int(m_logins.size());
    QPointer<PasswordFile> self(this);
    // the keyring copies what it saves; the list given goes with the run, its passwords overwritten as it ends
    auto given = std::make_shared<QList<Passwords::Login>>(m_logins);
    wipe();
    keyring->importLogins(*given, [self, given](int added, int kept, int left, const QString &failure) {
        for (Passwords::Login &l : *given)
            l.password.fill('\0');
        if (!self)
            return;
        self->setState(QString());
        emit self->saved({{QStringLiteral("added"), added}, {QStringLiteral("kept"), kept}, {QStringLiteral("left"), left},
                          {QStringLiteral("failure"), failure}});
    }, [self, total](int done) { if (self) emit self->progress(done, total); });
    return true;
}

bool PasswordFile::removeFile() {
    if (m_path.isEmpty())
        return false;
    const bool removed = QFile::remove(m_path);
    if (removed)
        m_path.clear();
    return removed;
}

void PasswordFile::forget() {
    wipe();
    setState(QString());
}
