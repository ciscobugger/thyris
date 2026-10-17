import QtQuick

// @'s last line (PLAN.md 3.7 7a), in the new-page card and the address card: what Enter does, and that Shift+Delete
// forgets, under a 30 % hairline. For 6 s after a forget, "Forgot <title> · Undo" takes Shift+Delete's place.
// `jump` false: only that undo, at the right of the address card's typing line ("↵ here · Alt+↵ new page", 3.2 2b).
Item {
    id: foot

    property var notice: null               // Main's notice; only a forget's shows here
    property bool jump: true
    readonly property bool forgot: notice !== null && notice.kind === "forgot"
    signal undo()

    height: 37

    Rectangle { visible: foot.jump; width: parent.width; height: 1; color: Theme.transparentize(Theme.outlineVariant, 0.7) }
    Row {
        visible: foot.jump
        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: 1 }
        spacing: 4
        Symbol { text: "keyboard_return"; iconSize: 14; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "bring back · switch"; font.pixelSize: Theme.font.smaller; color: Theme.colSubtext }
    }
    Label {
        visible: foot.jump && !foot.forgot
        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: 1 }
        text: "Shift+Delete forget"
        font.pixelSize: Theme.font.smaller
        color: Theme.colSubtext
    }
    Row {
        visible: foot.forgot
        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: 1 }
        spacing: 4
        Label {
            width: Math.min(implicitWidth, foot.width / 2 - 40)
            text: foot.forgot ? foot.notice.text : ""
            font.pixelSize: Theme.font.smaller
            color: Theme.colOnSurface
        }
        Label { text: "·"; font.pixelSize: Theme.font.smaller; color: Theme.colSubtext }
        Label {
            objectName: "undo"
            text: foot.forgot ? foot.notice.action : ""
            font.pixelSize: Theme.font.smaller
            color: undoArea.containsMouse ? Theme.colOnLayer0 : Theme.colSubtext
            Behavior on color { CAnim { hover: true } }
            MouseArea { id: undoArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: foot.undo() }
        }
    }
}
