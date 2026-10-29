import QtQuick
import "Asks.js" as Asks
import "Logins.js" as Logins
import "PageState.js" as PageState
import "RailRows.js" as RailRows

// Where the current page is, at the top of the rail: favicon, host, path dimmed; a hairline shows
// loading. A click, or Ctrl+L, lifts it out into the centred address card (AddressEditor, PLAN.md 3.2);
// while that is out the slot keeps only a faint outline. A click on the favicon opens the site panel (3.9). What the browser tells about the page grows
// the card under its first line (PLAN.md 3.8), and the rail rows move down with it: the page's ask (AskSection) alone,
// else the Fill rows of a login field (PLAN.md 7) and the password note.
Item {
    id: field

    required property var omni
    property var view: null                  // the current page's WebEngineView
    property bool lifted: false              // the address card is out of this slot
    property bool carriesAsks: false         // this card shows the page's ask
    property bool asksElsewhere: false       // the page's asks are in their sheet (AskSheet), not here, but for the quiet
                                             // "Save password?" line; the Fill rows stay
    property real dim: 1                     // the quiet rail's (PLAN.md 3.19): the path dims, the favicon and host stay

    signal clicked()
    signal siteClicked(string row)          // the site panel; `row`: a row whose choices come out at once
    // Main's notice on the second line, over what it would say: "Saved · Edit" for 3 s after Ctrl+D, "Forgot <title> ·
    // Undo" for 6 s after a forget in Earlier (PLAN.md 3.7); the action is a text action, as a download row's
    property var notice: null
    readonly property var shownNotice: notice !== null && notice.where === "card" ? notice : null
    signal noticeActed()

    readonly property var ask: carriesAsks && !lifted && view && view.ask && (!asksElsewhere || view.ask.kind === "password") ? view.ask : null
    readonly property bool askFocused: section.activeFocus
    readonly property alias askSection: section
    function focusAsk() { section.focusFirst() }

    // on a failure (PLAN.md 8f-8h) the address that failed, "!" in the slot: in the error tone for a
    // certificate, also on a page loaded past one (`questioned`), else colSubtext
    readonly property var failure: view ? view.failure ?? null : null
    readonly property var questioned: view ? view.questioned ?? null : null
    readonly property string url: view ? (failure ? failure.url : String(view.url)) : ""
    // the host and path; the browser's own pages, files, about:blank, data: and view-source: by their kind (PLAN.md 3.17)
    readonly property var parts: RailRows.card(url, view ? view.title ?? "" : "")
    readonly property bool insecure: !failure && PageState.insecure(url)
    readonly property bool warned: insecure || failure !== null || questioned !== null
    readonly property bool errorTone: insecure || questioned !== null || failure !== null && failure.tone === "error"
    // the second line: what holds the page (its dialog, a file pick, its popup; 8j-8l), what its certificate's
    // page says (8g), else 8a, a load under 30 % after 8 s naming its server; 8b: a password field on an http
    // page has the focus
    readonly property string stateLine: view ? PageState.stateLine({ dialog: !!view.dialog, choosing: !!view.choosing, popup: !!view.popup,
                                                                     failure: (failure ?? questioned ?? {}).cardLine ?? "",
                                                                     waitingFor: view.waitingFor }) : ""
    readonly property bool passwordNote: insecure && view !== null && view.passwordFocused
    // Fill (PLAN.md 7): while a login field of the page has the keys and the keyring holds logins of its origin, a
    // suggestions' row for each under a hairline; a click, or Enter once F6 brought the keys here, fills that login. It
    // gives way to an ask, and waits while the address is edited or find or the site panel is out.
    readonly property var logins: carriesAsks && !lifted && view && view.loginField && view.loginField.origin === Asks.originOf(url)
                                  ? Logins.forOrigin(Passwords.entries, view.loginField.origin) : []
    readonly property bool fillShown: !ask && logins.length > 0 && (view.loginFocused || fill.activeFocus)
    readonly property bool fillFocused: fill.activeFocus
    // the "Add to Thyris" line on a store page: F6 reaches it, Enter or Space presses it
    readonly property bool addShown: addLabel.visible && addLine === "add"
    readonly property bool addFocused: addLabel.activeFocus
    function focusAdd() { addLabel.forceActiveFocus(Qt.TabFocusReason) }
    function focusFill() { fill.focusFirst() }
    signal fillPicked(var entry)
    signal fillLeft()                       // Esc in the Fill rows: back to the page
    // shown when it is not the default zoom (Settings > Pages), 100 % unless set
    readonly property string zoomText: view && Math.abs(view.zoomFactor - (view.sites ? view.sites.defaultZoom : 1)) > 0.001 ? Math.round(view.zoomFactor * 100) + " %" : ""
    // Add to Thyris (src/webstore.*): on an extension's own page in the Chrome Web Store, a line of Thyris's own under the
    // address. The page offers only its id; nothing on it can draw or press this.
    readonly property string storeId: view ? view.storeItem ?? "" : ""
    readonly property string addLine: storeId === "" || stateLine !== "" || shownNotice !== null || ask !== null || lifted ? ""
                                      : (view.asks, WebStore.added(storeId)) ? "added" : view.extensionAsking ? "" : "add"
    readonly property int lineHeight: 40 + (stateLine !== "" || shownNotice !== null || addLine !== "" ? 14 : 0)

    width: parent ? parent.width : 280
    height: lineHeight + (ask ? section.height : (fillShown ? fill.height : 0) + (passwordNote ? note.height : 0))
    Behavior on height { Anim { type: Anim.StandardSmall } }

    // lifted: an outline in the 5 % wash, no text, swapped at once while the card covers the slot
    Rectangle {
        visible: field.lifted
        anchors.fill: parent
        radius: 10
        color: "transparent"
        border.width: 1
        border.color: Theme.transparentize(Theme.onSurface, 0.95)
    }
    Rectangle {
        id: card
        visible: !field.lifted
        anchors.fill: parent
        radius: 10
        border.width: 1
        border.color: Theme.transparentize(Theme.onSurface, 0.93)
        // the 5 % wash (6 % hovered) on the rail's slab, which is opaque docked and lifted (PLAN.md 3.19), so an ask, a
        // decision, never lies on frost
        color: Theme.transparentize(Theme.onSurface, restArea.containsMouse ? 0.94 : 0.95)
        Behavior on color { CAnim { hover: true } }
        // what grows in shows as the card opens over it
        clip: true

        // at rest: favicon slot, host, path elided in the middle; query and fragment hidden. Above
        // restArea, so the bell takes its own click.
        Item {
            z: 1
            width: parent.width
            height: 40

            // the slot is reserved: a globe (or the browser's own glyph for its pages and files) until the icon arrives,
            // busy while loading, ! on plain http and on a failure; a certificate's page holds its load without the busy glyph
            // back and forward live in the rail's top row (2026-10-09: in here they left the host too little room, and
            // browserbench.org showed as "…serbench.org"); on a failure reload tries again, as Ctrl+R does
            Image {
                id: favicon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                source: field.view ? (Engine.iconRevision, Engine.keptIcon(String(field.view.icon))) : ""
                visible: status === Image.Ready && !field.warned && !busy.visible
            }
            Busy {
                id: busy
                anchors.centerIn: favicon
                visible: field.view !== null && field.view.loading && !field.insecure && !(field.failure && field.failure.held)
            }
            Symbol {
                anchors.centerIn: favicon
                width: 16
                visible: !favicon.visible && !busy.visible
                text: field.warned ? "warning" : field.parts.glyph || "language"
                fill: RailRows.filled(text)
                iconSize: 16
                color: field.errorTone ? Theme.error : Theme.colSubtext
                opacity: field.view || field.insecure ? 1 : 0.38
            }
            // A web host too long for the card loses whole names from its start, never letters: accounts.google.com
            // shows as google.com, never "…ts.google.com" (2026-10-09). The last two names stay (three for a country's
            // second level, as bbc.co.uk), so whose site it is always shows; an address by number stays whole.
            FontMetrics { id: hostMetrics; font: hostText.font }
            readonly property string shownHost: {
                const host = field.view ? field.parts.host : "No page";
                const room = marks.x - 8 - 38;
                if (!field.view || !/^https?:/i.test(String(field.view.url)) || /^[\d.]+$|:/.test(host) || hostMetrics.advanceWidth(host) <= room)
                    return host;
                const names = host.split(".");
                const n = names.length;
                const keep = n >= 3 && names[n - 1].length === 2 && names[n - 2].length <= 3 ? 3 : 2;
                for (let i = 1; i < n - keep; i++) {
                    const shorter = names.slice(i).join(".");
                    if (hostMetrics.advanceWidth(shorter) <= room)
                        return shorter;
                }
                return names.slice(-keep).join(".");
            }
            Label {
                id: hostText
                anchors { left: parent.left; leftMargin: 38; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, marks.x - 8 - x)
                text: parent.shownHost
                // a site's own name too long even so loses its start, keeping its end
                elide: Text.ElideLeft
                font.pixelSize: Theme.font.body
                color: field.view ? Theme.colOnSurface : Theme.colSubtext
            }
            Label {
                anchors { left: hostText.right; leftMargin: field.insecure ? 8 : 3; right: marks.left; rightMargin: marks.width > 0 ? 8 : 0; verticalCenter: parent.verticalCenter }
                // at rest the place is its site (Tacit's sidebars, 2026-10-08); the whole address shows with Ctrl+L
                visible: field.insecure
                text: field.insecure ? "Not secure" : field.parts.path
                elide: Text.ElideMiddle
                font.pixelSize: field.insecure ? Theme.font.tiny : Theme.font.smaller
                color: field.insecure ? Theme.error : Theme.colSubtext
                opacity: field.insecure ? 1 : field.dim
            }
            // at the card's right: the site's zoom when not 100 % (12 px), the bell of a notification ask made
            // without a click (it brings the ask out), what an allowed permission keeps using this page load,
            // and popups refused this page load for want of a click (PLAN.md 8k; it opens the site panel's
            // Pop-ups row)
            IconButton {
                id: reloadButton
                objectName: "reloadButton"
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                glyph: field.view && field.view.loading ? "close" : "refresh"
                enabledState: field.view !== null
                onClicked: field.view.loading ? field.view.stop() : field.view.failure ? field.view.retry() : field.view.reload()
            }
            Row {
                id: marks
                anchors { right: reloadButton.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                spacing: 4
                Count {
                    visible: field.zoomText !== ""
                    height: 20
                    text: field.zoomText
                }
                Symbol {
                    objectName: "popupGlyph"
                    visible: field.view !== null && field.view.blockedPopups > 0
                    width: 20; height: 20
                    text: "web_asset_off"
                    iconSize: 16
                    color: popupArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                    Behavior on color { CAnim { hover: true } }
                    MouseArea { id: popupArea; anchors.fill: parent; enabled: parent.visible; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: field.siteClicked("popups") }
                }
                Symbol {
                    objectName: "bellGlyph"
                    visible: field.view !== null && !!field.view.quietAsk
                    width: 20; height: 20
                    text: "notifications"
                    iconSize: 16
                    color: bellArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                    Behavior on color { CAnim { hover: true } }
                    MouseArea { id: bellArea; anchors.fill: parent; enabled: parent.visible; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: field.view.unquiet() }
                }
                Repeater {
                    model: field.view ? Asks.glyphs(field.view.inUse) : []
                    delegate: Symbol {
                        required property string modelData
                        width: 20; height: 20
                        text: modelData
                        iconSize: 16
                    }
                }
            }
        }
        Label {
            visible: field.stateLine !== "" && field.shownNotice === null
            x: 12
            y: 31
            width: parent.width - 24
            text: field.stateLine
            font.pixelSize: Theme.font.smaller
            color: Theme.colSubtext
        }
        Label {
            id: addLabel
            objectName: "addExtension"
            z: 2
            activeFocusOnTab: true
            Keys.onPressed: event => {
                if (field.addLine === "add" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                    field.view.addFromStore();
                    Qt.callLater(() => field.focusAsk());
                    event.accepted = true;
                }
            }
            Rectangle {
                anchors { fill: parent; margins: -3 }
                z: -1
                visible: addLabel.activeFocus
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: Theme.colOnSurface
            }
            visible: field.addLine !== ""
            x: 12
            y: 31
            text: field.addLine === "added" ? "Added to Thyris · starts when Thyris reopens" : "Add to Thyris"
            font.pixelSize: Theme.font.smaller
            color: field.addLine === "add" && addArea.containsMouse ? Theme.colOnLayer0 : field.addLine === "add" ? Theme.colOnSurface : Theme.colSubtext
            Behavior on color { CAnim { hover: true } }
            MouseArea {
                id: addArea
                anchors { fill: parent; margins: -4 }
                enabled: field.addLine === "add"
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: field.view.addFromStore()
            }
        }
        // above restArea, so the action takes its own click
        Row {
            z: 2
            visible: field.shownNotice !== null
            x: 12
            y: 31
            spacing: 4
            Label {
                width: Math.min(implicitWidth, field.width - 24 - 40)
                text: field.shownNotice ? field.shownNotice.text : ""
                font.pixelSize: Theme.font.smaller
                color: Theme.colOnSurface
            }
            Label { visible: noticeAction.text !== ""; text: "·"; font.pixelSize: Theme.font.smaller; color: Theme.colSubtext }
            Label {
                id: noticeAction
                objectName: "noticeAction"
                text: field.shownNotice ? field.shownNotice.action ?? "" : ""
                font.pixelSize: Theme.font.smaller
                color: noticeArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
                Behavior on color { CAnim { hover: true } }
                MouseArea { id: noticeArea; anchors { fill: parent; margins: -4 } enabled: parent.text !== ""; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: field.noticeActed() }
            }
        }
        // the page's ask outranks the note: only one grown section shows
        AskSection {
            id: section
            y: field.lineHeight
            ask: field.ask
            count: field.view ? field.view.askCount : 0
            pageHost: field.parts.host
            onSiteSettings: type => field.siteClicked(type)
            onAnswered: (choice, data) => {
                const keys = section.activeFocus;
                field.view.answer(field.ask, choice, data);
                // the keys stay on the next ask, else go back to the page
                if (keys)
                    Qt.callLater(() => { if (field.ask) section.focusFirst(); else if (field.view) field.view.forceActiveFocus() });
            }
        }
        // the Fill rows, 32 px as the site panel's and the ask's; Up and Down move, Enter fills, Esc goes back to the page
        FocusScope {
            id: fill
            objectName: "fillRows"
            visible: field.fillShown
            y: field.lineHeight
            width: parent.width
            height: fillColumn.height + 8
            property int current: -1
            readonly property var rows: Logins.fillRows(field.logins)
            function focusFirst() {
                current = 0;
                forceActiveFocus(Qt.TabFocusReason);
            }
            onActiveFocusChanged: if (!activeFocus && !fillHover.hovered) current = -1
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up)
                    current = Math.max(0, Math.min(rows.length - 1, current + (event.key === Qt.Key_Down ? 1 : -1)));
                else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && rows[current])
                    field.fillPicked(rows[current].entry);
                else if (event.key === Qt.Key_Escape)
                    field.fillLeft();
                else
                    return;
                event.accepted = true;
            }
            Rectangle { width: parent.width; height: 1; color: Theme.transparentize(Theme.outlineVariant, 0.7) }
            Column {
                id: fillColumn
                x: 4
                y: 4
                width: parent.width - 8
                HoverHandler { id: fillHover; onHoveredChanged: if (!hovered && !fill.activeFocus) fill.current = -1 }
                Repeater {
                    model: fill.rows
                    delegate: SuggestionRow {
                        width: fillColumn.width
                        rowHeight: 32
                        titleSize: Theme.font.body
                        detailSize: Theme.font.caption
                        current: fill.current === index
                        onHovered: fill.current = index
                        onPicked: field.fillPicked(modelData.entry)
                        Rectangle {
                            visible: fill.activeFocus && parent.current
                            anchors { fill: parent; margins: -2 }
                            radius: Theme.rounding.verysmall + 2
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.primary
                        }
                    }
                }
            }
        }
        // a section under a hairline, as the card's other grown sections
        Item {
            id: note
            visible: field.passwordNote && !field.ask
            y: field.lineHeight + (field.fillShown ? fill.height : 0)
            width: parent.width
            height: noteText.implicitHeight + 20
            Rectangle { width: parent.width; height: 1; color: Theme.transparentize(Theme.outlineVariant, 0.7) }
            Label {
                id: noteText
                x: 12
                y: 9
                width: parent.width - 24
                text: "Passwords typed here are sent unencrypted"
                wrapMode: Text.Wrap
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
        LoadLine {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 10; rightMargin: 10; bottomMargin: 1 }
            view: field.view
        }
        // the address lines lift the card; its grown section keeps its own clicks
        MouseArea {
            id: restArea
            width: parent.width
            height: field.lineHeight
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onClicked: field.clicked()
        }
        // the favicon slot opens the site panel
        MouseArea {
            objectName: "favicon"
            x: 8
            width: 28
            height: 40
            enabled: field.view !== null
            cursorShape: Qt.PointingHandCursor
            onClicked: field.siteClicked("")
        }
    }
}
