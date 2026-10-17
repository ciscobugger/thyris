.pragma library

// Rules of the page states (PLAN.md 3.8): https-first for typed addresses and when the address card says
// Not secure; the card's second line; the page's own dialogs, popups, file picks, drops and full screen.

// The host name of `url`, lower case, without user:pass@ or port; an IPv6 address keeps its brackets.
function hostOf(url) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?(\[[^\]\/]*\]|[^\/:?#]*)/i.exec(url);
    return m ? m[1].toLowerCase() : "";
}

// Two addresses on the same site as a person sees it: the same host, or one under the other (a.claude.ai and
// claude.ai). No public-suffix list, so two siblings under co.uk do not count, which errs on the safe side.
function sameSite(a, b) {
    const x = hostOf(a), y = hostOf(b);
    return x !== "" && y !== "" && (x === y || x.endsWith("." + y) || y.endsWith("." + x));
}

// This machine: nothing sent to it crosses a network.
function loopback(host) {
    return /^(localhost|.+\.localhost|127(\.\d{1,3}){3}|\[::1\])$/.test(host);
}

// Loaded as typed, never tried over https: this machine and IP addresses, which certificates do not name.
function exempt(host) {
    return loopback(host) || /^(\d{1,3}(\.\d{1,3}){3}|\[[0-9a-f:.]*\])$/.test(host);
}

