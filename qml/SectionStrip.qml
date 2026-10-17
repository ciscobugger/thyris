import QtQuick
import QtWebEngine
import "Recall.js" as Recall

// The page's sections under it (PLAN.md 3.19): its h1-h3 as Recall reads them, one segment each, sized by the scroll
// range in which it is the one you are in, 6 px apart. At rest a 2 px hairline in the 6 px gap under the page, the
// current segment filling as you read. With the pointer near the page's foot it rises 16 px into it over a fade of the
// page's own ground, the names above their segments and an 8 px thumb at the reading position: a drag along it scrubs
// the page (at most one scroll a frame, as PageScrollBar's), a click on a segment goes to its section. Fewer than two
// sections, no strip. It lies over the page card (its parent's size); the rest line lies under it.
Item {
    id: strip

    property var view: null             // the page on screen, or null where it has none (Main decides)
    property var pointer: null          // the page area's HoverHandler

    // scrollPosition and contentsSize are CSS px; the view shows height / zoom of them
    readonly property real zoom: view ? view.zoomFactor : 1
    readonly property real maxScroll: view ? Math.max(0, view.contentsSize.height - height / zoom) : 0
    readonly property var sections: view ? view.sections ?? null : null
    readonly property real gap: 6
    // as many as fit at 4 px each, with their gaps, along the risen track
    readonly property var segments: Recall.segments(sections, maxScroll, Math.floor((width - 56 + gap) / (gap + 4)))
    readonly property bool shown: segments.length >= 2
    readonly property real readY: dragging || settling ? dragTo : view ? Math.max(0, Math.min(maxScroll, view.scrollPosition.y)) : 0
    readonly property var at: Recall.sectionAt(segments, readY)

    // the page's ground as it paints it, else white, and whether that is dark
    readonly property var rgb: sections && sections.ground ? sections.ground : [255, 255, 255]
    readonly property color pageGround: Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1)
    readonly property bool dark: 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] < 128

    // writable, so shots can pose it near
    property bool near: shown && (dragging || band.containsMouse || gapHover.hovered
                                  || pointer !== null && pointer.hovered && pointer.point.position.y > height - 48)
    property real rise: near ? 1 : 0
    Behavior on rise { Anim { type: Anim.DefaultSpatial } }
    readonly property real up: Math.max(0, Math.min(1, rise))  // without the curve's overshoot, for colours and fades

    readonly property real trackX: 6 + 22 * rise
    readonly property real trackW: width - 2 * trackX
    readonly property real trackY: height + 2 - 16 * rise
    // each segment's place along the track: { x, w }
    readonly property var boxes: {
        const avail = Math.max(0, trackW - gap * (segments.length - 1));
        let x = 0;
        return segments.map(g => {
            const b = { x: x, w: maxScroll > 0 ? avail * (g.to - g.from) / maxScroll : 0 };
            x += b.w + gap;
            return b;
        });
    }
    // on the window's ground at rest; risen, in a light page's tones (a dark page keeps the rest ones)
    readonly property color ahead: Theme.mix(dark ? Theme.stripAhead : Theme.stripAheadLight, Theme.stripAhead, up)
    readonly property color past: Theme.mix(dark ? Theme.stripPast : Theme.stripPastLight, Theme.stripPast, up)
    readonly property color fill: Theme.mix(dark ? Theme.stripFill : Theme.stripFillLight, Theme.stripFill, up)
    readonly property color accent: dark ? Theme.primary : Theme.inversePrimary

    visible: shown

    // the page's own ground rising behind the names, opaque where they lie
    Rectangle {
        visible: strip.up > 0
        opacity: strip.up
        y: strip.height - height
        width: strip.width
        height: 64
        bottomLeftRadius: Theme.rounding.small
        bottomRightRadius: Theme.rounding.small
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(strip.pageGround.r, strip.pageGround.g, strip.pageGround.b, 0) }
            GradientStop { position: 0.45; color: strip.pageGround }
            GradientStop { position: 1; color: strip.pageGround }
        }
    }

    Repeater {
        model: strip.segments
        Item {
            id: segment
            required property var modelData
            required property int index
            objectName: "segment:" + index
            readonly property var box: strip.boxes[index] ?? { x: 0, w: 0 }
            readonly property bool here: index === strip.at.index
            x: strip.trackX + box.x
            y: strip.trackY
            width: box.w
            height: 2
            Rectangle { anchors.fill: parent; radius: 1; color: segment.index < strip.at.index ? strip.past : strip.ahead }
            Rectangle { visible: segment.here; width: parent.width * strip.at.fill; height: 2; radius: 1; color: strip.fill }
            Label {
                visible: strip.up > 0 && segment.width >= 24
                opacity: strip.up
                y: -5 - height
                width: segment.width - 4
                text: segment.modelData.name
                font.pixelSize: Theme.font.smaller
                weight: segment.here ? Font.Medium : Theme.font.mainAxes.wght
                color: segment.here ? (strip.dark ? Theme.onSurfaceVariant : Theme.outlineVariant) : Theme.outline
            }
        }
    }

    // the reading position, at the end of the current segment's fill; 11 px while held
    Rectangle {
        objectName: "stripThumb"
        readonly property var box: strip.boxes[strip.at.index] ?? { x: 0, w: 0 }
        visible: strip.up > 0
        opacity: strip.up
        width: strip.dragging ? 11 : 8
        Behavior on width { Anim { type: Anim.FastSpatial } }
        height: width
        radius: width / 2
        x: strip.trackX + box.x + strip.at.fill * box.w - width / 2
        y: strip.trackY + 1 - height / 2
        color: strip.accent
        border.width: 1.5
        border.color: strip.pageGround
    }

    // the gap under the page, where the rest line lies: the pointer there brings it up too (passive)
    Item {
        y: strip.height
        width: strip.width
        height: 6
        HoverHandler { id: gapHover }
    }

    // risen: the names and the track take the pointer (a grab hand), the rest of the page's foot stays the page's
    property bool dragging: false
    property bool settling: false       // after a drag, until the page has caught up with the last scroll
    property real dragTo: 0
    property bool pending: false        // a scroll waiting for the next frame
    MouseArea {
        id: band
        objectName: "stripBand"
        enabled: strip.near && strip.up > 0.5
        x: strip.trackX - 4
        y: strip.trackY - 26
        width: strip.trackW + 8
        height: 34
        hoverEnabled: true
        preventStealing: true
        cursorShape: strip.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pressX: 0
        onPressed: mouse => { pressX = mouse.x; settleTimer.stop(); strip.settling = false }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            if (!strip.dragging && Math.abs(mouse.x - pressX) < 4)
                return;
            strip.dragging = true;
            strip.dragTo = strip.scrollAt(x + mouse.x);
            strip.pending = true;
        }
        onReleased: mouse => {
            if (strip.dragging)
                strip.release();
            else
                strip.goTo(strip.indexAt(x + mouse.x));
        }
        onCanceled: strip.release()
    }
    Timer { id: settleTimer; interval: 250; onTriggered: strip.settling = false }
    Connections {
        target: strip.view
        function onScrollPositionChanged() {
            if (strip.settling && Math.abs(strip.view.scrollPosition.y - strip.dragTo) < 1)
                strip.settling = false;
        }
    }
    onViewChanged: { dragging = false; settling = false; pending = false }

    // the segment at strip x, a gap counting half to each side
    function indexAt(x) {
        let i = 0;
        while (i + 1 < boxes.length && x >= trackX + boxes[i + 1].x - gap / 2)
            i++;
        return i;
    }
    // the scroll position at strip x
    function scrollAt(x) {
        const i = indexAt(x), b = boxes[i], g = segments[i];
        const f = b.w > 0 ? Math.max(0, Math.min(1, (x - trackX - b.x) / b.w)) : 0;
        return Math.round(g.from + f * (g.to - g.from));
    }
    function scrollTo(y) {
        view.runJavaScript("window.scrollTo({ top: " + y + ", behavior: 'instant' })", WebEngineScript.ApplicationWorld);
    }
    // a section's start: its heading on the reading line
    function goTo(i) {
        if (i >= 0 && i < segments.length)
            scrollTo(Math.ceil(segments[i].from));
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
        scrollTo(dragTo);
    }
    FrameAnimation { running: strip.pending; onTriggered: strip.send() }
}
