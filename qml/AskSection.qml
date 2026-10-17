import QtQuick
import "Asks.js" as Asks

// The browser's voice in the address card (PLAN.md 3.8): the page's shown ask under a hairline, worded
// by Asks.view(). AddressField grows it in the rail's card: the pinned rail's, or the overlay's, which it
// holds out while the rail is folded (PLAN.md 3.5). The page never draws here.
//   ask, count, pageHost     the ask (or null), the page's queue length ("1 of N"), the card's host
//   answered(choice, data)   data: { picked, <field key>: text }
//   siteSettings(type)       Site settings on an ask whose choice can last: the site panel, that type's row out
//   focusFirst()             F6: the keys on its first field or button; it never takes them itself
// Tab and Backtab move within it, Enter picks the focused button (in a field: the ask's submit), Esc
// picks the negative choice, Up and Down move the picked option. No button is the default, and an ask
// with options takes no other answer while none is picked.
FocusScope {
    id: section

    property var ask: null
    property int count: 0
    property string pageHost: ""
    property bool large: false      // in the page's ask sheet (AskSheet): the request at title size, taller buttons
    readonly property var model: ask ? Asks.view(ask, pageHost) : null
    property int picked: 0
    signal answered(string choice, var data)
    signal siteSettings(string type)
    // the site panel's row for the ask's lasting choice (PLAN.md 3.9), or "" for an ask that has none
    readonly property string settingsType: !ask ? "" : ask.kind === "permission" ? ask.types[0] ?? ""
                                                : ask.kind === "screen" ? "screen" : ask.kind === "external" && ask.app ? "app:" + ask.scheme : ""

    // Options change under a waiting ask as Chromium finds screens and windows: the pick stays with its
    // row, and goes when that row does, never falling back to another source.
    property int shownId: 0
    property var shownOptions: []
    onModelChanged: {
        const id = ask ? ask.id : 0, options = model ? model.options : [];
        if (id !== shownId) {
            picked = 0;
            if (id !== 0)
                arrived.restart();
        }
        else if (picked >= 0)
            picked = options.indexOf(shownOptions[picked]);
        shownId = id;
        shownOptions = options;
    }
    width: parent ? parent.width : 280
    height: model ? content.implicitHeight : 0
    visible: model !== null

    function values() {
        const d = { picked: picked };
        for (let i = 0; i < fields.count; i++)
            d[fields.itemAt(i).key] = fields.itemAt(i).input.text;
        return d;
    }
    function pick(choice) {
        if (!choice || choice !== model.negative && model.options.length > 0 && picked < 0)
            return;
        answered(choice, values());
    }
    function focusables() {
        const out = [];
        for (let i = 0; i < fields.count; i++)
            out.push(fields.itemAt(i).input);
        for (let i = 0; i < buttons.count; i++)
            out.push(buttons.itemAt(i));
        for (let i = 0; i < actions.count; i++)
            out.push(actions.itemAt(i).action);
        if (settings.visible)
            out.push(settings);
        return out;
    }
    function focusFirst() {
        const f = focusables();
        if (f.length > 0)
            f[0].forceActiveFocus(Qt.TabFocusReason);
    }
    function move(delta) {
        const f = focusables();
        if (f.length === 0)
            return;
        const at = f.findIndex(x => x.activeFocus);
        f[(at + delta + f.length) % f.length].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    // shots: a field as typed
    function fill(key, text) {
        for (let i = 0; i < fields.count; i++)
            if (fields.itemAt(i).key === key)
                fields.itemAt(i).input.text = text;
    }

    Keys.onPressed: event => {
        if (!model)
            return;
        if (event.key === Qt.Key_Tab)
            move(1);
        else if (event.key === Qt.Key_Backtab)
            move(-1);
        else if (event.key === Qt.Key_Escape)
            pick(model.negative);
        else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && model.options.length > 0)
            picked = Math.max(0, Math.min(model.options.length - 1, picked + (event.key === Qt.Key_Down ? 1 : -1)));
        else
            return;
        event.accepted = true;
    }

    component AskButton: TextButton {
        property string choice
        onPicked: section.pick(choice)
    }
    // a text action: 13 px subtext, full colour with the pointer or the keys on it; Tab reaches it
    component TextAction: Item {
        id: textAction
        property alias label: actionText.text
        signal picked()
        width: actionText.implicitWidth
        height: 18
        Keys.onReturnPressed: picked()
        Keys.onEnterPressed: picked()
        Keys.onSpacePressed: picked()
        Label {
            id: actionText
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Theme.font.caption
            color: actionArea.containsMouse || textAction.activeFocus ? Theme.colOnLayer0 : Theme.colSubtext
            Behavior on color { CAnim { hover: true } }
        }
        Rectangle {
            visible: textAction.activeFocus
            anchors { fill: parent; margins: -4 }
            radius: Theme.rounding.verysmall
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
        }
        MouseArea {
            id: actionArea
            anchors { fill: parent; margins: -4 }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: textAction.picked()
        }
    }

    FontMetrics { id: labelMetrics; font.family: Theme.font.main; font.pixelSize: Theme.font.caption; font.hintingPreference: Font.PreferNoHinting }
    readonly property real labelWidth: model ? Math.max(0, ...model.fields.map(f => labelMetrics.advanceWidth(f.label))) + 10 : 0

    Rectangle { visible: !section.large; width: parent.width; height: 1; color: Theme.transparentize(Theme.outlineVariant, 0.7) }
    // Found at a glance (the owner, 2026-10-16: the camera's ask was hard to find and read): one soft sand glow as an
    // ask arrives, and the sand tick beside the request while it waits, as Tacit marks the current row
    Rectangle {
        id: glow
        visible: !section.large         // the sheet's own slide out of the edge is its arrival
        anchors.fill: parent
        color: Theme.accent
        opacity: 0
        SequentialAnimation {
            id: arrived
            NumberAnimation { target: glow; property: "opacity"; from: 0; to: 0.22; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutCubic }
        }
    }
    Rectangle {
        x: section.large ? -14 : 4
        y: section.large ? 8 : 11
        width: 3
        height: section.large ? 20 : 16
        radius: 1.5
        color: Theme.accent
    }
    Column {
        id: content
        x: section.large ? 0 : 12
        width: parent.width - (section.large ? 0 : 24)
        topPadding: section.large ? 4 : 9
        bottomPadding: foot.visible ? 4 : 12

        // the request, 14 px; what follows it, 13 px colSubtext
        Repeater {
            model: section.model ? section.model.lines : []
            delegate: Label {
                required property var modelData
                required property int index
                width: content.width
                topPadding: index > 0 ? 2 : 0
                text: modelData.text
                wrapMode: Text.Wrap
                font.pixelSize: modelData.note ? Theme.font.caption : section.large ? Theme.font.title : Theme.font.body
                weight: modelData.note ? Theme.font.mainAxes.wght : Font.Medium
                color: modelData.note ? Theme.colSubtext : Theme.inkMain
            }
        }
        Item { width: 1; height: section.model && (section.model.fields.length > 0 || section.model.options.length > 0) ? 6 : 0 }
        Repeater {
            id: fields
            model: section.model ? section.model.fields : []
            delegate: Item {
                required property var modelData
                readonly property string key: modelData.key
                readonly property alias input: input
                width: content.width
                height: 34
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.label
                    font.pixelSize: Theme.font.caption
                    color: Theme.colSubtext
                }
                Rectangle {
                    x: section.labelWidth
                    width: parent.width - x
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.rounding.verysmall
                    color: Theme.terminal
                    border.width: 1
                    border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
                    TextInput {
                        id: input
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: parent.parent.modelData.secret ? TextInput.Password : TextInput.Normal
                        passwordCharacter: "•"
                        font.family: Theme.font.main
                        font.hintingPreference: Font.PreferNoHinting
                        font.pixelSize: Theme.font.body
                        color: Theme.colOnLayer0
                        selectionColor: Theme.transparentize(Theme.primary, 0.6)
                        selectedTextColor: Theme.colOnLayer0
                        selectByMouse: true
                        clip: true
                        onAccepted: section.pick(section.model.submit)
                    }
                }
            }
        }
        // one picked, on the current row's 14 % wash (hover is 10 %)
        Repeater {
            model: section.model ? section.model.options : []
            delegate: Rectangle {
                required property string modelData
                required property int index
                x: -4
                width: content.width + 8
                height: 32
                radius: Theme.rounding.verysmall
                color: optionArea.pressed && optionArea.containsMouse ? Theme.rowPressed : index === section.picked ? Theme.rowCurrent
                     : optionArea.containsMouse ? Theme.rowHover : Theme.transparentize(Theme.onSurface, 1)
                Behavior on color { CAnim { hover: true } }
                Label {
                    x: 4
                    width: parent.width - 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData
                    font.pixelSize: Theme.font.body
                }
                MouseArea { id: optionArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: section.picked = parent.index }
            }
        }
        Repeater {
            model: section.model ? section.model.notes : []
            delegate: Label {
                required property string modelData
                width: content.width
                topPadding: 2
                text: modelData
                wrapMode: Text.Wrap
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
        // an ask with only text actions (the password's) keeps them on its last line, under the request
        Item { width: 1; height: section.model && section.model.buttons.length > 0 ? (section.large ? 16 : 10) : 0 }
        Row {
            spacing: section.large ? 10 : 8
            Repeater {
                id: buttons
                model: section.model ? section.model.buttons : []
                delegate: AskButton {
                    required property var modelData
                    required property int index
                    label: modelData.label
                    choice: modelData.choice
                    // the first is the way on (Allow once, Sign in, Leave...): it fills more than the way back
                    restWash: index === 0 ? 0.16 : 0.05
                    height: section.large ? 38 : 32
                }
            }
        }
        // lasting choices (Site settings) or the ask's text actions, and the queue ("1 of 2")
        Item {
            id: foot
            visible: section.count > 1 || section.settingsType !== "" || actions.count > 0
            width: content.width
            height: 24
            TextAction {
                id: settings
                objectName: "siteSettings"
                visible: section.settingsType !== ""
                anchors.bottom: parent.bottom
                label: "Site settings"
                onPicked: section.siteSettings(section.settingsType)
            }
            Row {
                anchors.bottom: parent.bottom
                spacing: 6
                Repeater {
                    id: actions
                    model: section.model ? section.model.actions : []
                    delegate: Row {
                        required property var modelData
                        required property int index
                        readonly property alias action: act
                        spacing: 6
                        Label { visible: parent.index > 0; height: 18; verticalAlignment: Text.AlignVCenter; text: "·"; font.pixelSize: Theme.font.caption; color: Theme.colSubtext }
                        TextAction {
                            id: act
                            objectName: "askAction:" + parent.modelData.choice
                            label: parent.modelData.label
                            onPicked: section.pick(parent.modelData.choice)
                        }
                    }
                }
            }
            Count {
                visible: section.count > 1
                anchors { right: parent.right; bottom: parent.bottom }
                text: "1 of " + section.count
            }
        }
    }
}
