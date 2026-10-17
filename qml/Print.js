.pragma library

// Print (PLAN.md 3.16): the card's rows in the frame's order, what each offers and says, how the PDF is laid out, and
// the words the card and the address card use. PrintCard keeps the state and draws it; Printing (C++) makes the PDF and
// talks to CUPS.

var savePdf = "Save as PDF";
var keys = ["destination", "pages", "layout", "paper", "margins", "backgrounds"];
var labels = { destination: "Destination", pages: "Pages", layout: "Layout", paper: "Paper", margins: "Margins", backgrounds: "Backgrounds" };
var papers = ["A4", "A3", "A5", "Letter", "Legal"];
// Default is about Chromium's own default margin, 1 cm; None prints to the paper's edge
var marginMm = { "default": 10, none: 0 };

// A card as it opens: Save as PDF, every page, portrait A4, default margins, no backgrounds (the frame's values).
function defaults() {
    return { destination: savePdf, pages: "all", layout: "portrait", paper: "A4", margins: "default", backgrounds: "off" };
}

// What row `key` offers in place (its ›): [{ value, label }]. `s`: { printers (CUPS's names), page (the one the preview
// shows) }.
function choices(key, s) {
    switch (key) {
    case "destination": return [savePdf].concat(s.printers ?? []).map(p => ({ value: p, label: p }));
    case "pages": return [{ value: "all", label: "All" }, { value: "this", label: "This page (" + (s.page || 1) + ")" }];
    case "layout": return [{ value: "portrait", label: "Portrait" }, { value: "landscape", label: "Landscape" }];
    case "paper": return papers.map(p => ({ value: p, label: p }));
    case "margins": return [{ value: "default", label: "Default" }, { value: "none", label: "None" }];
    case "backgrounds": return [{ value: "off", label: "Off" }, { value: "on", label: "On" }];
    }
    return [];
}

// Row `key`'s value at rest for the card's settings `c`; `s` as for choices, with `count` (the preview's pages, 0 while
// it has none).
function value(key, c, s) {
    switch (key) {
    case "pages": return c.pages === "this" ? "This page (" + (s.page || 1) + ")" : "All" + (s.count > 0 ? " (" + s.count + ")" : "");
    case "destination":
    case "paper": return c[key];
    }
    return (choices(key, s).find(o => o.value === c[key]) ?? { label: "" }).label;
}

// Printing.toPdf's options for settings `c`: the preview has every page (`page` 0); the file sent or saved has page
// `page` alone for This page.
function options(c, page) {
    const one = c.pages === "this" && page > 0;
    return { paper: c.paper, landscape: c.layout === "landscape", margins: marginMm[c.margins] ?? marginMm["default"], from: one ? page : 0, to: one ? page : 0 };
}

// "camss: CSIPHY0 lanes ignored on x1p42100 · Issue #212.pdf": the page's title as a file name, as Chromium names a
// printed page; `/` and control characters become spaces, and the name is cut to 120 characters. No title: the host.
function fileName(title, host) {
    const clean = Array.from(title || "").map(c => c === "/" || c < " " || c === "\u007f" ? " " : c).join("").replace(/\s+/g, " ").trim();
    const name = Array.from(clean.replace(/^\.+|\.+$/g, "")).slice(0, 120).join("").trim();
    return (name || host || "page") + ".pdf";
}

function heading(title) { return "Print " + (title || "this page") }
function button(c) { return c.destination === savePdf ? "Save" : "Print" }
function sent(printer) { return "Sent to " + printer }
function notSent(error) { return "Not sent: " + (error || "the printer did not take it") }
var notMade = "the page could not be printed";
var notSaved = "Not saved: " + notMade;
