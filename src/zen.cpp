#include "zen.h"
#include "passwords.h"
#include "sitedata.h"
#include "chromeimport.h"
#ifdef BROWSER_CEF
#include "cef/cookies.h"
#endif

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QPointer>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QThreadPool>
#ifndef BROWSER_CEF
#include <QtWebEngineCore/QWebEngineCookieStore>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#endif
#include <QtEndian>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <functional>
#include <iostream>
#include <iterator>
#include <sqlite3.h>
#include <string>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <unistd.h>
#include <utility>

namespace {

// CityHash64 1.0 (Google, MIT licence, src/CityHash-COPYING): Firefox hashes the folder it runs from with it
// (commonupdatedir.cpp, from other-licenses/nsis/Contrib/CityHash) to name that install's [Install<hash>] section. Checked
// on this machine against both installs' sections; paths over 32 characters take the 64-byte loop, which those two did not.
namespace city {
using u64 = quint64;
constexpr u64 k0 = 0xc3a5c85c97cb3127ULL, k1 = 0xb492b66fbe98f273ULL, k2 = 0x9ae16a3b2f90404fULL, k3 = 0xc949d7c7509e6557ULL;
u64 fetch64(const char *p) {
    u64 v;
    std::memcpy(&v, p, 8);
    return qFromLittleEndian(v);
}
u64 fetch32(const char *p) {
    quint32 v;
    std::memcpy(&v, p, 4);
    return qFromLittleEndian(v);
}
u64 rotate(u64 v, int s) { return s == 0 ? v : (v >> s) | (v << (64 - s)); }
u64 rotateAtLeast1(u64 v, int s) { return (v >> s) | (v << (64 - s)); }
u64 shiftMix(u64 v) { return v ^ (v >> 47); }
u64 hash16(u64 u, u64 v) {
    constexpr u64 mul = 0x9ddfea08eb382d69ULL;
    u64 a = (u ^ v) * mul;
    a ^= a >> 47;
    u64 b = (v ^ a) * mul;
    b ^= b >> 47;
    return b * mul;
}
u64 len0to16(const char *s, size_t len) {
    if (len > 8) {
        const u64 a = fetch64(s), b = fetch64(s + len - 8);
        return hash16(a, rotateAtLeast1(b + len, int(len))) ^ b;
    }
    if (len >= 4)
        return hash16(len + (fetch32(s) << 3), fetch32(s + len - 4));
    if (len > 0) {
        const u64 y = u64(quint8(s[0])) + (u64(quint8(s[len >> 1])) << 8), z = len + (u64(quint8(s[len - 1])) << 2);
        return shiftMix((y * k2) ^ (z * k3)) * k2;
    }
    return k2;
}
u64 len17to32(const char *s, size_t len) {
    const u64 a = fetch64(s) * k1, b = fetch64(s + 8), c = fetch64(s + len - 8) * k2, d = fetch64(s + len - 16) * k0;
    return hash16(rotate(a - b, 43) + rotate(c, 30) + d, a + rotate(b ^ k3, 20) - c + len);
}
u64 len33to64(const char *s, size_t len) {
    u64 z = fetch64(s + 24), a = fetch64(s) + (len + fetch64(s + len - 16)) * k0, b = rotate(a + z, 52), c = rotate(a, 37);
    a += fetch64(s + 8);
    c += rotate(a, 7);
    a += fetch64(s + 16);
    const u64 vf = a + z, vs = b + rotate(a, 31) + c;
    a = fetch64(s + 16) + fetch64(s + len - 32);
    z = fetch64(s + len - 8);
    b = rotate(a + z, 52);
    c = rotate(a, 37);
    a += fetch64(s + len - 24);
    c += rotate(a, 7);
    a += fetch64(s + len - 16);
    const u64 wf = a + z, ws = b + rotate(a, 31) + c;
    const u64 r = shiftMix((vf + ws) * k2 + (wf + vs) * k0);
    return shiftMix(r * k0 + vs) * k2;
}
std::pair<u64, u64> weak32(const char *s, u64 a, u64 b) {
    const u64 w = fetch64(s), x = fetch64(s + 8), y = fetch64(s + 16), z = fetch64(s + 24);
    a += w;
    b = rotate(b + a + z, 21);
    const u64 c = a;
    a += x;
    a += y;
    b += rotate(a, 44);
    return {a + z, b + c};
}
u64 hash64(const char *s, size_t len) {
    if (len <= 16)
        return len0to16(s, len);
    if (len <= 32)
        return len17to32(s, len);
    if (len <= 64)
        return len33to64(s, len);
    u64 x = fetch64(s), y = fetch64(s + len - 16) ^ k1, z = fetch64(s + len - 56) ^ k0;
    auto v = weak32(s + len - 64, len, y);
    auto w = weak32(s + len - 32, len * k1, k0);
    z += shiftMix(v.second) * k1;
    x = rotate(z + x, 39) * k1;
    y = rotate(y, 33) * k1;
    len = (len - 1) & ~size_t(63);
    do {
        x = rotate(x + y + v.first + fetch64(s + 16), 37) * k1;
        y = rotate(y + v.second + fetch64(s + 48), 42) * k1;
        x ^= w.second;
        y ^= v.first;
        z = rotate(z ^ w.first, 33);
        v = weak32(s, v.second * k1, x + w.first);
        w = weak32(s + 32, z + w.second, y);
        std::swap(z, x);
        s += 64;
        len -= 64;
    } while (len != 0);
    return hash16(hash16(v.first, w.first) + shiftMix(y) * k1 + z, hash16(v.second, w.second) + x);
}
}

using Ini = QMap<QString, QMap<QString, QString>>;
// profiles.ini and installs.ini: [section] and key=value lines, as Firefox writes them (QSettings would read a comma
// in a path as a list)
Ini readIni(const QString &path) {
    Ini out;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return out;
    QString section;
    for (const QByteArray &raw : file.readAll().split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.startsWith(u'[') && line.endsWith(u']'))
            section = line.mid(1, line.size() - 2);
        else if (const qsizetype eq = line.indexOf(u'='); eq > 0 && !section.isEmpty() && !line.startsWith(u';') && !line.startsWith(u'#'))
            out[section][line.left(eq).trimmed()] = line.mid(eq + 1).trimmed();
    }
    return out;
}

// The folder of the program a desktop entry's Exec starts: its first word, found on PATH, symbolic links followed; a
// launcher script (Arch's /usr/bin/zen-browser) by the absolute program it execs.
QString programFolder(const QString &exec) {
    const QString word = exec.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts).value(0).remove(u'"');
    QString program = word.startsWith(u'/') ? word : QStandardPaths::findExecutable(word);
    program = QFileInfo(program).canonicalFilePath();
    if (program.isEmpty())
        return {};
    QFile file(program);
    if (file.open(QIODevice::ReadOnly) && file.peek(2) == "#!") {
        const auto m = QRegularExpression(QStringLiteral("\\bexec\\s+\"?(/[^\\s\"]+)")).match(QString::fromUtf8(file.read(64 * 1024)));
        if (m.hasMatch())
            program = QFileInfo(m.captured(1)).canonicalFilePath();
    }
    return program.isEmpty() ? QString() : QFileInfo(program).absolutePath();
}

// The folders a browser of the family runs from, as Firefox names its installs: the program its desktop entries (`entries`,
// "zen*.desktop") start, then the folder each profile says it last ran from (compatibility.ini's LastPlatformDir), where
// that still exists
QStringList installFolders(const QStringList &profileFolders, const QString &entries) {
    QStringList out;
    for (const QString &dir : QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation))
        for (const QFileInfo &entry : QDir(dir).entryInfoList({entries}, QDir::Files)) {
            const QString exec = readIni(entry.filePath()).value(QStringLiteral("Desktop Entry")).value(QStringLiteral("Exec"));
            if (const QString folder = programFolder(exec); !folder.isEmpty() && !out.contains(folder))
                out.append(folder);
        }
    for (const QString &profile : profileFolders) {
        const QString last = readIni(profile + QStringLiteral("/compatibility.ini")).value(QStringLiteral("Compatibility")).value(QStringLiteral("LastPlatformDir"));
        if (!last.isEmpty() && QFileInfo(last).isDir() && !out.contains(last))
            out.append(last);
    }
    return out;
}

