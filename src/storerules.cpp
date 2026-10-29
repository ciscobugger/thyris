#include "storerules.h"

#include <QJsonArray>
#include <algorithm>
#include <functional>
#include <QMap>
#include <QRegularExpression>
#include <QSet>
#include <QXmlStreamReader>

bool StoreRules::validId(const QString &id) {
    static const QRegularExpression plain(QStringLiteral("^[a-p]{32}$"));
    return plain.match(id).hasMatch();
}

QString StoreRules::itemId(const QUrl &page) {
    if (page.scheme() != u"https" || !page.userInfo().isEmpty() || (page.port() != -1 && page.port() != 443))
        return {};
    static const QRegularExpression current(QStringLiteral("^/detail/(?!\\.\\.?/)[^/]+/([a-p]{32})/?$"));
    static const QRegularExpression old(QStringLiteral("^/webstore/detail/(?!\\.\\.?/)[^/]+/([a-p]{32})/?$"));
    const QString path = page.path(QUrl::FullyEncoded);
    QRegularExpressionMatch m;
    if (page.host() == u"chromewebstore.google.com")
        m = current.match(path);
    else if (page.host() == u"chrome.google.com")
        m = old.match(path);
    return m.hasMatch() ? m.captured(1) : QString();
}

bool StoreRules::googleAddress(const QUrl &url) {
    if (!url.isValid() || url.scheme() != u"https" || !url.userInfo().isEmpty() || (url.port() != -1 && url.port() != 443))
        return false;
    const QString host = url.host(QUrl::FullyEncoded);      // lower case, punycode for non-ASCII names
    // Only the update service, its file host and Google's download hosts: other Google hosts (sites, docs, drive) hold
    // content anyone can put there.
    if (host == u"clients2.google.com" || host == u"clients2.googleusercontent.com")
        return true;
    const QLatin1String suffix(".gvt1.com");
    return host.endsWith(suffix) && host.size() > suffix.size();
}

QUrl StoreRules::nextHop(const QUrl &from, const QString &location) {
    if (location.isEmpty())
        return {};
    const QUrl to = from.resolved(QUrl(location, QUrl::StrictMode));
    return googleAddress(to) ? to : QUrl();
}

static bool plainVersion(const QString &v) {
    static const QRegularExpression plain(QStringLiteral("^[0-9]{1,9}(\\.[0-9]{1,9}){0,5}$"));
    return plain.match(v).hasMatch();
}

static QUrl updateUrl(const QString &query) {
    return QUrl::fromEncoded(QByteArray("https://clients2.google.com/service/update2/crx?") + query.toLatin1(), QUrl::StrictMode);
}

QUrl StoreRules::fileUrl(const QString &id, const QString &prodVersion) {
    if (!validId(id) || !plainVersion(prodVersion))
        return {};
    const QString x = QString::fromLatin1(QUrl::toPercentEncoding(QStringLiteral("id=%1&installsource=ondemand&uc").arg(id)));
    return updateUrl(QStringLiteral("response=redirect&prodversion=%1&acceptformat=crx3&x=%2").arg(prodVersion, x));
}

QUrl StoreRules::updateCheckUrl(const QString &id, const QString &prodVersion, const QString &haveVersion) {
    if (!validId(id) || !plainVersion(prodVersion) || haveVersion.size() > 64 || haveVersion.contains(QRegularExpression(QStringLiteral("[^0-9A-Za-z._-]"))))
        return {};
    const QString x = QString::fromLatin1(QUrl::toPercentEncoding(QStringLiteral("id=%1&v=%2&uc").arg(id, haveVersion)));
    return updateUrl(QStringLiteral("prodversion=%1&acceptformat=crx3&x=%2").arg(prodVersion, x));
}

bool StoreRules::versionNewer(const QString &a, const QString &b) {
    const QStringList x = a.split(u'.'), y = b.split(u'.');
    for (qsizetype i = 0; i < qMax(x.size(), y.size()); ++i) {
        const qint64 p = i < x.size() ? x.at(i).toLongLong() : 0, q = i < y.size() ? y.at(i).toLongLong() : 0;
        if (p != q)
            return p > q;
    }
    return false;
}

