import QtQuick
import QtQuick.Controls as Controls
import "RailRows.js" as RailRows

// The tabs along the top (Settings > Tabs), the rail's pages in a row: the Always pages as faces, then every open task, a
// hairline where a task of several pages begins or ends, and + at the end. A task of several pages leads with its name,
// the rail's task row on its side (name, how many pages when folded, the arrow); a click folds it or opens it, and its
// pages follow while it is open. A tab is the rail's page row on its
// side: favicon, title, sound and its one word, close under the pointer; right-click is the rail's page menu, a held tab
// moves (within its task, into another, out as a task of its own, onto the faces to keep it). Keys as the rail list's after
// F6: Left and Right, Home and End, Enter, Delete, Menu, Esc. The rail itself stays folded, with the address card.
Item {
    id: strip

    required property var session
    property bool offTheRecord: false
    property string hoverKey: ""            // shots: the tab drawn with the pointer on it

    signal activate(string pageId)
    signal closePage(string pageId)
    signal newPage()
    signal toggleMute(string pageId)
    signal command(string name, string ref, var arg)
    signal leaveList()                      // Esc: back to the page

    readonly property int tabHeight: 30
    readonly property int faceWidth: 34
    readonly property bool busy: menu.opened || drag !== null
    readonly property bool listFocused: list.activeFocus
    readonly property alias listView: list
    readonly property alias tabMenu: menu               // for the checks

    ListModel { id: rowModel }
    readonly property var rows: {
        session.revision;
        return RailRows.strip(session, { offTheRecord: strip.offTheRecord });
    }
    onRowsChanged: sync()
    Component.onCompleted: sync()
    property int synced: 0                  // counts the syncs, for what is measured from the rows
    function sync() {
        RailRows.sync(rowModel, rows);
        synced++;
        for (let i = 0; i < rowModel.count && cursorKey !== ""; i++)
            if (rowModel.get(i).key === cursorKey && i !== cursor) {
                cursor = i;
                break;
            }
        if (session.currentPage !== followed) {
            followed = session.currentPage;
            Qt.callLater(follow);
        }
    }
    property string followed: ""
    function follow() {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).current && rowModel.get(i).type !== "away") {
                reveal(i);
                return;
            }
    }
    function reveal(i) {
        list.forceLayout();
        list.positionViewAtIndex(i, ListView.Contain);
    }

    // the faces take faceWidth each; the tabs share what is left, between 100 and 220 px, and scroll past that
    readonly property int faces: {
        let n = 0;
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).type === "pin")
                n++;
        return n;
    }
    // a task's name takes what it needs, up to 168 px: the name, the count of its pages when folded and the arrow
    FontMetrics { id: nameMetrics; font.family: Theme.font.main; font.pixelSize: Theme.font.body; font.weight: Font.Medium }
    function headerWidth(r) {
        return Math.min(168, 10 + Math.ceil(nameMetrics.advanceWidth(r.title)) + 6 + (r.open ? 0 : 20) + 22);
    }
    readonly property var headers: {
        synced;
        let n = 0, w = 0;
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).type === "thread") {
                n++;
                w += headerWidth(rowModel.get(i)) + (rowModel.get(i).edge ? 9 : 0);
            }
        return { count: n, width: w };
    }
    readonly property int tabs: rowModel.count - faces - headers.count
    readonly property real tabWidth: Math.max(100, Math.min(220, tabs > 0 ? Math.floor((width - plus.width - 8 - faces * faceWidth - headers.width) / tabs) : 220))

    // the empty part of the row: right-click moves the tabs to the side
    MouseArea {
        id: emptyRow
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => strip.openMenu("tabs", "", "", emptyRow, mouse.x, mouse.y)
    }
    ListView {
        id: list
        orientation: ListView.Horizontal
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false
        height: strip.tabHeight
        width: Math.min(contentWidth, strip.width - plus.width - 8)
        model: rowModel
        interactive: false
        Keys.onPressed: event => event.accepted = strip.listKey(event)
        // a plain wheel scrolls the row sideways
        WheelHandler {
            acceptedModifiers: Qt.NoModifier
            onWheel: event => {
                const d = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y) ? event.angleDelta.x : event.angleDelta.y;
                list.contentX = Math.max(0, Math.min(list.contentWidth - list.width, list.contentX - d));
            }
        }
        add: Transition { Anim { property: "opacity"; from: 0; to: 1; type: Anim.FastEffects } }
        remove: Transition { Anim { property: "opacity"; to: 0; type: Anim.FastEffects } }
        displaced: Transition { Anim { property: "x"; type: Anim.FastSpatial } }
        move: Transition { Anim { property: "x"; type: Anim.FastSpatial } }

        delegate: Item {
            id: tab
            required property string key
            required property string type
            required property string ref
            required property string title
            required property string icon
            required property string glyph
            required property string letter
            required property bool edge
            required property int count
            required property bool open
            required property bool current
            required property bool dim
            required property bool audible
            required property bool muted
            required property bool loading
            required property string failed
            required property string word
            required property string wordGlyph
            required property bool accent
            required property int index

            readonly property bool face: type === "pin"
            readonly property bool header: type === "thread"
            readonly property bool hovered: area.containsMouse || closeArea.containsMouse || audioArea.containsMouse || strip.hoverKey === key
            readonly property real fade: dim ? 0.5 : 1
            readonly property alias washColor: wash.color      // for the checks
            objectName: "tab:" + ref
            width: (face ? strip.faceWidth : header ? strip.headerWidth(tab) : strip.tabWidth) + (edge ? 9 : 0)
            height: strip.tabHeight

            // where a task of several pages begins or ends
            Rectangle {
                visible: tab.edge
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16
                color: Theme.transparentize(Theme.outlineVariant, 0.5)
            }
            Item {
                id: body
                z: 1        // the close and sound areas above the tab's own
                x: tab.edge ? 9 : 0
                width: parent.width - x
                height: parent.height
                opacity: strip.drag && strip.drag.page === tab.ref ? 0.4 : 1
                Behavior on opacity { Anim { type: Anim.FastEffects } }

                Rectangle {
                    id: wash
                    anchors { fill: parent; leftMargin: 1; rightMargin: 1 }
                    radius: Theme.rounding.verysmall
                    color: area.pressed && area.containsMouse && !strip.drag ? Theme.rowPressed
                         : tab.current ? Theme.rowCurrent
                         : strip.dropTarget && strip.dropTarget.onto === tab.ref ? Theme.transparentize(Theme.onSurface, 0.9)
                         : strip.menuKey === tab.key ? Theme.transparentize(Theme.onSurface, 0.92)
                         : tab.hovered && !strip.drag ? Theme.rowHover
                         : Theme.transparentize(Theme.onSurface, 1)
                    Behavior on color { CAnim { hover: true } }
                    // keyboard focus (F6): 2 px, 2 px outside, as the rail's rows
                    Rectangle {
                        visible: strip.listFocused && strip.cursor === tab.index
                        anchors { fill: parent; margins: -2 }
                        radius: Theme.rounding.verysmall + 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.primary
                    }
                }

                Image {
                    id: favicon
                    x: tab.face ? (parent.width - 20) / 2 : 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: tab.face ? 20 : 16; height: width
                    sourceSize: Qt.size(40, 40)
                    source: (Engine.iconRevision, Engine.keptIcon(String(tab.icon)))
                    visible: status === Image.Ready && !(tab.loading && !tab.face) && tab.failed === "" && !tab.header
                    opacity: tab.fade
                }
                // no favicon: a face shows the site's first letter on a tile, a tab the page's glyph
                Rectangle {
                    visible: tab.face && !favicon.visible
                    anchors.centerIn: parent
                    width: 20; height: 20
                    radius: 5
                    color: Theme.rowCurrent
                    Label { anchors.centerIn: parent; text: tab.letter; font.pixelSize: Theme.font.smaller; weight: Font.Medium }
                }
                Symbol {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    visible: !tab.face && !tab.header && !favicon.visible && !tab.loading
                    text: tab.failed !== "" ? "warning" : tab.glyph || "language"
                    fill: RailRows.filled(text)
                    iconSize: 16
                    color: tab.failed === "certificate" ? Theme.error : Theme.colSubtext
                    opacity: tab.fade
                }
                Busy { x: 10; width: 16; height: 16; iconSize: 14; anchors.verticalCenter: parent.verticalCenter; visible: !tab.face && !tab.header && tab.loading }
                // a face's unread count on its top right corner, on a disc of the ground
                Rectangle {
                    visible: tab.face && tab.count > 0
                    x: parent.width - width - 1; y: 0
                    width: Math.max(14, unread.implicitWidth + 6); height: 14
                    radius: 7
                    color: Theme.terminal
                    Count { id: unread; anchors.centerIn: parent; text: tab.count; font.pixelSize: Theme.font.tiny; color: Theme.colOnSurface }
                }
                // a face's loading and sound marks sit on its corner
                Busy { x: parent.width - 18; y: parent.height - 14; width: 12; height: 12; iconSize: 12; visible: tab.face && tab.loading }
                Symbol {
                    x: parent.width - 18; y: parent.height - 14
                    visible: tab.face && !tab.loading && tab.audible && !tab.muted
                    text: "music_note"
                    iconSize: 12
                }

                Label {
                    visible: !tab.face && !tab.header
                    anchors { left: parent.left; leftMargin: 34; right: marks.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: tab.title
                    font.pixelSize: Theme.font.body
                    weight: tab.current ? Font.Medium : Theme.font.mainAxes.wght
                    color: Theme.colOnLayer0
                    opacity: Theme.dimTextReadable ? tab.fade : 1
                }
                // A task's name, then (folded) how many pages it holds or its one word's glyph, and the arrow that turns as it
                // opens, as the rail's task row
                Label {
                    visible: tab.header
                    anchors { left: parent.left; leftMargin: 10; right: headerMarks.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    text: tab.title
                    font.pixelSize: Theme.font.body
                    weight: Font.Medium
                    color: Theme.inkMain
                }
                Row {
                    id: headerMarks
                    visible: tab.header
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: tab.wordGlyph !== "" && tab.word !== ""
                        width: 18
                        text: tab.wordGlyph
                        iconSize: 17
                        color: Theme.inkMain
                    }
                    Count {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !tab.open && !(tab.wordGlyph !== "" && tab.word !== "")
                        height: 20
                        text: String(tab.count)
                        color: Theme.inkMeta
                    }
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 20
                        text: "chevron_right"
                        rotation: tab.open ? 90 : 0
                        Behavior on rotation { Anim { type: Anim.StandardSmall } }
                        iconSize: 16
                        color: Theme.colSubtext
                    }
                }
                // its one word's glyph, the sound (a click mutes), then close under the pointer or on the current tab
                Row {
                    id: marks
                    visible: !tab.face && !tab.header
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: tab.wordGlyph !== "" && tab.word !== ""
                        width: 18
                        text: tab.wordGlyph
                        iconSize: 17
                        color: Theme.inkMain
                    }
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: tab.wordGlyph === "" && (tab.audible || tab.muted)
                        width: 20; height: 20
                        text: tab.muted ? "volume_off" : "music_note"
                        iconSize: 16
                        color: audioArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                        MouseArea { id: audioArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: strip.toggleMute(tab.ref) }
                    }
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: tab.type === "page" && (tab.hovered || tab.current)
                        width: 20; height: 20
                        text: "close"
                        iconSize: 16
                        color: closeArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                        MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: strip.closePage(tab.ref) }
                    }
                }
            }

            MouseArea {
                id: area
                x: body.x
                width: body.width
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                // a held tab moves after 8 px; the row does not take it to scroll
                preventStealing: true
                property real pressX: 0
                property bool dragged: false
                onPressed: mouse => { pressX = mouse.x; dragged = false }
                onPositionChanged: mouse => {
                    if (!pressed || tab.type === "away" || tab.header || !(pressedButtons & Qt.LeftButton))
                        return;
                    const x = mapToItem(strip, mouse.x, 0).x;
                    if (!dragged && Math.abs(mouse.x - pressX) > 8) {
                        dragged = true;
                        strip.startDrag(tab.ref, x);
                    } else if (dragged) {
                        strip.moveDrag(x);
                    }
                }
                onReleased: if (dragged) strip.endDrag()
                onCanceled: if (dragged) strip.drag = null
                onClicked: mouse => {
                    if (dragged)
                        return;
                    if (mouse.button === Qt.RightButton)
                        strip.openMenu(tab.face ? "always" : tab.header ? "thread" : "page", tab.ref, tab.key, tab, mouse.x, mouse.y);
                    else if (mouse.button === Qt.MiddleButton && tab.type === "page")
                        strip.closePage(tab.ref);
                    else if (mouse.button === Qt.LeftButton && tab.header)
                        strip.toggleTask(tab.ref, tab.open);
                    else if (mouse.button === Qt.LeftButton)
                        strip.activate(tab.ref);
                }
                onContainsMouseChanged: containsMouse && !strip.drag ? strip.showTip(tab, tab.ref) : strip.hideTip(tab)
            }
        }
    }

    // + New page, after the last tab
    Item {
        id: plus
        objectName: "plus"
        x: list.width + 8
        width: 30
        height: strip.tabHeight
        readonly property bool hovered: plusArea.containsMouse
        Rectangle {
            anchors { fill: parent; leftMargin: 1; rightMargin: 1 }
            radius: Theme.rounding.verysmall
            color: plusArea.pressed && plusArea.containsMouse ? Theme.rowPressed : plus.hovered ? Theme.rowHover : Theme.transparentize(Theme.onSurface, 1)
            Behavior on color { CAnim { hover: true } }
        }
        Symbol { anchors.centerIn: parent; text: "add"; iconSize: 18; color: plus.hovered ? Theme.colOnLayer0 : Theme.colSubtext }
        MouseArea {
            id: plusArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: strip.newPage()
            onContainsMouseChanged: containsMouse ? strip.showHint(plus, "New page", "Ctrl+T") : strip.hideTip(plus)
        }
    }

    // a folded task comes back at its last-seen page, which opens it where it is (Session.activate); an open one folds
    function toggleTask(ref, open) {
        if (open)
            session.setOpen(ref, false);
        else
            strip.activate(session.mostRecentPage(ref));
    }

    // Row menus: the rail's page menu, task menu and Always menu, carried out by the same commands. A task's name is
    // renamed in the rail.
    property string menuKey: ""
    property var menuTarget: null
    function openMenu(type, ref, key, item, x, y) {
        const entries = RailRows.menu(session, type, ref, strip.offTheRecord, true).filter(e => e.action !== "rename");
        if (entries.length === 0)
            return;
        hideTip(item);
        menuTarget = { type: type, ref: ref };
        menuKey = key;
        menu.entries = entries;
        menu.parent = item;
        menu.x = x;
        menu.y = y;
        menu.open();
    }
    RowMenu {
        id: menu
        sub: menuSub
        onClosed: strip.menuKey = ""
        onPicked: (action, arg) => {
            const t = strip.menuTarget;
            if (action === "fold")
                strip.toggleTask(t.ref, session.isOpen(session.threadById(t.ref)));
            else
                strip.command(action, t.ref, arg);
        }
    }
    RowMenu { id: menuSub; owner: menu }
    // The menu of the tab with `key`, as for the Menu key and the shots; `sub` also opens its submenu.
    function showMenu(key, sub) {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).key === key) {
                reveal(i);
                const r = rowModel.get(i), item = list.itemAtIndex(i);
                if (!item)
                    return;
                openMenu(r.type === "pin" ? "always" : r.type === "thread" ? "thread" : "page", r.ref, key, item, Math.min(60, item.width / 2), item.height);
                if (sub)
                    menu.openSub(menu.entries.findIndex(e => e.sub));
                return;
            }
    }

    // the menu of the empty part of the row, for the shots and the checks
    function showTabsMenu() { openMenu("tabs", "", "", emptyRow, emptyRow.width - 120, 20); }

    // Tab tooltip after 600 ms: the full title, the host and whether the page is live, frozen or unloaded
    function showTip(item, pageId) {
        const p = session.pages[pageId];
        if (!p)
            return;
        tip.parent = item;
        tipTitle.text = p.title || RailRows.named(p.url);
        tipDetail.text = RailRows.split(p.url).host + " · " + ({ live: "live", frozen: "frozen", unloaded: "unloaded" }[p.state] ?? p.state);
        tip.x = 0;
        tip.y = item.height + 2;
        tip.open();
    }
    function showHint(item, title, detail) {
        tip.parent = item;
        tipTitle.text = title;
        tipDetail.text = detail;
        tip.x = 0;
        tip.y = item.height + 2;
        tip.open();
    }
    function hideTip(item) {
        if (tip.parent === item)
            tip.close();
    }
    Controls.ToolTip {
        id: tip
        delay: 600
        padding: 8
        width: Math.min(contentItem.implicitWidth + leftPadding + rightPadding, 320)
        background: Frost {
            radius: Theme.rounding.verysmall
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
            }
        }
        contentItem: Column {
            spacing: 2
            Label { id: tipTitle; width: Math.min(implicitWidth, 300); wrapMode: Text.Wrap; maximumLineCount: 3; font.pixelSize: Theme.font.caption }
            Label { id: tipDetail; width: Math.min(implicitWidth, 300); font.pixelSize: Theme.font.smaller; color: Theme.colSubtext }
        }
    }

    // Dragging a tab (as the rail's rows, PLAN.md 3.13): between two pages of a task it joins at that place; between tasks
    // it becomes a task of its own there; on the middle of another task's tab it joins that task; at the end of the row
    // it leaves its task; on the faces it is kept. Dropping where it already is does nothing.
    property var drag: null                 // { page, x, target } while a tab is held
    readonly property var dropTarget: drag ? drag.target : null
    function startDrag(ref, x) {
        tip.close();
        drag = { page: ref, x: x, target: dropAt(ref, x) };
    }
    function moveDrag(x) {
        if (drag)
            drag = Object.assign({}, drag, { x: x, target: dropAt(drag.page, x) });
    }
    function endDrag() {
        const d = drag;
        drag = null;
        if (d && d.target)
            strip.command("drop", d.page, d.target.arg);
    }
    // the tab (delegate index) under strip x, or -1
    function indexAt(x) {
        return list.indexAt(x - list.x + list.contentX, list.height / 2);
    }
    // Where a page dropped at strip x lands: { arg (Main.command "drop"'s), line (strip x of the insertion line, or -1),
    // onto (the page whose tab takes the wash), faces } or null for nowhere.
    function dropAt(ref, x) {
        if (!offTheRecord && faces > 0 && x < faces * faceWidth - list.contentX && !session.always.includes(ref))
            return { arg: { kind: "always" }, line: -1, onto: "", faces: true };
        let i = indexAt(x);
        const mine = session.pages[ref];
        const rows = [];
        for (let j = faces; j < rowModel.count; j++) {
            const r = rowModel.get(j);
            if (r.type === "page")
                rows.push({ ref: r.ref, thread: r.thread, index: j, afterName: j > 0 && rowModel.get(j - 1).type === "thread" });
        }
        if (rows.length === 0 || !mine)
            return null;
        // on a task's name: the page joins that task
        if (i >= 0 && rowModel.get(i).type === "thread") {
            const t = rowModel.get(i).ref;
            return mine.thread === t ? null : { arg: { kind: "onto", thread: t }, line: -1, onto: t, faces: false };
        }
        const lineAt = j => {
            const it = list.itemAtIndex(j);
            return it ? it.x - list.contentX + list.x + (it.edge ? 4 : 0) : -1;
        };
        const endLine = () => {
            const it = list.itemAtIndex(rowModel.count - 1);
            return it ? it.x + it.width - list.contentX + list.x : -1;
        };
        const at = i < 0 ? rows.length : rows.findIndex(r => r.index === i);
        if (at < 0)
            return null;       // over a face or the away tab
        // the end of the row, or past the last tab
        const place = (k, line) => {
            // k: the page the line lies before (-1 at the end)
            const b = k >= 0 ? rows[k] : null;
            const prev = k > 0 ? rows[k - 1] : k < 0 ? rows[rows.length - 1] : null;
            if (b && b.ref === ref || prev && prev.ref === ref)
                return null;
            // before a task's first page, under its name, is inside the task
            const own = prev && b && prev.thread === b.thread || b && b.afterName;
            if (own)
                return { arg: { kind: "into", thread: b.thread, before: b.ref }, line: line, onto: "", faces: false };
            // between tasks (or at an end): a task of its own there
            return { arg: { kind: "top", before: b ? b.thread : "" }, line: line, onto: "", faces: false };
        };
        if (i < 0)
            return place(-1, endLine());
        const item = list.itemAtIndex(i);
        const f = (x - list.x + list.contentX - item.x - (item.edge ? 9 : 0)) / (item.width - (item.edge ? 9 : 0));
        const r = rows[at];
        if (f < 0.25)
            return place(at, lineAt(i));
        if (f > 0.75)
            return place(at + 1 < rows.length ? at + 1 : -1, at + 1 < rows.length ? lineAt(rows[at + 1].index) : endLine());
        if (r.thread === mine.thread)
            return null;
        return { arg: { kind: "onto", thread: r.thread }, line: -1, onto: r.ref, faces: false };
    }
    // the insertion line
    Rectangle {
        visible: strip.dropTarget !== null && strip.dropTarget.line >= 0
        x: strip.dropTarget ? Math.round(strip.dropTarget.line) - 1 : 0
        y: 3
        width: 2
        height: strip.tabHeight - 6
        radius: 1
        color: Theme.transparentize(Theme.onSurface, 0.4)
    }
    // dropped on the faces: they take the wash
    Rectangle {
        visible: strip.dropTarget !== null && strip.dropTarget.faces
        x: 0
        width: Math.min(strip.faces * strip.faceWidth, list.width)
        height: strip.tabHeight
        radius: Theme.rounding.verysmall
        color: Theme.transparentize(Theme.onSurface, 0.9)
    }

    // The tabs after F6: Left and Right move the ring, Enter shows the page, Delete closes it, Menu opens its menu
    property int cursor: -1
    property string cursorKey: ""
    onCursorChanged: cursorKey = cursor >= 0 && cursor < rowModel.count ? rowModel.get(cursor).key : ""
    function focusList() {
        cursor = -1;
        for (let i = 0; i < rowModel.count && cursor < 0; i++)
            if (rowModel.get(i).current)
                cursor = i;
        if (cursor < 0 && rowModel.count > 0)
            cursor = 0;
        list.forceActiveFocus();
        if (cursor >= 0)
            reveal(cursor);
    }
    function moveCursor(delta) {
        const i = Math.max(0, Math.min(rowModel.count - 1, cursor + delta));
        if (i !== cursor) {
            cursor = i;
            reveal(i);
        }
    }
    function listKey(event) {
        const r = cursor >= 0 && cursor < rowModel.count ? rowModel.get(cursor) : null;
        const item = r ? list.itemAtIndex(cursor) : null;
        if (event.key === Qt.Key_Right) moveCursor(1);
        else if (event.key === Qt.Key_Left) moveCursor(-1);
        else if (event.key === Qt.Key_Home) moveCursor(-rowModel.count);
        else if (event.key === Qt.Key_End) moveCursor(rowModel.count);
        else if (event.key === Qt.Key_Escape) strip.leaveList();
        else if (!r) return false;
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && r.type === "thread") toggleTask(r.ref, r.open);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) strip.activate(r.ref);
        else if (event.key === Qt.Key_Delete && r.type === "thread") strip.command("file", r.ref, null);
        else if (event.key === Qt.Key_Delete && r.type === "page") closeFromList(r.ref);
        else if ((event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) && item)
            openMenu(r.type === "pin" ? "always" : r.type === "thread" ? "thread" : "page", r.ref, r.key, item, 20, item.height);
        else return false;
        return true;
    }
    // Delete: the ring stays on the tab that took the closed one's place, else the one before it. The close may wait on
    // the page's "Leave this page?", so this happens once Main reports it closed.
    property var closingFromList: null
    function closeFromList(pageId) {
        closingFromList = { page: pageId, at: cursor };
        strip.closePage(pageId);
    }
    function closeKept(pageId) {
        if (closingFromList && closingFromList.page === pageId)
            closingFromList = null;
    }
    function closed(pageId) {
        const c = closingFromList;
        if (!c || c.page !== pageId)
            return;
        closingFromList = null;
        if (session.currentPage === "")
            return;
        cursor = Math.max(0, Math.min(rowModel.count - 1, c.at));
        list.forceActiveFocus();
    }
}
