import QtQuick
// Qualified: unqualified, QtQuick.Controls' Label shadows ours (no elide, rich text, other colours).
import QtQuick.Controls as Controls
import QtQuick.Effects
import QtQuick.Shapes
import "Downloads.js" as Downloads
import "RailRows.js" as RailRows

// The rail (PLAN.md 3.1): nav row, the address card and + New page fixed at the top, threads and
// Earlier scrolling under them, Always and the fold button fixed at the foot. Ctrl+H, Ctrl+J and Ctrl+Shift+O
// turn the list into Earlier (3.7): "← Earlier", three tabs and a filter in + New page's place, and filed threads
// and closed pages by day, Saved or Downloads as the rows.
Item {
    id: rail

    required property var session
    required property var omni
    property var view: null                 // the current page's WebEngineView
    property bool pinned: true
    property bool asksInSheet: false        // the page's ask is drawn in its sheet over the page (AskSheet), not the card
    readonly property real addressCardY: addressSlot.y    // where the card is, for the sheet to dock level with it
    property bool overlay: false            // lying over the page (folded: hovered, or held out by find, the site panel or an ask)
    // The slab (PLAN.md 3.19), 0 docked .. 1 lifted: `lift` its radius (Main moves and sizes it), `fill` its fill and shadow.
    property real lift: 0
    property real fill: 0
    // the rail's fill as one opaque colour, for what covers rows inside it: docked the window's own ground (Tacit's
    // sidebars stand on it with no slab, 2026-10-08), lifted the glass
    readonly property color ground: Theme.mix(Theme.colRailGlass, Theme.terminal, fill)
    // The quiet rail (PLAN.md 3.19): everything but the Always faces and the current row at 50 % (Main says when)
    property bool quiet: false
    property real dim: quiet ? 0.5 : 1
    Behavior on dim { Anim { type: Anim.SlowEffects } }
    // a private window's rail (PLAN.md 3.14): the "Private" line under the nav row, no Earlier, no Always, no Downloads
    // group, and no rows carried to or from another window, whose profile is not this one's
    property bool offTheRecord: false
    property bool addressLifted: false      // the address card is out, centred over the page
    required property var finder            // Main's Finder: find shows in this card, the pinned rail's or folded the overlay's
    // find is called up: it lies over the rows (PLAN.md 3.8), and an ask waits until it closes
    readonly property bool finding: finder.open && finder.where === (overlay ? "peek" : "rail")
    readonly property alias findCard: findCard
    required property var site              // Main's SiteInfo: the site panel shows in this card, as find does
    // the site panel is called up: it lies over the rows too, and an ask waits until it closes (PLAN.md 3.9)
    readonly property bool siting: site.open && site.where === (overlay ? "peek" : "rail")
    readonly property alias sitePanel: sitePanel
    required property var downloads         // Main's Downloader: the rows' actions, and which summaries are listed
    property string hoverKey: ""            // shots: the row drawn with the pointer on it
    // the row under the pointer, and its task: a task's ✕ shows with the pointer anywhere over the task, its pages
    // included (the owner, 2026-10-16: closing a whole task was hard to find)
    property string pointerRow: ""
    readonly property string pointerTask: {
        const at = pointerRow.indexOf(":"), kind = pointerRow.slice(0, at), id = pointerRow.slice(at + 1);
        return kind === "t" ? id : (kind === "p" || kind === "run") && session.pages[id] ? session.pages[id].thread : "";
    }
    property bool allAlways: false
    // Main's Earlier state ({ view: "" or "history", "saved", "downloads", filter, open, editing, unfolded, older }) and
    // Saved (PLAN.md 3.7, 3.21)
    required property var earlier
    required property var saved
    readonly property bool inEarlier: earlier.view !== ""
    property var notice: null               // Main's notice, for the address card's second line
    signal noticeActed()
    readonly property alias listView: list
    // a menu, rename, edit or drag in progress: the hover overlay stays out while it lasts
    readonly property bool busy: rowMenu.opened || pageStack.opened || renaming !== "" || earlier.editing !== "" || drag !== null || incoming !== null

    signal activate(string pageId)
    signal closePage(string pageId)
    signal restoreThread(string threadId, string pageId)   // `pageId`: the page it comes back at ("": its last)
    signal newPage()
    signal addressClicked()
    signal siteClicked(string row)          // the favicon, Site settings in an ask, the refused pop-up glyph
    signal togglePin()
    signal settingsClicked()
    signal toggleMute(string pageId)
    // a row menu entry, a rename or a drop (PLAN.md 3.11, 3.13); Main.command carries it out
    signal command(string name, string ref, var arg)
    signal leaveList()                      // Esc in the rail list or the card's Fill rows: back to the page

    // the address card's rect in `item`'s coordinates, where the centred card lifts from and returns to
    function addressRect(item) { return address.mapToItem(item, 0, 0, address.width, address.height) }
    // the page's ask in the address card (the pinned rail's; folded, the overlay's)
    readonly property bool askFocused: address.askFocused
    readonly property alias addressField: address
    function focusAsk() { address.focusAsk() }
    // the Fill rows of a login field (PLAN.md 7), in the same card
    readonly property bool fillShown: address.fillShown
    readonly property bool fillFocused: address.fillFocused
    function focusFill() { address.focusFill() }
    signal fillPicked(var entry)

    implicitWidth: 300

    readonly property color wash: Theme.transparentize(Theme.onSurface, 0.95)
    readonly property var rows: {
        session.revision;
        if (rail.inEarlier) {
            rail.saved.revision;
            return RailRows.earlier(session, rail.saved, { view: earlier.view, filter: earlier.filter, open: earlier.open, editing: earlier.editing,
                                                           unfolded: earlier.unfolded, older: earlier.older });
        }
        return RailRows.build(session, { listed: rail.downloads.listed, offTheRecord: rail.offTheRecord, importHint: rail.importHint });
    }
    onRowsChanged: syncRows()
    Component.onCompleted: syncRows()
    // A hidden rail lays out the rows that came while it was hidden only when it comes out, after `filling` has been
    // reset, so each of them starts a fade-in then; after a restart the lifted rail showed only the current page, the
    // other rows at opacity 0 (2026-10-02). Once out and settled, every listed row is drawn.
    onVisibleChanged: if (visible) appearSettle.restart()
    Timer {
        id: appearSettle
        interval: 400
        onTriggered: {
            for (let i = 0; i < list.count; i++) {
                const it = list.itemAtIndex(i);
                if (it && it.appear < 1)
                    it.appear = 1;
            }
        }
    }

    ListModel { id: rowModel }
    // one line above the tasks just after a browser was brought over (Welcome), "" for none
    property string importHint: ""
    property string followed: ""
    // filling an empty list (startup, restore) is not a change to animate
    property bool filling: false
    function syncRows() {
        filling = rowModel.count === 0;
        RailRows.sync(rowModel, rows);
        // the F6 cursor stays on its row as rows around it come and go (a task put away moves its row, PLAN.md 3.19)
        for (let i = 0; i < rowModel.count && cursorKey !== ""; i++)
            if (rowModel.get(i).key === cursorKey && i !== cursor) {
                cursor = i;
                Qt.callLater(() => rail.reveal(rail.cursor));
                break;
            }
        Qt.callLater(() => rail.filling = false);
        // the scroll position follows the current row so it never leaves view
        if (session.currentPage !== followed) {
            followed = session.currentPage;
            Qt.callLater(follow);
        }
    }
    function follow() {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).current) {
                reveal(i);
                return;
            }
    }
    // Scrolls row i into view with the list's 8 px margins (ListView.Contain ignores bottomMargin).
    function reveal(i) {
        list.forceLayout();
        list.positionViewAtIndex(i, ListView.Contain);
        const it = list.itemAtIndex(i);
        if (!it)
            return;
        const top = it.y - list.topMargin, bottom = it.y + it.height + list.bottomMargin;
        if (top < list.contentY)
            list.contentY = top;
        else if (bottom > list.contentY + list.height)
            list.contentY = bottom - list.height;
    }

    // Row menus (PLAN.md 3.11). `menuKey` is the row whose menu is open: it takes an 8 % wash.
    property string menuKey: ""
    property var menuTarget: null
    function openMenu(type, ref, key, item, x, y) {
        const entries = RailRows.menu(session, type, ref, rail.offTheRecord);
        if (entries.length === 0)
            return;
        hideTip(item);
        menuTarget = { type: type, ref: ref };
        menuKey = key;
        rowMenu.entries = entries;
        rowMenu.parent = item;
        rowMenu.x = x;
        rowMenu.y = y;
        rowMenu.open();
    }
    RowMenu {
        id: rowMenu
        sub: rowSub
        onClosed: rail.menuKey = ""
        onPicked: (action, arg) => {
            const t = rail.menuTarget;
            if (action === "rename")
                rail.startRename(t.ref);
            else if (action === "forget")
                rail.command("forget", t.ref, t.type);
            else if (action === "fold")
                rail.toggleThread(t.ref, !rail.rowOpen("t:" + t.ref));
            else
                rail.command(action, t.ref, arg);
        }
    }
    RowMenu { id: rowSub; owner: rowMenu }

    // A folded task's pages beside it (PLAN.md 3.21): the pointer resting on its row for 400 ms lists them to the rail's
    // right, in the menus' look, each with its icon and word; the list never takes the keys. A click on one shows it,
    // which opens its task where it is. The list goes 250 ms after the pointer has left both the row and the list.
    property var stackRow: null
    property string stackRef: ""
    function stackOver(item, ref) {
        stackLeaveTimer.stop();
        if (pageStack.opened && stackRef === ref)
            return;
        stackRow = item;
        stackRef = ref;
        stackTimer.restart();
    }
    // `item`: the row the pointer left; another row's leaving (the pointer enters the next row before it leaves the last)
    // is not this one's
    function stackLeave(item) {
        if (item !== stackRow)
            return;
        stackTimer.stop();
        stackLeaveTimer.restart();
    }
    function openStack() {
        const t = session.threadById(stackRef);
        if (!t || !stackRow || rowMenu.opened || renaming !== "" || drag !== null)
            return;
        const now = Date.now();
        pageStack.entries = t.pages.map(id => session.pages[id]).filter(p => p).map(p => ({
            text: p.title || RailRows.untitled(p.url), icon: p.icon || "", glyph: RailRows.card(p.url, "").glyph || "language",
            action: "page", arg: p.id, shortcut: RailRows.pageWord(p, p.id === session.currentPage, now).word }));
        hideTip(stackRow);
        pageStack.parent = stackRow;
        pageStack.x = stackRow.width + 2;
        pageStack.y = -pageStack.padding;
        pageStack.open();
    }
    Timer { id: stackTimer; interval: 400; onTriggered: rail.openStack() }
    Timer { id: stackLeaveTimer; interval: 250; onTriggered: if (!pageStack.hovered) pageStack.close() }
    RowMenu {
        id: pageStack
        objectName: "pageStack"
        takesKeys: false
        onHoveredChanged: if (!hovered) rail.stackLeave(rail.stackRow)
        onPicked: (action, arg) => { if (action === "page") rail.activate(arg) }
    }
    readonly property alias pageStack: pageStack
    // The menu of the row or Always cell ("a:<id>") with `key`, as if right-clicked near its start;
    // `sub` also opens its submenu. For the keyboard's Menu key and the shots.
    function showMenu(key, sub) {
        let item = null, type = "", ref = "";
        if (key.startsWith("a:")) {
            ref = key.slice(2);
            type = "always";
            item = cellRepeater.itemAt(rail.cells.findIndex(c => c.id === ref));
        } else {
            for (let i = 0; i < rowModel.count && !item; i++)
                if (rowModel.get(i).key === key) {
                    reveal(i);
                    item = list.itemAtIndex(i);
                    type = rowModel.get(i).type;
                    ref = rowModel.get(i).ref;
                }
        }
        if (!item)
            return;
        openMenu(type, ref, key, item, Math.min(120, item.width / 2), item.height / 2);
        if (sub)
            rowMenu.openSub(rowMenu.entries.findIndex(e => e.sub));
    }

    function rowOpen(key) {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).key === key)
                return rowModel.get(i).open;
        return false;
    }

    // F2 or Rename: a field over the thread header's title. It lies over the list rather than in its
    // row, so the list's own focus handling cannot take the focus from it.
    property string renaming: ""
    property bool renameFromList: false
    function startRename(threadId) {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).key === "t:" + threadId) {
                reveal(i);
                const item = list.itemAtIndex(i);
                renameBox.y = item.mapToItem(rail, 0, 0).y + (item.height - renameBox.height) / 2;
                // over the name, after the task's icon
                renameBox.x = 34;
                renameFromList = list.activeFocus;
                renaming = threadId;
                renameField.text = rowModel.get(i).title;
                renameField.selectAll();
                renameField.forceActiveFocus();
                return;
            }
    }
    // The keys go back where the rename came from (the list after F2, else the page), unless the
    // focus already went elsewhere.
    function endRename(commit) {
        if (commit)
            rail.command("rename", renaming, renameField.text);
        renaming = "";
        if (!renameField.activeFocus)
            return;
        if (renameFromList)
            list.forceActiveFocus();
        else if (rail.view)
            rail.view.forceActiveFocus();
        else
            rail.leaveList();
    }
    Rectangle {
        id: renameBox
        visible: rail.renaming !== ""
        z: 4
        x: 34
        width: parent.width - x - 12
        height: 28
        radius: Theme.rounding.verysmall
        color: Theme.terminal
        border.width: 1
        border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
        TextInput {
            id: renameField
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.font.main
            font.hintingPreference: Font.PreferNoHinting
            font.pixelSize: Theme.font.caption
            font.variableAxes: Theme.font.mainAxes
            color: Theme.colOnLayer0
            selectionColor: Theme.transparentize(Theme.primary, 0.6)
            selectedTextColor: Theme.colOnLayer0
            clip: true
            onAccepted: rail.endRename(true)
            onActiveFocusChanged: if (!activeFocus && rail.renaming !== "") rail.endRename(false)
            Keys.onEscapePressed: rail.endRename(false)
        }
    }

    // Edit in place (PLAN.md 3.7 7c): Name and URL of a Saved page, Remove and Done under them, where its row was. It
    // lies over the list, as the rename field does, so the list's focus handling cannot take the keys from it; its
    // row keeps the room. Enter or Done keeps the change, Esc or the focus going elsewhere drops it.
    readonly property int editHeight: 102
    function editRow() {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).key === "edit:" + earlier.editing)
                return i;
        return -1;
    }
    function focusEdit() {
        const p = saved.pageById(earlier.editing), i = editRow();
        if (!p || i < 0)
            return;
        reveal(i);
        nameInput.text = p.name;
        urlInput.text = p.url;
        nameInput.forceActiveFocus();
        nameInput.selectAll();
    }
    // the keys go back to the list when the edit had them
    function endEdit(keep) {
        const id = earlier.editing, keys = editBox.activeFocus;
        if (id === "")
            return;
        if (keep)
            rail.command("saveEdit", id, { name: nameInput.text, url: urlInput.text });
        else
            rail.command("cancelEdit", id, null);
        if (keys)
            Qt.callLater(() => rail.focusList());
    }
    FocusScope {
        id: editBox
        readonly property var at: {
            list.contentY; list.contentHeight; list.count; rail.rows;
            const it = rail.inEarlier && rail.earlier.editing !== "" ? list.itemAtIndex(rail.editRow()) : null;
            return it ? list.y + it.y - list.contentY + 4 : null;
        }
        visible: at !== null
        z: 4
        x: 10
        y: at ?? 0
        width: parent.width - 20
        height: rail.editHeight
        onActiveFocusChanged: if (!activeFocus && rail.earlier.editing !== "" && Window.active) rail.endEdit(false)
        Rectangle {
            anchors.fill: parent
            radius: Theme.rounding.small
            color: Theme.over(Theme.transparentize(Theme.onSurface, 0.95), Theme.terminal)
            border.width: 1
            border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
        }
        MouseArea { anchors.fill: parent }
        component EditField: Item {
            property alias label: fieldLabel.text
            property alias input: fieldInput
            property Item next: null                // Tab and Backtab: the other field
            width: editBox.width
            height: 30
            Label { id: fieldLabel; x: 12; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.font.caption; color: Theme.colSubtext }
            TextInput {
                id: fieldInput
                anchors { left: parent.left; leftMargin: 52; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                clip: true
                font.family: Theme.font.main
                font.hintingPreference: Font.PreferNoHinting
                font.pixelSize: Theme.font.body
                font.variableAxes: Theme.font.mainAxes
                color: Theme.colOnLayer0
                selectionColor: Theme.transparentize(Theme.primary, 0.6)
                selectedTextColor: Theme.colOnLayer0
                selectByMouse: true
                renderType: Text.NativeRendering
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        rail.endEdit(true);
                    else if (event.key === Qt.Key_Escape)
                        rail.endEdit(false);
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                        parent.next.forceActiveFocus();
                    else
                        return;
                    event.accepted = true;
                }
            }
        }
        Column {
            y: 6
            EditField { id: nameField; label: "Name"; next: urlField.input }
            EditField { id: urlField; label: "URL"; next: nameField.input }
            Item {
                width: editBox.width
                height: 30
                EditAction { x: 12; name: "remove"; label: "Remove"; onPicked: { const keys = editBox.activeFocus; rail.command("removeSaved", rail.earlier.editing, null); if (keys) Qt.callLater(() => rail.focusList()) } }
                EditAction { anchors.right: parent.right; anchors.rightMargin: 12; name: "done"; label: "Done"; onPicked: rail.endEdit(true) }
            }
        }
    }
    readonly property alias nameInput: nameField.input
    readonly property alias urlInput: urlField.input
    // the edit's Remove and Done: 13 px text actions, as a download row's
    component EditAction: Label {
        id: editAction
        property string name
        property string label
        signal picked()
        objectName: "edit:" + name
        anchors.verticalCenter: parent.verticalCenter
        text: label
        font.pixelSize: Theme.font.caption
        color: editArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
        Behavior on color { CAnim { hover: true } }
        MouseArea { id: editArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: editAction.picked() }
    }

    // The rail list after F6 (PLAN.md 5): a focus ring on one row; Up/Down, Enter, Right/Left open and
    // fold, Delete closes a page, F2 renames, Menu or Shift+F10 opens the row menu, Esc goes back.
    readonly property bool listFocused: list.activeFocus
    property int cursor: -1
    property string cursorKey: ""
    onCursorChanged: cursorKey = cursor >= 0 && cursor < rowModel.count ? rowModel.get(cursor).key : ""
    function focusList() {
        cursor = -1;
        for (let i = 0; i < rowModel.count && cursor < 0; i++)
            if (rowModel.get(i).current)
                cursor = i;
        if (cursor < 0)
            moveCursor(1);
        list.forceActiveFocus();
        if (cursor >= 0)
            reveal(cursor);
    }
    // a file's row only in Earlier, where Earlier > Downloads has nothing else (Enter opens a landed file)
    function actionable(type) {
        return type === "page" || type === "thread" || type === "earlier" || type === "older"
            || type === "filed" || type === "closed" || type === "saved" || type === "savedThread" || type === "folder"
            || type === "download" && inEarlier;
    }
    function moveCursor(delta) {
        let i = cursor;
        do
            i += delta;
        while (i >= 0 && i < rowModel.count && !actionable(rowModel.get(i).type));
        if (i >= 0 && i < rowModel.count) {
            cursor = i;
            reveal(i);
        }
    }
    function listKey(event) {
        const r = cursor >= 0 && cursor < rowModel.count ? rowModel.get(cursor) : null;
        const item = r ? list.itemAtIndex(cursor) : null;
        // a closed task and an imported folder open and fold as tasks do
        const opens = r && r.type === "folder";
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        if (event.key === Qt.Key_Down) moveCursor(1);
        else if (event.key === Qt.Key_Up) {
            const at = cursor;
            moveCursor(-1);
            // above Earlier's first row, its filter
            if (cursor === at && inEarlier)
                focusFilter();
        }
        else if (event.key === Qt.Key_Escape) inEarlier ? rail.command("closeEarlier", "", null) : rail.leaveList();
        else if (!r) return false;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) rowClicked(r.type, r.ref, r.open, r.status);
        else if (event.key === Qt.Key_Right && r.type === "thread" && !r.open) toggleThread(r.ref, true);
        else if (event.key === Qt.Key_Left && r.type === "thread" && r.open) toggleThread(r.ref, false);
        else if (event.key === Qt.Key_Right && r.type === "earlier" && !r.open) rail.command("historyOpen", r.ref, true);
        else if (event.key === Qt.Key_Left && r.type === "earlier" && r.open) rail.command("historyOpen", r.ref, false);
        else if ((event.key === Qt.Key_Right || event.key === Qt.Key_Left) && opens) rail.command("earlierOpen", openKey(r), event.key === Qt.Key_Right);
        else if (event.key === Qt.Key_Delete && !shift && r.type === "page") closeFromList(r.ref);
        else if (event.key === Qt.Key_Delete && !shift && r.type === "thread") rail.command("file", r.ref, null);
        // Shift+Delete forgets (PLAN.md 3.7): a filed thread, one of its pages, a closed page
        else if (event.key === Qt.Key_Delete && shift && (r.type === "earlier" || r.type === "filed" || r.type === "closed")) rail.command("forget", r.ref, r.type);
        else if (event.key === Qt.Key_F2 && r.type === "thread") startRename(r.ref);
        else if (event.key === Qt.Key_F2 && r.type === "saved") rail.command("editSaved", r.ref, null);
        else if ((event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && shift)) && item)
            openMenu(r.type, r.ref, r.key, item, 40, item.height);
        else return false;
        return true;
    }
    // the key of Earlier's `open` for a row: a thread's id, "folder:" and an imported folder's name
    function openKey(r) { return r.type === "folder" ? "folder:" + r.ref : r.ref }
    // Delete in the list: the list keeps the keys (showing the next page took them) and the cursor
    // lands on the row that took the closed one's place, else the one before it. With no page left
    // the new-page card keeps them. The close may wait on the page's "Leave this page?" (Main.closePage),
    // so this happens once Main reports it closed.
    property var closingFromList: null
    function closeFromList(pageId) {
        closingFromList = { page: pageId, at: cursor };
        rail.closePage(pageId);
    }
    // Stay at its "Leave this page?": that close is over, and a later one by other means is not the list's
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
        cursor = c.at - 1;
        moveCursor(1);
        if (cursor === c.at - 1) {
            cursor = c.at;
            moveCursor(-1);
        }
        list.forceActiveFocus();
    }
    function rowClicked(type, ref, open, status) {
        if (type === "download" && status === "summary")
            rail.downloads.toggleListed(ref);
        else if (type === "download" && status === "done")
            rail.downloads.act(ref, "open");
        else if (type === "page")
            rail.activate(ref);
        // a folded task comes back at its last-seen page, which opens it where it is (Session.activate); an open one folds
        else if (type === "thread" && !open) {
            pageStack.close();
            rail.activate(session.mostRecentPage(ref));
        }
        else if (type === "thread")
            toggleThread(ref, false);
        // History (PLAN.md 3.20): a closed task opens in place to show its pages; one of them brings the task back with
        // that page on screen
        else if (type === "earlier")
            rail.command("historyOpen", ref, !open);
        else if (type === "filed")
            rail.restoreThread(session.pages[ref] ? session.pages[ref].thread : "", ref);
        else if (type === "closed")
            rail.command("reopenClosed", ref, null);
        else if (type === "older")
            rail.command("historyOlder", "", true);
        else if (type === "saved")
            rail.command("openSaved", ref, null);
        else if (type === "savedThread")
            rail.command("openSavedThread", ref, null);
        else if (type === "folder")
            rail.command("earlierOpen", "folder:" + ref, !open);
    }

    // Dragging a page row (PLAN.md 3.13): within the rail to reorder (a 2 px insertion line), onto a
    // thread header or a thread of one to join it, onto + New page to split it off, onto Always to keep.
    // A thread header moves its whole thread, between threads. Out of the window either goes on as the desktop's
    // drag, which another browser window's rail takes (PLAN.md 3.17).
    property var drag: null                 // { page, thread, title, icon, y, target } while a row is dragged
    function startDrag(ref, y, type) {
        tip.close();
        if (type === "thread") {
            const t = session.threadById(ref);
            drag = { page: "", thread: ref, title: t.title || "New task", icon: "", y: y, target: dropAt(y, true) };
        } else {
            const p = session.pages[ref];
            drag = { page: ref, thread: "", title: p.title || RailRows.untitled(p.url), icon: p.icon || "", y: y, target: dropAt(y) };
        }
        // the held row as the desktop drag's picture, should it leave the window
        Qt.callLater(() => { if (rail.drag) heldRow.grabToImage(r => rail.dragImage = r.url) });
    }
    function moveDrag(y) {
        if (drag)
            drag = Object.assign({}, drag, { y: y, target: dropAt(y, drag.thread !== "") });
    }
    function endDrag() {
        const d = drag;
        drag = null;
        if (d && d.target)
            rail.command(d.thread ? "dropThread" : "drop", d.thread || d.page, d.target);
    }

    // What a row carries between browser windows: { kind: "thread" or "page", ref } as JSON.
    readonly property string rowMime: "application/x-browser-row"
    // What it carries to Praxis: the page, or a thread's current page (the one on screen, else its most recent), as
    // { url, title } JSON. Never text/uri-list, which Pinax's rail would pin and the notch would park.
    readonly property string pageMime: "application/x-tacit-page"
    property url dragImage: ""
    // a held row's MIME map; a page with no address yet or a data: page (its content as the address) carries no page
    function rowPayload(d) {
        const out = { [rowMime]: JSON.stringify({ kind: d.thread ? "thread" : "page", ref: d.thread || d.page }) };
        const shown = session.pages[session.currentPage];
        const p = !d.thread ? session.pages[d.page]
            : shown && shown.thread === d.thread ? shown : session.pages[session.mostRecentPage(d.thread)];
        if (p && p.url && !/^data:/i.test(p.url))
            out[pageMime] = JSON.stringify({ url: p.url, title: p.title || RailRows.untitled(p.url) });
        return out;
    }
    // The held row leaves the window: the desktop's drag takes it on (on Wayland one of our windows gets it as any
    // drop; QDrag::exec returns when it lands), and the rail it left shows nothing.
    function carryOut() {
        const d = drag;
        drag = null;
        carrier.Drag.mimeData = rowPayload(d);
        carrier.Drag.imageSource = dragImage;
        carrier.Drag.active = true;
    }
    // A browser window's rail takes the row as a move (takeRow). Praxis takes the page as a copy: the row stays here,
    // as it does through any carry (only a rail's drop moves it).
    Item {
        id: carrier
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
        Drag.onDragFinished: Drag.active = false
    }
    // A row from another browser window (or this one's, carried out and back): its place shows as for a drag within
    // the rail, and the drop moves it here (Main.takeRow).
    property var incoming: null             // { kind, ref, target } while one is over the rail
    // when Downloads was last open: files landing after it count at the foot (places.landed)
    property double downloadsSeenAt: Date.now()
    Connections {
        target: rail.earlier
        function onViewChanged() { if (rail.earlier.view === "downloads") rail.downloadsSeenAt = Date.now() }
    }
    function overIncoming(d) {
        let payload = null;
        try {
            payload = JSON.parse(d.getDataAsString(rowMime));
        } catch (e) {}
        if (!payload || (payload.kind !== "thread" && payload.kind !== "page")) {
            incoming = null;
            return;
        }
        d.accept(Qt.MoveAction);
        incoming = { kind: payload.kind, ref: payload.ref, target: dropAt(d.y, payload.kind === "thread") };
    }
    DropArea {
        anchors.fill: parent
        enabled: !rail.offTheRecord
        keys: [rail.rowMime]
        onEntered: d => rail.overIncoming(d)
        onPositionChanged: d => rail.overIncoming(d)
        onExited: rail.incoming = null
        onDropped: d => {
            const i = rail.incoming;
            rail.incoming = null;
            if (!i || !i.target)
                return;
            d.accept(Qt.MoveAction);
            rail.command("dropFrom", i.ref, i);
        }
    }
    // where a held or incoming row would land, for the line and the washes
    readonly property var dropTarget: drag ? drag.target : incoming ? incoming.target : null
    // near the list's ends the list scrolls under a held row
    Timer {
        interval: 16
        repeat: true
        running: rail.drag !== null
        onTriggered: {
            const y = rail.drag.y - list.y;
            const step = y < 24 ? -6 : y > list.height - 24 ? 6 : 0;
            if (step === 0)
                return;
            const top = list.originY - list.topMargin;
            const end = Math.max(top, list.originY + list.contentHeight + list.bottomMargin - list.height);
            list.contentY = Math.max(top, Math.min(end, list.contentY + step));
            rail.moveDrag(rail.drag.y);
        }
    }
    function threadOfRow(r) {
        if (r.type === "thread")
            return r.ref;
        const p = r.type === "page" ? session.pages[r.ref] : r.type === "download" ? session.pages[r.page] : null;
        return p ? p.thread : "";
    }
    // the first thread listed after row i that is not row i's own; "" past the last open thread
    function threadAfter(i) {
        const own = threadOfRow(rowModel.get(i));
        for (let j = i + 1; j < rowModel.count; j++) {
            const t = threadOfRow(rowModel.get(j));
            if (t && t !== own)
                return t;
        }
        return "";
    }
    // Where a page dropped at rail y would land: { kind: "into", thread, before, line, depth } joins a
    // thread before a page ("" = at its end), { kind: "onto", thread, key } joins at the end (the row
    // takes a 10 % wash), { kind: "top", before, line } makes it a thread of one before a thread (under Pages), "new"
    // splits it off, "always" keeps it; null for nowhere. A whole thread (`whole`) lands only between threads: "top"
    // before the thread it is dropped on, or "new".
    function dropAt(y, whole) {
        const at = pageDropAt(y);
        if (!whole || !at || at.kind === "new" || at.kind === "top")
            return at;
        if (at.kind === "always")
            return null;
        const top = threadTop(at.thread);
        return top === null ? null : { kind: "top", before: at.thread, line: top, depth: 0 };
    }
    // the rail y of a listed thread's first row
    function threadTop(threadId) {
        for (let i = 0; i < rowModel.count; i++) {
            const r = rowModel.get(i);
            if ((r.type === "thread" || r.type === "page") && threadOfRow(r) === threadId) {
                const item = list.itemAtIndex(i);
                return item ? list.y + item.y - list.contentY : null;
            }
        }
        return null;
    }
    function pageDropAt(y) {
        if (y >= newRow.y && y < newRow.y + newRow.height)
            return { kind: "new" };
        if (alwaysRow.visible && y >= alwaysRow.y - 4 && y < alwaysRow.y + alwaysRow.height + 4)
            return { kind: "always" };
        if (y < list.y || y >= list.y + list.height)
            return null;
        const cy = y - list.y + list.contentY;
        const i = list.indexAt(20, cy);
        const line = v => list.y + v - list.contentY;
        if (i < 0) {
            const last = list.itemAtIndex(rowModel.count - 1);
            return last && cy >= last.y + last.height ? { kind: "top", before: firstFiled(), line: line(last.y + last.height), depth: 0 } : null;
        }
        const r = rowModel.get(i), item = list.itemAtIndex(i);
        const f = (cy - item.y) / item.height;
        if (r.type === "page" && r.depth === 1) {
            const t = session.threadById(session.pages[r.ref].thread);
            const at = t.pages.indexOf(r.ref);
            return { kind: "into", thread: t.id, before: f < 0.5 ? r.ref : (t.pages[at + 1] ?? ""),
                     line: line(f < 0.5 ? item.y : item.y + item.height), depth: 1 };
        }
        // a task's label or a put-away row takes the page into its thread; a page under Pages can also go before or after it
        if (r.type === "thread")
            return { kind: "onto", thread: r.ref, key: r.key };
        if (r.type === "page") {
            const t = threadOfRow(r);
            if (f < 0.25)
                return { kind: "top", before: t, line: line(item.y), depth: 0 };
            if (r.type === "page" && f > 0.75)
                return { kind: "top", before: threadAfter(i), line: line(item.y + item.height), depth: 0 };
            return { kind: "onto", thread: t, key: r.key };
        }
        // under a page of a thread: after that page; under a thread of one or in the Downloads group: its own thread
        if (r.type === "download") {
            const p = session.pages[r.page];
            const t = p && p.thread ? session.threadById(p.thread) : null;
            return t && !t.earlier && t.pages.length > 1
                ? { kind: "into", thread: t.id, before: t.pages[t.pages.indexOf(r.page) + 1] ?? "", line: line(item.y + item.height), depth: 1 }
                : { kind: "top", before: threadAfter(i), line: line(item.y + item.height), depth: 0 };
        }
        return null;
    }
    function firstFiled() {
        const t = session.threads.find(x => x.earlier);
        return t ? t.id : "";
    }


    // A thread opening or folding moves the rows below on the spatial curve; everything else is small.
    property bool spatialMove: false
    Timer { id: spatialEnd; interval: 400; onTriggered: rail.spatialMove = false }
    function toggleThread(id, open) {
        spatialMove = true;
        spatialEnd.restart();
        session.setOpen(id, open);
    }

    // The slab (PLAN.md 3.19): docked, none: the rail stands on the window's ground as Tacit Settings' and Files' columns
    // do (2026-10-08); lifted over the page, colRailGlass at radius 12 with a soft shadow (the shell's colShadow, as its
    // floating panels lift), opaque, so no page text shows through; no frost, the window's glass is the one layer.
    RectangularShadow {
        objectName: "slabShadow"
        visible: rail.fill > 0
        opacity: rail.fill
        anchors.fill: parent
        radius: slab.radius
        blur: 18
        offset: Qt.vector2d(0, 6)
        color: Theme.colShadow
        cached: true
    }
    Rectangle {
        id: slab
        objectName: "slab"
        anchors.fill: parent
        radius: Theme.rounding.slab + (Theme.rounding.small - Theme.rounding.slab) * rail.lift
        color: Theme.transparentize(rail.ground, 1 - rail.fill)
        border.width: 1
        border.color: Theme.transparentize(Theme.colRailSlabEdge, 1 - rail.fill)
    }

    // The top row: the fold or pin glyph, then back and forward, at the left; Settings at the right (2026-10-08; back and
    // forward moved up from the address card 2026-10-09, as Arc's and Safari's sidebars have them, so whole host names fit
    // the card). On a failure back leaves it, as Alt+Left does (PLAN.md 8f-8h).
    Item {
        id: navRow
        anchors { top: parent.top; topMargin: 10; left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
        height: 28
        opacity: rail.dim
        Row {
            spacing: 2
            IconButton {
                id: fold
                glyph: rail.pinned ? "left_panel_close" : "left_panel_open"
                onClicked: rail.togglePin()
            }
            IconButton {
                objectName: "backButton"
                readonly property var view: address.view
                glyph: "arrow_back"
                // a page a link opened goes back to its opener (Main.back)
                enabledState: { session.revision; return !!view && (view.canGoBack || session.backTo(view.pageId) !== "") }
                Accessible.name: "Back (Alt+Left)"
                onClicked: rail.command("back", view.pageId, null)
            }
            IconButton {
                objectName: "forwardButton"
                readonly property var view: address.view
                glyph: "arrow_forward"
                enabledState: view ? view.canGoForward : false
                Accessible.name: "Forward (Alt+Right)"
                onClicked: view.goForward()
            }
        }
        IconButton {
            id: settingsButton
            objectName: "settingsButton"
            anchors.right: parent.right
            glyph: "settings"
            Accessible.role: Accessible.Button
            Accessible.name: "Settings (Ctrl+,)"
            onClicked: { rail.hideTip(settingsButton); rail.settingsClicked() }
            HoverHandler { onHoveredChanged: hovered ? rail.showHint(settingsButton, "Settings", "Ctrl+,") : rail.hideTip(settingsButton) }
        }
    }

    // A private window's one mark (PLAN.md 3.14): no colour change, no glyph.
    Column {
        id: privateNote
        objectName: "privateNote"
        visible: rail.offTheRecord
        anchors { top: navRow.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18 }
        spacing: 2
        opacity: rail.dim
        Label {
            text: "Private"
            font.pixelSize: Theme.font.tiny
            color: Theme.colOnSurface
        }
        Label {
            width: parent.width
            text: "History and cookies end when this window closes."
            wrapMode: Text.Wrap
            font.pixelSize: Theme.font.tiny
            color: Theme.colSubtext
        }
    }

    // the address keeps a fixed slot; Ctrl+L lifts the card out of it. What the browser tells about the
    // page grows the card, and the rows below move down with it.
    Item {
        id: addressSlot
        anchors { top: rail.offTheRecord ? privateNote.bottom : navRow.bottom; topMargin: 8; left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
        height: address.height
    }

    // + New page, 4 px under the address card, its key at the right in the meta ink
    Item {
        id: newRow
        visible: !rail.inEarlier
        anchors { top: addressSlot.bottom; topMargin: 4; left: parent.left; right: parent.right }
        height: 34
        opacity: rail.dim
        Rectangle {
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            radius: Theme.rounding.verysmall
            color: rail.dropTarget && rail.dropTarget.kind === "new" ? Theme.transparentize(Theme.onSurface, 0.9)
                 : newArea.pressed && newArea.containsMouse ? Theme.rowPressed
                 : newArea.containsMouse && !rail.drag ? Theme.rowHover : "transparent"
            Behavior on color { CAnim { hover: true } }
        }
        Symbol {
            anchors { left: parent.left; leftMargin: 15; verticalCenter: parent.verticalCenter }
            width: 18
            text: "add"
            iconSize: 18
            color: Theme.colOnLayer0
        }
        Label {
            anchors { left: parent.left; leftMargin: 42; verticalCenter: parent.verticalCenter }
            text: "New page"
            font.pixelSize: Theme.font.body
            color: Theme.inkMain
        }
        Label {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: "Ctrl T"
            font.pixelSize: Theme.font.smaller
            color: Theme.inkMeta
        }
        MouseArea { id: newArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rail.newPage() }
    }

    // Always, "Pinned" (PLAN.md 3.12, 3.19): at the rail's foot over the places since 2026-10-08, under its label, where
    // the list can't push it away; 5 to a row, two rows,
    // then "+N"; before the first pin, a hint in its place. Each face is 24 px in a 40 px cell, 46 px apart (owner, 2026-10-09:
    // 18 px in 32 read small), a little
    // greyed at 85 % as the render draws them, bright with the pointer on it or on the page on screen (on the 14 % wash),
    // and bright when the quiet rail dims the rest; a letter tile where a site has no favicon. Under the cells, while one
    // is loading, playing or has unread mail, the marks.
    readonly property var cells: {
        session.revision;
        const ids = session.always;
        const shown = ids.length > 10 && !rail.allAlways ? ids.slice(0, 9) : ids;
        const out = shown.map(id => {
            const p = session.pages[id];
            const unread = /^\((\d+)\)\s/.exec(p.title || "");
            return { id: id, icon: p.icon || "", title: p.title || RailRows.named(p.url), current: id === session.currentPage,
                     letter: (session.siteOf(p.url) || "?").charAt(0).toUpperCase(),
                     loading: !!p.loading, audible: !!p.audible && !p.muted, unread: unread ? unread[1] : "" };
        });
        if (shown.length < ids.length)
            out.push({ id: "", more: ids.length - 9 });
        return out;
    }
    Item {
        id: alwaysRow
        objectName: "alwaysRow"
        // rail.cells, not session.always: a pin is pushed onto that list in place, which notifies nothing (the hint stayed
        // under the first pin, 2026-10-09)
        visible: !rail.inEarlier && (rail.cells.length > 0 || footHint.shown)
        anchors { bottom: foot.top; bottomMargin: 6; left: parent.left; right: parent.right }
        height: pinnedLabel.height + (rail.cells.length > 0 ? grid.height : footHint.implicitHeight + 8)

        // the group's label, as Tacit Settings labels its groups
        Label {
            id: pinnedLabel
            x: 18
            height: 26
            text: "Pinned"
            font.pixelSize: Theme.font.body
            weight: Font.Medium
            color: Theme.inkSec
            opacity: rail.dim
        }

        Label {
            id: footHint
            readonly property bool shown: rail.cells.length === 0 && !rail.session.learned.always && !rail.offTheRecord
            visible: shown
            anchors { left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 16; top: pinnedLabel.bottom; topMargin: 4 }
            text: "Drag a page here to pin it."
            wrapMode: Text.Wrap
            font.pixelSize: Theme.font.tiny
            color: Theme.colSubtext
            opacity: rail.dim
        }

        Grid {
            id: grid
            x: 9
            anchors.top: pinnedLabel.bottom
            columns: 5
            columnSpacing: 6
            rowSpacing: 4
            Repeater {
                id: cellRepeater
                model: rail.cells
                delegate: Item {
                    id: cell
                    required property var modelData
                    readonly property bool lit: !!cell.modelData.current || cellArea.containsMouse
                    objectName: "a:" + (cell.modelData.id ?? "")
                    width: 40
                    height: 40
                    Rectangle {
                        width: 40; height: 40
                        radius: Theme.rounding.verysmall
                        color: cellArea.pressed && cellArea.containsMouse ? Theme.rowPressed
                             : cell.modelData.current ? Theme.rowCurrent : rail.menuKey === "a:" + cell.modelData.id ? Theme.transparentize(Theme.onSurface, 0.92)
                             : cellArea.containsMouse ? Theme.rowHover : "transparent"
                        Behavior on color { CAnim { hover: true } }
                        Item {
                            anchors.centerIn: parent
                            width: 24; height: 24
                            opacity: cell.lit ? 1 : 0.85
                            layer.enabled: !cell.lit
                            layer.effect: MultiEffect { saturation: -0.55; brightness: -0.05 }
                            Image {
                                id: cellIcon
                                anchors.fill: parent
                                sourceSize: Qt.size(48, 48)
                                source: (Engine.iconRevision, Engine.keptIcon(String(cell.modelData.icon ?? "")))
                                visible: status === Image.Ready
                            }
                            // no favicon: the site's first letter on a tile
                            Rectangle {
                                anchors.fill: parent
                                visible: !cellIcon.visible && cell.modelData.more === undefined
                                radius: 6
                                color: Theme.rowCurrent
                                Label {
                                    anchors.centerIn: parent
                                    text: cell.modelData.letter ?? ""
                                    font.pixelSize: Theme.font.smaller
                                    weight: Font.Medium
                                }
                            }
                        }
                        Count {
                            anchors.centerIn: parent
                            visible: cell.modelData.more !== undefined
                            text: "+" + cell.modelData.more
                            font.pixelSize: Theme.font.smaller
                            color: Theme.colOnSurface
                        }
                    }
                    // on the icon's corners, on a disc of the rail's ground (PLAN.md 3.20): unread from a "(N)" title prefix at
                    // the top right; ~ while loading, ♪ while playing at the bottom right
                    Rectangle {
                        objectName: "unread"
                        visible: !!cell.modelData.unread
                        x: 24; y: 1
                        width: Math.max(16, unreadCount.implicitWidth + 8); height: 16
                        radius: 8
                        color: rail.ground
                        Count {
                            id: unreadCount
                            anchors.centerIn: parent
                            text: cell.modelData.unread ?? ""
                            font.pixelSize: Theme.font.tiny
                            color: Theme.colOnSurface
                        }
                    }
                    Rectangle {
                        visible: !!cell.modelData.loading || !!cell.modelData.audible
                        x: 26; y: 25
                        width: 14; height: 14
                        radius: 7
                        color: rail.ground
                        Busy { anchors.centerIn: parent; visible: !!cell.modelData.loading; iconSize: 12; width: 12; height: 12 }
                        Symbol {
                            anchors.centerIn: parent
                            visible: !cell.modelData.loading && !!cell.modelData.audible
                            text: "music_note"
                            iconSize: 12
                        }
                    }
                    MouseArea {
                        id: cellArea
                        width: 40; height: 40
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (cell.modelData.more !== undefined)
                                rail.allAlways = true;
                            else if (mouse.button === Qt.RightButton)
                                rail.openMenu("always", cell.modelData.id, "a:" + cell.modelData.id, cell, mouse.x, mouse.y);
                            else
                                rail.activate(cell.modelData.id);
                        }
                        onContainsMouseChanged: containsMouse && cell.modelData.id ? rail.showTip(cell, cell.modelData.id) : rail.hideTip(cell)
                    }
                }
            }
        }
    }

    // Earlier (PLAN.md 3.7 7b, 7c) in + New page's place: "← Earlier" (back, as Esc), the three views as 13 px text
    // tabs (the current one on a 10 % wash), and a filter in the address card's style. The filter is local.
    function focusFilter() {
        filterInput.forceActiveFocus();
        filterInput.selectAll();
    }
    // the filter or the edit has the keys (the rail is no focus scope, so its own activeFocus never says so)
    readonly property bool earlierFocused: filterInput.activeFocus || editBox.activeFocus
    Column {
        id: earlierHead
        visible: rail.inEarlier
        anchors { top: addressSlot.bottom; topMargin: 8; left: parent.left; right: parent.right }
        spacing: 4
        opacity: rail.dim
        Item {
            width: parent.width
            height: 36
            Rectangle {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                radius: Theme.rounding.verysmall
                color: backArea.pressed && backArea.containsMouse ? Theme.rowPressed : backArea.containsMouse ? Theme.rowHover : "transparent"
                Behavior on color { CAnim { hover: true } }
            }
            Symbol {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                width: 16
                text: "arrow_back"
                iconSize: 16
                color: Theme.colOnLayer0
            }
            Label {
                anchors { left: parent.left; leftMargin: 42; verticalCenter: parent.verticalCenter }
                text: rail.earlier.view === "history" ? "History" : rail.earlier.view === "saved" ? "Saved" : "Downloads"
                font.pixelSize: Theme.font.caption
            }
            MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rail.command("closeEarlier", "", null) }
        }
        Item { width: 1; height: 4 }
        Rectangle {
            x: 10
            width: parent.width - 20
            height: 40
            radius: Theme.rounding.small
            color: Theme.transparentize(Theme.onSurface, filterHover.hovered ? 0.94 : 0.95)
            Behavior on color { CAnim { hover: true } }
            HoverHandler { id: filterHover }
            Symbol {
                x: 12
                y: 12
                width: 16
                height: 16
                text: "search"
                iconSize: 16
            }
            TextInput {
                id: filterInput
                anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                clip: true
                text: rail.earlier.filter
                font.family: Theme.font.main
                font.hintingPreference: Font.PreferNoHinting
                font.pixelSize: Theme.font.caption
                font.variableAxes: Theme.font.mainAxes
                color: Theme.colOnLayer0
                selectionColor: Theme.transparentize(Theme.primary, 0.6)
                selectedTextColor: Theme.colOnLayer0
                selectByMouse: true
                renderType: Text.NativeRendering
                onTextEdited: rail.command("earlierFilter", "", text)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filterInput.text.length === 0
                    text: rail.earlier.view === "history" ? "Search history" : "Filter"
                    font.pixelSize: Theme.font.caption
                    color: Theme.colSubtext
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        rail.command("closeEarlier", "", null);
                    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        rail.focusList();
                    else
                        return;
                    event.accepted = true;
                }
            }
        }
    }

    ListView {
        id: list
        anchors { top: rail.inEarlier ? earlierHead.bottom : newRow.bottom; topMargin: 2; left: parent.left; right: parent.right; bottom: alwaysRow.visible ? alwaysRow.top : foot.top; bottomMargin: 4 }
        topMargin: 4
        bottomMargin: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // rows draw the current page and the cursor themselves; the view's own highlight, an invisible item, would
        // glide after its current item at 400 px/s for seconds after each change, a frame each time
        highlightFollowsCurrentItem: false
        model: rowModel
        Controls.ScrollBar.vertical: ThinScrollBar {}
        Keys.onPressed: event => event.accepted = rail.listKey(event)
        // the rename field lies over the list; it does not follow a scroll
        onContentYChanged: if (rail.renaming !== "") rail.endRename(false)

        // rows fade in and out by `appear`, which their opacity takes with the quiet rail's dim
        add: Transition {
            enabled: !rail.filling
            Anim { property: "appear"; from: 0; to: 1; type: Anim.FastEffects }
        }
        remove: Transition {
            Anim { property: "appear"; to: 0; type: Anim.FastEffects }
        }
        // a row moved or pushed while it fades in would keep the fade's last value (Qt's ViewTransition docs), so both
        // finish it
        move: Transition {
            Anim { property: "y"; type: Anim.FastSpatial }
            Anim { property: "appear"; to: 1; type: Anim.FastEffects }
        }
        displaced: Transition {
            Anim { property: "y"; type: rail.spatialMove ? Anim.FastSpatial : Anim.StandardSmall }
            Anim { property: "appear"; to: 1; type: Anim.FastEffects }
        }

        delegate: Item {
            id: row
            required property string key
            required property string type
            required property string ref
            required property string title
            required property string icon
            required property string detail
            required property string glyph
            required property int count
            required property int depth
            required property bool open
            required property bool current
            required property bool dim
            required property bool audible
            required property bool muted
            required property bool needsYou
            required property bool loading
            required property string capturing
            required property string failed
            required property string page
            required property string status
            required property string info
            required property string note
            required property real progress
            required property string from
            required property string origin
            required property string word
            required property string wordGlyph
            required property bool accent
            required property int index

            // Earlier's page rows (PLAN.md 3.7): a filed thread's page, a closed page, a saved page, drawn as a page row
            readonly property bool pageLike: type === "page" || type === "filed" || type === "closed" || type === "saved"
            // the favicon slot's x; titles start 24 px after it. A task's pages sit one step in, their titles on the
            // task's name line, and a page's files one step further (PLAN.md 3.20).
            readonly property real lead: pageLike && depth >= 1 ? 32
                                       : type === "download" && (!rail.inEarlier || rail.earlier.view === "history") ? 16 + 16 * Math.min(depth, 2) : 16
            // a task's row, open, folded or closed in History
            readonly property bool taskRow: type === "thread" || type === "earlier"
            // unloaded: 50 %; the title only where that keeps 4.5:1 on the terminal ground (PLAN.md 3.18)
            property real fade: dim ? 0.5 : 1
            Behavior on fade { Anim { type: Anim.FastEffects } }
            readonly property bool hovered: area.containsMouse || closeArea.containsMouse || audioArea.containsMouse || taskCloseArea.containsMouse
                                            || type === "download" && (fileHover.hovered || rail.hoverKey === key)
            onHoveredChanged: if (hovered) rail.pointerRow = key; else if (rail.pointerRow === key) rail.pointerRow = ""
            width: ListView.view.width
            z: ring.visible ? 1 : 0
            property real appear: 1
            opacity: appear
            // the quiet rail (PLAN.md 3.19): every row but the current one dims, all but its faces
            readonly property real quietDim: current ? 1 : rail.dim
            // a group's label carries the air above it; 12 px of air after an open task's pages (RailRows.build)
            height: type === "space" ? 12 : taskRow ? 33 : type === "download" ? file.fullHeight : type === "label" ? 40 : type === "day" ? 30
                  : type === "hint" ? hint.implicitHeight + 6 : type === "edit" ? rail.editHeight + 8 : pageLike && origin !== "" ? 46 : 33
            // a download row grows with the pointer on it, and as it comes to wait on you
            Behavior on height { enabled: row.type === "download"; Anim { type: Anim.StandardSmall } }
            // passive: the row's text actions keep their own hover
            HoverHandler { id: fileHover; enabled: row.type === "download" }

            readonly property alias washColor: rowWash.color      // for the checks
            // wash: pressed 22 %, current 14 %, hover 10 %; the current wash fades, never slides
            Rectangle {
                id: rowWash
                // 1 px apart, as the render's rows
                anchors { fill: parent; leftMargin: 6; rightMargin: 6; bottomMargin: 1 }
                radius: Theme.rounding.verysmall
                color: area.pressed && area.containsMouse && (row.type !== "download" || file.clickable) && !rail.drag ? Theme.rowPressed
                     : row.current ? Theme.rowCurrent
                     : rail.dropTarget && rail.dropTarget.key === row.key ? Theme.transparentize(Theme.onSurface, 0.9)
                     : rail.menuKey === row.key ? Theme.transparentize(Theme.onSurface, 0.92)
                     : row.hovered && area.enabled && (row.type !== "download" || file.clickable) && !rail.drag ? Theme.rowHover
                     : Theme.transparentize(Theme.onSurface, 1)
                Behavior on color { CAnim { hover: true } }
                // keyboard focus in the rail list (F6), the one place primary is used: 2 px, 2 px outside (3.18)
                Rectangle {
                    id: ring
                    visible: rail.listFocused && rail.cursor === row.index
                    anchors { fill: parent; margins: -2 }
                    radius: Theme.rounding.verysmall + 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.primary
                }
            }

            // page: favicon slot (globe until the icon arrives, busy while loading, ! on a failure: in the error
            // tone for a certificate, PLAN.md 8f-8h), title, its one word (PLAN.md 3.19), close on hover; on a 32 px
            // line, and under it where a page from another app came from (PLAN.md 3.6), or in Earlier where you stopped (3.7)
            Item {
                visible: row.pageLike
                width: parent.width
                height: 32
                z: 1        // the word's and the close glyph's areas above the row's own
                opacity: rail.drag && rail.drag.page === row.ref ? 0.4 : 1
                Behavior on opacity { Anim { type: Anim.FastEffects } }

                Image {
                    id: favicon
                    x: row.lead
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    sourceSize: Qt.size(32, 32)
                    source: row.pageLike ? (Engine.iconRevision, Engine.keptIcon(String(row.icon))) : ""
                    visible: status === Image.Ready && !row.loading && row.failed === ""
                    opacity: row.fade
                }
                Symbol {
                    x: row.lead
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    visible: !favicon.visible && !row.loading
                    text: row.failed !== "" ? "warning" : row.glyph || "language"
                    fill: RailRows.filled(text)
                    iconSize: 16
                    color: row.failed === "certificate" ? Theme.error : Theme.colSubtext
                    opacity: row.fade
                }
                Busy { x: row.lead; width: 16; height: 16; iconSize: 14; anchors.verticalCenter: parent.verticalCenter; visible: row.type === "page" && row.loading }
                Label {
                    anchors { left: parent.left; leftMargin: row.lead + 24; right: marks.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    text: row.title
                    font.pixelSize: Theme.font.body
                    weight: row.current ? Font.Medium : Theme.font.mainAxes.wght
                    // Earlier's rows are the past: a step back in the subtext tone
                    color: row.type === "filed" || row.type === "closed" ? Theme.colSubtext : Theme.colOnLayer0
                    opacity: (Theme.dimTextReadable ? row.fade : 1) * row.quietDim
                }
                // its one word (RailRows.pageWord; in Earlier a closed page's time), the accent for a file coming, an ask
                // waiting and its sound, which a click mutes; the close glyph after it with the pointer on the row
                Row {
                    id: marks
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    // what the word is about (an ask's camera, mic, place; the sound), so it reads without colour
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.wordGlyph !== "" && row.word !== ""
                        width: 18
                        text: row.wordGlyph
                        iconSize: 17
                        color: Theme.inkMain
                        opacity: row.quietDim
                    }
                    Count {
                        visible: text !== ""
                        height: 20
                        font.pixelSize: Theme.font.smaller
                        // a page's time since you saw it shows only under the pointer (PLAN.md 3.20)
                        text: row.word !== "" ? row.word : row.type !== "page" || row.hovered ? row.detail : ""
                        color: row.accent || audioArea.containsMouse ? Theme.inkMain : Theme.inkMeta
                        opacity: row.quietDim
                        MouseArea {
                            id: audioArea
                            anchors { fill: parent; margins: -4 }
                            enabled: row.type === "page" && (row.audible || row.muted)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rail.toggleMute(row.ref)
                        }
                    }
                    Symbol {
                        visible: row.type === "page" && row.hovered
                        width: 20; height: 20
                        text: "close"
                        iconSize: 16
                        color: closeArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                        MouseArea { id: closeArea; anchors.fill: parent; enabled: row.type === "page"; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rail.closePage(row.ref) }
                    }
                }
                Label {
                    visible: row.origin !== ""
                    opacity: row.quietDim
                    x: row.lead + 24
                    y: 28
                    width: parent.width - x - 16
                    height: 14
                    text: row.origin
                    font.pixelSize: Theme.font.tiny
                    color: Theme.colSubtext
                }
            }

            // A task's row (PLAN.md 3.20), open or folded alike: its newest page's icon, its name on the page titles' line,
            // its word or (folded) how many pages it holds, the close glyph under the pointer, and the arrow that turns as
            // it opens. A click on a folded task brings it back at its last-seen page; on an open one, folds it. In History
            // a closed task's row, its icon at half strength, its name in the subtext tone and its word when it closed.
            Item {
                visible: row.taskRow
                anchors.fill: parent
                readonly property bool past: row.type === "earlier"
                Image {
                    id: taskIcon
                    x: row.lead
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    sourceSize: Qt.size(32, 32)
                    source: row.taskRow ? (Engine.iconRevision, Engine.keptIcon(String(row.icon))) : ""
                    visible: status === Image.Ready
                    opacity: (parent.past ? 0.5 : 1) * row.quietDim
                }
                Symbol {
                    x: row.lead
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    visible: !taskIcon.visible
                    text: "language"
                    iconSize: 16
                    color: Theme.colSubtext
                    opacity: (parent.past ? 0.5 : 1) * row.quietDim
                }
                Label {
                    visible: rail.renaming !== row.ref
                    anchors { left: parent.left; leftMargin: row.lead + 24; right: taskMarks.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    text: row.title
                    font.pixelSize: Theme.font.body
                    weight: row.current ? Font.Medium : Theme.font.mainAxes.wght
                    color: parent.past ? Theme.colSubtext : Theme.colOnLayer0
                    opacity: row.quietDim
                }
                Row {
                    id: taskMarks
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.wordGlyph !== "" && row.word !== ""
                        width: 20
                        text: row.wordGlyph
                        iconSize: 17
                        color: Theme.inkMain
                        opacity: row.quietDim
                    }
                    Count {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        height: 20
                        font.pixelSize: Theme.font.smaller
                        text: row.word !== "" ? row.word : !row.open ? String(row.count) : ""
                        color: row.accent ? Theme.inkMain : Theme.inkMeta
                        opacity: row.quietDim
                    }
                    Symbol {
                        objectName: "taskClose"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.type === "thread" && (row.hovered || rail.pointerTask === row.ref)
                        width: 20; height: 20
                        text: "close"
                        iconSize: 16
                        color: taskCloseArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                        MouseArea { id: taskCloseArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rail.command("file", row.ref, null) }
                    }
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 20
                        text: "chevron_right"
                        rotation: row.open ? 90 : 0
                        Behavior on rotation { Anim { type: Anim.StandardSmall } }
                        iconSize: 16
                        color: Theme.colSubtext
                        opacity: row.quietDim
                    }
                }
            }

            // A download (PLAN.md 3.8 8d; its look of 2026-10-09, book4-edge/opsis-downloads-research.md): under the page
            // that started it, or in the Downloads group with the page it came from; several from one page as one row that
            // lists them. The file's kind in the favicon column, ringed with its progress while it comes; its name at row
            // size where the page's title starts; one quiet line of what it is doing, in tabular figures. A failure or a
            // warning says what happened in words and offers its ways on in the installer's rings, the safe one leading;
            // a coming or finished file shows its controls with the pointer on it. A finished row opens its file on a click.
            Item {
                id: file
                visible: row.type === "download"
                anchors.fill: parent
                z: 1        // the controls above the row's own area
                opacity: row.quietDim
                readonly property real textX: row.lead + 24
                readonly property bool waits: Downloads.waits(row.status)
                readonly property bool clickable: row.status === "done" || row.status === "summary"
                readonly property var ways: row.type === "download" ? Downloads.ways(row.status) : []
                readonly property var controls: row.type === "download" && row.hovered ? Downloads.controls(row.status) : []
                readonly property bool coming: row.status === "running" || row.status === "paused" || row.status === "summary" && row.progress >= 0
                readonly property real fullHeight: ways.length > 0 ? waysRow.y + waysRow.height + 12 : lines.y + lines.height + 9

                // the kind, and around it the progress (the installer's ring: 1.5 px of the accent at 75 %; paused, the
                // secondary ink)
                Item {
                    id: face
                    x: row.lead - 5
                    y: 8
                    width: 26; height: 26
                    Shape {
                        anchors.fill: parent
                        visible: file.coming
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: 1.5
                            strokeColor: Theme.transparentize(Theme.inkMain, 0.8)
                            fillColor: "transparent"
                            PathAngleArc { centerX: 13; centerY: 13; radiusX: 12; radiusY: 12; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeWidth: 1.5
                            strokeColor: row.status === "paused" ? Theme.inkMeta : Theme.transparentize(Theme.accent, 0.25)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 13; centerY: 13; radiusX: 12; radiusY: 12; startAngle: -90
                                sweepAngle: 360 * Math.max(0.02, row.progress)
                                Behavior on sweepAngle { Anim { type: Anim.StandardSmall } }
                            }
                        }
                    }
                    Symbol {
                        anchors.centerIn: parent
                        text: row.type === "download" ? row.glyph : ""
                        iconSize: 16
                        color: row.failed === "error" ? Theme.risk : row.status === "done" ? Theme.inkSec : Theme.inkMain
                    }
                }
                Column {
                    id: lines
                    x: file.textX
                    y: 7
                    width: parent.width - x - (controlRow.visible ? controlRow.width + 14 : 16)
                    spacing: 1
                    Label {
                        width: parent.width
                        height: 20
                        text: row.title
                        elide: Text.ElideMiddle         // the extension stays
                        font.pixelSize: Theme.font.body
                        color: Theme.inkMain
                    }
                    // what it is doing; a failure or warning in words
                    Label {
                        width: parent.width
                        text: row.note !== "" ? row.note : row.info
                        wrapMode: row.note !== "" ? Text.Wrap : Text.NoWrap
                        elide: Text.ElideRight
                        font.pixelSize: Theme.font.smaller
                        font.features: { "tnum": 1 }
                        lineHeight: 1.15
                        color: row.note !== "" ? Theme.inkSec : Theme.inkMeta
                    }
                    // the page it came from (the Downloads group)
                    Row {
                        visible: row.from !== ""
                        height: 18
                        spacing: 5
                        Image {
                            visible: status === Image.Ready
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12; height: 12
                            sourceSize: Qt.size(24, 24)
                            source: row.type === "download" ? (Engine.iconRevision, Engine.keptIcon(String(row.icon))) : ""
                        }
                        Label { text: row.from; font.pixelSize: Theme.font.smaller; color: Theme.inkMeta; height: 18; width: Math.min(implicitWidth, lines.width - 20) }
                    }
                }
                // with the pointer on a coming or finished file: its controls
                Row {
                    id: controlRow
                    visible: file.controls.length > 0
                    anchors { right: parent.right; rightMargin: 8 }
                    y: 9
                    spacing: 2
                    Repeater {
                        model: file.controls
                        IconButton {
                            required property var modelData
                            objectName: "action:" + modelData.name
                            glyph: modelData.glyph
                            onClicked: rail.downloads.act(row.ref, modelData.name)
                        }
                    }
                }
                // a failure or warning: its ways on, the safe one first
                Row {
                    id: waysRow
                    visible: file.ways.length > 0
                    x: file.textX
                    y: lines.y + lines.height + 8
                    spacing: 8
                    Repeater {
                        model: file.ways
                        Slab {
                            required property var modelData
                            objectName: "action:" + modelData.name
                            compact: true
                            text: modelData.label
                            tone: modelData.tone
                            onPicked: rail.downloads.act(row.ref, modelData.name)
                        }
                    }
                }
            }

            // a group's label (Put away, Pages, Downloads, Earlier; PLAN.md 3.19): small and grey at the foot of its line
            Label {
                visible: row.type === "label"
                opacity: row.quietDim
                anchors { left: parent.left; leftMargin: 18; bottom: parent.bottom; bottomMargin: 6 }
                height: implicitHeight
                text: row.title
                font.pixelSize: Theme.font.tiny
                weight: Font.Medium
                color: Theme.colSubtext
            }
            Label {
                id: hint
                visible: row.type === "hint"
                opacity: row.quietDim
                anchors { left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18; verticalCenter: parent.verticalCenter }
                text: row.type === "hint" ? row.title : ""
                wrapMode: Text.Wrap
                font.pixelSize: Theme.font.tiny
                color: Theme.colSubtext
            }

            // History's Older (the rest listed in place), a saved task, and an imported folder of Saved, a labelled group
            Item {
                visible: row.type === "older" || row.type === "savedThread" || row.type === "folder"
                anchors.fill: parent
                opacity: row.quietDim
                Symbol {
                    visible: row.type === "older" || row.type === "savedThread"
                    x: row.lead
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    text: row.type === "older" ? "history" : "circle"
                    iconSize: row.type === "older" ? 16 : 12
                    color: Theme.colSubtext
                }
                Label {
                    anchors { left: parent.left; leftMargin: row.type === "folder" ? 18 : row.lead + 24; right: age.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: row.title
                    font.pixelSize: Theme.font.caption
                    color: row.type === "older" ? Theme.colSubtext : Theme.colOnLayer0
                }
                Count {
                    id: age
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    font.pixelSize: Theme.font.tiny
                    text: row.detail !== "" ? row.detail : row.count > 0 ? row.count : ""
                }
            }
            // Earlier: a day label (small and grey, as the rail's labels), and Reopen thread under a filed thread's pages
            Label {
                visible: row.type === "day"
                opacity: row.quietDim
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                text: row.title
                font.pixelSize: Theme.font.tiny
                color: Theme.colSubtext
            }
            Label {
                visible: row.type === "action"
                opacity: row.quietDim
                anchors { left: parent.left; leftMargin: row.lead + 24; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: row.title
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }

            MouseArea {
                id: area
                anchors.fill: parent
                enabled: rail.actionable(row.type) || row.type === "download"
                hoverEnabled: true
                cursorShape: row.taskLabel || row.type === "download" && !file.clickable ? Qt.ArrowCursor : Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                // a held page or thread row moves after 8 px; the list does not steal it to flick
                preventStealing: row.type === "page" || row.type === "thread"
                property real pressY: 0
                property bool dragged: false
                onPressed: mouse => { pressY = mouse.y; dragged = false }
                onPositionChanged: mouse => {
                    if (!pressed || (row.type !== "page" && row.type !== "thread") || !(pressedButtons & Qt.LeftButton))
                        return;
                    const y = mapToItem(rail, 0, mouse.y).y;
                    // the pointer holds on to the window while the button is down: out past its edge, the row leaves it
                    const w = mapToItem(null, mouse.x, mouse.y);
                    if (dragged && rail.drag && !rail.offTheRecord && (w.x < 0 || w.y < 0 || w.x >= rail.Window.width || w.y >= rail.Window.height))
                        rail.carryOut();
                    else if (!dragged && Math.abs(mouse.y - pressY) > 8) {
                        dragged = true;
                        rail.startDrag(row.ref, y, row.type);
                    } else if (dragged) {
                        rail.moveDrag(y);
                    }
                }
                onReleased: if (dragged) rail.endDrag()
                onCanceled: if (dragged) rail.drag = null
                onClicked: mouse => {
                    if (dragged)
                        return;
                    if (mouse.button === Qt.RightButton)
                        rail.openMenu(row.type, row.ref, row.key, row, mouse.x, mouse.y);
                    else if (row.type === "page" && mouse.button === Qt.MiddleButton)
                        rail.closePage(row.ref);
                    else if (row.type === "thread" && mouse.button === Qt.MiddleButton)
                        rail.command("file", row.ref, null);
                    else if (mouse.button === Qt.LeftButton)
                        rail.rowClicked(row.type, row.ref, row.open, row.status);
                }
                onContainsMouseChanged: {
                    if (containsMouse && row.type === "page" && !rail.drag)
                        rail.showTip(row, row.ref);
                    // a folded task lists its pages beside it, which names them all
                    else if (containsMouse && row.type === "thread" && !row.open && !rail.drag)
                        rail.stackOver(row, row.ref);
                    else if (containsMouse && row.taskRow && !rail.drag)
                        rail.showNameTip(row, row.title, row.count + " pages");
                    else
                        rail.hideTip(row);
                    if (!containsMouse && row.type === "thread")
                        rail.stackLeave(row);
                }
            }
        }
    }

    // A download row's text action (PLAN.md 8d): 13 px subtext, full colour with the pointer on it, as the
    // rows' × and ♪ glyphs; its target reaches 4 px past the text.
    component RowAction: Label {
        id: action
        property string name
        property string label
        property string fileId
        objectName: "action:" + name
        height: 18
        text: label
        font.pixelSize: Theme.font.tiny
        color: actionArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
        Behavior on color { CAnim { hover: true } }
        MouseArea {
            id: actionArea
            anchors { fill: parent; margins: -4 }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rail.downloads.act(action.fileId, action.name)
        }
    }
    // the text action `name` of the row with `key`, for the checks: null when the row does not show it
    function rowAction(key, name) {
        for (let i = 0; i < rowModel.count; i++)
            if (rowModel.get(i).key === key) {
                reveal(i);
                const find = item => {
                    if (item.objectName === "action:" + name && item.visible)
                        return item;
                    for (const c of item.children) {
                        const f = find(c);
                        if (f)
                            return f;
                    }
                    return null;
                };
                const it = list.itemAtIndex(i);
                return it ? find(it) : null;
            }
        return null;
    }

    // 30 % hairlines only while rows scroll under the fixed top and foot
    Rectangle {
        anchors { left: parent.left; right: parent.right; rightMargin: 1 }
        y: list.y
        height: 1
        color: Theme.transparentize(Theme.outlineVariant, 0.7)
        opacity: (list.atYBeginning ? 0 : 1) * rail.dim
        Behavior on opacity { Anim { type: Anim.FastEffects } }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; rightMargin: 1 }
        y: list.y + list.height - 1
        height: 1
        color: Theme.transparentize(Theme.outlineVariant, 0.7)
        opacity: (list.atYEnd ? 0 : 1) * rail.dim
        Behavior on opacity { Anim { type: Anim.FastEffects } }
    }

    // The foot (PLAN.md 3.21): History, Saved and Downloads, the rail's other lists, and Settings' gear at its right end,
    // a button as well as Ctrl+,.
    Item {
        id: foot
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 4 }
        height: 32
        Row {
            id: places
            objectName: "footPlaces"
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            opacity: rail.dim
            visible: !rail.offTheRecord
            // files still coming whose page has no row in the list (closed, or in History): their share in, after Downloads
            readonly property string coming: {
                rail.session.revision;
                const now = Date.now();
                return RailRows.fetching((rail.session.downloads || []).filter(d => Downloads.place(d, rail.session, now) === "group"));
            }
            // files that have landed and left their pages' rows since Downloads was last open: their count in the accent
            // after Downloads, where they went ("row, then foot", 2026-10-09)
            readonly property int landed: {
                rail.session.revision;
                const now = Date.now();
                return (rail.session.downloads || []).filter(d => d.finished > rail.downloadsSeenAt && Downloads.landed(d, now)).length;
            }
            // the three as buttons, glyph and name, where the names fit; else by glyph alone, the name in the tip (a rail
            // near its narrowest)
            readonly property real namesWidth: ["History", "Saved", "Downloads"].reduce((w, n) => w + footFont.advanceWidth(n) + 16 + 22, 0)
                                               + (coming !== "" ? 6 + footFont.advanceWidth(coming) : 0) + 2 * spacing
            readonly property bool compact: namesWidth > foot.width - x - 8
            FontMetrics { id: footFont; font.family: Theme.font.main; font.pixelSize: Theme.font.smaller }
            Repeater {
                model: [{ view: "history", glyph: "history", title: "History", key: "Ctrl+H" },
                        { view: "saved", glyph: "bookmark", title: "Saved", key: "Ctrl+Shift+O" },
                        { view: "downloads", glyph: "download", title: "Downloads", key: "Ctrl+J" }]
                Item {
                    id: place
                    required property var modelData
                    readonly property bool on: rail.earlier.view === modelData.view
                    readonly property int landed: modelData.view === "downloads" ? places.landed : 0
                    onLandedChanged: if (landed > 0) arrive.restart()
                    objectName: "foot:" + modelData.view
                    width: placeRow.implicitWidth + 16
                    height: 30
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rounding.verysmall
                        color: place.on ? Theme.rowCurrent : placeArea.containsMouse ? Theme.rowHover : "transparent"
                        Behavior on color { CAnim { hover: true } }
                    }
                    Row {
                        id: placeRow
                        anchors.centerIn: parent
                        spacing: 6
                        Symbol {
                            id: placeGlyph
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            text: place.modelData.glyph
                            iconSize: 16
                            color: place.on ? Theme.inkMain : Theme.inkMeta
                            // a file arriving: one small lift on the spatial curve
                            SequentialAnimation {
                                id: arrive
                                Anim { target: placeGlyph; property: "scale"; to: 1.25; type: Anim.FastEffects }
                                Anim { target: placeGlyph; property: "scale"; to: 1; type: Anim.FastSpatial }
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !places.compact
                            text: place.modelData.title
                            font.pixelSize: Theme.font.smaller
                            color: place.on ? Theme.inkMain : Theme.inkSec
                        }
                        Count {
                            objectName: "footLanded"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: place.modelData.view === "downloads" && places.landed > 0 && places.coming === ""
                            text: places.landed
                            font.pixelSize: Theme.font.smaller
                            weight: Font.Medium
                            color: Theme.accent
                        }
                        Count {
                            objectName: "footComing"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: place.modelData.view === "downloads" && places.coming !== ""
                            text: places.coming
                            font.pixelSize: Theme.font.smaller
                            color: Theme.inkMain
                        }
                    }
                    MouseArea {
                        id: placeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: place.on ? rail.command("closeEarlier", "", null) : rail.command("earlierView", place.modelData.view, null)
                        onContainsMouseChanged: containsMouse ? rail.showHint(place, place.modelData.title, place.modelData.key) : rail.hideTip(place)
                    }
                }
            }
        }
    }
    readonly property alias alwaysRow: alwaysRow
    readonly property alias foldButton: fold
    readonly property alias topRow: navRow
    readonly property alias settingsButton: settingsButton
    readonly property alias tip: tip

    // drop targets while dragging: Always takes a 10 % wash, a place in the list a 2 px line
    Rectangle {
        visible: rail.dropTarget !== null && rail.dropTarget.kind === "always"
        x: 6
        y: alwaysRow.y - 4
        width: parent.width - 12
        height: alwaysRow.height + 8
        radius: Theme.rounding.verysmall
        color: Theme.transparentize(Theme.onSurface, 0.9)
    }
    Rectangle {
        readonly property var target: rail.dropTarget
        visible: target !== null && (target.kind === "into" || target.kind === "top")
        x: 8
        y: target ? Math.round(target.line) - 1 : 0
        width: parent.width - x - 8
        height: 2
        radius: 1
        color: Theme.transparentize(Theme.onSurface, 0.4)
    }
    // the held row follows just under the pointer (above it near the foot; under the Always row over it), so the row it
    // points at and its wash or line stay in view; opaque, as it lies over other rows
    Rectangle {
        id: heldRow
        visible: rail.drag !== null
        z: 6
        x: 20
        readonly property real below: rail.drag ? Math.max(rail.drag.y + 18, rail.drag.target && rail.drag.target.line ? rail.drag.target.line + 6 : 0) : 0
        y: !rail.drag ? 0 : rail.drag.target && rail.drag.target.kind === "always" ? alwaysRow.y + alwaysRow.height + 6
           : below + height <= rail.height - 4 ? below : rail.drag.y - 18 - height
        width: parent.width - 28
        height: 28
        radius: Theme.rounding.verysmall
        color: Theme.terminal
        border.width: 1
        border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.rowCurrent }
        Image {
            id: dragIcon
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            sourceSize: Qt.size(36, 36)
            source: rail.drag ? (Engine.iconRevision, Engine.keptIcon(String(rail.drag.icon))) : ""
            visible: status === Image.Ready
        }
        Symbol { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 18; visible: !dragIcon.visible; text: rail.drag && rail.drag.thread ? "chevron_right" : "language"; iconSize: 18 }
        Label {
            anchors { left: parent.left; leftMargin: 34; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: rail.drag ? rail.drag.title : ""
            font.pixelSize: Theme.font.caption
        }
    }

    // Row tooltip after 600 ms: full title, host and whether the page is live, frozen or unloaded.
    function showTip(item, pageId) {
        const p = session.pages[pageId];
        if (!p)
            return;
        tip.parent = item;
        tipTitle.text = p.title || RailRows.named(p.url);
        tipDetail.text = omni.hostOf(p.url) + " · " + ({ live: "live", frozen: "frozen", unloaded: "unloaded" }[p.state] ?? p.state);
        tip.x = item.width > 100 ? 34 : 0;
        tip.y = item.height + 2;
        tip.open();
    }
    // a task's: its whole name and how many pages it holds
    function showNameTip(item, title, detail) {
        tip.parent = item;
        tipTitle.text = title;
        tipDetail.text = detail;
        tip.x = item.width > 100 ? 34 : 0;
        tip.y = item.height + 2;
        tip.open();
    }
    // the same tip for a control in the foot, above it: its name and its key
    function showHint(item, title, detail) {
        tip.parent = item;
        tipTitle.text = title;
        tipDetail.text = detail;
        tip.x = Qt.binding(() => item.width - tip.width);
        // above the item; under it at the rail's top (Settings' button), where there is no room above
        tip.y = Qt.binding(() => item.mapToItem(rail, 0, 0).y < tip.height + 12 ? item.height + 4 : -tip.height - 4);
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
        // implicitContentWidth stays at 1 when the Column grows after the tip is set up, so size from the Column
        width: Math.min(contentItem.implicitWidth + leftPadding + rightPadding, rail.width - 44)
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
            Label { id: tipTitle; width: Math.min(implicitWidth, rail.width - 60); wrapMode: Text.Wrap; maximumLineCount: 3; font.pixelSize: Theme.font.caption }
            Label { id: tipDetail; width: Math.min(implicitWidth, rail.width - 60); font.pixelSize: Theme.font.smaller; color: Theme.colSubtext }
        }
    }

    AddressField {
        id: address
        x: addressSlot.x
        y: addressSlot.y
        width: addressSlot.width
        omni: rail.omni
        view: rail.view
        lifted: rail.addressLifted
        carriesAsks: !rail.finding && !rail.siting
        asksElsewhere: rail.asksInSheet
        dim: rail.dim
        notice: rail.notice
        onNoticeActed: rail.noticeActed()
        onClicked: rail.addressClicked()
        onSiteClicked: row => rail.siteClicked(row)
        onFillPicked: entry => rail.fillPicked(entry)
        onFillLeft: rail.leaveList()
    }
    // Settings open (SettingsPage, owner 2026-10-15): the rail's settings face over the address card and the rows, Pinned
    // and the foot kept; the sheet lines up with its current row. The face stays made while Settings is closed, so its
    // search keeps the keys through the moment Settings' address is not yet its own as it loads.
    required property var settings
    property bool settingsOpen: false
    readonly property Item settingsSearch: settingsFace.search
    readonly property real settingsRowY: settingsFace.y + settingsFace.anchorY
    Rectangle {
        visible: rail.settingsOpen
        anchors { top: addressSlot.top; topMargin: -4; left: parent.left; right: parent.right; leftMargin: 1; rightMargin: 1
                  bottom: alwaysRow.visible ? alwaysRow.top : foot.top }
        color: rail.ground
        MouseArea { anchors.fill: parent; hoverEnabled: true }
    }
    SettingsRail {
        id: settingsFace
        visible: rail.settingsOpen
        anchors { top: addressSlot.top; left: parent.left; right: parent.right; bottom: alwaysRow.visible ? alwaysRow.top : foot.top }
        settings: rail.settings
    }
    // closed, it shrinks back to the address card's 40 px before it goes
    FindCard {
        id: findCard
        here: rail.finding
        visible: rail.finding || height > 40
        z: 8
        x: addressSlot.x
        y: addressSlot.y
        width: addressSlot.width
        finder: rail.finder
    }
    // closed, it shrinks back to the address card's 40 px before it goes
    SitePanel {
        id: sitePanel
        here: rail.siting
        visible: rail.siting || height > 40
        z: 8
        x: addressSlot.x
        y: addressSlot.y
        width: addressSlot.width
        info: rail.site
    }
    // Under find or the site panel the slab's own fill, down to the end of the row its foot would cut
    // through (from its final height, so rows go at once as it grows): no half row of text shows under it,
    // and none through the slab's hairline or past its corners.
    Rectangle {
        readonly property Item card: findCard.shown ? findCard : sitePanel.shown ? sitePanel : null
        visible: card !== null
        z: 7
        x: 1
        width: parent.width - 2
        y: card ? card.y : 0
        height: card ? rail.rowEnd(card.y + card.implicitHeight) - y : 0
        color: rail.ground
        MouseArea { anchors.fill: parent; hoverEnabled: true }
    }
    // where the list row at rail y ends (y itself in no row)
    function rowEnd(y) {
        const cy = y - list.y + list.contentY;
        const i = list.count > 0 ? list.indexAt(20, cy) : -1;
        const it = i >= 0 ? list.itemAtIndex(i) : null;
        return it ? Math.min(list.y + list.height, list.y + it.y + it.height - list.contentY) : y;
    }
}
