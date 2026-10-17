import QtQuick

// A button in the installer's language (setup.qml Act/Quiet, 2026-10-08): a pill drawn as a ring, no fill at rest.
// `tone`: "default" (the way forward, Enter: a 1.5 px ring in the theme's accent, its word in the main ink, Medium,
// and wider), "risk" (a quiet ring in the error colour, its word in that colour after a warning glyph) or "" (the
// quiet ring: 1 px of the main ink at 42 %, its word in the secondary ink). The item is always the forward ring's
// height, so quiet and forward rings centre on one line. Hover and focus lift it with a faint neutral fill; the ring
// stays. `small` is the dialog's size; `compact` the shell kit's size for app surfaces (its Slab.qml: 40/36 px), for
// the rail. Enter or Space picks it.
Item {
    id: slab
    property string text
    // kept for callers; the installer's rings draw no key cap (the page says what Enter does)
    property string key: ""
    property string tone: ""
    property bool small: false
    property bool compact: false
    // kept for callers: a ring needs no surface to measure from
    property color on: Theme.terminal
    signal picked()

    readonly property bool accent: tone === "default"
    readonly property bool risky: tone === "risk"
    readonly property bool lifted: area.containsMouse || activeFocus
    readonly property color ink: accent ? Theme.inkMain : risky ? Theme.risk : lifted ? Theme.inkMain : Theme.inkSec
    readonly property int forwardHeight: compact ? 40 : small ? 42 : 50
    readonly property int quietHeight: compact ? 36 : small ? 38 : 44

    implicitWidth: compact ? (accent ? Math.max(104, row.implicitWidth + 52) : row.implicitWidth + 36)
                 : accent ? Math.max(small ? 112 : 190, row.implicitWidth + (small ? 56 : 72)) : row.implicitWidth + (small ? 40 : 52)
    implicitHeight: forwardHeight
    width: implicitWidth
    height: implicitHeight
    activeFocusOnTab: true
    scale: area.pressed ? 0.97 : 1
    Behavior on scale { Anim { type: Anim.FastEffects } }
    Keys.onReturnPressed: slab.picked()
    Keys.onEnterPressed: slab.picked()
    Keys.onSpacePressed: slab.picked()

    Rectangle {
        width: parent.width
        height: slab.accent ? slab.forwardHeight : slab.quietHeight
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Theme.transparentize(Theme.inkMain, slab.activeFocus ? 0.91 : area.containsMouse ? 0.95 : 1)
        border.width: slab.accent ? 1.5 : 1
        border.color: slab.accent ? Theme.transparentize(Theme.accent, 0.25)
                    : slab.risky ? Theme.transparentize(Theme.risk, 0.45)
                    : Theme.transparentize(Theme.inkMain, 0.58)
        Behavior on color { CAnim { hover: true } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        // a risk is said by its glyph too, not by colour alone
        Symbol {
            visible: slab.risky
            anchors.verticalCenter: word.verticalCenter
            text: "warning"
            iconSize: slab.small || slab.compact ? 15 : 17
            color: slab.ink
        }
        Label {
            id: word
            text: slab.text
            font.pixelSize: slab.compact ? Theme.font.body : slab.accent ? (slab.small ? 15 : 17) : (slab.small ? 15 : 16)
            weight: slab.accent ? Font.Medium : Theme.font.mainAxes.wght
            color: slab.ink
            Behavior on color { CAnim { hover: true } }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: slab.picked()
    }
}
