.pragma library

// The keyboard map (PLAN.md 5), for the keys whose features exist. Two classes:
//  R  the browser always acts and the page never sees the key: Main registers these as Shortcuts,
//     which Qt matches before the web view gets the key (Qt WebEngine claims only editing keys in
//     fields, such as Ctrl+C, and none of these).
//  P  the page first: the key goes to the page, and Main acts only on a key the page left unhandled,
//     which Qt WebEngine hands to the view's parent item. A key the page's script took
//     (defaultPrevented) or that has a default action where focus is (Ctrl+B bolds in a rich text
//     field, Alt+Down opens a select) never comes back.
// F keys (`/` find) are P keys that are printable, so a field would have taken them; they match the
// typed text, as `/` is Shift+7 on a Swedish keyboard.
// Ctrl+K and Ctrl+E belong to sites.

var reserved = [
    { action: "newPage", seqs: ["Ctrl+T"] },
    { action: "newWindow", seqs: ["Ctrl+N"] },
    { action: "privateWindow", seqs: ["Ctrl+Shift+N"] },
    { action: "closePage", seqs: ["Ctrl+W"] },
    { action: "fileThread", seqs: ["Ctrl+Shift+W"] },
    { action: "reopen", seqs: ["Ctrl+Shift+T"] },
    { action: "nextPage", seqs: ["Ctrl+Tab", "Ctrl+PgDown"] },
    { action: "previousPage", seqs: ["Ctrl+Shift+Tab", "Ctrl+PgUp"] },
    { action: "pageN", arg: 1, seqs: ["Ctrl+1"] },
    { action: "pageN", arg: 2, seqs: ["Ctrl+2"] },
    { action: "pageN", arg: 3, seqs: ["Ctrl+3"] },
    { action: "pageN", arg: 4, seqs: ["Ctrl+4"] },
    { action: "pageN", arg: 5, seqs: ["Ctrl+5"] },
    { action: "pageN", arg: 6, seqs: ["Ctrl+6"] },
    { action: "pageN", arg: 7, seqs: ["Ctrl+7"] },
    { action: "pageN", arg: 8, seqs: ["Ctrl+8"] },
    { action: "lastPage", seqs: ["Ctrl+9"] },
    { action: "address", seqs: ["Ctrl+L", "Alt+D"] },
    { action: "focusCycle", seqs: ["F6"] },
    { action: "quit", seqs: ["Ctrl+Q"] },
    { action: "fullScreen", seqs: ["F11"] },
    { action: "devtools", seqs: ["F12", "Ctrl+Shift+I"] },
];

var pageFirst = [
    { action: "back", seqs: ["Alt+Left"] },
    { action: "forward", seqs: ["Alt+Right"] },
    { action: "reload", seqs: ["Ctrl+R", "F5"] },
    { action: "hardReload", seqs: ["Ctrl+Shift+R", "Shift+F5"] },
    { action: "stop", seqs: ["Esc"] },
    { action: "nextThread", seqs: ["Alt+PgDown"] },
    { action: "previousThread", seqs: ["Alt+PgUp"] },
    { action: "movePageUp", seqs: ["Ctrl+Shift+PgUp"] },
    { action: "movePageDown", seqs: ["Ctrl+Shift+PgDown"] },
    { action: "jump", seqs: ["Ctrl+Shift+A"] },
    { action: "fold", seqs: ["Ctrl+B"] },
    // Meet's Ctrl+D mutes: the page has it first
    { action: "save", seqs: ["Ctrl+D"] },
    { action: "keepInAlways", seqs: ["Ctrl+Shift+D"] },
    // Earlier (PLAN.md 3.7): threads, downloads, saved
    { action: "earlier", arg: "history", seqs: ["Ctrl+H"] },
    { action: "earlier", arg: "downloads", seqs: ["Ctrl+J"] },
    { action: "earlier", arg: "saved", seqs: ["Ctrl+Shift+O"] },
    { action: "mute", seqs: ["Ctrl+M"] },
    { action: "print", seqs: ["Ctrl+P"] },
    { action: "viewSource", seqs: ["Ctrl+U"] },
    { action: "find", seqs: ["Ctrl+F"] },
    { action: "site", seqs: ["Ctrl+I"] },
    // Plus is Shift+= on a US keyboard, where Ctrl+= zooms in too
    { action: "zoomIn", seqs: ["Ctrl+Plus", "Ctrl+Shift+Plus", "Ctrl+="] },
    { action: "zoomOut", seqs: ["Ctrl+Minus"] },
    { action: "zoomReset", seqs: ["Ctrl+0"] },
    { action: "reader", seqs: ["Ctrl+Alt+R"] },
    // the browser's own pages (PLAN.md 3.15, 3.17): Settings, the key list (Ctrl+/ is Ctrl+Shift+7 on a Swedish
    // keyboard, where / is Shift+7), clear browsing data, Pages and memory
    { action: "settings", seqs: ["Ctrl+,"] },
    { action: "settings", arg: "keys", seqs: ["Ctrl+/", "Ctrl+Shift+/"] },
    { action: "settings", arg: "clear", seqs: ["Ctrl+Shift+Del"] },
    { action: "pages", seqs: ["Shift+Esc"] },
].concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => ({ action: "alwaysN", arg: n, seqs: ["Alt+" + n] })));

// Qt::Key values of the named keys the map uses (Qt's key codes are part of its ABI).
var names = {
    0x01000000: "Esc", 0x01000001: "Tab", 0x01000002: "Tab", 0x01000003: "Backspace", 0x01000004: "Return",
    0x01000005: "Enter", 0x01000007: "Del", 0x01000010: "Home", 0x01000011: "End", 0x01000012: "Left",
    0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down", 0x01000016: "PgUp", 0x01000017: "PgDown",
    0x2b: "Plus", 0x2d: "Minus",
};

// A key event as the map writes it: "Ctrl+Shift+PgDown", "Alt+1", "F5". Shift+Tab arrives as Backtab.
function sequence(key, modifiers) {
    let name = names[key];
    if (name === undefined && key >= 0x01000030 && key <= 0x01000052)
        name = "F" + (key - 0x01000030 + 1);
    if (name === undefined && key > 0x20 && key < 0x7f)
        name = String.fromCharCode(key).toUpperCase();
    if (name === undefined)
        return "";
    const shift = (modifiers & 0x02000000) || key === 0x01000002;
    return (modifiers & 0x04000000 ? "Ctrl+" : "") + (modifiers & 0x08000000 ? "Alt+" : "")
        + (modifiers & 0x10000000 ? "Meta+" : "") + (shift ? "Shift+" : "") + name;
}

var pageIndex = {};
for (const k of pageFirst)
    for (const s of k.seqs)
        pageIndex[s] = k;

// The P entry for a key the page left unhandled, or null.
function pageKey(key, modifiers) {
    return pageIndex[sequence(key, modifiers)] ?? null;
}

var typed = [
    { action: "find", text: "/" },
];

// The F entry for a printable key the page left unhandled (no Ctrl, Alt or Meta; Shift may make it), or null.
function typedKey(text, modifiers) {
    if (modifiers & (0x04000000 | 0x08000000 | 0x10000000))
        return null;
    return typed.find(k => k.text === text) ?? null;
}
