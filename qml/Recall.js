.pragma library

// Recall (PLAN.md 3.7): where you stopped on a page, and how @ and Earlier mark what matched. Nothing here is
// written by AI: "stopped at" is the page's own heading, or how far down it you were.
//
// A page's `stopped` (Session): { url, heading, index, offset, x, y, percent, at }. `heading`: the nearest h1-h3
// above the reading line, "" when none is; `index`: its place among the page's h1-h3; `offset`: the scroll
// position from the heading's top; `x`, `y`: the scroll position; `percent`: how far down the page; `url`: the
// address it was taken at (a page that went elsewhere since shows none of it).

// A heading's text, and whether it is pinned in place (fixed or sticky, as a site header's title): what `capture` and
// `sections` both read of the page's h1-h3, inside their scripts (`d` is the document element there).
var headingParts = " const text = e => (e.innerText || e.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 120);"
    + " const pinned = e => { for (let a = e; a && a !== d; a = a.parentElement) { const p = getComputedStyle(a).position;"
    + " if (p === 'fixed' || p === 'sticky') return true } return false };";

// Run in the browser's script world, where the page can neither see nor fake it. The reading line lies a quarter
// of the viewport (at most 120 px) under its top edge, so a heading still in view at the top counts as the one
// you are in. Headings pinned in place (fixed or sticky, as a site header's title) and hidden ones are skipped.
// Answers JSON: { x, y, max, heading, index, offset }, or "" (no document, or it threw).
var capture = "(() => { try { const d = document.documentElement; if (!d) return '';"
    + " const y = scrollY, x = scrollX, h = innerHeight, max = Math.max(0, d.scrollHeight - h), line = y + Math.min(h / 4, 120);"
    + headingParts
    + " const all = document.querySelectorAll('h1,h2,h3'), above = [];"
    + " for (let i = 0; i < all.length; i++) { const r = all[i].getBoundingClientRect();"
    + " if (r.width >= 2 && r.height >= 2 && r.top + y <= line) above.push({ i: i, top: r.top + y }) }"
    + " above.sort((a, b) => b.top - a.top);"
    + " let best = null; for (const c of above) { const t = text(all[c.i]); if (t && !pinned(all[c.i])) { best = Object.assign(c, { t: t }); break } }"
    + " return JSON.stringify({ x: x, y: y, max: max, heading: best ? best.t : '', index: best ? best.i : -1, offset: best ? y - best.top : 0 })"
    + " } catch (e) { return '' } })()";

// The page's sections, for the strip under it (PLAN.md 3.19): its h1-h3 read as `capture` reads them (hidden, empty,
// fixed and sticky ones skipped), each with its level and its top in the document, the reading line's distance under
// the viewport's top, and the page's ground ([r, g, b] of the body's background, else the root's; null when neither
// paints one). Answers JSON: { line, list: [{ name, level, top }], ground }, or "".
var sections = "(() => { try { const d = document.documentElement; if (!d) return '';"
    + " const y = scrollY, line = Math.min(innerHeight / 4, 120);"
    + headingParts
    + " const all = document.querySelectorAll('h1,h2,h3'), list = [];"
    + " for (let i = 0; i < all.length; i++) { const r = all[i].getBoundingClientRect(), t = text(all[i]);"
    + " if (r.width >= 2 && r.height >= 2 && t && !pinned(all[i])) list.push({ name: t, level: +all[i].tagName[1], top: r.top + y }) }"
    + " const rgb = e => { const m = e ? getComputedStyle(e).backgroundColor.match(/[\\d.]+/g) : null;"
    + " return m && m.length >= 3 && (m.length < 4 || +m[3] > 0.5) ? m.slice(0, 3).map(Number) : null };"
    + " return JSON.stringify({ line: line, list: list, ground: rgb(document.body) || rgb(d) })"
    + " } catch (e) { return '' } })()";

