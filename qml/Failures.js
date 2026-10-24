.pragma library
.import "PageState.js" as PageState

// The browser's own pages for failures (PLAN.md 3.8 8f-8i): which page a failed load, a questioned
// certificate, a stopped page process or an unclean quit shows, in wording that claims only what the browser
// measured. FailurePage draws one: { key, kind, url, host, title, body: [paragraphs], actions: [{ label,
// action }], details: [lines] (the site panel's too), facts: [{ label, value, mono, wide }] or null for the
// details as plain lines, code, codeNote, go (Continue's label, under the facts), note (under the
// buttons), cardLine (the address card's second line), tone ("error" for certificates) }.

function pad(n) { return (n < 10 ? "0" : "") + n }
function clock(ms) {
    const d = new Date(ms);
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
}
var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function day(ms) {
    const d = new Date(ms);
    return d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear();
}
// Memory as the page says it: "1.1 GB", "640 MB".
function size(bytes) {
    const gb = bytes / 1073741824;
    return gb >= 1 ? gb.toFixed(1) + " GB" : Math.max(1, Math.round(bytes / 1048576)) + " MB";
}
var numbers = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"];

// A name without www., for "doesn't exist" and the host one edit away.
function bareHost(url) { return PageState.hostOf(url).replace(/^www\./, "") }

// One letter added, dropped or changed.
function oneEdit(a, b) {
    if (a === b || Math.abs(a.length - b.length) > 1)
        return false;
    let i = 0;
    while (i < a.length && i < b.length && a[i] === b[i])
        i++;
    if (a.length === b.length)
        return a.slice(i + 1) === b.slice(i + 1);
    return a.length > b.length ? a.slice(i + 1) === b.slice(i) : a.slice(i) === b.slice(i + 1);
}
// The first of `hosts` (from history) one edit away from `host`.
function nearHost(host, hosts) {
    for (const h of hosts)
        if (oneEdit(host, h))
            return h;
    return "";
}

function page(fields) {
    return Object.assign({ body: [], actions: [], details: [], facts: null, code: "", codeNote: "", go: "", note: "", cardLine: "", tone: "" }, fields);
}
var tryAgain = { label: "Try again", action: "retry" };

// A main-frame load that failed, or got no reply in time. `f`: { url, at, code (Chromium's net error; 0 for
// the browser's own stop), domain ("connection", "dns", "certificate", "http", "status", "internal"), name
// (Qt's errorString), reachability ("none", "local", "online", "unknown": what the network backend reports),
// watching (a backend reports it at all), hosts (history), waited (seconds since the load started) }. null
// where the browser adds nothing: an HTTP status is the site's own page, a stop or a download is no
// failure, and a certificate has its own page. Chromium's own HTTP errors (ERR_EMPTY_RESPONSE,
// ERR_TOO_MANY_REDIRECTS) are failures like any other.
function load(f) {
    const host = PageState.pageHost(f.url) || f.url;
    const base = { kind: "", url: f.url, host: host, at: f.at, key: f.url + " " + f.at, code: (f.name || "").replace(/^net::/, ""),
                   codeNote: "tried " + clock(f.at), actions: [tryAgain] };
    // the browser's own stop, ERR_CONNECTION_TIMED_OUT, ERR_TIMED_OUT
    if (!f.code && f.waited > 0 || f.code === -118 || f.code === -7)
        return page(Object.assign(base, { kind: "noReply", title: host + " didn't answer", body: ["No reply within " + Math.round(f.waited) + " s."] }));
    if (f.domain === "status" || f.domain === "certificate" || f.code === -3)
        return null;
    // ERR_INTERNET_DISCONNECTED, or no network by the backend's account (not for this machine's own servers)
    if (f.code === -106 || f.reachability === "none" && !PageState.loopback(PageState.hostOf(f.url))
            && (f.domain === "connection" || f.domain === "dns")) {
        const body = ["This computer has no network connection."];
        if (f.watching)
            body.push("The page loads again by itself when the network is back.");
        return page(Object.assign(base, { kind: "offline", title: "Can't reach " + host, body: body }));
    }
    // ERR_NAME_NOT_RESOLVED
    if (f.code === -105) {
        const name = bareHost(f.url), near = nearHost(name, f.hosts ?? []);
        const actions = near ? [{ label: "Did you mean " + near + "?", action: "near" }] : [];
        return page(Object.assign(base, { kind: "name", title: name + " doesn't exist", body: ["DNS has no address for this name."],
                                          actions: actions.concat([{ label: "Search", action: "search" }]), near: near,
                                          search: name }));
    }
    return page(Object.assign(base, { kind: "connection", title: "Can't reach " + host }));
}

