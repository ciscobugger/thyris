import QtQuick

// The address under the tabs along the top (Settings > Tabs): back and forward, the rail's own AddressField (typing,
// the site's state line, "Add to Thyris", Fill, the page's quiet asks, reload and stop all live in it), and one button
// that brings out the rail for what only it holds: History, Saved, Downloads, the groups. The rail comes out on that
// button or Ctrl+B and on nothing else. A line the field grows under its first sits over the page, on the window's
// ground, as the rail's card grows over its rows.
Item {
    id: row

    required property var omni
    required property var session
    property var view: null
    property bool lifted: false             // the address card is out of this slot
    property bool railOut: false            // the rail is out over the page
    property var notice: null

    signal clicked()
    signal siteClicked(string row)
    signal fillPicked(var entry)
    signal fillLeft()
    signal noticeActed()
    signal back()
    signal railClicked()

    // what Main asks of the rail's card (F6, Ctrl+L), here too
    readonly property alias addressField: address
    readonly property alias railButton: railButton
    readonly property bool askFocused: address.askFocused
    readonly property bool fillShown: address.fillShown
    readonly property bool fillFocused: address.fillFocused
    readonly property bool addShown: address.addShown
    readonly property bool addFocused: address.addFocused
    function focusAsk() { address.focusAsk() }
    function focusFill() { address.focusFill() }
    function focusAdd() { address.focusAdd() }
    function addressRect(item) { return address.mapToItem(item, 0, 0, address.width, address.height) }

    height: 40

    // the ground under a grown card, so the page does not show through it
    Rectangle {
        x: address.x
        width: address.width
        height: address.height
        radius: 10
        color: Theme.terminal
        visible: address.height > 40
    }
    Row {
        id: nav
        height: 40
        spacing: 2
        IconButton {
            objectName: "backButton"
            anchors.verticalCenter: parent.verticalCenter
            glyph: "arrow_back"
            // a page a link opened goes back to its opener (Main.back)
            enabledState: { row.session.revision; return !!row.view && (row.view.canGoBack || row.session.backTo(row.view.pageId) !== "") }
            Accessible.name: "Back (Alt+Left)"
            onClicked: row.back()
        }
        IconButton {
            objectName: "forwardButton"
            anchors.verticalCenter: parent.verticalCenter
            glyph: "arrow_forward"
            enabledState: row.view ? row.view.canGoForward : false
            Accessible.name: "Forward (Alt+Right)"
            onClicked: row.view.goForward()
        }
    }
    AddressField {
        id: address
        x: nav.width + 6
        width: parent.width - x - 6 - railButton.width
        omni: row.omni
        view: row.view
        lifted: row.lifted
        carriesAsks: true
        asksElsewhere: true
        notice: row.notice
        onNoticeActed: row.noticeActed()
        onClicked: row.clicked()
        onSiteClicked: r => row.siteClicked(r)
        onFillPicked: entry => row.fillPicked(entry)
        onFillLeft: row.fillLeft()
    }
    IconButton {
        id: railButton
        objectName: "railButton"
        anchors { right: parent.right; top: parent.top; topMargin: 6 }
        glyph: row.railOut ? "left_panel_close" : "left_panel_open"
        picked: row.railOut
        Accessible.name: "History, Saved, Downloads and groups (Ctrl+B)"
        onClicked: row.railClicked()
    }
}
