import QtQuick
import QtTest
import "../qml/Find.js" as Find

// Find.js: find in page's count, "Also in this thread" and its skipped line (PLAN.md 3.8 8e).
TestCase {
    name: "Find"

    function test_count() {
        compare(Find.count("csiphy", { matches: 17, active: 3 }), "3 of 17");
        compare(Find.count("csiphy", { matches: 0, active: 0 }), "No matches", "no red, no shake: just the words");
        compare(Find.count("csiphy", null), "", "nothing before the page answers");
        compare(Find.count("", { matches: 4, active: 1 }), "", "nothing with nothing typed");
    }

    function test_others() {
        const pages = [{ id: "a", state: "live" }, { id: "b", state: "live" }, { id: "c", state: "frozen" },
                       { id: "d", state: "unloaded" }, { id: "e", state: "failed" }, { id: "f", state: "unloaded" }];
        compare(Find.others(pages, "a"), { search: ["b"], frozen: 1, unloaded: 2, capped: 0 }, "the page on screen is not among them");
        compare(Find.others([{ id: "a", state: "live" }], "a"), { search: [], frozen: 0, unloaded: 0, capped: 0 }, "a thread of one has none");
    }

    // at most 3 live pages are searched: the 3 seen last, kept in thread order
    function test_othersSearchesThreeLivePages() {
        const pages = [{ id: "a", state: "live", seen: 5 }, { id: "b", state: "live", seen: 1 }, { id: "c", state: "live", seen: 4 },
                       { id: "d", state: "frozen", seen: 9 }, { id: "e", state: "live", seen: 2 }, { id: "f", state: "live", seen: 3 }];
        compare(Find.others(pages, "a"), { search: ["c", "e", "f"], frozen: 1, unloaded: 0, capped: 1 });
    }

    function test_also() {
        const hits = [{ id: "a", count: 2 }, { id: "b", count: 0 }, { id: "c", count: 5 }, { id: "d", count: 2 }, { id: "e", count: 1 }];
        compare(Find.also(hits).map(h => h.id), ["c", "a", "d"], "most matches first, thread order on a tie, at most 3");
        compare(Find.also([{ id: "a", count: 0 }]), [], "pages without the words are not listed");
    }

    function test_skipped() {
        compare(Find.skipped(0, 1), "1 unloaded page skipped");
        compare(Find.skipped(0, 3), "3 unloaded pages skipped");
        compare(Find.skipped(1, 0), "1 frozen page skipped");
        compare(Find.skipped(1, 2), "1 frozen and 2 unloaded pages skipped");
        compare(Find.skipped(0, 0), "");
        compare(Find.skipped(0, 0, 2), "2 pages skipped", "live pages past the 3 searched");
        compare(Find.skipped(1, 1, 1), "3 pages skipped");
    }

    // the script as a page would run it, against a stand-in document
    function run(query, matchCase, text) {
        const f = new Function("document", "return " + Find.countScript(query, matchCase));
        return f(text === null ? { body: null } : { body: { innerText: text } });
    }
    function test_countScript() {
        compare(run("csiphy", false, "CSIPHY0 on csiphy-3ph, Csiphy"), 3);
        compare(run("csiphy", true, "CSIPHY0 on csiphy-3ph, Csiphy"), 1, "match case");
        compare(run("aa", false, "aaaa"), 2, "matches do not overlap");
        compare(run("x", false, null), 0, "a page without a body");
        compare(run("\" + alert(1) + \"", false, "\" + alert(1) + \""), 1, "the words are data in the script, never code");
    }
}
