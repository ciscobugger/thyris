import QtQuick
import QtQuick.Controls as Controls

// A menu (PLAN.md 3.11): opens at the pointer and may cross onto the page, so its ground is the frost
// (the wallpaper, never the page): 50 % hairline, radius 12, 32 px rows, 14 px text, 12 px shortcuts. Entries come
// from RailRows.menu. Up/Down pick, Enter or Right opens, Left or Esc closes a submenu.
Controls.Popup {
    id: menu

    property var entries: []
    property int current: -1
    property var owner: null            // set on a submenu
    property var sub: null              // one level of submenu (Move to thread ›), set by the owner
    // false for a list that opens under the pointer (a folded task's pages, Rail.openStack): the keys stay where they are
    property bool takesKeys: true
    readonly property bool hovered: menuHover.hovered
    // entries with an `icon` (a page's favicon address) or `glyph` draw it in a 16 px slot before their text
    readonly property bool iconSlot: entries.some(e => e.icon !== undefined || e.glyph !== undefined)
    signal picked(string action, var arg)

    padding: 4
    margins: 6
    // as wide as the widest entry (Popup takes its width from the content, which fills the width)
    width: {
        let w = 200;
        for (const e of entries)
            if (!e.separator)
                w = Math.max(w, 12 + (iconSlot ? 24 : 0) + bodyMetrics.advanceWidth(e.text) + 32 + (e.sub ? 16 : smallMetrics.advanceWidth(e.shortcut ?? "")) + 12);
        return Math.ceil(w) + 2 * padding + 4;
    }
    FontMetrics { id: bodyMetrics; font.family: Theme.font.main; font.pixelSize: Theme.font.body; font.hintingPreference: Font.PreferNoHinting }
    FontMetrics { id: smallMetrics; font.family: Theme.font.main; font.pixelSize: Theme.font.smaller; font.hintingPreference: Font.PreferNoHinting }
    focus: takesKeys
    closePolicy: owner ? Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
                       : Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    onOpened: current = -1
    onClosed: if (sub && sub.opened) sub.close()

    enter: Transition { Anim { property: "opacity"; from: 0; to: 1; type: Anim.FastEffects } }
    exit: Transition { Anim { property: "opacity"; to: 0; type: Anim.FastEffects } }

    background: Frost {
        radius: Theme.rounding.small
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
        }
    }

    function pick(i) {
        const e = entries[i];
        if (!e || e.separator)
            return;
        if (e.sub) {
            openSub(i);
            return;
        }
        close();
        if (owner)
            owner.close();
        (owner ?? menu).picked(e.action, e.arg);
    }
    function openSub(i) {
        const row = repeater.itemAt(i);
        if (!sub)
            return;
        sub.entries = entries[i].sub;
        sub.parent = row;
        sub.x = row.width - 4;
        sub.y = -menu.padding;
        sub.open();
    }
    function step(delta) {
        let i = current;
        do
            i += delta;
        while (i >= 0 && i < entries.length && entries[i].separator);
        if (i >= 0 && i < entries.length)
            current = i;
    }

    contentItem: Column {
        id: column
        focus: menu.takesKeys
        HoverHandler { id: menuHover }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) menu.step(1);
            else if (event.key === Qt.Key_Up) menu.step(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) menu.pick(menu.current);
            else if (event.key === Qt.Key_Right && menu.entries[menu.current]?.sub) menu.openSub(menu.current);
            else if (event.key === Qt.Key_Left && menu.owner) menu.close();
            else return;
            event.accepted = true;
        }

        Repeater {
            id: repeater
            model: menu.entries
            delegate: Item {
                id: entry
                required property var modelData
                required property int index
                width: column.width
                height: modelData.separator ? 9 : 32

                Rectangle {
                    visible: entry.modelData.separator === true
                    anchors { left: parent.left; right: parent.right; leftMargin: -menu.padding; rightMargin: -menu.padding; verticalCenter: parent.verticalCenter }
                    height: 1
                    color: Theme.transparentize(Theme.outlineVariant, 0.5)
                }
                Rectangle {
                    visible: !entry.modelData.separator
                    anchors.fill: parent
                    radius: Theme.rounding.verysmall
                    color: area.pressed && area.containsMouse ? Theme.rowPressed
                         : menu.current === entry.index || (menu.sub && menu.sub.opened && menu.sub.parent === entry) ? Theme.transparentize(Theme.onSurface, 0.9)
                         : area.containsMouse ? Theme.rowHover : Theme.transparentize(Theme.onSurface, 1)
                }
                Image {
                    id: entryIcon
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    sourceSize: Qt.size(32, 32)
                    source: entry.modelData.icon ? (Engine.iconRevision, Engine.keptIcon(String(entry.modelData.icon))) : ""
                    visible: !entry.modelData.separator && status === Image.Ready
                }
                Symbol {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    visible: !entry.modelData.separator && menu.iconSlot && !entryIcon.visible
                    text: entry.modelData.glyph || "language"
                    iconSize: 16
                    color: Theme.colSubtext
                }
                Label {
                    id: text
                    visible: !entry.modelData.separator
                    anchors { left: parent.left; leftMargin: menu.iconSlot ? 36 : 12; right: hint.left; rightMargin: 24; verticalCenter: parent.verticalCenter }
                    text: entry.modelData.text ?? ""
                    font.pixelSize: Theme.font.body
                }
                Label {
                    id: hint
                    visible: !entry.modelData.separator && !entry.modelData.sub
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: entry.modelData.shortcut ?? ""
                    font.pixelSize: Theme.font.smaller
                    color: Theme.colSubtext
                }
                Symbol {
                    visible: !!entry.modelData.sub
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "chevron_right"
                    iconSize: 16
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    enabled: !entry.modelData.separator
                    hoverEnabled: true
                    onEntered: {
                        menu.current = entry.index;
                        if (entry.modelData.sub)
                            menu.openSub(entry.index);
                        else if (menu.sub && menu.sub.opened)
                            menu.sub.close();
                    }
                    onClicked: menu.pick(entry.index)
                }
            }
        }
    }
}
