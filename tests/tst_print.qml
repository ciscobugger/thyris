import QtQuick
import QtTest
import "../qml/Print.js" as Print

// Print.js: the print card's rows, choices and wording, and the PDF's layout (PLAN.md 3.16).
TestCase {
    name: "Print"

    readonly property var facts: ({ printers: ["Brother_HL-L2350DW"], page: 2, count: 3 })

    // the frame's rows and values: Save as PDF, All (3), Portrait, A4, Default, Off
    function test_frameValues() {
        const c = Print.defaults();
        compare(Print.keys.map(k => Print.labels[k]), ["Destination", "Pages", "Layout", "Paper", "Margins", "Backgrounds"]);
        compare(Print.keys.map(k => Print.value(k, c, facts)), ["Save as PDF", "All (3)", "Portrait", "A4", "Default", "Off"]);
        compare(Print.value("pages", c, { page: 1, count: 0 }), "All", "no preview yet: no count");
        compare(Print.value("pages", Object.assign({}, c, { pages: "this" }), facts), "This page (2)");
    }

    function test_choices() {
        compare(Print.choices("destination", facts).map(o => o.label), ["Save as PDF", "Brother_HL-L2350DW"], "Save as PDF, then CUPS's printers");
        compare(Print.choices("destination", { printers: [] }).length, 1, "no CUPS: Save as PDF alone");
        compare(Print.choices("pages", facts).map(o => o.label), ["All", "This page (2)"]);
        compare(Print.choices("paper", facts).map(o => o.value), ["A4", "A3", "A5", "Letter", "Legal"]);
        compare(Print.choices("layout", facts).map(o => o.label), ["Portrait", "Landscape"]);
        compare(Print.choices("margins", facts).map(o => o.label), ["Default", "None"]);
        compare(Print.choices("backgrounds", facts).map(o => o.label), ["Off", "On"]);
    }

    // the preview has every page; This page sends the previewed one alone
    function test_options() {
        const c = Object.assign(Print.defaults(), { layout: "landscape", paper: "Letter", margins: "none", pages: "this" });
        compare(JSON.stringify(Print.options(c, 0)), JSON.stringify({ paper: "Letter", landscape: true, margins: 0, from: 0, to: 0 }));
        compare(JSON.stringify(Print.options(c, 2)), JSON.stringify({ paper: "Letter", landscape: true, margins: 0, from: 2, to: 2 }));
        compare(Print.options(Print.defaults(), 2).from, 0, "All: every page");
        compare(Print.options(Print.defaults(), 0).margins, 10);
    }

    function test_fileName() {
        compare(Print.fileName("camss: CSIPHY0 lanes ignored on x1p42100 · Issue #212", "github.com"), "camss: CSIPHY0 lanes ignored on x1p42100 · Issue #212.pdf");
        compare(Print.fileName("a/b\tc", "x.org"), "a b c.pdf", "no slash or control character in a name");
        compare(Print.fileName("", "lwn.net"), "lwn.net.pdf");
        compare(Print.fileName("...", ""), "page.pdf");
        compare(Print.fileName("x".repeat(300), "").length, 124, "cut to 120 characters");
    }

    function test_wording() {
        compare(Print.heading("camss: CSIPHY0 lanes"), "Print camss: CSIPHY0 lanes");
        compare(Print.button(Print.defaults()), "Save");
        compare(Print.button(Object.assign(Print.defaults(), { destination: "Brother_HL-L2350DW" })), "Print");
        compare(Print.sent("Brother_HL-L2350DW"), "Sent to Brother_HL-L2350DW");
        compare(Print.notSent("client-error-not-found"), "Not sent: client-error-not-found");
        compare(Print.notSent(Print.notMade), "Not sent: the page could not be printed", "the PDF was not made: not the printer's fault");
        compare(Print.notSaved, "Not saved: the page could not be printed");
    }
}
