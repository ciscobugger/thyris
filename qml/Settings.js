.pragma library
.import "Logins.js" as Logins
.import "Recall.js" as Recall
.import "Site.js" as Site

// Settings (PLAN.md 3.15, browser://settings): its sections in PLAN's order, the rows each lists for what exists
// today, what a value says at rest and offers when clicked, and the key list (Ctrl+/, PLAN.md 5). Prefs keeps the
// values, SettingsPage draws the rows in Tacit Settings' style.

// The search engines Search offers; `url` takes the words for %s.
var engines = [
    { key: "duckduckgo", name: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s" },
    { key: "google", name: "Google", url: "https://www.google.com/search?q=%s" },
    { key: "bing", name: "Bing", url: "https://www.bing.com/search?q=%s" },
    { key: "brave", name: "Brave Search", url: "https://search.brave.com/search?q=%s" },
    { key: "startpage", name: "Startpage", url: "https://www.startpage.com/do/search?q=%s" },
];
function engine(key) {
    return engines.find(e => e.key === key) ?? engines[0];
}
function searchUrl(key, words) {
    return engine(key).url.replace("%s", encodeURIComponent(words));
}

// What the browser does with nothing set: what it did before it had a Settings page.
var defaults = {
    engine: "duckduckgo", folder: "", zoom: 1, fonts: {}, minimumFont: 0, languages: [], spellCheck: false,
    thirdPartyCookies: "allow", httpsFirst: "on", listFailure: null, listUpdated: 0, zenImport: null, zenFailure: null, zenCookies: true, zenTabs: true, tabs: "side",
};

// The sections in the order of PLAN.md 3.15's frame: Search, Start and windows, Downloads, Ad blocking, "then Pages,
// Passwords, Privacy, Extensions, Keys, Import, About" (its list puts Pages before Ad blocking). The Agent section is
// phase 5's.
var order = ["search", "start", "downloads", "adblock", "pages", "passwords", "privacy", "sites", "extensions", "keys", "import", "about"];
var titles = {
    search: "Search", start: "Start and windows", downloads: "Downloads", pages: "Pages", adblock: "Ad blocking",
    passwords: "Passwords", privacy: "Privacy", sites: "Sites", extensions: "Extensions", keys: "Keys", import: "Import", about: "About",
};

// The six sections (opsis-settings-public-plan.md, 2026-10-02 sections in plain words; the rail's settings face lists
// them): each shows its member sections' rows, a member's name over its run where there are several. The members stay the keys
// rows, Ctrl+/ and the checks name.
var folds = [
    { key: "general", title: "General", glyph: "tune", members: ["search", "start", "downloads"],
      note: "Search, what opens at the start, downloads" },
    { key: "privacy", title: "Privacy and security", glyph: "shield", members: ["adblock", "passwords", "privacy"],
      note: "Ads and trackers, saved passwords, cookies and what the browser keeps" },
    { key: "sites", title: "Sites", glyph: "language", members: ["sites"],
      note: "What each site may use and how it shows, as you set it in its panel (Ctrl+I)" },
    { key: "appearance", title: "Appearance and reading", glyph: "text_fields", members: ["pages"],
      note: "Zoom, fonts, languages and spelling" },
    { key: "extensions", title: "Extensions and import", glyph: "extension", members: ["extensions", "import", "keys"],
      note: "Add-ons, what comes over from another browser, and the keys" },
    { key: "about", title: "About Thyris", glyph: "info", members: ["about"], note: "The version of Thyris you have" },
];
// a site's choices in one line, as its row in Sites says them: "Camera allowed, location blocked, 110 %"
function siteSummary(entry) {
    const out = [];
    for (const type of Object.keys((entry && entry.choices) || {}).sort()) {
        const v = entry.choices[type];
        if (type === "zoom")
            out.push(Site.zoomText(Number(v)));
        else if (type === "ads")
            out.push(v === "allow" ? "Ads allowed" : "Ads blocked");
        else if (type.indexOf("app:") === 0)
            out.push((v === "block" ? "Never opens " : "Opens ") + type.slice(4) + " links");
        else
            out.push(Site.label(type) + " " + Site.value(type, v).toLowerCase());
    }
    return out.map((t, i) => i === 0 ? t : t.charAt(0).toLowerCase() + t.slice(1)).join(", ");
}
function foldOf(section) {
    return folds.find(f => f.key === section || f.members.indexOf(section) >= 0) ?? folds[0];
}
// a count at a section's row in the rail's settings face, where it holds some
function foldCount(fold, s) {
    if (fold.key === "sites")
        return s.siteChoices.length > 0 ? String(s.siteChoices.length) : "";
    if (fold.key === "extensions")
        return s.extensions.length > 0 ? String(s.extensions.length) : "";
    return "";
}
// The sentence the sheet opens with (SettingsPage): what the section is set to now, its cause in the accent, as parts
// [text, accent]. `behind`: a page lies under the sheet.
function lead(fold, s, behind) {
    switch (fold.key) {
    case "general":
        return [["Thyris searches with ", false], [engine(s.engine).name, true], [" and reopens your tasks when it starts.", false]];
    case "privacy": {
        const lists = s.updating ? [["Ads and trackers are blocked; the lists are ", false], ["updating", true], [".", false]]
            : s.listFailure ? [["Ads and trackers are blocked, but the last list update ", false], ["failed", true], [".", false]]
            : upToDate(s) ? [["Ads and trackers are blocked, lists ", false], ["up to date", true], [".", false]]
            : s.lists.length > 0 ? [["Ads and trackers are blocked, lists updated ", false], [when(Math.max(...s.lists.map(l => l.modified || 0)), s.now), true], [".", false]]
            : [["No ad lists yet: ", false], ["Update now", true], [" fetches them.", false]];
        const n = s.passwords.state === "ready" ? s.passwords.entries.length : -1;
        return n < 0 ? lists : lists.concat([[n === 0 ? " No passwords are saved yet." : " " + (n === 1 ? "1 password is" : n + " passwords are") + " saved in your keyring.", false]]);
    }
    case "sites": {
        const n = s.siteChoices.length;
        return n === 0 ? [] : n === 1 ? [["1 site", true], [" has a choice of its own. Forget puts it back to asking.", false]]
            : [[n + " sites", true], [" have choices of their own. Forget puts one back to asking.", false]];
    }
    case "appearance":
        return [["Pages open at ", false], [Site.zoomText(s.zoom), true],
                [(s.fonts.standard ? " in " + s.fonts.standard : "") + "." + (behind ? " The page behind shows each change." : ""), false]];
    case "extensions": {
        const n = s.extensions.length;
        return (n === 0 ? [["No extensions installed. ", false]] : [[n === 1 ? "1 extension" : n + " extensions", true], [" installed. ", false]])
            .concat([["Import brings another browser's bookmarks, passwords and sign-ins.", false]]);
    }
    }
    return [];
}
// An update that succeeded in the last hour shows as done, with no Update now: after one, the row offered Update now as
// before, and read as not updated (owner, 2026-10-11)
function upToDate(s) {
    return !s.updating && !s.listFailure && s.listUpdated > 0 && s.now - s.listUpdated < 3600000;
}

// Passwords with no Secret Service to keep them (Passwords.state "none")
var noKeyring = "Passwords can't be saved: no password store is running (such as GNOME Keyring or KWallet).";

// What a page that names no font of its own gets where Settings > Fonts sets none ("Default"): Tacit's faces
// (2026-10-02: pages fell back to Noto); the serif stays the engine's own, as Tacit has none.
var tacitFonts = { standard: "Tacit Sans", sansSerif: "Tacit Sans", fixed: "Tacit Mono" };
function pageFonts(set) {
    const out = Object.assign({}, set);
    for (const k in tacitFonts)
        if (!out[k])
            out[k] = tacitFonts[k];
    return out;
}

// Font sizes in px, as Chromium takes them; 0 for the minimum is none.
var fontSizes = [9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 26, 28, 32];
var minimumSizes = [0, 6, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24];
function stepIn(list, v, delta) {
    const found = list.findIndex(x => x >= v), i = found < 0 ? list.length : found;
    const at = i < list.length && list[i] === v ? i + delta : delta > 0 ? i : i - 1;
    return list[Math.max(0, Math.min(list.length - 1, at))];
}
function px(v) {
    return v > 0 ? v + " px" : "Off";
}

// A row's choices when its value is clicked, [{ value, label }], and its value at rest (`v` as Prefs keeps it).
function choices(key) {
    switch (key) {
    case "engine": return engines.map(e => ({ value: e.key, label: e.name }));
    case "spellCheck": return [{ value: false, label: "Off" }, { value: true, label: "On" }];
    case "thirdPartyCookies": return [{ value: "allow", label: "Allow" }, { value: "block", label: "Block" }];
    case "httpsFirst": return [{ value: "on", label: "On" }, { value: "off", label: "Off" }];
    case "tabs": return [{ value: "side", label: "Along the side" }, { value: "top", label: "Along the top" }];
    case "zenCookies": case "zenTabs": return [{ value: false, label: "Off" }, { value: true, label: "On" }];
    }
    // an extension's row
    if (key.indexOf("ext:") === 0)
        return [{ value: "on", label: "On" }, { value: "off", label: "Off" }, { value: "remove", label: "Remove" }];
    return [];
}
function value(key, v) {
    switch (key) {
    case "engine": return engine(v).name;
    case "spellCheck": case "zenCookies": case "zenTabs": return v ? "On" : "Off";
    case "thirdPartyCookies": return v === "block" ? "Blocked" : "Allowed";
    case "httpsFirst": return v === "off" ? "Off" : "On";
    case "tabs": return v === "top" ? "Along the top" : "Along the side";
    }
    if (key.indexOf("ext:") === 0)
        return v === "on" ? "On" : v === "off" ? "Off" : v;
    return String(v);
}

// "~/Downloads" for a path under the home folder
function tilde(path, home) {
    return home && (path === home || path.indexOf(home + "/") === 0) ? "~" + path.slice(home.length) : path;
}
// "today 06:10", "Mon 06:10", "28 Sep 06:10"
function when(ms, now) {
    const day = Recall.day(ms, now);
    return (day === "Today" ? "today" : day.length > 3 && day.indexOf(" ") < 0 ? day.slice(0, 3) : day) + " " + Recall.clock(ms);
}
// A filter list as Settings names it: by its file for the lists tools/update-lists fetches, else by its own title.
var listNames = {
    "ubo-filters": "uBlock filters", "ubo-privacy": "uBlock Privacy", "ubo-badware": "uBlock Badware risks",
    "ubo-quick-fixes": "uBlock Quick fixes", "ubo-unbreak": "uBlock Unbreak", "easylist": "EasyList", "easyprivacy": "EasyPrivacy",
    "pgl": "Peter Lowe's list",
};
function listName(l) {
    return listNames[l.file] ?? (l.title || l.file);
}
// The update's failure in words: curl's code and message, or what the script said.
function failure(text) {
    const curl = /curl: \((\d+)\) (.*)$/.exec(text || "");
    if (!curl)
        return text || "";
    const code = Number(curl[1]), host = (/(?:host:|connect to) ([^\s]+)/i.exec(curl[2]) ?? /\/\/([^\/\s]+)/.exec(curl[2]) ?? [])[1];
    const status = (/error: (\d{3})/.exec(curl[2]) ?? [])[1];
    if (code === 6)
        return "Could not find " + (host || "a list's server") + ": no network, or no such name";
    if (code === 7)
        return "Could not connect to " + (host || "a list's server");
    if (code === 22)
        return "A list's server answered " + (status || "with an error");
    if (code === 28)
        return "A list's server did not answer in time";
    return curl[2];
}
// a row of one of a few `choices(key)`, set to `v`
function choice(key, label, v) {
    return { kind: "choice", key: key, label: label, value: value(key, v), picked: v,
             words: label + " " + choices(key).map(c => c.label).join(" ") };
}
// Import (PLAN.md 3.15, 3.4): Zen's bookmarks into Saved, its history into History and its passwords into the keyring,
// from the profile the Zen install uses (src/zen.*). As Ad blocking's update: when it last ran with Import, "Importing…"
// meanwhile, and the last failure in words. `z`: { profile ({ name, path } or null), state (Zen's: "", "reading",
// "cookies", "password", "saving"), wrong (the primary password given did not open them), logins (Zen's), run (this import's counts
// so far), last (the last one done: { at, bookmarks, history, passwords, cookies, tabs }), failure ({ at, text } or null),
// sites and tabs (what Zen has: the sites it holds cookies for, the tabs it has open; -1 before they are counted),
// cookies and openTabs (whether Import brings them, the two choices).
var zenFailures = { copy: "Could not read Zen's bookmarks and history", places: "Zen's bookmarks and history would not open" };
var zenSkipped = {
    "not given": "Skipped: no primary password given", none: "Skipped: no password store is running",
    locked: "Skipped: the password store stayed locked", failed: "Skipped: Zen's saved passwords would not open",
    unencrypted: "Skipped: your keyring has no password, so they would be kept as plain text",
};
// "12 into Saved", "12 into Saved, 3 already there", "none new, 15 already there"
function counted(c, into) {
    if (c.added > 0)
        return c.added + " " + into + (c.kept > 0 ? ", " + c.kept + " already there" : "");
    return c.kept > 0 ? "none new, " + c.kept + " already there" : "none";
}
// Zen's passwords (Zen.saved): the counts, then what was left out and why. Logins NSS did not open (`unopened`) and those
// a keyring failure left out (`left`) are counted after what went in ("4 into the keyring · 2 skipped: Zen's key4.db did
// not open them"); with nothing in, the reason alone ("Skipped: the keyring stayed locked").
function zenPasswords(p) {
    const reasons = [];
    if (p.unopened > 0)
        reasons.push(["failed", p.unopened]);
    if (p.skipped)
        reasons.push([p.skipped, p.left || 0]);
    const into = p.added > 0 || p.kept > 0;
    if (!into && reasons.length === 1)
        return zenSkipped[reasons[0][0]] ?? "Skipped";
    const parts = into || reasons.length === 0 ? [counted(p, "saved")] : [];
    for (const [key, n] of reasons) {
        const words = zenSkipped[key] ?? "Skipped";
        parts.push(n > 0 ? words.replace(/^Skipped:/, n + " skipped:") : words);
    }
    return parts.join(" · ");
}
function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many);
}
// What Import did with the cookies and the tabs, the last words on the page ({ added, kept, rejected, skipped } or { failure })
function zenCookies(c) {
    if (c.failure)
        return c.failure === "profile" ? "Skipped: no profile to put them in" : "Skipped: Zen's sign-ins would not open";
    const parts = [counted(c, "brought over")];
    if (c.skipped > 0)
        parts.push(c.skipped + " left out: Zen keeps them apart, per site or per container");
    if (c.rejected > 0)
        parts.push(c.rejected + " refused");
    return parts.join(" \u00b7 ");
}
function zenTabs(t) {
    if (t.failed)
        return "Skipped: Zen's open tabs could not be read";
    return t.added > 0 ? t.added + " opened" + (t.kept > 0 ? ", " + t.kept + " already open" : "") : t.kept > 0 ? "none new, " + t.kept + " already open" : "none";
}
// another browser on this computer (ChromeImport's and Zen's, through Welcome), whether or not Zen is here
var browserRow = { kind: "action", key: "browserImport", label: "From another browser", value: "Chrome, Firefox, Brave and others on this computer",
                   action: "Choose…", words: "Import another browser Chrome Chromium Brave Edge Vivaldi Opera Firefox LibreWolf Floorp bookmarks history passwords sign-ins" };
