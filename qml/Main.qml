import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Controls as Controls
import QtWebChannel
import QtWebEngine
import "Asks.js" as Asks
import "DevTools.js" as DevTools
import "Downloads.js" as Downloads
import "Failures.js" as Failures
import "KeyMap.js" as KeyMap
import "Lifecycle.js" as Lifecycle
import "Logins.js" as Logins
import "PageState.js" as PageState
import "RailRows.js" as RailRows
import "PageMenu.js" as PageMenu
import "Recall.js" as Recall
import "Settings.js" as Settings
import "Site.js" as Site
import "Swipe.js" as Swipe

Window {
    id: root

    required property string dataDir
    required property url startUrl
    property string startFrom: ""       // the app startUrl came from (`browser --from`, or Instance.caller), or ""
    property string startContext: ""    // what its caller was doing (Instance.context), for the task openLink picks
    // the single-instance socket (src/instance.*): links later `browser` runs hand over; null in shots
    property QtObject instance: null
    // Ctrl+L in the notch (src/notch.*, NotchAddress): the main profile's socket for the shell's address sheet; the first
    // window's, null in shots
    property QtObject notch: null
    // a sign-in popup in the notch (src/notch.*, NotchSignin): the main profile's second socket; the first window's, null in shots
    property QtObject signinNotch: null
    required property QtObject adblock
    // Set by `browser --shots`: pages are stand-ins (no WebEngine) and Shots.qml drives the state.
    property QtObject shots: null
    readonly property bool shotMode: shots !== null || primary !== null && primary.shotMode
    property QtObject engineCheck: null // set by `browser --check-engine`: EngineCheck.qml drives real pages

    // Every main window is a Main (PLAN.md 3.17). The first, which main.cpp loads, holds what they all share: history,
    // site choices, downloads, the profile, the one writer of threads.json and the list of windows; it
    // makes the others (newWindow) and is their `primary`. Closed while another is open it is only hidden, so what it
    // holds lives on, and it is the next new window.
    property var primary: null
    readonly property var hub: primary ?? root
    property string windowId: ""        // its threads carry it; "" for the first window
    // A private window (PLAN.md 3.14, Ctrl+Shift+N): a main window on an off-the-record profile of its own, with its own
    // threads, history, site choices, downloads and cookies, kept in memory and gone when it closes. It is none of the
    // first window's main windows, so links from other apps, a peek's Keep, @ and Ctrl+Shift+T elsewhere never reach it.
    property bool offTheRecord: false
    // The section strip (PLAN.md 3.19) is off: the owner had it removed on 2026-10-08 ("remove that content chapters in
    // bottom"). true brings it back; the strip check group sets it for its own pages.
    property bool sectionStripOn: false
    // lists of its own rather than the first window's: the first window, and a private window
    readonly property bool ownLists: primary === null || offTheRecord
    property var privateWindows: []     // the first window's: the private windows open
    property QtObject siteData: null    // a private window's cookie list (SiteData.forProfile); null: the SiteData singleton
    property string workspace: ""       // the Hyprland workspace it was on at the last answer (Backdrop.workspaceOf)
    property var mainWindows: [root]    // the first window's: every main window, the first first
    property var lastWindow: root       // the first window's: the main window that last had the focus
    property var pendingWindows: []     // the first window's: records of windows to restore once it is shown
    readonly property Item frostSource: frostTexture
    // Owns the windows this one makes (main windows, pop-ups) without being a window: a window's QObject
    // children that are windows lose their platform windows with it, so the first window closing took the others.
    QtObject { id: made }

    width: 1280
    height: 800
    // started with a link from another app, it shows once openLink has its page (reveal)
    visible: String(startUrl) === "" || shotMode
    title: {
        sessionModel.revision;
        if (offTheRecord)
            return RailRows.privateTitle(sessionModel.current);
        return sessionModel.current ? RailRows.windowTitle(sessionModel.current, sessionModel.currentThread) : "Browser";
    }
    color: "transparent"

    property var profile: null
    property var views: ({})            // pageId -> BrowserView, created the first time a page is shown
    property bool railPinned: true
    property int railWidth: 300         // drag 248-420, double-click resets
    property string hoveredLink: ""
    readonly property bool noPage: sessionModel.currentPage === ""
    readonly property Item popupLayer: Controls.Overlay.overlay  // where menus and tooltips draw

    // this window's threads over the lists every window shares (Session.qml)
    Session {
        id: sessionModel
        windowId: root.windowId
        offTheRecord: root.offTheRecord
        shared: root.ownLists ? null : root.primary.windowSession
        windowRecords: root.primary ? null : () => root.windowRecords()
    }
    readonly property alias windowSession: sessionModel
    readonly property alias windowRail: pinnedRail      // for the checks and shots of a window not the first
    readonly property alias windowPageMenu: pageMenu
    readonly property alias devToolsArea: devToolsArea
    readonly property alias askSheet: askSheet          // the page's ask (AskSheet), for the checks and shots
    readonly property alias windowBar: newBar
    readonly property alias windowHover: peek
    readonly property alias windowOverlay: peekRail
    readonly property alias windowSite: siteInfo
    readonly property alias windowAddress: addressEditor
    readonly property alias windowNotch: notchAddress
    readonly property alias windowSignin: notchSignin
    readonly property alias windowSettings: settingsPage
    readonly property alias windowPages: pagesPage
    readonly property alias windowPrint: printCard
    // History, site choices, downloads and continued certificates are the first window's, for every window; the
    // others' own are never loaded. A private window's are its own, in memory only.
    History { id: ownHistory; offTheRecord: root.offTheRecord }
    readonly property var historyModel: ownLists ? ownHistory : primary.historyModel
    // Saved (PLAN.md 3.7): the first window's, for every window; a private window saves to it only when you say so (3.14)
    Saved { id: ownSaved }
    readonly property var savedModel: primary ? primary.savedModel : ownSaved
    // a typed path of an existing file offers Open file before find (PLAN.md 3.3)
    Omnibox {
        id: omniModel
        session: sessionModel
        history: historyModel
        saved: root.savedModel
        offTheRecord: root.offTheRecord
        isFile: path => Facts.isFile(path)
        article: root.currentView && !root.noPage ? root.currentView.article ?? "" : ""
        engine: Settings.engine(root.prefs.get("engine")).name
        searchTemplate: Settings.engine(root.prefs.get("engine")).url
        httpsFirst: root.prefs.get("httpsFirst") !== "off"
        praxisHere: Engine.praxisHere()
        offerImport: (!!Zen.profile.path || ChromeImport.found.length > 0) && !root.prefs.get("zenImport") && !root.prefs.get("broughtOver")
    }
    // Settings (PLAN.md 3.15): the first window's, for every window, a private one's too
    Prefs { id: ownPrefs }
    readonly property var prefs: primary ? primary.prefs : ownPrefs
    // Earlier (PLAN.md 3.7): the view the rail list turns into, in the pinned rail or folded in the overlay, which it
    // holds out. `view`: "" (the rail's own list), "threads", "saved" or "downloads"; `open`: the filed threads and
    // imported folders listed open ({ id or "folder:<name>": true }); `editing`: the Saved page edited in place.
    QtObject {
        id: earlierState
        property string view: ""
        property string filter: ""
        property var open: ({})
        property string editing: ""
        // History (PLAN.md 3.21): the closed tasks listed open, and its Older listed
        property var unfolded: ({})
        property bool older: false
    }
    readonly property alias earlier: earlierState
    // The browser's short word in the address card's second line (PLAN.md 3.7): "Saved · Edit" for 3 s after Ctrl+D,
    // "Forgot <title> · Undo" for 6 s after a forget; { text, action, run, kind, where: "card" or "jump" (@'s last line) }.
    // Not `notice`: the full-screen notice has that id.
    property var cardNotice: null
    Timer { id: cardNoticeTimer; onTriggered: root.cardNotice = null }
    Sites { id: ownSites; offTheRecord: root.offTheRecord; defaultZoom: root.prefs.get("zoom") }
    readonly property var siteModel: ownLists ? ownSites : primary.siteModel
    // the ad blocker leaves the pages of the sites set to Allowed alone (PLAN.md 3.9), this profile's
    Connections {
        target: root.ownLists ? siteModel : null
        function onRevisionChanged() { if (root.adblock && root.profile) root.adblock.setAllowed(siteModel.adsAllowed(), root.profile) }
    }
    // The site panel (PLAN.md 3.9) for the page on screen: in the pinned rail's card, or folded in the
    // overlay's, held out while it is open (3.5). An ask waits until it closes.
    SiteInfo {
        id: siteInfo
        sites: siteModel
        adblock: root.adblock
        live: !root.shotMode
        view: root.noPage ? null : root.currentView
        viewsOf: origin => root.profileViews().filter(v => !v.parked && Asks.originOf(String(v.url)) === origin)
        waiting: open && root.shownAsk && root.shownAsk.kind === "password" ? root.shownAsk.host : ""
        siteData: root.siteData ?? SiteData
        // every window's pages of the site, as the profile's data is every window's (a private window's alone)
        onClearStarted: origin => root.profileWindowsDo(w => w.unloadSite(origin))
        onStorageWanted: origin => clearer.origin = origin
        onClearEnded: origin => root.profileWindowsDo(w => w.siteCleared(origin))
        onCopyRequested: text => root.copyText(text)
        onReaderWanted: root.toggleReader(siteInfo.view)
    }
    // Find in page (PLAN.md 3.8 8e), on the page on screen: in the pinned rail's card, or folded in the
    // overlay's, held out while it is open (3.5). A password ask, which takes the card, waits until it closes; the
    // others come out in their sheet (AskSheet).
    Finder {
        id: findModel
        session: sessionModel
        viewOf: id => root.views[id] ?? null
        live: !root.shotMode
        waiting: open && root.shownAsk && root.shownAsk.kind === "password" ? root.shownAsk.host : ""
        onJumpTo: id => root.findOn(id)
    }
    // Downloads (PLAN.md 3.8 8d): rows under their pages, run from the first window's; a folded window whose page
    // started one says so
    Downloader {
        id: ownDownloads
        session: sessionModel
        folder: root.downloadFolder
        onStarted: id => { const d = sessionModel.downloadById(id); (root.ownerOf(d ? d.page : "") ?? (root.offTheRecord ? root : root.lastMain())).downloadStarted(id) }
    }
    readonly property var downloadModel: ownLists ? ownDownloads : primary.downloadModel
    // Certificates continued past (PLAN.md 8g): host -> its certificate's page. The engine lets such a host
    // through until the browser quits; BrowserView shows the page again for each new load there.
    QtObject {
        id: ownCertificates
        property var accepted: ({})
        function accept(host, page) { accepted = Object.assign({}, accepted, { [host]: page }) }
    }
    readonly property var certificateModel: ownLists ? ownCertificates : primary.certificateModel
    property var currentView: null
    // Settings lies over the page you came from (docked from the rail, 2026-10-15): that page's view stays on screen under
    // the sheet, and Settings' own (an empty document) keeps the keys unseen, at opacity 0
    property var behindView: null
    // the browser's own page on screen (PLAN.md 3.17): "settings" or "pages" for browser://settings and browser://pages,
    // drawn over their view; "" for any other page, and for one of them whose load failed
    readonly property string ownKind: {
        const v = currentView;
        return v && !noPage && !v.failure ? ownPageOf(String(v.url)) : "";
    }
    function ownPageOf(url) {
        const m = /^browser:\/\/(settings|pages)([\/?#]|$)/i.exec(url);
        return m ? m[1].toLowerCase() : "";
    }
    // An own page that goes while it has the keys (its view loads another address, another page is shown) would keep
    // them hidden, as Qt Quick leaves active focus on a hidden item (measured: the hidden filter kept them): they go to
    // the page on screen, as a page shown by a click gets them (an own page there takes them from its view).
    onOwnKindChanged: {
        if (!currentView)
            return;
        Qt.callLater(() => {
            const f = root.activeFocusItem;
            const hidden = (settingsPage.activeFocus && !settingsPage.visible) || (pagesPage.activeFocus && !pagesPage.visible)
                || (!settingsPage.visible && (pinnedRail.settingsSearch.activeFocus || peekRail.settingsSearch.activeFocus));
            if (root.currentView && (hidden || root.ownKind === "" && (!f || f === root.contentItem || f === pageArea)))
                root.currentView.forceActiveFocus();
        });
    }
    // Settings > Downloads (PLAN.md 3.15): the folder set, while it is one, else Disk.downloads
    readonly property string downloadFolder: {
        const f = prefs.get("folder");
        return f && Facts.isFolder(f) ? f : Disk.downloads;
    }
    // what the engine gives a profile before Settings sets anything (the first window's): its fonts and languages. Qt
    // reports no Accept-Language it was not given; the engine then sends the application's locale (measured: a page's
    // navigator.languages).
    property var engineFonts: ({})
    property string engineLanguages: ""
    readonly property var defaultLanguages: hub.engineLanguages ? Settings.fromAcceptLanguage(hub.engineLanguages) : [Qt.locale().name.replace(/_/g, "-")]
    // The current page's ask (PLAN.md 3.8) shows in the rail's address card: the pinned rail's, or folded the
    // overlay's, which it holds out until it is answered (3.5). It waits while the address is edited, the
    // card's last line naming it.
    readonly property var shownAsk: currentView && !noPage ? currentView.ask : null
    property string waitingAsk: addressEditor.editing && shownAsk ? shownAsk.host : ""

    // Created disk-based from the start: a WebEngineProfile renamed after creation switches from
    // off-the-record, and extension calls on it crash (Qt 6.11). Made by the first window only: a second
    // prototype on the same path makes no profile and says so.
    Component {
        id: profilePrototype
        WebEngineProfilePrototype {
            storageName: "default"
            persistentStoragePath: root.dataDir + "/profile"
            // Allow once lasts for the page load, and lasting choices are the site panel's (Sites.qml), so the
            // engine keeps none of its own: every request reaches BrowserView.onPermissionRequested
            persistentPermissionsPolicy: WebEngineProfile.PersistentPermissionsPolicy.AskEveryTime
        }
    }
    // A private window's profile (PLAN.md 3.14): with no storage name a profile is off the record (cookies, cache and
    // storage in memory), and each is its own, so two private windows share no cookies.
    Component {
        id: privateProfile
        WebEngineProfilePrototype {
            persistentPermissionsPolicy: WebEngineProfile.PersistentPermissionsPolicy.AskEveryTime
        }
    }

    // The view whose download it is: its page, the opener's for an attached popup, or the fetcher's Retry;
    // its address counts for "insecure" only when the page started the load, and a new page with no address
    // yet (a link or window.open that opened it) counts its opener's. `download.view` is read here only: read
    // after that view is gone, it crashed (Qt 6.11).
    Connections {
        target: root.ownLists ? root.profile : null
        function onDownloadRequested(download) {
            const v = download.view;
            if (v !== null && v === fetcher.item) {
                downloadModel.requested(download, "", "", true);
                return;
            }
            const from = !v || v.typedLoad ? "" : String(v.url) || (v.openedBy ? String(v.openedBy.url) : "");
            // a sign-in's window has a holder but no opener: reading its opener threw, and the download was cancelled
            downloadModel.requested(download, !v ? "" : v.holder ? v.holder.opener?.pageId ?? "" : v.pageId ?? "", from, false);
        }
    }
    // Retry for a download that failed in an earlier run (Downloader.fetch): its address in a hidden view
    // that runs no script and shows no PDF, so a file answers as a download. It exists only while it loads.
    Loader {
        id: fetcher
        active: root.ownLists && downloadModel.fetchUrl !== "" && root.profile !== null
        sourceComponent: WebEngineView {
            visible: false
            width: 800
            height: 600
            profile: root.profile
            url: downloadModel.fetchUrl
            settings.javascriptEnabled: false
            settings.pdfViewerEnabled: false
            onLoadingChanged: request => {
                if (request.status === WebEngineView.LoadSucceededStatus)
                    downloadModel.fetchFailed("no file");
                else if (request.status === WebEngineView.LoadFailedStatus && !request.isDownload)
                    downloadModel.fetchFailed("network");
            }
        }
    }

    // The frost's wallpaper (Frost.qml): laid on the screen as the shell lays it (crop to fill), blurred
    // and graded towards Hyprland's blur (size 10, passes 3, vibrancy 0.62, brightness 1.06, contrast
    // 0.95), at a quarter of the screen's size, rendered once per wallpaper into the one texture every
    // frosted surface samples.
    Item {
        id: wallpaperScene
        visible: false
        width: Math.round(Backdrop.screenSize.width / 4)
        height: Math.round(Backdrop.screenSize.height / 4)
        // no wallpaper (a video, a missing file): the terminal tone
        Rectangle { anchors.fill: parent; color: Theme.terminal }
        Image {
            anchors.fill: parent
            source: ThemeSource.wallpaper
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width, height)
            asynchronous: true
            // Error and Null too, so a video, a missing file or no wallpaper captures the terminal tone
            onStatusChanged: if (status !== Image.Loading) frostTexture.scheduleUpdate()
        }
        Connections {
            target: Theme
            function onTerminalChanged() { frostTexture.scheduleUpdate() }
        }
    }
    MultiEffect {
        id: wallpaperGraded
        visible: false
        width: wallpaperScene.width
        height: wallpaperScene.height
        source: wallpaperScene
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 38
        saturation: 0.25
        brightness: 0.025
        contrast: -0.05
    }
    ShaderEffectSource {
        id: frostTexture
        visible: false
        width: wallpaperScene.width
        height: wallpaperScene.height
        sourceItem: wallpaperGraded
        hideSource: true
        live: false
    }
    // Window ground: opaque; Hyprland's opacity rule makes the whole window glass (Theme.windowOpacity).
    Rectangle { anchors.fill: parent; color: Theme.terminal }
    // Offscreen there is no Hyprland: the blurred wallpaper over the whole window at what the rule leaves
    // out, so shots show what the desktop shows. In the popup overlay, above the menus and tooltips, as
    // the rule covers them too.
    Frost {
        parent: root.shotMode ? root.popupLayer : root.contentItem
        anchors.fill: parent
        z: 1e7
        visible: root.shotMode && Theme.windowOpacity < 1
        tint: "transparent"
        opacity: 1 - Theme.windowOpacity
    }
    onWidthChanged: {
        Backdrop.refresh();
        sessionModel.saveSoon();
        // outside Hyprland a flick out and a reach for the left border to resize look the same; the resize sends it back
        if (peek.flung) { peek.flung = false; peek.open = false }
    }
    onHeightChanged: { Backdrop.refresh(); sessionModel.saveSoon() }
    onRailWidthChanged: sessionModel.saveSoon()
    // where Hyprland has it, for restore, and which window a peek's Keep goes to (PLAN.md 3.6, 3.17)
    onActiveChanged: {
        if (!active)
            return;
        if (!offTheRecord)
            hub.lastWindow = root;
        Backdrop.refresh();
    }

    // Fold and pin (PLAN.md 3.5, 3.19). Fold, the lift: the overlay takes the docked slab's place and look and lifts off
    // it (DefaultSpatial; its fill and shadow on DefaultEffects), while the page widens once under a still of itself and
    // then slides under it (Emphasized); with the pointer off it, it tucks away. Pin: it comes out if tucked and settles
    // into the dock as the page slides back, then the page narrows once beside it under a still and the pinned rail takes
    // its place. The web view never resizes frame by frame: it slides at its new width, by a translation.
    readonly property int inset: 6      // the window's ground round the page and the docked slab
    property bool pageBeside: true      // the page sits beside the rail rather than under it
    property bool docking: false        // the overlay settling into the dock; the pinned rail shows once it has
    property real railSlide: 0          // 1 once folded and the lift has ended
    property real railLift: 0           // the overlay's slab, 0 docked .. 1 lifted: its place, size and radius
    property real railFill: 0           // its fill and shadow, 0 the docked slab's .. 1 colRailGlass
    property real pageShift: 0          // the page's translation while it slides, from its place
    readonly property bool railMoving: liftAnim.running || dockAnim.running || pageSlide.running || pageStill.then !== null
    onRailPinnedChanged: {
        sessionModel.saveSoon();
        // find and the site panel show where the address card is, which just moved; and a hidden rail keeps
        // the keys unless they are handed on
        if (findModel.open)
            findModel.dismiss();
        if (siteInfo.open)
            siteInfo.dismiss();
        const hidden = railPinned ? peekRail : pinnedRail;
        if (hidden.listFocused || hidden.askFocused)
            focusPage();
        peek.flung = false;
        liftAnim.stop();
        dockAnim.stop();
        pageSlide.stop();
        pageStill.cancel();
        if (railPinned) {
            railSlide = 0;
            docking = true;
            closeTimer.stop();
            openTimer.stop();
            slideOut.stop();
            slideIn.restart();
            dockAnim.restart();
        } else {
            docking = false;
            peekRail.listView.contentY = pinnedRail.listView.contentY;
            slideIn.stop();
            slideOut.stop();
            peekRail.slide = 1;
            // folded under the pointer (its fold glyph), the lifted rail counts as hovered until the pointer moves, as
            // the overlay's own hover takes a move to learn it; folded by a key with the pointer elsewhere, it tucks
            // away as when the pointer leaves it
            peek.kept = pinnedHover.hovered;
            peek.keptAt = pinnedHover.point.scenePosition;
            peek.open = true;
            if (!peek.kept)
                closeTimer.restart();
            liftAnim.restart();
            pageStill.resize(false, () => pageSlide.restart());
        }
    }
    SequentialAnimation {
        id: liftAnim
        ParallelAnimation {
            Anim { target: root; property: "railLift"; to: 1; type: Anim.DefaultSpatial }
            Anim { target: root; property: "railFill"; to: 1; type: Anim.DefaultEffects }
        }
        PropertyAction { target: root; property: "railSlide"; value: 1 }
    }
    Anim { id: pageSlide; target: root; property: "pageShift"; to: 0; type: Anim.Emphasized }
    // the page first, the slab 40 ms after it, its fill once it has nearly settled (the lift film's order)
    SequentialAnimation {
        id: dockAnim
        ParallelAnimation {
            Anim { target: root; property: "pageShift"; to: root.pageBeside ? 0 : root.railWidth - root.inset; type: Anim.Emphasized }
            SequentialAnimation {
                PauseAnimation { duration: 40 }
                Anim { target: root; property: "railLift"; to: 0; type: Anim.DefaultSpatial }
            }
            SequentialAnimation {
                PauseAnimation { duration: 260 }
                Anim { target: root; property: "railFill"; to: 0; type: Anim.DefaultEffects }
            }
        }
        ScriptAction { script: pageStill.resize(true, () => root.docked()) }
    }
    // the pinned rail in the overlay's place, the same rows at the same scroll
    function docked() {
        docking = false;
        peek.kept = false;
        pinnedRail.listView.contentY = peekRail.listView.contentY;
        peek.open = false;
        slideIn.stop();
        slideOut.stop();
        peekRail.slide = 0;
    }
    // The quiet rail (PLAN.md 3.19): docked, while the pointer and the keys are on the page, everything in it but the
    // Always faces and the current row dims to 50 %; the pointer within 48 px of it wakes it (as the hovered link's
    // label moves at 48 px). Never while the page's ask waits, the rail has the keys (then the page has not) or the
    // overlay is out. Writable, so shots can pose it.
    property bool quietRail: railPinned && !docking && !pageFullScreen && currentView !== null && !noPage && currentView.activeFocus
                             && pagePointer.hovered && pagePointer.point.position.x >= 48 && shownAsk === null && !peek.out
    // beside the rail, or under it with its left edge where it was beside it, ready to slide
    function placePage(beside) {
        pageBeside = beside;
        pageShift = beside ? 0 : railWidth - inset;
    }

    // The page (PLAN.md 3.1, 3.19): inset 6 px in the window's ground, beside the docked slab or under the overlay,
    // corners radius 12. It changes place and width once per fold or pin, and slides between by `pageShift`.
    Item {
        id: pageArea
        x: root.pageFullScreen ? 0 : root.pageBeside ? root.railWidth : root.inset
        y: root.pageFullScreen ? 0 : root.inset
        width: parent.width - x - (root.pageFullScreen ? 0 : root.inset) - (root.devToolsShown && root.devToolsSide === "right" ? root.devToolsWidthShown + root.inset : 0)
        height: parent.height - 2 * y - (root.devToolsShown && root.devToolsSide === "bottom" ? root.devToolsHeight + root.inset : 0)
        transform: Translate { x: root.pageShift }
        // P keys: a web view hands the keys its page left unhandled to this, its parent
        Keys.onPressed: event => root.pageKey(event)

        // no page: the page area is the terminal tone, opaque, and the new-page card sits on it
        Rectangle {
            anchors.fill: parent
            visible: root.noPage
            color: Theme.terminal
        }
        // A new view is the terminal ground until its first load makes progress (PLAN.md 3.8), so no
        // white frame shows while the server has not answered. It covers the view: a web view is never
        // hidden or faded, and a hidden one could not take the keys (Esc stops).
        Rectangle {
            z: 5
            anchors.fill: parent
            visible: !root.noPage && root.currentView !== null && !root.currentView.drawn && root.behindView === null
            color: Theme.terminal
        }
        // the current page's failure (PLAN.md 8f-8h), or with no page the restore after a crash (8i)
        FailurePage {
            id: failurePage
            view: root.noPage ? null : root.currentView
            page: root.noPage ? root.restorePage : root.currentView ? root.currentView.failure : null
            onPicked: action => root.failureAction(root.currentView, action, null)
        }
        // the page's ask, docked out of the page's left edge level with the address card (AskSheet)
        AskSheet {
            id: askSheet
            objectName: "askSheet"
            z: 6
            view: root.noPage ? null : root.currentView
            // while the address card is edited the ask waits on its last line (AddressEditor's waiting), the sheet aside
            // the "Save password?" offer stays the card's quiet line: the page does not wait on it; in page full screen
            // the ask waits behind the notice ("is asking · Esc to answer")
            ask: addressEditor.editing || root.pageFullScreen || !root.shownAsk || root.shownAsk.kind === "password" ? null : root.shownAsk
            y: (root.railPinned ? pinnedRail.y + pinnedRail.addressCardY : peekRail.y + peekRail.addressCardY) - pageArea.y
            onSiteSettings: type => root.openSite(type)
        }
        // the browser's own pages (PLAN.md 3.15, 3.17), drawn over their empty documents; Settings are the main profile's
        SettingsPage {
            id: settingsPage
            view: root.ownKind === "settings" ? root.currentView : null
            behind: root.behindView !== null
            // docked, the rail draws the settings face and the sheet lines up with its row; folded, Settings draws both
            railFace: root.pageBeside && root.railPinned
            anchorY: pinnedRail.y + pinnedRail.settingsRowY - pageArea.y
            railSearch: railFace ? pinnedRail.settingsSearch : null
            onLeaveWanted: root.leaveSettings()
            prefs: root.prefs
            sites: root.hub.siteModel
            adblock: root.adblock
            profile: root.hub.profile
            siteData: SiteData
            engineFonts: root.hub.engineFonts
            defaultLanguages: root.defaultLanguages
            folder: root.downloadFolder
            zenRun: root.hub.zenRun
            onImportWanted: root.hub.importZen()
            onPasswordFileWanted: root.openPasswordFile()
            onBrowserImportWanted: root.openWelcome()
        }
        PagesPage {
            id: pagesPage
            view: root.ownKind === "pages" ? root.currentView : null
            live: !root.shotMode
            owner: root
        }

        // The card's corners: the window's opaque ground outside a quarter circle, laid over the page's
        // corners, so the web view itself is never masked or clipped.
        component Cap: Shape {
            z: 10
            // full screen, the page is the screen
            visible: !root.pageFullScreen
            width: Theme.rounding.small
            height: width
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.terminal
                strokeColor: "transparent"
                PathLine { x: Theme.rounding.small; y: 0 }
                PathArc { x: 0; y: Theme.rounding.small; radiusX: Theme.rounding.small; radiusY: Theme.rounding.small; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: 0 }
            }
        }
        Cap {}
        Cap { x: parent.width - width; rotation: 90 }
        Cap { x: parent.width - width; y: parent.height - height; rotation: 180 }
        Cap { y: parent.height - height; rotation: 270 }

        // Back and forward by a sideways swipe on the touchpad (BrowserView.swipeX): an arrow comes in from the edge the
        // swipe goes toward, filled with sand once it has gone far enough; lifting the fingers then goes back or forward.
        // Back on a page with no earlier history returns to its opener, as the Back button does (back()).
        Item {
            id: swipeCue
            z: 13
            anchors.fill: parent
            readonly property var v: root.noPage || root.ownKind !== "" ? null : root.currentView
            readonly property real dx: v ? v.swipeX ?? 0 : 0
            readonly property bool toBack: dx < 0
            readonly property bool can: !!v && dx !== 0 && (toBack ? v.canGoBack || !!v.failure || sessionModel.backTo(v.pageId) !== "" : v.canGoForward)
            readonly property real far: 140
            readonly property real reach: can ? Math.min(1, Math.abs(dx) / far) : 0
            // follows the fingers; slides out once they lift
            property real shown: reach
            Behavior on shown { enabled: !swipeCue.v || !swipeCue.v.swipeFingers; Anim { type: Anim.StandardSmall } }
            property bool side: toBack
            onDxChanged: if (dx !== 0) side = toBack
            visible: shown > 0
            Rectangle {
                width: 44
                height: 44
                radius: 22
                y: Math.round((parent.height - height) / 2)
                x: swipeCue.side ? -width + swipeCue.shown * (width + 16) : parent.width - swipeCue.shown * (width + 16)
                color: swipeCue.reach >= 1 ? Theme.primary : Theme.raisedHot
                Behavior on color { CAnim {} }
                Symbol {
                    anchors.centerIn: parent
                    text: swipeCue.side ? "arrow_back" : "arrow_forward"
                    iconSize: 20
                    color: swipeCue.reach >= 1 ? Theme.terminal : Theme.inkMain
                }
            }
            Connections {
                target: swipeCue.v
                ignoreUnknownSignals: true
                function onSwipeEnded() {
                    const v = swipeCue.v;
                    if (swipeCue.reach >= 1 && swipeCue.toBack)
                        root.back(v);
                    else if (swipeCue.reach >= 1)
                        v.goForward();
                    v.swipeX = 0;
                }
            }
        }

        PageScrollBar {
            id: pageScrollBar
            z: 12
            anchors.fill: parent
            view: root.noPage || root.currentView && (root.currentView.failure || root.ownKind !== "") ? null : root.currentView
            pointer: pagePointer
        }

        // folded: the loading line runs along the card's top edge, between its corners
        LoadLine {
            z: 15
            visible: !root.pageBeside && !root.pageFullScreen
            x: Theme.rounding.small
            width: parent.width - 2 * Theme.rounding.small
            view: root.currentView
        }

        // the hovered link, docked flush into the bottom-left corner; bottom-right when the pointer nears it.
        // While folded also a download's 3 s notice (PLAN.md 3.5 5a), under a hovered link.
        HoverHandler { id: pagePointer }
        Frost {
            id: linkLabel
            z: 15
            readonly property bool near: pagePointer.hovered && pagePointer.point.position.y > parent.height - height - 48
                && (onRight ? pagePointer.point.position.x > parent.width - width - 48 : pagePointer.point.position.x < width + 48)
            property bool onRight: false
            onNearChanged: if (near) onRight = !onRight
            // not `notice`: Main's full-screen notice has that id
            readonly property string downloadText: root.hoveredLink === "" ? root.downloadNotice || root.foldedNotice : ""
            visible: root.hoveredLink !== "" || downloadText !== ""
            x: onRight ? parent.width - width : 0
            y: parent.height - height
            width: Math.min((linkArrow.visible ? linkArrow.width + 4 : 0) + linkText.implicitWidth + 20, Math.round(parent.width * 0.5))
            height: 24
            topRightRadius: onRight ? 0 : Theme.rounding.verysmall
            topLeftRadius: onRight ? Theme.rounding.verysmall : 0
            // the docked corner is the card's
            bottomLeftRadius: onRight ? 0 : Theme.rounding.small
            bottomRightRadius: onRight ? Theme.rounding.small : 0
            Symbol { id: linkArrow; visible: linkLabel.downloadText === ""; x: 10; anchors.verticalCenter: parent.verticalCenter; text: "arrow_forward"; iconSize: 14 }
            Label {
                id: linkText
                anchors { left: linkArrow.visible ? linkArrow.right : parent.left; leftMargin: linkArrow.visible ? 4 : 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: linkLabel.downloadText !== "" ? linkLabel.downloadText : root.hoveredLink.replace(/^https?:\/\/([^\/?#@]*@)?(www\.)?/, "")
                font.pixelSize: Theme.font.smaller
                color: Theme.colOnSurface
            }
        }

        // the current page's alert, confirm or prompt (PLAN.md 8j), over that page only
        PageDialog { id: pageDialog; view: root.noPage ? null : root.currentView }

        // The page's sections (PLAN.md 3.19): a hairline in the gap under the page that rises into its foot; none in a
        // private window, on the browser's own pages, a failure or in page full screen
        SectionStrip {
            id: sectionStrip
            z: 11
            anchors.fill: parent
            view: root.sectionStripOn && !root.offTheRecord && root.ownKind === "" && !root.noPage && root.currentView && !root.currentView.failure
                  && !root.pageFullScreen ? root.currentView : null
            pointer: pagePointer
        }
    }
    readonly property alias windowStrip: sectionStrip
    // While the page slides at its folded width its right side lies past the window: the window's ground and the
    // card's two right corners stay where the folded page's right edge is.
    Item {
        visible: root.pageShift !== 0 && !root.pageFullScreen
        x: parent.width - root.inset - Theme.rounding.small
        width: root.inset + Theme.rounding.small
        height: parent.height
        Rectangle { x: Theme.rounding.small; width: root.inset; height: parent.height; color: Theme.terminal }
        Cap { y: root.inset; rotation: 90 }
        Cap { y: parent.height - root.inset - height; rotation: 180 }
    }

    // A web view that changes width shows its last frame, at the old size, in the new place until Chromium
    // draws the new one (about 100 ms): the page jumped twice around a seam. A still of the page covers it
    // until the page reports its new layout and two frames have passed, or for 150 ms: a narrower page
    // reports it late (266 ms, measured) though it draws within two frames. The page then changes once.
    // The still is a one-off copy of the part of the page area on screen (to the window's right inset while the page
    // lies slid), dropped when it goes.
    ShaderEffectSource {
        id: pageStill
        visible: false
        live: false
        property var then: null
        property bool beside: true
        property int frames: 0      // frames still to pass after the new layout
        function resize(beside, done) {
            if (root.pageBeside === beside) {
                done();
                return;
            }
            if (root.shotMode || !root.currentView) {
                root.placePage(beside);
                done();
                return;
            }
            x = pageArea.x + root.pageShift;
            y = pageArea.y;
            width = Math.min(pageArea.width, root.width - root.inset - x);
            height = pageArea.height;
            sourceRect = Qt.rect(0, 0, width, height);
            pageStill.beside = beside;
            then = done;
            sourceItem = pageArea;
            visible = true;
            scheduleUpdate();
        }
        onScheduledUpdateCompleted: {
            if (!then)
                return;
            root.placePage(beside);
            stillLimit.restart();
        }
        function cancel() {
            then = null;
            frames = 0;
            stillLimit.stop();
            visible = false;
            sourceItem = null;
        }
        function finish() {
            const done = then;
            cancel();
            if (done)
                done();
        }
        Timer { id: stillLimit; interval: 150; onTriggered: pageStill.finish() }
        Connections {
            target: pageStill.then && root.pageBeside === pageStill.beside ? root.currentView : null
            function onContentsSizeChanged() {
                if (pageStill.frames === 0) {
                    pageStill.frames = 2;
                    root.update();
                }
            }
        }
        Connections {
            target: pageStill.frames > 0 ? root : null
            function onFrameSwapped() {
                if (--pageStill.frames === 0)
                    pageStill.finish();
                else
                    root.update();
            }
        }
    }

    // The docked slab (PLAN.md 3.19): inset 6 px in the window, the page 6 px beside it. Folding hands its place to the
    // overlay at once, which lifts off it; pinning, the overlay settles here and hands it back.
    Rail {
        id: pinnedRail
        asksInSheet: true
        visible: root.railPinned && !root.docking && !root.pageFullScreen
        x: root.inset
        y: root.inset
        width: root.railWidth - 2 * root.inset
        height: parent.height - 2 * root.inset
        session: sessionModel
        omni: omniModel
        view: root.currentView
        pinned: root.railPinned
        quiet: root.quietRail
        offTheRecord: root.offTheRecord
        addressLifted: addressEditor.out
        finder: findModel
        site: siteInfo
        downloads: downloadModel
        earlier: earlierState
        saved: root.savedModel
        notice: root.cardNotice
        settings: settingsPage
        settingsOpen: root.ownKind === "settings"
        onNoticeActed: root.runNotice()
        onActivate: id => root.show(id)
        onClosePage: id => root.closePage(id)
        onRestoreThread: (id, page) => root.restoreThread(id, page)
        // a click goes where the keys go (addressKey, newPageKey)
        onNewPage: root.newPageKey()
        onAddressClicked: root.addressKey()
        onSiteClicked: row => root.openSite(row)
        onFillPicked: entry => root.fillLogin(entry)
        onTogglePin: root.railPinned = !root.railPinned
        // as Ctrl+, does
        onSettingsClicked: root.act("settings")
        onToggleMute: id => root.toggleMute(id)
        onCommand: (name, ref, arg) => root.command(name, ref, arg)
        onLeaveList: root.focusPage()
        Keys.onPressed: event => root.pageKey(event)
        // the pointer on it when it folds: the lifted rail stays out for it
        HoverHandler { id: pinnedHover }

        // the gap between the slab and the page: drag to resize, double-click for 300 again
        MouseArea {
            anchors { left: parent.right; top: parent.top; bottom: parent.bottom }
            width: root.inset
            visible: root.railPinned
            cursorShape: Qt.SizeHorCursor
            property real grab: 0
            onPressed: mouse => grab = mouse.x
            onPositionChanged: mouse => { if (pressed) root.railWidth = Math.max(248, Math.min(420, Math.round(root.railWidth + mouse.x - grab))) }
            onDoubleClicked: root.railWidth = 300
        }
    }

    // Folded (PLAN.md 3.5): a 16 px zone at the window's left edge opens the rail over the page, at once
    // when the pointer heads left into it, else after 40 ms; it leaves 260 ms after the pointer does. A
    // flick out of the window across its left side to the screen's edge opens it at once and holds it while
    // the cursor rests at the edge, until the pointer comes back or the window resizes (1.5 s where Hyprland
    // cannot say where the cursor is). Nothing opens it while a mouse button is held. Find, the site panel and
    // the page's ask hold it out while they are open in it: the pointer leaving does not close it, and when they
    // close it goes back unless the pointer is on it.
    Item {
        id: peek
        property bool open: false       // the pointer's: the hover zone, the overlay, a flick out
        property bool flung: false      // opened by a flick out across the left side; the pointer is away
        property bool kept: false       // lifted under the resting pointer, until it moves from `keptAt`
        property point keptAt
        readonly property bool hovered: kept || pointer.inZone && !pointer.held || peekHover.hovered || peekRail.busy || flung
        // held out by find, the site panel, Earlier, or the card's "Save password?" line (the other asks have their own
        // sheet over the page); not under an edit grown from the handle, where that line waits on the card's last line
        readonly property bool held: !root.railPinned && !root.pageFullScreen
            && (findModel.open && findModel.where === "peek" || siteInfo.open && siteInfo.where === "peek" || earlierState.view !== ""
                || root.shownAsk !== null && root.shownAsk.kind === "password" && root.railSlide === 1
                   && !(addressEditor.editing && !addressEditor.from.rest))
        readonly property bool out: open || held
        onHoveredChanged: {
            if (hovered) { closeTimer.stop(); openTimer.restart() }
            else { openTimer.stop(); closeTimer.restart() }
        }
        onOutChanged: {
            // settling into the dock it stays out, whatever the pointer does
            if (root.docking)
                return;
            if (out) { slideOut.stop(); slideIn.restart() }
            else { slideIn.stop(); slideOut.restart() }
        }
        Timer { id: openTimer; interval: 40; onTriggered: peek.open = true }
        Timer { id: closeTimer; interval: 260; onTriggered: { peek.open = false; if (!peek.out && (peekRail.listFocused || peekRail.fillFocused)) root.focusPage() } }
        Timer { id: flingTimer; interval: 1500; onTriggered: peek.flung = false }
        // flung: where the cursor is, every 100 ms (onCursorAnswered holds or drops it)
        Timer { id: flingPoll; interval: 100; repeat: true; running: peek.flung && !reask.running; onTriggered: root.askCursor() }
        // back from the edge on DefaultSpatial (as Files' rail), tucked away on Emphasized (the lift film, PLAN.md 3.19)
        Anim { id: slideIn; target: peekRail; property: "slide"; to: 1; type: Anim.DefaultSpatial }
        Anim { id: slideOut; target: peekRail; property: "slide"; to: 0; type: Anim.Emphasized }
    }
    // Folded, a grab handle over the page's left edge shows the rail is folded, not gone.
    Item {
        id: edge
        visible: !root.railPinned && !root.pageFullScreen
        width: 6
        height: parent.height
        // drawn once the rail has slid away
        Rectangle {
            id: handle
            visible: root.railSlide === 1
            x: root.inset + 4   // 4 px into the page, as the scrollbar pill
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 32
            radius: 2
            // the scrollbar pill's fill and hairline, so it reads on light and dark pages
            color: Theme.transparentize(Theme.onSurface, 0.45)
            border.width: 1
            border.color: Theme.transparentize(Theme.terminal, 0.45)
        }
    }
    // The lifted rail (PLAN.md 3.19), also the docked slab while it lifts and settles: at railLift 0 on the pinned
    // rail's place, at 1 inset 6 px inside the folded page with its right edge where the docked slab's was.
    Rail {
        id: peekRail
        asksInSheet: true
        property real slide: 0
        // from the start of its slide in, so what is held out in it can take the keys at once
        visible: (!root.railPinned || root.docking) && (slide > 0 || peek.out) && !root.pageFullScreen
        overlay: true
        lift: root.railLift
        fill: root.railFill
        readonly property real restX: root.inset * (1 + root.railLift)
        x: restX - (1 - slide) * (width + 12)
        y: root.inset * (1 + root.railLift)
        width: root.railWidth - root.inset * (2 + root.railLift)
        height: parent.height - 2 * y
        session: sessionModel
        omni: omniModel
        view: root.currentView
        pinned: root.railPinned
        offTheRecord: root.offTheRecord
        addressLifted: addressEditor.out
        finder: findModel
        site: siteInfo
        downloads: downloadModel
        earlier: earlierState
        saved: root.savedModel
        notice: root.cardNotice
        settings: settingsPage
        settingsOpen: root.ownKind === "settings"
        onNoticeActed: root.runNotice()
        HoverHandler { id: peekHover }
        onActivate: id => { peek.open = false; root.show(id) }
        onClosePage: id => root.closePage(id)
        onRestoreThread: (id, page) => { peek.open = false; root.restoreThread(id, page) }
        onNewPage: { peek.open = false; root.newPageKey() }
        onAddressClicked: root.addressKey()
        onSiteClicked: row => root.openSite(row)
        onFillPicked: entry => { peek.open = false; root.fillLogin(entry) }
        onTogglePin: root.railPinned = !root.railPinned
        onSettingsClicked: { peek.open = false; root.act("settings") }
        onToggleMute: id => root.toggleMute(id)
        onCommand: (name, ref, arg) => root.command(name, ref, arg)
        onLeaveList: { peek.open = false; root.focusPage() }
        Keys.onPressed: event => root.pageKey(event)
    }
    // Folded, the pointer anywhere in the window: the hover zone, the held button and the flick out across
    // the left side. Both handlers are passive, so the page and the rails get every event: the hover
    // handler sits on the window's root item (a sibling's would hide the hover from the items under it)
    // and the point handler on top of everything, where it sees presses before the page takes them.
    HoverHandler {
        id: windowPointer
        // offscreen the window gets one hover at (8, 8), in the zone, which opened the peek in the folded shots
        enabled: !root.railPinned && !root.shotMode && !root.pageFullScreen
        onPointChanged: {
            if (peek.kept && (point.scenePosition.x !== peek.keptAt.x || point.scenePosition.y !== peek.keptAt.y))
                peek.kept = false;
            if (!hovered || press.active)
                return;
            const x = point.position.x, y = point.position.y;
            if (!pointer.known || x !== pointer.lastX || y !== pointer.lastY)
                pointer.leftward = pointer.known && x < pointer.lastX && pointer.lastX - x > Math.abs(y - pointer.lastY);
            pointer.lastX = x;
            pointer.lastY = y;
            pointer.known = true;
            // heading out into the zone: at once; a way in or along the edge waits the 40 ms
            if (x < 16 && pointer.leftward && !peek.open)
                peek.open = true;
        }
        onHoveredChanged: {
            if (hovered) {
                flingTimer.stop();
                reask.stop();
                peek.flung = false;
                // the window may have moved (another monitor, another slot) since the last refresh
                Backdrop.refresh();
                return;
            }
            peek.kept = false;
            // out across the left side, not the top or bottom near it, from anywhere: a fast flick's last
            // sample inside can be hundreds of px in; then where did it go
            if (pointer.known && pointer.lastX < Math.min(pointer.lastY, root.height - pointer.lastY)
                    && (pointer.lastX <= 0 || pointer.leftward)) {
                reask.left = 10;
                reask.stop();
                root.askCursor();
            }
            pointer.known = false;
        }
    }
    // At the screen's left edge, level with the window, it is a flick; still in the gap before the window
    // (or in a neighbour) it is a reach for the resize border, and nothing opens. Hyprland often answers
    // before the next motion event, with the point that left the window, so an answer in the gap is asked
    // again every 16 ms, up to 10 times: a flick reaches the edge within a few frames, a reach stops in the
    // gap. Outside Hyprland it cannot tell, so it opens.
    Timer {
        id: reask
        property int left: 0
        readonly property bool again: left < 10 // a re-ask: Hyprland answered the first one
        interval: 16
        onTriggered: { left--; root.askCursor() }
    }
    // this window's place on the screen (Backdrop.posOf), refreshed with each answer from Hyprland
    readonly property point screenAt: { Backdrop.windowPos; return Backdrop.posOf(root) }
    // Backdrop answers every window; only one that asked takes the answer
    property bool cursorAsked: false
    function askCursor() {
        cursorAsked = true;
        Backdrop.askCursor();
    }
    Connections {
        target: Backdrop
        function onCursorAnswered(found, pos) {
            if (!root.cursorAsked)
                return;
            root.cursorAsked = false;
            if (root.railPinned || windowPointer.hovered || press.active)
                return;
            if (peek.flung) {
                // it holds while the cursor rests at the screen's edge, level with the window
                if (found) {
                    if (pos.x <= 1 && pos.y >= root.screenAt.y && pos.y < root.screenAt.y + root.height)
                        flingTimer.restart();
                    else
                        peek.flung = false;
                }
                return;
            }
            if (!found && reask.again)
                return;
            if (found && (pos.y < root.screenAt.y || pos.y >= root.screenAt.y + root.height))
                return;
            if (found && pos.x > 1) {
                if (pos.x < root.screenAt.x && reask.left > 0)
                    reask.restart();
                return;
            }
            peek.flung = true;
            peek.open = true;
            flingTimer.restart();
        }
    }
    Item {
        id: pointer
        anchors.fill: parent
        z: 100
        enabled: !root.railPinned && !root.pageFullScreen
        // the hover zone: the page's first 16 px
        readonly property bool inZone: windowPointer.hovered && windowPointer.point.position.x < 16
        readonly property bool held: press.active
        // the last hover position; unknown after a leave and from a press until the next hover move, since
        // no hover moves arrive while the page holds the grab
        property real lastX: 0
        property real lastY: 0
        property bool known: false
        property bool leftward: false   // the last move went mostly left
        PointHandler { id: press; acceptedButtons: Qt.AllButtons; onActiveChanged: if (active) pointer.known = false }
    }

    // Ctrl+L (PLAN.md 3.2, 5c): the address card lifts out of the visible rail, or out of the folded
    // edge's handle, into the centred card over the page, and goes back there.
    AddressEditor {
        id: addressEditor
        session: sessionModel
        omni: omniModel
        host: pageArea
        view: root.currentView
        waiting: root.waitingAsk
        origin: root.addressOrigin
        onNavigate: (url, fallback) => root.go(url, "navigate", "", "", "", false, fallback)
        onOpenHere: (url, name, fallback) => root.openHere(url, name, fallback)
        onPageAction: name => root.pageAction(name)
        onFindOnPage: text => root.openFind(text)
        onAskPraxis: question => root.askPraxis(question)
        onSwitchTo: id => root.show(id)
        onRestore: id => root.restoreThread(id)
        notice: root.cardNotice
        onReopen: id => root.reopenClosed(id)
        // its undo on the card's own last line, as the rail's card is an outline while this one is out
        onForgetRow: row => root.forgetRow(row, true)
        onUndo: root.runNotice()
        Keys.onPressed: event => root.pageKey(event)
    }
    // Ctrl+L in the notch (PLAN.md 3.19): the shell's address sheet answers from here; the card when it cannot
    NotchAddress {
        id: notchAddress
        app: root
        omni: omniModel
        session: sessionModel
        editor: addressEditor
        notch: root.offTheRecord ? null : root.hub.notch
    }
    // A sign-in popup in the notch (~/book4-edge/signin-notch-plan.md): the first window's, for every window's popups
    NotchSignin {
        id: notchSignin
        notch: root.primary === null ? root.signinNotch : null
    }
    // The floating card and bar, not the notch's sheet: the owner's choice (2026-10-02, "the old floating is more fluid
    // and nicer"). The notch path stays built and checked (EngineCheck's notch group switches it on). The first
    // window's value holds for every window (hub).
    property bool notchSearch: false
    // Ctrl+L and Alt+D, and a click on the address: the card; the notch's sheet when notchSearch is on and it can open
    function addressKey() {
        if (!root.hub.notchSearch || root.noPage || addressEditor.editing || !notchAddress.begin("edit"))
            editAddress();
    }
    // Ctrl+T, and New page: the bar; the notch's sheet as a new page when notchSearch is on and it can open (not while
    // the bar or the card is out, nor with no page: the bar is the page then)
    function newPageKey() {
        if (!root.hub.notchSearch || root.noPage || addressEditor.editing || newBar.opened || !notchAddress.begin("new"))
            newBar.show();
    }
    // the bar with the keys typed meanwhile, when Ctrl+T's sheet does not come (NotchAddress)
    function newPage(text) { newBar.show(text) }
    // an opening peek rail counts at the place it slides to; a closing one no longer counts
    function addressOrigin() {
        const rail = root.railPinned ? pinnedRail : peek.out ? peekRail : null;
        const r = rail ? rail.addressRect(addressEditor) : handle.mapToItem(addressEditor, 0, 0, handle.width, handle.height);
        const shift = rail === peekRail ? peekRail.restX - peekRail.x : 0;
        // the ground it lifts off: the slab's fill (docked or lifted), or the handle on the window's
        const ground = rail ? rail.ground : Theme.over(handle.color, Theme.terminal);
        return { x: r.x + shift, y: r.y, width: r.width, height: r.height, radius: rail ? Theme.rounding.small : handle.radius, rest: rail !== null, ground: ground };
    }

    CommandBar {
        id: newBar
        session: sessionModel
        omni: omniModel
        host: pageArea
        // the restore page (8i) is the page then, and the bar comes over it
        resident: root.noPage && !root.restorePage
        // in the current task, or a new one (Shift+Enter)
        onGo: (url, thread, name, background, fallback) => root.go(url, "new", thread, name, "", background, fallback)
        onPageAction: name => root.pageAction(name)
        onFindOnPage: text => root.openFind(text)
        onAskPraxis: question => root.askPraxis(question)
        // over the page, the bar takes the place of what was called up there; the rail shows its own list again
        onOpenedChanged: if (opened) { findModel.hide(); siteInfo.hide(); printCard.hide(); root.closeEarlier(false) }
        onSwitchTo: id => root.show(id)
        onRestore: id => root.restoreThread(id)
        notice: root.cardNotice
        onReopen: id => root.reopenClosed(id)
        onForgetRow: row => root.forgetRow(row, newBar.mode === "jump")
        onUndo: root.runNotice()
        // not when the address card took the focus from it (Ctrl+L, F6 or a click on the rail's address)
        onDismissed: {
            if (root.currentView && !addressEditor.editing)
                root.currentView.forceActiveFocus();
            else if (root.restorePage)
                failurePage.take();
        }
    }

    // Print (PLAN.md 3.16): Ctrl+P, > Print or the page's window.print(), over the page on screen; the PDF saved is listed
    // Developer tools (2026-10-15, the owner: "essential"): the page on screen's DevTools in a card of their own docked
    // under it or at its right (their own Dock side, 2026-10-16), 6 px of the window's ground between, the gap dragged to
    // resize them (double-click: 40 % again). F12, Ctrl+Shift+I or their own ✕ opens and closes them (DevTools.js); the
    // page menu's Inspect opens them at the element clicked. Each page keeps its own while it is open (its devToolsView),
    // shown with it.
    property real devToolsHeight: 0     // 40 % of the window when they first open
    property real devToolsWidth: 0      // docked right; 40 % of the window when they first open
    // as wide as that while the page keeps 320 px (a window tiled narrower), never under 200
    readonly property real devToolsWidthShown: Math.max(200, Math.min(devToolsWidth, width - pageArea.x - 2 * inset - 320))
    property string devToolsSide: "bottom"      // "bottom" or "right", kept (Store "devtools")
    readonly property real devToolsSize: devToolsSide === "right" ? devToolsWidthShown : devToolsHeight
    // F12 answers at once (the owner: "a delay and heavy" while new DevTools loaded unseen, 2026-10-15): the card slides
    // up on DevTools' own ground while their front end loads, and DevTools fade in once drawn (their view's `ready`).
    // The page makes room under heightStill, which keeps it as it was until the card is in place; closing, the card's
    // still slides down off the page that has taken its room back.
    readonly property bool devToolsWanted: !pageFullScreen && currentView !== null && !!currentView.devToolsView && ownKind === ""
    property bool devToolsShown: false
    property var devToolsShownFor: null
    property real devToolsSlide: 0      // 0 in place .. 1 below the window's foot
    onDevToolsWantedChanged: Qt.callLater(root.layDevTools)
    function layDevTools() {
        if (devToolsShown === devToolsWanted) {
            devToolsShownFor = currentView;
            return;
        }
        const lay = () => {
            root.devToolsShown = root.devToolsWanted;
            root.devToolsShownFor = root.currentView;
            // DevTools opened from the keys or the menu take them
            const d = root.devToolsShown && root.currentView ? root.currentView.devToolsView : null;
            if (d)
                d.dock(root.devToolsSide);
            if (d && d.takesKeys) {
                d.takesKeys = false;
                d.forceActiveFocus();
            }
        };
        if (devToolsWanted && currentView !== null && currentView === devToolsShownFor && !shotMode)
            heightStill.cover(lay, "open");
        else
            lay();
    }
    // The engine's frames between two heights squeezed and stretched the page (2026-10-15): while DevTools slide in or
    // out, stills keep the page (and closing, DevTools) as they were, so the page changes once, as the slide ends. Under
    // the card, which slides in over them. A resize (the gap dragged, or DevTools docked to their other side) keeps both
    // until each has drawn at its new size.
    Item {
        id: heightStill
        anchors.fill: parent
        // over DevTools while both change height; under the card that slides in
        z: mode === "resize" && then ? 1 : 0
        property var then: null
        property string mode: ""        // "open", "close", "resize"
        property int waiting: 0         // stills not taken yet
        component Copy: ShaderEffectSource {
            visible: false
            live: false
            onScheduledUpdateCompleted: if (heightStill.then && --heightStill.waiting === 0) heightStill.taken()
            function take(item) {
                sourceItem = item;
                x = item.x + root.pageShift;
                y = item.y;
                width = item.width;
                height = item.height;
                sourceRect = Qt.rect(0, 0, width, height);
                visible = true;
                scheduleUpdate();
            }
        }
        Copy { id: pageCopy }
        Copy { id: toolsCopy }
        Anim { id: toolsIn; target: root; property: "devToolsSlide"; from: 1; to: 0; type: Anim.EmphasizedSmall; onFinished: heightStill.finish() }
        Anim { id: toolsOut; target: toolsCopy; property: root.devToolsSide === "right" ? "x" : "y"; type: Anim.StandardSmall; onFinished: heightStill.finish() }
        // "open": DevTools come, sliding in; "close": they go, their still sliding out; "resize": both change size
        function cover(done, how) {
            if (then)
                finish();
            then = done;
            mode = how;
            waiting = how === "open" ? 1 : 2;
            pageCopy.take(pageArea);
            if (how !== "open")
                toolsCopy.take(devToolsArea);
        }
        function taken() {
            const done = then;
            then = () => {};
            if (mode === "close") {
                done();
                toolsOut.to = root.devToolsSide === "right" ? toolsCopy.x + toolsCopy.width + root.inset : toolsCopy.y + toolsCopy.height + root.inset;
                // the slide starts a frame later, once the page has drawn at its new size under DevTools' still (a frame
                // of ground showed where it grows, 2026-10-16)
                slideLater.enabled = true;
            } else if (mode === "open") {
                root.devToolsSlide = 1;
                done();
                toolsIn.restart();
            } else {
                done();
                resizeLimit.restart();
                resizeWatch.restart();
            }
        }
        Connections {
            id: slideLater
            target: root
            enabled: false
            function onFrameSwapped() {
                slideLater.enabled = false;
                toolsOut.restart();
            }
        }
        // a resize is over once the page and DevTools are on screen at their new sizes (or after 300 ms)
        Timer { id: resizeLimit; interval: 300; onTriggered: heightStill.finish() }
        Timer {
            id: resizeWatch
            interval: 16
            repeat: true
            onTriggered: {
                const v = root.currentView, d = v ? v.devToolsView : null;
                if ((!v || v.frameFits()) && (!d || d.frameFits()))
                    heightStill.finish();
            }
        }
        function finish() {
            slideLater.enabled = false;
            toolsIn.stop();
            toolsOut.stop();
            resizeLimit.stop();
            resizeWatch.stop();
            root.devToolsSlide = 0;
            then = null;
            for (const c of [pageCopy, toolsCopy]) {
                c.visible = false;
                c.sourceItem = null;
            }
        }
    }
    Item {
        id: devToolsArea
        readonly property bool atRight: root.devToolsSide === "right"
        visible: root.devToolsShown
        x: atRight ? root.width - root.inset - root.devToolsWidthShown : pageArea.x
        y: atRight ? pageArea.y : root.height - root.inset - root.devToolsHeight
        width: atRight ? root.devToolsWidthShown : pageArea.width
        height: atRight ? pageArea.height : root.devToolsHeight
        transform: Translate {
            x: root.pageShift + (devToolsArea.atRight ? root.devToolsSlide * (root.devToolsWidthShown + root.inset) : 0)
            y: devToolsArea.atRight ? 0 : root.devToolsSlide * (root.devToolsHeight + root.inset)
        }
        // DevTools' own ground (their dark theme's #262626) under a front end still loading
        Rectangle { anchors.fill: parent; color: "#262626" }
        Cap { z: 10 }
        Cap { z: 10; x: parent.width - width; rotation: 90 }
        Cap { z: 10; x: parent.width - width; y: parent.height - height; rotation: 180 }
        Cap { z: 10; y: parent.height - height; rotation: 270 }
        // Dragged, a ghost of the gap follows the pointer and the page and DevTools change once, on release (resized live,
        // the page's frames trailed the hand with an empty band under it, 2026-10-15)
        MouseArea {
            property real from: 0
            x: devToolsArea.atRight ? -root.inset : 0
            y: devToolsArea.atRight ? 0 : -root.inset
            width: devToolsArea.atRight ? root.inset : parent.width
            height: devToolsArea.atRight ? parent.height : root.inset
            cursorShape: devToolsArea.atRight ? Qt.SizeHorCursor : Qt.SizeVerCursor
            // where the pointer is across the gap, in the window
            function across(mouse) {
                const p = mapToItem(root.contentItem, mouse.x, mouse.y);
                return devToolsArea.atRight ? p.x : p.y;
            }
            onPressed: mouse => {
                from = across(mouse) + root.devToolsSize;
                root.devToolsDrag = root.devToolsSize;
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const most = devToolsArea.atRight ? root.width - pageArea.x - 2 * root.inset - 320 : root.height - 200;
                root.devToolsDrag = Math.round(Math.max(devToolsArea.atRight ? 280 : 120, Math.min(most, from - across(mouse))));
            }
            onReleased: root.resizeDevTools(root.devToolsDrag)
            onCanceled: root.devToolsDrag = -1
            onDoubleClicked: root.resizeDevTools(Math.round((devToolsArea.atRight ? root.width : root.height) * 0.4))
        }
    }
    property real devToolsDrag: -1      // the size the gap's ghost stands for while it is dragged
    function resizeDevTools(to) {
        devToolsDrag = -1;
        if (to < 0 || to === devToolsSize)
            return;
        const set = () => { if (root.devToolsSide === "right") root.devToolsWidth = to; else root.devToolsHeight = to };
        if (shotMode)
            set();
        else
            heightStill.cover(set, "resize");
    }
    // DevTools docked to their other side from their own menu (DevTools.js): the page and the card change once, under
    // stills; the side is kept, and the spare's front end told
    function dockDevTools(side) {
        if (side === devToolsSide || (side !== "bottom" && side !== "right"))
            return;
        if (devToolsShown && !shotMode)
            heightStill.cover(() => root.devToolsSide = side, "resize");
        else
            devToolsSide = side;
        if (!offTheRecord)
            Store.save("devtools", { used: Date.now(), side: side });
        if (devToolsSpare)
            devToolsSpare.dock(side);
    }
    // the ghost: the gap as it will be, the window's ground across the page with a hairline at its middle
    Rectangle {
        readonly property bool atRight: root.devToolsSide === "right"
        visible: root.devToolsShown && root.devToolsDrag >= 0 && root.devToolsDrag !== root.devToolsSize
        x: (atRight ? root.width - root.inset - root.devToolsDrag - root.inset : pageArea.x) + root.pageShift
        y: atRight ? pageArea.y : root.height - root.inset - root.devToolsDrag - root.inset
        width: atRight ? root.inset : pageArea.width
        height: atRight ? pageArea.height : root.inset
        color: Theme.terminal
        Rectangle {
            anchors.centerIn: parent
            width: parent.atRight ? 1 : parent.width
            height: parent.atRight ? parent.height : 1
            color: Theme.transparentize(Theme.inkMain, 0.6)
        }
    }
    Component {
        id: devToolsComponent
        WebEngineView {
            id: devTools
            anchors.fill: parent
            visible: inspectedView !== null && inspectedView === root.currentView
            // drawn: its front end has loaded, a frame of it has come and it reads the dark it is told (it drew one frame in
            // its light theme before, 2026-10-15), or 5 s have passed; it fades in then
            property bool ready: false
            property bool takesKeys: false
            property bool loaded: false
            // a spare loads unseen; once given a page and shown it waits for its first frame there
            onVisibleChanged: if (visible && loaded && !ready) painted.start()
            opacity: ready ? 1 : 0
            Behavior on opacity { Anim { type: Anim.FastEffects } }
            // their ground before their dark style applies: no white frame as they fade in
            backgroundColor: "#262626"
            // the side their front end is docked to, as it last said (DevTools.js)
            property string side: ""
            function dock(to) {
                if (side !== to)
                    runJavaScript(DevTools.dock(to));
            }
            // DevTools' own ✕ and Dock side, from their page (DevTools.js)
            webChannel: hostChannel
            webChannelWorld: WebEngineScript.ApplicationWorld
            WebChannel {
                id: hostChannel
                registeredObjects: [hostSink]
            }
            QtObject {
                id: hostSink
                WebChannel.id: "devtools"
                function host(what, side) {
                    if (what === "close") {
                        if (devTools.inspectedView !== null && devTools.inspectedView === root.currentView && root.devToolsShown)
                            root.toggleDevTools();
                        else
                            root.closeDevTools(devTools.inspectedView, devTools);
                    } else if (side === "bottom" || side === "right") {
                        devTools.side = side;
                        if (what === "pick" && devTools.visible)
                            root.dockDevTools(side);
                    }
                }
            }
            Component.onCompleted: {
                for (const [name, source, world] of [["thyris-devtools-host", DevTools.host(root.devToolsSide), WebEngineScript.MainWorld],
                                                     ["thyris-devtools-relay", DevTools.relay, WebEngineScript.ApplicationWorld]]) {
                    const s = WebEngine.script();
                    s.name = name;
                    s.sourceCode = source;
                    s.injectionPoint = WebEngineScript.DocumentCreation;
                    s.worldId = world;
                    userScripts.insert(s);
                }
            }
            Timer { interval: 5000; running: true; onTriggered: devTools.ready = true }
            Timer {
                id: painted
                property int dark: 0        // ticks in a row the page has read dark
                interval: 50
                repeat: true
                onTriggered: {
                    if (devTools.visible && devTools.frames() === 0)
                        return;
                    devTools.runJavaScript("matchMedia('(prefers-color-scheme: dark)').matches", d => {
                        painted.dark = d === true ? painted.dark + 1 : 0;
                        // a tick after it reads dark: its theme has followed
                        if (painted.dark >= 2 && painted.running) {
                            devTools.ready = true;
                            painted.stop();
                        }
                    });
                }
            }
            // DevTools closed themselves (their own close), or their page went
            onWindowCloseRequested: root.closeDevTools(inspectedView, devTools)
            // a link DevTools open (a request's address, a script's source) is a page of the inspected one's task
            onNewWindowRequested: request => {
                const p = inspectedView ? sessionModel.pages[inspectedView.pageId] : null, url = String(request.requestedUrl);
                if (p)
                    root.go(url, "new", p.thread, omniModel.hostOf(url), p.id, false);
            }
            // Tacit is dark: the DevTools page is told the system prefers dark, which DevTools' own default theme follows
            // (their Settings can still choose light)
            onLoadingChanged: {
                if (loading)
                    devtoolsCall("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
                // its load ends short of 100 % (70-74, 2026-10-15): the end is what counts
                else {
                    loaded = true;
                    if (!ready && visible)
                        painted.start();
                }
            }
        }
    }
    function toggleDevTools() {
        const v = root.currentView;
        if (!v || root.ownKind !== "" || v.failure)
            return false;
        const d = v.devToolsView;
        if (!d)
            openDevTools(v);
        else if (root.devToolsShown && v === root.currentView && !root.shotMode)
            // the stills first, while DevTools are still there; then they go and the page takes their room
            heightStill.cover(() => { root.closeDevTools(v, d); root.devToolsShown = false; root.devToolsShownFor = v }, "close");
        else
            closeDevTools(v, d);
        return true;
    }
    // Spare DevTools (the owner: "improve performance", 2026-10-15): once DevTools have been used, closing them readies
    // a spare, its front end loaded with no page (PageItem.prepareDevTools), which the next F12 on any page takes: it
    // shows at once instead of loading for 0.3-1.2 s. About 100 MB while it waits, so it goes after 10 minutes unused.
    property var devToolsSpare: null
    property bool devToolsUsed: false
    Timer { id: spareMake; interval: 1500; onTriggered: root.makeDevToolsSpare() }
    Timer { id: spareStart; interval: 8000; onTriggered: root.makeDevToolsSpare() }
    Timer { id: spareDrop; interval: 600000; onTriggered: { if (root.devToolsSpare) root.devToolsSpare.destroy(); root.devToolsSpare = null } }
    function makeDevToolsSpare() {
        if (devToolsSpare || shotMode)
            return;
        devToolsSpare = devToolsComponent.createObject(devToolsArea);
        devToolsSpare.prepareDevTools();
        spareDrop.restart();
    }
    function openDevTools(v) {
        if (!v.devToolsView) {
            if (root.devToolsHeight === 0)
                root.devToolsHeight = Math.round(root.height * 0.4);
            if (root.devToolsWidth === 0)
                root.devToolsWidth = Math.round(root.width * 0.4);
            const spare = root.devToolsSpare;
            root.devToolsSpare = null;
            spareDrop.stop();
            v.devToolsView = spare ?? devToolsComponent.createObject(devToolsArea);
            // the first use this run: kept, so the next start readies a spare
            if (!root.devToolsUsed && !root.offTheRecord)
                Store.save("devtools", { used: Date.now(), side: root.devToolsSide });
            root.devToolsUsed = true;
        }
        if (root.devToolsShown && v === root.currentView)
            v.devToolsView.forceActiveFocus();
        else
            v.devToolsView.takesKeys = true;
    }
    function closeDevTools(v, d) {
        const focused = !!d && d.activeFocus;
        if (v && v.devToolsView === d)
            v.devToolsView = null;
        if (d)
            d.destroy();
        if (root.devToolsUsed && !root.devToolsSpare)
            spareMake.restart();
        if (focused && v && v === root.currentView)
            v.forceActiveFocus();
    }
    // the page menu's Inspect: the element right-clicked, in the page's DevTools
    function inspectElement(v) {
        if (!v || v.failure)
            return;
        openDevTools(v);
        v.triggerWebAction(WebEngineView.InspectElement);
    }

    // under its page as a download (printSaved), and "Sent to <printer>" says a job went to CUPS
    PrintCard {
        id: printCard
        host: pageArea
        live: !root.shotMode
        folder: root.downloadFolder
        onSaved: (pageId, path) => root.printSaved(pageId, path)
        onNotice: (text, ms) => root.showNotice({ text: text, action: "", where: "card" }, ms)
        onDismissed: keys => { if (keys && root.currentView) root.currentView.forceActiveFocus() }
    }

    // the first start: bring a browser's things over (thyris-migration-plan.md; mock stage, only the shots open it)
    Welcome {
        id: welcomePage
        z: 1000
    }

    Component {
        id: viewComponent
        BrowserView {
            anchors.fill: parent
            visible: false
            // as Ctrl+Plus and Ctrl+Minus: the site's zoom, not on Opsis's own pages
            onZoomWanted: steps => { for (let i = 0; i < Math.abs(steps); i++) root.act(steps > 0 ? "zoomIn" : "zoomOut"); }
            readsSections: root.sectionStripOn && !root.offTheRecord
            adblock: root.adblock
            session: sessionModel
            visits: historyModel
            sites: siteModel
            certificates: certificateModel
        }
    }

    Component {
        id: standInComponent
        PageStandIn {
            anchors.fill: parent
            visible: false
            session: sessionModel
        }
    }

    // A sign-in or payment popup (PLAN.md 8k): attached to the page that opened it, which keeps window.opener. It
    // shows while that page is on screen, in the notch only (NotchSignin, ~/book4-edge/signin-notch-plan.md): its
    // page alone, shown under the app_id browser-signin into the hole the shell leaves under the notch, when the
    // shell says so, at the size it says (hypr/browser.lua floats and places it). Where the notch cannot take it, from
    // the first (openFromOpener) or later (popupToPage), it is a page instead: no window of its own (2026-10-14).
    Component {
        id: popupComponent
        Window {
            id: popupWindow
            required property var opener       // the opener's BrowserView
            required property rect asked       // the size window.open asked for, if any
            property string link: ""            // the address window.open asked for, for a page before it has loaded one
            readonly property alias view: popupView
            readonly property alias card: popupCard
            readonly property var main: root
            // "notch", or "" until NotchSignin has said so
            property string shownIn: ""
            readonly property bool openerShown: opener === root.currentView && root.visibility !== Window.Minimized
            // for NotchSignin: still its opener's popup, and whom it is for
            readonly property bool wanted: opener !== null && opener.popup === popupWindow
            readonly property bool fromApp: false
            readonly property string forName: PageState.pageHost(String(opener.url))
            readonly property string forIcon: (Engine.iconRevision, Engine.keptIcon(String(opener.icon)))
            // the notch cannot take it any more (the shell went, said off, or never said hello): a page instead
            function inWindow() { root.popupToPage(popupWindow) }
            // in the notch: the page alone at the size of the sheet's hole, given the keys
            function mapAt(w, h) {
                width = w;
                height = h;
                if (!visible)
                    Windows.showAs(popupWindow, "browser-signin");
                requestActivate();
                popupView.forceActiveFocus();
            }
            function unmap() {
                hide();
            }
            // Qt counts a window as active while its dialog has the focus, so the two windows' shortcuts
            // would both match (and neither fire): each acts only while its own contents have the keys
            readonly property bool hasKeys: contentItem.activeFocus
            // Done without saying so (the bug of 2026-09-29): a sign-in that left its opener's site and came back to
            // it, where the page never calls window.close() because its opener was to close it, and the sign-in
            // site's Cross-Origin-Opener-Policy cut the opener off. Back on the opener's site, loaded, still there
            // 1.5 s later, on no error page, with no field showing (a form it still asks you to fill) and no ask of
            // its header waiting (the sign-in's "Save password for <host>?"): done. An ask answered there starts the
            // 1.5 s again.
            property bool leftOpener: false
            readonly property bool backHome: leftOpener && PageState.sameSite(String(popupView.url), String(opener.url))
            readonly property bool settled: backHome && !popupView.loading && popupView.failure === null && popupView.asks.length === 0
            function closeIfDone() {
                if (!settled || opener.popup !== popupWindow)
                    return;
                popupView.runJavaScript("(() => { for (const f of document.querySelectorAll('input:not([type=hidden]):not([type=button]):not([type=submit])"
                    + ":not([type=reset]):not([type=image]), textarea, select, [contenteditable]:not([contenteditable=false])')) {"
                    + " const r = f.getBoundingClientRect(); if (r.width > 0 && r.height > 0) return true } return false })()",
                    WebEngineScript.ApplicationWorld,
                    asks => { if (asks === false && popupWindow.settled && popupWindow.opener.popup === popupWindow) root.closePopup(popupWindow, true, true) });
            }
            Timer { id: backHomeTimer; interval: 1500; onTriggered: popupWindow.closeIfDone() }
            Connections {
                target: popupView
                function onUrlChanged() {
                    const u = String(popupView.url);
                    if (PageState.hostOf(u) !== "" && !PageState.sameSite(u, String(popupWindow.opener.url)))
                        popupWindow.leftOpener = true;
                    backHomeTimer.stop();
                }
                function onLoadingChanged(request) {
                    if (request.status === WebEngineView.LoadSucceededStatus && popupWindow.backHome)
                        backHomeTimer.restart();
                }
            }
            // read here, not in the view's asksChanged, where this binding may not have taken the new asks yet
            onSettledChanged: if (settled) backHomeTimer.restart()
            // no dialog of the main window: Hyprland places it under the notch, not over its parent
            transientParent: null
            title: "Sign-in window · " + (popupView.pageTitle || PageState.pageHost(String(popupView.url)) || RailRows.untitled(String(popupView.url)))
            color: Theme.terminal
            // closed from outside (the compositor's close key): as its own close
            onClosing: close => { close.accepted = false; popupView.requestClose() }

            PopupCard {
                id: popupCard
                anchors.fill: parent
                view: popupView
                onCloseClicked: popupView.requestClose()
                onFailurePicked: action => root.failureAction(popupView, action, popupWindow)
            }
            BrowserView {
                id: popupView
                parent: popupCard.pageSlot
                anchors.fill: parent
                profile: root.profile
                adblock: root.adblock
                session: sessionModel
                visits: historyModel
                sites: siteModel
                certificates: certificateModel
                holder: popupWindow
                // a popup's own new windows join its opener's thread
                onOpenRequested: request => root.openFromOpener(popupWindow.opener.pageId, request, popupView)
                onCopyRequested: text => root.copyText(text)
                onLoginFailed: text => root.showNotice({ text: text, action: "", where: "card" }, 4000)
                onAsked: if (!popupWindow.active) popupWindow.alert(0)
                onSelfClosed: root.closePopup(popupWindow, true, true)
                onCloseAccepted: root.closePopup(popupWindow, true)
                onCloseWanted: root.closePopup(popupWindow, true)
                onProcessStopped: (status, code) => root.pageStopped(popupView, status, code, popupWindow.visible)
            }
            Shortcut { sequences: ["Ctrl+W"]; enabled: popupWindow.hasKeys; onActivated: popupView.requestClose() }
        }
    }

    // A sign-in from another app (~/book4-edge/signin-notch-plan.md): a link that is one (PageState.appSignIn) opens in
    // the notch: its page alone under the app_id browser-signin, which NotchSignin shows as it shows a popup,
    // "for" the app the link came from. Done when its navigation has passed the redirect_uri its link named (gcloud's
    // http://localhost:8085/, on to cloud.google.com's "You are now authenticated") and a page has loaded after it, or
    // when the page calls window.close(): it closes and the shell gives the keys back to the app's window. Signed only
    // when the redirect carried no error (a sign-in you denied comes back with one). Anywhere else it stays until Esc,
    // the flick or the way back. When the notch cannot show it, a page in the main window (appSigninToPage).
    property var appSignin: null
    Component {
        id: appSigninComponent
        Window {
            id: signinWindow
            required property string link
            property string from: ""            // the app the link came from
            property string context: ""         // what the caller was doing (Instance.context)
            readonly property alias view: signinView
            readonly property var main: root
            property string shownIn: ""
            // for NotchSignin, as a popup window: always "on screen"; the room asked for, the notch's largest page
            readonly property bool wanted: root.appSignin === signinWindow
            readonly property bool fromApp: true
            readonly property bool openerShown: true
            readonly property rect asked: Qt.rect(0, 0, 560, 480)
            readonly property string forName: from
            readonly property string forIcon: ""
            readonly property string redirect: PageState.redirectOf(link)
            // the redirect passed: "" not yet, "ok", or "error" (it came back with error=...)
            property string answer: ""
            function inWindow() { root.appSigninToPage(signinWindow) }
            function mapAt(w, h) {
                width = w;
                height = h;
                if (!visible)
                    Windows.showAs(signinWindow, "browser-signin");
                requestActivate();
                signinView.forceActiveFocus();
            }
            function unmap() { hide() }
            function note(url) {
                if (answer === "" && PageState.reached(url, redirect))
                    answer = PageState.queryOf(url).error !== undefined ? "error" : "ok";
            }
            transientParent: null
            width: 560
            height: 480
            visible: false
            title: "Sign-in window · " + (signinView.pageTitle || PageState.pageHost(String(signinView.url)) || RailRows.untitled(String(signinView.url)))
            color: Theme.terminal
            onClosing: close => { close.accepted = false; signinView.requestClose() }
            Timer { id: answered; interval: 400; onTriggered: if (signinWindow.wanted && !signinView.loading && signinView.failure === null) root.closeAppSignin(signinWindow, signinWindow.answer === "ok") }
            Connections {
                target: signinView
                // redirects too: gcloud's localhost answer redirects on at once, and only its address carries the code
                function onNavigationRequested(request) { if (request.isMainFrame) signinWindow.note(String(request.url)) }
                function onUrlChanged() { signinWindow.note(String(signinView.url)); answered.stop() }
                function onLoadingChanged(request) {
                    if (request.status === WebEngineView.LoadSucceededStatus && signinWindow.answer !== "")
                        answered.restart();
                }
            }
            Item {
                id: signinSlot
                anchors.fill: parent
                PageDialog { view: signinView }
                FailurePage { view: signinView; page: signinView.failure ?? null; onPicked: action => root.failureAction(signinView, action, null) }
                // a key the page left unhandled: Esc is the way back
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
                        event.accepted = true;
                        signinView.requestClose();
                    }
                }
            }
            BrowserView {
                id: signinView
                parent: signinSlot
                anchors.fill: parent
                profile: root.profile
                adblock: root.adblock
                session: sessionModel
                visits: historyModel
                sites: siteModel
                certificates: certificateModel
                holder: signinWindow
                // a sign-in's own new window loads in it; any other link from it is a page in the main window
                onOpenRequested: request => {
                    const url = String(request.requestedUrl);
                    if (PageState.appSignIn(url))
                        signinView.url = url;
                    else
                        root.openLink(url, signinWindow.from, "");
                }
                onCopyRequested: text => root.copyText(text)
                onSelfClosed: root.closeAppSignin(signinWindow, signinWindow.answer !== "error")
                onCloseAccepted: root.closeAppSignin(signinWindow, false)
                onCloseWanted: root.closeAppSignin(signinWindow, false)
                onProcessStopped: (status, code) => root.pageStopped(signinView, status, code, signinWindow.visible)
            }
            Shortcut { sequences: ["Ctrl+W"]; enabled: signinWindow.contentItem.activeFocus; onActivated: signinView.requestClose() }
        }
    }

    Loader {
        active: root.engineCheck !== null
        sourceComponent: EngineCheck { app: root; probe: root.engineCheck; session: sessionModel; address: addressEditor; newPageBar: newBar; hoverPeek: peek; peekedRail: peekRail; pageScroll: pageScrollBar; rail: pinnedRail; dialog: pageDialog; screenNotice: notice; ownPage: failurePage; history: historyModel; downloads: downloadModel; site: siteInfo }
    }
    Loader {
        // the first window's only: a window it makes (newWindow) is in shot mode too
        active: root.shots !== null
        // named apart from the ids: `peek: peek` would bind the property to itself; and through root, as Shots' own
        // function peek() hides the id in here
        sourceComponent: Shots { app: root; session: sessionModel; history: historyModel; hoverPeek: root.windowHover; peekedRail: peekRail; newPageBar: newBar; rail: pinnedRail; addressCard: addressEditor; pageScroll: pageScrollBar; failures: failurePage; site: siteInfo; welcome: welcomePage }
    }

    function viewFor(pageId) {
        let v = views[pageId];
        if (!v) {
            // made hidden: only show() makes a view visible. A page opened in the background stayed visible until the next
            // switch, so Chromium drew it, ran its timers unthrottled and kept its tiles (2026-10-03: 15 sites took
            // 2.3 GB against Chrome's 1.3 GB)
            v = (root.shotMode ? standInComponent : viewComponent).createObject(pageArea, { pageId: pageId, profile: root.profile, visible: false });
            v.openRequested.connect(request => root.openFromOpener(pageId, request));
            // a page's own menu (the shots' stand-in has none)
            if (v.menuWanted) {
                v.ownMenu = true;
                v.menuWanted.connect((request, at) => root.openPageMenu(v, request, at));
            }
            v.leaveAlways.connect(url => root.go(url, "new", "", omniModel.hostOf(url)));
            v.linkHovered.connect(url => { if (v === root.currentView) root.hoveredLink = String(url) });
            v.asked.connect(a => root.asked(pageId, a));
            v.closeAccepted.connect(() => root.finishClose(pageId));
            v.closeKept.connect(() => { pinnedRail.closeKept(pageId); peekRail.closeKept(pageId) });
            v.copyRequested.connect(text => root.copyText(text));
            v.closeWanted.connect(() => root.finishClose(pageId));
            v.processStopped.connect((status, code) => root.pageStopped(v, status, code, v === root.currentView && !v.parked));
            v.saveWanted.connect(a => root.saveToMain(a));
            v.loginFailed.connect(text => root.showNotice({ text: text, action: "", where: "card" }, 4000));
            // window.print() of the page on screen: the print card, as Ctrl+P
            v.printWanted.connect(() => { if (v === root.currentView && !v.parked) root.openPrint() });
            views[pageId] = v;
        }
        return v;
    }

    // `keys`: the keys stay where they are (the site panel, when its site's page comes back after a clear). A page in
    // another window's rail (@, a suggestion, Ctrl+Shift+T) shows there, and that window takes the focus.
    function show(pageId, keys) {
        const p = sessionModel.pages[pageId];
        if (!p)
            return;
        if (newBar.opened)
            newBar.hide();
        // the page the restore page offered (8i): opened, it is suspect for a minute
        const offered = root.restorePage !== null && pageId === root.restorePage.pageId;
        if (offered) {
            writeRun({ suspect: pageId });
            suspectTimer.restart();
        }
        const owner = ownerOf(pageId);
        if (owner && owner !== root) {
            // it was on screen in another window when the browser stopped: it shows there, and this window has no page
            if (offered) {
                root.restorePage = null;
                afterClose();
            }
            owner.show(pageId, keys);
            owner.raise();
            return;
        }
        const v = viewFor(pageId);
        const again = root.currentView === v && sessionModel.currentPage === pageId;
        // the page you leave: where you stopped on it (PLAN.md 3.7)
        if (root.currentView && root.currentView !== v)
            captureStop(root.currentView);
        // page full screen ends with its page leaving the screen
        if (root.currentView && root.currentView !== v && root.currentView.isFullScreen && !root.shotMode)
            root.currentView.fullScreenCancelled();
        // a page of a site whose data is being cleared stays unloaded until that is done (PLAN.md 3.9)
        const held = siteInfo.clearing !== null && Asks.originOf(String(v.url) || p.url) === siteInfo.clearing.origin;
        if (!held) {
            v.lifecycleState = WebEngineView.LifecycleState.Active;
            // a page moved from another window loads with the back history and scroll it had there
            if (String(v.url) === "" && p.url) {
                if (p.restore && Windows.restore(v, p.restore.history)) {
                    v.restoreScroll = p.restore.scroll;
                } else {
                    // loaded afresh (a thread brought back, a closed page reopened, a start): back where you stopped (3.7)
                    v.restoreStop = Recall.current(p);
                    v.url = p.url;
                }
            }
            if (p.restore)
                sessionModel.update(pageId, { restore: undefined });
            // a page whose process stopped loads again when opened (PLAN.md 8h), unless it stopped twice in 10
            // minutes; an offline page whose network came back while it was away loads once
            if (v.reloadOnShow) {
                v.reloadOnShow = false;
                v.reload();
            } else if (!again && v.failure && (v.failure.kind === "crash" && !v.failure.twice
                                                || v.failure.kind === "offline" && Facts.reachability === "online")) {
                v.retry();
            }
        }
        if (root.restorePage)
            root.restorePage = null;
        writeRun({ page: pageId });
        // Settings over the page you came from: that page stays on screen under it
        const settingsShown = ownPageOf(String(v.url) || p.url) === "settings";
        if (!settingsShown)
            root.behindView = null;
        else if (root.currentView && root.currentView !== v && ownPageOf(String(root.currentView.url)) === "")
            root.behindView = root.currentView;
        for (const id in views) {
            views[id].visible = settingsShown ? views[id] === v || views[id] === root.behindView : id === pageId && !held;
            views[id].opacity = settingsShown && views[id] === v ? 0 : 1;
        }
        sessionModel.activate(pageId);
        sessionModel.update(pageId, { state: held ? "unloaded" : "live" });
        root.currentView = v;
        root.hoveredLink = "";
        if (!keys)
            v.forceActiveFocus();
    }

    // A link opened from a page joins that page's thread, right after it (middle-click or Ctrl+click in
    // the background, Ctrl+Shift+click in front); Shift+click, or any link from an Always site, starts a
    // thread of one (PLAN.md 5, Mouse). window.open with a size, or to a sign-in or payment host, opens an
    // attached popup in the notch instead; where the notch cannot take it (a private window, full window) a page
    // right after its opener, which stays its window.opener and closes when it calls window.close() (PLAN.md 8k).
    // One without a click from you is refused. A file dropped
    // where the page does not take it comes as a new page too: a PDF, image or text file joins the thread,
    // any other opens nothing (8l). `popupView`: the request came from the opener's popup, whose new
    // windows are always pages.
    function openFromOpener(openerId, request, popupView) {
        const opener = sessionModel.pages[openerId];
        if (!opener)
            return;
        const url = String(request.requestedUrl);
        const drop = PageState.dropped(url, String((popupView ?? views[openerId]).url));
        if (drop === "nothing")
            return;
        const D = WebEngineNewWindowRequest;
        // a site whose pop-ups the site panel allows opens them without a click too
        const origin = Asks.originOf(String((popupView ?? views[openerId]).url));
        const where = drop === "page" ? "page" : PageState.newWindow(request.destination === D.InNewDialog ? "dialog" : request.destination === D.InNewBackgroundTab ? "background"
                                          : request.destination === D.InNewWindow ? "window" : "tab",
                                          request.userInitiated || siteModel.choice(origin, "popups") === "allow", url);
        if (where === "blocked") {
            siteModel.noteAsked(origin, ["popups"]);
            views[openerId].blockedPopups++;
            return;
        }
        if (where === "popup" && !popupView && root.hub.windowSignin.takes(root)) {
            openPopup(views[openerId], request);
            return;
        }
        const id = request.destination === WebEngineNewWindowRequest.InNewWindow
            ? sessionModel.addPage(sessionModel.newThread(omniModel.hostOf(url)), "", "")
            : sessionModel.addFromOpener(openerId, "", omniModel.hostOf(url));
        const v = viewFor(id);
        request.openIn(v);
        adopt(v, popupView ?? views[openerId]);
        sessionModel.update(id, { state: "live" });
        if (request.destination !== WebEngineNewWindowRequest.InNewBackgroundTab)
            show(id);
        // a popup as a page goes when it is done, as the popup would have
        if (where === "popup" && !popupView)
            v.selfClosed.connect(() => { if (views[id] === v) finishClose(id) });
    }

    // One popup per page: a new one takes the old one's place.
    function openPopup(opener, request) {
        if (opener.popup)
            closePopup(opener.popup, false);
        const g = request.requestedGeometry;
        const w = popupComponent.createObject(made, { opener: opener, asked: Qt.rect(0, 0, g.width, g.height), link: String(request.requestedUrl) });
        request.openIn(w.view);
        adopt(w.view, opener);
        opener.popup = w;
        // the notch takes it, or it is a window of its own
        if (!root.hub.windowSignin.want(w))
            w.inWindow();
    }
    // A popup the notch gave back (NotchSignin.fallBack, inWindow): a page right after its opener, at the address it has
    // reached (the one window.open asked for, before it has one). A live view cannot move between windows, so it loads
    // there afresh, without window.opener.
    function popupToPage(w) {
        const opener = w.opener, url = String(w.view.url) || w.link;
        w.shownIn = "";
        closePopup(w, false);
        if (opener && sessionModel.pages[opener.pageId] && url !== "")
            show(sessionModel.addFromOpener(opener.pageId, url, omniModel.hostOf(url)));
    }
    // Closed by itself (`signed`), by you or with its opener. `refocus`: the keys go back to the opener's page.
    function closePopup(w, refocus, signed) {
        const opener = w.opener;
        if (opener && opener.popup === w)
            opener.popup = null;
        // in the notch the page stays until the shell has closed its hole over it, then goes
        if (w.shownIn === "notch" && root.hub.windowSignin.closing(w, signed === true, () => finishPopup(w, opener, refocus, true)))
            return;
        if (w.shownIn === "notch")
            root.hub.windowSignin.closed(w, signed === true);
        finishPopup(w, opener, refocus, w.shownIn === "notch");
    }
    function finishPopup(w, opener, refocus, notched) {
        w.visible = false;
        retire(w.view);
        if (refocus && opener === root.currentView) {
            root.requestActivate();
            opener.forceActiveFocus();
            // the page in the notch was a window of no parent: Hyprland is told where the focus goes
            if (notched)
                Backdrop.focus(root);
        }
    }

    // "navigate": load into the current page. "new": a page in `thread` ("" makes a thread named `name`),
    // after page `after` or at the thread's end; in the background it loads but is not shown. A typed
    // address comes with `fallback`, the plain http it loads if its https attempt cannot connect. With `stop`
    // (Recall.js) it goes back where you stopped on that address once it has loaded (PLAN.md 3.7).
    function go(url, mode, thread, name, after, background, fallback, stop) {
        if (mode === "navigate" && sessionModel.current) {
            // typed on an Always site for another site: a thread of one, as a link from it would
            if (sessionModel.leavesAlways(sessionModel.currentPage, url))
                return go(url, "new", "", omniModel.hostOf(url), "", false, fallback, stop);
            const v = viewFor(sessionModel.currentPage);
            if (fallback)
                v.fallBackTo(fallback);
            if (stop)
                v.restoreStop = stop;
            v.url = url;
            return;
        }
        // a destination thread that went (moved out, filed) since it was chosen: a new thread instead
        const t = sessionModel.threadById(thread);
        const id = sessionModel.addPage(t && !t.earlier ? thread : sessionModel.newThread(name), url, after ?? "");
        if (fallback)
            viewFor(id).fallBackTo(fallback);
        // show() loads it back at the page's stop
        if (stop)
            sessionModel.setStopped(id, stop);
        if (!background) {
            show(id);
            return;
        }
        if (stop)
            viewFor(id).restoreStop = stop;
        viewFor(id).url = url;
        sessionModel.update(id, { state: "live" });
    }

    // A link from another app (PLAN.md 3.20), handed over by a later `browser` run or the one this run started with: a
    // page in front, in the main window that has the focus, else in the one that had it last, brought to your workspace
    // as Super+W brings it. It goes into the open task Ctrl+T's rule picks from its address and what the caller was
    // doing (`context`, Instance.context: a shell's folder), else into a task of its own. `from` names the app ("" when
    // unknown) and stays on the page. Returns where it went: "page" or "signin".
    function openLink(url, from, context) {
        // the browser's own pages are drawn in a main window only (PLAN.md 3.17), the one that is open if one is
        const own = ownPageOf(url);
        if (own && !root.shotMode) {
            const w = lastMain();
            showMain();
            // browser://settings/<section> opens at that section (SettingsPage.show takes a fold's or a member's name)
            w.openOwn(own, ((/^browser:\/\/[a-z]+\/([a-z]+)/i.exec(url) ?? [])[1] ?? "").toLowerCase()).requestActivate();
            return "page";
        }
        // a sign-in: in the notch (a page when the notch cannot show it)
        if (!root.shotMode && PageState.appSignIn(url) && appSigninLink(url, from, context ?? ""))
            return "signin";
        openPage(url, from, context ?? "", !root.shotMode);
        return "page";
    }
    // The page openLink opens, or one a sign-in from another app becomes where the notch cannot show it. `watch`: its
    // first load is watched for a sign-in after all (watchLink).
    function openPage(url, from, context, watch) {
        let m = activeMain() ?? (root.shotMode ? root : null);
        if (!m) {
            m = lastMain();
            showMain(true);
        }
        const s = m.windowSession;
        // the task it joins shares a word with what the app was doing: the words of an address alone (its host's, its
        // path's) match too many tasks
        let thread = context ? s.predictThread(url + " " + context + " ", "") : "";
        if (thread && s.sharedWords(context + " ", thread).length === 0)
            thread = "";
        const id = s.addPage(thread || s.newThread(omniModel.hostOf(url)), url, "");
        if (from)
            s.update(id, { from: from, fromAt: Date.now() });
        m.show(id);
        m.requestActivate();
        if (watch)
            m.watchLink(id, from, context);
    }
    // A link from another app that is a sign-in after all, on its first load: its address becomes one (a link that
    // redirects there), or the page asks for a password or a one-time code (PageState.signInFields), looked for just
    // after the load and once more when a script drew the form. It moves to the notch (pageToSignin), unless something
    // was typed into it; later loads are not watched.
    function watchLink(pageId, from, context) {
        const v = views[pageId];
        if (v)
            linkWatchComponent.createObject(v, { view: v, pageId: pageId, from: from, context: context });
    }
    Component {
        id: linkWatchComponent
        Item {
            id: watch
            required property var view
            required property string pageId
            required property string from
            required property string context
            property int tries: 0
            visible: false
            function move() {
                root.pageToSignin(pageId, from, context);
                destroy();
            }
            Connections {
                target: watch.view
                function onUrlChanged() {
                    if (PageState.appSignIn(String(watch.view.url)))
                        watch.move();
                }
                function onLoadingChanged(request) {
                    if (request.status === WebEngineView.LoadSucceededStatus)
                        look.restart();
                    else if (request.status === WebEngineView.LoadFailedStatus)
                        watch.destroy();
                }
            }
            Timer {
                id: look
                interval: watch.tries === 0 ? 300 : 1200
                onTriggered: watch.view.runJavaScript("!window.__browserEdited && " + PageState.signInFields, WebEngineScript.ApplicationWorld, found => {
                    if (found === true)
                        watch.move();
                    else if (++watch.tries < 2)
                        look.restart();
                    else
                        watch.destroy();
                })
            }
        }
    }
    // The page leaves this window for the notch, as if it had never opened here; it stays when the notch cannot take it
    function pageToSignin(pageId, from, context) {
        const v = views[pageId];
        if (!v || !hub.appSigninLink(String(v.url), from, context))
            return;
        const s = sessionModel;
        s.dropPage(pageId);
        if (s.currentPage === pageId)
            s.currentPage = s.mostRecentPage() ?? "";
        s.touch();
        dropViews([pageId]);
        afterClose();
        pinnedRail.closed(pageId);
        peekRail.closed(pageId);
    }
    Connections {
        target: root.instance
        // an empty url: `browser` run with no address (Super+W), which asks for the window: it comes to the workspace
        // you are on, as it is, a video in it still playing (owner, 2026-10-01: it stayed on the workspace it was on)
        function onOpened(url, from, context) {
            if (String(url) === "")
                root.showMain(true);
            else
                root.openLink(String(url), from, context);
        }
    }
    // A sign-in from another app (appSigninComponent): one at a time, a new one in place of the one before. False when
    // the notch cannot take it at all (no shell socket, a private window): the caller opens it as a page.
    function appSigninLink(url, from, context) {
        const old = root.appSignin;
        const w = appSigninComponent.createObject(made, { link: url, from: from ?? "", context: context ?? "" });
        // the new one is in place before the old one closes: closing it looks for anything left open, and with no
        // window shown yet (Thyris started for the sign-in) it found nothing and quit (a second sign-in link)
        root.appSignin = w;
        if (old)
            closeAppSignin(old, false);
        w.view.url = url;
        if (root.windowSignin.want(w))
            return true;
        root.appSignin = null;
        retire(w.view);
        return false;
    }
    // It closed (`signed`: done), the page first while it is in the notch; the shell gives the keys back to the app
    function closeAppSignin(w, signed) {
        if (root.appSignin === w)
            root.appSignin = null;
        const finish = () => {
            w.visible = false;
            retire(w.view);
            root.lastWindowGone();
        };
        if (w.shownIn === "notch" && root.windowSignin.closing(w, signed === true, finish))
            return;
        if (w.shownIn === "notch")
            root.windowSignin.closed(w, signed === true);
        finish();
    }
    // The notch cannot show it (any more): a page in the main window, at the address it has reached
    function appSigninToPage(w) {
        const url = String(w.view.url) || w.link, from = w.from, context = w.context;
        if (root.appSignin === w)
            root.appSignin = null;
        // the page first: with no other window, the browser would quit as the sign-in's goes
        openPage(url, from, context, false);
        w.visible = false;
        retire(w.view);
    }
    // The browser's last window went (a sign-in from another app alone, or a private window after the main windows): it
    // quits as Ctrl+Q does, but not while a file of the main profile is still coming, which quitting would cancel. It
    // then runs on with no window until the file lands, fails or is cancelled; `browser` or a link shows the main window,
    // the file in its Downloads group. Asked of the first window.
    function lastWindowGone() {
        if (!quitting && openMains().length === 0 && privateWindows.length === 0 && appSignin === null && !ownDownloads.coming)
            quitAll();
    }
    Connections {
        target: root.primary ? null : ownDownloads
        function onComingChanged() { if (!ownDownloads.coming) root.lastWindowGone() }
    }
    // `browser` with no address asks for a main window: the one that last had the focus; hidden while a sign-in from
    // another app was alone, the first window shows as a start shows it, with the other windows it restores
    // `here` (Super+W): the window is moved to your workspace before it takes the focus; raised where it is, Hyprland
    // would take you to its workspace instead
    function showMain(here) {
        const m = lastMain();
        // a window shown now opens where you are anyway, and Hyprland lists it only once it has mapped
        const shown = m.visible;
        if (!m.visible) {
            reveal(m);
            if (m.restorePage)
                m.takeRestore();
            else
                m.afterClose();
        }
        if (!here || !shown || !Backdrop.bringHere(m))
            m.raise();
    }
    function takeRestore() { failurePage.take() }

    // Alt+Enter in the address: a new page in this thread, right after this one, as a link would open
    function openHere(url, name, fallback, stop) {
        const p = sessionModel.current;
        go(url, "new", p ? p.thread : "", name, p ? p.id : "", false, fallback, stop);
    }

    // A download that starts while the rail is folded says so for 3 s in the docked label (PLAN.md 8d, 5a),
    // its percent kept current; not in page full screen, where downloads wait (8m), nor with the rail out.
    property string noticeDownload: ""
    readonly property string downloadNotice: {
        sessionModel.revision;
        const d = noticeDownload ? sessionModel.downloadById(noticeDownload) : null;
        if (!d || railPinned || peek.out || pageFullScreen)
            return "";
        const p = Downloads.percent(d);
        return "Downloading " + d.file + (p >= 0 ? " · " + p + " %" : "");
    }
    Timer { id: noticeEnd; interval: 3000; onTriggered: root.noticeDownload = "" }
    // folded with the overlay in, the card's notice ("Saved · Edit") says so in the docked label too, as a download does
    readonly property string foldedNotice: cardNotice && cardNotice.where === "card" && !railPinned && !peek.out && !pageFullScreen
                                           ? cardNotice.text + (cardNotice.action ? " · " + cardNotice.action : "") : ""
    function downloadStarted(id) {
        noticeDownload = id;
        noticeEnd.restart();
    }

    // The address card's and the > prefix's actions on the current page; the browser's own pages need none.
    function pageAction(name) {
        if (name === "settings" || name === "keys" || name === "pages") {
            openOwn(name === "pages" ? "pages" : "settings", name === "keys" ? "keys" : "");
            return;
        }
        // the first-run card's import row (PLAN.md 3.4): Welcome, with the browsers found and a password manager's file
        if (name === "import") {
            openWelcome();
            return;
        }
        const p = sessionModel.current;
        if (!p)
            return;
        if (name === "reload")
            views[p.id]?.reload();
        else if (name === "copy")
            copyText(p.url);
        else if (name === "markdown")
            copyText("[" + (p.title || p.url).replace(/([\[\]\\])/g, "\\$1") + "](" + p.url.replace(/\)/g, "%29") + ")");
        else if (name === "always")
            keepInAlways();
        else if (name === "close")
            closePage(p.id);
        else if (name === "print")
            openPrint();
        else if (name === "reader")
            toggleReader();
    }
    TextEdit { id: clipboard; visible: false; textFormat: TextEdit.PlainText }
    function copyText(text) {
        clipboard.text = text;
        clipboard.selectAll();
        clipboard.copy();
    }

    // The page's own right-click menu (PLAN.md 3.20 #8): PageMenu's entries at the pointer, over the page
    RowMenu {
        id: pageMenu
        property var view: null
        parent: root.contentItem
        onClosed: view = null
        onPicked: (action, arg) => root.pageMenuPicked(pageMenu.view, action, arg)
    }
    function openPageMenu(v, request, at) {
        const entries = PageMenu.entries(request, { back: v.canGoBack || sessionModel.backTo(v.pageId) !== "", forward: v.canGoForward }, omniModel.praxisHere && !root.offTheRecord);
        if (entries.length === 0)
            return;
        const p = v.mapToItem(root.contentItem, at.x, at.y);
        pageMenu.view = v;
        pageMenu.entries = entries;
        pageMenu.x = p.x;
        pageMenu.y = p.y;
        pageMenu.open();
    }
    function pageMenuPicked(v, action, arg) {
        if (!v)
            return;
        switch (action) {
        case "back": back(v); break;
        case "forward": v.goForward(); break;
        case "reload": v.reload(); break;
        case "openTask": go(arg, "new", "", omniModel.hostOf(arg), "", false, ""); break;
        case "openHere": openHere(arg, omniModel.hostOf(arg), ""); break;
        case "copyLink": copyText(arg); break;
        case "cut": v.triggerWebAction(WebEngineView.Cut); break;
        case "copy": v.triggerWebAction(WebEngineView.Copy); break;
        case "paste": v.triggerWebAction(WebEngineView.Paste); break;
        case "selectAll": v.triggerWebAction(WebEngineView.SelectAll); break;
        case "saveImage": v.triggerWebAction(WebEngineView.DownloadImageToDisk); break;
        case "copyImage": v.triggerWebAction(WebEngineView.CopyImageToClipboard); break;
        case "spell": v.replaceMisspelledWord(arg); break;
        case "ask": askPraxis("Explain this, from the page on screen:\n\n\u201c" + arg + "\u201d"); break;
        case "inspect": inspectElement(v); break;
        }
    }
    // a private window has no Always (PLAN.md 3.14)
    function keepInAlways() {
        if (sessionModel.current && !root.offTheRecord)
            sessionModel.keepInAlways(sessionModel.currentPage);
    }

    // Pages gone from the lists every main window shares (Remove from Always, in any window): their views here go, and
    // this window, if it showed one, shows its most recent page instead (a hidden one once it shows again).
    function pagesGone(ids) {
        const shown = ids.indexOf(sessionModel.currentPage) >= 0 || ids.some(id => views[id] !== undefined && views[id] === root.currentView);
        if (ids.indexOf(sessionModel.currentPage) >= 0)
            sessionModel.currentPage = sessionModel.mostRecentPage() ?? "";
        dropViews(ids);
        if (shown && root.visible)
            afterClose();
    }
    // `kept`: the pages live on elsewhere (another window, Always), so what they hold back stays
    function dropViews(ids, kept) {
        for (const id of ids)
            if (!kept)
                downloadModel.pageGone(id);
        for (const id of ids)
            if (views[id]) {
                // Ctrl+W on the opener closes both
                if (views[id].popup)
                    closePopup(views[id].popup, false);
                if (views[id] === root.currentView)
                    root.currentView = null;
                if (views[id] === root.behindView)
                    root.behindView = null;
                // its DevTools go with it
                if (views[id].devToolsView)
                    closeDevTools(views[id], views[id].devToolsView);
                retire(views[id]);
                delete views[id];
            }
    }

    // Qt WebEngine 6.11: a view given a page with openIn (window.open, target=_blank, a popup) keeps a
    // pointer into the view that opened it, and the first pointer event after that view is destroyed
    // crashes. So a closed view whose pages are still open is parked, hidden and discarded, until the last
    // of them goes.
    function adopt(child, from) {
        child.openedBy = from;
        from.opened++;
    }
    function retire(v) {
        if (v.opened > 0) {
            v.parked = true;
            v.visible = false;
            v.lifecycleState = WebEngineView.LifecycleState.Discarded;
            return;
        }
        const from = v.openedBy;
        (v.holder ?? v).destroy();
        if (from && --from.opened === 0 && from.parked)
            retire(from);
    }

    // Back: on a page a link opened, with nothing earlier in its own history, the page closes and the one whose link
    // opened it comes back, as in Safari and Arc (the owner, 2026-10-16: Back did nothing there)
    function back(v) {
        const to = sessionModel.backTo(v.pageId);
        if (v.failure)
            v.leave(false);
        else if (v.canGoBack || !to)
            v.goBack();
        else {
            show(to);
            closePage(v.pageId);
        }
    }

    function afterClose() {
        if (sessionModel.currentPage)
            show(sessionModel.currentPage);
        else if (!root.restorePage)
            newBar.show();
    }

    // A live page runs its beforeunload first, and closes once it lets go (a "Leave this page?" ask when
    // it has one and had input); a frozen or unloaded page cannot, and closes at once.
    // Where you stopped on it is asked first, for its closed entry (PLAN.md 3.7).
    function closePage(pageId) {
        const v = views[pageId];
        if (v && !root.shotMode && v.lifecycleState === WebEngineView.LifecycleState.Active && String(v.url) !== "")
            captureStops([[root, v]], () => { if (views[pageId] === v && !v.closing) v.requestClose() });
        else
            finishClose(pageId);
    }
    function finishClose(pageId) {
        dropViews(sessionModel.closePage(pageId));
        afterClose();
        pinnedRail.closed(pageId);
        peekRail.closed(pageId);
    }

    // A new ask: the page being closed shows it, as the close waits on it; an unfocused window asks
    // Hyprland for the urgent hint. Other background pages keep theirs behind ● on their row.
    // In page full screen the ask waits behind a 4 s notice (PLAN.md 8m).
    function asked(pageId, a) {
        if (a.kind === "leave" && views[pageId]?.closing && pageId !== sessionModel.currentPage)
            show(pageId);
        if (root.pageFullScreen && pageId === sessionModel.currentPage)
            notice.show(PageState.askingNotice(a.host), 4000);
        if (!root.active)
            root.alert(0);
    }

    function fileThread(threadId) {
        const t = sessionModel.threadById(threadId), id = sessionModel.currentPage, v = root.currentView;
        // a thread of one just closes (PLAN.md 3.12), as Ctrl+W does: its beforeunload, and where you stopped first
        if (t && !t.earlier && t.pages.length === 1) {
            closePage(t.pages[0]);
            return;
        }
        const kept = t && !t.earlier && t.pages.length > 1 && t.pages.indexOf(id) >= 0 && v !== null && v === views[id] ? v : null;
        const gone = sessionModel.fileThread(threadId);
        if (kept) {
            // the page on screen says where you stopped first (PLAN.md 3.7); its view goes once it has, unless the
            // thread is back by then
            dropViews(gone.filter(x => x !== id));
            root.currentView = null;
            kept.visible = false;
            captureStops([[root, kept]], () => {
                const p = sessionModel.pages[id], back = p ? sessionModel.threadById(p.thread) : null;
                if (views[id] === kept && kept !== root.currentView && (!back || back.earlier))
                    dropViews([id]);
            });
        } else {
            dropViews(gone);
        }
        afterClose();
    }

    // A filed thread comes back among the open threads (PLAN.md 3.7), `pageId` current (else the page it last showed),
    // which loads and goes back where you stopped; its other pages stay unloaded.
    function restoreThread(threadId, pageId) {
        sessionModel.restoreThread(threadId, pageId);
        closeEarlier(false);
        show(sessionModel.currentPage);
    }

    function toggleMute(pageId) {
        const v = views[pageId];
        if (v)
            v.audioMuted = !v.audioMuted;
    }

    // Ctrl+Tab and Ctrl+Shift+Tab: the next or previous page in rail order (as drawn, PLAN.md 3.19), wrapping
    function stepPage(delta) {
        const order = sessionModel.railOrder();
        if (order.length === 0)
            return;
        const at = order.indexOf(sessionModel.currentPage);
        show(order[at < 0 ? (delta > 0 ? 0 : order.length - 1) : (at + delta + order.length) % order.length]);
    }

    // the run record's `alive`, each minute (PLAN.md 8i)
    Timer {
        interval: 60000
        repeat: true
        running: !root.shotMode
        onTriggered: root.writeRun({})
    }
    // The memory net (Lifecycle.js, PLAN.md 3.12): every 10 s while the machine is low on memory, one page of every main
    // and private window's goes unloaded, the one seen longest ago that may, as Unload in Pages and memory does it (asked
    // first). The first window's alone.
    Timer {
        id: memoryNet
        interval: 10000
        repeat: true
        running: !root.shotMode && !root.primary
        onTriggered: root.relieveMemory()
    }
    readonly property alias memoryNetTimer: memoryNet   // for the checks
    property var memoryAsking: ({})     // the pages the net asked, until they answer: a page that never does is passed over
    function relieveMemory() {
        const m = Facts.systemMemory();
        if (!Lifecycle.low(m))
            return;
        const p = Lifecycle.pick(netPages());
        if (!p)
            return;
        root.memoryAsking[p.id] = true;
        p.owner.unloadPage(p.id, () => {
            delete root.memoryAsking[p.id];
            const url = p.url ?? "", host = PageState.hostOf(url) || url.split(":")[0] + ":";
            if (p.owner.views[p.id]?.lifecycleState === WebEngineView.LifecycleState.Discarded)
                console.info("memory low (" + Math.round(m.available / 1048576) + " MB available): unloaded " + host);
        });
    }
    // The pages the net picks from: each view's page, as Lifecycle.unloadable reads it, with the window that has it
    function netPages() {
        const out = [];
        for (const w of hub.mainWindows.concat(hub.privateWindows))
            for (const id in w.views) {
                const v = w.views[id], p = w.windowSession.pages[id];
                // a page with its popup open: the popup hands its answer back to it
                if (p && !v.parked && !v.popup && !root.memoryAsking[id])
                    out.push(Object.assign({}, p, { id: id, owner: w, shown: v === w.currentView, where: p.thread === "" ? "Pinned" : "",
                                                    state: Lifecycle.names[v.lifecycleState], edited: v.editedKept }));
            }
        return out;
    }
    // Where you stopped on a page (PLAN.md 3.7): asked of its view when you leave it, before its thread files and at a
    // quit. Only a live page of this window's lists answers; `done` runs once it has.
    function captureStop(v, done) {
        const id = v && !root.shotMode ? v.pageId ?? "" : "", s = sessionModel;
        if (id === "" || !s.pages[id] || v.parked || v.failure || v.lifecycleState !== WebEngineView.LifecycleState.Active || String(v.url) === "") {
            if (done)
                done();
            return;
        }
        v.captureStop(stop => {
            if (stop !== undefined && s.pages[id])
                s.setStopped(id, stop);
            if (done)
                done();
        });
    }
    // Each [window, view] of `list` answered, or 300 ms went by (a page that is stuck or gone answers nothing): then
    // `done`, once
    function captureStops(list, done) {
        let left = list.length + 1, over = false;
        const one = () => {
            if (!over && --left === 0) {
                over = true;
                done();
            }
        };
        const limit = stopLimit.createObject(root);
        limit.triggered.connect(() => { if (!over) { over = true; done() } limit.destroy() });
        limit.start();
        for (const [w, v] of list)
            w.captureStop(v, one);
        one();
    }
    Component { id: stopLimit; Timer { interval: 300 } }
    function setLifecycle(id, v, state) {
        v.lifecycleState = state;
        sessionModel.update(id, { state: Lifecycle.names[state] });
    }
    // The input listener behind "a text field edited since load" keeps nothing but a flag in the
    // browser's own script world, where the page cannot see or set it.
    function watchEdits() {
        const s = WebEngine.script();
        s.name = "edited";
        s.sourceCode = "addEventListener('input', e => { if (e.isTrusted) { window.__browserEdited = true;"
            + " try { window.top.__browserEdited = true } catch (x) {} } }, true)";
        s.injectionPoint = WebEngineScript.DocumentCreation;
        s.worldId = WebEngineScript.ApplicationWorld;
        s.runsOnSubFrames = true;
        root.profile.userScripts.insert(s);
    }

    // Passwords (PLAN.md 7): the login watch in the browser's script world of each top document (Logins.watcher); a
    // private window's never reports a sent form, so it never offers to save (3.14).
    function watchLogins() {
        const s = WebEngine.script();
        s.name = "logins";
        s.sourceCode = Logins.watcher(!root.offTheRecord);
        s.injectionPoint = WebEngineScript.DocumentCreation;
        s.worldId = WebEngineScript.ApplicationWorld;
        s.runsOnSubFrames = false;
        root.profile.userScripts.insert(s);
    }
    // Back and forward by a sideways touchpad swipe: the sideways steps nothing on the page scrolls by (Swipe.watcher)
    function watchSwipes() {
        const s = WebEngine.script();
        s.name = "swipe";
        s.sourceCode = Swipe.watcher;
        s.injectionPoint = WebEngineScript.DocumentCreation;
        s.worldId = WebEngineScript.ApplicationWorld;
        s.runsOnSubFrames = false;
        root.profile.userScripts.insert(s);
    }
    // Fill: a saved login into the page on screen, from its Fill rows; the keys go back to the page, and a fill that did
    // not happen says why in the card
    function fillLogin(entry) {
        const v = root.currentView;
        if (!v || root.noPage)
            return;
        v.forceActiveFocus();
        v.fillLogin(entry, failure => { if (failure) root.showNotice({ text: Logins.failed("fill", failure), action: "", where: "card" }, 4000) });
    }

    // Inner scroll areas' scrollbars as the shell's: a 4 px pill kept 17 px clear of rounded corners. Mid
    // grey rather than onSurfaceVariant, because pages are light as often as dark. The top document's
    // own scrollbar is hidden, lane and all (Qt WebEngine ignores Chromium's overlay-scrollbar switch):
    // PageScrollBar floats over the card instead. scrollbar-width on the root element is what Chromium
    // applies to the viewport, and while it is set the page's scrollbar-color and ::-webkit-scrollbar
    // rules no longer apply there.
    function styleScrollbars() {
        const css = "::-webkit-scrollbar{width:12px;height:12px;background:transparent}"
            + "::-webkit-scrollbar-track,::-webkit-scrollbar-corner{background:transparent}"
            + "::-webkit-scrollbar-track{margin:17px}"
            + "::-webkit-scrollbar-thumb{background-color:rgba(128,128,128,.5);border-radius:6px;border:4px solid transparent;background-clip:content-box;min-height:40px}"
            + "::-webkit-scrollbar-thumb:hover{background-color:rgba(128,128,128,.75)}";
        const rootCss = "html{scrollbar-width:none!important}html::-webkit-scrollbar{display:none!important}";
        const s = WebEngine.script();
        s.name = "scrollbars";
        // at DocumentCreation the root element may not exist yet
        s.sourceCode = "(() => { const css = " + JSON.stringify(css) + " + (window === window.top ? " + JSON.stringify(rootCss) + " : '');"
            + " const add = () => { const s = document.createElement('style'); s.textContent = css"
            + "; (document.head || document.documentElement).appendChild(s); };"
            + " if (document.documentElement) add(); else new MutationObserver((m, o) => { if (document.documentElement) { o.disconnect(); add(); } })"
            + ".observe(document, { childList: true }); })()";
        s.injectionPoint = WebEngineScript.DocumentCreation;
        s.worldId = WebEngineScript.ApplicationWorld;
        s.runsOnSubFrames = true;
        root.profile.userScripts.insert(s);
    }

    // ? in the cards (PLAN.md 3.20, 4): the question goes to Praxis as a new session, with the task's pages to read
    // first (the notch sheet's hand-off, NotchAddress.praxis). Not from a private window: its pages are its own.
    function askPraxis(question) {
        if (root.offTheRecord)
            return;
        const c = notchAddress.praxis();
        if (!Engine.askPraxis((c ? c.text + "\n\n" : "") + question))
            showNotice({ text: "Praxis could not be started", action: "", where: "card" }, 4000);
    }
    // with no page the new-page card is the page, and it takes the keys instead; the edit takes find's place
    function editAddress(text) {
        findModel.hide();
        siteInfo.hide();
        printCard.hide();
        if (root.noPage)
            newBar.show(text);
        else
            addressEditor.open(text);
    }

    // Find (PLAN.md 3.8 8e) on the page on screen, `text` typed (the / prefix), else the words it kept, all
    // selected. Not on the browser's own failure page, under the page's dialog or in page full screen,
    // where nothing else comes out either. Folded, in the overlay it holds out.
    function openFind(text) {
        const v = root.currentView;
        if (root.noPage || !v || v.failure || v.dialog || root.pageFullScreen || root.ownKind !== "")
            return false;
        // first, so the bar handing the keys back to the page does not close find
        if (newBar.opened)
            newBar.hide();
        printCard.hide();
        findModel.show(v, text, root.railPinned ? "rail" : "peek");
        // after find is out, so folded the overlay stays and the edit goes back into its slot
        siteInfo.hide();
        addressEditor.close();
        (root.railPinned ? pinnedRail : peekRail).findCard.focusInput(text === undefined);
        return true;
    }
    // A click on an "Also in this task" row: that page, find open on it at its first match.
    function findOn(pageId) {
        findModel.jumping = true;
        show(pageId);
        if (!openFind(findModel.text))
            findModel.hide();
        findModel.jumping = false;
    }
    // find is on the page on screen: another page there ends it; so does it the site panel. DevTools follow the page
    // (layDevTools).
    onCurrentViewChanged: {
        Qt.callLater(root.layDevTools);
        if (findModel.open && !findModel.jumping && findModel.view !== currentView)
            findModel.hide();
        siteInfo.hide();
        printCard.hide();
    }

    // The site panel (PLAN.md 3.9) for the page on screen, where the address card is (folded, in the overlay it
    // holds out); not on the browser's own failure page, under the page's dialog, in page full screen, nor for a
    // page without a host (data:, about:, file:), which has no site. `row`: a row whose choices come out at once.
    function openSite(row) {
        const v = root.currentView;
        if (root.noPage || !v || v.failure || v.dialog || root.pageFullScreen || PageState.hostOf(String(v.url)) === "" || root.ownKind !== "")
            return false;
        if (newBar.opened)
            newBar.hide();
        printCard.hide();
        siteInfo.show(root.railPinned ? "rail" : "peek", row);
        // after the panel is out, so folded the overlay stays and the edit goes back into its slot
        findModel.hide();
        addressEditor.close();
        (root.railPinned ? pinnedRail : peekRail).sitePanel.focusPanel();
        return true;
    }
    // A press anywhere but on the site panel closes it; folded, a press on the page, off the overlay, closes find
    // too (pinned, the page taking the keys from find's field does), and Earlier (PLAN.md 3.5). Passive, so the press
    // still reaches what is under it.
    Item {
        anchors.fill: parent
        z: 100
        enabled: siteInfo.open || findModel.open && findModel.where === "peek" || earlierState.view !== "" && !root.railPinned
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: {
                if (!active)
                    return;
                const p = point.scenePressPosition;
                if (siteInfo.open && !root.within(siteInfo.where === "rail" ? pinnedRail.sitePanel : peekRail.sitePanel, p))
                    siteInfo.hide();
                if (findModel.open && findModel.where === "peek" && !root.within(peekRail, p))
                    findModel.hide();
                // not on a menu from the overlay, which keeps it out
                if (earlierState.view !== "" && !root.railPinned && !root.within(peekRail, p) && !peekRail.busy)
                    root.closeEarlier(false);
            }
        }
    }
    function within(item, p) {
        const q = item.mapFromItem(null, p.x, p.y);
        return q.x >= 0 && q.y >= 0 && q.x < item.width && q.y < item.height;
    }
    // Clear site data (PLAN.md 3.9): the site's pages unload at once, the page on screen off the screen first
    // (a visible view is not discarded), and load again when opened after the clear or its undo.
    function unloadSite(origin) {
        for (const id in views) {
            const v = views[id];
            if (v.parked || Asks.originOf(String(v.url)) !== origin)
                continue;
            v.visible = false;
            setLifecycle(id, v, WebEngineView.LifecycleState.Discarded);
        }
    }
    function siteCleared(origin) {
        if (root.currentView && sessionModel.currentPage && Asks.originOf(String(root.currentView.url)) === origin)
            show(sessionModel.currentPage, siteInfo.open);
    }
    // A hidden page of the origin, loaded from a string with the origin as its base URL (no request leaves for
    // it), clears the origin's storage with Site.clearScript; the clear ends after 5 s whatever it says.
    Loader {
        id: clearer
        property string origin: ""
        active: origin !== "" && root.profile !== null
        sourceComponent: WebEngineView {
            visible: false
            width: 800
            height: 600
            profile: root.profile
            Component.onCompleted: loadHtml("<!doctype html><title>clearing</title>", clearer.origin + "/")
            onLoadingChanged: request => { if (request.status === WebEngineView.LoadSucceededStatus) runJavaScript(Site.clearScript) }
            onTitleChanged: if (title === "cleared" || title.startsWith("failed")) clearer.done()
        }
        function done() {
            clearLimit.stop();
            origin = "";
            siteInfo.storageCleared();
        }
        onActiveChanged: if (active) clearLimit.restart()
    }
    Timer { id: clearLimit; interval: 5000; onTriggered: clearer.done() }

    // R keys (KeyMap.js): the page never sees them. Not while the current page's popup has the keys: its
    // window counts as this one's (see popupComponent).
    readonly property bool popupKeys: currentView !== null && currentView.popup !== null && currentView.popup.hasKeys === true
    Instantiator {
        model: KeyMap.reserved
        delegate: Shortcut {
            required property var modelData
            enabled: !root.popupKeys
            sequences: modelData.seqs
            onActivated: root.act(modelData.action, modelData.arg)
        }
    }
    // P keys: only those the page left unhandled arrive here; so do F keys (`/`), which a field would have taken
    function pageKey(event) {
        const k = KeyMap.pageKey(event.key, event.modifiers) ?? KeyMap.typedKey(event.text, event.modifiers);
        // "/ opens find" Off in the site panel: `/` stays the site's
        const kept = k !== null && k.text === "/" && root.currentView !== null
            && siteModel.choice(Asks.originOf(String(root.currentView.url)), "slash") === "off";
        event.accepted = k !== null && !kept && root.act(k.action, k.arg);
    }

    // What a key does; false when it has nothing to act on, so the key goes on.
    function act(action, arg) {
        const p = sessionModel.current;
        const v = p ? views[p.id] ?? null : null;
        const order = sessionModel.railOrder();
        switch (action) {
        case "newPage": newPageKey(); return true;
        case "newWindow": {
            // every main window closed while a private one stays: the one set aside comes back (setAside)
            if (openMains().length === 0) {
                showMain();
                return true;
            }
            const w = hub.newWindow(windowState(), "");
            w.afterClose();
            w.requestActivate();
            return true;
        }
        case "privateWindow": { const w = hub.newPrivateWindow(windowState()); w.afterClose(); w.requestActivate(); return true; }
        case "closePage": if (p) closePage(p.id); return !!p;
        case "fileThread": if (p && p.thread) fileThread(p.thread); return !!p;
        case "reopen": {
            const w = sessionModel.takeWindow();
            if (w) {
                hub.reopenWindow(w);
                return true;
            }
            const id = sessionModel.reopenClosed();
            if (id)
                show(id);
            return true;
        }
        case "nextPage": stepPage(1); return true;
        case "previousPage": stepPage(-1); return true;
        case "pageN": if (order[arg - 1]) show(order[arg - 1]); return true;
        case "lastPage": if (order.length > 0) show(order[order.length - 1]); return true;
        case "address": addressKey(); return true;
        case "focusCycle": focusCycle(); return true;
        case "quit": hub.quitAll(); return true;
        case "fullScreen": toggleFullScreen(); return true;
        case "back": if (v) back(v); return !!v;
        case "forward": if (v) v.goForward(); return !!v;
        case "reload": if (v) v.failure ? v.retry() : v.reload(); return !!v;
        case "hardReload": if (v) v.reloadAndBypassCache(); return !!v;
        // Esc: a load stops; else Earlier goes back to the rail's own list (PLAN.md 3.7)
        case "stop":
            if (v && v.loading) {
                v.stop();
                return true;
            }
            if (earlierState.view !== "") {
                closeEarlier(true);
                return true;
            }
            return false;
        case "nextThread":
        case "previousThread": {
            const t = sessionModel.nearThread(action === "nextThread" ? 1 : -1);
            if (t)
                show(sessionModel.mostRecentPage(t.id));
            return true;
        }
        case "movePageUp": if (p) sessionModel.shiftPage(p.id, -1); return !!p;
        case "movePageDown": if (p) sessionModel.shiftPage(p.id, 1); return !!p;
        case "jump": newBar.show("@"); return true;
        case "fold": root.railPinned = !root.railPinned; return true;
        case "keepInAlways": keepInAlways(); return !!p && !root.offTheRecord;
        case "save": return saveCurrent();
        case "earlier": return openEarlier(arg);
        case "mute": if (p) toggleMute(p.id); return !!v;
        case "viewSource": if (p) go("view-source:" + p.url, "new", p.thread, "Source of " + omniModel.hostOf(p.url), p.id, false); return !!p;
        case "devtools": return toggleDevTools();
        case "alwaysN": { const id = sessionModel.always[arg - 1]; if (id) show(id); return true; }
        case "find": return openFind();
        case "site": if (siteInfo.open) { siteInfo.dismiss(); return true; } return openSite("");
        case "zoomIn": if (v && ownKind === "") siteInfo.stepZoom(1); return !!v && ownKind === "";
        case "zoomOut": if (v && ownKind === "") siteInfo.stepZoom(-1); return !!v && ownKind === "";
        // back to Settings' default zoom
        case "zoomReset": if (v && ownKind === "") siteInfo.setZoom(siteModel.defaultZoom); return !!v && ownKind === "";
        case "print": return openPrint();
        case "reader": return toggleReader();
        // the browser's own pages (PLAN.md 3.15, 3.17): Ctrl+, Ctrl+/ Ctrl+Shift+Delete and Shift+Esc
        case "settings": openOwn("settings", arg ?? ""); return true;
        case "pages": openOwn("pages", ""); return true;
        }
        return false;
    }
    // Settings and Pages and memory are a thread of one each (PLAN.md 3.17): the open one is shown, in whichever window
    // has it, else a new one opens here. `section`: where Settings opens ("keys", "clear"), "" where it was. Returns the
    // window that shows it.
    function openOwn(kind, section) {
        const own = new RegExp("^browser://" + kind + "([/?#]|$)", "i");
        // the threads are every main window's (a private window's are its own)
        let id = "";
        for (const t of sessionModel.threads)
            if (!t.earlier && !id)
                id = t.pages.find(pid => sessionModel.pages[pid] && own.test(sessionModel.pages[pid].url)) ?? "";
        if (id)
            show(id);
        else
            go("browser://" + kind, "new", "", kind === "pages" ? "Pages and memory" : "Settings");
        const owner = id ? ownerOf(id) ?? root : root;
        if (kind === "settings")
            Qt.callLater(() => owner.ownSection(section));
        return owner;
    }
    function ownSection(section) { settingsPage.show(section) }
    // Settings' way back (the rail face's slab, Esc): the page under it comes back, and Settings, a thread of one, closes
    function leaveSettings() {
        const id = sessionModel.currentPage;
        const back = root.behindView ? Object.keys(views).find(k => views[k] === root.behindView) ?? "" : "";
        if (back)
            show(back);
        closePage(id);
    }

    // Import from Zen (PLAN.md 3.4, 3.15), the first window's: Zen's bookmarks into Saved and its history into History once
    // they are read, then its passwords, which src/zen.* hands to the keyring itself. What it brought stays in
    // settings.json (zenImport; zenFailure until one succeeds) for Settings > Import. `zenRun`: this import's counts
    // until its passwords are done.
    property var zenRun: null
    function importZen() {
        // the two choices in Settings > Import (on until switched off); the cookies go into this window's own profile
        if (Zen.start({ cookies: root.prefs.get("zenCookies"), tabs: root.prefs.get("zenTabs") }, root.profile))
            zenRun = { at: Date.now() };
    }
    // A password manager's file (PasswordFile, book4-edge/thyris-migration-plan.md) through Welcome, in this window: where
    // each service keeps its export, Files to choose it, its logins counting into the keyring, then what came, what was
    // left out and why, and the file deleted if you say so. No password reaches QML: PasswordFile hands them over itself.
    property bool filePicking: false
    readonly property alias welcome: welcomePage     // for the checks
    property var fileRun: null          // { service, skipped } between the file read and its logins saved
    function openPasswordFile() {
        Object.assign(welcomePage, { mode: "file", notice: "", fileFrom: "", result: null, kinds: [], chosen: 0,
                                     sources: [{ name: "A password manager's file", kind: "file", glyph: "upload_file" }] });
        welcomePage.phase = PasswordFile.state === "saving" ? "bringing" : "arrive";
        Qt.callLater(() => welcomePage.forceActiveFocus());
    }
    function closeWelcome() {
        welcomePage.phase = "";
        welcomePage.mode = "";
        if (root.currentView)
            root.currentView.forceActiveFocus();
    }
    Connections {
        target: welcomePage
        function onPicked(action) {
            if (action === "file") {
                welcomePage.notice = "";
                if (Picker.pick("A password manager's export (.csv) · select it, then Choose"))
                    root.filePicking = true;
            } else if (action === "delete") {
                const removed = PasswordFile.removeFile();
                root.closeWelcome();
                root.showNotice({ text: removed ? "The file is deleted." : "Thyris couldn't delete the file. Delete it in Files.", action: "", where: "card" }, 5000);
            } else if (action === "bring") {
                if (!root.bringOver(welcomePage.source))
                    welcomePage.notice = "Thyris couldn't start bringing it over. Try again in a moment.";
            } else if (action === "default") {
                Apps.makeDefault();
                root.closeWelcome();
            } else if (action.startsWith("open:")) {
                root.closeWelcome();
                if (action === "open:Saved" || action === "open:History")
                    root.openEarlier(action === "open:Saved" ? "saved" : "history");
                else
                    root.openOwn("settings", action === "open:Passwords" ? "passwords" : "import");
            } else if (action !== "show") {
                // close, keep, later, fresh: nothing held stays in memory
                if (PasswordFile.state === "read")
                    PasswordFile.forget();
                root.closeWelcome();
            }
        }
    }
    Connections {
        target: root.filePicking ? Picker : null
        function onFinished(paths) {
            root.filePicking = false;
            if (paths.length === 0)
                return;
            const read = PasswordFile.read(paths[0]);
            if (read.failure !== "") {
                welcomePage.notice = "That file didn't work. " + read.failure;
                return;
            }
            root.fileRun = { service: read.service, skipped: read.skipped };
            welcomePage.fileFrom = read.service;
            welcomePage.kinds = [{ label: "Passwords", done: 0, total: read.logins }];
            welcomePage.phase = "bringing";
            if (!PasswordFile.bring()) {
                root.fileRun = null;
                welcomePage.phase = "arrive";
                welcomePage.notice = "Thyris couldn't reach your keyring, so nothing was brought over.";
            }
        }
    }
    Connections {
        target: root.fileRun ? PasswordFile : null
        function onProgress(done, total) {
            welcomePage.kinds = [{ label: "Passwords", done: done, total: total }];
        }
        function onSaved(result) {
            const run = root.fileRun, stayed = run.skipped.slice();
            root.fileRun = null;
            if (result.left > 0)
                stayed.unshift({ what: result.left === 1 ? "1 login" : result.left + " logins",
                                 why: result.failure === "none" ? "no keyring answered"
                                    : result.failure === "unencrypted" ? "your keyring has no password, so they'd be kept as plain text"
                                    : "the keyring refused them" });
            welcomePage.result = { file: true, from: run.service || "the file", added: result.added, kept: result.kept, stayed: stayed };
            welcomePage.phase = "done";
        }
    }

    // Bringing another browser over (book4-edge/thyris-migration-plan.md) through Welcome, in this window: the Chrome family's
    // profiles (ChromeImport) and the Firefox family's (Zen), most recently used first, then a password manager's file. The
    // one chosen counts its kinds into Saved, History, the cookie store and the keyring, and done says where each went. The
    // first start opens it once when a browser is found; the new page bar's import row and Settings > Import open it again.
    property var browserRun: null       // { kind, from, browser, want, cookies, passwords, bookmarks, history, stayed } while it runs
    property bool welcomeWhenFound: false
    function welcomeSources() {
        const out = [], chrome = ChromeImport.found;
        for (let i = 0; i < chrome.length; i++) {
            const p = chrome[i], several = chrome.filter(q => q.browser === p.browser).length > 1;
            out.push({ name: p.browser, profile: several ? p.name : "", email: p.email, kind: "chromium", icon: p.icon, glyph: p.icon ? "" : "public",
                       index: i, counts: p.counts, chips: [["passwords", "Passwords"], ["bookmarks", "Bookmarks"], ["history", "History"], ["sites", "Sign-ins"], ["tabs", "Tabs"]] });
        }
        for (let i = 0; i < Zen.browsers.length; i++) {
            const b = Zen.browsers[i], n = k => Math.max(0, b.counts[k] ?? 0);
            out.push({ name: b.browser, kind: "firefox", icon: b.icon, glyph: b.icon ? "" : "public", index: i,
                       counts: { passwords: n("passwords"), bookmarks: n("bookmarks"), tabs: n("tabs"), sites: n("sites") },
                       chips: [["bookmarks", "Bookmarks"], ["history", "History"], ["sites", "Sign-ins"], ["tabs", "Tabs"]] });
        }
        out.push({ name: "A password manager's file", kind: "file", glyph: "upload_file" });
        return out;
    }
    function openWelcome() {
        root.prefs.set("welcomed", true);
        ChromeImport.scan();
        Zen.scan();
        Object.assign(welcomePage, { mode: "", notice: "", fileFrom: "", result: null, chosen: 0, sources: welcomeSources() });
        welcomePage.phase = root.browserRun ? "bringing" : "arrive";
        // after what opened it (the new page bar gives the keys back to the page as it goes)
        Qt.callLater(() => welcomePage.forceActiveFocus());
    }
    // the scans answer after the page shows: the rows follow, the choice and its switches kept on the same source
    function refreshSources() {
        if (welcomePage.phase !== "arrive" || welcomePage.mode !== "")
            return;
        const was = welcomePage.source, list = welcomeSources();
        const at = was ? list.findIndex(x => x.kind === was.kind && x.name === was.name && (x.profile ?? "") === (was.profile ?? "")) : -1;
        if (at >= 0 && was.bring)
            list[at].bring = was.bring;
        welcomePage.sources = list;
        welcomePage.chosen = Math.max(0, at);
    }
    function welcomeIfFound() {
        if (root.welcomeWhenFound && (ChromeImport.found.length > 0 || Zen.browsers.length > 0)) {
            root.welcomeWhenFound = false;
            root.openWelcome();
        }
    }
    Connections {
        target: ChromeImport
        function onFoundChanged() { root.refreshSources(); root.welcomeIfFound() }
    }
    Connections {
        target: Zen
        function onScanned() { root.refreshSources(); root.welcomeIfFound() }
    }
    function setKind(key, fields) {
        welcomePage.kinds = welcomePage.kinds.map(k => k.key === key ? Object.assign({}, k, fields) : k);
    }
    // the chosen browser's things, the kinds it holds and you left on
    function bringOver(src) {
        const want = src.bring ?? {}, on = k => want[k] !== false, c = src.counts ?? {}, kinds = [];
        const add = (key, label, total, fields) => kinds.push(Object.assign({ key: key, label: label, done: 0, total: Math.max(0, total || 0) }, fields));
        const browser = src.name.replace(/^Google /, "");
        if (src.kind === "chromium") {
            if (on("passwords") && c.passwords > 0) add("passwords", "Passwords", c.passwords);
            if (on("bookmarks") && c.bookmarks > 0) add("bookmarks", "Bookmarks", c.bookmarks);
            if (on("history") && c.history > 0) add("history", "History", c.history);
            if (on("sites") && c.sites > 0) add("sites", "Signed-in sites", c.sites);
            if (on("tabs") && c.tabs > 0) add("tabs", "Open tabs", c.tabs);
            if (!ChromeImport.start(src.index, { passwords: on("passwords"), bookmarks: on("bookmarks"), history: on("history"), sites: on("sites"),
                                                 tabs: on("tabs") }, root.profile))
                return false;
        } else {
            Zen.choose(src.index);
            if (on("bookmarks") && c.bookmarks > 0) add("bookmarks", "Bookmarks", c.bookmarks);
            if (on("history")) add("history", "History", 0, { waiting: "Reading…" });
            if (on("sites") && c.sites > 0) add("sites", "Signed-in sites", c.sites);
            if (on("tabs") && c.tabs > 0) add("tabs", "Open tabs", c.tabs);
            if (c.passwords > 0) add("passwords", "Passwords", c.passwords);
            if (!Zen.start({ cookies: on("sites"), tabs: on("tabs") }, root.profile))
                return false;
            root.hub.zenRun = { at: Date.now(), want: { bookmarks: on("bookmarks"), history: on("history") } };
        }
        root.browserRun = { kind: src.kind, browser: browser, from: browser + (src.profile ? " · " + src.profile : ""), want: want, stayed: [] };
        welcomePage.kinds = kinds;
        welcomePage.phase = "bringing";
        return true;
    }
    Connections {
        target: root.browserRun && root.browserRun.kind === "chromium" ? ChromeImport : null
        function onRead(found) {
            const run = root.browserRun;
            if (run.want.bookmarks !== false)
                run.bookmarks = root.hub.savedModel.importPages(found.bookmarks, run.browser);
            if (run.want.history !== false)
                run.history = root.hub.historyModel.importEntries(found.history);
            if (run.want.tabs !== false && found.tabs.length > 0)
                run.tabs = root.openTabs(found.tabs, run.browser);
            root.setKind("bookmarks", { done: found.bookmarks.length, total: found.bookmarks.length });
            root.setKind("history", { done: found.history.length, total: found.history.length });
            root.setKind("tabs", { done: found.tabs.length, total: found.tabs.length });
        }
        function onStateChanged() { root.setKind("passwords", { waiting: ChromeImport.state === "keyring" ? "keyring" : "" }) }
        function onProgress(done, total) { root.setKind("passwords", { done: done, total: total, waiting: "" }) }
        function onCookiesDone(result) {
            root.browserRun.cookies = result;
            root.setKind("sites", { done: result.sites ?? 0, total: result.sites ?? 0 });
            if (result.left > 0)
                root.browserRun.stayed.push({ what: result.left === 1 ? "1 sign-in" : result.left + " sign-ins", why: "sealed with a key your keyring didn't give" });
        }
        function onSaved(result) {
            const run = root.browserRun;
            run.passwords = result;
            root.setKind("passwords", { done: result.added + result.kept, total: result.total, waiting: "" });
            if (result.left > 0 && result.failure === "no key")
                run.stayed.push({ what: result.left === 1 ? "1 password" : result.left + " passwords", why: run.browser + "'s key isn't in your keyring" });
            else if (result.left > 0)
                run.stayed.push({ what: result.left === 1 ? "1 password" : result.left + " passwords",
                                  why: result.failure === "unencrypted" ? "your keyring has no password, so they'd be kept as plain text" : "the keyring refused them" });
            root.finishBrowser();
        }
    }
    Connections {
        target: root.browserRun && root.browserRun.kind === "firefox" ? Zen : null
        function onRead(found) {
            root.setKind("bookmarks", { done: (found.bookmarks ?? []).length, total: (found.bookmarks ?? []).length });
            root.setKind("history", { done: (found.history ?? []).length, total: (found.history ?? []).length, waiting: "" });
            if (found.tabs)
                root.setKind("tabs", { done: found.tabs.length, total: found.tabs.length });
        }
        function onCookiesDone(result) {
            root.browserRun.cookies = result;
            root.setKind("sites", { done: result.sites ?? 0, total: result.sites ?? 0 });
        }
        function onStateChanged() {
            if (Zen.state === "password")
                root.setKind("passwords", { waiting: Zen.browser + "'s main password: enter it in Settings › Import" });
        }
        // the first window's own handler files what came (zenImport) first
        function onSaved(result) { Qt.callLater(root.finishBrowser) }
    }
    function finishBrowser() {
        const run = root.browserRun;
        if (!run)
            return;
        root.browserRun = null;
        const figures = [], fig = (v, label, place) => { if (v > 0) figures.push({ value: v, label: label, place: place }) };
        let tabs = 0;
        if (run.kind === "chromium") {
            fig(run.passwords ? run.passwords.added : 0, "passwords", "Passwords");
            fig(run.bookmarks ? run.bookmarks.added : 0, "bookmarks", "Saved");
            fig(run.history ? run.history.added : 0, "pages of history", "History");
            tabs = run.tabs ? run.tabs.added : 0;
            fig(tabs, "open tabs", "the rail");
        } else {
            const z = root.prefs.get("zenImport") ?? {};
            fig(z.passwords ? z.passwords.added : 0, "passwords", "Passwords");
            fig(z.bookmarks ? z.bookmarks.added : 0, "bookmarks", "Saved");
            fig(z.history ? z.history.added : 0, "pages of history", "History");
            tabs = z.tabs ? z.tabs.added ?? 0 : 0;
            fig(tabs, "open tabs", "the rail");
        }
        const c = run.cookies ?? {};
        welcomePage.result = { from: run.from, sitesCame: (c.added ?? 0) + (c.kept ?? 0) > 0 ? (c.sites ?? 0) : 0, google: c.google === true,
                               tabsCame: tabs, figures: figures, stayed: run.stayed };
        welcomePage.phase = "done";
        root.prefs.set("broughtOver", Date.now());
    }

    // A browser's open tabs as pages (unloaded, so none loads) in a thread of their own, "From Zen" (with Zen's workspace or
    // Chrome's tab group, "From Chrome: Kernel"); a page already open at that address before the import is left (a second
    // import adds nothing), a tab the browser has twice is two pages. Not shown: the page on screen stays.
    function openTabs(tabs, browser) {
        const have = new Set(Object.values(sessionModel.pages).map(p => p.url)), threads = {};
        let added = 0, kept = 0;
        for (const t of tabs) {
            if (have.has(t.url)) {
                kept++;
                continue;
            }
            const from = "From " + browser, group = t.space || t.group;
            const name = group ? from + ": " + group : from;
            threads[name] = threads[name] ?? sessionModel.newThread(name);
            const id = sessionModel.addPage(threads[name], t.url);
            if (t.title)
                sessionModel.update(id, { title: t.title });
            added++;
        }
        return { added: added, kept: kept };
    }
    Connections {
        target: root.primary ? null : Zen
        function onRead(found) {
            if (found.failure) {
                root.prefs.set("zenFailure", { at: Date.now(), text: found.failure });
                root.zenRun = null;
                return;
            }
            const want = (root.zenRun ?? {}).want ?? {};      // Welcome's switches (both on from Settings)
            const run = { bookmarks: want.bookmarks === false ? { added: 0, kept: 0 } : root.savedModel.importPages(found.bookmarks, Zen.browser || "Zen"),
                          history: want.history === false ? { added: 0, kept: 0 } : root.historyModel.importEntries(found.history) };
            if (found.tabs)
                run.tabs = found.tabsFailed ? { failed: true } : root.openTabs(found.tabs, Zen.browser || "Zen");
            root.zenRun = Object.assign({}, root.zenRun, run);
        }
        function onCookiesDone(result) {
            root.zenRun = Object.assign({}, root.zenRun, { cookies: result });
        }
        function onSaved(result) {
            root.prefs.set("zenImport", Object.assign({}, root.zenRun, { passwords: result }));
            root.prefs.set("zenFailure", null);
            root.zenRun = null;
        }
    }

    // Print (PLAN.md 3.16) the page on screen: not the browser's own pages or failure pages, nor under the page's dialog
    // or in page full screen, where nothing else comes out either. What was called up over the page gives way.
    function openPrint() {
        const v = root.currentView, p = sessionModel.current;
        if (root.noPage || !v || !p || v.failure || v.dialog || root.pageFullScreen || root.ownKind !== "")
            return false;
        if (printCard.opened)
            return true;
        if (newBar.opened)
            newBar.hide();
        findModel.hide();
        siteInfo.hide();
        addressEditor.close();
        printCard.show(v, p.id, v.pageTitle || p.title || "", PageState.pageHost(String(v.url)));
        return true;
    }
    // A printed page's PDF, saved: a finished download of its page, listed under it as downloads are, with the page as
    // its origin on the file (none in a private window, PLAN.md 3.14)
    function printSaved(pageId, path) {
        const p = sessionModel.pages[pageId] ?? null, t = p && p.thread ? sessionModel.threadById(p.thread) : null;
        const bytes = Printing.size(path), now = Date.now();
        sessionModel.addDownload({ page: p ? pageId : "", url: p ? p.url : "", file: path.split("/").pop(), path: path, total: bytes, received: bytes,
                                   state: "done", started: now, finished: now,
                                   from: p ? { title: p.title || RailRows.untitled(p.url), icon: p.icon || "", always: p.thread === "", url: p.url, thread: t ? t.title : "" } : null });
        if (!root.offTheRecord && p)
            Disk.mark(path, { "user.xdg.origin.url": p.url, "user.browser.thread": t ? t.title : "" });
    }
    // Reader view (PLAN.md 3.9; Ctrl+Alt+R, > Reader view, the site panel's row): page `v`'s article (the page on screen's
    // when none is given) in the page's place, or the page back. With no article, "No article here" in the card for 3 s,
    // as "Saved · Edit" says what Ctrl+D did.
    function toggleReader(v) {
        const view = v ?? root.currentView, onScreen = view === root.currentView;
        if (!view || view.failure || view.dialog || onScreen && (root.noPage || root.pageFullScreen || root.ownKind !== ""))
            return false;
        if (onScreen)
            printCard.hide();
        if (root.shotMode || !view.toggleReader)
            return true;
        view.toggleReader(readerTheme(), state => {
            if (state === "none" && view === root.currentView)
                root.showNotice({ text: "No article here", action: "", where: "card" }, 3000);
        });
        return true;
    }
    // the article's page in the browser's own colours and faces (Reader.js)
    function readerTheme() {
        return { ground: Theme.terminal, ink: Theme.colOnSurface, subtext: Theme.colSubtext, hairline: Theme.transparentize(Theme.outlineVariant, 0.7),
                 wash: Theme.transparentize(Theme.onSurface, 0.95), selection: Theme.transparentize(Theme.primary, 0.6),
                 font: Theme.font.main, title: Theme.font.titleFamily, mono: Theme.font.monospace };
    }
    // Pages and memory's pages (PLAN.md 3.17): every main window's, or a private window's own, with the sign-in
    // windows' pages, each with its state, its process and what holds it live (Processes.js)
    function memoryPages() {
        const out = [], seen = new Set();
        const add = (w, id, v, p, where) => {
            const shown = !!v && w.visible && v === w.currentView;
            out.push(Object.assign({}, p, { id: id, title: p.title || RailRows.untitled(p.url ?? ""), where: where, shown: shown,
                                            state: v ? Lifecycle.names[v.lifecycleState] ?? "live" : "unloaded",
                                            pid: v && v.lifecycleState !== WebEngineView.LifecycleState.Discarded ? v.renderProcessPid : 0,
                                            edited: !!v && v.editedKept }));
            if (v && v.popup)
                out.push({ id: id + ":popup", title: v.popup.view.pageTitle || RailRows.untitled(String(v.popup.view.url)), url: String(v.popup.view.url),
                           icon: String(v.popup.view.icon), where: "popup", shown: false, state: "live", pid: v.popup.view.renderProcessPid });
        };
        for (const w of root.offTheRecord ? [root] : hub.mainWindows) {
            const ws = w.windowSession;
            for (const t of ws.openThreads())
                for (const id of t.pages)
                    if (ws.pages[id] && !seen.has(id)) {
                        seen.add(id);
                        add(w, id, w.views[id] ?? null, ws.pages[id], "");
                    }
        }
        // Always cells are every window's: the view of the window that has one loaded
        for (const id of root.offTheRecord ? [] : sessionModel.always) {
            const p = sessionModel.pages[id];
            if (!p)
                continue;
            const w = hub.mainWindows.find(m => m.views[id] && m.views[id].lifecycleState !== WebEngineView.LifecycleState.Discarded)
                   ?? hub.mainWindows.find(m => m.views[id]) ?? root;
            add(w, id, w.views[id] ?? null, p, "Pinned");
        }
        return out;
    }
    // Unload in Pages and memory, and the memory net's (relieveMemory): in the window that has the page; not the page on
    // screen. A live page is asked first: where you stopped, and whether a field was edited, which keeps it live and says
    // so in its row (`editedKept`). `done` runs once it is decided.
    function unloadPage(id, done) {
        const w = ownerOf(id) ?? root, v = w.views[id];
        const over = () => { if (done) done() };
        if (!v || v === w.currentView || v.lifecycleState === WebEngineView.LifecycleState.Discarded) {
            over();
            return;
        }
        const unload = () => {
            v.visible = false;
            w.setLifecycle(id, v, WebEngineView.LifecycleState.Discarded);
            over();
        };
        if (v.lifecycleState !== WebEngineView.LifecycleState.Active || root.shotMode) {
            unload();
            return;
        }
        const at = String(v.url);
        v.runJavaScript("JSON.stringify({ edited: !!window.__browserEdited, stop: " + Recall.capture + " })", WebEngineScript.ApplicationWorld, answer => {
            let a = null;
            try {
                a = JSON.parse(answer);
            } catch (e) {}
            if (w.views[id] !== v) {
                over();
                return;
            }
            const stop = a && !v.failure ? Recall.stop(a.stop, at, Date.now()) : undefined;
            if (stop !== undefined)
                w.windowSession.setStopped(id, stop);
            if (a && a.edited) {
                v.editedKept = true;
                over();
            } else if (v !== w.currentView && v.lifecycleState !== WebEngineView.LifecycleState.Discarded) {
                unload();
            } else {
                over();
            }
        });
    }
    // Page full screen (PLAN.md 8m): the window goes full screen with the page and the rail is hidden;
    // nothing else comes out (an ask waits behind a notice), and Esc leaves. F11 is the browser's own full
    // screen: it folds the rail, and leaving it restores the fold you had.
    readonly property bool pageFullScreen: currentView !== null && !noPage && currentView.isFullScreen
    property bool browserFullScreen: false
    property bool pinnedBeforeFullScreen: true
    readonly property bool fullWindow: pageFullScreen || browserFullScreen
    onFullWindowChanged: if (!shotMode) root.visibility = fullWindow ? Window.FullScreen : lastVisibility
    onPageFullScreenChanged: {
        if (pageFullScreen) {
            peek.open = false;
            printCard.hide();
            notice.show(PageState.fullScreenNotice, 2000);
        } else {
            notice.hide();
        }
    }
    function toggleFullScreen() {
        if (pageFullScreen) {
            currentView.fullScreenCancelled();
        } else if (!browserFullScreen) {
            pinnedBeforeFullScreen = railPinned;
            browserFullScreen = true;
            railPinned = false;
        } else {
            browserFullScreen = false;
            railPinned = pinnedBeforeFullScreen;
        }
    }
    // Esc leaves page full screen first, whatever has the keys (an R key while it lasts): not while you
    // edit the address or type in the bar, nor with the page's dialog open, where Esc is Cancel.
    Shortcut {
        sequences: ["Esc"]
        enabled: root.pageFullScreen && !addressEditor.editing && !newBar.opened && !root.currentView.dialog && !root.popupKeys
        onActivated: root.currentView.fullScreenCancelled()
    }
    property int lastVisibility: Window.Windowed
    onVisibilityChanged: {
        if (root.visibility === Window.FullScreen || root.visibility === Window.Hidden)
            return;
        lastVisibility = root.visibility;
        // the compositor took full screen away: the page and the browser leave it too
        if (pageFullScreen)
            currentView.fullScreenCancelled();
        if (browserFullScreen) {
            browserFullScreen = false;
            railPinned = pinnedBeforeFullScreen;
        }
    }

    // Page full screen's notice (PLAN.md 8m): opaque terminal tone, radius 12, 13 px, 24 px from the top
    // edge, centred, fading in and out: "Esc exits full screen" on entry for 2 s, and for 4 s when an ask
    // arrives.
    Rectangle {
        id: notice
        z: 40
        readonly property alias text: noticeText.text
        readonly property bool shown: opacity > 0
        visible: opacity > 0
        opacity: 0
        Behavior on opacity { Anim { type: Anim.FastEffects } }
        x: Math.round((parent.width - width) / 2)
        y: 24
        width: noticeText.implicitWidth + 40
        height: 32
        radius: Theme.rounding.small
        color: Theme.terminal
        Label {
            id: noticeText
            anchors.centerIn: parent
            font.pixelSize: Theme.font.caption
            color: Theme.colOnSurface
        }
        Timer { id: noticeTimer; onTriggered: notice.opacity = 0 }
        function show(text, ms) {
            noticeText.text = text;
            opacity = 1;
            noticeTimer.interval = ms;
            noticeTimer.restart();
        }
        function hide() {
            noticeTimer.stop();
            opacity = 0;
        }
    }

    // F6: page, the ask's sheet (a waiting ask first), rail list, page
    function focusCycle() {
        const rail = railPinned ? pinnedRail : peekRail;
        if (addressEditor.editing) {
            // the peek opens first, so the card goes back into its slot rather than the handle
            if (!railPinned)
                peek.open = true;
            addressEditor.cancel();
            rail.focusList();
        } else if (findModel.open || siteInfo.open) {
            // find or the site panel is in the address card's place
            if (!railPinned)
                peek.open = true;
            findModel.hide();
            siteInfo.hide();
            rail.focusList();
        } else if (rail.listFocused) {
            peek.open = false;
            focusPage();
        } else if (askSheet.section.activeFocus || rail.askFocused || rail.fillFocused) {
            if (!railPinned)
                peek.open = true;
            rail.focusList();
        } else if (shownAsk && shownAsk.kind === "password") {
            // the "Save password?" line in the card: the pinned rail's, or folded the overlay's, which holds it out
            if (!railPinned)
                peek.open = true;
            rail.focusAsk();
        } else if (shownAsk) {
            // the ask's sheet over the page, folded or docked
            askSheet.section.focusFirst();
        } else if (rail.fillShown) {
            // a login field's Fill rows (PLAN.md 7), in the card that shows them: the pinned rail's, or folded the
            // overlay's, brought out first (a hidden item takes no keys); it goes back when they give the keys up
            if (!railPinned)
                peek.open = true;
            rail.focusFill();
        } else {
            editAddress();
        }
    }
    function focusPage() {
        if (root.currentView)
            root.currentView.forceActiveFocus();
        else if (newBar.opened)
            newBar.show(newBar.text);
    }

    // Row menus, renames and drops from the rail (PLAN.md 3.11, 3.13).
    function command(name, ref, arg) {
        const p = sessionModel.pages[ref];
        switch (name) {
        case "reload": views[ref]?.reload(); break;
        case "duplicate": go(p.url, "new", p.thread, p.title, ref, false); break;
        case "mute": toggleMute(ref); break;
        case "copy": copyText(p.url); break;
        case "moveTo": sessionModel.movePage(ref, arg, ""); break;
        case "split": sessionModel.splitPage(ref, sessionModel.openThreads()[0]?.id ?? ""); break;
        case "splitFrom": sessionModel.splitFrom(ref); break;
        case "always": sessionModel.keepInAlways(ref); break;
        case "close": closePage(ref); break;
        case "back": if (views[ref]) back(views[ref]); break;
        case "closeOthers": dropViews(sessionModel.closeOthers(ref)); afterClose(); break;
        case "rename": sessionModel.rename(ref, arg); break;
        case "newHere": newBar.show("", ref); break;
        case "file": fileThread(ref); break;
        case "restore": restoreThread(ref); break;
        case "openLast": {
            const last = sessionModel.pages[sessionModel.mostRecentPage(ref)];
            if (last) openHere(last.url, last.title);
            break;
        }
        case "copyLast": { const last = sessionModel.pages[sessionModel.mostRecentPage(ref)]; if (last) copyText(last.url); break; }
        // the pin away from its start (Session.awayPin) goes back to it, in front
        case "pinHome": {
            const home = sessionModel.sendHome(ref);
            if (!home)
                break;
            if (views[ref] && String(views[ref].url) !== "")
                views[ref].url = home;
            else
                sessionModel.update(ref, { url: home });
            show(ref);
            break;
        }
        case "moveLeft": sessionModel.moveAlways(ref, -1); break;
        case "moveRight": sessionModel.moveAlways(ref, 1); break;
        // the cell's page leaves the lists every main window shares: its view goes in each window that has one
        case "removeAlways": { const gone = sessionModel.removeAlways(ref); windowsDo(w => w.pagesGone(gone)); break; }
        case "drop":
            if (arg.kind === "into" || arg.kind === "onto")
                sessionModel.movePage(ref, arg.thread, arg.kind === "into" ? arg.before : "");
            else if (arg.kind === "top")
                sessionModel.splitPage(ref, arg.before);
            else if (arg.kind === "new")
                sessionModel.splitPage(ref, sessionModel.openThreads()[0]?.id ?? "");
            else if (arg.kind === "always")
                sessionModel.keepInAlways(ref);
            break;
        // a thread header dragged between threads
        case "dropThread": sessionModel.moveThread(ref, arg.kind === "new" ? sessionModel.openThreads()[0]?.id ?? "" : arg.before); break;
        case "dropFrom": takeRow(arg); break;
        // Earlier and Saved (PLAN.md 3.7); `ref` a page id for a filed page's row
        case "earlierView": openEarlier(ref); break;
        case "closeEarlier": closeEarlier(true); break;
        case "earlierFilter": earlierState.filter = arg; break;
        case "earlierOpen": earlierState.open = Object.assign({}, earlierState.open, { [ref]: arg }); break;
        case "historyOpen": earlierState.unfolded = Object.assign({}, earlierState.unfolded, { [ref]: arg }); break;
        case "historyOlder": earlierState.older = arg; break;
        case "restorePage": restoreThread(p.thread, ref); break;
        case "openPage": openHere(p.url, p.title); break;
        case "saveThread": saveThread(arg || ref); break;
        case "forget": forget(arg, ref); break;
        case "reopenClosed": reopenClosed(ref); break;
        case "openClosed": { const c = sessionModel.closed.find(e => e.id === ref); if (c) openHere(c.url, c.title); break; }
        case "copyClosed": { const c = sessionModel.closed.find(e => e.id === ref); if (c) copyText(c.url); break; }
        case "openSaved": openSaved(ref); break;
        case "openSavedThread": openSavedThread(ref); break;
        case "copySaved": { const sp = savedModel.pageById(ref); if (sp) copyText(sp.url); break; }
        case "editSaved": editSaved(ref); break;
        case "saveEdit": savedModel.edit(ref, arg.name, arg.url); earlierState.editing = ""; break;
        case "cancelEdit": earlierState.editing = ""; break;
        case "removeSaved": if (earlierState.editing === ref) earlierState.editing = ""; savedModel.removePage(ref); break;
        case "removeSavedThread": savedModel.removeThread(ref); break;
        }
    }

    // History, Saved and Downloads (PLAN.md 3.21): the rail's foot, Ctrl+H, Ctrl+Shift+O and Ctrl+J turn the rail list into one of them,
    // the filter taking the keys; folded, the overlay comes out and holds until Esc or a click on the page (3.5). A
    // private window has none (3.14). What was called up over the rail (find, the site panel, the cards) gives way.
    function openEarlier(view) {
        if (root.offTheRecord)
            return false;
        // with no page open the card is the page and stays (PLAN.md 3.4)
        if (newBar.opened && !newBar.resident)
            newBar.hide();
        addressEditor.close();
        findModel.hide();
        siteInfo.hide();
        printCard.hide();
        if (earlierState.view !== view) {
            earlierState.editing = "";
            earlierState.view = view;
        }
        Qt.callLater(() => (root.railPinned ? pinnedRail : peekRail).focusFilter());
        return true;
    }
    // `keys`: the page takes them back, if the rail had them
    function closeEarlier(keys) {
        if (earlierState.view === "")
            return;
        const rail = root.railPinned ? pinnedRail : peekRail;
        const had = rail.listFocused || rail.earlierFocused;
        earlierState.view = "";
        earlierState.filter = "";
        earlierState.open = {};
        earlierState.editing = "";
        earlierState.unfolded = {};
        earlierState.older = false;
        if (keys && had)
            focusPage();
    }

    // Ctrl+D (PLAN.md 3.7): the page saved, "Saved · Edit" in the card for 3 s. A private window asks first (3.14).
    function saveCurrent() {
        const p = sessionModel.current, v = root.currentView;
        if (!p || !/^(https?|file):/i.test(p.url))
            return false;
        if (root.offTheRecord) {
            if (v && !root.shotMode)
                v.enqueue({ kind: "save", origin: Asks.originOf(p.url), host: PageState.pageHost(p.url), url: p.url, title: p.title || RailRows.named(p.url), icon: p.icon || "" });
            return true;
        }
        const id = savedModel.savePage(p.url, p.title || RailRows.named(p.url), p.icon);
        showNotice({ text: "Saved", action: "Edit", run: () => root.editSaved(id), where: "card" }, 3000);
        return true;
    }
    // Save at a private window's ask: into the main profile's Saved, and nothing else of the window's
    function saveToMain(a) {
        savedModel.savePage(a.url, a.title, a.icon);
        showNotice({ text: "Saved", action: "", where: "card" }, 3000);
    }
    // Save thread (a thread's menu, an Earlier row): its pages as they are now
    function saveThread(threadId) {
        const t = sessionModel.threadById(threadId);
        if (!t || root.offTheRecord)
            return;
        savedModel.saveThread(t.id, t.title, t.pages.map(id => sessionModel.pages[id]).filter(q => q && q.url));
    }
    // Edit, F2 or the notice's Edit: the page's row in Earlier > Saved turns into its edit, which takes the keys
    function editSaved(id) {
        const sp = savedModel.pageById(id);
        if (!sp || !openEarlier("saved"))
            return;
        // its row listed: no filter, its imported folder open
        earlierState.filter = "";
        if (sp.folder)
            earlierState.open = Object.assign({}, earlierState.open, { ["folder:" + sp.folder]: true });
        earlierState.editing = id;
        Qt.callLater(() => (root.railPinned ? pinnedRail : peekRail).focusEdit());
    }
    // A saved page: shown where it is open, else as a thread of one
    function openSaved(id) {
        const sp = savedModel.pageById(id);
        if (!sp)
            return;
        closeEarlier(false);
        const open = Object.keys(sessionModel.pages).find(k => sessionModel.pages[k].url === sp.url && ownerOf(k) !== null);
        if (open)
            show(open);
        else
            go(sp.url, "new", "", sp.name);
    }
    // A saved thread opens as a thread (PLAN.md 3.7): the one it was saved from while it is open or filed, else a new
    // one with its pages, the first shown and the rest unloaded
    function openSavedThread(id) {
        const st = savedModel.threadById(id);
        if (!st || st.pages.length === 0)
            return;
        const from = sessionModel.threadById(st.thread);
        if (from && from.earlier) {
            restoreThread(from.id, "");
            return;
        }
        closeEarlier(false);
        if (from) {
            show(sessionModel.mostRecentPage(from.id));
            return;
        }
        const t = sessionModel.newThread(st.title);
        const ids = st.pages.map(q => { const pid = sessionModel.addPage(t, q.url, ""); sessionModel.update(pid, { title: q.title, icon: q.icon }); return pid });
        st.thread = t;
        savedModel.touch();
        show(ids[0]);
    }
    // A closed page from @ or Earlier opens again, back where you stopped
    function reopenClosed(entryId) {
        const id = sessionModel.reopenEntry(entryId);
        if (!id)
            return;
        closeEarlier(false);
        show(id);
    }

    // Forgetting (PLAN.md 3.7, Shift+Delete): an Earlier thread or one of its pages, a closed page, a history row; with
    // what they leave in history. "Forgot <title> · Undo" for 6 s: in the card, or on @'s last line when it came from there.
    function forget(kind, ref, where) {
        let title = "", undo = null;
        // an address leaves history too, unless another page of the session still holds it
        const unvisit = urls => {
            const held = new Set(Object.keys(sessionModel.pages).map(id => sessionModel.pages[id].url));
            return urls.filter(u => !held.has(u)).map(u => historyModel.forget(u)).filter(e => e);
        };
        if (kind === "history") {
            const e = historyModel.forget(ref);
            if (!e)
                return;
            title = e.title || ref;
            undo = () => historyModel.remember(e);
        } else if (kind === "closed") {
            const c = sessionModel.closed.find(x => x.id === ref);
            const u = sessionModel.forgetClosed(ref);
            if (!u)
                return;
            const h = unvisit([c.url]);
            title = c.title || RailRows.named(c.url);
            undo = () => { sessionModel.unforget(u); h.forEach(e => historyModel.remember(e)) };
        } else if (kind === "earlier" || kind === "filed") {
            const p = kind === "filed" ? sessionModel.pages[ref] : null;
            const t = sessionModel.threadById(p ? p.thread : ref);
            if (!t)
                return;
            const urls = p ? [p.url] : t.pages.map(id => sessionModel.pages[id]?.url).filter(u => u);
            const u = p ? sessionModel.forgetPage(ref) : sessionModel.forgetThread(ref);
            if (!u)
                return;
            const h = unvisit(urls);
            title = p ? p.title || RailRows.named(p.url) : t.title;
            undo = () => { sessionModel.unforget(u); h.forEach(e => historyModel.remember(e)) };
        }
        if (!undo)
            return;
        showNotice({ text: "Forgot " + title, action: "Undo", run: undo, kind: "forgot", where: where ?? "card" }, 6000);
    }
    // Shift+Delete on a row of the cards: a history row, a closed page or an Earlier thread. The undo is on the card's last
    // line (`jump`: @, and the address card, lifted out of the rail); from the new-page card's typed rows, in the rail's card.
    function forgetRow(row, jump) {
        const where = jump ? "jump" : "card";
        if (row.kind === "history")
            forget("history", row.url, where);
        else if (row.kind === "closed")
            forget("closed", row.closedId, where);
        else if (row.kind === "earlier")
            forget("earlier", row.threadId, where);
    }
    function showNotice(n, ms) {
        root.cardNotice = n;
        cardNoticeTimer.interval = ms;
        cardNoticeTimer.restart();
    }
    // the notice's action (Edit, Undo), once
    function runNotice() {
        const n = root.cardNotice;
        root.cardNotice = null;
        cardNoticeTimer.stop();
        if (n && n.run)
            n.run();
        if (newBar.opened)
            newBar.refresh();
        if (addressEditor.editing)
            addressEditor.refresh();
    }

    // A row dropped on this rail from another browser window (PLAN.md 3.13, 3.17), or carried out of this one and
    // back: a thread moves here whole, a page where the line or wash showed. Their views in the window they left go,
    // each live page's back history going with it into its next view here (a live view cannot move between windows),
    // and the page on screen there is on screen here.
    function takeRow(i) {
        const p = i.kind === "page" ? sessionModel.pages[i.ref] : null;
        const t = sessionModel.threadById(p ? p.thread : i.ref);
        if (!t || t.earlier || !i.target)
            return;
        const from = hub.mainWindows.find(w => w.windowId === (t.window ?? "")) ?? null;
        const moved = p ? [p.id] : t.pages.slice();
        const shown = from && from !== root && moved.indexOf(from.windowSession.currentPage) >= 0 ? from.windowSession.currentPage : "";
        if (from && from !== root && i.target.kind !== "always")
            from.handOver(moved);
        if (i.kind === "thread")
            sessionModel.adoptThread(t.id, i.target.kind === "new" ? sessionModel.openThreads()[0]?.id ?? "" : i.target.before);
        else
            command("drop", i.ref, i.target);
        if (!from || from === root)
            return;
        from.afterMove();
        if (shown && ownerOf(shown) === root) {
            show(shown);
            raise();
        }
    }
    // Pages leaving for another window's rail (takeRow): their views here go, with what each live one's back list was.
    function handOver(ids) {
        for (const id of ids) {
            const v = views[id];
            if (!v)
                continue;
            const fields = { state: "unloaded", loading: false, audible: false };
            if (String(v.url) !== "" && !v.parked)
                fields.restore = { history: Windows.history(v), scroll: null };
            sessionModel.update(id, fields);
        }
        dropViews(ids.filter(id => views[id]), true);
    }
    // after handOver: the page on screen here, if it went, gives way to this rail's most recent one
    function afterMove() {
        if (!sessionModel.ownOrAlways(sessionModel.currentPage))
            sessionModel.currentPage = sessionModel.mostRecentPage() ?? "";
        if (!root.currentView)
            afterClose();
    }

    // The browser's own failure pages (PLAN.md 3.8 8f-8i): what their buttons do. `popup`: the attached
    // popup window `v` sits in, or null.
    function failureAction(v, action, popup) {
        const f = v ? v.failure : null;
        switch (action) {
        case "open": show(root.restorePage.pageId); return;
        case "retry":
        case "reload": v.retry(); return;
        case "back": v.leave(true); return;
        case "continue": v.continueCertificate(); return;
        // the address with the history's host one edit away in place of the one that has no address
        case "near": v.url = f.url.replace(/^([a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?)[^\/:?#]*/i, "$1" + f.near); return;
        case "search": v.url = omniModel.searchUrl(f.search); return;
        }
    }

    // A page's process stopped (PLAN.md 8h). On screen, the page says how, with what the browser measured:
    // the process's memory, the journal's OOM record for its pid (it arrives later, if at all), and the
    // other pages that shared the process. A page not on screen just becomes unloaded and loads again when
    // opened; so do those others, which get the same signal.
    function pageStopped(v, status, code, onScreen) {
        if (!onScreen) {
            v.reloadOnShow = true;
            if (v.pageId)
                sessionModel.update(v.pageId, { state: "unloaded", loading: false });
            return;
        }
        const now = Date.now(), pid = v.lastPid, how = Failures.stopped(status, code);
        const siblings = Object.keys(views).filter(id => views[id] !== v && views[id].lastPid === pid
                                                   && views[id].lifecycleState !== WebEngineView.LifecycleState.Discarded).length;
        const facts = { url: String(v.url), at: now, pid: pid, how: how.how, code: how.code, stop: null, siblings: siblings,
                        memory: v.sample && v.sample.pid === pid ? v.sample : null, twice: Failures.twice(v.stops, now) };
        v.failure = Object.assign(Failures.crash(facts), { committed: true });
        Facts.lookUpStop(pid, v.sample && v.sample.pid === pid ? v.sample.cgroup : "", now - 60000);
    }
    // every page's view, the sign-in's from another app, and their popups'
    function allViews() {
        const out = Object.keys(views).map(id => views[id]).concat(root.appSignin ? [root.appSignin.view] : []);
        for (const v of out.slice())
            if (v.popup)
                out.push(v.popup.view);
        return out;
    }
    Connections {
        target: Facts
        function onStopFound(pid, source, at) {
            for (const v of root.allViews())
                if (v.failure && v.failure.kind === "crash" && v.failure.pid === pid)
                    v.failure = Object.assign(Failures.crash(Object.assign({}, v.failure.facts, { stop: { source: source, at: at } })), { committed: true });
        }
        // Offline pages load once by themselves when the network is reachable again (8f); never in a loop
        function onReachabilityChanged() {
            if (Facts.reachability !== "online")
                return;
            for (const v of root.allViews())
                if (v.failure && v.failure.kind === "offline" && v.lifecycleState === WebEngineView.LifecycleState.Active)
                    v.retry();
        }
    }
    // The current page's process memory, every 10 s, from /proc: what a stopped page says it was using. Only
    // while a live page is on screen, the only one whose stop says it; the first sample as it comes.
    readonly property alias sampling: memorySampler.running
    Timer {
        id: memorySampler
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: !root.shotMode && !root.noPage && root.currentView !== null && !root.currentView.failure
        onTriggered: root.sampleMemory()
    }
    function sampleMemory() {
        const v = root.currentView;
        if (!v || v.renderProcessPid <= 0)
            return;
        v.lastPid = v.renderProcessPid;
        const m = Facts.memory(v.renderProcessPid);
        if (m.bytes)
            v.sample = { pid: v.renderProcessPid, bytes: m.bytes, at: Date.now(), cgroup: m.cgroup };
    }

    // The clean-quit flag (PLAN.md 8i): the run record says the browser is running, when it was last seen
    // (on each page shown and each minute) and which page is on screen; a clean close marks it clean. It is the main
    // windows' record: a run started with a link keeps it as it found it until a main window shows (`runStarted`), so
    // a peek alone that stops leaves no crash behind it, and one that quits does not mark a crash before it clean.
    property var run: ({})
    property bool runStarted: false
    function writeRun(fields) {
        // a private window's pages are in no record
        if (root.offTheRecord)
            return;
        if (root.primary) {
            root.primary.writeRun(fields);
            return;
        }
        if (root.shotMode || !root.runStarted)
            return;
        root.run = Object.assign({}, root.run, fields, { clean: false, alive: Date.now() });
        Store.save("run", root.run);
    }
    // a page opened from the restore page stays suspect for a minute
    Timer { id: suspectTimer; interval: 60000; onTriggered: root.writeRun({ suspect: undefined }) }
    // The restore after a crash (8i), shown while no page is open, or null.
    property var restorePage: null
    // A start after a run record not marked clean: the browser did not close cleanly. The threads come back
    // unloaded as always and nothing loads; the page that was on screen is offered, not loaded. A page opened
    // from there that stopped the browser again within a minute is left out, into Earlier. False after a
    // clean close. This run's record starts here and keeps the page offered, so a stop before it is opened
    // offers it again.
    function startAfter(last) {
        const start = Failures.afterStart(last && typeof last === "object" ? last : null, Date.now());
        root.run = {};
        root.runStarted = true;
        if (!start.crashed) {
            writeRun({ page: "" });
            return false;
        }
        let leftOut = "";
        const out = sessionModel.pages[start.leaveOut];
        if (out && out.thread) {
            leftOut = out.title || RailRows.untitled(out.url);
            dropViews(sessionModel.closePage(start.leaveOut));
        }
        const p = sessionModel.pages[start.page];
        root.restorePage = Failures.restore({ at: start.at, pageId: p ? start.page : "", title: p ? p.title || RailRows.untitled(p.url) : "", leftOut: leftOut });
        writeRun({ page: root.restorePage.pageId });
        if (newBar.opened)
            newBar.hide();
        for (const id in views)
            views[id].visible = false;
        root.currentView = null;
        sessionModel.currentPage = "";
        sessionModel.touch();
        Qt.callLater(() => failurePage.take());
        return true;
    }

    // Closing a window (PLAN.md 3.17): one of several files its threads and goes (closeWindow); the last one quits with
    // the session kept, as Ctrl+Q does from any window.
    onClosing: close => {
        if (hub.quitting)
            return;
        if (offTheRecord) {
            // hidden rather than closed: Qt quits on its own when the last shown window closes, before quitAll saves
            close.accepted = false;
            closePrivate();
            return;
        }
        if (openMains().some(w => w !== root)) {
            closeWindow();
            return;
        }
        close.accepted = false;
        // the last main window, a private window still open: it waits hidden as a quit would keep it (setAside)
        if (hub.privateWindows.length > 0) {
            setAside();
            return;
        }
        hub.quitAll();
    }
    // This window goes while others stay: its multi-page threads file under Earlier, its single pages go to closed
    // pages (Session.closeWindow), and its views go with it. The first window is only hidden. The page on screen says
    // where you stopped first (PLAN.md 3.7), for its filed thread or closed entry.
    function closeWindow() {
        findModel.hide();
        siteInfo.hide();
        printCard.hide();
        addressEditor.close();
        notchAddress.close();
        if (newBar.opened)
            newBar.hide();
        const title = root.title, state = windowState();
        captureStops([[root, root.currentView]], () => {
            dropViews(sessionModel.closeWindow(title, state));
            // Always pages' views: the pages live on in the other windows
            dropViews(Object.keys(views), true);
            root.restorePage = null;
            hub.windowClosed(root);
        });
    }
    // The last main window closing while a private window is open (PLAN.md 3.14, 3.17): its threads stay as a quit keeps
    // them, its pages unloaded, and it waits hidden while the private window goes on. Ctrl+N there, `browser` or a
    // peek's Keep shows it again; closing the private window then quits.
    function setAside() {
        findModel.hide();
        siteInfo.hide();
        printCard.hide();
        addressEditor.close();
        notchAddress.close();
        if (newBar.opened)
            newBar.hide();
        root.visible = false;
        // where you stopped on the page on screen first (PLAN.md 3.7); shown again meanwhile, it keeps its pages
        captureStops([[root, root.currentView]], () => {
            if (root.visible)
                return;
            for (const id in views)
                sessionModel.update(id, { state: "unloaded", loading: false, audible: false });
            dropViews(Object.keys(views), true);
        });
    }
    // A private window closes (PLAN.md 3.14): its pages, history, site choices and cookies end with it (its profile is
    // its child), and nothing of it goes to closed pages or Earlier. A file still coming stops and its part-file goes;
    // the files that landed stay on disk.
    function closePrivate() {
        findModel.hide();
        siteInfo.hide();
        printCard.hide();
        addressEditor.close();
        if (newBar.opened)
            newBar.hide();
        for (const id in ownDownloads.requests)
            ownDownloads.requests[id].cancel();
        dropViews(Object.keys(views));
        clearer.origin = "";
        root.visible = false;
        hub.privateClosed(root);
    }
    // Ctrl+Q, or the last main window closing: every window stays as it is for the next start. Where each window is
    // is asked of Hyprland first, for restore (Backdrop answers within 500 ms). Check mode counts the quit instead,
    // and goes on.
    property bool quitting: false
    property int quits: 0
    property int quitWaits: 0           // Hyprland's answer and the pages' (where you stopped), before the save
    property bool quitAsked: false      // Backdrop was asked where the windows are
    function quitAll() {
        if (quitting)
            return;
        quitting = true;
        // no link is taken from here: a later `browser` waits, and takes over once this one has gone (Instance.start)
        if (root.instance)
            root.instance.close();
        quitWaits = 2;
        // a step that never answers cannot keep the browser running without windows, deaf to the next `browser`
        // (2026-10-15: no window, no answer, until it was killed)
        quitLimit.start();
        // where you stopped on each main window's page on screen, for the next start (PLAN.md 3.7)
        captureStops(openMains().map(w => [w, w.currentView]), () => root.quitStep());
        quitAsked = Backdrop.refresh();
        if (!quitAsked)
            quitStep();
    }
    function quitStep() {
        if (quitting && --quitWaits === 0)
            finishQuit();
    }
    Timer { id: quitLimit; interval: 3000; onTriggered: if (root.quitting) root.finishQuit() }
    Connections {
        target: root.primary ? null : Backdrop
        function onRefreshed() {
            if (root.quitting && root.quitAsked) {
                root.quitAsked = false;
                root.quitStep();
            }
        }
    }
    function finishQuit() {
        // a Clear browsing data still waiting on its undo happens at the quit, as it would have once the 6 s were over
        // (Passwords does the same with a Delete)
        const clearing = root.prefs.clearing;
        if (clearing) {
            root.prefs.undoClear();
            clearData(clearing.what);
        }
        quitLimit.stop();
        try {
            saveAll();
        } catch (e) {
            console.warn("browser: the quit's save failed:", e);
        }
        if (root.engineCheck) {
            root.quits++;
            root.quitting = false;
            if (root.instance)
                root.instance.start();
        } else {
            Qt.quit();
        }
    }
    function saveAll() {
        sessionModel.save();
        Store.save("history", historyModel.entries);
        siteModel.save();
        savedModel.save();
        // a Settings change still waiting on its 500 ms save
        if (prefs.saveTimer.running)
            prefs.save();
        if (root.runStarted)
            Store.save("run", { clean: true });
    }

    // The main windows (PLAN.md 3.17), asked of any window: the shown ones, the one with the focus (or null), the one
    // that last had it (else a shown one, else the first).
    function openMains() { return hub.mainWindows.filter(w => w.visible) }
    function activeMain() { return hub.mainWindows.find(w => w.visible && w.active) ?? null }
    // With none shown, the one that had it last: set aside (setAside), or the first, hidden before a link shows it.
    function lastMain() {
        const l = hub.lastWindow;
        return l && l.visible ? l : openMains()[0] ?? l ?? hub;
    }
    // the main window whose rail holds the page; null for an Always page, a filed one or none. A private window's pages
    // are its own.
    function ownerOf(pageId) {
        if (root.offTheRecord)
            return sessionModel.ownOrAlways(pageId) ? root : null;
        const p = sessionModel.pages[pageId];
        const t = p && p.thread ? sessionModel.threadById(p.thread) : null;
        return t && !t.earlier ? hub.mainWindows.find(w => w.windowId === (t.window ?? "")) ?? null : null;
    }
    // every window's views and their popups'
    function everyView() { return hub.mainWindows.reduce((all, w) => all.concat(w.allViews()), []) }
    function windowsDo(f) {
        for (const w of hub.mainWindows.slice())
            f(w);
    }
    // the views and windows on this window's profile: a private window's own, else every main window's
    function profileViews() { return root.offTheRecord ? allViews() : hub.everyView() }
    function profileWindowsDo(f) {
        if (root.offTheRecord)
            f(root);
        else
            windowsDo(f);
    }
    // Takes the focus: asked of the compositor, and of Hyprland, where an activation request alone may only mark the
    // window urgent.
    function raise() {
        if (!visible)
            visible = true;
        requestActivate();
        Backdrop.focus(root);
    }

    // This window's fold and size: its record, and a window opened from it.
    function windowState() { return { railPinned: railPinned, railWidth: railWidth, width: width, height: height } }
    function applyState(s) {
        if (s.width > 0)
            width = s.width;
        if (s.height > 0)
            height = s.height;
        railWidth = Math.max(248, Math.min(420, s.railWidth ?? railWidth));
        if (s.railPinned !== undefined)
            setFold(s.railPinned);
    }
    // folded (the overlay in) or pinned at once, without the fold's motion
    function setFold(pinned) {
        if (railPinned === pinned)
            return;
        railPinned = pinned;
        liftAnim.stop();
        dockAnim.stop();
        pageSlide.stop();
        pageStill.cancel();
        docking = false;
        peek.kept = false;
        peek.open = false;
        // after the fold's own hold went, whose end would start the close
        closeTimer.stop();
        openTimer.stop();
        slideIn.stop();
        slideOut.stop();
        peekRail.slide = 0;
        railSlide = pinned ? 0 : 1;
        railLift = pinned ? 0 : 1;
        railFill = railLift;
        pageBeside = pinned;
        pageShift = 0;
    }
    function record() {
        return Object.assign(windowState(), { id: windowId, currentPage: sessionModel.currentPage, workspace: Backdrop.workspaceOf(root) || workspace });
    }
    // For threads.json: every main window that is shown or holds threads, the first window first, and the records of
    // windows not restored yet. The first window hidden before a link shows it (no run started) keeps its record too.
    function windowRecords() {
        return mainWindows.filter(w => w.visible || w.windowSession.openThreads().length > 0 || w === root && !root.runStarted)
            .map(w => w.record()).concat(pendingWindows);
    }

    // A new main window (Ctrl+N, a closed window reopened, restore): the first window again while it is hidden with
    // nothing in its rail, else a new Main with its own Session over the first window's lists. `state`: its fold and
    // size; `id`: its windowId ("": a new one). Asked of the first window.
    function newWindow(state, id) {
        let w = root;
        if (root.visible || sessionModel.openThreads().length > 0) {
            w = Qt.createComponent("Browser", "Main").createObject(made, {
                dataDir: root.dataDir, startUrl: "", adblock: root.adblock, primary: root, profile: root.profile,
                windowId: id || sessionModel.uid(), transientParent: null, width: root.width, height: root.height });
            mainWindows = mainWindows.concat([w]);
        }
        w.applyState(state ?? {});
        w.visible = true;
        return w;
    }
    // Ctrl+Shift+N (PLAN.md 3.14): a private window, the size and fold of the window it came from. Asked of the first
    // window.
    function newPrivateWindow(state) {
        const w = Qt.createComponent("Browser", "Main").createObject(made, {
            offTheRecord: true, dataDir: root.dataDir, startUrl: "", adblock: root.adblock, primary: root,
            windowId: "private-" + sessionModel.uid(), transientParent: null, width: root.width, height: root.height });
        privateWindows = privateWindows.concat([w]);
        w.applyState(state ?? {});
        w.visible = true;
        return w;
    }
    // A private window closed (closePrivate); with no other window left the browser quits, as Ctrl+Q does
    // (lastWindowGone). Asked of the first window.
    function privateClosed(w) {
        privateWindows = privateWindows.filter(o => o !== w);
        w.destroy();
        lastWindowGone();
    }
    // A window closed while others stay (closeWindow). Asked of the first window.
    function windowClosed(w) {
        if (lastWindow === w)
            lastWindow = openMains().find(o => o !== w) ?? root;
        if (w === root)
            return;
        mainWindows = mainWindows.filter(o => o !== w);
        w.destroy();
    }
    // Ctrl+Shift+T on a closed window (PLAN.md 3.17): it comes back whole, with its fold and size. Asked of the first
    // window.
    function reopenWindow(entry) {
        const w = newWindow(entry.state, "");
        w.windowSession.restoreWindow(entry);
        w.afterClose();
        w.raise();
    }
    // A main window shows (a link, `browser`): the first one, hidden until then, brings the windows restored with it.
    function reveal(m) {
        if (m.visible)
            return;
        m.visible = true;
        if (m !== hub)
            return;
        // the run starts here when a link started the browser: a crash before it is offered now (8i), before the windows open
        if (!hub.runStarted)
            hub.startAfter(Store.load("run"));
        hub.openPendingWindows();
    }
    // Restore (PLAN.md 3.17): the other windows of the last run, each with its threads, fold and size and the page it
    // showed; then Hyprland is asked to move each of them to the workspace it was on. This window stays where it opened,
    // the workspace you started the browser on: moved back to its old one, it showed for a moment and was gone (owner,
    // 2026-10-01, Super+W). Outside Hyprland they just open. After a run that did not close cleanly nothing loads (8i):
    // the other windows open with no page, the restore page being this one's.
    function openPendingWindows() {
        const records = pendingWindows;
        pendingWindows = [];
        const placed = [];
        for (const r of records) {
            const w = newWindow(r, r.id);
            const s = w.windowSession;
            w.workspace = r.workspace ?? "";
            s.currentPage = root.restorePage ? "" : s.ownOrAlways(r.currentPage) ? r.currentPage : (s.mostRecentPage() ?? "");
            w.afterClose();
            placed.push({ window: w, workspace: w.workspace });
        }
        if (placed.some(p => p.workspace))
            Backdrop.place(placed);
    }

    // What every profile gets: the Downloads folder, the ad blocker, the scrollbars' style, the edit watch and the login watch.
    function setUpProfile() {
        // before any download: in check mode Disk.downloads is the throwaway data dir's
        root.profile.downloadPath = Disk.downloads;
        root.adblock.attach(root.profile);
        Engine.attach(root.profile);
        root.styleScrollbars();
        root.watchEdits();
        root.watchLogins();
        root.watchSwipes();
        // what the engine gives a profile, before Settings changes it
        if (!root.primary) {
            root.engineFonts = Engine.fonts(root.profile);
            root.engineLanguages = root.profile.httpAcceptLanguage;
        }
    }

    // Settings (PLAN.md 3.15) take effect at once: each window with a profile of its own (the first one's, a private
    // one's) applies them to it, and the first window to what every window shares. `key` "": all of them.
    Connections {
        target: root.ownLists ? root.prefs : null
        function onChanged(key) { root.applyPrefs(key) }
    }
    function applyPrefs(key) {
        const p = root.prefs, all = key === "";
        if (root.shotMode || !root.profile)
            return;
        if (all || key === "fonts" || key === "minimumFont")
            Engine.setFonts(root.profile, Object.assign(Settings.pageFonts(p.get("fonts")), { minimum: p.get("minimumFont") }));
        if (all || key === "languages" || key === "spellCheck")
            applyLanguages();
        // the profile's cookie list: attached once setUpProfile has run
        if (all || key === "thirdPartyCookies")
            (root.offTheRecord ? root.siteData : SiteData)?.refuseThirdParty(p.get("thirdPartyCookies") === "block");
        if (all || key === "folder")
            root.profile.downloadPath = root.downloadFolder;
        // pages of sites with no zoom of their own take the default at once
        if (key === "zoom")
            for (const v of root.profileViews())
                if (!v.parked && String(v.url) !== "")
                    v.zoomFactor = siteModel.zoom(Asks.originOf(String(v.url)));
    }
    // Languages: the pages' Accept-Language (and navigator.languages); spell check in them, once each has a dictionary
    // (Engine converts hunspell's). None set: the engine's own.
    function applyLanguages() {
        const p = root.prefs, set = p.get("languages");
        root.profile.httpAcceptLanguage = set.length > 0 ? Settings.acceptLanguage(set) : hub.engineLanguages;
        if (!p.get("spellCheck")) {
            root.profile.spellCheckEnabled = false;
            return;
        }
        Engine.convert(set.length > 0 ? set : root.defaultLanguages);
    }
    Connections {
        target: root.ownLists ? Engine : null
        function onConverted(dictionaries) {
            if (!root.profile || !root.prefs.get("spellCheck"))
                return;
            const ready = Object.keys(dictionaries).filter(l => dictionaries[l] === "ready");
            root.profile.spellCheckLanguages = ready;
            root.profile.spellCheckEnabled = ready.length > 0;
        }
    }
    // the list update's failure stays under Ad blocking until an update succeeds; when the last one succeeded, for its
    // "Up to date"
    Connections {
        target: root.primary ? null : root.adblock
        ignoreUnknownSignals: true
        function onUpdated(failure) {
            ownPrefs.set("listFailure", failure ? { at: Date.now(), text: failure } : null);
            if (!failure)
                ownPrefs.set("listUpdated", Date.now());
        }
    }
    // Clear browsing data (Settings > Privacy), once its undo has run out: the main profile's
    Connections {
        target: root.primary ? null : ownPrefs
        function onClearDue(what) { root.clearData(what) }
    }
    function clearData(what) {
        if (what === "history") {
            historyModel.clear();
            sessionModel.clearClosedPages();
        } else if (what === "cookies") {
            SiteData.clearAllCookies();
        } else if (what === "cache" && root.profile) {
            root.profile.clearHttpCache();
        }
    }
    // A private window starts (PLAN.md 3.14): the first window's site choices and the rail's learned hints copied in,
    // never written back, and an off-the-record profile of its own.
    function startPrivate() {
        const main = root.primary;
        ownSites.entries = JSON.parse(JSON.stringify(main.siteModel.entries));
        ownSites.revision++;
        sessionModel.learned = Object.assign({}, main.windowSession.learned);
        if (root.shotMode)
            return;
        root.profile = privateProfile.createObject(root).instance();
        setUpProfile();
        root.siteData = SiteData.forProfile(root.profile);
        root.adblock.setAllowed(siteModel.adsAllowed(), root.profile);
        applyPrefs("");
    }

    Component.onCompleted: {
        if (root.offTheRecord) {
            startPrivate();
            return;
        }
        // a window the first one made (newWindow): the first one set up the profile and loaded the session
        if (root.primary)
            return;
        Backdrop.texture = frostTexture;
        Backdrop.refresh();
        if (root.shotMode) {
            applyPrefs("");
            return;
        }
        ownPrefs.load();
        root.profile = profilePrototype.createObject(root).instance();
        setUpProfile();
        SiteData.attach(root.profile);
        applyPrefs("");
        historyModel.load();
        siteModel.load();
        savedModel.load();
        root.adblock.setAllowed(siteModel.adsAllowed(), root.profile);
        sessionModel.load();
        // this window's fold and size from its record (window.json, from before several windows), and the other
        // windows' records, which open once this window shows
        const w = sessionModel.loadedWindow ?? Store.load("window");
        if (w) {
            applyState(w);
            root.workspace = w.workspace ?? "";
        }
        root.pendingWindows = sessionModel.loadedWindows;
        downloadModel.schedule();
        // DevTools used in the last week: a spare is ready 8 s after the start, so the first F12 shows at once too
        const devTools = Store.load("devtools");
        if (devTools && Date.now() - devTools.used < 7 * 86400000)
            spareStart.start();
        if (devTools && devTools.side === "right")
            root.devToolsSide = "right";
        if (String(root.startUrl) !== "") {
            // this window is hidden until openLink shows it (reveal), the run starting then
            openLink(String(root.startUrl), root.startFrom, root.startContext);
            return;
        }
        const restoring = startAfter(Store.load("run"));
        if (restoring) {
            // the restore page is the page until one is opened
        } else if (sessionModel.currentPage) {
            // an Always page can be current with no thread left
            show(sessionModel.currentPage);
        } else {
            newBar.show();
            // nothing open, as at the first start: the browsers on this computer looked for, Welcome once if there are any
            if (!root.engineCheck && !root.prefs.get("welcomed"))
                root.welcomeWhenFound = true;
            ChromeImport.scan();
            Zen.scan();
        }
        openPendingWindows();
    }
}
