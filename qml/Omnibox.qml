import QtQuick
import "RailRows.js" as RailRows
import "PageState.js" as PageState
import "Recall.js" as Recall

// What typed text means and what to offer for it; shared by the address card and the new-page card.
QtObject {
    id: omni

    required property var session
    required property var history
    property var saved: null                 // Saved.qml: a history row of a saved page reads "Saved"
    // whether a typed absolute path names an existing file (Main: Facts.isFile)
    property var isFile: path => false
    // the page on screen's article (BrowserView.article): "none" makes > Reader view say "No article here"
    property string article: ""
    // a private window's (PLAN.md 3.14): no Earlier rows, no Always action and no import; its session and history
    // are the window's own
    property bool offTheRecord: false
    // Settings > Privacy (PLAN.md 3.15): an address typed with http:// tries https first
    property bool httpsFirst: true
    // Praxis's hand-off is here (Engine.praxisHere): ? asks it (PLAN.md 3.20, 4)
    property bool praxisHere: false
    // Import from Zen (PLAN.md 3.4): a Zen profile was found and nothing was imported from it yet
    property bool offerImport: false

    function looksLikeUrl(t) {
        if (/\s/.test(t))
            return false;
        return /^[a-z][a-z0-9+.-]*:\/\//i.test(t) || /^(about|chrome|file):/i.test(t)
            // Qt's JS engine has no \p{L}: host letters are ASCII plus everything from U+00C0 (IDN).
            || /^(localhost|\d{1,3}(\.\d{1,3}){3}|[0-9a-z\u00c0-\uffff-]+(\.[0-9a-z\u00c0-\uffff-]+)*\.[a-z\u00c0-\uffff]{2,})(:\d+)?([\/?#].*)?$/i.test(t);
    }
    function toUrl(t) {
        // "example.com:8080" is a host and a port, not a scheme
        if (/^[a-z][a-z0-9+.-]*:(?!\d)/i.test(t))
            return t;
        return (/^(localhost|\d{1,3}(\.\d{1,3}){3})/.test(t) ? "http://" : "https://") + t;
    }
    // user:pass@ is skipped: it is not the host, and it can pose as one. An address without one reads as the address
    // card names it ("File", "data: page · 4 kB").
    function hostOf(url) {
        const m = /^[a-z]+:\/\/(?:[^\/?#@]*@)?([^\/:?#]+)/i.exec(url);
        return m ? m[1].replace(/^www\./, "") : RailRows.card(url, "").host;
    }
    function split(url) { return RailRows.split(url) }

    // Prefixes, first character only (PLAN.md 3.3, 3.20): / find, > page actions, ? ask Praxis, @ jump.
    function mode(text) {
        return ({ "/": "find", ">": "actions", "?": "ask", "@": "jump" })[(text || "").trim().charAt(0)] ?? "";
    }

    // What a prefix does, for the new-page card's destination line and the address card's last line.
    function modeLine(m) {
        return ({ find: "Find on this page", actions: "Actions for this page", ask: "Ask Praxis about this task",
                  jump: "Jump to a task or page" })[m] ?? "";
    }

    // Words to match: the prediction's words (stop words and words under three letters dropped), or the
    // bare text when that leaves none ("qt", "ab").
    function queryWords(q) {
        const words = session.wordsOf(q);
        return words.length > 0 ? words : q.toLowerCase().split(/\s+/).filter(w => w.length > 0);
    }

    // What the typed words match, each list best first: open pages (Always included), history that is
    // not open, filed threads by their title and their pages' titles and URLs. A page's words include where you
    // stopped on it (PLAN.md 3.7).
    function matches(q, excludePage) {
        const words = queryWords(q);
        const hits = hay => words.filter(w => hay.toLowerCase().includes(w)).length;
        const open = [], threads = [], earlier = [], openUrls = new Set();
        const openIds = session.always.slice();
        for (const t of session.threads)
            if (t.earlier) {
                if (offTheRecord)
                    continue;
                const n = hits(t.title + " " + t.pages.map(id => pageWords(session.pages[id])).join(" "));
                if (n > 0)
                    earlier.push({ thread: t, n: n });
            } else {
                openIds.push(...t.pages);
                // an open thread by its title; a thread of one is its page
                const n = t.pages.length > 1 && t.pages.indexOf(excludePage) < 0 ? hits(t.title) : 0;
                if (n > 0)
                    threads.push({ thread: t, n: n });
            }
        for (const id of openIds) {
            const p = session.pages[id];
            openUrls.add(p.url);
            const n = id === excludePage ? 0 : hits(pageWords(p));
            if (n > 0)
                open.push({ page: p, n: n });
        }
        open.sort((a, b) => b.n - a.n || b.page.lastActive - a.page.lastActive);
        earlier.sort((a, b) => b.n - a.n || b.thread.lastActive - a.thread.lastActive);
        threads.sort((a, b) => b.n - a.n || b.thread.lastActive - a.thread.lastActive);
        return { open: open.map(h => h.page), threads: threads.map(h => h.thread), earlier: earlier.map(h => h.thread),
                 history: history.search(words, 12).filter(e => !openUrls.has(e.url)) };
    }

    function pageWords(p) {
        const s = Recall.current(p);
        return p.title + " " + p.url + (s ? " " + s.heading : "");
    }

    function pageRow(p, detail) {
        return { kind: "page", icon: p.icon || "", glyph: "language", dim: p.state === "unloaded", title: p.title || RailRows.untitled(p.url),
                 detail: detail, pageId: p.id };
    }
    function historyRow(e, now) {
        return { kind: "history", icon: e.icon || "", glyph: "language", title: e.title || e.url,
                 detail: e.saved || saved && saved.isSaved(e.url) ? "Saved" : RailRows.when(e.last, now), url: e.url, name: e.title || hostOf(e.url) };
    }

    // Typed text (PLAN.md 3.2 2b, 3.3). Row 1 is what Enter does; then open pages (Enter switches, never a
    // duplicate), history by frecency, filed threads (Enter restores); at most 8 rows. The address card
    // ("address") heads each group with a 12 px label; the new-page card ("bar", the default) ends each
    // row with the word for what Enter does when it is not plain navigation.
    function suggest(text, excludePage, surface, now) {
        const q = text.trim();
        if (q === "")
            return [];
        const at = now || Date.now();
        const m = mode(q);
        if (m === "jump")
            return jumpRows(q.slice(1).trim(), excludePage, at);
        if (m !== "")
            return prefixRows(m, q.slice(1).trim(), q);
        const address = surface === "address";
        const out = [];
        // an address tries https first; `fallback` is the plain http it loads if https cannot connect. With https-first
        // Off (Settings > Privacy) an address typed with http:// loads as typed.
        const first = !looksLikeUrl(q) ? null : httpsFirst || !/^http:\/\//i.test(q) ? PageState.httpsFirst(q, toUrl(q)) : { url: toUrl(q), fallback: "" };
        if (first)
            out.push({ kind: "go", glyph: "arrow_forward", title: toUrl(q), detail: "", url: first.url, fallback: first.fallback, name: hostOf(toUrl(q)) });
        else
            out.push({ kind: "go", glyph: "search", title: q, detail: address ? "Search" : engine, url: searchUrl(q), name: q });
        const found = matches(q, excludePage);
        const open = found.open.slice(0, 3), earlier = found.earlier.slice(0, 2);
        const hist = found.history.slice(0, Math.min(3, 7 - open.length - earlier.length));
        const group = (label, rows) => {
            if (rows.length > 0 && address)
                out.push({ kind: "label", title: label });
            out.push(...rows);
        };
        group("Open page", open.map(p => pageRow(p, address ? "" : "Switch")));
        group("History", hist.map(e => historyRow(e, at)));
        group("Closed tasks", earlier.map(t => ({
            kind: "earlier", glyph: "circle", threadId: t.id,
            title: address ? t.title : t.title + " · " + t.pages.length + (t.pages.length === 1 ? " page" : " pages"),
            detail: address ? String(t.pages.length) : "Restore" })));
        return out;
    }

    // Settings > Search (PLAN.md 3.15): the engine's name and its address with %s for the words
    property string engine: "DuckDuckGo"
    property string searchTemplate: "https://duckduckgo.com/?q=%s"
    function searchUrl(q) { return searchTemplate.replace("%s", encodeURIComponent(q)) }

    // @ (PLAN.md 3.7 7a): nothing new is made. Open threads (to their last page) and pages, in every window, then
    // Earlier, then closed pages, then history, at most 8 rows, the typed words' letters marked (`marks`). An Earlier
    // thread says why it matched in `lines`: up to two of its pages (those that matched, else the one it comes back
    // at) and where you stopped; a page that matched on where you stopped says so too.
    function jumpRows(q, excludePage, now) {
        if (q === "")
            return [];
        const words = queryWords(q), found = matches(q, excludePage);
        const hits = hay => words.filter(w => String(hay).toLowerCase().includes(w)).length;
        const stoppedHere = s => s && s.heading && hits(s.heading) > 0 ? [{ text: Recall.line(s) }] : [];
        function why(t) {
            const list = t.pages.map(id => session.pages[id]).filter(p => p);
            let shown = list.map(p => ({ p: p, n: hits(pageWords(p)) })).filter(h => h.n > 0)
                .sort((a, b) => b.n - a.n || b.p.lastActive - a.p.lastActive).slice(0, 2).map(h => h.p);
            if (shown.length === 0 && session.pages[session.mostRecentPage(t.id)])
                shown = [session.pages[session.mostRecentPage(t.id)]];
            const lines = [];
            let stop = null;
            for (const p of shown) {
                lines.push({ text: p.title || RailRows.named(p.url) });
                if (!stop && Recall.current(p)) {
                    stop = Recall.current(p);
                    lines.push({ text: Recall.line(stop) });
                }
            }
            return lines;
        }
        const openUrls = new Set(found.open.map(p => p.url));
        for (const t of session.threads)
            if (!t.earlier)
                t.pages.forEach(id => { if (session.pages[id]) openUrls.add(session.pages[id].url) });
        const closed = session.closedPages().filter(c => !openUrls.has(c.url))
            .map(c => ({ c: c, n: hits(c.title + " " + c.url + " " + (Recall.current({ url: c.url, stopped: c.stopped })?.heading ?? "")) }))
            .filter(h => h.n > 0).sort((a, b) => b.n - a.n || (b.c.at ?? 0) - (a.c.at ?? 0)).slice(0, 2).map(h => h.c);
        const closedUrls = new Set(closed.map(c => c.url));
        return found.threads.slice(0, 2).map(t => ({ kind: "page", glyph: "chevron_right", title: t.title, pageId: session.mostRecentPage(t.id),
                                                     detail: t.pages.length + " pages · Switch", marks: words }))
            .concat(found.open.slice(0, 3).map(p => Object.assign(pageRow(p, "Switch"), { marks: words, lines: stoppedHere(Recall.current(p)) })))
            .concat(found.earlier.slice(0, 3).map(t => ({ kind: "earlier", glyph: "circle", threadId: t.id, title: t.title, marks: words, lines: why(t),
                                                          detail: "Closed · " + t.pages.length + (t.pages.length === 1 ? " page" : " pages") })))
            .concat(closed.map(c => ({ kind: "closed", icon: c.icon || "", glyph: "language", title: c.title || RailRows.named(c.url), url: c.url,
                                       closedId: c.id, detail: c.at ? Recall.closedAgo(c.at, now) : "closed", marks: words,
                                       lines: stoppedHere(Recall.current({ url: c.url, stopped: c.stopped })) })))
            .concat(found.history.filter(e => !closedUrls.has(e.url)).slice(0, 2).map(e => Object.assign(historyRow(e, now), { marks: words })))
            .slice(0, 8);
    }

    // The page actions > lists, filtered by the typed words. / finds on this page (Enter opens find with
    // the words), and an existing file's path (`whole`, the text as typed) opens it, find second. ? shows
    // what it will do; Claude arrives in phase 5, so its row does nothing yet.
    readonly property var actions: [
        { kind: "action", action: "reload", glyph: "refresh", title: "Reload", detail: "Ctrl+R" },
        // print and reader first, in PLAN.md 7's order
        { kind: "action", action: "print", glyph: "print", title: "Print", detail: "Ctrl+P" },
        { kind: "action", action: "reader", glyph: "chrome_reader_mode", title: "Reader view", detail: "Ctrl+Alt+R" },
        { kind: "action", action: "copy", glyph: "link", title: "Copy link", detail: "" },
        { kind: "action", action: "markdown", glyph: "content_copy", title: "Copy as Markdown link", detail: "" },
        { kind: "action", action: "always", glyph: "keep", title: "Pin this site", detail: "Ctrl+Shift+D" },
        { kind: "action", action: "close", glyph: "close", title: "Close page", detail: "Ctrl+W" },
        // the browser's own pages (PLAN.md 7)
        { kind: "action", action: "settings", glyph: "settings", title: "Settings", detail: "Ctrl+," },
        { kind: "action", action: "keys", glyph: "keyboard", title: "Key list", detail: "Ctrl+/" },
        { kind: "action", action: "pages", glyph: "memory", title: "Pages and memory", detail: "Shift+Esc" },
    ]
    function prefixRows(m, q, whole) {
        if (m === "actions") {
            const words = q.toLowerCase().split(/\s+/).filter(w => w.length > 0);
            // a page with no article offers Reader view as a row that does nothing, saying why (PLAN.md 3.9)
            return actions.filter(a => words.every(w => a.title.toLowerCase().includes(w)) && !(offTheRecord && a.action === "always"))
                .map(a => a.action === "reader" && article === "none" ? { kind: "stub", glyph: a.glyph, title: a.title, detail: "No article here" } : a);
        }
        if (m === "find") {
            const find = { kind: "find", glyph: "find_in_page", title: q ? "Find \u201c" + q + "\u201d" : "Find on this page", detail: "", text: q };
            if (!whole || whole.indexOf("/", 1) < 0 || !isFile(whole))
                return [find];
            return [{ kind: "go", glyph: "description", title: "Open file", detail: "", url: "file://" + whole.split("/").map(encodeURIComponent).join("/"),
                      fallback: "", name: whole.split("/").pop() }, find];
        }
        // ? (PLAN.md 3.20): the question goes to Praxis, which reads the task's pages first (Main.askPraxis)
        if (!praxisHere)
            return [{ kind: "stub", glyph: "diamond", title: "Ask Praxis", detail: "Praxis is not installed" }];
        return [q ? { kind: "praxis", glyph: "diamond", title: q, detail: "Ask Praxis", text: q }
                  : { kind: "stub", glyph: "diamond", title: "Ask Praxis about this task", detail: "type a question" }];
    }

    // The address card with nothing typed (PLAN.md 3.2 2a): Enter reloads, the two copy actions, then
    // "In this task" (the rail's word): the thread's other open pages and the pages it left, newest first.
    function pageRows(pageId, now) {
        const p = session.pages[pageId];
        if (!p)
            return [];
        const at = now || Date.now();
        const out = [
            { kind: "action", action: "reload", glyph: "keyboard_return", title: "Reload this page", detail: "" },
            { kind: "action", action: "copy", title: "Copy link", detail: "Ctrl+C" },
            { kind: "action", action: "markdown", title: "Copy as Markdown link", detail: "" },
        ];
        const t = session.threadById(p.thread);
        if (!t)
            return out;
        const seen = t.pages.filter(id => id !== pageId).map(id => session.pages[id]);
        const urls = new Set(t.pages.map(id => session.pages[id].url));
        const trail = seen.map(q => Object.assign(pageRow(q, "open"), { at: q.lastActive }))
            .concat((t.trail ?? []).filter(e => !urls.has(e.url)).map(e => ({
                kind: "history", icon: e.icon || "", glyph: "language", title: e.title || RailRows.named(e.url), detail: RailRows.when(e.left, at),
                url: e.url, name: e.title, at: e.left })))
            .sort((a, b) => b.at - a.at).slice(0, 4);
        if (trail.length > 0)
            out.push({ kind: "label", title: "In this task" }, ...trail);
        return out;
    }

    // The new-page card with nothing typed (PLAN.md 3.4): Recent (the last 3 history entries that are not
    // open) and Earlier (the last 2 filed threads). On first run, only the import row, where there is a Zen to import from.
    function startRows(now) {
        const out = [];
        const openUrls = new Set();
        for (const t of session.threads)
            if (!t.earlier)
                for (const id of t.pages)
                    openUrls.add(session.pages[id].url);
        // the rail's order and times, so both Earlier lists agree
        const filed = offTheRecord ? [] : session.earlierThreads(now);
        const recent = Object.values(history.entries).filter(e => !openUrls.has(e.url))
            .sort((a, b) => b.last - a.last).slice(0, 3);
        if (recent.length === 0 && session.threads.length === 0 && !offTheRecord)
            return offerImport ? [{ kind: "import", glyph: "download", title: "Bring your things over from another browser or a password manager" }] : [];
        if (recent.length > 0)
            out.push({ kind: "label", title: "Recent" });
        for (const e of recent)
            out.push({ kind: "history", icon: e.icon || "", glyph: "language", title: e.title || e.url, detail: hostOf(e.url), url: e.url, name: e.title || hostOf(e.url) });
        if (filed.length > 0)
            out.push({ kind: "label", title: "Closed tasks" });
        for (const t of filed.slice(0, 2))
            out.push({ kind: "earlier", glyph: "circle", title: t.title, threadId: t.id,
                       detail: t.pages.length + (t.pages.length === 1 ? " page · " : " pages · ") + RailRows.when(t.filedAt ?? t.lastActive, now || Date.now()) });
        return out;
    }
}
