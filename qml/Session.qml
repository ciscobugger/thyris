import QtQuick
import Browser
import "RailRows.js" as RailRows
import "Recall.js" as Recall

// Threads and pages behind the rail and the pill, persisted to threads.json. Rules in DESIGN.md.
// Each main window has one (PLAN.md 3.17). The first window's (`windowId` "") loads and saves threads.json; the
// others' share its lists and revision through `shared`, so the one file has one writer. Open threads belong to
// one window (`window` on the thread); Earlier, Always, closed pages and downloads are every window's.
// A private window's (PLAN.md 3.14) shares nothing and is kept in memory only: `offTheRecord`.
QtObject {
    id: session

    property string windowId: ""
    property QtObject shared: null      // the first window's Session, for every other window's
    property bool offTheRecord: false   // never saved: what it holds ends with its window

    // in thread order: { id, title, named, pages: [pageId], lastActive, earlier, filedAt, open, trail, window }; `open` is
    // false while folded by hand, otherwise the thread is open (isOpen, PLAN.md 3.20); `named`: renamed by hand
    // (RailRows.taskName); `trail` holds
    // the pages the thread navigated away from or closed, newest first: { url, title, icon, left }; `window` is the
    // windowId of the window whose rail holds it ("" or none: the first window's)
    property var threads: shared ? shared.threads : []
    // pageId -> { id, thread, url, title, icon, lastActive, seen, opener, state }; thread "" = Always.
    // `seen`: when the page stopped being the current one (the memory net's order). A page from another app has
    // `from` (the app) and `fromAt`; one moved from another window has `restore`
    // ({ history, scroll }) until it is shown. `stopped`: where you stopped on it (Recall.js, PLAN.md 3.7).
    property var pages: shared ? shared.pages : ({})
    property var always: shared ? shared.always : []    // page ids of the Always faces under the rail's New page
    // most recent last, for Ctrl+Shift+T: a closed page's { id, thread, url, title, icon, at, stopped }, { thread, title,
    // filed }, a peek's closed before 2026-10-14 { id, thread: "", url, title, from, at }, or a closed window's { window, title, threads,
    // order, state, current }, after its single pages' { id, thread, page, url, title, icon, at, stopped, closedWith: window }
    property var closed: shared ? shared.closed : []
    // oldest first; Downloads.js describes a record. Kept for Earlier > Downloads (PLAN.md 3.7), at most 500.
    property var downloads: shared ? shared.downloads : []
    // the rail's two first-run hints go for good once a thread has had two pages / after the first pin
    property var learned: shared ? shared.learned : ({ threads: false, always: false })
    property string currentPage: ""
    property int revision: shared ? shared.revision : 0    // bumped on every change; bindings read it to refresh
    // the windows' records for threads.json (Main.windowRecords), the first window's first
    property var windowRecords: null
    // what load() read: the other windows' records, for Main to open them
    property var loadedWindows: []
    property var loadedWindow: null     // the first window's record

    readonly property var current: { revision; return pages[currentPage] ?? null }
    readonly property var currentThread: { revision; return current ? threadById(current.thread) : null }

    property Timer saveTimer: Timer { interval: 800; onTriggered: session.save() }

    function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7) }
    function touch() {
        if (shared) {
            shared.touch();
            return;
        }
        revision++;
        if (!offTheRecord)
            saveTimer.restart();
    }
    // a window's fold or size changed: its record is saved, nothing redraws
    function saveSoon() { (shared ?? session).saveTimer.restart() }
    function threadById(id) { return threads.find(t => t.id === id) ?? null }
    function ownThread(t) { return !t.earlier && (t.window ?? "") === windowId }

    function newThread(title) {
        const t = { id: uid(), title: title, pages: [], lastActive: Date.now(), earlier: false, window: windowId };
        threads.unshift(t);
        touch();
        return t.id;
    }

    // Returns "" when the thread is gone; no page is made then.
    function addPage(threadId, url, afterPageId, openerId) {
        const t = threadById(threadId);
        if (!t)
            return "";
        const p = { id: uid(), thread: threadId, url: url, title: "", icon: "", lastActive: Date.now(), state: "unloaded" };
        if (openerId)
            p.opener = openerId;
        pages[p.id] = p;
        const at = afterPageId ? t.pages.indexOf(afterPageId) : -1;
        if (at >= 0)
            t.pages.splice(at + 1, 0, p.id);
        else
            t.pages.push(p.id);
        if (t.pages.length >= 2)
            learned.threads = true;
        touch();
        return p.id;
    }

    function activate(pageId) {
        const p = pages[pageId];
        if (!p)
            return;
        const t = threadById(p.thread);
        p.lastActive = Date.now();
        if (currentPage !== pageId && pages[currentPage])
            pages[currentPage].seen = p.lastActive;
        if (t) {
            t.lastActive = p.lastActive;
            if (t.earlier)
                unfile(t);
            if (t.open === false)
                delete t.open;      // the current page's thread is always open
        }
        currentPage = pageId;
        touch();
    }

    // A link opened from a page joins the opener's thread right after it, after the pages it opened
    // before, so three middle-clicks keep their order. From an Always site it starts a thread of one.
    function addFromOpener(openerId, url, title) {
        const opener = pages[openerId];
        if (!opener)
            return "";
        if (!opener.thread)
            return addPage(newThread(title), url, "");
        const list = threadById(opener.thread).pages;
        let at = list.indexOf(openerId);
        while (at + 1 < list.length && pages[list[at + 1]].opener === openerId)
            at++;
        return addPage(opener.thread, url, list[at], openerId);
    }

    function update(pageId, fields) {
        const p = pages[pageId];
        if (!p)
            return;
        // navigating away: the page left joins its thread's trail (Ctrl+L "In this thread")
        if (fields.url !== undefined && fields.url !== p.url && p.url && p.title)
            leave(p);
        // a pin loading its start follows that load's redirects on its own site (homeOf)
        if (p.homing) {
            if (fields.url && siteOf(fields.url) === siteOf(p.home))
                p.home = fields.url;
            if (fields.loading === true)
                p.homing = "loading";
            else if (fields.loading === false && p.homing === "loading")
                delete p.homing;
        }
        let differs = false;
        for (const k in fields)
            if (p[k] !== fields[k]) { p[k] = fields[k]; differs = true; }
        if (differs)
            touch();
    }

    // Ctrl+W: a page closes; a thread of one goes with its page and is not filed (PLAN.md 3.12).
    // Always pages are removed with removeAlways instead. Returns the page ids whose views should go.
    function closePage(pageId) {
        const p = pages[pageId];
        if (!p)
            return [];
        const t = threadById(p.thread);
        if (!t)
            return [];
        closed.push({ id: uid(), thread: t.id, url: p.url, title: p.title, icon: p.icon || "", at: Date.now(), stopped: p.stopped ?? null });
        if (t.pages.length > 1 && p.url && p.title)
            leave(p);
        dropPage(pageId);
        if (currentPage === pageId)
            currentPage = (threadById(t.id) ? mostRecentPage(t.id) : null) ?? mostRecentPage() ?? "";
        touch();
        return [pageId];
    }

    // Takes a page out of its thread (a thread left empty goes too) and out of the page map.
    function dropPage(pageId) {
        detach(pageId);
        delete pages[pageId];
    }
    function detach(pageId) {
        const t = threadById(pages[pageId].thread);
        if (!t)
            return;
        t.pages.splice(t.pages.indexOf(pageId), 1);
        if (t.pages.length === 0)
            threads.splice(threads.indexOf(t), 1);
    }

    // Ctrl+Shift+W, Close thread: a multi-page thread moves into Earlier with its pages, unloaded;
    // a thread of one just closes. Returns the page ids whose views should go.
    function fileThread(threadId) {
        const t = threadById(threadId);
        if (!t || t.earlier)
            return [];
        if (t.pages.length === 1)
            return closePage(t.pages[0]);
        t.earlier = true;
        t.filedAt = Date.now();
        delete t.open;
        for (const id of t.pages)
            Object.assign(pages[id], { state: "unloaded", loading: false, audible: false });
        closed.push({ thread: threadId, title: t.title, filed: true });
        if (current && current.thread === threadId)
            currentPage = mostRecentPage() ?? "";
        touch();
        return t.pages.slice();
    }

    // Back among this window's open threads, first in the rail, as a new thread would be.
    function unfile(t) {
        t.earlier = false;
        delete t.filedAt;
        t.window = windowId;
        threads.splice(threads.indexOf(t), 1);
        threads.unshift(t);
    }

    // An Earlier thread comes back whole; `pageId` (one of its pages) or the page it last showed is current.
    function restoreThread(threadId, pageId) {
        const t = threadById(threadId);
        if (!t)
            return;
        if (t.earlier)
            unfile(t);
        activate(pageId && t.pages.indexOf(pageId) >= 0 ? pageId : mostRecentPage(threadId));
    }

    // Filed threads, most recently filed first.
    function filedThreads() {
        return threads.filter(t => t.earlier).sort((a, b) => (b.filedAt ?? b.lastActive) - (a.filedAt ?? a.lastActive));
    }
    // What the Earlier list shows (PLAN.md 3.7): the filed threads seen in the last 90 days. History and @ keep the rest.
    function earlierThreads(now) {
        const since = (now || Date.now()) - Recall.earlierDays * 86400000;
        return filedThreads().filter(t => Math.max(t.filedAt ?? 0, t.lastActive ?? 0) >= since);
    }
    // Closed pages (not filed threads or windows), newest first, one per address.
    function closedPages() {
        const out = [], seen = new Set();
        for (let i = closed.length - 1; i >= 0; i--) {
            const c = closed[i];
            if (c.filed || c.window || !c.url || seen.has(c.url))
                continue;
            seen.add(c.url);
            out.push(c);
        }
        return out;
    }

    // Where you stopped on a page (Recall.js): null clears it; the same place again changes nothing.
    function setStopped(pageId, stop) {
        const p = pages[pageId];
        if (!p)
            return;
        const place = s => s ? JSON.stringify([s.url, s.heading, s.index, s.offset, s.x, s.y]) : "";
        if (place(p.stopped) === place(stop))
            return;
        p.stopped = stop;
        touch();
    }

    // Forgetting (Shift+Delete, PLAN.md 3.7). Each returns what its undo puts back, or null when there was nothing.
    // A filed thread goes with its pages; its finished files stay listed in Earlier > Downloads only (`quiet`).
    function forgetThread(threadId) {
        const t = threadById(threadId);
        if (!t || !t.earlier)
            return null;
        const at = threads.indexOf(t), gone = t.pages.map(id => pages[id]).filter(p => p);
        const quiet = downloads.filter(d => t.pages.indexOf(d.page) >= 0 && !d.quiet && d.state !== "running" && d.state !== "paused");
        threads.splice(at, 1);
        for (const p of gone)
            delete pages[p.id];
        for (const d of quiet)
            d.quiet = true;
        touch();
        return { thread: t, at: at, pages: gone, quiet: quiet.map(d => d.id) };
    }
    // One page of a filed thread; the last one takes the thread with it.
    function forgetPage(pageId) {
        const p = pages[pageId];
        const t = p ? threadById(p.thread) : null;
        if (!t || !t.earlier)
            return null;
        if (t.pages.length === 1)
            return forgetThread(t.id);
        const at = t.pages.indexOf(pageId);
        t.pages.splice(at, 1);
        delete pages[pageId];
        touch();
        return { thread: t, page: p, pageAt: at };
    }
    // Clear browsing data (Settings > Privacy, PLAN.md 3.15): every closed page goes, a closed window's single pages too,
    // in place (every window's Session holds this list); filed threads stay, and a closed window brings back those alone.
    function clearClosedPages() {
        for (let i = closed.length - 1; i >= 0; i--)
            if (!closed[i].filed && !closed[i].window)
                closed.splice(i, 1);
        touch();
    }
    // A closed page, every time it was closed.
    function forgetClosed(entryId) {
        const c = closed.find(e => e.id === entryId);
        if (!c)
            return null;
        const taken = [];
        for (let i = closed.length - 1; i >= 0; i--)
            if (!closed[i].filed && !closed[i].window && closed[i].url === c.url)
                taken.unshift({ at: i, entry: closed.splice(i, 1)[0] });
        touch();
        return { closed: taken };
    }
    function unforget(u) {
        if (u.closed) {
            for (const e of u.closed)
                closed.splice(Math.min(e.at, closed.length), 0, e.entry);
        } else if (u.page) {
            pages[u.page.id] = u.page;
            if (threadById(u.thread.id))
                u.thread.pages.splice(u.pageAt, 0, u.page.id);
        } else {
            for (const p of u.pages)
                pages[p.id] = p;
            threads.splice(Math.min(u.at, threads.length), 0, u.thread);
            for (const id of u.quiet) {
                const d = downloadById(id);
                if (d)
                    delete d.quiet;
            }
        }
        touch();
    }

    // Drops filed entries whose thread is back or gone, and closed windows with nothing left to bring back;
    // returns what Ctrl+Shift+T would bring back.
    function nextClosed() {
        while (closed.length > 0) {
            const c = closed[closed.length - 1];
            if (c.window ? windowLeft(c) : !c.filed || threadById(c.thread)?.earlier)
                return c;
            closed.pop();
        }
        return null;
    }
    function windowLeft(c) { return c.threads.some(id => threadById(id)?.earlier) || closed.some(e => e.closedWith === c.window) }
    function reopenName() {
        const c = nextClosed();
        return !c ? "" : c.window ? "the window " + c.title : (c.title || RailRows.named(c.url || ""));
    }

    // A closed window's entry is Main's to reopen (takeWindow).
    function reopenClosed() {
        const c = nextClosed();
        if (!c || c.window)
            return "";
        closed.pop();
        const t = threadById(c.thread);
        if (t && t.earlier)
            unfile(t);
        if (c.filed) {
            touch();
            return mostRecentPage(c.thread);
        }
        return reopenPage(c, t);
    }
    // A closed page again, in its thread while that is open, else as a thread of one; where you stopped comes with it
    // (PLAN.md 3.7). An untitled page is named as the rail names it: a data: page never by its content (3.17).
    function reopenPage(c, t) {
        const id = addPage(t && !t.earlier ? t.id : newThread(c.title || RailRows.named(c.url)), c.url, "");
        if (c.from)
            Object.assign(pages[id], { from: c.from, fromAt: Date.now() });
        if (c.stopped)
            pages[id].stopped = c.stopped;
        return id;
    }
    // One closed page (@, Earlier): it leaves the closed list, every time it was closed, and opens. Returns its page id.
    function reopenEntry(entryId) {
        const c = closed.find(e => e.id === entryId);
        if (!c)
            return "";
        for (let i = closed.length - 1; i >= 0; i--)
            if (!closed[i].filed && !closed[i].window && closed[i].url === c.url)
                closed.splice(i, 1);
        return reopenPage(c, threadById(c.thread));
    }

    // A window closed while another is open (PLAN.md 3.17): its multi-page threads file under Earlier, its single
    // pages go to closed pages, and an entry after them lets Ctrl+Shift+T in another window bring the whole window
    // back. `title` names it, `state` is its fold and size. Returns the page ids whose views go.
    function closeWindow(title, state) {
        const key = uid(), open = openThreads(), gone = [], filed = [];
        for (const t of open) {
            gone.push(...t.pages);
            if (t.pages.length > 1) {
                t.earlier = true;
                t.filedAt = Date.now();
                delete t.open;
                for (const id of t.pages)
                    Object.assign(pages[id], { state: "unloaded", loading: false, audible: false });
                filed.push(t.id);
            } else {
                const p = pages[t.pages[0]];
                closed.push({ id: uid(), thread: t.id, page: p.id, url: p.url, title: p.title, icon: p.icon || "", from: p.from, at: Date.now(),
                              stopped: p.stopped ?? null, closedWith: key });
                dropPage(p.id);
            }
        }
        if (open.length > 0)
            closed.push({ window: key, title: title, threads: filed, order: open.map(t => t.id), state: state, current: currentPage });
        currentPage = "";
        touch();
        return gone;
    }
    // Ctrl+Shift+T on a closed window: its entry and its single pages leave the closed list; returns the entry with
    // `singles`, those pages' entries, or null when the next thing to reopen is not a window.
    function takeWindow() {
        const c = nextClosed();
        if (!c || !c.window)
            return null;
        closed.pop();
        const singles = closed.filter(e => e.closedWith === c.window);
        // in place: every window's Session holds this list
        for (let i = closed.length - 1; i >= 0; i--)
            if (closed[i].closedWith === c.window)
                closed.splice(i, 1);
        touch();
        return Object.assign({}, c, { singles: singles });
    }
    // The window taken back (takeWindow) comes back in this Session's window in its rail order: its filed threads
    // still in Earlier, its single pages as threads of one, where you stopped with them. The page it showed is current,
    // or its most recent one.
    function restoreWindow(w) {
        let current = "";
        for (const id of w.order) {
            const t = threadById(id), single = w.singles.find(e => e.thread === id);
            if (t && t.earlier && w.threads.indexOf(id) >= 0) {
                t.earlier = false;
                delete t.filedAt;
                t.window = windowId;
                threads.splice(threads.indexOf(t), 1);
                placeThread(t, "");
                if (t.pages.indexOf(w.current) >= 0)
                    current = w.current;
            } else if (single) {
                const n = newThread(single.title || RailRows.named(single.url));
                moveThread(n, "");
                const p = addPage(n, single.url, "");
                Object.assign(pages[p], { title: single.title || "", icon: single.icon || "" }, single.from ? { from: single.from, fromAt: Date.now() } : {},
                              single.stopped ? { stopped: single.stopped } : {});
                if (single.page === w.current)
                    current = p;
            }
        }
        currentPage = current || (mostRecentPage() ?? "");
        touch();
    }
    // A thread dragged onto this window's rail from another window's (PLAN.md 3.13, 3.17) moves here, before
    // `beforeThreadId` ("": after the open threads).
    function adoptThread(threadId, beforeThreadId) {
        const t = threadById(threadId);
        if (!t || t.earlier || threadId === beforeThreadId)
            return;
        threads.splice(threads.indexOf(t), 1);
        t.window = windowId;
        delete t.open;
        placeThread(t, beforeThreadId);
        touch();
    }

    // Most recently used page, within one thread or across this window's open threads.
    function mostRecentPage(threadId) {
        let best = null;
        for (const t of threads) {
            if (threadId ? t.id !== threadId : !ownThread(t))
                continue;
            for (const id of t.pages)
                if (!best || pages[id].lastActive > pages[best].lastActive)
                    best = id;
        }
        return best;
    }

    // Where Back goes on a page with nothing earlier in its own history: the page whose link opened it, while both are
    // in the same thread ("" for none)
    function backTo(pageId) {
        const p = pages[pageId], o = p && p.opener ? pages[p.opener] : null;
        return o && o.thread === p.thread ? o.id : "";
    }

    function setOpen(threadId, open) {
        const t = threadById(threadId);
        if (t && t.open !== open) {
            t.open = open;
            touch();
        }
    }

    // The site a URL belongs to, for Always (PLAN.md 3.12): its host without "www.". Hosts, not
    // registrable domains, so Gmail and Calendar keep a cell each.
    function siteOf(url) {
        return ((/^[a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?(?:www\.)?([^\/:?#]+)/i.exec(url || "") ?? [])[1] ?? "").toLowerCase();
    }

    // One Always cell per site: an existing cell for the same site is returned instead.
    function addAlways(url, title, icon) {
        const have = always.find(id => siteOf(pages[id].url) === siteOf(url));
        if (have)
            return have;
        const p = { id: uid(), thread: "", url: url, home: url, homing: true, title: title ?? "", icon: icon ?? "", lastActive: Date.now(),
                    state: "unloaded" };
        pages[p.id] = p;
        always.push(p.id);
        learned.always = true;
        touch();
        return p.id;
    }

    // Keep in Always (drag to the foot, row menu, Ctrl+Shift+D). A thread of one acts like a tab, so the
    // page itself moves into the cell; a page of a larger thread stays with its task and its site gets a
    // cell of its own. Returns the cell's page id.
    function keepInAlways(pageId) {
        const p = pages[pageId];
        if (!p || !p.thread)
            return pageId;
        const t = threadById(p.thread);
        const have = always.find(id => siteOf(pages[id].url) === siteOf(p.url));
        if (have || t.pages.length > 1) {
            const origin = /^[a-z]+:\/\/[^\/?#]+/i.exec(p.url);
            return have ?? (origin ? addAlways(origin[0] + "/", siteOf(p.url), p.icon) : "");
        }
        detach(pageId);
        p.thread = "";
        p.home = p.url;
        always.push(pageId);
        learned.always = true;
        touch();
        return pageId;
    }

    // Remove from Always: the cell and its page go. Returns the page ids whose views should go.
    function removeAlways(pageId) {
        const at = always.indexOf(pageId);
        if (at < 0)
            return [];
        always.splice(at, 1);
        delete pages[pageId];
        if (currentPage === pageId)
            currentPage = mostRecentPage() ?? "";
        touch();
        return [pageId];
    }

    function moveAlways(pageId, delta) {
        const at = always.indexOf(pageId), to = at + delta;
        if (at < 0 || to < 0 || to >= always.length)
            return;
        always.splice(to, 0, always.splice(at, 1)[0]);
        touch();
    }

    // An Always site keeps its cell for its own site: a link to another site leaves it (PLAN.md 3.12).
    function leavesAlways(pageId, url) {
        const p = pages[pageId];
        return !!p && p.thread === "" && /^https?:/i.test(url) && siteOf(url) !== siteOf(p.url);
    }

    // A pin's start (PLAN.md 3.12): the address it was pinned at, which follows the redirects of a load of it
    // (mail.google.com/ to /mail/u/0/); pins from before 2026-10-23 start at their site's root. Its address with
    // another # part is still the start, so reading a mail in Gmail is not away from it.
    function homeOf(pageId) {
        const p = pages[pageId];
        return p ? p.home || ((/^[a-z]+:\/\/[^\/?#]+/i.exec(p.url) ?? [""])[0] + "/") : "";
    }
    function awayFromHome(pageId) {
        const p = pages[pageId];
        const spot = url => String(url).split("#")[0].replace(/^[a-z][a-z0-9+.-]*:\/\/(www\.)?/i, "").replace(/\/+$/, "");
        return !!p && p.thread === "" && !!p.url && spot(p.url) !== spot(homeOf(pageId));
    }
    // The pin used last, while it is away from its start: its page shows as a row under the pins, so what you
    // opened in it is not hidden in its cell (immaculate_chipmunk, 2026-10-23)
    function awayPin() {
        const last = always.reduce((a, id) => !a || (pages[id].lastActive ?? 0) > (pages[a].lastActive ?? 0) ? id : a, "");
        return last && awayFromHome(last) ? last : "";
    }
    // Back to the start: Main loads homeOf in the pin's view
    function sendHome(pageId) {
        const p = pages[pageId];
        if (!p || p.thread !== "")
            return "";
        p.home = homeOf(pageId);
        p.homing = true;
        touch();
        return p.home;
    }

    // This window's open threads, top to bottom.
    function openThreads() { return threads.filter(t => ownThread(t)) }
    // Whether a task lists its pages under its row or is its row alone, folded where it is (PLAN.md 3.20): open unless
    // folded by hand. Tasks folded while you were elsewhere took two clicks to reach a page (the owner, 2026-10-16).
    function isOpen(t) { return t.open !== false }
    // The tasks the rail draws, in thread order: the open threads with a page.
    function drawnThreads() {
        return openThreads().filter(t => t.pages.some(id => pages[id]));
    }
    // The pages in the order the rail draws them, for Ctrl+Tab and Ctrl+1..9: a folded task is its row, its last-seen
    // page.
    function railOrder() {
        const out = [];
        for (const t of drawnThreads()) {
            const listed = t.pages.filter(id => pages[id]);
            if (listed.length > 1 && !isOpen(t))
                out.push(mostRecentPage(t.id));
            else
                out.push(...listed);
        }
        return out;
    }
    // The open thread `delta` steps from the current page's in drawn order (wrapping), for Alt+PgDn / Alt+PgUp.
    function nearThread(delta) {
        const open = drawnThreads();
        if (open.length === 0)
            return null;
        const at = open.findIndex(t => current && t.id === current.thread);
        return open[((at < 0 ? (delta > 0 ? -1 : 0) : at) + delta + open.length) % open.length];
    }

    // Moves a page into `threadId` before `beforeId` (at the end for ""). A thread left empty goes.
    function movePage(pageId, threadId, beforeId) {
        const p = pages[pageId], t = threadById(threadId);
        if (!p || !t || t.earlier || pageId === beforeId || (p.thread === threadId && t.pages.length === 1))
            return;
        detach(pageId);
        p.thread = threadId;
        const at = beforeId ? t.pages.indexOf(beforeId) : -1;
        t.pages.splice(at >= 0 ? at : t.pages.length, 0, pageId);
        if (t.pages.length >= 2)
            learned.threads = true;
        touch();
    }

    // A page leaves its thread and becomes a thread of one in this window, placed before `beforeThreadId` (after
    // the open threads for ""). A thread of one simply moves, from another window's rail too.
    function splitPage(pageId, beforeThreadId) {
        const p = pages[pageId];
        if (!p || !p.thread)
            return;
        const old = threadById(p.thread);
        let t = old;
        if (old.pages.length > 1) {
            detach(pageId);
            t = { id: uid(), title: p.title || siteOf(p.url) || "New task", pages: [pageId], lastActive: p.lastActive, earlier: false, window: windowId };
            p.thread = t.id;
        } else {
            if (t.id === beforeThreadId)
                return;
            threads.splice(threads.indexOf(t), 1);
            t.window = windowId;
        }
        placeThread(t, beforeThreadId);
        touch();
    }

    // Split thread from here: this page and the ones after it become a new thread, right below.
    function splitFrom(pageId) {
        const p = pages[pageId];
        const old = p ? threadById(p.thread) : null;
        const at = old ? old.pages.indexOf(pageId) : -1;
        if (at <= 0)
            return "";
        const t = { id: uid(), title: p.title || siteOf(p.url) || "New task", pages: old.pages.splice(at), lastActive: p.lastActive, earlier: false,
                    window: windowId };
        for (const id of t.pages)
            pages[id].thread = t.id;
        const next = openThreads()[openThreads().indexOf(old) + 1];
        placeThread(t, next ? next.id : "");
        touch();
        return t.id;
    }

    function moveThread(threadId, beforeThreadId) {
        const t = threadById(threadId);
        if (!t || threadId === beforeThreadId)
            return;
        threads.splice(threads.indexOf(t), 1);
        placeThread(t, beforeThreadId);
        touch();
    }
    function placeThread(t, beforeThreadId) {
        const before = threadById(beforeThreadId);
        let at = before ? threads.indexOf(before) : threads.findIndex(x => x.earlier);
        threads.splice(at < 0 ? threads.length : at, 0, t);
    }

    // Ctrl+Shift+PgUp / PgDn: one place up or down; past its thread's edge the page joins the neighbour
    // thread, at the end of the one above or the start of the one below.
    function shiftPage(pageId, delta) {
        const p = pages[pageId];
        const t = p ? threadById(p.thread) : null;
        if (!t)
            return;
        const at = t.pages.indexOf(pageId), to = at + delta;
        if (to >= 0 && to < t.pages.length) {
            t.pages.splice(to, 0, t.pages.splice(at, 1)[0]);
            touch();
            return;
        }
        // past the edge: the thread above or below as the rail draws them
        const open = drawnThreads();
        const near = open[open.indexOf(t) + delta];
        if (near)
            movePage(pageId, near.id, delta > 0 ? near.pages[0] : "");
    }

    // Close other pages here: the thread keeps only this page. Returns the page ids whose views should go.
    function closeOthers(pageId) {
        const p = pages[pageId];
        const t = p ? threadById(p.thread) : null;
        if (!t)
            return [];
        const gone = t.pages.filter(id => id !== pageId);
        for (const id of gone)
            closePage(id);
        return gone;
    }

    function rename(threadId, title) {
        const t = threadById(threadId);
        if (t && title.trim() !== "" && t.title !== title.trim()) {
            t.title = title.trim();
            t.named = true;
            touch();
        }
    }

    // Words that say nothing about a task, and the URL parts every page has.
    readonly property var stopWords: new Set([
        "the", "and", "for", "with", "from", "how", "what", "why", "when", "where", "who", "which", "this", "that",
        "are", "was", "not", "you", "your", "can", "does", "into", "about",
        "och", "att", "det", "som", "för", "med", "den", "till", "från", "har", "inte", "ett", "var", "hur",
        "vad", "när", "jag", "men", "kan", "ska", "eller", "efter", "utan", "över", "under", "också", "sig",
        "http", "https", "www", "com", "org", "net", "html", "htm", "php", "index"
    ])
    // Qt's JS engine has no \p{L}: letters are ASCII plus everything from U+00C0 (åäö, Greek, ...).
    function wordsOf(s) {
        return (s || "").toLowerCase().split(/[^0-9a-z\u00c0-\uffff]+/).filter(w => w.length >= 3 && !stopWords.has(w))
    }
    // filter: the threads and pages lists can be replaced one after the other
    function threadWords(t) {
        return new Set(wordsOf(t.title + " " + t.pages.map(id => pages[id]).filter(p => p).map(p => p.title + " " + p.url).join(" ")))
    }

    // The typed words split into finished ones and the word still being typed (no space after it yet).
    function typedWords(query) {
        const words = [...new Set(wordsOf(query))];
        const m = /([0-9a-z\u00c0-\uffff]+)$/i.exec(query || "");
        const tail = m ? wordsOf(m[1])[0] : undefined;
        return tail === undefined ? { full: words, partial: "" } : { full: words.filter(w => w !== tail), partial: tail };
    }
    // What a thread shares with the typed words; the word being typed counts as a prefix of one of the thread's.
    function sharedWith(typed, bag) {
        const out = typed.full.filter(w => bag.has(w));
        if (typed.partial && [...bag].some(b => b.startsWith(typed.partial)))
            out.push(typed.partial);
        return out;
    }

    // The typed words a thread shares, for the new-page bar's "shares:" line.
    function sharedWords(query, threadId) {
        const t = threadById(threadId);
        return t ? sharedWith(typedWords(query), threadWords(t)) : [];
    }

    // Thread a new page probably belongs to, or "" for a new thread (PLAN.md 3.3). A thread is over the
    // threshold when it shares two of the typed words (the only one, for a one-word query). The word
    // still being typed counts only once it matches, so typing it never flips the line away and back.
    // Ties keep `keep` (the thread the bar already shows), then the current thread.
    function predictThread(query, keep) {
        const typed = typedWords(query);
        let best = "", bestScore = 0;
        for (const t of threads) {
            if (!ownThread(t))
                continue;
            const shared = sharedWith(typed, threadWords(t));
            const counted = typed.full.length + (shared.indexOf(typed.partial) >= 0 && typed.partial ? 1 : 0);
            const score = shared.length;
            if (score === 0 || score < Math.min(2, counted))
                continue;
            const preferred = t.id === keep || (best !== keep && current && current.thread === t.id);
            if (score > bestScore || (score === bestScore && preferred)) {
                best = t.id;
                bestScore = score;
            }
        }
        return best;
    }

    // Downloads (PLAN.md 8d). `quiet`: a progress tick, which neither puts off the save nor redraws; the tick
    // bumps `revision` once for all its files. Returns whether anything changed.
    function addDownload(fields) {
        const d = Object.assign({ id: uid(), page: "", url: "", file: "", path: "", total: -1, received: 0, left: -1, state: "running",
                                  reason: "", warn: "", started: Date.now(), finished: 0, opened: 0, from: null }, fields);
        downloads.push(d);
        touch();
        return d.id;
    }
    function downloadById(id) { return downloads.find(d => d.id === id) ?? null }
    function updateDownload(id, fields, quiet) {
        const d = downloadById(id);
        if (!d)
            return false;
        let differs = false;
        for (const k in fields)
            if (d[k] !== fields[k]) { d[k] = fields[k]; differs = true; }
        if (differs && !quiet)
            touch();
        return differs;
    }
    function removeDownload(id) {
        const at = downloads.findIndex(d => d.id === id);
        if (at < 0)
            return;
        downloads.splice(at, 1);
        touch();
    }

    // Pages left behind by navigation or closing; the newest entry per URL, at most 10.
    function leave(p) {
        const t = threadById(p.thread);
        if (!t)
            return;
        const trail = (t.trail ?? []).filter(e => e.url !== p.url);
        trail.unshift({ url: p.url, title: p.title, icon: p.icon || "", left: Date.now() });
        t.trail = trail.slice(0, 10);
    }

    function save() {
        if (offTheRecord)
            return;
        // closed pages are Ctrl+Shift+T's and Earlier's (PLAN.md 3.7)
        Store.save("threads", { threads: threads, pages: pages, always: always, closed: closed.slice(-300),
                                currentPage: currentPage, learned: learned, downloads: downloads.slice(-500),
                                windows: windowRecords ? windowRecords() : [] });
    }

    function load() {
        const s = Store.load("threads");
        if (!s || !s.threads)
            return false;
        pages = s.pages ?? {};
        threads = s.threads.filter(t => t.pages && t.pages.every(id => pages[id]) && t.pages.length > 0);
        always = (s.always ?? []).filter(id => pages[id]);
        // a page no thread or Always cell holds is never shown again
        const held = new Set(always);
        for (const t of threads)
            t.pages.forEach(id => held.add(id));
        for (const id in pages)
            if (held.has(id))
                Object.assign(pages[id], { state: "unloaded", loading: false, audible: false, needsYou: false, asking: "", capturing: "", failed: "", downloading: false });
            else
                delete pages[id];
        closed = s.closed ?? [];
        // entries from before closed pages had ids (Earlier and @ name them by it)
        for (const c of closed)
            if (!c.id && !c.window && !c.filed)
                c.id = uid();
        // Qt WebEngine cancels what is still coming when the browser quits and keeps no download history: those
        // are failures now, which Retry fetches again; a held insecure one was never fetched, and goes
        downloads = (s.downloads ?? []).filter(d => d && d.id && d.state !== "blocked").map(d =>
            d.state === "running" || d.state === "paused" ? Object.assign(d, { state: "failed", reason: "browser closed", left: -1 }) : d);
        learned = s.learned ?? { threads: threads.some(t => t.pages.length >= 2), always: always.length > 0 };
        // The first record is this window's: its threads, and any a record no longer names, become "". The other
        // records are for Main to open (PLAN.md 3.17, restore).
        const records = (s.windows ?? []).filter(w => w && typeof w.id === "string");
        const others = new Set(records.slice(1).map(w => w.id));
        for (const t of threads)
            if (!t.earlier && !others.has(t.window ?? ""))
                t.window = "";
        loadedWindow = records[0] ?? null;
        loadedWindows = records.slice(1);
        const shown = loadedWindow ? loadedWindow.currentPage : s.currentPage;
        currentPage = pages[shown] && ownOrAlways(shown) ? shown : (mostRecentPage() ?? "");
        revision++;
        return threads.length > 0;
    }
    // a page this window can show: one of its threads', or an Always cell's
    function ownOrAlways(pageId) {
        const p = pages[pageId];
        return !!p && (p.thread === "" ? always.indexOf(pageId) >= 0 : !!threadById(p.thread) && ownThread(threadById(p.thread)));
    }
}
