import QtQuick
import QtWebEngine
import Browser
import "Asks.js" as Asks
import "PageState.js" as PageState

// A sign-in popup in the notch (~/book4-edge/signin-notch-plan.md): the shell draws the sheet, its header (lock and host,
// "for" and the opener's favicon, which is the way back), the asks under the page and the grabber, and leaves a hole where
// the popup's page window shows through (app_id browser-signin, hypr/browser.lua). The first window's; it speaks for every
// main window's popups, and for sign-ins from other apps (Main's appSignin: `opener` is then the app,
// `app` true, and the call's mode "app"), over the sign-in socket (src/notch.*), one JSON object a line, one at a time:
// the others wait their turn. A private window's popups are pages (Main.openFromOpener).
//   to the shell:   hello { host, secure, opener, icon, app, width, height, count }; page { host, secure, opener, icon, app } when
//                   those change; ask { ask, count } (the shown ask as Asks.view words it, with its id and kind; null when
//                   none); code { on } (a one-time code's field has the keys); aside { on } (its opener is off screen);
//                   count { count }; unmapped; done { signed } (closed: by itself when signed, else by you)
//   from the shell: hello; map { width, height } (the sheet has settled: the page shows at that size, and again when it
//                   changes); unmap (the sheet folds: the page goes first); back, close (the way back, the flick up);
//                   answer { id, choice, data }; fill { text } (a code from your phone, into the focused field)
// The popup is a page instead (Main.popupToPage; never a window of its own, 2026-10-14) when the call fails, the shell
// says "off" (its notch off, on no screen of that name, or under a full-screen window), no hello comes within
// `helloLimit`, its window is full screen, or the shell goes away while it is up.
Item {
    id: link

    property var notch: null            // the C++ Notch for sign-ins; null in shots and until the checks set one
    property int helloLimit: 1500
    property var queue: []              // popups waiting for the notch, oldest first
    property var current: null          // the popup the notch shows, or is being asked to
    property string state: ""           // "", "calling" (the hello not here yet), "open"
    property bool mapped: false         // the shell has said map and not unmap since
    readonly property bool mine: notch !== null && notch.owner === link
    readonly property int count: (current ? 1 : 0) + queue.length

    // Whether the notch takes `main`'s popups: not a private window's, nor one in full window, nor without the shell.
    function takes(main) {
        return !!notch && notch.listening && !main.offTheRecord && !main.fullWindow && !main.shotMode;
    }
    // A new popup: true when the notch takes it (now, or after the one there), false when it is a page instead.
    function want(w) {
        if (!takes(w.main))
            return false;
        w.shownIn = "notch";
        queue = queue.concat([w]);
        if (current === null)
            next();
        else
            say({ op: "count", count: count });
        return true;
    }
    // A popup in the notch closing (Main.closePopup) while its page shows: the shell hears done (`signed`: it closed
    // itself, and the notch breathes out in the success tone), closes its hole over the page and says unmap; then
    // `finish` hides it and lets it go, 150 ms later without the unmap. False when it is not the one on screen.
    property var finishing: null
    function closing(w, signed, finish) {
        // closed again while it goes (the page's close and its own window.close())
        if (finishing && w === current)
            return true;
        if (w !== current || state !== "open" || !w.visible)
            return false;
        say({ op: "done", signed: signed === true });
        finishing = finish;
        finishTimer.restart();
        return true;
    }
    function finished() {
        finishTimer.stop();
        const f = finishing;
        finishing = null;
        if (f)
            f();
        say({ op: "unmapped" });
        end();
        next();
    }
    Timer { id: finishTimer; interval: 150; onTriggered: link.finished() }
    // A popup closed (Main.closePopup) whose page did not show: the shell folds (breathing out when `signed`), and the
    // next one waiting is asked for; one still waiting its turn leaves the queue.
    function closed(w, signed) {
        if (w !== current) {
            const before = queue.length;
            queue = queue.filter(q => q !== w);
            if (queue.length !== before && current)
                say({ op: "count", count: count });
            return;
        }
        if (state === "open")
            say({ op: "done", signed: signed === true });
        end();
        next();
    }

    function next() {
        while (queue.length > 0 && !live(queue[0]))
            queue = queue.slice(1);
        if (queue.length === 0 || !notch || !notch.listening)
            return;
        current = queue[0];
        queue = queue.slice(1);
        notch.owner = link;
        // an island still connected from the sign-in before goes; the new one says hello afresh
        notch.hangUp();
        state = "calling";
        mapped = false;
        helloTimer.interval = helloLimit;
        helloTimer.restart();
        notch.call(current.main.screen ? current.main.screen.name : "", current.fromApp ? "app" : "open");
    }
    function live(w) {
        return w && w.wanted && w.shownIn === "notch";
    }
    function end() {
        helloTimer.stop();
        state = "";
        mapped = false;
        current = null;
        if (mine)
            notch.hangUp();
    }
    // the notch cannot show it: a page instead (inWindow), and the others waiting try in turn
    function fallBack() {
        const w = current;
        end();
        if (live(w))
            w.inWindow();
        next();
    }
    function say(o) {
        if (mine && state === "open")
            notch.send(JSON.stringify(o));
    }

    Timer { id: helloTimer; onTriggered: if (link.state === "calling") link.fallBack() }

    Connections {
        target: link.notch
        function onMessage(line) { if (link.mine) link.receive(line) }
        function onCalled(ok) { if (link.mine && link.state === "calling" && !ok) link.fallBack() }
        // the shell went away with the sheet up (a reload, a crash): the sign-in goes on as a page
        function onHungUp() { if (link.mine && link.state !== "") link.fallBack() }
    }

    // what the sheet's header says: the page's host and whether it is secure, and whom it is for (the opener's host and
    // favicon, or the app the link came from)
    readonly property var page: {
        const w = current;
        if (!w || !w.view)
            return null;
        const url = String(w.view.url);
        return { host: PageState.pageHost(url), secure: !PageState.insecure(url), opener: w.forName, icon: w.forIcon, app: w.fromApp === true };
    }
    onPageChanged: if (state === "open" && page) say(Object.assign({ op: "page" }, page))
    // the page's shown ask, as the address card words it (Asks.view)
    // the page's shown ask, as the address card words it (Asks.view), and how many wait ("1 of N")
    readonly property var asking: {
        const v = current ? current.view : null, a = v ? v.ask : null;
        return { ask: a ? Object.assign({ id: a.id, kind: a.kind }, Asks.view(a, page ? page.host : "")) : null,
                 count: v ? Asks.order(v.asks).length : 0 };
    }
    onAskingChanged: say(Object.assign({ op: "ask" }, asking))
    readonly property bool code: current !== null && current.view !== null && current.view.codeField === true
    onCodeChanged: say({ op: "code", on: code })
    readonly property bool aside: current !== null && !current.openerShown
    onAsideChanged: {
        if (state !== "open")
            return;
        // off screen with its opener: the page goes at once, the shell folds to its waiting wing
        if (aside && mapped) {
            mapped = false;
            current.unmap();
        }
        say({ op: "aside", on: aside });
    }

    function receive(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.op === "hello") {
            // too late (a page took over) or nothing asked
            if (state !== "calling" && state !== "open") {
                notch.send(JSON.stringify({ op: "close" }));
                notch.hangUp();
                return;
            }
            helloTimer.stop();
            state = "open";
            const w = current;
            say(Object.assign({ op: "hello", width: w.asked.width, height: w.asked.height, count: count }, page));
            if (asking.ask)
                say(Object.assign({ op: "ask" }, asking));
            if (code)
                say({ op: "code", on: true });
            if (aside)
                say({ op: "aside", on: true });
            return;
        }
        // the page closing: the shell has closed its hole over it
        if (m.op === "unmap" && finishing) {
            finished();
            return;
        }
        if (state !== "open" || !live(current))
            return;
        const w = current;
        if (m.op === "map") {
            if (aside)
                return;
            mapped = true;
            w.mapAt(Math.max(200, m.width | 0), Math.max(120, m.height | 0));
        } else if (m.op === "unmap") {
            mapped = false;
            w.unmap();
            say({ op: "unmapped" });
        } else if (m.op === "back" || m.op === "close") {
            w.view.requestClose();
        } else if (m.op === "answer") {
            const a = w.view.ask;
            if (a && a.id === m.id)
                w.view.answer(a, String(m.choice ?? ""), m.data ?? {});
        } else if (m.op === "fill") {
            fill(w.view, String(m.text ?? ""));
        }
    }

    // a code from your phone into the page's focused field, as typed (the page's own input events); never kept
    function fill(view, text) {
        if (!/^[0-9A-Za-z-]{3,12}$/.test(text))
            return;
        view.runJavaScript("(() => { let d = document, e = d.activeElement; for (;;) {"
            + " if (e && e.shadowRoot && e.shadowRoot.activeElement) e = e.shadowRoot.activeElement;"
            + " else if (e && /^I?FRAME$/.test(e.tagName)) { try { d = e.contentDocument } catch (x) { return false } e = d && d.activeElement }"
            + " else break }"
            + " if (!e || e.tagName !== 'INPUT') return false; e.focus(); return d.execCommand('insertText', false, " + JSON.stringify(text) + ") })()",
            WebEngineScript.ApplicationWorld, () => {});
    }
}