// Chromium's names for WebEngineCertificateError.type, for Details.
var certificateCodes = {
    "-150": "ERR_SSL_PINNED_KEY_NOT_IN_CERT_CHAIN", "-200": "ERR_CERT_COMMON_NAME_INVALID", "-201": "ERR_CERT_DATE_INVALID",
    "-202": "ERR_CERT_AUTHORITY_INVALID", "-203": "ERR_CERT_CONTAINS_ERRORS", "-204": "ERR_CERT_NO_REVOCATION_MECHANISM",
    "-205": "ERR_CERT_UNABLE_TO_CHECK_REVOCATION", "-206": "ERR_CERT_REVOKED", "-207": "ERR_CERT_INVALID",
    "-208": "ERR_CERT_WEAK_SIGNATURE_ALGORITHM", "-210": "ERR_CERT_NON_UNIQUE_NAME", "-211": "ERR_CERT_WEAK_KEY",
    "-212": "ERR_CERT_NAME_CONSTRAINT_VIOLATION", "-213": "ERR_CERT_VALIDITY_TOO_LONG", "-214": "ERR_CERTIFICATE_TRANSPARENCY_REQUIRED",
    "-215": "ERR_CERT_SYMANTEC_LEGACY", "-217": "ERR_CERT_KNOWN_INTERCEPTION_BLOCKED", "-218": "ERR_SSL_OBSOLETE_VERSION"
};
var risk = "Someone on this network could read or change what you send to this site.";

// A certificate the engine questions (8g). `c`: { url, at, now, type, overridable (false for an HSTS host and
// the fatal errors), names (DNS names the certificate is for), subject, issuer, from, until (ms), sha256 }.
// Revoked certificates and HSTS hosts get no Continue; Continue lasts for one page load.
function certificate(c) {
    const host = PageState.pageHost(c.url) || c.url;
    let title = "The certificate for " + host + " can't be trusted", body = risk, line = "Certificate not trusted", go = c.overridable;
    if (c.type === -206) {
        title = "The issuer revoked this certificate";
        line = "Certificate revoked";
        go = false;
    } else if (c.type === -203 || c.type === -207) {
        title = "The certificate for " + host + " is not valid";
        line = "Certificate not valid";
    } else if (!c.overridable) {
        title = PageState.hostOf(c.url).replace(/^www\./, "") + " only allows secure connections, and this one isn't";
        line = "Secure connection required";
    } else if (c.type === -201 && c.until < c.now) {
        title = "The certificate for " + host + " expired";
        body = "It expired on " + day(c.until) + ". " + risk;
        line = "Certificate expired";
    } else if (c.type === -201) {
        title = "The certificate for " + host + " isn't valid yet";
        body = "It is valid from " + day(c.from) + ". " + risk;
        line = "Certificate not valid yet";
    } else if (c.type === -200) {
        title = "The certificate is for " + ((c.names ?? [])[0] || "another site") + ", not this site";
        line = "Certificate for another site";
    } else if (c.type === -202) {
        title = "No known authority signed this certificate";
        line = "Unknown certificate authority";
    }
    const details = [], facts = [];
    if (c.subject || c.issuer) {
        details.push("Issued to " + (c.subject || "?") + " by " + (c.issuer || "?"));
        facts.push({ label: "Issued to", value: c.subject || "?" });
    }
    if (c.until) {
        details.push("Valid " + day(c.from) + " - " + day(c.until) + (c.sha256 ? " · SHA-256 " + c.sha256 : ""));
        facts.push({ label: "Valid", value: day(c.from) + " – " + day(c.until) });
    }
    if (c.subject || c.issuer)
        facts.push({ label: "Issued by", value: c.issuer || "?", wide: true });
    if (c.sha256)
        facts.push({ label: "Fingerprint (SHA-256)", value: c.sha256, mono: true, wide: true });
    return page({ kind: "certificate", url: c.url, host: host, at: c.at, key: c.url + " " + c.at, title: title, body: [body],
                  actions: [{ label: "Go back", action: "back" }], details: details, facts: facts, code: certificateCodes[String(c.type)] ?? "",
                  go: go ? "Continue to " + host + " once (not safe)" : "", cardLine: line, tone: "error" });
}