// a password manager's export (PasswordFile through Welcome), whether or not Zen is here
var passwordFileRow = { kind: "action", key: "passwordFile", label: "Passwords from a file", value: "Bitwarden, 1Password, Apple, Google and others",
                        action: "Choose…", words: "Import passwords from a file CSV export Bitwarden 1Password Apple Passwords Google Proton Pass KeePassXC LastPass Dashlane Firefox" };
// the Firefox family's rows name the browser chosen (Zen.browser: Firefox, LibreWolf...): Zen's words with its name
function importRows(z, now) {
    const name = z.browser || "Zen";
    const rows = zenRows(z, now);
    if (name === "Zen")
        return rows;
    const named = v => typeof v === "string" ? v.replace(/\bZen\b/g, name) : v;
    return rows.map(r => r === passwordFileRow || r === browserRow ? r : Object.assign({}, r, { label: named(r.label), value: named(r.value), words: named(r.words) }));
}
function zenRows(z, now) {
    if (!z.profile)
        return [{ kind: "note", key: "zen-none", label: "Zen isn't installed, so there's nothing of Zen's to import." }, browserRow, passwordFileRow];
    const out = [
        { kind: "pair", key: "zen-profile", label: "Zen profile", value: z.profile.name },
    ];
    if (z.sites > 0)
        out.push(choice("zenCookies", "Stay signed in to " + plural(z.sites, "site", "sites"), z.cookies));
    if (z.tabs > 0)
        out.push(choice("zenTabs", "Open your " + plural(z.tabs, "tab", "tabs"), z.openTabs));
    out.push(
        { kind: "action", key: "zen", label: "Imported", action: z.state === "" ? "Import" : "",
          value: z.state !== "" ? "Importing…" : z.last ? when(z.last.at, now) : "never", words: "Imported Import from Zen bookmarks history passwords cookies signed in tabs" });
    const shown = z.state !== "" ? z.run : z.last;
    if (shown && shown.bookmarks)
        out.push({ kind: "pair", key: "zen-bookmarks", label: "Bookmarks", value: counted(shown.bookmarks, "into Saved") },
                 { kind: "pair", key: "zen-history", label: "History", value: counted(shown.history, "into History") });
    if (z.state === "password") {
        out.push({ kind: "pair", key: "zen-passwords", label: "Passwords", value: z.logins + " locked by Zen's primary password" },
                 { kind: "secret", key: "zen-primary", label: "Primary password", words: "Primary password Zen passwords" });
        if (z.wrong)
            out.push({ kind: "note", key: "zen-wrong", label: "That is not Zen's primary password." });
    } else if (shown && shown.passwords) {
        const p = shown.passwords;
        out.push({ kind: "pair", key: "zen-passwords", label: "Passwords", value: zenPasswords(p) });
    }
    if (shown && shown.cookies)
        out.push({ kind: "pair", key: "zen-cookies", label: "Signed in", value: zenCookies(shown.cookies) });
    if (shown && shown.tabs)
        out.push({ kind: "pair", key: "zen-tabs", label: "Tabs", value: zenTabs(shown.tabs) });
    if (z.failure && z.state === "")
        out.push({ kind: "pair", key: "zen-failure", label: "Last import failed", value: when(z.failure.at, now) + " · " + (zenFailures[z.failure.text] ?? z.failure.text) });
    if (shown && shown.cookies && shown.cookies.added > 0 && z.state === "")
        out.push({ kind: "note", key: "zen-signin",
                   label: "A few sites may ask you to sign in again: Zen keeps some cookies apart per site or per container, which cannot be brought over, and some sites tie a session to the browser it started in." });
    out.push(browserRow, passwordFileRow);
    return out;
}

