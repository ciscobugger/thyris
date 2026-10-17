import QtQuick
import QtTest
import Browser
import "../qml"
import "../qml/Recall.js" as Recall
import "../qml/RailRows.js" as RailRows
import "../qml/Downloads.js" as Downloads

// Recall (PLAN.md 3.7, 3.20): where you stopped, @, History in the rail, Saved, Downloads and forgetting.
TestCase {
    name: "Recall"

    Component { id: sessionComponent; Session {} }
    Component { id: historyComponent; History {} }
    Component { id: savedComponent; Saved {} }
    Component { id: omniComponent; Omnibox {} }

    function init() { Store.files = {} }

    readonly property real day: 86400000
    function stopAt(url, heading, y) { return { url: url, heading: heading, index: 2, offset: 40, x: 0, y: y, percent: 42, at: Date.now() } }

    // a filed thread "Book4 charging PD" of three pages (the last one shown last, stopped under a heading), an open
    // thread, and a closed page
    function seed() {
        const s = createTemporaryObject(sessionComponent, this);
        const open = s.newThread("x1p42100 camera");
        const cam = s.addPage(open, "https://github.com/linux-msm/linux/issues/212", "");
        s.update(cam, { title: "camss: CSIPHY0 lanes ignored" });
        const t = s.newThread("Book4 charging PD");
        const ids = [["https://example.org/s2mm006.pdf", "S2MM006 PD controller - datasheet (PDF)"], ["https://example.org/isl9241", "ISL9241 registers"],
                     ["https://example.org/ucsi", "ucsi: PD renegotiation after resume"]].map(([u, title]) => {
            const id = s.addPage(t, u, "");
            s.update(id, { title: title });
            return id;
        });
        s.pages[ids[0]].lastActive = Date.now();
        s.setStopped(ids[0], stopAt("https://example.org/s2mm006.pdf", "0x4E action register", 3000));
        s.fileThread(t);
        s.activate(cam);
        const gone = s.newThread("book4-pd-charge");
        const g = s.addPage(gone, "https://github.com/abdul/book4-pd-charge", "");
        s.update(g, { title: "book4-pd-charge - github.com" });
        s.closePage(g);
        return { s: s, thread: t, pages: ids, cam: cam };
    }

    function test_stopRecordsFromTheAnswer() {
        const at = 1000;
        compare(Recall.stop("", "https://a.example/", at), undefined, "no answer changes nothing");
        compare(Recall.stop("{\"y\":0,\"x\":0,\"max\":900}", "https://a.example/", at), null, "at the top: nowhere to come back to");
        const s = Recall.stop(JSON.stringify({ x: 0, y: 378, max: 900, heading: "", index: -1, offset: 0 }), "https://a.example/", at);
        compare([s.heading, s.percent, s.y, s.url], ["", 42, 378, "https://a.example/"]);
        compare(Recall.line(s), "42 % down", "a page with no heading above");
        const h = Recall.stop(JSON.stringify({ x: 0, y: 5000, max: 9000, heading: "Changes in v3", index: 4, offset: 212.4 }), "https://a.example/", at);
        compare([h.heading, h.index, h.offset, h.percent], ["Changes in v3", 4, 212, 56]);
        compare(Recall.line(h), "stopped at \u201cChanges in v3\u201d");
        compare(Recall.line(null), "");
        compare(Recall.current({ url: "https://a.example/other", stopped: h }), null, "a page that went elsewhere shows none of it");
        compare(Recall.current({ url: "https://a.example/", stopped: h }), h);
    }

    function test_marks() {
        const m = Recall.marks("Book4 charging PD", ["char"]);
        compare(m.map(r => (r.marked ? "*" : "") + r.text), ["Book4 ", "*char", "ging PD"]);
        compare(Recall.marks("CSIPHY csiphy", ["csiphy"]).map(r => r.marked), [true, false, true], "any case, every place");
        compare(Recall.marks("abc", []).map(r => r.text), ["abc"]);
        compare(Recall.marks("", ["x"]), []);
    }

    function test_dayLabels() {
        const now = new Date(2026, 8, 29, 14, 0).getTime();
        compare(Recall.day(now - 3 * 3600000, now), "Today");
        compare(Recall.day(new Date(2026, 8, 28, 9, 0).getTime(), now), "Monday");
        compare(Recall.day(new Date(2026, 8, 27, 9, 0).getTime(), now), "Sunday");
        compare(Recall.day(new Date(2026, 8, 13, 9, 0).getTime(), now), "13 Sep");
        compare(Recall.day(new Date(2025, 8, 13, 9, 0).getTime(), now), "13 Sep 2025");
        compare(Recall.clock(new Date(2026, 8, 29, 11, 2).getTime()), "11:02");
        compare(Recall.closedAgo(now - 2 * 3600000, now), "closed 2 h ago");
        compare(Recall.closedAgo(now - 5 * 60000, now), "closed 5 min ago");
        compare(Recall.closedAgo(new Date(2026, 8, 28, 9, 0).getTime(), now), "closed Mon");
    }

    // PLAN.md 3.7: where you stopped rides with the page, into a closed page and back
    function test_stoppedStaysWithThePage() {
        const s = createTemporaryObject(sessionComponent, this);
        const t = s.newThread("a");
        const p = s.addPage(t, "https://a.example/long", "");
        const saves = () => Store.files.threads;
        s.setStopped(p, stopAt("https://a.example/long", "Section 1500", 450000));
        compare(s.pages[p].stopped.heading, "Section 1500");
        const r = s.revision;
        s.setStopped(p, Object.assign(stopAt("https://a.example/long", "Section 1500", 450000), { at: 1 }));
        compare(s.revision, r, "the same place again changes nothing");
        s.save();
        verify(saves().indexOf("Section 1500") >= 0, "kept in threads.json");
        s.closePage(p);
        const c = s.closed[s.closed.length - 1];
        verify(!!c.id && c.at > 0, "a closed page has an id and a time");
        compare(c.stopped.heading, "Section 1500");
        const back = s.reopenClosed();
        compare(s.pages[back].stopped.y, 450000, "Ctrl+Shift+T brings where you stopped with it");
        s.setStopped(back, null);
        compare(s.pages[back].stopped, null);
    }

    function test_reopenEntryTakesEveryCloseOfTheAddress() {
        const d = seed(), s = d.s;
        const t = s.newThread("again");
        const p = s.addPage(t, "https://github.com/abdul/book4-pd-charge", "");
        s.closePage(p);
        compare(s.closedPages().filter(c => c.url === "https://github.com/abdul/book4-pd-charge").length, 1, "one row per address");
        const id = s.reopenEntry(s.closedPages()[0].id);
        compare(s.pages[id].url, "https://github.com/abdul/book4-pd-charge");
        compare(s.closedPages().length, 0);
    }

    function test_forgetAndUndo() {
        const d = seed(), s = d.s;
        const u = s.forgetThread(d.thread);
        compare(s.threadById(d.thread), null);
        verify(!s.pages[d.pages[0]], "its pages go");
        s.unforget(u);
        compare(s.threadById(d.thread).pages, d.pages, "Undo puts it back");
        compare(s.pages[d.pages[0]].stopped.heading, "0x4E action register");
        const one = s.forgetPage(d.pages[1]);
        compare(s.threadById(d.thread).pages, [d.pages[0], d.pages[2]]);
        s.unforget(one);
        compare(s.threadById(d.thread).pages, d.pages);
        const c = s.closedPages()[0];
        const uc = s.forgetClosed(c.id);
        compare(s.closedPages().length, 0);
        s.unforget(uc);
        compare(s.closedPages()[0].id, c.id);
        compare(s.forgetThread(s.threads.find(t => !t.earlier).id), null, "only a filed thread is forgotten");
    }

    // a forgotten thread's finished files stay in Earlier > Downloads only
    function test_forgottenFilesAreQuiet() {
        const d = seed(), s = d.s, now = Date.now();
        const id = s.addDownload({ page: d.pages[0], file: "S2MM006_rev1.4.pdf", state: "done", finished: now });
        const u = s.forgetThread(d.thread);
        compare(Downloads.place(s.downloadById(id), s, now), "", "not in the rail's Downloads group");
        compare(RailRows.earlier(s, null, { view: "downloads", now: now }).filter(r => r.type === "download").length, 1);
        s.unforget(u);
        compare(s.downloadById(id).quiet, undefined);
    }

    // PLAN.md 3.20: History in the rail: closed tasks and pages, newest first; a closed task opens in place to list its
    // pages, where you stopped on each, and its files (@ searches them, test_jump*)
    function test_historyInTheRail() {
        const d = seed(), s = d.s, now = Date.now();
        s.addDownload({ page: d.pages[0], file: "S2MM006_rev1.4.pdf", state: "done", finished: now });
        const t = s.threadById(d.thread);
        t.filedAt = now - 5000;
        let rows = RailRows.history(s, now, {}, false);
        compare(rows.map(r => r.type), ["closed", "earlier"]);
        compare([rows[1].title, rows[1].count, rows[1].open], ["Book4 charging PD", 3, false]);
        verify(/^\d\d:\d\d$/.test(rows[0].word), "a closed page says when");
        rows = RailRows.history(s, now, { [d.thread]: true }, false);
        compare(rows.map(r => r.type), ["closed", "earlier", "filed", "filed", "filed", "download", "space"]);
        compare(rows[2].origin, "stopped at \u201c0x4E action register\u201d");
        compare(rows[3].origin, "", "a page you never left scrolled says nothing");
        t.filedAt = t.lastActive = now - 91 * day;
        compare(RailRows.history(s, now, {}, true).map(r => r.type), ["closed"], "unseen 90 days: out of the list");
    }

    // a page closed by an earlier version has no close time: no day in Earlier, and @ claims none
    function test_closedWithoutATime() {
        const d = seed(), s = d.s, now = Date.now();
        const c = s.closedPages()[0];
        delete c.at;
        verify(!RailRows.history(s, now, {}, true).some(r => r.type === "closed"));
        const omni = createTemporaryObject(omniComponent, this, { session: s, history: createTemporaryObject(historyComponent, this) });
        compare(omni.suggest("@pd-charge", "", "bar", now).find(r => r.kind === "closed").detail, "closed");
    }

    // Import from Zen (PLAN.md 3.7): each folder a labelled group, after what is saved; a page saved already stays
    function test_importPages() {
        const s = createTemporaryObject(sessionComponent, this), saved = createTemporaryObject(savedComponent, this);
        saved.savePage("https://lwn.net/", "LWN.net", "");
        const zen = [{ url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", folder: ["Toolbar"], added: 1000 },
                     { url: "https://lore.kernel.org/linux-media/", title: "", folder: ["Toolbar", "Kernel"], added: 2000 },
                     { url: "https://lwn.net/", title: "LWN", folder: ["Menu"], added: 3000 }];
        compare(saved.importPages(zen), { added: 2, kept: 1 });
        compare(saved.pages.map(p => p.name + "|" + p.folder), ["LWN.net|", "Libcamera - ArchWiki|From Zen: Toolbar",
                                                               "https://lore.kernel.org/linux-media/|From Zen: Toolbar / Kernel"]);
        compare(saved.pages[1].added, 1000, "when Zen saved it");
        compare(new Set(saved.pages.map(p => p.id)).size, 3, "an id each");
        compare(saved.importPages(zen), { added: 0, kept: 3 }, "again: none added");
        compare(saved.pages.length, 3);
        const rows = RailRows.earlier(s, saved, { view: "saved" });
        compare(rows.map(r => r.type + ":" + r.title), ["day:Pages", "saved:LWN.net", "folder:From Zen: Toolbar", "folder:From Zen: Toolbar / Kernel"]);
    }

    // PLAN.md 3.7 7c
    function test_savedView() {
        const s = createTemporaryObject(sessionComponent, this), saved = createTemporaryObject(savedComponent, this);
        const a = saved.savePage("https://wiki.archlinux.org/title/Libcamera", "Libcamera - ArchWiki", "");
        compare(saved.savePage("https://wiki.archlinux.org/title/Libcamera", "again", ""), a, "saved once");
        const b = saved.savePage("https://lore.kernel.org/lkml/", "lore.kernel.org", "");
        for (let i = 0; i < 3; i++)
            saved.pages.push({ id: "z" + i, url: "https://z.example/" + i, name: "zen " + i, icon: "", added: 0, folder: "From Zen: Toolbar" });
        saved.saveThread("t1", "Book4 charging PD", [{ url: "https://example.org/1", title: "one" }, { url: "https://example.org/2", title: "two" }]);
        compare(saved.saveThread("t1", "Book4 charging PD", [{ url: "https://example.org/1", title: "one" }]), saved.threads[0].id, "saving it again replaces it");
        compare(saved.threads.length, 1);
        let rows = RailRows.earlier(s, saved, { view: "saved" });
        compare(rows.map(r => r.type), ["day", "savedThread", "day", "saved", "saved", "folder"]);
        compare(rows.map(r => r.title), ["Saved tasks", "Book4 charging PD", "Pages", "lore.kernel.org", "Libcamera - ArchWiki", "From Zen: Toolbar"]);
        compare(rows[5].count, 3);
        rows = RailRows.earlier(s, saved, { view: "saved", editing: b, open: { "folder:From Zen: Toolbar": true } });
        compare(rows.map(r => r.type), ["day", "savedThread", "day", "edit", "saved", "folder", "saved", "saved", "saved"]);
        compare(rows[6].depth, 1);
        saved.edit(b, " Linux kernel mailing ", "lore.kernel.org/lkml");
        compare([saved.pageById(b).name, saved.pageById(b).url], ["Linux kernel mailing", "https://lore.kernel.org/lkml"], "renamed in place");
        saved.edit(b, "", "");
        compare(saved.pageById(b).name, "Linux kernel mailing", "an empty field keeps what was there");
        saved.edit(b, "", "router.lan:8080/admin");
        compare(saved.pageById(b).url, "https://router.lan:8080/admin", "a host and a port is no scheme, as the address card reads it");
        saved.edit(b, "", "localhost:3000");
        compare(saved.pageById(b).url, "http://localhost:3000");
        saved.edit(b, "", "about:blank");
        compare(saved.pageById(b).url, "about:blank");
        saved.edit(b, "", "lore.kernel.org/lkml");
        saved.removePage(b);
        compare(saved.pageById(b), null);
        saved.save();
        const back = createTemporaryObject(savedComponent, this);
        back.load();
        compare(back.pages.length, 4);
        compare(back.threads[0].pages.length, 1);
        verify(back.isSaved("https://wiki.archlinux.org/title/Libcamera"));
    }

    // Ctrl+J: every file kept, newest first by day, each naming its page
    function test_downloadsView() {
        const s = createTemporaryObject(sessionComponent, this), now = Date.now();
        s.addDownload({ file: "old.pdf", state: "done", started: now - 3 * day, from: { title: "Old page", icon: "", always: false } });
        s.addDownload({ file: "new.bin", state: "running", started: now - 1000, from: { title: "New page", icon: "", always: false } });
        const rows = RailRows.earlier(s, null, { view: "downloads", now: now });
        compare(rows.map(r => r.type === "download" ? r.title : r.title), ["Today", "new.bin", Recall.day(now - 3 * day, now), "old.pdf"]);
        compare(rows[1].from, "New page");
        compare(RailRows.earlier(s, null, { view: "downloads", now: now, filter: "old" }).length, 2);
    }

    // PLAN.md 3.7 7a: open, Earlier, closed pages, history; the typed letters marked; an Earlier thread says why
    function test_jump() {
        const d = seed(), s = d.s, now = Date.now();
        const history = createTemporaryObject(historyComponent, this);
        history.entries = { "https://wiki.archlinux.org/title/USB_PD": { url: "https://wiki.archlinux.org/title/USB_PD", title: "USB PD charging - ArchWiki", visits: 1, last: now - 16 * day } };
        const omni = createTemporaryObject(omniComponent, this, { session: s, history: history });
        const rows = omni.suggest("@char", d.cam, "bar", now);
        compare(rows.map(r => r.kind), ["earlier", "closed", "history"]);
        compare(rows[0].detail, "Closed · 3 pages");
        compare(rows[0].marks, ["char"]);
        compare(rows[0].lines.map(l => l.text), ["S2MM006 PD controller - datasheet (PDF)", "stopped at \u201c0x4E action register\u201d"],
                "matched on its title: the page it comes back at, and where you stopped");
        compare([rows[1].title, rows[1].detail], ["book4-pd-charge - github.com", "closed 1 min ago"]);
        compare(rows[2].title, "USB PD charging - ArchWiki");
        // where you stopped is matched too, and says so
        const byHeading = omni.suggest("@0x4e", d.cam, "bar", now);
        compare(byHeading.map(r => r.kind), ["earlier"]);
        compare(byHeading[0].lines[0].text, "S2MM006 PD controller - datasheet (PDF)");
        // a page matched: it is listed, with its heading
        compare(omni.suggest("@isl9241", d.cam, "bar", now)[0].lines.map(l => l.text), ["ISL9241 registers"]);
        // an open page comes first, never duplicated
        s.setStopped(d.cam, stopAt(s.pages[d.cam].url, "Lanes in the DT", 900));
        const open = omni.suggest("@lanes", "", "bar", now);
        compare(open[0].kind, "page");
        compare(open[0].pageId, d.cam);
        compare(open[0].lines.map(l => l.text), ["stopped at \u201cLanes in the DT\u201d"]);
        // at most 8 rows: open threads and pages, Earlier, closed pages and history all match
        for (let i = 0; i < 3; i++) {
            const t = s.newThread("charge " + i), f = s.newThread("charge filed " + i), c = s.newThread("charge closed " + i);
            s.addPage(t, "https://example.org/charge/" + i, "");
            s.addPage(t, "https://example.org/charge/" + i + "/b", "");
            s.addPage(f, "https://example.org/charge-filed/" + i, "");
            s.addPage(f, "https://example.org/charge-filed/" + i + "/b", "");
            s.fileThread(f);
            s.closePage(s.addPage(c, "https://example.org/charge-closed/" + i, ""));
            history.visit("https://example.org/charge-history/" + i, "charge history " + i);
        }
        const many = omni.suggest("@charge", d.cam, "bar", now);
        compare(many.length, 8);
        compare(many.map(r => r.kind), ["page", "page", "page", "page", "page", "earlier", "earlier", "earlier"], "in order, open first");
    }

    // Saved in the cards: a history row of a saved page reads Saved
    function test_historyRowSaysSaved() {
        const s = createTemporaryObject(sessionComponent, this), saved = createTemporaryObject(savedComponent, this);
        const history = createTemporaryObject(historyComponent, this);
        history.entries = { "https://wiki.archlinux.org/title/Libcamera": { url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", visits: 3, last: Date.now() } };
        const omni = createTemporaryObject(omniComponent, this, { session: s, history: history, saved: saved });
        compare(omni.suggest("libcamera", "", "bar").find(r => r.kind === "history").detail !== "Saved", true);
        saved.savePage("https://wiki.archlinux.org/title/Libcamera", "Libcamera - ArchWiki", "");
        compare(omni.suggest("libcamera", "", "bar").find(r => r.kind === "history").detail, "Saved");
    }

    function test_historyForgetAndRemember() {
        const h = createTemporaryObject(historyComponent, this);
        h.visit("https://a.example/", "A");
        const e = h.forget("https://a.example/");
        compare(e.title, "A");
        compare(h.forget("https://a.example/"), null);
        h.remember(e);
        compare(h.entries["https://a.example/"].visits, 1);
    }

    // The section strip (PLAN.md 3.19): each heading's segment is the scroll range in which it is the one you are in
    function test_sections() {
        compare(Recall.readSections("not json"), null);
        compare(Recall.readSections(""), null);
        const s = Recall.readSections(JSON.stringify({ line: 120, ground: [255, 255, 255], list: [
            { name: "Fourth", level: 2, top: 3800 }, { name: "Title", level: 1, top: 40 }, { name: "Second", level: 2, top: 1280 },
            { name: "Third", level: 3, top: 2560 }] }));
        const segs = Recall.segments(s, 5052, 100);
        compare(segs.map(g => g.name), ["Title", "Second", "Third", "Fourth"]);
        compare(segs.map(g => g.from), [0, 1160, 2440, 3680]);
        compare(segs.map(g => g.to), [1160, 2440, 3680, 5052]);
        compare(Recall.sectionAt(segs, 0), { index: 0, fill: 0 });
        compare(Recall.sectionAt(segs, 1800), { index: 1, fill: 0.5 });
        compare(Recall.sectionAt(segs, 5052).index, 3);
        // too many to fit: the h3s go first
        compare(Recall.segments(s, 5052, 3).map(g => g.name), ["Title", "Second", "Fourth"]);
        compare(Recall.segments(s, 5052, 1), []);
        // a heading the page cannot scroll to the reading line, and one the next takes over from at once, get none
        const t = { line: 120, list: [{ name: "A", level: 2, top: 0 }, { name: "B", level: 2, top: 60 }, { name: "C", level: 2, top: 900 },
                                      { name: "D", level: 2, top: 900.5 }, { name: "E", level: 2, top: 2000 }] };
        compare(Recall.segments(t, 1500, 100).map(g => g.name + " " + g.from), ["B 0", "D 780.5"]);
        // one section, no headings, or no room to scroll: no strip
        compare(Recall.segments({ line: 120, list: [{ name: "A", level: 1, top: 0 }] }, 3000, 100), []);
        compare(Recall.segments({ line: 120, list: [] }, 3000, 100), []);
        compare(Recall.segments(s, 0, 100), []);
        compare(Recall.segments(null, 3000, 100), []);
    }
}
