import QtQuick
import Browser

// Saved (PLAN.md 3.7): pages you saved (Ctrl+D) and whole threads (Save thread), persisted to saved.json. The first
// window's, for every main window; a private window saves nothing of its own and asks first (3.14).
QtObject {
    id: saved

    // newest first: { id, url, name, icon, added, folder }; `folder`: an imported group ("From Zen: Toolbar"), "" for none
    property var pages: []
    // newest first: { id, title, thread (the thread it was saved from), pages: [{ url, title, icon }], added }
    property var threads: []
    property int revision: 0
    property Timer saveTimer: Timer { interval: 800; onTriggered: saved.save() }

    function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7) }
    function touch() {
        revision++;
        saveTimer.restart();
    }
    function pageById(id) { return pages.find(p => p.id === id) ?? null }
    function pageByUrl(url) { return pages.find(p => p.url === url) ?? null }
    function threadById(id) { return threads.find(t => t.id === id) ?? null }
    function isSaved(url) { return pages.some(p => p.url === url) }

    // Ctrl+D: a page saved once; saving it again keeps the one there. Returns its id.
    function savePage(url, name, icon) {
        const have = pageByUrl(url);
        if (have)
            return have.id;
        const p = { id: uid(), url: url, name: name || url, icon: icon || "", added: Date.now(), folder: "" };
        pages.unshift(p);
        touch();
        return p.id;
    }
    // Edit in place (PLAN.md 3.7 7c): the name and the address; an empty one keeps what was there
    function edit(id, name, url) {
        const p = pageById(id);
        if (!p)
            return;
        const n = (name ?? "").trim(), u = (url ?? "").trim();
        if (n !== "")
            p.name = n;
        // as Omnibox.toUrl reads a typed address: "example.com:8080" is a host and a port, not a scheme
        if (u !== "")
            p.url = /^[a-z][a-z0-9+.-]*:(?!\d)/i.test(u) ? u : (/^(localhost|\d{1,3}(\.\d{1,3}){3})/.test(u) ? "http://" : "https://") + u;
        touch();
    }
    // Import from another browser (PLAN.md 3.7; Zen's, ChromeImport's): its bookmarks after what is saved, each folder a
    // labelled group ("From Zen: Toolbar", a folder in it "From Zen: Toolbar / Kernel"; `from` names the browser). A page
    // saved already, in any folder, stays as it is, so importing again adds none. `list`: [{ url, title, folder (its names
    // from the root), added }]; returns { added, kept }.
    function importPages(list, from) {
        const have = new Set(pages.map(p => p.url)), stamp = Date.now().toString(36);
        let added = 0, kept = 0;
        for (const b of list) {
            if (have.has(b.url)) {
                kept++;
                continue;
            }
            have.add(b.url);
            pages.push({ id: stamp + "z" + added, url: b.url, name: b.title || b.url, icon: "", added: b.added || Date.now(),
                         folder: "From " + (from || "Zen") + ": " + b.folder.join(" / ") });
            added++;
        }
        if (added > 0)
            touch();
        return { added: added, kept: kept };
    }
    function removePage(id) {
        const at = pages.findIndex(p => p.id === id);
        if (at < 0)
            return;
        pages.splice(at, 1);
        touch();
    }

    // Save thread: its pages as they are now. Saving the same thread again replaces what was saved of it.
    function saveThread(threadId, title, list) {
        const have = threads.find(t => t.thread === threadId);
        const fields = { title: title, pages: list.map(p => ({ url: p.url, title: p.title || "", icon: p.icon || "" })) };
        if (have) {
            Object.assign(have, fields);
            touch();
            return have.id;
        }
        const t = Object.assign({ id: uid(), thread: threadId, added: Date.now() }, fields);
        threads.unshift(t);
        touch();
        return t.id;
    }
    function removeThread(id) {
        const at = threads.findIndex(t => t.id === id);
        if (at < 0)
            return;
        threads.splice(at, 1);
        touch();
    }

    function save() { Store.save("saved", { pages: pages, threads: threads }) }
    function load() {
        const s = Store.load("saved");
        pages = (s && Array.isArray(s.pages) ? s.pages : []).filter(p => p && p.id && p.url);
        threads = (s && Array.isArray(s.threads) ? s.threads : []).filter(t => t && t.id && Array.isArray(t.pages));
        revision++;
    }
}
