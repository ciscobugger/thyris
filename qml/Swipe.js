.pragma library

// Back and forward by a sideways swipe on the touchpad (BrowserView, Main's swipe cue), as in Chrome and Safari. Run in
// the browser's script world of each top document, `watcher` tells the browser, over the view's web channel (object
// "swipe", which only that world can reach), how far each sideways wheel step went where nothing under the pointer could
// scroll that way and the page did not take the step for itself (a map, a game). A step that scrolled something, or went
// more down than across, holds the swipe off for 300 ms: a gesture that began on a carousel, or as a scroll down the
// page, never turns into one when the carousel runs out. Pixel steps only (a touchpad's; a mouse wheel's are lines).
// The listener is passive, so the page's scrolling never waits on it.
var watcher = "(() => { if (window !== window.top) return;"
    + " const send = dx => { if (typeof qt !== 'undefined' && qt.webChannelTransport)"
    + " qt.webChannelTransport.send(JSON.stringify({ type: 6, object: 'swipe', method: 'free', args: [dx] })) };"
    + " const scrolls = (el, dx) => { const root = el === document.scrollingElement, s = getComputedStyle(el);"
    + " if (root ? /^(hidden|clip)$/.test(s.overflowX) : !/^(auto|scroll|overlay)$/.test(s.overflowX)) return false;"
    + " const max = el.scrollWidth - el.clientWidth; if (max < 1) return false;"
    + " const at = s.direction === 'rtl' ? el.scrollLeft + max : el.scrollLeft; return dx < 0 ? at > 0.5 : at < max - 0.5 };"
    + " let held = 0;"
    + " addEventListener('wheel', e => { if (!e.isTrusted || e.deltaMode !== 0 || e.ctrlKey) return;"
    + " const now = performance.now(), dx = e.deltaX;"
    + " if (Math.abs(dx) <= Math.abs(e.deltaY) || e.composedPath().some(n => n instanceof Element && scrolls(n, dx))) { held = now + 300; return }"
    + " if (now < held) { held = now + 300; return }"
    + " setTimeout(() => { if (!e.defaultPrevented) send(dx) }, 0) }, { capture: true, passive: true }) })()";
