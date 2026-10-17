.pragma library
.import "Failures.js" as Failures
.import "PageState.js" as PageState

// The site panel (PLAN.md 3.9): the rows it lists for a page's site, what each value says at rest and offers
// when clicked, and the wording of its lines. SiteInfo keeps the state, SitePanel draws the rows.

// The permission rows in the order All permissions lists them. A site may also have asked for the pointer
// lock, the fonts on this computer and links to other apps ("app:<scheme>"), which are listed once it has.
var permissions = ["camera", "microphone", "location", "notifications", "sound", "popups", "clipboard", "screen"];
var extras = ["pointer", "fonts"];
var labels = {
    camera: "Camera", microphone: "Microphone", location: "Location", notifications: "Notifications", sound: "Sound",
    popups: "Pop-ups", clipboard: "Clipboard", screen: "Screen sharing", pointer: "Pointer lock", fonts: "Fonts on this computer",
    ads: "Ads and trackers", slash: "/ opens find",
};
function label(type) {
    return type.indexOf("app:") === 0 ? "Opens apps: " + type.slice(4) : labels[type] ?? type;
}

// What a row offers when its value is clicked: [{ value (as Sites keeps it; "" is the default), label }].
// Sound plays and pop-ups need a click unless you choose otherwise; the screen-share ask is its picker, so
// a lasting Allow could not skip it.
function choices(type) {
    switch (type) {
    case "ads": return [{ value: "", label: "Block" }, { value: "allow", label: "Allow" }];
    case "slash": return [{ value: "", label: "On" }, { value: "off", label: "Off" }];
    case "sound": return [{ value: "", label: "Allow" }, { value: "block", label: "Block" }];
    case "popups": return [{ value: "", label: "Block" }, { value: "allow", label: "Allow" }];
    case "screen": return [{ value: "", label: "Ask" }, { value: "block", label: "Block" }];
    }
    return [{ value: "", label: "Ask" }, { value: "allow", label: "Allow" }, { value: "block", label: "Block" }];
}
// A row's value at rest, for the site's choice `v`.
function value(type, v) {
    switch (type) {
    case "ads":
    case "popups": return v === "allow" ? "Allowed" : "Blocked";
    case "sound": return v === "block" ? "Blocked" : "Allowed";
    case "slash": return v === "off" ? "Off" : "On";
    }
    return v === "allow" ? "Allowed" : v === "block" ? "Blocked" : "Ask";
}

// The permission types listed for a site's Sites entry ({ choices, asked }): what it asked for or you
// changed, and `also` (a row called up by name), or with `all` every type besides.
function permissionTypes(entry, all, also) {
    const asked = Object.keys((entry && entry.asked) || {}).concat(also || []), chosen = Object.keys((entry && entry.choices) || {});
    const known = t => asked.indexOf(t) >= 0 || chosen.indexOf(t) >= 0;
    const apps = asked.concat(chosen).filter((t, i, list) => t.indexOf("app:") === 0 && list.indexOf(t) === i).sort();
    return permissions.filter(t => all || known(t)).concat(extras.filter(known), apps);
}

// The line under the host: { text, tone ("error" or ""), certificate (› opens the certificate view) }.
// `questioned`: the card line of a certificate the page was let past (PLAN.md 8g); `tls`: the panel's own
// handshake with the host (Facts.lookUpTls), null until it answers. Only the handshake shows a certificate.
function security(url, questioned, tls) {
    const certificate = !!tls && !!tls.sha256;
    if (questioned)
        return { text: questioned, tone: "error", certificate: certificate };
    if (/^https:/i.test(url))
        return { text: "Secure" + (tls && tls.protocol ? " · " + tls.protocol : ""), tone: "", certificate: certificate };
    if (PageState.insecure(url))
        return { text: "Not secure", tone: "error", certificate: false };
    return { text: "On this computer", tone: "", certificate: false };
}

// The certificate view's rows for the handshake's answer. Qt reports the cipher of a TLS 1.3 session but
// not its key exchange group, so the TLS line names the cipher.
function certificateRows(c) {
    const out = [];
    if (c.subject)
        out.push({ kind: "pair", key: "subject", label: "Issued to", value: c.subject });
    if (c.issuer)
        out.push({ kind: "pair", key: "issuer", label: "By", value: c.issuer });
    if (c.until)
        out.push({ kind: "pair", key: "until", label: "Valid", value: "until " + Failures.day(c.until) });
    if (c.sha256)
        out.push({ kind: "pair", key: "sha256", label: "SHA-256", value: c.sha256 });
    if (c.protocol)
        out.push({ kind: "text", key: "tls", label: c.protocol + (c.cipher ? " · " + c.cipher : "") });
    if (c.pem)
        out.push({ kind: "action", key: "pem", label: "Copy PEM" });
    return out;
}

