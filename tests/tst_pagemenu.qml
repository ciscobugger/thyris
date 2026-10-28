import QtQuick
import QtTest
import "../qml/PageMenu.js" as PageMenu

// PageMenu.js: the page's own right-click menu (PLAN.md 3.11, 3.20 #8).
TestCase {
    name: "PageMenu"

    function texts(entries) { return entries.map(e => e.separator ? "-" : e.text) }
    function req(fields) { return PageMenu.request(Object.assign({ linkUrl: "", selectedText: "", mediaUrl: "", mediaType: 0, isContentEditable: false, misspelledWord: "" }, fields)) }
    readonly property var nav: ({ back: true, forward: false })

    function test_aPlainPageGoesBackOrReloads() {
        compare(texts(PageMenu.entries(req({}), nav, true)), ["Back", "Reload", "-", "Inspect"]);
        compare(texts(PageMenu.entries(req({}), { back: true, forward: true }, true)), ["Back", "Forward", "Reload", "-", "Inspect"]);
    }
    function test_aLinkFirst() {
        const e = PageMenu.entries(req({ linkUrl: "https://lore.kernel.org/x" }), nav, true);
        compare(texts(e), ["Open link in new task", "Open link in this task", "Copy link", "-", "Back", "Reload", "-", "Inspect"]);
        compare(e[0].arg, "https://lore.kernel.org/x");
    }
    function test_anImage() {
        compare(texts(PageMenu.entries(req({ mediaType: 1, mediaUrl: "https://e.org/a.png" }), nav, true)),
                ["Open image in new task", "Save image", "Copy image", "Copy image link", "-", "Back", "Reload", "-", "Inspect"]);
        compare(texts(PageMenu.entries(req({ mediaType: 2, mediaUrl: "https://e.org/a.webm" }), nav, true)), ["Back", "Reload", "-", "Inspect"], "a video is not an image");
    }
    function test_aSelectionCopiesAndAsksPraxis() {
        compare(texts(PageMenu.entries(req({ selectedText: "CSIPHY0" }), nav, true)), ["Copy", "Ask Praxis about this", "-", "Back", "Reload", "-", "Inspect"]);
        compare(texts(PageMenu.entries(req({ selectedText: "CSIPHY0" }), nav, false)), ["Copy", "-", "Back", "Reload", "-", "Inspect"], "no Praxis here");
    }
    function test_aFieldEditsAndSpells() {
        compare(texts(PageMenu.entries(req({ isContentEditable: true }), nav, true)), ["Cut", "Copy", "Paste", "Select all", "-", "Inspect"], "no Back or Reload in a field");
        const e = PageMenu.entries(req({ isContentEditable: true, misspelledWord: "lanse", spellCheckerSuggestions: ["lanes", "lance", "lane", "lass", "lapse"] }), nav, true);
        compare(texts(e), ["lanes", "lance", "lane", "lass", "-", "Cut", "Copy", "Paste", "Select all", "-", "Inspect"], "four suggestions at most");
        compare([e[0].action, e[0].arg], ["spell", "lanes"]);
    }
}
