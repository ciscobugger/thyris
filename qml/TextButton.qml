import QtQuick

// A text button (PLAN.md 3.8): 32 px, radius 12, 5 % wash (8 % hovered), 30 % hairline, 14 px label, none
// filled or the default; the focus ring only for keys. Enter, Return and Space pick it as a click does. The
// browser's own pages set 36 px and a 6 % hover (8f).
Item {
    id: button

    property string label
    property real hoverWash: 0.08
    property real restWash: 0.05                // the fill at rest; an answer that is the way on (an ask's yes) fills more
    property real maxWidth: Number.MAX_VALUE    // a longer label elides
    signal picked()

    width: Math.min(buttonText.implicitWidth + 28, maxWidth)
    height: 32
    Keys.onReturnPressed: button.picked()
    Keys.onEnterPressed: button.picked()
    Keys.onSpacePressed: button.picked()

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding.small
        color: Theme.transparentize(Theme.onSurface, 1 - (buttonArea.containsMouse ? (button.restWash > 0.05 ? button.restWash + 0.04 : button.hoverWash) : button.restWash))
        Behavior on color { CAnim { hover: true } }
        border.width: 1
        border.color: Theme.transparentize(Theme.outlineVariant, 0.7)
    }
    Rectangle {
        visible: button.activeFocus
        anchors { fill: parent; margins: -2 }
        radius: Theme.rounding.small + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
    }
    Label {
        id: buttonText
        anchors.centerIn: parent
        width: implicitWidth > button.width - 28 ? button.width - 28 : undefined
        text: button.label
        font.pixelSize: Theme.font.body
    }
    MouseArea { id: buttonArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.picked() }
}
