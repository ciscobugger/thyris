import QtQuick

// A glyph button: 28 px, a quiet wash on hover, dimmed when it cannot act; a toggle that is on (`picked`)
// keeps a 10 % wash.
Item {
    id: button

    property string glyph
    property bool enabledState: true
    property bool picked: false
    signal clicked()

    width: 28
    height: 28
    opacity: enabledState ? 1 : 0.38

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding.verysmall
        color: button.picked ? Theme.transparentize(Theme.onSurface, 0.9)
             : area.containsMouse && button.enabledState ? Theme.transparentize(Theme.onSurface, area.pressed ? 0.9 : 0.94) : "transparent"
        Behavior on color { CAnim { hover: true } }
    }
    Symbol {
        anchors.centerIn: parent
        text: button.glyph
        iconSize: 18
        color: (area.containsMouse || button.picked) && button.enabledState ? Theme.colOnLayer0 : Theme.colSubtext
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: button.enabledState ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (button.enabledState) button.clicked()
    }
}
