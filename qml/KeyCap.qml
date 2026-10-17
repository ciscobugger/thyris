import QtQuick

// A key and what it does, as the notch's sheet draws them: the key in a 20 px cap (onSurface 8 %, a 6 % edge), its
// word beside it in colSubtext. The card's and the bar's foot lines.
Row {
    property string key: ""
    property string label: ""
    spacing: 6
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        height: 20
        width: Math.max(20, cap.implicitWidth + 10)
        radius: 6
        color: Theme.transparentize(Theme.onSurface, 0.92)
        border.width: 1
        border.color: Theme.transparentize(Theme.onSurface, 0.94)
        Label {
            id: cap
            anchors.centerIn: parent
            text: parent.parent.key
            font.pixelSize: 11
            weight: Font.Medium
            color: Theme.colOnSurface
        }
    }
    Label {
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: parent.label
        font.pixelSize: Theme.font.smaller
        color: Theme.colSubtext
    }
}
