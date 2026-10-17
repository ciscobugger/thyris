.pragma library
.import "RailRows.js" as RailRows

// Passwords (PLAN.md 7, 3.15): what the browser's script world does on a page's login forms, and how the browser
// names a saved login. Qt WebEngine has no password manager: `watcher` tells the browser, over the view's web channel
// (object "logins", which only that world can reach), when a login field of the top document takes or leaves the
// focus and when a login form is sent; `fill` fills one. The page's own scripts see neither. Passwords (C++) keeps the
// logins in the system keyring.

// Shared by both scripts: a login form's fields. The user name for password field `p` is its form's
// autocomplete=username (or email) field, else the last text, email or tel field before it.
var helpers = "const input = e => e instanceof HTMLInputElement, secret = e => input(e) && e.type === 'password',"
    + " plain = e => input(e) && /^(text|email|tel)$/.test(e.type);"
    + " const fieldsOf = e => e.form ? Array.from(e.form.elements).filter(input) : Array.from(e.getRootNode().querySelectorAll('input'));"
    + " const userFor = (list, p) => { const named = list.find(x => plain(x) && /\\b(username|email)\\b/.test(x.autocomplete));"
    + " if (named) return named; const before = list.slice(0, list.indexOf(p)).filter(plain); return before[before.length - 1] || null };";

// Run in the browser's script world at the start of each top document. Messages: field({ origin, role }), role
// "password", "user" (the user name field of a form with a password field), "code" (a one-time code's field: autocomplete
// one-time-code, or named, labelled or hinted as a code, OTP or PIN; the notch offers a code from your phone for it) or ""
// when such a field loses the focus to
// the page (not when the page loses it to the browser, as F6 to the Fill rows does: it comes back with the page's);
// submitted({ origin, user, password }) for a form sent with a password in it by you, the new password of a sign-up or
// change form. Sent by you: a trusted submit within 5 s (Chromium's user activation lifespan) of your Enter in one of
// its fields or your click on one of its submit buttons, each good for one submit. A trusted submit alone is not
// enough: a script's form.requestSubmit() or button.click() makes Blink send one too. armed(...) carries the same login
// at that Enter or click, before the form goes: a page that leaves at once can lose the submitted message (CEF), and the
// browser then takes the armed one when the form's load starts (BrowserView). Focus events a page dispatches
// itself are not trusted and say nothing. `saves` false (a private window, PLAN.md 3.14): no form is ever reported, so
// its passwords never leave the page.
function watcher(saves) {
    return "(() => { if (window !== window.top) return; " + helpers
        + " let n = 0; const send = (method, m) => { if (typeof qt === 'undefined' || !qt.webChannelTransport) return;"
        + " qt.webChannelTransport.send(JSON.stringify({ type: 6, object: 'logins', method: method, args: [JSON.stringify(m)], id: ++n })) };"
        + " const code = e => input(e) && /^(text|tel|number)$/.test(e.type) && (e.autocomplete === 'one-time-code'"
        + " || /(^|[^a-z])(otp|totp|2fa|mfa|one.?time|code|pin|verification)([^a-z]|$)/i.test([e.name, e.id, e.placeholder, e.getAttribute('aria-label')].join(' ')));"
        + " const role = e => { if (secret(e)) return 'password'; if (code(e)) return 'code'; if (!plain(e)) return ''; const list = fieldsOf(e), p = list.find(secret);"
        + " return p && userFor(list, p) === e ? 'user' : '' };"
        + " const target = e => e.composedPath()[0] || e.target;"
        + " addEventListener('focusin', e => { if (!e.isTrusted) return; const r = role(target(e)); if (r) send('field', { origin: location.origin, role: r }) }, true);"
        + " addEventListener('focusout', e => { if (e.isTrusted && role(target(e)) && document.hasFocus()) send('field', { origin: location.origin, role: '' }) }, true);"
        + (saves ? " let armed = null; const login = f => { const list = Array.from(f.elements).filter(input), sent = list.filter(x => secret(x) && x.value);"
                   + " if (sent.length === 0) return null; const last = sent[sent.length - 1];"
                   + " const p = sent.find(x => x.autocomplete === 'new-password') || (sent.length > 1 && last.value === sent[sent.length - 2].value ? last : sent[0]);"
                   + " const u = userFor(list, sent[0]); return { origin: location.origin, user: u ? u.value : '', password: p.value } };"
                   + " const arm = f => { if (!(f instanceof HTMLFormElement)) return; armed = { form: f, at: Date.now() }; const m = login(f); if (m) send('armed', m) };"
                   + " addEventListener('keydown', e => { const t = target(e); if (e.isTrusted && e.key === 'Enter' && input(t)) arm(t.form) }, true);"
                   + " addEventListener('click', e => { if (!e.isTrusted) return; const b = e.composedPath().find(x => (x instanceof HTMLButtonElement"
                   + " || x instanceof HTMLInputElement) && /^(submit|image)$/.test(x.type)); if (b) arm(b.form) }, true);"
                   + " addEventListener('submit', e => { const f = e.target; if (!e.isTrusted || !(f instanceof HTMLFormElement)) return;"
                   + " const yours = armed && armed.form === f && Date.now() - armed.at < 5000; armed = null; if (!yours) return;"
                   + " const m = login(f); if (m) send('submitted', m) }, true);"
                 : "")
        + " })()";
}

