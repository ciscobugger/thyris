import QtQuick
import QtQuick.Controls as Controls

// The frame of the browser's own pages, Settings and Pages and memory (PLAN.md 3.15, 3.17): drawn in QML on the
// opaque terminal ground over the page area, as the failure pages are, the web view under it untouched. A 680 px
// column at 28 % from the left, as the failure pages' block; the title (18 px Readex Pro) level with the rail's
// address card and what `header` holds (the filter) under it stay put, and the rows scroll under them, a 30 % hairline
// showing only while they do (as the rail's fixed top, 3.12). It takes the keys whenever its page is given them: Tab or
// Down and Backtab or Up move between its targets (items named "own:…"), Enter or Space picks; what it leaves (Esc
// with nothing to fold, Ctrl+W, Ctrl+H) goes on to Main.
FocusScope {
    id: page

    property var view: null                  // the page whose address this is
    property string title
    default property alias content: column.data
    property alias header: headerSlot.data
    // Settings' layout (Tacit Settings'): a side list in `side`, no title or header, the rows scrolling from the top
    property alias side: sideSlot.data
    property bool bare: false
    // bare: where the rows begin, under what the page keeps fixed at its top
    property int bareTop: 0
    // a press on the ground or between the rows (Settings folds a list it has out)
    signal pressedOutside()
    property alias flick: flick
    // the first target, where the keys go when the page takes them
    property Item first: null
    // Esc: true when the page had something to fold or leave (`mods`: the key's modifiers)
    property var back: mods => false
    // the ground: the opaque terminal; Settings veils the page it lies over with it instead
    property color ground: Theme.terminal
    // drawn on the ground, under the rows (Settings' sheet)
    property alias under: underSlot.data
    // where the rows scroll: across the page, or Settings' sheet
    property int frameX: 0
    property int frameWidth: width - frameX
    property int frameBottom: 0
    property real frameOpacity: 1
    readonly property real rowsHeight: column.height
    // a target outside the page that comes before its own (Settings' search, in the rail)
    property Item outsideFirst: null

    property int columnX: Math.max(40, Math.min(Math.round(width * 0.28), width - 680 - 40))
    property int columnWidth: Math.max(240, Math.min(680, width - columnX - 40))

    anchors.fill: parent
    z: 6

    Connections {
        target: page.visible ? page.view : null
        function onActiveFocusChanged() { if (page.view.activeFocus) Qt.callLater(page.take) }
    }
    onVisibleChanged: if (visible && view && view.activeFocus) Qt.callLater(take)
    function take() {
        if (!visible)
            return;
        if (first && first.visible)
            first.forceActiveFocus();
        else
            page.forceActiveFocus();
    }

    // the targets in order: the header's, the side list's, then the rows'
    function targets(item, out) {
        const list = out ?? (outsideFirst && outsideFirst.visible ? [outsideFirst] : []);
        for (const c of (item ?? headerSlot).children) {
            if (!c.visible)
                continue;
            if (c.objectName.startsWith("own:"))
                list.push(c);
            targets(c, list);
        }
        if (!item) {
            targets(sideSlot, list);
            targets(column, list);
        }
        return list;
    }
    function target(name) { return targets().find(t => t.objectName === name) ?? null }
    function move(delta) {
        const all = targets();
        if (all.length === 0)
            return;
        const at = all.findIndex(t => t.activeFocus);
        const next = all[at < 0 ? (delta > 0 ? 0 : all.length - 1) : (at + delta + all.length) % all.length];
        next.forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        reveal(next);
    }
    // The Column places its rows once a frame: rows made anew since (a Repeater given a new list) all lie at 0 until
    // then, so a scroll computed from them first has it place them (measured: Settings opened at Import scrolled to 0)
    function layout() { column.forceLayout() }
    // scrolls a row's target into view, clear of the fixed top
    function reveal(item) {
        let inRows = false;
        for (let p = item; p && !inRows; p = p.parent)
            inRows = p === column;
        if (!inRows)
            return;
        layout();
        const y = item.mapToItem(column, 0, 0).y;
        if (y < flick.contentY)
            flick.contentY = Math.max(0, y - 8);
        else if (y + item.height > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, y + item.height - flick.height + 8);
    }
    // After a pick with the keys the rows may change under the focused one: the keys go to `name`'s target.
    function refocus(name) {
        Qt.callLater(() => {
            const t = target(name);
            if (t && page.activeFocus) {
                t.forceActiveFocus(Qt.TabFocusReason);
                reveal(t);
            }
        });
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down)
            move(1);
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up)
            move(-1);
        else if (event.key !== Qt.Key_Escape || !page.back(event.modifiers))
            return;
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: page.ground
        // nothing reaches the page under a veil: no hover, no wheel
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: { page.forceActiveFocus(); page.pressedOutside() }
            onWheel: wheel => wheel.accepted = true
        }
    }
    Item {
        id: underSlot
        anchors.fill: parent
    }

    Label {
        id: titleText
        visible: !page.bare
        x: page.columnX
        y: 54
        height: 24
        text: page.title
        font.family: Theme.font.titleFamily
        font.pixelSize: Theme.font.title
        color: Theme.colOnSurface
    }
    Item {
        id: headerSlot
        visible: !page.bare
        x: page.columnX
        y: 94
        width: page.columnWidth
        height: childrenRect.height
    }

    Flickable {
        id: flick
        anchors { top: page.bare ? parent.top : headerSlot.bottom; topMargin: page.bare ? page.bareTop : 8; bottom: parent.bottom; bottomMargin: page.frameBottom
                  left: parent.left; leftMargin: page.frameX }
        width: page.frameWidth
        opacity: page.frameOpacity
        contentWidth: width
        contentHeight: column.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: ThinScrollBar {}
        MouseArea {
            width: flick.contentWidth
            height: Math.max(flick.contentHeight, flick.height)
            onPressed: { page.forceActiveFocus(); page.pressedOutside() }
        }
        Column {
            id: column
            x: page.columnX
            width: page.columnWidth
        }
    }
    Item {
        id: sideSlot
        anchors.fill: parent
    }
    // the fixed top's edge, only while rows lie under it
    Rectangle {
        visible: !page.bare && flick.contentY > 0
        anchors { top: flick.top; left: parent.left; right: parent.right }
        height: 1
        color: Theme.transparentize(Theme.outlineVariant, 0.7)
    }
}
