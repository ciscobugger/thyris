import QtQuick
import QtTest
import Browser
import "../qml"
import "../qml/RailRows.js" as RailRows
import "../qml/Downloads.js" as Downloads

// RailRows.js: what the rail lists (PLAN.md 3.1, 3.4, 3.12, 3.19, 3.20) and the keyed sync into its ListModel.
TestCase {
    name: "RailRows"

    Component { id: sessionComponent; Session {} }
    Component { id: modelComponent; ListModel {} }

    function init() { Store.files = {} }

    // threads given as [title, pageCount]; the first page of the first thread is current
    function make(spec) {
        const s = createTemporaryObject(sessionComponent, this);
        const ids = [];
        for (const [title, n] of spec.slice().reverse()) {
            const t = s.newThread(title);
            for (let i = 0; i < n; i++)
                ids.push(s.addPage(t, "https://example.org/" + title + "/" + i, ""));
        }
        s.activate(s.threads[0].pages[0]);
        return s;
    }
    function keys(rows) { return rows.map(r => r.key.split(":")[0] + ":" + (r.title || "")) }
    function firstPage(rows) { return rows.find(r => r.type === "page") }
    function types(rows) { return rows.map(r => r.type) }

    function test_untitledPageReadsAsHostAndPath() {
        const s = make([["a", 1]]);
        s.update(s.threads[0].pages[0], { url: "https://www.example.org/search?q=agc#top" });
        compare(firstPage(RailRows.build(s, {})).title, "example.org/search");
    }

    // PLAN.md 3.17's table: what the address card shows for the browser's own and special pages
    function test_cardNamesPagesByKind() {
        const c = (url, title) => { const r = RailRows.card(url, title ?? ""); return [r.glyph, r.host, r.path, r.own].join("|") };
        compare(c("browser://settings"), "settings|Settings||true");
        compare(c("browser://settings#keys"), "settings|Settings||true", "the key list is a section of Settings");
        compare(c("browser://pages"), "memory|Pages and memory||true");
        compare(c("browser://answer/7f3k", "Laptop chargers 100 W"), "diamond|Answer|Laptop chargers 100 W|true", "the Answer's title after its name");
        compare(c("file:///home/abdul/Documents/S2MM006.pdf"), "description|File|/home/abdul/Documents/S2MM006.pdf|true");
        compare(c("file:///home/abdul/My%20Notes/a%C3%A5.txt"), "description|File|/home/abdul/My Notes/aå.txt|true", "the path decoded");
        compare(c("about:blank"), "|Blank page||true");
        compare(c("view-source:https://github.com/linux-msm/linux/pull/212?tab=files"), "|Source of github.com|/linux-msm/linux/pull/212|true");
        compare(c("https://www.example.org/datasheets/S2MM006.pdf"), "|example.org|/datasheets/S2MM006.pdf|false", "a PDF reads as any page");
        compare(c("about:version"), "|about:version||false", "other about: pages as before");
        compare(c(""), "|||false", "no page");
    }
    // the rail row shows the card's glyph (PLAN.md 3.10 10b "◆ Answer", 3.15 "[·] Settings"); ◆ is drawn filled
    function test_rowsCarryTheCardsGlyph() {
        const s = make([["a", 4]]);
        const ids = s.threads[0].pages;
        s.update(ids[1], { url: "file:///home/abdul/Documents/S2MM006.pdf", title: "S2MM006.pdf" });
        s.update(ids[2], { url: "browser://settings" });
        s.update(ids[3], { url: "browser://answer/7f3k" });
        const glyphs = RailRows.build(s, {}).filter(r => r.type === "page").map(r => r.title + ":" + r.glyph);
        compare(glyphs, ["example.org/a/0:", "S2MM006.pdf:description", "Settings:settings", "Answer:diamond"]);
        compare(["diamond", "settings", "description", "warning", ""].map(RailRows.filled), [1, 0, 0, 0, 0]);
    }
    function test_dataPageIsNeverShownByItsContent() {
        const html = "<p>" + "a".repeat(4089) + "</p>";
        const url = "data:text/html," + encodeURIComponent(html);
        compare(RailRows.card(url, "").host, "data: page · 4 kB", "its size decoded: 4096 bytes");
        compare(RailRows.card("data:text/plain;base64,aGVsbG8gd29ybGQ=", "").host, "data: page · 11 B", "base64: three bytes for four characters");
        compare(RailRows.card("data:,", "").host, "data: page · 0 B");
        const shown = JSON.stringify(RailRows.card(url, "")) + RailRows.untitled(url) + RailRows.named(url);
        verify(shown.indexOf("aaaa") < 0 && shown.indexOf("<p>") < 0 && shown.indexOf("%3Cp") < 0, shown.slice(0, 80));
        const s = make([["a", 1]]);
        s.update(s.threads[0].pages[0], { url: url, title: RailRows.pageTitle("data:text/html,<p>" + "a".repeat(40), url) });
        compare(s.current.title, "", "Chromium's stand-in title (the address) is no title");
        compare(firstPage(RailRows.build(s, {})).title, "data: page · 4 kB", "the rail row");
        compare(RailRows.windowTitle(s.current, s.currentThread), "data: page · 4 kB", "the window title");
    }
    function test_pageTitleDropsOnlyTheStandIn() {
        compare(RailRows.pageTitle("about:blank", "about:blank"), "");
        compare(RailRows.pageTitle("view-source:127.0.0.1:8080/plain", "view-source:http://127.0.0.1:8080/plain"), "");
        compare(RailRows.pageTitle("file:///nonexistent/x.txt", "file:///nonexistent/x.txt"), "", "a file that failed");
        compare(RailRows.pageTitle("S2MM006.pdf", "file:///home/abdul/S2MM006.pdf"), "S2MM006.pdf", "a file's name stays");
        compare(RailRows.pageTitle("Note", "data:text/html,<title>Note</title>"), "Note", "a data: page's own title stays");
        compare(RailRows.pageTitle("example.org/x", "https://example.org/x"), "example.org/x", "web pages as before");
        compare(RailRows.untitled("view-source:http://127.0.0.1:8080/plain"), "Source of 127.0.0.1:8080 /plain");
        compare(RailRows.untitled("file:///home/abdul/S2MM006.pdf"), "File /home/abdul/S2MM006.pdf");
        compare(RailRows.untitled("about:blank"), "Blank page");
        compare(RailRows.named("https://example.org/closed?x=1"), "https://example.org/closed?x=1", "a web address stays whole where one is named");
        compare(RailRows.named("about:blank"), "Blank page");
    }

    function test_windowTitle() {
        const s = make([["x1p42100 camera", 2]]);
        const id = s.threads[0].pages[0];
        s.update(id, { title: "[PATCH v3 2/4] media: qcom: camss" });
        compare(RailRows.windowTitle(s.current, s.currentThread), "[PATCH v3 2/4] media: qcom: camss · x1p42100 camera");
        s.update(id, { title: "" });
        compare(RailRows.windowTitle(s.current, s.currentThread), "example.org/x1p42100 camera/0 · x1p42100 camera", "untitled: host and path, as in the rail");
        const one = s.addPage(s.newThread("data:text/html,secret"), "data:text/html,secret", "");
        s.activate(one);
        s.update(one, { title: "Note" });
        compare(RailRows.windowTitle(s.current, s.currentThread), "Note", "a thread of one is not named");
        const hub = s.newThread("github.com");
        s.addPage(hub, "https://github.com/linux-msm", "");
        s.activate(s.addPage(hub, "https://github.com/", ""));
        compare(RailRows.windowTitle(s.current, s.currentThread), "github.com", "a thread named as its page is not named twice");
        s.keepInAlways(one);
        s.activate(one);
        s.update(one, { title: "Gmail" });
        compare(RailRows.windowTitle(s.current, s.currentThread), "Gmail", "an Always page has no thread");
    }

    // PLAN.md 3.20: one order that a click never changes: every task open, its pages one step in, then air; a task of
    // one is its page's row. A task folded by hand stays folded in its place while you are elsewhere.
    function test_tasksFoldWhereTheyAre() {
        const s = make([["a", 2], ["b", 3], ["solo", 1]]);
        let rows = RailRows.build(s, {});
        compare(types(rows), ["thread", "page", "page", "space", "thread", "page", "page", "page", "space", "page"]);
        compare([rows[0].title, rows[0].open], ["a", true]);
        compare([rows[4].title, rows[4].open], ["b", true], "open though the page on screen is elsewhere");
        compare(rows[1].current, true);
        compare(rows[1].word, "", "the page on screen says nothing");
        compare(rows[1].depth, 1);
        compare(rows[9].depth, 0, "a task of one");
        s.setOpen(s.threads[1].id, false);
        rows = RailRows.build(s, {});
        compare(types(rows), ["thread", "page", "page", "space", "thread", "page"], "b folds where it is");
        compare([rows[4].title, rows[4].open, rows[4].count], ["b", false, 3]);
        s.activate(s.threads[1].pages[0]);
        s.activate(s.threads[0].pages[0]);
        compare(RailRows.build(s, {})[4].open, true, "shown, b opened, and stays open when left");
    }

    // PLAN.md 8f-8h: a failed page's row carries its mark ("error", "certificate"), every other row ""
    function test_failedPagesCarryTheirMark() {
        const s = make([["a", 2]]);
        s.update(s.threads[0].pages[1], { failed: "certificate" });
        const rows = RailRows.build(s, {});
        compare(rows.map(r => r.failed ?? ""), ["", "", "certificate"]);
        const m = createTemporaryObject(modelComponent, this);
        RailRows.sync(m, rows);
        compare(m.get(0).failed, "", "the thread row has the role too");
    }

    function test_threadOfOneIsAPageRowAtThreadLevel() {
        const s = make([["a", 2], ["solo", 1]]);
        const rows = RailRows.build(s, {});
        const last = rows[rows.length - 1];
        compare(last.type, "page");
        compare(last.depth, 0);
    }

    function test_foldingTheCurrentTaskKeepsItsPlace() {
        const s = make([["a", 2], ["b", 2]]);
        s.setOpen(s.threads[0].id, false);
        const rows = RailRows.build(s, {});
        compare(keys(rows).slice(0, 2), ["t:a", "t:b"]);
        compare(rows[0].open, false);
        compare(rows[0].current, true, "the row keeps the place marked");
        compare([rows[0].word, rows[0].count], ["", 2], "nothing happening: the row shows how many pages");
        s.activate(s.threads[0].pages[1]);
        compare(RailRows.build(s, {})[0].open, true, "the current page's task opens again when a page in it is shown");
    }

    // a folded task's one word: a page in it asking, then files coming, then sound; otherwise none
    function test_foldedTaskWord() {
        const s = make([["a", 1], ["b", 3]]);
        const b = s.threads[1];
        s.setOpen(b.id, false);
        const row = () => RailRows.build(s, {}).find(r => r.type === "thread");
        compare(row().word, "", "nothing happening");
        s.update(b.pages[0], { audible: true });
        compare([row().word, row().accent], ["playing", true]);
        download(s, b.pages[1]);
        compare(row().word, "40 %");
        s.update(b.pages[2], { needsYou: true, asking: "camera?" });
        compare([row().word, row().accent], ["camera?", true]);
        s.update(b.pages[2], { asking: "" });
        compare(row().word, "asks you");
    }
    // a task's row leads with the icon of its most recently used page that has one
    function test_taskRowLeadsWithItsNewestIcon() {
        const s = make([["a", 1], ["b", 3]]);
        const b = s.threads[1];
        ["sas.png", "tk.png", ""].forEach((icon, i) => s.update(b.pages[i], { icon: icon }));
        b.pages.forEach((id, i) => s.pages[id].lastActive = 100 * (i + 1));
        compare(RailRows.build(s, {}).find(r => r.type === "thread").icon, "tk.png");
        for (const id of b.pages)
            s.update(id, { icon: "" });
        compare(RailRows.build(s, {}).find(r => r.type === "thread").icon, "", "none: the row draws a globe");
    }
    // a task still named as its first page is called by that page's site; renamed, by its own name
    function test_taskName() {
        const s = make([["solo", 1]]);
        const p = s.threads[0].pages[0];
        s.update(p, { url: "https://www.skatteverket.se/foretag/moms", title: "Momsdeklaration - Skatteverket" });
        s.threads[0].title = "Momsdeklaration - Skatteverket";
        s.addFromOpener(p, "https://www.skatteverket.se/foretag/moms/registrering", "skatteverket.se");
        compare(RailRows.build(s, {})[0].title, "Skatteverket");
        s.rename(s.threads[0].id, "Moms");
        compare(RailRows.build(s, {})[0].title, "Moms");
        s.rename(s.threads[0].id, "Momsdeklaration - Skatteverket");
        compare(RailRows.build(s, {})[0].title, "Momsdeklaration - Skatteverket", "renamed by hand, even as its first page");
    }
    // an open task's run of three or more pages named alike but for a number, all unloaded, is one row
    function test_runsFoldIntoOneRow() {
        const s = make([["pd", 6]]);
        const ps = s.threads[0].pages;
        ps.slice(1).forEach((id, i) => s.update(id, { title: "USB PD notes " + (4 + i), state: "unloaded" }));
        let pages = RailRows.build(s, {}).filter(r => r.type === "page");
        compare(pages.map(r => r.title), ["example.org/pd/0", "USB PD notes 4–8"]);
        compare(pages[1].origin, "5 pages");
        s.update(ps[3], { state: "live" });
        pages = RailRows.build(s, {}).filter(r => r.type === "page");
        compare(pages.length, 6, "one of them loaded: each its own row");
    }
    // a page row's one word: only what is happening, the most telling first (PLAN.md 3.20)
    function test_pageWords() {
        const s = make([["a", 3]]);
        const [p0, p1, p2] = s.threads[0].pages;
        const now = Date.now();
        const row = id => RailRows.build(s, { now: now }).find(r => r.ref === id);
        s.pages[p1].seen = now - 2 * 3600000;
        compare([row(p1).word, row(p1).detail], ["", "2h"], "no word; how long since you saw it, under the pointer");
        compare([row(p0).word, row(p0).detail], ["", ""], "the page on screen");
        s.update(p1, { muted: true });
        compare(row(p1).word, "muted");
        s.update(p1, { audible: true, muted: false });
        compare([row(p1).word, row(p1).accent], ["playing", true]);
        s.update(p1, { capturing: "mic" });
        compare(row(p1).word, "mic", "a device in use before the sound");
        s.update(p1, { failed: "error" });
        compare(row(p1).word, "failed");
        s.update(p1, { needsYou: true, asking: "camera?" });
        compare([row(p1).word, row(p1).accent], ["camera?", true]);
        download(s, p1);
        compare(row(p1).word, "camera?", "its file says what is coming on its own row");
        // a day-old page says when while it is loaded; unloaded, its half strength says it
        const later = new Date(2026, 8, 30, 10, 0).getTime();
        s.pages[p2].seen = new Date(2026, 8, 28, 10, 0).getTime();
        s.update(p2, { state: "live" });
        compare(RailRows.build(s, { now: later }).find(r => r.ref === p2).word, "Mon");
        s.update(p2, { state: "unloaded" });
        compare(RailRows.build(s, { now: later }).find(r => r.ref === p2).word, "");
    }
    function test_age() {
        const now = new Date(2026, 9, 1, 15, 0).getTime();
        compare(RailRows.age(now - 10000, now), "1m");
        compare(RailRows.age(now - 59 * 60000, now), "59m");
        compare(RailRows.age(now - 5 * 3600000, now), "5h");
        compare(RailRows.age(now - 3 * 86400000, now), "3d");
        compare(RailRows.age(now - 8 * 86400000, now), "23 Sep");
    }

    // PLAN.md 8d: a download grows in under the page that started it, its name where the page's title starts
    function download(s, page, fields) {
        return s.addDownload(Object.assign({ page: page, file: "camss-v3.mbox", total: 8.4e6, received: 3.36e6, state: "running" }, fields));
    }
    function test_downloadRowSitsUnderItsPage() {
        const s = make([["a", 2]]);
        download(s, s.threads[0].pages[0]);
        const rows = RailRows.build(s, {});
        compare(types(rows), ["thread", "page", "download", "page"]);
        compare(rows[2].detail, "40 %");
        compare(rows[2].depth, 2, "under a page of a thread");
        compare(rows[2].page, s.threads[0].pages[0]);
        compare(rows[2].from, "", "its page says where it came from");
        const m = createTemporaryObject(modelComponent, this);
        RailRows.sync(m, rows);
        compare(m.get(0).status, "", "every row has the download roles");
        compare(m.get(2).progress, 0.4);
    }
    function test_downloadUnderAThreadOfOne() {
        const s = make([["solo", 1]]);
        download(s, s.threads[0].pages[0]);
        const rows = RailRows.build(s, {}).filter(r => r.type !== "hint" && r.type !== "label");
        compare(types(rows), ["page", "download"]);
        compare(rows[1].depth, 1);
    }
    function test_severalFromOnePageAreOneRowListedOnAClick() {
        const s = make([["a", 2]]);
        const p = s.threads[0].pages[0];
        download(s, p, { file: "one", total: 1e6, received: 1e6, state: "done" });
        download(s, p, { file: "two", total: 2e6, received: 0.2e6 });
        download(s, p, { file: "three", total: 2e6, received: 0.8e6 });
        const rows = RailRows.build(s, {});
        compare(types(rows), ["thread", "page", "download", "page"]);
        compare(rows[2].status, "summary");
        compare(rows[2].title, "3 downloads · 40 %");
        compare(rows[2].key, "s:" + p);
        const listed = RailRows.build(s, { listed: [p] });
        compare(listed.map(r => r.title).slice(2, 6), ["3 downloads · 40 %", "one", "two", "three"]);
        compare(listed[2].open, true);
    }
    function test_failuresAndWarningsKeepRowsOfTheirOwn() {
        const s = make([["a", 2]]);
        const p = s.threads[0].pages[0];
        download(s, p, { file: "flash-tool.AppImage", state: "done", warn: "program" });
        download(s, p, { file: "driver.run", state: "blocked", received: 0 });
        const rows = RailRows.build(s, {});
        compare(rows.slice(2, 4).map(r => r.status + " " + r.title), ["program flash-tool.AppImage", "blocked driver.run"]);
        download(s, p, { file: "a" });
        download(s, p, { file: "b" });
        compare(RailRows.build(s, {}).slice(2, 5).map(r => r.status), ["summary", "program", "blocked"], "only the rest collapse");
    }
    // PLAN.md 3.20: a Pinned site's or a closed page's downloads have no row in the list; the rail's foot says what is
    // still coming of them, and Downloads lists them
    function test_pagelessDownloadsAreTheFoots() {
        const s = make([["a", 1], ["f1", 2]]);
        s.threads[1].earlier = true;
        const cell = s.addAlways("https://mail.example/", "(12) Inbox - Gmail", "g.png");
        download(s, cell, { file: "inbox-export.mbox", from: { title: "(12) Inbox - Gmail", icon: "g.png", always: true } });
        download(s, "closed", { file: "notes.pdf", state: "done", from: { title: "Notes", icon: "", always: false } });
        compare(RailRows.build(s, {}).some(r => r.type === "download"), false);
        const now = Date.now();
        compare(RailRows.fetching(s.downloads.filter(d => Downloads.place(d, s, now) === "group")), "40 %");
        const listed = RailRows.earlier(s, null, { view: "downloads", now: now }).filter(r => r.type === "download");
        compare(listed.map(r => r.from).sort().join(), "Notes,Pinned");
    }
    function test_aPageKeptInAlwaysSaysAlways() {
        const s = make([["a", 1], ["b", 2]]);
        const solo = s.threads[0].pages[0];
        download(s, solo, { from: { title: "a 0", icon: "", always: false } });
        s.keepInAlways(solo);
        compare(RailRows.earlier(s, null, { view: "downloads" }).find(r => r.type === "download").from, "Pinned", "the page as it is now");
    }
    // PLAN.md 3.17: a data: page is never named by its content, in Downloads either
    function test_theDownloadsGroupNamesAnUntitledPageAsItsRowDoes() {
        const s = make([["a", 1], ["f1", 2]]);
        const p = s.threads[1].pages[0];
        s.update(p, { url: "data:text/html,<p>open sesame</p>", title: "" });
        s.fileThread(s.threads[1].id);
        download(s, p, { from: { title: "as it was", icon: "", always: false } });
        const row = RailRows.earlier(s, null, { view: "downloads" }).find(r => r.type === "download");
        compare(row.from, "data: page · 18 B", "its page, filed, as the rail names it");
    }
    function test_closingAPageMovesItsDownloadToTheFoot() {
        const s = make([["a", 2]]);
        const p = s.threads[0].pages[1];
        download(s, p, { from: { title: "a 1", icon: "", always: false } });
        s.closePage(p);
        compare(RailRows.build(s, {}).some(r => r.type === "download"), false, "no row in the list");
        compare(Downloads.place(s.downloads[0], s, Date.now()), "group", "the foot's");
        compare(RailRows.earlier(s, null, { view: "downloads" }).find(r => r.type === "download").from, "a 1");
    }

    // PLAN.md 3.21: History, the rail's list from its foot: what was closed in the last week, newest first, then Older for
    // the rest; the search reaches every one. The rail's own list has none of it.
    function test_historyListsTheWeekThenOlder() {
        const s = make([["a", 1], ["f1", 2], ["f2", 2], ["f3", 2]]);
        const now = Date.now(), day = 86400000;
        for (const title of ["f1", "f2", "f3"])
            s.fileThread(s.threads.find(t => t.title === title).id);
        s.threads.find(t => t.title === "f1").filedAt = now - 10 * day;
        s.threads.find(t => t.title === "f2").filedAt = now - 2 * day;
        s.threads.find(t => t.title === "f3").filedAt = now - day;
        compare(RailRows.build(s, { now: now }).some(r => r.type === "earlier" || r.type === "label"), false, "not in the rail's own list");
        let rows = RailRows.earlier(s, null, { view: "history", now: now });
        compare(types(rows), ["earlier", "earlier", "older"]);
        compare(rows.filter(r => r.type === "earlier").map(r => r.title), ["f3", "f2"]);
        compare(rows[rows.length - 1].count, 1);
        rows = RailRows.earlier(s, null, { view: "history", now: now, older: true });
        compare(rows.filter(r => r.type === "earlier").map(r => r.title), ["f3", "f2", "f1"]);
        compare(rows.some(r => r.type === "older"), false);
        compare(RailRows.earlier(s, null, { view: "history", now: now, filter: "f1" }).map(r => r.title), ["f1"], "the search reaches past the week");
    }
    // a closed task opens in place: its pages one step in, then air
    function test_historyOpensATaskInPlace() {
        const s = make([["a", 1], ["f1", 3]]);
        const f = s.threads[1];
        s.fileThread(f.id);
        const rows = RailRows.earlier(s, null, { view: "history", unfolded: { [f.id]: true } });
        compare(types(rows), ["earlier", "filed", "filed", "filed", "space"]);
        compare(rows.find(r => r.type === "earlier").open, true);
        compare(rows.filter(r => r.type === "filed").map(r => r.depth), [1, 1, 1]);
    }
    // PLAN.md 3.7: threads unseen for 90 days leave the Earlier list (history and @ keep them)
    function test_earlierLeavesThreadsUnseen90Days() {
        const s = make([["a", 1], ["recent", 2], ["old", 2]]);
        const now = Date.now(), day = 86400000;
        for (const t of s.threads.slice(1))
            s.fileThread(t.id);
        Object.assign(s.threads.find(t => t.title === "old"), { lastActive: now - 91 * day, filedAt: now - 91 * day });
        compare(RailRows.earlier(s, null, { view: "history", now: now, older: true }).filter(r => r.type === "earlier").map(r => r.title), ["recent"]);
        compare(s.earlierThreads(now).map(t => t.title), ["recent"]);
        compare(s.filedThreads().length, 2, "still filed");
    }

    // PLAN.md 3.17: a window lists its own tasks; History is every window's
    function test_eachWindowListsItsOwnThreads() {
        const s = make([["a", 1], ["f1", 2]]);
        s.threads[1].earlier = true;
        const w = createTemporaryObject(sessionComponent, this, { windowId: "w2", shared: s });
        const t = w.newThread("b");
        w.addPage(t, "https://example.org/b/0", "");
        w.addPage(t, "https://example.org/b/1", "");
        w.activate(w.threads[0].pages[0]);
        compare(keys(RailRows.build(s, {})), ["p:example.org/a/0"]);
        compare(keys(RailRows.build(w, {})), ["t:b", "p:example.org/b/0", "p:example.org/b/1"]);
        compare(keys(RailRows.earlier(w, null, { view: "history" })), ["e:f1"]);
    }


    function test_hintUntilAThreadHasTwoPages() {
        const s = make([["a", 1]]);
        compare(RailRows.build(s, {}).some(r => r.type === "hint"), true);
        s.addPage(s.threads[0].id, "https://example.org/2", "");
        compare(RailRows.build(s, {}).some(r => r.type === "hint"), false);
    }

    function test_when() {
        const now = new Date(2026, 8, 23, 15, 0).getTime();
        compare(RailRows.when(now - 20 * 60000, now), "14:40");
        compare(RailRows.when(now - 5 * 3600000, now), "today");
        compare(RailRows.when(new Date(2026, 8, 21, 12, 0).getTime(), now), "Mon");
        compare(RailRows.when(new Date(2026, 8, 1, 12, 0).getTime(), now), "1 Sep");
    }

    // PLAN.md 3.12: a task of one grows a row of its own when a second page joins and loses it at one again;
    // the page row keeps its key, so the rail moves it rather than fading it out and in.
    function test_threadOfOneTransitions() {
        const s = make([["solo", 1]]);
        const t = s.threads[0], p = t.pages[0];
        let rows = RailRows.build(s, {});
        compare(rows[0].key, "p:" + p);
        compare(rows[0].depth, 0);
        const q = s.addFromOpener(p, "https://example.org/next", "example.org");
        rows = RailRows.build(s, {});
        compare(rows.map(r => r.key).slice(0, 3), ["t:" + t.id, "p:" + p, "p:" + q], "a task now, its row over its pages");
        compare(rows[1].depth, 1);
        s.closePage(q);
        rows = RailRows.build(s, {});
        compare(rows[0].key, "p:" + p);
        compare(rows[0].depth, 0, "a page's row again");
    }

    function test_filedThreadsListMostRecentlyFiledFirst() {
        const s = make([["a", 1], ["f1", 2], ["f2", 2]]);
        s.fileThread(s.threads[1].id);
        s.fileThread(s.threads[2].id);
        s.threads.find(t => t.title === "f1").filedAt = Date.now() - 1000;
        s.threads.find(t => t.title === "f2").filedAt = Date.now() - 2000;
        compare(RailRows.earlier(s, null, { view: "history" }).filter(r => r.type === "earlier").map(r => r.title), ["f1", "f2"]);
    }

    function texts(entries) { return entries.map(e => e.separator ? "-" : e.text) }

    // PLAN.md 3.11: only the entries that apply, in the wireframe's order
    function test_pageMenu() {
        const s = make([["a", 3], ["b", 1]]);
        const [p0, p1] = s.threads[0].pages;
        s.update(p1, { state: "live" });
        compare(texts(RailRows.menu(s, "page", p1)), ["Reload", "Duplicate", "Mute page", "Copy link", "-", "Move to task",
            "Split task from here", "Pin", "-", "Close page", "Close other pages here"]);
        compare(texts(RailRows.menu(s, "page", p0)), ["Duplicate", "Copy link", "-", "Move to task", "Pin", "-",
            "Close page", "Close other pages here"], "unloaded: no Reload or Mute; first page: no Split");
        const move = RailRows.menu(s, "page", p1).find(e => e.sub).sub;
        compare(move.map(e => e.text), ["https://example.org/b/0", "New task"], "a thread of one is named by its page (no title yet: its URL)");
        compare(move[0].arg, s.threads[1].id);
        const solo = s.threads[1].pages[0];
        compare(texts(RailRows.menu(s, "page", solo)), ["Duplicate", "Copy link", "-", "Move to task", "Pin", "-", "Close page"]);
        compare(RailRows.menu(s, "page", solo).find(e => e.sub).sub.map(e => e.text), ["a"], "already alone: no New thread");
    }

    function test_tabsPlaceLine() {
        const s = make([["a", 3], ["b", 1]]), p = s.threads[0].pages[0];
        compare(texts(RailRows.menu(s, "page", p, false, false)).slice(-2), ["-", "Show tabs along the top"]);
        compare(texts(RailRows.menu(s, "page", p, false, true)).slice(-2), ["-", "Show tabs on the side"]);
        compare(texts(RailRows.menu(s, "thread", s.threads[0].id, false, false)).slice(-1), ["Show tabs along the top"]);
        compare(texts(RailRows.menu(s, "tabs", "", false, false)), ["Show tabs along the top"]);
        compare(texts(RailRows.menu(s, "tabs", "", false, true)), ["Show tabs on the side"]);
        compare(RailRows.menu(s, "tabs", ""), [], "no tabs shown: no line");
    }

    function test_otherMenus() {
        const s = make([["a", 2]]);
        compare(texts(RailRows.menu(s, "thread", s.threads[0].id)), ["Rename", "New page here", "Save task", "Fold", "-", "Close task"]);
        compare(texts(RailRows.menu(s, "thread", s.threads[0].id, true)), ["Rename", "New page here", "Fold", "-", "Close task"], "a private window saves nothing");
        const a = s.addAlways("https://a.example/", "a", ""), b = s.addAlways("https://b.example/", "b", "");
        compare(texts(RailRows.menu(s, "always", a)), ["Copy link", "Move right", "-", "Unpin"]);
        s.update(b, { state: "frozen" });
        compare(texts(RailRows.menu(s, "always", b)), ["Reload", "Mute", "Copy link", "Move left", "-", "Unpin"]);
        const f = s.newThread("filed");
        s.addPage(f, "https://f.example/1", "");
        s.addPage(f, "https://f.example/2", "");
        s.fileThread(f);
        compare(texts(RailRows.menu(s, "earlier", f)), ["Reopen task", "Open its last page in the current task", "Copy link", "Save task", "-", "Forget"]);
        // Earlier's own rows (PLAN.md 3.7, 3.11)
        const fp = s.threadById(f).pages[0];
        compare(texts(RailRows.menu(s, "filed", fp)), ["Reopen task", "Open this page in the current task", "Copy link", "Save task", "-", "Forget"]);
        compare(RailRows.menu(s, "filed", fp).find(e => e.action === "saveThread").arg, f);
        compare(RailRows.menu(s, "earlier", f).find(e => e.action === "forget").shortcut, "Shift+Delete");
        compare(texts(RailRows.menu(s, "closed", "c1")), ["Open this page in the current task", "Copy link", "-", "Forget"]);
        compare(texts(RailRows.menu(s, "saved", "s1")), ["Edit", "Copy link", "-", "Remove"]);
    }

    // The model must end up equal to the rows, whatever came before.
    function checkSync(model, rows) {
        RailRows.sync(model, rows);
        compare(model.count, rows.length);
        for (let i = 0; i < rows.length; i++)
            compare(model.get(i).key, rows[i].key, "row " + i);
    }

    function test_syncFollowsEveryChange() {
        const model = createTemporaryObject(modelComponent, this);
        const s = make([["a", 3], ["b", 2], ["solo", 1]]);
        s.threads[2].earlier = true;
        checkSync(model, RailRows.build(s, {}));
        checkSync(model, RailRows.build(s, { ghost: { thread: s.threads[0].id, text: "q" } }));
        checkSync(model, RailRows.build(s, { ghost: { thread: "", text: "" } }));
        checkSync(model, RailRows.build(s, {}));
        s.setOpen(s.threads[1].id, true);
        checkSync(model, RailRows.build(s, {}));
        s.closePage(s.threads[0].pages[1]);
        checkSync(model, RailRows.build(s, {}));
        checkSync(model, []);
    }

    // a task dragged above another: its rows travel instead of being removed and added again
    function test_syncMovesARow() {
        const model = createTemporaryObject(modelComponent, this);
        const s = make([["a", 1], ["b", 1]]);
        RailRows.sync(model, RailRows.build(s, {}));
        let moved = 0, inserted = 0, removed = 0;
        model.rowsMoved.connect(() => moved++);
        model.rowsInserted.connect(() => inserted++);
        model.rowsRemoved.connect(() => removed++);
        const b = s.threads[1];
        s.moveThread(b.id, s.threads[0].id);
        checkSync(model, RailRows.build(s, {}));
        compare(model.get(0).key, "p:" + b.pages[0]);
        verify(moved >= 1);
        compare(inserted, 0, "nothing is new");
        compare(removed, 0, "nothing fades out and back in");
    }

    function test_syncKeepsUnchangedRows() {
        const model = createTemporaryObject(modelComponent, this);
        const s = make([["a", 2]]);
        RailRows.sync(model, RailRows.build(s, {}));
        let changed = 0;
        model.dataChanged.connect(() => changed++);
        RailRows.sync(model, RailRows.build(s, {}));
        compare(changed, 0);
        s.update(s.threads[0].pages[1], { title: "new title" });
        RailRows.sync(model, RailRows.build(s, {}));
        compare(changed, 1);
    }

    // PLAN.md 3.14: a private window's rail lists its tasks only; its menus no Pinned
    function test_aPrivateRailListsItsThreadsOnly() {
        const s = make([["a", 1], ["f1", 2]]);
        s.fileThread(s.threads[1].id);
        download(s, "closed", { file: "notes.pdf", state: "done", from: { title: "Notes", icon: "", always: false } });
        compare(keys(RailRows.build(s, { offTheRecord: true })), ["p:example.org/a/0"]);
        const solo = s.threads[0].pages[0];
        compare(texts(RailRows.menu(s, "page", solo, true)), ["Duplicate", "Copy link", "-", "Close page"], "one separator, no Keep in Always");
    }
    function test_privateTitle() {
        const s = make([["x1p42100 camera", 2]]);
        s.update(s.threads[0].pages[0], { title: "SAS · Stockholm - Mogadishu" });
        compare(RailRows.privateTitle(s.current), "Private · SAS · Stockholm - Mogadishu", "the page's title, no thread");
        s.update(s.threads[0].pages[0], { title: "" });
        compare(RailRows.privateTitle(s.current), "Private · example.org/x1p42100 camera/0");
        compare(RailRows.privateTitle(null), "Private");
    }

    // the tabs along the top: faces, then every page of every open task, a hairline where a task of several pages begins
    function test_stripListsFacesThenEveryPageOfEveryTask() {
        const s = make([["a", 1], ["b", 3], ["c", 1], ["d", 1]]);
        s.addAlways("https://example.org/pin", "Pin", "");
        const rows = RailRows.strip(s, {});
        compare(rows.map(r => r.type), ["pin", "page", "page", "page", "page", "page", "page"]);
        compare(rows.filter(r => r.type === "page").map(r => r.thread), [0, 1, 1, 1, 2, 3].map(i => s.threads[i].id))
        compare(rows.filter(r => r.type === "page").map(r => r.edge), [false, true, false, false, true, false], "a hairline before and after the task of three, none between tasks of one");
        s.setOpen(s.threads[1].id, false);
        compare(RailRows.strip(s, {}).filter(r => r.type === "page").length, 6, "a task folded in the rail still lists its pages");
        compare(RailRows.strip(s, { offTheRecord: true }).filter(r => r.type === "pin").length, 0, "a private window has no faces");
    }
    function test_stripSyncsIntoTheRailsModel() {
        const s = make([["a", 2], ["b", 1]]);
        const m = createTemporaryObject(modelComponent, this);
        RailRows.sync(m, RailRows.strip(s, {}));
        compare(m.count, 3);
        s.update(s.threads[0].pages[0], { title: "Renamed" });
        RailRows.sync(m, RailRows.strip(s, {}));
        compare(m.get(0).title, "Renamed");
        compare(m.get(2).edge, true);
    }
}
