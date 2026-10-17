#include "chromeimport.h"
#include "passwordfile.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QSet>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QUrl>
#include <algorithm>
#include <memory>
#include <openssl/evp.h>
#include <sqlite3.h>
#include "sitedata.h"
#ifdef BROWSER_CEF
#include "cef/cookies.h"
#endif
#include <QNetworkCookie>

using namespace Qt::StringLiterals;

namespace {
// the family, as each keeps its profiles on Linux (native, then Flatpak), and the `application` its keyring secret is
// filed under (a fork that names none of its own shares Chromium's)
struct Kind {
    const char *name, *icon;
    QStringList dirs, apps;
};
const QList<Kind> &kinds() {
    static const QList<Kind> list = {
        {"Google Chrome", "google-chrome", {u".config/google-chrome"_s, u".var/app/com.google.Chrome/config/google-chrome"_s}, {u"chrome"_s}},
        {"Chromium", "chromium", {u".config/chromium"_s, u".var/app/org.chromium.Chromium/config/chromium"_s}, {u"chromium"_s}},
        {"Brave", "brave-browser", {u".config/BraveSoftware/Brave-Browser"_s, u".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"_s}, {u"brave"_s}},
        {"Microsoft Edge", "microsoft-edge", {u".config/microsoft-edge"_s, u".var/app/com.microsoft.Edge/config/microsoft-edge"_s}, {u"microsoft-edge"_s, u"chromium"_s}},
        {"Vivaldi", "vivaldi", {u".config/vivaldi"_s, u".var/app/com.vivaldi.Vivaldi/config/vivaldi"_s}, {u"vivaldi"_s, u"chrome"_s}},
        {"Opera", "opera", {u".config/opera"_s}, {u"opera"_s, u"chromium"_s}},
        {"Thorium", "thorium-browser", {u".config/thorium"_s}, {u"thorium"_s, u"chromium"_s}},
    };
    return list;
}

// the app's icon from the icon theme, as a file: URL, "" when the theme has none
QString iconOf(const char *name) {
    for (const char *size : {"256x256", "128x128", "96x96", "64x64", "48x48"}) {
        const QString path = u"/usr/share/icons/hicolor/"_s + QLatin1String(size) + u"/apps/"_s + QLatin1String(name) + u".png"_s;
        if (QFileInfo::exists(path))
            return QUrl::fromLocalFile(path).toString();
    }
    for (const QString &path : {u"/usr/share/icons/hicolor/scalable/apps/"_s + QLatin1String(name) + u".svg"_s,
                                u"/usr/share/pixmaps/"_s + QLatin1String(name) + u".png"_s})
        if (QFileInfo::exists(path))
            return QUrl::fromLocalFile(path).toString();
    return {};
}

// a copy of one of the profile's SQLite files (with its write-ahead log) in `into`, opened read-only; null for none
sqlite3 *openCopy(const QString &from, const QString &into) {
    if (!QFileInfo(from).isFile())
        return nullptr;
    const QString copy = into + u'/' + QFileInfo(from).fileName();
    for (const char *suffix : {"", "-wal"}) {
        QFile::remove(copy + QLatin1String(suffix));
        if (QFileInfo::exists(from + QLatin1String(suffix)) && !QFile::copy(from + QLatin1String(suffix), copy + QLatin1String(suffix)) && !*suffix)
            return nullptr;
    }
    sqlite3 *db = nullptr;
    if (sqlite3_open_v2(copy.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
        sqlite3_close(db);
        return nullptr;
    }
    return db;
}
void closeCopy(sqlite3 *db, const QString &from, const QString &into) {
    sqlite3_close(db);
    const QString copy = into + u'/' + QFileInfo(from).fileName();
    for (const char *suffix : {"", "-wal", "-shm", "-journal"})
        QFile::remove(copy + QLatin1String(suffix));
}
// each row of `sql`, its columns as sqlite3 gives them
template <typename Row>
void rows(sqlite3 *db, const char *sql, Row row) {
    sqlite3_stmt *st = nullptr;
    if (!db || sqlite3_prepare_v2(db, sql, -1, &st, nullptr) != SQLITE_OK)
        return;
    while (sqlite3_step(st) == SQLITE_ROW)
        row(st);
    sqlite3_finalize(st);
}
QString text(sqlite3_stmt *st, int i) { return QString::fromUtf8(reinterpret_cast<const char *>(sqlite3_column_text(st, i))); }
QByteArray blob(sqlite3_stmt *st, int i) {
    return QByteArray(static_cast<const char *>(sqlite3_column_blob(st, i)), sqlite3_column_bytes(st, i));
}
// Chromium's times: microseconds since 1601-01-01; ms since 1970 here, 0 for none
qint64 epochMs(qint64 webkit) { return webkit > 0 ? webkit / 1000 - 11644473600000LL : 0; }

// the bookmarks of Bookmarks: [{ url, title, folder: [the root's name, the folders under it], added }]
void bookmarksIn(const QJsonObject &node, QStringList folder, QVariantList &out) {
    if (node.value(u"type"_s).toString() == u"url") {
        out.append(QVariantMap{{u"url"_s, node.value(u"url"_s).toString()}, {u"title"_s, node.value(u"name"_s).toString()},
                               {u"folder"_s, folder}, {u"added"_s, epochMs(node.value(u"date_added"_s).toString().toLongLong())}});
        return;
    }
    if (!folder.isEmpty() || !node.value(u"name"_s).toString().isEmpty())
        folder.append(node.value(u"name"_s).toString());
    for (const QJsonValue &child : node.value(u"children"_s).toArray())
        bookmarksIn(child.toObject(), folder, out);
}
QVariantList bookmarksOf(const QString &file) {
    QFile f(file);
    QVariantList out;
    if (!f.open(QIODevice::ReadOnly))
        return out;
    const QJsonObject roots = QJsonDocument::fromJson(f.readAll()).object().value(u"roots"_s).toObject();
    const QList<std::pair<QString, QString>> named = {{u"bookmark_bar"_s, u"Bookmarks bar"_s}, {u"other"_s, u"Other bookmarks"_s},
                                                      {u"synced"_s, u"Mobile bookmarks"_s}};
    for (const auto &[key, name] : named) {
        const QJsonObject root = roots.value(key).toObject();
        for (const QJsonValue &child : root.value(u"children"_s).toArray())
            bookmarksIn(child.toObject(), {name}, out);
    }
    return out;
}

// The open tabs of a profile's session (Sessions/Session_<time>, the newest; "Current Session" before Chrome 86), as
// Chromium writes it: "SNSS", a version (1, or 3 with markers), then commands, each a 16-bit size, an id and its payload.
// The commands are replayed as Chromium restores a session: which window a tab is in and where, its pages and the one
// shown, closed tabs and windows gone, its tab group's title. Normal windows only (no popups or apps), in the order
// Chrome first named them, tabs by their place, each its page shown: [{ url, title, group }], http(s) pages only. Nothing for a session that is not there or does not read.
namespace snss {
qint32 i32(const QByteArray &b, qsizetype at) {
    if (at < 0 || at + 4 > b.size())
        return 0;
    return qint32(quint8(b[at]) | quint8(b[at + 1]) << 8 | quint8(b[at + 2]) << 16 | quint32(quint8(b[at + 3])) << 24);
}
quint64 u64(const QByteArray &b, qsizetype at) {
    return quint64(quint32(i32(b, at))) | quint64(quint32(i32(b, at + 4))) << 32;
}
// a Pickle's string (a length, then the bytes, padded to 4) from `at`, which moves past it; false past the end
bool string8(const QByteArray &b, qsizetype &at, QString &out) {
    const qint32 n = i32(b, at);
    if (n < 0 || at + 4 + n > b.size())
        return false;
    out = QString::fromUtf8(b.mid(at + 4, n));
    at += 4 + ((n + 3) & ~3);
    return true;
}
bool string16(const QByteArray &b, qsizetype &at, QString &out) {
    const qint32 n = i32(b, at);
    if (n < 0 || at + 4 + 2 * qsizetype(n) > b.size())
        return false;
    out = QString(reinterpret_cast<const QChar *>(b.constData() + at + 4), n);
    at += 4 + ((2 * n + 3) & ~3);
    return true;
}
}
QVariantList tabsOf(const QString &profile) {
    QString file;
    const QFileInfoList sessions = QDir(profile + u"/Sessions"_s).entryInfoList({u"Session_*"_s}, QDir::Files, QDir::Name);
    if (!sessions.isEmpty())
        file = sessions.last().filePath();
    else if (QFileInfo::exists(profile + u"/Current Session"_s))
        file = profile + u"/Current Session"_s;
    QFile f(file);
    if (file.isEmpty() || !f.open(QIODevice::ReadOnly))
        return {};
    const QByteArray d = f.readAll();
    const qint32 version = snss::i32(d, 4);
    if (!d.startsWith("SNSS") || (version != 1 && version != 3))
        return {};
    struct Tab { qint32 window = -1, index = 0, current = -1; QByteArray group; QMap<qint32, std::pair<QString, QString>> pages; };
    QHash<qint32, Tab> tabs;
    QHash<qint32, qint32> types;        // window -> its type, 0 normal
    QList<qint32> windows;              // in the order first named
    QHash<QByteArray, QString> groups;  // group token -> title
    const auto window = [&](qint32 id) { if (!windows.contains(id)) windows.append(id); };
    for (qsizetype at = 8; at + 3 <= d.size();) {
        const qsizetype size = quint8(d[at]) | quint8(d[at + 1]) << 8;
        if (size == 0 || at + 2 + size > d.size())
            break;
        const quint8 id = quint8(d[at + 2]);
        const QByteArray p = d.mid(at + 3, size - 1);
        at += 2 + size;
        switch (id) {
        case 0:     // tab -> window
            tabs[snss::i32(p, 4)].window = snss::i32(p, 0);
            window(snss::i32(p, 0));
            break;
        case 2:     // tab's place in its window
            tabs[snss::i32(p, 0)].index = snss::i32(p, 4);
            break;
        case 5: {   // its pages pruned from the back: those from `index` on go
            Tab &t = tabs[snss::i32(p, 0)];
            for (auto it = t.pages.begin(); it != t.pages.end();)
                it = it.key() >= snss::i32(p, 4) ? t.pages.erase(it) : std::next(it);
            break;
        }
        case 6: {   // a page of a tab: a Pickle, its size, the tab, the page's index, its address, its title
            qsizetype q = 12;
            QString url, title;
            if (snss::string8(p, q, url) && snss::string16(p, q, title))
                tabs[snss::i32(p, 4)].pages[snss::i32(p, 8)] = {url, title};
            break;
        }
        case 7:     // the page a tab shows
            tabs[snss::i32(p, 0)].current = snss::i32(p, 4);
            break;
        case 9:     // a window's type
            types[snss::i32(p, 0)] = snss::i32(p, 4);
            window(snss::i32(p, 0));
            break;
        case 11:    // pruned from the front: the first `count` go, the others move down
        case 24: {  // pruned: `count` from `index` go
            Tab &t = tabs[snss::i32(p, 0)];
            const qint32 from = id == 11 ? 0 : snss::i32(p, 4), count = id == 11 ? snss::i32(p, 4) : snss::i32(p, 8);
            QMap<qint32, std::pair<QString, QString>> kept;
            for (auto it = t.pages.cbegin(); it != t.pages.cend(); ++it)
                if (it.key() < from)
                    kept.insert(it.key(), it.value());
                else if (it.key() >= from + count)
                    kept.insert(it.key() - count, it.value());
            t.pages = kept;
            if (t.current >= from + count)
                t.current -= count;
            break;
        }
        case 16:    // a tab closed
            tabs.remove(snss::i32(p, 0));
            break;
        case 17:    // a window closed, its tabs with it
            types[snss::i32(p, 0)] = -1;
            break;
        case 25:    // a tab's group: its token (two 64-bit halves), and whether it has one
            tabs[snss::i32(p, 0)].group = p.size() > 24 && p[24] != 0 ? p.mid(8, 16) : QByteArray();
            break;
        case 27: {  // a group's title: a Pickle, its size, the token, the title
            qsizetype q = 20;
            QString title;
            if (snss::string16(p, q, title))
                groups[p.mid(4, 16)] = title;
            break;
        }
        default:
            break;
        }
    }
    QVariantList out;
    for (const qint32 w : windows) {
        if (types.value(w, 0) != 0)
            continue;
        QList<const Tab *> in;
        for (const Tab &t : tabs)
            if (t.window == w && !t.pages.isEmpty())
                in.append(&t);
        std::stable_sort(in.begin(), in.end(), [](const Tab *a, const Tab *b) { return a->index < b->index; });
        for (const Tab *t : in) {
            const auto page = t->pages.value(t->current, t->pages.last());
            if (!page.first.startsWith(u"https://"_s) && !page.first.startsWith(u"http://"_s))
                continue;
            out.append(QVariantMap{{u"url"_s, page.first}, {u"title"_s, page.second}, {u"group"_s, groups.value(t->group)}});
        }
    }
    return out;
}

// a host's registrable domain, near enough for counting sites: its last two labels, three under a two-letter country
// code with a short second level (co.uk, com.au); an address or a single label as it is (as Zen's count does)
QString siteOf(QString host) {
    if (host.startsWith(u'.'))
        host.remove(0, 1);
    const QStringList labels = host.split(u'.');
    const qsizetype n = labels.size();
    if (n <= 2 || host.contains(u':') || labels.last().isEmpty() || labels.last().at(0).isDigit())
        return host;
    const bool second = n >= 3 && labels.last().size() == 2 && labels.at(n - 2).size() <= 3;
    return labels.mid(n - (second ? 3 : 2)).join(u'.');
}

// the profile's cookies as they would come: unexpired, in no partition (CHIPS: kept per top-level site, which the store
// cannot be told), `each(host, name, value, sealed, path, expires ms or 0, secure, httpOnly, sameSite)`
template <typename Each>
void cookiesIn(sqlite3 *db, Each each) {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const auto row = [&](sqlite3_stmt *st, bool partitioned) {
        if (partitioned && !text(st, 10).isEmpty())
            return;
        const qint64 expires = sqlite3_column_int(st, 9) ? epochMs(sqlite3_column_int64(st, 5)) : 0;
        if (expires > 0 && expires < now)
            return;
        // Chromium's samesite: -1 unspecified, 0 none, 1 lax, 2 strict; CEF's: 0 unspecified, 1 none, 2 lax, 3 strict
        each(text(st, 0), text(st, 1), blob(st, 2), blob(st, 3), text(st, 4), expires, sqlite3_column_int(st, 6) != 0,
             sqlite3_column_int(st, 7) != 0, std::clamp(sqlite3_column_int(st, 8) + 1, 0, 3));
    };
    bool any = false;
    rows(db, "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, is_persistent, top_frame_site_key FROM cookies",
         [&](sqlite3_stmt *st) { any = true; row(st, true); });
    if (!any)       // an older profile: no partitions yet
        rows(db, "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, is_persistent FROM cookies",
             [&](sqlite3_stmt *st) { row(st, false); });
}

QByteArray keyOf(const QByteArray &secret) {
    unsigned char key[16];
    PKCS5_PBKDF2_HMAC_SHA1(secret.constData(), int(secret.size()), reinterpret_cast<const unsigned char *>("saltysalt"), 9, 1, 16, key);
    return QByteArray(reinterpret_cast<const char *>(key), 16);
}
}

// What start() read off the thread, for the passwords that follow on it: the logins still encrypted.
struct ChromeImport::Read {
    QString browser;
    QStringList apps;
    QVariantList bookmarks, history, tabs;
    struct Login { QString origin, user; QByteArray sealed; };
    QList<Login> logins;
    bool passwords = true;
    // cookies: a plain value, or sealed (v10/v11) for the key
    struct Cookie { QString host, name, path; QByteArray value, sealed; qint64 expires; bool secure, httpOnly; int sameSite; };
    QList<Cookie> cookies;
    bool sites = true;
};

ChromeImport::ChromeImport(QObject *parent) : QObject(parent), m_home(QDir::homePath()) {}

bool ChromeImport::googleSignIn(const QString &host, const QString &name) {
    return siteOf(host) == u"google.com" && (name == u"SID" || name == u"__Secure-1PSID");
}

void ChromeImport::setState(const QString &state) {
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

QString ChromeImport::themeIcon(const QString &name) { return iconOf(name.toLatin1().constData()); }

void ChromeImport::useHome(const QString &home) {
    m_home = home;
    noUserProfile = false;
}

QByteArray ChromeImport::encrypt(const QByteArray &plain, const QByteArray &secret, const char *tag) {
    const QByteArray key = keyOf(qstrcmp(tag, "v10") == 0 ? QByteArray("peanuts") : secret), iv(16, ' ');
    QByteArray out(plain.size() + 32, Qt::Uninitialized);
    int n = 0, m = 0;
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    EVP_EncryptInit_ex(ctx, EVP_aes_128_cbc(), nullptr, reinterpret_cast<const unsigned char *>(key.constData()), reinterpret_cast<const unsigned char *>(iv.constData()));
    EVP_EncryptUpdate(ctx, reinterpret_cast<unsigned char *>(out.data()), &n, reinterpret_cast<const unsigned char *>(plain.constData()), int(plain.size()));
    EVP_EncryptFinal_ex(ctx, reinterpret_cast<unsigned char *>(out.data()) + n, &m);
    EVP_CIPHER_CTX_free(ctx);
    out.resize(n + m);
    return QByteArray(tag) + out;
}

QByteArray ChromeImport::decrypt(const QByteArray &data, const QByteArray &secret) {
    const bool v10 = data.startsWith("v10");
    if (!(v10 || data.startsWith("v11")) || data.size() <= 3 || (!v10 && secret.isEmpty()))
        return {};
    const QByteArray key = keyOf(v10 ? QByteArray("peanuts") : secret), iv(16, ' '), sealed = data.mid(3);
    QByteArray out(sealed.size() + 16, Qt::Uninitialized);
    int n = 0, m = 0;
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit_ex(ctx, EVP_aes_128_cbc(), nullptr, reinterpret_cast<const unsigned char *>(key.constData()), reinterpret_cast<const unsigned char *>(iv.constData()));
    const bool ok = EVP_DecryptUpdate(ctx, reinterpret_cast<unsigned char *>(out.data()), &n, reinterpret_cast<const unsigned char *>(sealed.constData()), int(sealed.size())) == 1
                    && EVP_DecryptFinal_ex(ctx, reinterpret_cast<unsigned char *>(out.data()) + n, &m) == 1;
    EVP_CIPHER_CTX_free(ctx);
    if (!ok) {
        out.fill('\0');
        return {};
    }
    out.resize(n + m);
    return out.isNull() ? QByteArray("") : out;
}

void ChromeImport::scan() {
    if (noUserProfile)
        return;
    const QString home = m_home;
    const int serial = ++m_scans;
    setState(m_state.isEmpty() ? u"scanning"_s : m_state);
    QPointer<ChromeImport> self(this);
    QThreadPool::globalInstance()->start([self, home, serial] {
        QVariantList found;
        QTemporaryDir copies;
        for (const Kind &kind : kinds()) {
            for (const QString &dir : kind.dirs) {
                const QString root = home + u'/' + dir;
                QFile state(root + u"/Local State"_s);
                if (!state.open(QIODevice::ReadOnly))
                    continue;
                const QJsonObject cache = QJsonDocument::fromJson(state.readAll()).object().value(u"profile"_s).toObject().value(u"info_cache"_s).toObject();
                for (auto it = cache.begin(); it != cache.end(); ++it) {
                    const QString profile = root + u'/' + it.key();
                    if (!QFileInfo(profile).isDir())
                        continue;
                    const QJsonObject info = it.value().toObject();
                    QSet<QString> logins;
                    for (const QString &file : {u"Login Data"_s, u"Login Data For Account"_s}) {
                        sqlite3 *db = openCopy(profile + u'/' + file, copies.path());
                        rows(db, "SELECT origin_url, username_value FROM logins WHERE blacklisted_by_user = 0 AND length(password_value) > 0",
                             [&](sqlite3_stmt *st) {
                            // counted as start() will bring them: web origins only
                            bool app = false;
                            const QString origin = PasswordFile::originOf(text(st, 0), &app);
                            if (!origin.isEmpty())
                                logins.insert(origin + u'\n' + text(st, 1));
                        });
                        closeCopy(db, profile + u'/' + file, copies.path());
                    }
                    int history = 0;
                    sqlite3 *db = openCopy(profile + u"/History"_s, copies.path());
                    rows(db, "SELECT count(*) FROM urls WHERE hidden = 0 AND (url LIKE 'http://%' OR url LIKE 'https://%')",
                         [&](sqlite3_stmt *st) { history = sqlite3_column_int(st, 0); });
                    closeCopy(db, profile + u"/History"_s, copies.path());
                    QSet<QString> sites;
                    db = openCopy(profile + u"/Cookies"_s, copies.path());
                    cookiesIn(db, [&](const QString &host, auto &&...) { sites.insert(siteOf(host)); });
                    closeCopy(db, profile + u"/Cookies"_s, copies.path());
                    found.append(QVariantMap{
                        {u"browser"_s, QString::fromLatin1(kind.name)}, {u"icon"_s, iconOf(kind.icon)}, {u"root"_s, root}, {u"dir"_s, it.key()},
                        {u"name"_s, info.value(u"name"_s).toString()}, {u"email"_s, info.value(u"user_name"_s).toString()},
                        {u"active"_s, info.value(u"active_time"_s).toDouble()},
                        {u"counts"_s, QVariantMap{{u"passwords"_s, int(logins.size())}, {u"bookmarks"_s, int(bookmarksOf(profile + u"/Bookmarks"_s).size())},
                                                  {u"history"_s, history}, {u"sites"_s, int(sites.size())}, {u"tabs"_s, int(tabsOf(profile).size())}}}});
                }
                break;      // the native one before Flatpak's: one install of a browser
            }
        }
        std::stable_sort(found.begin(), found.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(u"active"_s).toDouble() > b.toMap().value(u"active"_s).toDouble(); });
        QMetaObject::invokeMethod(self, [self, found, serial] {
            if (!self || serial != self->m_scans)
                return;
            self->m_found = found;
            emit self->foundChanged();
            if (self->m_state == u"scanning")
                self->setState(QString());
        }, Qt::QueuedConnection);
    });
}

bool ChromeImport::start(int index, const QVariantMap &want, QObject *target) {
    if (index < 0 || index >= m_found.size() || (!m_state.isEmpty() && m_state != u"scanning"))
        return false;
    const QVariantMap p = m_found.at(index).toMap();
    const QString profile = p.value(u"root"_s).toString() + u'/' + p.value(u"dir"_s).toString(), browser = p.value(u"browser"_s).toString();
    QStringList apps;
    for (const Kind &kind : kinds())
        if (QString::fromLatin1(kind.name) == browser)
            apps = kind.apps;
    const bool bookmarks = want.value(u"bookmarks"_s, true).toBool(), history = want.value(u"history"_s, true).toBool();
    const bool passwords = want.value(u"passwords"_s, true).toBool(), sites = want.value(u"sites"_s, true).toBool();
    const bool tabs = want.value(u"tabs"_s, true).toBool();
    m_profile = target;
    setState(u"reading"_s);
    QPointer<ChromeImport> self(this);
    QThreadPool::globalInstance()->start([self, profile, browser, apps, bookmarks, history, passwords, sites, tabs] {
        auto r = std::make_shared<Read>();
        r->browser = browser;
        r->apps = apps;
        r->passwords = passwords;
        r->sites = sites;
        QTemporaryDir copies;
        if (bookmarks)
            r->bookmarks = bookmarksOf(profile + u"/Bookmarks"_s);
        if (tabs)
            r->tabs = tabsOf(profile);
        if (history) {
            sqlite3 *db = openCopy(profile + u"/History"_s, copies.path());
            rows(db, "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0", [&](sqlite3_stmt *st) {
                r->history.append(QVariantMap{{u"url"_s, text(st, 0)}, {u"title"_s, text(st, 1)}, {u"visits"_s, sqlite3_column_int(st, 2)},
                                              {u"last"_s, epochMs(sqlite3_column_int64(st, 3))}});
            });
            closeCopy(db, profile + u"/History"_s, copies.path());
        }
        if (passwords) {
            QSet<QString> seen;
            for (const QString &file : {u"Login Data"_s, u"Login Data For Account"_s}) {
                sqlite3 *db = openCopy(profile + u'/' + file, copies.path());
                rows(db, "SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user = 0 AND length(password_value) > 0",
                     [&](sqlite3_stmt *st) {
                    bool app = false;
                    const QString origin = PasswordFile::originOf(text(st, 0), &app), user = text(st, 1);
                    if (origin.isEmpty() || seen.contains(origin + u'\n' + user))
                        return;
                    seen.insert(origin + u'\n' + user);
                    r->logins.append({origin, user, blob(st, 2)});
                });
                closeCopy(db, profile + u'/' + file, copies.path());
            }
        }
        if (sites) {
            sqlite3 *db = openCopy(profile + u"/Cookies"_s, copies.path());
            cookiesIn(db, [&](const QString &host, const QString &name, const QByteArray &value, const QByteArray &sealed, const QString &path,
                              qint64 expires, bool secure, bool httpOnly, int sameSite) {
                r->cookies.append({host, name, path, value, sealed, expires, secure, httpOnly, sameSite});
            });
            closeCopy(db, profile + u"/Cookies"_s, copies.path());
        }
        QMetaObject::invokeMethod(self, [self, r] { if (self) self->afterRead(r); }, Qt::QueuedConnection);
    });
    return true;
}

void ChromeImport::afterRead(std::shared_ptr<Read> r) {
    emit read({{u"browser"_s, r->browser}, {u"bookmarks"_s, r->bookmarks}, {u"history"_s, r->history}, {u"tabs"_s, r->tabs}, {u"failure"_s, QString()}});
    r->bookmarks.clear();
    r->history.clear();
    r->tabs.clear();
    if (r->logins.isEmpty() && r->cookies.isEmpty()) {
        setState(QString());
        if (r->sites)
            emit cookiesDone({{u"added"_s, 0}, {u"refused"_s, 0}, {u"left"_s, 0}, {u"sites"_s, 0}});
        emit saved({{u"added"_s, 0}, {u"kept"_s, 0}, {u"left"_s, 0}, {u"total"_s, 0}, {u"failure"_s, QString()}});
        return;
    }
    // v10 alone needs no secret of the browser's
    if (std::none_of(r->logins.cbegin(), r->logins.cend(), [](const Read::Login &l) { return l.sealed.startsWith("v11"); })
        && std::none_of(r->cookies.cbegin(), r->cookies.cend(), [](const Read::Cookie &c) { return c.sealed.startsWith("v11"); })) {
        bring(r, QByteArray());
        return;
    }
    setState(u"keyring"_s);
    withKey(r, 0);
}

// the browser's secret, under each of its `application` names in turn
void ChromeImport::withKey(std::shared_ptr<Read> r, int app) {
    auto *keyring = qmlEngine(this) ? qmlEngine(this)->singletonInstance<Passwords *>("Browser", "Passwords") : nullptr;
    if (!keyring || app >= r->apps.size()) {
        bring(r, QByteArray());
        return;
    }
    QPointer<ChromeImport> self(this);
    keyring->secretMatching({{u"application"_s, r->apps.at(app)}}, false, [self, r, app](const QByteArray &secret, const QString &failure) {
        if (!self)
            return;
        if (failure == u"missing")
            self->withKey(r, app + 1);
        else
            self->bring(r, failure.isEmpty() ? secret : QByteArray());
    });
}

void ChromeImport::bring(std::shared_ptr<Read> r, QByteArray secret) {
    // the cookies first, so the sites keep you signed in; a value newer Chromium seals begins with its host's SHA-256
    if (!r->cookies.isEmpty()) {
#ifdef BROWSER_CEF
        QList<CefCookies::Set> set;
        QSet<QString> sites;
        int left = 0, kept = 0;
        bool google = false;
        // one the store has already (as SiteData lists it) is kept, so bringing the profile again sets none
        auto *held = qmlEngine(this) ? qmlEngine(this)->singletonInstance<SiteData *>("Browser", "SiteData") : nullptr;
        for (Read::Cookie &c : r->cookies) {
            QNetworkCookie probe(c.name.toUtf8());
            probe.setDomain(c.host);
            probe.setPath(c.path.isEmpty() ? u"/"_s : c.path);
            if (held && held->holds(probe)) {
                ++kept;
                sites.insert(siteOf(c.host));
                google = google || googleSignIn(c.host, c.name);
                c.sealed.fill('\0');
                continue;
            }
            QByteArray value = c.sealed.isEmpty() ? c.value : decrypt(c.sealed, secret);
            c.sealed.fill('\0');
            if (value.isNull()) {
                ++left;
                continue;
            }
            if (!c.sealed.isEmpty() || value.size() >= 32) {
                const QByteArray hashed = QCryptographicHash::hash(c.host.toUtf8(), QCryptographicHash::Sha256);
                if (value.startsWith(hashed))
                    value.remove(0, 32);
            }
            set.append({c.name, c.host, c.path, value, c.secure, c.httpOnly, c.sameSite, c.expires});
            sites.insert(siteOf(c.host));
            google = google || googleSignIn(c.host, c.name);
        }
        r->cookies.clear();
        QPointer<ChromeImport> self(this);
        const int count = int(sites.size());
        CefCookies::set(m_profile, set, this, [self, r, secret, left, kept, count, google](int added, int refused) mutable {
            if (!self)
                return;
            emit self->cookiesDone({{u"added"_s, added}, {u"kept"_s, kept}, {u"refused"_s, refused}, {u"left"_s, left}, {u"sites"_s, count},
                                    {u"google"_s, google}});
            self->bring(r, secret);
        });
        for (CefCookies::Set &c : set)
            c.value.fill('\0');
        return;
#else
        r->cookies.clear();
        emit cookiesDone({{u"failure"_s, u"profile"_s}});
#endif
    }
    auto *keyring = qmlEngine(this) ? qmlEngine(this)->singletonInstance<Passwords *>("Browser", "Passwords") : nullptr;
    if (r->logins.isEmpty()) {
        secret.fill('\0');
        setState(QString());
        emit saved({{u"added"_s, 0}, {u"kept"_s, 0}, {u"left"_s, 0}, {u"total"_s, 0}, {u"failure"_s, QString()}});
        return;
    }
    QList<Passwords::Login> open;
    int closed = 0;
    for (Read::Login &l : r->logins) {
        QByteArray plain = decrypt(l.sealed, secret);
        if (plain.isNull())
            ++closed;
        else
            open.append({l.origin, l.user, plain});
        l.sealed.fill('\0');
    }
    secret.fill('\0');
    const int total = int(r->logins.size());
    r->logins.clear();
    if (!keyring || open.isEmpty()) {
        setState(QString());
        emit saved({{u"added"_s, 0}, {u"kept"_s, 0}, {u"left"_s, total}, {u"total"_s, total}, {u"failure"_s, closed > 0 ? u"no key"_s : u"none"_s}});
        return;
    }
    setState(u"saving"_s);
    QPointer<ChromeImport> self(this);
    auto given = std::make_shared<QList<Passwords::Login>>(open);
    for (Passwords::Login &l : open)
        l.password.fill('\0');
    keyring->importLogins(*given, [self, given, closed, total](int added, int kept, int left, const QString &failure) {
        for (Passwords::Login &l : *given)
            l.password.fill('\0');
        if (!self)
            return;
        self->setState(QString());
        emit self->saved({{u"added"_s, added}, {u"kept"_s, kept}, {u"left"_s, left + closed}, {u"total"_s, total},
                          {u"failure"_s, !failure.isEmpty() ? failure : closed > 0 ? u"no key"_s : QString()}});
    }, [self, total](int done) { if (self) emit self->progress(done, total); });
}
