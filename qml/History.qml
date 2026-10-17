import QtQuick
import Browser

// Visited pages, for the address card and the new-page card: url -> { url, title, icon, visits, last };
// persisted to history.json. What is saved is Saved.qml's (an older `saved` flag here still reads as Saved).
// A private window's (PLAN.md 3.14) is its own and `offTheRecord`: kept in memory until the window closes.
QtObject {
    id: history

    property var entries: ({})
    property bool offTheRecord: false
    property Timer saveTimer: Timer { interval: 2000; onTriggered: if (!history.offTheRecord) Store.save("history", history.entries) }

    function visit(url, title) {
        if (!/^https?:/.test(url))
            return;
        const e = entries[url] ?? { url: url, title: "", visits: 0, last: 0 };
        e.visits += 1;
        e.last = Date.now();
        if (title)
            e.title = title;
        entries[url] = e;
        saveTimer.restart();
    }

    function retitle(url, title) {
        if (entries[url] && title) {
            entries[url].title = title;
            saveTimer.restart();
        }
    }

    function reicon(url, icon) {
        if (entries[url] && icon && entries[url].icon !== icon) {
            entries[url].icon = icon;
            saveTimer.restart();
        }
    }

    // Shift+Delete on a history row; returns the entry for the undo (PLAN.md 3.7), or null
    function forget(url) {
        if (!(url in entries))
            return null;
        const e = entries[url];
        delete entries[url];
        saveTimer.restart();
        return e;
    }
    function remember(e) {
        if (!e || !e.url)
            return;
        entries[e.url] = e;
        saveTimer.restart();
    }

    // Clear browsing data (Settings > Privacy, PLAN.md 3.15): every entry
    function clear() {
        entries = {};
        saveTimer.restart();
    }

    // Import from Zen (PLAN.md 3.4): its history, [{ url, title, visits, last }]. An address with an entry here keeps it,
    // taking Zen's visits and time where they are more, so importing again changes nothing. Web pages only, as visit()
    // keeps. The new ones fill only the room under the 5000 load() keeps, Zen's most recent first: none of this
    // browser's own entries goes for them, and what is counted as added stays. Returns { added, kept }.
    function importEntries(list) {
        let added = 0, kept = 0;
        const fresh = [];
        for (const z of list) {
            if (!/^https?:/.test(z.url))
                continue;
            const e = entries[z.url];
            if (e) {
                e.visits = Math.max(e.visits, z.visits || 1);
                e.last = Math.max(e.last, z.last || 0);
                if (!e.title && z.title)
                    e.title = z.title;
                kept++;
                continue;
            }
            fresh.push(z);
        }
        fresh.sort((a, b) => (b.last || 0) - (a.last || 0));
        let room = limit - Object.keys(entries).length;
        for (const z of fresh) {
            if (room <= 0)
                break;
            if (entries[z.url])
                continue;
            entries[z.url] = { url: z.url, title: z.title || "", visits: z.visits || 1, last: z.last || 0 };
            added++;
            room--;
        }
        saveTimer.restart();
        return { added: added, kept: kept };
    }
    // Keep the file bounded: the 5000 most recent.
    readonly property int limit: 5000
    function bound() {
        const urls = Object.keys(entries);
        if (urls.length > limit) {
            urls.sort((a, b) => entries[b].last - entries[a].last);
            for (const u of urls.slice(limit))
                delete entries[u];
        }
    }

    // Entries sharing at least one of the words (a string, or a list of words) with their title or URL,
    // most words first, then by visits decaying with age (frecency).
    function search(query, limit) {
        const words = (Array.isArray(query) ? query : query.split(/\s+/)).map(w => w.toLowerCase()).filter(w => w.length > 0);
        if (words.length === 0)
            return [];
        const now = Date.now();
        const hits = [];
        for (const url in entries) {
            const e = entries[url];
            const hay = (e.title + " " + url).toLowerCase();
            const matched = words.filter(w => hay.includes(w)).length;
            if (matched > 0)
                hits.push({ entry: e, matched: matched, score: e.visits / (1 + (now - e.last) / 86400000) });
        }
        hits.sort((a, b) => b.matched - a.matched || b.score - a.score);
        return hits.slice(0, limit).map(h => h.entry);
    }

    function load() {
        const e = Store.load("history");
        entries = e ?? {};
        bound();
    }
}