bool isWebOrigin(const QString &origin) {
    static const QRegularExpression web(QStringLiteral("^https?://[^/?#@\\s]+$"), QRegularExpression::CaseInsensitiveOption);
    return web.match(origin).hasMatch();
}
// the logins the browser can use: a site's sign-in form (no httpRealm: those are HTTP sign-ins, which the browser does not
// fill) at an http or https origin
bool importable(const QJsonObject &login) {
    return isWebOrigin(login.value(QStringLiteral("hostname")).toString()) && login.value(QStringLiteral("httpRealm")).isNull();
}
QJsonArray loginsOf(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QJsonArray out;
    for (const QJsonValue &v : QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("logins")).toArray())
        if (importable(v.toObject()))
            out.append(v);
    return out;
}

// The database and its write-ahead log, copied as one moment: Zen may be writing while the copy is made, and a
// checkpoint in between moves pages from the log into the database, so both are copied again if either changed.
bool copyDatabase(const QString &from, const QString &to) {
    const auto stamp = [](const QString &path) {
        const QFileInfo f(path);
        return f.exists() ? QString::number(f.lastModified().toMSecsSinceEpoch()) + u'/' + QString::number(f.size()) : QString();
    };
    for (int attempt = 0; attempt < 3; ++attempt) {
        const QString db = stamp(from), wal = stamp(from + QStringLiteral("-wal"));
        QFile::remove(to);
        QFile::remove(to + QStringLiteral("-wal"));
        if (!QFile::copy(from, to) || (!wal.isEmpty() && !QFile::copy(from + QStringLiteral("-wal"), to + QStringLiteral("-wal"))))
            return false;
        if (stamp(from) == db && stamp(from + QStringLiteral("-wal")) == wal)
            break;
    }
    return true;
}

QString text(sqlite3_stmt *row, int column) {
    const auto *t = reinterpret_cast<const char *>(sqlite3_column_text(row, column));
    return t ? QString::fromUtf8(t) : QString();
}

// Mozilla's session files: 8 bytes "mozLz40\0", the size (4 bytes, little endian), then one LZ4 block. Empty when the
// header, a length or an offset is wrong, or the block does not fill the size.
QByteArray unMozLz4(const QByteArray &in) {
    constexpr qsizetype header = 12;
    constexpr quint32 most = 512u << 20;
    if (in.size() < header || std::memcmp(in.constData(), "mozLz40\0", 8) != 0)
        return {};
    const quint32 size = qFromLittleEndian<quint32>(in.constData() + 8);
    if (size == 0 || size > most)
        return {};
    QByteArray out(qsizetype(size), Qt::Uninitialized);
    const auto *s = reinterpret_cast<const uchar *>(in.constData()) + header;
    const auto *end = reinterpret_cast<const uchar *>(in.constData()) + in.size();
    uchar *const start = reinterpret_cast<uchar *>(out.data());
    uchar *o = start, *const oend = start + size;
    // a length: its 4 bits, and while they are 15, further bytes added until one is not 255
    const auto length = [&](size_t n, size_t &into) {
        if (n == 15) {
            uchar b;
            do {
                if (s >= end)
                    return false;
                b = *s++;
                n += b;
            } while (b == 255);
        }
        into = n;
        return true;
    };
    while (s < end) {
        const unsigned token = *s++;
        size_t literals;
        if (!length(token >> 4, literals) || literals > size_t(end - s) || literals > size_t(oend - o))
            return {};
        std::memcpy(o, s, literals);
        o += literals;
        s += literals;
        if (s == end)
            break;      // the last sequence has literals only
        if (end - s < 2)
            return {};
        const size_t offset = size_t(s[0]) | size_t(s[1]) << 8;
        s += 2;
        size_t match;
        if (!length(token & 15, match))
            return {};
        match += 4;
        if (offset == 0 || offset > size_t(o - start) || match > size_t(oend - o))
            return {};
        for (size_t i = 0; i < match; ++i, ++o)     // one byte at a time: a match may overlap what it writes
            *o = *(o - offset);
    }
    return o == oend ? out : QByteArray();
}

// "www.example.co.uk" and ".example.co.uk" are one site, example.co.uk: the last two labels, three under a two-letter
// country code's short second level; an address is its own site. A count for the import's words, not a public suffix list.
QString siteOf(QString host) {
    if (host.startsWith(u'.'))
        host.remove(0, 1);
    const QStringList labels = host.split(u'.');
    const qsizetype n = labels.size();
    if (n <= 2 || host.contains(u':') || labels.last().at(0).isDigit())
        return host;
    const bool second = n >= 3 && labels.last().size() == 2 && labels.at(n - 2).size() <= 3;
    return labels.mid(n - (second ? 3 : 2)).join(u'.');
}

// What Zen's cookies.sqlite holds that the browser can take
struct Jar {
    QList<QNetworkCookie> cookies;
    QSet<QString> sites;
    int partitioned = 0;    // Firefox keeps these per top-level site (partitionKey), which the engine cannot be told
    int other = 0;          // in a container (userContextId) or private window: another jar than this browser's one
    int expired = 0;
};

