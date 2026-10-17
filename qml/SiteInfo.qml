import QtQuick
import Browser
import "Asks.js" as Asks
import "PageState.js" as PageState
import "Site.js" as Site

// The site panel (PLAN.md 3.9) for the page on screen: Main opens it (a favicon click, Ctrl+I, Site settings in
// an ask, the refused pop-up glyph) where the address card is, the pinned rail's card or, folded, the
// overlay's (3.5); SitePanel draws it. This keeps what the panel shows and carries out
// what its rows set. The clear waits here on its undo, so closing the panel does not cancel it.
QtObject {
    id: info

    required property var sites             // Main's Sites
    property var adblock: null              // the C++ Adblock; null in shots
    property bool live: true                // false in shots: no handshake, no polling, no clear
    property var viewsOf: origin => []      // Main: the views whose page is at `origin`
    property var view: null                 // Main: the page on screen
    property bool open: false
    property string where: "rail"           // "rail" (the pinned rail's card) or "peek" (the overlay's, folded)
    property string sub: ""                 // "", "certificate" or "all"
    property string expand: ""              // the row whose choices are out
    property string waiting: ""             // Main: the host of an ask that waits until the panel closes
    // what the panel learns as it opens; shots set them
    property var tls: null                  // Facts.lookUpTls's answer for the page's host
    property var seen: ({ blocked: 0, insecureImages: false })
    property bool blocker: adblock !== null && adblock.ready
    // the profile's cookie list: the SiteData singleton's, a private window's own (PLAN.md 3.14)
    property var siteData: SiteData
    property int cookies: { siteData.revision; return open && host ? siteData.cookies(host) : 0 }
    // a clear waiting on its undo: { origin, host }, and the seconds left
    property var clearing: null
    property int left: 0

    readonly property string url: view ? String(view.url) : ""
    readonly property string origin: Asks.originOf(url)
    readonly property string host: PageState.hostOf(url)
    readonly property var entry: { sites.revision; return sites.entries[origin] ?? null }
    readonly property var security: Site.security(url, view && view.questioned ? view.questioned.cardLine ?? "" : "", tls)
    readonly property bool clearingHere: clearing !== null && clearing.origin === origin
    readonly property real zoom: { sites.revision; return sites.zoom(origin) }
    // Reader view (PLAN.md 3.9): whether the page has an article, as the page last said, and whether it shows it
    readonly property string article: view ? view.article ?? "" : ""
    readonly property bool reading: view ? view.reader === true : false
    readonly property var rows: Site.rows({ view: sub, clearing: clearingHere, mixed: seen.insecureImages && /^https:/i.test(url), blocker: blocker,
                                            ads: choice("ads"), types: Site.permissionTypes(entry, sub === "all", [expand]), tls: tls, waiting: waiting })
    function choice(type) { sites.revision; return sites.choice(origin, type) }

    signal clearStarted(string origin)      // Main unloads the site's pages
    signal storageWanted(string origin)     // Main's hidden page clears the origin's storage; storageCleared() answers
    signal clearEnded(string origin)        // cleared or undone: Main shows the page on screen again
    signal copyRequested(string text)
    signal readerWanted()                   // Reader view's row: Main puts the article in the page's place, or back

    // `row`: a row whose choices come out at once (Site settings in an ask, the refused pop-up glyph)
    function show(w, row) {
        where = w;
        sub = "";
        expand = row ?? "";
        open = true;
        lookUp();
        poll();
        // what the page added since it loaded may have made an article of it, or taken it away
        if (live && view && view.probeArticle)
            view.probeArticle();
    }
    function hide() {
        if (!open)
            return;
        open = false;
        sub = "";
        expand = "";
    }
    // Esc: closed, and the keys go back to the page
    function dismiss() {
        const v = view;
        hide();
        if (v)
            v.forceActiveFocus();
    }
    onOriginChanged: if (open) { lookUp(); poll() }

    // A row's choice. Ads and trackers reloads the page, which starts its count again; sound and zoom reach
    // the site's pages at once; the others apply to what the site asks next.
    function set(type, value) {
        sites.setChoice(origin, type, value);
        expand = "";
        if (type === "ads" && view)
            view.reload();
        else if (type === "sound")
            for (const v of viewsOf(origin))
                v.muteForSite(value === "block");
    }
    function setZoom(z) {
        if (!origin)
            return;
        sites.setZoom(origin, z);
        for (const v of viewsOf(origin))
            v.zoomFactor = sites.zoom(origin);
    }
    function stepZoom(delta) { setZoom(Site.zoomStep(zoom, delta)) }

    // Clear site data: the site's pages unload now, and its data goes when the undo has run out.
    function startClear() {
        if (!origin || clearing)
            return;
        clearing = { origin: origin, host: host };
        left = Site.undoSeconds;
        sub = "";
        expand = "";
        clearStarted(origin);
        if (live)
            countdown.restart();
    }
    function undo() {
        const c = clearing;
        if (!c)
            return;
        countdown.stop();
        clearing = null;
        clearEnded(c.origin);
    }
    // cookies through the cookie store for the host, storage through a page of the origin (Main)
    function finish() {
        countdown.stop();
        siteData.clearCookies(clearing.host);
        storageWanted(clearing.origin);
    }
    function storageCleared() {
        const c = clearing;
        clearing = null;
        if (c)
            clearEnded(c.origin);
    }
    property Timer countdown: Timer {
        interval: 1000
        repeat: true
        onTriggered: if (--info.left <= 0) info.finish()
    }

    // The TLS and certificate the host presents to a handshake of the browser's own (the engine reports
    // neither for a loaded page), asked as the panel opens on an https page.
    property var asked: null
    function lookUp() {
        tls = null;
        asked = null;
        const m = /^https:\/\/(?:[^\/?#@]*@)?(\[[^\]\/]*\]|[^\/:?#]*)(?::(\d+))?/i.exec(url);
        if (!live || !open || !m)
            return;
        asked = { host: m[1].replace(/^\[|\]$/g, ""), port: Number(m[2] || 443) };
        Facts.lookUpTls(asked.host, asked.port);
    }
    property Connections answers: Connections {
        target: Facts
        function onTlsFound(host, port, tls) {
            if (info.asked && info.asked.host === host && info.asked.port === port)
                info.tls = Object.keys(tls).length > 0 ? tls : null;
        }
    }
    // What the interceptor saw for the page: its count and any image over http, kept current while it is open.
    function poll() {
        if (!adblock || !url)
            return;
        const s = adblock.seen(url, view ? view.profile : null);
        if (s.blocked !== seen.blocked || s.insecureImages !== seen.insecureImages)
            seen = s;
    }
    property Timer poller: Timer {
        interval: 1000
        repeat: true
        running: info.open && info.live
        onTriggered: info.poll()
    }
}
