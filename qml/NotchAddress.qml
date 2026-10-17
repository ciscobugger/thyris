import QtQuick
import QtWebEngine
import "RailRows.js" as RailRows

// Ctrl+L and Ctrl+T in the notch (PLAN.md 3.19, ~/book4-edge/ctrll-notch-plan.md): the shell draws the address sheet and
// this window answers it over the Notch socket, one JSON object a line. Ctrl+L calls the shell with "edit", Ctrl+T with
// "new"; the island connects and says hello, and gets the page, the keys typed since the key, the rows under the line
// before anything is typed (`where`: Where next, or Ctrl+T's Recent and Earlier; again as { where } when they change) and
// what Ask Praxis hands over (`praxis`). It asks for rows as you type ({ query, text, seq }, answered { rows, seq, dest }:
// the card's rows with Ask Praxis second) and says what to do ({ go, index, seq, text, where: here | new | background },
// { go, next } for a where row, { reload }, { praxis } when the question went to the notch's Ask, { close }).
// The card (or the new-page bar) opens instead when the call fails, the shell's notch is off, no hello comes within
// `helloLimit`, or the window is full screen. While it waits for the hello this item holds the keys.
Item {
    id: link

    required property var app           // Main
    required property var omni
    required property var session
    required property var editor        // Main's AddressEditor: the address shown, and a row acts as the card's
    property var notch: null            // the C++ Notch, the main profile's; null in a private window and in shots
    property int helloLimit: 1500
    property string state: ""           // "", "calling" (the hello not here yet), "open"
    property string mode: "edit"        // "edit" (Ctrl+L) or "new" (Ctrl+T: a new page where the bar would put it)
    property string typed: ""           // keys typed while calling
    property var rows: []               // the last rows answered, as Omnibox gives them
    property int seq: -1
    property var links: []              // the page's likeliest links (linksScript), read at Ctrl+L
    property var where: []              // the rows under the line before anything is typed, as last sent
    property string target: ""          // new: the thread the page goes to ("" a new thread), predicted as the bar does
    property string text: ""            // new: the text last asked about

    readonly property bool mine: notch !== null && notch.owner === link
    onMineChanged: if (!mine && state !== "") reset()

    // Ctrl+L ("edit") and Ctrl+T ("new"): true when the shell was asked, false when the card or the bar should open
    function begin(how) {
        if (!notch || !notch.listening || app.fullWindow || app.offTheRecord || app.shotMode)
            return false;
        notch.owner = link;
        // an island still up from an earlier Ctrl+L goes; the new one says hello afresh
        notch.hangUp();
        reset();
        mode = how ?? "edit";
        state = "calling";
        readLinks();
        link.forceActiveFocus();
        helloTimer.interval = helloLimit;
        helloTimer.restart();
        notch.call(app.screen ? app.screen.name : "", mode);
        return true;
    }
    function reset() {
        helloTimer.stop();
        state = "";
        typed = "";
        rows = [];
        seq = -1;
        links = [];
        where = [];
        target = "";
        text = "";
    }
    // the island is done (or gone): the page has the keys again, and with `focusWindow` the window takes the focus back
    // from the island (again 250 ms later, as the island may still hold it when the first one comes)
    function end(focusWindow) {
        const keys = link.activeFocus;
        reset();
        if (mine)
            notch.hangUp();
        if (keys)
            app.focusPage();
        if (focusWindow && !app.shotMode) {
            Backdrop.focus(app);
            refocus.restart();
        }
    }
    // the window closes or is set aside: the island hears it and folds
    function close() {
        if (state === "" || !mine)
            return;
        notch.send(JSON.stringify({ op: "close" }));
        end(false);
    }
    function fallBack() {
        const keys = typed, how = mode;
        end(false);
        if (how === "new")
            app.newPage(keys !== "" ? keys : undefined);
        else
            app.editAddress(keys !== "" ? keys : undefined);
    }

    Timer { id: helloTimer; onTriggered: if (link.state === "calling") link.fallBack() }
    Timer { id: refocus; interval: 250; onTriggered: if (!link.app.active) Backdrop.focus(link.app) }

    // keys typed before the island has them: text and Backspace wait for the hello, Esc gives up
    Keys.onPressed: event => {
        if (state !== "calling")
            return;
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            close();
            return;
        }
        if (event.key === Qt.Key_Backspace)
            typed = typed.slice(0, -1);
        else if (event.text !== "" && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            typed += event.text;
    }

    Connections {
        target: link.notch
        function onMessage(line) { if (link.mine) link.receive(line) }
        function onCalled(ok) { if (link.mine && link.state === "calling" && !ok) link.fallBack() }
        function onHungUp() { if (link.mine && link.state !== "") link.end(false) }
    }
    // the task's pages changing while the sheet is open: Where next again
    Connections {
        target: link.session
        enabled: link.state === "open"
        function onRevisionChanged() { link.sendWhere() }
    }

    function receive(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.op === "hello") {
            // too late: the card took over, or nothing asked (an island reconnecting while open gets the state again)
            if (state === "") {
                notch.send(JSON.stringify({ op: "close" }));
                notch.hangUp();
                return;
            }
            helloTimer.stop();
            state = "open";
            const keys = typed;
            typed = "";
            where = whereRows();
            const hello = { op: "hello", typed: keys, mode: mode, where: where.map(drawn), praxis: praxis() };
            if (mode === "new") {
                target = homeThread();
                hello.dest = dest("");
            }
            notch.send(JSON.stringify(Object.assign(hello, page())));
            return;
        }
        if (state !== "open")
            return;
        if (m.op === "query") {
            const text = String(m.text ?? ""), prefix = omni.mode(text);
            // Ask Praxis second, after what Enter does (the render); a ? question is only that
            const found = prefix === "ask" ? [] : omni.suggest(text, session.currentPage, "address");
            rows = prefix === "ask" ? [{ kind: "praxis" }] : prefix === "" && found.length > 0 ? [found[0], { kind: "praxis" }].concat(found.slice(1)) : found;
            seq = m.seq ?? -1;
            const answer = { op: "rows", seq: seq, rows: rows.map(drawn) };
            if (mode === "new") {
                target = prefix !== "" ? "" : text.trim() === "" ? homeThread() : session.predictThread(text, homeThread());
                link.text = text;
                answer.dest = dest(prefix);
            }
            notch.send(JSON.stringify(answer));
        } else if (m.op === "go") {
            // a where row; the row shown for the last query, else what Enter does for the text
            const row = m.next !== undefined ? where[m.next]
                : m.seq === seq && rows[m.index] ? rows[m.index] : omni.suggest(String(m.text ?? ""), session.currentPage, "address")[0];
            const thread = target;
            end(true);
            if (row && row.kind !== "label" && row.kind !== "praxis")
                open(row, m.where, thread);
        } else if (m.op === "reload") {
            end(true);
            app.pageAction("reload");
        } else if (m.op === "praxis") {
            // the notch's Ask has the question and the keys
            end(false);
        } else if (m.op === "close") {
            end(true);
        }
    }

    // A row as the card acts on it, or for Ctrl+T as the bar does: a page to load opens as a new page in the thread
    // predicted (`thread`), in the background for Alt+Enter. An address you have been at loads back where you stopped.
    function open(row, where, thread) {
        const stop = row.kind === "history" ? stopFor(row.url) : null;
        if (row.kind === "import")
            app.pageAction("import");
        else if (mode === "new" && (row.kind === "go" || row.kind === "history"))
            app.go(row.url, "new", thread, row.name, "", where === "background", row.fallback ?? "", stop);
        else if (stop && where === "new")
            app.openHere(row.url, row.name, "", stop);
        else if (stop)
            app.go(row.url, "navigate", "", "", "", false, "", stop);
        else
            editor.activate(row, where === "new");
    }

    // the hello's state: the address as the card shows it, the page's title and host, the task as the rail's foot names it
    function page() {
        const p = session.current, t = session.currentThread, url = editor.url;
        const n = t ? t.pages.length : 1;
        const title = p ? p.title || RailRows.untitled(p.url) : "";
        return { link: url, title: title, host: omni.hostOf(url), task: !t ? "Pinned" : n > 1 ? t.title || "New task" : title, pages: n };
    }
    // Ctrl+T with nothing typed puts the page in the task on screen (the owner, 2026-10-02); words that match another
    // task send it there, words that match none to a new thread, as the bar predicts. Always pages have no task.
    function homeThread() {
        const t = session.currentThread;
        return t && session.ownThread(t) ? t.id : "";
    }
    // Ctrl+T's words for where the page goes, as the bar's destination line ("" for a prefix: its rows say it)
    function dest(prefix) {
        if (prefix !== "")
            return "";
        const t = session.threadById(target);
        return t ? "new page in " + (t.title || "this task") : "new task";
    }
    // What Ask Praxis hands the notch's Ask: the task's pages, the one on screen first, for Praxis to read before it answers
    // (the shell draws `label` as the Ask sheet's context chip and sends `text` with the question)
    function praxis() {
        const p = session.current, t = session.currentThread;
        if (!p)
            return null;
        const pages = [p].concat((t ? t.pages : []).map(id => session.pages[id]).filter(q => q && q !== p)).slice(0, 12);
        const name = page().task;
        return { label: pages.length > 1 ? name + " · " + pages.length + " pages" : name,
                 text: "The user asks from their browser, in the task \"" + name + "\". Read its pages before you answer:\n"
                       + pages.map(q => "- " + (q.title || RailRows.untitled(q.url)) + ": " + q.url + (q === p ? " (on screen)" : "")).join("\n") };
    }

    // The page's likeliest links, for Where next: links with words (not icons) outside the site's header, navigation,
    // sidebars and footer, to another address. Those in view count most, then those in the page's main part, in larger
    // type, with more words, to another site. Run in the browser's script world; answers JSON [{ url, title }] best first.
    readonly property string linksScript: "(() => { try { if (!document.body) return '';"
        + " const here = location.href.split('#')[0], h = innerHeight, seen = new Set(), out = [], all = document.querySelectorAll('a[href]');"
        + " for (let i = 0; i < all.length && i < 3000; i++) { const a = all[i], url = a.href.split('#')[0];"
        + " if (!/^https?:/.test(url) || url === here || seen.has(url)) continue;"
        + " if (a.closest('nav,header,footer,aside,menu,[role=navigation],[role=banner],[role=contentinfo],[role=complementary],[role=menu],[aria-hidden=true]')) continue;"
        + " const r = a.getBoundingClientRect(); if (r.width < 2 || r.height < 2) continue;"
        + " const text = (a.innerText || a.textContent || '').replace(/\\s+/g, ' ').trim(); if (text.length < 3) continue;"
        + " const s = getComputedStyle(a); if (s.visibility !== 'visible' || +s.opacity === 0) continue;"
        + " seen.add(url);"
        + " const far = r.bottom < 0 ? -r.bottom / h : r.top > h ? (r.top - h) / h : 0;"
        + " const score = (far === 0 ? 4 : Math.max(0, 2 - far)) + (a.closest('main,article,[role=main]') ? 2 : 0)"
        + " + Math.min(2, (parseFloat(s.fontSize) || 16) / 16) + Math.min(2, text.length / 20) + (a.hostname !== location.hostname ? 1 : 0);"
        + " out.push({ url: a.href, title: text.slice(0, 160), score: score, at: i }) }"
        + " out.sort((x, y) => y.score - x.score || x.at - y.at);"
        + " return JSON.stringify(out.slice(0, 6).map(x => ({ url: x.url, title: x.title })))"
        + " } catch (e) { return '' } })()"
    // at Ctrl+L, of the page on screen; an answer after the page went elsewhere, or the sheet closed, goes nowhere
    function readLinks() {
        const v = app.currentView, at = v ? String(v.url) : "";
        if (mode !== "edit" || !v || !v.runJavaScript || v.failure || at === "")
            return;
        v.runJavaScript(linksScript, WebEngineScript.ApplicationWorld, answer => {
            if (state === "" || mode !== "edit" || app.currentView !== v || String(v.url) !== at)
                return;
            let list = [];
            try {
                list = JSON.parse(answer);
            } catch (e) {}
            links = Array.isArray(list) ? list.filter(l => l && typeof l.url === "string" && typeof l.title === "string") : [];
            sendWhere();
        });
    }

    // Where next (the render's three): the page's likeliest link first, then the task's other pages and those it left,
    // newest first (the card's "In this thread"), then the rest of the links. Ctrl+T's: the bar's Recent and Earlier.
    function whereRows() {
        if (mode === "new")
            return omni.startRows().map(r => r.kind === "history" ? Object.assign({}, r, { word: stopFor(r.url) ? "opens where you stopped" : "" })
                                             : r.kind === "earlier" ? Object.assign({}, r, { word: "restore" }) : r);
        const p = session.current;
        if (!p)
            return [];
        const now = Date.now(), own = omni.pageRows(p.id, now), from = own.findIndex(r => r.kind === "label");
        const urlOf = r => r.url ?? (session.pages[r.pageId] ? session.pages[r.pageId].url : "");
        const task = (from < 0 ? [] : own.slice(from + 1)).map(r => Object.assign({}, r, { detail: omni.hostOf(urlOf(r)), word: "in this task · " + RailRows.age(r.at, now) }));
        const taken = new Set([p.url].concat(task.map(urlOf)));
        const found = links.filter(l => !taken.has(l.url)).slice(0, 3)
            .map(l => ({ kind: "go", glyph: "link", title: l.title, url: l.url, fallback: "", name: l.title, detail: omni.hostOf(l.url),
                         word: "linked on this page", icon: iconOf(l.url) }));
        const picked = found.slice(0, 1).concat(task.slice(0, 2), found.slice(1), task.slice(2)).slice(0, 3);
        return picked.length > 0 ? [{ kind: "label", title: "Where next" }].concat(picked) : [];
    }
    // the where rows again, sent when they changed
    function sendWhere() {
        if (state !== "open")
            return;
        const next = whereRows(), drawnNext = JSON.stringify(next.map(drawn));
        if (drawnNext === JSON.stringify(where.map(drawn)))
            return;
        where = next;
        notch.send(JSON.stringify({ op: "where", rows: JSON.parse(drawnNext) }));
    }
    // a link's favicon: its own address's from history, else another page of its site's
    function iconOf(url) {
        const entries = omni.history.entries;
        if (entries[url] && entries[url].icon)
            return entries[url].icon;
        const host = omni.hostOf(url);
        for (const k in entries)
            if (entries[k].icon && omni.hostOf(k) === host)
                return entries[k].icon;
        return "";
    }
    // Where you stopped on an address you have been at (PLAN.md 3.7): the latest place a closed page or any page of the
    // session took there, or null
    function stopFor(url) {
        let best = null;
        const take = s => {
            if (s && s.url === url && (!best || (s.at ?? 0) > (best.at ?? 0)))
                best = s;
        };
        for (const c of session.closedPages())
            take(c.stopped);
        for (const id in session.pages)
            take(session.pages[id].stopped);
        return best;
    }

    // A row as the sheet draws it (the render's words): Search the web with the engine, Ask Praxis, Open and Been here
    // groups, a page's host, a history row's host and age, one word at the right; `enter`: what Enter does.
    function drawn(r) {
        if (r.kind === "label")
            return { kind: "label", title: ({ "Open page": "Open", "History": "Been here" })[r.title] ?? r.title };
        if (r.kind === "praxis")
            return { kind: "praxis", title: "Ask Praxis", detail: "reads this task's pages first", word: "Tab", glyph: "diamond", icon: "", enter: "praxis" };
        const search = r.kind === "go" && r.glyph === "search";
        const url = r.url ?? (r.pageId && session.pages[r.pageId] ? session.pages[r.pageId].url : "");
        let detail = r.detail ?? "", word = r.word ?? "";
        if (search)
            detail = omni.engine;
        else if (r.word !== undefined)
            detail = r.detail ?? "";
        else if (r.kind === "page") {
            detail = omni.hostOf(url);
            word = "switch";
        } else if (r.kind === "history") {
            // an address you have been at opens where you stopped on it
            word = stopFor(url) ? "opens where you stopped" : r.detail === "Saved" ? "saved" : "";
            detail = omni.hostOf(url) + (r.detail && r.detail !== "Saved" ? " · " + r.detail : "");
        } else if (r.kind === "earlier") {
            detail = r.detail + (r.detail === "1" ? " page" : " pages");
            word = "restore";
        }
        const enter = ({ go: search ? "search" : "go", page: "switch", earlier: "restore", closed: "reopen", history: "go", find: "find",
                         action: "act" })[r.kind] ?? "none";
        return { kind: r.kind, title: search ? "Search the web" : r.title, detail: detail, word: word, glyph: r.glyph ?? "",
                 icon: r.icon ? Engine.keptIcon(r.icon) : "", enter: enter };
    }
}