// The cookies of a copy of cookies.sqlite, unexpired and in no partition or container, as the engine sets them: a host
// with a leading dot is a domain cookie, one without is the host's own; the expiry is in seconds in older Zen and in
// milliseconds in newer (told by size); 0 is a session cookie; SameSite is 0 None, 1 Lax, 2 Strict, 256 unset. The copy
// is deleted once read: it holds every session. True when there is none to read or it was read. `values` false (the
// scan's count) reads no cookie value and fills only the sites.
bool readCookies(const QString &profile, const QString &into, Jar &jar, bool values = true) {
    const QString from = profile + QStringLiteral("/cookies.sqlite"), copy = into + QStringLiteral("/cookies.sqlite");
    if (!QFileInfo(from).isFile())
        return true;
    const auto remove = [&] {
        for (const char *suffix : {"", "-wal", "-shm"})
            QFile::remove(copy + QLatin1String(suffix));
    };
    sqlite3 *db = nullptr;
    sqlite3_stmt *row = nullptr;
    bool ok = copyDatabase(from, copy)
        && sqlite3_open_v2(QFile::encodeName(copy).constData(), &db, SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK
        && sqlite3_prepare_v2(db, values ? "SELECT name, value, host, path, expiry, isSecure, isHttpOnly, sameSite, originAttributes FROM moz_cookies"
                                         : "SELECT '', '', host, '', expiry, 0, 0, 0, originAttributes FROM moz_cookies", -1, &row, nullptr) == SQLITE_OK;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const auto bytes = [&row](int column) {
        return QByteArray(reinterpret_cast<const char *>(sqlite3_column_blob(row, column)), sqlite3_column_bytes(row, column));
    };
    int step = SQLITE_DONE;
    while (ok && (step = sqlite3_step(row)) == SQLITE_ROW) {
        const QString attributes = text(row, 8), host = text(row, 2).toLower();
        if (attributes.contains(QStringLiteral("partitionKey="))) {
            ++jar.partitioned;
            continue;
        }
        if (!attributes.isEmpty()) {
            ++jar.other;
            continue;
        }
        qint64 expiry = sqlite3_column_int64(row, 4);
        if (expiry > 0 && expiry < 100000000000)
            expiry *= 1000;
        if (host.isEmpty())
            continue;
        if (expiry > 0 && expiry <= now) {
            ++jar.expired;
            continue;
        }
        jar.sites.insert(siteOf(host));
        if (!values)
            continue;
        QNetworkCookie cookie(bytes(0), bytes(1));
        cookie.setDomain(host);
        cookie.setPath(text(row, 3));
        cookie.setSecure(sqlite3_column_int(row, 5) != 0);
        cookie.setHttpOnly(sqlite3_column_int(row, 6) != 0);
        if (expiry > 0)
            cookie.setExpirationDate(QDateTime::fromMSecsSinceEpoch(expiry));
        // None without Secure is refused by the engine, as Chromium has it: it takes the default (Lax) instead
        switch (sqlite3_column_int(row, 7)) {
        case 0: cookie.setSameSitePolicy(cookie.isSecure() ? QNetworkCookie::SameSite::None : QNetworkCookie::SameSite::Default); break;
        case 1: cookie.setSameSitePolicy(QNetworkCookie::SameSite::Lax); break;
        case 2: cookie.setSameSitePolicy(QNetworkCookie::SameSite::Strict); break;
        default: cookie.setSameSitePolicy(QNetworkCookie::SameSite::Default);
        }
        jar.cookies.append(cookie);
    }
    ok = ok && step == SQLITE_DONE;
    sqlite3_finalize(row);
    sqlite3_close(db);
    remove();
    return ok;
}

// The tabs of the newest session file Zen has (sessionstore.jsonlz4, or recovery.jsonlz4 in sessionstore-backups, which
// a running Zen writes), of every window: { url, title, space }, essential tabs first, then pinned, then the rest, each
// in Zen's order. Only web pages and files; `space` (the workspace's name) only when the tabs span more than one. `ok`
// is false when a session file exists and none opens.
QVariantList readTabs(const QString &profile, const QString &into, bool &ok) {
    ok = true;
    QStringList files;
    for (const char *name : {"/sessionstore.jsonlz4", "/sessionstore-backups/recovery.jsonlz4"})
        if (QFileInfo(profile + QLatin1String(name)).isFile())
            files.append(profile + QLatin1String(name));
    std::sort(files.begin(), files.end(), [](const QString &a, const QString &b) { return QFileInfo(a).lastModified() > QFileInfo(b).lastModified(); });
    const QString copy = into + QStringLiteral("/session.jsonlz4");
    for (const QString &file : std::as_const(files)) {
        QFile::remove(copy);
        if (!QFile::copy(file, copy))
            continue;
        QFile in(copy);
        const QByteArray raw = in.open(QIODevice::ReadOnly) ? unMozLz4(in.readAll()) : QByteArray();
        in.close();
        QFile::remove(copy);
        const QJsonObject session = QJsonDocument::fromJson(raw).object();
        if (!session.contains(QStringLiteral("windows")))
            continue;
        struct Tab { QString url, title, space; int rank; };
        QList<Tab> tabs;
        QSet<QString> spaces;
        for (const QJsonValue &w : session.value(QStringLiteral("windows")).toArray()) {
            const QJsonObject window = w.toObject();
            QMap<QString, QString> names;
            for (const QJsonValue &s : window.value(QStringLiteral("spaces")).toArray())
                names.insert(s.toObject().value(QStringLiteral("uuid")).toString(), s.toObject().value(QStringLiteral("name")).toString());
            for (const QJsonValue &t : window.value(QStringLiteral("tabs")).toArray()) {
                const QJsonObject tab = t.toObject();
                const QJsonArray entries = tab.value(QStringLiteral("entries")).toArray();
                if (entries.isEmpty())
                    continue;
                const qsizetype at = std::clamp<qsizetype>(tab.value(QStringLiteral("index")).toInt(entries.size()), 1, entries.size()) - 1;
                const QJsonObject entry = entries.at(at).toObject();
                const QString url = entry.value(QStringLiteral("url")).toString();
                if (!url.startsWith(QStringLiteral("https://")) && !url.startsWith(QStringLiteral("http://")) && !url.startsWith(QStringLiteral("file:")))
                    continue;
                const QString space = tab.value(QStringLiteral("zenWorkspace")).toString();
                spaces.insert(space);
                tabs.append({url, entry.value(QStringLiteral("title")).toString(), names.value(space),
                             tab.value(QStringLiteral("zenEssential")).toBool() ? 0 : tab.value(QStringLiteral("pinned")).toBool() ? 1 : 2});
            }
        }
        std::stable_sort(tabs.begin(), tabs.end(), [](const Tab &a, const Tab &b) { return a.rank < b.rank; });
        QVariantList out;
        for (const Tab &t : std::as_const(tabs))
            out.append(QVariantMap{{QStringLiteral("url"), t.url}, {QStringLiteral("title"), t.title},
                                   {QStringLiteral("space"), spaces.size() > 1 ? t.space : QString()}});
        return out;
    }
    ok = files.isEmpty();
    return {};
}

// What readProfile takes out of the profile besides what it returns: the cookies (never to QML), the numbers about them
struct Taken {
    QList<QNetworkCookie> cookies;
    QVariantMap cookieCounts;   // { cookies, sites, skipped, expired } or { failure }; empty with no cookies file or none wanted
};

// Off the UI thread: the profile's files copied into `into`, then its bookmarks (by folder, in Zen's order), its history
// (the 5000 last visited, as History keeps) and how many logins it has. Nothing is decrypted here.
QVariantMap readProfile(const QString &profile, const QString &into, bool cookies, bool tabs, Taken &taken) {
    QVariantMap out;
    if (!copyDatabase(profile + QStringLiteral("/places.sqlite"), into + QStringLiteral("/places.sqlite"))) {
        out.insert(QStringLiteral("failure"), QStringLiteral("copy"));
        return out;
    }
    for (const char *name : {"logins.json", "key4.db", "cert9.db"})
        if (QFileInfo(profile + u'/' + QLatin1String(name)).isFile())
            QFile::copy(profile + u'/' + QLatin1String(name), into + u'/' + QLatin1String(name));
    sqlite3 *db = nullptr;
    // read-write: opening the copy replays its write-ahead log
    if (sqlite3_open_v2(QFile::encodeName(into + QStringLiteral("/places.sqlite")).constData(), &db, SQLITE_OPEN_READWRITE, nullptr) != SQLITE_OK) {
        sqlite3_close(db);
        out.insert(QStringLiteral("failure"), QStringLiteral("places"));
        return out;
    }
    const auto query = [db](const char *sql, const std::function<void(sqlite3_stmt *)> &each) {
        sqlite3_stmt *row = nullptr;
        if (sqlite3_prepare_v2(db, sql, -1, &row, nullptr) != SQLITE_OK) {
            sqlite3_finalize(row);
            return false;
        }
        int step;
        while ((step = sqlite3_step(row)) == SQLITE_ROW)
            each(row);
        sqlite3_finalize(row);
        return step == SQLITE_DONE;
    };
    // the four roots Firefox shows (the tags root is left out: its folders repeat bookmarks by tag); a folder's path is
    // its names from the root, joined by U+001F
    QVariantList bookmarks;
    const bool marks = query(
        "WITH RECURSIVE folders(id, rank, path) AS ("
        " SELECT id, CASE guid WHEN 'toolbar_____' THEN 0 WHEN 'menu________' THEN 1 WHEN 'unfiled_____' THEN 2 ELSE 3 END,"
        "  CASE guid WHEN 'toolbar_____' THEN 'Toolbar' WHEN 'menu________' THEN 'Menu' WHEN 'unfiled_____' THEN 'Other' ELSE 'Mobile' END"
        "  FROM moz_bookmarks WHERE guid IN ('toolbar_____', 'menu________', 'unfiled_____', 'mobile______')"
        " UNION ALL SELECT b.id, f.rank, f.path || char(31) || COALESCE(NULLIF(b.title, ''), 'Folder')"
        "  FROM moz_bookmarks b JOIN folders f ON b.parent = f.id WHERE b.type = 2)"
        " SELECT p.url, COALESCE(NULLIF(b.title, ''), p.title, ''), f.path, b.dateAdded"
        " FROM moz_bookmarks b JOIN folders f ON b.parent = f.id JOIN moz_places p ON p.id = b.fk"
        " WHERE b.type = 1 ORDER BY f.rank, f.path, b.position",
        [&](sqlite3_stmt *row) {
            const QString url = text(row, 0);
            // bookmarklets (javascript:) and Firefox's own queries (place:) are no pages
            if (!url.startsWith(QStringLiteral("https://")) && !url.startsWith(QStringLiteral("http://")) && !url.startsWith(QStringLiteral("file:")))
                return;
            bookmarks.append(QVariantMap{{QStringLiteral("url"), url}, {QStringLiteral("title"), text(row, 1)},
                                         {QStringLiteral("folder"), text(row, 2).split(QChar(31))},
                                         {QStringLiteral("added"), double(sqlite3_column_int64(row, 3) / 1000)}});
        });
    QVariantList history;
    const bool visits = query(
        "SELECT url, COALESCE(title, ''), visit_count, last_visit_date FROM moz_places"
        " WHERE visit_count > 0 AND hidden = 0 AND last_visit_date IS NOT NULL AND (url LIKE 'https://%' OR url LIKE 'http://%')"
        " ORDER BY last_visit_date DESC LIMIT 5000",
        [&](sqlite3_stmt *row) {
            history.append(QVariantMap{{QStringLiteral("url"), text(row, 0)}, {QStringLiteral("title"), text(row, 1)},
                                       {QStringLiteral("visits"), sqlite3_column_int(row, 2)},
                                       {QStringLiteral("last"), double(sqlite3_column_int64(row, 3) / 1000)}});
        });
    sqlite3_close(db);
    // the history is read: only what the passwords need stays in the copy while they wait
    for (const char *suffix : {"", "-wal", "-shm"})
        QFile::remove(into + QStringLiteral("/places.sqlite") + QLatin1String(suffix));
    if (!marks || !visits) {
        out.insert(QStringLiteral("failure"), QStringLiteral("places"));
        return out;
    }
    if (cookies && QFileInfo(profile + QStringLiteral("/cookies.sqlite")).isFile()) {
        Jar jar;
        if (readCookies(profile, into, jar))
        {
            taken.cookieCounts = {{QStringLiteral("cookies"), int(jar.cookies.size())}, {QStringLiteral("sites"), int(jar.sites.size())},
                                  {QStringLiteral("skipped"), jar.partitioned + jar.other}, {QStringLiteral("partitioned"), jar.partitioned},
                                  {QStringLiteral("expired"), jar.expired},
                                  {QStringLiteral("google"), std::any_of(jar.cookies.cbegin(), jar.cookies.cend(), [](const QNetworkCookie &c) {
                                      return ChromeImport::googleSignIn(c.domain(), QString::fromUtf8(c.name())); })}};
            taken.cookies = std::move(jar.cookies);
        } else {
            taken.cookieCounts = {{QStringLiteral("failure"), QStringLiteral("cookies")}};
        }
    }
    if (tabs) {
        bool ok;
        out.insert(QStringLiteral("tabs"), readTabs(profile, into, ok));
        if (!ok)
            out.insert(QStringLiteral("tabsFailed"), true);
    }
    out.insert(QStringLiteral("bookmarks"), bookmarks);
    out.insert(QStringLiteral("history"), history);
    out.insert(QStringLiteral("logins"), loginsOf(into + QStringLiteral("/logins.json")).size());
    return out;
}
}

