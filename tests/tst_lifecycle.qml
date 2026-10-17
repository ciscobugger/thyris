import QtQuick
import QtTest
import "../qml/Lifecycle.js" as Lifecycle

// Lifecycle.js: when the machine is low on memory, and which page the memory net unloads (PLAN.md 3.12).
TestCase {
    name: "Lifecycle"

    readonly property real gib: 1024 * 1024 * 1024
    readonly property int min: 60000
    // a live page in a thread, not on screen, seen `ago` minutes before minute 100
    function page(id, ago, fields) {
        return Object.assign({ id: id, lastActive: 0, seen: (100 - ago) * min, state: "live", shown: false, where: "" }, fields);
    }

    function test_lowIsUnderOneGibOrTenPercent() {
        compare(Lifecycle.low({ available: 0.9 * gib, total: 8 * gib }), true, "under 1 GiB of 8");
        compare(Lifecycle.low({ available: 1.1 * gib, total: 8 * gib }), false, "over 1 GiB, which is more than 10 % of 8");
        compare(Lifecycle.low({ available: 1.5 * gib, total: 16 * gib }), true, "under 10 % of 16");
        compare(Lifecycle.low({ available: 1.7 * gib, total: 16 * gib }), false);
        compare(Lifecycle.low({}), false, "nothing read: not low");
    }

    function test_pickTakesTheOneSeenLongestAgo() {
        const pages = [page("a", 5), page("b", 50), page("c", 20)];
        compare(Lifecycle.pick(pages).id, "b");
        compare(Lifecycle.pick([page("a", 5), page("never", 0, { seen: undefined, lastActive: 10 * min })]).id, "never",
                "a page never shown counts from when it was made");
        compare(Lifecycle.pick([]), null);
    }

    // PLAN.md 8, phase 1 check: Lofi Girl keeps playing with memory low
    function test_exemptPagesStay() {
        const exempt = [
            page("screen", 90, { shown: true }), page("gone", 90, { state: "unloaded" }), page("always", 90, { where: "Always" }),
            page("popup", 90, { where: "popup" }), page("audio", 90, { audible: true }),
            page("mic", 90, { capturing: "mic" }), page("file", 90, { downloading: true }), page("field", 90, { edited: true }),
            page("ask", 90, { needsYou: true }),
        ];
        compare(Lifecycle.pick(exempt), null, "none of them may go");
        compare(Lifecycle.pick(exempt.concat([page("idle", 1)])).id, "idle", "a page seen a minute ago goes before any of them");
        compare(Lifecycle.pick([page("muted", 90, { audible: true, muted: true })]).id, "muted", "muted audio does not count");
        compare(Lifecycle.pick([page("frozen", 90, { state: "frozen" })]).id, "frozen", "a frozen page still holds memory");
    }

    function test_whatKeepsAPageLive() {
        compare(Lifecycle.keeps(page("p", 60, { audible: true }), false, false), "audio");
        compare(Lifecycle.keeps(page("p", 60, { downloading: true }), false, false), "download");
        compare(Lifecycle.keeps(page("p", 60, { downloading: false }), false, false), "");
        compare(Lifecycle.keeps(page("p", 60), false, true), "edited", "a text field edited since load");
        compare(Lifecycle.keeps(page("p", 60, { capturing: "videocam" }), false, false), "capturing");
        compare(Lifecycle.keeps(page("p", 60, { keep: true }), false, false), "", "Keep page loaded is gone");
        compare(Lifecycle.keeps(page("p", 60, { notifies: true }), true, false), "notifies");
        compare(Lifecycle.keeps(page("p", 60, { notifies: true }), false, false), "", "only Always sites");
    }
}