// Run in the browser's script world: `user` and `password` into the login form of the focused field (else the page's
// first form with a password field), only while the top document is still at `origin`; answers whether it filled.
// The fields take them as typed text does (input and change events), so the page's own scripts see a value.
function fill(origin, user, password) {
    return "(() => { const s = " + JSON.stringify({ origin: origin, user: user, password: password }) + ";"
        + " if (window !== window.top || location.origin !== s.origin) return false; " + helpers
        + " let a = document.activeElement; while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;"
        + " let list = input(a) ? fieldsOf(a) : []; if (!list.some(secret)) { const p = document.querySelector('input[type=password]'); list = p ? fieldsOf(p) : [] }"
        + " const p = list.find(x => secret(x) && x.autocomplete !== 'new-password') || list.find(secret); if (!p) return false;"
        + " const set = (e, v) => { e.focus(); e.value = v; e.dispatchEvent(new Event('input', { bubbles: true, composed: true }));"
        + " e.dispatchEvent(new Event('change', { bubbles: true })) };"
        + " const u = userFor(list, p); if (u && s.user) set(u, s.user); set(p, s.password);"
        + " (list.indexOf(a) >= 0 ? a : p).focus(); return true })()";
}

// A message of `watcher` for the page at `pageOrigin`: the parsed object, or null for one that does not parse or
// comes from another origin (the page went on since) or from a page that is neither http nor https.
function parse(text, pageOrigin) {
    let m = null;
    try {
        m = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!m || typeof m.origin !== "string" || m.origin !== pageOrigin || !/^https?:\/\//.test(m.origin))
        return null;
    return m;
}

// The saved logins of `origin` (the keyring's entries: { id, origin, user }).
function forOrigin(entries, origin) {
    return origin ? entries.filter(e => e.origin === origin) : [];
}
function saved(entries, origin, user) {
    return entries.find(e => e.origin === origin && e.user === user) ?? null;
}

// How a login's site reads: its host as the address card reads it ("github.com"), with "http://" before it for a
// plain http one, which is another origin than the https one of that host.
function host(origin) {
    const h = RailRows.split(origin).host;
    return /^http:\/\//i.test(origin) ? "http://" + h : h;
}
// the Fill rows (PLAN.md 7): a suggestions' row per login, its user name (the host for one saved without)
function fillRows(logins) {
    return logins.map(e => ({ kind: "fill", glyph: "key", title: e.user || host(e.origin), detail: "Fill", entry: e }));
}

// Why a save, a fill or Settings' Show did not happen, by its failure: "none" (no Secret Service answers), "locked"
// (the keyring's unlock was refused), "unencrypted" (the keyring has no password, Passwords.plainKeyring), "form" (the page has no login form now), "exists" (an edit to a user name another
// login of the site has, whose item saving would replace), else the keyring refused it. The first two are the card's
// short word (Main's cardNotice), the last Settings' line under the login.
function failed(what, failure) {
    const why = failure === "none" ? "no keyring answers" : failure === "locked" ? "the keyring stayed locked"
              : failure === "unencrypted" ? "your keyring has no password, so it would be kept as plain text"
              : failure === "form" ? "no login form here" : failure === "exists" ? "that user name is saved for this site already"
              : "the keyring refused it";
    return ({ save: "Not saved: ", fill: "Not filled: ", show: "Not shown: " })[what] + why;
}