// The copies of a profile an import makes (`browser-zen-<pid>-XXXXXX` in the temp dir) whose browser is gone: one that
// did not quit (SIGKILL, a crash) left its copy behind, as QTemporaryDir removes it only when it is destroyed.
static void sweepCopies() {
    for (const QFileInfo &f : QDir(QDir::tempPath()).entryInfoList({QStringLiteral("browser-zen-*")}, QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks)) {
        const qint64 pid = f.fileName().section(u'-', 2, 2).toLongLong();
        if (pid > 0 && pid != QCoreApplication::applicationPid() && f.ownerId() == ::getuid()
            && !QFileInfo::exists(QStringLiteral("/proc/%1").arg(pid)))
            QDir(f.filePath()).removeRecursively();
    }
}

Zen::Zen(QObject *parent) : QObject(parent) {
    sweepCopies();
    find();
}

// the copy of the profile goes with the browser, should a quit come while the passwords wait; a copy still being made
// is done first, or it would be written into the folder as it goes
Zen::~Zen() {
    if (m_helper) {
        m_helper->kill();
        m_helper->waitForFinished(1000);
    }
    m_reader.waitForDone();
    m_copy.reset();
    guard(false);
}

QString Zen::installHash(const QString &folder) {
    const QByteArray utf16(reinterpret_cast<const char *>(folder.utf16()), folder.size() * 2);
    return QString::number(city::hash64(utf16.constData(), size_t(utf16.size())), 16).toUpper();
}

void Zen::useRoot(const QString &root) {
    m_root = root;
    find();
}

void Zen::fake(const QVariantMap &profile) {
    m_fake = true;
    m_profile = profile;
    emit profileChanged();
}

void Zen::setState(const QString &state, bool wrong) {
    m_state = state;
    m_wrong = wrong;
    emit stateChanged();
}

namespace {
// The Firefox family on Linux: where each keeps profiles.ini (native, then Flatpak and Snap) and its desktop entries' names
struct Fox {
    const char *name, *icon, *entries;
    QStringList roots;      // under the home folder; Zen's ~/.config/zen first (Zen 1.x), ~/.zen before it
};
const QList<Fox> &family() {
    static const QList<Fox> list = {
        {"Zen", "zen-browser", "zen*.desktop", {QStringLiteral(".config/zen"), QStringLiteral(".zen"), QStringLiteral(".var/app/app.zen_browser.zen/.zen")}},
        {"Firefox", "firefox", "firefox*.desktop", {QStringLiteral(".mozilla/firefox"), QStringLiteral(".var/app/org.mozilla.firefox/.mozilla/firefox"),
                                                    QStringLiteral("snap/firefox/common/.mozilla/firefox")}},
        {"LibreWolf", "librewolf", "librewolf*.desktop", {QStringLiteral(".librewolf"), QStringLiteral(".var/app/io.gitlab.librewolf-community/.librewolf")}},
        {"Floorp", "floorp", "floorp*.desktop", {QStringLiteral(".floorp"), QStringLiteral(".var/app/one.ablaze.floorp/.floorp")}},
        {"Waterfox", "waterfox", "waterfox*.desktop", {QStringLiteral(".waterfox"), QStringLiteral(".var/app/net.waterfox.waterfox/.waterfox")}},
    };
    return list;
}
}

// A family member's profile in `root`: the one of the install it runs from ([Install<hash>] in profiles.ini or
// installs.ini); else the only install's; else the one marked Default=1, which is what Firefox falls back to for an
// install with none of its own. { name, path }, {} for none.
static QVariantMap profileIn(const QString &root, const QString &entries) {
    QVariantMap found;
    if (!root.isEmpty()) {
        const Ini profiles = readIni(root + QStringLiteral("/profiles.ini"));
        // install hash -> the profile's Path as written; profiles.ini's [Install<hash>] over installs.ini's [<hash>]
        QMap<QString, QString> byInstall;
        const Ini installs = readIni(root + QStringLiteral("/installs.ini"));
        for (auto it = installs.cbegin(); it != installs.cend(); ++it)
            if (it->contains(QStringLiteral("Default")))
                byInstall.insert(it.key().toUpper(), it->value(QStringLiteral("Default")));
        for (auto it = profiles.cbegin(); it != profiles.cend(); ++it)
            if (it.key().startsWith(QStringLiteral("Install")) && it->contains(QStringLiteral("Default")))
                byInstall.insert(it.key().mid(7).toUpper(), it->value(QStringLiteral("Default")));
        // [ProfileN]: Path as written (relative to the root with IsRelative=1), its name, and Default=1
        QMap<QString, QPair<QString, QString>> byPath;
        QString marked;
        for (auto it = profiles.cbegin(); it != profiles.cend(); ++it) {
            if (!it.key().startsWith(QStringLiteral("Profile")) || it->value(QStringLiteral("Path")).isEmpty())
                continue;
            const QString path = it->value(QStringLiteral("Path"));
            const QString folder = it->value(QStringLiteral("IsRelative"), QStringLiteral("1")) == u"1" ? root + u'/' + path : path;
            byPath.insert(path, {it->value(QStringLiteral("Name")), folder});
            if (it->value(QStringLiteral("Default")) == u"1")
                marked = path;
        }
        QStringList folders;
        for (const auto &p : std::as_const(byPath))
            folders.append(p.second);
        QString chosen;
        for (const QString &folder : installFolders(folders, entries))
            if (const QString hash = Zen::installHash(folder); byInstall.contains(hash)) {
                chosen = byInstall.value(hash);
                break;
            }
        if (chosen.isEmpty() && byInstall.size() == 1)
            chosen = byInstall.first();
        if (chosen.isEmpty())
            chosen = marked;
        const auto p = byPath.value(chosen, {QString(), chosen.isEmpty() ? QString() : QDir(root).absoluteFilePath(chosen)});
        if (!p.second.isEmpty() && QFileInfo(p.second + QStringLiteral("/places.sqlite")).isFile())
            found = {{QStringLiteral("name"), p.first.isEmpty() ? QFileInfo(p.second).fileName() : p.first}, {QStringLiteral("path"), p.second}};
    }
    return found;
}

