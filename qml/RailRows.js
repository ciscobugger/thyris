.pragma library
.import "Downloads.js" as Downloads
.import "Recall.js" as Recall

// What the rail lists under New page (PLAN.md 3.1, 3.4, 3.12, 3.19), as flat rows, and the in-place sync
// into the rail's ListModel, so a title or loading change updates one row instead of rebuilding the
// list (which reset the scroll position and dropped hover).

// Every row carries every role: a ListModel fixes a role's type from the first row that has it.
var defaults = {
    key: "", type: "", ref: "", title: "", icon: "", detail: "", glyph: "", count: 0, depth: 0,
    open: false, current: false, dim: false, audible: false, muted: false, needsYou: false, loading: false, capturing: "", failed: "",
    // downloads (Downloads.row): the page they came from, what the row stands for and its lines
    page: "", status: "", info: "", note: "", progress: -1, from: "",
    // a page from another app: "from foot · 14:31", a second line under its title (PLAN.md 3.6, 6b)
    origin: "",
    // the tabs along the top: a page's task, a face's letter, a hairline before the tab
    thread: "", letter: "", edge: false,
    // the one word at a row's right, whether it matters (the main ink, else the meta ink; never the accent, 2026-10-08)
    // and the glyph that says what it is about, so it reads without colour (PLAN.md 3.20)
    word: "", accent: false, wordGlyph: ""
};

// What an ask's word is about, as a glyph beside it (Asks.word's words)
var askGlyphs = { "camera?": "videocam", "mic?": "mic", "location?": "location_on", "screen?": "screen_share",
                  "notify?": "notifications", "clipboard?": "content_paste", "sign in": "key", "passkey": "key",
                  "password?": "key", "certificate?": "warning", "save?": "download", "open app?": "open_in_new" };
function askGlyph(word) {
    return askGlyphs[word] ?? "help";
}

