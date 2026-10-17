.pragma library

// Memory rules (PLAN.md 3.12, DESIGN.md): no page freezes or unloads for the time it goes unseen. The memory net
// (Main.relieveMemory) unloads one page every 10 s while the machine is low on memory (`low`), the one seen longest
// ago that may go (`pick`). States use WebEngineView.LifecycleState's numbers: 0 live (Active), 1 frozen, 2 unloaded
// (Discarded).

// Low on memory: MemAvailable under 1 GiB or under 10 % of MemTotal, whichever is more. `m`: Facts.systemMemory().
function low(m) {
    return m.available !== undefined && m.available < Math.max(1024 * 1024 * 1024, m.total / 10);
}

// Why a page must stay live, or "" when it may unload. `edited`: a text field was edited since load.
// Mic, camera, location and screen share arrive as `capturing`; notification permission for Always sites as
// `notifies`; a download the page started that is running or paused as `downloading` (Downloader.qml).
function keeps(p, always, edited) {
    if (p.audible && !p.muted) return "audio";
    if (p.capturing) return "capturing";
    if (p.downloading) return "download";
    if (edited) return "edited";
    if (always && p.notifies) return "notifies";
    return "";
}

// A page the net, or Unload in Pages and memory, may unload: `p` as Main.memoryPages gives it (state, shown, where,
// edited, needsYou and what keeps reads). Not one on screen, already unloaded, Always or a popup, nor one whose
// ask waits behind its ● (PLAN.md 3.8): unloading it would drop the ask unanswered.
function unloadable(p) {
    return p.state !== "unloaded" && !p.shown && p.where === "" && !p.needsYou && keeps(p, false, !!p.edited) === "";
}

// The page the net unloads of `pages`: the unloadable one seen longest ago (`seen`, else when it was made), or null.
function pick(pages) {
    const at = p => p.seen ?? p.lastActive ?? 0;
    let out = null;
    for (const p of pages)
        if (unloadable(p) && (out === null || at(p) < at(out)))
            out = p;
    return out;
}

var names = ["live", "frozen", "unloaded"];