function blocked(n) { return n + " blocked on this page" }
// Reader view's value (PLAN.md 3.9): its key, or why it is off; `article` as BrowserView.article
function reader(article) { return article === "none" ? "No article here" : "Ctrl+Alt+R" }
function cookies(n) { return "Cookies " + n + " · storage" }
function countdown(seconds) { return "Site data cleared in " + seconds + " s" }
var undoSeconds = 6;

// Zoom per site, in Chromium's steps; Qt takes 25 % to 500 %.
var zooms = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5];
function zoomStep(z, delta) {
    const found = zooms.findIndex(s => s >= z - 0.001), i = found < 0 ? zooms.length : found;
    // from between two steps, the next one in that direction
    const at = i < zooms.length && Math.abs(zooms[i] - z) < 0.001 ? i + delta : delta > 0 ? i : i - 1;
    return zooms[Math.max(0, Math.min(zooms.length - 1, at))];
}
function zoomText(z) { return Math.round(z * 100) + " %" }

// The panel's rows, top to bottom. `s`: { view ("", "certificate", "all"), clearing (a clear waits on its
// undo), mixed (an image came over http), blocker (ad blocking runs), ads (the site's choice), types (the
// permission types listed), tls (the handshake's answer, for the certificate view), waiting (the host of an
// ask that waits, or "") }. Kinds: head, note, split, choice, count, link, zoom, reader, action, back, pair, text,
// title, waiting; `key` names what a row sets or does. Values that change while the panel is open (counts,
// zoom, the countdown, the choices) are read by the rows themselves, so the list changes only with its shape.
function rows(s) {
    const out = [];
    const split = () => out.push({ kind: "split", key: "split" + out.length });
    const choice = t => ({ kind: "choice", key: t, label: label(t) });
    if (s.clearing) {
        out.push({ kind: "head", key: "head", plain: true });
        split();
        out.push({ kind: "title", key: "countdown" }, { kind: "note", key: "unloaded", text: "Its pages are unloaded until then." },
                 { kind: "action", key: "undo", label: "Undo" });
    } else if (s.view === "certificate") {
        out.push({ kind: "back", key: "back", label: "Certificate" });
        split();
        out.push(...certificateRows(s.tls || {}));
    } else if (s.view === "all") {
        out.push({ kind: "back", key: "back", label: "All permissions" });
        split();
        out.push(...s.types.map(choice));
    } else {
        out.push({ kind: "head", key: "head" });
        if (s.mixed)
            out.push({ kind: "note", key: "mixed", text: "Some images load over http" });
        if (s.blocker) {
            split();
            out.push(choice("ads"));
            if (s.ads !== "allow")
                out.push({ kind: "count", key: "blocked" });
        }
        split();
        out.push(...s.types.map(choice), { kind: "link", key: "all", label: "All permissions" });
        split();
        out.push({ kind: "zoom", key: "zoom", label: "Zoom" }, { kind: "reader", key: "reader", label: "Reader view" }, choice("slash"));
        split();
        out.push({ kind: "action", key: "clear", value: "Clear" });
    }
    if (s.waiting)
        out.push({ kind: "waiting", key: "waiting", text: s.waiting + " is asking  ·  after this" });
    return out;
}

// Clears the page's origin's local storage, IndexedDB and Cache Storage, then sets the title to "cleared"
// (or "failed ..."). It runs in a page loaded from a string with the origin as its base URL, which is a
// document of that origin that made no request. Service workers cannot be reached from it
// (InvalidStateError), so they stay.
var clearScript = "(async () => { localStorage.clear(); sessionStorage.clear();"
    + " if (indexedDB.databases) for (const d of await indexedDB.databases())"
    + " await new Promise(done => { const q = indexedDB.deleteDatabase(d.name); q.onsuccess = q.onerror = q.onblocked = done });"
    + " if (window.caches) for (const k of await caches.keys()) await caches.delete(k);"
    + " document.title = 'cleared' })().catch(e => document.title = 'failed ' + e.name)";
