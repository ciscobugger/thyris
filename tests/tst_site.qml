import QtQuick
import QtTest
import Browser
import "../qml"
import "../qml/Site.js" as Site

// Site.js, SiteInfo.qml and the site panel's choices in Sites.qml (PLAN.md 3.9): the rows listed, their
// wording, zoom steps, and the clear that waits on its undo.
TestCase {
    name: "Site"

    Component { id: sitesComponent; Sites {} }
    Component { id: infoComponent; SiteInfo {} }
    // a private profile's cookie list (SiteData.forProfile), as the fake SiteData
    Component {
        id: ownCookies
        QtObject {
            property int revision: 0
            property var counts: ({})
            property var cleared: []
            function cookies(host) { return counts[host] ?? 0 }
            function clearCookies(host) { cleared = cleared.concat([host]); revision++; return 0 }
        }
    }
    // a page as SiteInfo uses one
    Component {
        id: viewComponent
        QtObject {
            property url url
            property var questioned: null
            property real zoomFactor: 1
            property bool audioMuted: false
            property int reloads: 0
            function reload() { reloads++ }
            function forceActiveFocus() {}
            // BrowserView's: it also unmutes only what the site muted (checked in the engine check)
            function muteForSite(block) { audioMuted = block }
        }
    }

    function init() {
        Store.files = {};
        SiteData.counts = {};
        SiteData.cleared = [];
        Facts.asked = [];
    }
    function kinds(rows) { return rows.map(r => r.kind + (r.kind === "choice" ? ":" + r.key : "")) }

    function test_permissionsListedAreWhatTheSiteAskedForOrYouChanged() {
        const entry = { asked: { notifications: 1, microphone: 2, "app:magnet": 3, fonts: 4 }, choices: { sound: "block", ads: "allow", zoom: 1.1 } };
        compare(Site.permissionTypes(entry, false), ["microphone", "notifications", "sound", "fonts", "app:magnet"],
                "All permissions' order, then the pointer and fonts, then apps; the panel's own rows are not permissions");
        compare(Site.permissionTypes(null, false), []);
        compare(Site.permissionTypes(entry, true), ["camera", "microphone", "location", "notifications", "sound", "popups", "clipboard", "screen",
                                                    "fonts", "app:magnet"], "All permissions: every type, and what else the site asked for");
        compare(Site.permissionTypes(entry, false, ["popups"]).indexOf("popups"), 3, "a row called up by name is listed, in its place");
        compare(Site.permissionTypes(entry, false, ["ads", ""]).length, 5, "and only a permission");
        compare(Site.label("app:magnet"), "Opens apps: magnet");
        compare(Site.label("popups"), "Pop-ups");
    }

    function test_valuesAndTheirChoices() {
        compare(Site.choices("microphone").map(c => c.label), ["Ask", "Allow", "Block"]);
        compare(Site.value("microphone", ""), "Ask");
        compare(Site.value("notifications", "block"), "Blocked");
        compare(Site.value("camera", "allow"), "Allowed");
        compare(Site.choices("screen").map(c => c.label), ["Ask", "Block"], "the screen-share ask is its picker: no lasting Allow");
        compare(Site.value("ads", ""), "Blocked", "ads and trackers are blocked unless allowed");
        compare(Site.value("ads", "allow"), "Allowed");
        compare(Site.value("popups", ""), "Blocked", "pop-ups without a click");
        compare(Site.value("sound", ""), "Allowed");
        compare(Site.value("slash", ""), "On", "/ opens find unless the site keeps it");
        compare(Site.choices("slash").map(c => c.value), ["", "off"], "the default is no choice");
    }

    function test_securityLine() {
        compare(Site.security("https://www.youtube.com/watch?v=x", "", null), { text: "Secure", tone: "", certificate: false },
                "no TLS version or certificate until the handshake answers");
        compare(Site.security("https://www.youtube.com/", "", { protocol: "TLS 1.3", sha256: "7c:3e" }), { text: "Secure · TLS 1.3", tone: "", certificate: true });
        compare(Site.security("https://cert.test/", "Unknown certificate authority", { protocol: "TLS 1.3", sha256: "ab" }),
                { text: "Unknown certificate authority", tone: "error", certificate: true }, "a certificate let past says so, in the error tone");
        compare(Site.security("http://neverssl.com/", "", null), { text: "Not secure", tone: "error", certificate: false });
        compare(Site.security("http://127.0.0.1:8080/", "", null), { text: "On this computer", tone: "", certificate: false },
                "this machine's pages are not flagged");
    }

    function test_certificateView() {
        const until = new Date(2026, 11, 1).getTime();
        const rows = Site.certificateRows({ subject: "www.youtube.com", issuer: "WR2 · Google Trust Services", until: until, sha256: "7c:3e:91",
                                            protocol: "TLS 1.3", cipher: "TLS_AES_128_GCM_SHA256", pem: "-----BEGIN CERTIFICATE-----" });
        compare(rows.map(r => r.label + (r.value ? " " + r.value : "")),
                ["Issued to www.youtube.com", "By WR2 · Google Trust Services", "Valid until 1 Dec 2026", "SHA-256 7c:3e:91",
                 "TLS 1.3 · TLS_AES_128_GCM_SHA256", "Copy PEM"]);
        compare(Site.certificateRows({}), [], "nothing claimed that the handshake did not show");
    }

    function test_wording() {
        compare(Site.blocked(214), "214 blocked on this page");
        compare(Site.cookies(14), "Cookies 14 · storage");
        compare(Site.countdown(6), "Site data cleared in 6 s");
        compare(Site.zoomText(1.1), "110 %");
        compare(Site.zoomText(0.67), "67 %");
    }

    function test_zoomSteps() {
        compare(Site.zoomStep(1, 1), 1.1);
        compare(Site.zoomStep(1, -1), 0.9);
        compare(Site.zoomStep(1.1, 1), 1.25);
        compare(Site.zoomStep(1.05, 1), 1.1, "from between two steps, the next one up");
        compare(Site.zoomStep(1.05, -1), 1, "or down");
        compare(Site.zoomStep(5, 1), 5, "500 % is Qt's most");
        compare(Site.zoomStep(0.25, -1), 0.25, "25 % its least");
        compare(Site.zoomStep(7, -1), 5);
    }

    function test_mainRows() {
        const s = { view: "", clearing: false, mixed: false, blocker: true, ads: "", types: ["notifications", "microphone"], tls: null, waiting: "" };
        compare(kinds(Site.rows(s)), ["head", "split", "choice:ads", "count", "split", "choice:notifications", "choice:microphone", "link",
                                      "split", "zoom", "reader", "choice:slash", "split", "action"]);
        compare(Site.rows(s)[13].key, "clear");
        compare(Site.rows(s)[10].label, "Reader view", "between Zoom and / opens find, as the frame has it");
        compare(kinds(Site.rows(Object.assign({}, s, { ads: "allow" }))).indexOf("count"), -1, "no count while ads are allowed");
        compare(kinds(Site.rows(Object.assign({}, s, { blocker: false }))).slice(0, 3), ["head", "split", "choice:notifications"],
                "no blocker row without filter lists");
        const mixed = Site.rows(Object.assign({}, s, { mixed: true }));
        compare(mixed[1].text, "Some images load over http", "mixed content under the security line, before the blocker");
        const waiting = Site.rows(Object.assign({}, s, { waiting: "meet.google.com" }));
        compare(waiting[waiting.length - 1].text, "meet.google.com is asking  ·  after this", "an ask waits on the last line");
    }

    // PLAN.md 3.9: "Reader view  Ctrl+Alt+R", or off with "No article here" when Readability finds none
    function test_readerValue() {
        compare(Site.reader("yes"), "Ctrl+Alt+R");
        compare(Site.reader(""), "Ctrl+Alt+R", "not asked yet: the row works, and a click finds out");
        compare(Site.reader("none"), "No article here");
    }

    function test_otherViews() {
        const base = { view: "", clearing: false, mixed: false, blocker: true, ads: "", types: ["camera"], tls: null, waiting: "" };
        compare(kinds(Site.rows(Object.assign({}, base, { clearing: true }))), ["head", "split", "title", "note", "action"]);
        compare(Site.rows(Object.assign({}, base, { clearing: true }))[0].plain, true, "the host alone, as the clear frame draws it");
        compare(Site.rows(Object.assign({}, base, { clearing: true }))[3].text, "Its pages are unloaded until then.");
        compare(Site.rows(Object.assign({}, base, { clearing: true }))[4].label, "Undo");
        const cert = Site.rows(Object.assign({}, base, { view: "certificate", tls: { subject: "cert.test", protocol: "TLS 1.3" } }));
        compare(kinds(cert), ["back", "split", "pair", "text"]);
        compare(cert[0].label, "Certificate");
        compare(kinds(Site.rows(Object.assign({}, base, { view: "all", types: ["camera", "microphone"] }))), ["back", "split", "choice:camera", "choice:microphone"]);
    }

    function test_sitesKeepThePanelsChoices() {
        const s = createTemporaryObject(sitesComponent, this);
        compare(s.zoom("https://www.youtube.com"), 1);
        s.setZoom("https://www.youtube.com", 1.1);
        compare(s.zoom("https://www.youtube.com"), 1.1);
        s.setZoom("https://www.youtube.com", 1);
        compare(s.entries["https://www.youtube.com"].choices.zoom, undefined, "100 % is no choice");
        // Settings > Pages (PLAN.md 3.15): a site with no zoom of its own takes the default, and the default is no choice
        s.defaultZoom = 1.25;
        compare(s.zoom("https://www.youtube.com"), 1.25);
        s.setZoom("https://www.youtube.com", 1);
        compare(s.zoom("https://www.youtube.com"), 1, "100 % is a choice now");
        s.setZoom("https://www.youtube.com", 1.25);
        compare(s.entries["https://www.youtube.com"].choices.zoom, undefined);
        s.defaultZoom = 1;
        s.setChoice("https://www.youtube.com", "ads", "allow");
        s.setChoice("http://www.youtube.com", "ads", "allow");
        s.setChoice("https://news.example", "ads", "");
        compare(s.adsAllowed(), ["www.youtube.com"], "the ad blocker's allowlist is hosts");
    }

    function info(url) {
        const sites = createTemporaryObject(sitesComponent, this);
        const view = createTemporaryObject(viewComponent, this, { url: url });
        const other = createTemporaryObject(viewComponent, this, { url: url.replace(/\/[^\/]*$/, "/other") });
        const i = createTemporaryObject(infoComponent, this, { sites: sites, view: view, viewsOf: o => [view, other].filter(v => v.url.toString().startsWith(o)) });
        return { info: i, sites: sites, view: view, other: other };
    }

    function test_choicesReachTheSitesPages() {
        const t = info("https://www.youtube.com/watch");
        t.info.show("rail", "microphone");
        compare(t.info.expand, "microphone", "Site settings in an ask brings its row's choices out");
        t.info.set("microphone", "block");
        compare(t.sites.choice("https://www.youtube.com", "microphone"), "block");
        compare(t.info.expand, "", "a pick folds the choices");
        t.info.set("ads", "allow");
        compare(t.view.reloads, 1, "Ads and trackers reloads the page, which starts its count again");
        t.info.set("sound", "block");
        verify(t.view.audioMuted && t.other.audioMuted, "sound: every page of the site");
        t.info.stepZoom(1);
        compare(t.view.zoomFactor, 1.1);
        compare(t.other.zoomFactor, 1.1, "zoom: every page of the site");
        compare(t.info.zoom, 1.1);
        t.info.setZoom(1);
        compare(t.view.zoomFactor, 1);
        t.info.hide();
        verify(!t.info.open);
    }

    function test_handshakeAnswersOnlyForTheHostAsked() {
        const t = info("https://cert.test:4433/plain");
        t.info.show("rail", "");
        compare(Facts.asked, ["cert.test:4433"]);
        Facts.tlsFound("other.test", 4433, { protocol: "TLS 1.3", sha256: "ab" });
        compare(t.info.tls, null, "another host's answer");
        Facts.tlsFound("cert.test", 4433, { protocol: "TLS 1.3", sha256: "ab" });
        compare(t.info.security.text, "Secure · TLS 1.3");
        verify(t.info.security.certificate);
        Facts.tlsFound("cert.test", 4433, {});
        compare(t.info.tls, null, "a handshake that failed shows nothing");
        const plain = info("http://neverssl.com/online");
        plain.info.show("rail", "");
        compare(Facts.asked.length, 1, "no handshake for plain http");
    }

    function test_clearWaitsOnItsUndo() {
        const t = info("https://www.youtube.com/watch");
        SiteData.counts = { "www.youtube.com": 14 };
        const started = [], wanted = [], ended = [];
        t.info.clearStarted.connect(o => started.push(o));
        t.info.storageWanted.connect(o => wanted.push(o));
        t.info.clearEnded.connect(o => ended.push(o));
        t.info.show("rail", "");
        compare(t.info.cookies, 14);
        t.info.startClear();
        compare(started, ["https://www.youtube.com"], "the site's pages unload at once");
        compare(t.info.left, 6);
        compare(kinds(t.info.rows).slice(0, 3), ["head", "split", "title"]);
        t.info.countdown.triggered();
        compare(t.info.left, 5, "Site data cleared in 5 s");
        t.info.undo();
        compare(t.info.clearing, null);
        compare(ended, ["https://www.youtube.com"], "undone: the page on screen loads again");
        compare(SiteData.cleared, [], "and nothing was cleared");
        t.info.startClear();
        for (let i = 0; i < 6; i++)
            t.info.countdown.triggered();
        compare(SiteData.cleared, ["www.youtube.com"], "cookies through the cookie store for the host");
        compare(wanted, ["https://www.youtube.com"], "storage through a page of the origin");
        verify(t.info.clearing !== null, "until that page answers");
        t.info.storageCleared();
        compare(t.info.clearing, null);
        compare(ended.length, 2);
        compare(t.info.cookies, 0);
    }

    // PLAN.md 3.14: a private window's site choices start as the main profile's and are never written
    function test_aPrivateWindowsSitesAreNeverSaved() {
        const s = createTemporaryObject(sitesComponent, this, { offTheRecord: true });
        s.setChoice("https://meet.google.com", "camera", "block");
        s.noteAsked("https://meet.google.com", ["camera"]);
        s.save();
        s.saveTimer.triggered();
        compare(Store.files.sites, undefined);
        compare(s.choice("https://meet.google.com", "camera"), "block");
    }
    // its site panel counts and clears the cookies of its own profile
    function test_thePanelUsesItsProfilesCookies() {
        const t = info("https://www.youtube.com/watch?v=1");
        const own = createTemporaryObject(ownCookies, this);
        own.counts = { "www.youtube.com": 4 };
        SiteData.counts = { "www.youtube.com": 9 };
        t.info.siteData = own;
        t.info.open = true;
        compare(t.info.cookies, 4);
        t.info.clearing = { origin: "https://www.youtube.com", host: "www.youtube.com" };
        t.info.finish();
        compare(own.cleared, ["www.youtube.com"]);
        compare(SiteData.cleared.indexOf("www.youtube.com"), -1, "the main profile's are left alone");
    }
}
