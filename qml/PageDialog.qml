import QtQuick
import QtQuick.Controls as Controls

// A page's alert, confirm or prompt (PLAN.md 3.8 8j). It is the page speaking, so it is drawn in the page
// area and never in the address card: centred in the page area over a 40 % scrim on that page only (owner's
// pick, 2026-10-08, "A centred" of opsis-ux-batch1: docked to the top edge it read as a second notch and its
// 15 % scrim hardly showed), which keeps the page's clicks while it waits. The rail, other pages and the
// browser keep working. It takes the keys whenever its page is given them: Enter is OK, Esc is Cancel, Tab moves.
FocusScope {
    id: dialog

    property var view: null                  // the page whose `dialog` (BrowserView) shows here
    readonly property var model: view ? view.dialog : null
    // what shows, kept while it fades out
    property var shown: null
    onModelChanged: {
        if (!model)
            return;
        shown = model;
        input.text = model.text ?? "";
        if (view.activeFocus)
            Qt.callLater(take);
    }
    Connections {
        target: dialog.view
        function onActiveFocusChanged() { if (dialog.view.activeFocus && dialog.model) Qt.callLater(dialog.take) }
    }

    anchors.fill: parent
    z: 16
    visible: model !== null || opacity > 0
    opacity: model ? 1 : 0
    Behavior on opacity { Anim { type: Anim.FastEffects } }

    function take() {
        if (!model)
            return;
        if (model.type === "prompt") {
            input.forceActiveFocus();
            input.selectAll();
        } else {
            dialog.forceActiveFocus();
        }
    }
    function answer(ok) {
        const v = view, keys = dialog.activeFocus;
        if (!v || !v.dialog)
            return;
        v.answerDialog(ok, input.text);
        if (keys)
            v.forceActiveFocus();
    }
    function block() {
        const v = view, keys = dialog.activeFocus;
        if (!v || !v.dialog)
            return;
        v.blockDialogs();
        if (keys)
            v.forceActiveFocus();
    }
    function focusables() {
        const out = shown && shown.type === "prompt" ? [input] : [];
        for (let i = 0; i < buttons.count; i++)
            out.push(buttons.itemAt(i));
        if (blockLine.visible)
            out.push(blockLine);
        return out;
    }
    function move(delta) {
        const f = focusables();
        const at = f.findIndex(x => x.activeFocus);
        f[(at + delta + f.length) % f.length].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            answer(false);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            answer(true);
        else if (event.key === Qt.Key_Tab)
            move(1);
        else if (event.key === Qt.Key_Backtab)
            move(-1);
        else
            return;
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.transparentize(Theme.terminal, 0.6)
        MouseArea {
            anchors.fill: parent
            enabled: dialog.model !== null
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onPressed: dialog.take()
            onWheel: wheel => wheel.accepted = true
        }
    }

    // opaque terminal + onSurface 6 %, hairline 50 %, a little above the middle of the page area
    Rectangle {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) * 0.36)
        width: Math.min(520, parent.width - 96)
        height: content.implicitHeight + 1
        radius: Theme.rounding.normal
        color: Theme.over(Theme.transparentize(Theme.onSurface, 0.94), Theme.terminal)
        border.width: 1
        border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
        MouseArea { anchors.fill: parent; onPressed: dialog.take() }

        Column {
            id: content
            x: 24
            y: 1
            width: parent.width - 48
            topPadding: 24
            bottomPadding: 20

            // always the top frame's host over the message; all on the middle line, as the installer
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: dialog.shown ? dialog.shown.site : ""
                font.pixelSize: 15
                weight: Font.DemiBold
                color: Theme.inkMeta
            }
            Item { width: 1; height: 8 }
            // the page's text, 19 px; a long one scrolls
            Flickable {
                id: message
                width: parent.width
                height: Math.min(messageText.implicitHeight, Math.round(dialog.height * 0.5))
                contentHeight: messageText.implicitHeight
                interactive: contentHeight > height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: ThinScrollBar {}
                Label {
                    id: messageText
                    width: message.width
                    text: dialog.shown ? dialog.shown.message : ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    font.pixelSize: 19
                    lineHeight: 1.2
                    color: Theme.inkMain
                }
            }
            // prompt(): one 36 px field
            Item {
                visible: dialog.shown !== null && dialog.shown.type === "prompt"
                width: parent.width
                height: visible ? 48 : 0
                Rectangle {
                    y: 12
                    width: parent.width
                    height: 36
                    radius: Theme.rounding.verysmall
                    color: Theme.terminal
                    border.width: 1
                    border.color: Theme.transparentize(Theme.outlineVariant, 0.5)
                    TextInput {
                        id: input
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.font.main
                        font.hintingPreference: Font.PreferNoHinting
                        font.pixelSize: Theme.font.body
                        color: Theme.colOnLayer0
                        selectionColor: Theme.transparentize(Theme.primary, 0.6)
                        selectedTextColor: Theme.colOnLayer0
                        selectByMouse: true
                        clip: true
                        onAccepted: dialog.answer(true)
                    }
                }
            }
            Item { width: 1; height: 22 }
            // the answers
            Item {
                id: answers
                width: parent.width
                height: buttons.count > 0 ? buttons.itemAt(0).height : 0
                // the default last, at the right of the pair
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    Repeater {
                        id: buttons
                        // the default (Enter) on the right, in the accent
                        model: !dialog.shown ? [] : dialog.shown.type === "alert" ? [{ label: "OK", ok: true }]
                             : [{ label: "Cancel", ok: false }, { label: "OK", ok: true }]
                        delegate: Slab {
                            required property var modelData
                            text: modelData.label
                            small: true
                            tone: modelData.ok ? "default" : ""
                            key: modelData.ok ? "↵" : "Esc"
                            // the dialog moves the keys itself (move()), not Qt's tab chain
                            activeFocusOnTab: false
                            onPicked: dialog.answer(modelData.ok)
                        }
                    }
                }
            }
            // from the second dialog in a page load: a quiet line under the answers
            Item {
                id: blockLine
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dialog.shown !== null && dialog.shown.block !== ""
                width: blockText.implicitWidth
                height: visible ? 34 : 0
                Keys.onReturnPressed: dialog.block()
                Keys.onEnterPressed: dialog.block()
                Keys.onSpacePressed: dialog.block()
                Rectangle {
                    visible: blockLine.activeFocus
                    anchors { fill: parent; leftMargin: -4; rightMargin: -4 }
                    radius: Theme.rounding.verysmall
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.primary
                }
                Label {
                    id: blockText
                    anchors.bottom: parent.bottom
                    height: 24
                    text: dialog.shown ? dialog.shown.block : ""
                    font.pixelSize: 15
                    color: blockArea.containsMouse ? Theme.inkMain : Theme.inkMeta
                    Behavior on color { CAnim { hover: true } }
                }
                MouseArea { id: blockArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dialog.block() }
            }
        }
    }
}