// The answer to `sections`, or null when the page gave none.
function readSections(answer) {
    try {
        const a = JSON.parse(answer);
        return a && Array.isArray(a.list) && typeof a.line === "number" ? a : null;
    } catch (e) {
        return null;
    }
}

// The strip's segments for the page's sections `s` and its scroll range `max`: [{ name, from, to }] in scroll px, the
// range in which each heading is the one you are in by `capture`'s rule (the nearest above the reading line). The first
// starts at the top of the page, the last ends at its end. A heading the page cannot scroll to the reading line, or one
// the next heading takes over from at once, is never the one you are in and gets no segment. With more than `room`
// segments the deepest level goes (h3, then h2); fewer than two make no strip ([]).
function segments(s, max, room) {
    if (!s || !s.list || !(max >= 1))
        return [];
    for (let level = 3; level >= 1; level--) {
        const list = s.list.filter(h => (h.level || 3) <= level).map(h => ({ name: h.name, start: h.top - s.line }))
            .filter(h => h.start < max).sort((a, b) => a.start - b.start);
        // of those over the line at the top of the page, the last is the one you are in there
        let first = 0;
        while (first + 1 < list.length && list[first + 1].start <= 0)
            first++;
        const kept = [];
        for (let i = first; i < list.length; i++) {
            if (kept.length > 0 && list[i].start - Math.max(0, kept[kept.length - 1].start) < 1)
                kept.pop();
            kept.push(list[i]);
        }
        const out = kept.map((h, i) => ({ name: h.name, from: i === 0 ? 0 : h.start, to: i + 1 < kept.length ? kept[i + 1].start : max }));
        if (out.length <= room || level === 1)
            return out.length >= 2 && out.length <= room ? out : [];
    }
    return [];
}

// Where reading position `y` lies among `segs`: { index, fill } (fill 0..1 through that segment).
function sectionAt(segs, y) {
    let i = 0;
    while (i + 1 < segs.length && y >= segs[i + 1].from)
        i++;
    const g = segs[i];
    return { index: segs.length > 0 ? i : -1, fill: g && g.to > g.from ? Math.max(0, Math.min(1, (y - g.from) / (g.to - g.from))) : 0 };
}

// The page's answer to `capture` as a `stopped` record taken at `url`; null at the top of the page, where there is
// nowhere to come back to; undefined when the page gave no answer (gone, or not a document), which changes nothing.
function stop(answer, url, now) {
    let a = null;
    try {
        a = JSON.parse(answer);
    } catch (e) {
        return undefined;
    }
    if (!a || typeof a.y !== "number")
        return undefined;
    if (a.y < 1)
        return null;
    return { url: url, heading: a.heading || "", index: a.index ?? -1, offset: Math.round(a.offset || 0), x: Math.round(a.x || 0),
             y: Math.round(a.y), percent: a.max > 0 ? Math.min(100, Math.round(100 * a.y / a.max)) : 0, at: now };
}

// The page's `stopped` while it still holds for the address the page is at, else null.
function current(p) {
    return p && p.stopped && p.stopped.url === p.url ? p.stopped : null;
}

// "stopped at “0x4E action register”", or "42 % down" on a page with no heading above where you were.
function line(s) {
    if (!s)
        return "";
    return s.heading ? "stopped at “" + s.heading + "”" : s.percent + " % down";
}