// "en-GB, sv" typed: the language codes, as Chromium names them ("en-GB"), empty ones dropped
function languages(text) {
    return String(text || "").split(/[,\s]+/).map(l => l.trim().replace(/_/g, "-")).filter(l => /^[a-z]{2,3}(-[a-z0-9]{2,8})*$/i.test(l));
}
// Accept-Language for the languages, the first one first: "sv-SE,sv;q=0.9,en;q=0.8"
function acceptLanguage(list) {
    return list.map((l, i) => i === 0 ? l : l + ";q=" + Math.max(0.1, 1 - i / 10).toFixed(1)).join(",");
}
// the codes of an Accept-Language value, weights dropped
function fromAcceptLanguage(header) {
    return String(header || "").split(",").map(p => p.split(";")[0].trim()).filter(l => l !== "");
}
// The families the font field offers for what is typed: those holding every typed word, at most 5.
function families(all, typed) {
    const words = Recall.words(typed);
    return all.filter(f => Recall.passes(f, words)).slice(0, 5);
}
var fontRows = [
    { key: "standard", label: "Standard font" }, { key: "serif", label: "Serif font" },
    { key: "sansSerif", label: "Sans-serif font" }, { key: "fixed", label: "Fixed-width font" },
];

// The key list (Ctrl+/): PLAN.md 5's rows for the keys whose features exist, in its order and wording, with its
// groups. Rows name what a key does and the keys, as the table does.
var keys = [
    { group: "", rows: [
        ["New-page bar", "Ctrl+T"],
        ["New window / private window", "Ctrl+N / Ctrl+Shift+N"],
        ["Close page / close the task (it goes to History)", "Ctrl+W / Ctrl+Shift+W"],
        ["Reopen the last closed page, task or window (repeatable)", "Ctrl+Shift+T"],
        ["Next / previous page in rail order", "Ctrl+Tab, Ctrl+PgDn / Ctrl+Shift+Tab, Ctrl+PgUp"],
        ["Page row n in rail order / last page row, as in Chrome", "Ctrl+1..8 / Ctrl+9"],
        ["Lift the address card out into the centred card, full URL selected", "Ctrl+L, Alt+D"],
        ["Focus cycle: page, address card (a waiting ask first), rail list, page", "F6"],
        ["Quit (session kept)", "Ctrl+Q"],
        ["Browser full screen", "F11"],
        ["Back / forward", "Alt+Left / Alt+Right"],
        ["Reload / reload without cache", "Ctrl+R, F5 / Ctrl+Shift+R, Shift+F5"],
        ["Stop", "Esc while loading"],
        ["Next / previous task (its last-seen page)", "Alt+PgDn / Alt+PgUp"],
        ["Pinned site n", "Alt+1..9"],
        ["Move page up / down (past a task's edge it joins the neighbour)", "Ctrl+Shift+PgUp / PgDn"],
        ["Jump (@)", "Ctrl+Shift+A"],
        ["Fold / pin the rail (the fold button in the rail's foot always works)", "Ctrl+B"],
        ["Save page / pin the site", "Ctrl+D / Ctrl+Shift+D"],
        ["Mute page", "Ctrl+M"],
        ["Find in page", "Ctrl+F"],
        ["Find in page (unless the site panel sets “/ opens find” Off)", "/"],
        ["Site panel", "Ctrl+I"],
        ["Zoom this site / reset", "Ctrl+Plus / Ctrl+Minus / Ctrl+0"],
        ["Reader view", "Ctrl+Alt+R"],
        ["Print / view source (new page in this task)", "Ctrl+P / Ctrl+U"],
        ["Developer tools, under the page / at the element right-clicked", "F12, Ctrl+Shift+I / right-click › Inspect"],
        ["History / Downloads / Saved", "Ctrl+H / Ctrl+J / Ctrl+Shift+O"],
        ["Pages and memory", "Shift+Esc"],
        ["Settings / key list / clear browsing data", "Ctrl+, / Ctrl+/ / Ctrl+Shift+Delete"],
    ] },
    { group: "In the address card and the Ctrl+T bar", rows: [
        ["Address: go here / new page in this task. Bar: open and show / open in background", "Enter / Alt+Enter"],
        ["Flip destination: predicted task / new task", "Tab (bar)"], ["Open as a new task", "Shift+Enter (bar)"],
        ["Pick / forget a history row / restore or close", "Up, Down / Shift+Delete / Esc"],
        ["Prefixes: / find, > page actions, @ jump", "/  >  @"],
        ["Find: next / previous match. Alt+C match case", "Enter, F3, Down / Shift+Enter, Shift+F3, Up"],
    ] },
    { group: "Rail list (after F6)", rows: [
        ["Move", "Up / Down"], ["Open", "Enter"], ["Open / fold a task", "Right / Left"], ["Close page", "Delete"],
        ["Forget (History)", "Shift+Delete"], ["Rename", "F2"], ["Row menu", "Menu or Shift+F10"], ["Back to the page", "Esc"],
    ] },
    { group: "Asks and dialogs", rows: [
        ["No chord answers an ask: F6 reaches it, Tab moves, Enter picks", "F6, Tab, Enter"], ["Deny for this load", "Esc"],
        ["Page dialogs: OK / Cancel", "Enter / Esc"],
    ] },
    { group: "Mouse", rows: [
        ["A link: join this task in the background", "Middle-click, Ctrl+click"], ["A link: join this task in front", "Ctrl+Shift+click"],
        ["A link: new task", "Shift+click"], ["A row: close", "Middle-click"], ["A row: its menu", "Right-click"],
    ] },
];

