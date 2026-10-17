.pragma library
.import "PageState.js" as PageState

// Downloads (PLAN.md 3.8 8d): a download's words, its rail row and where it shows. Session keeps the
// records, Downloader.qml runs them: { id, page, url, file, path, total, received, left, state, reason,
// warn, started, finished, opened, from }
//   state   "running", "paused", "done", "failed", or "blocked" (an http file from an https page, not
//           fetched until Keep)
//   total   bytes, -1 while unknown; `left`: seconds to go, -1 while unknown
//   reason  a failure in a word or two (reason()), for "Failed: <reason>"
//   warn    "program" on a finished file that runs as a program, until Keep
//   from    { title, icon, always, url, thread } of the page that started it: the Downloads group's
//           "from" line, and the origin written on the file

// "188 kB", "2.1 MB", "1.2 GB": the shell's sizes (tacit-shell services/Voice.qml)
function size(bytes) {
    const b = Math.max(0, Math.round(Number(bytes) || 0));
    if (b < 1000)
        return b + " B";
    if (b < 1e6)
        return Math.round(b / 1000) + " kB";
    if (b < 1e9)
        return (b / 1e6).toFixed(b < 1e7 ? 1 : 0) + " MB";
    return (b / 1e9).toFixed(1) + " GB";
}

// "2.1 of 8.4 MB": what has come of the total, in the total's unit; "2.1 MB" while the total is unknown
function sizeOf(received, total) {
    if (!(total > 0))
        return size(received);
    const t = size(total), unit = t.split(" ")[1];
    const scale = { "B": 1, "kB": 1e3, "MB": 1e6, "GB": 1e9 }[unit];
    const digits = unit === "GB" || (unit === "MB" && total < 1e7) ? 1 : 0;
    return (Math.min(received, total) / scale).toFixed(digits) + " of " + t;
}

// "12 s", "4 min", "1 h 20 min"
function duration(seconds) {
    const s = Math.max(1, Math.round(seconds));
    if (s < 60)
        return s + " s";
    const m = Math.round(s / 60);
    if (m < 60)
        return m + " min";
    return Math.floor(m / 60) + " h" + (m % 60 ? " " + m % 60 + " min" : "");
}

// When a download finished: a time today, a weekday within the week, else a date.
function finishedAt(ms, now) {
    const d = new Date(ms), n = new Date(now);
    const pad = v => (v < 10 ? "0" : "") + v;
    if (d.toDateString() === n.toDateString())
        return pad(d.getHours()) + ":" + pad(d.getMinutes());
    if (now - ms < 6 * 86400000)
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
    return d.getDate() + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
}

// Whole percent done, or -1 while the total is unknown.
function percent(d) {
    return d.total > 0 ? Math.floor(100 * Math.min(d.received, d.total) / d.total) : -1;
}

// Qt WebEngine has no Safe Browsing verdict: only files that run as programs are marked, by name.
function runsAsProgram(file) {
    return /\.(appimage|run|sh|desktop)$/i.test(file || "");
}

// Chromium blocks a file fetched over plain http from an https page; Qt WebEngine lets it through, so the
// browser holds it. This machine's addresses are not insecure (PageState.insecure).
function insecure(fileUrl, pageUrl) {
    return /^https:\/\//i.test(pageUrl || "") && PageState.insecure(fileUrl || "");
}

// A download's interrupt reason (WebEngineDownloadRequest.DownloadInterruptReason, which keeps Chromium's
// numbers) in a word or two, for "Failed: <reason>".
function reason(code) {
    if (code >= 20 && code <= 24)
        return "network";
    switch (code) {
    case 2: return "no permission";
    case 3: return "disk full";
    case 5: return "name too long";
    case 6: return "file too large";
    case 7:
    case 11: return "blocked";
    case 1:
    case 10:
    case 12:
    case 13:
    case 14: return "file error";
    case 30:
    case 37:
    case 38:
    case 39: return "server";
    case 33: return "no file";
    case 34: return "sign-in needed";
    case 35: return "certificate";
    case 36: return "forbidden";
    }
    return "download error";
}

