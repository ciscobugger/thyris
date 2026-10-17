import QtQuick
import QtQuick.Controls

// The shell's StyledScrollBar: a 4 px pill, shown while scrolling or hovered, clear of rounded corners.
ScrollBar {
    id: bar
    policy: ScrollBar.AsNeeded
    topPadding: Theme.rounding.normal
    bottomPadding: Theme.rounding.normal
    active: hovered || pressed

    contentItem: Rectangle {
        implicitWidth: 4
        implicitHeight: bar.visualSize
        radius: width / 2
        color: Theme.onSurfaceVariant
        opacity: bar.policy === ScrollBar.AlwaysOn || (bar.active && bar.size < 1.0) ? 0.5 : 0
        Behavior on opacity { Anim { type: Anim.SlowEffects } }
    }
}
