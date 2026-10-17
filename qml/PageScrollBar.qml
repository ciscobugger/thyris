import QtQuick
import QtWebEngine

// The page's own scrollbar (PLAN.md 3.1): Chromium's is hidden for the top document (Main.styleScrollbars)
// and this pill floats over the page card's right edge instead, 4 px wide (8 px while hovered or
// dragged), 4 px in from the edge and clear of the card's corners. It fades in (150 ms) while the page
// scrolls or the pointer nears the edge and out (300 ms) 1 s after both stop. Only the pill itself
// (4 px slop above and below, its hovered width) takes the pointer, and only while it shows: a drag
// scrolls the page. The lane above and below it stays the page's, so it does not page up or down.
// Size and place come from the view's scrollPosition and contentsSize.
Item {
    id: bar

    property var view: null             // the current page's WebEngineView (or its stand-in in shots)
    property var pointer: null          // the page area's HoverHandler
    // scrollPosition and contentsSize are CSS px; the view shows height / zoom of them
    readonly property real zoom: view ? view.zoomFactor : 1
    readonly property real viewportH: height / zoom
    readonly property real contentH: view ? view.contentsSize.height : 0
    readonly property real maxScroll: Math.max(0, contentH - viewportH)
    readonly property bool scrollable: view !== null && maxScroll >= 1
    // after a drag, until the page has caught up with the last scrollTo
    property bool settling: false
    readonly property real scrollY: dragging || settling ? dragTo : view ? Math.max(0, Math.min(maxScroll, view.scrollPosition.y)) : 0

    readonly property real inset: Theme.rounding.small
    readonly property real trackH: height - 2 * inset
    readonly property real pillH: scrollable ? Math.min(trackH, Math.max(32, Math.round(trackH * viewportH / contentH))) : 0
    readonly property real pillY: inset + (maxScroll > 0 ? Math.round((trackH - pillH) * scrollY / maxScroll) : 0)

    readonly property bool near: pointer !== null && pointer.hovered && pointer.point.position.x > width - 24
    // writable, so shots can pose it hovered
    property bool wide: laneHover.hovered || dragging
    readonly property bool awake: near || wide
    property bool recent: false         // scrolled, or the pointer left, less than 1 s ago
    readonly property bool showing: scrollable && (awake || recent)

    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { Anim { type: bar.showing ? Anim.FastEffects : Anim.SlowEffects } }

    Timer { id: idle; interval: 1000; onTriggered: bar.recent = false }
    function stir() { recent = true; idle.restart() }
    onAwakeChanged: if (!awake) stir()
    onViewChanged: { idle.stop(); recent = false; dragging = false; settling = false }
    Connections {
        target: bar.view
        function onScrollPositionChanged() {
            if (bar.settling && Math.abs(bar.view.scrollPosition.y - bar.dragTo) < 1)
                bar.settling = false;
            if (!bar.dragging)
                bar.stir();
        }
    }
    // a page that clamps the scroll elsewhere never catches up
    Timer { id: settleTimer; interval: 250; onTriggered: bar.settling = false }

    // passive: the page still gets the hover in the last 16 px
    Item {
        x: bar.width - 16
        width: 16
        height: bar.height
        HoverHandler { id: laneHover }
    }

    Rectangle {
        width: bar.wide ? 8 : 4
        Behavior on width { Anim { type: Anim.FastSpatial } }
        x: bar.width - 4 - width
        y: bar.pillY
        height: bar.pillH
        radius: width / 2
        // onSurface reads on dark pages, the terminal-tone hairline on light ones
        color: Theme.transparentize(Theme.onSurface, bar.wide ? 0.3 : 0.45)
        border.width: 1
        border.color: Theme.transparentize(Theme.terminal, 0.45)
    }

    // the pill (at its hovered width); it moves with the pill, so positions are taken in bar's coordinates
    property bool dragging: false
    property real dragTo: 0
    property real grabY: 0
    property real grabScroll: 0
    property bool pending: false        // a scroll waiting for the next frame
    MouseArea {
        id: grip
        x: bar.width - 12
        y: bar.pillY - 4
        width: 8
        height: bar.pillH + 8
        enabled: bar.showing
        preventStealing: true
        onPressed: mouse => {
            settleTimer.stop();
            bar.settling = false;
            bar.grabY = grip.y + mouse.y;
            bar.grabScroll = bar.scrollY;
            bar.dragTo = bar.scrollY;
            bar.dragging = true;
        }
        onPositionChanged: mouse => {
            if (!bar.dragging)
                return;
            const span = bar.trackH - bar.pillH;
            bar.dragTo = Math.max(0, Math.min(bar.maxScroll, bar.grabScroll + (span > 0 ? (grip.y + mouse.y - bar.grabY) * bar.maxScroll / span : 0)));
            bar.pending = true;
        }
        onReleased: bar.release()
        onCanceled: bar.release()
    }
    function release() {
        if (!dragging)
            return;
        if (pending)
            send();
        settling = Math.abs(view.scrollPosition.y - dragTo) >= 1;
        if (settling)
            settleTimer.restart();
        dragging = false;
    }
    function send() {
        pending = false;
        view.runJavaScript("window.scrollTo({ top: " + dragTo + ", behavior: 'instant' })", WebEngineScript.ApplicationWorld);
    }
    // at most one scroll a frame
    FrameAnimation { running: bar.pending; onTriggered: bar.send() }
}