// The file's kind as a Tacit symbol, by its extension: the row's face (2026-10-09, book4-edge/opsis-downloads-research.md)
function kind(file) {
    const name = String(file || "").toLowerCase(), ext = name.includes(".") ? name.slice(name.lastIndexOf(".") + 1) : "";
    if (/\.tar\.[a-z0-9]+$/.test(name) || ["zip", "7z", "rar", "gz", "xz", "zst", "bz2", "tgz", "tar"].includes(ext))
        return "folder_zip";
    if (ext === "pdf")
        return "picture_as_pdf";
    if (["png", "jpg", "jpeg", "gif", "webp", "heic", "avif", "svg", "bmp", "tiff"].includes(ext))
        return "image";
    if (["mp4", "mkv", "webm", "mov", "avi", "m4v"].includes(ext))
        return "movie";
    if (["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"].includes(ext))
        return "music_note";
    if (["deb", "rpm", "pkg", "flatpak"].includes(ext))
        return "deployed_code";
    if (runsAsProgram(name) || ["exe", "msi", "bin"].includes(ext))
        return "terminal";
    if (["js", "ts", "py", "c", "h", "cpp", "rs", "go", "java", "json", "yaml", "yml", "toml", "patch", "diff"].includes(ext))
        return "code";
    if (["mbox", "eml"].includes(ext))
        return "mail";
    if (["txt", "md", "doc", "docx", "odt", "rtf", "pages", "csv", "xlsx", "ods", "pptx", "odp", "epub"].includes(ext))
        return "description";
    return "draft";
}

// A failure in plain words (2026-10-09): what happened, as a sentence, for the row of a file that did not land
function failure(reason) {
    switch (reason) {
    case "network": return "The connection dropped.";
    case "server": return "The site stopped sending it.";
    case "no file": return "There was no file at that address.";
    case "sign-in needed": return "The site wants you signed in first.";
    case "forbidden": return "The site refused it.";
    case "disk full": return "This computer is out of space.";
    case "no permission": return "Thyris can't write to that folder.";
    case "name too long": return "Its name is too long for the folder.";
    case "file too large": return "It is too large for that disk.";
    case "blocked": return "This computer blocked it.";
    case "certificate": return "The site's certificate failed.";
    case "browser closed": return "Thyris closed before it finished.";
    }
    return "It couldn't be finished.";
}

// The controls a coming or finished row shows with the pointer on it, as glyphs: { name, glyph, tip }
function controls(status) {
    switch (status) {
    case "running": return [{ name: "pause", glyph: "pause", tip: "Pause" }, { name: "cancel", glyph: "close", tip: "Cancel" }];
    case "paused": return [{ name: "resume", glyph: "play_arrow", tip: "Resume" }, { name: "cancel", glyph: "close", tip: "Cancel" }];
    case "done": return [{ name: "show", glyph: "folder_open", tip: "Show in Files" }];
    }
    return [];
}
// The ways on from a row that waits on you, as the installer's rings, the safe one first and leading
function ways(status) {
    switch (status) {
    case "failed": return [{ name: "retry", label: "Try again", tone: "default" }, { name: "remove", label: "Remove", tone: "" }];
    case "program": return [{ name: "delete", label: "Delete", tone: "default" }, { name: "keep", label: "Keep", tone: "" }];
    case "blocked": return [{ name: "keep", label: "Download anyway", tone: "risk" }];
    }
    return [];
}

// What the row stands for: its state, or "program" for a finished file that runs as a program until Keep.
function status(d) {
    return d.state === "done" && d.warn === "program" ? "program" : d.state;
}

// The text actions a row offers (8d), for its status.
function actions(status) {
    switch (status) {
    case "running": return [{ name: "pause", label: "Pause" }, { name: "cancel", label: "Cancel" }];
    case "paused": return [{ name: "resume", label: "Resume" }, { name: "cancel", label: "Cancel" }];
    case "done": return [{ name: "open", label: "Open" }, { name: "show", label: "Show in Files" }];
    case "failed": return [{ name: "retry", label: "Retry" }, { name: "remove", label: "Remove" }];
    case "program": return [{ name: "keep", label: "Keep" }, { name: "delete", label: "Delete" }];
    case "blocked": return [{ name: "keep", label: "Keep" }];
    }
    return [];
}
// Running and finished rows show their details and actions only with the pointer on them; a failure or a
// warning always shows them, as it waits on you.
function waits(status) {
    return status === "failed" || status === "program" || status === "blocked";
}