// The rows, top to bottom, of the page (`sub` "") or of one of its views in place (‹ returns): "fonts", "allowed" (Sites
// allowed), "clear" (Clear browsing data) and "passwords" (Saved passwords). `s` holds what they show:
//   engine, defaultBrowser ("yes", "no", "" unknown), folder, home, zoom, fonts (the families and sizes in use),
//   minimumFont, languages, spellCheck, dictionaries ({ language: "ready" | "hunspell" | "" }), allowed (origins), lists,
//   updating, listFailure ({ at, text } or null), thirdPartyCookies, httpsFirst, tabs ("side" or "top"),
//   cookies (every site's count), clearing ({ what, left } or null), extensions ([{ id, name, enabled, error }]),
//   passwords ({ state (Passwords': "", "ready", "none"), entries ([{ id, origin, user }]), removing ({ id: seconds
//   left }), revealed ({ id: { secret } or { failure } }) }), zen (Import's, as importRows takes it), versions, now.
// Kinds: head (a section's title), group (a label in the key list), choice, step (− value +), pair, action (value and
// a text action; `detail`, when there is one, is what the page says under the label instead of the value), link (a
// count and ›), field (a value edited in place), pick (a folder chosen in Files), note, back, login (a saved password: host, user name, Show · Edit · Delete), secret (Zen's primary
// password typed in the row, Import · Skip). `key` names what a row sets or does; `words` is what the filter looks in,
// never a password.
function rows(s, sub, filter) {
    const words = Recall.words(filter);
    const out = [];
    function section(name, list) {
        if (list.length === 0)
            return;
        const head = titles[name] ?? name;
        // a section's title matches for all its rows
        const shown = Recall.passes(head, words) ? list : list.filter(r => Recall.passes(head + " " + (r.words ?? (r.label + " " + (r.value ?? ""))), words));
        if (shown.length === 0)
            return;
        out.push({ kind: "head", key: "head:" + name, section: name, label: head });
        for (const r of shown)
            out.push(Object.assign({ section: name }, r));
    }
    if (sub === "fonts") {
        out.push({ kind: "back", key: "back", label: "Fonts" });
        for (const f of fontRows)
            out.push({ kind: "field", key: "font:" + f.key, label: f.label, value: s.fonts[f.key] || "" });
        out.push({ kind: "step", key: "fontSize", label: "Font size", value: px(s.fonts.size) });
        return out.filter(r => r.kind === "back" || Recall.passes(r.label + " " + r.value, words));
    }
    if (sub === "allowed") {
        out.push({ kind: "back", key: "back", label: "Sites allowed" });
        for (const origin of s.allowed.filter(o => Recall.passes(o, words)))
            out.push({ kind: "action", key: "allowed:" + origin, label: origin.replace(/^https?:\/\//, ""), value: "", action: "Remove" });
        if (s.allowed.length === 0)
            out.push({ kind: "note", key: "none", label: "None yet. A site shows ads when you allow them in its panel (Ctrl+I)." });
        return out;
    }
    // Saved passwords (PLAN.md 3.15): host, user name, Show (the keyring may ask to unlock), Edit, Delete; the filter
    // looks in the hosts and user names. A deleted one waits 6 s for Undo.
    if (sub === "passwords") {
        const pw = s.passwords;
        out.push({ kind: "back", key: "back", label: "Saved passwords" });
        if (pw.state === "none")
            return out.concat([{ kind: "note", key: "passwords-none", label: noKeyring }]);
        for (const e of pw.entries) {
            const host = Logins.host(e.origin), left = pw.removing[e.id];
            if (!Recall.passes(host + " " + e.user, words))
                continue;
            if (left !== undefined)
                out.push({ kind: "action", key: "undelete:" + e.id, label: host, value: "Deleted in " + Math.max(1, left) + " s", action: "Undo" });
            else
                out.push({ kind: "login", key: "login:" + e.id, id: e.id, label: host, value: e.user, words: host + " " + e.user,
                           shown: pw.revealed[e.id] ?? null });
        }
        if (pw.entries.length === 0)
            out.push({ kind: "note", key: "none", label: "None yet. When you sign in to a site, Thyris asks to save the password." });
        return out;
    }
    if (sub === "clear") {
        out.push({ kind: "back", key: "back", label: "Clear browsing data" });
        const names = { history: "History and closed pages", cookies: "Cookies", cache: "Cached files" };
        if (s.clearing) {
            out.push({ kind: "action", key: "undo", label: names[s.clearing.what], value: "Cleared in " + Math.max(1, s.clearing.left) + " s", action: "Undo" });
            return out;
        }
        out.push({ kind: "action", key: "clear:history", label: names.history, value: "", action: "Clear" },
                 { kind: "action", key: "clear:cookies", label: names.cookies, value: String(s.cookies), detail: s.cookies === 1 ? "1 cookie" : s.cookies + " cookies", action: "Clear" },
                 { kind: "action", key: "clear:cache", label: names.cache, value: "", action: "Clear" },
                 { kind: "note", key: "clear-note", label: "Each can be undone for " + Site.undoSeconds + " seconds. One site's data is cleared in its panel (Ctrl+I)." });
        return out;
    }

    section("search", [choice("engine", "Search engine", s.engine)]);
    section("start", [
        { kind: "pair", key: "restore", label: "When Thyris starts", value: "Reopens your tasks" },
        { kind: "action", key: "defaultBrowser", label: "Default browser", value: s.defaultBrowser === "yes" ? "Yes" : s.defaultBrowser === "no" ? "No" : "",
          detail: s.defaultBrowser === "yes" ? "Links from other apps open here" : s.defaultBrowser === "no" ? "Links from other apps open in another browser" : "",
          action: s.defaultBrowser === "yes" ? "Set again" : "Make default" },
    ]);
    section("downloads", [{ kind: "pick", key: "folder", label: "Folder", value: tilde(s.folder, s.home) }]);
    // uBlock Origin's parts are one list here, as in uBO
    const lists = s.lists.map(l => l.file.indexOf("ubo-") === 0 ? "uBlock filters" : listName(l)).filter((n, i, all) => all.indexOf(n) === i);
    section("adblock", [
        { kind: "pair", key: "lists", label: "Lists", value: lists.length > 0 ? lists.join(", ") : "None" },
        { kind: "action", key: "update", label: upToDate(s) ? "Up to date" : "Updated", action: s.updating || upToDate(s) ? "" : "Update now",
          value: s.updating ? "Updating…" : s.lists.length > 0 ? when(Math.max(...s.lists.map(l => l.modified || 0)), s.now) : "never" },
    ].concat(s.listFailure ? [{ kind: "pair", key: "failure", label: "Last update failed", value: when(s.listFailure.at, s.now) + " · " + failure(s.listFailure.text) }] : []).concat([
        { kind: "link", key: "allowed", label: "Sites allowed", value: String(s.allowed.length), words: "Sites allowed ads " + s.allowed.join(" ") },
    ]));
    const missing = s.spellCheck ? s.languages.filter(l => s.dictionaries[l] !== "ready" && s.dictionaries[l] !== "hunspell") : [];
    section("pages", [
        choice("tabs", "Tabs", s.tabs),
        { kind: "step", key: "zoom", label: "Default zoom", value: Site.zoomText(s.zoom) },
        { kind: "link", key: "fonts", label: "Fonts", value: (s.fonts.standard ? s.fonts.standard + ", " : "") + px(s.fonts.size),
          words: "Fonts " + fontRows.map(f => f.label + " " + (s.fonts[f.key] || "")).join(" ") + " Font size" },
        { kind: "step", key: "minimumFont", label: "Smallest text size", value: px(s.minimumFont) },
    ].concat(s.minimumFont > 0 ? [{ kind: "note", key: "minimum-note", label: "A page takes the minimum when it loads again." }] : []).concat([
        { kind: "field", key: "languages", label: "Languages", value: s.languages.join(", ") },
        choice("spellCheck", "Spell check", s.spellCheck),
    ]).concat(missing.length === 0 ? [] : [{ kind: "note", key: "dictionaries",
        label: "Spell check skips " + missing.join(", ") + ": no spelling dictionary for " + (missing.length === 1 ? "it" : "them") + " is installed." }]));
    // Passwords (PLAN.md 3.15): the saved ones in a view in place, as Sites allowed; the filter finds them by host and user
    // name from here too
    const pw = s.passwords;
    section("passwords", (pw.state === "none" ? [{ kind: "note", key: "passwords-none", label: noKeyring }]
                          : [{ kind: "link", key: "passwords", label: "Saved passwords", value: pw.state === "ready" ? String(pw.entries.length) : "",
                               words: "Saved passwords " + pw.entries.map(e => Logins.host(e.origin) + " " + e.user).join(" ") }])
        .concat([{ kind: "note", key: "autofill", label: "Thyris doesn't fill in addresses or card numbers, and never stores card numbers." }]));
    section("privacy", [
        { kind: "link", key: "clear", label: "Clear browsing data", value: "", words: "Clear browsing data history closed pages cookies cached files cache" },
        choice("thirdPartyCookies", "Cookies from other sites", s.thirdPartyCookies),
        choice("httpsFirst", "Always use secure connections", s.httpsFirst),
    ]);
    // Sites (new, 2026-10-15): every site with a choice of its own; Forget puts all of them back to asking
    section("sites", s.siteChoices.length === 0
        ? [{ kind: "note", key: "sites-none", label: "No site has a choice of its own yet. What you set in a site's panel (Ctrl+I) shows here." }]
        : s.siteChoices.map(c => ({ kind: "action", key: "forget:" + c.origin, label: c.host, detail: c.summary, action: "Forget",
                                    words: c.host + " " + c.summary })));
    // The engine has no extension manager: Thyris keeps the added ones itself (src/extensions.cpp) and the engine runs
    // them from its next start. The Web Store's Add button needs the manager and does nothing here.
    section("extensions", s.extensionsInstall === false
        ? [{ kind: "note", key: "none", label: "Thyris can't add extensions yet. Ads are blocked by uBlock Origin Lite, which comes with it." }]
        : s.extensions.map(e => Object.assign(choice("ext:" + e.id, e.name, e.error ? "Failed: " + e.error : e.enabled ? "on" : "off"), { words: e.name })).concat([
        { kind: "action", key: "install", label: "Add from a folder or .zip", value: "", action: "Choose" },
    ]).concat(s.extensionProblem ? [{ kind: "note", key: "problem", label: s.extensionProblem }] : [])
      .concat(s.extensionsRestart ? [{ kind: "note", key: "restart", label: "Changes to extensions start the next time Thyris opens." }] : [])
      .concat([
        { kind: "note", key: "store", label: "The Chrome Web Store's Add button doesn't work in Thyris. Download the extension, unpack it or keep the .zip, and add it here." },
        { kind: "note", key: "access", label: "Each extension can read the sites it asks for." },
    ]));
    section("import", s.zen ? importRows(s.zen, s.now) : []);
    const keyRows = [];
    for (const g of keys) {
        if (g.group)
            keyRows.push({ kind: "group", key: "keys:" + g.group, label: g.group, words: g.group + " " + g.rows.map(r => r.join(" ")).join(" ") });
        for (const r of g.rows)
            keyRows.push({ kind: "pair", key: "key:" + r[0], label: r[0], value: r[1], words: g.group + " " + r[0] + " " + r[1] });
    }
    section("keys", keyRows);
    // About, as Tacit Settings' opens: the name, its version, what it is built on (owner 2026-10-11: "simple and premium",
    // no list of credits; the filter lists' dates are Ad blocking's)
    const chromium = s.versions.chromium ?? "";
    section("about", [{ kind: "identity", key: "identity", label: "Thyris", value: "Version " + (s.versions.opsis ?? ""),
                        detail: chromium ? "Built on Chromium " + chromium.split(".")[0] : "",
                        words: "Thyris version " + (s.versions.opsis ?? "") + " Chromium " + chromium }]);
    return out;
}
