.pragma library

// The browser's asks (PLAN.md 3.8, 11): the order they queue in, what each says and offers, and the
// rules behind Allow once, Deny and remembered choices. BrowserView keeps a page's queue; AskSection
// draws the one shown. An ask is a plain object { id, kind, host, origin, ... } with kind one of
//   leave, signin, proxy, certificate, passkey   page-blocking: the page waits on the answer
//   claude                                       Claude needs you (phase 5)
//   permission, screen                           a site wants a capability; `types` lists which
//   external                                     a link to another app's scheme: `url`, `scheme`, `app`
//   save                                         Ctrl+D in a private window: the page to save, `url`, `title`, `icon`
//   password                                     a login form sent: "Save password for <host>?" for `origin`, `user`,
//                                                `password` (in memory only, gone with the ask)
// `quiet`: a notification ask made without a click, shown only as a bell at the card's right.

// Stacked states (PLAN.md 11): page-blocking > Claude needs you > permission > external app > saving (a page, a
// password) > the insecure note, which AddressField shows only with no ask.
var ranks = { leave: 0, signin: 0, proxy: 0, certificate: 0, passkey: 0, claude: 1, permission: 2, screen: 2, external: 3, save: 4, password: 4 };

// The queue as it shows: loud asks by rank, then in arrival order. The first is the one in the card.
function order(asks) {
    return asks.filter(a => !a.quiet).sort((a, b) => (ranks[a.kind] ?? 9) - (ranks[b.kind] ?? 9) || a.id - b.id);
}
function shown(asks) {
    return order(asks)[0] ?? null;
}

// A new ask joins the queue (a new array). Permission asks from one origin that wait together merge
// into one, which reads as one sentence; a link to an address already waiting is not asked twice.
function add(asks, a) {
    if (a.kind === "permission") {
        const i = asks.findIndex(o => o.kind === "permission" && o.origin === a.origin && !!o.quiet === !!a.quiet);
        if (i >= 0) {
            const o = asks[i];
            const merged = Object.assign({}, o, { types: o.types.concat(a.types.filter(t => o.types.indexOf(t) < 0)),
                                                  requests: o.requests.concat(a.requests), sound: o.sound || a.sound });
            return asks.slice(0, i).concat([merged], asks.slice(i + 1));
        }
    }
    if (a.kind === "external" && asks.some(o => o.kind === "external" && o.url === a.url))
        return asks;
    return asks.concat([a]);
}

// What a permission request needs no answer for, from `decided(type)`: the answer given for this page
// load ("allow" / "deny") or the site's lasting choice ("allow" / "block"). Allowed only when every
// type it asks for is; refused when any is refused; otherwise "" and the card asks.
function preset(types, decided) {
    const d = types.map(decided);
    if (d.some(v => v === "deny" || v === "block"))
        return "deny";
    return d.length > 0 && d.every(v => v === "allow") ? "allow" : "";
}

// What a waiting ask is, in the one word of its page's rail row (PLAN.md 3.20): "camera?", "sign in", "leave?"
var askWords = { leave: "leave?", signin: "sign in", proxy: "sign in", certificate: "certificate?", passkey: "passkey",
                 screen: "screen?", external: "open app?", save: "save?", password: "password?" };
var typeWords = [["screen", "screen?"], ["camera", "camera?"], ["microphone", "mic?"], ["location", "location?"],
                 ["notifications", "notify?"], ["clipboard", "clipboard?"]];
function word(a) {
    if (!a)
        return "";
    if (a.kind === "permission") {
        const t = typeWords.find(w => (a.types || []).indexOf(w[0]) >= 0);
        return t ? t[1] : "allow?";
    }
    return askWords[a.kind] ?? "asks you";
}

// Glyphs for what an allowed permission keeps using (the card's right and the page's row), most
// telling first; the row shows the first.
var useGlyphs = [["screen", "screen_share"], ["camera", "videocam"], ["microphone", "mic"], ["location", "location_on"]];
function glyphs(types) {
    return useGlyphs.filter(g => types.indexOf(g[0]) >= 0).map(g => g[1]);
}

