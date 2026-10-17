.pragma library
.import "Failures.js" as Failures
.import "Lifecycle.js" as Lifecycle
.import "Recall.js" as Recall

// Pages and memory (PLAN.md 3.17, 7: browser://pages, Shift+Esc or > Pages and memory): each page's state, process
// and memory. Memory is a process's resident size as /proc says it, the measure a stopped page's wording gives
// (PLAN.md 8h); pages that share a process share its memory, so it is said once, on the process.

// A browser process by what Chromium started it as (Facts.processes: type, service).
var services = {
    "network.mojom.NetworkService": "Network service", "storage.mojom.StorageService": "Storage service",
    "audio.mojom.AudioService": "Audio service", "video_capture.mojom.VideoCaptureService": "Video capture service",
    "data_decoder.mojom.DataDecoderService": "Data decoder",
};
// A page process forked from the zygote keeps the zygote's command line, so a zygote with no process under it is one.
// A process under the browser that is not Chromium's (the list update's sh and curl, the Files relay) goes by its name.
function processName(p, all) {
    if (p.type === "")
        return !p.parent ? "Main process" : p.name || "Process " + p.pid;
    if (p.type === "gpu-process")
        return "GPU process";
    if (p.type === "zygote" && (all ?? []).some(c => c.parent === p.pid))
        return "Zygote";
    if (p.type === "renderer" || p.type === "zygote")
        return "Other page process";
    if (p.type === "utility")
        return services[p.service] ?? (p.service ? p.service.split(".")[0] : "Utility process");
    return p.type;
}

// Why a page stays live though unseen (Lifecycle.keeps), in words.
var capture = { screen_share: "sharing the screen", videocam: "using the camera", mic: "using the microphone", location_on: "using location" };
function kept(p) {
    switch (Lifecycle.keeps(p, p.where === "Pinned", !!p.edited)) {
    case "audio": return "playing audio";
    case "capturing": return capture[p.capturing] ?? "using a device";
    case "download": return "downloading";
    // Unload asked the page (Main.unloadPage), as the memory net does (PLAN.md 3.12)
    case "edited": return "a text field edited";
    case "notifies": return "Always, with notifications";
    }
    return "";
}
// A page's line at the right: its state, then what holds it there.
function detail(p) {
    const state = { live: "Live", frozen: "Frozen", unloaded: "Unloaded" }[p.state] ?? "Live";
    // an ask waiting behind its row's ● keeps it from unloading (PLAN.md 3.8)
    const why = p.shown ? "on screen" : p.state === "unloaded" ? "" : kept(p) || (p.needsYou ? "an ask waits" : "");
    return [state, why, p.where === "popup" ? "sign-in window" : ""].filter(t => t !== "").join(" · ");
}

// The rows, top to bottom. `pages`: [{ id, title, url, icon, state ("live", "frozen", "unloaded"), pid (its process,
// 0 without one), shown (on screen in its window), where ("", "Pinned", "popup"), and what Lifecycle.keeps
// reads (audible, muted, capturing, downloading, edited, notifies) }]; `processes`: Facts.processes(); `at` when they
// were measured. Kinds: head (a section and its memory), process (a browser process), page, note. The browser's own
// processes first, then the page processes, most memory first, then the pages with none.
function rows(pages, processes, at) {
    const out = [{ kind: "note", key: "measured", label: at ? "Measured " + Recall.clock(at) + ", again every 10 s while this page is open." : "" }];
    const byPid = {};
    for (const p of pages)
        if (p.pid > 0 && p.state !== "unloaded")
            (byPid[p.pid] = byPid[p.pid] || []).push(p);
    const own = processes.filter(p => !byPid[p.pid]);
    if (own.length > 0) {
        // no total: resident sizes share pages between processes, so their sum is no measure
        out.push({ kind: "head", key: "head:browser", label: "Browser", value: "" });
        for (const p of own.slice().sort((a, b) => b.bytes - a.bytes))
            out.push({ kind: "process", key: "process:" + p.pid, label: processName(p, processes), value: Failures.size(p.bytes), pid: p.pid });
    }
    const pageRow = p => ({ kind: "page", key: "page:" + p.id, ref: p.id, label: p.title || p.url, icon: p.icon || "", url: p.url, value: detail(p),
                            unload: Lifecycle.unloadable(p) });
    const measured = pid => processes.find(p => p.pid === pid) ?? null;
    const renderers = Object.keys(byPid).map(Number).map(pid => ({ pid: pid, bytes: measured(pid) ? measured(pid).bytes : 0 }))
        .sort((a, b) => b.bytes - a.bytes);
    for (const r of renderers) {
        const list = byPid[r.pid];
        out.push({ kind: "head", key: "head:" + r.pid, label: "Process " + r.pid + (list.length > 1 ? " · " + list.length + " pages" : ""),
                   value: measured(r.pid) ? Failures.size(r.bytes) : "" });
        out.push(...list.map(pageRow));
    }
    const none = pages.filter(p => !(p.pid > 0 && p.state !== "unloaded"));
    if (none.length > 0) {
        out.push({ kind: "head", key: "head:unloaded", label: "No process", value: "" });
        out.push(...none.map(pageRow));
    }
    return out;
}