// A page's title without the site's own name, which its icon already says: "Lofi Girl - radio - YouTube" on
// youtube.com reads "Lofi Girl - radio", "… · Issue #212 · linux-msm/linux · GitHub" loses "GitHub". Only a trailing
// part that names the host goes, and never the whole title.
function trimTitle(title, url) {
    const host = (split(url || "").host || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    if (host === "" || !title)
        return title;
    let t = title;
    for (;;) {
        const m = /^(.*\S)\s+[-–—|·•]\s+([^-–—|·•]+)$/.exec(t);
        if (!m)
            break;
        const part = m[2].toLowerCase().replace(/[^a-z0-9]/g, "");
        if (part.length < 3 || host.indexOf(part) < 0)
            break;
        t = m[1];
    }
    return t;
}

// Age of a filed thread: a time for the last three hours, "today", a weekday within the week, else a date.
function when(ms, now) {
    const d = new Date(ms), n = new Date(now);
    const pad = v => (v < 10 ? "0" : "") + v;
    if (d.toDateString() === n.toDateString())
        return now - ms < 3 * 3600000 ? pad(d.getHours()) + ":" + pad(d.getMinutes()) : "today";
    if (now - ms < 6 * 86400000)
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
    return d.getDate() + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
}

// "github.com" and "/ciscobugger/Wedding/pull/341" for display: user:pass@, www., query and fragment dropped.
function split(url) {
    const m = /^[a-z]+:\/\/(?:[^\/?#@]*@)?([^\/?#]+)([^?#]*)/i.exec(url);
    if (!m)
        return { host: url, path: "" };
    return { host: m[1].replace(/^www\./, ""), path: m[2] === "/" ? "" : m[2] };
}
// How the address card reads an address (PLAN.md 3.17): { glyph, host, path, own }. Web addresses read as split()
// reads them. The browser's own pages, local files, about:blank, data: and view-source: read by their kind (`own`),
// a data: page never by its content; `glyph` is the browser's own glyph in the favicon slot ("": the page's favicon,
// else the globe), in the card and the page's rail row alike (PLAN.md 3.10 10b, 3.15). `title` is the page's, which
// an Answer shows after its name. Settings (browser://settings) and Pages and memory (browser://pages) are the browser's
// own pages (Engine's scheme, SettingsPage and PagesPage); the Answer (browser://answer/<id>) is named for phase 5.
var ownPages = { settings: { glyph: "settings", host: "Settings" }, pages: { glyph: "memory", host: "Pages and memory" },
                 answer: { glyph: "diamond", host: "Answer" } };
function card(url, title) {
    const own = /^browser:\/\/([a-z]+)/i.exec(url);
    if (own && ownPages[own[1].toLowerCase()]) {
        const p = ownPages[own[1].toLowerCase()];
        return { glyph: p.glyph, host: p.host, path: p === ownPages.answer ? title || "" : "", own: true };
    }
    if (/^file:/i.test(url))
        return { glyph: "description", host: "File", path: filePath(url), own: true };
    if (/^about:blank([?#]|$)/i.test(url))
        return { glyph: "", host: "Blank page", path: "", own: true };
    if (/^data:/i.test(url))
        return { glyph: "", host: "data: page · " + Downloads.size(dataBytes(url)), path: "", own: true };
    if (/^view-source:/i.test(url)) {
        const s = card(url.slice(12), "");
        return { glyph: "", host: "Source of " + s.host, path: s.path, own: true };
    }
    return Object.assign(split(url), { glyph: "", own: false });
}
// A glyph's fill: ◆ is Claude's mark (PLAN.md 3), drawn filled as the rail's thread rows draw it.
function filled(glyph) {
    return glyph === "diamond" ? 1 : 0;
}
// "/home/you/Documents/S2MM006.pdf" for file:///home/you/Documents/S2MM006.pdf: the path, decoded
function filePath(url) {
    const path = url.replace(/^file:(\/\/[^\/]*)?/i, "").replace(/[?#].*$/, "");
    try {
        return decodeURIComponent(path);
    } catch (e) {
        return path;
    }
}
// What a data: address holds, decoded: a %XX escape is one byte, and base64 three for every four characters.
function dataBytes(url) {
    const comma = url.indexOf(",");
    if (comma < 0)
        return 0;
    const body = url.slice(comma + 1).replace(/#.*$/, "");
    if (/;base64$/i.test(url.slice(0, comma)))
        return Math.floor(body.replace(/%[0-9a-f]{2}|[^a-z0-9+\/]/gi, "").length * 3 / 4);
    return body.replace(/%[0-9a-f]{2}/gi, "%").length;
}
// The title the browser keeps for a page. Chromium names a page with no title of its own by its address (a data:
// page by its content, a view-source: page by "view-source:<address>"); for the addresses card() reads by their kind
// that stand-in is no title, so the page reads as untitled() does. A file's own name, Chromium's title for a file, stays.
function pageTitle(title, url) {
    const scheme = /^[a-z][a-z0-9+.-]*:/i.exec(url);
    return scheme && card(url, "").own && title.toLowerCase().startsWith(scheme[0].toLowerCase()) ? "" : title;
}
// A page with no title yet reads as its host and path, like the address card; a page card() names by its kind as
// that name and its detail ("File /home/you/…", "Blank page").
function untitled(url) {
    const s = card(url, "");
    return s.host + (s.own && s.path ? " " : "") + s.path;
}
// Where a page's name falls back to its whole address: a web address as it is, one card() names by its kind as
// untitled() names it.
function named(url) {
    return card(url, "").own ? untitled(url) : url;
}
// The window's title as Alt-Tab and the Super palette show it (PLAN.md 3.17): "<page title> · <thread>". An Always
// page has no thread; a thread of one is a plain page row in the rail, its name never shown; and a thread named as its
// page is not named twice.
function windowTitle(page, thread) {
    const title = page.title || untitled(page.url);
    return thread && thread.pages.length > 1 && thread.title && thread.title !== title ? title + " · " + thread.title : title;
}
// A private window's title (PLAN.md 3.14): "Private · <page title>", or "Private" with no page.
function privateTitle(page) {
    return page ? "Private · " + (page.title || untitled(page.url)) : "Private";
}

// The one word at a page row's right (PLAN.md 3.20): only what is happening, the most telling first: its ask waiting
// ("camera?", Asks.word), a failure ("failed"), a device it is using ("mic", "camera", "screen", "location"), its sound
// ("playing", "muted"); a loaded page not looked at for a day says when that was ("Mon"). Otherwise no word, and
// `detail` is how long since you saw it, which the row shows under the pointer. `accent`: the ask and the sound. Files
// it is fetching say so on their own rows under it.
var deviceWords = { mic: "mic", videocam: "camera", screen_share: "screen", location_on: "location" };
function pageWord(p, onScreen, now) {
    if (p.needsYou)
        return { word: p.asking || "asks you", accent: true, detail: "", glyph: askGlyph(p.asking) };
    if (p.failed)
        return { word: "failed", accent: false, detail: "" };
    if (p.capturing)
        return { word: deviceWords[p.capturing] ?? "in use", accent: false, detail: "", glyph: p.capturing };
    if (p.audible && !p.muted)
        return { word: "playing", accent: true, detail: "", glyph: "volume_up" };
    if (p.muted)
        return { word: "muted", accent: false, detail: "", glyph: "volume_off" };
    if (onScreen)
        return { word: "", accent: false, detail: "" };
    const seen = p.seen || p.lastActive || now;
    if (p.state !== "unloaded" && now - seen >= 86400000)
        return { word: when(seen, now), accent: false, detail: "" };
    return { word: "", accent: false, detail: age(seen, now) };
}
// What files still coming say: their share in ("40 %"), what has come when the size is unknown, "paused"; "" for none
function fetching(files) {
    const coming = files.filter(d => d.state === "running");
    if (coming.length === 0)
        return files.some(d => d.state === "paused") ? "paused" : "";
    const sized = coming.filter(d => d.total > 0);
    if (sized.length === 0)
        return Downloads.size(coming.reduce((n, d) => n + d.received, 0));
    const total = sized.reduce((n, d) => n + d.total, 0), got = sized.reduce((n, d) => n + Math.min(d.received, d.total), 0);
    return Math.floor(100 * got / total) + " %";
}
// How long since a page was seen: "5m", "2h", "3d" within the week, then its date ("28 Sep")
function age(ms, now) {
    const min = Math.max(1, Math.floor((now - ms) / 60000));
    if (min < 60)
        return min + "m";
    if (min < 24 * 60)
        return Math.floor(min / 60) + "h";
    if (min < 7 * 24 * 60)
        return Math.floor(min / (24 * 60)) + "d";
    const d = new Date(ms);
    return d.getDate() + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
}
// A folded task's word: a page in it asking (Asks.word), its files coming, its sound; otherwise none, and the row shows
// how many pages it holds. `files`: its pages' downloads.
function threadWord(pages, files) {
    const asking = pages.find(p => p.needsYou);
    if (asking)
        return { word: asking.asking || "asks you", accent: true, glyph: askGlyph(asking.asking) };
    const coming = fetching(files);
    if (coming)
        return { word: coming, accent: true, glyph: "download" };
    if (pages.some(p => p.audible && !p.muted))
        return { word: "playing", accent: true, glyph: "volume_up" };
    return { word: "", accent: false };
}
// A task's name in the rail: its own once renamed; one still named as its first page (a link opened from that page made
// it) is called by that page's site, so the name and its first row never read the same ("Skatteverket").
function taskName(t, pages) {
    const first = pages[0];
    if (t.named || t.title && (!first || t.title !== first.title))
        return t.title;
    const host = first ? split(first.url).host : "";
    const name = host.split(".").slice(-2, -1)[0] || host;
    return name ? name.charAt(0).toUpperCase() + name.slice(1) : "New task";
}
// The icon a task's row leads with: its most recently used page that has one
function leadIcon(pages) {
    let p = null;
    for (const q of pages)
        if (q.icon && (!p || (q.lastActive || 0) > (p.lastActive || 0)))
            p = q;
    return p ? p.icon : "";
}
// A task's pages with each run of three or more named alike but for a number at the end ("USB PD notes 4" to "12") as
// one entry, where `fold(page)` holds for the whole run: [{ page, run: null or { title: "USB PD notes 4–12", n } }]
function runs(pages, fold) {
    const stem = p => (p.title || "").replace(/\s*\d+$/, "");
    const numbered = p => stem(p) !== (p.title || "");
    const out = [];
    for (let i = 0; i < pages.length; i++) {
        const p = pages[i];
        let j = i;
        while (numbered(p) && j + 1 < pages.length && numbered(pages[j + 1]) && stem(pages[j + 1]) === stem(p))
            j++;
        if (j - i >= 2 && pages.slice(i, j + 1).every(fold)) {
            out.push({ page: p, run: { title: stem(p) + " " + /\d+$/.exec(p.title)[0] + "–" + /\d+$/.exec(pages[j].title)[0], n: j - i + 1 } });
            i = j;
        } else {
            out.push({ page: p, run: null });
        }
    }
    return out;
}

// A page's row, as the rail lists it
function pageRowOf(p, depth, current, now) {
    const w = pageWord(p, p.id === current, now);
    return {
        key: "p:" + p.id, type: "page", ref: p.id, title: p.title ? trimTitle(p.title, p.url) : untitled(p.url), icon: p.icon || "", glyph: card(p.url, "").glyph, depth: depth,
        current: p.id === current, dim: p.state === "unloaded", audible: !!p.audible, muted: !!p.muted,
        needsYou: !!p.needsYou, loading: !!p.loading, capturing: p.capturing || "", failed: p.failed || "",
        origin: p.from ? "from " + p.from + " · " + when(p.fromAt || p.lastActive, now) : "", word: w.word, accent: w.accent, detail: w.detail,
        wordGlyph: w.glyph || ""
    };
}

// The tabs along the top (Settings > Tabs): the Always pages as faces, then every page of every open task in the rail's
// order, whatever a task's fold; `edge` marks the first page of a task that sits beside one of several pages, where the
// strip draws a hairline. Rows carry the rail's roles, so the same sync keeps them.
function strip(session, options) {
    const opts = options || {};
    const now = opts.now || Date.now();
    const current = session.currentPage;
    const out = [];
    if (!opts.offTheRecord) {
        for (const id of session.always) {
            const p = session.pages[id];
            if (!p)
                continue;
            const r = pageRowOf(p, 0, current, now);
            out.push(Object.assign(r, { key: "a:" + id, type: "pin", title: p.title ? p.title.replace(/^\(\d+\)\s+/, "") : named(p.url),
                                        letter: (session.siteOf(p.url) || "?").charAt(0).toUpperCase(),
                                        // the unread count a page puts in its title as "(N) ", on its face
                                        count: Number((/^\((\d+)\)\s/.exec(p.title || "") || [0, 0])[1]) }));
        }
        // the pin used last while it is away from its start is a tab of its own, as the rail's page row under the faces
        const away = session.awayPin();
        if (away && session.pages[away])
            out.push(Object.assign(pageRowOf(session.pages[away], 0, current, now), { key: "away:" + away, type: "away" }));
    }
    let before = 0;
    for (const t of session.drawnThreads()) {
        const pages = t.pages.map(id => session.pages[id]).filter(p => p);
        pages.forEach((p, i) => {
            const r = pageRowOf(p, 0, current, now);
            r.thread = t.id;
            r.edge = i === 0 && before > 0 && (before > 1 || pages.length > 1);
            out.push(r);
        });
        before = pages.length;
    }
    return out;
}

// What the rail lists under New page and the Pinned faces (PLAN.md 3.20): this window's tasks in one order that a click
// never changes. A task of two or more pages is one row (its newest page's icon, its name, its word or how many pages
// it holds, an arrow), with its pages one step in under it while it is open; a task of one is its page's row. A task is
// open unless folded by hand (Session.isOpen). Then the first-run hint. Only what is open: History, Saved and Downloads
// are the rail's foot (earlier()). Rows carry one word each (pageWord).
// options: { now, listed: the pages whose several downloads are listed in place }
function build(session, options) {
    const opts = options || {};
    const now = opts.now || Date.now();
    const current = session.currentPage;
    const listed = opts.listed || [];
    // downloads under their pages; those whose page has no row the rail's foot says (Rail's Downloads)
    const byPage = {};
    for (const d of session.downloads || [])
        if (Downloads.place(d, session, now) === "page")
            (byPage[d.page] = byPage[d.page] || []).push(d);
    const out = [];
    const pageRow = (p, depth) => pageRowOf(p, depth, current, now);
    // A page's downloads under it: one file row, or several as one summary row that lists them under it on a
    // click. A failure or a warning waits on you, so it always has a row of its own (PLAN.md 8d).
    function downloadRows(p, depth) {
        const list = byPage[p.id] || [];
        const rest = list.filter(d => !Downloads.waits(Downloads.status(d)));
        if (rest.length === 1)
            out.push(Downloads.row(rest[0], depth + 1, false, now));
        if (rest.length >= 2) {
            const open = listed.indexOf(p.id) >= 0;
            out.push(Object.assign({ key: "s:" + p.id, type: "download", ref: p.id, page: p.id, status: "summary", depth: depth + 1, open: open },
                                   Downloads.summary(rest)));
            if (open)
                for (const d of rest)
                    out.push(Downloads.row(d, depth + 1, false, now));
        }
        for (const d of list)
            if (Downloads.waits(Downloads.status(d)))
                out.push(Downloads.row(d, depth + 1, false, now));
    }
    const pagesOf = t => t.pages.map(id => session.pages[id]).filter(p => p);
    // an open task's pages that may hide in a run: unloaded, not on screen, fetching nothing
    const quiet = p => p.state === "unloaded" && p.id !== current && !(byPage[p.id] || []).length;

    let afterOpen = false;
    for (const t of session.drawnThreads()) {
        const pages = pagesOf(t);
        // the air after an open task's pages, so the row after them never reads as one of them
        if (afterOpen)
            out.push({ key: "space:" + t.id, type: "space" });
        afterOpen = false;
        if (pages.length === 1) {
            out.push(pageRow(pages[0], 0));
            downloadRows(pages[0], 0);
            continue;
        }
        const open = session.isOpen(t);
        const w = open ? { word: "", accent: false } : threadWord(pages, [].concat(...pages.map(p => byPage[p.id] || [])));
        out.push({ key: "t:" + t.id, type: "thread", ref: t.id, title: taskName(t, pages), icon: leadIcon(pages), count: pages.length,
                   open: open, current: !open && pages.some(p => p.id === current), needsYou: pages.some(p => p.needsYou),
                   word: w.word, accent: w.accent, wordGlyph: w.glyph || "" });
        if (!open)
            continue;
        for (const r of runs(pages, quiet)) {
            if (r.run) {
                out.push(Object.assign(pageRow(r.page, 1), { key: "run:" + r.page.id, title: r.run.title, origin: r.run.n + " pages", word: "", wordGlyph: "", detail: "" }));
                continue;
            }
            out.push(pageRow(r.page, 1));
            downloadRows(r.page, 1);
        }
        afterOpen = true;
    }

    if (!session.learned.threads)
        out.push({ key: "hint", type: "hint", title: "Links you open from a page stay under it, as one task." });
    // just after a browser was brought over (Welcome): where its windows went, once, above them
    if (options && options.importHint)
        out.unshift({ key: "import-hint", type: "hint", title: options.importHint });
    return out;
}

// History (PLAN.md 3.21), the rail's list from its foot or Ctrl+H: closed tasks and closed pages, newest first: those of
// the last 7 days, then one Older row for the rest (`older`: listed, back to Recall.earlierDays); with `words` (the
// search) every one whose name, pages, addresses or where you stopped has them all. A closed task is a task's row, its
// icon at half strength and its word when it was closed; open (`unfolded`), its pages one step in, each saying where
// you stopped, and their files. A click on one of those pages brings the task back with that page on screen
// (Session.restoreThread).
function history(session, now, unfolded, older, words) {
    const w = words || [];
    const stopOf = p => { const s = Recall.current(p); return s ? s.heading : "" };
    const items = session.earlierThreads(now).map(t => ({ at: t.filedAt ?? t.lastActive, thread: t }))
        // a page closed before closed pages kept when has no time to show; Ctrl+Shift+T and @ still have it
        .concat(session.closedPages().filter(c => c.at).map(c => ({ at: c.at, closed: c })))
        .filter(it => {
            if (w.length === 0)
                return true;
            if (it.closed)
                return Recall.passes(it.closed.title + " " + it.closed.url + " " + stopOf({ url: it.closed.url, stopped: it.closed.stopped }), w);
            const pages = it.thread.pages.map(id => session.pages[id]).filter(p => p);
            return Recall.passes(it.thread.title + " " + pages.map(p => p.title + " " + p.url + " " + stopOf(p)).join(" "), w);
        })
        .sort((a, b) => b.at - a.at);
    const recent = w.length > 0 ? items : items.filter(it => now - it.at < 7 * 86400000);
    const out = [];
    for (const it of older ? items : recent) {
        if (it.closed) {
            const c = it.closed;
            out.push({ key: "c:" + c.id, type: "closed", ref: c.id, title: c.title || untitled(c.url), icon: c.icon || "",
                       glyph: card(c.url, "").glyph, word: when(c.at, now) });
            continue;
        }
        const t = it.thread, pages = t.pages.map(id => session.pages[id]).filter(p => p), open = !!unfolded[t.id];
        out.push({ key: "e:" + t.id, type: "earlier", ref: t.id, title: taskName(t, pages), icon: leadIcon(pages), count: pages.length,
                   open: open, word: when(it.at, now) });
        if (!open)
            continue;
        for (const r of runs(pages, () => true))
            out.push({ key: "f:" + r.page.id, type: "filed", ref: r.page.id, title: r.run ? r.run.title : r.page.title || untitled(r.page.url),
                       icon: r.page.icon || "", glyph: card(r.page.url, "").glyph, depth: 1,
                       origin: r.run ? r.run.n + " pages" : Recall.line(Recall.current(r.page)) });
        for (const d of session.downloads || [])
            if (t.pages.indexOf(d.page) >= 0)
                out.push(Downloads.row(d, 2, false, now));
        out.push({ key: "space:e:" + t.id, type: "space" });
    }
    if (!older && recent.length < items.length)
        out.push({ key: "older", type: "older", title: "Older", count: items.length - recent.length });
    return out;
}

// The rail list turned into History, Saved or Downloads, opened from the rail's foot (PLAN.md 3.21; Ctrl+H, Ctrl+Shift+O,
// Ctrl+J). options: { view: "history", "saved" or "downloads", filter (its words must all be in a row's text), open:
// { "folder:<name>": true } for the imported folders listed open, unfolded: { taskId: true } for History's closed tasks
// listed open, older: History's Older listed, editing: the Saved page edited in place, now }.
//   history    history()
//   saved      Saved tasks, then Pages: the saved pages, and each imported folder as a group
//   downloads  every download kept, newest first by day, each naming its page
function earlier(session, saved, options) {
    const o = options || {}, now = o.now || Date.now(), open = o.open || {};
    const words = Recall.words(o.filter);
    const out = [];
    let day = "";
    function dated(ms, row) {
        const d = Recall.day(ms, now);
        if (d !== day)
            out.push({ key: "day:" + d, type: "day", title: d });
        day = d;
        out.push(row);
    }
    if (o.view === "history")
        return history(session, now, o.unfolded || {}, !!o.older, words);
    if (o.view === "saved") {
        const threads = saved.threads.filter(t => Recall.passes(t.title + " " + t.pages.map(p => p.title + " " + p.url).join(" "), words));
        if (threads.length > 0)
            out.push({ key: "label:saved-threads", type: "day", title: "Saved tasks" });
        for (const t of threads)
            out.push({ key: "st:" + t.id, type: "savedThread", ref: t.id, title: t.title || "Task", count: t.pages.length });
        const pages = saved.pages.filter(p => Recall.passes(p.name + " " + p.url + " " + (p.folder || ""), words));
        const loose = pages.filter(p => !p.folder), folders = [];
        for (const p of pages)
            if (p.folder && folders.indexOf(p.folder) < 0)
                folders.push(p.folder);
        if (loose.length > 0 || folders.length > 0)
            out.push({ key: "label:saved-pages", type: "day", title: "Pages" });
        const pageRow = (p, depth) => p.id === o.editing ? { key: "edit:" + p.id, type: "edit", ref: p.id, depth: depth }
            : { key: "s:" + p.id, type: "saved", ref: p.id, title: p.name || untitled(p.url), icon: p.icon || "", glyph: card(p.url, "").glyph, depth: depth };
        for (const p of loose)
            out.push(pageRow(p, 0));
        for (const f of folders) {
            const inside = pages.filter(p => p.folder === f), isOpen = !!open["folder:" + f];
            out.push({ key: "g:" + f, type: "folder", ref: f, title: f, count: inside.length, open: isOpen });
            if (isOpen)
                for (const p of inside)
                    out.push(pageRow(p, 1));
        }
    } else if (o.view === "downloads") {
        const list = (session.downloads || []).slice().sort((a, b) => (b.started || 0) - (a.started || 0));
        for (const d of list) {
            const p = session.pages[d.page] ?? null;
            const from = p ? p.title || untitled(p.url) : d.from ? d.from.title || "" : "";
            if (!Recall.passes(d.file + " " + d.url + " " + from, words))
                continue;
            // its page as it is now, named as its row names it (a data: page never by its content); else as the record kept it
            dated(d.started || now, Downloads.row(d, 1, true, now, p ? Object.assign({}, p, { title: p.title || untitled(p.url) }) : null));
        }
    }
    return out;
}

// Brings `model` (a ListModel) in line with `rows` by key: unchanged rows stay, so the view keeps its
// delegates, scroll position and hover. Rows that went are removed where they were, rows that moved
// (the ghost row after Tab) are moved, and new rows are inserted, so each gets the view's transition.
function sync(model, rows) {
    const keys = new Set(rows.map(r => r.key));
    for (let i = model.count - 1; i >= 0; i--)
        if (!keys.has(model.get(i).key))
            model.remove(i);
    for (let i = 0; i < rows.length; i++) {
        const row = Object.assign({}, defaults, rows[i]);
        let j = i;
        while (j < model.count && model.get(j).key !== row.key)
            j++;
        if (j === model.count) {
            model.insert(i, row);
            continue;
        }
        if (j > i)
            model.move(j, i, 1);
        const have = model.get(i);
        for (const k in row)
            if (have[k] !== row[k]) {
                model.set(i, row);
                break;
            }
    }
}

// The row menus (PLAN.md 3.11): only the entries that apply, in the wireframe's order. Entries are
// { text, shortcut, action, arg }, { separator: true } or { text, sub: [entries] }. Hand to Claude, Open in new
// window and Delete thread wait for their phases. A private window (`offTheRecord`) has no Always and saves nothing.
// Earlier's rows (PLAN.md 3.7): a filed thread and each of its pages, a closed page, a Saved page and thread.
function menu(session, type, ref, offTheRecord) {
    const sep = { separator: true };
    function label(t) {
        return t.pages.length === 1 ? (session.pages[t.pages[0]].title || named(session.pages[t.pages[0]].url)) : t.title;
    }
    if (type === "page") {
        const p = session.pages[ref];
        if (!p)
            return [];
        const t = session.threadById(p.thread);
        const loaded = p.state !== "unloaded";
        const several = t.pages.length > 1;
        const others = session.openThreads().filter(o => o.id !== t.id)
            .map(o => ({ text: label(o), action: "moveTo", arg: o.id }));
        if (several)
            others.push({ text: "New task", action: "split" });
        const out = [];
        if (loaded)
            out.push({ text: "Reload", shortcut: "Ctrl+R", action: "reload" });
        out.push({ text: "Duplicate", action: "duplicate" });
        if (loaded)
            out.push({ text: p.muted ? "Unmute page" : "Mute page", shortcut: "Ctrl+M", action: "mute" });
        out.push({ text: "Copy link", action: "copy" }, sep);
        if (others.length > 0)
            out.push({ text: "Move to task", sub: others });
        if (several && t.pages.indexOf(ref) > 0)
            out.push({ text: "Split task from here", action: "splitFrom" });
        if (!offTheRecord)
            out.push({ text: "Pin", shortcut: "Ctrl+Shift+D", action: "always" });
        if (out[out.length - 1] !== sep)
            out.push(sep);
        out.push({ text: "Close page", shortcut: "Ctrl+W", action: "close" });
        if (several)
            out.push({ text: "Close other pages here", action: "closeOthers" });
        return out;
    }
    if (type === "thread") {
        const t = session.threadById(ref);
        const open = session.isOpen(t);
        return [
            { text: "Rename", shortcut: "F2", action: "rename" },
            { text: "New page here", action: "newHere" },
        ].concat(offTheRecord ? [] : [{ text: "Save task", action: "saveThread" }]).concat([
            { text: open ? "Fold" : "Open", action: "fold" },
            sep,
            { text: "Close task", shortcut: "Ctrl+Shift+W", action: "file" },
        ]);
    }
    if (type === "always") {
        const p = session.pages[ref];
        const at = session.always.indexOf(ref);
        const out = [];
        if (p.state !== "unloaded")
            out.push({ text: "Reload", action: "reload" }, { text: p.muted ? "Unmute" : "Mute", action: "mute" });
        out.push({ text: "Copy link", action: "copy" });
        if (at > 0)
            out.push({ text: "Move left", action: "moveLeft" });
        if (at < session.always.length - 1)
            out.push({ text: "Move right", action: "moveRight" });
        out.push(sep, { text: "Unpin", action: "removeAlways" });
        return out;
    }
    const here = !!session.current && !!session.current.thread;
    const forget = { text: "Forget", shortcut: "Shift+Delete", action: "forget" };
    if (type === "earlier") {
        const out = [{ text: "Reopen task", action: "restore" }];
        if (here)
            out.push({ text: "Open its last page in the current task", action: "openLast" });
        out.push({ text: "Copy link", action: "copyLast" }, { text: "Save task", action: "saveThread" }, sep, forget);
        return out;
    }
    // a page of a filed thread, listed open in Earlier
    if (type === "filed") {
        const p = session.pages[ref];
        if (!p)
            return [];
        const out = [{ text: "Reopen task", action: "restorePage" }];
        if (here)
            out.push({ text: "Open this page in the current task", action: "openPage" });
        out.push({ text: "Copy link", action: "copy" }, { text: "Save task", action: "saveThread", arg: p.thread }, sep, forget);
        return out;
    }
    if (type === "closed") {
        const out = here ? [{ text: "Open this page in the current task", action: "openClosed" }] : [];
        return out.concat([{ text: "Copy link", action: "copyClosed" }, sep, forget]);
    }
    if (type === "saved")
        return [{ text: "Edit", shortcut: "F2", action: "editSaved" }, { text: "Copy link", action: "copySaved" }, sep, { text: "Remove", action: "removeSaved" }];
    if (type === "savedThread")
        return [{ text: "Remove", action: "removeSavedThread" }];
    return [];
}
