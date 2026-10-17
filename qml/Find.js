.pragma library

// Find in page (PLAN.md 3.8 8e): the count by the find field and "Also in this task", the thread's other
// live pages that contain the words. Those are counted with a read-only script over each page's text, not
// findText, so their selection and scroll do not move. Frozen and unloaded pages answer no script in the
// browser's script world, so they are not searched, and the section's last line says how many were skipped.

// By the field: "3 of 17", "No matches", or "" with nothing typed or before the page answers.
// `result`: { matches, active } from findTextFinished (active counts from 1).
function count(query, result) {
    if (!query || !result)
        return "";
    return result.matches > 0 ? result.active + " of " + result.matches : "No matches";
}

// The thread's other pages by what the find can do with them: `pages` in thread order, { id, state, seen } with
// state "live", "frozen", "unloaded" or "failed" (the browser's failure page shows there, not the site's).
// Returns { search: [ids], frozen: n, unloaded: n, capped: n }; failed pages are neither searched nor counted.
// Each search reads a page's whole text, so at most `searched` live pages are: the ones seen last, in thread
// order; `capped` counts the rest.
var searched = 3;
function others(pages, currentId) {
    const out = { search: [], frozen: 0, unloaded: 0, capped: 0 };
    const live = [];
    for (const p of pages) {
        if (p.id === currentId)
            continue;
        if (p.state === "live")
            live.push(p);
        else if (p.state === "frozen")
            out.frozen++;
        else if (p.state === "unloaded")
            out.unloaded++;
    }
    const last = live.slice().sort((a, b) => (b.seen ?? 0) - (a.seen ?? 0)).slice(0, searched);
    out.search = live.filter(p => last.indexOf(p) >= 0).map(p => p.id);
    out.capped = live.length - out.search.length;
    return out;
}

// The pages that had matches, most first and in thread order on a tie, at most 3. `hits`: [{ id, count }]
// in thread order.
function also(hits) {
    return hits.map((h, i) => ({ h: h, i: i })).filter(x => x.h.count > 0)
        .sort((a, b) => b.h.count - a.h.count || a.i - b.i).slice(0, 3).map(x => x.h);
}

// The section's last line: what was not searched, or "". `capped`: live pages past the ones searched.
function skipped(frozen, unloaded, capped) {
    const n = frozen + unloaded + (capped ?? 0);
    if (n === 0)
        return "";
    const pages = n === 1 ? " page skipped" : " pages skipped";
    if (capped > 0)
        return n + pages;
    if (frozen > 0 && unloaded > 0)
        return frozen + " frozen and " + unloaded + " unloaded" + pages;
    return n + (frozen > 0 ? " frozen" : " unloaded") + pages;
}

// The script that counts `query` in a page's visible text (non-overlapping, as find matches), run in the
// browser's script world, where the page can neither see nor change the answer. It reads, never selects.
function countScript(query, matchCase) {
    return "(() => { const b = document.body; if (!b) return 0;"
        + " const fold = s => " + (matchCase ? "s" : "s.toLowerCase()") + ";"
        + " const t = fold(b.innerText), q = fold(" + JSON.stringify(query) + ");"
        + " let n = 0; for (let i = t.indexOf(q); q && i >= 0; i = t.indexOf(q, i + q.length)) n++;"
        + " return n })()";
}