// Run in the browser's script world once the page has loaded: back to the heading, at the same distance under it
// (so content added above it since does not move you off it), else to the saved position. While the page is still
// growing (or the heading not there yet) it tries again every 150 ms for 3 s, and it gives up as soon as you scroll,
// press a key or anything else moves the page.
function restore(s) {
    return "(() => { const s = " + JSON.stringify({ heading: s.heading, index: s.index, offset: s.offset, x: s.x, y: s.y }) + ";"
        + " const d = document.documentElement;"
        + " const text = e => (e.innerText || e.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 120);"
        + " const find = () => { if (!s.heading) return null; const all = document.querySelectorAll('h1,h2,h3');"
        + " if (all[s.index] && text(all[s.index]) === s.heading) return all[s.index];"
        + " let best = null, gap = Infinity; for (let i = 0; i < all.length; i++)"
        + " if (Math.abs(i - s.index) < gap && text(all[i]) === s.heading) { best = all[i]; gap = Math.abs(i - s.index) } return best };"
        + " let tries = 20, checks = 2, over = false, last = null; const stop = () => over = true;"
        + " for (const t of ['wheel', 'keydown', 'mousedown', 'touchstart']) addEventListener(t, stop, { capture: true, once: true, passive: true });"
        + " const go = () => { if (over || !d || last !== null && Math.abs(scrollY - last) > 2) return;"
        + " const e = find(), want = e ? e.getBoundingClientRect().top + scrollY + s.offset : s.y, max = Math.max(0, d.scrollHeight - innerHeight);"
        + " if ((want > max + 1 || s.heading && !e) && --tries > 0) { setTimeout(go, 150); return }"
        + " scrollTo(s.x, Math.max(0, Math.min(want, max))); last = scrollY;"
        + " if (checks-- > 0) setTimeout(go, 300) };"
        + " go(); return true })()";
}

// `text` cut into runs { text, marked }: every place one of `words` occurs (any case) is marked, for the typed
// letters in DemiBold (PLAN.md 3.7: weight, never colour).
function marks(text, words) {
    const t = String(text ?? ""), low = t.toLowerCase();
    const on = [];
    for (let i = 0; i < t.length; i++)
        on.push(false);
    // lower case of the odd letter is longer ("İ"): then nothing is marked rather than the wrong letters
    if (low.length === t.length)
        for (const w of words || []) {
            const k = String(w ?? "").toLowerCase();
            if (k === "")
                continue;
            for (let i = low.indexOf(k); i >= 0; i = low.indexOf(k, i + k.length))
                for (let j = i; j < i + k.length; j++)
                    on[j] = true;
        }
    const out = [];
    for (let i = 0; i < t.length; i++) {
        if (out.length > 0 && out[out.length - 1].marked === on[i])
            out[out.length - 1].text += t[i];
        else
            out.push({ text: t[i], marked: on[i] });
    }
    return out;
}

// Earlier's day labels (PLAN.md 3.7 7b): "Today", a weekday within the week, else a date (with its year when it
// is not this one's).
var weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function day(ms, now) {
    const d = new Date(ms), n = new Date(now);
    if (d.toDateString() === n.toDateString())
        return "Today";
    if (ms < now && now - ms < 6 * 86400000)
        return weekdays[d.getDay()];
    return d.getDate() + " " + months[d.getMonth()] + (d.getFullYear() !== n.getFullYear() ? " " + d.getFullYear() : "");
}
// "11:02"
function clock(ms) {
    const d = new Date(ms), pad = v => (v < 10 ? "0" : "") + v;
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
}
// When a page was closed, for @ (7a): "closed 2 h ago"; past a day, its weekday or date.
function closedAgo(ms, now) {
    const min = Math.max(1, Math.round((now - ms) / 60000));
    if (min < 60)
        return "closed " + min + " min ago";
    if (min < 24 * 60)
        return "closed " + Math.round(min / 60) + " h ago";
    const d = new Date(ms);
    return "closed " + (now - ms < 6 * 86400000 ? weekdays[d.getDay()].slice(0, 3) : d.getDate() + " " + months[d.getMonth()]);
}

// Threads unseen this long leave the Earlier list; history and @ still find them (PLAN.md 3.7).
var earlierDays = 90;

// A filter's words (Earlier's filter, local): each must be in `hay`, any case.
function words(filter) {
    return String(filter ?? "").toLowerCase().split(/\s+/).filter(w => w.length > 0);
}
function passes(hay, list) {
    const h = String(hay ?? "").toLowerCase();
    return list.every(w => h.indexOf(w) >= 0);
}
