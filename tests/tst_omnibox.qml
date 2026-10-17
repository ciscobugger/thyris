import QtQuick
import QtTest
import Browser
import "../qml"

// Omnibox.qml: what typed text means, and the suggestion rows for it.
TestCase {
    name: "Omnibox"

    Component { id: sessionComponent; Session {} }
    Component { id: historyComponent; History {} }
    Component { id: omniComponent; Omnibox {} }

    property var session
    property var history
    property var omni

    function init() {
        Store.files = {};
        session = createTemporaryObject(sessionComponent, this);
        history = createTemporaryObject(historyComponent, this);
        omni = createTemporaryObject(omniComponent, this, { session: session, history: history });
    }

    function test_looksLikeUrl_data() {
        return [
            { tag: "domain", text: "github.com", url: true },
            { tag: "domain and path", text: "github.com/linux-msm/linux/issues/212", url: true },
            { tag: "subdomain", text: "lore.kernel.org", url: true },
            { tag: "swedish domain", text: "skatteverket.se", url: true },
            { tag: "IDN", text: "räksmörgås.se", url: true },
            { tag: "scheme", text: "https://example.org", url: true },
            { tag: "localhost with port", text: "localhost:8080", url: true },
            { tag: "IPv4", text: "192.168.1.1", url: true },
            { tag: "about", text: "about:blank", url: true },
            { tag: "file", text: "file:///home/abdul/x.pdf", url: true },
            { tag: "two words", text: "libcamera agc", url: false },
            { tag: "one word", text: "libcamera", url: false },
            { tag: "file name", text: "agc.c", url: false },
            { tag: "domain then a word", text: "github.com issues", url: false },
        ];
    }
    function test_looksLikeUrl(data) {
        compare(omni.looksLikeUrl(data.text), data.url);
    }

    function test_toUrl() {
        compare(omni.toUrl("github.com"), "https://github.com");
        compare(omni.toUrl("localhost:8080"), "http://localhost:8080");
        compare(omni.toUrl("plain.test:8123/login"), "https://plain.test:8123/login", "a host and port, not a scheme");
        compare(omni.toUrl("mailto:abdul@example.org"), "mailto:abdul@example.org");
        compare(omni.toUrl("192.168.1.1/admin"), "http://192.168.1.1/admin");
        compare(omni.toUrl("https://example.org/"), "https://example.org/");
        compare(omni.toUrl("about:blank"), "about:blank");
    }

    function test_hostAndSplit() {
        compare(omni.hostOf("https://www.github.com/linux-msm"), "github.com");
        compare(omni.hostOf("not a url"), "not a url");
        // an address without a host is named as the address card names it (PLAN.md 3.17): a new thread's title
        compare(omni.hostOf("data:text/html,%3Cp%3Esecret"), "data: page · 9 B");
        compare(omni.hostOf("file:///home/abdul/S2MM006.pdf"), "File");
        compare(omni.split("https://github.com/linux-msm/linux/issues/212?tab=1#c3"),
                { host: "github.com", path: "/linux-msm/linux/issues/212" });
        compare(omni.split("https://example.org/"), { host: "example.org", path: "" });
        compare(omni.split("about:blank"), { host: "about:blank", path: "" });
        // user:pass@ can pose as the host
        compare(omni.split("https://accounts.google.com.x@evil.example/login"), { host: "evil.example", path: "/login" });
        compare(omni.hostOf("https://bank.com:x@evil.example/"), "evil.example");
    }

    function test_emptyTextSuggestsNothing() {
        compare(omni.suggest("", ""), []);
    }

    function test_firstRowIsWhatEnterDoes() {
        const search = omni.suggest("libcamera agc", "")[0];
        compare(search.kind, "go");
        compare(search.url, "https://duckduckgo.com/?q=libcamera%20agc");
        compare(search.detail, "DuckDuckGo");
        const go = omni.suggest("github.com", "")[0];
        compare(go.kind, "go");
        compare(go.url, "https://github.com");
        compare(go.name, "github.com");
    }

    // PLAN.md 3.8: a typed address tries https first and carries the plain http it falls back to
    function test_goRowTriesHttpsFirst() {
        const bare = omni.suggest("neverssl.com", "")[0];
        compare(bare.url, "https://neverssl.com");
        compare(bare.fallback, "http://neverssl.com");
        const http = omni.suggest("http://neverssl.com/online", "")[0];
        compare(http.title, "http://neverssl.com/online", "the row reads what was typed");
        compare(http.url, "https://neverssl.com/online");
        compare(http.fallback, "http://neverssl.com/online");
        compare(omni.suggest("https://expired.badssl.com", "")[0].fallback, "");
        compare(omni.suggest("localhost:8080", "")[0].url, "http://localhost:8080");
        compare(omni.suggest("libcamera agc", "")[0].fallback, undefined, "a search has none");
    }

    // Settings (PLAN.md 3.15): the search engine named in row 1, and https-first Off loading an http:// address as typed
    function test_settingsEngineAndHttpsFirst() {
        omni.engine = "Google";
        omni.searchTemplate = "https://www.google.com/search?q=%s";
        const search = omni.suggest("libcamera agc", "")[0];
        compare(search.url, "https://www.google.com/search?q=libcamera%20agc");
        compare(search.detail, "Google");
        omni.httpsFirst = false;
        const http = omni.suggest("http://neverssl.com/online", "")[0];
        compare(http.url, "http://neverssl.com/online");
        compare(http.fallback, "");
        compare(omni.suggest("neverssl.com", "")[0].fallback, "http://neverssl.com", "a bare name still tries https first");
        compare(omni.suggest("browser://settings", "")[0].url, "browser://settings", "the browser's own pages as typed");
    }

    function test_openPagesAndEarlierThreads() {
        const cam = session.newThread("x1p42100 camera");
        const here = session.addPage(cam, "https://github.com/linux-msm/linux/issues/212", "");
        session.update(here, { title: "camss: CSIPHY0 lanes ignored" });
        const other = session.addPage(cam, "https://lists.libcamera.org/", "");
        session.update(other, { title: "Re: softisp AGC starves on GPU" });
        const zen = session.newThread("Camera dark in Zen");
        session.addPage(zen, "https://bugzilla.mozilla.org/", "");
        session.threadById(zen).earlier = true;

        const rows = omni.suggest("camera", here);
        compare(rows.map(r => r.kind), ["go", "page", "earlier"]);
        compare(rows[1].pageId, other, "matches the URL; the current page is left out");
        compare(rows[2].threadId, zen);
    }

    function test_historySkipsOpenPages() {
        const t = session.newThread("t");
        session.addPage(t, "https://git.libcamera.org/agc.cpp", "");
        history.entries = {
            "https://git.libcamera.org/agc.cpp": { url: "https://git.libcamera.org/agc.cpp", title: "agc.cpp - libcamera", visits: 5, last: Date.now() },
            "https://wiki.archlinux.org/title/Libcamera": { url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", visits: 1, last: Date.now() },
        };
        const rows = omni.suggest("libcamera", "");
        compare(rows.filter(r => r.kind === "history").map(r => r.url), ["https://wiki.archlinux.org/title/Libcamera"]);
        compare(rows.filter(r => r.kind === "page").length, 1, "the open one is offered as a switch instead");
    }

    function test_startRowsOnFirstRunOffersImportOnly() {
        compare(omni.startRows(), [], "no other browser found: nothing to offer");
        omni.offerImport = true;
        const rows = omni.startRows();
        compare(rows.map(r => r.kind + ":" + r.title), ["import:Bring your things over from another browser or a password manager"], "PLAN.md 3.4 4b; Welcome");
        omni.offerImport = false;
    }

    function test_startRowsRecentAndEarlier() {
        const t = session.newThread("open");
        session.addPage(t, "https://open.example/", "");
        const f = session.newThread("filed");
        session.addPage(f, "https://filed.example/", "");
        session.addPage(f, "https://filed.example/2", "");
        session.fileThread(f);
        history.entries = {
            "https://open.example/": { url: "https://open.example/", title: "Open", visits: 1, last: 50 },
            "https://a.example/": { url: "https://a.example/", title: "A", visits: 1, last: 10 },
            "https://b.example/": { url: "https://b.example/", title: "B", visits: 1, last: 30 },
            "https://c.example/": { url: "https://c.example/", title: "C", visits: 1, last: 20 },
            "https://d.example/": { url: "https://d.example/", title: "D", visits: 1, last: 5 },
        };
        const rows = omni.startRows();
        compare(rows.map(r => r.kind === "label" ? r.title : r.title), ["Recent", "B", "C", "A", "Closed tasks", "filed"]);
        verify(rows[5].detail.startsWith("2 pages · "));
    }

    // the rail's Earlier: most recently filed first, with the filing time
    function test_startRowsEarlierInFilingOrder() {
        const now = new Date(2026, 8, 23, 16, 0).getTime(), min = 60000;
        const a = session.newThread("used last, filed first");
        session.addPage(a, "https://a.example/", "");
        session.addPage(a, "https://a.example/2", "");
        const b = session.newThread("used first, filed last");
        session.addPage(b, "https://b.example/", "");
        session.addPage(b, "https://b.example/2", "");
        session.fileThread(a);
        session.fileThread(b);
        Object.assign(session.threadById(a), { lastActive: now - 10 * min, filedAt: now - 5 * min });
        Object.assign(session.threadById(b), { lastActive: now - 60 * min, filedAt: now - 2 * min });
        const rows = omni.startRows(now).filter(r => r.kind === "earlier");
        compare(rows.map(r => r.title), ["used first, filed last", "used last, filed first"]);
        compare(rows[0].detail, "2 pages · 15:58");
    }

    // The PLAN.md 3.1 camera thread with its neighbours, and history to match against.
    function seed() {
        const now = Date.now(), day = 86400000;
        const cam = session.newThread("x1p42100 camera");
        const here = session.addPage(cam, "https://github.com/linux-msm/linux/issues/212", "");
        session.update(here, { title: "camss: CSIPHY0 lanes ignored", lastActive: now });
        const lore = session.addPage(cam, "https://lore.kernel.org/v3", "");
        session.update(lore, { title: "[PATCH v3] camss", lastActive: now - 60000 });
        const soft = session.addPage(cam, "https://lists.libcamera.org/052113.html", "");
        session.update(soft, { title: "Re: softisp AGC starves on GPU", lastActive: now - 120000 });
        session.threadById(cam).trail = [{ url: "https://lore.kernel.org/v2", title: "[PATCH v2] camss", icon: "", left: now - 90000 }];
        const zen = session.newThread("Camera dark in Zen");
        session.addPage(zen, "https://bugzilla.mozilla.org/1901234", "");
        session.update(session.addPage(zen, "https://git.libcamera.org/agc.cpp", ""), { title: "agc.cpp - libcamera" });
        session.threadById(zen).earlier = true;
        history.entries = {
            "https://git.libcamera.org/agc.cpp": { url: "https://git.libcamera.org/agc.cpp", title: "agc.cpp - libcamera", visits: 6, last: now - day },
            "https://wiki.archlinux.org/title/Libcamera": { url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", visits: 3, last: now - 5 * day, saved: true },
            "https://lists.libcamera.org/052113.html": { url: "https://lists.libcamera.org/052113.html", title: "Re: softisp AGC starves on GPU", visits: 2, last: now },
        };
        session.activate(here);
        return { cam: cam, here: here, lore: lore, soft: soft, zen: zen };
    }

    // 3.2 2b: Enter's row, then Open page, History, Earlier, each under a 12 px label
    function test_addressOrderAndLabels() {
        const ids = seed();
        const rows = omni.suggest("libcamera agc", ids.here, "address");
        compare(rows.map(r => r.kind === "label" ? r.title : r.kind),
                ["go", "Open page", "page", "History", "history", "history", "Closed tasks", "earlier"]);
        compare(rows[0].detail, "Search");
        compare(rows[2].pageId, ids.soft);
        compare(rows[2].detail, "", "Enter switches; no word needed in the narrow card");
        compare(rows[4].title, "agc.cpp - libcamera", "both words first");
        compare(rows[5].detail, "Saved");
        compare(rows[7].threadId, ids.zen);
        compare(rows[7].detail, "2");
    }

    // 3.3: the same order with no labels, and the trailing word when Enter is not plain navigation
    function test_barOrderAndTrailingWords() {
        const ids = seed();
        const rows = omni.suggest("softisp agc cpu mode", ids.here, "bar");
        compare(rows.map(r => r.kind), ["go", "page", "history", "earlier"]);
        compare(rows[0].detail, "DuckDuckGo");
        compare(rows[1].detail, "Switch");
        compare(rows[1].dim, true, "an unloaded page's favicon is dimmed");
        compare(rows[2].title, "agc.cpp - libcamera");
        compare(rows[3].title, "Camera dark in Zen · 2 pages");
        compare(rows[3].detail, "Restore");
        verify(!rows.some(r => r.pageId === ids.here), "never the current page");
        verify(!rows.some(r => r.url === "https://lists.libcamera.org/052113.html" && r.kind === "history"),
               "an open page is offered as a switch, never as history");
    }

    function test_atMostEightRows() {
        const t = session.newThread("many");
        const entries = {};
        for (let i = 0; i < 10; i++) {
            session.update(session.addPage(t, "https://open.example/" + i, ""), { title: "camera open " + i });
            entries["https://h.example/" + i] = { url: "https://h.example/" + i, title: "camera history " + i, visits: 1, last: Date.now() };
        }
        history.entries = entries;
        for (let i = 0; i < 3; i++) {
            const f = session.newThread("camera filed " + i);
            session.addPage(f, "https://f.example/" + i, "");
            session.threadById(f).earlier = true;
        }
        const rows = omni.suggest("camera", "", "bar");
        compare(rows.length, 8);
        compare(rows.map(r => r.kind), ["go", "page", "page", "page", "history", "history", "earlier", "earlier"]);
    }

    // 3.2 2a: Enter reloads, the copy actions, then the thread's trail with the pages it left
    function test_pageRowsWithNothingTyped() {
        const ids = seed();
        const rows = omni.pageRows(ids.here, Date.now());
        compare(rows.slice(0, 3).map(r => r.action), ["reload", "copy", "markdown"]);
        compare(rows[3].title, "In this task");
        compare(rows.slice(4).map(r => r.title), ["[PATCH v3] camss", "[PATCH v2] camss", "Re: softisp AGC starves on GPU"]);
        compare(rows.slice(4).map(r => r.kind), ["page", "history", "page"]);
        compare(rows[4].detail, "open");
        verify(/^\d\d:\d\d$/.test(rows[5].detail), "a page left shows when");
        compare(omni.pageRows("", Date.now()), [], "no page, no rows");
    }

    function test_prefixes() {
        compare(["/x", ">x", "?x", "@x", "x", " @x"].map(t => omni.mode(t)), ["find", "actions", "ask", "jump", "", "jump"]);
        const ids = seed();
        const find = omni.suggest("/csiphy", ids.here);
        compare(find.map(r => r.kind), ["find"]);
        compare([find[0].title, find[0].text], ["Find “csiphy”", "csiphy"]);
        compare(omni.suggest("/", ids.here)[0].title, "Find on this page");
        compare(omni.suggest("?why", ids.here).map(r => r.kind), ["stub"], "Claude arrives in phase 5");
        compare(omni.suggest(">copy", ids.here).map(r => r.action), ["copy", "markdown"]);
        // the browser's own pages (PLAN.md 7: > settings, keys, Pages and memory)
        compare(omni.suggest(">settings", ids.here).map(r => r.action), ["settings"]);
        compare(omni.suggest(">memory", ids.here).map(r => r.title + " " + r.detail), ["Pages and memory Shift+Esc"]);
        compare(omni.suggest(">key", ids.here).map(r => r.detail), ["Ctrl+/"]);
        // print and reader view (PLAN.md 7), after Reload; with no article on the page, Reader view does nothing and says why
        compare(omni.suggest(">", ids.here).slice(0, 3).map(r => r.action), ["reload", "print", "reader"]);
        compare(omni.suggest(">print", ids.here).map(r => r.title + " " + r.detail), ["Print Ctrl+P"]);
        compare(omni.suggest(">reader", ids.here).map(r => r.kind + " " + r.detail), ["action Ctrl+Alt+R"]);
        omni.article = "none";
        compare(omni.suggest(">reader", ids.here).map(r => r.kind + " " + r.title + " " + r.detail), ["stub Reader view No article here"]);
        omni.article = "";
        compare(omni.suggest("@", ids.here), [], "nothing typed after @");
        const jump = omni.suggest("@camera", ids.here);
        compare(jump.map(r => r.kind), ["page", "earlier", "history", "history"]);
        compare(jump[0].pageId, ids.soft, "an open page; the current thread itself is not offered");
        compare(jump[1].detail, "Closed · 2 pages");
    }

    // PLAN.md 3.3: an existing file's path makes row 1 Open file, with find second
    function test_filePath() {
        const ids = seed();
        omni.isFile = path => path === "/home/abdul/My notes #2.pdf";
        const rows = omni.suggest("/home/abdul/My notes #2.pdf", ids.here);
        compare(rows.map(r => r.kind), ["go", "find"]);
        compare(rows[0].title, "Open file");
        compare(rows[0].url, "file:///home/abdul/My%20notes%20%232.pdf", "the name's # is not a fragment");
        compare(omni.suggest("/home/abdul/missing.pdf", ids.here).map(r => r.kind), ["find"], "no such file: find only");
        compare(omni.suggest("/csiphy", ids.here).map(r => r.kind), ["find"]);
    }

    // PLAN.md 3.14: a private window's cards offer no Earlier, no Always and no import
    function test_aPrivateWindowOffersNoEarlierAlwaysOrImport() {
        omni.offTheRecord = true;
        omni.offerImport = true;
        compare(omni.startRows(), [], "no import row on its first page");
        const t = session.newThread("camera");
        const here = session.addPage(t, "https://example.org/camera", "");
        const f = session.newThread("camera filed");
        session.addPage(f, "https://filed.example/camera", "");
        session.addPage(f, "https://filed.example/camera/2", "");
        session.fileThread(f);
        compare(omni.suggest("camera", "").map(r => r.kind), ["go", "page"]);
        compare(omni.suggest("@camera", "").map(r => r.kind), ["page"]);
        compare(omni.startRows(), []);
        compare(omni.suggest(">pin", here), [], "no Pin this site");
        omni.offTheRecord = false;
        omni.offerImport = false;
        compare(omni.suggest(">pin", here).map(r => r.action), ["always"]);
    }
}
