import QtQuick
import QtTest
import Browser
import "../qml"

// History.qml: visits and frecency search.
TestCase {
    name: "History"

    Component { id: historyComponent; History {} }

    function init() { Store.files = {} }
    function make() { return createTemporaryObject(historyComponent, this) }

    function test_visitCountsAndKeepsTitle() {
        const h = make();
        h.visit("https://example.org/a", "A");
        h.visit("https://example.org/a", "");
        compare(h.entries["https://example.org/a"].visits, 2);
        compare(h.entries["https://example.org/a"].title, "A", "an empty title does not replace one");
    }

    function test_onlyWebPagesAreRecorded() {
        const h = make();
        h.visit("file:///home/abdul/x.pdf", "x");
        h.visit("about:blank", "");
        h.visit("chrome://gpu", "GPU");
        compare(Object.keys(h.entries), []);
    }

    function test_retitleOnlyKnownUrls() {
        const h = make();
        h.visit("https://example.org/a", "A");
        h.retitle("https://example.org/a", "A2");
        h.retitle("https://example.org/b", "B");
        compare(h.entries["https://example.org/a"].title, "A2");
        verify(!("https://example.org/b" in h.entries));
    }

    function test_searchRanksByWordsMatchedInTitleOrUrl() {
        const h = make();
        h.entries = {
            "https://git.libcamera.org/agc.cpp": { url: "https://git.libcamera.org/agc.cpp", title: "agc.cpp - libcamera", visits: 1, last: Date.now() },
            "https://wiki.archlinux.org/title/Libcamera": { url: "https://wiki.archlinux.org/title/Libcamera", title: "Libcamera - ArchWiki", visits: 1, last: Date.now() },
        };
        compare(h.search("libcamera agc", 8).map(e => e.title), ["agc.cpp - libcamera", "Libcamera - ArchWiki"],
                "both words first, then one of them");
        compare(h.search("softisp agc", 8).map(e => e.title), ["agc.cpp - libcamera"]);
        compare(h.search(["libcamera", "agc"], 8).length, 2, "a list of words");
        compare(h.search("LIBCAMERA", 8).length, 2, "case does not matter");
        compare(h.search("archlinux", 8).map(e => e.title), ["Libcamera - ArchWiki"], "the URL counts");
        compare(h.search("   ", 8), [], "no words, no results");
    }

    // Shift+Delete on a history row
    function test_forget() {
        const h = make();
        h.visit("https://a.example/", "A");
        h.visit("https://b.example/", "B");
        h.forget("https://a.example/");
        h.forget("https://never.example/");
        compare(Object.keys(h.entries), ["https://b.example/"]);
    }

    function test_searchRanksByFrecency() {
        const h = make();
        const now = Date.now(), day = 86400000;
        const e = (url, visits, age) => ({ url: url, title: "camera " + url, visits: visits, last: now - age });
        h.entries = {
            "https://old-favourite.example/": e("https://old-favourite.example/", 20, 30 * day),   // 20 / 31
            "https://yesterday.example/": e("https://yesterday.example/", 3, day),                  // 3 / 2
            "https://just-now.example/": e("https://just-now.example/", 1, 0),                      // 1 / 1
        };
        compare(h.search("camera", 8).map(x => x.url),
                ["https://yesterday.example/", "https://just-now.example/", "https://old-favourite.example/"]);
        compare(h.search("camera", 1).length, 1, "limit");
    }

    function test_loadKeepsTheNewest5000() {
        const entries = {};
        for (let i = 0; i < 5003; i++)
            entries["https://example.org/" + i] = { url: "https://example.org/" + i, title: "", visits: 1, last: i };
        Store.save("history", entries);
        const h = make();
        h.load();
        compare(Object.keys(h.entries).length, 5000);
        verify(!("https://example.org/2" in h.entries), "the oldest go");
        verify("https://example.org/5002" in h.entries);
    }

    // Import from Zen (PLAN.md 3.4): by address, web pages only, and importing again changes nothing
    function test_importEntries() {
        const h = make();
        h.visit("https://example.org/a", "");
        const here = h.entries["https://example.org/a"].last;
        const zen = [{ url: "https://example.org/a", title: "A", visits: 4, last: 1000 }, { url: "https://example.org/b", title: "B", visits: 2, last: 2000 },
                     { url: "file:///home/abdul/x.pdf", title: "x", visits: 1, last: 3000 }];
        compare(h.importEntries(zen), { added: 1, kept: 1 });
        compare([h.entries["https://example.org/a"].visits, h.entries["https://example.org/a"].last, h.entries["https://example.org/a"].title], [4, here, "A"],
                "an entry here keeps its time, takes Zen's visits where they are more and a title where it had none");
        compare(h.entries["https://example.org/b"], { url: "https://example.org/b", title: "B", visits: 2, last: 2000 });
        verify(!("file:///home/abdul/x.pdf" in h.entries), "only web pages, as a visit keeps");
        const before = JSON.stringify(h.entries);
        compare(h.importEntries(zen), { added: 0, kept: 2 });
        compare(JSON.stringify(h.entries), before, "again: nothing changes");
        h.saveTimer.triggered();
        verify(JSON.parse(Store.files.history)["https://example.org/b"], "saved");
        // an entry of this browser's own older than all of Zen's: it stays, and Zen's fill the room left
        h.entries["https://example.org/old"] = { url: "https://example.org/old", title: "old", visits: 1, last: 1 };
        const many = [];
        for (let i = 0; i < 5010; i++)
            many.push({ url: "https://z.example/" + i, title: "", visits: 1, last: 10000 + i });
        compare(h.importEntries(many), { added: 4997, kept: 0 }, "only what stays is counted");
        compare(Object.keys(h.entries).length, 5000, "within the 5000 a load keeps");
        verify("https://example.org/a" in h.entries);
        verify("https://example.org/old" in h.entries, "none of this browser's own goes for Zen's");
        verify("https://z.example/5009" in h.entries, "Zen's most recent first");
        verify(!("https://z.example/12" in h.entries));
        h.saveTimer.triggered();
        h.load();
        compare(Object.keys(h.entries).length, 5000, "a load keeps them all");
        compare(h.importEntries(many), { added: 0, kept: 4997 }, "again: nothing added, nothing dropped");
        compare(Object.keys(h.entries).length, 5000);
    }

    function test_loadWithoutFile() {
        const h = make();
        h.load();
        compare(Object.keys(h.entries), []);
    }

    // PLAN.md 3.14: a private window's history lives in memory until the window closes
    function test_aPrivateWindowsHistoryIsNeverSaved() {
        const h = createTemporaryObject(historyComponent, this, { offTheRecord: true });
        h.visit("https://www.flysas.com/", "SAS");
        h.saveTimer.triggered();
        compare(Store.files.history, undefined);
        compare(h.search("sas", 5).length, 1, "the window's own suggestions still find it");
    }
}