// Every member of the family with a profile; the checks' made-up folder (useRoot) stands for Zen alone. The chosen
// one's profile is `profile` (Zen's, as before, when it is here).
void Zen::find() {
    if (m_fake)
        return;
    QVariantList browsers;
    const QVariantMap unscanned{{QStringLiteral("passwords"), -1}, {QStringLiteral("bookmarks"), -1}, {QStringLiteral("sites"), -1}, {QStringLiteral("tabs"), -1}};
    const auto add = [&](const Fox &fox, const QVariantMap &p) {
        // counts already scanned for that profile stay
        QVariantMap counts = unscanned;
        for (const QVariant &b : std::as_const(m_browsers))
            if (b.toMap().value(QStringLiteral("path")) == p.value(QStringLiteral("path")))
                counts = b.toMap().value(QStringLiteral("counts")).toMap();
        browsers.append(QVariantMap{{QStringLiteral("browser"), QString::fromLatin1(fox.name)}, {QStringLiteral("icon"), ChromeImport::themeIcon(QString::fromLatin1(fox.icon))},
                                    {QStringLiteral("name"), p.value(QStringLiteral("name"))}, {QStringLiteral("path"), p.value(QStringLiteral("path"))},
                                    {QStringLiteral("counts"), counts}});
    };
    if (!m_root.isEmpty()) {
        if (const QVariantMap p = profileIn(m_root, QStringLiteral("zen*.desktop")); !p.isEmpty())
            add(family().first(), p);
    } else if (!noUserProfile || !m_home.isEmpty()) {
        const QString home = m_home.isEmpty() ? QDir::homePath() : m_home;
        for (const Fox &fox : family())
            for (const QString &dir : fox.roots)
                if (QFileInfo(home + u'/' + dir + QStringLiteral("/profiles.ini")).isFile()) {
                    if (const QVariantMap p = profileIn(home + u'/' + dir, QString::fromLatin1(fox.entries)); !p.isEmpty())
                        add(fox, p);
                    break;
                }
    }
    m_chosen = std::clamp(m_chosen, 0, std::max(0, int(browsers.size()) - 1));
    const QVariantMap chosen = browsers.value(m_chosen).toMap();
    const QVariantMap found = chosen.isEmpty() ? QVariantMap() : QVariantMap{{QStringLiteral("name"), chosen.value(QStringLiteral("name"))}, {QStringLiteral("path"), chosen.value(QStringLiteral("path"))}};
    if (found != m_profile || browsers != m_browsers) {
        m_browsers = browsers;
        m_profile = found;
        m_browser = chosen.value(QStringLiteral("browser")).toString();
        emit profileChanged();
    }
}

void Zen::useHome(const QString &home) {
    m_root.clear();
    m_home = home;
    find();
}

void Zen::choose(int index) {
    if (!m_state.isEmpty() || index < 0 || index >= m_browsers.size() || index == m_chosen)
        return;
    m_chosen = index;
    m_sites = m_tabs = -1;
    find();
}

