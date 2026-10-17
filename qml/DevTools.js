.pragma library

// DevTools' own ✕ and Dock side (2026-10-16, the owner: "chrome has x button, we need also right side version").
// Chromium attaches its DevTools embedder (DevToolsUIBindings, with devtools_compatibility.js's InspectorFrontendHost)
// to every devtools: page, so the front end Thyris loads (can_dock=true in its address, DevToolsBridge) runs as Chrome's
// docked DevTools do: its toolbar ends with ✕ and its ⋮ menu has Dock side. For a page that is not a DevTools window
// that embedder's close and docking do nothing, and docked, the front end keeps an empty slot beside itself for the page
// (Chrome lays the page over it). These scripts make DevTools' own controls Thyris's: ✕ closes them as F12 does, Dock side
// moves Thyris's card (bottom or right: Thyris has no floating windows, and on the left DevTools would sit between the
// rail and the page, so those two are not offered), and DevTools fill their card.

// In DevTools' page, in its own world, at its start: `side` the one Thyris docks them to. What happens goes over
// window.postMessage to `relay`: ["close"], ["pick", side] for a side picked in their menu (or Ctrl+Shift+D), ["is", side]
// for one Thyris gave them. window.__thyrisDock(side) docks them to Thyris's side.
function host(side) {
    return "(() => { if (window !== top) return;"
        + " const tell = (what, side) => postMessage({ thyrisDevTools: [what, side] }, '*');"
        + " let want = '" + side + "', forced = false, started = false;"
        // the embedder's host as devtools_compatibility.js sets it, after this script: its close tells Thyris
        + " const wrap = h => { if (h && !h.thyris) { h.thyris = true; h.closeWindow = () => tell('close', '') } return h };"
        + " let h = wrap(window.InspectorFrontendHost);"
        + " Object.defineProperty(window, 'InspectorFrontendHost', { configurable: true, enumerable: true, get: () => h, set: v => { h = wrap(v) } });"
        // their first side (their start's own call) and the ones Thyris gives are Thyris's; picked, only bottom or right
        + " import('devtools://devtools/bundled/ui/legacy/legacy.js').then(UI => { const D = UI.DockController.DockController, set = D.prototype.setDockSide;"
        + " D.prototype.setDockSide = function (side) { const given = !started || forced; started = true;"
        + " if (given) side = want; else if (side !== 'bottom' && side !== 'right') return;"
        + " const was = this.dockSide(); set.call(this, side); if (this.dockSide() !== was) tell(given ? 'is' : 'pick', side) };"
        + " window.__thyrisDock = side => { want = side; if (!started) return; forced = true; try { D.instance().setDockSide(side) } finally { forced = false } } });"
        // the page's slot and its resizer hidden in their root split, which holds them beside it: they fill the card;
        // undock and left hidden in their menu, a glass pane (a shadow root) added to the body
        + " const slot = '.shadow-split-widget-main, .shadow-split-widget-resizer { display: none !important }'"
        + " + ' .shadow-split-widget-sidebar { flex: auto !important }';"
        + " const deep = (root, out) => { for (const e of root.querySelectorAll('*')) { out.push(e); if (e.shadowRoot) deep(e.shadowRoot, out) } return out };"
        + " const menu = new MutationObserver(records => { for (const r of records) for (const n of r.addedNodes) if (n.shadowRoot)"
        + " for (const b of deep(n.shadowRoot, [])) if (/current-dock-state-(undock|left)\\b/.test(b.getAttribute('jslog') || '')) b.style.display = 'none' });"
        + " const start = new MutationObserver(() => { const root = document.querySelector('body > .root-view'), split = root && root.querySelector(':scope > .split-widget');"
        + " if (!split || !split.shadowRoot) return; start.disconnect(); const style = document.createElement('style'); style.textContent = slot;"
        + " split.shadowRoot.append(style); menu.observe(document.body, { childList: true }) });"
        + " start.observe(document, { childList: true, subtree: true });"
        + " })()";
}

// In DevTools' page, in Thyris's world: what `host` says, to the view's web channel (object "devtools", host(what, side))
var relay = "(() => { if (window !== top) return;"
    + " addEventListener('message', e => { const m = e.source === window && e.data && e.data.thyrisDevTools;"
    + " if (Array.isArray(m) && typeof qt !== 'undefined' && qt.webChannelTransport)"
    + " qt.webChannelTransport.send(JSON.stringify({ type: 6, object: 'devtools', method: 'host', args: [String(m[0]), String(m[1])] })) }) })()";

// DevTools docked to `side`, run in their page's own world
function dock(side) {
    return "window.__thyrisDock && __thyrisDock('" + side + "')";
}
