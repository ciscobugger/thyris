import QtQuick

// One suggestion: favicon or glyph, title, a short detail on the right. Kind "label" is a section
// heading (12 px Medium, as the notch's sheet), never picked. @'s rows (PLAN.md 3.7 7a) mark the typed letters in DemiBold
// (`marks`: the words) and may say why they matched under the title (`lines`, 13 px colSubtext).
Rectangle {
    id: row

    required property var modelData
    required property int index
    property bool current: false
    property int rowHeight: 38
    property int titleSize: Theme.font.caption
    property int detailSize: Theme.font.smaller
    property bool enterMark: false          // ↵ on the row Enter picks
    readonly property bool label: modelData.kind === "label"
    readonly property var lines: modelData.lines ?? []
    signal picked()
    signal hovered(point at)                // the pointer on the row, `at` in the window


    width: ListView.view ? ListView.view.width : 0
    height: label ? 28 : rowHeight + (lines.length > 0 ? lines.length * 18 - 4 : 0)
    radius: Theme.rounding.verysmall
    // current (the pointer moves it too, so it is also the hover) 10 %, pressed 22 %
    color: label ? "transparent" : pressArea.pressed && pressArea.containsMouse ? Theme.rowPressed
         : current ? Theme.transparentize(Theme.onSurface, 0.9) : "transparent"

    Label {
        visible: row.label
        anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
        text: row.label ? row.modelData.title : ""
        font.pixelSize: Theme.font.tiny
        weight: Font.Medium
        color: Theme.colSubtext
    }

    // a row with neither favicon nor glyph (Copy link) starts its text in the glyph column
    readonly property bool bare: !row.modelData.icon && !row.modelData.glyph
    readonly property int textX: bare ? 10 : 36

    // the row's first line; what it says about why it matched goes under it
    Item {
        id: head
        width: parent.width
        height: row.rowHeight

        // an unloaded page's favicon at 50 %, 18 px as in the rail, centred on the 16 px glyphs' column
        Image {
            id: icon
            anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
            width: 18; height: 18
            sourceSize: Qt.size(36, 36)
            source: (Engine.iconRevision, Engine.keptIcon(String(row.modelData.icon ?? "")))
            visible: !row.label && status === Image.Ready
            opacity: row.modelData.dim ? 0.5 : 1
        }
        Symbol {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width: 16
            visible: !row.label && !icon.visible && !row.bare
            text: row.modelData.glyph ?? ""
            iconSize: text === "circle" ? 12 : 16
            opacity: row.modelData.dim ? 0.5 : 1
        }
        Marked {
            id: title
            visible: !row.label
            anchors { left: parent.left; leftMargin: row.textX; verticalCenter: parent.verticalCenter }
            width: Math.min(implicitWidth, parent.width - row.textX - 10 - (detail.text ? Math.min(detail.implicitWidth, 160) + 10 : 0) - (enter.visible ? 24 : 0))
            height: implicitHeight
            text: row.label ? "" : row.modelData.title
            words: row.modelData.marks ?? []
            pixelSize: row.titleSize
        }
        Label {
            id: detail
            visible: !row.label
            anchors { left: title.right; leftMargin: 10; right: enter.visible ? enter.left : parent.right; rightMargin: enter.visible ? 6 : 10; verticalCenter: parent.verticalCenter }
            horizontalAlignment: Text.AlignRight
            text: row.modelData.detail ?? ""
            font.pixelSize: row.detailSize
            font.features: { "tnum": 1 }
            color: Theme.colSubtext
        }
        Symbol {
            id: enter
            visible: row.enterMark && row.current && !row.label
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: "keyboard_return"
            iconSize: 16
        }
    }
    Column {
        x: row.textX + 16
        y: row.rowHeight - 8
        width: parent.width - x - 10
        Repeater {
            model: row.label ? [] : row.lines
            Marked {
                required property var modelData
                width: parent.width
                height: 18
                text: modelData.text
                words: row.modelData.marks ?? []
                pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
    }
    MouseArea {
        id: pressArea
        anchors.fill: parent
        enabled: !row.label
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // also as rows come under a resting pointer; the card tells a move by where it is in the window
        onEntered: row.hovered(mapToItem(null, mouseX, mouseY))
        onPositionChanged: mouse => row.hovered(mapToItem(null, mouse.x, mouse.y))
        onClicked: row.picked()
    }
}
