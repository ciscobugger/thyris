import QtQuick
import "RailRows.js" as RailRows

// Find in page in the address card (PLAN.md 3.8 8e): the address slot becomes the find field, with the
// count at its right, and the host drops to a 12 px line beside ↑ ↓ Aa; under a hairline, "Also in this
// thread" (at most 3 pages, a click shows the first match there) and what was skipped. It lies over the
// rail's rows on its own opaque ground, grown from the card's 40 px, in the pinned rail or folded in the
// overlay. Keys: Enter, F3 or Down next; with Shift, or Up, previous; Alt+C match case; Esc closes. Leaving
// the field closes it too.
Item {
    id: card

    required property var finder
    property bool here: true                // find is open in this card (the pinned rail's or the overlay's)
    readonly property bool shown: here && visible && finder.open
    readonly property bool matched: finder.result !== null && finder.result.matches > 0
    readonly property bool section: finder.hits.length > 0 || finder.skipped !== ""
    readonly property alias hitRows: hitRepeater    // the engine check clicks one
    function focusInput(select) {
        input.text = finder.text;
        input.forceActiveFocus();
        if (select)
            input.selectAll();
        else
            input.cursorPosition = input.length;
    }

    implicitHeight: column.height
    height: shown ? implicitHeight : 40
    Behavior on height { Anim { type: Anim.StandardSmall } }
    clip: true

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

        // the find field on the address card's 40 px line, the search glyph in the favicon slot
        Item {
            width: parent.width
            height: 40
            Symbol {
                x: 12
                y: 12
                width: 16
                height: 16
                text: "search"
                iconSize: 16
            }
            TextInput {
                id: input
                anchors { left: parent.left; leftMargin: 36; right: countLabel.left; rightMargin: 8 }
                y: 20 - height / 2
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
                onTextChanged: if (card.shown) card.finder.setText(text)
                // the window losing focus (switching to another app) is not leaving find
                onActiveFocusChanged: if (!activeFocus && card.shown && !card.finder.jumping && Window.active) card.finder.hide()
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: "Find on this page"
                    font.pixelSize: Theme.font.body
                    color: Theme.colSubtext
                }
                Keys.onPressed: event => {
                    if (!card.shown)
                        return;
                    const back = (event.modifiers & Qt.ShiftModifier) !== 0;
                    if (event.key === Qt.Key_Escape)
                        card.finder.dismiss();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_F3)
                        card.finder.step(back);
                    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up)
                        card.finder.step(event.key === Qt.Key_Up);
                    else if (event.key === Qt.Key_C && (event.modifiers & Qt.AltModifier))
                        card.finder.toggleCase();
                    else if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
                        return;
                    event.accepted = true;
                }
            }
            Count {
                id: countLabel
                anchors { right: parent.right; rightMargin: 12 }
                y: 20 - height / 2
                text: card.finder.count
            }
        }

        // the host, and the controls
        Item {
            width: parent.width
            height: 30
            Label {
                anchors { left: parent.left; leftMargin: 36; right: controls.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: card.finder.view ? RailRows.card(String(card.finder.view.url), "").host : ""
                elide: Text.ElideLeft
                font.pixelSize: Theme.font.smaller
                color: Theme.colSubtext
            }
            Row {
                id: controls
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                IconButton { glyph: "arrow_upward"; enabledState: card.matched; onClicked: card.finder.step(true) }
                IconButton { glyph: "arrow_downward"; enabledState: card.matched; onClicked: card.finder.step(false) }
                IconButton { glyph: "match_case"; picked: card.finder.matchCase; onClicked: card.finder.toggleCase() }
            }
        }
        // 80 px in all, so over the pinned rail it covers + New page whole rather than half of it
        Item { width: 1; height: 10 }

        // the thread's other live pages with the words
        Rectangle {
            visible: card.section
            width: parent.width
            height: 1
            color: Theme.transparentize(Theme.outlineVariant, 0.7)
        }
        Label {
            visible: card.section
            x: 12
            height: 30
            text: "Also in this task"
            font.pixelSize: Theme.font.smaller
            weight: Font.DemiBold
            color: Theme.colSubtext
        }
        Repeater {
            id: hitRepeater
            model: card.finder.hits
            delegate: Item {
                id: hit
                required property var modelData
                width: column.width
                height: 28
                Rectangle {
                    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                    radius: Theme.rounding.verysmall
                    color: hitArea.pressed && hitArea.containsMouse ? Theme.rowPressed : hitArea.containsMouse ? Theme.rowHover : Theme.transparentize(Theme.onSurface, 1)
                    Behavior on color { CAnim { hover: true } }
                }
                Image {
                    id: hitIcon
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    sourceSize: Qt.size(32, 32)
                    source: (Engine.iconRevision, Engine.keptIcon(String(hit.modelData.icon)))
                    visible: status === Image.Ready
                }
                Symbol {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    visible: !hitIcon.visible
                    text: "language"
                    iconSize: 16
                }
                Label {
                    anchors { left: parent.left; leftMargin: 36; right: hitCount.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: hit.modelData.title
                    font.pixelSize: Theme.font.caption
                }
                Count {
                    id: hitCount
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: hit.modelData.count
                }
                MouseArea {
                    id: hitArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.finder.jumpTo(hit.modelData.pageId)
                }
            }
        }
        Label {
            visible: card.finder.skipped !== ""
            x: 12
            height: 28
            text: card.finder.skipped
            font.pixelSize: Theme.font.smaller
            color: Theme.colSubtext
        }
        // an ask waits until find closes
        Label {
            visible: card.finder.waiting !== ""
            x: 12
            width: parent.width - 24
            height: 28
            text: card.finder.waiting + " is asking  ·  after this"
            font.pixelSize: Theme.font.smaller
            color: Theme.colOnSurface
        }
        Item { width: 1; height: card.section || card.finder.waiting !== "" ? 4 : 0 }
    }
}
