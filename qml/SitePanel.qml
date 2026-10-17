import QtQuick
import "RailRows.js" as RailRows
import "Site.js" as Site

// The site panel (PLAN.md 3.9), as SiteInfo describes it: the host and its security line (› opens the
// certificate view in place, ‹ returns), then the site's rows. One row type throughout: label 14 px left,
// value 13 px colSubtext right, 32 px rows with a 10 % hover (22 % pressed), sections split by 30 % hairlines; a
// clicked value lays its choices out in the row, the picked one on the current row's 14 % wash. No popups and no filled switches. It
// lies over the rail's rows on its own opaque ground, grown from the address card's 40 px, in the pinned rail
// or folded in the overlay. Keys: Tab or Down and Backtab or Up move, Enter or Space picks, Esc folds the
// choices, then goes back, then closes. Leaving it closes it.
FocusScope {
    id: panel

    required property var info              // Main's SiteInfo
    property bool here: true                // the panel is open in this card (the pinned rail's or the overlay's)
    readonly property bool shown: here && visible && info.open
    function focusPanel() { forceActiveFocus() }

    implicitHeight: column.height
    height: shown ? implicitHeight : 40
    Behavior on height { Anim { type: Anim.StandardSmall } }
    clip: true

    // the window losing focus (switching to another app) is not leaving the panel
    onActiveFocusChanged: if (!activeFocus && shown && Window.active) info.hide()

    // the checks click through these: "site:<key>" for a row, "site:<key>=<value>" for a choice
    function target(name, item) {
        const at = item ?? column;
        if (at.objectName === name && at.visible)
            return at;
        for (const c of at.children) {
            const t = c.visible ? target(name, c) : null;
            if (t)
                return t;
        }
        return null;
    }
    function hits(item, out) {
        const list = out ?? [];
        for (const c of (item ?? column).children) {
            if (!c.visible)
                continue;
            if (c.objectName.startsWith("site:"))
                list.push(c);
            hits(c, list);
        }
        return list;
    }
    function move(delta) {
        const all = hits();
        if (all.length === 0)
            return;
        const at = all.findIndex(h => h.activeFocus);
        const next = at < 0 ? (delta > 0 ? 0 : all.length - 1) : (at + delta + all.length) % all.length;
        all[next].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    // After a pick with the keys the rows may change under the focused one: the keys go to `name`'s row.
    function refocus(name) {
        Qt.callLater(() => {
            const t = target(name);
            if (t && panel.activeFocus)
                t.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    function back() {
        if (info.expand !== "") {
            const key = info.expand;
            panel.forceActiveFocus();
            info.expand = "";
            refocus("site:" + key);
        } else if (info.sub !== "") {
            panel.forceActiveFocus();
            info.sub = "";
            refocus("site:all");
        } else {
            info.dismiss();
        }
    }
    Keys.onPressed: event => {
        if (!shown)
            return;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down)
            move(1);
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up)
            move(-1);
        else if (event.key === Qt.Key_Escape)
            back();
        else
            return;
        event.accepted = true;
    }

    // A click target: a row's value, a choice, ›, ‹, − and +. `keyed`: picked with the keys, which then stay
    // in the panel while the rows change.
    component Hit: Item {
        id: hit
        property string name
        property bool picked: false
        signal activated(bool keyed)
        objectName: name
        function pick() {
            const keyed = hit.activeFocus;
            if (keyed)
                panel.forceActiveFocus();
            hit.activated(keyed);
        }
        Keys.onReturnPressed: pick()
        Keys.onEnterPressed: pick()
        Keys.onSpacePressed: pick()
        Rectangle {
            anchors.fill: parent
            radius: Theme.rounding.verysmall
            color: area.pressed && area.containsMouse ? Theme.rowPressed : hit.picked ? Theme.rowCurrent
                 : area.containsMouse ? Theme.rowHover : Theme.transparentize(Theme.onSurface, 1)
            Behavior on color { CAnim { hover: true } }
        }
        // keyboard focus, the one place primary is used: 2 px, 2 px outside
        Rectangle {
            visible: hit.activeFocus
            anchors { fill: parent; margins: -2 }
            radius: Theme.rounding.verysmall + 2
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
        }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hit.pick() }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding.small
        color: Theme.over(Theme.transparentize(Theme.onSurface, 0.95), Theme.terminal)
        border.width: 1
        border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
    }
    // the rows under it take no clicks
    MouseArea { anchors.fill: parent }

    Column {
        id: column
        width: parent.width

        Repeater {
            // rows only where it shows (or shrinks back into the rail's card)
            model: panel.visible ? panel.info.rows : []
            delegate: Loader {
                required property var modelData
                readonly property var row: modelData
                width: column.width
                sourceComponent: ({ head: headKind, note: noteKind, split: splitKind, choice: choiceKind, count: countKind, link: linkKind,
                                    zoom: zoomKind, reader: readerKind, action: actionKind, back: backKind, pair: pairKind, text: textKind,
                                    title: titleKind, waiting: waitingKind })[modelData.kind] ?? null
            }
        }
        Item { width: 1; height: 4 }
    }

    // The host, 17 px Readex Pro, and its security line: in the error tone for Not secure and a certificate the
    // page was let past; › once the handshake has shown the certificate.
    Component {
        id: headKind
        Item {
            readonly property var row: parent.row
            width: parent.width
            height: row.plain ? 40 : 60
            Image {
                id: favicon
                x: 12
                y: 12
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                source: panel.info.view ? (Engine.iconRevision, Engine.keptIcon(String(panel.info.view.icon))) : ""
                visible: status === Image.Ready && panel.info.security.tone === ""
            }
            Symbol {
                anchors.centerIn: favicon
                width: 16
                visible: !favicon.visible
                text: panel.info.security.tone === "error" ? "warning" : "language"
                iconSize: 16
                color: panel.info.security.tone === "error" ? Theme.error : Theme.colSubtext
            }
            Label {
                x: 36
                y: 8
                width: parent.width - 48
                height: 24
                text: RailRows.split(panel.info.url).host
                elide: Text.ElideLeft
                font.family: Theme.font.titleFamily
                font.pixelSize: Theme.font.large
                color: Theme.colOnSurface
            }
            Hit {
                visible: !parent.row.plain
                name: panel.info.security.certificate ? "site:certificate" : ""
                enabled: panel.info.security.certificate
                x: 30
                y: 32
                width: parent.width - 36
                height: 24
                onActivated: keyed => { panel.info.sub = "certificate"; if (keyed) panel.refocus("site:back") }
                Label {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30
                    text: panel.info.security.text
                    font.pixelSize: Theme.font.caption
                    color: panel.info.security.tone === "error" ? Theme.error : Theme.colSubtext
                }
                Symbol {
                    visible: panel.info.security.certificate
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: "chevron_right"
                    iconSize: 16
                }
            }
        }
    }
    Component {
        id: noteKind
        Item {
            width: parent.width
            height: noteText.implicitHeight + 8
            Label {
                id: noteText
                x: 12
                width: parent.width - 24
                text: parent.parent.row.text
                wrapMode: Text.Wrap
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
    }
    Component {
        id: splitKind
        Item {
            width: parent.width
            height: 9
            Rectangle { y: 4; width: parent.width; height: 1; color: Theme.transparentize(Theme.outlineVariant, 0.7) }
        }
    }
    // a value; clicked, its choices in the row
    Component {
        id: choiceKind
        Item {
            id: choiceRow
            readonly property var row: parent.row
            readonly property bool out: panel.info.expand === row.key
            readonly property string picked: panel.info.choice(row.key)
            width: parent.width
            height: out ? 62 : 32
            Behavior on height { Anim { type: Anim.StandardSmall } }
            clip: true
            Hit {
                name: "site:" + choiceRow.row.key
                x: 4
                width: parent.width - 8
                height: 32
                onActivated: keyed => {
                    const key = choiceRow.row.key, was = choiceRow.out;
                    panel.info.expand = was ? "" : key;
                    if (keyed)
                        panel.refocus(was ? "site:" + key : "site:" + key + "=" + choiceRow.picked);
                }
                Label {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 16 - (rest.visible ? rest.implicitWidth + 8 : 0)
                    text: choiceRow.row.label
                    font.pixelSize: Theme.font.body
                }
                Label {
                    id: rest
                    visible: !choiceRow.out
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: Site.value(choiceRow.row.key, choiceRow.picked)
                    font.pixelSize: Theme.font.caption
                    color: Theme.colSubtext
                }
            }
            Row {
                visible: choiceRow.out
                x: 8
                y: 32
                spacing: 4
                Repeater {
                    model: Site.choices(choiceRow.row.key)
                    delegate: Hit {
                        required property var modelData
                        name: "site:" + choiceRow.row.key + "=" + modelData.value
                        picked: choiceRow.picked === modelData.value
                        width: choiceText.implicitWidth + 20
                        height: 26
                        onActivated: keyed => {
                            const key = choiceRow.row.key;
                            panel.info.set(key, modelData.value);
                            if (keyed)
                                panel.refocus("site:" + key);
                        }
                        Label {
                            id: choiceText
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            font.pixelSize: Theme.font.caption
                        }
                    }
                }
            }
        }
    }
    Component {
        id: countKind
        Item {
            width: parent.width
            height: 22
            Count {
                x: 12
                y: 0
                height: 16
                text: Site.blocked(panel.info.seen.blocked)
            }
        }
    }
    Component {
        id: linkKind
        Item {
            readonly property var row: parent.row
            width: parent.width
            height: 32
            Hit {
                name: "site:" + parent.row.key
                x: 4
                width: parent.width - 8
                height: 32
                onActivated: keyed => { panel.info.sub = parent.row.key; if (keyed) panel.refocus("site:back") }
                Label {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.row.label
                    font.pixelSize: Theme.font.body
                }
                Symbol {
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: "chevron_right"
                    iconSize: 16
                }
            }
        }
    }
    // − value +; Ctrl+Plus, Ctrl+Minus and Ctrl+0 set it too
    Component {
        id: zoomKind
        Item {
            width: parent.width
            height: 32
            Label {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.row.label
                font.pixelSize: Theme.font.body
            }
            Row {
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                spacing: 2
                Hit {
                    name: "site:zoom-out"
                    width: 28; height: 28
                    onActivated: panel.info.stepZoom(-1)
                    Symbol { anchors.centerIn: parent; text: "remove"; iconSize: 16 }
                }
                Label {
                    width: 44
                    height: 28
                    horizontalAlignment: Text.AlignHCenter
                    text: Site.zoomText(panel.info.zoom)
                    font.pixelSize: Theme.font.caption
                    font.features: { "tnum": 1 }
                    color: Theme.colSubtext
                }
                Hit {
                    name: "site:zoom-in"
                    width: 28; height: 28
                    onActivated: panel.info.stepZoom(1)
                    Symbol { anchors.centerIn: parent; text: "add"; iconSize: 16 }
                }
            }
        }
    }
    // Reader view (PLAN.md 3.9): a click puts the article in the page's place (the row on the picked wash while it
    // shows) or the page back; with no article it is a plain row, the label in colSubtext, that says so
    Component {
        id: readerKind
        Item {
            id: readerRow
            readonly property var row: parent.row
            readonly property bool off: panel.info.article === "none" && !panel.info.reading
            width: parent.width
            height: 32
            Hit {
                visible: !readerRow.off
                name: "site:reader"
                picked: panel.info.reading
                x: 4
                width: parent.width - 8
                height: 32
                onActivated: keyed => { panel.info.readerWanted(); if (keyed) panel.refocus("site:reader") }
            }
            Label {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: readerRow.row.label
                font.pixelSize: Theme.font.body
                color: readerRow.off ? Theme.colSubtext : Theme.colOnLayer0
            }
            Label {
                objectName: "readerValue"
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: Site.reader(panel.info.article)
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
    }
    // Clear (the cookie line's value), Undo and Copy PEM
    Component {
        id: actionKind
        Item {
            id: actionRow
            readonly property var row: parent.row
            readonly property bool valued: row.value !== undefined
            width: parent.width
            height: 32
            Label {
                visible: actionRow.valued
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: Site.cookies(panel.info.cookies)
                font.pixelSize: Theme.font.body
            }
            Hit {
                name: "site:" + actionRow.row.key
                x: actionRow.valued ? parent.width - width - 4 : 4
                width: actionRow.valued ? actionText.implicitWidth + 16 : parent.width - 8
                height: actionRow.valued ? 26 : 32
                anchors.verticalCenter: parent.verticalCenter
                onActivated: {
                    const key = actionRow.row.key;
                    if (key === "clear")
                        panel.info.startClear();
                    else if (key === "undo")
                        panel.info.undo();
                    else if (key === "pem")
                        panel.info.copyRequested(panel.info.tls.pem);
                }
                Label {
                    id: actionText
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: actionRow.valued ? actionRow.row.value : actionRow.row.label
                    font.pixelSize: actionRow.valued ? Theme.font.caption : Theme.font.body
                    color: actionRow.valued ? Theme.colSubtext : Theme.colOnLayer0
                }
            }
        }
    }
    // ‹ and the view's name, in the host's place
    Component {
        id: backKind
        Item {
            readonly property var row: parent.row
            width: parent.width
            height: 40
            Hit {
                name: "site:back"
                x: 4
                y: 4
                width: parent.width - 8
                height: 32
                onActivated: keyed => { panel.info.sub = ""; if (keyed) panel.refocus(parent.row.label === "Certificate" ? "site:certificate" : "site:all") }
                Symbol {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_left"
                    iconSize: 16
                }
                Label {
                    x: 28
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.row.label
                    font.pixelSize: Theme.font.body
                    weight: Font.DemiBold
                }
            }
        }
    }
    Component {
        id: pairKind
        Item {
            readonly property var row: parent.row
            width: parent.width
            height: 32
            Label {
                id: pairLabel
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: parent.row.label
                font.pixelSize: Theme.font.body
            }
            Label {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, parent.width - pairLabel.implicitWidth - 36)
                text: parent.row.value
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
    }
    Component {
        id: textKind
        Item {
            width: parent.width
            height: 32
            Label {
                x: 12
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.row.label
                font.pixelSize: Theme.font.body
            }
        }
    }
    Component {
        id: titleKind
        Item {
            width: parent.width
            height: 32
            Label {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: Site.countdown(Math.max(1, panel.info.left))
                font.pixelSize: Theme.font.body
            }
        }
    }
    // an ask waits until the panel closes
    Component {
        id: waitingKind
        Item {
            width: parent.width
            height: 28
            Label {
                x: 12
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.row.text
                font.pixelSize: Theme.font.smaller
                color: Theme.colOnSurface
            }
        }
    }
}
