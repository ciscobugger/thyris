import QtQuick

// A click target on the browser's own pages, as the site panel's (SitePanel.qml): a row's value, a choice, an action.
// 10 % hover, 22 % while held, the picked choice on the current row's 14 %, radius 8; the focus ring (2 px primary,
// 2 px outside) for keys only. Enter, Return and Space pick it as a click does. Picked with the keys, the keys go to
// `scope` first, as the rows may change under this one (OwnPage.refocus brings them back).
Item {
    id: hit

    property string name
    property bool picked: false
    property Item scope: null
    property real radius: Theme.rounding.verysmall
    // a button's 1 px outline (Settings' buttons, as Tacit Settings' TextButton); its colour (Settings' way forward: the accent)
    property bool outlined: false
    property color outline: Theme.colOutlineVariant
    signal activated(bool keyed)

    objectName: name
    function pick() {
        const keyed = hit.activeFocus;
        if (keyed && scope)
            scope.forceActiveFocus();
        hit.activated(keyed);
    }
    Keys.onReturnPressed: pick()
    Keys.onEnterPressed: pick()
    Keys.onSpacePressed: pick()

    Rectangle {
        anchors.fill: parent
        radius: hit.radius
        border.width: hit.outlined ? 1 : 0
        border.color: hit.outline
        color: area.pressed && area.containsMouse ? Theme.rowPressed : hit.picked ? Theme.rowCurrent
             : area.containsMouse ? Theme.rowHover : Theme.transparentize(Theme.onSurface, 1)
        Behavior on color { CAnim { hover: true } }
    }
    Rectangle {
        visible: hit.activeFocus
        anchors { fill: parent; margins: -2 }
        radius: hit.radius + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hit.pick() }
}
