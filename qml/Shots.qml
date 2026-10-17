import QtQuick
import "Asks.js" as Asks
import "Failures.js" as Failures
import "PageState.js" as PageState
import "RailRows.js" as RailRows
import "PageMenu.js" as PageMenu

// Shot mode only (`browser --shots`, tools/shots): seeds the example session from PLAN.md 3.1, drives
// Main into one named state through its own functions (no synthetic input), waits for motion to end
// and asks the launcher to grab the window. A new scenario is one more entry in `scenarios`.
QtObject {
    id: shots

    required property var app          // Main
    required property var session
    required property var history
    required property var hoverPeek    // Main's peek
    required property var peekedRail   // Main's rail inside the peek
    required property var newPageBar   // Main's newBar
    required property var rail         // Main's pinned rail
    required property var addressCard  // Main's AddressEditor
    required property var pageScroll   // Main's PageScrollBar
    required property var failures     // Main's FailurePage
    required property var site         // Main's SiteInfo
    required property var welcome      // Main's Welcome

    readonly property var scenarios: ({
        "everyday": () => { everyday(); app.hoveredLink = "https://lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org/"; },
        "address-empty": () => { everyday(); app.editAddress(); },
        // the first start (thyris-migration-plan.md): the browsers found, bringing Chrome over, done
        "welcome-arrive": () => { everyday(); welcomeSample("arrive"); },
        "welcome-arrive-zen": () => { everyday(); welcomeSample("arrive"); welcome.chosen = 2; },
        "welcome-arrive-keys": () => { everyday(); welcomeSample("arrive"); welcome.forceActiveFocus(); welcome.keyed = true; welcome.chosen = 1; },
        // the chosen browser with History switched off
        "welcome-arrive-choose": () => { everyday(); welcomeSample("arrive"); const s = welcome.sources.slice(); s[0] = Object.assign({}, s[0], { bring: { history: false } }); welcome.sources = s; },
        // a password manager's file chosen: where each service keeps its export
        "welcome-file": () => { everyday(); welcomeSample("arrive"); welcome.chosen = 3; },
        // the page gone: the rail holds the imported windows, one line says so
        "welcome-handoff": () => { everyday(); rail.importHint = "Your 9 Chrome windows are below, one task each. Pages you open from one stay under it."; },
        // Start fresh: the empty browser, and the way back to the import
        "welcome-fresh": () => { newPageBar.show(); later(() => { newPageBar.rows = [{ kind: "import", glyph: "download", title: "Bring your things over from another browser or a password manager" }]; newPageBar.current = -1 }); },
        "welcome-none": () => { everyday(); welcomeSample("arrive"); welcome.sources = welcome.sources.filter(x => x.kind === "file"); welcome.chosen = 0; },
        "welcome-bringing": () => { everyday(); welcomeSample("bringing"); },
        "welcome-keyring": () => { everyday(); welcomeSample("bringing", k => { k[0] = { label: "Passwords", done: 0, total: 312, waiting: "keyring" } }); },
        "welcome-failed": () => { everyday(); welcomeSample("bringing", k => { k[0] = { label: "Passwords", done: 0, total: 312, failed: "the keyring stayed locked" } }); },
        "welcome-done": () => { everyday(); welcomeSample("done"); },
        // Settings > Import > Passwords from a file: the file alone, a file refused, its logins counting, done
        "welcome-file-arrive": () => { everyday(); welcomeFile("arrive"); },
        "welcome-file-refused": () => { everyday(); welcomeFile("arrive"); welcome.notice = "That file didn't work. It has no password column, so it isn't a password export."; },
        "welcome-file-bringing": () => { everyday(); welcomeFile("bringing"); },
        "welcome-file-done": () => { everyday(); welcomeFile("done"); },
        // Ctrl+L on a long sign-in address, as the owner met it (2026-10-09)
        "address-edit-long": () => { everyday(); app.currentView.url = "https://accounts.google.com/v3/signin/identifier?continue=https%3A%2F%2Fmail.google.com%2Fmail%2Fu%2F0%2F&emr=1&followup=https%3A%2F%2Fmail.google.com%2Fmail%2Fu%2F0%2F&ifkv=AcMMx-cH3&osid=1&passive=1209600&service=mail&flowName=GlifWebSignIn&flowEntry=ServiceLogin"; app.editAddress(); },
        "address-typing": () => { everyday(); app.editAddress("libcamera agc"); },
        // 3.2: an ask that arrives while typing waits on the card's last line
        "address-ask": () => { meet([micAndCamera()]); app.editAddress("libcamera agc"); },
        // 3.2: the card halfway from its rail slot to the centre, contents not yet faded in
        "address-morph": () => { everyday(); app.editAddress(); later(() => addressCard.pose(0.5)); },
        // the close's last frame (and the open's first): on its slot, the rail card's contents back, no
        // hairline; it should match "everyday" pixel for pixel
        "address-morph-end": () => { everyday(); app.editAddress(); later(() => addressCard.pose(0, 1)); },
        "newpage": () => { everyday(); newPageBar.show("softisp agc cpu mode"); },
        "newpage-after-tab": () => { everyday(); newPageBar.show("softisp agc cpu mode"); newPageBar.flip(); },
        // no thread over the threshold: "New thread", the ghost row at the top
        "newpage-no-match": () => { everyday(); newPageBar.show("weather mogadishu"); },
        // Esc keeps the text for 30 s: Ctrl+T again brings it back
        "newpage-kept": () => { everyday(); newPageBar.show("softisp agc cpu mode"); newPageBar.dismiss(); newPageBar.show(); },
        // Enter puts the page where the ghost row was
        "newpage-enter": () => { everyday(); newPageBar.show("softisp agc cpu mode"); newPageBar.activate(newPageBar.rows[0], false); },
        // Alt+Enter: the same place, in the background
        "newpage-background": () => { everyday(); newPageBar.show("softisp agc cpu mode"); newPageBar.flip(); newPageBar.activate(newPageBar.rows[0], true); },
        "newpage-jump": () => { everyday(); newPageBar.show("@camera"); },
        // 3.7 7a: Ctrl+Shift+A, "char": the Book4 thread from Earlier with the page it comes back at and where you
        // stopped, a closed page, history; the typed letters in DemiBold
        "jump": () => { recall(); newPageBar.show("@char"); },
        // Shift+Delete on the closed page: "Forgot … · Undo" on the last line for 6 s
        "jump-forgot": () => { recall(); newPageBar.show("@char"); newPageBar.current = newPageBar.rows.findIndex(r => r.kind === "closed"); newPageBar.forget(); },
        // the same in the address card (Ctrl+L, then @)
        "jump-address": () => { recall(); app.editAddress("@char"); },
        // 2b typing, Shift+Delete on a history row: the undo at the right of the card's last line for 6 s
        "address-forgot": () => { everyday(); app.editAddress("libcamera agc"); addressCard.current = addressCard.rows.findIndex(r => r.kind === "history"); addressCard.forget(); },
        // 3.21 Ctrl+H: History, the rail's list from its foot, the search taking the keys; the Book4 task opened in place:
        // its pages, where you stopped, its file
        "earlier": () => { recall(); app.openEarlier("history"); app.command("historyOpen", session.threads.find(t => t.title === "Book4 charging PD").id, true); },
        "earlier-filter": () => { recall(); app.openEarlier("history"); app.command("earlierFilter", "", "blur"); },
        // History's Older listed in place
        "earlier-older": () => { recall(); app.openEarlier("history"); app.command("historyOlder", "", true); },
        // Shift+Delete on a closed task in History: the card says "Forgot … · Undo" for 6 s
        "earlier-forgot": () => { recall(); app.openEarlier("history"); app.forget("earlier", session.threads.find(t => t.title === "Zen blur config").id); },
        // 7c Ctrl+Shift+O: Saved threads, Pages with one edited in place, the imported folder as a group
        "earlier-saved": () => { recall(); app.editSaved(app.savedModel.pages.find(p => p.url === "https://lore.kernel.org/lkml/").id); },
        // Ctrl+J: every file kept, by day, each naming its page
        "earlier-downloads": () => { recall(); app.openEarlier("downloads"); },
        // 3.4 with Ctrl+H: no page open, the card stays the page while the rail shows History
        "earlier-empty": () => { recall(); fileEverything(); app.dropViews(Object.keys(app.views)); newPageBar.show(); app.openEarlier("history"); },
        // folded (3.5): Ctrl+H brings the overlay out in History, held until Esc or a click on the page
        "earlier-folded": () => { recall(); app.setFold(false); app.openEarlier("history"); },
        // 3.20 #4: ? hands the question to Praxis (the row when Praxis's hand-off is here)
        "ask-praxis": () => { everyday(); rail.omni.praxisHere = true; app.editAddress("?is the lane bug fixed in v3"); },
        // 3.20 #8: the page's own right-click menu on a link, with text selected
        "page-menu": () => { everyday(); rail.omni.praxisHere = true;
            app.openPageMenu(app.currentView, PageMenu.request({ linkUrl: "https://lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org/",
                                                                 selectedText: "data-lanes", mediaType: 0 }), Qt.point(460, 236)); },
        "page-menu-field": () => { everyday();
            app.openPageMenu(app.currentView, PageMenu.request({ isContentEditable: true, misspelledWord: "lanse", spellCheckerSuggestions: ["lanes", "lance", "lane"] }),
                             Qt.point(460, 236)); },
        // Ctrl+D: the card says "Saved · Edit" for 3 s
        "saved-notice": () => { recall(); app.saveCurrent(); },
        // 3.14: Ctrl+D in a private window asks first
        "private-save": () => {
            everyday();
            later(() => {
                const w = app.newPrivateWindow(app.windowState()), s = w.windowSession;
                const id = s.addPage(s.newThread("NeverSSL"), "http://neverssl.com/online", "");
                s.update(id, { title: "NeverSSL - Connecting", icon: favicon("N", "#3f6b3a") });
                w.show(id);
                w.currentView.asks = [{ id: 1, kind: "save", host: "neverssl.com", url: "http://neverssl.com/online", title: "NeverSSL - Connecting", icon: "" }];
                shots.window = w;
                later(() => settle.restart());
            });
        },
        "newpage-actions": () => { everyday(); newPageBar.show(">copy"); },
        // 3.15 Ctrl+,: Settings as a thread of one, the page's sections in the site panel's row style
        "settings": () => { everyday(); settings(); },
        // a value clicked: its choices in the row, the picked one on the current row's wash
        "settings-choice": () => { everyday(); settings(); app.windowSettings.expand = "engine"; },
        // the filter: only the rows with the words, under their sections' titles
        "settings-filter": () => { everyday(); settings(); app.windowSettings.filter = "cookies"; },
        // Ctrl+/: the key list
        "settings-keys": () => { everyday(); settings("keys"); },
        // each section on its own, as the side list opens it
        "settings-start": () => { everyday(); settings("start"); },
        "settings-pages": () => { everyday(); settings("pages"); },
        "settings-privacy": () => { everyday(); settings("privacy"); },
        "settings-extensions": () => { everyday(); settings("extensions"); },
        "settings-about": () => { everyday(); settings("about"); },
        // Pages > Fonts ›: the view in place, a family edited with the installed ones that hold the words typed
        "settings-fonts": () => { everyday(); settings(); app.windowSettings.openView("fonts"); app.windowSettings.edit("font:sansSerif", "noto"); },
        // Ad blocking > Sites allowed ›
        "settings-allowed": () => { everyday(); settings(); app.windowSettings.openView("allowed"); },
        // Ctrl+Shift+Delete: Clear browsing data, then Cookies cleared, waiting 6 s on its undo
        "settings-clear": () => { everyday(); settings("clear"); },
        "settings-clearing": () => { everyday(); settings("clear"); app.prefs.clearing = { what: "cookies", left: 6 }; },
        // an update that failed: the failure in words, and Updated with Update now
        "settings-failure": () => { everyday(); settings(); later(() => app.windowSettings.scrollTo("head:adblock")); app.prefs.set("listFailure", { at: Date.now() - 3600000, text: "curl: (6) Could not resolve host: easylist.to" }); },
        // Passwords (3.15): Saved passwords ›, and the gap PLAN names
        "settings-passwords": () => { everyday(); logins(); settings(); later(() => app.windowSettings.scrollTo("head:passwords")); },
        // Saved passwords ›: host, user name, Show · Edit · Delete; one shown, one deleted and waiting on its Undo, one whose
        // Show the keyring did not unlock
        "settings-passwords-list": () => {
            everyday(); logins(); settings(); app.windowSettings.openView("passwords");
            app.windowSettings.revealed = { [shotLogins[1].id]: { secret: "correct horse battery" }, [shotLogins[3].id]: { failure: "locked" } };
            Passwords.removeLater(shotLogins[2].id);
        },
        // Edit: User and Password in the row, Done
        "settings-passwords-edit": () => {
            everyday(); logins(); settings(); app.windowSettings.openView("passwords");
            app.windowSettings.edit("login:" + shotLogins[0].id, shotLogins[0].user);
            app.windowSettings.editSecret = "correct horse battery";
        },
        // no Secret Service on the session bus
        "settings-passwords-none": () => { everyday(); settings(); later(() => app.windowSettings.scrollTo("head:passwords")); },
        // 3.17 Shift+Esc: Pages and memory, the processes measured with their pages
        "pages": () => { everyday(); pagesAndMemory(); },
        // Unload on a page with a field edited (Main.unloadPage asks first): it stays live, its row saying why, with no Unload
        "pages-edited": () => {
            everyday();
            pagesAndMemory();
            // the issue's page, live, nothing else keeping it (the patch page's download would come first)
            const m = app.windowPages.measured, id = session.threads.find(t => t.title === "x1p42100 camera").pages[1];
            app.windowPages.measured = Object.assign({}, m, { pages: m.pages.map(p => p.id === id ? Object.assign({}, p, { state: "live", edited: true }) : p) });
        },
        // 3.8 8e: find in the rail's card, over the rows; the thread's other live pages with the words, and
        // what it skipped
        "find": () => { everyday(); find("csiphy", { matches: 17, active: 3 }, true); },
        // Aa (Alt+C): match case
        "find-case": () => { everyday(); rail.finder.matchCase = true; find("CSIPHY", { matches: 4, active: 1 }, false); },
        "find-no-matches": () => { everyday(); find("csiphy lanes 4", { matches: 0, active: 0 }, false); },
        // an ask that arrives while find is open waits on its last line
        "find-ask": () => { meet([micAndCamera()]); find("standup", { matches: 2, active: 1 }, false); },
        // folded (3.5): the overlay held out with find in its address slot, the page beside it in view
        "find-folded": () => { everyday(); app.setFold(false); find("csiphy", { matches: 17, active: 3 }, true); },
        // 3.2: the / prefix in the address card; a typed path of an existing file opens it, find second (3.3)
        "address-find": () => { everyday(); app.editAddress("/csiphy"); },
        "address-file": () => { everyday(); rail.omni.isFile = p => p === "/home/you/Downloads/camss-v3.pdf"; app.editAddress("/home/you/Downloads/camss-v3.pdf"); },
        "empty": () => { seed(); fileEverything(); newPageBar.show(); },
        "firstrun": () => newPageBar.show(),
        // 3.4 4b, Down: the import row current; Enter opens Settings at Import, where it runs
        "firstrun-import": () => { newPageBar.show(); newPageBar.step(1); },
        // Settings > Import (3.15): the import running
        "settings-import-running": () => { everyday(); zenShot({ state: "reading" }); },
        // the bookmarks and history in, the passwords waiting for Zen's primary password, one given that did not open them
        "settings-import-password": () => {
            everyday();
            zenShot({ state: "password", wrong: true, logins: 5, run: { at: Date.now(), bookmarks: { added: 31, kept: 0 }, history: { added: 3874, kept: 0 } } });
            app.windowSettings.zenPrimary = "hunter2";
            later(() => app.windowSettings.target("own:zen-primary:input").forceActiveFocus());
        },
        // done: what it brought, and when
        "settings-import": () => {
            everyday();
            zenShot({ last: { at: Date.now() - 600000, bookmarks: { added: 31, kept: 0 }, history: { added: 3874, kept: 0 }, passwords: { added: 5, kept: 0, skipped: "" } } });
        },
        // imported again: nothing twice; its passwords skipped at the primary password
        "settings-import-again": () => {
            everyday();
            zenShot({ last: { at: Date.now() - 60000, bookmarks: { added: 2, kept: 31 }, history: { added: 14, kept: 3874 }, passwords: { added: 0, kept: 0, skipped: "not given" } } });
        },
        // done, two of its six logins left out: records NSS did not open (Zen.saved's unopened)
        "settings-import-partial": () => {
            everyday();
            zenShot({ last: { at: Date.now() - 600000, bookmarks: { added: 4, kept: 0 }, history: { added: 3855, kept: 0 },
                              passwords: { added: 4, kept: 0, unopened: 2, skipped: "" } } });
        },
        // Zen has cookies and tabs to bring: the two choices, before the import
        "settings-import-choices": () => { everyday(); zenShot({ sites: 214, tabs: 23, cookies: true, openTabs: true }); },
        // done, with the cookies and the tabs (the last words say a few sites may ask to sign in again)
        "settings-import-signed-in": () => {
            everyday();
            zenShot({ sites: 214, tabs: 23, cookies: true, openTabs: false, last: { at: Date.now() - 600000, bookmarks: { added: 4, kept: 0 }, history: { added: 3855, kept: 0 },
                      passwords: { added: 5, kept: 0, skipped: "" }, cookies: { added: 1575, kept: 0, rejected: 2, skipped: 333 }, tabs: { added: 23, kept: 0 } } });
        },
        "folded": () => { everyday(); app.setFold(false); loading(0.6); },
        "folded-peek": () => { everyday(); app.setFold(false); hoverPeek.open = true; },
        // a row's tooltip over the peek's frost (the tip waits 600 ms, so the grab waits for it)
        "folded-peek-tip": () => { everyday(); app.setFold(false); hoverPeek.open = true; later(() => { const it = peekedRail.listView.itemAtIndex(1); peekedRail.showTip(it, it.ref); later(() => settle.restart()); }); },
        "folded-address": () => { everyday(); app.setFold(false); app.editAddress("libcamera agc"); },
        // 3.19: the docked slab; lifted over the page (the pointer on it); tucked away; halfway through the lift (the
        // slab on its way, the page sliding under it at its folded width); the quiet rail while you read; Settings' tip
        "rail-docked": () => { everyday(); },
        // the foot at the narrowest rail: History, Saved and Downloads as glyphs, the names in their tips
        "rail-narrow": () => { everyday(); app.railWidth = 248; },
        // a host too long for the card at the narrowest rail: whole names leave its start (accounts.google.com as google.com)
        "address-long-host": () => { everyday(); app.railWidth = 248; app.currentView.url = "https://accounts.google.com/v3/signin/identifier"; },
        // the owner's case of 2026-10-09 at the narrowest rail: browserbench.org whole
        "address-browserbench": () => { everyday(); app.railWidth = 248; app.currentView.url = "https://browserbench.org/Speedometer3.1/"; },
        // 3.21: the pointer resting on a folded task: its pages beside the rail
        "rail-stack": () => {
            everyday();
            const f = session.threads.find(t => (t.title || "").indexOf("Flights") === 0);
            later(() => {
                const v = rail.listView;
                for (let i = 0; i < v.count; i++) { const it = v.itemAtIndex(i); if (it && it.key === "t:" + f.id) { rail.stackRow = it; rail.stackRef = f.id; rail.openStack(); } }
            });
        },
        // a file still coming from a page that has gone: its share after Downloads, at the default width and the narrowest
        "foot-coming": () => { everyday(); session.updateDownload("d0", { page: "gone" }); },
        // a file landed a moment ago: its row has left the page for the foot's Downloads, which counts it in the accent
        "foot-landed": () => {
            everyday();
            rail.downloadsSeenAt = Date.now() - 60000;
            session.updateDownload("d0", { state: "done", received: 8.4e6, finished: Date.now() - 20000 });
            session.update(session.threads[0].pages[0], { downloading: false });
        },
        "foot-coming-narrow": () => { everyday(); app.railWidth = 248; session.updateDownload("d0", { page: "gone" }); },
        "rail-lifted": () => { everyday(); app.setFold(false); hoverPeek.open = true; },
        "rail-tucked": () => { everyday(); app.setFold(false); },
        "rail-lifting": () => {
            everyday();
            later(() => { app.setFold(false); peekedRail.slide = 1; app.railLift = 0.45; app.railFill = 0.8; app.pageShift = Math.round((app.railWidth - app.inset) * 0.35) });
        },
        "rail-quiet": () => { everyday(); app.quietRail = true; },
        "rail-settings-tip": () => { everyday(); later(() => { rail.showHint(rail.settingsButton, "Settings", "Ctrl+,"); later(() => settle.restart()) }); },
        // the section strip under a long page read 45 % down (in Steps): at rest, the pointer near, the thumb held, a
        // dark page with the pointer near, and folded (the strip under the full-width page)
        "strip-rest": () => { everyday(); sectioned(false); },
        "strip-near": () => { everyday(); sectioned(false); app.windowStrip.near = true; },
        "strip-grabbed": () => { everyday(); sectioned(false, true); app.windowStrip.near = true; },
        "strip-dark-near": () => { everyday(); sectioned(true); app.windowStrip.near = true; },
        "strip-folded": () => { everyday(); app.setFold(false); sectioned(false); },
        // folded, the card grows out of the edge's handle
        "folded-address-morph": () => { everyday(); app.setFold(false); later(() => { app.editAddress(); addressCard.pose(0.5); }); },
        // F6 from the card while folded: the peek slides in and the card goes halfway back into its slot
        "folded-address-f6": () => { everyday(); app.setFold(false); later(() => { app.editAddress(); app.focusCycle(); addressCard.pose(0.5); }); },
        "loading": () => { everyday(); loading(0.3); session.update("issue212", { loading: true }); },
        // 3.8 8a at 8 s under 30 %: typed lwn.net, the host at once, the old page still on screen
        "loading-waiting": () => {
            everyday();
            app.currentView.url = "https://lwn.net/Articles/991234/";
            loading(0);
            app.currentView.waitingFor = "lwn.net";
            session.update("issue212", { loading: true });
        },
        // a new page before its server answers: the terminal ground, not a blank page
        "loading-new-view": () => {
            everyday();
            const id = session.addPage(session.threads[0].id, "https://lwn.net/Articles/991234/", "issue212");
            app.show(id);
            app.currentView.drawn = false;
            loading(0);
            session.update(id, { loading: true });
        },
        // 3.8 8b: plain http is all that works; then a password field on it has the focus
        "insecure": () => insecure(false),
        "insecure-password": () => insecure(true),
        "wide": () => { everyday(); app.railWidth = 420; },
        // 3.8 8c: Meet asks for the microphone and camera, a second ask waits behind it; the rows move down
        "ask-permission": () => meet([micAndCamera(), { id: 2, kind: "external", host: "meet.google.com", scheme: "zoommtg", app: "Zoom" }]),
        // F6 from the page reaches the ask: the focus ring on its first button
        "ask-keys": () => { meet([micAndCamera()]); later(() => app.focusCycle()); },
        // folded (3.5): the ask brings the overlay out, in its card under the host on the terminal ground
        "ask-folded": () => { meet([micAndCamera()]); app.setFold(false); },
        // the same over a long page scrolled a third of the way: only the overlay's strip is covered
        "ask-folded-long": () => { meet([micAndCamera()]); scrolled(false); app.setFold(false); },
        // 8j: the browser's own asks, in the ask layout
        "ask-signin": () => {
            page("router.lan", "http://router.lan/", "R", "#5b6b7a").asks = [{ id: 1, kind: "signin", host: "router.lan", secure: false }];
            later(() => { app.askSheet.section.fill("user", "admin"); app.askSheet.section.fill("password", "hunter22") });
        },
        "ask-proxy": () => { everyday(); app.currentView.asks = [{ id: 1, kind: "proxy", host: "proxy.lokal:3128" }]; },
        // the host as BrowserView makes it from WebEngineClientCertificateSelection.host
        "ask-certificate": () => page("vpn.lokal", "https://vpn.lokal/", "V", "#2d5f8a").asks = [{ id: 1, kind: "certificate",
            host: RailRows.split(Asks.tlsOrigin("//vpn.lokal:443")).host, options: ["abdul · Sectigo · 2027", "abdul · work CA · 2026", "No certificate"] }],
        "ask-leave": () => { everyday(); app.currentView.asks = [{ id: 1, kind: "leave", host: "github.com" }]; },
        "ask-passkey": () => page("Sign in to GitHub", "https://github.com/login", "G", "#24292f").asks = [{ id: 1, kind: "passkey", host: "github.com", state: "touch" }],
        "ask-passkey-pin": () => {
            page("Sign in to GitHub", "https://github.com/login", "G", "#24292f").asks = [{ id: 1, kind: "passkey", host: "github.com", state: "CollectPin",
                pinReason: "Challenge", pinError: "WrongPin", attempts: 2 }];
            later(() => app.askSheet.section.fill("pin", "1234"));
        },
        "ask-screen": () => meet([{ id: 1, kind: "screen", host: "meet.google.com", screens: 1,
            options: ["Entire screen · eDP-1", "Window · foot  ~/book4-edge/camss", "Window · Code"] }]),
        "ask-external": () => page("Free torrents - WebTorrent", "https://webtorrent.io/free-torrents", "W", "#b0452c").asks = [
            { id: 1, kind: "external", host: "webtorrent.io", scheme: "magnet", app: "qBittorrent" }],
        "ask-external-none": () => page("Free torrents - WebTorrent", "https://webtorrent.io/free-torrents", "W", "#b0452c").asks = [
            { id: 1, kind: "external", host: "webtorrent.io", scheme: "magnet", app: "" }],
        // PLAN.md 7: a login form sent on GitHub, the page it went on to: "Save password for github.com? Save · Not now"
        "password-save": () => { signedIn([passwordAsk(1)]); },
        // F6 from the page: the keys on Save
        "password-save-keys": () => { signedIn([passwordAsk(1)]); later(() => app.focusCycle()); },
        // stacked (PLAN.md 11): a link to another app outranks it, which waits behind with "1 of 2"
        "password-save-behind": () => { signedIn([passwordAsk(1), { id: 2, kind: "external", host: "github.com", scheme: "zoommtg", app: "Zoom" }]); },
        // folded: it brings the overlay out, as an ask does, on the terminal ground
        "password-save-folded": () => { signedIn([passwordAsk(1)]); app.setFold(false); },
        // the keyring's unlock refused at Save: the card's short word
        "password-not-saved": () => { signedIn([]); app.showNotice({ text: "Not saved: the keyring stayed locked", action: "", where: "card" }, 60000); },
        // GitHub's sign-in, the user name field with the keys: the Fill rows of the two logins saved for github.com
        "password-fill": () => { loginField("user"); },
        // F6 from the field: the keys on the first Fill row
        "password-fill-keys": () => { loginField("user"); later(() => app.focusCycle()); },
        // a router over plain http: its Fill row and, the password field having the keys, the password note under it
        "password-fill-insecure": () => {
            page("router.lan", "http://router.lan/", "R", "#5b6b7a");
            logins();
            app.currentView.loginField = { origin: "http://router.lan", role: "password" };
            app.currentView.loginFocused = true;
            app.currentView.passwordFocused = true;
        },
        // folded, F6 from the field: the overlay out with the Fill rows, the keys on the first
        "password-fill-folded": () => { loginField("user"); app.setFold(false); app.focusCycle(); },
        // a notification ask made without a click: only the bell; the microphone allowed for this load
        "ask-bell": () => {
            meet([{ id: 1, kind: "permission", host: "meet.google.com", origin: "https://meet.google.com", types: ["notifications"], quiet: true }]);
            app.currentView.inUse = ["microphone"];
            session.update(session.currentPage, { capturing: "mic", needsYou: false });
        },
        // 8j: the page's confirm, the second in its page load, so it offers to block the rest
        "dialog-confirm": () => { everyday(); dialog("confirm", "Discard this comment? Your text will be lost.", "", true); },
        "dialog-prompt": () => { everyday(); dialog("prompt", "Name the branch for this fix:", "camss-x1p-lanes", false); },
        // folded: the page takes the window, the dialog stays docked to its top
        "dialog-alert-folded": () => { everyday(); app.setFold(false); dialog("alert", "This issue was locked while you were editing. Your comment was not posted.", "", false); },
        // 3.20: a link from another app, a task of one in front, where it came from under it
        "link-from-app": () => {
            seed();
            const id = session.addPage(session.newThread("lore.kernel.org"), "https://lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org/", "");
            session.update(id, { title: "[PATCH v3 2/4] media: qcom: camss: add x1p42100 CSIPHY lane config", icon: favicon("L", "#4d5b6a"),
                                 from: "foot", fromAt: Date.now() - 60000 });
            session.setOpen(session.threads[1].id, true);
            app.show(id);
        },
        // a popup refused for want of a click: the glyph at the card's right
        "popup-blocked": () => { everyday(); app.currentView.blockedPopups = 1; },
        // 8l: a file input's pick is open in Files
        "file-pick": () => { everyday(); app.currentView.choosing = { mode: "multiple" }; },
        // 8m: YouTube's player in page full screen, just entered; then Meet in full screen when it asks
        "fullscreen": () => {
            seed();
            app.show(session.threads[4].pages[0]);
            app.currentView.dark = true;
            app.currentView.isFullScreen = true;
        },
        "fullscreen-ask": () => {
            meet([]);
            app.currentView.isFullScreen = true;
            later(() => { const a = micAndCamera(); app.currentView.asks = [a]; app.asked(session.currentPage, a); });
        },
        // 8f: the lore page reloaded with no network; Details open
        "failure-offline": () => offline(false),
        "failure-offline-details": () => offline(true),
        // 8f's other causes: a name with no address (a host one edit away in history), no reply in 30 s
        "failure-name": () => {
            everyday();
            fail(Failures.load({ url: "https://lore.kernl.org/linux-media/", at: at(14, 12), code: -105, domain: "connection", name: "net::ERR_NAME_NOT_RESOLVED",
                                 reachability: "online", watching: true, hosts: ["github.com", "lore.kernel.org", "git.kernel.org"] }));
        },
        "failure-no-answer": () => {
            everyday();
            fail(Failures.load({ url: "https://lore.kernel.org/linux-media/", at: at(14, 12), code: 0, waited: 30 }));
        },
        // 8g: an expired certificate, its facts and Continue under them; then the page loaded past it once
        "failure-certificate": () => certificate(),
        "failure-certificate-details": () => { certificate(); later(() => failures.open = true); },
        "failure-certificate-hsts": () => certificate({ url: "https://github.com/", overridable: false, type: -202, names: ["github.com"], subject: "github.com" }),
        "failure-certificate-continued": () => {
            const v = certificate();
            v.questioned = v.failure;
            v.failure = null;
        },
        // 8h: the YouTube page's process killed by oomd while on screen; two pages that shared it unloaded
        "crash": () => crash({ how: "killed", code: 0, memory: { bytes: 1.1 * 1073741824, at: at(14, 31) },
                               stop: { source: "systemd-oomd", at: at(14, 31) }, siblings: 2 }, true),
        "crash-twice": () => crash({ how: "exited", code: 250, memory: { bytes: 640 * 1048576, at: at(14, 40) }, siblings: 0, twice: true }, false),
        // PLAN.md 3.17's table: the browser's own and special pages in the address card and the rail
        "internal-file": () => specialPages("file"),
        "internal-data": () => specialPages("data"),
        "internal-data-edit": () => { specialPages("data"); app.editAddress(); },
        "internal-source": () => specialPages("source"),
        "internal-blank": () => specialPages("blank"),
        // 8i: the browser did not close cleanly; nothing loads, the page that was on screen is offered
        "restore": () => restore(false),
        // it stopped the browser again within a minute of opening it: left out, into Earlier
        "restore-left-out": () => restore(true),
        // the floating scrollbar on a long page just scrolled; hovered (8 px); on a near-black page
        "scrolled": () => { everyday(); scrolled(false); },
        "scrolled-hover": () => { everyday(); scrolled(false); pageScroll.wide = true; },
        "scrolled-dark": () => { everyday(); scrolled(true); },
        "scrolled-dark-hover": () => { everyday(); scrolled(true); pageScroll.wide = true; },
        // 3.11: right-click a page row; the row takes 8 %, the menu crosses onto the page
        "row-menu": () => { everyday(); rail.showMenu("p:" + session.threads[0].pages[0]); },
        "row-menu-move": () => { everyday(); rail.showMenu("p:" + session.threads[0].pages[0], true); },
        "thread-menu": () => { everyday(); rail.showMenu("t:" + session.threads[1].id); },
        "always-menu": () => { everyday(); session.update("a0", { state: "frozen" }); rail.showMenu("a:a1"); },
        // 3.13: a page held between two pages of the open thread (the 2 px line), and over a folded thread
        // 3.17: Ctrl+N after a window closed: the new window's rail has no threads of its own, Earlier and Always are
        // every window's (the closed window's Flights thread first in Earlier), and the card offers the window back
        "window-new": () => {
            everyday();
            const w = secondWindow(["Flights ARN - MGQ", "Momsdeklaration - Skatteverket"]);
            w.show(session.threads.find(t => t.title === "Flights ARN - MGQ").pages[0]);
            w.close();
            later(() => { const n = app.newWindow(app.windowState(), ""); n.afterClose(); shots.window = n; later(() => settle.restart()) });
        },
        // 3.14: Ctrl+Shift+N: a private window with its new-page card, the "Private" line under the nav row, nothing else
        // marked; no Earlier, Always or Downloads, and none of the main window's threads
        "private-new": () => {
            everyday();
            later(() => { const w = app.newPrivateWindow(app.windowState()); w.afterClose(); shots.window = w; later(() => settle.restart()) });
        },
        // 3.14's frame: the flights thread, opened in the private window, SAS on screen
        "private-window": () => {
            everyday();
            later(() => {
                const w = app.newPrivateWindow(app.windowState()), s = w.windowSession;
                const t = s.newThread("Flights ARN - MGQ");
                const sas = s.addPage(t, "https://www.flysas.com/en/booking/passengers?from=ARN&to=MGQ", "");
                s.update(sas, { title: "SAS · Stockholm - Mogadishu", icon: favicon("F", "#1d3b6e") });
                const turkish = s.addPage(t, "https://www.turkishairlines.com/en-se/flights/booking/", "");
                s.update(turkish, { title: "Turkish · ARN - MGQ", icon: favicon("T", "#c8102e"), state: "frozen" });
                w.show(sas);
                shots.window = w;
                later(() => settle.restart());
            });
        },
        // folded: the overlay rail of a private window carries the same line
        "private-folded": () => {
            everyday();
            later(() => {
                const w = app.newPrivateWindow(app.windowState()), s = w.windowSession;
                const t = s.newThread("Flights ARN - MGQ");
                const sas = s.addPage(t, "https://www.flysas.com/en/booking/passengers?from=ARN&to=MGQ", "");
                s.update(sas, { title: "SAS · Stockholm - Mogadishu", icon: favicon("F", "#1d3b6e") });
                w.show(sas);
                w.setFold(false);
                w.windowHover.open = true;
                shots.window = w;
                later(() => settle.restart());
            });
        },
        // 3.13, 3.17: a thread from another window's rail over this one: the 2 px line where it will land
        "window-drop": () => {
            everyday();
            const t = session.threads.find(x => x.title === "Flights ARN - MGQ");
            secondWindow([t.title]);
            later(() => rail.incoming = { kind: "thread", ref: t.id, target: rail.dropAt(rowY("Standup", 0.1), true) });
        },
        "drag": () => { everyday(); dragTo("x1e80100 camcc", 0.4, 0.2); },
        "drag-onto-thread": () => { everyday(); dragTo("x1e80100 camcc", 0.55, 0.5, "Flights ARN - MGQ"); },
        "drag-to-always": () => { everyday(); later(() => { rail.startDrag(session.threads[0].pages[2], 500); rail.moveDrag(rail.alwaysRow.y + 10); }); },
        // 3.12: a link from a thread of one: it grows a header, the page slides under it
        "opener-join": () => {
            seed();
            const solo = session.threads[3].pages[0];
            app.show(solo);
            const id = session.addFromOpener(solo, "https://www.skatteverket.se/foretag/moms/momsregistrering", "skatteverket.se");
            // live at once, as Main.openFromOpener makes it
            session.update(id, { state: "live" });
        },
        // 8d downloads: the lore page's mbox, running with the pointer on it; finished; failed
        "download-running": () => { everyday(); rail.hoverKey = "d:d0"; },
        "download-finished": () => {
            everyday();
            session.updateDownload("d0", { state: "done", received: 8.4e6, finished: Date.now() - 2000 });
            session.update(session.threads[0].pages[0], { downloading: false });
            rail.hoverKey = "d:d0";
        },
        "download-failed": () => {
            everyday();
            session.updateDownload("d0", { state: "failed", reason: "network" });
            session.update(session.threads[0].pages[0], { downloading: false });
        },
        // several from one page as one row; a download from the Gmail cell, which has no row, in the Downloads group
        "downloads-several": () => several(false),
        // a click on the row lists them in place
        "downloads-listed": () => several(true),
        // a finished program and an http file from an https page wait on you, each on its own row
        "download-warnings": () => {
            const id = releases();
            session.downloads = session.downloads.concat([
                download("d1", id, "flash-tool.AppImage", 48e6, 1, "done", { warn: "program", finished: at(14, 21) }),
                download("d2", id, "driver.run", 2.2e6, 0, "blocked"),
            ]);
        },
        // the camera thread folded while another page is on screen: its ↓ before the count
        "download-folded": () => { seed(); app.show(session.threads[4].pages[0]); },
        // the rail folded: a download that starts says so for 3 s in the docked label
        "download-notice": () => { everyday(); app.setFold(false); app.downloadStarted("d0"); },
        // 3.9: the site panel on the Lofi Girl page, grown from the rail's card over the rows, Microphone's
        // choices out as the frame draws them; then the certificate (›), All permissions and the clear's undo
        "site": () => lofiSite("microphone"),
        "site-certificate": () => { lofiSite(""); shots.site.sub = "certificate"; },
        "site-all": () => { lofiSite(""); shots.site.sub = "all"; },
        "site-clear": () => {
            lofiSite("");
            shots.site.clearing = { origin: "https://www.youtube.com", host: "www.youtube.com" };
            shots.site.left = 6;
            app.unloadSite("https://www.youtube.com");
        },
        // an https page with an image that came over http
        "site-mixed": () => {
            page("Notes on the Book4 port", "https://blog.example.se/book4-port", "B", "#8a5a2b");
            app.openSite("");
            siteFacts({ protocol: "TLS 1.3", sha256: "1f:22" }, { blocked: 3, insecureImages: true }, 2);
        },
        // plain http: Not secure, and no certificate to show
        "site-insecure": () => { insecure(false); app.openSite(""); siteFacts(null, { blocked: 0, insecureImages: false }, 1); },
        // folded (3.5): the overlay held out with the panel over its rows
        "site-folded": () => { app.setFold(false); lofiSite(""); },
        // Site settings in Meet's ask: the panel at the ask's row, the ask waiting on its last line
        "site-ask": () => { meet([micAndCamera()]); shots.site.sites.noteAsked("https://meet.google.com", ["microphone", "camera"]); app.openSite("microphone"); siteFacts({ protocol: "TLS 1.3", sha256: "aa" }, { blocked: 12, insecureImages: false }, 9); },
        // 3.9 Reader view on an article: its row between Zoom and / opens find, Ctrl+Alt+R at its right
        "site-reader": () => { article(false); app.openSite(""); siteFacts({ protocol: "TLS 1.3", sha256: "3a:9c" }, { blocked: 9, insecureImages: false }, 3); },
        // the article shown in the page's place: the row on the picked wash
        "site-reader-on": () => { article(true); app.openSite(""); siteFacts({ protocol: "TLS 1.3", sha256: "3a:9c" }, { blocked: 9, insecureImages: false }, 3); },
        // "off: no article": GitHub's issue list, where Readability finds none
        "site-no-article": () => { noArticle(); app.openSite(""); siteFacts({ protocol: "TLS 1.3", sha256: "91:0e" }, { blocked: 0, insecureImages: false }, 12); },
        // Ctrl+Alt+R there: "No article here" in the card for 3 s
        "reader-none": () => { noArticle(); app.showNotice({ text: "No article here", action: "", where: "card" }, 60000); },
        // PLAN.md 7: > in the address card, Print and Reader view after Reload
        "address-actions": () => { everyday(); app.editAddress(">"); },
        // > reader with no article on the page: the row says so, and Enter does nothing
        "address-actions-no-article": () => { noArticle(); app.editAddress(">reader"); },
        // 3.16 Ctrl+P on the issue page: the card in the Ctrl+T card's place over the scrim, the preview (a sample PDF: shots
        // make no page PDF), the rows as the frame has them
        "print": () => { everyday(); printPage(); },
        // Paper ›: its choices in place, A4 picked
        "print-choices": () => { everyday(); printPage(); app.windowPrint.sub = "paper"; },
        // Destination ›: Save as PDF and CUPS's printers
        "print-destination": () => { everyday(); printPage(); app.windowPrint.sub = "destination"; },
        // a printer picked, the preview turned to page 2, This page: the button says Print
        "print-printer": () => { everyday(); printPage(); const c = app.windowPrint; c.set("destination", "Brother_HL-L2350DW"); c.page = 2; c.set("pages", "this"); },
        // folded: the card over the whole page
        "print-folded": () => { everyday(); app.setFold(false); printPage(); },
        // Print: the card closed, "Sent to <printer>" in the address card for 3 s
        "print-sent": () => { everyday(); app.showNotice({ text: "Sent to Brother_HL-L2350DW", action: "", where: "card" }, 60000); },
        // Save: the PDF as a download row under the page, the pointer on it
        "print-saved": () => {
            everyday();
            app.printSaved("issue212", app.shots.samplePdf("camss: CSIPHY0 lanes ignored on x1p42100 · Issue #212.pdf", session.pages.issue212.title, printLines, 3));
            rail.hoverKey = "d:" + session.downloads[session.downloads.length - 1].id;
        },
        // a site zoomed to 110 %: the value at the card's right
        "zoomed": () => { everyday(); app.currentView.zoomFactor = 1.1; },
        // F6 into the rail list: the focus ring on the current row, then one row down
        "rail-keys": () => { everyday(); rail.focusList(); rail.moveCursor(1); },
        "rename": () => { everyday(); later(() => rail.startRename(session.threads[0].id)); },
        // 3.12: a long thread at the narrowest rail; the list scrolls to keep the current row in view
        "overflow": () => {
            seed();
            app.railWidth = 248;
            const t = session.threads[1];
            for (let i = 0; i < 36; i++)
                session.addPage(t.id, "https://github.com/qt/qtwebengine/pull/" + (812 + i), "");
            for (const id of t.pages.slice(4))
                session.update(id, { title: "PR #" + (808 + t.pages.indexOf(id)) + " - review qtwebengine 6.11 port", state: "frozen" });
            app.show(t.pages[30]);
        },
    })

    property string current: ""
    // longer than the slowest motion (a fold's lift and tuck, 660 ms), so every shot shows a settled state
    property Timer settle: Timer { interval: 900; onTriggered: shots.app.shots.capture(shots.current, shots.window) }
    property var window: null           // the window to grab when not the first (PLAN.md 3.17)

    Component.onCompleted: Qt.callLater(run)

    function run() {
        current = app.shots.begin(Object.keys(scenarios));
        if (current === "")
            return;
        // a made-up Zen profile to import from (PLAN.md 3.4)
        Zen.fake({ name: "Default (release)", path: "/home/you/.config/zen/k3v9w2qa.Default (release)" });
        app.requestActivate();
        scenarios[current]();
        settle.start();
    }

    function welcomeFile(phase) {
        Object.assign(welcome, { mode: "file", notice: "", fileFrom: "Bitwarden", chosen: 0,
                                 sources: [{ name: "A password manager's file", kind: "file", glyph: "upload_file" }],
                                 kinds: [{ label: "Passwords", done: 141, total: 286 }],
                                 result: { file: true, from: "Bitwarden", added: 271, kept: 15,
                                           stayed: [{ what: "12 entries", why: "not a login (a note, a card or an identity)" },
                                                    { what: "3 entries", why: "an app's, with no web address" }] } });
        welcome.phase = phase;
    }
    // sample browsers for Welcome: real icons from the icon theme, made-up counts; `edit` changes the kinds
    function welcomeSample(phase, edit) {
        const icon = n => "file:///usr/share/icons/hicolor/128x128/apps/" + n + ".png";
        welcome.sources = [
            { name: "Google Chrome", profile: "Personal", email: "you@gmail.com", kind: "chromium", icon: icon("google-chrome"),
              counts: { passwords: 312, bookmarks: 1204, tabs: 9, sites: 41 } },
            { name: "Google Chrome", profile: "Work", email: "you@company.se", kind: "chromium", icon: icon("google-chrome"),
              counts: { passwords: 64, bookmarks: 88, tabs: 4, sites: 12 } },
            { name: "Zen", kind: "firefox", icon: icon("zen-browser"), counts: { passwords: 86, bookmarks: 240, tabs: 3, sites: 17 } },
            { name: "A password manager's file", kind: "file", glyph: "upload_file" }];
        welcome.exportGuide = [
            { service: "Google Password Manager", steps: "passwords.google.com › Settings › Export passwords" },
            { service: "Apple Passwords", steps: "Passwords on a Mac › File › Export All Passwords" },
            { service: "Bitwarden", steps: "Tools › Export vault, as .csv" },
            { service: "1Password", steps: "File › Export, then CSV" },
            { service: "Firefox", steps: "about:logins › ··· › Export passwords" }];
        welcome.chosen = 0;
        const kinds = [
            { label: "Passwords", done: 312, total: 312 }, { label: "Bookmarks", done: 1204, total: 1204 },
            { label: "History", done: 6120, total: 14870 }, { label: "Open tabs", done: 0, total: 9 },
            { label: "Signed-in sites", done: 0, total: 41 }];
        if (edit)
            edit(kinds);
        welcome.kinds = kinds;
        welcome.result = { from: "Chrome · Personal", sitesCame: 41, google: true, tabsCame: 9,
                           figures: [{ value: 312, label: "passwords", place: "Passwords" }, { value: 1204, label: "bookmarks", place: "Saved" },
                                     { value: 14870, label: "pages of history", place: "History" }, { value: 9, label: "open tabs", place: "the rail" }],
                           stayed: [{ what: "4 passkeys", why: "Thyris can't use passkeys yet" },
                                    { what: "2 extensions", why: "they install from Google's store" },
                                    { what: "Passwords kept only in your Google account", why: "they aren't on this computer", link: "Bring them with a file" }] };
        welcome.phase = phase;
    }

    function everyday() {
        seed();
        app.show("issue212");
    }

    // Settings (3.15) opened by Ctrl+, (`section` as Ctrl+/ and Ctrl+Shift+Delete give it), with what the page would read
    // from the profile, the ad blocker and the desktop, which shots have none of
    function settings(section) {
        const now = Date.now(), day = 86400000, at = h => { const d = new Date(now); d.setHours(h, 10, 0, 0); return d.getTime() };
        app.windowSettings.shotState = {
            defaultBrowser: "yes", folder: "/home/you/Downloads", home: "/home/you",
            fonts: { standard: "Noto Serif", serif: "Noto Serif", sansSerif: "Noto Sans", fixed: "Noto Sans Mono", size: 16, minimum: 0 },
            languages: ["en-GB", "sv"], dictionaries: { "en-GB": "ready", sv: "" },
            allowed: ["https://lwn.net", "https://www.skatteverket.se", "https://github.com"],
            lists: [{ file: "ubo-filters", modified: at(6), version: "2026.928.1504" }, { file: "ubo-privacy", modified: at(6), version: "2026.928.1504" },
                    { file: "ubo-badware", modified: at(6), version: "2026.927.1622" }, { file: "ubo-quick-fixes", modified: at(6), version: "2026.929.512" },
                    { file: "ubo-unbreak", modified: at(6), version: "2026.926.1903" }, { file: "easylist", modified: at(6), version: "202609290512" },
                    { file: "easyprivacy", modified: at(6), version: "202609290512" }, { file: "pgl", modified: at(6) - day }],
            cookies: 214,
            extensions: [{ id: "ddkjiahejlhfcafbddmgiahcphecmpfh", name: "uBlock Origin Lite", enabled: true, error: "" }],
        };
        app.openOwn("settings", section ?? "");
    }
    // Settings at Import (3.15) with the import's state `z` as src/zen.* and Main would give it
    function zenShot(z) {
        settings("import");
        app.windowSettings.shotState = Object.assign({}, app.windowSettings.shotState, {
            zen: Object.assign({ profile: Zen.profile, state: "", wrong: false, logins: 0, run: null, last: null, failure: null, sites: -1, tabs: -1, cookies: true, openTabs: true }, z) });
    }
    // Pages and memory (3.17) with the seeded threads as the rail shows them and processes as /proc would say them: the
    // camera thread's pages in one process (the patch live while its file comes), Lofi Girl live for its sound, Meet
    // live, this page on screen, the rest unloaded
    function pagesAndMemory() {
        const mb = n => n * 1048576, of = title => session.threads.find(t => t.title === title).pages;
        const camera = of("x1p42100 camera"), lofi = of("Lofi Girl - radio")[0], meet = of("Standup 23 Sep")[0];
        const pids = { [camera[0]]: 4121, [camera[1]]: 4121, [camera[2]]: 4121, [lofi]: 4388, [meet]: 4502 };
        const states = { [camera[0]]: "live", [camera[1]]: "frozen", [camera[2]]: "frozen", [lofi]: "live", [meet]: "live" };
        app.openOwn("pages", "");
        const own = session.currentPage;
        app.windowPages.live = false;
        app.windowPages.measured = { at: Date.now(),
            pages: app.memoryPages().map(p => Object.assign({}, p, { pid: p.id === own ? 4610 : pids[p.id] ?? 0, state: p.id === own ? "live" : states[p.id] ?? "unloaded" })),
            processes: [
                { pid: 3890, type: "", service: "", bytes: mb(412) }, { pid: 3921, type: "gpu-process", service: "", bytes: mb(236) },
                { pid: 3924, type: "utility", service: "network.mojom.NetworkService", bytes: mb(58) },
                { pid: 3925, type: "utility", service: "storage.mojom.StorageService", bytes: mb(31) },
                // page processes are forked from the zygote, whose command line they keep
                { pid: 3930, parent: 3890, type: "zygote", service: "", bytes: mb(24) }, { pid: 4121, parent: 3930, type: "zygote", service: "", bytes: mb(684) },
                { pid: 4388, parent: 3930, type: "zygote", service: "", bytes: mb(233) }, { pid: 4502, parent: 3930, type: "zygote", service: "", bytes: mb(318) },
                { pid: 4610, parent: 3930, type: "zygote", service: "", bytes: mb(38) }] };
    }

    // A second main window (Ctrl+N) holding the seeded threads titled `titles`.
    function secondWindow(titles) {
        const w = app.newWindow(app.windowState(), "");
        for (const t of session.threads)
            if (titles.indexOf(t.title) >= 0)
                t.window = w.windowId;
        session.revision++;
        return w;
    }

    // Holds the page titled `title` and moves it to a fraction of the way down the rail list, or onto the
    // row titled `over` at `at` of its height.
    // Runs once the window has its size and the rail its rows (the scenario runs before layout).
    function dragTo(title, from, to, over) {
        later(() => {
            const id = Object.keys(session.pages).find(k => session.pages[k].title.startsWith(title));
            rail.startDrag(id, rail.height * from);
            rail.moveDrag(over ? rowY(over, to) : rail.height * to);
        });
    }
    property var pending: null
    property Timer laterTimer: Timer { interval: 200; onTriggered: shots.pending() }
    function later(fn) {
        pending = fn;
        laterTimer.start();
    }
    function rowY(title, at) {
        const list = rail.listView;
        for (let i = 0; i < list.count; i++) {
            const it = list.itemAtIndex(i);
            if (it && it.title.startsWith(title))
                return list.y + it.y - list.contentY + it.height * at;
        }
        return 0;
    }

    // a long page with three sections as Recall.sections would read them (the page's ground as its stand-in paints it),
    // 45 % down; `held`: the strip's thumb held there
    function sectioned(dark, held) {
        app.currentView.repeats = 40;
        app.currentView.dark = dark;
        later(() => {
            const v = app.currentView, max = v.contentsSize.height - v.height;
            v.sections = { line: 120, ground: dark ? [17, 18, 20] : [251, 251, 250],
                           list: [{ name: "Description", level: 2, top: 40 }, { name: "Steps", level: 2, top: max * 0.36 + 120 },
                                  { name: "Comments · 12", level: 2, top: max * 0.63 + 120 }] };
            v.scrollPosition = Qt.point(0, max * 0.45);
            if (held) {
                app.windowStrip.dragTo = max * 0.45;
                app.windowStrip.dragging = true;
            }
        });
    }
    // a long page, scrolled a third of the way down
    function scrolled(dark) {
        app.currentView.repeats = 40;
        app.currentView.dark = dark;
        later(() => { const v = app.currentView; v.scrollPosition = Qt.point(0, (v.contentsSize.height - v.height) / 3); });
    }

    // Find open on the page on screen with `text`, as the page answered; `also`: the camera thread's other
    // pages as 8e lists them (stand-in pages run no count script)
    function find(text, result, also) {
        app.openFind(text);
        const f = rail.finder;
        f.result = result;
        if (!also)
            return;
        const t = session.threadById(session.current.thread);
        f.hits = [[0, 5], [2, 2]].map(([i, n]) => { const q = session.pages[t.pages[i]]; return { pageId: q.id, title: q.title, icon: q.icon, count: n } });
        f.skipped = "1 unloaded page skipped";
    }

    // The site panel on the Lofi Girl page (a YouTube thread of one) with `row`'s choices out, as the page, the
    // interceptor and the handshake answered: notifications blocked, the microphone allowed, zoom 110 %.
    function lofiSite(row) {
        seed();
        app.show(session.threads[4].pages[0]);
        const origin = "https://www.youtube.com";
        shots.site.sites.entries = { [origin]: { choices: { notifications: "block", microphone: "allow", zoom: 1.1 }, asked: { notifications: 1, microphone: 2 } } };
        shots.site.sites.revision++;
        app.currentView.zoomFactor = 1.1;
        app.openSite(row);
        siteFacts(youtubeTls(), { blocked: 214, insecureImages: false }, 14);
    }
    // An LWN article as a thread of one, current, which has an article (Readability-readerable's answer), shown when `on`
    function article(on) {
        const v = page("Lane configuration for camera PHYs [LWN.net]", "https://lwn.net/Articles/991234/", "L", "#e3b341");
        v.article = "yes";
        v.reader = on;
    }
    // GitHub's issue list, where Readability finds no article
    function noArticle() {
        page("Issues · linux-msm/linux", "https://github.com/linux-msm/linux/issues", "G", "#24292f").article = "none";
    }
    // Ctrl+P on the page on screen, its preview a sample PDF of the stand-in page's text over three pages
    readonly property var printLines: ["The ov02c10 probes on CSIPHY0, but data-lanes from the DT is ignored and the PHY is set up",
        "for 4 lanes. The v3 series on lore fixes it; see the link below.", "",
        "Steps: boot with the x1p42100 DTB, run cam -l, the sensor lists, capture is black.",
        "lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org", "", "Tested v3 on the Book4 Edge: capture works, 1928x1092 at 30 fps.", ""]
    function printPage() {
        app.openPrint();
        app.windowPrint.preview = app.shots.samplePdf("print-preview.pdf", session.current.title, printLines, 3);
    }
    function youtubeTls() {
        return { protocol: "TLS 1.3", cipher: "TLS_AES_128_GCM_SHA256", subject: "www.youtube.com", issuer: "WR2 · Google Trust Services",
                 until: new Date(2026, 11, 1).getTime(), sha256: "7c:3e:91:0a:5d:e2:44:b1:9f:03:6c:d8:21:7e:aa:40:15:c6:8b:32:f9:57:0e:d4:6a:91:bb:03:7f:28:c5:e1",
                 pem: "-----BEGIN CERTIFICATE-----" };
    }
    // what the panel learns as it opens: the handshake, the interceptor's count, the cookie store's
    function siteFacts(tls, seen, cookies) {
        shots.site.tls = tls;
        shots.site.seen = seen;
        shots.site.cookies = cookies;
        shots.site.blocker = true;
    }

    // Three files from the Releases page, one still coming, and Gmail's export in the Downloads group
    function several(listed) {
        const id = releases();
        session.downloads = session.downloads.concat([
            download("d1", id, "qdl-2.3-x86_64.tar.gz", 1.6e6, 1, "done", { finished: at(14, 18) }),
            download("d2", id, "qdl-2.3-aarch64.tar.gz", 1.5e6, 1, "done", { finished: at(14, 18) }),
            download("d3", id, "firmware-x1p42100.zip", 11e6, 0.12, "running", { left: 40 }),
            download("d4", "a0", "inbox-export-2026-09.mbox", 310e6, 0.6, "running", { left: 95,
                from: { title: "(12) Inbox - Gmail", icon: session.pages.a0.icon, always: true } }),
        ]);
        if (listed)
            rail.downloads.toggleListed(id);
    }

    // the current page's dialog, as BrowserView makes it
    function dialog(type, message, text, second) {
        const url = String(app.currentView.url);
        app.currentView.dialog = { type: type, message: message, text: text, says: PageState.says(url), site: PageState.pageHost(url) || "This page",
                                   block: second ? PageState.blockMore(url) : "" };
    }

    // today at hh:mm
    function at(h, m) { const d = new Date(); d.setHours(h, m, 0, 0); return d.getTime() }
    // the current stand-in page's failure, as BrowserView keeps it
    function fail(page) { app.currentView.failure = Object.assign(page, { committed: true }) }
    function offline(details) {
        seed();
        app.show(session.threads[0].pages[0]);
        fail(Failures.load({ url: session.current.url, at: at(14, 12), code: -106, domain: "connection", name: "net::ERR_INTERNET_DISCONNECTED",
                             reachability: "none", watching: true, hosts: [] }));
    }
    // expired.badssl.com as a thread of one; returns its view
    function certificate(c) {
        const f = Object.assign({ url: "https://expired.badssl.com/", type: -201, overridable: true, names: ["*.badssl.com", "badssl.com"],
                                  subject: "*.badssl.com", issuer: "COMODO RSA Domain Validation Secure Server CA",
                                  from: new Date(2015, 3, 9).getTime(), until: new Date(2015, 3, 12, 23, 59).getTime(),
                                  sha256: "ba:10:5c:3f:6a:4d:e1:77:09:c2:be:5d:0e:8a:e6:23:f7:5d:61:05:9b:32:c5:4e:1a:90:7b:6c:48:ea:12:d3" }, c ?? {});
        const v = page(PageState.pageHost(f.url), f.url, "B", "#6b6b6b");
        session.update(session.currentPage, { icon: "" });
        v.failure = Object.assign(Failures.certificate(Object.assign({ at: at(14, 20), now: Date.now() }, f)), { committed: true });
        return v;
    }
    // a thread of four YouTube and Docs pages; the first on screen, stopped, and the next two unloaded with it
    function crash(facts, siblings) {
        seed();
        const t = session.newThread("Wedding DJ set");
        const yt = favicon("Y", "#b3261e");
        const ids = [["https://www.youtube.com/watch?v=vibin", "Vibin - wxoda - YouTube", yt], ["https://www.youtube.com/playlist?list=dj", "Playlist - YouTube", yt],
                     ["https://www.youtube.com/shorts/dj", "Shorts - YouTube", yt], ["https://docs.google.com/document/d/setlist", "Setlist - Docs", favicon("D", "#2f6fdb")]]
            .map(([url, title, icon]) => { const id = session.addPage(t, url, ""); session.update(id, { title: title, icon: icon, state: "frozen" }); return id; });
        if (siblings)
            for (const id of ids.slice(1, 3))
                session.update(id, { state: "unloaded" });
        app.show(ids[0]);
        fail(Failures.crash(Object.assign({ url: session.current.url, at: at(14, 31), pid: 48211 }, facts)));
    }
    function restore(leftOut) {
        seed();
        for (const id in session.pages)
            session.update(id, { state: "unloaded", audible: false });
        app.startAfter({ clean: false, alive: at(14, 2), page: "issue212", suspect: leftOut ? "issue212" : undefined });
    }

    // NeverSSL as a thread of one, over plain http
    function insecure(password) {
        seed();
        const id = session.addPage(session.newThread("NeverSSL - Connecting"), "http://neverssl.com/online", "");
        session.update(id, { title: "NeverSSL - Connecting", icon: favicon("N", "#3f6b3a") });
        app.show(id);
        app.currentView.passwordFocused = password;
    }

    // Passwords (PLAN.md 7): made-up logins in the keyring's list (Passwords.fake: shots have no keyring)
    readonly property var shotLogins: [
        { id: "/org/freedesktop/secrets/collection/login/1", origin: "https://github.com", user: "abdul" },
        { id: "/org/freedesktop/secrets/collection/login/2", origin: "https://github.com", user: "abdul-work" },
        { id: "/org/freedesktop/secrets/collection/login/3", origin: "https://lwn.net", user: "abdul" },
        { id: "/org/freedesktop/secrets/collection/login/4", origin: "http://router.lan", user: "admin" },
        { id: "/org/freedesktop/secrets/collection/login/5", origin: "https://www.skatteverket.se", user: "199001011234" },
    ]
    function logins() { Passwords.fake(shotLogins) }
    function passwordAsk(id) { return { id: id, kind: "password", host: "github.com", origin: "https://github.com", user: "abdul", password: "" } }
    // GitHub as a thread of one, current, after its sign-in form was sent, with `asks` queued on it
    function signedIn(asks) {
        page("GitHub", "https://github.com/", "G", "#24292f").asks = asks;
    }
    // GitHub's sign-in page, its `role` field ("user" or "password") with the keys
    function loginField(role) {
        page("Sign in to GitHub", "https://github.com/login", "G", "#24292f");
        logins();
        app.currentView.loginField = { origin: "https://github.com", role: role };
        app.currentView.loginFocused = true;
    }

    // Meet in the Standup thread, current, with `asks` queued on it
    function meet(asks) {
        seed();
        app.show(session.threads[2].pages[0]);
        app.currentView.asks = asks;
    }
    function micAndCamera() {
        return { id: 1, kind: "permission", host: "meet.google.com", origin: "https://meet.google.com", types: ["microphone", "camera"] };
    }
    // a thread of one, current; returns its view
    function page(title, url, letter, colour) {
        seed();
        const id = session.addPage(session.newThread(title), url, "");
        session.update(id, { title: title, icon: favicon(letter, colour) });
        app.show(id);
        return app.currentView;
    }

    // A thread of a local PDF, a data: page, the source of a page and a blank page (PLAN.md 3.17), `shown` on screen.
    // Only the file has a title: Chromium's stand-in for the others (their address) is none.
    function specialPages(shown) {
        seed();
        const t = session.newThread("S2MM006 datasheet");
        const ids = { file: session.addPage(t, "file:///home/you/Documents/datasheets/S2MM006.pdf", ""),
                      data: session.addPage(t, "data:text/html," + encodeURIComponent("<p>" + "x".repeat(4089) + "</p>"), ""),
                      source: session.addPage(t, "view-source:https://github.com/linux-msm/linux/pull/212", ""),
                      blank: session.addPage(t, "about:blank", "") };
        session.update(ids.file, { title: "S2MM006.pdf" });
        app.show(ids[shown]);
    }

    // the current stand-in page mid-load
    function loading(progress) {
        app.currentView.loading = true;
        app.currentView.loadProgress = Math.round(progress * 100);
    }

    // Letter favicons, like the [G] and [L] of the wireframes; page content, so not Theme colours.
    function favicon(letter, colour) {
        const svg = "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32'>"
            + "<rect width='32' height='32' rx='7' fill='" + colour + "'/>"
            + "<text x='16' y='22.5' font-family='sans-serif' font-size='17' font-weight='700' fill='#ffffff' text-anchor='middle'>"
            + letter + "</text></svg>";
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
    }

    // A download record as Downloader keeps it (Downloads.js), `fraction` of `total` bytes in.
    function download(id, page, file, total, fraction, state, fields) {
        return Object.assign({ id: id, page: page, url: "https://example.org/" + file, file: file, path: "/home/you/Downloads/" + file,
                               total: total, received: Math.round(total * fraction), left: -1, state: state, reason: "", warn: "",
                               started: Date.now() - 60000, finished: 0, opened: 0, from: null }, fields ?? {});
    }
    // The Releases page of the downloads frames (8d) in a thread after the camera one, current; its id
    function releases() {
        seed();
        const t = session.newThread("Flashing the Book4");
        const id = session.addPage(t, "https://github.com/linux-msm/qdl/releases", "");
        const readme = session.addPage(t, "https://github.com/linux-msm/qdl#readme", "");
        session.update(id, { title: "Releases · linux-msm/qdl", icon: favicon("G", "#24292f"), state: "live" });
        session.update(readme, { title: "linux-msm/qdl: Qualcomm download tool", icon: favicon("G", "#24292f"), state: "frozen" });
        session.moveThread(t, session.threads[2].id);
        app.show(id);
        return id;
    }

    // The session of PLAN.md 3.1: its audio, needs-you and Always are fields the real app fills as pages
    // play and ask; its download is a record as Downloader keeps one.
    function seed() {
        const now = Date.now(), min = 60000, day = 86400000;
        const icons = {
            github: favicon("G", "#24292f"), lore: favicon("L", "#4d5b6a"), kernel: favicon("K", "#3b5c85"),
            libcamera: favicon("C", "#6b4f8f"), sas: favicon("F", "#1d3b6e"), google: favicon("G", "#3c6fd8"),
            meet: favicon("M", "#1f7a68"), skatteverket: favicon("S", "#1e5b3c"), youtube: favicon("Y", "#b3261e"),
            arch: favicon("W", "#1793d1"), hyprland: favicon("H", "#2b8fb3"),
        };
        const threads = [], pages = {};
        let n = 0;
        function thread(title, list, fields) {
            const t = Object.assign({ id: "t" + threads.length, title: title, pages: [], lastActive: now - threads.length * min, earlier: false }, fields);
            for (const p of list) {
                const id = p.id ?? "p" + (n++);
                pages[id] = Object.assign({ id: id, thread: t.id, icon: "", lastActive: t.lastActive - t.pages.length * min, state: "frozen" }, p, { id: id });
                t.pages.push(id);
            }
            threads.push(t);
            return t;
        }

        const camera = thread("x1p42100 camera", [
            { url: "https://lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org/", title: "[PATCH v3] camss: CSIPHY0 lanes on x1p42100",
              icon: icons.lore, downloading: true },
            { id: "issue212", url: "https://github.com/linux-msm/linux/issues/212", title: "camss: CSIPHY0 lanes ignored on x1p42100 · Issue #212", icon: icons.github },
            { url: "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/clk/qcom/camcc-x1e80100.c",
              title: "x1e80100 camcc - kernel/git/torvalds/linux.git", icon: icons.kernel },
            { url: "https://lists.libcamera.org/pipermail/libcamera-devel/2026-September/052113.html",
              title: "Re: softisp AGC starves on GPU", icon: icons.libcamera, state: "unloaded" },
        ]);
        // the v3 page was the v2 patch until the thread moved on (3.2 2a: "In this thread")
        camera.trail = [{ url: "https://lore.kernel.org/linux-media/20260914-camss-x1p-v2-2@kernel.org/",
                          title: "[PATCH v2] camss: CSIPHY0 lanes on x1p42100", icon: icons.lore, left: now - 25 * min }];
        thread("Flights ARN - MGQ", [
            { url: "https://www.flysas.com/en/book/flights?from=ARN&to=MGQ", title: "SAS · Stockholm - Mogadishu", icon: icons.sas },
            { url: "https://www.google.com/travel/flights?q=ARN+MGQ", title: "Flights from Stockholm to Mogadishu", icon: icons.google },
            { url: "https://www.turkishairlines.com/en-se/flights/booking/", title: "Turkish Airlines · Book a flight", icon: favicon("T", "#c8102e") },
            { url: "https://www.flydubai.com/en/", title: "flydubai · Stockholm to Mogadishu", icon: favicon("D", "#0d3b66") },
        ]);
        thread("Standup 23 Sep", [
            { url: "https://meet.google.com/xqd-kmfa-pwe", title: "Meet - Standup", icon: icons.meet, needsYou: true, asking: "camera?" },
            { url: "https://docs.google.com/document/d/1standup/edit", title: "Standup notes - Google Docs", icon: favicon("D", "#2f6fdb") },
        ]);
        thread("Momsdeklaration - Skatteverket", [
            { url: "https://www.skatteverket.se/foretag/moms/deklareramoms", title: "Momsdeklaration - Skatteverket", icon: icons.skatteverket },
        ]);
        thread("Lofi Girl - radio", [
            { url: "https://www.youtube.com/watch?v=jfKfPfyJRdk", title: "Lofi Girl - radio", icon: icons.youtube, state: "live", audible: true },
        ]);
        thread("Hyprland blur", [
            { url: "https://wiki.hypr.land/Configuring/Variables/#blur", title: "Variables - Hyprland Wiki", icon: icons.hyprland },
            { url: "https://github.com/hyprwm/Hyprland/issues/9142", title: "blur: xray and popups · Issue #9142", icon: icons.github },
        ], { earlier: true, lastActive: now - 3 * 60 * min });
        const pd = [];
        for (let i = 1; i <= 12; i++)
            pd.push({ url: "https://www.ti.com/lit/an/slva" + (840 + i) + "/", title: "USB PD notes " + i, icon: favicon("P", "#7a5230") });
        thread("Book4 charging PD", pd, { earlier: true, lastActive: now - 2 * day });
        thread("Camera dark in Zen", [
            { url: "https://bugzilla.mozilla.org/show_bug.cgi?id=1901234", title: "Camera preview dark in Zen", icon: favicon("Z", "#3d3d3d") },
            { url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", icon: icons.arch },
            { url: "https://libcamera.org/getting-started.html", title: "Getting started - libcamera", icon: icons.libcamera },
            { url: "https://git.libcamera.org/libcamera/libcamera.git/tree/src/ipa/simple/algorithms/agc.cpp", title: "agc.cpp - libcamera", icon: icons.libcamera },
        ], { earlier: true, lastActive: now - 5 * day });

        const always = [
            { url: "https://mail.google.com/", title: "(12) Inbox - Gmail", icon: favicon("M", "#c5221f") },
            { url: "https://calendar.google.com/", title: "Calendar", icon: favicon("C", "#1a73e8") },
            { url: "https://claude.ai/", title: "Claude", icon: favicon("C", "#b8643c") },
            { url: "https://github.com/", title: "GitHub", icon: icons.github },
            { url: "https://www.youtube.com/", title: "YouTube", icon: icons.youtube },
        ].map((a, i) => {
            pages["a" + i] = Object.assign({ id: "a" + i, thread: "", lastActive: now - day, state: "frozen" }, a);
            return "a" + i;
        });

        // the v3 series as an mbox, 40 % in (PLAN.md 3.1, 8d)
        const lore = camera.pages[0];
        session.downloads = [download("d0", lore, "camss-v3.mbox", 8.4e6, 0.4, "running", { left: 12, started: now - 8000,
            from: { title: pages[lore].title, icon: icons.lore, always: false, url: pages[lore].url, thread: camera.title } })];

        session.threads = threads;
        session.pages = pages;
        session.always = always;
        session.learned = { threads: true, always: true };
        session.currentPage = "";
        session.revision++;

        history.entries = {
            "https://git.libcamera.org/libcamera/libcamera.git/tree/src/ipa/simple/algorithms/agc.cpp":
                { url: "https://git.libcamera.org/libcamera/libcamera.git/tree/src/ipa/simple/algorithms/agc.cpp", title: "agc.cpp - libcamera", icon: icons.libcamera, visits: 6, last: now - 1 * day },
            "https://wiki.archlinux.org/title/Libcamera":
                { url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", icon: icons.arch, visits: 3, last: now - 5 * day, saved: true },
            "https://www.flysas.com/en/book/flights?from=ARN&to=MGQ":
                { url: "https://www.flysas.com/en/book/flights?from=ARN&to=MGQ", title: "SAS · Stockholm - Mogadishu", icon: icons.sas, visits: 4, last: now - 90 * min },
        };
    }

    // PLAN.md 3.7's session over 3.1's: the Book4 thread filed yesterday with the pages 7a and 7b name (the datasheet shown
    // last, where you stopped at its 0x4E register, a file from it), Zen blur config filed two days ago, NeverSSL closed
    // this morning and book4-pd-charge 2 h ago, the ArchWiki's USB PD page in history, and Saved as 7c draws it.
    function recall() {
        seed();
        const now = Date.now(), min = 60000, day = 86400000;
        const book4 = session.threads.find(t => t.title === "Book4 charging PD");
        Object.assign(book4, { filedAt: now - day, lastActive: now - day });
        const named = [["https://www.samsung.com/semiconductor/power-ic/S2MM006.pdf", "S2MM006 PD controller - datasheet (PDF)", favicon("P", "#7a5230")],
                       ["https://www.renesas.com/isl9241/registers", "ISL9241 registers", favicon("R", "#2a4d8f")],
                       ["https://lore.kernel.org/linux-usb/ucsi-pd-renegotiation", "ucsi: PD renegotiation after resume", favicon("L", "#4d5b6a")]];
        named.forEach(([url, title, icon], i) => session.update(book4.pages[i], { url: url, title: title, icon: icon, lastActive: now - day - i * min }));
        const sheet = book4.pages[0];
        session.setStopped(sheet, { url: named[0][0], heading: "0x4E action register", index: 14, offset: 36, x: 0, y: 9120, percent: 38, at: now - day });
        session.setStopped(book4.pages[1], { url: named[1][0], heading: "", index: -1, offset: 0, x: 0, y: 4400, percent: 42, at: now - day });
        session.downloads = session.downloads.concat([download("d5", sheet, "S2MM006_rev1.4.pdf", 2.4e6, 1, "done", { finished: now - day - 5 * min, started: now - day - 6 * min })]);
        session.threads.find(t => t.title === "Hyprland blur").filedAt = now - 3 * 60 * min;
        const zen = session.newThread("Zen blur config");
        [["https://docs.zen-browser.app/guides/live-editing", "Live editing - Zen docs"], ["https://github.com/zen-browser/desktop/issues/4411", "blur behind the sidebar · Issue #4411"],
         ["https://wiki.hypr.land/Configuring/Window-Rules/", "Window Rules - Hyprland Wiki"]].forEach(([url, title]) => {
            const id = session.addPage(zen, url, "");
            session.update(id, { title: title, icon: favicon(title.charAt(0), "#3d3d3d"), state: "frozen" });
        });
        session.fileThread(zen);
        Object.assign(session.threadById(zen), { filedAt: now - 2 * day, lastActive: now - 2 * day });
        const closedAt = Math.min(at(11, 2), now - 30 * min);
        session.closed = [{ id: "c0", thread: "", url: "https://github.com/abdul/book4-pd-charge", title: "book4-pd-charge - github.com", icon: favicon("G", "#24292f"), at: now - 2 * 60 * min },
                          { id: "c1", thread: "", url: "http://neverssl.com/", title: "NeverSSL", icon: favicon("N", "#3f6b3a"), at: closedAt }];
        history.entries["https://wiki.archlinux.org/title/USB_Power_Delivery"] = { url: "https://wiki.archlinux.org/title/USB_Power_Delivery", title: "USB PD charging - ArchWiki",
                                                                                 icon: favicon("W", "#1793d1"), visits: 2, last: now - 16 * day };
        const saved = app.savedModel;
        saved.pages = [{ id: "s0", url: "https://wiki.archlinux.org/title/Libcamera", name: "Libcamera - ArchWiki", icon: favicon("W", "#1793d1"), added: now - 5 * day, folder: "" },
                       { id: "s1", url: "https://lore.kernel.org/lkml/", name: "Linux kernel mailing list", icon: favicon("L", "#4d5b6a"), added: now - 9 * day, folder: "" },
                       { id: "s2", url: "https://github.com/linux-msm/linux", name: "linux-msm/linux", icon: favicon("G", "#24292f"), added: now - 12 * day, folder: "" }]
            .concat(Array.from({ length: 31 }, (_, i) => ({ id: "z" + i, url: "https://zen.example/" + i, name: "Toolbar " + i, icon: "", added: 0, folder: "From Zen: Toolbar" })));
        saved.threads = [{ id: "st0", thread: book4.id, title: book4.title, added: now - day, pages: book4.pages.map(id => ({ url: session.pages[id].url, title: session.pages[id].title, icon: session.pages[id].icon })) }];
        saved.revision++;
        session.revision++;
        app.show("issue212");
    }

    // 4a: every page closed. Single pages just close; the multi-page threads file, the camera one last.
    function fileEverything() {
        session.threads = session.threads.filter(t => t.pages.length > 1);
        for (const t of session.threads.filter(t => !t.earlier).reverse())
            session.fileThread(t.id);
        session.currentPage = "";
        session.revision++;
    }
}