function scheme(url) {
    const m = /^([a-z][a-z0-9+.-]*):/i.exec(url);
    return m ? m[1].toLowerCase() : "";
}
// Schemes the engine loads itself; any other is another app's (mailto:, magnet:, zoommtg:). browser: is the browser's
// own pages (Engine's scheme, PLAN.md 3.17).
var internal = ["http", "https", "file", "data", "blob", "about", "view-source", "javascript", "chrome", "chrome-error",
                "chrome-extension", "devtools", "qrc", "filesystem", "ws", "wss", "browser"];
function external(url) {
    const s = scheme(url);
    return s !== "" && internal.indexOf(s) < 0;
}

// "https://meet.google.com" for any URL of that origin; "" for one without a host (data:, about:).
function originOf(url) {
    const m = /^([a-z][a-z0-9+.-]*:\/\/)(?:[^\/?#@]*@)?([^\/?#]+)/i.exec(url);
    return m ? (m[1] + m[2]).toLowerCase() : "";
}
// The https origin of WebEngineClientCertificateSelection.host, a URL with a host and port and no scheme
// ("//vpn.lokal:443"), with the default port dropped as a page's address drops it.
function tlsOrigin(hostAndPort) {
    const m = /^(?:\/\/)?([^\/?#@]+?)(?::443)?$/.exec(hostAndPort);
    return m ? "https://" + m[1].toLowerCase() : "";
}

// A client certificate as its row reads: "abdul · Sectigo · 2027".
function certLabel(subject, issuer, expiry) {
    const year = expiry && !isNaN(new Date(expiry).getTime()) ? String(new Date(expiry).getFullYear()) : "";
    return [subject, issuer, year].filter(s => s).join(" · ");
}

function list(parts) {
    return parts.length < 2 ? parts.join("") : parts.slice(0, -1).join(", ") + " and " + parts[parts.length - 1];
}
var verbs = { location: "know your location", notifications: "show notifications", clipboard: "see what you copy",
              pointer: "lock your pointer", fonts: "see the fonts on this computer" };
// "use your microphone and camera", "know your location": what a permission ask wants, in one sentence.
function wants(types, sound) {
    const use = ["microphone", "camera"].filter(t => types.indexOf(t) >= 0);
    const parts = [];
    if (use.length > 0)
        parts.push("use your " + use.join(" and "));
    if (types.indexOf("screen") >= 0)
        parts.push(sound ? "share your screen and its sound" : "share your screen");
    for (const t of types)
        if (verbs[t])
            parts.push(verbs[t]);
    return list(parts);
}

var failures = {
    Timeout: "The security key didn't answer in time",
    KeyNotRegistered: "This security key isn't registered here",
    KeyAlreadyRegistered: "This security key is registered here already",
    SoftPinBlock: "Too many wrong PINs: take the key out and put it back",
    HardPinBlock: "The key is locked after too many wrong PINs",
    UserConsentDenied: "The key refused",
};

// What the card shows for ask `a` on a page at `pageHost`: `lines` (the first is the request, 14 px;
// { text, note } lines after it are 13 px colSubtext), `fields` ({ key, label, secret }), `options`
// (rows, one picked), `notes` under them, `buttons` ({ label, choice }; none is the default), `actions` (text actions
// on the ask's last line instead of buttons, { label, choice }), `negative` (what Esc picks) and `submit` (what Enter in
// a field picks). An ask from another origin than the page's names itself.
function view(a, pageHost) {
    const who = a.host && a.host !== pageHost ? a.host + " wants" : "Wants";
    const button = (label, choice) => ({ label: label, choice: choice });
    const out = { lines: [], fields: [], options: [], notes: [], buttons: [], actions: [], negative: "cancel", submit: "" };
    switch (a.kind) {
    case "permission":
        out.lines = [{ text: who + " to " + wants(a.types, a.sound) }];
        out.buttons = [button("Allow once", "allow"), button("Deny", "deny")];
        out.negative = "deny";
        break;
    case "signin":
    case "proxy":
        out.lines = [{ text: a.kind === "proxy" ? "Sign in to the proxy " + a.host : "Sign in to " + a.host }];
        out.fields = [{ key: "user", label: "User", secret: false }, { key: "password", label: "Pass", secret: true }];
        if (a.kind === "signin" && !a.secure)
            out.notes = ["Sent without encryption"];
        out.buttons = [button("Sign in", "signin"), button("Cancel", "cancel")];
        out.submit = "signin";
        break;
    case "certificate":
        out.lines = [{ text: who + " a certificate to identify you" }];
        out.options = a.options;
        out.buttons = [button("Send", "send"), button("Cancel", "cancel")];
        break;
    case "leave":
        out.lines = [{ text: "Leave this page?" }, { text: a.host + " has changes that may not be saved.", note: true }];
        out.buttons = [button("Leave", "leave"), button("Stay", "stay")];
        out.negative = "stay";
        break;
    case "passkey":
        out.lines = [{ text: who + " to use a passkey" }];
        if (a.state === "SelectAccount") {
            out.lines.push({ text: "Choose an account", note: true });
            out.options = a.options;
            out.buttons = [button("Continue", "account"), button("Cancel", "cancel")];
        } else if (a.state === "CollectPin") {
            out.fields = [{ key: "pin", label: a.pinReason === "Challenge" ? "Key PIN" : "New key PIN", secret: true }];
            if (a.pinError === "WrongPin")
                out.notes = ["Wrong PIN" + (a.attempts > 0 ? " · " + a.attempts + (a.attempts === 1 ? " try" : " tries") + " left" : "")];
            else if (a.pinError === "TooShort")
                out.notes = ["The PIN needs at least " + a.minPin + " characters"];
            else if (a.pinError === "InvalidCharacters")
                out.notes = ["The PIN has characters the key does not take"];
            else if (a.pinError === "SameAsCurrentPin")
                out.notes = ["The new PIN is the same as the old one"];
            out.buttons = [button("Continue", "pin"), button("Cancel", "cancel")];
            out.submit = "pin";
        } else if (a.state === "RequestFailed") {
            out.lines.push({ text: failures[a.failure] ?? "The passkey request failed", note: true });
            out.buttons = [button("Try again", "retry"), button("Cancel", "cancel")];
        } else {
            out.lines.push({ text: "Touch your security key", note: true });
            out.buttons = [button("Cancel", "cancel")];
        }
        break;
    case "screen":
        out.lines = [{ text: who + " to share your screen" }];
        if (a.picker)
            out.lines.push({ text: "Choose what to share in the picker", note: true });
        else
            out.options = a.options;
        // Share only once there is something to share: sources fill in as Chromium finds them
        out.buttons = (a.picker || a.options.length > 0 ? [button("Share", "share")] : []).concat([button("Cancel", "cancel")]);
        break;
    case "external":
        if (a.app) {
            out.lines = [{ text: who + " to open " + (/^[aeiou]/.test(a.scheme) ? "an " : "a ") + a.scheme + ": link in " + a.app },
                         { text: "(default app for " + a.scheme + ":)", note: true }];
            out.buttons = [button("Open", "open"), button("Cancel", "cancel")];
        } else {
            out.lines = [{ text: "No app opens " + a.scheme + ": links" }];
            out.buttons = [button("Copy link", "copy"), button("Cancel", "cancel")];
        }
        break;
    // a private window saves nothing of its own (PLAN.md 3.14)
    case "save":
        out.lines = [{ text: "Save to the main profile?" }];
        out.buttons = [button("Save", "save"), button("Cancel", "cancel")];
        break;
    // PLAN.md 7: a line in the card, "Save password for <host>? Save · Not now"
    case "password":
        out.lines = [{ text: "Save password for " + a.host + "?" }];
        out.actions = [button("Save", "save"), button("Not now", "notnow")];
        out.negative = "notnow";
        break;
    }
    return out;
}