StoreRules::UpdateAnswer StoreRules::parseUpdateCheck(const QByteArray &xml, const QString &id, const QString &haveVersion) {
    UpdateAnswer out;
    QXmlStreamReader r(xml);
    bool mine = false;
    while (!r.atEnd()) {
        if (r.readNext() != QXmlStreamReader::StartElement)
            continue;
        if (r.name() == u"app") {
            mine = r.attributes().value(u"appid") == id;
        } else if (r.name() == u"updatecheck" && mine) {
            const QString status = r.attributes().value(u"status").toString();
            if (status == u"noupdate") {
                out.ok = true;
                return out;
            }
            const QString version = r.attributes().value(u"version").toString();
            const QUrl file(r.attributes().value(u"codebase").toString(), QUrl::StrictMode);
            if (status != u"ok" || !plainVersion(version) || !googleAddress(file))
                return out;
            out.ok = true;
            out.version = version;
            out.file = file;
            out.sha256 = r.attributes().value(u"hash_sha256").toString().toLower();
            out.newer = versionNewer(version, haveVersion);
            return out;
        }
    }
    return out;
}

namespace {

// What a permission lets an extension do. Rank orders the lines, the most far-reaching first.
struct Word {
    int rank;
    const char *text;
};
const QMap<QString, Word> &permissionTable() {
    static const QMap<QString, Word> table{
        {QStringLiteral("debugger"), {10, "Read and change everything on any page, like a developer"}},
        {QStringLiteral("history"), {20, "See your browsing history"}},
        {QStringLiteral("tabs"), {21, "See the addresses and titles of your open pages"}},
        {QStringLiteral("sessions"), {22, "See your recently closed pages"}},
        {QStringLiteral("topSites"), {23, "See the sites you visit most"}},
        {QStringLiteral("cookies"), {24, "Read and change the cookies sites keep, which can hold sign-ins"}},
        {QStringLiteral("webRequest"), {25, "See the requests your pages make"}},
        {QStringLiteral("declarativeNetRequest"), {26, "Block things on pages"}},
        {QStringLiteral("declarativeNetRequestWithHostAccess"), {26, "Block things on pages"}},
        {QStringLiteral("declarativeNetRequestFeedback"), {27, "See what it blocked"}},
        {QStringLiteral("webNavigation"), {28, "See where your pages go as they load"}},
        {QStringLiteral("nativeMessaging"), {30, "Talk to programs on your computer"}},
        {QStringLiteral("management"), {31, "See and manage your other extensions"}},
        {QStringLiteral("proxy"), {32, "Control how Thyris connects to the internet"}},
        {QStringLiteral("privacy"), {33, "Change privacy settings"}},
        {QStringLiteral("contentSettings"), {34, "Change what sites are allowed to do"}},
        {QStringLiteral("browsingData"), {35, "Clear your browsing data"}},
        {QStringLiteral("bookmarks"), {36, "See and change your bookmarks"}},
        {QStringLiteral("downloads"), {37, "Download files and see what you downloaded"}},
        {QStringLiteral("desktopCapture"), {40, "Record your screen"}},
        {QStringLiteral("tabCapture"), {41, "Record the page you are on"}},
        {QStringLiteral("pageCapture"), {42, "Save pages as files"}},
        {QStringLiteral("geolocation"), {43, "Know your location"}},
        {QStringLiteral("clipboardRead"), {44, "See what you copy"}},
        {QStringLiteral("clipboardWrite"), {45, "Put things on your clipboard"}},
        {QStringLiteral("identity"), {46, "Sign in with your Google account"}},
        {QStringLiteral("notifications"), {47, "Show notifications"}},
        {QStringLiteral("system.cpu"), {50, "See what your computer is made of"}},
        {QStringLiteral("system.memory"), {50, "See what your computer is made of"}},
        {QStringLiteral("system.storage"), {50, "See what your computer is made of"}},
        {QStringLiteral("system.display"), {50, "See what your computer is made of"}},
        {QStringLiteral("idle"), {51, "Know when you are away from the computer"}},
        {QStringLiteral("power"), {52, "Keep the computer awake"}},
        {QStringLiteral("activeTab"), {60, "Use the page you are on when you press its button"}},
    };
    return table;
}

struct Pattern {
    QString scheme, host, path;     // host keeps a leading "*." ; "*" is every host
};

// Permissions that give an extension no reach over the person's pages or data: not worth a line, and not "new" either.
const QSet<QString> &quietPermissions() {
    static const QSet<QString> quiet{QStringLiteral("storage"), QStringLiteral("unlimitedStorage"), QStringLiteral("alarms"),
                                     QStringLiteral("scripting"), QStringLiteral("contextMenus"), QStringLiteral("fontSettings"),
                                     QStringLiteral("tts"), QStringLiteral("ttsEngine")};
    return quiet;
}

struct Grants {
    bool everySite = false;
    bool files = false;
    QList<Pattern> sites;
    QSet<QString> perms;        // every permission name, listed in the table or not
    QSet<QString> other;        // externally_connectable ids, other reach: any entry not seen before is new
    bool otherNew = false;      // set for the words of what an update adds
};

bool parsePattern(const QString &pattern, Pattern *out) {
    if (pattern == u"<all_urls>") {
        *out = {QStringLiteral("*"), QStringLiteral("*"), QStringLiteral("/*")};
        return true;
    }
    static const QRegularExpression parts(QStringLiteral("^(\\*|https?|ftp|file|wss?|ws)://([^/]*)(/.*)?$"));
    const auto m = parts.match(pattern);
    if (!m.hasMatch())
        return false;
    *out = {m.captured(1), m.captured(2).toLower(), m.captured(3).isEmpty() ? QStringLiteral("/*") : m.captured(3)};
    return true;
}

bool schemeCovers(const QString &have, const QString &want) {
    return have == want || (have == u"*" && (want == u"http" || want == u"https" || want == u"*"));
}

// Does a grant of `have` already allow everything `want` allows (scheme, host with its subdomains, path)?
bool covers(const Pattern &have, const Pattern &want) {
    if (have.scheme == u"*" && have.host == u"*" && have.path == u"/*" && want.scheme != u"file")
        return true;        // <all_urls>
    if (!schemeCovers(have.scheme, want.scheme))
        return false;
    bool hostOk = have.host == want.host || have.host == u"*";
    if (!hostOk && have.host.startsWith(u"*.")) {
        const QString base = have.host.mid(2);
        hostOk = want.host == base || want.host.endsWith(u'.' + base);      // also covers "*.sub.base"
    }
    return hostOk && (have.path == u"/*" || have.path == want.path);
}

void addPattern(Grants &g, const QString &pattern) {
    Pattern p;
    if (!parsePattern(pattern, &p))
        return;
    if (p.scheme == u"file") {
        g.files = true;
        return;
    }
    if (p.host == u"*")
        g.everySite = true;
    g.sites << p;
}

QString siteName(const Pattern &p) {
    return p.host.startsWith(u"*.") ? p.host.mid(2) : p.host;
}

void addStrings(const QJsonValue &v, const std::function<void(const QString &)> &each) {
    for (const QJsonValue &x : v.toArray())
        if (x.isString())
            each(x.toString());
}

Grants grantsOf(const QJsonObject &manifest) {
    Grants g;
    const auto host = [&g](const QString &p) { addPattern(g, p); };
    // the optional lists are what the extension may ask for later: counted as asked for now
    for (const char *key : {"host_permissions", "optional_host_permissions"})
        addStrings(manifest.value(QLatin1String(key)), host);
    for (const char *key : {"permissions", "optional_permissions"})
        addStrings(manifest.value(QLatin1String(key)), [&g](const QString &p) {
            if (p.contains(u"://") || p == u"<all_urls>")
                addPattern(g, p);
            else
                g.perms.insert(p);
        });
    for (const QJsonValue &c : manifest.value(QStringLiteral("content_scripts")).toArray())
        addStrings(c.toObject().value(QStringLiteral("matches")), host);
    // who else may talk to it
    const QJsonObject ext = manifest.value(QStringLiteral("externally_connectable")).toObject();
    addStrings(ext.value(QStringLiteral("ids")), [&g](const QString &i) { g.other << QStringLiteral("ec-id:") + i; });
    addStrings(ext.value(QStringLiteral("matches")), [&g](const QString &i) { g.other << QStringLiteral("ec-match:") + i; });
    // pages that can load its files
    for (const QJsonValue &w : manifest.value(QStringLiteral("web_accessible_resources")).toArray()) {
        const QJsonObject o = w.toObject();
        addStrings(o.value(QStringLiteral("matches")), [&g](const QString &i) { g.other << QStringLiteral("war-match:") + i; });
        addStrings(o.value(QStringLiteral("extension_ids")), [&g](const QString &i) { g.other << QStringLiteral("war-id:") + i; });
        if (o.value(QStringLiteral("use_dynamic_url")).toBool())
            g.other << QStringLiteral("war-dynamic");
    }
    return g;
}

QStringList wordsOf(const Grants &g) {
    QStringList out;
    if (g.everySite) {
        out << QObject::tr("Read and change the pages you visit, on every site");
    } else if (!g.sites.isEmpty()) {
        QSet<QString> names;
        for (const Pattern &p : g.sites)
            names.insert(siteName(p));
        QStringList hosts = names.values();
        hosts.sort();
        if (hosts.size() <= 2)
            out << QObject::tr("Read and change your data on %1").arg(hosts.join(QObject::tr(" and ")));
        else
            out << QObject::tr("Read and change your data on %1, %2 and %3").arg(hosts.at(0), hosts.at(1),
                                                                                  hosts.size() == 3 ? QObject::tr("1 other site") : QObject::tr("%1 other sites").arg(hosts.size() - 2));
    }
    if (g.files)
        out << QObject::tr("Read files on your computer that you open in Thyris");
    QMap<QPair<int, QString>, QString> byRank;
    bool unlisted = false;
    for (const QString &p : g.perms) {
        if (permissionTable().contains(p))
            byRank.insert({permissionTable().value(p).rank, p}, QString::fromUtf8(permissionTable().value(p).text));
        else if (!quietPermissions().contains(p))
            unlisted = true;
    }
    // two permissions can say the same thing (the system ones): once
    for (const QString &line : std::as_const(byRank))
        if (!out.contains(line))
            out << line;
    if (unlisted)
        out << QObject::tr("Use other abilities of Thyris that are not listed here");
    if (g.otherNew)
        out << QObject::tr("Let other extensions or sites it names talk to it");
    return out;
}

}

QStringList StoreRules::permissionWords(const QJsonObject &manifest) {
    return wordsOf(grantsOf(manifest));
}

QStringList StoreRules::addedWords(const QJsonObject &before, const QJsonObject &now) {
    const Grants had = grantsOf(before);
    Grants more = grantsOf(now);
    // a site is new unless an earlier grant already covered its scheme, host (with subdomains) and path
    QList<Pattern> sites;
    for (const Pattern &p : std::as_const(more.sites)) {
        bool seen = false;
        for (const Pattern &h : had.sites)
            seen = seen || covers(h, p);
        if (!seen)
            sites << p;
    }
    more.sites = sites;
    more.everySite = std::any_of(sites.cbegin(), sites.cend(), [](const Pattern &p) { return p.host == u"*"; });
    more.files = more.files && !had.files;
    more.perms.subtract(had.perms);
    more.other.subtract(had.other);
    more.otherNew = !more.other.isEmpty();
    QStringList out = wordsOf(more);
    return out;
}
