import QtQuick
import QtQuick.Window
import QtWebEngine
import "Asks.js" as Asks
import "Downloads.js" as Downloads
import "Lifecycle.js" as Lifecycle
import "Logins.js" as Logins
import "Recall.js" as Recall

// `browser --check-engine` only (tools/check-engine): opens fixture pages in real web views, presses keys
// through the window system and runs the memory net, then checks what the browser and the pages did
// (PLAN.md 5 and the phase 1 checks: Ctrl+B bolds in a rich text field and folds elsewhere, a key the
// page takes stays the page's, R keys never reach the page; with memory low pages unload one at a time unless a
// field was edited; the folded rail's hover peek, with the pointer moved through the window system; loading
// and https-first against a local server, the asks, and the page's own voice: its dialogs, popups, file
// picks and full screen, and downloads, PLAN.md 3.8; links a second `browser` hands over (single instance); and
// that the window draws no frame while nothing on screen changes). The steps come in groups;
// `browser --check-engine <group ...>` runs only those (see `all`).
QtObject {
    id: check

    required property var app
    required property var probe        // the C++ EngineCheck
    required property var session
    required property var address    // Main's AddressEditor
    required property var newPageBar
    required property var hoverPeek  // Main's peek
    required property var peekedRail // Main's overlay rail (named apart from its id)
    required property var pageScroll // Main's PageScrollBar
    required property var rail       // Main's pinned rail
    required property var dialog     // Main's PageDialog
    required property var screenNotice // Main's full-screen notice
    required property var ownPage    // Main's FailurePage (named apart from its id)
    required property var history    // Main's History
    required property var downloads  // Main's Downloader
    required property var site       // Main's SiteInfo

    // Gmail compose takes Ctrl+B itself; a plain rich text field bolds by default.
    readonly property string fixture: "<!doctype html><title>keys</title><body>"
        + "<p>plain text</p><div id=rich contenteditable>rich text</div><div id=gmail contenteditable>compose</div>"
        + "<select id=sel><option>a<option>b</select><input id=field>"
        + "<script>window.seen = [];"
        + "document.getElementById('gmail').addEventListener('keydown', e => { if (e.ctrlKey && e.key === 'b') e.preventDefault() });"
        + "document.addEventListener('keydown', e => seen.push((e.ctrlKey ? 'Ctrl+' : '') + (e.altKey ? 'Alt+' : '') + e.key), true);"
        + "</script>"
    readonly property string plain: "data:text/html," + encodeURIComponent("<!doctype html><title>plain</title><p>nothing to edit")

    property string keysPage: ""
    property string idlePage: ""
    property string idlePage2: ""
    property string otherPage: ""
    function state(id) { return app.views[id] ? app.views[id].lifecycleState : -1 }
    function recommended(id) { return app.views[id] ? app.views[id].recommendedState : -1 }
    function unseenFor(id, minutes) { session.pages[id].seen = Date.now() - minutes * 60000 }
    // The memory net (Main.relieveMemory): this machine's threshold (Lifecycle.low), and one tick with MemAvailable
    // faked at `bytes`; the lines it logged
    function netLow() { return Math.max(1024 * 1048576, Facts.systemMemory().total / 10) }
    function netTick(bytes) { Facts.fakeAvailable(bytes); app.relieveMemory(); Facts.fakeAvailable(-1) }
    readonly property real lowMemory: 256 * 1048576
    property int netLines: 0

    readonly property int ctrl: Qt.ControlModifier
    // Each step: optional `focus` (script run on the current page first; a function returns it), a key (`key`, `mods`, `text`)
    // or an `act`, then after `wait` ms `expect()`, and optionally `page` evaluated in the page (in
    // `world`; a function returns it) and checked by `pageExpect` (default: true).
    // `{ group: name }` starts a group, run in this order; the command line's group names pick which run (none: all).
    // A `setup` step makes what its group takes from the groups before it, and runs only when one of those did
    // not run, so the whole run is the checks alone.
    readonly property var all: [
        { group: "keys" },
        { name: "no field edited yet", expect: () => true, page: "!!window.__browserEdited", world: WebEngineScript.ApplicationWorld, pageExpect: v => v === false },
        { name: "Ctrl+B on the page folds the rail (P key the page left alone)", focus: "document.activeElement.blur()",
          key: Qt.Key_B, mods: ctrl, expect: () => app.railPinned === false },
        { name: "Ctrl+B again pins it", focus: "document.activeElement.blur()",
          key: Qt.Key_B, mods: ctrl, expect: () => app.railPinned === true },
        { name: "Ctrl+B in a rich text field bolds and does not fold", focus: "rich.focus(); getSelection().selectAllChildren(rich)",
          key: Qt.Key_B, mods: ctrl, expect: () => app.railPinned === true, page: "document.queryCommandState('bold')" },
        { name: "Ctrl+B in Gmail-like compose (the page calls preventDefault) does not fold", focus: "gmail.focus()",
          key: Qt.Key_B, mods: ctrl, expect: () => app.railPinned === true },
        { name: "Ctrl+L in a page field edits the address (R key)", focus: "field.focus()",
          key: Qt.Key_L, mods: ctrl, expect: () => address.editing === true },
        { name: "Esc puts the address card back in its slot", key: Qt.Key_Escape, expect: () => address.editing === false && address.out === false },
        { name: "Ctrl+T in a page field opens the new-page bar (R key)", focus: "field.focus()",
          key: Qt.Key_T, mods: ctrl, expect: () => newPageBar.opened === true },
        { name: "Esc closes the bar", key: Qt.Key_Escape, expect: () => newPageBar.opened === false },
        { name: "Ctrl+T opens the bar again", key: Qt.Key_T, mods: ctrl, expect: () => newPageBar.opened === true },
        { name: "Ctrl+L over the open bar swaps it for the address card",
          key: Qt.Key_L, mods: ctrl, expect: () => newPageBar.opened === false && address.editing === true },
        // offscreen the window is never active, so a card that lost the focus stays drawn; Esc shows it
        { name: "Esc puts that card back, so the card kept the focus", key: Qt.Key_Escape, expect: () => address.editing === false },
        { name: "Alt+Down on a select stays the page's", focus: "sel.focus()",
          key: Qt.Key_Down, mods: Qt.AltModifier, expect: () => app.railPinned === true },
        { name: "the page saw its keys and none of the R keys", expect: () => true, page: "JSON.stringify(seen)",
          pageExpect: v => { const s = JSON.parse(v); return s.indexOf("Ctrl+b") >= 0 && s.indexOf("Alt+ArrowDown") >= 0
              && s.indexOf("Ctrl+l") < 0 && s.indexOf("Ctrl+t") < 0 } },
        { name: "typing in a field (Ctrl+B above already counted) marks the page edited, in the browser's script world", focus: "field.focus()",
          key: Qt.Key_X, text: "x", expect: () => true, page: "!!window.__browserEdited", world: WebEngineScript.ApplicationWorld },
        { name: "the page itself cannot see the mark", expect: () => true, page: "typeof window.__browserEdited", pageExpect: v => v === "undefined" },
        { group: "lifecycle" },
        // only keys comes before, so the page on screen is the keys page
        { setup: true, name: "(a field typed into: the keys page is edited)", focus: "field.focus()", key: Qt.Key_X, text: "x",
          expect: () => true, page: "!!window.__browserEdited", world: WebEngineScript.ApplicationWorld },
        { name: "two pages open in the background and the first leaves view", wait: 1500,
          act: () => {
              check.keysPage = session.currentPage;
              check.idlePage = session.addPage(session.current.thread, check.plain, "");
              app.viewFor(check.idlePage).url = check.plain;
              check.idlePage2 = session.addPage(session.current.thread, check.plain, "");
              app.viewFor(check.idlePage2).url = check.plain;
              check.otherPage = session.addPage(session.current.thread, check.plain, "");
              app.show(check.otherPage);
          },
          expect: () => state(keysPage) === 0 && state(idlePage) === 0 && state(idlePage2) === 0 },
        // The memory net (PLAN.md 3.12), a tick at a time with MemAvailable faked; time unseen alone unloads nothing
        { name: "pages unseen for hours, memory just above the threshold: nothing unloads", wait: 1000,
          act: () => { unseenFor(keysPage, 300); unseenFor(idlePage, 200); unseenFor(idlePage2, 100); check.netLines = probe.outputCount("memory low (");
              check.netTick(check.netLow() + 64 * 1048576) },
          expect: () => state(keysPage) === 0 && state(idlePage) === 0 && state(idlePage2) === 0 && probe.outputCount("memory low (") === check.netLines },
        { name: "under it: the page seen longest ago is asked first, and the field edited there keeps it live", wait: 1000,
          act: () => check.netTick(check.lowMemory),
          expect: () => state(keysPage) === 0 && app.views[check.keysPage].editedKept && state(idlePage) === 0 && state(idlePage2) === 0 },
        { name: "the next tick unloads the next one alone, and logs it in one line", wait: 1000, act: () => check.netTick(check.lowMemory),
          expect: () => state(idlePage) === 2 && session.pages[idlePage].state === "unloaded" && state(idlePage2) === 0 && state(keysPage) === 0
              && probe.outputCount("memory low (") === check.netLines + 1 && probe.outputHolding("memory low (256 MB available): unloaded data:") },
        { name: "the tick after, the one after it", wait: 1000, act: () => check.netTick(check.lowMemory),
          expect: () => state(idlePage2) === 2 && state(keysPage) === 0 && probe.outputCount("memory low (") === check.netLines + 2 },
        { name: "then nothing: the edited page and the page on screen stay", wait: 1000, act: () => check.netTick(check.lowMemory),
          expect: () => state(keysPage) === 0 && state(check.otherPage) === 0 && probe.outputCount("memory low (") === check.netLines + 2 },
        { name: "showing an unloaded page loads it again", wait: 1500, act: () => app.show(idlePage),
          expect: () => state(idlePage) === 0 && session.pages[idlePage].state === "live" && view.title === "plain" },
        // the page the net passes over is the one seen longest ago
        { name: "a page whose ask waits behind its ● stays (unloading would drop the ask); the next one seen longest ago goes", wait: 1000,
          act: () => { app.views[check.idlePage].asks = [check.standInAsk()]; app.show(check.keysPage); unseenFor(idlePage, 400); check.netTick(check.lowMemory) },
          expect: () => session.pages[idlePage].needsYou && state(idlePage) === 0 && state(check.otherPage) === 2 },
        { name: "(its ask gone)", wait: 300, act: () => { app.views[check.idlePage].asks = [] }, expect: () => !session.pages[idlePage].needsYou },
        { name: "the net runs on its own every 10 s", wait: 10600, act: () => { Facts.fakeAvailable(check.lowMemory); app.memoryNetTimer.restart() },
          expect: () => app.memoryNetTimer.interval === 10000 && state(idlePage) === 2 && probe.outputCount("memory low (") === check.netLines + 4 },
        { name: "(memory to spare again; back on the idle page)", wait: 1500, act: () => { Facts.fakeAvailable(-1); app.show(check.idlePage) },
          expect: () => state(idlePage) === 0 && !session.pages[idlePage].needsYou },
        { group: "peek" },
        // The hover peek (PLAN.md 3.5): folded, the page starts 6 px in from the window's left side (PLAN.md 3.19).
        { name: "folded, with the pointer on the page: no peek", wait: 800,
          act: () => { app.railPinned = false; probe.pointer(700, 400) }, expect: () => !app.railPinned && !hoverPeek.open },
        { name: "12 px in: the peek is out within 100 ms", wait: 100,
          act: () => probe.pointer(12, 400), expect: () => hoverPeek.open },
        { name: "back on the page it leaves", wait: 600, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.open },
        { name: "the page under the hover zone still sees the pointer and the click", wait: 300,
          focus: "window.downs = []; window.moves = 0; addEventListener('mousedown', e => downs.push(e.clientX));"
              + " addEventListener('mousemove', e => { if (e.clientX < 10) moves++ })",
          act: () => { probe.pointer(10, 400); probe.pointer(11, 400); probe.pointer(11, 400, Qt.LeftButton); probe.pointer(11, 400) },
          expect: () => true, page: "JSON.stringify([downs, moves])", pageExpect: v => { const r = JSON.parse(v); return r[0].join() === "5" && r[1] > 0 } },
        { name: "and it leaves again", wait: 600, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.open },
        { name: "a flick out across the left side opens it at once", wait: 0,
          act: () => { probe.pointer(60, 400); probe.pointer(20, 400); probe.leave() }, expect: () => hoverPeek.open },
        { name: "it stays while the pointer is away", wait: 1000, expect: () => hoverPeek.open },
        { name: "it leaves when the pointer has not come back after 1.5 s", wait: 1100, expect: () => !hoverPeek.open },
        { name: "flicked out, a resize from the left border sends it back",
          act: () => { probe.pointer(60, 400); probe.pointer(20, 400); probe.leave(); app.width = 1200 }, wait: 300,
          expect: () => app.width === 1200 && !hoverPeek.open },
        { name: "the window back at its width", wait: 300, act: () => app.width = 1280, expect: () => app.width === 1280 && !hoverPeek.open },
        { name: "flicked out again", wait: 300,
          act: () => { probe.pointer(60, 400); probe.pointer(20, 400); probe.leave() }, expect: () => hoverPeek.open },
        { name: "back onto the rail it stays", wait: 400, act: () => probe.pointer(150, 400), expect: () => hoverPeek.open },
        { name: "off the rail it leaves", wait: 600, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.open },
        { name: "leaving by moving right opens nothing", wait: 400,
          act: () => { probe.pointer(18, 400); probe.pointer(22, 400); probe.leave() }, expect: () => !hoverPeek.open },
        { name: "leaving across the top near the left side opens nothing", wait: 400,
          act: () => { probe.pointer(60, 400); probe.pointer(20, 400); probe.pointer(20, 3); probe.leave() }, expect: () => !hoverPeek.open },
        { name: "leaving across the right side opens nothing", wait: 400,
          act: () => { probe.pointer(1270, 400); probe.leave() }, expect: () => !hoverPeek.open },
        { name: "a press near the left side dragged out across the right side opens nothing", wait: 400,
          act: () => { probe.pointer(60, 400); probe.pointer(20, 400); probe.pointer(20, 400, Qt.LeftButton); probe.pointer(1270, 400, Qt.LeftButton); probe.pointer(1270, 400); probe.leave() },
          expect: () => !hoverPeek.open },
        { name: "a drag from the page into the zone opens nothing while the button is held", wait: 400,
          act: () => { probe.pointer(700, 400); probe.pointer(700, 400, Qt.LeftButton); probe.pointer(300, 400, Qt.LeftButton); probe.pointer(10, 400, Qt.LeftButton) },
          expect: () => !hoverPeek.open },
        { name: "nor a drag out across the left side released outside", wait: 400,
          act: () => { probe.pointer(-20, 400, Qt.LeftButton); probe.pointer(-20, 400); probe.leave() }, expect: () => !hoverPeek.open },
        // Under Hyprland the peek asks where the cursor went; offscreen Backdrop answers fakeCursor, on the
        // screen, where the window lies at (6, 44), 800 high.
        { name: "a flick that reaches the screen's edge level with the window opens it at once", wait: 0,
          act: () => { Backdrop.fakeCursor = Qt.point(0, 444); probe.pointer(60, 400); probe.pointer(20, 400); probe.leave() },
          expect: () => hoverPeek.open },
        { name: "back on the page it leaves", wait: 600, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.open },
        { name: "a reach for the left resize border, the cursor still in the gap (or a neighbour), opens nothing", wait: 400,
          act: () => { Backdrop.fakeCursor = Qt.point(3, 444); probe.pointer(60, 400); probe.pointer(20, 400); probe.leave() },
          expect: () => !hoverPeek.open },
        // Hyprland answers before the next motion event: the first answer is the point that left the window
        { name: "a flick first answered in the gap opens once a later answer reaches the edge", wait: 300,
          act: () => { Backdrop.fakeCursor = Qt.point(3, 444); probe.pointer(60, 400); probe.pointer(20, 400); probe.leave(); Backdrop.fakeCursor = Qt.point(0, 444) },
          expect: () => hoverPeek.open },
        { name: "and back on the page it leaves", wait: 600, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.open },
        { name: "a fast flick last seen 400 px in opens it at once", wait: 0,
          act: () => { Backdrop.fakeCursor = Qt.point(0, 444); probe.pointer(700, 400); probe.pointer(300, 400); probe.leave() },
          expect: () => hoverPeek.open },
        { name: "the cursor resting at the screen's edge holds it past 1.5 s", wait: 1800, expect: () => hoverPeek.open },
        { name: "the cursor gone from the edge (into the gap), it leaves", wait: 600,
          act: () => Backdrop.fakeCursor = Qt.point(3, 444), expect: () => !hoverPeek.open },
        { name: "heading left into the zone opens it at once", wait: 0,
          act: () => { probe.pointer(700, 400); probe.pointer(60, 400); probe.pointer(10, 400) }, expect: () => hoverPeek.open },
        { name: "and off it on the page it leaves", wait: 600, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.open },
        { name: "the screen's edge above the window opens nothing", wait: 400,
          act: () => { Backdrop.fakeCursor = Qt.point(0, 20); probe.pointer(60, 400); probe.pointer(20, 400); probe.leave() },
          expect: () => !hoverPeek.open },
        { name: "Ctrl+B pins again", focus: "document.activeElement.blur()", wait: 1200,
          key: Qt.Key_B, mods: ctrl, expect: () => app.railPinned && !hoverPeek.open && !app.railMoving },
        // a rail row with the button held on it (PLAN.md 3.1)
        { name: "the button held on the current page's row: the 22 % pressed wash", wait: 300,
          act: () => { const p = check.rowCentre("p:" + session.currentPage); probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton) },
          expect: () => Qt.colorEqual(check.rowItem("p:" + session.currentPage).washColor, Theme.rowPressed) },
        { name: "released, it is the current row's 14 % again", wait: 300,
          act: () => { const p = check.rowCentre("p:" + session.currentPage); probe.pointer(p.x, p.y); probe.pointer(700, 400) },
          expect: () => Qt.colorEqual(check.rowItem("p:" + session.currentPage).washColor, Theme.rowCurrent) },
        { group: "scrollbar" },
        // The floating scrollbar (PLAN.md 3.1). Pinned, the page spans x 300-1274, y 6-794 (PLAN.md 3.19); the pill
        // (hovered) is x 1262-1270, and only the pill takes presses.
        { name: "a long page: no root scrollbar lane, even against its own scrollbar styles; inner areas keep theirs", wait: 2000,
          act: () => app.go(check.long(true), "navigate"),
          expect: () => pageScroll.scrollable && !pageScroll.showing,
          page: "JSON.stringify([innerWidth - fixed.offsetWidth, inner.offsetWidth - inner.clientWidth])",
          pageExpect: v => { const r = JSON.parse(v); return r[0] === 0 && r[1] > 0 } },
        { name: "contentsSize and scrollPosition are in the page's CSS px", expect: () => true,
          page: "JSON.stringify([document.documentElement.scrollHeight, innerHeight])",
          pageExpect: v => { const r = JSON.parse(v); return Math.abs(pageScroll.contentH - r[0]) <= 1 && Math.abs(pageScroll.viewportH - r[1]) <= 1 } },
        { name: "the page scrolling shows the pill, placed by the scroll position", wait: 300,
          act: () => view.runJavaScript("scrollTo(0, 2000)"),
          expect: () => pageScroll.showing && pageScroll.visible && Math.abs(pageScroll.scrollY - 2000) < 1
              && Math.abs(pageScroll.pillY - (12 + (pageScroll.trackH - pageScroll.pillH) * 2000 / pageScroll.maxScroll)) <= 1 },
        { name: "it fades out 1 s after the scrolling stops", wait: 1500, expect: () => !pageScroll.visible },
        { name: "the pointer near the right edge shows it, and on its column it widens", wait: 400,
          act: () => probe.pointer(1266, 400), expect: () => pageScroll.visible && pageScroll.wide },
        { name: "dragging the pill 100 px scrolls the page in proportion", wait: 500,
          act: () => {
              const y = pageScroll.mapToItem(app.contentItem, 0, pageScroll.pillY + pageScroll.pillH / 2).y;
              check.expected = 2000 + 100 * pageScroll.maxScroll / (pageScroll.trackH - pageScroll.pillH);
              probe.pointer(1266, y); probe.pointer(1266, y, Qt.LeftButton);
              for (let d = 10; d <= 100; d += 10)
                  probe.pointer(1266, y + d, Qt.LeftButton);
              probe.pointer(1266, y + 100);
              // released, the pill stays where the drag left it until the page catches up
              check.held = !pageScroll.dragging && Math.abs(pageScroll.scrollY - check.expected) <= 1;
          },
          expect: () => check.held && !pageScroll.dragging && !pageScroll.settling, page: "scrollY", pageExpect: v => Math.abs(v - check.expected) <= 1 },
        { name: "a click in the pill's column 100 px below it, the bar showing, reaches the page and scrolls nothing", wait: 500,
          act: () => {
              check.expected = view.scrollPosition.y;
              const y = pageScroll.mapToItem(app.contentItem, 0, pageScroll.pillY + pageScroll.pillH + 100).y;
              probe.pointer(1266, y); probe.pointer(1266, y, Qt.LeftButton); probe.pointer(1266, y);
          },
          expect: () => pageScroll.showing, page: "JSON.stringify([scrollY, clicks])",
          pageExpect: v => { const r = JSON.parse(v); return Math.abs(r[0] - check.expected) <= 1 && r[1].join() === "966" } },
        { name: "clicks beside the pill and in the 4 px past it reach the page; the pill's did not", wait: 300,
          act: () => {
              probe.pointer(1252, 400); probe.pointer(1252, 400, Qt.LeftButton); probe.pointer(1252, 400);
              probe.pointer(1272, 400); probe.pointer(1272, 400, Qt.LeftButton); probe.pointer(1272, 400);
              probe.pointer(700, 400);
          },
          expect: () => true, page: "clicks.join()", pageExpect: v => v === "966,952,972" },
        { name: "a quirks-mode page: no root scrollbar lane either", wait: 2000,
          act: () => app.go(check.long(false), "navigate"),
          expect: () => pageScroll.scrollable,
          page: "JSON.stringify([document.compatMode, innerWidth - fixed.offsetWidth])",
          pageExpect: v => { const r = JSON.parse(v); return r[0] === "BackCompat" && r[1] === 0 } },
        { group: "loading" },
        { setup: true, name: "(a page to stay on: the long page)", wait: 2000, act: () => app.go(check.long(false), "navigate"),
          expect: () => view.title === "long" && !view.loading },
        // Loading and https-first (PLAN.md 3.8), against EngineCheck::serve, where /slow never answers, /empty
        // closes with no reply and an https attempt cannot connect. The pinned rail's address card is 40 px on one line.
        { name: "the fixture server runs", wait: 100, act: () => check.serveFixtures(), expect: () => check.port > 0 },
        { name: "a load the server does not answer: its host at once, the old page stays on screen", wait: 300,
          act: () => app.go(check.served("slow", "/slow"), "navigate"),
          expect: () => view.loading && String(view.url) === check.served("slow", "/slow") && view.visible && card() === 40,
          page: "document.title", pageExpect: v => v === "long" },
        { name: "8 s under 30 %: the card grows a second line, Waiting for slow.test", wait: 7900,
          expect: () => view.waitingFor === "slow.test:" + check.port && view.loadProgress < 30 && card() > 40 },
        { name: "Esc stops it (P key); the card is one line again", focus: "document.activeElement.blur()",
          key: Qt.Key_Escape, wait: 400, expect: () => !view.loading && view.waitingFor === "" && card() === 40 },
        // A suggestion row that comes under a resting pointer is not the current row; a move makes it so.
        { name: "(the card once, to see where its last row comes)", key: Qt.Key_L, mods: ctrl, wait: 900, act: () => probe.leave(),
          expect: () => { check.rowAt = Qt.point(address.toX + address.toWidth / 2, address.toY + address.fullHeight - 68); return address.editing && address.rows.length > 3 } },
        { name: "(Esc; the pointer comes to rest there, over the page)", key: Qt.Key_Escape, wait: 900, act: () => probe.pointer(check.rowAt.x, check.rowAt.y),
          expect: () => !address.out },
        { name: "Ctrl+L under the resting pointer: row 1 stays the row Enter picks", key: Qt.Key_L, mods: ctrl, wait: 900,
          expect: () => address.editing && address.current === 0 },
        { name: "a move of the pointer makes the row under it the current one", wait: 300, act: () => probe.pointer(check.rowAt.x + 4, check.rowAt.y),
          expect: () => address.current === address.rows.length - 1 },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 900, act: () => probe.leave(), expect: () => !address.out },
        { name: "a scheme-less address typed in the card", wait: 200,
          act: () => { probe.leave(); check.starts = []; address.open("plain.test:" + check.port + "/login") }, expect: () => address.editing },
        { name: "tries https first; that cannot connect, so it loads over http, leaving no history entry for the attempt",
          key: Qt.Key_Return, wait: 1000,
          expect: () => String(view.url) === check.served("plain", "/login") && !view.loading && view.settings.errorPageEnabled
              && check.starts.join() === ["https://plain.test:" + check.port + "/login", check.served("plain", "/login")].join()
              && check.historyUrls(view).every(u => !u.startsWith("https:")) },
        { name: "a password field on the http page takes the focus: the card grows the note", focus: "pw.focus()", wait: 700,
          expect: () => view.passwordFocused && card() > 40 },
        { name: "leaving the field takes the note away", focus: "pw.blur()", wait: 700,
          expect: () => !view.passwordFocused && card() === 40 },
        // the poll asks the page only while the page has the keys
        { name: "(the field again: the note)", focus: "pw.focus()", wait: 700, expect: () => view.passwordFocused },
        { name: "the keys in the address card: the field has no focus, so no note", key: Qt.Key_L, mods: ctrl, wait: 700, act: () => probe.leave(),
          expect: () => address.editing && !view.passwordFocused },
        { name: "back on the page the field has it again, and the note", key: Qt.Key_Escape, wait: 900, expect: () => !address.editing && view.passwordFocused },
        { name: "the window loses the focus to another app: no note", wait: 700, act: () => probe.away(), expect: () => !view.passwordFocused },
        { name: "(back, and out of the field)", focus: "pw.blur()", wait: 700, act: () => probe.back(), expect: () => !view.passwordFocused && card() === 40 },
        { name: "Back goes to the page before it, not to the failed attempt", wait: 1000, act: () => view.goBack(),
          expect: () => !view.loading, page: "document.title", pageExpect: v => v === "long" },
        { name: "a scheme-less address in the new-page bar", wait: 200,
          act: () => { check.starts = []; newPageBar.show("plain.test:" + check.port + "/plain") }, expect: () => newPageBar.opened },
        { name: "its new page falls back the same way, with nothing to go back to", key: Qt.Key_Return, wait: 1000,
          expect: () => String(view.url) === check.served("plain", "/plain") && !view.loading && !view.canGoBack
              && check.starts.length === 2 && view.drawn },
        { name: "a new page whose server does not answer: its view stays under the terminal ground", wait: 500,
          act: () => app.go(check.served("slow", "/slow"), "new", "", "slow"),
          expect: () => view.loading && view.loadProgress === 0 && !view.drawn && view.visible },
        { name: "Esc stops it; with nothing drawn the ground stays", key: Qt.Key_Escape, wait: 300,
          expect: () => !view.loading && !view.drawn },
        { name: "a load that makes progress shows the view", wait: 1000, act: () => view.url = check.served("plain", "/plain"),
          expect: () => !view.loading && view.drawn },
        // /empty stands in for an https side that answers with nothing: the attempt's own address is not what is checked
        { name: "an attempt that fails short of an answer from the site (ERR_EMPTY_RESPONSE, not a connection error) falls back to http too",
          wait: 1000, act: () => { check.starts = []; app.go(check.served("plain", "/empty"), "navigate", "", "", "", false, check.served("plain", "/login")) },
          expect: () => String(view.url) === check.served("plain", "/login") && view.title === "login" && !view.loading && !view.failure
              && view.settings.errorPageEnabled && check.starts.join() === [check.served("plain", "/empty"), check.served("plain", "/login")].join() },
        // silent.test's https side takes the connection and never answers, as a host that drops port 443
        { name: "a typed address whose https side never answers", wait: 200,
          act: () => { probe.leave(); check.starts = []; address.open("silent.test:" + check.port + "/plain") }, expect: () => address.editing },
        { name: "at 2.5 s it still waits on the https attempt", key: Qt.Key_Return, wait: 2500,
          expect: () => view.loading && check.starts.join() === "https://silent.test:" + check.port + "/plain" },
        // the http load takes the pending attempt's place: Qt WebEngine reports no start of its own for it, CEF one
        { name: "3 s without an answer: it loads over http, as Chrome falls back, with no history entry for the attempt", wait: 1100,
          expect: () => String(view.url) === check.served("silent", "/plain") && view.title === "plain" && !view.loading && !view.failure
              && view.settings.errorPageEnabled && check.historyUrls(view).every(u => !u.startsWith("https:"))
              && [["https://silent.test:" + check.port + "/plain"].join(), ["https://silent.test:" + check.port + "/plain", check.served("silent", "/plain")].join()]
                     .indexOf(check.starts.join()) >= 0 },
        // A host whose https side takes the handshake and is slow to answer: the check says the browser's own
        // handshake completed (silent.test's never does), with the no-reply limit lowered to 5 s.
        { name: "the same address again, its https side taking the handshake this time", wait: 200,
          act: () => { view.replyLimit = 5000; probe.leave(); check.starts = []; address.open("silent.test:" + check.port + "/plain") }, expect: () => address.editing },
        { name: "past 3 s it still waits on https, as any load", key: Qt.Key_Return, wait: 3500,
          act: () => Facts.tlsFound("silent.test", check.port, { protocol: "TLS 1.3" }),
          expect: () => view.loading && view.attemptAnswered && check.starts.join() === "https://silent.test:" + check.port + "/plain" },
        { name: "no reply within the limit: the no-reply page for the https address; nothing was sent over http", wait: 2500,
          expect: () => view.failure && view.failure.kind === "noReply" && view.failure.url === "https://silent.test:" + check.port + "/plain"
              && !view.loading && view.fallback === "" && view.settings.errorPageEnabled && check.starts.join() === "https://silent.test:" + check.port + "/plain" },
        { name: "(the limit back at 30 s; Go back)", wait: 300, act: () => { view.replyLimit = 30000; view.leave(true) },
          expect: () => !view.failure && view.title === "plain" },
        { group: "asks" },
        check.server,
        // a thread to look away to; the closes at the end take the asking page and two more, and need one left
        { setup: true, name: "(a thread of three pages)", wait: 100,
          act: () => { const t = session.newThread("other"); for (let i = 0; i < 3; i++) session.addPage(t, check.plain, "") },
          expect: () => session.threads.length >= 2 && Object.keys(session.pages).length >= 4 },
        // Asks (PLAN.md 3.8), from a page on this machine (a secure context, so it may ask) after a click on
        // its button (check.click); the keys go in through the window system. The ask comes out of the page's left edge
        // as a sheet (AskSheet, 2026-10-16); the pinned rail's card stays 40 px.
        { name: "a page that asks", wait: 1500, act: () => app.go(check.local("/asks"), "navigate"),
          expect: () => !view.loading && view.title === "asks" && !view.ask },
        { name: "a click asks for the microphone: its sheet comes out of the page's edge, the card stays, the row gets its ●", wait: 800,
          focus: "act = mic", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "microphone" && check.askText() === "Wants to use your microphone"
              && check.sheetOut() && card() === 40 && session.current.needsYou },
        { name: "F6 reaches the ask, Tab moves to Deny, Enter picks it: refused, and the keys go back to the page", wait: 600,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && check.sheetIn() && card() === 40 && !session.current.needsYou && view.activeFocus,
          page: "log.join()", pageExpect: v => /^mic (NotAllowed|Abort)Error$/.test(v) },
        { name: "Deny lasts for this page load: asking again is refused with no ask", wait: 600, act: () => check.click(),
          expect: () => !view.ask, page: "log.join()", pageExpect: v => /^mic (NotAllowed|Abort)Error,mic (NotAllowed|Abort)Error$/.test(v) },
        { name: "a click asks to show notifications", wait: 800, focus: "act = notify", act: () => check.click(),
          expect: () => view.ask && check.askText() === "Wants to show notifications" },
        { name: "Esc on the ask is Deny", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) },
          expect: () => !view.ask, page: "log.join()", pageExpect: v => v.endsWith("notify denied") },
        { name: "a reload starts the page load afresh", wait: 1500, act: () => view.reload(), expect: () => !view.loading && view.title === "asks" },
        { name: "the notification ask comes again", wait: 800, focus: "act = notify", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "notifications" },
        { name: "Allow once (F6, Enter on the first button) grants it", wait: 500,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask, page: "log.join()", pageExpect: v => v === "notify granted" },
        { name: "Allow once lasts for this page load: asked again without a click, granted with no ask", wait: 500, focus: "notify()",
          expect: () => view.asks.length === 0, page: "log.join()", pageExpect: v => v === "notify granted,notify granted" },
        { name: "reloaded, a notification ask made without a click gets only the bell", wait: 1500, act: () => view.reload(),
          expect: () => view.title === "asks" },
        { name: "(asked without a click)", wait: 600, focus: "notify()",
          expect: () => view.asks.length === 1 && !!view.quietAsk && !view.ask && card() === 40 && check.sheetIn() && !session.current.needsYou },
        { name: "a click on the bell at the card's right brings the ask out, in its sheet", wait: 700, act: () => check.clickBell(),
          expect: () => view.ask && view.ask.types.join() === "notifications" && check.sheetOut() },
        { name: "(Esc denies it)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) },
          expect: () => view.asks.length === 0 },
        // the link's app is looked up (Apps.lookUp, xdg-mime) before its ask queues: over 1.2 s on the Book4
        { name: "a location ask and a link to another app from one click queue in one sheet: 1 of 2", wait: 4000,
          focus: "act = () => { where(); location.href = 'browsercheck:hello' }", act: () => check.click(),
          expect: () => view.askCount === 2 && view.ask.kind === "permission" && check.section().count === 2 && check.askText() === "Wants to know your location" },
        { name: "answered, the next shows with the keys still on it: No app opens browsercheck: links", wait: 600,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => view.askCount === 1 && view.ask.kind === "external" && check.askText() === "No app opens browsercheck: links" && app.askSheet.section.activeFocus,
          page: "log.join()", pageExpect: v => v.endsWith("where 1") },
        { name: "Cancel (Tab, Enter): nothing opened, by the browser or by Qt", wait: 400,
          act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && Apps.lastOpened === "" && probe.qtLaunches().length === 0 && view.activeFocus },
        { name: "a link to a scheme with a default app asks to open it in that app", wait: 1000,
          focus: "act = () => location.href = 'browsercheckapp:hello'", act: () => { probe.fakeApp("browsercheckapp", "Check App"); check.click() },
          expect: () => view.ask && check.askText() === "Wants to open a browsercheckapp: link in Check App"
              && check.section().model.lines[1].text === "(default app for browsercheckapp:)" },
        { name: "Open hands the link to the app (a dry run here); Qt launched nothing itself", wait: 400,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && Apps.lastOpened === "browsercheckapp:hello" && probe.qtLaunches().length === 0 },
        { name: "reloaded, with lasting choices set (the site panel's): Allow and Block answer at once", wait: 1500,
          act: () => { view.sites.setChoice(check.origin(), "notifications", "allow"); view.sites.setChoice(check.origin(), "location", "block"); view.reload() },
          expect: () => view.title === "asks" },
        { name: "(asked without a click, no ask, no bell)", wait: 700, focus: "notify(); where()",
          expect: () => view.asks.length === 0, page: "log.slice().sort().join()", pageExpect: v => v === "notify granted,where 1" },
        // Chromium asks for the source first (desktopMediaRequested); here it finds no screen or window
        { name: "a screen share after a click asks for what to share; with nothing found, only Cancel", wait: 1000,
          act: () => { view.sites.setChoice(check.origin(), "notifications", ""); view.sites.setChoice(check.origin(), "location", ""); check.click() },
          focus: "act = share",
          expect: () => view.ask && view.ask.kind === "screen" && check.askText() === "Wants to share your screen"
              && check.section().model.buttons.map(b => b.label).join() === "Cancel" },
        { name: "Cancel refuses it", wait: 800, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask, page: "log.join()", pageExpect: v => /share (NotAllowed|Abort)Error$/.test(v) },
        { name: "Screen sharing Blocked in the site panel: a share is refused with no picker", wait: 800,
          act: () => { view.sites.setChoice(check.origin(), "screen", "block"); check.click() },
          expect: () => view.asks.length === 0, page: "log.join()", pageExpect: v => /share (NotAllowed|Abort)Error,share (NotAllowed|Abort)Error$/.test(v) },
        { name: "(Screen sharing back to Ask)", wait: 100, act: () => view.sites.setChoice(check.origin(), "screen", ""),
          expect: () => view.sites.choice(check.origin(), "screen") === "" },
        // sources that come and go under a waiting screen-share ask (a stand-in ask: offscreen lists none)
        { name: "a source found above the picked one: the pick stays on its row", wait: 200,
          act: () => {
              view.asks = [{ id: 99, kind: "screen", host: check.origin().slice(7), options: ["Entire screen · A", "Window · foot"], screens: 1 }];
              check.section().picked = 1;
              view.replace(view.asks[0], Object.assign({}, view.asks[0], { options: ["Entire screen · A", "Window · Code", "Window · foot"] }));
          },
          expect: () => check.section().picked === 2 },
        { name: "the picked source gone: nothing is picked, and Share does nothing", wait: 200,
          act: () => {
              view.replace(view.asks[0], Object.assign({}, view.asks[0], { options: ["Entire screen · A", "Window · Code"] }));
              check.section().pick("share");
          },
          expect: () => check.section().picked === -1 && view.askCount === 1 },
        { name: "(the stand-in goes)", wait: 200, act: () => view.asks = [], expect: () => !view.ask },
        { name: "a denial is not kept past the page load: reloaded, the page is asked again", wait: 1500, act: () => view.reload(),
          expect: () => view.title === "asks" },
        { name: "(notifications, denied in an earlier load, ask again)", wait: 800, focus: "act = notify", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "notifications" },
        { name: "(Allow once)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask, page: "log.join()", pageExpect: v => v === "notify granted" },
        { name: "nor a grant: reloaded, asked again", wait: 1500, act: () => view.reload(), expect: () => view.title === "asks" },
        { name: "(notifications ask again)", wait: 800, focus: "act = notify", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "notifications" },
        { name: "(Esc)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) }, expect: () => !view.ask },
        { name: "the page on another origin (localhost)", wait: 1500,
          act: () => app.go("http://localhost:" + check.port + "/asks", "navigate"), expect: () => view.title === "asks" },
        { name: "an ask on a page you leave waits behind its row's ●", wait: 800, focus: "act = mic",
          act: () => { check.asker = session.currentPage; check.click() }, expect: () => view.ask && session.pages[check.asker].needsYou },
        { name: "(another page on screen: no sheet)", wait: 700,
          act: () => app.show(session.threads.find(t => t.pages.indexOf(check.asker) < 0).pages[0]),
          expect: () => session.currentPage !== check.asker && !view.ask && check.sheetIn() && session.pages[check.asker].needsYou },
        { name: "back on the page, its sheet shows the ask", wait: 700, act: () => app.show(check.asker),
          expect: () => view.ask && check.sheetOut() },
        { name: "Ctrl+L: the sheet steps aside, the ask waits, the card's last line names it", key: Qt.Key_L, mods: ctrl, wait: 700, act: () => probe.leave(),
          expect: () => address.editing && address.waiting === "localhost:" + check.port && check.sheetIn() },
        { name: "Esc: the ask's sheet is back", key: Qt.Key_Escape, wait: 700,
          expect: () => !address.editing && view.ask && check.sheetOut() },
        // folded (PLAN.md 3.5): the ask's sheet comes out of the page's edge as when docked; the overlay stays in
        { name: "folded, the ask's sheet stays out at the page's edge; the overlay stays in, the keys on the page", wait: 1500,
          act: () => app.railPinned = false,
          expect: () => !app.railPinned && !hoverPeek.held && !hoverPeek.out && check.sheetOut() && check.section().model !== null && view.activeFocus },
        { name: "a click on the page leaves it out: the ask waits for its answer", wait: 700, act: () => check.click(700),
          expect: () => view.ask && check.sheetOut() && !hoverPeek.out },
        { name: "Ctrl+L grows the card out of the handle; the sheet steps aside and the ask waits on the card's last line", key: Qt.Key_L, mods: ctrl, wait: 900,
          act: () => probe.leave(),
          expect: () => address.editing && address.waiting === "localhost:" + check.port && check.sheetIn() },
        { name: "Esc: the card goes back into the handle, and the ask's sheet comes out again", key: Qt.Key_Escape, wait: 900,
          expect: () => !address.out && view.ask && check.sheetOut() && !hoverPeek.out },
        { name: "F6 reaches it there; Esc denies, and the sheet slides back", wait: 900,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) },
          expect: () => !view.ask && check.sheetIn() && !hoverPeek.out,
          page: "log.join()", pageExpect: v => /mic (NotAllowed|Abort)Error$/.test(v) },
        { name: "Ctrl+L with the overlay in: the card grows out of the handle", key: Qt.Key_L, mods: ctrl, wait: 900, act: () => probe.leave(),
          expect: () => address.editing && !address.from.rest && !hoverPeek.out },
        // a stand-in ask, as BrowserView queues one
        { name: "an ask that comes meanwhile waits on the card's last line; no sheet yet", wait: 700, act: () => view.asks = [check.standInAsk()],
          expect: () => view.ask && address.waiting === view.ask.host && check.sheetIn() && !hoverPeek.out },
        { name: "Esc: the card goes back into the handle and the ask's sheet comes out", key: Qt.Key_Escape, wait: 1000,
          expect: () => !address.out && check.sheetOut() && !hoverPeek.out },
        { name: "(the stand-in ask goes, and its sheet slides back)", wait: 900, act: () => view.asks = [], expect: () => check.sheetIn() },
        { name: "Ctrl+B pins again", focus: "document.activeElement.blur()", key: Qt.Key_B, mods: ctrl, wait: 1200, expect: () => app.railPinned },
        // Loads that replace no document keep the page load's asks and answers: a link from an Always page to
        // another site (refused there; it opens a thread of one) and a file link (a download).
        { name: "an Always page that asks", wait: 1500,
          act: () => { check.alwaysPage = session.addAlways(check.local("/asks"), "asks"); app.show(check.alwaysPage) },
          expect: () => session.currentPage === check.alwaysPage && view.title === "asks" && !view.loading },
        { name: "(its microphone asked for)", wait: 800,
          focus: "navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { window.s = s; log.push('mic ok') }, e => log.push('mic ' + e.name))",
          expect: () => view.ask && view.ask.types.join() === "microphone" },
        { name: "(Allow once: it records, the row shows it)", wait: 800, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && session.pages[check.alwaysPage].capturing === "mic", page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        { name: "(a notification ask made without a click waits as the bell)", wait: 600, focus: "notify()",
          expect: () => view.asks.length === 1 && !!view.quietAsk },
        { name: "a link from it to another site opens a thread of one; the Always page keeps its bell ask, its microphone and Allow once", wait: 1500,
          focus: () => "const a = document.createElement('a'); a.href = 'http://localhost:" + check.port + "/plain'; document.body.appendChild(a); a.click()",
          expect: () => { const v = app.views[check.alwaysPage]; check.outPage = session.currentPage;
                          return check.outPage !== check.alwaysPage && view.title === "plain" && String(v.url) === check.local("/asks") && !!v.quietAsk
                              && session.pages[check.alwaysPage].capturing === "mic" && v.thisLoad[check.local("") + " microphone"] === "allow" },
          pageIn: () => app.views[check.alwaysPage], page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        { name: "back on it, a click on the bell brings that ask out", wait: 700,
          act: () => { app.show(check.alwaysPage); check.later(() => check.clickNamed(rail.addressField, "bellGlyph")) },
          expect: () => view.ask && view.ask.types.join() === "notifications" },
        { name: "and Allow once still reaches the page", wait: 600, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask, page: "log.join()", pageExpect: v => v.endsWith("notify granted") },
        { name: "(a location ask waits)", wait: 800, focus: "where()", expect: () => view.ask && view.ask.types.join() === "location" },
        { name: "a file link on it: the file downloads, and the page keeps its location ask and Allow once", wait: 1500,
          focus: "location.href = '/file/always.bin?size=2000'",
          expect: () => { const d = check.lastDownload();
                          return d.file === "always.bin" && d.page === check.alwaysPage && view.title === "asks" && view.ask && view.ask.types.join() === "location"
                              && view.thisLoad[check.local("") + " microphone"] === "allow" } },
        // Qt WebEngine reset the grant as the file link's load started, which ended the stream; Chromium (CEF) keeps a
        // stream through a download. Either way the page's Allow once answers the next ask.
        { name: "asked again after the file link, Allow once answers with no ask (the old stream ended on Qt WebEngine, kept on CEF)", wait: 800,
          focus: "window.old = s; navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { window.s = s; log.push('mic again') }, e => log.push('mic ' + e.name))",
          expect: () => view.askCount === 1 && view.ask.types.join() === "location" && session.pages[check.alwaysPage].capturing === "mic",
          page: "JSON.stringify([old.getTracks()[0].readyState, log.indexOf('mic again') >= 0])", pageExpect: v => v === '["ended",true]' || v === '["live",true]' },
        { name: "(Esc denies the location ask; the file, the Always cell and the page it opened go)", wait: 1500,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0); downloads.act(check.lastDownload().id, "delete");
                       app.command("removeAlways", check.alwaysPage); app.closePage(check.outPage) },
          expect: () => !session.pages[check.alwaysPage] && !session.pages[check.outPage] && !session.downloads.some(d => d.file === "always.bin") },
        // A file from another origin: that load keeps no grant, so nothing is reset and the stream goes on
        { name: "(a page that records, in a thread of its own)", wait: 1500,
          act: () => { check.other = session.currentPage; app.go(check.local("/asks"), "new", "", "grants"); check.asker = session.currentPage },
          expect: () => view.title === "asks" && !view.loading && session.current.thread !== "" },
        { name: "(its microphone asked for)", wait: 800,
          focus: "navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { window.s = s; log.push('mic ok') }, e => log.push('mic ' + e.name))",
          expect: () => view.ask && view.ask.types.join() === "microphone" },
        { name: "(Allow once)", wait: 800, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && session.current.capturing === "mic", page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        { name: "a file link to another origin: the file downloads, and the microphone goes on", wait: 1500,
          focus: () => "location.href = 'http://localhost:" + check.port + "/file/other.bin?size=2000'",
          expect: () => { const d = check.lastDownload(); return d.file === "other.bin" && d.state === "done" && view.title === "asks" && session.current.capturing === "mic" },
          page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        // a load of another origin that never commits (here stopped before its reply) leaves the page as it was
        { name: "a link to another origin that has not answered: the page records on, and its glyph and row mark stay", wait: 800,
          focus: () => "location.href = '" + check.served("slow", "/slow") + "'",
          expect: () => view.loading && session.current.capturing === "mic" && view.inUse.join() === "microphone",
          page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        { name: "Esc stops it: still recording, with the mark and its Allow once", focus: "document.activeElement.blur()", key: Qt.Key_Escape, wait: 400,
          expect: () => !view.loading && view.title === "asks" && session.current.capturing === "mic" && view.answered.length === 1
              && view.thisLoad[check.local("") + " microphone"] === "allow",
          page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        { name: "a reload ends that Allow once: the mark goes", wait: 1500, act: () => view.reload(),
          expect: () => view.title === "asks" && !view.loading && session.current.capturing === "" },
        { name: "and the grant with it: the microphone is asked for afresh", wait: 800,
          focus: "navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { window.s = s; log.push('mic ok') }, e => log.push('mic ' + e.name))",
          expect: () => view.ask && view.ask.types.join() === "microphone", page: "log.join()", pageExpect: v => v === "" },
        { name: "(Allow once: it records again)", wait: 800, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && session.current.capturing === "mic", page: "s.getTracks()[0].readyState", pageExpect: v => v === "live" },
        { name: "(a page of that other origin)", wait: 1500, act: () => app.go("http://localhost:" + check.port + "/plain", "navigate"),
          expect: () => view.title === "plain" && !view.loading && session.current.capturing === "" },
        { name: "(this origin again)", wait: 1500, act: () => app.go(check.local("/asks"), "navigate"), expect: () => view.title === "asks" && !view.loading },
        { name: "the engine kept no grant across those loads: the microphone is asked for afresh", wait: 800,
          focus: "navigator.mediaDevices.getUserMedia({ audio: true }).then(s => log.push('mic ok'), e => log.push('mic ' + e.name))",
          expect: () => view.ask && view.ask.types.join() === "microphone", page: "log.join()", pageExpect: v => v === "" },
        { name: "(Esc denies it; the file deleted, the page closed, back on the page before it)", wait: 800,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0); downloads.act(session.downloads.find(d => d.file === "other.bin").id, "delete");
                       app.closePage(check.asker); app.show(check.other) },
          expect: () => !session.pages[check.asker] && session.currentPage === check.other && !session.downloads.some(d => d.file === "other.bin") },
        // the sign-in holds the load: nothing times out while it waits
        { name: "(the no-reply limit lowered to 1 s)", wait: 100, act: () => view.replyLimit = 1000, expect: () => view.replyLimit === 1000 },
        { name: "a page behind HTTP sign-in: the card asks, saying the password goes unencrypted", wait: 1500,
          act: () => app.go(check.served("router", "/auth"), "navigate"),
          expect: () => view.ask && view.ask.kind === "signin" && check.askText() === "Sign in to router.test:" + check.port
              && check.section().model.notes.join() === "Sent without encryption" },
        { name: "left waiting past the no-reply limit and 8 s: still loading, no failure, not Waiting for", wait: 7500,
          expect: () => view.loading && !view.failure && view.waitingFor === "" && view.ask && view.ask.kind === "signin" },
        { name: "typed into its fields (F6, Tab), Enter signs in", wait: 1500,
          act: () => { probe.press(Qt.Key_F6, 0); check.type("admin"); probe.press(Qt.Key_Tab, 0); check.type("secret"); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && !view.loading && view.title === "signed in" },
        { name: "(the limit back at 30 s)", wait: 100, act: () => view.replyLimit = 30000, expect: () => view.replyLimit === 30000 },
        { name: "a page with a beforeunload handler, typed into", wait: 1500,
          act: () => { app.go(check.local("/leave"), "navigate"); check.leaver = session.currentPage },
          expect: () => view.title === "leave" },
        { name: "(typing)", focus: "f.focus()", key: Qt.Key_X, text: "x", wait: 300, expect: () => true },
        { name: "Ctrl+W asks Leave this page?; the page stays until answered", key: Qt.Key_W, mods: ctrl, wait: 800,
          expect: () => view.ask && view.ask.kind === "leave" && check.askText() === "Leave this page?" && !!session.pages[check.leaver] },
        { name: "Stay (Tab, Enter): the page stays", wait: 500,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && session.currentPage === check.leaver && !view.closing },
        { name: "Delete in the rail list (F6, F6) asks too", wait: 800,
          act: () => { probe.leave(); probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Delete, 0) },
          expect: () => view.ask && view.ask.kind === "leave" && !!session.pages[check.leaver] },
        { name: "Stay (F6, F6, Tab, Enter): the rail no longer waits on that close", wait: 500,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && session.currentPage === check.leaver && rail.closingFromList === null },
        { name: "an address typed on it asks too", wait: 200, act: () => address.open("plain.test:" + check.port + "/plain"), expect: () => address.editing },
        { name: "(Enter)", key: Qt.Key_Return, wait: 800, expect: () => view.ask && view.ask.kind === "leave" && !address.editing },
        { name: "Stay: that load never starts, and its https attempt goes with it", wait: 500,
          act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && view.title === "leave" && !view.loading && view.fallback === "" && view.settings.errorPageEnabled },
        { name: "a reload asks too", wait: 800, act: () => view.reload(), expect: () => view.ask && view.ask.kind === "leave" },
        { name: "Leave reloads it", wait: 1500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.ask && !view.loading && view.title === "leave", page: "f.value", pageExpect: v => v === "" },
        { name: "(typing again)", focus: "f.focus()", key: Qt.Key_X, text: "x", wait: 300, expect: () => true },
        { name: "Ctrl+W, then Leave: the page closes", key: Qt.Key_W, mods: ctrl, wait: 800, expect: () => view.ask && view.ask.kind === "leave" },
        { name: "(Leave): the keys go to the next page, not the rail list", wait: 800, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !session.pages[check.leaver] && session.currentPage !== check.leaver && !rail.listFocused && view.activeFocus },
        { name: "Ctrl+W on a page with no beforeunload handler closes it at once", wait: 400,
          act: () => { check.leaver = session.currentPage; probe.press(Qt.Key_W, ctrl) }, expect: () => !session.pages[check.leaver] },
        { name: "Delete in the rail list (F6, F6) closes the page there, the list keeping the keys", wait: 600,
          act: () => { probe.leave(); check.leaver = session.currentPage; probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Delete, 0) },
          expect: () => !session.pages[check.leaver] && rail.listFocused && !address.editing },
        { name: "Esc goes back to the page", key: Qt.Key_Escape, wait: 300, expect: () => !rail.listFocused && view.activeFocus },
        { group: "dialogs" },
        check.server,
        // The page's dialogs (PLAN.md 8j), opened from a timer so the check's own script returns; while one
        // is open the page runs no script, so those steps look only at the browser.
        { name: "a page with dialogs", wait: 1500, act: () => app.go(check.local("/dialogs"), "navigate"), expect: () => view.title === "dialogs" },
        { name: "alert(): drawn over the page, naming the top frame's host; the card says Dialog from this page; it takes the keys",
          wait: 600, focus: "setTimeout(() => { alert('Saved.'); log.push('alert') }, 0)",
          expect: () => view.dialog && view.dialog.type === "alert" && dialog.visible && dialog.shown.says === "127.0.0.1:" + check.port + " says"
              && view.dialog.message === "Saved." && view.dialog.block === "" && card() > 40 && check.stateText() === "Dialog from this page" && dialog.activeFocus },
        { name: "Enter is OK: the dialog goes and the keys go back to the page", key: Qt.Key_Return, wait: 400,
          expect: () => !view.dialog && card() === 40 && view.activeFocus, page: "log.join()", pageExpect: v => v === "alert" },
        { name: "the second dialog in the page load offers to block the rest", wait: 600,
          focus: "setTimeout(() => log.push('confirm ' + confirm('Discard this comment? Your text will be lost.')), 0)",
          expect: () => view.dialog && view.dialog.type === "confirm" && view.dialog.block === "Block more dialogs from 127.0.0.1:" + check.port },
        { name: "Esc is Cancel: confirm() is false", key: Qt.Key_Escape, wait: 400, expect: () => !view.dialog,
          page: "log.join()", pageExpect: v => v.endsWith("confirm false") },
        { name: "prompt(): its field has the keys, the page's default text selected", wait: 600,
          focus: "setTimeout(() => log.push('prompt ' + prompt('Name the branch', 'camss')), 0)",
          expect: () => view.dialog && view.dialog.type === "prompt" && view.dialog.text === "camss" && dialog.activeFocus },
        { name: "typed over and Enter: the page gets the text", wait: 400, act: () => { check.type("lanes"); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.dialog, page: "log.join()", pageExpect: v => v.endsWith("prompt lanes") },
        { name: "a dialog waits on its page while you go elsewhere", wait: 600,
          focus: "setTimeout(() => log.push('confirm ' + confirm('Leave the draft?')), 0)",
          act: () => check.asker = session.currentPage, expect: () => view.dialog && dialog.visible },
        { name: "(another page on screen: no dialog, the rail and the browser as always)", wait: 1000,
          act: () => { check.other = session.addPage(session.newThread("other"), check.plain, ""); app.show(check.other) },
          expect: () => session.currentPage !== check.asker && !view.dialog && !dialog.visible && card() === 40 },
        { name: "back on its page the dialog shows again and takes the keys", wait: 400, act: () => app.show(check.asker),
          expect: () => view.dialog && dialog.visible && dialog.activeFocus },
        { name: "Tab past Cancel and OK to Block more dialogs, Enter: blocked, as Cancel", wait: 400,
          act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.dialog && view.dialogsBlocked, page: "log.join()", pageExpect: v => v.endsWith("confirm false") },
        { name: "blocked, the page load's next dialog returns at once", wait: 400,
          focus: "setTimeout(() => log.push('again ' + confirm('Again?')), 0)",
          expect: () => !view.dialog, page: "log.join()", pageExpect: v => v.endsWith("again false") },
        { name: "a reload lets the page speak again, from a first dialog", wait: 1500, act: () => view.reload(), expect: () => view.title === "dialogs" },
        { name: "(alert, with no offer to block)", wait: 600, focus: "setTimeout(() => alert('Back.'), 0)",
          expect: () => view.dialog && view.dialog.block === "" },
        { name: "(OK)", key: Qt.Key_Return, wait: 400, expect: () => !view.dialog },
        { group: "files" },
        check.server,
        // File inputs (PLAN.md 8l): Files is the Picker's dry run here; answer() plays Choose and Cancel.
        { name: "a page with file inputs", wait: 1500,
          act: () => { check.files = [probe.fixtureFile("notes.txt", "notes"), probe.fixtureFile("shot.png", "png")]; app.go(check.local("/upload"), "navigate") },
          expect: () => view.title === "upload" && check.files.every(f => f !== "") },
        { name: "a click on a file input opens Files; the card says Choosing files in Files", wait: 800, act: () => check.click(),
          expect: () => view.choosing && Picker.busy && Picker.label === "Choose files for 127.0.0.1:" + check.port
              && card() > 40 && check.stateText() === "Choosing files in Files" },
        { name: "Choose with two files: an input without multiple takes the first", wait: 500, act: () => Picker.answer(check.files),
          expect: () => !view.choosing && !Picker.busy && card() === 40, page: "log.join()", pageExpect: v => v === "one notes.txt" },
        { name: "an input with multiple", wait: 800, act: () => check.click(750), expect: () => Picker.busy && view.choosing && view.choosing.mode === "multiple" },
        { name: "takes both", wait: 500, act: () => Picker.answer(check.files), expect: () => !Picker.busy,
          page: "log.join()", pageExpect: v => v.endsWith("many notes.txt+shot.png") },
        { name: "picking again", wait: 800, act: () => check.click(), expect: () => Picker.busy && view.choosing },
        { name: "focus back in the browser with nothing chosen: after 1 s the pick is over, and the page is as it was", wait: 1500,
          act: () => { probe.away(); probe.back() },
          expect: () => !Picker.busy && !view.choosing && card() === 40,
          page: "JSON.stringify([one.files.length && one.files[0].name, log.length])", pageExpect: v => v === '["notes.txt",2]' },
        { name: "(picking again)", wait: 800, act: () => check.click(), expect: () => Picker.busy && view.choosing },
        { name: "a new document there ends the pick, which nothing waits on any more", wait: 1500, act: () => view.reload(),
          expect: () => !view.loading && view.title === "upload" && !view.choosing && !Picker.busy },
        { name: "so a file input on it picks at once", wait: 800, act: () => check.click(), expect: () => Picker.busy && view.choosing },
        { name: "(Cancel)", wait: 500, act: () => Picker.answer([]), expect: () => !Picker.busy && !view.choosing },
        // A file dropped on the page (PLAN.md 8l): the page takes it where it takes drops; elsewhere a text
        // file opens as a new page after this one, and a file of another type does nothing.
        { name: "a page with a drop zone", wait: 1500,
          act: () => { check.files.push(probe.fixtureFile("camss.zip", "zip")); app.go(check.local("/drop"), "navigate"); check.opener = session.currentPage },
          expect: () => view.title === "drop" },
        { name: "dropped on its zone, the page takes the file", wait: 800,
          act: () => { check.rows = Object.keys(session.pages).length; probe.drop(350, 150, check.files[0]) },
          expect: () => session.currentPage === check.opener && Object.keys(session.pages).length === check.rows,
          page: "log.join()", pageExpect: v => v === "zone notes.txt" },
        { name: "dropped where the page takes none, a text file opens as a new page right after it", wait: 1500,
          act: () => probe.drop(900, 500, check.files[0]),
          expect: () => Object.keys(session.pages).length === check.rows + 1 && session.currentPage !== check.opener
              && String(view.url) === "file://" + check.files[0] && session.current.thread === session.pages[check.opener].thread
              && session.threadById(session.current.thread).pages.indexOf(session.currentPage) === session.threadById(session.current.thread).pages.indexOf(check.opener) + 1 },
        { name: "the page it was dropped on stays as it was", wait: 500, act: () => app.show(check.opener),
          expect: () => String(view.url) === check.local("/drop"), page: "log.join()", pageExpect: v => v === "zone notes.txt" },
        { name: "a file of another type does nothing", wait: 1000, act: () => probe.drop(900, 500, check.files[2]),
          expect: () => Object.keys(session.pages).length === check.rows + 1 && session.currentPage === check.opener && String(view.url) === check.local("/drop") },
        { name: "a file: address typed on the page still loads in place", wait: 1000, act: () => app.go("file://" + check.files[0], "navigate"),
          expect: () => session.currentPage === check.opener && String(view.url) === "file://" + check.files[0] },
        { group: "popups" },
        check.server,
        { setup: true, name: "(a page of its own thread, to look away to)", wait: 100,
          act: () => check.other = session.addPage(session.newThread("other"), check.plain, ""), expect: () => !!session.pages[check.other] },
        // Popups (PLAN.md 8k): window.open with a size opens an attached popup in the notch (the signin group); where
        // the notch cannot take it, as here (check mode has no shell), a page right after its opener, which stays its
        // window.opener. Never a window of its own (2026-10-14).
        { name: "a page that opens popups", wait: 1500, act: () => { app.go(check.local("/popup-opener"), "navigate"); check.opener = session.currentPage },
          expect: () => view.title === "opener" },
        { name: "window.open with a size after a click, no notch to take it: a page after its opener in its task, in front, keeping window.opener; no window", wait: 1500,
          focus: "act = sized", act: () => { check.rows = Object.keys(session.pages).length; check.click() },
          expect: () => { const t = session.currentThread;
              return !app.views[check.opener].popup && view.title === "sign in" && Object.keys(session.pages).length === check.rows + 1
                  && t.pages.indexOf(check.opener) >= 0 && t.pages.indexOf(session.currentPage) > t.pages.indexOf(check.opener) },
          page: "String(hasOpener)", pageExpect: v => v === "true" },
        { name: "it closes itself: the page goes, and the opener, back in front with the keys, has its answer", wait: 1200,
          act: () => view.runJavaScript("done()"),
          expect: () => session.currentPage === check.opener && view.activeFocus && Object.keys(session.pages).length === check.rows,
          page: "log.join()", pageExpect: v => v === "message signed in" },
        { name: "window.open without a size joins the thread, as before", wait: 1200, focus: "act = plain", act: () => check.click(),
          expect: () => !view.popup && Object.keys(session.pages).length === check.rows + 1 && session.currentPage !== check.opener && view.title === "plain" },
        { name: "(back on the opener)", wait: 400, act: () => app.show(check.opener), expect: () => view.title === "opener" },
        { name: "a popup without a click from you is refused: no page, no window, the glyph at the card's right", wait: 800,
          focus: "setTimeout(sized, 0)", expect: () => !view.popup && view.blockedPopups === 1 && Object.keys(session.pages).length === check.rows + 1 },
        { name: "(again with a click: the sign-in page)", wait: 1500, focus: "act = sized", act: () => check.click(),
          expect: () => view.title === "sign in" && session.currentPage !== check.opener },
        { name: "Ctrl+W there closes only it; the keys go back to its opener", wait: 1500, act: () => { probe.back(); probe.press(Qt.Key_W, ctrl) },
          expect: () => !!session.pages[check.opener] && session.currentPage === check.opener && view.activeFocus },
        { name: "(the sign-in page once more)", wait: 1500, focus: "act = sized", act: () => check.click(),
          expect: () => { check.signinPage = session.currentPage; return view.title === "sign in" && check.signinPage !== check.opener } },
        { name: "Ctrl+W on the opener closes it alone: the sign-in page is a page of its own", wait: 1500,
          act: () => { app.show(check.opener); check.later(() => { probe.back(); probe.press(Qt.Key_W, ctrl) }) },
          expect: () => !session.pages[check.opener] && !!session.pages[check.signinPage] },
        // Qt WebEngine points a page opened with openIn back into the view that opened it: that view is kept
        // (parked) while the page lives, or the pointer on the page crashed the browser
        { name: "a page the closed opener opened takes the pointer; the opener's view waits, discarded, until they go", wait: 600,
          act: () => { probe.pointer(700, 400); probe.pointer(700, 420); check.click(700) },
          expect: () => (view.title === "plain" || view.title === "sign in") && view.openedBy !== null && view.openedBy.parked
              && view.openedBy.lifecycleState === WebEngineView.LifecycleState.Discarded && !view.openedBy.visible },
        { group: "fullscreen" },
        check.server,
        // Page full screen (PLAN.md 8m); offscreen the screen is smaller than the window.
        { name: "a page that goes full screen", wait: 1500, act: () => app.go(check.local("/full"), "navigate"), expect: () => view.title === "full" },
        { name: "a click asks for full screen: the window goes with it, the rail hidden, Esc exits full screen", wait: 1000, act: () => check.click(),
          expect: () => view.isFullScreen && app.pageFullScreen && app.visibility === Window.FullScreen && !rail.visible
              && screenNotice.shown && screenNotice.text === "Esc exits full screen", page: "log.join()", pageExpect: v => v === "in,entered" },
        { name: "the notice goes after 2 s", wait: 1800, expect: () => !screenNotice.shown && app.pageFullScreen },
        { name: "Esc leaves: the window and the rail as they were", key: Qt.Key_Escape, wait: 800,
          expect: () => !view.isFullScreen && !app.pageFullScreen && app.visibility !== Window.FullScreen && rail.visible
              && app.width === 1280 && app.height === 800, page: "log.join()", pageExpect: v => v.endsWith("left") },
        { name: "(full screen again)", wait: 1000, act: () => check.click(), expect: () => app.pageFullScreen },
        { name: "an ask in page full screen waits: only the notice, is asking · Esc to answer", wait: 800, focus: "mic()",
          expect: () => view.ask && screenNotice.shown && screenNotice.text === "127.0.0.1:" + check.port + " is asking · Esc to answer"
              && !rail.visible && !hoverPeek.out && check.sheetIn() && session.current.needsYou },
        { name: "Esc leaves full screen and the waiting ask's sheet comes out", key: Qt.Key_Escape, wait: 800,
          expect: () => !app.pageFullScreen && rail.visible && view.ask && check.sheetOut() },
        { name: "(F6, Esc: denied)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) }, expect: () => !view.ask },
        { name: "(folded)", wait: 1200, act: () => app.railPinned = false, expect: () => !app.railPinned },
        { name: "(full screen again)", wait: 1000, act: () => check.click(), expect: () => app.pageFullScreen },
        // location: the microphone was denied for this page load, and the site checks count what the origin asked for
        { name: "folded, an ask in page full screen waits behind the notice; the overlay stays in", wait: 800,
          focus: "navigator.geolocation.getCurrentPosition(() => log.push('where ok'), e => log.push('where ' + e.code))",
          expect: () => view.ask && screenNotice.shown && !hoverPeek.out && !peekedRail.visible && check.sheetIn() },
        { name: "Esc leaves full screen, and the ask's sheet comes out; the overlay stays in", key: Qt.Key_Escape, wait: 1000,
          expect: () => !app.pageFullScreen && view.ask && check.sheetOut() && !hoverPeek.out },
        { name: "(F6, Esc: denied, the overlay goes)", wait: 900, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) },
          expect: () => !view.ask && !hoverPeek.out },
        { name: "(Ctrl+B pins again)", focus: "document.activeElement.blur()", key: Qt.Key_B, mods: ctrl, wait: 1200, expect: () => app.railPinned },
        { name: "F11: browser full screen folds the rail", key: Qt.Key_F11, wait: 1200,
          expect: () => app.browserFullScreen && app.visibility === Window.FullScreen && !app.railPinned },
        { name: "F11 again leaves it and pins the rail again, as it was", key: Qt.Key_F11, wait: 1200,
          expect: () => !app.browserFullScreen && app.visibility !== Window.FullScreen && app.railPinned && app.width === 1280 },
        { group: "errors" },
        check.server,
        // The browser's own failure pages (PLAN.md 3.8 8f-8i), drawn over the view. No step reads a stopped
        // page's script: a page without its process never answers.
        { name: "the fixture server over TLS (a self-signed cert.test), and a port nothing listens on", wait: 100,
          act: () => { check.tlsPort = probe.serveTls(); check.closed = probe.closedPort() }, expect: () => check.tlsPort > 0 && check.closed > 0 },
        { name: "no network by the backend's account: a load that cannot connect shows the offline page, ! in the card and on the row", wait: 1500,
          act: () => { Facts.fakeReachability("none"); app.go("http://down.test:" + check.closed + "/", "navigate") },
          expect: () => view.failure && view.failure.kind === "offline" && ownPage.visible && ownPage.page.title === "Can't reach down.test:" + check.closed
              && ownPage.page.body.join("|") === "This computer has no network connection.|The page loads again by itself when the network is back."
              && !view.loading && card() === 40 && session.current.failed === "error" && rail.addressField.url === "http://down.test:" + check.closed + "/" },
        { name: "the network back: the page loads again by itself, once (refused now, a plain Can't reach)", wait: 2500,
          act: () => { check.starts = []; Facts.fakeReachability("online") },
          expect: () => check.starts.length === 1 && view.failure && view.failure.kind === "connection" && ownPage.page.body.length === 0 },
        { name: "the network gone and back again: a page that is not offline does not reload", wait: 1500,
          act: () => { check.starts = []; Facts.fakeReachability("none"); Facts.fakeReachability("online") }, expect: () => check.starts.length === 0 },
        { name: "(the failure page has the page's keys)", wait: 300, act: () => app.focusPage(), expect: () => ownPage.activeFocus },
        { name: "Try again with the keys (Tab, Enter) loads it again", wait: 1500,
          act: () => { check.starts = []; probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => check.starts.length === 1 && view.failure && view.failure.kind === "connection" },
        { name: "a name with no address: doesn't exist, the history's host one edit away, and Search", wait: 1500,
          act: () => { history.visit("http://lore.kernel.invalid/", "lore"); app.go("http://lore.kernl.invalid/list", "navigate") },
          expect: () => view.failure && view.failure.kind === "name" && ownPage.page.title === "lore.kernl.invalid doesn't exist"
              && ownPage.page.actions.map(a => a.label).join() === "Did you mean lore.kernel.invalid?,Search" },
        { name: "(keys on the page)", wait: 300, act: () => app.focusPage(), expect: () => ownPage.activeFocus },
        { name: "Did you mean (Tab, Enter) loads that host, which has no address here either", wait: 1500,
          act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => String(view.url) === "http://lore.kernel.invalid/list" && ownPage.page.title === "lore.kernel.invalid doesn't exist" },
        { name: "(a page that answers)", wait: 1000, act: () => app.go(check.served("plain", "/plain"), "navigate"),
          expect: () => !view.failure && view.title === "plain" && session.current.failed === "" },
        { name: "no reply within the limit (2 s here): the browser stops the load and says so", wait: 3000,
          act: () => { view.replyLimit = 2000; app.go(check.served("slow", "/slow"), "navigate"); app.focusPage() },
          expect: () => view.failure && view.failure.kind === "noReply" && ownPage.page.title === "slow.test:" + check.port + " didn't answer"
              && ownPage.page.body[0] === "No reply within 2 s." && !view.loading && rail.addressField.url === check.served("slow", "/slow") && ownPage.activeFocus },
        { name: "Alt+Left: the page before it, still under it, shows again", key: Qt.Key_Left, mods: Qt.AltModifier, wait: 500,
          expect: () => !view.failure && view.title === "plain" && !view.loading },
        { name: "a certificate no known authority signed: its page, the load held; ! in the error tone, the card's second line", wait: 1500,
          act: () => app.go("https://cert.test:" + check.tlsPort + "/plain", "navigate"),
          expect: () => view.failure && view.failure.kind === "certificate" && view.held && view.loading && !session.current.loading
              && ownPage.page.title === "No known authority signed this certificate" && check.stateText() === "Unknown certificate authority"
              && card() > 40 && session.current.failed === "certificate" && rail.addressField.errorTone },
        { name: "held past the reply limit: not stopped, and no Waiting for", wait: 2000, expect: () => view.held && view.loading },
        { name: "(keys on the page)", wait: 300, act: () => app.focusPage(), expect: () => ownPage.activeFocus },
        { name: "Go back is the default (its key shown), Continue anyway a risk; one sentence says what each does; the certificate's facts under Certificate details", wait: 300,
          expect: () => {
              const v = ownPage.say ? ownPage.say.verbs : [];
              return v.length === 2 && v[0].label === "Go back" && v[0].tone === "default" && ownPage.defaultVerb === v[0]
                  && v[1].label === "Continue anyway" && v[1].tone === "risk" && /^↵ goes back .* Continuing lets them read what you type\.$/.test(ownPage.say.hint)
                  && ownPage.page.details[0] === "Issued to cert.test by cert.test" && /^Valid .+ · SHA-256 ([0-9a-f]{2}:){31}[0-9a-f]{2}$/.test(ownPage.page.details[1])
                  && ownPage.page.code === "ERR_CERT_AUTHORITY_INVALID" && ownPage.page.go === "Continue to cert.test:" + check.tlsPort + " once (not safe)" } },
        { name: "Go back (Backtab starts at it, not at Continue; Enter): refused, back on the page before it", wait: 1500,
          act: () => { probe.press(Qt.Key_Backtab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.failure && view.title === "plain" && String(view.url) === check.served("plain", "/plain") && session.current.failed === "" },
        { name: "refused, the next load there asks again", wait: 1500, act: () => app.go("https://cert.test:" + check.tlsPort + "/plain", "navigate"),
          expect: () => view.held },
        { name: "Continue loads it; the card keeps its ! and second line", wait: 1500, act: () => { check.starts = []; app.failureAction(view, "continue") },
          expect: () => !view.failure && view.title === "plain" && String(view.url).startsWith("https://cert.test:") && view.questioned !== null
              && check.stateText() === "Unknown certificate authority" && session.current.failed === "certificate" && rail.addressField.errorTone },
        { name: "for that page load only: a reload shows the certificate's page again, though the engine would let it through", wait: 1000,
          act: () => view.reload(),
          expect: () => view.failure && view.failure.kind === "certificate" && !view.held && !view.loading && ownPage.visible },
        { name: "Continue again loads it again", wait: 1500, act: () => { check.starts = []; app.failureAction(view, "continue") },
          expect: () => !view.failure && check.starts.length === 1 && view.title === "plain" },
        { name: "another page there shows it again; Go back shows the page it was on", wait: 1000,
          act: () => app.go("https://cert.test:" + check.tlsPort + "/login", "navigate"),
          expect: () => view.failure && view.failure.kind === "certificate" && rail.addressField.url === "https://cert.test:" + check.tlsPort + "/login" },
        { name: "(Go back)", wait: 500, act: () => app.failureAction(view, "back"),
          expect: () => !view.failure && String(view.url) === "https://cert.test:" + check.tlsPort + "/plain" },
        { name: "(that page again, and Continue)", wait: 1500,
          act: () => { app.go("https://cert.test:" + check.tlsPort + "/login", "navigate"); check.later(() => app.failureAction(view, "continue")) },
          expect: () => { check.rows = check.historyUrls(view).length; return !view.failure && view.title === "login" } },
        { name: "Back there shows the certificate's page again", wait: 1000, act: () => view.goBack(),
          expect: () => view.failure && view.failure.kind === "certificate" && rail.addressField.url === "https://cert.test:" + check.tlsPort + "/plain" },
        { name: "Continue goes back to that entry, not to a new one: Forward leads on to the page left", wait: 1500,
          act: () => app.failureAction(view, "continue"),
          expect: () => !view.failure && view.title === "plain" && view.canGoForward && check.historyUrls(view).length === check.rows },
        { name: "(a page there with a form, and Continue)", wait: 1500,
          act: () => { app.go("https://cert.test:" + check.tlsPort + "/post", "navigate"); check.later(() => app.failureAction(view, "continue")) },
          expect: () => !view.failure && view.title === "post" },
        { name: "its form, sent, goes to the host with its data: no certificate's page between", wait: 1500, focus: "f.submit()",
          expect: () => !view.failure && view.title === "posted" && String(view.url) === "https://cert.test:" + check.tlsPort + "/posted" },
        // A page's process stopping (8h). The opener and the page it opened share a process.
        { name: "a page and one it opened, which shares its process", wait: 1500,
          act: () => { view.replyLimit = 30000; app.go(check.local("/popup-opener"), "navigate"); check.opener = session.currentPage },
          expect: () => view.title === "opener" },
        { name: "(window.open without a size: a page in the thread)", wait: 1500, focus: "act = plain",
          act: () => { check.click(); }, expect: () => session.currentPage !== check.opener && view.title === "plain" },
        { name: "(back on the opener: one process for both)", wait: 800,
          act: () => { check.sibling = session.currentPage; app.show(check.opener) },
          expect: () => view.renderProcessPid > 0 && app.views[check.sibling].renderProcessPid === view.renderProcessPid },
        { name: "its process killed (SIGKILL) on screen: This page's process was stopped, with its measured memory and the page that shared it", wait: 1500,
          act: () => { app.sampleMemory(); check.pid = view.renderProcessPid; probe.sendSignal(check.pid, 9) },
          expect: () => view.failure && view.failure.kind === "crash" && ownPage.page.title === "This page's process was stopped"
              && /^127\.0\.0\.1:\d+ was using about \d+ MB \(measured \d\d:\d\d\)\. One other page shared its process\. It is unloaded and loads again when you open it\.$/.test(ownPage.page.body[0])
              && ownPage.page.details[0] === "killed · pid " + check.pid && session.current.failed === "error"
              && session.pages[check.sibling].state === "unloaded" && app.views[check.sibling].reloadOnShow && !app.sampling },
        { name: "the page that shared it loads again when opened", wait: 1500, act: () => app.show(check.sibling),
          expect: () => !view.loading && view.title === "plain" && !view.failure && session.current.state === "live" },
        { name: "back on the stopped page, it loads again by itself (its first stop)", wait: 1500, act: () => app.show(check.opener),
          expect: () => !view.failure && !view.loading && view.title === "opener" && session.current.failed === "" },
        { name: "stopped again within 10 minutes: It stopped twice in 10 minutes.", wait: 1500,
          act: () => { check.pid = view.renderProcessPid; probe.sendSignal(check.pid, 9) },
          expect: () => view.failure && view.failure.kind === "crash" && view.failure.twice && ownPage.page.body[0].endsWith("It stopped twice in 10 minutes.") },
        { name: "away and back, it stays stopped", wait: 1000, act: () => { app.show(check.sibling); app.show(check.opener) },
          expect: () => view.failure && view.failure.kind === "crash" && !view.loading },
        { name: "(keys on the page)", wait: 300, act: () => app.focusPage(), expect: () => ownPage.activeFocus },
        { name: "Reload (Tab, Enter) loads it", wait: 1500, act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !view.failure && view.title === "opener" },
        { name: "SIGABRT: Chromium's own handler ends the process with an exit code", wait: 1500,
          act: () => { check.pid = view.renderProcessPid; probe.sendSignal(check.pid, 6) },
          expect: () => { check.said = view.failure ? view.failure.title : ""; return /^The page's process exited with code \d+$|^This page crashed$/.test(check.said) } },
        { name: "(reloaded)", wait: 1500, act: () => app.failureAction(view, "reload"), expect: () => !view.failure && view.title === "opener" },
        // After a browser crash (8i): Main.startAfter with the run record the start reads.
        { name: "a start after a run not marked clean: the restore page, no page open, the page that was on screen offered and kept in the run record", wait: 500,
          act: () => { check.shown = session.currentPage; check.shownTitle = session.current.title; app.writeRun({ page: "" });
                       app.startAfter({ clean: false, alive: Date.now() - 60000, page: check.shown }) },
          expect: () => session.currentPage === "" && app.noPage && ownPage.visible && /^The browser did not close cleanly at \d\d:\d\d$/.test(ownPage.page.title)
              && ownPage.page.actions.map(a => a.label).join() === "Open " + check.shownTitle && rail.addressField.parts.host === "" && ownPage.activeFocus
              && Store.load("run").page === check.shown && !app.sampling },
        { name: "stopped again before Open: the next start offers it again", wait: 500, act: () => app.startAfter(Store.load("run")),
          expect: () => app.restorePage && ownPage.page.actions.map(a => a.label).join() === "Open " + check.shownTitle && ownPage.activeFocus },
        { name: "Open (Tab, Enter): the page shows and loads, suspect for a minute in the run record", wait: 1500,
          act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => { const r = Store.load("run"); return session.currentPage === check.shown && !app.restorePage && !ownPage.visible && view.title === "opener"
              && r.clean === false && r.suspect === check.shown && r.page === check.shown } },
        { name: "stopped again within that minute, the next start leaves it out, into History", wait: 500,
          act: () => app.startAfter(Store.load("run")),
          expect: () => !session.pages[check.shown] && session.closed[session.closed.length - 1].title === check.shownTitle && ownPage.page.actions.length === 0
              && ownPage.page.note === check.shownTitle + " was open when the browser stopped twice, so it was left out. It is listed in History." },
        { name: "(a page again: the restore page goes)", wait: 1000, act: () => app.show(session.railOrder()[0]), expect: () => !app.restorePage && !ownPage.visible && app.sampling },
        { group: "find" },
        check.server,
        { setup: true, name: "(a file to type the path of)", wait: 100,
          act: () => { if (!check.files.length) check.files = [probe.fixtureFile("notes.txt", "notes")] }, expect: () => !!check.files[0] },
        // Find in page (PLAN.md 3.8 8e), on a thread of four: the page on screen (3 matches for csiphy, 1 with
        // its case), a live one (2, 1 with its case, the second 3000 px down), a frozen and an unloaded one.
        // The keys go into find's field through the window system.
        { name: "find: a thread with a live page, a frozen one and an unloaded one besides the page on screen", wait: 2500,
          act: () => {
              const t = session.newThread("find");
              check.findPages = ["/find", "/find-other", "/plain", "/plain"].map(p => session.addPage(t, check.local(p), ""));
              for (const id of check.findPages.slice(1))
                  app.viewFor(id).url = session.pages[id].url;
              app.show(check.findPages[0]);
          },
          expect: () => view.title === "find" && !view.loading && check.findPages.slice(1).every(id => !app.views[id].loading) },
        { name: "(one frozen, one unloaded)", wait: 500,
          act: () => { const [, , f, u] = check.findPages; app.setLifecycle(f, app.views[f], WebEngineView.LifecycleState.Frozen); app.setLifecycle(u, app.views[u], WebEngineView.LifecycleState.Discarded) },
          expect: () => state(check.findPages[2]) === 1 && state(check.findPages[3]) === 2 },
        { name: "Ctrl+F on the page opens find in the rail's card, over the rows (the card itself does not grow)", focus: "document.activeElement.blur()",
          key: Qt.Key_F, mods: ctrl, wait: 500, expect: () => rail.finder.open && rail.finder.where === "rail" && rail.findCard.shown && card() === 40 },
        { name: "typed into its field: the count by it, the first match active", wait: 800, act: () => check.type("csiphy"),
          expect: () => rail.finder.text === "csiphy" && rail.finder.count === "1 of 3" },
        { name: "Also in this thread: the live page and its count, by a script that moved neither its selection nor its scroll; the others said skipped", wait: 600,
          expect: () => rail.finder.hits.map(h => h.pageId + " " + h.count).join() === check.findPages[1] + " 2"
              && rail.finder.skipped === "1 frozen and 1 unloaded pages skipped" && state(check.findPages[2]) === 1 && state(check.findPages[3]) === 2,
          pageIn: () => app.views[check.findPages[1]], page: "JSON.stringify([getSelection().toString(), scrollY])", pageExpect: v => v === '["",0]' },
        { name: "Enter: the next match", key: Qt.Key_Return, wait: 400, expect: () => rail.finder.count === "2 of 3" },
        { name: "F3: the next", key: Qt.Key_F3, wait: 400, expect: () => rail.finder.count === "3 of 3" },
        { name: "Down: past the last, the count goes back to 1", key: Qt.Key_Down, wait: 400, expect: () => rail.finder.count === "1 of 3" },
        { name: "Shift+Enter: the previous, back round to the last", key: Qt.Key_Return, mods: Qt.ShiftModifier, wait: 400, expect: () => rail.finder.count === "3 of 3" },
        { name: "Up: the previous", key: Qt.Key_Up, wait: 400, expect: () => rail.finder.count === "2 of 3" },
        { name: "Shift+F3: the previous", key: Qt.Key_F3, mods: Qt.ShiftModifier, wait: 400, expect: () => rail.finder.count === "1 of 3" },
        { name: "Alt+C matches case: this page's count and the other page's follow; nothing typed", key: Qt.Key_C, mods: Qt.AltModifier, text: "c", wait: 800,
          expect: () => rail.finder.matchCase && rail.finder.text === "csiphy" && rail.finder.count === "1 of 1" && rail.finder.hits.map(h => h.count).join() === "1" },
        { name: "Alt+C again", key: Qt.Key_C, mods: Qt.AltModifier, text: "c", wait: 800,
          expect: () => !rail.finder.matchCase && rail.finder.result.matches === 3 && rail.finder.hits.map(h => h.count).join() === "2" },
        { name: "words the page does not have: No matches, no page listed, the skipped ones still said", wait: 800, act: () => check.type("x"),
          expect: () => rail.finder.count === "No matches" && rail.finder.hits.length === 0 && rail.finder.skipped !== "" },
        { name: "(Backspace)", key: Qt.Key_Backspace, wait: 800, expect: () => rail.finder.text === "csiphy" && rail.finder.result.matches === 3 },
        { name: "(Enter: the second match)", key: Qt.Key_Return, wait: 400, expect: () => rail.finder.count === "2 of 3" },
        // the answer dropped as the key goes in, so only a search of the new document brings one back
        { name: "Ctrl+R in find reloads the page (P key); find stays open and counts the new document", key: Qt.Key_R, mods: ctrl, wait: 1500,
          act: () => rail.finder.result = null,
          expect: () => rail.finder.open && !view.loading && view.title === "find" && rail.finder.result !== null && rail.finder.result.matches === 3 },
        { name: "Esc closes find; the keys go back to the page, the match left selected for Ctrl+C", key: Qt.Key_Escape, wait: 400,
          expect: () => !rail.finder.open && !rail.finding && view.activeFocus, page: "getSelection().toString()", pageExpect: v => v.toLowerCase() === "csiphy" },
        { name: "/ on the page, no field focused, opens find with the words it kept, selected", focus: "document.activeElement.blur()",
          key: Qt.Key_Slash, text: "/", wait: 500, expect: () => rail.finder.open && rail.finder.text === "csiphy" },
        { name: "typing replaces them", wait: 800, act: () => check.type("lanes"), expect: () => rail.finder.text === "lanes" && rail.finder.count === "1 of 1" },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 300, expect: () => !rail.finder.open },
        { name: "/ in a page field types it; find stays closed", focus: "field.focus()", key: Qt.Key_Slash, text: "/", wait: 400,
          expect: () => !rail.finder.open, page: "field.value", pageExpect: v => v === "/" },
        { name: "a page that takes / itself (as GitHub does) keeps it", key: Qt.Key_Slash, text: "/", wait: 400,
          focus: "document.activeElement.blur(); window.slashes = 0; addEventListener('keydown', e => { if (e.key === '/') { e.preventDefault(); slashes++ } })",
          expect: () => !rail.finder.open, page: "slashes", pageExpect: v => v === 1 },
        // the letters wait for Ctrl+F to come back from the page, as a P key does
        { name: "(Ctrl+F)", focus: "document.activeElement.blur()", key: Qt.Key_F, mods: ctrl, wait: 400, expect: () => rail.finder.open },
        { name: "(csiphy)", wait: 800, act: () => check.type("csiphy"), expect: () => rail.finder.count === "1 of 3" && rail.finder.hits.length === 1 },
        { name: "a click on the listed page shows it at its first match, find open on it, the page before now listed", wait: 1000, act: () => check.clickHit(0),
          expect: () => session.currentPage === check.findPages[1] && rail.finder.open && rail.finder.view === app.views[check.findPages[1]]
              && rail.finder.count === "1 of 2" && rail.finder.hits.map(h => h.pageId + " " + h.count).join() === check.findPages[0] + " 3" },
        { name: "(the keys are in find there: Esc closes it)", key: Qt.Key_Escape, wait: 400, expect: () => !rail.finder.open && view.activeFocus },
        // the pointer out of the window first: a suggestion row that opens under it becomes the current row
        { name: "the / prefix in the address card: Enter takes the words to find", wait: 800,
          act: () => { probe.leave(); probe.press(Qt.Key_L, ctrl); probe.press(Qt.Key_Slash, 0, "/"); check.type("lanes"); probe.press(Qt.Key_Return, 0) },
          expect: () => !address.editing && rail.finder.open && rail.finder.text === "lanes" && rail.finder.count === "1 of 1" },
        { name: "(the keys are in find)", wait: 600, act: () => check.type("x"), expect: () => rail.finder.text === "lanesx" },
        { name: "F6 from find goes on to the rail list, and find closes", key: Qt.Key_F6, wait: 400, expect: () => !rail.finder.open && rail.listFocused },
        { name: "(Esc: back to the page)", key: Qt.Key_Escape, wait: 300, expect: () => !rail.listFocused && view.activeFocus },
        { name: "a typed path of an existing file offers Open file first, find second; a missing one only find", wait: 300,
          act: () => address.open(check.files[0]),
          expect: () => { const found = address.rows.map(r => r.kind).join(); address.open(check.files[0] + ".missing");
                          return found === "go,find" && address.rows.map(r => r.kind).join() === "find" } },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 700, expect: () => !address.editing },
        { name: "the / prefix in the new-page bar finds on the page on screen; no page opens", wait: 800,
          act: () => { check.rows = session.railOrder().length; probe.press(Qt.Key_T, ctrl); probe.press(Qt.Key_Slash, 0, "/"); check.type("csiphy"); probe.press(Qt.Key_Return, 0) },
          expect: () => !newPageBar.opened && rail.finder.open && rail.finder.text === "csiphy" && rail.finder.count === "1 of 2" && session.railOrder().length === check.rows },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 300, expect: () => !rail.finder.open },
        { name: "(Ctrl+T)", key: Qt.Key_T, mods: ctrl, wait: 300, expect: () => newPageBar.opened },
        { name: "Ctrl+F in the new-page bar (P key): the bar gives way to find", key: Qt.Key_F, mods: ctrl, wait: 500,
          expect: () => !newPageBar.opened && rail.finder.open && rail.finding },
        // a stand-in permission ask, as BrowserView queues one
        { name: "an ask that arrives while find is open: its sheet comes out of the page's edge, find and the card as they were", wait: 800,
          act: () => view.asks = [check.standInAsk()],
          expect: () => view.ask && rail.finder.open && rail.finder.waiting === "" && check.sheetOut() && card() === 40 },
        { name: "Esc: find closes, the ask still in its sheet", key: Qt.Key_Escape, wait: 600,
          expect: () => !rail.finder.open && view.ask && check.sheetOut() && card() === 40 },
        { name: "(the stand-in ask goes)", wait: 500, act: () => view.asks = [], expect: () => !view.ask && card() === 40 },
        { name: "(folded)", wait: 1200, act: () => app.railPinned = false, expect: () => !app.railPinned },
        { name: "folded, Ctrl+F brings the overlay out with find in its address slot; nothing over the page but the overlay", focus: "document.activeElement.blur()",
          key: Qt.Key_F, mods: ctrl, wait: 900, act: () => probe.pointer(700, 400),
          expect: () => rail.finder.open && rail.finder.where === "peek" && peekedRail.finding && peekedRail.findCard.shown && hoverPeek.held
              && peekedRail.slide === 1 && !hoverPeek.open && !address.out && !rail.finding && card() === 40 },
        { name: "its field has the keys", wait: 800, act: () => check.type("lanes"), expect: () => rail.finder.text === "lanes" && rail.finder.count === "1 of 1" },
        { name: "the pointer onto the overlay: its own hold on it comes on too", wait: 300, act: () => probe.pointer(150, 600),
          expect: () => rail.finder.open && hoverPeek.open && hoverPeek.held },
        { name: "off it again, past the pointer's 260 ms: find stays, and the overlay with it", wait: 700, act: () => probe.pointer(700, 400),
          expect: () => rail.finder.open && hoverPeek.out && peekedRail.slide === 1 && !hoverPeek.open },
        { name: "Esc: find closes and the overlay slides back; the keys on the page", key: Qt.Key_Escape, wait: 900,
          expect: () => !rail.finder.open && !hoverPeek.out && peekedRail.slide === 0 && view.activeFocus },
        { name: "(Ctrl+F there again)", focus: "document.activeElement.blur()", key: Qt.Key_F, mods: ctrl, wait: 900, expect: () => peekedRail.finding && peekedRail.slide === 1 },
        { name: "a click on the page closes it, and the overlay slides back", wait: 900, act: () => check.click(700),
          expect: () => !rail.finder.open && !hoverPeek.out && peekedRail.slide === 0 },
        { name: "(Ctrl+F there again, then the pointer onto the overlay)", focus: "document.activeElement.blur()", key: Qt.Key_F, mods: ctrl, wait: 900,
          act: () => check.later(() => probe.pointer(150, 600)), expect: () => peekedRail.finding && hoverPeek.open },
        { name: "Esc with the pointer on the overlay: find closes, the overlay stays while the pointer does", key: Qt.Key_Escape, wait: 700,
          expect: () => !rail.finder.open && hoverPeek.out && peekedRail.slide === 1 },
        { name: "the pointer off it, it slides back", wait: 900, act: () => probe.pointer(700, 400), expect: () => !hoverPeek.out && peekedRail.slide === 0 },
        { name: "(Ctrl+F there again)", focus: "document.activeElement.blur()", key: Qt.Key_F, mods: ctrl, wait: 900, expect: () => peekedRail.finding && peekedRail.slide === 1 },
        { name: "an ask while find is open there: its sheet comes out, find and the overlay's card as they were", wait: 800, act: () => view.asks = [check.standInAsk()],
          expect: () => view.ask && rail.finder.waiting === "" && peekedRail.finding && check.sheetOut() && card() === 40 },
        { name: "Esc: find closes, the ask still in its sheet; nothing holds the overlay out", key: Qt.Key_Escape, wait: 900,
          expect: () => !rail.finder.open && view.ask && check.sheetOut() && !hoverPeek.held },
        { name: "(the stand-in ask goes, and the overlay slides back)", wait: 900, act: () => view.asks = [], expect: () => !hoverPeek.out && peekedRail.slide === 0 },
        { name: "(Ctrl+B pins again)", focus: "document.activeElement.blur()", key: Qt.Key_B, mods: ctrl, wait: 1200, expect: () => app.railPinned },
        { group: "downloads" },
        check.server,
        { setup: true, name: "(the fixture server over TLS)", wait: 100,
          act: () => { if (!check.tlsPort) check.tlsPort = probe.serveTls() }, expect: () => check.tlsPort > 0 },
        // Downloads (PLAN.md 3.8 8d), from the fixture server's /file/<name>: an attachment, 1 kB every `delay` ms,
        // dropped at `cut` with the resume refused until probe.allowResume. Files land in Disk.downloads, the
        // throwaway data dir's Downloads. The row actions are clicked through the window system.
        { name: "downloads go to the throwaway data dir's Downloads, never ~/Downloads", wait: 100,
          expect: () => Disk.downloads === Store.dataDir.replace(/\/browser$/, "/Downloads") && app.profile.downloadPath === Disk.downloads },
        { name: "(a page to download from)", wait: 1500, act: () => { app.go(check.local("/plain"), "new", "", "downloads"); check.dlPage = session.currentPage },
          expect: () => view.title === "plain" && !view.loading },
        { name: "a file the page fetches grows a row under it, running with its percent; the page stays", wait: 1200,
          focus: "location.href = '/file/camss-v3.mbox?size=300000&delay=20'",
          expect: () => { check.dl = check.lastDownload().id; const d = check.record(), r = check.rowOf("d:" + d.id);
                          return d.page === check.dlPage && d.state === "running" && d.path === Disk.downloads + "/camss-v3.mbox"
                              && Facts.isFile(d.path + ".download") && !!r && /^\d+ %$/.test(r.detail) && session.current.downloading
                              && view.title === "plain" && String(view.url) === check.local("/plain") } },
        { name: "the pointer on it: the size and time left, the bar, Pause and Cancel", wait: 500, act: () => check.hoverRow("d:" + check.dl),
          expect: () => !!rail.rowAction("d:" + check.dl, "pause") && !!rail.rowAction("d:" + check.dl, "cancel") && check.rowItem("d:" + check.dl).height >= 48
              && /^\d+ of 300 kB/.test(check.rowOf("d:" + check.dl).info) },
        { name: "Pause holds it", wait: 600, act: () => check.clickAction("d:" + check.dl, "pause"),
          expect: () => { check.bytes = downloads.requests[check.dl].receivedBytes; return check.record().state === "paused" && check.rowOf("d:" + check.dl).detail === "Paused" } },
        { name: "(nothing comes while paused)", wait: 800,
          expect: () => downloads.requests[check.dl].receivedBytes === check.bytes && check.bytes < 300000 && !!rail.rowAction("d:" + check.dl, "resume") },
        { name: "Resume: it lands; the part-file is gone and the file carries its origin (URL, page, thread)", wait: 6500,
          act: () => check.clickAction("d:" + check.dl, "resume"),
          expect: () => { const d = check.record(), a = probe.attributes(d.path);
                          return d.state === "done" && d.received === 300000 && Facts.isFile(d.path) && !Facts.isFile(d.path + ".download")
                              && a["user.xdg.origin.url"] === d.url && a["user.xdg.referrer.url"] === check.local("/plain") && a["user.browser.thread"] === "downloads"
                              && !session.current.downloading } },
        { name: "finished, the pointer on it: Open and Show in Files", wait: 500, act: () => { probe.pointer(700, 400); check.hoverRow("d:" + check.dl) },
          expect: () => !!rail.rowAction("d:" + check.dl, "show") && /^300 kB · \d\d:\d\d$/.test(check.rowOf("d:" + check.dl).info) },
        { name: "Show in Files hands the file to Files (a dry run)", wait: 300, act: () => check.clickAction("d:" + check.dl, "show"),
          expect: () => Apps.lastRevealed === check.record().path },
        { name: "a click on it opens it in its app (a dry run); the row stays for now", wait: 300, act: () => check.clickRow("d:" + check.dl),
          expect: () => Apps.lastOpened === check.record().path && check.record().opened > 0 && !!check.rowOf("d:" + check.dl) },
        { name: "10 min after it was opened the row has left; the record stays for Downloads", wait: 300,
          act: () => session.updateDownload(check.dl, { opened: Date.now() - 600001 }), expect: () => !check.rowOf("d:" + check.dl) && !!check.record() },
        { name: "three more from the page: one row, 3 downloads with the percent of them all", wait: 800,
          focus: "for (const n of ['one.bin', 'two.bin', 'three.bin']) { const a = document.createElement('a'); a.href = '/file/' + n + '?size=100000&delay=15'; a.download = n; document.body.appendChild(a); a.click() }",
          act: () => probe.pointer(700, 400),
          expect: () => { const r = check.rowOf("s:" + check.dlPage); return !!r && r.title === "3 downloads" && /^\d+ % · 3 coming$/.test(r.info) && session.downloads.filter(d => d.page === check.dlPage && d.state === "running").length === 3 } },
        { name: "a click on it lists them in place", wait: 500, act: () => check.clickRow("s:" + check.dlPage),
          expect: () => downloads.listed.indexOf(check.dlPage) >= 0 && session.downloads.slice(-3).every(d => !!check.rowOf("d:" + d.id)) },
        { name: "a click again folds them back into it; when all are done it reads 3 downloads", wait: 2500, act: () => check.clickRow("s:" + check.dlPage),
          expect: () => downloads.listed.length === 0 && !check.rowOf("d:" + session.downloads[session.downloads.length - 1].id)
              && check.rowOf("s:" + check.dlPage).title === "3 downloads" },
        { name: "a connection that drops, its resume refused: The site stopped sending it., with Try again and Remove and no pointer on it", wait: 2000,
          act: () => { probe.pointer(700, 400); probe.allowResume(false) }, focus: "location.href = '/file/cut.bin?size=100000&delay=5&cut=20000'",
          expect: () => { check.dl = check.lastDownload().id; const d = check.record();
                          return d.state === "failed" && d.reason === "server" && check.rowOf("d:" + d.id).note === "The site stopped sending it."
                              && !!rail.rowAction("d:" + d.id, "retry") && !!rail.rowAction("d:" + d.id, "remove") } },
        { name: "Retry, the server taking the resume again: it lands whole", wait: 1500, act: () => { probe.allowResume(true); check.clickAction("d:" + check.dl, "retry") },
          expect: () => check.record().state === "done" && check.record().received === 100000 && Facts.isFile(check.record().path) },
        { name: "(another that drops)", wait: 2000, act: () => probe.allowResume(false), focus: "location.href = '/file/cut2.bin?size=100000&delay=5&cut=20000'",
          expect: () => { check.dl = check.lastDownload().id; return check.record().state === "failed" } },
        { name: "Remove: its row, record and part-file go", wait: 800, act: () => { check.path = check.record().path; check.clickAction("d:" + check.dl, "remove") },
          expect: () => !check.record() && !check.rowOf("d:" + check.dl) && !Facts.isFile(check.path + ".download") && !Facts.isFile(check.path) },
        { name: "a file that runs as a program lands saying so, with Delete leading and Keep, and no Open", wait: 1200,
          focus: "location.href = '/file/flash-tool.AppImage?size=5000'",
          expect: () => { check.dl = check.lastDownload().id; const d = check.record(), r = check.rowOf("d:" + d.id);
                          return d.state === "done" && d.warn === "program" && r.note.startsWith("It runs as a program. Keep it only if you trust ") && !!rail.rowAction(r.key, "keep")
                              && !!rail.rowAction(r.key, "delete") && !rail.rowAction(r.key, "open") } },
        { name: "Delete: the file and its row go", wait: 500, act: () => { check.path = check.record().path; check.clickAction("d:" + check.dl, "delete") },
          expect: () => !Facts.isFile(check.path) && !check.record() && !check.rowOf("d:" + check.dl) },
        { name: "(another program)", wait: 1200, focus: "location.href = '/file/run-me.sh?size=5000'",
          expect: () => { check.dl = check.lastDownload().id; return check.record().warn === "program" } },
        { name: "Keep: then it is a finished file like any other, in the page's summary row", wait: 600, act: () => check.clickAction("d:" + check.dl, "keep"),
          expect: () => check.record().warn === "" && Facts.isFile(check.record().path) && !check.rowOf("d:" + check.dl)
              && /^\d+ downloads$/.test(check.rowOf("s:" + check.dlPage).title) },
        { name: "(an https page: the certificate's page for cert.test, then Continue)", wait: 1500,
          act: () => { probe.pointer(700, 400); app.go("https://cert.test:" + check.tlsPort + "/plain", "new", "", "tls"); check.tlsPage = session.currentPage },
          expect: () => view.failure && view.failure.kind === "certificate" },
        { name: "(Continue)", wait: 1500, act: () => app.failureAction(view, "continue"), expect: () => !view.failure && view.title === "plain" },
        { name: "an http file through a link on the https page that opens a new page is held too, though that page has no address yet", wait: 1500,
          focus: () => "{ const a = document.createElement('a'); a.id = 'blank'; a.target = '_blank'; a.textContent = 'file';"
              + " a.href = 'http://plain.test:" + check.port + "/file/blank.bin?size=5000'; a.style = 'position:fixed;left:0;top:0;width:400px;height:300px'; document.body.appendChild(a) }",
          act: () => check.click(),
          expect: () => { const d = check.lastDownload(); return d.file === "blank.bin" && d.state === "blocked" && !Facts.isFile(d.path) && session.currentPage !== check.tlsPage } },
        { name: "(that page closed, the held file with it; back on the https page)", wait: 800,
          act: () => { if (session.currentPage !== check.tlsPage) app.closePage(session.currentPage); app.show(check.tlsPage); view.runJavaScript("blank.remove()") },
          expect: () => session.currentPage === check.tlsPage && !session.downloads.some(d => d.file === "blank.bin") },
        { name: "an http file from the https page is not fetched: its connection wasn't private, Download anyway", wait: 1500,
          focus: () => "location.href = 'http://plain.test:" + check.port + "/file/driver.run?size=5000'",
          expect: () => { check.dl = check.lastDownload().id; const d = check.record(), r = check.rowOf("d:" + d.id);
                          return d.state === "blocked" && d.page === check.tlsPage && !downloads.requests[d.id] && !Facts.isFile(d.path) && !Facts.isFile(d.path + ".download")
                              && r.note === "Not downloaded: its connection wasn't private." && !!rail.rowAction(r.key, "keep") && !rail.rowAction(r.key, "open") } },
        { name: "Keep fetches it (in the hidden fetcher); it lands under its page, and runs as a program too", wait: 1500,
          act: () => check.clickAction("d:" + check.dl, "keep"),
          expect: () => check.record().state === "done" && check.record().warn === "program" && Facts.isFile(check.record().path)
              && check.record().page === check.tlsPage && downloads.fetchUrl === "" },
        { name: "the same file typed as the address on the https page: yours, so not held", wait: 1500,
          act: () => { app.go("http://plain.test:" + check.port + "/file/typed.bin?size=5000", "navigate"); },
          expect: () => { check.dl = check.lastDownload().id; const d = check.record();
                          return d.file === "typed.bin" && d.state === "done" && d.page === check.tlsPage && String(view.url).startsWith("https://cert.test:") } },
        { name: "(another held one; the typed file deleted)", wait: 1500, focus: () => "location.href = 'http://plain.test:" + check.port + "/file/held.bin?size=5000'",
          act: () => downloads.act(check.dl, "delete"),
          expect: () => { check.dl = check.lastDownload().id; check.path = check.record().path; return check.record().state === "blocked" } },
        { name: "a held file goes with its page, never fetched; the page's finished one leaves the list for Downloads, from it", wait: 800,
          act: () => { app.closePage(check.tlsPage); check.later(() => app.openEarlier("downloads")) },
          expect: () => !session.pages[check.tlsPage] && !check.record() && !Facts.isFile(check.path) && !Facts.isFile(check.path + ".download")
              && app.earlier.view === "downloads" && check.rowOf("d:" + session.downloads.find(d => d.page === check.tlsPage).id).from === "plain" },
        { name: "(the program there: Delete)", wait: 400, act: () => { const d = session.downloads.find(x => x.page === check.tlsPage); check.clickAction("d:" + d.id, "delete") },
          expect: () => !session.downloads.some(d => d.page === check.tlsPage) },
        { name: "(back on the downloads page)", wait: 800, act: () => { app.closeEarlier(false); app.show(check.dlPage) }, expect: () => session.currentPage === check.dlPage && !rail.inEarlier },
        { name: "(a file that takes 16 s)", wait: 800, focus: "location.href = '/file/slow.bin?size=400000&delay=40'",
          expect: () => { check.dl = check.lastDownload().id; return check.record().state === "running" && session.pages[check.dlPage].downloading } },
        { name: "a page whose file is still coming is not the memory net's pick, though seen longest ago", wait: 1000,
          act: () => { const other = session.addPage(session.newThread("away"), check.local("/plain"), ""); app.show(other); unseenFor(check.dlPage, 100000) },
          expect: () => state(check.dlPage) === 0 && Lifecycle.keeps(session.pages[check.dlPage], false, false) === "download"
              && Lifecycle.pick(app.netPages())?.id !== check.dlPage && view.title === "plain" },
        { name: "its page closed while the file still comes: the foot's Downloads says its share; Downloads lists it, from that page", wait: 1500,
          act: () => { app.closePage(check.dlPage); check.later(() => app.openEarlier("downloads")) },
          expect: () => { const coming = check.named(rail, "footComing");
              return !session.pages[check.dlPage] && check.record().state === "running" && !!coming && /^\d+ %$/.test(coming.text) && check.rowOf("d:" + check.dl).from === "plain" } },
        { name: "Cancel there (the pointer on it): the row and the part-file go", wait: 800,
          act: () => { check.path = check.record().path; check.hoverRow("d:" + check.dl) },
          expect: () => !!rail.rowAction("d:" + check.dl, "cancel") },
        { name: "(Cancel)", wait: 800, act: () => check.clickAction("d:" + check.dl, "cancel"),
          expect: () => !check.record() && !check.rowOf("d:" + check.dl) && !Facts.isFile(check.path + ".download") && !Facts.isFile(check.path) },
        { name: "Retry on a record from an earlier run (no request left) loads its address in the hidden fetcher: the same row lands", wait: 2000,
          act: () => {
              probe.pointer(700, 400);
              app.closeEarlier(false);
              check.dl = session.addDownload({ page: session.currentPage, url: check.local("/file/again.bin?size=5000"), file: "again.bin", path: Disk.downloads + "/again.bin",
                                               state: "failed", reason: "browser closed", from: { title: "plain", icon: "", always: false, url: check.plain, thread: "away" } });
              downloads.act(check.dl, "retry");
          },
          expect: () => { const d = check.record(); return d.state === "done" && d.received === 5000 && Facts.isFile(d.path) && downloads.fetchUrl === ""
                              && d.page === session.currentPage && !!check.rowOf("d:" + d.id) && session.downloads.filter(x => x.file === "again.bin").length === 1 } },
        { name: "two Retries of one address, queued: each gets a fresh fetch and lands", wait: 2500,
          act: () => {
              check.twice = [0, 1].map(() => session.addDownload({ page: session.currentPage, url: check.local("/file/twice.bin?size=5000"), file: "twice.bin",
                                                                   path: Disk.downloads + "/twice.bin", state: "failed", reason: "browser closed" }));
              for (const id of check.twice)
                  downloads.act(id, "retry");
          },
          expect: () => check.twice.every(id => session.downloadById(id).state === "done" && Facts.isFile(session.downloadById(id).path))
              && session.downloadById(check.twice[0]).path !== session.downloadById(check.twice[1]).path && downloads.fetchUrl === "" },
        { name: "a Retry whose address loads a page instead: There was no file at that address.", wait: 1500,
          act: () => { check.dl = session.addDownload({ page: session.currentPage, url: check.local("/plain"), file: "gone.bin", path: Disk.downloads + "/gone.bin",
                                                        state: "failed", reason: "browser closed" }); downloads.act(check.dl, "retry") },
          expect: () => check.record().state === "failed" && check.record().reason === "no file" && downloads.fetchUrl === "" },
        { name: "(folded)", wait: 1200, act: () => { downloads.act(check.dl, "remove"); app.railPinned = false }, expect: () => !app.railPinned },
        { name: "folded, a download that starts says so in the docked label, its percent kept", wait: 700,
          focus: "location.href = '/file/notice.bin?size=100000&delay=10'", act: () => probe.pointer(700, 400),
          expect: () => /^Downloading notice\.bin · \d+ %$/.test(app.downloadNotice) },
        { name: "the notice goes after 3 s", wait: 2600, expect: () => app.downloadNotice === "" },
        { name: "(Ctrl+B pins again)", focus: "document.activeElement.blur()", key: Qt.Key_B, mods: ctrl, wait: 1200, expect: () => app.railPinned },
        // progress reaches the rail from Downloader's 500 ms tick, one rebuild for every file coming
        { name: "(three files that take 4 s)", wait: 800,
          focus: "for (const n of ['a.bin', 'b.bin', 'c.bin']) { const a = document.createElement('a'); a.href = '/file/tick-' + n + '?size=100000&delay=40'; a.download = 'tick-' + n; document.body.appendChild(a); a.click() }",
          expect: () => session.downloads.filter(d => d.file.startsWith("tick-") && d.state === "running").length === 3 },
        { name: "while the three come, the rail is rebuilt about twice a second, not twice a second for each", wait: 2000, act: () => check.rebuilds = 0,
          expect: () => { check.probe.report("     rail rebuilds in 2 s: " + check.rebuilds); return check.rebuilds <= 5 } },
        { name: "(Cancel them)", wait: 800, act: () => { for (const d of session.downloads.filter(d => d.file.startsWith("tick-"))) downloads.act(d.id, "cancel") },
          expect: () => !session.downloads.some(d => d.file.startsWith("tick-")) },
    ].concat(siteSteps, instanceSteps, linkSteps, windowSteps, privateSteps, internalSteps, edgeSteps, recallSteps, ownSteps, passwordSteps, passkeySteps, passwordFileSteps, chromeSteps, foxSteps, readerSteps,
             printSteps, zenSteps, zenSessionSteps, zenRealSteps, railSteps, liftSteps, stripSteps, idleSteps, faviconSteps, glideSteps, swipeSteps, notchSteps, signinSteps)
    // The site panel (PLAN.md 3.9), on a page of 127.0.0.1 (the asks above noted what it asked for). The check's
    // filter list refuses ads.test and hides div.check-ad; clicks and keys go in through the window system.
    readonly property var siteSteps: [
        { group: "site" },
        check.server,
        { setup: true, name: "(the asks page, to ask what the asks group asked for)", wait: 1500, act: () => app.go(check.local("/asks"), "navigate"),
          expect: () => view.title === "asks" && !view.loading },
        { setup: true, name: "(a click asks for the microphone)", wait: 800, focus: "act = mic", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "microphone" },
        { setup: true, name: "(Esc denies it)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) }, expect: () => !view.ask },
        { setup: true, name: "(a click asks to show notifications)", wait: 800, focus: "act = notify", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "notifications" },
        { setup: true, name: "(Esc denies it)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) }, expect: () => !view.ask },
        { name: "the site's page: its ad refused and its banner hidden by the filter list, its storage written", wait: 1500,
          act: () => { probe.leave(); app.go(check.local("/site"), "navigate") },
          expect: () => view.title === "site" && app.adblock.seen(String(view.url)).blocked === 1 && SiteData.cookies("127.0.0.1") === 1,
          page: "getComputedStyle(banner).display + ' ' + window.stored", pageExpect: v => v === "none true" },
        { name: "Ctrl+I opens the site panel in the rail's card, over the rows (the card does not grow), with the keys", focus: "document.activeElement.blur()",
          key: Qt.Key_I, mods: ctrl, wait: 600,
          expect: () => site.open && site.where === "rail" && rail.siting && rail.sitePanel.shown && rail.sitePanel.activeFocus && card() === 40
              && site.security.text === "On this computer" && site.seen.blocked === 1 && site.cookies === 1 && !!rail.sitePanel.target("site:ads") },
        { name: "it lists what the site asked for and nothing it did not", wait: 100,
          expect: () => { const k = check.siteKinds(); return k.indexOf("choice:microphone") >= 0 && k.indexOf("choice:notifications") >= 0
                                                         && k.indexOf("choice:camera") < 0 && k.indexOf("count") === k.indexOf("choice:ads") + 1 } },
        { name: "Esc closes it; the keys go back to the page", key: Qt.Key_Escape, wait: 500, expect: () => !site.open && !rail.siting && view.activeFocus },
        { name: "a click on the favicon opens it", wait: 500, act: () => check.clickFavicon(), expect: () => site.open && rail.siting },
        { name: "a click on the page closes it, and the page gets the click", wait: 500, act: () => check.click(900),
          expect: () => !site.open, page: "log.join()", pageExpect: v => v === "down" },
        { name: "(Ctrl+I)", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 500, expect: () => site.open },
        { name: "a click on Ads and trackers' value lays its choices out in the row", wait: 500, act: () => check.clickSite("site:ads"),
          expect: () => site.expand === "ads" && !!rail.sitePanel.target("site:ads=allow") && site.open },
        { name: "Allowed: the page reloads, nothing refused, the banner shown; the panel stays", wait: 1500, act: () => check.clickSite("site:ads=allow"),
          expect: () => site.choice("ads") === "allow" && site.expand === "" && view.title === "site" && !view.loading
              && app.adblock.seen(String(view.url)).blocked === 0 && site.open && check.siteKinds().indexOf("count") < 0,
          page: "getComputedStyle(banner).display", pageExpect: v => v !== "none" },
        { name: "(Ads and trackers' value)", wait: 500, act: () => check.clickSite("site:ads"), expect: () => site.expand === "ads" },
        { name: "Blocked again: refused and hidden once more", wait: 1500, act: () => check.clickSite("site:ads="),
          expect: () => site.choice("ads") === "" && !view.loading && app.adblock.seen(String(view.url)).blocked === 1 && site.seen.blocked === 1,
          page: "getComputedStyle(banner).display", pageExpect: v => v === "none" },
        { name: "the keys: Tab reaches the first row, Enter lays out its choices on the picked one", wait: 400,
          act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => site.expand === "ads" && rail.sitePanel.target("site:ads=").activeFocus },
        { name: "Esc folds them, the keys back on the row", key: Qt.Key_Escape, wait: 400,
          expect: () => site.expand === "" && site.open && rail.sitePanel.target("site:ads").activeFocus },
        { name: "Esc again closes the panel", key: Qt.Key_Escape, wait: 400, expect: () => !site.open && view.activeFocus },
        { name: "(Ctrl+I; the microphone's value)", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 500,
          act: () => check.later(() => check.clickSite("site:microphone")), expect: () => site.expand === "microphone" },
        { name: "Block: a lasting choice for the site", wait: 500, act: () => check.clickSite("site:microphone=block"),
          expect: () => site.choice("microphone") === "block" && view.sites.choice(check.origin(), "microphone") === "block" },
        { name: "the site's next microphone request is refused at once, with no ask", wait: 1500, act: () => app.go(check.local("/asks"), "navigate"),
          expect: () => view.title === "asks" },
        { name: "(a click asks)", wait: 800, focus: "act = mic", act: () => check.click(),
          expect: () => !view.ask, page: "log.join()", pageExpect: v => /^mic (NotAllowed|Abort)Error$/.test(v) },
        { name: "(back to Ask, and a reload: the engine keeps a refusal for the page load)", wait: 1500,
          act: () => { site.set("microphone", ""); view.reload() }, expect: () => view.title === "asks" && !view.loading && site.choice("microphone") === "" },
        { name: "a click asks again", wait: 800, focus: "act = mic", act: () => check.click(),
          expect: () => view.ask && view.ask.types.join() === "microphone" && !!check.section().model },
        { name: "Site settings in the ask's sheet opens the panel at its row, the ask still in its sheet", wait: 600,
          act: () => check.clickNamed(app.askSheet, "siteSettings"),
          expect: () => site.open && site.expand === "microphone" && site.waiting === "" && view.ask && check.sheetOut() && card() === 40
              && !!rail.sitePanel.target("site:microphone=allow") },
        { name: "Esc folds the row's choices; Esc again closes the panel, the ask still in its sheet", wait: 600,
          act: () => { probe.press(Qt.Key_Escape, 0); probe.press(Qt.Key_Escape, 0) },
          expect: () => !site.open && view.ask && check.sheetOut() },
        { name: "(F6, Esc: denied)", wait: 500, act: () => { probe.press(Qt.Key_F6, 0); probe.press(Qt.Key_Escape, 0) }, expect: () => !view.ask },
        { name: "(the site's page)", wait: 1500, act: () => app.go(check.local("/site"), "navigate"), expect: () => view.title === "site" },
        { name: "(Ctrl+I)", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 500, expect: () => site.open },
        { name: "+ zooms the site to 110 %: the page, and the value at the card's right", wait: 600, act: () => check.clickSite("site:zoom-in"),
          expect: () => Math.abs(view.zoomFactor - 1.1) < 0.001 && site.zoom === 1.1 && rail.addressField.zoomText === "110 %",
          page: "devicePixelRatio", pageExpect: v => Math.abs(v - 1.1) < 0.01 },
        { name: "another page of the site takes its zoom", wait: 1500, act: () => app.go(check.local("/site-other"), "navigate"),
          expect: () => view.title === "site other" && Math.abs(view.zoomFactor - 1.1) < 0.001, page: "devicePixelRatio", pageExpect: v => Math.abs(v - 1.1) < 0.01 },
        { name: "a page of another site does not, though Qt keeps a view's zoom", wait: 1500, act: () => app.go("http://localhost:" + check.port + "/plain", "navigate"),
          expect: () => view.title === "plain" && Math.abs(view.zoomFactor - 1) < 0.001 && rail.addressField.zoomText === "",
          page: "devicePixelRatio", pageExpect: v => Math.abs(v - 1) < 0.01 },
        { name: "back on the site, 110 % again", wait: 1500, act: () => view.goBack(),
          expect: () => view.title === "site other" && Math.abs(view.zoomFactor - 1.1) < 0.001 },
        { name: "Ctrl+0 resets it (P key)", focus: "document.activeElement.blur()", key: Qt.Key_0, mods: ctrl, wait: 500,
          expect: () => Math.abs(view.zoomFactor - 1) < 0.001 && site.choice("zoom") === "" },
        { name: "Ctrl+Plus zooms in", focus: "document.activeElement.blur()", key: Qt.Key_Plus, mods: ctrl, text: "+", wait: 500,
          expect: () => Math.abs(view.zoomFactor - 1.1) < 0.001 },
        { name: "Ctrl+Minus out", focus: "document.activeElement.blur()", key: Qt.Key_Minus, mods: ctrl, text: "-", wait: 500,
          expect: () => Math.abs(view.zoomFactor - 1) < 0.001 && site.choice("zoom") === "" },
        { name: "(the site at 150 %)", wait: 500, act: () => site.setZoom(1.5), expect: () => Math.abs(view.zoomFactor - 1.5) < 0.001 },
        { name: "a link to a site that does not answer, then another site typed before it does: that one commits at its own zoom", wait: 2000,
          focus: () => "location.href = '" + check.served("slow", "/slow") + "'", act: () => check.later(() => app.go("http://localhost:" + check.port + "/plain", "navigate")),
          expect: () => view.title === "plain" && String(view.url).startsWith("http://localhost:") && Math.abs(view.zoomFactor - 1) < 0.001 },
        { name: "(back on the site, its zoom back to 100 %)", wait: 1500, act: () => { view.sites.setZoom(Asks.originOf(check.local("/")), 1); view.goBack() },
          expect: () => view.title === "site other" && Math.abs(view.zoomFactor - 1) < 0.001 },
        { name: "(a page of the site in the background)", wait: 1500,
          act: () => { check.other = session.addPage(session.current.thread, check.local("/site-other"), ""); app.viewFor(check.other).url = check.local("/site-other") },
          expect: () => state(check.other) === 0 && !app.views[check.other].loading },
        { name: "(Ctrl+I; the slash row's value, with no Keep page loaded row)", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 500,
          act: () => check.later(() => check.clickSite("site:slash")), expect: () => site.expand === "slash" && !rail.sitePanel.target("site:keep") },
        { name: "/ opens find Off: `/` on the page stays the site's", wait: 600,
          act: () => { check.clickSite("site:slash=off"); probe.press(Qt.Key_Escape, 0); app.focusPage(); probe.press(Qt.Key_Slash, 0, "/") },
          expect: () => site.choice("slash") === "off" && !site.open && !rail.finder.open },
        { name: "On again: `/` opens find", wait: 500,
          act: () => { site.set("slash", ""); app.focusPage(); probe.press(Qt.Key_Slash, 0, "/") }, expect: () => rail.finder.open },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 300, expect: () => !rail.finder.open },
        { name: "(Ctrl+I)", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 500, expect: () => site.open },
        { name: "All permissions (›) lists every type in place", wait: 500, act: () => check.clickSite("site:all"),
          expect: () => site.sub === "all" && ["camera", "microphone", "location", "notifications", "sound", "popups", "clipboard", "screen"]
              .every(t => check.siteKinds().indexOf("choice:" + t) >= 0) },
        { name: "(Sound's value)", wait: 500, act: () => check.clickSite("site:sound"), expect: () => site.expand === "sound" },
        // the other page discarded right after, as the memory net can: Qt 6.11 drops a mute on discarding
        { name: "Sound Blocked mutes the site's pages, one discarded right after too", wait: 500,
          act: () => { check.clickSite("site:sound=block"); app.setLifecycle(check.other, app.views[check.other], WebEngineView.LifecycleState.Discarded) },
          expect: () => { check.probe.report("     DIAG view muted " + view.audioMuted + " other " + check.other + " state " + state(check.other) + " muted " + (app.views[check.other] ? app.views[check.other].audioMuted : "none") + " url " + (app.views[check.other] ? app.views[check.other].url : "") + " choice " + site.choice("sound") + " expand " + site.expand + " sub " + site.sub + " current " + session.currentPage + " " + view.url + " origin " + site.origin); return view.audioMuted && app.views[check.other].audioMuted && site.choice("sound") === "block" } },
        { name: "‹ goes back", wait: 500, act: () => { site.set("sound", ""); check.clickSite("site:back") },
          expect: () => site.sub === "" && !view.audioMuted && !!rail.sitePanel.target("site:all") },
        { name: "(Esc; Sound Blocked for the site)", wait: 500, act: () => { probe.press(Qt.Key_Escape, 0); site.set("sound", "block") },
          expect: () => !site.open && view.audioMuted },
        { name: "a page of another site in that view is not muted", wait: 1500, act: () => app.go("http://localhost:" + check.port + "/plain", "navigate"),
          expect: () => view.title === "plain" && !view.audioMuted && !session.current.muted },
        { name: "back on the site it is muted again", wait: 1500, act: () => view.goBack(), expect: () => view.title === "site other" && view.audioMuted },
        { name: "(Sound back to Ask)", wait: 300, act: () => site.set("sound", ""), expect: () => !view.audioMuted && !app.views[check.other].audioMuted },
        // Pop-ups without a click: refused, and the glyph at the card's right opens the panel at its row
        { name: "(the site's page)", wait: 1500, act: () => { probe.press(Qt.Key_Escape, 0); app.go(check.local("/site"), "navigate") },
          expect: () => view.title === "site" && !site.open },
        { name: "a pop-up without a click is refused; the glyph at the card's right opens the panel at Pop-ups", wait: 600, focus: "tryOpen()",
          act: () => check.later(() => check.clickNamed(rail.addressField, "popupGlyph")),
          expect: () => view.blockedPopups === 1 && site.open && site.expand === "popups" && !!rail.sitePanel.target("site:popups=allow") },
        { name: "Allowed: the next one opens as a page in the thread without a click", wait: 1500,
          act: () => { check.clickSite("site:popups=allow"); check.rows = session.railOrder().length; check.opener = session.currentPage;
                       check.later(() => app.views[check.opener].runJavaScript("tryOpen()")) },
          expect: () => site.choice("popups") === "allow" && session.railOrder().length === check.rows + 1 && session.currentPage !== check.opener },
        { name: "(that page closed; back on the site's page)", wait: 800,
          act: () => { site.sites.setChoice(check.origin(), "popups", ""); app.closePage(session.currentPage); app.show(check.opener) },
          expect: () => session.currentPage === check.opener && view.title === "site" },
        // Clear, with undo: /site wrote a cookie, local storage, IndexedDB and Cache Storage when it loaded
        { name: "Clear: the site's pages unload at once, the page on screen off the screen, and it counts down", focus: "document.activeElement.blur()",
          key: Qt.Key_I, mods: ctrl, wait: 700, act: () => check.later(() => check.clickSite("site:clear")),
          expect: () => site.clearing && site.left === 6 && !view.visible && state(session.currentPage) === 2 && session.current.state === "unloaded"
              && state(check.other) === 2 && check.siteKinds().join() === "head,split,title,note,action" && site.open },
        { name: "a page of the site opened meanwhile stays unloaded", wait: 400, act: () => app.show(check.other),
          expect: () => !app.views[check.other].visible && state(check.other) === 2 && session.pages[check.other].state === "unloaded" && !site.open },
        { name: "back on its page, the panel shows the countdown again: in 5 s", wait: 600,
          act: () => { app.show(check.opener); app.act("site") },
          expect: () => site.open && site.clearingHere && site.left <= 5 && !view.visible },
        { name: "Undo: nothing cleared; the page back on screen, loading again", wait: 1500, act: () => check.clickSite("site:undo"),
          expect: () => !site.clearing && view.visible && state(check.opener) === 0 && view.title === "site" && !view.loading && SiteData.cookies("127.0.0.1") === 1
              && site.open && check.siteKinds()[1] === "split",
          page: "window.report", pageExpect: v => v === '["v","c=1","db1","c1"]' },
        { name: "Clear again and let the undo run out: its cookies, local storage, IndexedDB and Cache Storage are gone", wait: 8000,
          act: () => check.clickSite("site:clear"),
          expect: () => !site.clearing && view.visible && view.title === "site" && !view.loading && site.open && check.siteKinds()[0] === "head",
          page: "window.report", pageExpect: v => v === '[null,"","",""]' },
        // A certificate the page was let past: the handshake reads what the engine questioned
        { name: "(a page past its certificate: the certificate's page, then Continue)", wait: 1500,
          act: () => { if (!check.tlsPort) check.tlsPort = probe.serveTls(); probe.press(Qt.Key_Escape, 0); app.go("https://cert.test:" + check.tlsPort + "/plain", "navigate") },
          expect: () => view.failure && view.failure.kind === "certificate" },
        { name: "(Continue)", wait: 1500, act: () => app.failureAction(view, "continue"), expect: () => !view.failure && view.questioned !== null },
        { name: "the panel says so in the error tone, with the TLS its own handshake read", focus: "document.activeElement.blur()",
          key: Qt.Key_I, mods: ctrl, wait: 1500,
          expect: () => site.security.text === "Unknown certificate authority" && site.security.tone === "error" && site.security.certificate
              && site.tls.protocol === "TLS 1.3" && site.tls.subject === "cert.test" },
        { name: "› shows the certificate the engine questioned (its SHA-256), and Copy PEM copies it", wait: 600,
          act: () => { check.copied = ""; check.clickSite("site:certificate"); check.later(() => check.clickSite("site:pem")) },
          expect: () => site.sub === "certificate" && view.questioned.details[1].endsWith("SHA-256 " + site.tls.sha256)
              && check.siteKinds().join() === "back,split,pair,pair,pair,pair,text,action" && check.copied.startsWith("-----BEGIN CERTIFICATE-----") },
        { name: "(an https page with an image over plain http: first its certificate's page)", wait: 1500,
          act: () => { probe.press(Qt.Key_Escape, 0); app.go("https://cert.test:" + check.tlsPort + "/mixed#p=" + check.port, "navigate") },
          expect: () => view.failure && view.failure.kind === "certificate" },
        { name: "(Continue)", wait: 1500, act: () => app.failureAction(view, "continue"), expect: () => view.title === "mixed" && !view.loading },
        { name: "Some images load over http, under the security line", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 600,
          expect: () => site.open && site.seen.insecureImages && check.siteKinds()[1] === "note" && site.rows[1].text === "Some images load over http" },
        { name: "(Esc)", wait: 400, act: () => probe.press(Qt.Key_Escape, 0), expect: () => !site.open },
        { name: "(folded)", wait: 1200, act: () => app.railPinned = false, expect: () => !app.railPinned },
        { name: "folded, Ctrl+I brings the overlay out with the panel over its rows, the keys in the panel", focus: "document.activeElement.blur()",
          key: Qt.Key_I, mods: ctrl, wait: 900, act: () => probe.pointer(700, 400),
          expect: () => site.open && site.where === "peek" && peekedRail.siting && peekedRail.sitePanel.shown && peekedRail.sitePanel.activeFocus
              && hoverPeek.held && peekedRail.slide === 1 && !hoverPeek.open && !address.out && !rail.siting },
        { name: "the pointer onto the overlay: its own hold on it comes on too", wait: 300, act: () => probe.pointer(150, 400),
          expect: () => site.open && hoverPeek.open && hoverPeek.held },
        { name: "off it again, past the pointer's 260 ms: the panel stays, and the overlay with it", wait: 700, act: () => probe.pointer(700, 400),
          expect: () => site.open && hoverPeek.out && peekedRail.slide === 1 && !hoverPeek.open },
        { name: "a click on its row keeps it (Ads and trackers' choices out)", wait: 500, act: () => check.clickSite("site:ads"),
          expect: () => site.open && site.expand === "ads" && hoverPeek.out },
        { name: "a click on the page closes it, and the overlay slides back", wait: 1000, act: () => check.click(700),
          expect: () => !site.open && !hoverPeek.out && peekedRail.slide === 0 },
        { name: "(the pointer brings the overlay out)", wait: 800, act: () => { probe.pointer(60, 400); probe.pointer(10, 400) }, expect: () => hoverPeek.open && peekedRail.slide === 1 },
        { name: "its favicon opens the panel in it, and the pointer leaving does not close it", wait: 700,
          act: () => { check.clickFavicon(); probe.pointer(700, 400) },
          expect: () => site.open && site.where === "peek" && peekedRail.sitePanel.activeFocus && hoverPeek.out && !hoverPeek.open },
        { name: "Esc: the panel closes and the overlay slides back; the keys on the page", key: Qt.Key_Escape, wait: 900,
          expect: () => !site.open && !hoverPeek.out && peekedRail.slide === 0 && view.activeFocus },
        { name: "(Ctrl+B pins again)", focus: "document.activeElement.blur()", key: Qt.Key_B, mods: ctrl, wait: 1200, expect: () => app.railPinned },
    ]
    // Single instance (PLAN.md 4, 8 phase 3): this run is the running browser, listening in its throwaway runtime dir,
    // and the links come from second `browser` processes started there as other apps start them.
    readonly property var instanceSteps: [
        { group: "instance" },
        check.server,
        // the main window has the focus: links open there (the links group: while it has not)
        { name: "a second `browser --from foot <address>` hands the link over and exits 0", wait: 3000,
          act: () => { probe.back(); probe.launch(["--from", "foot", check.served("foot", "/plain")]) }, expect: () => check.launchedOk() },
        { name: "the link is a thread of one in front, loaded, and says it came from foot",
          expect: () => session.current.url === check.served("foot", "/plain") && session.currentThread.pages.length === 1
              && session.current.from === "foot" && view.title === "plain" && view.activeFocus },
        { name: "the window's title is the page's title alone while its thread has one page (PLAN.md 3.17)", expect: () => app.title === "plain" },
        { name: "a second page in the thread: \"<page title> · <thread>\"", wait: 1500,
          act: () => app.openHere(check.served("foot", "/login"), "login"), expect: () => app.title === "login · foot.test" },
        { name: "with no --from, run by a shell under a process that owns a window: named by that window's class, a reverse-DNS one by its last part",
          wait: 3000, act: () => probe.launch([check.served("caller", "/plain")], { BROWSER_CHECK_CLIENTS: JSON.stringify([{ pid: probe.pid(), class: "org.quickshell" }]) }, true),
          expect: () => check.launchedOk() && session.current.url === check.served("caller", "/plain") && session.current.from === "quickshell" },
        { name: "with no --from and no window above it, the link names no app", wait: 3000,
          act: () => probe.launch([check.served("nameless", "/plain")]),
          expect: () => check.launchedOk() && session.current.url === check.served("nameless", "/plain") && session.current.from === undefined },
        { name: "`browser` with no address exits 0 and opens nothing", wait: 3000,
          act: () => { check.pageCount = Object.keys(session.pages).length; probe.launch([]) },
          expect: () => check.launchedOk() && Object.keys(session.pages).length === check.pageCount && session.current.url === check.served("nameless", "/plain") },
        { name: "run again from another workspace (Super+W), `browser` with no address brings the window there without following it and focuses it",
          wait: 3000,
          act: () => { Backdrop.fakeClients = JSON.stringify([{ pid: probe.pid(), class: "browser", title: "", address: "0xa", mapped: true, at: [6, 44],
                                                                workspace: { id: 3, name: "3" } }]);
              Backdrop.fakeWorkspace = 4; Backdrop.dispatched = []; probe.launch([]) },
          expect: () => { probe.report("     " + Backdrop.dispatched.join(" | "));
              return check.launchedOk() && Backdrop.dispatched.join("|") === ['dispatch hl.dsp.window.move({ workspace = 4, follow = false, window = "address:0xa" })',
                                                                               'dispatch hl.dsp.focus({ window = "address:0xa" })'].join("|") } },
        { name: "on the workspace it is on already, only the focus", wait: 3000,
          act: () => { Backdrop.fakeWorkspace = 3; Backdrop.dispatched = []; probe.launch([]) },
          expect: () => check.launchedOk() && Backdrop.dispatched.join("|") === 'dispatch hl.dsp.focus({ window = "address:0xa" })' },
        { name: "(no Hyprland again)", act: () => { Backdrop.fakeClients = undefined; Backdrop.fakeWorkspace = undefined; Backdrop.dispatched = [] },
          expect: () => !Backdrop.refresh() },
        { name: "a socket file left by a browser that did not quit cleanly: a start listens in its place",
          act: () => { app.instance.close(); check.stale = probe.staleSocket(app.instance.path); check.started = app.instance.start() },
          expect: () => check.stale && check.started === 0 },
        { name: "and the next link reaches it", wait: 3000,
          act: () => probe.launch(["--from", "foot", check.served("again", "/plain")]),
          expect: () => check.launchedOk() && session.current.url === check.served("again", "/plain") && session.current.from === "foot" },
    ]
    property int pageCount: 0
    property bool stale: false
    property int started: -1
    // the second `browser` exited 0; its time and what it printed go in the log, a line each (tools/check-engine
    // drops the noise lines)
    function launchedOk() {
        const r = probe.launched();
        probe.report("     exit " + r.code + " after " + r.ms + " ms");
        for (const line of r.output.split("\n"))
            if (line.trim())
                probe.report("     | " + line);
        return r.code === 0;
    }
    // Links from other apps (PLAN.md 3.20): handed over while no main window has the focus, as foot's are while you type
    // in foot (probe.away), they open in the main window that had it last, brought forward, as a task of one in front;
    // into an open task when it matches what the app was doing (a shell's folder). No window of their own.
    readonly property var linkSteps: [
        { group: "links" },
        check.server,
        { name: "(a task for a link to join: x1p42100 camera, two pages about camss on the Book4 Edge)",
          act: () => {
              const t = session.newThread("x1p42100 camera");
              for (const [path, title] of [["/plain", "[PATCH v3] camss: x1p42100 CSIPHY lanes"], ["/login", "camss on the Book4 Edge: CSIPHY0 lanes"]])
                  session.update(session.addPage(t, check.served("lore", path), ""), { title: title });
              check.camThread = t;
          }, expect: () => session.threadById(check.camThread) !== null },
        { name: "(the main window loses the focus to foot; this run's socket is in its throwaway runtime dir)", act: () => probe.away(),
          expect: () => { probe.report("     socket: " + app.instance.path); return !app.active && app.instance.path.startsWith("/tmp/") } },
        { name: "a link handed over while no main window has the focus opens in the main window, focused: a task of one in front, from foot",
          wait: 2500, act: () => { check.windows = app.mainWindows.length; probe.launch(["--from", "foot", check.local("/peek")]) },
          expect: () => check.launchedOk() && app.active && session.current.url === check.local("/peek") && session.currentThread.pages.length === 1
              && session.current.from === "foot" && session.threads[0].id === session.current.thread && view.title.startsWith("[PATCH v3 2/4]")
              && app.mainWindows.length === check.windows },
        { name: "a second link, from Signal: a task of its own too", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "Signal", check.local("/peek-two")]) },
          expect: () => check.launchedOk() && app.active && session.current.url === check.local("/peek-two") && session.currentThread.pages.length === 1
              && session.current.from === "Signal" },
        { name: "a link whose address shares words with x1p42100 camera, from an app doing something else: still a task of its own", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "foot", check.served("lore", "/plain")]) },
          expect: () => check.launchedOk() && session.current.url === check.served("lore", "/plain") && session.current.thread !== check.camThread
              && session.currentThread.pages.length === 1 },
        // (the folder names the camera task's words alone: the earlier links' pages are about camss too)
        { name: "a link from a shell in ~/.../book4-edge/camera joins x1p42100 camera, at its end", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "foot", check.local("/peek-four")], {}, false, probe.fixtureDir("book4-edge/camera")) },
          expect: () => { const t = session.threadById(check.camThread);
              return check.launchedOk() && app.active && session.current.thread === check.camThread && t.pages[t.pages.length - 1] === session.currentPage
                  && t.pages.length === 3 && session.current.from === "foot" } },
        { name: "with no main window shown (hidden, as when the link started the browser), a link shows it with the page in front and nothing else loaded",
          wait: 2500,
          act: () => { app.visible = false; probe.away(); check.liveViews = Object.keys(app.views).length; probe.launch(["--from", "foot", check.local("/peek-six")]) },
          expect: () => check.launchedOk() && app.visible && app.active && session.current.url === check.local("/peek-six")
              && Object.keys(app.views).length === check.liveViews + 1 },
    ]
    property string camThread: ""
    property int windows: 0
    property int liveViews: 0
    property int quits: 0
    // printable ASCII, typed through the window system
    function typeText(text) {
        for (const c of text)
            probe.press(c.toUpperCase().charCodeAt(0), 0, c);
    }

    // Several windows (PLAN.md 3.17): Ctrl+N, threads that belong to one window over lists every window shares, @ and
    // Keep across windows, a thread dragged between rails, a window closed and reopened whole, restore with the
    // workspaces asked of Hyprland (faked: Backdrop.fakeClients), the last window closing, and frame pacing.
    readonly property var windowSteps: [
        { group: "windows" },
        check.server,
        { name: "(the main window focused)", act: () => probe.back(app), expect: () => app.active && app.mainWindows.length === 1 },
        { name: "Ctrl+N opens a main window of the same size and fold, transient for none, focused, with its new-page card and an empty rail",
          key: Qt.Key_N, mods: ctrl, wait: 1000,
          expect: () => { const w = check.second();
              return app.mainWindows.length === 2 && w.visible && w.active && !app.active && w.transientParent === null && w.windowId !== ""
                  && w.width === app.width && w.height === app.height && w.railPinned === app.railPinned && w.windowBar.opened
                  && w.windowSession.openThreads().length === 0 && w.windowSession.currentPage === "" && w.title === "Browser" } },
        { name: "an address typed there opens in that window, a thread of its own; the first window's rail and page stay", wait: 3000,
          act: () => { check.firstPage = session.currentPage; check.typeText("harbour.test:" + check.port + "/harbour"); probe.press(Qt.Key_Return, 0) },
          expect: () => { const w = check.second(), s = w.windowSession;
              return String(w.currentView.url) === check.served("harbour", "/harbour") && w.currentView.title === "harbour lights"
                  && s.currentThread.window === w.windowId && session.currentPage === check.firstPage && !check.rowOf("p:" + s.currentPage) } },
        { name: "(in that view the page goes on to lantern notes; a second page, meadow map, joins its thread; orchard walk opens as a thread of one)",
          wait: 3000, act: () => { const w = check.second(); w.go(check.local("/lantern"), "navigate");
              check.later(() => { w.openHere(check.local("/meadow"), "meadow"); w.go(check.local("/orchard"), "new", "", "orchard") }) },
          expect: () => { const w = check.second(), s = w.windowSession;
              check.lantern = check.pageTitled(s, "lantern notes"); check.meadow = check.pageTitled(s, "meadow map"); check.orchard = check.pageTitled(s, "orchard walk");
              check.harbourThread = s.pages[check.lantern].thread;
              return s.openThreads().length === 2 && s.threadById(check.harbourThread).pages.join() === [check.lantern, check.meadow].join()
                  && s.currentPage === check.orchard && w.views[check.lantern].canGoBack } },
        { name: "History, site choices and downloads are the first window's, one of each for every window; the page seen there is in it",
          expect: () => { const w = check.second();
              return w.historyModel === history && w.siteModel === app.siteModel && w.downloadModel === downloads && w.windowSession.downloads === session.downloads
                  && !!history.entries[check.local("/lantern")] } },
        { name: "(the first window focused; Ctrl+T there)", act: () => { probe.back(app); probe.press(Qt.Key_T, ctrl) }, wait: 600,
          expect: () => app.active && newPageBar.opened },
        { name: "@ in the first window finds the page in the second window's rail", wait: 600, act: () => check.typeText("@lantern notes"),
          expect: () => newPageBar.rows.length > 0 && newPageBar.rows[0].kind === "page" && newPageBar.rows[0].pageId === check.lantern },
        { name: "Enter focuses the second window with that page on screen; the first window's page and bar stay put", key: Qt.Key_Return, wait: 1500,
          expect: () => { const w = check.second();
              return w.active && !app.active && w.windowSession.currentPage === check.lantern && w.currentView.title === "lantern notes"
                  && session.currentPage === check.firstPage && !newPageBar.opened } },
        { name: "foot has the focus, the second window having had it last: a link opens there", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "foot", check.local("/peek")]) },
          expect: () => { const w = check.second(), s = w.windowSession;
              return check.launchedOk() && s.current.url === check.local("/peek") && s.currentThread.window === w.windowId && s.current.from === "foot"
                  && w.active && session.currentPage === check.firstPage } },
        { name: "(the second window back on lantern notes)", wait: 800, act: () => check.second().show(check.lantern),
          expect: () => check.second().windowSession.currentPage === check.lantern },
        { name: "a thread dragged from the second window over the first window's rail shows where it lands (the 2 px line before a thread)",
          act: () => { const at = check.rowTop("p:" + check.firstPage);
              probe.dragData(app, at.x, at.y + 2, rail.rowMime, JSON.stringify({ kind: "thread", ref: check.harbourThread }), false) },
          expect: () => rail.incoming !== null && rail.dropTarget.kind === "top" && rail.dropTarget.before === session.pages[check.firstPage].thread },
        { name: "dropped, it moves to the first window above that thread; its views leave the second window, and the page on screen there is on screen here with its back list", wait: 2500,
          act: () => { const at = check.rowTop("p:" + check.firstPage);
              probe.dragData(app, at.x, at.y + 2, rail.rowMime, JSON.stringify({ kind: "thread", ref: check.harbourThread }), true) },
          expect: () => { const w = check.second(), open = session.openThreads().map(t => t.id);
              return rail.incoming === null && session.threadById(check.harbourThread).window === "" && open.indexOf(check.harbourThread) === open.indexOf(session.pages[check.firstPage].thread) - 1
                  && !w.views[check.lantern] && !w.views[check.meadow] && w.windowSession.currentPage !== check.lantern
                  && session.currentPage === check.lantern && view.title === "lantern notes" && app.active
                  && check.historyUrls(view).join() === [check.served("harbour", "/harbour"), check.local("/lantern")].join() } },
        { name: "a single page dropped below a thread's last row in the other rail joins that thread there", wait: 1500,
          act: () => { const at = check.rowCentre("p:" + check.meadow);
              probe.dragData(app, at.x, at.y, rail.rowMime, JSON.stringify({ kind: "page", ref: check.orchard }), true) },
          expect: () => { const t = session.threadById(check.harbourThread);
              return t.pages.join() === [check.lantern, check.meadow, check.orchard].join() && !check.second().views[check.orchard] } },
        { name: "(the second window: a thread of two, brook one and brook two, folded, 1000 x 700)", wait: 3000,
          act: () => { const w = check.second(); probe.back(w); w.go(check.local("/brook"), "new", "", "brook");
              check.later(() => w.openHere(check.local("/brook-two"), "brook")); w.railPinned = false; w.width = 1000; w.height = 700 },
          expect: () => { const w = check.second(), s = w.windowSession;
              check.closedOrder = s.openThreads().map(t => t.id); check.closedTitle = w.title;
              return s.openThreads().length === 2 && s.currentThread.pages.length === 2 && w.currentView.title === "brook two" && !w.railPinned } },
        { name: "closing the second window files its thread of two under History and sends its single page to closed pages; the first window stays", wait: 1500,
          act: () => { check.brookThread = check.second().windowSession.currentThread.id; check.second().close() },
          expect: () => { const c = session.closed, e = c[c.length - 1];
              return app.mainWindows.length === 1 && app.visible && session.threadById(check.brookThread).earlier && e.window && e.title === check.closedTitle
                  && e.state.width === 1000 && e.state.railPinned === false && c[c.length - 2].closedWith === e.window && c[c.length - 2].url === check.local("/peek")
                  && session.reopenName() === "the window " + check.closedTitle } },
        { name: "(the first window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "Ctrl+Shift+T there reopens the whole window: its threads in their order, the filed one out of History, the single page a thread of one, its fold, size and page",
          key: Qt.Key_T, mods: ctrl | Qt.ShiftModifier, wait: 3000,
          expect: () => { const w = check.second(), s = w.windowSession, open = s.openThreads();
              return app.mainWindows.length === 2 && w.active && !w.railPinned && w.width === 1000 && w.height === 700
                  && open.length === 2 && open[check.closedOrder.indexOf(check.brookThread)].id === check.brookThread
                  && !session.threadById(check.brookThread).earlier && session.threadById(check.brookThread).window === w.windowId
                  && s.pages[open[1 - check.closedOrder.indexOf(check.brookThread)].pages[0]].from === "foot"
                  && s.current.url === check.local("/brook-two") && w.currentView.title === "brook two" } },
        { name: "each window's threads, fold, size and page are saved for the next start, the first window first", wait: 300,
          act: () => { session.save(); check.records = Store.load("threads").windows },
          expect: () => { const r = check.records;
              return r.length === 2 && r[0].id === "" && r[0].railPinned === app.railPinned && r[0].width === app.width && r[0].currentPage === session.currentPage
                  && r[1].id === check.second().windowId && r[1].railPinned === false && r[1].width === 1000 && r[1].height === 700
                  && r[1].currentPage === check.second().windowSession.currentPage } },
        { name: "restore with no Hyprland: the window of the last run opens with its threads, fold, size and page; nothing is asked of Hyprland", wait: 2500,
          act: () => { check.restart(); app.openPendingWindows() },
          expect: () => { const w = check.second(), s = w.windowSession;
              return app.mainWindows.length === 2 && w.windowId === check.records[1].id && !w.railPinned && w.width === 1000 && w.height === 700
                  && s.openThreads().map(t => t.id).join() === check.restoredThreads.join() && s.currentPage === check.records[1].currentPage
                  && w.currentView.title === "brook two" && Backdrop.dispatched.length === 0 } },
        { name: "restore under Hyprland: it is asked to move each other window to the workspace it was on without following it (by address); the one started stays where it opened", wait: 2500,
          act: () => { check.restart();
              Backdrop.fakeClients = JSON.stringify(["0xa", "0xb"].map((a, i) => ({ pid: probe.pid(), class: "browser", title: "", address: a, mapped: true,
                                                                                     at: [6 + 960 * i, 44], workspace: { id: 1, name: "1" } })));
              app.workspace = "2"; check.records[1].workspace = "name:web"; app.pendingWindows = [check.records[1]]; app.openPendingWindows() },
          expect: () => { probe.report("     " + Backdrop.dispatched.join(" | "));
              return app.mainWindows.length === 2 && check.second().width === 1000
                  && Backdrop.dispatched.join("|") === 'dispatch hl.dsp.window.move({ workspace = "name:web", follow = false, window = "address:0xb" })' } },
        { name: "(no Hyprland again)", act: () => { Backdrop.fakeClients = undefined; Backdrop.dispatched = []; app.workspace = "" }, expect: () => !Backdrop.refresh() },
        { name: "(each window on a page that moves every frame)", wait: 3000,
          act: () => { check.second().go(check.local("/anim"), "navigate"); app.go(check.local("/anim"), "new", "", "anim") },
          expect: () => view.title === "anim" && check.second().currentView.title === "anim" },
        { name: "(both measured from here for 2 s)", wait: 2000, act: () => check.paceStart([view, check.second().currentView]), expect: () => true },
        { name: "frame pacing offscreen (no compositor, no vsync), both windows' pages moving: each window draws frames", wait: 300,
          act: () => check.paceEnd([view, check.second().currentView]), expect: () => check.paceReport("both pages moving") },
        { name: "(the second window's page moved on to a still one)", wait: 1500, act: () => check.second().go(check.local("/plain"), "navigate"),
          expect: () => check.second().currentView.title === "plain" },
        { name: "(measured again for 2 s)", wait: 2000, act: () => check.paceStart([view]), expect: () => true },
        { name: "frame pacing offscreen, the first window's page alone moving (the second window at rest)", wait: 300,
          act: () => check.paceEnd([view]), expect: () => check.paceReport("first page alone moving") },
        { name: "(the first window on a still page, the pointer out of the windows)", wait: 1500, act: () => { probe.leave(); app.go(check.local("/plain"), "navigate") },
          expect: () => view.title === "plain" },
        { name: "two windows open, nothing changing: no frame in either in 2 s", wait: 2000, act: () => { check.frames = 0; check.secondFrames = 0 },
          expect: () => { probe.report("     frames: " + check.frames + " and " + check.secondFrames); return check.frames === 0 && check.secondFrames === 0 } },
        { name: "closing the first window while the second is open only hides it; its threads filed, its pages closed", wait: 1500,
          act: () => { check.firstOrder = session.openThreads().length; app.close() },
          expect: () => !app.visible && app.mainWindows.length === 2 && session.openThreads().length === 0 && check.second().visible
              && Object.keys(app.views).length === 0 && !!session.closed[session.closed.length - 1].window },
        { name: "Ctrl+Shift+T in the second window brings the first back whole", wait: 3000,
          act: () => { probe.back(check.second()); probe.press(Qt.Key_T, ctrl | Qt.ShiftModifier) },
          expect: () => app.visible && app.active && app.mainWindows.length === 2 && session.openThreads().length === check.firstOrder && view !== null },
        { name: "(the second window closed)", wait: 1500, act: () => check.second().close(), expect: () => app.mainWindows.length === 1 },
        { name: "closing the last main window quits with the session kept, marked clean (counted in check mode)", wait: 1500,
          act: () => { probe.back(app); check.quits = app.quits; app.close() },
          expect: () => app.quits === check.quits + 1 && app.visible && Store.load("run").clean === true
              && Store.load("threads").windows.length === 1 && Store.load("threads").windows[0].id === "" },
        { name: "(the run marked running again)", act: () => app.writeRun({}), expect: () => app.active && Store.load("run").clean === false },
    ]
    property string firstPage: ""
    property string lantern: ""
    property string meadow: ""
    property string orchard: ""
    property string harbourThread: ""
    property string brookThread: ""
    property string closedTitle: ""
    property var closedOrder: []
    property var records: []
    property var restoredThreads: []
    property int firstOrder: 0
    function second() { return app.mainWindows[1] ?? null }
    function pageTitled(s, title) { return Object.keys(s.pages).find(id => s.pages[id].title === title && s.ownOrAlways(id)) ?? "" }
    // the top of a row in the first window's rail, in the window
    function rowTop(key) { const it = rowItem(key); return it.mapToItem(app.contentItem, it.width / 2, 0) }
    // As the next start finds it: the second window gone without filing anything, its saved record pending.
    function restart() {
        const w = second();
        restoredThreads = w.windowSession.openThreads().map(t => t.id);
        w.dropViews(Object.keys(w.views), true);
        app.mainWindows = app.mainWindows.filter(o => o !== w);
        w.visible = false;
        w.destroy();
        app.pendingWindows = [records[1]];
    }
    // the second window's frames (QQuickWindow::frameSwapped)
    property int secondFrames: 0
    property Connections secondFrameCount: Connections {
        target: check.app.mainWindows[1] ?? null
        ignoreUnknownSignals: true
        function onFrameSwapped() { check.secondFrames++ }
    }
    // Frame pacing: each window's frames and each measured page's requestAnimationFrame count over the same span.
    property var pace: ({})
    function paceStart(views) {
        pace = { at: Date.now(), from: views.map(() => -1), to: views.map(() => -1), frames: [] };
        check.frames = 0;
        check.secondFrames = 0;
        views.forEach((v, i) => v.runJavaScript("n", n => pace.from[i] = n));
    }
    function paceEnd(views) {
        pace.frames = [check.frames, check.secondFrames];
        pace.ms = Date.now() - pace.at;
        views.forEach((v, i) => v.runJavaScript("n", n => pace.to[i] = n));
    }
    function paceReport(what) {
        const perS = n => Math.round(n * 1000 / pace.ms);
        const pages = pace.to.map((n, i) => n - pace.from[i]);
        probe.report("     " + what + ", over " + pace.ms + " ms: windows " + pace.frames.map(perS).join(" and ") + " frames/s, pages "
                     + pages.map(perS).join(" and ") + " animation frames/s");
        return pace.frames[0] > 0 && pages.every(n => n > 0) && (pages.length < 2 || pace.frames[1] > 0);
    }

    // The private window (PLAN.md 3.14): Ctrl+Shift+N opens a main window on an off-the-record profile of its own, marked
    // only by its "Private" line. Its pages load from a host named afresh each run (`hush`), which no source file holds,
    // so the last checks can look for it in every file of the throwaway data dir: the stored session, history, site
    // choices, run record and the main profile's own files.
    readonly property var privateSteps: [
        { group: "private" },
        check.server,
        { name: "(the main window focused, on a page of its own; this run's hosts: one for the private pages, one both profiles load)",
          wait: 2000, act: () => {
              const run = Date.now().toString(36);
              check.hush = "hush" + run + ".test";
              check.both = "both" + run + ".test";
              check.quits = app.quits;
              probe.back(app);
              app.go(check.local("/plain"), "new", "", "plain");
              app.siteModel.setZoom(check.bothOrigin(), 1.25);
          },
          expect: () => { probe.report("     private host " + check.hush + ", shared host " + check.both);
              return app.active && view.title === "plain" && app.privateWindows.length === 0 } },
        { name: "Ctrl+Shift+N opens a private window: its own, the size and fold of this one, focused, its new-page card over an empty rail, titled Private, none of the main windows",
          key: Qt.Key_N, mods: ctrl | Qt.ShiftModifier, wait: 1500,
          expect: () => { const w = check.priv();
              return app.privateWindows.length === 1 && w.offTheRecord && w.visible && w.active && !app.active && w.transientParent === null
                  && w.width === app.width && w.height === app.height && w.railPinned === app.railPinned && w.windowBar.opened
                  && w.windowSession.openThreads().length === 0 && w.title === "Private" && app.mainWindows.indexOf(w) < 0 } },
        { name: "its profile is off the record and its own; its session, history, site choices, downloads and cookie list too",
          expect: () => { const w = check.priv();
              probe.report("     storage name \"" + w.profile.storageName + "\", off the record " + w.profile.offTheRecord);
              return w.profile !== null && w.profile.offTheRecord && w.profile.storageName === "" && w.profile !== app.profile
                  && w.windowSession.threads !== session.threads && w.windowSession.downloads !== session.downloads && w.windowSession.closed !== session.closed
                  && w.historyModel !== history && w.siteModel !== app.siteModel && w.downloadModel !== downloads && w.siteData !== null } },
        { name: "its rail's one mark under the nav row: \"Private\" (Theme.font.tiny, the rail's small text) and \"History and cookies end when this window closes.\"; no Always cells",
          expect: () => { const w = check.priv(), note = check.named(w.windowRail, "privateNote");
              return note !== null && note.children[0].text === "Private" && note.children[0].font.pixelSize === Theme.font.tiny
                  && note.children[1].text === "History and cookies end when this window closes." && w.windowRail.cells.length === 0
                  && check.named(rail, "privateNote") === null } },
        { name: "an address typed there opens in it as a thread of one, over http after its https attempt; the title is \"Private · <page title>\"",
          wait: 4000, act: () => { check.typeText(check.hush + ":" + check.port + "/hush"); probe.press(Qt.Key_Return, 0) },
          expect: () => { const w = check.priv(), s = w.windowSession;
              check.hushPage = s.currentPage;
              return w.currentView !== null && String(w.currentView.url) === check.hushed("/hush") && w.currentView.title === "hush one"
                  && s.currentThread.pages.length === 1 && w.title === "Private · hush one" } },
        { name: "the visit is in the private window's history alone; the main window's session and history know nothing of it",
          expect: () => { probe.report("     private history " + !!check.priv().historyModel.entries[check.hushed("/hush")] + " (" + Object.keys(check.priv().historyModel.entries).join(" ")
                                       + "), main history " + check.mentions(history.entries) + ", session " + check.mentions(session.pages) + "/" + check.mentions(session.threads));
              return !!check.priv().historyModel.entries[check.hushed("/hush")] && !check.mentions(history.entries)
                  && !check.mentions(session.pages) && !check.mentions(session.threads) } },
        { name: "a link Ctrl+clicked there joins its thread in the background (opener joining); the title stays the page's", wait: 2500,
          act: () => { const w = check.priv(), p = w.currentView.mapToItem(w.contentItem, 100, 50);
              probe.leave(); probe.pointer(p.x, p.y, 0, ctrl); probe.pointer(p.x, p.y, Qt.LeftButton, ctrl); probe.pointer(p.x, p.y, 0, ctrl) },
          expect: () => { const w = check.priv(), s = w.windowSession, t = s.currentThread;
              check.hushTwo = t.pages[1] ?? "";
              return t.pages.length === 2 && t.pages[0] === check.hushPage && s.currentPage === check.hushPage && s.pages[check.hushTwo].url === check.hushed("/hush-two")
                  && !!w.views[check.hushTwo] && w.views[check.hushTwo].title === "hush two" && w.title === "Private · hush one" } },
        { name: "Ctrl+T there: the new-page card predicts the window's own thread for words its pages share", key: Qt.Key_T, mods: ctrl, wait: 900,
          act: () => check.later(() => check.typeText("hush two")),
          expect: () => { const w = check.priv(); return w.windowBar.opened && w.windowBar.target === w.windowSession.currentThread.id } },
        { name: "(Esc)", key: Qt.Key_Escape, expect: () => !check.priv().windowBar.opened },
        // the card keeps what Esc left in it for 30 s: the prefix goes in with its words, in place of those
        { name: "@ there finds nothing of the main window's (its page titled plain)", wait: 900, act: () => check.priv().windowBar.show("@plain"),
          expect: () => check.priv().windowBar.opened && check.priv().windowBar.rows.length === 0 },
        { name: "and finds the window's own page", wait: 900, act: () => check.priv().windowBar.show("@hush"),
          expect: () => { const r = check.priv().windowBar.rows; return r.length > 0 && r[0].kind === "page" && r[0].pageId === check.hushTwo } },
        { name: "(Esc; the main window focused)", act: () => { probe.press(Qt.Key_Escape, 0); probe.back(app) },
          expect: () => app.active && !check.priv().windowBar.opened },
        { name: "@ in the main window finds nothing of the private window's", wait: 900,
          act: () => { probe.press(Qt.Key_T, ctrl); check.later(() => check.typeText("@hush")) },
          expect: () => newPageBar.opened && newPageBar.rows.length === 0 },
        { name: "(Esc; the private window focused)", act: () => { probe.press(Qt.Key_Escape, 0); probe.back(check.priv()) },
          expect: () => check.priv().active && !newPageBar.opened },
        { name: "Ctrl+W closes a page there; the main window's closed pages get nothing", key: Qt.Key_W, mods: ctrl, wait: 1500,
          expect: () => { const s = check.priv().windowSession, c = s.closed[s.closed.length - 1];
              return !s.pages[check.hushPage] && !!c && c.url === check.hushed("/hush") && s.currentPage === check.hushTwo && !check.mentions(session.closed) } },
        { name: "Ctrl+Shift+T there reopens it, in its thread", key: Qt.Key_T, mods: ctrl | Qt.ShiftModifier, wait: 2500,
          expect: () => { const w = check.priv(), s = w.windowSession;
              check.hushPage = s.currentPage;
              return s.current.url === check.hushed("/hush") && s.currentThread.pages.length === 2 && w.currentView.title === "hush one" } },
        { name: "Ctrl+Shift+W closes the thread of two; nothing files where it shows: no History in this rail, nothing in the main window's",
          key: Qt.Key_W, mods: ctrl | Qt.ShiftModifier, wait: 1500,
          expect: () => { const w = check.priv(), s = w.windowSession;
              return s.openThreads().length === 0 && w.windowRail.rows.every(r => r.type === "hint") && !check.mentions(session.threads) && !check.mentions(session.pages) } },
        { name: "and Ctrl+Shift+T there brings it back whole", key: Qt.Key_T, mods: ctrl | Qt.ShiftModifier, wait: 2500,
          expect: () => { const w = check.priv(), s = w.windowSession;
              return s.openThreads().length === 1 && s.currentThread.pages.length === 2 && s.currentThread.pages.indexOf(check.hushTwo) >= 0 && w.currentView !== null } },
        { name: "(the main window loads a page of the shared host, which sets its cookie there)", wait: 2500,
          act: () => { probe.back(app); app.go(check.bothUrl("/cookie#main"), "new", "", "both") },
          expect: () => view.title === "cookie" && String(view.url).indexOf(check.both) >= 0 },
        { name: "the private window's page there sees no cookie of the main profile's, and sets its own", wait: 2500,
          act: () => { probe.back(check.priv()); check.priv().go(check.bothUrl("/cookie#private"), "new", "", "both") },
          expect: () => { const v = check.priv().currentView; check.bothPage = check.priv().windowSession.currentPage; return v.title === "cookie" },
          pageIn: () => check.priv().currentView, page: "window.before", pageExpect: v => v === "" },
        { name: "each profile's cookie list counts its own one cookie there", wait: 500,
          expect: () => { const w = check.priv(); probe.report("     main " + SiteData.cookies(check.both) + ", private " + w.siteData.cookies(check.both));
              return SiteData.cookies(check.both) === 1 && w.siteData.cookies(check.both) === 1 } },
        { name: "the main window's page, loaded again, sees its own cookie alone", wait: 2500, act: () => { probe.back(app); view.reload() },
          expect: () => view.title === "cookie", page: "window.before", pageExpect: v => v === "main=1" },
        { name: "a site choice of the main profile holds in the private window, copied as it opened: the shared host's page there at 125 %",
          expect: () => check.priv().siteModel.zoom(check.bothOrigin()) === 1.25 && Math.abs(check.priv().views[check.bothPage].zoomFactor - 1.25) < 0.001 },
        { name: "(the private window focused, on its first page)", wait: 1500, act: () => { const w = check.priv(); probe.back(w); w.show(check.hushPage) },
          expect: () => check.priv().active && check.priv().currentView.title === "hush one" },
        { name: "Ctrl+Plus there zooms its site in this window alone: the main profile's choices get nothing", key: Qt.Key_Plus, mods: ctrl, wait: 800,
          expect: () => check.priv().siteModel.zoom(check.hushOrigin()) > 1 && !check.mentions(app.siteModel.entries) },
        { name: "a file from its page lands in Downloads with no record on it of where it came from, listed under that page in this window alone", wait: 2500,
          act: () => check.priv().currentView.runJavaScript("location.href = '/file/quiet.bin?size=3000'"),
          expect: () => { const w = check.priv(), d = w.windowSession.downloads.find(x => x.file.startsWith("quiet"));
              if (d)
                  probe.report("     " + d.path + ", attributes " + JSON.stringify(probe.attributes(d.path)));
              return !!d && d.state === "done" && d.page === check.hushPage && Facts.isFile(d.path) && Object.keys(probe.attributes(d.path)).length === 0
                  && w.windowRail.rows.some(r => r.type === "download" && r.ref === d.id) && !check.mentions(session.downloads)
                  && !rail.rows.some(r => r.type === "download" && r.ref === d.id) } },
        { name: "a link from another app while the private window has the focus opens in the main window that last had it, never the private one",
          wait: 2500, act: () => { check.pageCount = Object.keys(check.priv().windowSession.pages).length; probe.launch(["--from", "foot", check.local("/peek")]) },
          expect: () => { probe.report("     socket: " + app.instance.path);
              return check.launchedOk() && session.current.url === check.local("/peek") && app.active && view.profile === app.profile
                  && Object.keys(check.priv().windowSession.pages).length === check.pageCount } },
        { name: "a main window's thread dragged over the private window's rail finds no place there; dropped, nothing moves", wait: 800,
          act: () => { const w = check.priv(), r = w.windowRail, at = r.mapToItem(w.contentItem, r.width / 2, r.height / 2), row = JSON.stringify({ kind: "thread", ref: session.current.thread });
              check.dragged = session.current.thread;
              probe.dragData(w, at.x, at.y, rail.rowMime, row, false);
              check.incomingSeen = r.incoming !== null;
              probe.dragData(w, at.x, at.y, rail.rowMime, row, true) },
          expect: () => !check.incomingSeen && check.priv().windowRail.incoming === null && !check.priv().windowSession.threadById(check.dragged)
              && session.openThreads().some(t => t.id === check.dragged) },
        { name: "(the private window focused, the pointer out of it)", wait: 1500, act: () => { probe.back(check.priv()); probe.leave() },
          expect: () => check.priv().active },
        // the file it fetched moves from its page's row to the foot Downloads.keepLanded after it finished, with a lift there:
        // that is the window changing, so rest is measured once it has
        { name: "(the private window's file at the foot, its lift over)",
          get wait() { const d = check.priv().windowSession.downloads.find(x => x.file.startsWith("quiet"));
                       return d && d.finished ? Math.max(100, Downloads.keepLanded + 700 - (Date.now() - d.finished)) : 100 },
          expect: () => check.priv().active },
        { name: "the private window at rest draws no frame in 2 s", wait: 2000, act: () => check.privateFrames = 0,
          expect: () => { probe.report("     frames: " + check.privateFrames); return check.privateFrames === 0 } },
        { name: "(the private window focused)", act: () => probe.back(check.priv()), expect: () => check.priv().active },
        { name: "Ctrl+Shift+N there opens a second private window, on a profile of its own", key: Qt.Key_N, mods: ctrl | Qt.ShiftModifier, wait: 1500,
          expect: () => { const b = app.privateWindows[1] ?? null;
              return app.privateWindows.length === 2 && b.active && b.profile.offTheRecord && b.profile !== check.priv().profile && b.windowSession !== check.priv().windowSession } },
        { name: "its page on the shared host sees neither the first private window's cookie nor the main profile's", wait: 2500,
          act: () => app.privateWindows[1].go(check.bothUrl("/cookie#second"), "new", "", "both"),
          expect: () => app.privateWindows[1].currentView.title === "cookie", pageIn: () => app.privateWindows[1].currentView, page: "window.before", pageExpect: v => v === "" },
        { name: "(the second private window closed)", wait: 1500, act: () => app.privateWindows[1].close(), expect: () => app.privateWindows.length === 1 && app.quits === check.quits },
        { name: "closing the private window: it and its profile go, the main window stays; its closed pages, History and Ctrl+Shift+T get nothing", wait: 2000,
          act: () => { check.closedCount = session.closed.length; check.reopen = session.reopenName(); check.privateProfile = check.priv().profile; check.priv().close() },
          expect: () => { probe.report("     its profile afterwards: " + check.privateProfile);
              return app.privateWindows.length === 0 && app.visible && app.quits === check.quits && session.closed.length === check.closedCount
                  && session.reopenName() === check.reopen && !check.privateProfile } },
        { name: "saved as a quit saves: no file under the throwaway data dir holds the private pages' host (the session, history, site choices, run record, the main profile's own files); the shared host's is found",
          wait: 2500, act: () => app.saveAll(),
          expect: () => { const r = probe.filesHolding(check.hush), control = probe.filesHolding(check.both);
              probe.report("     " + r.files + " files, " + Math.round(r.bytes / 1024) + " kB read; holding the private host: " + (r.holding.join(", ") || "none")
                           + "; holding the shared host: " + control.holding.join(", "));
              return r.files > 0 && r.holding.length === 0 && control.holding.length > 0
                  && ["threads", "history", "sites", "run"].every(n => JSON.stringify(Store.load(n) ?? null).indexOf(check.hush) < 0) } },
        { name: "(the run marked running again)", act: () => app.writeRun({}), expect: () => Store.load("run").clean === false },
        { name: "(a private window again, from the main window)", wait: 1500, act: () => { probe.back(app); probe.press(Qt.Key_N, ctrl | Qt.ShiftModifier) },
          expect: () => app.privateWindows.length === 1 && check.priv().active },
        { name: "Ctrl+Q there quits every window, as in a main window (counted in check mode)", key: Qt.Key_Q, mods: ctrl, wait: 1500,
          expect: () => app.quits === check.quits + 1 },
        { name: "(the run marked running again)", act: () => { check.quits = app.quits; app.writeRun({}) }, expect: () => Store.load("run").clean === false },
        { name: "the last main window closed while a private window is open waits hidden, its threads kept as a quit keeps them, its pages unloaded; the private window stays",
          wait: 1500, act: () => { check.firstOrder = session.openThreads().length; check.shown = session.currentPage; app.close() },
          expect: () => !app.visible && check.priv() !== null && check.priv().visible && app.quits === check.quits && session.openThreads().length === check.firstOrder
              && Object.keys(app.views).length === 0 && session.currentPage === check.shown && session.pages[check.shown].state === "unloaded" },
        { name: "Ctrl+N in the private window brings it back, on the page it was on", wait: 2500,
          act: () => { probe.back(check.priv()); probe.press(Qt.Key_N, ctrl) },
          expect: () => app.visible && app.active && app.mainWindows.length === 1 && session.openThreads().length === check.firstOrder
              && session.currentPage === check.shown && view !== null },
        { name: "(the main window closed again, the private window alone)", wait: 1500, act: () => app.close(), expect: () => !app.visible && check.priv().visible },
        { name: "closing the private window then quits, the main window's threads saved for the next start (counted in check mode)", wait: 1500,
          act: () => check.priv().close(),
          expect: () => { const t = Store.load("threads");
              probe.report("     quits " + (app.quits - check.quits) + ", windows " + t.windows.length + ", open threads " + t.threads.filter(x => !x.earlier).length + " of " + check.firstOrder);
              return app.privateWindows.length === 0 && app.quits === check.quits + 1 && t.windows.length === 1
                  && t.threads.filter(x => !x.earlier).length === check.firstOrder } },
        { name: "(the main window back, focused, the run marked running again)", wait: 2000, act: () => { app.showMain(); probe.back(app); app.writeRun({}) },
          expect: () => app.visible && app.active && view !== null && Store.load("run").clean === false },
    ]
    property string hush: ""            // the private pages' host, named afresh each run
    property string both: ""            // a host both profiles load
    property string hushPage: ""
    property string hushTwo: ""
    property string bothPage: ""
    property var privateProfile: null
    property string dragged: ""
    property bool incomingSeen: false
    property int closedCount: 0
    property string reopen: ""
    function priv() { return app.privateWindows[0] ?? null }
    function hushed(path) { return "http://" + hush + ":" + port + path }
    function bothUrl(path) { return "http://" + both + ":" + port + path }
    function hushOrigin() { return Asks.originOf(hushed("/")) }
    function bothOrigin() { return Asks.originOf(bothUrl("/")) }
    // whether `value`, a list or record of the main window's, names the private pages' host
    function mentions(value) { return JSON.stringify(value ?? null).indexOf(hush) >= 0 }
    // the private window's frames (QQuickWindow::frameSwapped)
    property int privateFrames: 0
    property Connections privateFrameCount: Connections {
        target: check.app.privateWindows[0] ?? null
        ignoreUnknownSignals: true
        function onFrameSwapped() { check.privateFrames++ }
    }

    // How the browser's own and special pages read (PLAN.md 3.17's table), in the address card, the editing card, the
    // rail and the window title, a local file from another app among them; then the clean-quit flag (8i) with several
    // windows: a crash with two windows open, a quit from the last window or from the second, and a run started with a link.
    // Settings and Pages and memory have theirs in `ownpages`; the Answer (RailRows.card) gets its steps here once it is built.
    readonly property var internalSteps: [
        { group: "internal" },
        check.server,
        { setup: true, name: "(the main window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "a data: page with no title of its own: the card reads data: page and its size; its content is in no title (the stored one, the rail row, the window, the thread)",
          wait: 1500, act: () => { probe.back(app); app.go(check.dataPage, "new", "", rail.addressField.omni.hostOf(check.dataPage)) },
          expect: () => { const f = rail.addressField, name = "data: page · 4 kB", shown = check.drawn(f).join("|");
              probe.report("     card: " + shown + "; the engine's title starts " + JSON.stringify(view.title.slice(0, 20)));
              return view.title.startsWith("data:") && f.parts.host === name && f.parts.path === "" && session.current.title === ""
                  && check.rowOf("p:" + session.currentPage).title === name && app.title === name && session.currentThread.title === name
                  && shown.indexOf(name) >= 0 && [shown, app.title, session.current.title, session.currentThread.title].every(t => t.indexOf("sesame") < 0) } },
        { name: "Ctrl+L: the editing card holds the data: address, all of it selected", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_L, mods: ctrl, wait: 900,
          expect: () => { const e = check.editor(); return address.editing && e.text === String(view.url) && e.selectedText === e.text && e.text.startsWith("data:text/html,") } },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 800, expect: () => !address.out },
        { name: "about:blank reads Blank page, the globe in the slot", wait: 1500, act: () => app.go("about:blank", "navigate"),
          expect: () => { const f = rail.addressField;
              return String(view.url) === "about:blank" && f.parts.host === "Blank page" && f.parts.path === "" && session.current.title === ""
                  && check.rowOf("p:" + session.currentPage).title === "Blank page" && check.drawn(f).indexOf("language") >= 0 } },
        { name: "a local file: the file glyph (in the card and its rail row), File and its path decoded; the file's name is its title", wait: 1500,
          act: () => { check.filePath = probe.fixtureFile("S2MM006 notes.txt", "lane config"); app.go(check.fileUrl(check.filePath), "navigate") },
          expect: () => { const f = rail.addressField, shown = check.drawn(f), row = check.drawn(check.rowItem("p:" + session.currentPage));
              probe.report("     card: " + shown.join("|") + "; rail row: " + row.join("|") + "; window: " + app.title);
              return f.parts.host === "File" && f.parts.path === check.filePath && shown.indexOf("description") >= 0 && shown.indexOf("File") >= 0
                  && row.indexOf("description") >= 0 && session.current.title === "S2MM006 notes.txt" && app.title === "S2MM006 notes.txt" } },
        { name: "Ctrl+L: the editing card holds its file: address", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_L, mods: ctrl, wait: 900,
          expect: () => { const e = check.editor(); return address.editing && e.text === String(view.url) && e.text.startsWith("file:///") && e.selectedText === e.text } },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 800, expect: () => !address.out },
        { name: "a local PDF shows in the viewer, not downloaded: File and its path; the file's name is its title", wait: 2500,
          act: () => { check.pdfPath = probe.fixtureFile("S2MM006.pdf", check.pdf); check.downloadCount = session.downloads.length;
              app.go(check.fileUrl(check.pdfPath), "navigate") },
          expect: () => { const f = rail.addressField;
              probe.report("     card: " + check.drawn(f).join("|") + "; window: " + app.title);
              return String(view.url) === check.fileUrl(check.pdfPath) && session.downloads.length === check.downloadCount && f.parts.host === "File"
                  && f.parts.path === check.pdfPath && session.current.title === "S2MM006.pdf" && app.title === "S2MM006.pdf" } },
        { name: "a PDF over http: its host and path, as a page", wait: 2500, act: () => app.go(check.local("/sheet.pdf"), "navigate"),
          expect: () => { const f = rail.addressField;
              probe.report("     card: " + check.drawn(f).join("|") + "; window: " + app.title);
              return String(view.url) === check.local("/sheet.pdf") && session.downloads.length === check.downloadCount && f.parts.host === "127.0.0.1:" + check.port
                  && f.parts.path === "/sheet.pdf" && session.current.title === "sheet.pdf" } },
        { name: "(a plain page)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" },
        // DevTools (2026-10-15): Chromium's front end docked under the page, talking to it through Thyris's relay
        { name: "F12: DevTools dock under the page, the front end on Thyris's relay at 127.0.0.1, given the page's document and the keys",
          focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_F12, wait: 5000,
          expect: () => { const d = view.devToolsView, s = view.devToolsState;
              probe.report("     " + (d ? String(d.url).replace(/\/[0-9a-f]{16,}&/, "/<token>&") : "no DevTools view") + "; " + JSON.stringify(s));
              return !!d && /^devtools:\/\/devtools\/bundled\/devtools_app\.html\?ws=127\.0\.0\.1:\d+\/[0-9a-f]{16,}&can_dock=true$/.test(String(d.url))
                  && app.devToolsShown && d.visible && d.height > 100 && d.inspectedView === view && !!s.connected && !!s.document && d.activeFocus } },
        { name: "a right-click on an element, Inspect: the element is shown in Elements", wait: 2500,
          act: () => {
              view.runJavaScript("document.body.insertAdjacentHTML('afterbegin', '<p id=inspected style=\"position:fixed;left:0;top:0;margin:0;padding:24px;background:#fff;z-index:9\">inspect me</p>')");
              check.later(() => { const p = view.mapToItem(app.contentItem, 30, 30); probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.RightButton); probe.pointer(p.x, p.y);
                                  check.later(() => { const m = app.windowPageMenu; check.inspectEntry = m.entries.length > 0 ? m.entries[m.entries.length - 1].action : "";
                                                      m.close(); app.pageMenuPicked(view, "inspect") }) });
          },
          expect: () => { probe.report("     menu's last entry " + check.inspectEntry + "; " + JSON.stringify(view.devToolsState));
              return check.inspectEntry === "inspect" && view.devToolsState.inspected > 0 } },
        // their own ✕ and Dock side (2026-10-16, DevTools.js)
        { name: "DevTools' own controls: ✕ at their toolbar's end, Dock side offering bottom (theirs now) and right only", wait: 1200,
          act: () => { check.dockMenu = null; const d = view.devToolsView;
              d.runJavaScript(check.devToolsDeep + "const x = all(document, []).find(e => e.classList.contains('close-devtools'));"
              + " all(document, []).find(e => e.classList.contains('main-menu')).click();"
              + " setTimeout(() => window.dockMenu = JSON.stringify({ close: !!x && x.checkVisibility(), side: document.body.classList.contains('bottom') ? 'bottom' : 'other',"
              + " dock: all(document, []).filter(e => /current-dock-state-/.test(e.getAttribute('jslog') || '')).map(e => e.getAttribute('jslog').split('current-dock-state-')[1] + (e.checkVisibility() ? '' : ' hidden')) }), 300) })()");
              check.later(() => check.later(() => d.runJavaScript("window.dockMenu", r => check.dockMenu = r))) },
          expect: () => { probe.report("     " + check.dockMenu + "; the view's side " + view.devToolsView.side);
              return check.dockMenu === JSON.stringify({ close: true, side: "bottom", dock: ["undock hidden", "left hidden", "bottom", "right"] }) && view.devToolsView.side === "bottom" } },
        { name: "Dock to right picked there: the card at the page's right, as tall as the page, the side kept", wait: 1500,
          act: () => view.devToolsView.runJavaScript(check.devToolsDeep + "all(document, []).find(e => /current-dock-state-right/.test(e.getAttribute('jslog') || '')).click() })()"),
          expect: () => { const d = view.devToolsView, a = app.devToolsArea, p = view.mapToItem(app.contentItem, 0, 0);
              probe.report("     side " + app.devToolsSide + "/" + (d && d.side) + "; page " + Math.round(p.x) + "," + Math.round(p.y) + " " + view.width + "x" + view.height
                           + "; DevTools " + a.x + "," + a.y + " " + a.width + "x" + a.height + "; kept " + JSON.stringify(Store.load("devtools")));
              return app.devToolsSide === "right" && !!d && d.side === "right" && Math.abs(a.x - (p.x + view.width + app.inset)) < 1 && Math.abs(a.y - p.y) < 1
                  && a.height === view.height && Math.abs(a.width - app.devToolsWidthShown) < 1 && d.width === a.width && Store.load("devtools").side === "right" } },
        { name: "their ✕: DevTools close as F12 closes them, the page whole with the keys", wait: 1500,
          act: () => view.devToolsView.runJavaScript(check.devToolsDeep + "all(document, []).find(e => e.classList.contains('close-devtools')).click() })()"),
          expect: () => !view.devToolsView && !app.devToolsShown && view.activeFocus && app.devToolsArea.children.every(c => !c.inspectedView) },
        { name: "F12: DevTools open docked right, their front end told so", key: Qt.Key_F12, wait: 4000,
          expect: () => { const d = view.devToolsView;
              probe.report("     side " + app.devToolsSide + "/" + (d && d.side) + "; " + JSON.stringify(view.devToolsState));
              return !!d && app.devToolsShown && d.side === "right" && !!view.devToolsState.document && app.devToolsArea.x > view.mapToItem(app.contentItem, 0, 0).x + view.width } },
        { name: "F12 again: DevTools close, the page whole again with the keys", key: Qt.Key_F12, wait: 1500,
          expect: () => !view.devToolsView && !app.devToolsShown && Object.keys(view.devToolsState).length === 0 && view.activeFocus
              && app.devToolsArea.children.every(c => !c.inspectedView) },
        { name: "DevTools closed, a spare is readied: their front end loaded with no page, unseen", wait: 4000,
          expect: () => { check.spare = app.devToolsSpare; return !!check.spare && check.spare.loaded && !check.spare.visible && !check.spare.inspectedView } },
        { name: "a page of its own, Ctrl+Shift+I: it takes the spare, loaded, which gets the page's document", wait: 3000,
          act: () => { app.go(check.local("/plain"), "new", "", "devtools page"); check.later(() => { app.focusPage(); probe.press(Qt.Key_I, ctrl | Qt.ShiftModifier) }) },
          expect: () => !!view.devToolsView && view.devToolsView === check.spare && !!view.devToolsState.document && app.devToolsSpare === null },
        { name: "closing that page closes its DevTools", wait: 1500, act: () => app.closePage(session.currentPage),
          expect: () => !app.devToolsShown && app.devToolsArea.children.every(c => !c.inspectedView) && view.title === "plain" },
        { name: "(DevTools back to the bottom)", wait: 200, act: () => app.dockDevTools("bottom"),
          expect: () => app.devToolsSide === "bottom" && Store.load("devtools").side === "bottom" },
        { name: "view source (Ctrl+U): a new page in this thread reading Source of <host> and the path", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_U, mods: ctrl, wait: 1500,
          expect: () => { const f = rail.addressField, name = "Source of 127.0.0.1:" + check.port;
              probe.report("     card: " + check.drawn(f).join("|") + "; the engine's title " + JSON.stringify(view.title));
              return String(view.url) === "view-source:" + check.local("/plain") && f.parts.host === name && f.parts.path === "/plain"
                  && session.current.title === "" && check.rowOf("p:" + session.currentPage).title === name + " /plain" && session.currentThread.pages.length === 2 } },
        { name: "Ctrl+L: the editing card holds the view-source: address", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_L, mods: ctrl, wait: 900, expect: () => address.editing && check.editor().text === "view-source:" + check.local("/plain") },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 800, expect: () => !address.out },
        { name: "an error page: the address that failed, ! in the slot", wait: 1500,
          act: () => app.go("http://down.test:" + probe.closedPort() + "/lane", "navigate"),
          expect: () => { const f = rail.addressField;
              return view.failure && f.parts.host.startsWith("down.test:") && f.parts.path === "/lane" && check.drawn(f).indexOf("warning") >= 0 } },
        { name: "Ctrl+L: the editing card holds that address", key: Qt.Key_L, mods: ctrl, wait: 900,
          expect: () => address.editing && check.editor().text === view.failure.url && view.failure.url.startsWith("http://down.test:") },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 800, expect: () => !address.out },
        { name: "a file that is not there: File and its path, ! in the slot; no address in its title", wait: 1500,
          act: () => app.go("file:///nonexistent/S2MM006.txt", "navigate"),
          expect: () => { const f = rail.addressField;
              return view.failure && f.parts.host === "File" && f.parts.path === "/nonexistent/S2MM006.txt" && check.drawn(f).indexOf("warning") >= 0
                  && session.current.title === "" && check.rowOf("p:" + session.currentPage).title === "File /nonexistent/S2MM006.txt"
                  && app.title.startsWith("File /nonexistent/S2MM006.txt · ") } },
        { name: "a local file from another app opens as a page: its address reads File and its path, the file glyph in the slot", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "foot", check.fileUrl(check.filePath)]) },
          expect: () => { const f = rail.addressField, shown = check.drawn(f);
              probe.report("     address: " + shown.join("|") + "; the window: " + app.title);
              return check.launchedOk() && f.parts.host === "File" && f.parts.path === check.filePath
                  && shown.indexOf("description") >= 0 && app.title === "S2MM006 notes.txt" } },
        { name: "(the page closed)", wait: 1500, act: () => app.closePage(session.currentPage), expect: () => session.current?.url !== check.fileUrl(check.filePath) },
        // The clean-quit flag (8i) with several windows.
        { name: "(a second window, on a page of its own, the last page shown)", wait: 3000,
          act: () => { probe.back(app); app.go(check.local("/plain"), "new", "", "plain"); probe.press(Qt.Key_N, ctrl);
              check.later(() => check.second().go(check.local("/orchard"), "new", "", "orchard")) },
          expect: () => { const w = check.second(); check.crashPage = w ? w.windowSession.currentPage : "";
              return app.mainWindows.length === 2 && w.currentView.title === "orchard walk" } },
        { name: "running, the record says so: both windows saved, the run not clean, the page shown last the second window's", wait: 1200,
          act: () => session.save(),
          expect: () => { const r = Store.load("run"), t = Store.load("threads");
              check.records = t.windows;
              return r.clean === false && r.page === check.crashPage && t.windows.length === 2 && t.windows[1].id === check.second().windowId } },
        { name: "a crash with two windows open: the next start restores both with nothing loaded, the first offering the page that was on screen", wait: 2500,
          act: () => { check.restart(); app.startAfter(Store.load("run")); app.openPendingWindows() },
          expect: () => { const w = check.second(), s = w ? w.windowSession : null;
              return app.mainWindows.length === 2 && w.windowId === check.records[1].id && s.openThreads().some(t => t.pages.indexOf(check.crashPage) >= 0)
                  && s.currentPage === "" && Object.keys(w.views).length === 0 && session.currentPage === "" && app.currentView === null
                  && Object.keys(app.views).every(id => !app.views[id].visible) && ownPage.visible
                  && ownPage.page.actions.map(a => a.label).join() === "Open orchard walk" } },
        { name: "Open (Tab, Enter): the page shows in its own window, which takes the focus; the first window's restore page goes, and the page is suspect in the record",
          wait: 2000, act: () => { probe.back(app); app.takeRestore(); probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => { const w = check.second(), r = Store.load("run");
              return w.active && w.windowSession.currentPage === check.crashPage && w.currentView.title === "orchard walk" && !app.restorePage
                  && app.noPage && app.windowBar.opened && r.clean === false && r.suspect === check.crashPage && r.page === check.crashPage } },
        { name: "Ctrl+Q in the second window: quits (counted in check mode) with both windows kept, marked clean", wait: 1500,
          act: () => { check.quits = app.quits; probe.back(check.second()); probe.press(Qt.Key_Q, ctrl) },
          expect: () => app.quits === check.quits + 1 && Store.load("run").clean === true && Store.load("threads").windows.length === 2 },
        { name: "(the run marked running again; the second window closed)", wait: 1500, act: () => { app.writeRun({}); check.second().close() },
          expect: () => app.mainWindows.length === 1 && Store.load("run").clean === false },
        // A run started with a link (PLAN.md 3.20): the main window hidden and the run record not started until the link
        // shows it.
        { name: "(as a start with a link finds it: the last run closed cleanly, the main window hidden on a page of its own)", wait: 1000,
          act: () => { app.show(check.pageTitled(session, "plain")); app.runStarted = false; Store.save("run", { clean: true }); app.visible = false },
          expect: () => !app.visible && !app.runStarted },
        { name: "the link shows the main window with its page in front and starts the run: the record this run's", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "foot", check.local("/peek-four")]) },
          expect: () => { const r = Store.load("run");
              return check.launchedOk() && app.visible && app.runStarted && session.current.url === check.local("/peek-four") && !app.restorePage
                  && r.clean === false && r.page === session.currentPage } },
        { name: "(the last run did not close cleanly, with a page on screen; as a start with a link finds it)", wait: 1000,
          act: () => { check.shown = session.currentPage; check.crashRecord = { clean: false, alive: Date.now() - 120000, page: check.shown };
              Store.save("run", check.crashRecord); app.runStarted = false; app.visible = false },
          expect: () => !app.visible && !app.runStarted },
        { name: "a link then starts the run on its page, as a page opened at a start does: the record this run's", wait: 2500,
          act: () => { probe.away(); probe.launch(["--from", "foot", check.local("/peek-five")]) },
          expect: () => { const r = Store.load("run");
              return check.launchedOk() && app.visible && app.runStarted && session.current.url === check.local("/peek-five") && !app.restorePage
                  && r.clean === false && r.page === session.currentPage && r.alive > check.crashRecord.alive } },
    ]
    property var ownRecord: null
    property string filePath: ""
    property string pdfPath: ""
    property int downloadCount: 0
    property string crashPage: ""
    property var crashRecord: null
    // a 4096-byte HTML page with no title, as a data: address; its words never show outside the page
    readonly property string dataPage: "data:text/html," + encodeURIComponent("<p>" + "open sesame ".repeat(340) + "okay</p>")
    function fileUrl(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }
    // the visible texts and glyphs under `item`, as drawn
    function drawn(item) {
        const out = [];
        const walk = it => {
            if (!it.visible || it.opacity === 0)
                return;
            if (typeof it.text === "string" && it.text !== "")
                out.push(it.text);
            for (const c of it.children)
                walk(c);
        };
        walk(item);
        return out;
    }
    // the address card's text field while it edits
    function editor() {
        const find = it => {
            if (it.cursorRectangle !== undefined && it.selectedText !== undefined)
                return it;
            for (const c of it.children) {
                const f = find(c);
                if (f)
                    return f;
            }
            return null;
        };
        return find(address);
    }
    // a one-page PDF, its cross-reference table at the offsets it has
    readonly property string pdf: {
        const objs = ["<</Type/Catalog/Pages 2 0 R>>", "<</Type/Pages/Kids[3 0 R]/Count 1>>", "<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>"];
        let out = "%PDF-1.4\n";
        const at = [];
        objs.forEach((o, i) => { at.push(out.length); out += (i + 1) + " 0 obj" + o + "endobj\n" });
        const xref = out.length;
        out += "xref\n0 " + (objs.length + 1) + "\n0000000000 65535 f \n" + at.map(n => String(n).padStart(10, "0") + " 00000 n \n").join("");
        return out + "trailer<</Size " + (objs.length + 1) + "/Root 1 0 R>>\nstartxref\n" + xref + "\n%%EOF\n";
    }

    // What phase 3's review found (PLAN.md 3.12, 3.17): links sent while the browser quits or is busy, an Always cell
    // removed while another window shows it, and Hyprland's windows matched and placed once a window was shown again or
    // closed (Backdrop.fakeClients).
    readonly property var edgeSteps: [
        { group: "edges" },
        check.server,
        { name: "(the main window focused, on a page of its own)", wait: 1500,
          act: () => { probe.back(app); app.go(check.local("/plain"), "new", "", "plain") }, expect: () => app.active && view.title === "plain" },
        { name: "a quit takes no link from its start: the socket closes while Hyprland is asked where the windows are (check mode then listens again)",
          wait: 600, act: () => { check.quits = app.quits; Backdrop.fakeClients = "[]"; app.quitAll(); check.listened = app.instance.listening },
          expect: () => !check.listened && app.quits === check.quits + 1 && app.instance.listening },
        { name: "(no Hyprland again; the run marked running again)", act: () => { Backdrop.fakeClients = undefined; app.writeRun({}) },
          expect: () => Store.load("run").clean === false },
        // the link is sent into the socket while the browser is busy (1.5 s), and the socket closes before it is answered
        { name: "a link sent as the browser stops taking links (a quit starting) is dropped unanswered: its `browser` tries again, and nothing opens",
          wait: 1500, act: () => { probe.back(); check.pageCount = Object.keys(session.pages).length; probe.launch(["--from", "foot", check.served("waiting", "/plain")]);
                                   for (const until = Date.now() + 1500; Date.now() < until;) {} app.instance.close() },
          expect: () => probe.launched().code === -1 && Object.keys(session.pages).length === check.pageCount },
        { name: "it hands the link to the browser that listens next (this one again here) and exits 0", wait: 1500, act: () => app.instance.start(),
          expect: () => check.launchedOk() && session.current.url === check.served("waiting", "/plain") && session.current.from === "foot" },
        { name: "a browser busy past the 5 s its answer is waited for: `browser` exits 0, saying the link opens when it answers", wait: 1500,
          act: () => { check.pageCount = Object.keys(session.pages).length; probe.launch(["--from", "foot", check.served("busy", "/plain")]);
                       for (const until = Date.now() + 6500; Date.now() < until;) {} },
          expect: () => check.launchedOk() && /has not answered yet; it opens the link when it does/.test(probe.launched().output) },
        { name: "and the link opens once the browser runs again, once", expect: () => session.current.url === check.served("busy", "/plain")
              && Object.keys(session.pages).length === check.pageCount + 1 },
        // Remove from Always (PLAN.md 3.12, 3.17) while another window shows the cell's page
        { name: "(an Always cell, its page on screen in a second window)", wait: 3000,
          act: () => { check.cell = session.addAlways(check.served("cell", "/plain"), "", ""); probe.press(Qt.Key_N, ctrl);
                       check.later(() => check.second().show(check.cell)) },
          expect: () => { const w = check.second();
              return app.mainWindows.length === 2 && w.windowSession.currentPage === check.cell && w.currentView === w.views[check.cell] && w.currentView.title === "plain" } },
        { name: "Unpin in the first window: the page's view goes in the second too, which shows its next page (none: the new-page card)",
          wait: 1000, act: () => { probe.back(app); app.command("removeAlways", check.cell) },
          expect: () => { const w = check.second();
              return !session.pages[check.cell] && !w.views[check.cell] && !app.views[check.cell] && w.windowSession.currentPage === "" && w.currentView === null
                  && w.windowBar.opened } },
        { name: "(the second window closed)", wait: 1000, act: () => check.second().close(), expect: () => app.mainWindows.length === 1 },
        // Backdrop (PLAN.md 3.17) with Hyprland's list faked: what would go to Hyprland is in Backdrop.dispatched
        { name: "(two main windows on pages of one title)", wait: 3000,
          act: () => { probe.back(app); app.go(check.local("/plain"), "new", "", "plain"); probe.press(Qt.Key_N, ctrl);
                       check.later(() => check.second().go(check.local("/plain"), "new", "", "plain")) },
          expect: () => app.mainWindows.length === 2 && app.title === "plain" && check.second().title === "plain" },
        { name: "the first window hidden and shown again maps anew, after the second: windows of one title are matched to Hyprland's in the order shown",
          wait: 800,
          act: () => { app.visible = false; app.visible = true; Backdrop.dispatched = [];
              Backdrop.fakeClients = JSON.stringify(["0xb", "0xa"].map(a => ({ pid: probe.pid(), class: "browser", title: "plain", address: a, mapped: true,
                                                                               at: [6, 44], workspace: { id: 1, name: "1" } })));
              Backdrop.focus(app) },
          expect: () => { probe.report("     " + Backdrop.dispatched.join(" | ")); return Backdrop.dispatched.join("|") === 'dispatch hl.dsp.focus({ window = "address:0xa" })' } },
        { name: "a window closed while Hyprland is asked where to place the windows: the others are placed, the one gone left alone", wait: 1500,
          act: () => { const w = check.second(); Backdrop.dispatched = [];
              Backdrop.fakeClients = JSON.stringify([{ pid: probe.pid(), class: "browser", title: "plain", address: "0xa", mapped: true, at: [6, 44],
                                                       workspace: { id: 1, name: "1" } }]);
              Backdrop.place([{ window: w, workspace: "3" }, { window: app, workspace: "2" }]);
              check.later(() => w.close()) },
          expect: () => { probe.report("     " + Backdrop.dispatched.join(" | "));
              return app.mainWindows.length === 1 && Backdrop.dispatched.join("|") === 'dispatch hl.dsp.window.move({ workspace = 2, follow = false, window = "address:0xa" })' } },
        { name: "(no Hyprland again; the main window focused, the run marked running)", act: () => { Backdrop.fakeClients = undefined; Backdrop.dispatched = []; probe.back(app); app.writeRun({}) },
          expect: () => !Backdrop.refresh() && app.active && Store.load("run").clean === false },
    ]
    property string cell: ""
    property bool listened: true
    // a click at `x`, `y` on popup window `w`'s page, through the window system
    function clickPopupPage(w, x, y) {
        const p = w.card.pageSlot.mapToItem(w.contentItem, x, y);
        probe.back(w);
        probe.leave();
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }

    // With nothing changing on screen the window draws no frame: nothing animates or polls into a redraw on its own.
    // Recall (PLAN.md 3.7): where you stopped, taken when you leave a page, before it unloads, before its thread files,
    // before it closes and at a quit; a filed thread and a closed page coming back there (by the heading, so content
    // added above it since does not move you off it); History in the rail, opened in place; @; Saved edited in place and
    // saved threads; forgetting with its undo; the folded overlay; and a private window, which asks before it saves.
    property string recallThread: ""
    property var recall: ({})           // the thread's pages: headings, plain, long (2000 headings), top (not scrolled)
    property real captureMs: -1
    property var longStop: null
    property string savedId: ""
    property string recallFile: ""
    property var recallPriv: null
    property string recallHost: ""
    property string shownStop: ""
    property int channelLines: 0
    property string heldClosed: ""
    property string pwEditKey: ""
    property bool clearingAtQuit: false
    function recallPage(path) {
        const t = session.threadById(check.recallThread);
        return t ? t.pages.find(id => session.pages[id].url === check.local(path)) ?? "" : "";
    }
    function stopOf(id) { return session.pages[id] ? session.pages[id].stopped ?? null : null }
    function recallUrl(path) { return "http://" + check.recallHost + ":" + check.port + path }
    readonly property var recallSteps: [
        { group: "recall" },
        check.server,
        { name: "(a thread of four pages: headings under a sticky header on screen, and in the background none, 2000 headings over 600 000 px, a short page)",
          wait: 3000, act: () => {
              probe.back(app);
              app.go(check.local("/recall-h"), "new", "", "recall");
              check.recallThread = session.current.thread;
              for (const path of ["/recall-plain", "/recall-long", "/plain"])
                  app.go(check.local(path), "new", check.recallThread, "", "", true);
              check.recall = { headings: session.currentPage, plain: check.recallPage("/recall-plain"), long: check.recallPage("/recall-long"), top: check.recallPage("/plain") };
          },
          expect: () => { const r = check.recall;
              return view.title === "recall headings" && app.views[r.plain].title === "recall plain" && app.views[r.long].title === "recall long" && app.views[r.top].title === "plain" } },
        { name: "leaving a page keeps where you stopped: under \u201cChanges in v3\u201d, 200 px into it; the sticky header's h1 is not it", wait: 800,
          focus: "scrollTo(0, 1780)", act: () => app.show(check.recall.plain),
          expect: () => { const s = check.stopOf(check.recall.headings);
              probe.report("     " + JSON.stringify(s));
              return !!s && s.heading === "Changes in v3" && s.offset === 200 && s.y === 1780 && Recall.line(s) === "stopped at \u201cChanges in v3\u201d" } },
        { name: "a page without headings: \u201c42 % down\u201d", wait: 800,
          focus: "scrollTo(0, Math.round(0.42 * (document.documentElement.scrollHeight - innerHeight)))", act: () => app.show(check.recall.long),
          expect: () => { const s = check.stopOf(check.recall.plain); return !!s && s.heading === "" && s.percent === 42 && Recall.line(s) === "42 % down" } },
        { name: "a very long page (2000 headings, 600 000 px): \u201cSection 1500\u201d, 100 px into it, answered within 500 ms", wait: 1200,
          focus: "scrollTo(0, 1499 * 300 + 100)",
          act: () => {
              const t0 = Date.now();
              view.captureStop(s => { check.captureMs = Date.now() - t0; check.longStop = s });
              check.later(() => app.show(check.recall.top));
          },
          expect: () => { const s = check.stopOf(check.recall.long);
              probe.report("     answered in " + check.captureMs + " ms; " + JSON.stringify(s));
              return check.captureMs >= 0 && check.captureMs < 500 && !!check.longStop && check.longStop.heading === "Section 1500"
                  && !!s && s.heading === "Section 1500" && s.offset === 100 && s.y === 449800 } },
        { name: "a page you did not scroll keeps nothing", wait: 800, act: () => app.show(check.recall.headings),
          expect: () => check.stopOf(check.recall.top) === null && view.title === "recall headings" },
        { name: "before the memory net unloads it: a page its own script scrolled while unseen says where it is now (80 % down), and unloads", wait: 1500,
          act: () => {
              app.views[check.recall.plain].runJavaScript("scrollTo(0, Math.round(0.8 * (document.documentElement.scrollHeight - innerHeight)))");
              check.later(() => { unseenFor(check.recall.plain, 100000); check.netTick(check.lowMemory) });
          },
          expect: () => { const s = check.stopOf(check.recall.plain);
              return !!s && s.percent === 80 && state(check.recall.plain) === 2 } },
        { name: "Ctrl+Shift+W files the thread; the page on screen says where you stopped first (\u201c0x4E action register\u201d), then its view goes",
          focus: "scrollTo(0, 3170)", key: Qt.Key_W, mods: ctrl | Qt.ShiftModifier, wait: 1200,
          expect: () => { const s = check.stopOf(check.recall.headings), t = session.threadById(check.recallThread);
              return !!t && t.earlier && !!s && s.heading === "0x4E action register" && s.offset === 50 && !app.views[check.recall.headings] && !app.views[check.recall.long] } },
        { name: "Ctrl+H: History, the rail's list from its foot, the search taking the keys; the task opened in place shows where you stopped on each page",
          wait: 1000, focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_H, mods: ctrl,
          act: () => check.later(() => app.command("historyOpen", check.recallThread, true)),
          expect: () => { const r = check.recall, lines = [r.headings, r.plain, r.long, r.top].map(id => (check.rowOf("f:" + id) ?? {}).origin);
              probe.report("     " + JSON.stringify(lines));
              return rail.inEarlier && app.earlier.view === "history" && rail.earlierFocused && check.rowOf("e:" + check.recallThread).open
                  && JSON.stringify(lines) === JSON.stringify(["stopped at \u201c0x4E action register\u201d", "80 % down", "stopped at \u201cSection 1500\u201d", ""]) } },
        { name: "the search reads where you stopped too: \u201csection\u201d leaves this task alone", wait: 800, act: () => check.type("section"),
          expect: () => { const rows = rail.rows.filter(x => x.type === "earlier" || x.type === "closed");
              return app.earlier.filter === "section" && rows.length === 1 && rows[0].ref === check.recallThread } },
        { name: "Down, Shift+Delete: the task forgotten, \u201cForgot recall \u00b7 Undo\u201d in the card", wait: 800,
          act: () => { probe.press(Qt.Key_Down, 0); probe.press(Qt.Key_Delete, Qt.ShiftModifier) },
          expect: () => session.threadById(check.recallThread) === null && !!app.cardNotice && app.cardNotice.text === "Forgot recall"
              && check.drawn(rail.addressField).indexOf("Undo") >= 0 && !history.entries[check.local("/recall-long")] },
        { name: "Undo brings it back, where you stopped and all", wait: 800, act: () => check.clickNamed(rail.addressField, "noticeAction"),
          expect: () => { const t = session.threadById(check.recallThread);
              return !!t && t.earlier && check.stopOf(check.recall.long).heading === "Section 1500" && app.cardNotice === null && !!history.entries[check.local("/recall-long")] } },
        { name: "Esc goes back to the rail's own list, with no History in it", key: Qt.Key_Escape, wait: 800,
          expect: () => !rail.inEarlier && app.earlier.filter === "" && !rail.rows.some(r => r.type === "earlier" || r.type === "closed") },
        { name: "the foot's History opens it", wait: 800, act: () => check.clickAt(check.named(rail, "foot:history")),
          expect: () => app.earlier.view === "history" && rail.inEarlier },
        { name: "(Esc: the rail's own list)", key: Qt.Key_Escape, wait: 800, expect: () => !rail.inEarlier },
        { name: "@ finds the thread by where you stopped: \u201c0x4e\u201d, with the page it comes back at and that heading", wait: 800,
          act: () => newPageBar.show("@0x4e"),
          expect: () => { const r = newPageBar.rows[0];
              return newPageBar.opened && !!r && r.kind === "earlier" && r.threadId === check.recallThread
                  && r.lines.map(l => l.text).join("|") === "recall headings|stopped at \u201c0x4E action register\u201d" } },
        { name: "Enter brings the thread back: its last page loads and goes back under \u201c0x4E action register\u201d; the others stay unloaded",
          key: Qt.Key_Return, wait: 3000,
          expect: () => { const t = session.threadById(check.recallThread), r = check.recall;
              return !!t && !t.earlier && session.currentPage === r.headings && view.title === "recall headings" && !app.views[r.plain] && session.pages[r.plain].state === "unloaded" },
          page: "scrollY", pageExpect: v => { probe.report("     scrollY " + v); return Math.abs(v - 3170) <= 2 } },
        { name: "a page's row in History brings the task back with that page current: the long page, at \u201cSection 1500\u201d again", wait: 4000,
          act: () => {
              app.fileThread(check.recallThread);
              app.openEarlier("history");
              app.command("historyOpen", check.recallThread, true);
              check.later(() => check.clickRow("f:" + check.recall.long));
          },
          expect: () => session.currentPage === check.recall.long && view.title === "recall long" && !rail.inEarlier,
          page: Recall.capture, world: WebEngineScript.ApplicationWorld,
          pageExpect: v => { probe.report("     " + v); const a = JSON.parse(v); return a.heading === "Section 1500" && Math.abs(a.y - 449800) <= 2 } },
        { name: "the heading, not the pixel: 400 px added above it since, the page comes back under the same heading", wait: 3000,
          focus: "localStorage.setItem('shift', '400')",
          act: () => { app.fileThread(check.recallThread); app.restoreThread(check.recallThread, check.recall.headings) },
          expect: () => session.currentPage === check.recall.headings && view.title === "recall headings",
          page: "scrollY", pageExpect: v => { probe.report("     scrollY " + v); return Math.abs(v - 3570) <= 2 } },
        { name: "(Ctrl+W: closed, where you stopped asked first)", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_W, mods: ctrl, wait: 1000,
          expect: () => { const c = session.closed[session.closed.length - 1];
              return !session.pages[check.recall.headings] && !!c && c.url === check.local("/recall-h") && !!c.stopped && Math.abs(c.stopped.y - 3570) <= 2 } },
        { name: "Ctrl+Shift+T: the closed page comes back where you stopped", key: Qt.Key_T, mods: ctrl | Qt.ShiftModifier, wait: 3000,
          expect: () => { check.recall = Object.assign({}, check.recall, { headings: session.currentPage });
              return session.current.url === check.local("/recall-h") && session.current.thread === check.recallThread && view.title === "recall headings" },
          page: "scrollY", pageExpect: v => { probe.report("     scrollY " + v); return Math.abs(v - 3570) <= 2 } },
        { name: "Ctrl+D saves the page: \u201cSaved \u00b7 Edit\u201d in the card", focus: "localStorage.removeItem('shift'); document.activeElement && document.activeElement.blur()",
          key: Qt.Key_D, mods: ctrl, wait: 800,
          expect: () => { const p = app.savedModel.pageByUrl(check.local("/recall-h"));
              check.savedId = p ? p.id : "";
              return !!p && p.name === "recall headings" && !!app.cardNotice && app.cardNotice.text === "Saved" && check.drawn(rail.addressField).indexOf("Edit") >= 0 } },
        { name: "Edit: Saved, the page's row turned into its edit, its name taking the keys", wait: 1000,
          act: () => check.clickNamed(rail.addressField, "noticeAction"),
          expect: () => app.earlier.view === "saved" && app.earlier.editing === check.savedId && rail.nameInput.activeFocus && rail.nameInput.selectedText === "recall headings" },
        { name: "a new name, Enter: renamed in place, the row back", wait: 800, act: () => { check.type("notes"); probe.press(Qt.Key_Return, 0) },
          expect: () => app.savedModel.pageById(check.savedId).name === "notes" && app.earlier.editing === "" && (check.rowOf("s:" + check.savedId) ?? {}).title === "notes" },
        { name: "Edit with the filter hiding its row (as the card's Saved \u00b7 Edit can come): the filter emptied, its row an edit with the keys", wait: 1000,
          act: () => { app.command("earlierFilter", "", "nothing like it"); check.later(() => app.editSaved(check.savedId)) },
          expect: () => app.earlier.filter === "" && app.earlier.editing === check.savedId && rail.nameInput.activeFocus && rail.nameInput.selectedText === "notes" },
        { name: "(Enter: the row back)", key: Qt.Key_Return, wait: 800, expect: () => app.earlier.editing === "" && (check.rowOf("s:" + check.savedId) ?? {}).title === "notes" },
        { name: "F2 on it edits it again; Remove takes it out", wait: 1200,
          act: () => { probe.press(Qt.Key_F2, 0); check.later(() => check.clickNamed(rail, "edit:remove")) },
          expect: () => app.savedModel.pageById(check.savedId) === null && app.earlier.editing === "" && !check.rowOf("s:" + check.savedId) },
        { name: "Save task (as its menu does): Saved tasks lists it; a click on it brings back the task it came from", wait: 2500,
          act: () => {
              app.command("saveThread", check.recallThread);
              app.fileThread(check.recallThread);
              app.openEarlier("saved");
              check.later(() => check.clickRow("st:" + app.savedModel.threads[0].id));
          },
          expect: () => { const t = session.threadById(check.recallThread), st = app.savedModel.threads[0];
              return st.pages.length === 4 && st.title === "recall" && !!t && !t.earlier && !rail.inEarlier && session.current.thread === t.id } },
        { name: "the thread it came from forgotten, it opens as a new thread of its pages, the first on screen and the others unloaded", wait: 2500,
          act: () => { app.fileThread(check.recallThread); app.forget("earlier", check.recallThread); app.openSavedThread(app.savedModel.threads[0].id) },
          expect: () => { const t = session.currentThread;
              return !!t && t.id !== check.recallThread && t.title === "recall" && t.pages.length === 4 && session.current.url === check.local("/recall-plain")
                  && view.title === "recall plain" && t.pages.slice(1).every(id => session.pages[id].state === "unloaded") } },
        { name: "@: Shift+Delete forgets a history row, \u201cForgot \u2026 \u00b7 Undo\u201d on the card's last line", wait: 1000,
          act: () => { history.visit("https://forget.test/row", "forgettable row"); newPageBar.show("@forgettable"); check.later(() => probe.press(Qt.Key_Delete, Qt.ShiftModifier)) },
          expect: () => !history.entries["https://forget.test/row"] && !!app.cardNotice && app.cardNotice.where === "jump" && check.named(newPageBar, "undo") !== null },
        { name: "Undo there brings it back", wait: 800, act: () => check.clickNamed(newPageBar, "undo"),
          expect: () => !!history.entries["https://forget.test/row"] && app.cardNotice === null },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 600, expect: () => !newPageBar.opened },
        { name: "(the page on screen's address again in a thread of its own)", wait: 2500,
          act: () => app.go(check.local("/recall-plain"), "new", "", "recall plain again"),
          expect: () => view.title === "recall plain" && session.currentThread.pages.length === 1
              && Object.keys(session.pages).filter(id => session.pages[id].url === check.local("/recall-plain")).length === 2 },
        { name: "(Ctrl+W: closed)", focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_W, mods: ctrl, wait: 1000,
          expect: () => { const c = session.closed[session.closed.length - 1]; check.heldClosed = c ? c.id : "";
              return !!c && c.url === check.local("/recall-plain") && Object.keys(session.pages).some(id => session.pages[id].url === check.local("/recall-plain")) } },
        { name: "that closed page forgotten: its address stays in history, as another page holds it", wait: 300,
          act: () => app.forget("closed", check.heldClosed),
          expect: () => !session.closed.some(c => c.id === check.heldClosed) && !!history.entries[check.local("/recall-plain")] && app.cardNotice !== null },
        { name: "(Undo)", act: () => app.runNotice(), expect: () => session.closed.some(c => c.id === check.heldClosed) && app.cardNotice === null },
        { name: "Ctrl+J: Downloads, every file kept", focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_J, mods: ctrl, wait: 800,
          act: () => { check.recallFile = session.addDownload({ file: "recall-notes.txt", path: Disk.downloads + "/recall-notes.txt", state: "done",
                                                                 started: Date.now() + 60000, finished: Date.now() }) },
          expect: () => app.earlier.view === "downloads" && rail.rows.filter(r => r.type === "download").length === session.downloads.length },
        { name: "Down, Enter: the newest file, first in the list, opens (a dry run)", wait: 800,
          act: () => { probe.press(Qt.Key_Down, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => rail.listFocused && Apps.lastOpened === Disk.downloads + "/recall-notes.txt" && session.downloadById(check.recallFile).opened > 0 },
        { name: "Ctrl+Shift+O: Saved", key: Qt.Key_O, mods: ctrl | Qt.ShiftModifier, wait: 800, expect: () => app.earlier.view === "saved" },
        { name: "Esc: the rail's own list", key: Qt.Key_Escape, wait: 800, expect: () => app.earlier.view === "" },
        { name: "folded, Ctrl+H brings the overlay out in History and holds it", wait: 1500,
          act: () => { app.railPinned = false; check.later(() => { app.focusPage(); probe.press(Qt.Key_H, ctrl) }) },
          expect: () => !app.railPinned && hoverPeek.out && peekedRail.inEarlier && peekedRail.earlierFocused },
        { name: "a click on the page puts it back", wait: 1200, act: () => check.click(700), expect: () => app.earlier.view === "" && !hoverPeek.out },
        { name: "(pinned again)", wait: 1500, act: () => app.railPinned = true, expect: () => app.railPinned && !app.railMoving },
        // the other ways a page on screen goes: a thread of one filed (as Ctrl+W), a window closed while another stays,
        // the last main window set aside while a private window is open
        { name: "(a thread of one on a headings page)", wait: 2500, act: () => app.go(check.local("/recall-one"), "new", "", "recall one"),
          expect: () => view.title === "recall one" && session.currentThread.pages.length === 1 },
        { name: "Ctrl+Shift+W on a thread of one closes it as Ctrl+W does, where you stopped asked first", focus: "scrollTo(0, 1780)",
          key: Qt.Key_W, mods: ctrl | Qt.ShiftModifier, wait: 1200,
          expect: () => { const c = session.closed[session.closed.length - 1];
              return !!c && c.url === check.local("/recall-one") && !!c.stopped && c.stopped.heading === "Changes in v3" && c.stopped.y === 1780
                  && !Object.keys(session.pages).some(id => session.pages[id].url === check.local("/recall-one")) } },
        { name: "Ctrl+Shift+T: back there", key: Qt.Key_T, mods: ctrl | Qt.ShiftModifier, wait: 3000,
          expect: () => session.current.url === check.local("/recall-one") && view.title === "recall one",
          page: "scrollY", pageExpect: v => { probe.report("     scrollY " + v); return Math.abs(v - 1780) <= 2 } },
        { name: "(a second window, a headings page on screen there, scrolled)", wait: 3000,
          act: () => { const w = app.newWindow(app.windowState(), ""); w.afterClose(); probe.back(w); w.go(check.local("/recall-two"), "new", "", "recall two");
              check.later(() => check.later(() => w.currentView.runJavaScript("scrollTo(0, 3170)"))) },
          expect: () => !!check.second() && !!check.second().currentView && check.second().currentView.title === "recall two" },
        { name: "closing it: the page on screen says where you stopped first, for its closed entry", wait: 1500, act: () => check.second().close(),
          expect: () => { const c = session.closed, e = c[c.length - 1], single = c[c.length - 2];
              return app.mainWindows.length === 1 && !!e.window && single.closedWith === e.window && single.url === check.local("/recall-two")
                  && !!single.stopped && single.stopped.heading === "0x4E action register" } },
        { name: "(the first window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "Ctrl+Shift+T brings the window back, its page where you stopped", key: Qt.Key_T, mods: ctrl | Qt.ShiftModifier, wait: 3000,
          expect: () => app.mainWindows.length === 2 && !!check.second().currentView && check.second().currentView.title === "recall two",
          pageIn: () => check.second().currentView, page: "scrollY", pageExpect: v => { probe.report("     scrollY " + v); return Math.abs(v - 3170) <= 2 } },
        { name: "(the second window closed again)", wait: 1500, act: () => check.second().close(), expect: () => app.mainWindows.length === 1 },
        { name: "(its entry out of the closed list; the first window focused)", act: () => { session.takeWindow(); probe.back(app) }, expect: () => app.active },
        { name: "(the recall thread's short page on screen again)", wait: 2000,
          act: () => { const t = session.threads.find(x => x.title === "recall" && !x.earlier);
              app.show(t.pages.find(id => session.pages[id].url === check.local("/recall-plain"))) },
          expect: () => session.currentThread.title === "recall" && view.title === "recall plain" && !view.loading },
        { name: "(a private window on a host named afresh, the headings page on screen)", wait: 3000,
          act: () => {
              check.recallHost = "hushrecall" + Date.now().toString(36) + ".test";
              const w = app.newPrivateWindow(app.windowState());
              check.recallPriv = w;
              w.afterClose();
              probe.back(w);
              w.go(check.recallUrl("/recall-h"), "new", "", "private recall");
          },
          expect: () => !!check.recallPriv.currentView && check.recallPriv.currentView.title === "recall headings" },
        { name: "where you stopped there stays in its own lists", wait: 2000,
          act: () => { const w = check.recallPriv; w.currentView.runJavaScript("scrollTo(0, 1780)"); check.later(() => w.go(check.recallUrl("/plain"), "new", "", "plain")) },
          expect: () => { const s = check.recallPriv.windowSession, id = Object.keys(s.pages).find(k => s.pages[k].url === check.recallUrl("/recall-h"));
              return !!id && !!s.pages[id].stopped && s.pages[id].stopped.heading === "Changes in v3" && check.recallPriv.currentView.title === "plain" } },
        { name: "Ctrl+D there asks \u201cSave to the main profile?\u201d", wait: 800,
          act: () => { probe.back(check.recallPriv); check.recallPriv.focusPage(); probe.press(Qt.Key_D, ctrl) },
          expect: () => { const v = check.recallPriv.currentView, s = check.recallPriv.askSheet.section;
              return !!v.ask && v.ask.kind === "save" && !!s.model && s.model.lines[0].text === "Save to the main profile?" && !app.savedModel.pageByUrl(check.recallUrl("/plain")) } },
        { name: "Save: into the main profile's Saved, and nothing else of the window is written (saved as a quit saves)", wait: 800,
          act: () => { const v = check.recallPriv.currentView; v.answer(v.ask, "save", {}); check.later(() => app.saveAll()) },
          expect: () => { const f = probe.filesHolding(check.recallHost);
              probe.report("     files holding the private host: " + JSON.stringify(f.holding));
              return !!app.savedModel.pageByUrl(check.recallUrl("/plain")) && !check.recallPriv.currentView.ask
                  && f.holding.length === 1 && f.holding[0].endsWith("/saved.json") } },
        { name: "the last main window closed while the private window is open: set aside, the page on screen says where you stopped first", wait: 1500,
          act: () => {
              check.shownStop = session.currentThread.pages.find(id => session.pages[id].url === check.local("/recall-plain"));
              app.show(check.shownStop);
              check.later(() => { view.runJavaScript("scrollTo(0, Math.round(0.3 * (document.documentElement.scrollHeight - innerHeight)))"); app.close() });
          },
          expect: () => { const s = check.stopOf(check.shownStop);
              return !app.visible && check.recallPriv.visible && Object.keys(app.views).length === 0 && !!s && s.percent === 30 } },
        { name: "Ctrl+N in the private window brings it back, that page where you stopped", wait: 3000,
          act: () => { probe.back(check.recallPriv); probe.press(Qt.Key_N, ctrl) },
          expect: () => app.visible && session.currentPage === check.shownStop && view !== null && view.title === "recall plain",
          page: "Math.round(100 * scrollY / (document.documentElement.scrollHeight - innerHeight))", pageExpect: v => { probe.report("     " + v + " %"); return Math.abs(v - 30) <= 1 } },
        { name: "(the private window closed; the main window focused)", wait: 1500,
          act: () => { check.recallPriv.close(); probe.back(app) }, expect: () => app.privateWindows.length === 0 && app.active },
        { name: "(the headings page of that thread on screen)", wait: 2500,
          act: () => app.show(session.currentThread.pages.find(id => session.pages[id].url === check.local("/recall-h"))),
          expect: () => view.title === "recall headings" && !view.loading },
        { name: "a quit asks the page on screen where you stopped, for the next start (counted in check mode)", wait: 1500,
          act: () => { check.quits = app.quits; view.runJavaScript("scrollTo(0, 3170)"); check.later(() => app.quitAll()) },
          expect: () => { const p = Store.load("threads").pages[session.currentPage];
              return app.quits === check.quits + 1 && !!p && !!p.stopped && p.stopped.heading === "0x4E action register" } },
        { name: "(the run marked running again)", act: () => app.writeRun({}), expect: () => Store.load("run").clean === false },
    ]
    // The browser's own pages (PLAN.md 3.15, 3.17): Settings and Pages and memory, drawn over their browser:// pages; each
    // setting taking effect at once where PLAN says so, and kept in settings.json. Clicks and keys go in through the
    // window system; the Downloads folder and an extension's folder are picked through Picker's dry run, the default
    // browser is only recorded (Apps' dry run), and Update now runs a script of the check's own.
    function own() { return app.windowSettings }
    function ownRow(key) { return own().rows.find(r => r.key === key) ?? null }
    function clickOwn(name, page) {
        // Settings shows one section at a time: the one holding the row first
        if (!page)
            own().reach(name);
        const t = (page ?? own()).target(name);
        if (!t)
            throw new Error("nothing named " + name);
        (page ?? own()).reveal(t);
        const p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    // the own page's target `name` within the view of its rows, under the fixed top
    function ownShown(name) {
        const t = own().target(name), f = own().flick;
        const y = t ? t.mapToItem(f, 0, 0).y : -1;
        return !!t && y >= 0 && y + t.height <= f.height;
    }
    // the engine gives a browser:// address its "/"
    function ownPages(url) { return Object.keys(session.pages).filter(id => session.pages[id].url.replace(/\/$/, "") === url && session.ownOrAlways(id)) }
    function fontsView() { return app.views[check.fontsPage] }
    property string fontsPage: ""
    property string settingsId: ""
    property string monoFamily: ""
    property real widthBefore: 0
    property var menuSeen: null
    property string inspectEntry: ""        // DevTools: the page menu's last entry when Inspect is picked
    property var dockMenu: null             // DevTools: their ✕ and Dock side as their page has them
    // DevTools: the start of a script for their page that finds its elements through the shadow roots, all(document, [])
    readonly property string devToolsDeep: "(() => { const all = (r, o) => { for (const e of r.querySelectorAll('*')) { o.push(e); if (e.shadowRoot) all(e.shadowRoot, o) } return o }; "
    property var spare: null                // DevTools: the spare readied after they closed
    property bool cacheCleared: false
    property string extDir: ""
    property string pickedDir: ""
    property int cookiesBefore: 0
    property string defaultBefore: ""
    property string langsBefore: ""
    property var ownPriv: null
    property Connections contextMenus: Connections {
        target: check.view
        ignoreUnknownSignals: true
        function onContextMenuRequested(request) {
            check.menuSeen = { word: request.misspelledWord, suggestions: request.spellCheckerSuggestions };
            request.accepted = true;
        }
    }
    property Connections cacheClears: Connections {
        target: check.app.profile
        ignoreUnknownSignals: true
        function onClearHttpCacheCompleted() { check.cacheCleared = true }
    }
    readonly property var ownSteps: [
        { group: "ownpages" },
        check.server,
        { setup: true, name: "(the main window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "(the fonts page, a thread of its own)", wait: 2000,
          act: () => { probe.back(app); app.go(check.local("/fonts"), "new", "", "fonts") },
          expect: () => { check.fontsPage = session.currentPage; return view.title === "fonts" && !view.loading } },
        { name: "(its text measured in the browser's own fonts)", wait: 300, pageIn: () => check.fontsView(), page: "s.getBoundingClientRect().width",
          expect: () => true, pageExpect: v => { check.widthBefore = v; return v > 0 } },
        { name: "(the languages the page is told before Settings sets any)", wait: 300, pageIn: () => check.fontsView(), page: "window.langs",
          expect: () => true, pageExpect: v => { check.langsBefore = v; probe.report("     " + v + "; Settings reads " + app.defaultLanguages); return v === app.defaultLanguages.join() } },
        { name: "Ctrl+, opens Settings as a thread of one: [·] Settings in the card and its rail row, the window's title, the keys in its filter",
          focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_Comma, mods: ctrl, wait: 1500,
          expect: () => { const f = rail.addressField, s = check.own(), row = check.rowOf("p:" + session.currentPage);
              check.settingsId = session.currentPage;
              probe.report("     card: " + check.drawn(f).join("|") + "; window: " + app.title + "; engine title " + JSON.stringify(view.title) + "; url " + view.url
                           + "; row " + JSON.stringify(row) + "; filter focused " + s.target("own:filter").activeFocus);
              return String(view.url) === "browser://settings/" && view.title === "Settings" && app.ownKind === "settings" && s.visible && !view.failure
                  && !view.ask && session.currentThread.pages.length === 1 && f.parts.host === "Settings" && check.drawn(f).indexOf("settings") >= 0
                  && !!row && row.title === "Settings" && row.glyph === "settings" && app.title === "Settings" && s.target("own:filter").activeFocus } },
        { name: "Ctrl+L: the editing card holds browser://settings", key: Qt.Key_L, mods: ctrl, wait: 900,
          expect: () => address.editing && check.editor().text === "browser://settings" },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 900, expect: () => !address.out },
        { name: "Ctrl+, again, from the fonts page: the same Settings page, never a second", wait: 1200,
          act: () => { app.show(check.fontsPage); check.later(() => probe.press(Qt.Key_Comma, ctrl)) },
          expect: () => session.currentPage === check.settingsId && check.ownPages("browser://settings").length === 1 && check.own().visible },
        { name: "typing filters: “cookies” leaves Privacy with Clear browsing data and Third-party cookies", wait: 700,
          act: () => { check.own().first.forceActiveFocus(); check.type("cookies") },
          expect: () => check.own().filter === "cookies" && check.own().rows.map(r => r.key).join() === "head:privacy,clear,thirdPartyCookies" },
        { name: "Esc empties the filter; the keys stay in it", key: Qt.Key_Escape, wait: 500,
          expect: () => check.own().filter === "" && check.own().target("own:filter").activeFocus && check.own().rows.length > 50 },
        { name: "Tab reaches the first row, Enter lays its choices out in the row with the picked one focused", wait: 600,
          act: () => { probe.press(Qt.Key_Tab, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => check.own().expand === "engine" && !!check.own().target("own:engine=duckduckgo") && check.own().target("own:engine=duckduckgo").activeFocus },
        { name: "Esc folds them, the row keeping the keys", key: Qt.Key_Escape, wait: 600,
          expect: () => check.own().expand === "" && check.own().target("own:engine").activeFocus },
        { name: "a click on the value and on Google: row 1 of a search names Google at once, and settings.json keeps it", wait: 1000,
          act: () => { check.clickOwn("own:engine"); check.later(() => check.clickOwn("own:engine=google")) },
          expect: () => { const r = rail.omni.suggest("libcamera agc", "")[0];
              return app.prefs.get("engine") === "google" && r.url === "https://www.google.com/search?q=libcamera%20agc" && r.detail === "Google"
                  && check.ownRow("engine").value === "Google" && (Store.load("settings") ?? {}).engine === "google" } },
        { name: "Default zoom +: an open page of a site with no zoom of its own takes 110 % at once, and its card shows none, as it is the default",
          wait: 800, act: () => check.clickOwn("own:zoom:plus"),
          expect: () => Math.abs(check.fontsView().zoomFactor - 1.1) < 0.001 && app.windowSite.sites.defaultZoom === 1.1 && check.ownRow("zoom").value === "110 %" },
        { name: "(the fonts page: no zoom in its card; Ctrl+0 keeps the default)", wait: 1000,
          act: () => { app.show(check.fontsPage); check.later(() => { app.focusPage(); probe.press(Qt.Key_0, ctrl) }) },
          expect: () => rail.addressField.zoomText === "" && Math.abs(view.zoomFactor - 1.1) < 0.001 },
        // the click 500 ms after Settings is shown again: 250 ms was not always enough (one run in two)
        { name: "Default zoom back to 100 %", wait: 1200, act: () => { app.show(check.settingsId); check.later(() => check.later(() => check.clickOwn("own:zoom:minus"))) },
          expect: () => { probe.report("     " + JSON.stringify({ page: check.fontsView().zoomFactor, pref: app.prefs.get("zoom"), file: (Store.load("settings") ?? {}).zoom,
                                                                   shown: app.ownKind, row: (check.ownRow("zoom") ?? {}).value }));
              return Math.abs(check.fontsView().zoomFactor - 1) < 0.001 && app.prefs.get("zoom") === 1 && !("zoom" in (Store.load("settings") ?? { zoom: 0 })) } },
        { name: "Fonts ›, a family picked from those that hold the words typed: the open page's text takes it at once", wait: 1200,
          act: () => {
              check.monoFamily = Engine.families(true).find(f => /mono/i.test(f)) ?? Engine.families(true)[0];
              check.own().openView("fonts");
              check.later(() => { check.own().edit("font:standard", check.monoFamily); check.later(() => check.clickOwn("own:font:standard=" + check.monoFamily)) });
          },
          pageIn: () => check.fontsView(), page: "s.getBoundingClientRect().width",
          expect: () => { probe.report("     family " + check.monoFamily + "; the engine's: " + JSON.stringify(Engine.fonts(app.profile)));
              return Engine.fonts(app.profile).standard === check.monoFamily && check.own().sub === "fonts" && check.ownRow("font:standard").value === check.monoFamily },
          pageExpect: v => { probe.report("     width " + check.widthBefore + " -> " + v); return v > 0 && Math.abs(v - check.widthBefore) > 1 } },
        { name: "Font size +: 18 px in the open page at once", wait: 900, act: () => check.clickOwn("own:fontSize:plus"),
          pageIn: () => check.fontsView(), page: "getComputedStyle(document.body).fontSize",
          expect: () => check.ownRow("fontSize").value === "18 px" && Engine.fonts(app.profile).size === 18, pageExpect: v => v === "18px" },
        // Chromium applies a new minimum at a page's next load, not to the document it has (measured, 2.5 s after)
        { name: "Minimum size 12 px, the page loaded again: its 6 px line is drawn at 12 px; the row says when a page takes it", wait: 1800,
          act: () => { check.own().openView(""); app.prefs.set("minimumFont", 12); check.later(() => check.fontsView().reload()) },
          pageIn: () => check.fontsView(), page: "JSON.stringify([getComputedStyle(tiny).fontSize, tiny.getBoundingClientRect().height])",
          expect: () => { probe.report("     " + JSON.stringify(Engine.fonts(app.profile)));
              return Engine.fonts(app.profile).minimum === 12 && (check.ownRow("minimum-note") ?? {}).label === "A page takes the minimum when it loads again." },
          pageExpect: v => { probe.report("     the 6 px line: " + v); const a = JSON.parse(v); return a[0] === "12px" || a[1] >= 12 } },
        { name: "(the fonts back to the browser's own: Tacit Sans and Tacit Mono where Settings sets none)", wait: 900,
          act: () => { app.prefs.set("fonts", {}); app.prefs.set("minimumFont", 0) },
          pageIn: () => check.fontsView(), page: "[getComputedStyle(document.body).fontSize, s.getBoundingClientRect().width].join()",
          expect: () => { const f = Engine.fonts(app.profile); return f.standard === "Tacit Sans" && f.sansSerif === "Tacit Sans" && f.fixed === "Tacit Mono" },
          pageExpect: v => { const [size, width] = String(v).split(","); return size === "16px" && Math.abs(Number(width) - check.widthBefore) < 0.5 } },
        { name: "a change is saved by a quit before its 500 ms are up (saved as a quit saves)", wait: 100,
          act: () => { app.prefs.set("minimumFont", 9); app.saveAll() }, expect: () => (Store.load("settings") ?? {}).minimumFont === 9 },
        { name: "(Minimum size Off again; the run marked running again)", wait: 900, act: () => { app.prefs.set("minimumFont", 0); app.writeRun({}) },
          expect: () => !("minimumFont" in (Store.load("settings") ?? {})) && Store.load("run").clean === false },
        { name: "Languages typed in place: every page's Accept-Language and, loaded again, navigator.languages", wait: 1800,
          act: () => { check.own().openView(""); check.own().commit("languages", "sv-SE, en"); check.later(() => check.fontsView().reload()) },
          pageIn: () => check.fontsView(), page: "window.langs",
          expect: () => app.profile.httpAcceptLanguage === "sv-SE,en;q=0.9" && check.ownRow("languages").value === "sv-SE, en", pageExpect: v => v === "sv-SE,en" },
        { name: "Spell check On, with hunspell's en_GB there: converted into the engine's dictionaries and in use for en-GB", wait: 4000,
          act: () => {
              probe.fixtureFile("hunspell/en_GB.aff", "SET UTF-8\nTRY esianrtolcdugmphbyfvkwz\n");
              probe.fixtureFile("hunspell/en_GB.dic", "3\nhello\nworld\nbrowser\n");
              check.own().commit("languages", "en-GB");
              app.prefs.set("spellCheck", true);
          },
          expect: () => { probe.report("     dictionaries " + JSON.stringify(Engine.dictionaries(["en-GB"])) + " in " + Engine.dictionaryFolder()
                                       + "; profile " + app.profile.spellCheckEnabled + " " + app.profile.spellCheckLanguages);
              return Engine.dictionaries(["en-GB"])["en-GB"] === "ready" && app.profile.spellCheckEnabled && app.profile.spellCheckLanguages.join() === "en-GB"
                  && !check.ownRow("dictionaries") } },
        { name: "(the misspelt field on screen, clicked into as you would: its caret in it)", wait: 3000,
          act: () => { app.show(check.fontsPage); check.later(() => { check.fontsView().reload(); check.later(() => check.later(() => check.later(() =>
              { const p = view.mapToItem(app.contentItem, 300, 260); probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
                view.runJavaScript("t.setSelectionRange(1, 1)") }))) }) },
          expect: () => view.title === "fonts" && !view.loading },
        { name: "a right-click on “helo”: the page's menu has it as misspelt; Thyris's own menu opens, its suggestions first, then the field's edits",
          wait: 1500,
          act: () => { check.menuSeen = null; const p = view.mapToItem(app.contentItem, 12, 210); probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.RightButton); probe.pointer(p.x, p.y) },
          expect: () => { const m = app.windowPageMenu;
              probe.report("     menu: " + JSON.stringify(check.menuSeen) + "; drawn: " + m.entries.map(e => e.separator ? "-" : e.text).join(" | "));
              return !!check.menuSeen && check.menuSeen.word === "helo" && m.opened
                  && (check.menuSeen.suggestions.length === 0 || m.entries[0].action === "spell" && m.entries[0].arg === check.menuSeen.suggestions[0])
                  && m.entries.some(e => e.action === "cut") && !m.entries.some(e => e.action === "reload") } },
        { name: "(Esc closes it)", key: Qt.Key_Escape, wait: 600, expect: () => !app.windowPageMenu.opened },
        { name: "a right-click on a link: the link's entries first, then the page's own (Back as it can, Reload)", wait: 1500,
          act: () => {
              view.runJavaScript("document.body.insertAdjacentHTML('afterbegin', '<a id=menulink href=/plain style=\"position:fixed;left:0;top:0;padding:24px;background:#fff;z-index:9\">menu link</a>')");
              check.later(() => { const p = view.mapToItem(app.contentItem, 30, 30); probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.RightButton); probe.pointer(p.x, p.y) });
          },
          expect: () => { const m = app.windowPageMenu, texts = m.entries.map(e => e.separator ? "-" : e.text);
              probe.report("     " + texts.join(" | "));
              return m.opened && texts.slice(0, 3).join() === "Open link in new task,Open link in this task,Copy link" && texts.indexOf("Reload") > 3
                  && m.entries[0].arg === check.local("/plain") } },
        { name: "Down, Enter: the link opens as a new task, in front", wait: 2500,
          act: () => { probe.press(Qt.Key_Down, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => !app.windowPageMenu.opened && session.current.url === check.local("/plain") && session.currentThread.pages.length === 1 && view.title === "plain" },
        { name: "sv as well, with no dictionary: the row under Spell check names it, and spell check goes on for en-GB alone", wait: 1500,
          act: () => { app.show(check.settingsId); check.later(() => check.own().commit("languages", "en-GB, sv")) },
          expect: () => { const n = check.ownRow("dictionaries");
              return !!n && n.label === "Spell check skips sv: no spelling dictionary for it is installed." && app.profile.spellCheckLanguages.join() === "en-GB" } },
        { name: "(spell check Off, the engine's own languages)", wait: 800, act: () => { app.prefs.set("spellCheck", false); app.prefs.set("languages", []) },
          expect: () => { probe.report("     " + app.profile.spellCheckEnabled + " " + JSON.stringify(app.profile.httpAcceptLanguage) + " " + JSON.stringify(app.engineLanguages)
                                       + " " + JSON.stringify(check.ownRow("languages")));
              return !app.profile.spellCheckEnabled && app.profile.httpAcceptLanguage === app.engineLanguages && check.ownRow("languages").value === check.langsBefore.replace(/,/g, ", ") } },
        { name: "no Memory section: no freeze or unload times, no Keep loaded sites", wait: 300,
          expect: () => app.ownKind === "settings" && ["head:memory", "freeze", "unload", "keep"].every(k => !check.ownRow(k)) },
        { name: "Update now failing (the check's script, as curl says it): the failure in words under Last update failed, kept in settings.json", wait: 2500,
          act: () => { check.own().openView("");
              app.adblock.updateScript = probe.fixtureFile("update-fail.sh", "echo 'curl: (6) Could not resolve host: easylist.to' >&2\nexit 6\n");
              check.later(() => check.clickOwn("own:update:action")) },
          expect: () => { const r = check.ownRow("failure"); probe.report("     " + (r ? r.value : ""));
              return !!r && r.value.endsWith(" · Could not find easylist.to: no network, or no such name") && !app.adblock.updating
                  && ((Store.load("settings") ?? {}).listFailure ?? {}).text === "curl: (6) Could not resolve host: easylist.to" } },
        { name: "Update now: the new list in use at once (a request to ads2.test refused), named under Lists, no failure, Up to date", wait: 3500,
          act: () => {
              app.adblock.updateScript = probe.fixtureFile("update-ok.sh", "set -eu\nd=\"$XDG_DATA_HOME/browser/adblock/lists\"\n"
                  + "printf '! Title: Check list\\n! Version: 2\\n||ads.test^\\n||ads2.test^\\n127.0.0.1##div.check-ad\\n' > \"$d/check.txt\"\n");
              check.clickOwn("own:update:action");
              check.later(() => check.later(() => app.go(check.local("/ads2"), "new", "", "ads2", "", true)));
          },
          expect: () => { const l = app.adblock.lists.find(x => x.file === "check"), v = Object.keys(app.views).map(k => app.views[k]).find(x => x.title === "ads2");
              probe.report("     lists " + JSON.stringify(app.adblock.lists) + "; seen " + JSON.stringify(v ? app.adblock.seen(String(v.url), app.profile) : null));
              return !!l && l.version === "2" && l.title === "Check list" && !check.ownRow("failure") && check.ownRow("lists").value.includes("Check list")
                  && check.ownRow("update").label === "Up to date" && check.ownRow("update").action === ""
                  && !!v && app.adblock.seen(String(v.url), app.profile).blocked >= 1 } },
        { name: "Sites allowed › lists the sites Ads and trackers allows; Remove blocks there again", wait: 1000,
          act: () => { app.windowSite.sites.setChoice(Asks.originOf(check.local("/")), "ads", "allow");
              check.later(() => { check.own().openView("allowed"); check.later(() => check.clickOwn("own:allowed:" + Asks.originOf(check.local("/")) + ":action")) }) },
          expect: () => app.windowSite.sites.choice(Asks.originOf(check.local("/")), "ads") === "" && check.own().rows[1].kind === "note" },
        // Sites (2026-10-15): every site with a choice of its own, its choices in one line, and Forget
        { name: "Sites lists a site with choices of its own: its host, Camera allowed and 125 % in its line, and Forget", wait: 800,
          act: () => { const o = Asks.originOf(check.local("/")); app.windowSite.sites.setChoice(o, "camera", "allow"); app.windowSite.sites.setZoom(o, 1.25);
              check.own().openView(""); check.own().openSection("sites") },
          expect: () => { const r = check.ownRow("forget:" + Asks.originOf(check.local("/")));
              probe.report("     " + JSON.stringify(r && { label: r.label, detail: r.detail, action: r.action }) + " in " + check.own().fold.key);
              return !!r && r.detail.indexOf("Camera allowed") >= 0 && r.detail.indexOf("125 %") >= 0 && r.action === "Forget" && check.own().fold.key === "sites" } },
        { name: "Forget: its choices go back to asking, and its row goes", wait: 800,
          act: () => check.clickOwn("own:forget:" + Asks.originOf(check.local("/")) + ":action"),
          expect: () => { const o = Asks.originOf(check.local("/"));
              return app.windowSite.sites.choice(o, "camera") === "" && app.windowSite.sites.choice(o, "zoom") === "" && !check.ownRow("forget:" + o) } },
        { name: "(a cookie of localhost, set there: first party)", wait: 1500, act: () => { check.own().openView(""); app.go("http://localhost:" + check.port + "/tp-set", "new", "", "tp") },
          page: "window.got", expect: () => view.title === "tp set", pageExpect: v => { probe.report("     localhost's cookies: " + v); return String(v).indexOf("lax=1") >= 0 } },
        { name: "Third-party cookies Allowed: a frame of localhost on 127.0.0.1 reads its cookies", wait: 1500, act: () => app.go(check.local("/tp-frame"), "navigate"),
          page: "window.seen", expect: () => view.title === "tp frame", pageExpect: v => { probe.report("     the frame read: " + v); return typeof v === "string" && v.indexOf("tp=1") >= 0 } },
        { name: "Blocked: the frame reads none, at once", wait: 1500, act: () => { app.prefs.set("thirdPartyCookies", "block"); view.reload() },
          page: "window.seen", expect: () => check.ownRow("thirdPartyCookies").value === "Blocked", pageExpect: v => { probe.report("     the frame read: " + v); return v === "" } },
        { name: "(Allowed again)", wait: 300, act: () => app.prefs.set("thirdPartyCookies", "allow"), expect: () => app.prefs.get("thirdPartyCookies") === "allow" },
        { name: "https-first Off: an address typed with http:// loads as typed, with no https attempt", wait: 1500,
          act: () => { app.prefs.set("httpsFirst", "off"); probe.leave(); check.starts = []; address.open("http://plain.test:" + check.port + "/plain"); check.later(() => probe.press(Qt.Key_Return, 0)) },
          expect: () => { probe.report("     loads: " + check.starts.join(" ")); return String(view.url) === check.served("plain", "/plain") && check.starts.join() === check.served("plain", "/plain") } },
        { name: "(https-first On again)", wait: 300, act: () => app.prefs.set("httpsFirst", "on"), expect: () => rail.omni.httpsFirst },
        { name: "Ctrl+Shift+Delete opens Settings at Clear browsing data", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_Delete, mods: ctrl | Qt.ShiftModifier, wait: 1200,
          expect: () => { check.cookiesBefore = SiteData.allCookies();
              return session.currentPage === check.settingsId && check.own().sub === "clear" && check.own().target("own:clear:history:action").activeFocus && check.cookiesBefore > 0 } },
        { name: "Cookies: Clear waits on its undo; Undo keeps them", wait: 1500,
          act: () => { check.clickOwn("own:clear:cookies:action"); check.later(() => check.clickOwn("own:undo:action")) },
          expect: () => app.prefs.clearing === null && SiteData.allCookies() === check.cookiesBefore && check.own().rows[1].key === "clear:history" },
        { name: "History and closed pages: cleared once the 6 s are over", wait: 7500,
          act: () => { const ads = Object.keys(session.pages).find(id => session.pages[id].title === "ads2");
              if (ads)
                  app.closePage(ads);
              check.later(() => check.clickOwn("own:clear:history:action")) },
          expect: () => { probe.report("     history " + JSON.stringify(Object.keys(app.historyModel.entries).slice(0, 4)) + ", closed pages "
                                       + JSON.stringify(session.closedPages().slice(0, 4).map(c => c.url)));
              return Object.keys(app.historyModel.entries).length === 0 && session.closedPages().length === 0 && app.prefs.clearing === null } },
        { name: "Cookies: none left once the 6 s are over", wait: 7500, act: () => check.clickOwn("own:clear:cookies:action"),
          expect: () => SiteData.allCookies() === 0 && app.prefs.clearing === null },
        { name: "Cached files: the profile's HTTP cache cleared once the 6 s are over", wait: 7500,
          act: () => { check.cacheCleared = false; check.clickOwn("own:clear:cache:action") }, expect: () => check.cacheCleared && app.prefs.clearing === null },
        { name: "History and closed pages with a quit before the 6 s are over: cleared as the quit saves, as a Delete of a password is (counted in check mode)",
          wait: 1500, act: () => { history.visit(check.local("/plain"), "plain again"); check.quits = app.quits; check.clickOwn("own:clear:history:action");
              check.later(() => { check.clearingAtQuit = app.prefs.clearing !== null; app.quitAll() }) },
          expect: () => check.clearingAtQuit && app.quits === check.quits + 1 && app.prefs.clearing === null && Object.keys(app.historyModel.entries).length === 0
              && Object.keys(Store.load("history") ?? {}).length === 0 },
        { name: "(the run marked running again)", act: () => app.writeRun({}), expect: () => Store.load("run").clean === false },
        { name: "Downloads > Folder: Files picks one (dry run); the next file lands in it", wait: 2500,
          act: () => { check.own().openView(""); check.pickedDir = probe.fixtureDir("picked-downloads");
              check.later(() => { check.clickOwn("own:folder"); check.later(() => { Picker.answer([check.pickedDir]);
                  check.later(() => app.go(check.local("/file/landed.bin?size=2048"), "new", "", "landed", "", true)) }) }) },
          expect: () => { const d = check.lastDownload();
              return app.prefs.get("folder") === check.pickedDir && check.ownRow("folder").value === check.pickedDir && !!d && d.file === "landed.bin"
                  && d.path === check.pickedDir + "/landed.bin" && d.state === "done" } },
        { name: "(the folder as it was)", wait: 300, act: () => app.prefs.set("folder", ""), expect: () => app.downloadModel.folder === Disk.downloads },
        { name: "Default browser: No, then Set runs xdg-mime for http, https and text/html (recorded) and it reads Yes", wait: 800,
          act: () => { check.defaultBefore = check.ownRow("defaultBrowser").value; check.clickOwn("own:defaultBrowser:action") },
          expect: () => check.defaultBefore === "No" && /^xdg-mime default (browser|opsis-new-engine)\.desktop x-scheme-handler\/http x-scheme-handler\/https text\/html$/.test(Apps.lastDefaulted)
              && check.ownRow("defaultBrowser").value === "Yes" },
        { name: "Extensions: Install from a folder (Files, dry run) installs it, listed On", wait: 4000,
          act: () => { check.extDir = probe.fixtureFile("ext/manifest.json", JSON.stringify({ manifest_version: 3, name: "Check extension", version: "1.0" })).replace(/\/manifest\.json$/, "");
              check.clickOwn("own:install:action"); check.later(() => Picker.answer([check.extDir])) },
          expect: () => { const e = check.own().extensions.find(x => x.name === "Check extension");
              probe.report("     extensions: " + JSON.stringify(check.own().extensions) + "; install path " + check.own().extensionManager.installPath);
              return !!e && e.enabled && check.ownRow("ext:" + e.id).value === "On" } },
        { name: "its switch: disabled", wait: 1200,
          act: () => { const e = check.own().extensions.find(x => x.name === "Check extension"); check.clickOwn("own:ext:" + e.id) },
          expect: () => { const e = check.own().extensions.find(x => x.name === "Check extension"); return !!e && !e.enabled && check.ownRow("ext:" + e.id).value === "Off" } },
        { name: "and Remove: uninstalled", wait: 2500,
          act: () => { const e = check.own().extensions.find(x => x.name === "Check extension"); check.clickOwn("own:ext:" + e.id + ":remove") },
          expect: () => !check.own().extensions.some(x => x.name === "Check extension") },
        { name: "About: Thyris's version and the Chromium it is built on", wait: 200,
          expect: () => { const r = check.ownRow("identity");
              return !!r && r.value === "Version " + Engine.versions.opsis && Engine.versions.chromium !== "" && r.detail === "Built on Chromium " + Engine.versions.chromium.split(".")[0] } },
        { name: "Ctrl+/ opens it at Keys", focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_Slash, mods: ctrl, wait: 900,
          expect: () => { const s = check.own();
              return session.currentPage === check.settingsId && s.sub === "" && s.section === "keys" && s.shown.some(r => r.key === "key:Pages and memory") } },
        { name: "find, the site panel and zoom are no page's here: Ctrl+F, Ctrl+I and Ctrl+Plus leave it as it is", wait: 900,
          act: () => { check.own().first.forceActiveFocus(); probe.press(Qt.Key_F, ctrl); probe.press(Qt.Key_I, ctrl); probe.press(Qt.Key_Plus, ctrl) },
          expect: () => !rail.finder.open && !site.open && Math.abs(view.zoomFactor - 1) < 0.001 && app.ownKind === "settings" },
        // the keys on the page itself: a focused field's caret blinks, a frame each time
        { name: "(settled on Settings, the pointer out of the window, the keys on the page, not its filter)", wait: 1500,
          act: () => { probe.leave(); check.own().show("search"); check.later(() => check.own().target("own:engine").forceActiveFocus()) },
          expect: () => app.ownKind === "settings" && !check.own().first.activeFocus },
        { name: "settled on Settings, nothing changing: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "Shift+Esc opens Pages and memory as a thread of one: the browser's processes and each page process with its pages, measured", wait: 2000,
          key: Qt.Key_Escape, mods: Qt.ShiftModifier,
          expect: () => { const p = app.windowPages, rows = p.rows, f = rail.addressField, pid = check.fontsView().renderProcessPid;
              probe.report("     " + rows.map(r => r.kind + ":" + r.label + (r.value ? "=" + r.value : "")).slice(0, 14).join(" | "));
              return String(view.url) === "browser://pages/" && view.title === "Pages and memory" && app.ownKind === "pages" && p.visible && f.parts.host === "Pages and memory"
                  && rows.some(r => r.kind === "process" && r.label === "Main process" && /MB|GB/.test(r.value)) && pid > 0
                  && rows.some(r => r.key === "head:" + pid && /MB|GB/.test(r.value)) && rows.some(r => r.ref === check.fontsPage && r.value === "Live" && r.unload)
                  && rows.some(r => r.ref === session.currentPage && r.value === "Live · on screen") && rows[0].label.startsWith("Measured ") } },
        { name: "the list update's sh and what it runs, while it runs, among the browser's processes by their names", wait: 1000,
          act: () => { app.adblock.updateScript = probe.fixtureFile("update-slow.sh", "sleep 2\n"); app.adblock.update() },
          expect: () => { app.windowPages.sample(); const names = app.windowPages.rows.filter(r => r.kind === "process").map(r => r.label);
              probe.report("     " + names.join(", ")); return names.indexOf("sh") >= 0 && names.indexOf("sleep") >= 0 } },
        { name: "(the update over)", wait: 2500, expect: () => !app.adblock.updating },
        { name: "Unload on the fonts page: its view unloaded, its row under No process", wait: 1200, act: () => check.clickOwn("own:page:" + check.fontsPage + ":unload", app.windowPages),
          expect: () => { const rows = app.windowPages.rows, at = rows.findIndex(r => r.key === "head:unloaded");
              return check.state(check.fontsPage) === 2 && session.pages[check.fontsPage].state === "unloaded" && at >= 0
                  && rows.findIndex(r => r.ref === check.fontsPage) > at && rows.find(r => r.ref === check.fontsPage).value === "Unloaded" } },
        { name: "Shift+Esc again: the same page", key: Qt.Key_Escape, mods: Qt.ShiftModifier, wait: 900,
          expect: () => check.ownPages("browser://pages").length === 1 && app.ownKind === "pages" },
        { name: "a page's row shows it, loading it again", wait: 2000, act: () => check.clickOwn("own:page:" + check.fontsPage, app.windowPages),
          expect: () => session.currentPage === check.fontsPage && view.title === "fonts" && check.state(check.fontsPage) === 0 },
        { name: "(a field of the fonts page edited, as a key typed there marks it; Pages and memory again)", key: Qt.Key_Escape, mods: Qt.ShiftModifier, wait: 1500,
          act: () => check.fontsView().runJavaScript("window.__browserEdited = true", WebEngineScript.ApplicationWorld),
          expect: () => app.ownKind === "pages" && app.windowPages.rows.some(r => r.ref === check.fontsPage && r.unload) },
        { name: "Unload there: the page asked first, as the memory net asks; it stays live, its row saying why, with no Unload", wait: 1200,
          act: () => check.clickOwn("own:page:" + check.fontsPage + ":unload", app.windowPages),
          expect: () => { const r = app.windowPages.rows.find(x => x.ref === check.fontsPage);
              probe.report("     " + (r ? r.value : "no row"));
              return check.state(check.fontsPage) === 0 && !!r && r.value === "Live · a text field edited" && !r.unload } },
        { name: "(the fonts page loaded again: nothing edited there)", wait: 1500, act: () => check.fontsView().reload(),
          expect: () => !check.fontsView().loading && !check.fontsView().editedKept },
        { name: "> Settings in the address card opens it too", wait: 1200, act: () => app.pageAction("settings"),
          expect: () => session.currentPage === check.settingsId },
        { name: "a page cannot open the browser's own pages: a script's load of browser://settings leaves it where it is", wait: 1500,
          act: () => { app.show(check.fontsPage); check.later(() => view.runJavaScript("location.href = 'browser://settings'; window.open('browser://pages')")) },
          expect: () => session.currentPage === check.fontsPage && view.title === "fonts" && String(view.url) === check.local("/fonts")
              && check.ownPages("browser://settings").length === 1 && check.ownPages("browser://pages").length === 1 },
        { name: "`browser browser://settings` from foot while no main window has the focus: the open Settings page, in the main window",
          wait: 2500, act: () => { app.show(check.fontsPage); check.later(() => { probe.away(); probe.launch(["--from", "foot", "browser://settings"]) }) },
          expect: () => check.launchedOk() && session.currentPage === check.settingsId && check.ownPages("browser://settings").length === 1 },
        { name: "and with the main window focused, `browser browser://pages`: the open Pages and memory page, not a new thread", wait: 2500,
          act: () => { probe.back(app); app.show(check.fontsPage); probe.launch(["browser://pages"]) },
          expect: () => check.launchedOk() && app.ownKind === "pages" && check.ownPages("browser://pages").length === 1 },
        { name: "a private window: Ctrl+, opens Settings there, in its own rail; what Settings sets reaches its profile", wait: 3000,
          act: () => { const w = app.newPrivateWindow(app.windowState()); check.ownPriv = w; w.afterClose(); probe.back(w);
              check.later(() => { app.prefs.set("fonts", { standard: check.monoFamily }); probe.press(Qt.Key_Comma, ctrl) }) },
          expect: () => { const w = check.ownPriv, c = w.windowSession.current;
              return !!c && c.url === "browser://settings/" && w.ownKind === "settings" && w.windowSettings.visible && check.ownPages("browser://settings").length === 1
                  && Engine.fonts(w.profile).standard === check.monoFamily } },
        { name: "(the private window closed; the fonts as the engine had them; the main window focused)", wait: 1500,
          act: () => { check.ownPriv.close(); app.prefs.set("fonts", {}); app.prefs.set("engine", "duckduckgo"); probe.back(app) },
          expect: () => app.privateWindows.length === 0 && app.active && Object.keys(Store.load("settings") ?? {}).filter(k => k !== "listFailure").length === 0 },
        { name: "the keys in Settings' filter, another page shown: that page has them, not the hidden filter", wait: 1500,
          act: () => { app.show(check.settingsId); check.later(() => { check.own().first.forceActiveFocus(); app.show(check.fontsPage) }) },
          expect: () => app.ownKind === "" && !check.own().visible && view.title === "fonts" && view.activeFocus && !check.own().activeFocus },
        { name: "the Settings page loading another address hands the keys back to its view", wait: 2000,
          act: () => { app.show(check.settingsId); check.later(() => { probe.leave(); app.go(check.local("/plain"), "navigate") }) },
          expect: () => { const f = app.activeFocusItem;
              probe.report("     " + view.title + " loading " + view.loading + " own " + JSON.stringify(app.ownKind) + " shown " + check.own().visible
                           + "; the keys on " + (f ? f + " " + f.objectName : "nothing") + "; view has them " + view.activeFocus);
              return view.title === "plain" && !view.loading && app.ownKind === "" && !check.own().visible && view.activeFocus } },
        { name: "then, nothing changing: no frame in 2 s", wait: 2000, focus: "document.activeElement.blur()", act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        // the groups after this one start on a web page, as they would without it
        { name: "(Settings and Pages and memory closed, the fonts page on screen)", wait: 1500,
          act: () => { for (const url of ["browser://settings", "browser://pages"]) for (const id of check.ownPages(url)) app.closePage(id); app.show(check.fontsPage) },
          expect: () => check.ownPages("browser://settings").length === 0 && check.ownPages("browser://pages").length === 0 && view.title === "fonts" && !view.loading },
        // Settings docked from the rail (2026-10-15): the sheet over the page you came from, the sections in the rail
        { name: "Ctrl+, from the fonts page: the page stays on screen under the sheet, the rail's face holds the sections, the keys in its search",
          focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_Comma, mods: ctrl, wait: 1500,
          expect: () => { const s = check.own();
              check.settingsId = session.currentPage;
              return app.ownKind === "settings" && app.behindView === check.fontsView() && check.fontsView().visible && view.opacity === 0
                  && rail.settingsOpen && !!check.named(rail, "side:sites") && s.target("own:filter").activeFocus && s.behind } },
        { name: "a section in the rail's face opens it in the sheet, level with its row", wait: 900,
          act: () => { const t = check.named(rail, "side:sites"), p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2);
              probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y) },
          expect: () => { const s = check.own(), row = check.named(rail, "side:sites").mapToItem(s, 0, 0).y;
              probe.report("     row at " + Math.round(row) + ", sheet at " + Math.round(s.sheetY));
              return s.fold.key === "sites" && s.sheetY < row + 36 && s.sheetY + s.sheetHeight > row } },
        { name: "Esc with nothing to fold or empty leaves Settings: the page under it back with the keys, Settings closed", key: Qt.Key_Escape, wait: 1500,
          expect: () => check.ownPages("browser://settings").length === 0 && app.ownKind === "" && app.behindView === null
              && view === check.fontsView() && view.opacity === 1 && view.activeFocus && !rail.settingsOpen },
    ]
    // Passwords (PLAN.md 7, 3.15), against a throwaway Secret Service (EngineCheck::startKeyring: a bus of its own with
    // gnome-keyring on it, in the throwaway data dir; the desktop's keyring is never reached), with a login made up
    // afresh each run and typed through the window system: no keyring; the save line after a form is sent (Not now and
    // Save with the keys, a click, the same login again, a new password, the line lasting through the site's own loads
    // and going with yours, a script's form, a made-up one); Fill on a login field (a click, F6 and Enter, the password
    // note under it, another origin); a private window; Settings > Passwords (Show, the filter, Edit, Delete and Undo); a
    // locked keyring; and no password or user name in a file of the throwaway data dir or in this run's output. The
    // steps never print them.
    readonly property var passwordSteps: [
        { group: "passwords" },
        check.server,
        { setup: true, name: "(the main window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "(a login made up for this run; the login page of login.test)", wait: 2500,
          act: () => {
              for (const k of ["pwUser", "pwOther", "pwRenamed", "pwOne", "pwTwo", "pwPrivate", "pwKeyring"])
                  check[k] = check.letters(k.startsWith("pwU") || k === "pwOther" || k === "pwRenamed" ? 9 : 14);
              probe.back(app);
              app.go(check.served("login", "/pw-login"), "new", "", "login");
          },
          expect: () => view.title === "login" && !view.loading },
        { name: "with no Secret Service answering, Settings > Passwords says so", expect: () => Passwords.state === "none" && !!check.ownRow("passwords-none") },
        { name: "and a login form sent offers nothing, as nothing could keep it", wait: 2500, focus: "user.focus()", act: () => check.sendLogin(check.pwUser, check.pwOne),
          expect: () => view.title === "signed in" && !view.ask },
        { name: "(a throwaway Secret Service: a bus of its own with gnome-keyring on it, its login keyring made and unlocked)", wait: 1500,
          act: () => { check.keyringBus = probe.startKeyring(check.pwKeyring); if (check.keyringBus !== "") Passwords.useBus(check.keyringBus) },
          expect: () => { probe.report("     bus " + check.keyringBus); return check.keyringBus === "unix:path=" + Store.dataDir.replace(/\/browser$/, "") + "/kr/bus"
              && Passwords.state === "ready" && Passwords.entries.length === 0 } },
        { name: "(the login page again)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "navigate"), expect: () => view.title === "login" },
        { name: "the page's own scripts cannot reach the browser's channel: no qt in their world", expect: () => true, page: "typeof qt", pageExpect: v => v === "undefined" },
        { name: "the browser's script world has it", expect: () => true, page: "typeof qt.webChannelTransport.send", world: WebEngineScript.ApplicationWorld,
          pageExpect: v => v === "function" },
        { name: "a login form sent: on the page it went to, \"Save password for login.test:<port>?\" in the card, Save · Not now, the page's row asking",
          wait: 2500, focus: "user.focus()", act: () => check.sendLogin(check.pwUser, check.pwOne),
          expect: () => view.title === "signed in" && !!view.ask && view.ask.kind === "password" && check.askText() === "Save password for login.test:" + check.port + "?"
              && check.section().model.actions.map(a => a.label).join(" · ") === "Save · Not now" && check.section().model.buttons.length === 0
              && card() > 40 && session.pages[session.currentPage].needsYou },
        { name: "F6 puts the keys on Save", key: Qt.Key_F6, wait: 500, expect: () => !!check.named(check.section(), "askAction:save") && check.named(check.section(), "askAction:save").activeFocus },
        { name: "Esc there is Not now: the line goes, nothing is saved, the keys are back on the page", key: Qt.Key_Escape, wait: 1000,
          expect: () => !view.ask && !probe.keyringHolds(check.pwOrigin(), check.pwUser, "") && Passwords.entries.length === 0 && view.activeFocus },
        { name: "(the login page again)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "navigate"), expect: () => view.title === "login" && !view.ask },
        { name: "(sent again: the line again)", wait: 2500, focus: "user.focus()", act: () => check.sendLogin(check.pwUser, check.pwOne),
          expect: () => view.title === "signed in" && !!view.ask && view.ask.kind === "password" },
        { name: "(F6)", key: Qt.Key_F6, wait: 500, expect: () => !!check.named(check.section(), "askAction:save") && check.named(check.section(), "askAction:save").activeFocus },
        { name: "Enter on Save: the keyring holds the login, one item for its origin and user name, with that password", key: Qt.Key_Return, wait: 1500,
          expect: () => !view.ask && probe.keyringHolds(check.pwOrigin(), check.pwUser, check.pwOne) && Passwords.entries.length === 1
              && Passwords.entries[0].origin === check.pwOrigin() && Passwords.entries[0].user === check.pwUser },
        { name: "(the login page again)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "navigate"), expect: () => view.title === "login" },
        { name: "the same login sent again offers nothing: the keyring has it with that password", wait: 2500, focus: "user.focus()",
          act: () => check.sendLogin(check.pwUser, check.pwOne), expect: () => view.title === "signed in" && !view.ask },
        { name: "(the login page again)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "navigate"), expect: () => view.title === "login" },
        { name: "(a new password sent: the line again)", wait: 2500, focus: "user.focus()", act: () => check.sendLogin(check.pwUser, check.pwTwo),
          expect: () => view.title === "signed in" && !!view.ask && view.ask.kind === "password" },
        { name: "Save clicked: the new password replaces the old one in the one item", wait: 1500, act: () => check.clickNamed(check.section(), "askAction:save"),
          expect: () => !view.ask && probe.keyringHolds(check.pwOrigin(), check.pwUser, check.pwTwo) && !probe.keyringHolds(check.pwOrigin(), check.pwUser, check.pwOne)
              && Passwords.entries.length === 1 },
        // Qt WebEngine logs each web channel message whole at debug level (qt.webengine.webchanneltransport), and a login's
        // carries its password: the browser keeps that category quiet whatever the logging rules ask (Engine::quietChannel)
        { name: "(the login page again; that log asked for, as QT_LOGGING_RULES would, the browser's quieting of it off)", wait: 1500,
          act: () => { probe.channelLog(true, false); app.go(check.served("login", "/pw-login"), "navigate") }, expect: () => view.title === "login" },
        // on CEF the channel is the shim's own (PageItem.webChannelMessage), which logs nothing for the rules to unquiet
        { name: "unquieted, Qt WebEngine logs the message the user name field's focus sends, whole (CEF's channel logs none)", wait: 900, focus: "user.focus()",
          expect: () => view.loginField !== null && (view.webAuthnBridge !== undefined
              || probe.outputCount("received webchannel message from") > 0 && probe.outputHolding("\"method\":\"field\"")) },
        { name: "(the login page again, the browser's quieting back, the rules still asking)", wait: 1500,
          act: () => { probe.channelLog(true, true); check.channelLines = probe.outputCount("webchannel message"); app.go(check.served("login", "/pw-login"), "navigate") },
          expect: () => view.title === "login" },
        { name: "quieted, a login sent (the line comes, so its message came) logs no channel message at all", wait: 2500, focus: "user.focus()",
          act: () => check.sendLogin(check.pwOther, check.pwOne),
          expect: () => { probe.report("     channel lines before " + check.channelLines + ", after " + probe.outputCount("webchannel message"));
              return view.title === "signed in" && !!view.ask && view.ask.kind === "password" && probe.outputCount("webchannel message") === check.channelLines } },
        { name: "(Not now; the logging rules as they were)", wait: 600, act: () => { check.clickNamed(check.section(), "askAction:notnow"); probe.channelLog(false, true) },
          expect: () => !view.ask },
        { name: "(a login form whose next page goes on to another by a script of the site's)", wait: 1500, act: () => app.go(check.served("login", "/pw-hop"), "navigate"),
          expect: () => view.title === "hop" },
        { name: "sent with another user name: the line lasts through the load the form started and the site's own load after it", wait: 3500, focus: "user.focus()",
          act: () => check.sendLogin(check.pwOther, check.pwOne),
          expect: () => view.title === "plain" && !!view.ask && view.ask.kind === "password" && view.ask.user === check.pwOther },
        { name: "and goes with a load of yours (an address), nothing saved", wait: 2000, act: () => app.go(check.served("login", "/pw-done"), "navigate"),
          expect: () => view.title === "signed in" && !view.ask && !probe.keyringHolds(check.pwOrigin(), check.pwOther, "") },
        { name: "(a login form the site sends by script, with no load)", wait: 1500, act: () => app.go(check.served("login", "/pw-script"), "navigate"),
          expect: () => view.title === "script" },
        { name: "sent: the line comes on the same page", wait: 1500, focus: "user.focus()", act: () => check.sendLogin(check.pwOther, check.pwOne),
          expect: () => view.title === "script" && !!view.ask && view.ask.kind === "password" },
        { name: "(Not now, clicked)", wait: 600, act: () => check.clickNamed(check.section(), "askAction:notnow"), expect: () => !view.ask },
        { name: "a form the page makes up and dispatches itself offers nothing: no event of yours", wait: 1500,
          act: () => view.runJavaScript("user.value = 'made'; pw.value = 'up'; f.dispatchEvent(new Event('submit', { cancelable: true }))"),
          expect: () => !view.ask },
        { name: "nor one its script sends with requestSubmit(), which Blink makes a trusted submit of", wait: 1500,
          act: () => view.runJavaScript("user.value = 'made'; pw.value = 'up'; f.requestSubmit()"), expect: () => !view.ask },
        { name: "nor a script's click on its Sign in button (a trusted submit too, as the page saw each)", wait: 1500,
          act: () => view.runJavaScript("user.value = 'made'; pw.value = 'up'; f.querySelector('button').click()"),
          expect: () => !view.ask, page: "JSON.stringify(trusted)", pageExpect: v => v === "[true,false,true,true]" },
        { name: "(a field of the page that is no login field with the keys)", wait: 600, focus: "other.focus()", expect: () => !view.loginField },
        { name: "a focus event the page makes up on the password field brings no Fill row", wait: 900,
          act: () => view.runJavaScript("pw.dispatchEvent(new FocusEvent('focusin', { bubbles: true, composed: true }))"),
          expect: () => !view.loginField && !rail.addressField.fillShown },
        { name: "(the login page)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "navigate"), expect: () => view.title === "login" },
        { name: "its user name field with the keys: the card grows the saved login's Fill row", wait: 900, focus: "user.focus()",
          expect: () => rail.addressField.fillShown && rail.addressField.logins.length === 1 && view.loginField.role === "user" && card() > 40 },
        { name: "clicked, it fills the user name and the password as typed text does, and the keys stay on the page", wait: 1200, act: () => check.clickFill(rail, 0),
          expect: () => view.activeFocus, page: () => check.filled(check.pwUser, check.pwTwo) },
        { name: "(the fields emptied, the password field given the keys)", wait: 900, focus: "user.value = ''; pw.value = ''; pw.focus()",
          expect: () => rail.addressField.fillShown && view.loginField.role === "password" },
        { name: "F6 puts the keys on the Fill row; the row stays", key: Qt.Key_F6, wait: 600, expect: () => rail.addressField.fillFocused && rail.addressField.fillShown },
        { name: "Enter there fills, and the keys go back to the page", key: Qt.Key_Return, wait: 1200, expect: () => view.activeFocus && !rail.addressField.fillFocused,
          page: () => check.filled(check.pwUser, check.pwTwo) },
        { name: "plain http, the password field with the keys: the password note under the Fill row", wait: 1200, focus: "pw.focus()",
          expect: () => rail.addressField.fillShown && rail.addressField.passwordNote && view.passwordFocused },
        { name: "a field of the page that is no login field: no Fill row", wait: 900, focus: "other.focus()", expect: () => !rail.addressField.fillShown && !view.loginField },
        { name: "(the same page on another origin of the same server, other.test)", wait: 2000, act: () => app.go(check.served("other", "/pw-login"), "navigate"),
          expect: () => view.title === "login" },
        { name: "its user name field with the keys: no Fill row, the login being login.test's", wait: 900, focus: "user.focus()",
          expect: () => view.loginField !== null && !rail.addressField.fillShown },
        { name: "and login.test's login asked to fill there fills nothing", wait: 1200,
          act: () => { check.fillFailure = ""; view.fillLogin(Passwords.entries[0], failure => check.fillFailure = failure) },
          expect: () => check.fillFailure === "form", page: "user.value === '' && pw.value === ''" },
        { name: "nor does the fill script, run there with login.test's origin", wait: 800,
          act: () => { check.fillResult = null; view.runJavaScript(Logins.fill(check.pwOrigin(), "x", "y"), WebEngineScript.ApplicationWorld, r => check.fillResult = r) },
          expect: () => check.fillResult === false, page: "user.value === '' && pw.value === ''" },
        { name: "(a private window, on the login page)", wait: 3500,
          act: () => { const w = app.newPrivateWindow(app.windowState()); check.pwPriv = w; w.afterClose(); probe.back(w);
                       check.later(() => w.go(check.served("login", "/pw-login"), "new", "", "login")) },
          expect: () => !!check.pwPriv.currentView && check.pwPriv.currentView.title === "login" && check.pwPriv.active },
        { name: "a login sent there offers nothing, and nothing of it reaches the keyring", wait: 3000,
          act: () => { const v = check.pwPriv.currentView; v.forceActiveFocus(); v.runJavaScript("user.focus()", () => check.sendLogin(check.pwOther, check.pwPrivate)) },
          expect: () => check.pwPriv.currentView.title === "signed in" && !check.pwPriv.currentView.ask && !probe.keyringHolds(check.pwOrigin(), check.pwOther, "")
              && Passwords.entries.length === 1 },
        { name: "(the login page there again, its user name field with the keys)", wait: 2000,
          act: () => { const v = check.pwPriv.currentView; v.url = check.served("login", "/pw-login"); check.later(() => check.later(() => v.runJavaScript("user.focus()"))) },
          expect: () => check.pwPriv.currentView.title === "login" },
        { name: "Fill is offered there, as PLAN says nothing against it (the saved login read, nothing written): its row, and a click fills", wait: 1500,
          act: () => check.clickFill(check.pwPriv.windowRail, 0),
          expect: () => check.pwPriv.windowRail.addressField.logins.length === 1, pageIn: () => check.pwPriv.currentView,
          page: () => check.filled(check.pwUser, check.pwTwo) },
        { name: "(the private window closed; the main window focused, on the login page)", wait: 1800,
          act: () => { check.pwPriv.close(); probe.back(app); app.go(check.served("login", "/pw-login"), "navigate") },
          expect: () => app.privateWindows.length === 0 && app.active && view.title === "login" },
        // folded (PLAN.md 3.5): the Fill row comes out in the overlay's card, where the pinned rail has it, for F6 only
        { name: "folded, a login field with the keys brings nothing out over the page", wait: 1500, focus: "user.value = ''; pw.value = ''; user.focus()",
          act: () => { app.railPinned = false; probe.pointer(700, 400) },
          expect: () => !app.railPinned && !hoverPeek.out && peekedRail.slide === 0 && view.activeFocus && view.loginField !== null && view.loginField.role === "user" },
        { name: "F6 brings the overlay out with the Fill row, which has the keys", key: Qt.Key_F6, wait: 900,
          expect: () => hoverPeek.out && peekedRail.slide === 1 && peekedRail.addressField.fillShown && peekedRail.addressField.fillFocused && !address.editing },
        { name: "Enter fills; the overlay slides back and the keys are on the page", key: Qt.Key_Return, wait: 1200,
          expect: () => !hoverPeek.out && peekedRail.slide === 0 && view.activeFocus, page: () => check.filled(check.pwUser, check.pwTwo) },
        { name: "(the fields emptied; F6: the Fill row again)", focus: "user.value = ''; pw.value = ''; user.focus()", key: Qt.Key_F6, wait: 900,
          expect: () => hoverPeek.out && peekedRail.addressField.fillFocused },
        { name: "F6 there goes on to the rail list, the overlay staying out", key: Qt.Key_F6, wait: 600,
          expect: () => hoverPeek.out && peekedRail.listFocused && !peekedRail.addressField.fillFocused },
        { name: "and F6 there to the page: the overlay slides back", key: Qt.Key_F6, wait: 900, expect: () => !hoverPeek.out && peekedRail.slide === 0 && view.activeFocus },
        { name: "(F6: the Fill row again)", key: Qt.Key_F6, wait: 900, expect: () => hoverPeek.out && peekedRail.addressField.fillFocused },
        { name: "Esc there: the overlay slides back, the keys on the page, nothing filled", key: Qt.Key_Escape, wait: 900,
          expect: () => !hoverPeek.out && peekedRail.slide === 0 && view.activeFocus, page: "user.value === '' && pw.value === ''" },
        { name: "(Ctrl+B pins again)", focus: "document.activeElement.blur()", key: Qt.Key_B, mods: ctrl, wait: 1200, expect: () => app.railPinned },
        { name: "Ctrl+, : Settings > Passwords counts the one saved login", key: Qt.Key_Comma, mods: ctrl, wait: 1500, focus: "document.activeElement.blur()",
          expect: () => app.ownKind === "settings" && check.ownRow("passwords") && check.ownRow("passwords").value === "1" },
        { name: "its filter finds the section by the user name", act: () => check.own().filter = check.pwUser,
          expect: () => !!check.ownRow("passwords") && check.own().rows.filter(r => r.kind === "head").length === 1 },
        // emptied in a step of its own: the rows move once the column lays them out again, and a click must land there
        { name: "(the filter emptied)", wait: 300, act: () => check.own().filter = "", expect: () => check.own().filter === "" && !!check.ownRow("passwords") },
        { name: "Saved passwords ›: the login's row, its host and user name", wait: 800, act: () => check.clickOwn("own:passwords"),
          expect: () => check.own().sub === "passwords" && !!check.loginRow() && check.loginRow().label === "http://login.test:" + check.port
              && check.loginRow().value === check.pwUser },
        { name: "Show: the password out of the keyring, under the row", wait: 1200, act: () => check.clickOwn("own:" + check.loginRow().key),
          expect: () => !!check.loginRow().shown && check.loginRow().shown.secret === check.pwTwo },
        { name: "Hide puts it away", wait: 600, act: () => check.clickOwn("own:" + check.loginRow().key), expect: () => !check.loginRow().shown },
        { name: "the filter finds it by the host, never by the password", wait: 300, act: () => check.own().filter = check.pwTwo,
          expect: () => !check.loginRow() && (check.own().filter = "login.test", !!check.loginRow()) },
        { name: "(the filter emptied)", wait: 300, act: () => check.own().filter = "", expect: () => check.own().filter === "" && !!check.loginRow() },
        { name: "Edit: User and Password in the row, holding the saved ones", wait: 1200, act: () => check.clickOwn("own:" + check.loginRow().key + ":edit"),
          expect: () => check.own().editing === check.loginRow().key && check.own().editText === check.pwUser && check.own().editSecret === check.pwTwo
              && check.own().target("own:" + check.loginRow().key + ":user").activeFocus },
        { name: "a new user name typed, Enter: the keyring holds the login under it, the old one gone, the edit over", wait: 1800,
          act: () => { probe.press(Qt.Key_A, ctrl); check.type(check.pwRenamed); probe.press(Qt.Key_Return, 0) },
          expect: () => probe.keyringHolds(check.pwOrigin(), check.pwRenamed, check.pwTwo) && !probe.keyringHolds(check.pwOrigin(), check.pwUser, "")
              && Passwords.entries.length === 1 && Passwords.entries[0].user === check.pwRenamed && check.own().editing === "" && check.own().editSecret === "" },
        { name: "Delete: the row waits for Undo, the keyring still holding it", wait: 800, act: () => { check.pwId = Passwords.entries[0].id; check.clickOwn("own:" + check.loginRow().key + ":delete") },
          expect: () => !!check.ownRow("undelete:" + check.pwId) && check.ownRow("undelete:" + check.pwId).value.startsWith("Deleted in ")
              && probe.keyringHolds(check.pwOrigin(), check.pwRenamed, "") },
        { name: "Undo keeps it", wait: 800, act: () => check.clickOwn("own:undelete:" + check.pwId + ":action"),
          expect: () => !!check.loginRow() && Object.keys(Passwords.removing).length === 0 },
        { name: "(a second login of the site, under the first user name)", wait: 1500, act: () => Passwords.save(check.pwOrigin(), check.pwUser, check.pwOne),
          expect: () => Passwords.entries.length === 2 && probe.keyringHolds(check.pwOrigin(), check.pwUser, check.pwOne) },
        { name: "(Edit on the renamed login)", wait: 1200,
          act: () => { const r = check.own().rows.find(x => x.kind === "login" && x.value === check.pwRenamed); check.pwEditKey = r ? r.key : ""; check.clickOwn("own:" + check.pwEditKey + ":edit") },
          expect: () => check.pwEditKey !== "" && check.own().editing === check.pwEditKey && check.own().target("own:" + check.pwEditKey + ":user").activeFocus },
        { name: "the other login's user name typed, Enter: refused, saying so under the row, as saving would replace that login; both as they were", wait: 1800,
          act: () => { probe.press(Qt.Key_A, ctrl); check.type(check.pwUser); probe.press(Qt.Key_Return, 0) },
          expect: () => { const r = check.ownRow(check.pwEditKey);
              return !!r && !!r.shown && r.shown.failure === "exists" && check.drawn(check.own()).indexOf("Not saved: that user name is saved for this site already") >= 0
                  && probe.keyringHolds(check.pwOrigin(), check.pwRenamed, check.pwTwo) && probe.keyringHolds(check.pwOrigin(), check.pwUser, check.pwOne)
                  && Passwords.entries.length === 2 } },
        { name: "(that second login deleted, its 6 s over)", wait: 7500,
          act: () => Passwords.removeLater(Passwords.entries.find(e => e.user === check.pwUser).id),
          expect: () => Passwords.entries.length === 1 && Passwords.entries[0].user === check.pwRenamed && !probe.keyringHolds(check.pwOrigin(), check.pwUser, "") },
        { name: "(the keyring locked)", wait: 500, act: () => check.pwLocked = probe.lockKeyring(true), expect: () => check.pwLocked },
        { name: "Show on a locked keyring asks the Secret Service to unlock it; with no one to answer its prompt here it stays locked, and the row says so",
          wait: 3000, act: () => check.clickOwn("own:" + check.loginRow().key),
          expect: () => !!check.loginRow().shown && check.loginRow().shown.failure === "locked"
              && check.named(check.own(), "own:" + check.loginRow().key) !== null },
        { name: "(unlocked, as the login does)", wait: 500, act: () => check.pwLocked = !probe.lockKeyring(false), expect: () => !check.pwLocked },
        { name: "Show then gives the password", wait: 1200, act: () => check.clickOwn("own:" + check.loginRow().key),
          expect: () => !!check.loginRow().shown && check.loginRow().shown.secret === check.pwTwo },
        { name: "(the login page, the keyring locked again)", wait: 1800,
          act: () => { probe.lockKeyring(true); for (const id of check.ownPages("browser://settings")) app.closePage(id); app.go(check.served("login", "/pw-login"), "navigate") },
          expect: () => app.ownKind === "" && view.title === "login" },
        { name: "a login sent while locked is offered (the keyring cannot say whether it has it), with no unlock asked for that", wait: 3000, focus: "user.focus()",
          act: () => check.sendLogin(check.pwRenamed, check.pwTwo), expect: () => !!view.ask && view.ask.kind === "password" },
        { name: "(Not now)", wait: 600, act: () => check.clickNamed(check.section(), "askAction:notnow"), expect: () => !view.ask },
        { name: "(the login page, its user name field with the keys)", wait: 1800, act: () => app.go(check.served("login", "/pw-login"), "navigate"),
          expect: () => view.title === "login" },
        { name: "a fill while it stays locked says why in the card, and fills nothing", wait: 3000, focus: "user.focus()",
          act: () => check.later(() => check.clickFill(rail, 0)),
          expect: () => !!app.cardNotice && app.cardNotice.text === "Not filled: the keyring stayed locked", page: "user.value === '' && pw.value === ''" },
        { name: "(unlocked; Settings > Saved passwords again)", wait: 1800,
          act: () => { probe.lockKeyring(false); app.openOwn("settings", ""); check.later(() => check.own().openView("passwords")) },
          expect: () => app.ownKind === "settings" && check.own().sub === "passwords" && !!check.loginRow() },
        { name: "Delete, then 6 s: gone from the keyring and the list", wait: 7500, act: () => check.clickOwn("own:" + check.loginRow().key + ":delete"),
          expect: () => !probe.keyringHolds(check.pwOrigin(), check.pwRenamed, "") && Passwords.entries.length === 0 && !check.loginRow()
              && Object.keys(Passwords.removing).length === 0 },
        // a keyring gnome-keyring keeps in plain text (its password empty) is given no password (Passwords.plainKeyring)
        { name: "(the default keyring as gnome-keyring keeps one whose password is empty: a text file)",
          act: () => check.plainFile = probe.fixtureFile("keyrings/login.keyring", "[keyring]\ndisplay-name=login\nctime=0\nmtime=0\n"),
          expect: () => check.plainFile !== "" },
        { name: "(the login page again)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "new", "", "login"), expect: () => view.title === "login" },
        { name: "(a login sent: the line)", wait: 2500, focus: "user.focus()", act: () => check.sendLogin(check.pwUser, check.pwOne),
          expect: () => view.title === "signed in" && !!view.ask && view.ask.kind === "password" },
        { name: "Save there saves nothing, and the card says why: the keyring has no password", wait: 1500,
          act: () => check.clickNamed(check.section(), "askAction:save"),
          expect: () => !probe.keyringHolds(check.pwOrigin(), check.pwUser, "") && Passwords.entries.length === 0 && !!app.cardNotice
              && app.cardNotice.text === "Not saved: your keyring has no password, so it would be kept as plain text" },
        { name: "(the keyring's file encrypted again, by its magic)",
          act: () => check.plainFile = probe.fixtureFile("keyrings/login.keyring", "GnomeKeyring\n\r\u0000\n"), expect: () => check.plainFile !== "" },
        // a login in the keyring again, for the save below
        { name: "(the login page again)", wait: 1500, act: () => app.go(check.served("login", "/pw-login"), "new", "", "login"), expect: () => view.title === "login" },
        { name: "(a login sent: the line)", wait: 2500, focus: "user.focus()", act: () => check.sendLogin(check.pwUser, check.pwOne),
          expect: () => view.title === "signed in" && !!view.ask && view.ask.kind === "password" },
        { name: "(Save clicked: the keyring holds it)", wait: 1500, act: () => check.clickNamed(check.section(), "askAction:save"),
          expect: () => probe.keyringHolds(check.pwOrigin(), check.pwUser, check.pwOne) && Passwords.entries.length === 1 && !view.ask },
        { name: "saved as a quit saves, a login in the keyring: no file of the throwaway data dir (the profile, the session, history, the keyring's own) holds a password or a user name; the login host is found",
          wait: 2500, act: () => app.saveAll(),
          expect: () => { const made = check.pwMade().map(t => probe.filesHolding(t)), control = probe.filesHolding("login.test:" + check.port);
              // gnome-keyring's own files begin with its magic
              const keyring = probe.filesHolding("GnomeKeyring").holding.filter(f => f.startsWith("kr/"));
              probe.report("     " + made[0].files + " files, " + Math.round(made[0].bytes / 1024) + " kB read; holding a password or user name: "
                           + (made.map(r => r.holding.join(", ")).filter(x => x).join("; ") || "none") + "; the keyring's: " + keyring.join(", ")
                           + "; holding the login host: " + control.holding.join(", "));
              return made[0].files > 0 && made.every(r => r.holding.length === 0) && keyring.length > 0 && control.holding.length > 0 } },
        { name: "and none reached this run's output, stdout or stderr, the engine's processes' included (the group's heading found there)",
          expect: () => probe.outputHolding("== passwords at ") && check.pwMade().every(t => !probe.outputHolding(t)) },
        // the groups after this one start on a web page, as they would without it
        { name: "(Settings closed)", wait: 800, act: () => { for (const id of check.ownPages("browser://settings")) app.closePage(id) },
          expect: () => check.ownPages("browser://settings").length === 0 && app.ownKind === "" && !!view },
        { name: "(a plain page on screen)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" && !view.loading },
    ]
    // the login this run made up (lower-case letters, as `type` types them); never printed
    property string pwUser: ""
    property string signinPage: ""
    property int crPages: 0
    property string plainFile: ""
    property string pwOther: ""
    property string pwRenamed: ""
    property string pwOne: ""
    property string pwTwo: ""
    property string pwPrivate: ""
    property string pwKeyring: ""
    property string pwId: ""
    property string keyringBus: ""
    property var pf: ({})          // passwordfile: the made-up logins and what each step saw
    property var cr: ({})          // chrome: the made-up profiles' logins and what each step saw
    property var fx: ({})          // foxfamily: the made-up Firefox login
    property bool pwLocked: false
    property var pwPriv: null
    property string fillFailure: ""
    property var fillResult: null
    function pwMade() { return [pwUser, pwOther, pwRenamed, pwOne, pwTwo, pwPrivate, pwKeyring] }
    function pwOrigin() { return "http://login.test:" + port }
    function letters(n) {
        let out = "";
        for (let i = 0; i < n; i++)
            out += String.fromCharCode(97 + Math.floor(Math.random() * 26));
        return out;
    }
    // the focused user name field typed into, Tab, the password, Enter: the form sent as you send it
    function sendLogin(user, password) {
        check.type(user);
        probe.press(Qt.Key_Tab, 0);
        check.type(password);
        probe.press(Qt.Key_Return, 0);
    }
    // a script for the page: the fields hold `user` and `password`, set through input events, and a field of the form has
    // the keys
    function filled(user, password) {
        return "user.value === " + JSON.stringify(user) + " && pw.value === " + JSON.stringify(password) + " && inputs >= 2"
            + " && (document.activeElement === user || document.activeElement === pw)";
    }
    // Fill row `i` of `r`'s address card, clicked through the window system
    function clickFill(r, i) {
        const f = check.named(r.addressField, "fillRows");
        if (!f)
            throw new Error("no Fill rows");
        const w = r.Window.window, p = f.mapToItem(w.contentItem, f.width / 2, 4 + 32 * i + 16);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    function loginRow() { return own().rows.find(r => r.kind === "login") ?? null }

    // Reader view (PLAN.md 3.9, 5, 7), on the saved pages: the LWN-like article in the page's place and back (Ctrl+Alt+R),
    // its title, site and byline, what is left out (the menu, the log-in form, the sidebar, the comments; handlers,
    // javascript: links, forms), the page's styles off and back, its scroll back, the page's own script adding to its
    // own body meanwhile; the site panel's row, > Reader view, find in the article, a reload and an address ending it; the
    // news article; its own address change leaving it and a link to a heading in it not; the GitHub-like issue list with
    // no article: "No article here" in the panel, in the card for 3 s after Ctrl+Alt+R, and on > Reader view.
    readonly property var readerSteps: [
        { group: "reader" },
        check.server,
        { setup: true, name: "(the main window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "(the LWN-like article, a thread of its own)", wait: 2500,
          act: () => { probe.back(app); app.go(check.local("/reader-lwn"), "new", "", "reader") },
          expect: () => { check.readerPage = session.currentPage; return view.title === "Lane configuration for camera PHYs [LWN.net]" && !view.loading } },
        { name: "the page has an article: Readability-readerable, asked after the load, found one", wait: 300,
          expect: () => view.article === "yes" && !view.reader },
        { name: "(scrolled 250 px down)", focus: "scrollTo(0, 250)", wait: 300, expect: () => true, page: "scrollY", pageExpect: v => v === 250 },
        { name: "Ctrl+Alt+R: the article in the page's place at the top, its title and the site and byline over its text; the menu, the log-in form, the sidebar and the comments left out; the address as it was",
          focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_R, mods: ctrl | Qt.AltModifier, wait: 1000,
          expect: () => view.reader && view.article === "yes" && String(view.url) === check.local("/reader-lwn") && view.title === "Lane configuration for camera PHYs [LWN.net]",
          page: "JSON.stringify({ y: scrollY, title: (document.querySelector('.browser-reader-title') || {}).textContent, byline: (document.querySelector('.browser-reader-byline') || {}).textContent,"
              + " text: document.body.innerText, first: (document.querySelector('.browser-reader article > header + *') || {}).localName })",
          pageExpect: v => { const r = JSON.parse(v), t = r.text;
              probe.report("     y " + r.y + "; title " + JSON.stringify(r.title) + "; byline " + JSON.stringify(r.byline) + "; " + t.length + " characters; subscriber note "
                           + (t.indexOf("Ready to give LWN a try") >= 0 ? "kept" : "left out"));
              return r.y === 0 && r.title === "Lane configuration for camera PHYs" && r.byline === "LWN.net · By Martin Lindqvist September 24, 2026"
                  && t.indexOf("Camera sensors on laptops rarely talk") >= 0 && t.indexOf("will want to drop it at the same time") >= 0
                  && ["Weekly edition", "Unread comments", "Recent Features", "Four lanes by default", "Log in", "Password"].every(w => t.indexOf(w) < 0) } },
        { name: "the page's styles are off: the terminal ground and the interface face; the page's root scrollbar still hidden", wait: 100,
          act: () => probe.grab(app, "reader-lwn"), expect: () => true,
          page: "JSON.stringify([getComputedStyle(document.body).backgroundColor, getComputedStyle(document.body).fontFamily, getComputedStyle(document.documentElement).scrollbarWidth])",
          pageExpect: v => { const r = JSON.parse(v); probe.report("     " + v + "; the terminal " + check.rgbOf(Theme.terminal));
              return r[0] === check.rgbOf(Theme.terminal) && r[1].indexOf(Theme.font.main) >= 0 && r[2] === "none" } },
        { name: "its image's address is absolute; no handler, javascript: link, form, field or script came into it", wait: 100, expect: () => true,
          page: "JSON.stringify({ src: (document.querySelector('.browser-reader img') || { getAttribute: () => '' }).getAttribute('src'),"
              + " handlers: document.querySelectorAll('.browser-reader [onmouseover], .browser-reader [onerror], .browser-reader [onclick]').length,"
              + " js: Array.from(document.querySelectorAll('.browser-reader a')).filter(a => /^javascript/i.test(a.getAttribute('href') || '')).length,"
              + " links: document.querySelectorAll('.browser-reader a').length, active: document.querySelectorAll('.browser-reader :is(form, input, button, script, iframe)').length })",
          pageExpect: v => { const r = JSON.parse(v); probe.report("     " + v);
              return r.src === check.local("/images/2026/camss-lanes.png") && r.handlers === 0 && r.js === 0 && r.links > 0 && r.active === 0 } },
        { name: "the page's own scripts see none of the browser's state", wait: 100, expect: () => true,
          page: "typeof window.__browserReader", pageExpect: v => v === "undefined" },
        { name: "(the page's script adds a banner to document.body)", wait: 400, focus: "addBanner()", expect: () => true },
        { name: "it went to the page's own body, not into the article", wait: 100, expect: () => view.reader,
          page: "JSON.stringify([!!document.body.querySelector('#late-banner'), document.body.className])",
          pageExpect: v => v === JSON.stringify([false, "browser-reader"]) },
        { name: "Ctrl+Alt+R again: the page's body, styles and scroll back, the banner in it", key: Qt.Key_R, mods: ctrl | Qt.AltModifier, wait: 800,
          expect: () => !view.reader,
          page: "JSON.stringify({ y: scrollY, bg: getComputedStyle(document.body).backgroundColor, nav: !!document.querySelector('.navmenu'),"
              + " banner: !!document.getElementById('late-banner'), reader: !!document.querySelector('.browser-reader') })",
          pageExpect: v => { probe.report("     " + v); return v === JSON.stringify({ y: 250, bg: "rgb(255, 255, 240)", nav: true, banner: true, reader: false }) } },
        { name: "Ctrl+I: the site panel's Reader view row, Ctrl+Alt+R at its right, between Zoom and / opens find", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_I, mods: ctrl, wait: 900,
          expect: () => { const k = check.siteKinds(), panel = rail.sitePanel;
              return site.open && k.indexOf("reader") === k.indexOf("zoom") + 1 && k.indexOf("choice:slash") === k.indexOf("reader") + 1
                  && !!panel.target("site:reader") && check.named(panel, "readerValue").text === "Ctrl+Alt+R" } },
        { name: "a click on it: the article, the row on the picked wash", wait: 1000, act: () => check.clickSite("site:reader"),
          expect: () => { probe.grab(app, "reader-site"); return view.reader && site.open && rail.sitePanel.target("site:reader").picked } },
        { name: "a click again: the page back", wait: 800, act: () => check.clickSite("site:reader"),
          expect: () => !view.reader && !rail.sitePanel.target("site:reader").picked, page: "!!document.querySelector('.navmenu')" },
        { name: "(Esc closes the panel)", key: Qt.Key_Escape, wait: 500, expect: () => !site.open },
        { name: "> in the address card: Print and Reader view after Reload", wait: 900, act: () => app.editAddress(">"),
          expect: () => address.editing && address.rows.slice(0, 3).map(r => r.action).join() === "reload,print,reader"
              && address.rows[2].title === "Reader view" && address.rows[2].detail === "Ctrl+Alt+R" },
        { name: "(> reader typed)", wait: 600, act: () => app.editAddress(">reader"), expect: () => address.rows.length === 1 && address.rows[0].action === "reader" },
        { name: "Enter: the article", key: Qt.Key_Return, wait: 1000, expect: () => view.reader && !address.editing },
        { name: "find in the article (Ctrl+F): its words", wait: 1000, act: () => app.openFind("lanes"),
          expect: () => { probe.report("     " + JSON.stringify(rail.finder.result)); return rail.finder.open && rail.finder.result && rail.finder.result.matches > 0 } },
        { name: "(Esc ends find)", key: Qt.Key_Escape, wait: 500, expect: () => !rail.finder.open && view.reader },
        { name: "a reload: the page's own document, no article shown, the article found again", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_R, mods: ctrl, wait: 2500, expect: () => !view.reader && view.article === "yes" && !view.loading, page: "!!document.querySelector('.navmenu')" },
        { name: "(the article again)", key: Qt.Key_R, mods: ctrl | Qt.AltModifier, wait: 1000, expect: () => view.reader },
        { name: "an address loaded over it ends it: the news page, which has an article too", wait: 2500, act: () => app.go(check.local("/reader-news"), "navigate"),
          expect: () => !view.reader && view.title === "Harbour ferries move to battery power by 2028 | The Harbour Post" && view.article === "yes",
          page: "!!document.querySelector('.cookie-banner') && !document.querySelector('.browser-reader')" },
        { name: "Ctrl+Alt+R on the news article, whose policy refuses inline styles: laid out all the same, its headline, the site and the author, the story; the cookie banner, sections, ads, the newsletter form and most read left out",
          focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_R, mods: ctrl | Qt.AltModifier, wait: 1000, expect: () => view.reader,
          page: "JSON.stringify({ title: document.querySelector('.browser-reader-title').textContent, byline: document.querySelector('.browser-reader-byline').textContent,"
              + " text: document.body.innerText, ground: getComputedStyle(document.body).backgroundColor })",
          pageExpect: v => { const r = JSON.parse(v), t = r.text;
              probe.report("     title " + JSON.stringify(r.title) + "; byline " + JSON.stringify(r.byline) + "; related box " + (t.indexOf("Quay cranes to run overnight") >= 0 ? "kept" : "left out")
                           + "; share tools " + (t.indexOf("Share") >= 0 ? "kept" : "left out") + "; the lead image's caption " + (t.indexOf("first charging mast goes up") >= 0 ? "kept" : "left out"));
              return r.ground === check.rgbOf(Theme.terminal) && r.title === "Harbour ferries move to battery power by 2028" && r.byline === "The Harbour Post · Lina Park"
                  && t.indexOf("replace all six of the city's diesel ferries") >= 0 && t.indexOf("smell of exhaust") >= 0
                  && ["We use cookies", "Accept all", "Advertisement", "Get the City newsletter", "Sign up", "Most read", "All rights reserved", "Opinion"].every(w => t.indexOf(w) < 0) } },
        { name: "a link to a heading in it (the address's #) keeps the article", focus: "location.hash = 'story'", wait: 500,
          act: () => probe.grab(app, "reader-news"),
          expect: () => view.reader && String(view.url).endsWith("#story"), page: "document.body.className", pageExpect: v => v === "browser-reader" },
        { name: "the page's own address change (history.pushState) leaves it: the page's body back", focus: "history.pushState({}, '', '/reader-news-2')", wait: 800,
          expect: () => !view.reader && String(view.url) === check.local("/reader-news-2"), page: "!!document.querySelector('.cookie-banner') && !document.querySelector('.browser-reader')" },
        { name: "the new address is asked again, as a load is: the page's script puts a list of links in and pushes another address, and it has no article",
          focus: "document.body.innerHTML = '<ul>' + Array.from({ length: 30 }, (_, i) => '<li><a href=/x' + i + '>link ' + i + '</a>').join('') + '</ul>';"
              + " history.pushState({}, '', '/reader-news-3')", wait: 1000,
          expect: () => !view.reader && view.article === "none" && view.articleAt === check.local("/reader-news-3") },
        { name: "the GitHub-like issue list: no article", wait: 2500, act: () => app.go(check.local("/reader-github"), "navigate"),
          expect: () => view.title === "Issues · linux-msm/linux" && !view.loading && view.article === "none" && !view.reader },
        { name: "Ctrl+I: Reader view is a plain row saying “No article here”, which takes no click or key", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_I, mods: ctrl, wait: 900,
          expect: () => { const panel = rail.sitePanel;
              return site.open && site.article === "none" && check.siteKinds().indexOf("reader") >= 0 && panel.target("site:reader") === null
                  && check.named(panel, "readerValue").text === "No article here" && !panel.hits().some(h => h.objectName === "site:reader") && (probe.grab(app, "reader-none"), true) } },
        { name: "(Esc closes the panel)", key: Qt.Key_Escape, wait: 500, expect: () => !site.open },
        { name: "Ctrl+Alt+R there: “No article here” in the card; the page as it was", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_R, mods: ctrl | Qt.AltModifier, wait: 700,
          expect: () => { probe.report("     card: " + JSON.stringify(check.noticeText())); return !view.reader && check.noticeText() === "No article here" },
          page: "!!document.querySelector('.js-navigation-container') && !document.querySelector('.browser-reader')" },
        { name: "3 s later it is gone", wait: 2800, expect: () => check.noticeText() === "" },
        { name: "> Reader view says “No article here”, and Enter there does nothing", wait: 900, act: () => app.editAddress(">reader"),
          expect: () => address.rows.length === 1 && address.rows[0].kind === "stub" && address.rows[0].title === "Reader view" && address.rows[0].detail === "No article here" },
        { name: "(Enter: nothing; Esc)", wait: 500, act: () => { probe.press(Qt.Key_Return, 0); check.later(() => probe.press(Qt.Key_Escape, 0)) },
          expect: () => !address.editing && !view.reader },
        // the groups after this one start on a web page, as they would without it
        { name: "(the reader thread closed)", wait: 1000, act: () => app.closePage(check.readerPage), expect: () => !session.pages[check.readerPage] },
        { name: "(a plain page on screen)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" && !view.loading },
    ]
    property string readerPage: ""
    // Main's notice as the rail's card shows it on its second line ("Saved · Edit", "No article here"), "" for none
    function noticeText() { const f = rail.addressField; return f.shownNotice ? f.shownNotice.text : "" }
    // "rgb(r, g, b)" of an opaque colour, as getComputedStyle reads it
    function rgbOf(c) { return "rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")" }

    // Print (PLAN.md 3.16), on a page of a coloured band and three sections a page each: Ctrl+P (the card, its rows and
    // the preview from the page's PDF: A4 portrait, the band left out), a row's choices in place, a change making a new
    // preview only after 300 ms (Landscape, A5 with no margins, Backgrounds On), the pages turned and This page, Save (the
    // PDF of that page in the downloads folder under the page's title, a download row under the page, the page as its
    // origin on the file) and a second one's name, Esc and the scrim, the keys, the check's stand-in printer (Print, the job
    // recorded, "Sent to Check printer" for 3 s), window.print(), nothing on Settings or a failure page, no frame at rest,
    // a private window's PDF (no origin written, listed there alone), and the reader view printed.
    readonly property var printSteps: [
        { group: "print" },
        check.server,
        { setup: true, name: "(the main window focused)", act: () => probe.back(app), expect: () => app.active },
        { name: "(the print page, a thread of its own)", wait: 2500,
          act: () => { probe.back(app); app.go(check.local("/print-long"), "new", "", "print") },
          expect: () => { check.printPage = session.currentPage; return view.title === "print long" && !view.loading } },
        { name: "Ctrl+P: the card over the page, “Print print long”, the rows as the frame has them, the keys in it; the preview comes: All (3)",
          focus: "document.activeElement && document.activeElement.blur()", key: Qt.Key_P, mods: ctrl, wait: 2500,
          expect: () => { const c = check.pc();
              probe.report("     rows: " + check.printRows().join(" | ") + "; preview " + c.preview + "; " + c.count + " pages");
              probe.grab(app, "print-card");
              return c.opened && c.visible && c.activeFocus && c.title === "print long" && c.count === 3 && Printing.size(c.preview) > 0
                  && check.printRows().join(" | ") === "Destination Save as PDF | Pages All (3) | Layout Portrait | Paper A4 | Margins Default | Backgrounds Off"
                  && check.named(check.pc(), "print:commit").label === "Save" } },
        { name: "the preview is the page's PDF, from the temp dir: A4 portrait, its text, the band's background left out",
          expect: () => { const f = probe.pdf(check.pc().preview), band = probe.pdfColor(check.pc().preview, 0.5, 0.1);
              probe.report("     " + JSON.stringify({ pages: f.pages, width: f.width, height: f.height, left: f.left, band: band }));
              return f.pages === 3 && check.near(f, 595, 842) && f.text.indexOf("print fixture section 1") >= 0 && band === "#ffffff"
                  && check.pc().preview.startsWith(probe.tempDir() + "/browser-print-") } },
        { name: "Layout ›: its choices in place, Portrait picked", wait: 500, act: () => check.clickPrint("print:layout"),
          expect: () => { const c = check.pc(); return c.sub === "layout" && c.target("print:layout=portrait").picked && !c.target("print:layout=landscape").picked && !!c.target("print:back") } },
        { name: "Landscape: the rows back, and no new preview for 300 ms", wait: 150, act: () => { check.before = check.pc().preview; check.clickPrint("print:layout=landscape") },
          expect: () => { const c = check.pc(); return c.sub === "" && c.settings.layout === "landscape" && c.preview === check.before && c.job === null } },
        { name: "then the new preview: landscape A4 (842 × 595 pt), and the old file gone", wait: 1500,
          expect: () => { const c = check.pc(), f = probe.pdf(c.preview);
              return c.preview !== check.before && Printing.size(check.before) === -1 && check.near(f, 842, 595) && f.pages === 3 } },
        { name: "(Paper A5)", wait: 500, act: () => { check.clickPrint("print:paper"); check.later(() => check.clickPrint("print:paper=A5")) },
          expect: () => check.pc().settings.paper === "A5" && check.pc().sub === "" },
        { name: "(its text's left edge with Default margins)", wait: 1500,
          expect: () => { const f = probe.pdf(check.pc().preview); check.leftBefore = f.left; return check.near(f, 595, 420) && f.left > 20 } },
        { name: "Margins None: the text starts at the paper's edge, 10 mm (28 pt) further left", wait: 1800,
          act: () => { check.clickPrint("print:margins"); check.later(() => check.clickPrint("print:margins=none")) },
          expect: () => { const f = probe.pdf(check.pc().preview); probe.report("     left " + check.leftBefore + " -> " + f.left);
              return check.pc().settings.margins === "none" && Math.abs(check.leftBefore - f.left - 28.35) < 2 } },
        { name: "Backgrounds On: the band prints", wait: 1800,
          act: () => { check.clickPrint("print:backgrounds"); check.later(() => check.clickPrint("print:backgrounds=on")) },
          expect: () => { const c = probe.pdfColor(check.pc().preview, 0.5, 0.05); probe.report("     band " + c); return c === "#cc3333" } },
        { name: "(back to portrait A4, default margins, no backgrounds)", wait: 2000,
          act: () => { const c = check.pc(); c.set("layout", "portrait"); c.set("paper", "A4"); c.set("margins", "default"); c.set("backgrounds", "off") },
          expect: () => { const f = probe.pdf(check.pc().preview); return check.near(f, 595, 842) && probe.pdfColor(check.pc().preview, 0.5, 0.1) === "#ffffff" } },
        { name: "Right turns the preview to page 2 of 3", key: Qt.Key_Right, wait: 400, expect: () => check.pc().page === 2 && check.pc().activeFocus },
        { name: "Pages ›: All picked, then This page (2)", wait: 500, act: () => check.clickPrint("print:pages"),
          expect: () => check.pc().target("print:pages=all").picked && !!check.pc().target("print:pages=this") },
        { name: "(This page)", wait: 400, act: () => check.clickPrint("print:pages=this"),
          expect: () => check.pc().settings.pages === "this" && check.printRows()[1] === "Pages This page (2)" },
        { name: "Save: the card goes, the keys back on the page; page 2 alone as “print long.pdf” in the downloads folder, a download row under the page, the page its origin on the file",
          wait: 2500, act: () => { check.downloadCount = session.downloads.length; check.clickPrint("print:commit") },
          expect: () => { const d = check.lastDownload(), f = d ? probe.pdf(d.path) : {}, a = d ? probe.attributes(d.path) : {};
              probe.report("     " + JSON.stringify({ file: d && d.file, state: d && d.state, pages: f.pages, text: f.text, xattrs: a, row: !!(d && check.rowOf("d:" + d.id)) }));
              return !check.pc().opened && view.activeFocus && session.downloads.length === check.downloadCount + 1 && d.file === "print long.pdf"
                  && d.path === app.downloadFolder + "/print long.pdf" && d.state === "done" && d.page === check.printPage && d.total === Printing.size(d.path)
                  && f.pages === 1 && f.text.indexOf("print fixture section 2") >= 0 && f.text.indexOf("section 1") < 0
                  && a["user.xdg.origin.url"] === check.local("/print-long") && !!check.rowOf("d:" + d.id) } },
        { name: "the preview's file went with the card", expect: () => Printing.size(check.before) === -1 && check.pc().preview === "" },
        { name: "Ctrl+P again: the card as it opens (All, page 1); Enter saves every page as “print long (1).pdf”", key: Qt.Key_P, mods: ctrl, wait: 2000,
          expect: () => check.pc().opened && check.pc().count === 3 && check.pc().settings.pages === "all" && check.pc().page === 1 },
        { name: "(Enter)", key: Qt.Key_Return, wait: 2500,
          expect: () => { const d = check.lastDownload(); return !check.pc().opened && d.file === "print long (1).pdf" && probe.pdf(d.path).pages === 3 } },
        { name: "Esc cancels: nothing saved, the preview's file gone", wait: 2500, focus: "document.activeElement && document.activeElement.blur()",
          act: () => { check.downloadCount = session.downloads.length; probe.press(Qt.Key_P, ctrl) },
          expect: () => { check.before = check.pc().preview; return check.pc().opened && check.pc().count === 3 } },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 500,
          expect: () => !check.pc().opened && Printing.size(check.before) === -1 && session.downloads.length === check.downloadCount && view.activeFocus },
        { name: "a click on the scrim cancels too", wait: 2000, key: Qt.Key_P, mods: ctrl, expect: () => check.pc().opened },
        { name: "(the click, beside the card)", wait: 500, act: () => { probe.pointer(app.railWidth + 30, 60); probe.pointer(app.railWidth + 30, 60, Qt.LeftButton); probe.pointer(app.railWidth + 30, 60) },
          expect: () => !check.pc().opened && session.downloads.length === check.downloadCount },
        { name: "the keys: Tab reaches Paper, Enter lists its choices with the keys on A4, Down and Enter pick Letter, the keys back on Paper",
          wait: 2500, key: Qt.Key_P, mods: ctrl, expect: () => check.pc().opened && check.pc().count === 3 },
        { name: "(Tab to Paper: next page, Destination, Pages, Layout, Paper)", wait: 300,
          act: () => { for (let i = 0; i < 5; i++) probe.press(Qt.Key_Tab, 0) }, expect: () => check.pc().target("print:paper").activeFocus },
        { name: "(Enter)", key: Qt.Key_Return, wait: 400, expect: () => check.pc().sub === "paper" && check.pc().target("print:paper=A4").activeFocus },
        { name: "(Down three times, Enter)", wait: 400, act: () => { for (let i = 0; i < 3; i++) probe.press(Qt.Key_Down, 0); probe.press(Qt.Key_Return, 0) },
          expect: () => check.pc().settings.paper === "Letter" && check.pc().sub === "" && check.pc().target("print:paper").activeFocus },
        { name: "Esc on a row's choices goes back to the rows, then Esc cancels", wait: 400,
          act: () => { probe.press(Qt.Key_Return, 0); probe.press(Qt.Key_Escape, 0) }, expect: () => check.pc().opened && check.pc().sub === "" },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 400, expect: () => !check.pc().opened },
        { name: "the check's stand-in printer after Save as PDF in Destination; picked, the button says Print", wait: 2000,
          act: () => { probe.press(Qt.Key_P, ctrl); check.later(() => check.clickPrint("print:destination")) },
          expect: () => { const c = check.pc();
              return c.printers.join() === "Check printer" && c.sub === "destination" && !!c.target("print:destination=Save as PDF") && !!c.target("print:destination=Check printer") } },
        { name: "(Check printer)", wait: 500, act: () => check.clickPrint("print:destination=Check printer"),
          expect: () => check.printRows()[0] === "Destination Check printer" && check.named(check.pc(), "print:commit").label === "Print" },
        { name: "Print: the page's PDF to it, named after the page, on A4; the card closes, “Sent to Check printer” in the card, the job's file gone",
          wait: 1500, act: () => { check.jobs = Printing.jobs().length; check.clickPrint("print:commit") },
          expect: () => { const j = Printing.jobs()[Printing.jobs().length - 1];
              probe.report("     job: " + JSON.stringify(j) + "; card: " + JSON.stringify(check.noticeText()));
              return !check.pc().opened && Printing.jobs().length === check.jobs + 1 && j.printer === "Check printer" && j.title === "print long" && j.paper === "A4"
                  && j.bytes > 0 && Printing.size(j.path) === -1 && check.noticeText() === "Sent to Check printer" } },
        { name: "3 s later the card's line is gone", wait: 2500, expect: () => check.noticeText() === "" },
        { name: "window.print() from the page: the card", focus: "print()", wait: 2000, expect: () => check.pc().opened },
        { name: "the page loading another document closes it: the card was for the one that went", wait: 2500,
          act: () => { check.before = check.pc().preview; view.reload() },
          expect: () => !check.pc().opened && Printing.size(check.before) === -1 && view.title === "print long" && !view.loading },
        { name: "the card open, the preview drawn: no frame in 2 s", wait: 2500, key: Qt.Key_P, mods: ctrl,
          expect: () => check.pc().opened && check.pc().count === 3 },
        { name: "(nothing changing)", wait: 2000, act: () => check.frames = 0, expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 400, expect: () => !check.pc().opened },
        { name: "Ctrl+P on Settings does nothing", key: Qt.Key_Comma, mods: ctrl, wait: 1500,
          act: () => check.later(() => probe.press(Qt.Key_P, ctrl)), expect: () => app.ownKind === "settings" && !check.pc().opened },
        { name: "(Settings closed, the print page on screen)", wait: 1500,
          act: () => { for (const id of check.ownPages("browser://settings")) app.closePage(id); check.later(() => app.show(check.printPage)) },
          expect: () => check.ownPages("browser://settings").length === 0 && view.title === "print long" },
        { name: "nor on a failure page (a refused connection)", wait: 3000, act: () => app.go("http://127.0.0.1:" + probe.closedPort() + "/", "navigate"),
          expect: () => !!view.failure },
        { name: "(Ctrl+P there)", key: Qt.Key_P, mods: ctrl, wait: 600, expect: () => !check.pc().opened },
        { name: "(back on the print page)", wait: 2500, act: () => app.go(check.local("/print-long"), "navigate"), expect: () => !view.failure && view.title === "print long" },
        { name: "two Saves, the second asked for before the first has landed: two files, \u201cprint long (2).pdf\u201d and \u201c(3)\u201d, both under the page",
          wait: 5000, act: () => { check.downloadCount = session.downloads.length; app.openPrint(); check.later(() => { const c = check.pc(); c.commit(); app.openPrint(); c.commit() }) },
          expect: () => { const got = session.downloads.slice(check.downloadCount).map(d => d.file + ":" + d.state + ":" + probe.pdf(d.path).pages);
              probe.report("     " + got.join(", "));
              return !check.pc().opened && check.pc().job === null && got.join() === "print long (2).pdf:done:3,print long (3).pdf:done:3" } },
        { name: "(another page to print, a thread of its own, its card's preview drawn)", wait: 3000,
          act: () => { app.go(check.local("/print-long"), "new", "", "print two"); check.later(() => check.later(() => check.later(() => app.openPrint()))) },
          expect: () => { check.printTwo = session.currentPage; return check.printTwo !== check.printPage && check.pc().opened && check.pc().count === 3 } },
        { name: "Save, and its page closed before the PDF is made: the job fails, saying so, and nothing is saved", wait: 1500,
          act: () => { check.downloadCount = session.downloads.length; check.pc().commit(); app.finishClose(check.printTwo) },
          expect: () => { probe.report("     card: " + JSON.stringify(check.noticeText()) + "; the file " + Printing.size(app.downloadFolder + "/print long (4).pdf"));
              return !session.pages[check.printTwo] && check.pc().job === null && check.pc().queued.length === 0 && session.downloads.length === check.downloadCount
                  && check.noticeText() === "Not saved: the page could not be printed" } },
        { name: "and Ctrl+P works on after it: the card and its preview", wait: 2500,
          act: () => { app.show(check.printPage); check.later(() => app.openPrint()) },
          expect: () => view.title === "print long" && check.pc().opened && check.pc().count === 3 && check.pc().job === null },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 400, expect: () => !check.pc().opened },
        { name: "the reader view prints as it shows: the article's text, not the menu", wait: 3500,
          act: () => app.go(check.local("/reader-lwn"), "navigate"),
          expect: () => view.title === "Lane configuration for camera PHYs [LWN.net]" && !view.loading && view.article === "yes" },
        { name: "(Ctrl+Alt+R, Ctrl+P)", wait: 3000, focus: "document.activeElement && document.activeElement.blur()",
          act: () => { probe.press(Qt.Key_R, ctrl | Qt.AltModifier); check.later(() => probe.press(Qt.Key_P, ctrl)) },
          expect: () => { const c = check.pc(), f = c.preview ? probe.pdf(c.preview) : { text: "" };
              probe.grab(app, "print-reader");
              if (c.preview)
                  probe.keep(c.preview, "print-reader.pdf");
              probe.report("     " + f.pages + " pages; " + f.text.slice(0, 80).replace(/\s+/g, " "));
              return view.reader && c.opened && f.text.indexOf("Lane configuration for camera PHYs") >= 0 && f.text.indexOf("Weekly edition") < 0 } },
        { name: "(Esc; the page back)", wait: 800, act: () => { probe.press(Qt.Key_Escape, 0); check.later(() => probe.press(Qt.Key_R, ctrl | Qt.AltModifier)) },
          expect: () => !check.pc().opened && !view.reader },
        { name: "a private window: Ctrl+P and Save there; the PDF lands in the downloads folder, listed in that window alone, with no origin written on it",
          wait: 3500, act: () => {
              check.privateWin = app.newPrivateWindow(app.windowState());
              check.privateWin.afterClose();
              probe.back(check.privateWin);
              check.privateWin.go(check.served("printhush", "/print-long"), "new", "", "hush print");
              check.downloadCount = session.downloads.length;
          },
          expect: () => { const w = check.privateWin; return w.currentView && w.currentView.title === "print long" && !w.currentView.loading } },
        { name: "(Ctrl+P, Enter there)", wait: 3500,
          act: () => { probe.press(Qt.Key_P, ctrl); check.later(() => check.privateWin.windowPrint.commit()) },
          expect: () => { const w = check.privateWin, s = w.windowSession, d = s.downloads[s.downloads.length - 1];
              probe.report("     " + (d ? d.file + " at " + d.path + "; xattrs " + JSON.stringify(probe.attributes(d.path)) : "no record"));
              return !!d && /^print long( \(\d+\))?\.pdf$/.test(d.file) && d.state === "done" && Printing.size(d.path) > 0 && Object.keys(probe.attributes(d.path)).length === 0
                  && session.downloads.length === check.downloadCount && !session.downloads.some(x => x.path === d.path) } },
        { name: "(the private window closed)", wait: 1000, act: () => { check.privateWin.closePrivate(); check.privateWin = null; probe.back(app) }, expect: () => app.privateWindows.length === 0 },
        // the groups after this one start on a web page, as they would without it
        { name: "(the print thread closed)", wait: 1000, act: () => app.closePage(check.printPage), expect: () => !session.pages[check.printPage] },
        { name: "(a plain page on screen)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" && !view.loading },
    ]
    property string printPage: ""
    property string before: ""
    property real leftBefore: 0
    property int jobs: 0
    property var privateWin: null
    function pc() { return app.windowPrint }
    property string printTwo: ""
    // a PDF page of about `w` x `h` points (Chromium's A4 is 594.96 x 840.96)
    function near(f, w, h) { return Math.abs(f.width - w) < 3 && Math.abs(f.height - h) < 3 }
    // the print card's rows as they read: "<label> <value>"
    function printRows() {
        return ["destination", "pages", "layout", "paper", "margins", "backgrounds"].map(k => {
            const t = pc().target("print:" + k);
            if (!t)
                return "";
            const labels = [];
            for (const c of t.children)
                if (c.text !== undefined && c.visible && c.iconSize === undefined)     // a Symbol's text is its glyph's name
                    labels.push(c.text);
            return labels.filter(x => x).join(" ");
        });
    }
    // the print card's click target `name`, clicked through the window system
    function clickPrint(name) {
        const t = pc().target(name);
        if (!t)
            throw new Error("the print card shows no " + name);
        const p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }

    // Import from Zen (PLAN.md 3.4, 3.15, `zen`) from Zen folders made up in the throwaway data dir (EngineCheck::zenProfile):
    // the profile of the install its desktop entry starts, not the one marked Default=1; the first-run card's row (Down,
    // Enter) opening Settings at Import; the bookmarks into Saved by folder (a separator, a bookmarklet, a query and a
    // tag left out, one only in the write-ahead log of a database held exclusively, as a running Zen holds it), the
    // history (hidden, unvisited and file: rows left out), and the logins decrypted by NSS in the helper into the keyring
    // (an HTTP sign-in left out, one the keyring had kept as it was); nothing twice on a second import; a primary password
    // asked for in the row (a wrong one, the right one, Skip); no keyring answering; the profiles never written, no copy
    // left in the temp dir, and no password or user name in any file of the data dir or in the run's output.
    // A password manager's file (PasswordFile, book4-edge/thyris-migration-plan.md): exports of nine services, made up
    // afresh each run with logins never printed, read by their header (the service named, what each row gave or why it
    // was left out, no password in what QML gets), then brought into a throwaway keyring (each password exact, a second
    // time adds none), the file deleted, and no password in a file of the throwaway data dir or in this run's output.
    readonly property var passwordFileSteps: [
        { group: "passwordfile" },
        { name: "(a Secret Service of the check's own, unlocked; the logins made up for this run, never printed)", wait: 1500,
          act: () => {
              const pf = { steps: 0, saved: null };
              for (let i = 1; i <= 9; i++) {
                  pf["user" + i] = check.letters(9);
                  pf["pass" + i] = check.letters(15);
              }
              pf.odd = 'PA,"' + check.letters(6) + '\n' + check.letters(6);   // a comma, a quote and a line break
              check.pf = pf;
              check.pwKeyring = check.pwKeyring || check.letters(14);
              check.keyringBus = check.keyringBus || probe.startKeyring(check.pwKeyring);
              probe.lockKeyring(false);
              if (Passwords.state !== "ready")
                  Passwords.useBus(check.keyringBus);
              PasswordFile.saved.connect(r => check.pf.saved = r);
              PasswordFile.progress.connect(() => check.pf.steps++);
          },
          expect: () => check.keyringBus !== "" && Passwords.state === "ready" },
        { name: "a Bitwarden export: three logins (one with two addresses), its note and an app's login left out with their reasons",
          act: () => {
              const q = v => '"' + v.replace(/"/g, '""') + '"';
              check.pf.bitwarden = probe.fixtureFile("bitwarden_export.csv", "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n"
                  + ",,login,Site A,,,0,https://a.pf.test/login," + check.pf.user1 + "," + check.pf.pass1 + ",\n"
                  + ",,login,Site B,,,0," + q("https://b.pf.test,https://b2.pf.test/x") + "," + check.pf.user2 + "," + check.pf.pass2 + ",\n"
                  + ",,note,A note,just a note,,0,,,,\n"
                  + ",,login,An app,,,0,android://hash@com.example.app/," + check.pf.user3 + "," + check.pf.pass3 + ",\n");
              check.pf.read = PasswordFile.read(check.pf.bitwarden);
          },
          expect: () => { const r = check.pf.read, why = r.skipped.map(x => x.what + " " + x.why).sort().join("; ");
              probe.report("     " + r.service + ", " + r.logins + " logins; left out: " + why);
              return r.service === "Bitwarden" && r.logins === 3 && r.failure === ""
                  && why === "1 entry an app's, with no web address; 1 entry not a login (a note, a card or an identity)"
                  && ![check.pf.pass1, check.pf.pass2, check.pf.pass3].some(x => JSON.stringify(r).indexOf(x) >= 0) && PasswordFile.state === "read" } },
        { name: "brought into the keyring: each login with its exact password, the strip told each step, the logins dropped from memory", wait: 3000,
          act: () => PasswordFile.bring(),
          expect: () => !!check.pf.saved && check.pf.saved.added === 3 && check.pf.saved.kept === 0 && check.pf.saved.failure === "" && check.pf.steps === 3
              && probe.keyringHolds("https://a.pf.test", check.pf.user1, check.pf.pass1) && probe.keyringHolds("https://b.pf.test", check.pf.user2, check.pf.pass2)
              && probe.keyringHolds("https://b2.pf.test", check.pf.user2, check.pf.pass2) && !probe.keyringHolds("https://com.example.app", check.pf.user3, check.pf.pass3)
              && PasswordFile.state === "" && !PasswordFile.bring() },
        { name: "the same file again adds none: all three kept as the keyring has them", wait: 3000,
          act: () => { check.pf.saved = null; PasswordFile.read(check.pf.bitwarden); PasswordFile.bring() },
          expect: () => !!check.pf.saved && check.pf.saved.added === 0 && check.pf.saved.kept === 3 },
        { name: "deleted when asked: the file is gone, and reading it again says it can't be opened",
          act: () => { check.pf.removed = PasswordFile.removeFile(); check.pf.again = PasswordFile.read(check.pf.bitwarden) },
          expect: () => check.pf.removed && check.pf.again.failure === "Thyris can't open that file." },
        { name: "Google Password Manager's (Chrome's) export with a byte order mark, \\r\\n, and a password holding a comma, a quote and a line break: exact in the keyring", wait: 2500,
          act: () => {
              check.pf.saved = null;
              const q = v => '"' + v.replace(/"/g, '""') + '"';
              const r = PasswordFile.read(probe.fixtureFile("Chrome Passwords.csv", "﻿name,url,username,password,note\r\nSite C,https://c.pf.test/," + check.pf.user4 + "," + q(check.pf.odd) + "," + q("a, note") + "\r\n"));
              check.pf.google = r.service + " " + r.logins;
              PasswordFile.bring();
          },
          expect: () => check.pf.google === "Google Password Manager 1" && !!check.pf.saved && check.pf.saved.added === 1
              && probe.keyringHolds("https://c.pf.test", check.pf.user4, check.pf.odd) },
        { name: "Firefox's: an address's port kept; 1Password's: an address with no scheme taken as https; Proton Pass's: the e-mail where the user name is empty", wait: 3500,
          act: () => {
              check.pf.saved = null;
              const ff = PasswordFile.read(probe.fixtureFile("logins.csv", '"url","username","password","httpRealm","formActionOrigin","guid","timeCreated","timeLastUsed","timePasswordChanged"\n'
                  + '"http://d.pf.test:8080","' + check.pf.user5 + '","' + check.pf.pass5 + '",,"http://d.pf.test:8080","{1}","1","1","1"\n'));
              check.pf.firefox = ff.service + " " + ff.logins;
              check.pf.firefoxBring = PasswordFile.bring();
          },
          expect: () => check.pf.firefox === "Firefox 1" && !!check.pf.saved && probe.keyringHolds("http://d.pf.test:8080", check.pf.user5, check.pf.pass5) },
        { name: "(1Password's export)", wait: 2500,
          act: () => {
              check.pf.saved = null;
              const op = PasswordFile.read(probe.fixtureFile("1PasswordExport.csv", "Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes\n"
                  + "Site E,e.pf.test," + check.pf.user6 + "," + check.pf.pass6 + ",,false,false,,\n"));
              check.pf.one = op.service + " " + op.logins;
              PasswordFile.bring();
          },
          expect: () => check.pf.one === "1Password 1" && !!check.pf.saved && probe.keyringHolds("https://e.pf.test", check.pf.user6, check.pf.pass6) },
        { name: "(Proton Pass's export)", wait: 2500,
          act: () => {
              check.pf.saved = null;
              const pp = PasswordFile.read(probe.fixtureFile("Proton Pass_export.csv", "type,name,url,email,username,password,note,totp,createTime,modifyTime,vault\n"
                  + "login,Site F,https://f.pf.test," + check.pf.user7 + "@pf.test,," + check.pf.pass7 + ",,,1,1,Personal\n"
                  + "note,A note,,,,,secret,,1,1,Personal\n"));
              check.pf.proton = pp.service + " " + pp.logins + " " + pp.skipped.length;
              PasswordFile.bring();
          },
          expect: () => check.pf.proton === "Proton Pass 1 1" && !!check.pf.saved && probe.keyringHolds("https://f.pf.test", check.pf.user7 + "@pf.test", check.pf.pass7) },
        { name: "Apple Passwords', KeePassXC's, LastPass's and Dashlane's exports named by their headers",
          act: () => {
              const row = (h, r) => PasswordFile.read(probe.fixtureFile("x.csv", h + "\n" + r + "\n")).service;
              check.pf.names = [
                  row("Title,URL,Username,Password,Notes,OTPAuth", "G,https://g.pf.test,u,p,,"),
                  row('"Group","Title","Username","Password","URL","Notes","TOTP","Icon","Last Modified","Created"', '"Root","H","u","p","https://h.pf.test","","","0","",""'),
                  row("url,username,password,totp,extra,name,grouping,fav", "https://i.pf.test,u,p,,,I,,0"),
                  row("username,username2,username3,title,password,note,url,category,otpSecret", "u,,,J,p,,https://j.pf.test,,")].join("|");
              PasswordFile.forget();
          },
          expect: () => check.pf.names === "Apple Passwords|KeePassXC|LastPass|Dashlane" },
        { name: "a file that is no password export is refused with the reason; rows with no password or a repeated login are left out as such",
          act: () => {
              check.pf.not = PasswordFile.read(probe.fixtureFile("people.csv", "name,age\nbob,3\n"));
              const r = PasswordFile.read(probe.fixtureFile("dupes.csv", "name,url,username,password,note\nK,https://k.pf.test,u," + check.pf.pass8 + ",\nK2,https://k.pf.test/again,u," + check.pf.pass9 + ",\nL,https://l.pf.test,u,,\n"));
              check.pf.dupes = r.logins + "; " + r.skipped.map(x => x.what + " " + x.why).sort().join("; ");
              PasswordFile.forget();
          },
          expect: () => { probe.report("     " + check.pf.not.failure + " / " + check.pf.dupes);
              return check.pf.not.failure === "It has no password column, so it isn't a password export." && PasswordFile.state === ""
                  && check.pf.dupes === "1; 1 entry no password; 1 entry the same site and user name as another entry" } },
        { name: "Settings > Import: Passwords from a file, Choose… opens Welcome on the file, with where each service keeps its export", wait: 1500,
          act: () => { app.openOwn("settings", "import"); check.later(() => check.clickOwn("own:passwordFile:action")) },
          expect: () => app.welcome.visible && app.welcome.mode === "file" && app.welcome.phase === "arrive" && app.welcome.fileRoute
              && app.welcome.exportGuide.length === 5 && app.welcome.activeFocus },
        { name: "Enter picks the file in Files; a file that is no export says why on the page and nothing is held", wait: 1500,
          key: Qt.Key_Return,
          act: () => check.later(() => Picker.answer([probe.fixtureFile("people.csv", "name,age\nbob,3\n")])),
          expect: () => app.welcome.phase === "arrive" && app.welcome.notice === "That file didn't work. It has no password column, so it isn't a password export."
              && PasswordFile.state === "" },
        { name: "an export chosen: its logins count into the keyring, then done says how many and what was left out, Delete the file the way forward", wait: 3500,
          key: Qt.Key_Return,
          act: () => {
              check.pf.ui = probe.fixtureFile("bitwarden_export.csv", "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n"
                  + ",,login,Site M,,,0,https://m.pf.test," + check.pf.user8 + "," + check.pf.pass8 + ",\n"
                  + ",,login,Site A,,,0,https://a.pf.test/login," + check.pf.user1 + "," + check.pf.pass1 + ",\n"
                  + ",,note,A note,just a note,,0,,,,\n");
              check.later(() => Picker.answer([check.pf.ui]));
          },
          expect: () => { const r = app.welcome.result;
              return app.welcome.phase === "done" && !!r && r.file && r.from === "Bitwarden" && r.added === 1 && r.kept === 1 && r.stayed.length === 1
                  && probe.keyringHolds("https://m.pf.test", check.pf.user8, check.pf.pass8) } },
        { name: "Enter deletes the file: Welcome goes, the card says so, the page has the keys again", wait: 1200,
          key: Qt.Key_Return,
          expect: () => !app.welcome.visible && PasswordFile.read(check.pf.ui).failure === "Thyris can't open that file."
              && !!app.cardNotice && app.cardNotice.text === "The file is deleted." },
        { name: "no password of these files in a file of the throwaway data dir (the keyring's own aside) or in this run's output", wait: 500,
          act: () => app.saveAll(),
          expect: () => {
              const made = [1, 2, 4, 5, 6, 7].map(i => check.pf["pass" + i]);
              const holding = [].concat(...made.map(t => Array.from(probe.filesHolding(t).holding).filter(f => !f.startsWith("kr/") && !f.endsWith(".csv"))));
              probe.report("     holding one: " + (holding.join(", ") || "none"));
              return holding.length === 0 && !made.some(t => probe.outputHolding(t)) } },
    ]
    // The Chrome family (ChromeImport): a made-up home with Chrome (two profiles) and Brave, Chrome's key in the throwaway
    // keyring under application=chrome as Chromium files it, logins sealed v11 with it and v10 with "peanuts"; found most
    // recently used first with what each holds (never-save sites and app logins not counted), bookmarks and history read
    // for Main, passwords exact in the keyring; Brave's v11 ones left out for want of its key, its v10 one brought; a
    // second time adds none; no password in a file of the throwaway data dir or in the output.
    readonly property var chromeSteps: [
        { group: "chrome" },
        check.server,
        { setup: true, name: "(the main window focused, on a plain page)", wait: 1500, act: () => { probe.back(app); app.go(check.local("/plain"), "navigate") },
          expect: () => app.active && view.title === "plain" },
        { name: "(a Secret Service of the check's own; Chrome's key in it; two Chrome profiles and a Brave one made up, never printed)", wait: 1500,
          act: () => {
              const cr = { steps: 0, saved: null, read: null, cookies: null, secret: check.letters(16), braveSecret: check.letters(16), session: check.letters(20) };
              for (let i = 1; i <= 6; i++) { cr["user" + i] = check.letters(9); cr["pass" + i] = check.letters(15) }
              check.cr = cr;
              check.pwKeyring = check.pwKeyring || check.letters(14);
              check.keyringBus = check.keyringBus || probe.startKeyring(check.pwKeyring);
              probe.lockKeyring(false);
              if (Passwords.state !== "ready")
                  Passwords.useBus(check.keyringBus);
              cr.keyed = probe.keyringPut({ application: "chrome", "xdg:schema": "chrome_libsecret_os_crypt_password_v2" }, cr.secret);
              const now = Date.now(), h = 3600000;
              probe.chromeHome({ dir: ".config/google-chrome", secret: cr.secret, profiles: [
                  { dir: "Default", name: "Personal", email: "you@cr.test", active: now / 1000,
                    logins: [{ origin: "https://a.cr.test/login", user: cr.user1, password: cr.pass1, tag: "v11" },
                             { origin: "https://b.cr.test/", user: cr.user2, password: cr.pass2, tag: "v11" },
                             { origin: "http://c.cr.test:8080/", user: cr.user3, password: cr.pass3, tag: "v10" },
                             { origin: "https://never.cr.test/", user: "", password: "", never: true },
                             { origin: "android://x@com.cr.app/", user: cr.user4, password: cr.pass4, tag: "v11" }],
                    accountLogins: [{ origin: "https://a.cr.test/", user: cr.user1, password: cr.pass1, tag: "v11" }],
                    bookmarks: [{ url: "https://cr.test/one", title: "One", folder: "bar" }, { url: "https://cr.test/two", title: "Two", folder: "bar/Kernel" },
                                { url: "https://cr.test/three", title: "Three", folder: "other" }],
                    history: [{ url: "https://cr.test/h1", title: "h one", visits: 4, last: now - h }, { url: "https://cr.test/h2", title: "h two", visits: 1, last: now - 2 * h },
                              { url: "https://cr.test/hidden", title: "", visits: 1, last: now, hidden: true }, { url: "chrome://settings", title: "Settings", visits: 9, last: now }],
                    // the check's server's own session; a domain cookie; one in the clear; an expired one and a partitioned one stay behind
                    cookies: [{ host: "127.0.0.1", name: "cr_session", value: cr.session, path: "/" },
                              { host: ".cr.test", name: "pref", value: "dark", path: "/", expires: now + 30 * 24 * h, sameSite: 1 },
                              { host: ".google.com", name: "SID", value: check.letters(12), path: "/", secure: true, expires: now + 30 * 24 * h },
                              { host: "plain.cr.test", name: "old", value: "clear", path: "/", plain: true, expires: now + h },
                              { host: "gone.cr.test", name: "late", value: "x", path: "/", expires: now - h },
                              { host: "part.example", name: "chips", value: "y", path: "/", partition: "https://top.example" }],
                    // open tabs: tab two placed after tab one though named first, tab one with pages before it, a tab group, a
                    // closed tab, a chrome:// page, a popup window and an older session file, none of which come
                    tabs: [{ url: "https://cr.test/tab-two", title: "Tab two", index: 1, group: "Kernel" },
                           { url: "https://cr.test/tab-one", title: "Tab one", index: 0, back: ["https://cr.test/before", "https://cr.test/before-2"] },
                           { url: "https://cr.test/closed", title: "Closed", index: 2, closed: true },
                           { url: "chrome://newtab/", title: "New Tab", index: 3 },
                           { url: "https://cr.test/popup", title: "Popup", window: 2, popup: true },
                           { url: "https://cr.test/tab-three", title: "Tab three", window: 3 }],
                    oldTabs: [{ url: "https://cr.test/old", title: "Old" }] },
                  { dir: "Profile 1", name: "Work", email: "you@work.cr.test", active: now / 1000 - 86400,
                    logins: [{ origin: "https://w.cr.test/", user: cr.user5, password: cr.pass5, tag: "v11" }] }] });
              probe.chromeHome({ dir: ".config/BraveSoftware/Brave-Browser", secret: cr.braveSecret, profiles: [
                  { dir: "Default", name: "Personal", email: "", active: now / 1000 - 3600,
                    logins: [{ origin: "https://x.cr.test/", user: cr.user6, password: cr.pass6, tag: "v11" },
                             { origin: "https://y.cr.test/", user: cr.user6, password: cr.pass3, tag: "v10" }] }] });
              ChromeImport.read.connect(f => check.cr.read = f);
              ChromeImport.saved.connect(r => check.cr.saved = r);
              ChromeImport.progress.connect(() => check.cr.steps++);
              ChromeImport.useHome(Store.dataDir.replace(/\/browser$/, "") + "/chrome-home");
              ChromeImport.scan();
          },
          expect: () => check.cr.keyed && Passwords.state === "ready" && ChromeImport.found.length === 3 },
        { name: "found most recently used first: Chrome Personal, Brave, Chrome Work, each with its email and counts (never-save and app logins not counted; tabs open in normal windows)",
          expect: () => {
              const f = ChromeImport.found, line = p => p.browser + " " + p.name + " " + p.email + " " + p.counts.passwords + "/" + p.counts.bookmarks + "/" + p.counts.history + "/" + p.counts.sites
                  + "/" + p.counts.tabs;
              probe.report("     " + f.map(line).join(" | "));
              return f.map(line).join(" | ") === "Google Chrome Personal you@cr.test 3/3/2/3/3 | Brave Personal  2/0/0/0/0 | Google Chrome Work you@work.cr.test 1/0/0/0/0" } },
        { name: "Chrome Personal brought: bookmarks with their folders, its history and its open tabs read for Main; passwords v11 and v10 exact in the keyring, the strip told each; Google's sign-in among its cookies", wait: 4000,
          act: () => { ChromeImport.cookiesDone.connect(c => check.cr.cookies = c); ChromeImport.start(0, {}, app.profile) },
          expect: () => {
              const r = check.cr.read, s = check.cr.saved, c = check.cr.cookies;
              if (!r || !s || !c)
                  return false;
              probe.report("     cookies " + JSON.stringify(c));
              if (c.added !== 4 || c.refused !== 0 || c.left !== 0 || c.sites !== 3 || c.google !== true)
                  return false;
              const marks = r.bookmarks.map(b => b.title + ":" + b.folder.join(" / ")).sort().join(", ");
              const tabs = r.tabs.map(t => t.title + "@" + t.url.replace("https://cr.test/", "") + (t.group ? ":" + t.group : "")).join(", ");
              probe.report("     bookmarks " + marks + "; history " + r.history.length + "; tabs " + tabs + "; passwords " + JSON.stringify(s));
              return marks === "One:Bookmarks bar, Three:Other bookmarks, Two:Bookmarks bar / Kernel" && r.history.length === 3
                  && tabs === "Tab one@tab-one, Tab two@tab-two:Kernel, Tab three@tab-three"
                  && s.added === 3 && s.kept === 0 && s.left === 0 && s.failure === "" && check.cr.steps === 3
                  && probe.keyringHolds("https://a.cr.test", check.cr.user1, check.cr.pass1) && probe.keyringHolds("https://b.cr.test", check.cr.user2, check.cr.pass2)
                  && probe.keyringHolds("http://c.cr.test:8080", check.cr.user3, check.cr.pass3) && ChromeImport.state === "" } },
        { name: "and the engine sends the session cookie it brought: a page of the check's server reads it", wait: 2500,
          act: () => view.reload(),
          expect: () => view.title === "plain" && !view.loading, page: "document.cookie", pageExpect: v => String(v).indexOf("cr_session=" + check.cr.session) >= 0 },
        { name: "Brave with no key of its own in the keyring: its v11 login left out as such, its v10 one brought", wait: 4000,
          act: () => { check.cr.saved = null; ChromeImport.start(1) },
          expect: () => { const s = check.cr.saved;
              return !!s && s.added === 1 && s.left === 1 && s.failure === "no key"
                  && probe.keyringHolds("https://y.cr.test", check.cr.user6, check.cr.pass3) && !probe.keyringHolds("https://x.cr.test", check.cr.user6, "") } },
        { name: "Chrome Personal again adds none: all kept as the keyring has them", wait: 4000,
          act: () => { check.cr.saved = null; ChromeImport.start(0) },
          expect: () => !!check.cr.saved && check.cr.saved.added === 0 && check.cr.saved.kept === 3 },
        { name: "nothing wanted but bookmarks: no passwords touched, the read still comes", wait: 3000,
          act: () => { check.cr.saved = null; check.cr.read = null; ChromeImport.start(2, { passwords: false, history: false }) },
          expect: () => !!check.cr.read && check.cr.read.history.length === 0 && !!check.cr.saved && check.cr.saved.total === 0
              && !probe.keyringHolds("https://w.cr.test", check.cr.user5, "") },
        { name: "Welcome: the browsers found as rows, Chrome's two profiles named (Brave's one not), then a password manager's file; the keys on it", wait: 1500,
          act: () => app.openWelcome(),
          expect: () => {
              const rows = app.welcome.sources.map(x => x.name + (x.profile ? " · " + x.profile : "")).join(" | ");
              probe.report("     " + rows);
              return app.welcome.visible && app.welcome.phase === "arrive" && app.welcome.activeFocus
                  && rows === "Google Chrome · Personal | Brave | Google Chrome · Work | A password manager's file" } },
        { name: "Chrome Personal's open tabs alone: pages none of which loads, in a task of their own, the tab group's in its own; done counts them for the rail", wait: 3000,
          act: () => { check.crPages = Object.keys(session.pages).length;
              app.bringOver(Object.assign({}, app.welcome.sources[0], { bring: { passwords: false, bookmarks: false, history: false, sites: false } })) },
          expect: () => { const r = app.welcome.result, from = session.threads.filter(t => /^From Chrome/.test(t.title));
              const line = from.map(t => t.title + ": " + t.pages.map(id => session.pages[id].title).join(", ")).sort().join(" | ");
              probe.report("     " + line + "; " + JSON.stringify(r && r.figures));
              return app.welcome.phase === "done" && !!r && r.tabsCame === 3 && r.figures.some(f => f.value === 3 && f.place === "the rail")
                  && line === "From Chrome: Kernel: Tab two | From Chrome: Tab one, Tab three"
                  && Object.keys(session.pages).length === check.crPages + 3 && from.every(t => t.pages.every(id => !app.views[id])) } },
        { name: "brought again, none is added: they are open already", wait: 3000,
          act: () => app.bringOver(Object.assign({}, app.welcome.sources[0], { bring: { passwords: false, bookmarks: false, history: false, sites: false } })),
          expect: () => app.welcome.phase === "done" && app.welcome.result.tabsCame === 0 && Object.keys(session.pages).length === check.crPages + 3 },
        { name: "(those tasks filed; Welcome from the start again)", wait: 1000,
          act: () => { for (const t of session.threads.filter(t => /^From Chrome/.test(t.title))) app.fileThread(t.id); app.openWelcome() },
          expect: () => app.welcome.phase === "arrive" && app.welcome.visible && !session.openThreads().some(t => /^From Chrome/.test(t.title)) },
        { name: "(Down)", key: Qt.Key_Down, wait: 300, expect: () => app.welcome.chosen === 1 },
        { name: "Down again: Chrome Work chosen, the way forward saying so", key: Qt.Key_Down, wait: 300,
          expect: () => app.welcome.chosen === 2 && app.welcome.sourceName === "Chrome · Work" },
        { name: "Enter brings it: its login into the keyring, done saying how many and where", key: Qt.Key_Return, wait: 5000,
          expect: () => { const r = app.welcome.result;
              probe.report("     " + JSON.stringify(r && r.figures));
              return app.welcome.phase === "done" && !!r && r.from === "Chrome · Work" && r.figures.length === 1 && r.figures[0].value === 1 && r.google === false
                  && r.figures[0].place === "Passwords" && probe.keyringHolds("https://w.cr.test", check.cr.user5, check.cr.pass5) } },
        { name: "Enter there makes Thyris the default browser, and Welcome goes", key: Qt.Key_Return, wait: 1200,
          expect: () => !app.welcome.visible && /^xdg-mime default (browser|opsis-new-engine)\.desktop x-scheme-handler\/http/.test(Apps.lastDefaulted) },
        { name: "no password of these profiles in a file of the throwaway data dir (theirs and the keyring's aside) or in this run's output", wait: 500,
          act: () => app.saveAll(),
          expect: () => {
              const made = [1, 2, 3, 5, 6].map(i => check.cr["pass" + i]);
              const holding = [].concat(...made.map(t => Array.from(probe.filesHolding(t).holding).filter(f => !f.startsWith("kr/") && !f.startsWith("chrome-home/"))));
              probe.report("     holding one: " + (holding.join(", ") || "none"));
              return holding.length === 0 && !made.some(t => probe.outputHolding(t)) } },
        { name: "(the made-up browsers put away: none found, and the first start's marks cleared, for the groups after)", wait: 1000,
          act: () => { ChromeImport.useHome(Store.dataDir.replace(/\/browser$/, "") + "/no-browsers"); ChromeImport.scan();
              for (const k of ["broughtOver", "welcomed"]) app.prefs.set(k, null) },
          expect: () => ChromeImport.found.length === 0 && !app.prefs.get("broughtOver") && !app.welcome.visible },
    ]
    // Security keys (book4-edge/cef-pgo/webauthn-patch.py): the engine says each step of a page's WebAuthn request
    // (PageItem.webAuthnStep) and the passkey ask in the card answers it (PageItem.webAuthnAnswer). First with the steps
    // made up, as Opsis's CEF build says them; then a real request through the engine, Chromium's virtual security key
    // (the DevTools WebAuthn domain) answering, which needs that build.
    readonly property var passkeySteps: [
        { group: "passkeys" },
        check.server,
        { name: "(a page of its own, on localhost: a secure context and a relying party)", wait: 1500,
          act: () => { probe.back(app); app.go("http://localhost:" + check.port + "/asks", "new", "", "passkeys") },
          expect: () => view.title === "asks" && !view.loading },
        { name: "a request's first step: the card asks to use a passkey, Touch your security key, Cancel", wait: 500,
          act: () => view.webAuthnStep(41, { state: "touch", rp: "localhost", create: false }),
          expect: () => { const m = check.section().model;
              return !!view.ask && view.ask.kind === "passkey" && view.ask.state === "touch" && /to use a passkey$/.test(m.lines[0].text)
                  && m.lines[1].text === "Touch your security key" && m.buttons.map(b => b.label).join() === "Cancel" } },
        { name: "the key asks its PIN: a secret field and Continue; a wrong one says so, with the tries left", wait: 500,
          act: () => view.webAuthnStep(41, { state: "pin", rp: "localhost", reason: "Challenge", error: "WrongPin", minLength: 4, attempts: 5 }),
          expect: () => { const m = check.section().model;
              return view.ask.state === "CollectPin" && view.ask.pinError === "WrongPin" && view.ask.attempts === 5 && m.fields[0].secret === true
                  && m.notes[0] === "Wrong PIN · 5 tries left" } },
        { name: "Continue with a PIN answers the engine's request (the check notes the answer, never the PIN)", wait: 300,
          act: () => view.answer(view.ask, "pin", { pin: check.letters(6) }),
          expect: () => view.lastWebAuthnAnswer === "41 pin" },
        { name: "accounts to choose from: their names", wait: 500,
          act: () => view.webAuthnStep(41, { state: "accounts", rp: "localhost", names: ["abdul", "work"] }),
          expect: () => view.ask.state === "SelectAccount" && view.ask.options.join() === "abdul,work" },
        { name: "the second picked: its place goes to the engine", wait: 300,
          act: () => view.answer(view.ask, "account", { picked: 1 }),
          expect: () => view.lastWebAuthnAnswer === "41 account" },
        { name: "a failure: the card says why, Try again", wait: 500,
          act: () => view.webAuthnStep(41, { state: "failed", rp: "localhost", failure: "KeyNotRegistered" }),
          expect: () => view.ask.state === "RequestFailed" && check.section().model.lines[1].text === "This security key isn't registered here" },
        { name: "Try again answers retry", wait: 300, act: () => view.answer(view.ask, "retry", {}), expect: () => view.lastWebAuthnAnswer === "41 retry" },
        { name: "done, then the request's end: the ask goes", wait: 600,
          act: () => { view.webAuthnStep(41, { state: "done", rp: "localhost" }); view.webAuthnStep(41, { state: "end", rp: "localhost" }) },
          expect: () => !view.ask },
        { name: "another request, cancelled in the card: the engine hears cancel and the ask goes", wait: 800,
          act: () => { view.webAuthnStep(42, { state: "touch", rp: "localhost" }); check.later(() => view.answer(view.ask, "cancel", {})) },
          expect: () => view.lastWebAuthnAnswer === "42 cancel" && !view.ask },
        { name: "(its end comes after: nothing more)", wait: 400, act: () => view.webAuthnStep(42, { state: "end" }), expect: () => !view.ask },
        { name: "the engine's bridge is there (Opsis's CEF build with webauthn-patch.py)", expect: () => view.webAuthnBridge },
        { name: "a passkey made through the engine's handler with Chromium's virtual security key: Thyris hears it done, then its end, and the page has its credential (the virtual key answers at once: a real key's Touch step is the owner's check)", wait: 5000,
          act: () => { check.passkeyStates = [];
              view.webAuthnStep.connect((r, step) => check.passkeyStates.push(step.state + (step.state === "touch" && view.ask ? ":asked" : "")));
              view.devtoolsCall("WebAuthn.enable", { enableUI: true });      // the prompt kept: Chromium switches it off for a virtual key unless asked
              view.devtoolsCall("WebAuthn.addVirtualAuthenticator", { options: { protocol: "ctap2", transport: "usb", hasResidentKey: true,
                  hasUserVerification: true, isUserVerified: true, automaticPresenceSimulation: true } });
              check.later(() => view.runJavaScript("passkey()")) },
          expect: () => { probe.report("     steps " + check.passkeyStates.join(" ")); return check.passkeyStates.indexOf("done") >= 0 && check.passkeyStates[check.passkeyStates.length - 1] === "end" && !view.ask },
          page: "log.join()", pageExpect: v => /passkey ok/.test(String(v)) },
    ]
    property var passkeyStates: []

    // The Firefox family (Zen's import, its discovery a table of members): a made-up home with Zen and Firefox, each found
    // with the profile its install uses and counted, Zen chosen first as before; Firefox chosen: Settings > Import names
    // it, its bookmarks land in Saved as "From Firefox", its login exact in the keyring, its rows say Firefox, not Zen.
    readonly property var foxSteps: [
        { group: "foxfamily" },
        check.server,
        { setup: true, name: "(the main window focused, on a plain page)", wait: 1500, act: () => { probe.back(app); app.go(check.local("/plain"), "navigate") },
          expect: () => app.active && view.title === "plain" },
        { name: "(a Secret Service of the check's own; a home with Zen and Firefox made up, logins never printed)", wait: 1500,
          act: () => {
              check.fx = { user: check.letters(9), pass: check.letters(15) };
              check.pwKeyring = check.pwKeyring || check.letters(14);
              check.keyringBus = check.keyringBus || probe.startKeyring(check.pwKeyring);
              probe.lockKeyring(false);
              if (Passwords.state !== "ready")
                  Passwords.useBus(check.keyringBus);
              probe.zenProfile("fox-home/.config/zen", { entry: "zen-browser", name: "Zen fox", primary: "",
                  bookmarks: [{ folder: "toolbar", url: "https://zen.fx.test/", title: "Zen mark" }], history: [], logins: [] });
              probe.zenProfile("fox-home/.mozilla/firefox", { entry: "firefox", name: "default-release", primary: "",
                  bookmarks: [{ folder: "toolbar", url: "https://fx.test/one", title: "One" }, { folder: "toolbar/Kernel", url: "https://fx.test/two", title: "Two" }],
                  history: [{ url: "https://fx.test/h1", title: "fx history", visits: 2, last: Date.now() - 3600000 }],
                  logins: [{ hostname: "https://login.fx.test", username: check.fx.user, password: check.fx.pass }] });
              Zen.useHome(Store.dataDir.replace(/\/browser$/, "") + "/fox-home");
              Zen.scan();
          },
          expect: () => check.keyringBus !== "" && Passwords.state === "ready" && Zen.browsers.length === 2 },
        { name: "found Zen, then Firefox, each with the profile its install uses and its counts; Zen chosen, as before", wait: 1500,
          expect: () => {
              const b = Zen.browsers.map(x => x.browser + " " + x.name + " " + [x.counts.passwords, x.counts.bookmarks].join("/")).join(" | ");
              probe.report("     " + b);
              return b === "Zen Zen fox 0/1 | Firefox default-release 1/2" && Zen.browser === "Zen" } },
        { name: "Firefox chosen: its profile now, and Settings > Import names it", wait: 1000,
          act: () => { Zen.choose(1); app.openOwn("settings", "import") },
          expect: () => Zen.browser === "Firefox" && Zen.profile.path.indexOf("/.mozilla/firefox/") > 0
              && (check.ownRow("zen-profile") ?? {}).label === "Firefox profile" },
        { name: "Import: its bookmarks in Saved as From Firefox (folders kept), its login exact in the keyring, the rows saying Firefox", wait: 8000,
          act: () => check.clickOwn("own:zen:action"),
          expect: () => {
              const folders = [...new Set(app.savedModel.pages.filter(p => p.url.indexOf("fx.test/") > 0).map(p => p.folder))].sort().join(", ");
              const words = JSON.stringify(["zen-profile", "zen", "zen-bookmarks", "zen-history", "zen-passwords"].map(k => check.ownRow(k)).filter(r => !!r).map(r => [r.label, r.value]));
              probe.report("     " + words);
              probe.report("     " + folders);
              return Zen.state === "" && folders === "From Firefox: Toolbar, From Firefox: Toolbar / Kernel"
                  && probe.keyringHolds("https://login.fx.test", check.fx.user, check.fx.pass) && words.indexOf("Zen") < 0 } },
        { name: "(the made-up home put away: no browser of the family found, its import's record cleared, for the groups after)", wait: 800,
          act: () => { Zen.useHome(""); for (const k of ["zenImport", "zenFailure", "broughtOver", "welcomed"]) app.prefs.set(k, null) },
          expect: () => Zen.browsers.length === 0 && !Zen.profile.path && !app.prefs.get("zenImport") },
    ]
    readonly property var zenSteps: [
        { group: "zen" },
        check.server,
        { setup: true, name: "(the main window focused, on a plain page)", wait: 1500, act: () => { probe.back(app); app.go(check.local("/plain"), "navigate") },
          expect: () => app.active && view.title === "plain" },
        { name: "(a Secret Service of the check's own, unlocked; the logins made up for this run, never printed)", wait: 1500,
          act: () => {
              for (const k of ["zenUserOne", "zenUserTwo", "zenPassOne", "zenPassTwo", "zenPassKept", "zenUserThree", "zenPassThree", "zenPrimary", "zenWrong"])
                  check[k] = check.letters(k.indexOf("User") > 0 ? 9 : 13);
              check.pwKeyring = check.pwKeyring || check.letters(14);
              check.keyringBus = probe.startKeyring(check.pwKeyring);
              probe.lockKeyring(false);
              if (Passwords.state !== "ready")
                  Passwords.useBus(check.keyringBus);
          },
          expect: () => check.keyringBus !== "" && Passwords.state === "ready" },
        { name: "no Zen folder looked in yet (check mode never reads the user's): no profile, and the first-run card offers no import",
          expect: () => !Zen.profile.path && !rail.omni.offerImport },
        { name: "(a Zen folder: a Default=1 profile, another install's, and the one of the install its desktop entry starts, with bookmarks, history and logins)",
          wait: 500, act: () => {
              const now = Date.now(), h = 3600000;
              check.zenMade = probe.zenProfile("zen", { name: "Zen check", primary: "",
                  bookmarks: [{ folder: "toolbar", url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki" },
                              { folder: "toolbar", separator: true },
                              { folder: "toolbar/Kernel", url: "https://lore.kernel.org/linux-media/", title: "linux-media" },
                              { folder: "toolbar/Kernel", url: "javascript:alert(1)", title: "bookmarklet" },
                              { folder: "toolbar", url: "https://zen.test/wal-only", title: "only in the log", wal: true },
                              { folder: "menu", url: "https://lwn.net/", title: "LWN.net" },
                              { folder: "menu", url: "place:sort=8&maxResults=10", title: "Most visited" },
                              { folder: "unfiled", url: "https://zen.test/other", title: "other bookmark" },
                              { folder: "unfiled", url: "https://wiki.archlinux.org/title/Libcamera", title: "again" },
                              { folder: "tags/linux", url: "https://lwn.net/", title: "" }],
                  history: [{ url: "https://zen.test/h1", title: "zen history one", visits: 3, last: now - h },
                            { url: "http://zen.test:8080/h2", title: "zen history two", visits: 1, last: now - 2 * h },
                            { url: "https://zen.test/hidden", title: "hidden", visits: 2, hidden: true, last: now - h },
                            { url: "https://zen.test/never", title: "never", visits: 0 },
                            { url: "file:///tmp/zen.pdf", title: "a file", visits: 2, last: now - h },
                            { url: "https://zen.test/h-wal", title: "zen history in the log", visits: 5, last: now - h / 2, wal: true }],
                  logins: [{ hostname: "https://login.zen.test", username: check.zenUserOne, password: check.zenPassOne },
                           { hostname: "http://zen.test:8080", username: check.zenUserTwo, password: check.zenPassTwo, des3: true },
                           { hostname: "https://router.zen.test", username: "admin", password: check.zenPassOne, realm: "Router" },
                           { hostname: "https://broken.zen.test", username: check.zenUserOne, password: check.zenPassTwo, damaged: true }] });
              Zen.useRoot(check.zenMade.root ?? "");
          },
          expect: () => { const z = check.zenMade, p = z.profile ? probe.zenProbe(z.profile) : {};
              probe.report("     " + JSON.stringify({ locked: z.locked, probe: p, profile: Zen.profile.name }));
              return !!z.root && z.locked && p.logins === 3 && p.primary === false } },
        { name: "the NSS helper run by hand on it (`browser --zen-nss decrypt`) opens nothing: it takes only an import's own copy",
          expect: () => { const d = probe.zenDecrypt(check.zenMade.profile); probe.report("     " + JSON.stringify(d)); return d.state === "failed" && d.logins === 0 } },
        { name: "the profile Zen's install uses, not the one marked Default=1; the card offers the import",
          expect: () => Zen.profile.path === check.zenMade.profile && Zen.profile.name === "Zen check" && rail.omni.offerImport },
        { name: "(one of Zen's logins already in the keyring with a password of its own)", wait: 1500,
          act: () => Passwords.save("http://zen.test:8080", check.zenUserTwo, check.zenPassKept),
          expect: () => probe.keyringHolds("http://zen.test:8080", check.zenUserTwo, check.zenPassKept) && Passwords.entries.some(e => e.user === check.zenUserTwo) },
        // the card offers the row only on a first run (no thread, no history; tools/test's Omnibox checks), which a check
        // run is not: the card here holds that row
        { name: "(Ctrl+T, the card holding the first-run row)", key: Qt.Key_T, mods: ctrl, wait: 600,
          act: () => {
              check.zenStamp = probe.folderStamp(check.zenMade.root);
              check.later(() => { newPageBar.rows = [{ kind: "import", glyph: "download", title: "Import bookmarks and history from Zen" }]; newPageBar.current = -1 });
          },
          expect: () => newPageBar.opened && newPageBar.rows.length === 1 && newPageBar.current === -1 },
        { name: "Down puts the row current", key: Qt.Key_Down, wait: 300, expect: () => newPageBar.current === 0 },
        { name: "Enter: Welcome, on the browser found (Zen, its icon and counts) and a password manager's file", key: Qt.Key_Return, wait: 600,
          expect: () => !newPageBar.opened && app.welcome.visible && app.welcome.phase === "arrive" && app.welcome.mode === ""
              && app.welcome.sources.map(x => x.name).join("|") === "Zen|A password manager's file" && app.welcome.source.name === "Zen" },
        { name: "Esc closes it, the keys back where they were", key: Qt.Key_Escape, wait: 600, expect: () => !app.welcome.visible },
        { name: "(Settings > Import's Import runs the import there)", wait: 600,
          act: () => { check.savedBefore = app.savedModel.pages.length; check.historyBefore = Object.keys(history.entries).length; check.zenStates = [];
              app.openOwn("settings", "import"); check.later(() => check.clickOwn("own:zen:action")) },
          expect: () => { probe.report("     section " + check.own().section);
              return app.ownKind === "settings" && (Zen.state !== "" || check.zenStates.length > 0) && !!check.ownRow("zen") && check.own().section === "import" } },
        { name: "done, through reading and saving, \"Importing…\" meanwhile: its bookmarks in Saved by folder, the log's too; the separator, bookmarklet, query and tag left out, one saved twice in Zen once",
          wait: 4000, expect: () => {
              const zen = app.savedModel.pages.filter(p => p.folder.startsWith("From Zen:"));
              probe.report("     states " + check.zenStates.join(" > ") + "; " + zen.map(p => p.name + " | " + p.folder).join("; "));
              return Zen.state === "" && check.zenStates.join() === "reading:Importing…,saving:Importing…,:" + check.ownRow("zen").value && JSON.stringify(zen.map(p => p.url + "|" + p.folder)) === JSON.stringify([
                  "https://wiki.archlinux.org/title/Libcamera|From Zen: Toolbar", "https://zen.test/wal-only|From Zen: Toolbar",
                  "https://lore.kernel.org/linux-media/|From Zen: Toolbar / Kernel", "https://lwn.net/|From Zen: Menu", "https://zen.test/other|From Zen: Other"])
                  && !app.savedModel.isSaved("https://decoy.test/") && app.savedModel.pages.length === check.savedBefore + 5 } },
        { name: "its history: the visited web pages with their titles, visits and times, the log's too; hidden, unvisited and file: rows left out",
          expect: () => { const e = history.entries, h1 = e["https://zen.test/h1"];
              return !!h1 && h1.title === "zen history one" && h1.visits === 3 && Math.abs(h1.last - (Date.now() - 3600000)) < 60000
                  && !!e["http://zen.test:8080/h2"] && !!e["https://zen.test/h-wal"] && e["https://zen.test/h-wal"].visits === 5
                  && !e["https://zen.test/hidden"] && !e["https://zen.test/never"] && !e["file:///tmp/zen.pdf"]
                  && Object.keys(e).length === check.historyBefore + 3 } },
        { name: "its sign-in logins in the keyring, 3DES and AES; the HTTP sign-in and the one NSS cannot open left out; the login the keyring had kept with its own password",
          expect: () => probe.keyringHolds("https://login.zen.test", check.zenUserOne, check.zenPassOne)
              && probe.keyringHolds("http://zen.test:8080", check.zenUserTwo, check.zenPassKept) && !probe.keyringHolds("http://zen.test:8080", check.zenUserTwo, check.zenPassTwo)
              && !probe.keyringHolds("https://router.zen.test", "admin", "") && Passwords.entries.filter(e => /zen\.test/.test(e.origin)).length === 2 },
        { name: "Settings > Import says so: when, 5 into Saved (1 already there), 3 into History, 1 into the keyring (1 already there), 1 NSS did not open",
          expect: () => { const v = k => (check.ownRow(k) ?? {}).value;
              probe.report("     " + ["zen-profile", "zen", "zen-bookmarks", "zen-history", "zen-passwords"].map(v).join(" | "));
              return v("zen-profile") === "Zen check" && /^today \d\d:\d\d$/.test(v("zen")) && check.ownRow("zen").action === "Import"
                  && v("zen-bookmarks") === "5 into Saved, 1 already there" && v("zen-history") === "3 into History"
                  && v("zen-passwords") === "1 saved, 1 already there \u00b7 1 skipped: Zen's saved passwords would not open"
                  && !check.ownRow("zen-failure") && check.ownShown("own:zen:action") } },
        { name: "and it is kept in settings.json; the card offers the import no more", wait: 800,
          expect: () => { const z = (Store.load("settings") ?? {}).zenImport;
              return !!z && z.bookmarks.added === 5 && z.passwords.added === 1 && z.passwords.unopened === 1 && !rail.omni.offerImport } },
        { name: "the copy of the profile gone from the temp dir; Zen's folder not written: every file as it was",
          expect: () => !probe.entries(probe.tempDir()).some(n => n.startsWith("browser-zen-")) && probe.folderStamp(check.zenMade.root) === check.zenStamp },
        { name: "Import again (a click): nothing twice, in Saved, History or the keyring", wait: 4000,
          act: () => { check.savedBefore = app.savedModel.pages.length; check.historyBefore = Object.keys(history.entries).length; check.clickOwn("own:zen:action") },
          expect: () => { const v = k => (check.ownRow(k) ?? {}).value;
              probe.report("     " + ["zen-bookmarks", "zen-history", "zen-passwords"].map(v).join(" | "));
              return Zen.state === "" && app.savedModel.pages.length === check.savedBefore && Object.keys(history.entries).length === check.historyBefore
                  && Passwords.entries.filter(e => /zen\.test/.test(e.origin)).length === 2 && v("zen-bookmarks") === "none new, 6 already there"
                  && v("zen-history") === "none new, 3 already there"
                  && v("zen-passwords") === "none new, 2 already there \u00b7 1 skipped: Zen's saved passwords would not open" } },
        { name: "(another Zen folder, its logins under a primary password)", wait: 500,
          act: () => {
              check.zenLocked = probe.zenProfile("zen-primary", { name: "Zen locked", primary: check.zenPrimary,
                  bookmarks: [{ folder: "toolbar", url: "https://zen.test/primary-bookmark", title: "primary bookmark" }],
                  history: [{ url: "https://zen.test/primary-history", title: "primary history", visits: 1, last: Date.now() - 60000 }],
                  logins: [{ hostname: "https://primary.zen.test", username: check.zenUserThree, password: check.zenPassThree }] });
              Zen.useRoot(check.zenLocked.root ?? "");
          },
          expect: () => { const p = check.zenLocked.profile ? probe.zenProbe(check.zenLocked.profile) : {};
              return Zen.profile.name === "Zen locked" && p.logins === 1 && p.primary === true } },
        { name: "Import: the bookmarks and history in at once; the passwords wait for Zen's primary password, the keys in its field", wait: 4000,
          act: () => check.clickOwn("own:zen:action"),
          expect: () => { const v = k => (check.ownRow(k) ?? {}).value, t = check.own().target("own:zen-primary:input");
              probe.report("     " + ["zen", "zen-bookmarks", "zen-history", "zen-passwords"].map(v).join(" | "));
              return Zen.state === "password" && app.savedModel.isSaved("https://zen.test/primary-bookmark") && !!history.entries["https://zen.test/primary-history"]
                  && v("zen") === "Importing…" && v("zen-bookmarks") === "1 into Saved" && v("zen-passwords") === "1 locked by Zen's primary password"
                  && !!t && t.activeFocus && check.ownShown("own:zen-primary:input") && !probe.keyringHolds("https://primary.zen.test", check.zenUserThree, "") } },
        { name: "Skip: the rest imported, the passwords said to be skipped, none saved, the copy gone", wait: 1000, act: () => check.clickOwn("own:zen-primary:skip"),
          expect: () => { const v = k => (check.ownRow(k) ?? {}).value;
              return Zen.state === "" && v("zen-passwords") === "Skipped: no primary password given" && v("zen-bookmarks") === "1 into Saved"
                  && !probe.keyringHolds("https://primary.zen.test", check.zenUserThree, "") && !probe.entries(probe.tempDir()).some(n => n.startsWith("browser-zen-")) } },
        { name: "(Import again: the passwords wait again, the rest already there)", wait: 4000, act: () => check.clickOwn("own:zen:action"),
          expect: () => { const t = check.own().target("own:zen-primary:input");
              return Zen.state === "password" && check.ownRow("zen-bookmarks").value === "none new, 1 already there" && !!t && t.activeFocus } },
        { name: "a wrong one typed, Enter: \"That is not Zen's primary password.\", the field empty and with the keys again, nothing saved", wait: 3000,
          act: () => { check.type(check.zenWrong); probe.press(Qt.Key_Return, 0) },
          expect: () => { const t = check.own().target("own:zen-primary:input");
              return Zen.state === "password" && Zen.wrong && !!check.ownRow("zen-wrong") && check.ownRow("zen-wrong").label === "That is not Zen's primary password."
                  && !!t && t.activeFocus && t.text === "" && check.own().zenPrimary === "" && !probe.keyringHolds("https://primary.zen.test", check.zenUserThree, "") } },
        { name: "the right one typed, Enter: its login in the keyring; 1 into the keyring", wait: 3000,
          act: () => { check.type(check.zenPrimary); probe.press(Qt.Key_Return, 0) },
          expect: () => Zen.state === "" && probe.keyringHolds("https://primary.zen.test", check.zenUserThree, check.zenPassThree)
              && check.ownRow("zen-passwords").value === "1 saved" && !check.ownRow("zen-primary") && check.own().zenPrimary === "" },
        { name: "no keyring answering: the passwords skipped, saying so", wait: 4000,
          act: () => { Passwords.useBus("unix:path=" + Store.dataDir.replace(/\/browser$/, "") + "/no-bus"); Zen.useRoot(check.zenMade.root); check.later(() => check.clickOwn("own:zen:action")) },
          expect: () => Passwords.state === "none" && Zen.state === "" && check.ownRow("zen-passwords").value === "Skipped: no password store is running" },
        { name: "(the check's Secret Service again)", wait: 1500, act: () => Passwords.useBus(check.keyringBus), expect: () => Passwords.state === "ready" },
        { name: "no file of the data dir (the keyring's own included) holds a password, user name or primary password of Zen's",
          expect: () => { const made = check.zenMade_().map(t => probe.filesHolding(t));
              probe.report("     " + made[0].files + " files, " + Math.round(made[0].bytes / 1024) + " kB read; holding one: "
                           + (made.map(r => r.holding.join(", ")).filter(x => x).join("; ") || "none"));
              return made[0].files > 0 && made.every(r => r.holding.length === 0) } },
        { name: "and none reached this run's output (the group's heading found there)",
          expect: () => probe.outputHolding("== zen at ") && check.zenMade_().every(t => !probe.outputHolding(t)) },
        // the group after this one starts on a web page, as it would without it
        { name: "(Settings closed)", wait: 800, act: () => { for (const id of check.ownPages("browser://settings")) app.closePage(id) },
          expect: () => check.ownPages("browser://settings").length === 0 && app.ownKind === "" && !!view },
        { name: "(a plain page on screen)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" && !view.loading },
    ]
    // Import from Zen's cookies and tabs (PLAN.md 3.4, `zensession`) from a Zen folder made up in the throwaway data dir:
    // Settings > Import counting the sites and tabs in plain words behind two choices; the cookies set into the profile's
    // store (host-only and domain, Secure, HttpOnly, SameSite, expiry in seconds or milliseconds; expired, partitioned and
    // container cookies left out and counted; a session cookie kept); a page of the store's own reading a brought cookie;
    // the tabs from the session file opened in a thread of their own, essential and pinned first, unloaded, the page on
    // screen unchanged; nothing twice on a second import; both choices off bringing neither; Zen's folder not written, no
    // copy left in the temp dir. `zenreal` (BROWSER_ZEN_COPY: a copy of a real Zen folder) does the same with real data,
    // printing counts only.
    readonly property var zenSessionSteps: [
        { group: "zensession" },
        check.server,
        { setup: true, name: "(the main window focused, on a plain page)", wait: 1500, act: () => { probe.back(app); app.go(check.local("/plain"), "navigate") },
          expect: () => app.active && view.title === "plain" },
        { name: "(a Zen folder with cookies of every kind and a session of tabs)", wait: 500, act: () => {
              const now = Date.now(), day = 86400000, future = now + 30 * day;
              check.cookieFuture = future;
              check.zenMade = probe.zenProfile("zen-session", { name: "Zen session", bookmarks: [], history: [] });
              const tab = (url, title, more) => Object.assign({ entries: [{ url: "https://before.test/", title: "before" }, { url: url, title: title }], index: 2 }, more ?? {});
              check.zenCookiesMade = probe.zenSession(check.zenMade.profile, {
                  cookies: [
                      { name: "sid", value: "v-sid", host: "app.signin.test", path: "/", expiry: future, secure: true, httpOnly: true, sameSite: 2 },
                      { name: "dom", value: "v-dom", host: ".signin.test", path: "/", expiry: Math.floor(future / 1000), secure: true, sameSite: 1 },
                      { name: "old", value: "v-old", host: "app.signin.test", path: "/", expiry: now - day, sameSite: 1 },
                      { name: "part", value: "v-part", host: ".embed.test", path: "/", expiry: future, attributes: "^partitionKey=%28https%2Csite.test%29" },
                      { name: "box", value: "v-box", host: "box.test", path: "/", expiry: future, attributes: "^userContextId=2" },
                      { name: "sess", value: "v-sess", host: "sess.test", path: "/", expiry: 0 },
                      { name: "unset", value: "v-unset", host: "unset.test", path: "/", expiry: future, sameSite: 256 },
                      { name: "none", value: "v-none", host: "none.test", path: "/", expiry: future, sameSite: 0 },
                      { name: "zenprobe", value: "zv", host: "127.0.0.1", path: "/", expiry: future, sameSite: 256 },
                      { name: "deep", value: "v-deep", host: "app.signin.test", path: "/app", expiry: future },
                  ],
                  session: { windows: [{ spaces: [{ uuid: "{1}", name: "Work" }], tabs: [
                      tab("https://one.test/", "One"),
                      tab("https://two.test/a", "Two"),
                      { entries: [{ url: "about:blank", title: "blank" }], index: 1 },
                      tab("https://pin.test/", "Pinned", { pinned: true }),
                      tab("https://ess.test/", "Essential", { pinned: true, zenEssential: true }),
                      { entries: [{ url: "moz-extension://x/y.html", title: "extension" }], index: 1 },
                      tab("https://one.test/", "One again"),
                  ] }] } });
              check.zenStamp = probe.folderStamp(check.zenMade.root);
              check.cookiesBefore = SiteData.allCookies();
              check.pagesBefore = Object.keys(session.pages).length;
              Zen.useRoot(check.zenMade.root ?? "");
          }, expect: () => !!check.zenMade.root && check.zenCookiesMade && Zen.profile.path === check.zenMade.profile },
        { name: "Settings opens at Import and counts what Zen has: the two choices, on, in plain words", wait: 2500, act: () => app.openOwn("settings", "import"),
          expect: () => { const c = check.ownRow("zenCookies"), t = check.ownRow("zenTabs");
              probe.report("     " + (c ? c.label + " " + c.value : "-") + " | " + (t ? t.label + " " + t.value : "-"));
              return !!c && !!t && c.label === "Stay signed in to 5 sites" && c.value === "On" && t.label === "Open your 5 tabs" && t.value === "On" && Zen.sites === 5 && Zen.tabs === 5 } },
        { name: "Import: through the cookies, to done", wait: 3000, act: () => check.clickOwn("own:zen:action"),
          expect: () => { const z = (Store.load("settings") ?? {}).zenImport, v = k => (check.ownRow(k) ?? {}).value;
              probe.report("     " + JSON.stringify(z && z.cookies) + " " + JSON.stringify(z && z.tabs) + " | " + [v("zen-cookies"), v("zen-tabs")].join(" | "));
              return Zen.state === "" && !!z && !!z.cookies && z.cookies.added === 7 && z.cookies.kept === 0 && z.cookies.rejected === 0 && z.cookies.skipped === 2
                  && z.cookies.expired === 1 && z.cookies.sites === 5 && z.cookies.google === false && z.tabs.added === 5 && z.tabs.kept === 0 } },
        { name: "the store holds them: 7 more, the host's own (host-only: not sent to a host under it) and the domain's one, the expired, partitioned and container ones not",
          expect: () => SiteData.allCookies() === check.cookiesBefore + 7 && SiteData.cookies("app.signin.test") === 3 && SiteData.cookies("signin.test") === 1
              && SiteData.cookies("x.app.signin.test") === 1
              && SiteData.cookies("sess.test") === 1 && SiteData.cookies("none.test") === 1 && SiteData.cookies("embed.test") === 0 && SiteData.cookies("box.test") === 0 },
        { name: "each as Zen had it: Secure, HttpOnly, and the expiry (Zen's seconds or milliseconds), a session cookie still one (Qt does not report SameSite back)",
          expect: () => { const a = (n, d, p) => SiteData.attributes(n, d, p), near = (v, t) => Math.abs(v - t) < 2000,
                  sid = a("sid", "app.signin.test", "/"), dom = a("dom", ".signin.test", "/"), sess = a("sess", "sess.test", "/"), none = a("none", "none.test", "/");
              probe.report("     " + JSON.stringify({ sid: [sid.secure, sid.httpOnly, sid.expires - check.cookieFuture], dom: [dom.secure, dom.httpOnly, dom.expires - check.cookieFuture],
                                                      sess: sess.expires, none: [none.secure, none.httpOnly] }));
              return sid.secure === true && sid.httpOnly === true && near(sid.expires, check.cookieFuture)
                  && dom.secure === true && dom.httpOnly === false && near(dom.expires, check.cookieFuture)
                  && sess.expires === 0 && none.secure === false && none.expires > 0 } },
        { name: "(a page of the store's own)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" && !view.loading },
        { name: "(it reads its cookies)", wait: 800, act: () => { check.cookieSeen = ""; view.runJavaScript("document.cookie", r => check.cookieSeen = String(r)) },
          expect: () => check.cookieSeen.split("; ").includes("zenprobe=zv") },
        { name: "Settings > Import says so, in plain words, and that a few sites may ask to sign in again", wait: 800, act: () => app.openOwn("settings", "import"),
          expect: () => { const v = k => (check.ownRow(k) ?? {}).value, n = check.ownRow("zen-signin");
              probe.report("     " + [v("zen-cookies"), v("zen-tabs")].join(" | "));
              return v("zen-cookies") === "7 brought over · 2 left out: Zen keeps them apart, per site or per container" && v("zen-tabs") === "5 opened"
                  && !!n && /sign in again/.test(n.label) } },
        { name: "the tabs: one thread, From Zen, essential and pinned first, with their titles, none loaded, the page on screen the one it was",
          expect: () => { const t = session.threads.find(t => t.title === "From Zen"), pages = t ? t.pages.map(id => session.pages[id]) : [];
              probe.report("     " + pages.map(p => p.url.replace(/^https:\/\/|\/.*$/g, "") + ":" + p.title + ":" + p.state).join(", "));
              return !!t && pages.map(p => p.url).join() === "https://ess.test/,https://pin.test/,https://one.test/,https://two.test/a,https://one.test/"
                  && pages.map(p => p.title).join() === "Essential,Pinned,One,Two,One again" && pages.every(p => p.state === "unloaded")
                  && !t.pages.includes(session.currentPage) && session.currentPage !== "" } },
        { name: "Zen's folder not written; no copy of it left in the temp dir",
          expect: () => probe.folderStamp(check.zenMade.root) === check.zenStamp && !probe.entries(probe.tempDir()).some(n => n.startsWith("browser-zen-")) },
        { name: "Import again: the cookies already there, no tab twice", wait: 3000, act: () => { check.cookiesBefore = SiteData.allCookies(); check.pagesBefore = Object.keys(session.pages).length; check.clickOwn("own:zen:action") },
          expect: () => { const v = k => (check.ownRow(k) ?? {}).value;
              probe.report("     " + [v("zen-cookies"), v("zen-tabs")].join(" | "));
              return Zen.state === "" && v("zen-cookies") === "none new, 7 already there · 2 left out: Zen keeps them apart, per site or per container" && v("zen-tabs") === "none new, 5 already open"
                  && SiteData.allCookies() === check.cookiesBefore && Object.keys(session.pages).length === check.pagesBefore } },
        { name: "(Stay signed in switched off by a click)", wait: 1200, act: () => check.clickOwn("own:zenCookies"),
          expect: () => app.prefs.get("zenCookies") === false && check.ownRow("zenCookies").value === "Off" },
        { name: "(Open your tabs switched off by a click)", wait: 1200, act: () => check.clickOwn("own:zenTabs"),
          expect: () => app.prefs.get("zenTabs") === false && check.ownRow("zenTabs").value === "Off" },
        { name: "Import with them off: no cookie and no tab brought, the rows not shown", wait: 3000, act: () => { check.cookiesBefore = SiteData.allCookies(); check.pagesBefore = Object.keys(session.pages).length; check.clickOwn("own:zen:action") },
          expect: () => Zen.state === "" && !check.ownRow("zen-cookies") && !check.ownRow("zen-tabs") && !check.ownRow("zen-signin") && SiteData.allCookies() === check.cookiesBefore
              && Object.keys(session.pages).length === check.pagesBefore },
        { name: "(the choices on again)", wait: 800, act: () => { app.prefs.set("zenCookies", true); app.prefs.set("zenTabs", true) }, expect: () => app.prefs.get("zenCookies") === true },
        { name: "(Settings closed)", wait: 800, act: () => { for (const id of check.ownPages("browser://settings")) app.closePage(id) },
          expect: () => check.ownPages("browser://settings").length === 0 && app.ownKind === "" && !!view },
        { name: "(a plain page on screen)", wait: 1500, act: () => app.go(check.local("/plain"), "navigate"), expect: () => view.title === "plain" && !view.loading },
    ]
    // With BROWSER_ZEN_COPY set to a copy of a Zen folder (profiles.ini and the profile with cookies.sqlite, its log, and the
    // session files): the same import on real data; counts only, never a value, name or address
    readonly property var zenRealSteps: [
        { group: "zenreal" },
        { name: "(a copy of a real Zen folder: BROWSER_ZEN_COPY)", wait: 500, act: () => {
              check.realRoot = probe.env("BROWSER_ZEN_COPY");
              if (check.realRoot === "")
                  return;
              Zen.useRoot(check.realRoot);
              check.realStamp = probe.folderStamp(check.realRoot);
              check.cookiesBefore = SiteData.allCookies();
          }, expect: () => { probe.report("     " + (check.realRoot === "" ? "no copy given, nothing run" : "profile found: " + !!Zen.profile.path)); return check.realRoot === "" || !!Zen.profile.path } },
        { name: "Settings > Import counts the sites and tabs", wait: 4000, act: () => { if (check.realRoot !== "") app.openOwn("settings", "import") },
          expect: () => { if (check.realRoot === "") return true;
              const c = check.ownRow("zenCookies"), t = check.ownRow("zenTabs");
              probe.report("     " + (c ? c.label : "-") + " | " + (t ? t.label : "-"));
              return !!c && !!t && Zen.sites > 0 && Zen.tabs > 0 } },
        { name: "Import: the cookies into the store, the tabs as pages", wait: 15000, act: () => { if (check.realRoot !== "") check.clickOwn("own:zen:action") },
          expect: () => { if (check.realRoot === "") return true;
              const z = (Store.load("settings") ?? {}).zenImport;
              probe.report("     cookies " + JSON.stringify(z && z.cookies) + " tabs " + JSON.stringify(z && z.tabs));
              return Zen.state === "" && !!z && !!z.cookies && z.cookies.added > 0 && !!z.tabs && z.tabs.added > 0 } },
        { name: "the store holds the imported cookies: every host's count as Zen's file gives it (a request to that host would send), and 5 more than before in all but those the engine refused",
          expect: () => { if (check.realRoot === "") return true;
              const z = (Store.load("settings") ?? {}).zenImport.cookies, expect = probe.zenCookieCounts(Zen.profile.path), hosts = Object.keys(expect);
              const off = hosts.filter(h => SiteData.cookies(h) !== expect[h]);
              probe.report("     " + hosts.length + " hosts, " + (hosts.length - off.length) + " with the count Zen's file gives, " + off.length + " not: "
                           + off.slice(0, 8).map(h => h.replace(/[^.]+/g, "*") + " " + expect[h] + "/" + SiteData.cookies(h)).join(", ")
                           + "; store " + check.cookiesBefore + " -> " + SiteData.allCookies());
              return SiteData.allCookies() === check.cookiesBefore + z.added && (z.rejected > 0 || off.length === 0) } },
        { name: "the tabs are in one thread, From Zen, unloaded, and the page on screen is still the one it was",
          expect: () => { if (check.realRoot === "") return true;
              const z = (Store.load("settings") ?? {}).zenImport.tabs, t = session.threads.find(t => t.title.startsWith("From Zen"));
              probe.report("     " + (t ? t.pages.length : 0) + " pages in the thread, " + (t ? t.pages.filter(id => session.pages[id].state === "unloaded").length : 0) + " of them unloaded");
              return !!t && t.pages.length === z.added && t.pages.every(id => session.pages[id].state === "unloaded") && !t.pages.includes(session.currentPage) } },
        { name: "Zen's folder (the copy) not written; no copy left in the temp dir",
          expect: () => check.realRoot === "" || (probe.folderStamp(check.realRoot) === check.realStamp && !probe.entries(probe.tempDir()).some(n => n.startsWith("browser-zen-"))) },
        { name: "(Settings closed)", wait: 800, act: () => { for (const id of check.ownPages("browser://settings")) app.closePage(id) },
          expect: () => check.ownPages("browser://settings").length === 0 && !!view },
    ]
    property var zenCookiesMade: false
    property string realRoot: ""
    property string realStamp: ""
    property int pagesBefore: 0
    property string cookieSeen: ""
    property real cookieFuture: 0
    property var zenMade: ({})
    property var zenLocked: ({})
    property string zenStamp: ""
    property string zenUserOne: ""
    property string zenUserTwo: ""
    property string zenUserThree: ""
    property string zenPassOne: ""
    property string zenPassTwo: ""
    property string zenPassThree: ""
    property string zenPassKept: ""
    property string zenPrimary: ""
    property string zenWrong: ""
    // Zen's states as the import goes, each with what the Imported row said then
    property var zenStates: []
    property Connections zenState: Connections {
        target: Zen
        function onStateChanged() { Qt.callLater(() => check.zenStates.push(Zen.state + ":" + ((check.ownRow("zen") ?? {}).value ?? ""))) }
    }
    property int savedBefore: 0
    property int historyBefore: 0
    // what this run made up for Zen's logins; never printed
    function zenMade_() { return [zenUserOne, zenUserTwo, zenUserThree, zenPassOne, zenPassTwo, zenPassThree, zenPassKept, zenPrimary, zenWrong] }

    // The rail's structure (PLAN.md 3.21), keys and clicks through the window system: tasks in thread order, the open one
    // as its row over its pages one step in, the other folded in its place as one row, a page of its own as its row; the
    // words; the foot; Ctrl+Tab and Ctrl+Shift+Tab in drawn order, the task left keeping its fold; F6, Left folding the
    // task where it is with the cursor on its row, Enter opening it again at its last-seen page; a click on a folded row;
    // the task left while the pointer is on the rail staying open until it leaves; a click on an open task's row folding
    // it; the Pinned faces under New page, a click on one.
    // Favicons of pages the lifecycle unloaded (2026-10-01: the browser crashed in WebContentsAdapter::icon() after it was
    // left alone a while). Qt's favicon provider answers an image://favicon address from the view that has it, unloaded
    // or not, and drawing it for an unloaded page crashed (reproduced here with an Image given the address). Every
    // favicon is drawn from the copy Engine.keepIcon saves while the view is live.
    property string iconPage: ""
    property string iconAddress: ""
    property string iconFile: ""
    property Item iconProbe: null
    // Touchpad momentum (Glide, src/glide.*): a quick two-finger scroll goes on after the fingers lift, slowing to a stop;
    // fingers that rest before they lift stop the page where it is
    property real glideAt: 0
    readonly property var glideSteps: [
        { group: "glide" },
        check.server,
        { name: "(a tall page on screen)", wait: 2500, act: () => { probe.back(app); app.go(check.local("/tall"), "new", "", "glide") },
          expect: () => view.title === "tall" && !view.loading },
        { name: "(a quick swipe down the page)", wait: 120,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.pointer(c.x, c.y); probe.swipe(c.x, c.y, -240, 8, 8) },
          expect: () => true, page: "scrollY", pageExpect: v => { check.glideAt = v; probe.report("     at the lift " + v); return v > 0 } },
        { name: "it goes on after the lift, slowing to a stop", wait: 3200,
          expect: () => true, page: "scrollY", pageExpect: v => { probe.report("     after " + v); return v > check.glideAt + 100 } },
        { name: "(back to the top)", wait: 600, act: () => view.runJavaScript("scrollTo(0, 0)"), expect: () => true, page: "scrollY", pageExpect: v => v === 0 },
        { name: "fingers that rest before they lift: the page stays where they left it", wait: 1200,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.swipe(c.x, c.y, -240, 2, 200) },
          expect: () => true, page: "scrollY", pageExpect: v => { check.glideAt = v; probe.report("     " + v); return v > 0 } },
        { name: "(still there)", wait: 800, expect: () => true, page: "scrollY", pageExpect: v => v === check.glideAt },
        // A gesture's End reaches the engine (2026-10-11: CEF dropped it, having no movement; Chromium kept the first
        // gesture going and scrolled what it had latched first, so a pane WhatsApp swapped in for a chat never scrolled)
        { name: "(a scrolling pane over the page, as a chat's)", wait: 500,
          act: () => view.runJavaScript("document.body.insertAdjacentHTML('beforeend', '<div id=pane style=\\'position:fixed;inset:0;overflow:auto;background:#fff\\'><div style=\\'height:6000px\\'></div></div>')"),
          expect: () => true, page: "document.getElementById('pane').scrollHeight", pageExpect: v => v > 5000 },
        { name: "(a slow swipe over it scrolls it)", wait: 1000,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.pointer(c.x, c.y); probe.swipe(c.x, c.y, -240, 2, 200) },
          expect: () => true, page: "document.getElementById('pane').scrollTop", pageExpect: v => { probe.report("     pane " + v); return v > 0 } },
        { name: "the pane swapped for a new one, as a chat switch: the next swipe scrolls the new pane", wait: 1400,
          act: () => { view.runJavaScript("document.getElementById('pane').remove(); document.body.insertAdjacentHTML('beforeend', '<div id=pane2 style=\\'position:fixed;inset:0;overflow:auto;background:#fff\\'><div style=\\'height:6000px\\'></div></div>')");
              check.later(() => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.swipe(c.x, c.y, -240, 2, 200) }) },
          expect: () => true, page: "document.getElementById('pane2').scrollTop", pageExpect: v => { probe.report("     new pane " + v); return v > 0 } },
    ]
    // Back and forward by a sideways touchpad swipe (Swipe.js, BrowserView, Main's swipe cue): far enough goes, a short one
    // stays, and one over something that scrolls sideways scrolls it instead. A swipe right (pixels +x) goes back.
    readonly property var swipeSteps: [
        { group: "swipe" },
        check.server,
        { name: "(brook one on screen)", wait: 2500, act: () => { probe.back(app); app.go(check.local("/brook"), "new", "", "swipe") },
          expect: () => view.title === "brook one" && !view.loading },
        { name: "(then brook two in the same page)", wait: 2500, act: () => view.url = check.local("/brook-two"),
          expect: () => view.title === "brook two" && !view.loading && view.canGoBack },
        { name: "a swipe right goes back", wait: 2500,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.pointer(c.x, c.y); probe.swipe(c.x, c.y, 0, 12, 16, 240) },
          expect: () => view.title === "brook one" && !view.loading },
        { name: "a swipe left goes forward", wait: 2500,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.swipe(c.x, c.y, 0, 12, 16, -240) },
          expect: () => view.title === "brook two" && !view.loading },
        { name: "a short swipe stays", wait: 1500,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.swipe(c.x, c.y, 0, 2, 200, 60) },
          expect: () => view.title === "brook two" && view.swipeX === 0 },
        { name: "(a sideways strip over the page, scrolled to its middle)", wait: 500,
          act: () => view.runJavaScript("document.body.insertAdjacentHTML('beforeend', '<div id=strip style=\\'position:fixed;inset:0;overflow-x:auto\\'><div style=\\'width:6000px;height:100%\\'></div></div>'); strip.scrollLeft = 3000"),
          expect: () => true, page: "document.getElementById('strip').scrollLeft", pageExpect: v => v === 3000 },
        { name: "a swipe right over it scrolls the strip and stays", wait: 2000,
          act: () => { const c = view.mapToItem(app.contentItem, view.width / 2, view.height / 2); probe.swipe(c.x, c.y, 0, 12, 16, 240) },
          expect: () => view.title === "brook two", page: "document.getElementById('strip').scrollLeft", pageExpect: v => { probe.report("     strip " + v); return v < 3000 } },
    ]
    // Ctrl+L in the notch (PLAN.md 3.19, src/notch.*, NotchAddress): the check plays the shell. The command the browser
    // runs is a stand-in (no `qs` is ever run), and the island is the probe's own client on the notch socket.
    readonly property var notchSteps: [
        { group: "notch" },
        check.server,
        { name: "(the notch's sheet switched on for these checks; the card is the default)", act: () => { app.notchSearch = true }, expect: () => app.notchSearch },
        { name: "(a task of two pages, login on screen, find other in its history; the notch socket listening, its shell a stand-in that exits 0)",
          wait: 3000,
          act: () => { probe.back(app); app.notch.command = ["true"]; app.notch.listen(); app.windowNotch.helloLimit = 5000;
              app.go(check.local("/find-other"), "new", "", "notch task");
              check.later(() => { app.go(check.local("/plain"), "navigate"); check.later(() => app.openHere(check.local("/login"), "login")) }) },
          expect: () => app.notch.listening && view.title === "login" && !view.loading && session.currentThread.pages.length === 2 },
        { name: "Ctrl+L asks the shell for the sheet with the socket, the window's monitor and edit; no card",
          focus: "window.keysSeen = 0; document.addEventListener('keydown', () => keysSeen++, true); document.activeElement.blur()",
          key: Qt.Key_L, mods: ctrl, wait: 300,
          expect: () => { probe.report("     " + app.notch.lastCall.join(" "));
              return app.notch.lastCall.join(" ") === ["true", app.notch.path, app.screen ? app.screen.name : "", "edit"].join(" ")
                  && app.windowNotch.state === "calling" && !address.editing } },
        { name: "keys typed before the island says hello wait in the browser (Backspace too), not on the page", wait: 300,
          act: () => { probe.press(Qt.Key_L, 0, "l"); probe.press(Qt.Key_I, 0, "i"); probe.press(Qt.Key_X, 0, "x"); probe.press(Qt.Key_Backspace, 0);
              probe.press(Qt.Key_B, 0, "b") },
          expect: () => app.windowNotch.typed === "lib" && !address.editing, page: "keysSeen", pageExpect: v => v === 0 },
        { name: "the island says hello: the answer has the address, title, host, task, page count and the keys typed", wait: 400,
          act: () => { check.islandUp = probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => { const h = check.heard("hello"); probe.report("     " + JSON.stringify(h));
              return check.islandUp && !!h && h.link === check.local("/login") && h.title === "login" && h.host === "127.0.0.1" && h.task === "notch task"
                  && h.pages === 2 && h.typed === "lib" && app.windowNotch.state === "open" && app.windowNotch.typed === "" } },
        { name: "and Where next (a page with no links: the task's other page and the one it left, \"in this task\"), mode edit, and what Ask Praxis hands over: the task's pages, the one on screen first",
          expect: () => { const h = check.heard("hello"), w = h ? h.where : [];
              probe.report("     " + w.map(x => x.kind + ":" + x.title + " (" + x.detail + ") " + x.word).join(" | "));
              return !!h && h.mode === "edit" && w.length === 3 && w[0].kind === "label" && w[0].title === "Where next"
                  && w.some(x => x.kind === "page" && x.title === "plain" && x.detail === "127.0.0.1" && /^in this task · \d+m$/.test(x.word) && x.enter === "switch")
                  && w.some(x => x.kind === "history" && /^in this task · \d+m$/.test(x.word))
                  && !!h.praxis && h.praxis.label === "notch task · 2 pages"
                  && h.praxis.text.indexOf("- login: " + check.local("/login") + " (on screen)\n- plain: " + check.local("/plain")) >= 0 } },
        { name: "an island that connects again while open says hello again and gets the state again (the keys already handed over)", wait: 400,
          act: () => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => { const h = check.heard("hello");
              return !!h && h.link === check.local("/login") && h.typed === "" && app.windowNotch.state === "open" && probe.islandConnected() } },
        { name: "a query is answered with the card's rows in its order (Search the web first, then Ask Praxis, Open, Been here) and its seq", wait: 400,
          act: () => probe.islandSay(JSON.stringify({ op: "query", text: "plain other", seq: 4 })),
          expect: () => { const r = check.heard("rows"), card = app.windowNotch.omni.suggest("plain other", session.currentPage, "address");
              const names = { "Open page": "Open", "History": "Been here" }, rows = r ? r.rows.filter((x, i) => i !== 1) : [], ask = r ? r.rows[1] : null;
              probe.report("     " + (r ? r.rows.map(x => x.kind + ":" + x.title + (x.detail ? " (" + x.detail + ")" : "") + (x.word ? " " + x.word : "")).join(" | ") : "none"));
              return !!r && r.seq === 4 && rows.length === card.length && rows.every((x, i) => x.kind === card[i].kind)
                  && !!ask && ask.kind === "praxis" && ask.title === "Ask Praxis" && ask.detail === "reads this task's pages first" && ask.word === "Tab"
                  && ask.glyph === "diamond" && ask.enter === "praxis" && r.rows.filter(x => x.kind === "praxis").length === 1
                  && rows[0].title === "Search the web" && rows[0].detail === app.windowNotch.omni.engine && rows[0].enter === "search"
                  && rows.every((x, i) => i === 0 || x.title === (card[i].kind === "label" ? names[card[i].title] ?? card[i].title : card[i].title))
                  && r.rows.some(x => x.kind === "page" && x.title === "plain" && x.word === "switch" && x.detail === "127.0.0.1")
                  && r.rows.some(x => x.kind === "label" && x.title === "Been here")
                  && r.rows.some(x => x.kind === "history" && x.title === "find other" && /^127\.0\.0\.1 · /.test(x.detail)) } },
        { name: "a ? question is Ask Praxis alone; a / or > prefix has no Ask Praxis row", wait: 600,
          act: () => { probe.islandSay(JSON.stringify({ op: "query", text: "? is the lane fix upstream", seq: 5 }));
              check.later(() => probe.islandSay(JSON.stringify({ op: "query", text: ">reload", seq: 6 }))) },
          expect: () => { const all = probe.islandHeard().filter(m => m.op === "rows"), ask = all.find(m => m.seq === 5), act = all.find(m => m.seq === 6);
              return !!ask && ask.rows.length === 1 && ask.rows[0].kind === "praxis" && !!act && act.rows.length > 0 && !act.rows.some(x => x.kind === "praxis") } },
        { name: "go to row 1 of an address typed: it loads in this page, the island is hung up and the window takes the focus back", wait: 2500,
          act: () => { Backdrop.fakeClients = JSON.stringify([{ pid: probe.pid(), class: "browser", title: "", address: "0xb", mapped: true, at: [6, 44],
                                                                workspace: { id: 1, name: "1" } }]);
              Backdrop.dispatched = [];
              probe.islandSay(JSON.stringify({ op: "query", text: check.local("/find"), seq: 7 }));
              check.later(() => probe.islandSay(JSON.stringify({ op: "go", index: 0, seq: 7, text: check.local("/find"), where: "here" }))) },
          expect: () => { probe.report("     " + Backdrop.dispatched.join(" | "));
              return String(view.url) === check.local("/find") && view.title === "find" && session.currentThread.pages.length === 2
                  && app.windowNotch.state === "" && !probe.islandConnected() && view.activeFocus
                  && Backdrop.dispatched.indexOf('dispatch hl.dsp.focus({ window = "address:0xb" })') >= 0 } },
        { name: "Alt+Enter (go, where new) with rows out of date: the text decides, a new page in this thread", wait: 2500,
          act: () => { probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "go", index: 3, seq: 99, text: check.local("/plain"), where: "new" })) }) },
          expect: () => String(view.url) === check.local("/plain") && session.currentThread.pages.length === 3 && app.windowNotch.state === ""
              && !probe.islandConnected() },
        { name: "Shift+Enter (reload): the page loads again", wait: 1500,
          act: () => { check.starts = []; probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path);
              probe.islandSay(JSON.stringify({ op: "hello" })); probe.islandSay(JSON.stringify({ op: "reload" })) }) },
          expect: () => check.starts.join() === check.local("/plain") && !view.loading && app.windowNotch.state === "" },
        { name: "Esc in the island (close): the session ends and the page has the keys", wait: 800,
          act: () => { probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path);
              probe.islandSay(JSON.stringify({ op: "hello" })); probe.islandSay(JSON.stringify({ op: "close" })) }) },
          expect: () => app.windowNotch.state === "" && !probe.islandConnected() && view.activeFocus && String(view.url) === check.local("/plain") },
        { name: "the island going away (its connection closed) ends the session too", wait: 800,
          act: () => { probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              check.later(() => probe.islandHangUp()) }) },
          expect: () => app.windowNotch.state === "" && !app.notch.connected && view.activeFocus },
        { name: "(the page on screen goes to a page of links: header, navigation, sidebar and footer links, a same-page, a script and an icon link, one link in view in its main part and one far down)",
          wait: 2000, act: () => { check.notchTask = session.currentThread.id; app.go(check.local("/where"), "navigate") },
          expect: () => view.title === "where" && !view.loading },
        { name: "Ctrl+L reads the page's likeliest links: the one in view first, then the one far down; none of the others", wait: 700,
          act: () => { probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" })) }) },
          expect: () => { const l = app.windowNotch.links; probe.report("     " + JSON.stringify(l));
              return l.length === 2 && l[0].title === "[PATCH v3] camss: honour data-lanes" && l[0].url === check.local("/harbour")
                  && l[1].title === "a link far down the page" && l[1].url === check.local("/plain?far") } },
        { name: "Where next: that link first (its host, \"linked on this page\"), then the task's pages; three rows under the label", wait: 100,
          expect: () => { const w = check.notchWhere(); probe.report("     " + w.map(x => x.kind + ":" + x.title + " (" + x.detail + ") " + x.word).join(" | "));
              return w.length === 4 && w[0].title === "Where next" && w[1].kind === "go" && w[1].title === "[PATCH v3] camss: honour data-lanes"
                  && w[1].detail === "127.0.0.1" && w[1].word === "linked on this page" && w[1].enter === "go"
                  && w.slice(2).every(x => /^in this task · /.test(x.word)) } },
        { name: "Enter on the selected link (go, next): Where next's first row loads in this page", wait: 2000,
          act: () => probe.islandSay(JSON.stringify({ op: "go", next: 1, where: "here" })),
          expect: () => String(view.url) === check.local("/harbour") && view.title === "harbour lights" && app.windowNotch.state === "" && !probe.islandConnected() },
        { name: "a page joining the task while the sheet is open: Where next is sent again (where)", wait: 1200,
          act: () => { probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              check.later(() => check.notchExtra = session.addPage(check.notchTask, check.local("/orchard"), "")) }) },
          expect: () => { const m = check.heard("where"), h = check.heard("hello"); probe.report("     " + (m ? m.rows.map(x => x.title).join(" | ") : "none"));
              return !!h && !h.where.some(x => x.title.indexOf("orchard") >= 0) && !!m && m.rows.some(x => x.title.indexOf("orchard") >= 0) } },
        { name: "Tab in the island (praxis): the session ends, and the window leaves the keys with the notch", wait: 800,
          act: () => { Backdrop.dispatched = []; probe.islandSay(JSON.stringify({ op: "praxis", text: "why" })) },
          expect: () => { probe.report("     " + Backdrop.dispatched.join(" | "));
              return app.windowNotch.state === "" && !probe.islandConnected() && !Backdrop.dispatched.some(d => d.indexOf("focus") >= 0) } },
        { name: "(a page of headings in the task, scrolled under \"Changes in v3\", then closed: where you stopped goes with it)", wait: 2500,
          // the recall group's pages, when it ran first, would answer the query as open pages ("switch")
          act: () => { app.closePage(check.notchExtra);
              for (const id in session.pages) if (String(session.pages[id].url).indexOf(check.local("/recall")) === 0) app.closePage(id);
              app.openHere(check.local("/recall-h"), "recall") },
          expect: () => view.title === "recall headings" && !view.loading },
        { name: "(closed)", focus: "scrollTo(0, 1780)", wait: 1200, act: () => app.closePage(session.currentPage),
          expect: () => { const c = session.closed[session.closed.length - 1];
              return !!c && c.url === check.local("/recall-h") && !!c.stopped && c.stopped.heading === "Changes in v3" } },
        { name: "Been here: the page you stopped on reads \"opens where you stopped\"", wait: 900,
          act: () => { probe.press(Qt.Key_L, ctrl); check.later(() => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "query", text: "recall headings", seq: 8 })) }) },
          expect: () => { const r = check.heard("rows"), rows = r ? r.rows : [];
              check.notchRecall = rows.findIndex(x => x.kind === "history" && x.title === "recall headings");
              probe.report("     " + rows.map(x => x.kind + ":" + x.title + " " + x.word).join(" | "));
              return !!r && r.seq === 8 && check.notchRecall > 0 && rows[check.notchRecall].word === "opens where you stopped"
                  && /^127\.0\.0\.1 · /.test(rows[check.notchRecall].detail) } },
        { name: "Enter on it: it loads in this page and goes back under \"Changes in v3\"", wait: 3000,
          act: () => probe.islandSay(JSON.stringify({ op: "go", index: check.notchRecall, seq: 8, text: "recall headings", where: "here" })),
          expect: () => view.title === "recall headings" && app.windowNotch.state === "",
          page: "scrollY", pageExpect: v => { probe.report("     scrollY " + v); return Math.abs(v - 1780) <= 2 } },
        { name: "Ctrl+T asks the shell for the sheet as a new page (mode new); no bar", focus: "document.activeElement && document.activeElement.blur()",
          key: Qt.Key_T, mods: ctrl, wait: 300,
          expect: () => app.notch.lastCall[3] === "new" && app.windowNotch.state === "calling" && app.windowNotch.mode === "new" && !newPageBar.opened },
        { name: "its hello: mode new, the bar's Recent and Closed tasks under the line, the task on screen for where the page goes", wait: 400,
          act: () => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => { const h = check.heard("hello"), w = h ? h.where : [];
              probe.report("     " + w.map(x => x.kind + ":" + x.title + " (" + x.detail + ") " + x.word).join(" | "));
              const t = session.currentThread, home = t && session.ownThread(t) ? "new page in " + (t.title || "this task") : "new task";
              probe.report("     dest " + (h ? h.dest : "") + ", want " + home);
              return !!h && h.mode === "new" && h.dest === home && w.length > 0 && w[0].kind === "label" && w[0].title === "Recent"
                  && w.every(x => ["label", "history", "earlier"].indexOf(x.kind) >= 0) && w.filter(x => x.kind === "history").every(x => x.detail !== "" && x.detail.indexOf(" · ") < 0) } },
        { name: "typing the task's words: \"new page in notch task\"; the rail stays as it is", wait: 400,
          act: () => probe.islandSay(JSON.stringify({ op: "query", text: "notch task", seq: 3 })),
          expect: () => { const r = check.heard("rows");
              return !!r && r.seq === 3 && r.dest === "new page in notch task" && !rail.rows.some(x => x.type === "ghost") } },
        { name: "Enter with an address typed since (rows out of date): a new page in that task, shown", wait: 2500,
          act: () => probe.islandSay(JSON.stringify({ op: "go", index: 0, seq: 99, text: check.local("/meadow"), where: "here" })),
          expect: () => String(view.url) === check.local("/meadow") && session.currentThread.id === check.notchTask && app.windowNotch.state === "" },
        { name: "Ctrl+T with the shell's call failing: the bar, with the keys typed meanwhile", wait: 1200,
          act: () => { app.notch.command = ["sh", "-c", "sleep 0.3; exit 1", "qs"]; probe.press(Qt.Key_T, ctrl); probe.press(Qt.Key_A, 0, "a"); probe.press(Qt.Key_B, 0, "b") },
          expect: () => newPageBar.opened && newPageBar.text === "ab" && app.windowNotch.state === "" },
        { name: "(Esc: the bar goes)", key: Qt.Key_Escape, wait: 600, expect: () => !newPageBar.opened },
        { name: "the shell's call failing (no shell): the card opens, with the keys typed meanwhile", wait: 1200,
          act: () => { app.notch.command = ["sh", "-c", "sleep 0.3; exit 1", "qs"]; probe.press(Qt.Key_L, ctrl); probe.press(Qt.Key_A, 0, "a"); probe.press(Qt.Key_B, 0, "b") },
          expect: () => address.editing && address.rows.length > 0 && address.rows[0].title === "ab" && app.windowNotch.state === "" },
        { name: "(Esc: the card back in its slot)", key: Qt.Key_Escape, wait: 900, expect: () => !address.out && view.activeFocus },
        { name: "the shell saying \"off\" (its notch off): the card at once", wait: 900,
          act: () => { app.notch.command = ["sh", "-c", "echo off", "qs"]; probe.press(Qt.Key_L, ctrl) },
          expect: () => address.editing && app.windowNotch.state === "" },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 900, expect: () => !address.out },
        { name: "no hello within the limit (the shell took the call and opened nothing): the card", wait: 1500,
          act: () => { app.notch.command = ["true"]; app.windowNotch.helloLimit = 700; probe.press(Qt.Key_L, ctrl) },
          expect: () => address.editing && app.windowNotch.state === "" },
        { name: "a hello after that is answered close and hung up", wait: 600,
          act: () => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => !!check.heard("close") && !check.heard("hello") && !probe.islandConnected() && address.editing },
        { name: "(Esc)", key: Qt.Key_Escape, wait: 900, act: () => app.windowNotch.helloLimit = 5000, expect: () => !address.out },
        { name: "full screen (F11): the card, and the shell is not asked", wait: 1500,
          act: () => { app.notch.command = ["sh", "-c", "exit 0", "full"]; app.toggleFullScreen(); check.later(() => probe.press(Qt.Key_L, ctrl)) },
          expect: () => address.editing && app.notch.lastCall[3] !== "full" && app.windowNotch.state === "" },
        { name: "(Esc; F11 again)", key: Qt.Key_Escape, wait: 1200, act: () => check.later(() => app.toggleFullScreen()), expect: () => !address.out && !app.fullWindow },
        { name: "a second window's Ctrl+L: the island answers that window", wait: 3000,
          act: () => { app.notch.command = ["true"]; probe.press(Qt.Key_N, ctrl);
              check.later(() => { const w = check.second(); w.go(check.local("/find"), "new", "", "notch second");
                  check.later(() => { probe.back(w); probe.press(Qt.Key_L, ctrl);
                      check.later(() => { probe.islandConnect(app.notch.path); probe.islandSay(JSON.stringify({ op: "hello" })) }) }) }) },
          expect: () => { const w = check.second(), h = check.heard("hello");
              return !!w && w.windowNotch.state === "open" && app.windowNotch.state === "" && !!h && h.link === check.local("/find") && h.task === "find" && h.pages === 1 } },
        { name: "that window closing ends the session: the island hears close and is hung up", wait: 1500,
          act: () => check.second().close(),
          expect: () => app.mainWindows.length === 1 && !!check.heard("close") && !probe.islandConnected() && !app.notch.connected },
        { name: "(the notch socket closed again, Hyprland's list gone, the task's pages closed)", wait: 1500,
          act: () => { app.notch.close(); Backdrop.fakeClients = undefined; Backdrop.dispatched = []; probe.back(app);
              for (const id of session.currentThread.pages.slice()) app.closePage(id) },
          expect: () => !app.notch.listening },
    ]
    // A sign-in popup in the notch (NotchSignin.qml, ~/book4-edge/signin-notch-plan.md): the shell a stand-in that exits 0,
    // the island the probe's stand-in on the sign-in socket.
    readonly property var signinSteps: [
        { group: "signin" },
        check.server,
        { name: "(a page that opens popups, and one of its own thread to look away to; the sign-in socket listening)", wait: 1800,
          act: () => { probe.back(app); app.signinNotch.command = ["true"]; app.signinNotch.listen(); app.windowSignin.helloLimit = 5000;
              check.other = session.addPage(session.newThread("other"), check.plain, "");
              app.go(check.local("/popup-opener"), "new", "", "signin task"); check.later(() => check.opener = session.currentPage) },
          expect: () => app.signinNotch.listening && view.title === "opener" && !view.loading },
        { name: "window.open with a size after a click: the shell is asked for the notch (signin, the socket, the monitor, open); no window shows meanwhile",
          wait: 800, focus: "act = sized", act: () => check.click(),
          expect: () => { check.popupWin = view.popup; probe.report("     " + app.signinNotch.lastCall.join(" "));
              return !!view.popup && view.popup.shownIn === "notch" && !view.popup.visible && app.windowSignin.state === "calling"
                  && app.signinNotch.lastCall.join(" ") === ["true", app.signinNotch.path, app.screen ? app.screen.name : "", "open"].join(" ") } },
        { name: "the island says hello: the answer has the popup's host, secure, the opener's host, the size it asked and how many sign-ins", wait: 500,
          act: () => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => { const h = check.heard("hello"); probe.report("     " + JSON.stringify(h));
              return !!h && h.host === "127.0.0.1:" + check.port && h.secure === true && h.opener === "127.0.0.1:" + check.port
                  && h.width === 480 && h.height === 560 && h.count === 1 && app.windowSignin.state === "open" && !check.popupWin.visible } },
        { name: "map: the page alone at the size the shell says, under the app_id browser-signin, no header and no parent, with the keys", wait: 800,
          act: () => probe.islandSay(JSON.stringify({ op: "map", width: 500, height: 400 })),
          expect: () => { const w = check.popupWin;
              return w.visible && w.width === 500 && w.height === 400 && w.transientParent === null
                  && probe.propertyOf(w, "appId") === "browser-signin" && w.card.pageSlot.y === 0 && w.view.activeFocus } },
        { name: "an ask in the page (Save password) goes to the island in the address card's words", wait: 500,
          act: () => check.popupWin.view.enqueue({ kind: "password", origin: Asks.originOf(String(check.popupWin.view.url)), host: "127.0.0.1:" + check.port,
                                                   user: "", password: check.letters(12) }),
          expect: () => { const a = check.heard("ask"); probe.report("     " + JSON.stringify(a));
              return !!a && !!a.ask && a.ask.kind === "password" && a.ask.lines[0].text === "Save password for 127.0.0.1:" + check.port + "?"
                  && a.ask.actions.map(x => x.choice).join() === "save,notnow" && a.count === 1 } },
        { name: "the island's answer (Not now) answers it; the island hears there is none", wait: 500,
          act: () => probe.islandSay(JSON.stringify({ op: "answer", id: check.popupWin.view.ask.id, choice: "notnow", data: {} })),
          expect: () => { const a = check.heard("ask"); return check.popupWin.view.asks.length === 0 && !!a && a.ask === null } },
        { name: "unmap: the page hides, and the island hears it has", wait: 400, act: () => probe.islandSay(JSON.stringify({ op: "unmap" })),
          expect: () => !check.popupWin.visible && !!check.heard("unmapped") && !!view.popup },
        { name: "its opener off screen: the island hears aside; back on it, aside off, and the page waits for the shell's map", wait: 900,
          act: () => { probe.islandSay(JSON.stringify({ op: "map", width: 500, height: 400 }));
              check.later(() => { app.show(check.other); check.later(() => { check.hidden = !check.popupWin.visible; app.show(check.opener) }) }) },
          expect: () => { const all = probe.islandHeard().filter(m => m.op === "aside");
              return check.hidden && all.length === 2 && all[0].on === true && all[1].on === false && !check.popupWin.visible } },
        { name: "(map)", wait: 500, act: () => probe.islandSay(JSON.stringify({ op: "map", width: 500, height: 400 })), expect: () => check.popupWin.visible },
        { name: "the way back (back): the popup closes and the island hears done, not signed; the page stays until the shell's unmap", wait: 80,
          act: () => probe.islandSay(JSON.stringify({ op: "back" })),
          expect: () => { const d = check.heard("done"); return !!d && d.signed === false && !view.popup && check.popupWin !== null && check.popupWin.visible } },
        { name: "unmap: it goes; the keys are its opener's; nothing moved in the rail", wait: 600, act: () => probe.islandSay(JSON.stringify({ op: "unmap" })),
          expect: () => (check.popupWin === null || !check.popupWin.visible) && session.currentPage === check.opener && view.activeFocus && !probe.islandConnected() },
        { name: "a popup that closes itself: done, signed; with no unmap from the shell it goes 150 ms later; the opener has its answer", wait: 2200,
          focus: "act = sized; log.length = 0",
          act: () => { check.click(); check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "map", width: 480, height: 440 }));
              check.later(() => { check.popupWin = view.popup; check.popupWin.view.runJavaScript("done()") }) }) },
          expect: () => { const d = check.heard("done"); return !!d && d.signed === true && !view.popup && (check.popupWin === null || !check.popupWin.visible) && view.activeFocus },
          page: "log.join()", pageExpect: v => v === "message signed in" },
        { name: "Esc in the page, which leaves it: the popup closes, done not signed", wait: 2500,
          focus: "act = sized",
          act: () => { check.click(); check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "map", width: 480, height: 440 }));
              check.later(() => { check.popupWin = view.popup; probe.back(check.popupWin); probe.press(Qt.Key_Escape, 0) }) }) },
          expect: () => { const d = check.heard("done"); return !!d && d.signed === false && !view.popup } },
        // the bug of 2026-09-29, in the notch: a sign-in whose last page never calls window.close()
        { name: "a sign-in on another site whose COOP cuts it off from its opener comes back to the opener's site: the page there has no opener", wait: 1300,
          focus: "act = coop",
          act: () => { check.click(); check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "map", width: 480, height: 440 })); check.popupWin = view.popup }) },
          expect: () => !!view.popup && view.popup.shownIn === "notch" && view.popup.view.title === "back" && view.popup.leftOpener,
          pageIn: () => check.popupWin.view, page: "String(cutOff)", pageExpect: v => v === "true" },
        { name: "back home, loaded and still there after a moment, it closes itself: done, signed; the keys are its opener's", wait: 2800,
          expect: () => { const d = check.heard("done"), w = view.popup;
              probe.report("     done " + JSON.stringify(d) + "; popup " + (w ? [w.view.title, w.leftOpener, w.backHome, w.settled, w.view.loading, w.view.asks.length].join(",") : "none")
                           + "; opener in front " + (session.currentPage === check.opener) + ", keys " + view.activeFocus);
              return !!d && d.signed === true && !view.popup && session.currentPage === check.opener && view.activeFocus } },
        { name: "(again, back home)", wait: 1300, focus: "act = coop",
          act: () => { check.click(); check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "map", width: 480, height: 440 })); check.popupWin = view.popup }) },
          expect: () => !!view.popup && view.popup.view.title === "back" },
        { name: "an ask waiting there (the sign-in's \u201cSave password for <host>?\u201d): it stays past the 1.5 s", wait: 2500,
          act: () => check.popupWin.view.enqueue({ kind: "password", origin: Asks.originOf(String(check.popupWin.view.url)), host: "127.0.0.1:" + check.port,
                                                    user: "", password: check.letters(12) }),
          expect: () => !!view.popup && view.popup.view.asks.length === 1 && view.popup.view.ask.kind === "password" && !view.popup.settled },
        { name: "answered (Not now), it closes itself 1.5 s later", wait: 2800,
          act: () => { const v = check.popupWin.view; v.answer(v.ask, "notnow", {}) },
          expect: () => !view.popup && session.currentPage === check.opener },
        { name: "one that stays on the other site stays open", wait: 3000, focus: "act = coopStay",
          act: () => { check.click(); check.later(() => check.popupWin = view.popup) },
          expect: () => !!view.popup && view.popup.view.title === "idp stays" },
        { name: "(closed)", wait: 600, act: () => app.closePopup(check.popupWin, true), expect: () => !view.popup },
        { name: "one back on the opener's site with a form still to fill stays open", wait: 3500, focus: "act = coopField",
          act: () => { check.click(); check.later(() => check.popupWin = view.popup) },
          expect: () => !!view.popup && view.popup.view.title === "back with a form" && view.popup.backHome },
        { name: "(closed)", wait: 600, act: () => app.closePopup(check.popupWin, true), expect: () => !view.popup },
        { name: "one on the opener's own site that never left stays open", wait: 2500, focus: "act = sized",
          act: () => { check.click(); check.later(() => check.popupWin = view.popup) },
          expect: () => !!view.popup && !view.popup.leftOpener },
        { name: "(closed)", wait: 600, act: () => app.closePopup(check.popupWin, true), expect: () => !view.popup },
        { name: "a one-time code's field with the keys: the island hears code on", wait: 2500,
          focus: "act = code",
          act: () => { check.click(); check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "map", width: 480, height: 440 }));
              check.later(() => { check.popupWin = view.popup; check.popupWin.view.runJavaScript("otp.focus()") }) }) },
          expect: () => { const c = check.heard("code"); return !!c && c.on === true && check.popupWin.view.codeField } },
        { name: "fill: the code from the phone typed into it, as typed", wait: 500, act: () => probe.islandSay(JSON.stringify({ op: "fill", text: "482913" })),
          pageIn: () => check.popupWin.view, page: "otp.value", pageExpect: v => v === "482913", expect: () => true },
        { name: "(another page that opens popups, in the same task)", wait: 1800,
          act: () => { check.signinFirst = check.popupWin; app.openHere(check.local("/popup-opener"), "opener two"); check.later(() => check.signinSecond = session.currentPage) },
          expect: () => view.title === "opener" && session.currentPage !== check.opener && !view.loading },
        { name: "two sign-ins: the second waits its turn, hidden, and the island hears there are 2", wait: 800, focus: "act = sized",
          act: () => { probe.back(app); check.click() },
          expect: () => { const c = check.heard("count");
              return !!view.popup && view.popup !== check.signinFirst && view.popup.shownIn === "notch" && !view.popup.visible
                  && app.windowSignin.current === check.signinFirst && !!c && c.count === 2 } },
        { name: "the first closed: the shell is asked again, for the second", wait: 600,
          act: () => { check.popupWin = view.popup; app.closePopup(check.signinFirst, false) },
          expect: () => app.windowSignin.current === check.popupWin && app.windowSignin.state === "calling" && !!check.heard("done") },
        { name: "the shell going away while it is up: the sign-in goes on as a page after its opener, at the address it reached; no window", wait: 1200,
          act: () => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
              probe.islandSay(JSON.stringify({ op: "map", width: 480, height: 440 })); check.later(() => probe.islandHangUp()) },
          expect: () => { const t = session.currentThread;
              return !app.views[check.signinSecond].popup && (check.popupWin === null || !check.popupWin.visible) && session.current.url === check.local("/popup")
                  && t.pages.indexOf(check.signinSecond) >= 0 && t.pages.indexOf(session.currentPage) > t.pages.indexOf(check.signinSecond)
                  && app.windowSignin.state === "" } },
        { name: "(that page closed: the opener in front again)", wait: 1200, act: () => app.closePage(session.currentPage),
          expect: () => session.currentPage === check.signinSecond && view.title === "opener" },
        { name: "the shell saying off (its notch off, or under a full-screen window): a page at once", wait: 1500,
          focus: "act = sized", act: () => { app.signinNotch.command = ["sh", "-c", "echo off", "qs"]; check.click() },
          expect: () => !app.views[check.signinSecond].popup && session.current.url === check.local("/popup") },
        { name: "(that page closed)", wait: 1200, act: () => app.closePage(session.currentPage), expect: () => session.currentPage === check.signinSecond },
        { name: "no hello within the limit: a page", wait: 2000, focus: "act = sized",
          act: () => { app.signinNotch.command = ["true"]; app.windowSignin.helloLimit = 700; check.click() },
          expect: () => !app.views[check.signinSecond].popup && session.current.url === check.local("/popup") },
        { name: "a hello after that is answered close and hung up", wait: 600,
          act: () => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => !!check.heard("close") && !check.heard("hello") && !probe.islandConnected() },
        // A sign-in from another app (gcloud's in foot): a link that is one opens in the notch, not as a page
        { name: "(the sign-in socket listening, its shell a stand-in; the main window loses the focus to foot)", wait: 400,
          act: () => { if (view.popup) app.closePopup(view.popup, false);
              app.signinNotch.command = ["true"]; app.signinNotch.listen(); app.windowSignin.helloLimit = 5000; probe.away();
              check.pageCount = Object.keys(session.pages).length },
          expect: () => app.signinNotch.listening && !app.active },
        { name: "an OAuth authorize link launched from foot: no page; the shell is asked in mode app; nothing shows meanwhile", wait: 2500,
          act: () => probe.launch(["--from", "foot", check.authorizeLink()]),
          expect: () => { const w = app.appSignin; probe.report("     " + app.signinNotch.lastCall.join(" "));
              return check.launchedOk() && !!w && !w.visible && w.shownIn === "notch" && app.signinNotch.lastCall[3] === "app"
                  && app.windowSignin.state === "calling" && Object.keys(session.pages).length === check.pageCount } },
        { name: "hello: for foot, an app's; the authorize page's host; the notch's largest page asked", wait: 500,
          act: () => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" })) },
          expect: () => { const h = check.heard("hello"); probe.report("     " + JSON.stringify(h));
              return !!h && h.opener === "foot" && h.app === true && h.host === "127.0.0.1:" + check.port && h.width === 560 && h.height === 480 } },
        { name: "map: its page alone under the app_id browser-signin, with the keys", wait: 800,
          act: () => probe.islandSay(JSON.stringify({ op: "map", width: 560, height: 480 })),
          expect: () => { const w = app.appSignin;
              return w.visible && w.width === 560 && w.height === 480 && probe.propertyOf(w, "appId") === "browser-signin" && w.view.title === "authorize"
                  && w.view.activeFocus } },
        { name: "consent: it passes the localhost redirect (a 302 on to another host), lands on “You are now authenticated”: done, signed; then it goes",
          wait: 2500, act: () => app.appSignin.view.runJavaScript("consent()"),
          expect: () => { const d = check.heard("done");
              return !!d && d.signed === true && app.appSignin === null && Object.keys(session.pages).length === check.pageCount } },
        { name: "a sign-in you deny comes back with error=: done, not signed", wait: 4500,
          act: () => { probe.launch(["--from", "foot", check.authorizeLink()]);
              check.later(() => check.later(() => check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
                  probe.islandSay(JSON.stringify({ op: "map", width: 560, height: 480 }));
                  check.later(() => check.later(() => app.appSignin.view.runJavaScript("deny()"))) }))) },
          expect: () => { const d = check.heard("done"); return !!d && d.signed === false && app.appSignin === null } },
        { name: "one that ends anywhere else stays open", wait: 4000,
          act: () => { probe.launch(["--from", "foot", check.authorizeLink()]);
              check.later(() => check.later(() => check.later(() => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" }));
                  probe.islandSay(JSON.stringify({ op: "map", width: 560, height: 480 })); check.later(() => app.appSignin.view.url = check.served("elsewhere", "/plain")) }))) },
          expect: () => !!app.appSignin && app.appSignin.visible && app.appSignin.view.title === "plain" && !check.heard("done") },
        { name: "Esc there (the page leaves it): it closes, done, not signed", wait: 800,
          act: () => { probe.back(app.appSignin); probe.press(Qt.Key_Escape, 0) },
          expect: () => { const d = check.heard("done"); return !!d && d.signed === false && app.appSignin === null } },
        { name: "a link from foot whose first load redirects into a sign-in: the page it opened as goes to the notch, and out of the rail", wait: 3000,
          act: () => probe.launch(["--from", "foot", check.local("/to-signin")]),
          expect: () => { const w = app.appSignin;
              return !!w && w.from === "foot" && w.shownIn === "notch" && app.signinNotch.lastCall[3] === "app"
                  && Object.keys(session.pages).length === check.pageCount } },
        { name: "(it goes: the shell hangs up, so it falls back to a page in the main window, at the address it reached)", wait: 1500,
          act: () => { probe.islandConnect(app.signinNotch.path); probe.islandSay(JSON.stringify({ op: "hello" })); check.later(() => probe.islandHangUp()) },
          expect: () => app.appSignin === null && /\/oauth\/authorize\?/.test(session.current.url) && session.current.from === "foot" && app.active },
        { name: "(that page closed)", wait: 1000, act: () => app.closePage(session.currentPage), expect: () => Object.keys(session.pages).length === check.pageCount },
        // a page from an app that asks for a password is a sign-in whatever its address (2026-10-10: a site's own
        // login from an app came up in the old floating peek)
        { name: "a link from foot to a page asking for a password, at an address that names no sign-in: the page goes to the notch", wait: 3000,
          act: () => probe.launch(["--from", "foot", check.local("/welcome-pw")]),
          expect: () => { const w = app.appSignin;
              probe.report("     sign-in " + (w ? w.shownIn + " " + String(w.view.url) : "none") + "; page " + session.current?.url + " (" + view.title
                           + ", loading " + view.loading + "), pages " + Object.keys(session.pages).length + " of " + check.pageCount);
              return !!w && w.from === "foot" && w.shownIn === "notch" && /\/welcome-pw$/.test(String(w.view.url))
                  && Object.keys(session.pages).length === check.pageCount } },
        { name: "(it closed)", wait: 1000, act: () => app.closeAppSignin(app.appSignin, false), expect: () => app.appSignin === null },
        { name: "one whose password field a script draws a moment after the load: the notch too", wait: 4000,
          act: () => probe.launch(["--from", "foot", check.local("/welcome-late")]),
          expect: () => !!app.appSignin && app.appSignin.shownIn === "notch" && Object.keys(session.pages).length === check.pageCount },
        { name: "(it closed)", wait: 1000, act: () => app.closeAppSignin(app.appSignin, false), expect: () => app.appSignin === null },
        { name: "a page from foot with no password field stays a page", wait: 3500,
          act: () => probe.launch(["--from", "foot", check.local("/welcome-plain")]),
          expect: () => app.appSignin === null && /\/welcome-plain$/.test(session.current.url) && session.current.from === "foot" },
        { name: "(the page closed)", wait: 1000, act: () => app.closePage(session.currentPage), expect: () => Object.keys(session.pages).length === check.pageCount },
        { name: "the shell saying off: the sign-in link opens as a page in the main window", wait: 3000,
          act: () => { app.signinNotch.command = ["sh", "-c", "echo off", "qs"]; probe.launch(["--from", "foot", check.authorizeLink()]) },
          expect: () => app.appSignin === null && session.current.from === "foot" && /\/oauth\/authorize\?/.test(session.current.url) },
        { name: "(that page closed; back on the main window)", wait: 1000, act: () => { app.closePage(session.currentPage); probe.back(app) },
          expect: () => Object.keys(session.pages).length === check.pageCount },
        { name: "(closed; the sign-in socket closed again)", wait: 600,
          act: () => { if (view.popup) app.closePopup(view.popup, true); app.signinNotch.close(); app.windowSignin.helloLimit = 1500 },
          expect: () => !view.popup && !app.signinNotch.listening },
    ]
    property var signinFirst: null
    // gcloud's kind of link: an OAuth authorize address on this server whose redirect_uri is localhost on its port
    function authorizeLink() {
        return check.local("/oauth/authorize?response_type=code&client_id=check&redirect_uri=" + encodeURIComponent("http://localhost:" + check.port + "/"));
    }
    property string signinSecond: ""
    property bool islandUp: false
    property string notchTask: ""
    property string notchExtra: ""
    property int notchRecall: -1
    // the where rows the stand-in island has now: the last where update, else the hello's
    function notchWhere() {
        const m = heard("where"), h = heard("hello");
        return m ? m.rows : h ? h.where : [];
    }
    // the last message the stand-in island heard with that op
    function heard(op) {
        const all = probe.islandHeard().filter(m => m.op === op);
        return all.length > 0 ? all[all.length - 1] : null;
    }
    readonly property var faviconSteps: [
        { name: "(the notch's sheet off again)", act: () => { app.notchSearch = false }, expect: () => !app.notchSearch },
        { group: "favicons" },
        check.server,
        { name: "a page with a favicon of its own, in the background: the favicon is kept as a file while the page is live", wait: 3000,
          act: () => { const t = session.newThread("icons"); check.iconPage = session.addPage(t, check.local("/icon"), "");
              app.viewFor(check.iconPage).url = check.local("/icon") },
          expect: () => { const p = session.pages[check.iconPage]; check.iconAddress = p ? p.icon || "" : "";
              probe.report("     icon " + check.iconAddress + " kept " + Engine.keptIcon(check.iconAddress));
              return check.iconAddress.startsWith("image://favicon/") && Engine.keptIcon(check.iconAddress).startsWith("file://") } },
        { name: "(unloaded, as the memory net unloads it)", wait: 1500, act: () => app.unloadPage(check.iconPage),
          expect: () => state(check.iconPage) === WebEngineView.LifecycleState.Discarded },
        { name: "its favicon drawn again after the unload, as the rail draws it (the kept copy): the image comes", wait: 2500,
          act: () => { check.iconProbe = Qt.createQmlObject("import QtQuick; Image { cache: false; width: 16; height: 16 }", app.contentItem);
              check.iconProbe.source = Engine.keptIcon(check.iconAddress) },
          expect: () => { probe.report("     status " + check.iconProbe.status); return check.iconProbe.status === Image.Ready } },
        { name: "with the copy gone and the page still unloaded, a page asking for it gets nothing and Qt's provider is not asked",
          wait: 1500,
          act: () => { check.iconFile = Engine.keptIcon(check.iconAddress); probe.removeCached(check.iconFile); Engine.keptIcon(check.iconAddress) },
          expect: () => Engine.keptIcon(check.iconAddress) === "" },
        { name: "once the page is closed, a missing copy comes from the profile's favicons", wait: 2500,
          act: () => { app.closePage(check.iconPage); Engine.keptIcon(check.iconAddress) },
          expect: () => { probe.report("     " + Engine.keptIcon(check.iconAddress)); return Engine.keptIcon(check.iconAddress).startsWith("file://") } },
        { name: "no favicon is drawn from Qt's provider: no image://favicon/ address among the rail's images", wait: 300,
          expect: () => { const found = []; const walk = item => { for (const c of item.children) { if (String(c.source ?? "").startsWith("image://favicon/")) found.push(String(c.source)); walk(c) } };
              walk(app.contentItem); probe.report("     " + found.join(" ")); return found.length === 0 } },
        { name: "(the probe gone)", act: () => { check.iconProbe.destroy(); check.iconProbe = null }, expect: () => true },
    ]
    readonly property var railSteps: [
        { group: "rail" },
        check.server,
        { name: "(three threads at the rail's top: a task of two pages, one on screen; a task of two seen before it; a page of its own)",
          wait: 3000,
          act: () => {
              app.setFold(true);
              probe.pointer(700, 400);
              const solo = session.newThread("rail solo"), away = session.newThread("rail away"), task = session.newThread("rail task");
              check.railSolo = session.addPage(solo, check.local("/plain"), "");
              check.railAway = [session.addPage(away, check.local("/plain"), ""), session.addPage(away, check.local("/find"), "")];
              check.railTask = [session.addPage(task, check.local("/plain"), ""), session.addPage(task, check.local("/find"), "")];
              app.show(check.railAway[1]);
              check.later(() => app.show(check.railTask[0]));
          },
          expect: () => session.currentPage === check.railTask[0] && !view.loading && app.railPinned },
        // the owner, 2026-10-16: tasks folding as you left them took two clicks to reach a page
        { name: "the task left stays open: every page one click away",
          expect: () => check.rowOf("t:" + session.pages[check.railAway[0]].thread).open && check.rowIndex("p:" + check.railAway[0]) >= 0 },
        { name: "(the other task folded by hand)", wait: 600, act: () => session.setOpen(session.pages[check.railAway[0]].thread, false),
          expect: () => !check.rowOf("t:" + session.pages[check.railAway[0]].thread).open },
        { name: "drawn in thread order: the task's row over its pages one step in, air, the other task folded in its place, the page of its own",
          expect: () => { const at = k => check.rowIndex(k), task = session.pages[check.railTask[0]].thread, away = session.pages[check.railAway[0]].thread;
              const t = check.rowOf("t:" + task), a = check.rowOf("t:" + away);
              probe.report("     at " + [at("t:" + task), at("p:" + check.railTask[0]), at("p:" + check.railTask[1]), at("space:" + away), at("t:" + away),
                                         at("p:" + check.railSolo)].join(" "));
              return t.open && !a.open && a.count === 2 && check.rowOf("p:" + check.railTask[0]).depth === 1 && check.rowOf("p:" + check.railSolo).depth === 0
                  && at("t:" + task) < at("p:" + check.railTask[0]) && at("p:" + check.railTask[0]) < at("p:" + check.railTask[1])
                  && at("p:" + check.railTask[1]) < at("space:" + away) && at("space:" + away) < at("t:" + away) && at("t:" + away) < at("p:" + check.railSolo)
                  && at("p:" + check.railAway[0]) < 0 } },
        { name: "words only for what happens: none for the page on screen, none for the other (its age under the pointer), the folded task its count",
          expect: () => { const other = check.rowOf("p:" + check.railTask[1]), away = check.rowOf("t:" + session.pages[check.railAway[0]].thread);
              probe.report("     " + [check.rowOf("p:" + check.railTask[0]).word, other.word, other.detail, away.word, away.count].join(" | "));
              return check.rowOf("p:" + check.railTask[0]).word === "" && other.word === "" && /^\d+m$/.test(other.detail) && away.word === "" && away.count === 2 } },
        { name: "the foot: Saved and Downloads, then Settings; no status line",
          expect: () => !!check.named(rail, "foot:saved") && !!check.named(rail, "foot:downloads") && !!check.named(rail, "settingsButton")
              && check.named(rail, "statusLine") === null },
        { name: "Ctrl+Tab: the task's next page", key: Qt.Key_Tab, mods: ctrl, wait: 800, focus: "document.activeElement.blur()",
          expect: () => session.currentPage === check.railTask[1] },
        { name: "Ctrl+Tab: the folded task at its last-seen page; it opens where it is, the task left keeps its fold", key: Qt.Key_Tab, mods: ctrl, wait: 800,
          focus: "document.activeElement.blur()",
          expect: () => { const task = "t:" + session.pages[check.railTask[0]].thread, away = "t:" + session.pages[check.railAway[0]].thread;
              return session.currentPage === check.railAway[1] && check.rowOf(away).open && check.rowOf(task).open && check.rowIndex(task) < check.rowIndex(away) } },
        { name: "Ctrl+Shift+Tab: the page drawn above it now, the other page of its task", key: Qt.Key_Backtab, mods: ctrl | Qt.ShiftModifier, wait: 800,
          focus: "document.activeElement.blur()", expect: () => session.currentPage === check.railAway[0] },
        { name: "Ctrl+Shift+Tab again: the task's last page, where it came from", key: Qt.Key_Backtab, mods: ctrl | Qt.ShiftModifier, wait: 800,
          focus: "document.activeElement.blur()", expect: () => session.currentPage === check.railTask[1] },
        { name: "F6 into the rail list, Up to the task's row, Left: it folds where it is, marked, the cursor still on its row", wait: 900,
          act: () => { app.focusCycle(); app.focusCycle(); check.later(() => { probe.press(Qt.Key_Up, 0); probe.press(Qt.Key_Up, 0); probe.press(Qt.Key_Left, 0) }) },
          expect: () => { const k = "t:" + session.pages[check.railTask[0]].thread, r = check.rowOf(k);
              return rail.listFocused && !r.open && r.current && check.rowIndex(k) < check.rowIndex("t:" + session.pages[check.railAway[0]].thread)
                  && rail.cursor === check.rowIndex(k) } },
        { name: "Enter on it: it opens again at its last-seen page", key: Qt.Key_Return, wait: 900,
          expect: () => check.rowOf("t:" + session.pages[check.railTask[0]].thread).open && session.currentPage === check.railTask[1] },
        { name: "(Esc: the keys back on the page; the other task folded)", key: Qt.Key_Escape, wait: 600,
          act: () => session.setOpen(session.pages[check.railAway[0]].thread, false), expect: () => !rail.listFocused && !check.rowOf("t:" + session.pages[check.railAway[0]].thread).open },
        { name: "a click on a folded row: that task back at its last-seen page (its first, seen by Ctrl+Shift+Tab)", wait: 900,
          act: () => check.clickRow("t:" + session.pages[check.railAway[0]].thread),
          expect: () => session.currentPage === check.railAway[0] && check.rowOf("t:" + session.pages[check.railAway[0]].thread).open },
        { name: "a click on a page of the first task: the task left stays open", wait: 900,
          act: () => check.clickRow("p:" + check.railTask[0]),
          expect: () => session.currentPage === check.railTask[0] && check.rowOf("t:" + session.pages[check.railAway[0]].thread).open
              && check.rowOf("t:" + session.pages[check.railTask[0]].thread).open },
        { name: "the pointer leaves the rail: it still stays open", wait: 900, act: () => probe.pointer(700, 400),
          expect: () => check.rowOf("t:" + session.pages[check.railAway[0]].thread).open && check.rowOf("t:" + session.pages[check.railTask[0]].thread).open },
        { name: "a click on the open task's row folds it where it is, the page on screen marked", wait: 900,
          act: () => check.clickRow("t:" + session.pages[check.railTask[0]].thread),
          expect: () => { const k = "t:" + session.pages[check.railTask[0]].thread, r = check.rowOf(k);
              return !r.open && r.current && session.currentPage === check.railTask[0] && check.rowIndex(k) < check.rowIndex("t:" + session.pages[check.railAway[0]].thread) } },
        { name: "the other task folded by hand, the pointer resting on it: its pages beside the rail, the keys where they were", wait: 1000,
          act: () => { session.setOpen(session.pages[check.railAway[0]].thread, false); check.later(() => check.hoverRow("t:" + session.pages[check.railAway[0]].thread)) },
          expect: () => { const s = rail.pageStack;
              return s.opened && s.entries.map(e => e.arg).join() === check.railAway.join() && !rail.listFocused && !s.contentItem.activeFocus } },
        { name: "a click on its second page there: that page on screen, its task open where it is, the list gone", wait: 1200,
          act: () => check.clickAt(rail.pageStack.contentItem.children.find(c => c.modelData && c.modelData.arg === check.railAway[1])),
          expect: () => { const k = "t:" + session.pages[check.railAway[0]].thread;
              return session.currentPage === check.railAway[1] && check.rowOf(k).open && !rail.pageStack.opened
                  && check.rowIndex("t:" + session.pages[check.railTask[0]].thread) < check.rowIndex(k) } },
        { name: "(the pointer away)", wait: 600, act: () => probe.pointer(700, 400), expect: () => !rail.pageStack.opened },
        // Back on a page a link opened, with nothing earlier of its own, closes it and shows its opener (Main.back)
        { name: "a link opened from a page: a page after it in its task, with no history of its own", wait: 1500,
          act: () => { check.railLink = session.addFromOpener(check.railTask[0], check.local("/find"), "link"); app.show(check.railLink) },
          expect: () => session.currentPage === check.railLink && !view.canGoBack && session.pages[check.railLink].thread === session.pages[check.railTask[0]].thread },
        { name: "Back there closes it and shows the page whose link opened it", wait: 1200, act: () => check.clickNamed(rail, "backButton"),
          expect: () => !session.pages[check.railLink] && session.currentPage === check.railTask[0] },
        // the owner, 2026-10-16: closing a whole task was hard to find
        { name: "the pointer on a task's page: the task's ✕ shows on its row", wait: 600, act: () => check.hoverRow("p:" + check.railAway[0]),
          expect: () => !!check.named(check.rowItem("t:" + session.pages[check.railAway[0]].thread), "taskClose")
              && !check.named(check.rowItem("t:" + session.pages[check.railTask[0]].thread), "taskClose") },
        { name: "a middle click on a task's row closes the task: filed in History, its pages gone from the rail", wait: 1200,
          act: () => { const it = check.rowItem("t:" + session.pages[check.railAway[0]].thread), p = it.mapToItem(app.contentItem, it.width / 2, 12);
              check.railAwayThread = session.pages[check.railAway[0]].thread;
              probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.MiddleButton); probe.pointer(p.x, p.y) },
          expect: () => session.threadById(check.railAwayThread).earlier && check.rowIndex("t:" + check.railAwayThread) < 0 && check.rowIndex("p:" + check.railAway[0]) < 0 },
        { name: "(the pointer away)", wait: 600, act: () => probe.pointer(700, 400), expect: () => !rail.pageStack.opened },
        { name: "Pinned: its faces at the rail's foot under its label, below the list and over the places; a click on one shows its page", wait: 1500,
          act: () => { check.railCell = session.addAlways(check.local("/site-other"), "rail cell", ""); check.later(() => check.clickAt(check.named(rail, "a:" + check.railCell))) },
          expect: () => { const row = check.named(rail, "alwaysRow"), places = check.named(rail, "footPlaces");
              return !!row && row.y >= rail.listView.y + rail.listView.height && !!places && row.y + row.height <= places.mapToItem(rail, 0, 0).y
                  && session.currentPage === check.railCell } },
        { name: "(the cell removed, the three threads closed)", wait: 1500,
          act: () => { app.command("removeAlways", check.railCell, null); for (const id of [check.railSolo].concat(check.railAway, check.railTask)) app.closePage(id) },
          expect: () => session.always.indexOf(check.railCell) < 0 && ![check.railSolo].concat(check.railAway, check.railTask).some(id => session.pages[id]) },
    ]
    property string railSolo: ""
    property var railAway: []
    property var railTask: []
    property string railLink: ""
    property string railAwayThread: ""
    property string railCell: ""
    function rowIndex(key) {
        const m = rail.listView.model;
        for (let i = 0; i < m.count; i++)
            if (m.get(i).key === key)
                return i;
        return -1;
    }

    // The rail's look and the lift (PLAN.md 3.19), with the pointer moved and clicks made through the window system:
    // the docked slab, the fold glyph lifting it while the page slides under it at its folded width (resized once), the
    // pointer off it tucking it away, the window's edge bringing it back and the pin glyph docking it; Ctrl+B with the
    // pointer elsewhere; the quiet rail while you read, woken by the pointer near it, an ask and the keys; Settings by
    // its button.
    readonly property var liftSteps: [
        { group: "lift" },
        check.server,
        { name: "(a plain page, pinned, the pointer on it)", wait: 2000,
          act: () => { app.setFold(true); probe.pointer(700, 400); app.go(check.local("/plain"), "navigate") },
          expect: () => view.title === "plain" && !view.loading && app.railPinned && !app.railMoving },
        { name: "docked: no slab, the rail on the window's ground as Tacit Settings' column (its fill and edge clear), 288 x 788 at 6, 6, no shadow; the page 6 px beside it and 6 px inside the window",
          expect: () => { const b = check.named(rail, "slab"), p = view.mapToItem(app.contentItem, 0, 0);
              probe.report("     slab " + [rail.x, rail.y, rail.width, rail.height].join(" ") + ", page " + [p.x, p.y, view.width, view.height].join(" "));
              return rail.visible && !peekedRail.visible && rail.x === 6 && rail.y === 6 && rail.width === 288 && rail.height === 788 && b.radius === 14
                  && b.color.a < 0.01 && b.border.color.a < 0.01
                  && check.named(rail, "slabShadow") === null && p.x === 300 && p.y === 6 && view.width === 974 && view.height === 788 } },
        { name: "the fold glyph: the overlay takes the slab's place at once and lifts off it, the page widening once under it", wait: 120,
          act: () => { check.widths = 0; check.midShifts = 0; check.clickAt(rail.foldButton) },
          expect: () => !app.railPinned && peekedRail.visible && !rail.visible && app.railLift > 0 && app.railLift < 1 && hoverPeek.open },
        { name: "lifted: colRailGlass inset 6 px inside the page (282 x 776 at 12, 12), radius 12, its shadow; the page under it at 6, 6, its full width, resized once and slid there; the pointer resting on it keeps it out", wait: 900,
          expect: () => { const b = check.named(peekedRail, "slab"), sh = check.named(peekedRail, "slabShadow"), p = view.mapToItem(app.contentItem, 0, 0);
              probe.report("     overlay " + [peekedRail.x, peekedRail.y, peekedRail.width, peekedRail.height].join(" ") + ", page " + [p.x, p.y, view.width].join(" ")
                           + ", width changes " + check.widths + ", slide frames " + check.midShifts);
              return hoverPeek.open && peekedRail.x === 12 && peekedRail.y === 12 && peekedRail.width === 282 && peekedRail.height === 776 && b.radius === 12
                  && check.like(b.color, Theme.colRailGlass) && sh !== null && sh.opacity === 1 && app.pageShift === 0 && p.x === 6 && p.y === 6
                  && view.width === 1268 && check.widths === 1 && check.midShifts >= 3 && app.railSlide === 1 && !app.railMoving } },
        { name: "the pointer off it, on the page: it tucks away", wait: 1000, act: () => probe.pointer(700, 400),
          expect: () => !hoverPeek.out && !peekedRail.visible && peekedRail.slide === 0 },
        // 2026-10-02: after a restart the lifted rail showed only the current page; the others' rows were there (their tips
        // answered) but drawn at opacity 0
        { name: "(pages added while it is tucked away)", wait: 600,
          act: () => { for (const q of ["a", "b", "c", "d"]) session.addPage(session.current.thread, check.local("/plain?" + q), "") },
          expect: () => !peekedRail.visible },
        { name: "the window's left edge brings it back, lifted", wait: 800, act: () => { probe.pointer(60, 400); probe.pointer(10, 400) },
          expect: () => hoverPeek.open && peekedRail.visible && peekedRail.slide === 1 && peekedRail.x === 12 },
        { name: "every row of the lifted rail is drawn (none left at opacity 0 by its fade-in)",
          expect: () => { const list = peekedRail.listView, faint = [];
              for (let i = 0; i < list.count; i++) { const it = list.itemAtIndex(i); if (it && it.opacity < 0.99) faint.push(it.type + ":" + (it.title || it.key) + "=" + it.opacity.toFixed(2)) }
              probe.report("     rows " + list.count + ", faint " + faint.length + (faint.length ? " (" + faint.slice(0, 6).join(", ") + ")" : ""));
              return list.count > 4 && faint.length === 0 } },
        { name: "the pin glyph docks it: it settles on the slab's place as the page slides back, the page narrows once beside it and the pinned rail takes over", wait: 1400,
          act: () => { check.midShifts = 0; check.clickAt(peekedRail.foldButton) },
          expect: () => { const p = view.mapToItem(app.contentItem, 0, 0);
              probe.report("     page " + [p.x, view.width].join(" ") + ", width changes " + check.widths + ", slide frames " + check.midShifts);
              return app.railPinned && rail.visible && !peekedRail.visible && !hoverPeek.open && app.railLift === 0 && app.railFill === 0
                  && p.x === 300 && view.width === 974 && check.widths === 2 && check.midShifts >= 3 && !app.railMoving } },
        { name: "Ctrl+B with the pointer on the page: it lifts, then tucks away", focus: "document.activeElement.blur()", wait: 1600,
          act: () => { probe.pointer(700, 400); probe.press(Qt.Key_B, ctrl) },
          expect: () => !app.railPinned && !hoverPeek.out && !peekedRail.visible && app.railSlide === 1 && app.railLift === 1 && !app.railMoving },
        { name: "Ctrl+B pins it again", focus: "document.activeElement.blur()", wait: 1600, key: Qt.Key_B, mods: ctrl,
          expect: () => app.railPinned && rail.visible && !peekedRail.visible && !app.railMoving },
        { name: "the keys and the pointer on the page: the quiet rail, everything but the current row (and the faces) at 50 %, on SlowEffects", wait: 700,
          act: () => { app.focusPage(); probe.pointer(700, 420); probe.pointer(701, 420) },
          expect: () => { const cur = check.rowItem("p:" + session.currentPage), other = check.rowItem("t:" + session.current.thread);
              return app.quietRail && rail.quiet && rail.dim === 0.5 && cur.quietDim === 1 && (other === null || other.quietDim === 0.5)
                  && rail.addressField.dim === 0.5 && rail.topRow.opacity === 0.5 } },
        { name: "the quiet rail at rest draws nothing: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 && rail.quiet } },
        { name: "the pointer within 48 px of the rail wakes it", wait: 700, act: () => probe.pointer(330, 420),
          expect: () => !app.quietRail && rail.dim === 1 },
        { name: "back on the page it is quiet again", wait: 700, act: () => probe.pointer(700, 420), expect: () => app.quietRail && rail.dim === 0.5 },
        { name: "an ask in the card wakes it, and its answer lets it go quiet", wait: 700, act: () => view.asks = [check.standInAsk()],
          expect: () => !app.quietRail && rail.dim === 1 },
        { name: "(the ask gone)", wait: 700, act: () => view.asks = [], expect: () => app.quietRail && rail.dim === 0.5 },
        { name: "the keys in the rail (F6, the address card) wake it", key: Qt.Key_F6, wait: 700, expect: () => address.editing && !app.quietRail && rail.dim === 1 },
        { name: "(Esc: the keys back on the page, quiet)", key: Qt.Key_Escape, wait: 900, expect: () => !address.editing && app.quietRail },
        { name: "the pointer on the Settings button: after 600 ms its tip under it (the button is at the rail's top), \"Settings\" and \"Ctrl+,\"", wait: 1000,
          act: () => { const b = rail.settingsButton, p = b.mapToItem(app.contentItem, b.width / 2, b.height / 2); probe.pointer(p.x, p.y) },
          expect: () => rail.tip.visible && rail.tip.parent === rail.settingsButton && rail.tip.y > 0 && rail.tip.contentItem.children[0].text === "Settings"
              && rail.tip.contentItem.children[1].text === "Ctrl+," },
        { name: "the Settings button, at the right end of the rail's top row, opens Settings as Ctrl+, does", wait: 1500,
          act: () => { check.liftPage = session.currentPage; check.clickAt(rail.settingsButton) },
          expect: () => { const b = rail.settingsButton.mapToItem(rail, 0, 0);
              return app.ownKind === "settings" && b.y < 40 && b.x + rail.settingsButton.width >= rail.width - 12 } },
        { name: "(Settings closed, back on the plain page)", wait: 1000, act: () => { app.closePage(session.currentPage); app.show(check.liftPage) },
          expect: () => app.ownKind === "" && session.currentPage === check.liftPage },
    ]
    property int widths: 0
    property int midShifts: 0
    property string liftPage: ""
    property Connections viewWidths: Connections { target: check.view; function onWidthChanged() { check.widths++ } }
    property Connections pageShifts: Connections {
        target: check.app
        function onPageShiftChanged() { if (check.app.pageShift > 1 && check.app.pageShift < check.app.railWidth - check.app.inset - 1) check.midShifts++ }
    }
    // colours equal within a step of 8 bits (bindings mix them in floating point)
    function like(a, b) {
        const x = Qt.color(a), y = Qt.color(b), ok = [x.r - y.r, x.g - y.g, x.b - y.b, x.a - y.a].every(d => Math.abs(d) < 1.5 / 255);
        if (!ok)
            probe.report("     " + x + " is not " + y);
        return ok;
    }
    // a click on an item's centre through the window system
    function clickAt(item) {
        const p = item.mapToItem(app.contentItem, item.width / 2, item.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }

    // The section strip under the page (PLAN.md 3.19), on fixture pages with headings under a sticky header, a hidden and
    // an empty one, on a dark ground and with one heading: the sections read in the browser's script world, the segments
    // by their scroll ranges, the current one filling as you read, the pointer near the foot raising it (the page's ground
    // and tones, the names, a grab hand), a drag scrubbing the page, a click going to a section, the pointer away sinking
    // it, folded, and none on one heading, on Settings or in a private window.
    readonly property var stripSteps: [
        { group: "strip" },
        check.server,
        { name: "(the strip page, pinned, at its top, the pointer away from its foot)", wait: 2500,
          act: () => { app.sectionStripOn = true; app.setFold(true); probe.pointer(700, 300); app.go(check.local("/strip"), "navigate") },
          expect: () => view.title === "strip" && !view.loading && view.sections !== null && view.readsSections },
        { name: "its sections, read in the browser's script world as Recall reads headings: the sticky header's, the hidden and the empty heading left out",
          expect: () => { const n = view.sections.list.map(h => h.name); probe.report("     " + JSON.stringify(n)); return n.join("|") === "Strip fixture|Second|Third|Fourth" } },
        { name: "one segment each, sized by the scroll range in which it is the one you are in, 6 px apart, a 2 px line in the 6 px gap under the page",
          expect: () => { const st = app.windowStrip, g = st.segments, b = st.boxes, avail = st.trackW - 6 * (g.length - 1);
              probe.report("     from " + g.map(x => Math.round(x.from)).join(" ") + ", widths " + b.map(x => Math.round(x.w)).join(" ") + ", max " + st.maxScroll);
              return st.visible && g.length === 4 && [0, 1160, 2440, 3680].every((v, i) => Math.abs(g[i].from - v) <= 1) && Math.abs(st.maxScroll - 5052) <= 1
                  && g.every((x, i) => Math.abs(b[i].w - avail * (x.to - x.from) / st.maxScroll) < 0.01 && (i === 0 || Math.abs(b[i].x - b[i - 1].x - b[i - 1].w - 6) < 0.01))
                  && st.trackY === st.height + 2 && st.trackX === 6 && check.named(st, "segment:0").height === 2 } },
        { name: "at the top: the first is the one you are in, nothing filled yet; at rest onSurface 9 % ahead, 18 % past, the fill primary 55 %",
          expect: () => { const st = app.windowStrip;
              return st.at.index === 0 && st.at.fill === 0 && check.like(st.ahead, Theme.stripAhead) && check.like(st.past, Theme.stripPast) && check.like(st.fill, Theme.stripFill) } },
        { name: "read 1800 px down: the second, half filled", wait: 500, act: () => view.runJavaScript("scrollTo(0, 1800)"),
          expect: () => app.windowStrip.at.index === 1 && Math.abs(app.windowStrip.at.fill - 0.5) < 0.01 },
        { name: "the pointer near the page's foot: it rises 16 px into it over the page's own ground (white), in the page's tones, the names above, the current one Medium",
          wait: 900, act: () => probe.pointer(700, 774),
          expect: () => { const st = app.windowStrip, cur = check.named(st, "segment:1").children[2], other = check.named(st, "segment:0").children[2];
              return st.near && st.rise === 1 && st.trackY === st.height - 14 && st.trackX === 28 && check.like(st.pageGround, "#ffffff") && !st.dark
                  && check.like(st.ahead, Theme.stripAheadLight) && check.like(st.past, Theme.stripPastLight) && check.like(st.fill, Theme.stripFillLight)
                  && cur.text === "Second" && check.like(cur.color, Theme.outlineVariant) && cur.weight === Font.Medium
                  && check.like(other.color, Theme.outline) && other.visible && check.named(st, "stripThumb").width === 8 } },
        { name: "over it the pointer is a grab hand", wait: 300,
          act: () => { const t = check.named(app.windowStrip, "stripThumb"), p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2); probe.pointer(p.x, p.y) },
          expect: () => { const band = check.named(app.windowStrip, "stripBand"); return band.enabled && band.containsMouse && band.cursorShape === Qt.OpenHandCursor } },
        { name: "grabbed (a closed hand, an 11 px thumb) and dragged 200 px, it scrubs the page; let go, the page stays where the drag left it", wait: 700,
          act: () => {
              const st = app.windowStrip, t = check.named(st, "stripThumb"), p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2);
              const at = t.mapToItem(st, t.width / 2, 0).x;
              check.expected = st.scrollAt(at + 200);
              probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton);
              for (let d = 20; d <= 200; d += 20)
                  probe.pointer(p.x + d, p.y, Qt.LeftButton);
              const band = check.named(st, "stripBand");
              check.held = st.dragging && band.cursorShape === Qt.ClosedHandCursor && Math.abs(st.readY - check.expected) <= 1;
              probe.pointer(p.x + 200, p.y);
          },
          expect: () => { probe.report("     to " + check.expected); return check.held && !app.windowStrip.dragging && app.windowStrip.near },
          page: "scrollY", pageExpect: v => Math.abs(v - check.expected) <= 1 },
        { name: "a click on the last segment goes to its section: its heading on the reading line, the one Recall says you are in", wait: 600,
          act: () => check.clickAt(check.named(app.windowStrip, "segment:3")),
          expect: () => app.windowStrip.at.index === 3,
          page: Recall.capture, world: WebEngineScript.ApplicationWorld, pageExpect: v => { const a = JSON.parse(v); return a.heading === "Fourth" && Math.abs(a.y - 3680) <= 1 } },
        { name: "the pointer away: it sinks back to the hairline", wait: 900, act: () => probe.pointer(700, 300),
          expect: () => !app.windowStrip.near && app.windowStrip.rise === 0 && app.windowStrip.trackY === app.windowStrip.height + 2 },
        { name: "the pointer in the gap under the page brings it up too", wait: 900, act: () => probe.pointer(700, 797), expect: () => app.windowStrip.near },
        { name: "folded: the strip spans the page at its full width", wait: 1600, act: () => { probe.pointer(700, 300); app.railPinned = false },
          expect: () => !app.railPinned && !app.railMoving && !hoverPeek.out && app.windowStrip.visible && app.windowStrip.width === 1268 && !app.windowStrip.near },
        { name: "(pinned again)", wait: 1600, act: () => app.railPinned = true, expect: () => app.railPinned && !app.railMoving },
        { name: "the strip at rest draws nothing: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "a dark page: risen, its own ground and the dark tones, the current name in onSurfaceVariant", wait: 3000,
          act: () => { probe.pointer(700, 300); app.go(check.local("/strip-dark"), "navigate"); check.later(() => probe.pointer(700, 774)) },
          expect: () => { const st = app.windowStrip, cur = check.named(st, "segment:0").children[2];
              return view.title === "strip dark" && st.near && st.dark && check.like(st.pageGround, "#111111") && check.like(st.ahead, Theme.stripAhead)
                  && check.like(st.fill, Theme.stripFill) && check.like(st.accent, Theme.primary) && check.like(cur.color, Theme.onSurfaceVariant) } },
        { name: "a page with one heading has no strip", wait: 2500, act: () => { probe.pointer(700, 300); app.go(check.local("/strip-one"), "navigate") },
          expect: () => view.title === "strip one" && view.sections !== null && view.sections.list.length === 1 && !app.windowStrip.visible },
        { name: "Settings has none", wait: 1500, act: () => { check.liftPage = session.currentPage; app.act("settings") },
          expect: () => app.ownKind === "settings" && app.windowStrip.view === null && !app.windowStrip.visible },
        { name: "(Settings closed, back on the strip page)", wait: 2500,
          act: () => { app.closePage(session.currentPage); app.show(check.liftPage); app.go(check.local("/strip"), "navigate") },
          expect: () => app.ownKind === "" && view.title === "strip" && app.windowStrip.visible },
        { name: "a private window's page reads no sections and has no strip", wait: 3000,
          act: () => { const w = app.newPrivateWindow(app.windowState()); check.stripWindow = w; w.go(check.local("/strip"), "new", "", "strip") },
          expect: () => { const w = check.stripWindow, v = w ? w.currentView : null;
              return !!v && v.title === "strip" && !v.loading && !v.readsSections && v.sections === null && w.windowStrip.view === null && !w.windowStrip.visible } },
        { name: "(the private window closed)", wait: 1500, act: () => { check.stripWindow.close(); probe.back(app) }, expect: () => app.privateWindows.length === 0 },
    ]
    property var stripWindow: null

    readonly property var idleSteps: [
        { group: "idle" },
        check.server,
        { name: "(a plain page, settled, the pointer out of the window)", wait: 2000,
          act: () => { probe.leave(); app.go(check.local("/plain"), "navigate") }, expect: () => view.title === "plain" && !view.loading && app.railPinned },
        { name: "pinned, nothing changing: no frame in 2 s", wait: 2000, focus: "document.activeElement.blur()", act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(folded)", wait: 1500, act: () => app.railPinned = false, expect: () => !app.railPinned && !app.railMoving },
        { name: "folded, nothing changing: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(pinned again; an http page with a password field, where the password poll runs)", wait: 2000,
          act: () => { app.railPinned = true; app.go(check.served("plain", "/login"), "navigate") }, expect: () => view.title === "login" && app.railPinned },
        { name: "the poll draws nothing either: no frame in 2 s", wait: 2000, focus: "document.activeElement.blur()", act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(Ctrl+L: the address card out)", focus: "document.activeElement.blur()", key: Qt.Key_L, mods: ctrl, wait: 900, expect: () => address.editing },
        { name: "(Esc: back in its slot)", key: Qt.Key_Escape, wait: 1000, expect: () => !address.out },
        { name: "the address card out and back: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(a page joins the thread in the background: a row grows in the rail)", wait: 1000,
          act: () => { check.other = session.addPage(session.current.thread, check.local("/plain"), "") }, expect: () => !!check.rowOf("p:" + check.other) },
        { name: "a row joined: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(that page closed)", wait: 800, act: () => app.closePage(check.other), expect: () => !session.pages[check.other] },
        { name: "(an ask in the card)", wait: 800, act: () => view.asks = [check.standInAsk()], expect: () => !!view.ask && card() > 40 },
        { name: "an ask waiting in the card: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(the ask gone; the site panel open, its count polled every second)", focus: "document.activeElement.blur()", key: Qt.Key_I, mods: ctrl, wait: 1000,
          act: () => view.asks = [], expect: () => site.open && !view.ask },
        { name: "the site panel open: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(Esc; a load that gets no reply within 2 s: the failure page)", wait: 3500,
          act: () => { probe.press(Qt.Key_Escape, 0); view.replyLimit = 2000; app.go(check.served("slow", "/slow"), "navigate") },
          expect: () => !site.open && view.failure && view.failure.kind === "noReply" && !view.loading },
        { name: "the failure page: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(back on the page; folded, the overlay out under the resting pointer)", wait: 2500,
          act: () => { view.replyLimit = 30000; view.leave(false); app.railPinned = false; check.later(() => { probe.pointer(60, 400); probe.pointer(10, 400); probe.pointer(150, 400) }) },
          expect: () => !view.failure && hoverPeek.open && peekedRail.slide === 1 },
        { name: "the overlay out, the pointer resting on it: no frame in 2 s", wait: 2000, act: () => check.frames = 0,
          expect: () => { check.probe.report("     frames: " + check.frames); return check.frames === 0 } },
        { name: "(the pointer off it; pinned again)", wait: 1500, act: () => { probe.pointer(700, 400); probe.leave(); app.railPinned = true },
          expect: () => app.railPinned && !hoverPeek.out },
    ]
    // Fixture for the asks: a button over the page's top-left that runs `act`, and what each ask calls;
    // `log` keeps the page's answers.
    readonly property string asksPage: "<!doctype html><title>asks</title>"
        + "<button id=b style='position:fixed;left:0;top:0;width:400px;height:300px' onclick='act()'>act</button><script>"
        + "window.log = []; window.act = () => {}; const note = s => log.push(s);"
        + "window.mic = () => navigator.mediaDevices.getUserMedia({ audio: true }).then(() => note('mic ok'), e => note('mic ' + e.name));"
        + "window.notify = () => Notification.requestPermission().then(r => note('notify ' + r));"
        + "window.where = () => navigator.geolocation.getCurrentPosition(() => note('where ok'), e => note('where ' + e.code));"
        + "window.share = () => navigator.mediaDevices.getDisplayMedia({ video: true }).then(() => note('share ok'), e => note('share ' + e.name));"
        + "window.passkey = () => navigator.credentials.create({ publicKey: { rp: { name: 'check' }, challenge: new Uint8Array(16),"
        + " user: { id: new Uint8Array(8), name: 'abdul', displayName: 'abdul' }, pubKeyCredParams: [{ type: 'public-key', alg: -7 }], timeout: 20000 } })"
        + ".then(() => note('passkey ok'), e => note('passkey ' + e.name));"
        + "</script>"
    function local(path) { return "http://127.0.0.1:" + port + path }
    // The site panel's page: an ad from ads.test, a banner, and what it finds stored before it stores its own
    // (a cookie, local storage, IndexedDB, Cache Storage); `log` has its mousedowns and pop-ups.
    readonly property string sitePage: "<!doctype html><title>site</title><img id=ad><div class=check-ad id=banner>banner</div><script>"
        + "window.log = []; addEventListener('mousedown', () => log.push('down'));"
        + "ad.src = 'http://ads.test:' + location.port + '/ad.png';"
        + "window.tryOpen = () => log.push(window.open('/plain') ? 'opened' : 'refused');"
        + "(async () => { const idb = (await indexedDB.databases()).map(d => d.name).join('+'), keys = (await caches.keys()).join('+');"
        + " window.report = JSON.stringify([localStorage.getItem('k'), document.cookie, idb, keys]);"
        + " localStorage.setItem('k', 'v'); document.cookie = 'c=1; path=/';"
        + " await new Promise(done => { const r = indexedDB.open('db1'); r.onupgradeneeded = () => r.result.createObjectStore('o'); r.onsuccess = () => { r.result.close(); done() } });"
        + " await caches.open('c1'); window.stored = true })()"
        + "</script>"
    // the site panel's click target `name` (SitePanel.target), clicked through the window system
    function clickSite(name) {
        const t = (site.where === "rail" ? rail : peekedRail).sitePanel.target(name);
        if (!t)
            throw new Error("the site panel shows no " + name);
        const p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    // the visible item named `name` under `item`, or null
    function named(item, name) {
        if (item.objectName === name && item.visible)
            return item;
        for (const c of item.children) {
            const f = c.visible ? named(c, name) : null;
            if (f)
                return f;
        }
        return null;
    }
    // the visible item named `name` under `item`, clicked
    function clickNamed(item, name) {
        const t = named(item, name);
        if (!t)
            throw new Error("nothing named " + name);
        const p = t.mapToItem(app.contentItem, t.width / 2, t.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    // the rail card's favicon slot
    function clickFavicon() {
        const r = shownRail().addressRect(app.contentItem), x = r.x + 18, y = r.y + 20;
        probe.pointer(x, y); probe.pointer(x, y, Qt.LeftButton); probe.pointer(x, y);
    }
    function siteKinds() { return site.rows.map(r => r.kind + (r.kind === "choice" ? ":" + r.key : "")) }
    property bool keyed: false
    property string copied: ""
    property Connections copies: Connections { target: check.site; function onCopyRequested(text) { check.copied = text } }
    // runs `fn` 250 ms into a step, once what the step started has drawn (a row laid out, a page's answer)
    property var laterFn: null
    property Timer laterTimer: Timer { interval: 250; onTriggered: { const f = check.laterFn; check.laterFn = null; try { f() } catch (e) { check.probe.report("     " + e) } } }
    function later(fn) { laterFn = fn; laterTimer.restart() }
    function origin() { return Asks.originOf(String(view.url)) }
    // the button, where it lies whether the rail is pinned (page from x 300) or folded (from 6); or at `x`
    function click(x) { const at = x ?? 350; probe.pointer(at, 150); probe.pointer(at, 150, Qt.LeftButton); probe.pointer(at, 150) }
    // the bell, first at the card's right (12 px in, 20 px wide), level with the host
    function clickBell() {
        const b = check.named(shownRail().addressField, "bellGlyph"), q = b.mapToItem(app.contentItem, b.width / 2, b.height / 2), x = q.x, y = q.y;
        probe.pointer(x, y); probe.pointer(x, y, Qt.LeftButton); probe.pointer(x, y);
    }
    // the page's ask: in its sheet, but the "Save password?" line, which stays in the card
    function section() { return view && view.ask && view.ask.kind === "password" ? shownRail().addressField.askSection : app.askSheet.section }
    // the page's ask sheet: out of the page's edge with an ask, back in without
    function sheetOut() { return app.askSheet.ask !== null && app.askSheet.slide > 0.99 }
    function sheetIn() { return app.askSheet.slide < 0.01 && !app.askSheet.visible }
    // the rail the address card shows in: the pinned one, or folded the overlay
    function shownRail() { return app.railPinned ? rail : peekedRail }
    // the find card's "Also in this thread" row `i`
    function clickHit(i) {
        const it = shownRail().findCard.hitRows.itemAt(i), p = it.mapToItem(app.contentItem, it.width / 2, it.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    // downloads: the newest record, the one being checked, and the rail's rows
    property string dl: ""
    property var twice: []
    property string dlPage: ""
    property string tlsPage: ""
    property string path: ""
    property real bytes: 0
    function lastDownload() { return session.downloads[session.downloads.length - 1] ?? null }
    function record() { return session.downloadById(check.dl) }
    function rowOf(key) {
        const m = rail.listView.model;
        for (let i = 0; i < m.count; i++)
            if (m.get(i).key === key)
                return m.get(i);
        return null;
    }
    function rowItem(key) {
        const m = rail.listView.model;
        for (let i = 0; i < m.count; i++)
            if (m.get(i).key === key) {
                rail.reveal(i);
                return rail.listView.itemAtIndex(i);
            }
        return null;
    }
    function rowCentre(key) { const it = rowItem(key); return it.mapToItem(app.contentItem, it.width / 2, it.height / 2) }
    // the pointer on a row's first line; a click there; a click on its text action `name`
    function hoverRow(key) { const it = rowItem(key), p = it.mapToItem(app.contentItem, it.width / 2, 12); probe.pointer(p.x, p.y) }
    function clickRow(key) {
        const it = rowItem(key), p = it.mapToItem(app.contentItem, it.width / 2, 12);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    function clickAction(key, name) {
        const a = rail.rowAction(key, name);
        if (!a)
            return;
        const p = a.mapToItem(app.contentItem, a.width / 2, a.height / 2);
        probe.pointer(p.x, p.y); probe.pointer(p.x, p.y, Qt.LeftButton); probe.pointer(p.x, p.y);
    }
    function standInAsk() {
        return { id: 97, kind: "permission", origin: check.origin(), host: "127.0.0.1:" + check.port, types: ["microphone"], requests: [] };
    }
    function askText() { return section().model ? section().model.lines[0].text : "" }
    // lower-case letters, typed through the window system
    function type(text) {
        for (const c of text)
            probe.press(Qt.Key_A + c.charCodeAt(0) - 97, 0, c);
    }
    property int tlsPort: 0
    property int closed: 0             // a port nothing listens on
    property real pid: 0
    property string sibling: ""        // the page the opener opened, which shares its process
    property string shown: ""          // the page on screen when the restore checks start
    property string shownTitle: ""
    property string said: ""
    property string asker: ""
    property string leaver: ""
    property string alwaysPage: ""
    property string outPage: ""        // the page a link from the Always page opened
    property string opener: ""
    property string other: ""          // a page of its own thread, to look away from a page
    property var popupWin: null
    property int rows: 0
    property bool hidden: false
    property var files: []
    property var findPages: []          // the find thread: on screen, live, frozen, unloaded
    // the card's second line
    function stateText() { return rail.addressField.stateLine }
    // A fixture page: `title`, a button over the page's top-left that runs `act`, `log` for what the page saw,
    // and `script`.
    function fixturePage(title, script) {
        return "<!doctype html><title>" + title + "</title>"
            + "<button style='position:fixed;left:0;top:0;width:400px;height:300px' onclick='act()'>act</button>"
            + "<script>window.log = []; window.act = () => {};" + script + "</script>";
    }
    // a file input over the top-left (one file) and one beside it (multiple)
    readonly property string uploadPage: "<!doctype html><title>upload</title>"
        + "<input type=file id=one style='position:fixed;left:0;top:0;width:400px;height:300px'>"
        + "<input type=file id=many multiple style='position:fixed;left:400px;top:0;width:400px;height:300px'>"
        + "<script>window.log = []; for (const i of [one, many]) i.onchange = () => log.push(i.id + ' ' + [...i.files].map(f => f.name).join('+'))</script>"
    readonly property string fullPage: check.fixturePage("full",
        "window.act = () => document.body.requestFullscreen().then(() => log.push('in'), e => log.push('refused ' + e.name));"
        + "document.addEventListener('fullscreenchange', () => log.push(document.fullscreenElement ? 'entered' : 'left'));"
        + "window.mic = () => navigator.mediaDevices.getUserMedia({ audio: true }).then(() => log.push('mic ok'), e => log.push('mic ' + e.name));")
    // a 6000 px page that styles its own scrollbar, with an inner scroll area and a full-width fixed probe
    function long(standards) {
        return "data:text/html," + encodeURIComponent((standards ? "<!doctype html>" : "") + "<title>long</title>"
            + "<style>html{scrollbar-color:red blue;scrollbar-width:auto}::-webkit-scrollbar{width:20px;background:red}body{margin:0}</style>"
            + "<div id=fixed style='position:fixed;left:0;right:0;top:0;height:1px'></div>"
            + "<div id=inner style='height:100px;overflow:auto'><div style='height:400px'></div></div>"
            + "<div style='height:6000px'></div>"
            + "<script>window.clicks = []; addEventListener('mousedown', e => clicks.push(e.clientX))</script>")
    }
    property real expected: 0
    property bool held: false
    property point rowAt                // where a suggestion row of the address card comes
    // the rail's rebuilds, and the window's frames (QQuickWindow::frameSwapped)
    property int rebuilds: 0
    property Connections railRebuilds: Connections { target: check.rail; function onRowsChanged() { check.rebuilds++ } }
    property int frames: 0
    property Connections frameCount: Connections { target: check.app; function onFrameSwapped() { check.frames++ } }

    property int port: 0
    // the fixture server, started once: by the loading checks, or by a group's setup
    function serveFixtures() {
        if (port)
            return;
        const pages = { "/plain": "<title>plain</title><p>plain page",
            "/login": "<title>login</title><form><input id=user><input id=pw type=password></form>",
            "/asks": check.asksPage, "/auth": { body: "<title>signed in</title>", auth: "admin:secret" },
            "/leave": "<title>leave</title><input id=f><script>onbeforeunload = e => { e.preventDefault(); e.returnValue = '' }</script>",
            "/dialogs": check.fixturePage("dialogs", ""), "/upload": check.uploadPage, "/full": check.fullPage,
            "/drop": "<!doctype html><title>drop</title><div id=zone style='position:fixed;left:0;top:0;width:400px;height:300px'>zone</div>"
                + "<script>window.log = []; zone.ondragover = e => e.preventDefault();"
                + "zone.ondrop = e => { e.preventDefault(); log.push('zone ' + [...e.dataTransfer.files].map(f => f.name).join('+')) }</script>",
            "/popup-opener": check.fixturePage("opener", "addEventListener('message', e => log.push('message ' + e.data));"
                + "window.sized = () => window.open('/popup', 'signin', 'width=480,height=560'); window.plain = () => window.open('/plain');"
                + "const idp = p => window.open('http://localhost:' + location.port + p, 'signin', 'width=480,height=560');"
                + "window.coop = () => idp('/coop-idp'); window.coopStay = () => idp('/coop-stay'); window.coopField = () => idp('/coop-idp-field');"
                + "window.code = () => window.open('/popup-code', 'signin', 'width=480,height=560');"),
            "/popup": "<title>sign in</title><p>sign in<script>window.hasOpener = !!window.opener;"
                + "window.done = () => { opener.postMessage('signed in', '*'); close() }</script>",
            // a sign-in's second step: a one-time code's field (the notch offers a code from your phone for it)
            "/popup-code": "<title>code</title><p>check your phone<input id=otp autocomplete=one-time-code>",
            // a sign-in from another app, as gcloud's: an OAuth authorize page (any query) whose consent goes to the
            // redirect_uri on localhost, which answers with a 302 on to another host's "You are now authenticated"; a
            // denial comes back with error=; a link that redirects into the authorize page
            "/oauth/authorize?*": "<title>authorize</title><p>choose an account<script>const r = new URLSearchParams(location.search).get('redirect_uri');"
                + "window.consent = () => location.href = r + 'oauth/callback?code=abc&state=s'; window.deny = () => location.href = r + 'oauth/callback?error=access_denied'</script>",
            "/oauth/callback?*": { body: "", status: "302 Found", headers: "Location: http://done.test:{port}/oauth/done" },
            "/oauth/done": "<title>authenticated</title><p>You are now authenticated",
            // pages from an app at addresses that name no sign-in: one asking for a password, one whose password field
            // a script draws 800 ms after the load, one with no password field at all
            "/welcome-pw": "<title>welcome</title><p>Sign in to continue<form><input name=email><input type=password name=pw></form>",
            "/welcome-late": "<title>welcome</title><p>Loading<script>setTimeout(() => document.body.insertAdjacentHTML('beforeend',"
                + " '<form><input name=email><input type=password name=pw></form>'), 800)</script>",
            "/welcome-plain": "<title>welcome</title><p>Thanks for installing. Your email: <input name=email>",
            "/to-signin": { body: "", status: "302 Found",
                            headers: "Location: http://127.0.0.1:{port}/oauth/authorize?response_type=code&client_id=check&redirect_uri=http%3A%2F%2Flocalhost%3A{port}%2F" },
            // a sign-in on another origin whose Cross-Origin-Opener-Policy cuts the popup off from its opener (both
            // loopback origins are secure contexts, so the header counts), then back on the opener's site with a page
            // that never calls window.close(); one that stays; one that comes back to a form
            "/coop-idp": { body: "<title>idp</title><script>setTimeout(() => location.href = 'http://127.0.0.1:' + location.port + '/coop-back', 300)</script>",
                           headers: "Cross-Origin-Opener-Policy: same-origin" },
            "/coop-stay": { body: "<title>idp stays</title><p>choose an account", headers: "Cross-Origin-Opener-Policy: same-origin" },
            "/coop-idp-field": { body: "<title>idp</title><script>setTimeout(() => location.href = 'http://127.0.0.1:' + location.port + '/coop-field', 300)</script>",
                                 headers: "Cross-Origin-Opener-Policy: same-origin" },
            "/coop-back": "<title>back</title><p>signed in<script>window.cutOff = window.opener === null</script>",
            "/coop-field": "<title>back with a form</title><p>one more step<input id=name>",
            // a sign-in popup with a link that asks for a new window (a privacy policy)
            "/popup-link": "<title>sign in</title><a href=/plain target=_blank style='position:fixed;left:0;top:0;width:300px;height:200px;display:block'>policy</a>",
            "/find": "<title>find</title><p>CSIPHY0 lanes on csiphy-3ph, Csiphy</p><input id=field>",
            "/find-other": "<title>find other</title><p>csiphy</p><div style='height:3000px'></div><p>CSIPHY lanes</p>",
            // Where next (Ctrl+L in the notch): the links it skips and the two it keeps, the one in view first
            "/where": "<!doctype html><title>where</title><header><a href=/lantern>Site header link</a></header><nav><a href=/brook>Navigation link</a></nav>"
                + "<aside><a href=/brook-two>Sidebar link</a></aside><main><p><a href='#top'>Back to the top</a> <a href='javascript:void 0'>script link</a>"
                + " <a href=/orchard><svg width=16 height=16></svg></a> <a href=/harbour>[PATCH v3] camss: honour data-lanes</a> <a href=/meadow>v2</a></p>"
                + "<div style='height:3000px'></div><p><a href='/plain?far'>a link far down the page</a></p></main><footer><a href='/lantern?foot'>Footer link</a></footer>",
            "/site": check.sitePage, "/site-other": "<title>site other</title><p>another page of the site",
            "/post": "<title>post</title><form id=f method=post action=/posted><input name=a value=b></form>", "/posted": "<title>posted</title>",
            "/mixed": "<title>mixed</title><img id=i><script>i.src = 'http://plain.test:' + location.hash.slice(3) + '/plain'</script>" };
        // a link's page from another app (the links group), at several addresses
        for (const n of ["", "-two", "-three", "-four", "-five", "-six"])
            pages["/peek" + n] = check.peekHtml;
        // several windows (PLAN.md 3.17): pages whose titles no other group uses, and one that moves every frame
        for (const [path, title] of [["/harbour", "harbour lights"], ["/lantern", "lantern notes"], ["/meadow", "meadow map"],
                                     ["/orchard", "orchard walk"], ["/brook", "brook one"], ["/brook-two", "brook two"]])
            pages[path] = "<title>" + title + "</title><p>" + title;
        // the private window (PLAN.md 3.14): a link at the top-left to Ctrl+click, and a page that reports the cookies
        // it found and sets one named after its fragment
        pages["/hush"] = "<title>hush one</title><a href=/hush-two style='position:fixed;left:0;top:0;width:300px;height:120px;display:block'>next</a>";
        pages["/hush-two"] = "<title>hush two</title><p>the second page";
        pages["/cookie"] = "<title>cookie</title><script>window.before = document.cookie; document.cookie = location.hash.slice(1) + '=1; path=/'</script>";
        pages["/tall"] = "<title>tall</title>" + "<p>a line of a tall page, to scroll</p>".repeat(600)
        pages["/icon"] = "<title>icon</title><link rel=icon href='/fav.svg'><p>a page with its own favicon"
        pages["/fav.svg"] = { type: "image/svg+xml", body: "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16' fill='#c33'/></svg>" }
        pages["/anim"] = "<title>anim</title><div id=d style='width:100px;height:100px;background:#c33'></div>"
            + "<script>window.n = 0; (function f() { n++; d.style.transform = 'translateX(' + (n % 200) + 'px)'; requestAnimationFrame(f) })()</script>";
        pages["/sheet.pdf"] = { body: check.pdf, type: "application/pdf" };
        // recall (PLAN.md 3.7): headings under a sticky header (with room above them that localStorage can add), no
        // headings, and 2000 headings over 600 000 px
        pages["/recall-h"] = "<!doctype html><title>recall headings</title><style>body{margin:0}h1,h2,h3{margin:0;height:40px}.gap{height:1500px}"
            + "header{position:sticky;top:0;height:40px;background:#eee}</style><header><h1>Site header</h1></header><div id=shift></div>"
            + "<h1>Recall fixture</h1><div class=gap></div><h2>Changes in v3</h2><div class=gap></div><h3>0x4E action register</h3>"
            + "<div class=gap></div><h2>Tail</h2><div style='height:3000px'></div><script>shift.style.height = (localStorage.getItem('shift') || 0) + 'px'</script>";
        pages["/recall-one"] = pages["/recall-h"].replace("<title>recall headings</title>", "<title>recall one</title>");
        pages["/recall-two"] = pages["/recall-h"].replace("<title>recall headings</title>", "<title>recall two</title>");
        pages["/recall-plain"] = "<!doctype html><title>recall plain</title><style>body{margin:0}</style><div style='height:10000px'></div>";
        // the section strip (PLAN.md 3.19): headings under a sticky header with a hidden and an empty one, on white; the
        // same on a dark ground; one heading
        pages["/strip"] = "<!doctype html><title>strip</title><style>body{margin:0;background:#fff}h1,h2,h3{margin:0;height:40px}.gap{height:1200px}"
            + "header{position:sticky;top:0;height:40px;background:#eee}</style><header><h1>Site header</h1></header><h1>Strip fixture</h1>"
            + "<div class=gap></div><h2>Second</h2><div class=gap></div><h3 style='display:none'>Hidden</h3><h3></h3><h3>Third</h3>"
            + "<div class=gap></div><h2>Fourth</h2><div style='height:2000px'></div>";
        pages["/strip-dark"] = pages["/strip"].replace("<title>strip</title>", "<title>strip dark</title>").replace("background:#fff", "background:#111;color:#eee");
        pages["/strip-one"] = "<!doctype html><title>strip one</title><style>body{margin:0}</style><h1>Only one</h1><div style='height:5000px'></div>";
        // the browser's own pages (PLAN.md 3.15): text in the page's default font, a 6 px line, a misspelt field, the
        // languages the page is told, an image from a host a list update refuses, and a cookie of localhost read in a
        // frame of it on 127.0.0.1 (a third party there)
        pages["/fonts"] = "<!doctype html><title>fonts</title><span id=s>mmmmmmmmmmiiiiiiiiii</span><p><span id=tiny style='font-size:6px'>tiny</span>"
            + "<p><textarea id=t style='position:fixed;left:0;top:200px;width:400px;height:100px'>helo wrld browser</textarea>"
            + "<script>window.langs = navigator.languages.join()</script>";
        pages["/ads2"] = "<title>ads2</title><img src=/plain><script>const i = new Image(); i.src = 'http://ads2.test:' + location.port + '/x.png'</script>";
        pages["/tp-set"] = "<title>tp set</title><script>document.cookie = 'tp=1; SameSite=None; Secure; path=/'; document.cookie = 'lax=1; path=/';"
            + " window.got = document.cookie</script>";
        pages["/tp-frame"] = "<title>tp frame</title><script>window.seen = null; addEventListener('message', e => window.seen = String(e.data));"
            + " const f = document.createElement('iframe'); f.src = 'http://localhost:' + location.port + '/tp-read'; document.documentElement.appendChild(f)</script>";
        pages["/tp-read"] = "<title>tp read</title><script>parent.postMessage(document.cookie, '*')</script>";
        // passwords (PLAN.md 7): a login form sent to a page, one whose next page goes on by a script, one the site sends
        // by script with no load, the input events a fill makes counted, and a field that is no login field
        const login = (title, action, extra) => "<!doctype html><title>" + title + "</title><form id=f method=post action=" + action + ">"
            + "<input id=user name=login><input id=pw name=password type=password><button>Sign in</button></form><input id=other>"
            + "<script>window.inputs = 0; addEventListener('input', () => inputs++);" + (extra ?? "") + "</script>";
        pages["/pw-login"] = login("login", "/pw-done");
        pages["/pw-done"] = "<title>signed in</title><p>signed in";
        pages["/pw-hop"] = login("hop", "/pw-away");
        pages["/pw-away"] = "<title>away</title><script>location.href = '/plain'</script>";
        pages["/pw-script"] = login("script", "/pw-done", "window.trusted = []; f.onsubmit = e => { e.preventDefault(); trusted.push(e.isTrusted) };");
        pages["/recall-long"] = "<!doctype html><title>recall long</title><style>body{margin:0}h2{margin:0;height:40px}p{margin:0;height:260px}</style>"
            + "<script>for (let i = 1; i <= 2000; i++) document.write('<h2>Section ' + i + '</h2><p>text ' + i + '</p>')</script>";
        // reader view (PLAN.md 3.9): saved pages in LWN's, a news site's and GitHub's markup (tests/fixtures/reader)
        for (const name of ["lwn", "news", "github"])
            pages["/reader-" + name] = probe.savedPage("reader/" + name + ".html");
        // print (PLAN.md 3.16): a coloured band (a background, printed only with Backgrounds On), then three sections, each
        // on a page of its own whatever the paper
        pages["/print-long"] = "<!doctype html><title>print long</title><style>body{margin:0;font:16px sans-serif}.band{height:150px;background:#cc3333}"
            + "section{height:200px;break-after:page}section:last-child{break-after:auto}</style><div class=band></div>"
            + "<section><p>print fixture section 1</p></section><section><p>print fixture section 2</p></section><section><p>print fixture section 3</p></section>";
        port = probe.serve(pages);
    }
    // a sized pop-up from its button, a link, a field, a microphone ask, and room to scroll
    readonly property string peekHtml: "<!doctype html><title>[PATCH v3 2/4] media: qcom: camss: add x1p42100 CSIPHY lane config</title>"
        + "<button style='position:fixed;left:0;top:0;width:400px;height:300px' onclick='act()'>act</button>"
        + "<a id=next href=/plain style='position:fixed;left:410px;top:0;width:60px;height:40px;display:block'>next</a>"
        + "<p>CSIPHY0 on x1p42100 ignored data-lanes; read them from the endpoint, program only the csiphy lanes in use.</p>"
        + "<input id=field><div style='height:6000px'></div><script>window.log = [];"
        + "window.act = () => window.open('/popup', 'signin', 'width=480,height=560');"
        + "window.mic = () => navigator.mediaDevices.getUserMedia({ audio: true }).then(() => log.push('mic ok'), e => log.push('mic ' + e.name));</script>"
    readonly property var server: ({ setup: true, name: "(the fixture server)", wait: 100, act: () => check.serveFixtures(), expect: () => check.port > 0 })
    function served(host, path) { return "http://" + host + ".test:" + port + path }
    function card() { return shownRail().addressRect(app.contentItem).height }
    // the URLs in a view's back/forward list (WebEngineHistoryModel's UrlRole, Qt::UserRole)
    function historyUrls(v) {
        const m = v.history.items, out = [];
        for (let i = 0; i < m.rowCount(); i++)
            out.push(String(m.data(m.index(i, 0), 256)));
        return out;
    }
    // loads started on the current view, in order
    property var starts: []
    property Connections loads: Connections {
        target: check.view
        function onLoadingChanged(request) {
            if (request.status === WebEngineView.LoadStartedStatus)
                check.starts.push(String(request.url));
        }
    }

    // the group names after --check-engine
    readonly property var wanted: Array.prototype.slice.call(Qt.application.arguments, 2)
    readonly property var groupNames: all.filter(s => s.group).map(s => s.group)
    // the wanted groups, each its marker and steps; its setup steps only when a group before it did not run
    readonly property var steps: {
        const out = [];
        let run = false, setup = false, skipped = false;
        for (const s of all) {
            if (s.group) {
                run = wanted.length === 0 || wanted.indexOf(s.group) >= 0;
                setup = skipped;
                skipped = skipped || !run;
                if (run)
                    out.push(s);
            } else if (run && (setup || !s.setup)) {
                out.push(s);
            }
        }
        return out;
    }

    property bool opened: false
    property int at: -1
    property int failures: 0
    property real began: 0
    property var view: app.currentView

    property Timer loaded: Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            const unknown = check.wanted.filter(g => check.groupNames.indexOf(g) < 0);
            if (unknown.length > 0) {
                stop();
                check.probe.report("no group " + unknown.join(", ") + "; the groups: " + check.groupNames.join(" "));
                check.probe.finish(1);
                return;
            }
            // after Main has made the profile: a view made before it would get the default profile
            if (!check.opened && check.app.profile) {
                check.opened = true;
                check.app.go("data:text/html," + encodeURIComponent(check.fixture), "new", "", "keys");
            }
            if (check.at < 0 && check.view && !check.view.loading && check.view.title === "keys") {
                stop();
                check.began = Date.now();
                check.at = 0;
                check.step();
            }
        }
    }
    property Timer settle: Timer { onTriggered: check.verify() }
    property Timer watchdog: Timer {
        interval: 1800000
        running: true
        onTriggered: { check.probe.report("FAIL timed out at step " + check.at); check.probe.finish(1) }
    }


    function step() {
        const s = steps[at];
        if (s.group) {
            check.probe.report("== " + s.group + " at " + Math.round((Date.now() - check.began) / 1000) + " s");
            at++;
            step();
            return;
        }
        const run = () => {
            if (s.key)
                check.probe.press(s.key, s.mods ?? 0, s.text ?? "");
            if (s.act) {
                try {
                    s.act();
                } catch (e) {
                    check.probe.report("     " + e);
                }
            }
            settle.interval = s.wait ?? 600;
            settle.restart();
        };
        if (!s.focus) {
            run();
            return;
        }
        app.focusPage();
        view.runJavaScript(typeof s.focus === "function" ? s.focus() : s.focus, () => run());
    }

    function verify() {
        const s = steps[at];
        const done = (ok, extra) => {
            check.probe.report((ok ? "ok   " : "FAIL ") + s.name + (extra !== undefined ? "  [page: " + extra + "]" : "")
                + (!check.idlePage ? "" : "  [edited page " + state(keysPage) + ", idle page " + state(idlePage) + " (recommended " + recommended(idlePage) + ")]"));
            if (!ok)
                failures++;
            at++;
            if (at < steps.length) {
                step();
            } else {
                watchdog.stop();
                check.probe.report("== " + steps.filter(x => !x.group).length + " checks, " + failures + " failed, "
                    + Math.round((Date.now() - check.began) / 1000) + " s");
                check.probe.finish(failures);
            }
        };
        let ok = false;
        // a check that throws fails, rather than stopping the run
        try {
            ok = s.expect();
        } catch (e) {
            check.probe.report("     " + e);
        }
        if (!s.page) {
            done(ok);
            return;
        }
        (s.pageIn ? s.pageIn() : view).runJavaScript(typeof s.page === "function" ? s.page() : s.page, s.world ?? WebEngineScript.MainWorld,
                                                     v => done(ok && (s.pageExpect ? s.pageExpect(v) : v === true), v));
    }
}
