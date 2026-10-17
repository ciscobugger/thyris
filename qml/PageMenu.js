.pragma library

// The page's own right-click menu (PLAN.md 3.11, 3.20 #8), the same on both engines: what was clicked first (a
// misspelled word's suggestions; in a field Cut, Copy, Paste, Select all; a link; an image; selected text), then the
// page's Back, Forward and Reload, and last Inspect (DevTools at the element). Entries as RowMenu takes them; `arg`
// carries the address or the word.

// What a context menu request says (Qt WebEngine's ContextMenuRequest, or the map PageItem emits on CEF), as a plain
// object. MediaTypeImage is 1 in both.
function request(r) {
    return {
        link: r.linkUrl ? String(r.linkUrl) : "",
        selection: r.selectedText || "",
        image: r.mediaType === 1 && r.mediaUrl ? String(r.mediaUrl) : "",
        editable: !!r.isContentEditable,
        misspelled: r.misspelledWord || "",
        suggestions: r.spellCheckerSuggestions ? Array.from(r.spellCheckerSuggestions) : []
    };
}

// `nav`: { back, forward } the page can go; `praxis`: Praxis's hand-off is here (Engine.praxisHere)
function entries(r, nav, praxis) {
    const out = [];
    const inspect = { text: "Inspect", shortcut: "Ctrl+Shift+I", action: "inspect" };
    const group = list => {
        if (list.length === 0)
            return;
        if (out.length > 0)
            out.push({ separator: true });
        out.push(...list);
    };
    if (r.editable && r.misspelled)
        group(r.suggestions.slice(0, 4).map(s => ({ text: s, action: "spell", arg: s })));
    if (r.editable) {
        group([{ text: "Cut", shortcut: "Ctrl+X", action: "cut" }, { text: "Copy", shortcut: "Ctrl+C", action: "copy" },
               { text: "Paste", shortcut: "Ctrl+V", action: "paste" }, { text: "Select all", shortcut: "Ctrl+A", action: "selectAll" }]);
        group([inspect]);
        return out;
    }
    if (r.link)
        group([{ text: "Open link in new task", action: "openTask", arg: r.link }, { text: "Open link in this task", action: "openHere", arg: r.link },
               { text: "Copy link", action: "copyLink", arg: r.link }]);
    if (r.image)
        group([{ text: "Open image in new task", action: "openTask", arg: r.image }, { text: "Save image", action: "saveImage" },
               { text: "Copy image", action: "copyImage" }, { text: "Copy image link", action: "copyLink", arg: r.image }]);
    if (r.selection)
        group([{ text: "Copy", shortcut: "Ctrl+C", action: "copy" }].concat(praxis ? [{ text: "Ask Praxis about this", action: "ask", arg: r.selection }] : []));
    group([nav.back ? { text: "Back", shortcut: "Alt+Left", action: "back" } : null,
           nav.forward ? { text: "Forward", shortcut: "Alt+Right", action: "forward" } : null,
           { text: "Reload", shortcut: "Ctrl+R", action: "reload" }].filter(e => e));
    group([inspect]);
    return out;
}