// a profile's bookmarks of web pages, counted in a copy of places.sqlite (the browser may hold it)
static int bookmarkCount(const QString &profile, const QString &into) {
    const QString copy = into + QStringLiteral("/places-count.sqlite");
    for (const char *suffix : {"", "-wal"}) {
        QFile::remove(copy + QLatin1String(suffix));
        QFile::copy(profile + QStringLiteral("/places.sqlite") + QLatin1String(suffix), copy + QLatin1String(suffix));
    }
    int n = 0;
    sqlite3 *db = nullptr;
    if (sqlite3_open_v2(QFile::encodeName(copy).constData(), &db, SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK) {
        sqlite3_stmt *st = nullptr;
        if (sqlite3_prepare_v2(db, "SELECT count(*) FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk WHERE b.type = 1"
                                   " AND (p.url LIKE 'http://%' OR p.url LIKE 'https://%')", -1, &st, nullptr) == SQLITE_OK
            && sqlite3_step(st) == SQLITE_ROW)
            n = sqlite3_column_int(st, 0);
        sqlite3_finalize(st);
    }
    sqlite3_close(db);
    for (const char *suffix : {"", "-wal", "-shm"})
        QFile::remove(copy + QLatin1String(suffix));
    return n;
}

// Counts, for every browser found, its passwords, bookmarks, the sites it holds cookies for and its open tabs, in copies
// of its files, off the UI thread; answers with scanned() (`sites` and `tabs` the chosen one's)
void Zen::scan() {
    if (!m_state.isEmpty() || m_scanning || m_fake)
        return;
    find();
    QStringList profiles;
    for (const QVariant &b : std::as_const(m_browsers))
        profiles.append(b.toMap().value(QStringLiteral("path")).toString());
    auto copy = std::make_shared<QTemporaryDir>(QDir::tempPath() + QStringLiteral("/browser-zen-%1-XXXXXX").arg(QCoreApplication::applicationPid()));
    if (profiles.isEmpty() || !copy->isValid())
        return;
    m_scanning = true;
    // the count reads no value, but SQLite's page cache still holds the copy's pages, sessions included
    guard(true);
    const QPointer<Zen> self(this);
    m_reader.start([self, profiles, copy] {
        QList<QVariantMap> counts;
        for (const QString &profile : profiles) {
            Jar jar;
            bool ok;
            const bool read = readCookies(profile, copy->path(), jar, false);
            counts.append({{QStringLiteral("sites"), read ? int(jar.sites.size()) : 0}, {QStringLiteral("tabs"), int(readTabs(profile, copy->path(), ok).size())},
                           {QStringLiteral("passwords"), int(loginsOf(profile + QStringLiteral("/logins.json")).size())},
                           {QStringLiteral("bookmarks"), bookmarkCount(profile, copy->path())}});
        }
        QMetaObject::invokeMethod(self, [self, profiles, counts, copy] {
            if (!self)
                return;
            self->m_scanning = false;
            if (self->m_state.isEmpty())    // an import begun meanwhile keeps the guard until it ends
                self->guard(false);
            for (qsizetype i = 0; i < self->m_browsers.size(); ++i) {
                QVariantMap b = self->m_browsers.at(i).toMap();
                const qsizetype at = profiles.indexOf(b.value(QStringLiteral("path")).toString());
                if (at >= 0)
                    b.insert(QStringLiteral("counts"), counts.at(at));
                self->m_browsers[i] = b;
            }
            const QVariantMap chosen = self->m_browsers.value(self->m_chosen).toMap().value(QStringLiteral("counts")).toMap();
            self->m_sites = chosen.value(QStringLiteral("sites"), -1).toInt();
            self->m_tabs = chosen.value(QStringLiteral("tabs"), -1).toInt();
            emit self->profileChanged();
            emit self->scanned();
        }, Qt::QueuedConnection);
    });
}

bool Zen::start(const QVariantMap &want, QObject *profile) {
    if (!m_state.isEmpty() || m_fake)
        return false;
    find();
    const QString folder = m_profile.value(QStringLiteral("path")).toString();
    auto copy = std::make_unique<QTemporaryDir>(QDir::tempPath() + QStringLiteral("/browser-zen-%1-XXXXXX").arg(QCoreApplication::applicationPid()));
    if (folder.isEmpty() || !copy->isValid())
        return false;
    const QString into = copy->path();
    const bool cookies = want.value(QStringLiteral("cookies")).toBool(), tabs = want.value(QStringLiteral("tabs")).toBool();
    m_copy = std::move(copy);
    m_logins = 0;
    m_target = profile;
    m_jar.clear();
    m_jarCounts.clear();
    if (cookies)
        guard(true);
    setState(QStringLiteral("reading"));
    const QPointer<Zen> self(this);
    auto taken = std::make_shared<Taken>();
    m_reader.start([self, folder, into, cookies, tabs, taken] {
        const QVariantMap found = readProfile(folder, into, cookies, tabs, *taken);
        QMetaObject::invokeMethod(self, [self, found, taken] {
            if (!self)
                return;
            self->m_logins = found.value(QStringLiteral("logins")).toInt();
            self->m_jar = std::move(taken->cookies);
            self->m_jarCounts = taken->cookieCounts;
            emit self->read(found);
            if (found.contains(QStringLiteral("failure"))) {
                self->m_jar.clear();
                self->guard(false);
                self->m_copy.reset();
                self->setState(QString());
            } else {
                self->afterRead();
            }
        }, Qt::QueuedConnection);
    });
    return true;
}

// The cookies go in first (their copy is gone by now), then the passwords
void Zen::afterRead() {
    if (m_jarCounts.contains(QStringLiteral("failure")))
        emit cookiesDone({{QStringLiteral("failure"), m_jarCounts.value(QStringLiteral("failure"))}});
    else if (!m_jarCounts.isEmpty()) {
        importCookies();
        return;
    }
    carryOn();
}

void Zen::carryOn() {
    if (m_logins == 0) {
        finish({{QStringLiteral("added"), 0}, {QStringLiteral("kept"), 0}, {QStringLiteral("skipped"), QString()}});
    } else {
        // with no primary password this opens them; with one it answers "locked" and the flow asks for it
        decrypt(QString());
    }
}

// Into the cookie store of the profile the import was started with, and only if the cookie list (SiteData) is that
// store's: the ones it holds already are left as they are. Qt gives no answer for a cookie set, so the store's cookieAdded
// tells which were taken; a quiet spell after the last is the rest refused.
void Zen::importCookies() {
#ifdef BROWSER_CEF
    // CEF: into the profile's store through CefCookies::set, as ChromeImport's (a host with a leading dot a domain cookie)
    // one the store has already (as SiteData lists it) is kept, so importing again sets none
    auto *sites = qmlEngine(this) ? qmlEngine(this)->singletonInstance<SiteData *>("Browser", "SiteData") : nullptr;
    QList<CefCookies::Set> set;
    int kept = 0;
    for (const QNetworkCookie &c : std::as_const(m_jar)) {
        if (sites && sites->holds(c)) {
            ++kept;
            continue;
        }
        const QNetworkCookie::SameSite policy = c.sameSitePolicy();
        const int same = policy == QNetworkCookie::SameSite::None ? 1 : policy == QNetworkCookie::SameSite::Lax ? 2
                       : policy == QNetworkCookie::SameSite::Strict ? 3 : 0;
        set.append({QString::fromUtf8(c.name()), c.domain(), c.path(), c.value(), c.isSecure(), c.isHttpOnly(), same,
                    c.isSessionCookie() ? 0 : c.expirationDate().toMSecsSinceEpoch()});
    }
    m_jar.clear();
    setState(QStringLiteral("cookies"));
    QPointer<Zen> self(this);
    CefCookies::set(m_target, set, this, [self, kept](int added, int refused) {
        if (!self)
            return;
        emit self->cookiesDone({{QStringLiteral("added"), added}, {QStringLiteral("kept"), kept}, {QStringLiteral("rejected"), refused},
                                {QStringLiteral("skipped"), self->m_jarCounts.value(QStringLiteral("skipped"))},
                                {QStringLiteral("expired"), self->m_jarCounts.value(QStringLiteral("expired"))},
                                {QStringLiteral("sites"), self->m_jarCounts.value(QStringLiteral("sites"))},
                                {QStringLiteral("google"), self->m_jarCounts.value(QStringLiteral("google"))}});
        self->carryOn();
    });
    for (CefCookies::Set &c : set)
        c.value.fill('\0');
#else
    auto *profile = qobject_cast<QQuickWebEngineProfile *>(m_target.data());
    auto *sites = qmlEngine(this) ? qmlEngine(this)->singletonInstance<SiteData *>("Browser", "SiteData") : nullptr;
    m_store = profile ? profile->cookieStore() : nullptr;
    if (!m_store || !sites || sites->store() != m_store) {
        m_jar.clear();
        emit cookiesDone({{QStringLiteral("failure"), QStringLiteral("profile")}});
        carryOn();
        return;
    }
    setState(QStringLiteral("cookies"));
    m_todo.clear();
    m_waiting.clear();
    m_kept = m_accepted = 0;
    m_at = 0;
    const auto key = [](const QNetworkCookie &c) { return QString::fromUtf8(c.name()) + u'\n' + c.domain() + u'\n' + c.path(); };
    for (const QNetworkCookie &c : std::as_const(m_jar)) {
        if (sites->holds(c)) {
            ++m_kept;
        } else {
            m_todo.append(c);
            m_waiting.insert(key(c));
        }
    }
    m_jar.clear();
    if (!m_quiet) {
        m_quiet = new QTimer(this);
        m_quiet->setSingleShot(true);
        m_quiet->setInterval(600);
        connect(m_quiet, &QTimer::timeout, this, &Zen::doneCookies);
    }
    m_added = connect(m_store, &QWebEngineCookieStore::cookieAdded, this, [this, key](const QNetworkCookie &c) {
        if (!m_waiting.remove(key(c)))
            return;
        ++m_accepted;
        if (m_at >= m_todo.size())
            m_waiting.isEmpty() ? doneCookies() : m_quiet->start();
    });
    post();
#endif
}

// 500 at a time, so a profile of tens of thousands does not hold the UI thread
void Zen::post() {
#ifdef BROWSER_CEF
#else
    if (!m_store)
        return;
    const qsizetype to = std::min<qsizetype>(m_at + 500, m_todo.size());
    for (; m_at < to; ++m_at) {
        // a cookie with a domain is a domain cookie to the engine, even one with no dot: Zen's host-only cookies (no leading
        // dot) are set with no domain, from a URL of their host, which is how a Set-Cookie without Domain makes one
        QNetworkCookie cookie = m_todo.at(m_at);
        const QString domain = cookie.domain(), host = domain.startsWith(u'.') ? domain.mid(1) : domain;
        if (!domain.startsWith(u'.'))
            cookie.setDomain(QString());
        m_store->setCookie(cookie, QUrl((cookie.isSecure() ? QStringLiteral("https://") : QStringLiteral("http://"))
                                        + (host.contains(u':') ? u'[' + host + u']' : host) + u'/'));
    }
    if (m_at < m_todo.size())
        QTimer::singleShot(0, this, &Zen::post);
    else if (m_waiting.isEmpty())
        doneCookies();
    else
        m_quiet->start();
#endif
}

void Zen::doneCookies() {
#ifdef BROWSER_CEF
#else
    if (!m_store && m_todo.isEmpty())
        return;
    disconnect(m_added);
    m_quiet->stop();
    const int total = int(m_todo.size());
    m_todo.clear();
    m_waiting.clear();
    m_store = nullptr;
    emit cookiesDone({{QStringLiteral("added"), m_accepted}, {QStringLiteral("kept"), m_kept}, {QStringLiteral("rejected"), total - m_accepted},
                      {QStringLiteral("skipped"), m_jarCounts.value(QStringLiteral("skipped"))}, {QStringLiteral("expired"), m_jarCounts.value(QStringLiteral("expired"))},
                      {QStringLiteral("sites"), m_jarCounts.value(QStringLiteral("sites"))},
                      {QStringLiteral("google"), m_jarCounts.value(QStringLiteral("google"))}});
    carryOn();
#endif
}

void Zen::unlock(const QString &primary) {
    if (m_state == u"password" && !primary.isEmpty())
        decrypt(primary);
}

void Zen::skip() {
    if (m_state == u"password")
        finish({{QStringLiteral("added"), 0}, {QStringLiteral("kept"), 0}, {QStringLiteral("skipped"), QStringLiteral("not given")}});
}

// While the primary password or decrypted logins are in this process (until the keyring has them): no core dump, which
// systemd-coredump would keep with them in it (as this machine has it: core_pattern its pipe, RLIMIT_CORE unlimited).
// Put back as it was after.
void Zen::guard(bool on) {
    if (on == m_guarded)
        return;
    m_guarded = on;
    if (on) {
        m_dumpable = ::prctl(PR_GET_DUMPABLE);
        ::getrlimit(RLIMIT_CORE, &m_core);
        const rlimit none{0, m_core.rlim_max};
        ::setrlimit(RLIMIT_CORE, &none);
        ::prctl(PR_SET_DUMPABLE, 0);
    } else {
        ::prctl(PR_SET_DUMPABLE, m_dumpable);
        ::setrlimit(RLIMIT_CORE, &m_core);
    }
}

// The helper decrypts the copy's logins and hands them back over its stdout, which only this process reads; its stderr
// goes nowhere. The primary password goes over its stdin, never its command line. With no keyring to take them they are
// not decrypted at all.
void Zen::decrypt(const QString &primary) {
    auto *keyring = qmlEngine(this) ? qmlEngine(this)->singletonInstance<Passwords *>("Browser", "Passwords") : nullptr;
    if (!keyring || keyring->state() == u"none") {
        finish({{QStringLiteral("added"), 0}, {QStringLiteral("kept"), 0}, {QStringLiteral("skipped"), QStringLiteral("none")}});
        return;
    }
    guard(true);
    setState(QStringLiteral("saving"));
    auto *helper = new QProcess;
    m_helper.reset(helper);
    helper->setProgram(QCoreApplication::applicationFilePath());
    helper->setArguments({QStringLiteral("--zen-nss"), QStringLiteral("decrypt"), m_copy->path()});
    helper->setStandardErrorFile(QProcess::nullDevice());
    const bool given = !primary.isEmpty();
    connect(helper, &QProcess::finished, this, [this, helper, given](int code, QProcess::ExitStatus status) {
        QByteArray out = helper->readAllStandardOutput();
        m_helper.release();
        helper->deleteLater();
        const QJsonObject answer = QJsonDocument::fromJson(out).object();
        out.fill(0);
        const QString state = answer.value(QStringLiteral("state")).toString();
        if (state == u"locked" || state == u"wrong") {
            guard(false);
            setState(QStringLiteral("password"), given);
            return;
        }
        auto *store = qmlEngine(this) ? qmlEngine(this)->singletonInstance<Passwords *>("Browser", "Passwords") : nullptr;
        if (status != QProcess::NormalExit || code != 0 || state != u"ok" || !store) {
            finish({{QStringLiteral("added"), 0}, {QStringLiteral("kept"), 0}, {QStringLiteral("skipped"), QStringLiteral("failed")}});
            return;
        }
        // the logins NSS could not open (another key, a damaged record): the rest go in, and Settings says how many did not
        const int unopened = answer.value(QStringLiteral("failed")).toInt();
        QList<Passwords::Login> logins;
        for (const QJsonValue &v : answer.value(QStringLiteral("logins")).toArray()) {
            const QJsonObject o = v.toObject();
            logins.append({o.value(QStringLiteral("origin")).toString(), o.value(QStringLiteral("user")).toString(),
                           o.value(QStringLiteral("password")).toString().toUtf8()});
        }
        const QPointer<Zen> self(this);
        store->importLogins(std::move(logins), [self, unopened](int added, int kept, int left, const QString &failure) {
            if (self)
                self->finish({{QStringLiteral("added"), added}, {QStringLiteral("kept"), kept}, {QStringLiteral("left"), left},
                              {QStringLiteral("unopened"), unopened}, {QStringLiteral("skipped"), failure}});
        });
    });
    connect(helper, &QProcess::errorOccurred, this, [this, helper](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_helper.release();
        helper->deleteLater();
        finish({{QStringLiteral("added"), 0}, {QStringLiteral("kept"), 0}, {QStringLiteral("skipped"), QStringLiteral("failed")}});
    });
    helper->start();
    helper->write(primary.toUtf8() + '\n');
    helper->closeWriteChannel();
}

void Zen::finish(const QVariantMap &result) {
    m_copy.reset();
    guard(false);
    setState(QString());
    emit saved(result);
}

// ---- the NSS helper (`browser --zen-nss`), its own process ----

namespace {
namespace nss {
// NSS's types as its headers declare them (seccomon.h, pk11sdr.h): SECStatus 0 is SECSuccess, PRBool an int
struct Item {
    int type = 0;
    unsigned char *data = nullptr;
    unsigned int len = 0;
};
using Slot = void;
constexpr unsigned readOnly = 0x1, noModuleDb = 0x4, noRootInit = 0x10;   // NSS_INIT_*
constexpr unsigned long aesCbc = 0x1082, des3Cbc = 0x133;                  // CKM_AES_CBC, CKM_DES3_CBC

// libnss3 as the system has it, loaded when the helper runs (nothing of NSS is linked at build time)
struct Api {
    int (*initialize)(const char *, const char *, const char *, const char *, unsigned) = nullptr;
    int (*shutdown)() = nullptr;
    Slot *(*keySlot)() = nullptr;
    void (*freeSlot)(Slot *) = nullptr;
    int (*needLogin)(Slot *) = nullptr;
    int (*needUserInit)(Slot *) = nullptr;
    int (*checkPassword)(Slot *, const char *) = nullptr;
    int (*initPin)(Slot *, const char *, const char *) = nullptr;
    int (*encrypt)(Slot *, Item *, unsigned long, Item *, Item *, void *) = nullptr;
    int (*decrypt)(Item *, Item *, void *) = nullptr;
    void (*freeItem)(Item *, int) = nullptr;
    template <typename F> static bool get(void *lib, const char *name, F &f) {
        f = reinterpret_cast<F>(dlsym(lib, name));
        return f != nullptr;
    }
    bool load() {
        void *lib = dlopen("libnss3.so", RTLD_NOW | RTLD_GLOBAL);
        return lib && get(lib, "NSS_Initialize", initialize) && get(lib, "NSS_Shutdown", shutdown)
            && get(lib, "PK11_GetInternalKeySlot", keySlot) && get(lib, "PK11_FreeSlot", freeSlot) && get(lib, "PK11_NeedLogin", needLogin)
            && get(lib, "PK11_NeedUserInit", needUserInit) && get(lib, "PK11_CheckUserPassword", checkPassword)
            && get(lib, "PK11_InitPin", initPin) && get(lib, "PK11SDR_EncryptWithMechanism", encrypt) && get(lib, "PK11SDR_Decrypt", decrypt)
            && get(lib, "SECITEM_ZfreeItem", freeItem);
    }
};

void answer(const QJsonObject &o) {
    QByteArray out = QJsonDocument(o).toJson(QJsonDocument::Compact);
    std::fwrite(out.constData(), 1, size_t(out.size()), stdout);
    std::fflush(stdout);
    out.fill(0);
}

// One of logins.json's encrypted fields (base64 of NSS's SDR record): its text, or false when it did not open
bool open(const Api &api, const QString &field, QString &plain) {
    QByteArray der = QByteArray::fromBase64(field.toLatin1());
    Item in{0, reinterpret_cast<unsigned char *>(der.data()), unsigned(der.size())}, out;
    if (der.isEmpty() || api.decrypt(&in, &out, nullptr) != 0)
        return false;
    plain = QString::fromUtf8(reinterpret_cast<const char *>(out.data), int(out.len));
    api.freeItem(&out, 0);
    return true;
}

// --check-engine: logins.json and key4.db for a Zen profile made up in `dir`, with NSS's own encryption (AES, or 3DES
// as Firefox's older records have it), under `primary` ("" for none). Stdin: { primary, logins: [{ hostname, username,
// password, realm, des3, damaged }] }.
int encrypt(const Api &api, const QString &dir) {
    // only into a folder with no key database or logins of its own: this never writes over a real profile's
    for (const char *name : {"key4.db", "logins.json", "cert9.db"})
        if (QFileInfo::exists(dir + u'/' + QLatin1String(name)))
            return 1;
    std::string in((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
    const QJsonObject spec = QJsonDocument::fromJson(QByteArray::fromStdString(in)).object();
    const QByteArray primary = spec.value(QStringLiteral("primary")).toString().toUtf8();
    if (api.initialize(("sql:" + QFile::encodeName(dir)).constData(), "", "", "secmod.db", noModuleDb | noRootInit) != 0)
        return 1;
    Slot *slot = api.keySlot();
    if (!slot || (api.needUserInit(slot) && api.initPin(slot, nullptr, primary.constData()) != 0)
        || (!primary.isEmpty() && api.checkPassword(slot, primary.constData()) != 0))
        return 1;
    QJsonArray logins;
    int id = 0;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (const QJsonValue &v : spec.value(QStringLiteral("logins")).toArray()) {
        const QJsonObject l = v.toObject();
        const auto seal = [&](const QString &plain) {
            QByteArray bytes = plain.toUtf8();
            Item keyid, data{0, reinterpret_cast<unsigned char *>(bytes.data()), unsigned(bytes.size())}, out;
            if (api.encrypt(slot, &keyid, l.value(QStringLiteral("des3")).toBool() ? des3Cbc : aesCbc, &data, &out, nullptr) != 0)
                return QString();
            const QString sealed = QString::fromLatin1(QByteArray(reinterpret_cast<const char *>(out.data), int(out.len)).toBase64());
            api.freeItem(&out, 0);
            return sealed;
        };
        const QString host = l.value(QStringLiteral("hostname")).toString(), realm = l.value(QStringLiteral("realm")).toString();
        const QString user = seal(l.value(QStringLiteral("username")).toString());
        // `damaged`: a password record NSS cannot open, as one made under another key or cut short
        const QString password = l.value(QStringLiteral("damaged")).toBool() ? QString::fromLatin1(QByteArray("no SDR record").toBase64())
                                                                             : seal(l.value(QStringLiteral("password")).toString());
        if (user.isEmpty() || password.isEmpty())
            return 1;
        logins.append(QJsonObject{
            {QStringLiteral("id"), ++id}, {QStringLiteral("hostname"), host},
            {QStringLiteral("httpRealm"), realm.isEmpty() ? QJsonValue() : QJsonValue(realm)},
            {QStringLiteral("formSubmitURL"), realm.isEmpty() ? QJsonValue(host) : QJsonValue()},
            {QStringLiteral("usernameField"), QStringLiteral("login")}, {QStringLiteral("passwordField"), QStringLiteral("password")},
            {QStringLiteral("encryptedUsername"), user}, {QStringLiteral("encryptedPassword"), password},
            {QStringLiteral("guid"), QStringLiteral("{check-%1}").arg(id)}, {QStringLiteral("encType"), 1},
            {QStringLiteral("timeCreated"), now}, {QStringLiteral("timeLastUsed"), now}, {QStringLiteral("timePasswordChanged"), now},
            {QStringLiteral("timesUsed"), 1}});
    }
    api.freeSlot(slot);
    QFile file(dir + QStringLiteral("/logins.json"));
    const bool written = file.open(QIODevice::WriteOnly)
        && file.write(QJsonDocument(QJsonObject{{QStringLiteral("nextId"), id + 1}, {QStringLiteral("logins"), logins},
                                                {QStringLiteral("potentiallyVulnerablePasswords"), QJsonArray()},
                                                {QStringLiteral("dismissedBreachAlertsByLoginGUID"), QJsonObject()},
                                                {QStringLiteral("version"), 3}}).toJson()) > 0;
    file.close();
    return api.shutdown() == 0 && written ? 0 : 1;
}
}
}

// `browser --zen-nss <mode> <dir>`, on a copy of a Zen profile (or, for encrypt, a folder of the check's):
//   probe    { logins, primary }: how many logins the browser can use and whether a primary password locks them;
//            nothing is decrypted
//   decrypt  the primary password on stdin's first line ("" for none); { state: "ok", logins: [{ origin, user,
//            password }], failed }, or { state: "locked" } (a primary password, none given), "wrong" or "failed";
//            only on the import's copy (below)
//   encrypt  see nss::encrypt
// NSS opens the copy read-only, with no module database and no root certificates.
int Zen::nssHelper(int argc, char *argv[]) {
    // it holds every login in the clear and the primary password: no core dump of it, which systemd-coredump would keep
    ::prctl(PR_SET_DUMPABLE, 0);
    const rlimit none{0, 0};
    ::setrlimit(RLIMIT_CORE, &none);
    const QByteArray mode = argc > 3 ? QByteArray(argv[2]) : QByteArray();
    const QString dir = argc > 3 ? QFile::decodeName(argv[3]) : QString();
    nss::Api api;
    if (dir.isEmpty() || !api.load()) {
        nss::answer({{QStringLiteral("state"), QStringLiteral("failed")}});
        return 1;
    }
    if (mode == "encrypt")
        return nss::encrypt(api, dir);
    // decrypt opens only the copy its own browser made for an import (Zen::start: browser-zen-<that browser's pid>-…
    // in the temp dir), never a profile or a copy left lying about, so no one runs it by hand on those. A process of
    // this user can open NSS itself; this keeps the browser from being the tool that prints the logins.
    if (mode == "decrypt") {
        const QFileInfo folder(dir);
        if (!folder.fileName().startsWith(QStringLiteral("browser-zen-%1-").arg(::getppid())) || folder.isSymLink() || !folder.isDir()
            || folder.ownerId() != ::getuid() || folder.absoluteDir().canonicalPath() != QDir(QDir::tempPath()).canonicalPath()) {
            nss::answer({{QStringLiteral("state"), QStringLiteral("failed")}});
            return 1;
        }
    }
    std::string primary;
    if (mode == "decrypt")
        std::getline(std::cin, primary);
    const QJsonArray logins = loginsOf(dir + QStringLiteral("/logins.json"));
    nss::Slot *slot = nullptr;
    if (api.initialize(("sql:" + QFile::encodeName(dir)).constData(), "", "", "secmod.db", nss::readOnly | nss::noModuleDb | nss::noRootInit) != 0
        || !(slot = api.keySlot())) {
        nss::answer({{QStringLiteral("state"), QStringLiteral("failed")}});
        return 1;
    }
    // a key database with an empty password asks for a login that "" passes
    const bool locked = api.needLogin(slot) && api.checkPassword(slot, "") != 0;
    int code = 0;
    if (mode == "probe") {
        nss::answer({{QStringLiteral("logins"), logins.size()}, {QStringLiteral("primary"), locked}});
    } else if (mode != "decrypt") {
        code = 2;
    } else if (locked && (primary.empty() || api.checkPassword(slot, primary.c_str()) != 0)) {
        nss::answer({{QStringLiteral("state"), primary.empty() ? QStringLiteral("locked") : QStringLiteral("wrong")}});
    } else {
        QJsonArray out;
        int failed = 0;
        for (const QJsonValue &v : logins) {
            const QJsonObject l = v.toObject();
            QString user, password;
            if (!nss::open(api, l.value(QStringLiteral("encryptedUsername")).toString(), user)
                || !nss::open(api, l.value(QStringLiteral("encryptedPassword")).toString(), password)) {
                ++failed;
                continue;
            }
            out.append(QJsonObject{{QStringLiteral("origin"), l.value(QStringLiteral("hostname")).toString().toLower()},
                                   {QStringLiteral("user"), user}, {QStringLiteral("password"), password}});
        }
        nss::answer({{QStringLiteral("state"), QStringLiteral("ok")}, {QStringLiteral("logins"), out}, {QStringLiteral("failed"), failed}});
    }
    std::fill(primary.begin(), primary.end(), '\0');
    api.freeSlot(slot);
    api.shutdown();
    return code;
}
