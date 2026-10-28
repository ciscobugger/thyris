import QtQuick
import QtTest
import Browser
import "../qml"
import "../qml/Settings.js" as Settings
import "../qml/Processes.js" as Processes

// Settings.js, Prefs.qml and Processes.js (PLAN.md 3.15, 3.17): the sections in order with the rows that exist, their
// wording, the filter, the views in place, what a change keeps, and Pages and memory's rows.
TestCase {
    name: "Settings"

    Component { id: prefsComponent; Prefs {} }

    function init() { Store.files = {} }

    readonly property real now: new Date(2026, 8, 29, 18, 0).getTime()
    function state(fields) {
        return Object.assign({
            engine: "duckduckgo", defaultBrowser: "yes", folder: "/home/abdul/Downloads", home: "/home/abdul", zoom: 1,
            fonts: { standard: "Noto Serif", serif: "Noto Serif", sansSerif: "Noto Sans", fixed: "Noto Sans Mono", size: 16 }, minimumFont: 0,
            languages: ["en-GB"], spellCheck: false, dictionaries: { "en-GB": "" }, allowed: ["https://lwn.net"],
            lists: [{ file: "ubo-filters", modified: new Date(2026, 8, 29, 6, 10).getTime(), version: "2026.928.1504" },
                    { file: "ubo-privacy", modified: 0, version: "1" }, { file: "easylist", modified: 0, version: "202609290512" }],
            updating: false, listFailure: null, thirdPartyCookies: "allow", httpsFirst: "on", cookies: 3, clearing: null, extensions: [],
            passwords: { state: "ready", entries: [], removing: {}, revealed: {} },
            zen: { profile: null, state: "", wrong: false, logins: 0, run: null, last: null, failure: null },
            versions: { qt: "6.11.2", chromium: "134.0.6998.208", security: "134.0.6998.208" }, now: now,
        }, fields ?? {});
    }
    // Tabs: the side is the default and the only value kept apart from it is "top"
    function test_tabsChoice() {
        compare(Settings.defaults.tabs, "side");
        compare(Settings.choices("tabs").map(c => c.value), ["side", "top"]);
        compare(Settings.choice("tabs", "Tabs", "side").value, "Along the side");
        compare(Settings.choice("tabs", "Tabs", "top").value, "Along the top");
        compare(Settings.foldOf("pages").key, "appearance", "in Appearance and reading, with the zoom and fonts");
        const prefs = createTemporaryObject(prefsComponent, this);
        prefs.set("tabs", "top");
        compare(prefs.values.tabs, "top");
        prefs.set("tabs", "side");
        compare(prefs.values.tabs, undefined, "the default is no value");
    }
    function heads(rows) { return rows.filter(r => r.kind === "head").map(r => r.label) }
    function row(rows, key) { return rows.find(r => r.key === key) ?? null }

    function test_sectionsInTheFramesOrderWithNoneForWhatIsNotBuilt() {
        compare(heads(Settings.rows(state(), "", "")), ["Search", "Start and windows", "Downloads", "Ad blocking", "Pages", "Passwords",
                                                         "Privacy", "Extensions", "Keys", "Import", "About"],
                "Import between Keys and About; no Memory, as the memory net has no setting");
        compare(Settings.order.indexOf("passwords"), Settings.order.indexOf("pages") + 1, "Passwords after Pages");
        compare(heads(Settings.rows(state({ zen: null }), "", "")).indexOf("Import"), -1, "with nothing of Zen's to show, no Import");
    }

    // Import (PLAN.md 3.15, 3.4): the Zen profile, when it ran (Ad blocking's pattern), what it brought, the passwords
    // waiting for Zen's primary password, and the last failure in words
    function test_importRows() {
        const zen = z => state({ zen: Object.assign({ profile: { name: "Default (release)", path: "/p" }, state: "", wrong: false, logins: 0,
                                                      run: null, last: null, failure: null }, z) });
        const kinds = rows => rows.filter(r => r.section === "import" && r.kind !== "head").map(r => r.kind + ":" + r.key);
        let rows = Settings.rows(state(), "", "");
        compare(kinds(rows), ["note:zen-none", "action:browserImport", "action:passwordFile"], "a password manager's file, Zen or not");
        compare(row(rows, "zen-none").label, "Zen isn't installed, so there's nothing of Zen's to import.");
        compare([row(rows, "passwordFile").label, row(rows, "passwordFile").value, row(rows, "passwordFile").action],
                ["Passwords from a file", "Bitwarden, 1Password, Apple, Google and others", "Choose…"]);
        rows = Settings.rows(zen({}), "", "");
        compare(kinds(rows), ["pair:zen-profile", "action:zen", "action:browserImport", "action:passwordFile"]);
        compare([row(rows, "zen-profile").value, row(rows, "zen").label, row(rows, "zen").value, row(rows, "zen").action],
                ["Default (release)", "Imported", "never", "Import"]);
        rows = Settings.rows(zen({ state: "reading" }), "", "");
        compare([row(rows, "zen").value, row(rows, "zen").action], ["Importing…", ""], "no Import while it runs");
        const run = { at: now, bookmarks: { added: 31, kept: 0 }, history: { added: 3874, kept: 2 } };
        rows = Settings.rows(zen({ state: "password", logins: 5, run: run }), "", "");
        compare(kinds(rows), ["pair:zen-profile", "action:zen", "pair:zen-bookmarks", "pair:zen-history", "pair:zen-passwords", "secret:zen-primary",
                              "action:browserImport", "action:passwordFile"]);
        compare([row(rows, "zen-bookmarks").value, row(rows, "zen-history").value, row(rows, "zen-passwords").value, row(rows, "zen-primary").label],
                ["31 into Saved", "3874 into History, 2 already there", "5 locked by Zen's primary password", "Primary password"]);
        rows = Settings.rows(zen({ state: "password", logins: 5, run: run, wrong: true }), "", "");
        compare(row(rows, "zen-wrong").label, "That is not Zen's primary password.");
        const at = new Date(2026, 8, 29, 17, 10).getTime();
        const done = p => Settings.rows(zen({ last: { at: at, bookmarks: { added: 0, kept: 31 }, history: { added: 0, kept: 0 }, passwords: p } }), "", "");
        rows = done({ added: 5, kept: 1, skipped: "" });
        compare([row(rows, "zen").value, row(rows, "zen").action, row(rows, "zen-bookmarks").value, row(rows, "zen-history").value, row(rows, "zen-passwords").value],
                ["today 17:10", "Import", "none new, 31 already there", "none", "5 saved, 1 already there"]);
        compare(row(done({ added: 0, kept: 0, skipped: "" }), "zen-passwords").value, "none");
        compare(row(done({ added: 0, kept: 0, skipped: "not given" }), "zen-passwords").value, "Skipped: no primary password given");
        compare(row(done({ added: 0, kept: 0, skipped: "none" }), "zen-passwords").value, "Skipped: no password store is running");
        compare(row(done({ added: 0, kept: 0, skipped: "failed" }), "zen-passwords").value, "Skipped: Zen's saved passwords would not open");
        // partly in: what went in, then what was left out and why
        compare(row(done({ added: 3, kept: 0, left: 3, skipped: "locked" }), "zen-passwords").value, "3 saved · 3 skipped: the password store stayed locked",
                "the keyring locked after the 3rd: those 3 are said to be in");
        compare(row(done({ added: 2, kept: 0, skipped: "locked" }), "zen-passwords").value, "2 saved · Skipped: the password store stayed locked",
                "a record of before the count of those left out");
        compare(row(done({ added: 4, kept: 0, unopened: 2, skipped: "" }), "zen-passwords").value, "4 saved · 2 skipped: Zen's saved passwords would not open");
        compare(row(done({ added: 0, kept: 1, unopened: 1, left: 2, skipped: "locked" }), "zen-passwords").value,
                "none new, 1 already there · 1 skipped: Zen's saved passwords would not open · 2 skipped: the password store stayed locked");
        compare(row(done({ added: 0, kept: 0, unopened: 5, skipped: "" }), "zen-passwords").value, "Skipped: Zen's saved passwords would not open",
                "none opened: the reason alone");
        // the two choices, in plain words with Zen's counts, only when Zen has some; the cookies and tabs after an import
        rows = Settings.rows(zen({ sites: 214, tabs: 23, cookies: true, openTabs: false }), "", "");
        compare(kinds(rows), ["pair:zen-profile", "choice:zenCookies", "choice:zenTabs", "action:zen", "action:browserImport", "action:passwordFile"]);
        compare([row(rows, "zenCookies").label, row(rows, "zenCookies").value, row(rows, "zenTabs").label, row(rows, "zenTabs").value],
                ["Stay signed in to 214 sites", "On", "Open your 23 tabs", "Off"]);
        compare([row(Settings.rows(zen({ sites: 1, tabs: 1, cookies: true, openTabs: true }), "", ""), "zenCookies").label,
                 row(Settings.rows(zen({ sites: 1, tabs: 1, cookies: true, openTabs: true }), "", ""), "zenTabs").label], ["Stay signed in to 1 site", "Open your 1 tab"]);
        compare(kinds(Settings.rows(zen({ sites: 0, tabs: -1 }), "", "")), ["pair:zen-profile", "action:zen", "action:browserImport", "action:passwordFile"], "none counted, none offered");
        const both = c => Settings.rows(zen({ last: { at: at, bookmarks: { added: 0, kept: 0 }, history: { added: 0, kept: 0 }, passwords: { added: 0, kept: 0, skipped: "" },
                                                      cookies: c, tabs: { added: 23, kept: 2 } } }), "", "");
        rows = both({ added: 1688, kept: 0, rejected: 2, skipped: 333 });
        compare([row(rows, "zen-cookies").value, row(rows, "zen-tabs").value],
                ["1688 brought over · 333 left out: Zen keeps them apart, per site or per container · 2 refused", "23 opened, 2 already open"]);
        verify(/sign in again/.test(row(rows, "zen-signin").label), "a few sites may ask to sign in again");
        compare(row(both({ failure: "cookies" }), "zen-cookies").value, "Skipped: Zen's sign-ins would not open");
        compare(row(both({ added: 0, kept: 9, skipped: 0 }), "zen-signin"), null, "nothing brought, nothing to say");
        rows = Settings.rows(zen({ failure: { at: at, text: "places" } }), "", "");
        compare(row(rows, "zen-failure").value, "today 17:10 · Zen's bookmarks and history would not open");
        compare(row(rows, "zen").value, "never", "the last import done, not the failure");
        compare(kinds(Settings.rows(zen({}), "", "zen")), ["pair:zen-profile", "action:zen"], "the filter finds them by Zen");
        compare(kinds(Settings.rows(zen({ state: "password", logins: 5, run: run }), "", "primary")), ["pair:zen-passwords", "secret:zen-primary"]);
    }

    function test_rowsAndTheirWording() {
        const rows = Settings.rows(state(), "", "");
        compare(row(rows, "engine").value, "DuckDuckGo");
        compare(row(rows, "restore").value, "Reopens your tasks");
        compare(row(rows, "defaultBrowser").value, "Yes");
        compare(row(rows, "defaultBrowser").action, "Set again");
        compare(row(rows, "defaultBrowser").detail, "Links from other apps open here");
        compare(Settings.rows(state({ defaultBrowser: "no" }), "", "").find(r => r.key === "defaultBrowser").action, "Make default");
        compare(row(rows, "folder").value, "~/Downloads");
        compare(row(rows, "lists").value, "uBlock filters, EasyList", "uBlock's parts are one list");
        compare(row(rows, "update").value, "today 06:10");
        compare(row(rows, "update").action, "Update now");
        compare(row(rows, "failure"), null, "no failure row while none failed");
        compare(row(rows, "allowed").value, "1");
        compare(row(rows, "zoom").value, "100 %");
        compare(row(rows, "fonts").value, "Noto Serif · 16 px");
        compare(row(rows, "minimumFont").value, "Off");
        compare(row(rows, "languages").value, "en-GB");
        compare([row(rows, "freeze"), row(rows, "unload"), row(rows, "keep")], [null, null, null], "no timed freeze or unload, no Keep loaded sites");
        compare(row(rows, "thirdPartyCookies").value, "Allowed");
        compare(row(rows, "httpsFirst").value, "On");
        compare([row(rows, "qt"), row(rows, "chromium"), row(rows, "list:easylist")], [null, null, null], "About names no versions but its own and Chromium's");
        compare(row(Settings.rows(state({ updating: true }), "", ""), "update").value, "Updating\u2026");
        compare(row(Settings.rows(state({ updating: true }), "", ""), "update").action, "", "no second update while one runs");
        const done = row(Settings.rows(state({ listUpdated: now - 60000, lists: [{ file: "easylist", modified: now - 60000 }] }), "", ""), "update");
        compare([done.label, done.value, done.action], ["Up to date", "today 17:59", ""], "an update just done says so, with no Update now");
        compare(Settings.now("adblock", state({ listUpdated: now - 60000 })), "Up to date");
        compare(row(Settings.rows(state({ listUpdated: now - 2 * 3600000 }), "", ""), "update").action, "Update now", "an hour on, it is offered again");
    }

    function test_choicesAndValues() {
        compare(Settings.choices("engine").map(c => c.label), ["DuckDuckGo", "Google", "Bing", "Brave Search", "Startpage"]);
        compare(Settings.choices("ext:abc").map(c => c.label), ["On", "Off", "Remove"]);
        compare(Settings.searchUrl("google", "libcamera agc"), "https://www.google.com/search?q=libcamera%20agc");
        compare(Settings.engine("nothing").name, "DuckDuckGo", "an unknown engine is the default");
    }

    function test_theFailureInWords() {
        compare(Settings.failure("curl: (6) Could not resolve host: easylist.to"), "Could not find easylist.to: no network, or no such name");
        compare(Settings.failure("curl: (7) Failed to connect to easylist.to port 443 after 3 ms: Couldn't connect to server"),
                "Could not connect to easylist.to");
        compare(Settings.failure("curl: (22) The requested URL returned error: 404"), "A list's server answered 404");
        compare(Settings.failure("curl: (28) Operation timed out after 30000 milliseconds"), "A list's server did not answer in time");
        compare(Settings.failure("node: not found"), "node: not found", "anything else as the script said it");
        const rows = Settings.rows(state({ listFailure: { at: new Date(2026, 8, 29, 17, 2).getTime(), text: "curl: (6) Could not resolve host: easylist.to" } }), "", "");
        compare(row(rows, "failure").value, "today 17:02 · Could not find easylist.to: no network, or no such name");
    }

    function test_filterKeepsTheRowsWithTheWordsUnderTheirSections() {
        const rows = Settings.rows(state(), "", "cookies");
        compare(heads(rows), ["Privacy"]);
        compare(rows.filter(r => r.kind !== "head").map(r => r.key), ["clear", "thirdPartyCookies"], "Clear browsing data holds Cookies in its view");
        compare(heads(Settings.rows(state(), "", "ad blocking")), ["Ad blocking"], "a section's title shows all its rows");
        compare(Settings.rows(state(), "", "ad blocking").length, 4, "with no failure, no failure row");
        compare(heads(Settings.rows(state(), "", "memory")), ["Keys"], "Pages and memory's key");
        compare(heads(Settings.rows(state(), "", "google")), ["Search", "Import"], "a choice's labels count; Import's file row names Google Password Manager");
        compare(heads(Settings.rows(state(), "", "ctrl+,")), ["Keys"]);
        compare(Settings.rows(state(), "", "zzzz").length, 0);
    }

    function test_theKeyList() {
        const rows = Settings.rows(state(), "", "").filter(r => r.section === "keys");
        const pair = label => rows.find(r => r.label === label).value;
        compare(pair("New-page bar"), "Ctrl+T");
        compare(pair("Settings / key list / clear browsing data"), "Ctrl+, / Ctrl+/ / Ctrl+Shift+Delete");
        compare(pair("Pages and memory"), "Shift+Esc");
        compare(rows.filter(r => r.kind === "group").map(r => r.label),
                ["In the address card and the Ctrl+T bar", "Rail list (after F6)", "Asks and dialogs", "Mouse"]);
        compare(pair("Reader view"), "Ctrl+Alt+R");
        compare(pair("Print / view source (new page in this task)"), "Ctrl+P / Ctrl+U", "save page and open file are not built");
        verify(!rows.some(r => /DevTools|Claude|save page|open file/.test(r.label)), "only the keys whose features exist");
    }

    function test_viewsInPlace() {
        const fonts = Settings.rows(state(), "fonts", "");
        compare(fonts.map(r => r.key), ["back", "font:standard", "font:serif", "font:sansSerif", "font:fixed", "fontSize"]);
        compare(fonts[4].value, "Noto Sans Mono");
        const allowed = Settings.rows(state(), "allowed", "");
        compare(allowed.map(r => r.label), ["Sites allowed", "lwn.net"]);
        compare(allowed[1].action, "Remove");
        compare(Settings.rows(state({ allowed: [] }), "allowed", "")[1].kind, "note", "none: says where a site is added");
        const clear = Settings.rows(state(), "clear", "");
        compare(clear.filter(r => r.kind === "action").map(r => r.label + "|" + r.value), ["History and closed pages|", "Cookies|3", "Cached files|"]);
        const clearing = Settings.rows(state({ clearing: { what: "cookies", left: 4 } }), "clear", "");
        compare(clearing.map(r => r.label + "|" + (r.value ?? "")), ["Clear browsing data|", "Cookies|Cleared in 4 s"]);
        compare(clearing[1].action, "Undo");
    }

    function test_theSideListSaysWhatEachSectionIsSetTo() {
        const s = state({ passwords: { state: "ready", entries: [{ id: "1" }, { id: "2" }], removing: {}, revealed: {} }, extensions: [], versions: { opsis: "0.1", chromium: "140.0.7339.225" } });
        compare(Settings.now("search", s), "DuckDuckGo");
        compare(Settings.now("start", s), "Default browser");
        compare(Settings.now("downloads", s), "~/Downloads");
        compare(Settings.now("pages", s), "100 % · Noto Serif");
        compare(Settings.now("passwords", s), "2 saved");
        compare(Settings.now("extensions", s), "None");
        compare(Settings.now("about", s), "Version 0.1");
        const about = Settings.rows(s, "", "").filter(r => r.section === "about" && r.kind !== "head");
        compare(about.map(r => r.label + "|" + r.value + "|" + r.detail), ["Thyris|Version 0.1|Built on Chromium 140"], "About: the name, the version, the engine");
        compare(Settings.now("adblock", state({ updating: true })), "Updating…");
        compare(Settings.order.every(n => Settings.glyphs[n] && Settings.notes[n]), true, "every section has a glyph and a line");
        compare(Settings.clusters.reduce((all, c) => all.concat(c), []).sort(), Settings.order.slice().sort(), "every section in one run of the side list");
    }

    function test_spellCheckSaysWhichLanguageHasNoDictionary() {
        let rows = Settings.rows(state({ spellCheck: true, languages: ["en-GB", "sv"], dictionaries: { "en-GB": "ready", sv: "" } }), "", "");
        compare(row(rows, "dictionaries").label, "Spell check skips sv: no spelling dictionary for it is installed.");
        rows = Settings.rows(state({ spellCheck: true, dictionaries: { "en-GB": "hunspell" } }), "", "");
        compare(row(rows, "dictionaries"), null, "one hunspell has is converted");
        compare(row(Settings.rows(state(), "", ""), "dictionaries"), null, "only with spell check on");
    }

    function test_languages() {
        compare(Settings.languages("en-GB, sv  de_DE,,x"), ["en-GB", "sv", "de-DE"]);
        compare(Settings.acceptLanguage(["sv-SE", "sv", "en"]), "sv-SE,sv;q=0.9,en;q=0.8");
        compare(Settings.fromAcceptLanguage("en-GB,en;q=0.9"), ["en-GB", "en"]);
        compare(Settings.families(["Noto Sans", "Noto Serif", "Inter", "Noto Sans Mono"], "noto sans"), ["Noto Sans", "Noto Sans Mono"]);
    }

    // Chromium applies a new minimum at a page's next load (measured): the row says so while one is set
    function test_minimumSizeSaysWhenAPageTakesIt() {
        compare(row(Settings.rows(state(), "", ""), "minimum-note"), null);
        compare(row(Settings.rows(state({ minimumFont: 12 }), "", ""), "minimum-note").label, "A page takes the minimum when it loads again.");
        compare(row(Settings.rows(state({ minimumFont: 12 }), "", ""), "minimumFont").value, "12 px");
    }

    function test_steps() {
        compare(Settings.stepIn(Settings.fontSizes, 16, 1), 18);
        compare(Settings.stepIn(Settings.fontSizes, 17, -1), 16, "from between two steps, the next one down");
        compare(Settings.stepIn(Settings.minimumSizes, 0, 1), 6);
        compare(Settings.stepIn(Settings.minimumSizes, 0, -1), 0, "Off is the least");
        compare(Settings.px(0), "Off");
    }

    function test_prefsKeepOnlyWhatDiffersFromTheDefault() {
        const p = prefsComponent.createObject(null);
        let heard = [];
        p.changed.connect(k => heard.push(k));
        compare(p.get("engine"), "duckduckgo");
        p.set("engine", "google");
        compare(p.get("engine"), "google");
        compare(heard, ["engine"]);
        p.save();
        compare(Store.load("settings").engine, "google");
        p.set("engine", "duckduckgo");
        p.save();
        compare(Store.load("settings").engine, undefined, "back to the default: dropped from the file");
        p.set("languages", ["sv"]);
        p.save();
        const q = prefsComponent.createObject(null);
        q.load();
        compare(q.get("languages"), ["sv"], "a start reads what was set");
        p.destroy();
        q.destroy();
    }

    function test_clearWaitsOnItsUndo() {
        const p = prefsComponent.createObject(null);
        let due = [];
        p.clearDue.connect(w => due.push(w));
        p.startClear("cookies");
        compare(p.clearing.left, 6);
        p.startClear("history");
        compare(p.clearing.what, "cookies", "one at a time");
        p.undoClear();
        compare(p.clearing, null);
        p.startClear("cache");
        for (let i = 0; i < 6; i++)
            p.clearTimer.triggered();
        compare(due, ["cache"], "done once the 6 s are over, not before");
        compare(p.clearing, null);
        p.destroy();
    }

    // Pages and memory (PLAN.md 3.17): the browser's processes, then each page process with its pages, then the pages
    // with none; Unload where the memory net may unload (Lifecycle.unloadable)
    function test_pagesAndMemory() {
        const mb = n => n * 1048576;
        const pages = [
            { id: "a", title: "camss", url: "https://github.com/x", state: "live", pid: 41, shown: true, where: "" },
            { id: "b", title: "patch", url: "https://lore.kernel.org/y", state: "frozen", pid: 41, shown: false, where: "" },
            { id: "c", title: "Lofi", url: "https://www.youtube.com/z", state: "live", pid: 43, shown: false, where: "", audible: true },
            { id: "d", title: "Meet", url: "https://meet.google.com/q", state: "live", pid: 44, shown: false, where: "", needsYou: true },
            { id: "e", title: "Gmail", url: "https://mail.google.com/", state: "unloaded", pid: 0, shown: false, where: "Always" },
            { id: "f", title: "SAS", url: "https://www.flysas.com/", state: "live", pid: 45, shown: false, where: "", keep: true },
        ];
        const processes = [{ pid: 1, type: "", service: "", bytes: mb(400) }, { pid: 2, type: "gpu-process", service: "", bytes: mb(200) },
                           { pid: 3, type: "utility", service: "network.mojom.NetworkService", bytes: mb(50) },
                           { pid: 41, type: "renderer", service: "", bytes: mb(700) }, { pid: 43, type: "renderer", service: "", bytes: mb(230) },
                           { pid: 44, type: "renderer", service: "", bytes: mb(300) }, { pid: 45, type: "renderer", service: "", bytes: mb(90) },
                           { pid: 50, type: "renderer", service: "", bytes: mb(40) }];
        const rows = Processes.rows(pages, processes, new Date(2026, 8, 29, 14, 31).getTime());
        compare(rows[0].label, "Measured 14:31, again every 10 s while this page is open.");
        compare(rows.filter(r => r.kind === "head").map(r => r.label + "|" + r.value),
                ["Browser|", "Process 41 · 2 pages|700 MB", "Process 44|300 MB", "Process 43|230 MB", "Process 45|90 MB", "No process|"]);
        compare(rows.filter(r => r.kind === "process").map(r => r.label),
                ["Main process", "GPU process", "Network service", "Other page process"], "a page process of no listed page is the browser's");
        const page = id => rows.find(r => r.ref === id);
        compare(page("a").value, "Live · on screen");
        compare(page("a").unload, false, "the page on screen stays");
        compare(page("b").value, "Frozen");
        compare(page("b").unload, true);
        compare(page("c").value, "Live · playing audio");
        compare(page("c").unload, false, "what keeps a page live keeps Unload away");
        compare(page("d").unload, false, "an ask waits on it");
        compare(page("d").value, "Live · an ask waits");
        compare(page("e").value, "Unloaded");
        compare(page("f").value, "Live", "Keep page loaded is gone");
        compare(page("f").unload, true);
        compare(Processes.processName({ type: "utility", service: "storage.mojom.StorageService" }), "Storage service");
        compare(Processes.processName({ pid: 60, parent: 1, type: "", service: "", name: "curl" }), "curl",
                "a process under the browser that is not Chromium's, by its name");
        compare(Processes.processName({ pid: 61, parent: 1, type: "", service: "", name: "" }), "Process 61");
    }
}