// What a typed address loads first, `url` being what the text resolved to (Omnibox.toUrl), and what
// it falls back to if https cannot connect: { url, fallback }. A scheme-less or http:// address
// tries https first; https:// as typed has no fallback, and neither has an exempt host.
function httpsFirst(text, url) {
    if (/^http:\/\//i.test(url) && !exempt(hostOf(url)))
        return { url: "https://" + url.slice(7), fallback: url };
    if (/^https:\/\//i.test(url) && !/^[a-z][a-z0-9+.-]*:\/\//i.test(text.trim()))
        return { url: url, fallback: "http://" + url.slice(8) };
    return { url: url, fallback: "" };
}

// The card reads Not secure for a page served over plain http, unless it comes from this machine.
function insecure(url) {
    return /^http:\/\//i.test(url) && !loopback(hostOf(url));
}

// The page's host as the address card shows it (www. dropped, port kept), or "" for an address without
// one (data:, about:blank, file:).
function pageHost(url) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?([^\/?#]+)/i.exec(url);
    return m ? m[1].toLowerCase().replace(/^www\./, "") : "";
}

// A page's alert, confirm or prompt (PLAN.md 8j) names the top frame's host, never a frame's.
function says(url) {
    return (pageHost(url) || "This page") + " says";
}
function blockMore(url) {
    return "Block more dialogs from " + (pageHost(url) || "this page");
}

// The address card's second line (PLAN.md 3.8): what holds the page now, then what its certificate's page
// says of it (8g, `failure`: the page's cardLine), else a load that waits. `s`: { dialog, choosing, popup,
// failure, waitingFor } of the page.
function stateLine(s) {
    if (s.dialog)
        return "Dialog from this page";
    if (s.choosing)
        return "Choosing files in Files";
    if (s.popup)
        return "Sign-in window open";
    if (s.failure)
        return s.failure;
    return s.waitingFor ? "Waiting for " + s.waitingFor : "";
}

// Hosts that only sign in or take payments: a popup to one keeps window.opener to hand its answer back,
// so it opens attached even without a size. 3-D Secure pages run on the bank's own "3ds." host.
var signInHosts = ["accounts.google.com", "login.microsoftonline.com", "login.live.com", "appleid.apple.com",
                   "www.paypal.com", "pay.google.com"];
function signIn(url) {
    const host = hostOf(url);
    return signInHosts.indexOf(host) >= 0 || /^3ds\./.test(host);
}

// A link from another app that is a sign-in (~/book4-edge/signin-notch-plan.md): it opens in the notch, not as a page.
// An OAuth or OpenID Connect authorize address (response_type, client_id and redirect_uri all in its query), the
// sign-in pages of Google, Microsoft, GitHub and Apple, the 3-D Secure hosts of the popup rule above, a host that
// only signs in (login., auth., accounts., sso., id.: Tailscale, OpenAI, Spotify) and an address whose last part
// names a sign-in (/login, /signin, /sso, /authorize, /device). Only the last part counts: a docs page under
// /oauth2/ or a file named login.go stays a page. A page from an app that asks for a password or a one-time code
// moves to the notch as well, whatever its address (Main.watchLink, signInFields). Before 2026-10-10 only the first
// four opened in the notch, and a site's own login from an app came up in the old floating peek.
var signInWords = /^(login|log-in|signin|sign-in|sign_in|sso|authorize|device|devicelogin)$/i;
var signInHosts2 = /^(login|auth|accounts?|sso|signin|id|identity)\./i;
function appSignIn(url) {
    if (!/^https?:\/\//i.test(url))
        return false;
    const q = queryOf(url);
    if (q.response_type !== undefined && q.client_id !== undefined && q.redirect_uri !== undefined)
        return true;
    const host = hostOf(url), path = pathOf(url);
    switch (host) {
    case "accounts.google.com":
        return /^\/(o\/oauth2\/|signin(\/|$)|servicelogin|accountchooser|v3\/signin)/i.test(path);
    case "login.microsoftonline.com":
    case "login.live.com":
        return true;
    case "github.com":
        return /^\/(login|login\/oauth\/authorize|login\/device|session)\/?$/i.test(path);
    case "appleid.apple.com":
        return /^\/auth\//i.test(path);
    }
    const parts = path.split("/").filter(x => x.length);
    return /^3ds\./.test(host) || signInHosts2.test(host) || (parts.length > 0 && signInWords.test(parts[parts.length - 1]));
}
// Run in a page: does it ask for a password or a one-time code on screen
var signInFields = "(() => { for (const f of document.querySelectorAll('input[type=password], input[autocomplete~=one-time-code],"
    + " input[autocomplete~=current-password]')) { const r = f.getBoundingClientRect(); if (r.width > 0 && r.height > 0) return true }"
    + " return false })()";
// An address's path ("/" for none) and its query's names and values (the first of each, decoded)
function pathOf(url) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/[^\/?#]*([^?#]*)/i.exec(url);
    return m ? m[1] || "/" : "";
}
function queryOf(url) {
    const out = {}, m = /\?([^#]*)/.exec(url);
    if (!m)
        return out;
    const decode = t => { try { return decodeURIComponent(t.replace(/\+/g, " ")) } catch (e) { return t } };
    for (const part of m[1].split("&")) {
        const at = part.indexOf("="), name = decode(at < 0 ? part : part.slice(0, at));
        if (name !== "" && !(name in out))
            out[name] = at < 0 ? "" : decode(part.slice(at + 1));
    }
    return out;
}
// Where an app's sign-in hands its answer back: the redirect_uri its link names, or ""
function redirectOf(url) {
    const r = queryOf(url).redirect_uri ?? "";
    return /^https?:\/\//i.test(r) ? r : "";
}
// The sign-in at `url` is at its redirect: the same host and port (any loopback name for another: apps listen on
// localhost, 127.0.0.1 and [::1] alike) and under the same path. Not on a sign-in page itself, whose host the redirect
// may share.
function reached(url, redirect) {
    if (!redirect || appSignIn(url))
        return false;
    const port = u => { const m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?(?:\[[^\]]*\]|[^\/:?#]*):(\d+)/i.exec(u); return m ? m[1] : /^https:/i.test(u) ? "443" : "80" };
    const a = hostOf(url), b = hostOf(redirect), path = pathOf(url), base = pathOf(redirect);
    const under = path === base || path.startsWith(base.endsWith("/") ? base : base + "/");
    return (a === b || loopback(a) && loopback(b)) && port(url) === port(redirect) && under;
}

// Where a page's new window goes (PLAN.md 8k): "popup" (an attached popup window) for window.open with a
// size, or to a sign-in or payment host; "page" (a rail row, as before) otherwise; "blocked" when it came
// without a click from you. `destination`: "tab", "background", "window" or "dialog" (window.open with a size).
function newWindow(destination, userInitiated, url) {
    if (!userInitiated)
        return "blocked";
    return destination === "dialog" || destination === "tab" && signIn(url) ? "popup" : "page";
}

// A file input's pick in Files (PLAN.md 8l), for `mode` "one", "multiple" or "folder": the label on Files'
// Choose bar, and the paths the page gets from what was chosen (one unless the input takes several).
function pickLabel(mode, host) {
    return (mode === "folder" ? "Choose a folder for " : "Choose files for ") + (host || "this page");
}
function pickedFor(mode, paths) {
    return mode === "multiple" ? paths.slice() : paths.slice(0, 1);
}

// Page full screen's notices (PLAN.md 8m).
var fullScreenNotice = "Esc exits full screen";
function askingNotice(host) {
    return host + " is asking · Esc to answer";
}

// A file dropped where the page does not take it (PLAN.md 8l, 3.13): Chromium opens it as a new page
// (crbug.com/451659), and a page that is not itself a file cannot open a file: address any other way.
// Returns "page" for a PDF, image or text file, which joins this thread, "nothing" for any other file, and
// "" when the new page for `target`, opened from a page at `current`, is no drop.
var pageTypes = ["pdf", "png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "bmp", "txt", "md", "log", "csv"];
function dropped(target, current) {
    if (!/^file:/i.test(target) || current === "" || /^file:/i.test(current))
        return "";
    const ext = (/\.([a-z0-9]+)$/i.exec(target.replace(/[?#].*$/, "")) ?? [])[1] ?? "";
    return pageTypes.indexOf(ext.toLowerCase()) >= 0 ? "page" : "nothing";
}