// The parts of a download's row: its glyph ("download", "check", "warning"), `failed` ("error" for the
// error tone), `detail` (right of the name at rest), `info` (the line under it with the pointer on it),
// `note` (a failure or warning), `progress` (0-1, -1 when there is none to draw).
function parts(d, now) {
    const p = percent(d), s = status(d);
    const out = { glyph: kind(d.file), failed: "", detail: "", info: "", note: "", progress: -1 };
    switch (s) {
    case "running":
    case "paused":
        out.detail = s === "paused" ? "Paused" : p >= 0 ? p + " %" : size(d.received);
        out.info = s === "paused" ? "Paused · " + sizeOf(d.received, d.total) : sizeOf(d.received, d.total) + (d.left >= 0 ? " · " + duration(d.left) + " left" : "");
        out.progress = p >= 0 ? p / 100 : -1;
        break;
    case "done":
        out.info = size(d.total > 0 ? d.total : d.received) + " · " + finishedAt(d.finished || now, now);
        break;
    case "failed":
        out.failed = "error";
        out.note = failure(d.reason);
        break;
    case "program":
        out.note = "It runs as a program. Keep it only if you trust " + (PageState.hostOf(String(d.url)) || "where it came from") + ".";
        break;
    case "blocked":
        out.note = "Not downloaded: its connection wasn't private.";
        break;
    }
    return out;
}

// Rows leave 10 min after you open the file (PLAN.md 8d).
var keepOpened = 10 * 60000;
// A finished file stays under its page for a moment after it lands, then lives in the foot's Downloads (the owner's
// "row, then foot", 2026-10-09); a program waiting on Keep stays until answered.
var keepLanded = 8000;

// A finished file past its moment under its page
function landed(d, now) {
    return d.state === "done" && d.warn !== "program" && now - (d.finished || now) >= keepLanded;
}

// Where a download shows: "page" (under the page that started it), "group" (the Downloads group above
// Earlier: its page has no row, as an Always site's or a closed page's) or "" (nowhere). Filing a thread
// takes its files out of the rail, save one still coming; forgetting it keeps them in Earlier > Downloads only
// (`quiet`, PLAN.md 3.7).
function place(d, session, now) {
    if (d.quiet || d.opened && now - d.opened >= keepOpened || landed(d, now))
        return "";
    const p = session.pages[d.page];
    const t = p && p.thread ? session.threadById(p.thread) : null;
    if (t && !t.earlier)
        return "page";
    if (t)
        return d.state === "running" || d.state === "paused" ? "group" : "";
    return "group";
}

// Several running or finished from one page as one row (failures and warnings keep rows of their own):
// "3 downloads · 40 %" of all their bytes while any is coming, "3 downloads" once all are done.
function summary(list) {
    const coming = list.some(d => d.state === "running" || d.state === "paused");
    const sized = list.filter(d => d.total > 0);
    const total = sized.reduce((a, d) => a + d.total, 0);
    const got = sized.reduce((a, d) => a + Math.min(d.received, d.total), 0);
    const left = list.filter(d => d.state === "running" || d.state === "paused").length;
    return {
        title: list.length + " downloads",
        glyph: "files",
        info: coming ? (total > 0 ? Math.floor(100 * got / total) + " % · " : "") + left + " coming" : "All in Downloads",
        progress: coming && total > 0 ? got / total : -1,
    };
}

// A download's rail row. `depth` 2 sits under a page of a thread (and in the Downloads group), 1 under a
// thread of one. `grouped`: it is in the Downloads group, so it names the page it came from (`page`, the
// page as it is now if it is still open, else as the record kept it).
function row(d, depth, grouped, now, page) {
    const v = parts(d, now);
    const src = !grouped ? null : page ? { title: page.title || page.url, icon: page.icon, always: page.thread === "" } : d.from;
    const from = src ? (src.always ? "Pinned" : src.title || "") : "";
    return { key: "d:" + d.id, type: "download", ref: d.id, page: d.page || "", title: d.file, depth: depth, status: status(d),
             glyph: v.glyph, failed: v.failed, detail: v.detail, info: v.info, note: v.note, progress: v.progress,
             from: from, icon: from && src.icon ? src.icon : "" };
}