// How a page's process ended, from renderProcessTerminated: `status` "normal", "abnormal", "crashed" or
// "killed", and `code`. Qt 6.11 reports a renderer that a signal ended as crashed and passes the raw wait
// status as the code (SIGKILL, as the kernel's OOM killer and oomd send it, arrives as crashed with 9); a
// crash Chromium's own handler catches exits with a code. -> { how: "killed" | "crashed" | "exited", code }
function stopped(status, code) {
    if (status === "killed")
        return { how: "killed", code: 0 };
    const signal = code & 0x7f, exit = (code >> 8) & 0xff;
    if (status === "crashed") {
        if (signal !== 0 && signal !== 0x7f)
            return { how: signal === 9 || signal === 15 ? "killed" : "crashed", code: 0 };
        return exit !== 0 ? { how: "exited", code: exit } : { how: "crashed", code: 0 };
    }
    return { how: "exited", code: code > 255 ? exit : code };
}

// Two stops of one page in 10 minutes: it no longer reloads by itself.
function twice(stops, now) {
    return stops.filter(t => now - t < 600000).length >= 2;
}

// The page you were looking at lost its process (8h). `c`: { url, at, pid, how, code (stopped()),
// memory ({ bytes, at } sampled from /proc), stop ({ source, at }: the journal's OOM record for the pid),
// siblings (other pages that shared the process), twice }.
function crash(c) {
    const host = PageState.pageHost(c.url) || "The page";
    const title = c.how === "killed" ? "This page's process was stopped" : c.how === "crashed" ? "This page crashed"
                : "The page's process exited with code " + c.code;
    const said = [];
    if (c.memory)
        said.push(host + " was using about " + size(c.memory.bytes) + " (measured " + clock(c.memory.at) + ").");
    if (c.how === "killed" && c.stop)
        said.push("The system stopped it because memory ran low.");
    if (c.siblings === 1)
        said.push("One other page shared its process. It is unloaded and loads again when you open it.");
    else if (c.siblings > 1)
        said.push((numbers[c.siblings] ?? String(c.siblings)) + " other pages shared its process. They are unloaded and load again when you open them.");
    if (c.twice)
        said.push("It stopped twice in 10 minutes.");
    const how = c.how === "exited" ? "exited with code " + c.code : c.how;
    return page({ kind: "crash", url: c.url, host: host, at: c.at, key: c.url + " " + c.at, title: title, body: said.length > 0 ? [said.join(" ")] : [],
                  actions: [{ label: "Reload", action: "reload" }], pid: c.pid, twice: !!c.twice, facts: c,
                  details: [how + " · pid " + c.pid + (c.stop ? " · journal: " + c.stop.source + ", " + clock(c.stop.at) : "")] });
}

// The page's process stopped answering: Wait gives it more time, Reload ends the process and loads the page again.
function unresponsive(c) {
    const host = PageState.pageHost(c.url) || "The page";
    return page({ kind: "unresponsive", url: c.url, host: host, at: c.at, key: c.url + " " + c.at, title: "This page isn't answering",
                  actions: [{ label: "Wait", action: "wait" }, { label: "Reload", action: "reload" }] });
}

// What the last start left behind (`last`: the run record, { clean, alive, page, suspect }, or null on a
// first start): whether the browser did not close cleanly, when it was last seen running, the page that was
// on screen, and the page to leave out because the browser stopped again within a minute of opening it.
function afterStart(last, now) {
    const crashed = !!last && last.clean === false;
    return { crashed: crashed, at: crashed ? (last.alive ?? now) : 0, page: crashed ? (last.page ?? "") : "",
             leaveOut: crashed ? (last.suspect ?? "") : "" };
}

// After a browser crash (8i). `r`: { at, pageId, title (of the page that was on screen, or ""), leftOut (the
// title of a page left out) }.
function restore(r) {
    const note = r.title ? "That page was on screen when the browser stopped. If it stops the browser again, it stays closed next time."
               : r.leftOut ? r.leftOut + " was open when the browser stopped twice, so it was left out. It is listed in History." : "";
    return page({ kind: "restore", key: "restore " + r.at, pageId: r.pageId ?? "", title: "The browser did not close cleanly at " + clock(r.at),
                  body: ["Your tasks are back. No page loads until you open it."],
                  actions: r.title ? [{ label: "Open " + r.title, action: "open" }] : [], note: note });
}
