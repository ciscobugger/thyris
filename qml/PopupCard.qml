import QtQuick

// An attached sign-in or payment popup's contents (PLAN.md 3.8 8k) as the notch shows them
// (~/book4-edge/signin-notch-plan.md): the page alone, its dialogs and its failure page over it. The shell draws its
// host, the way back and its asks. Main hosts it in the popup window. Until 2026-10-14 it also had a two-line header,
// for the popup's own floating window, which is gone.
Item {
    id: card

    property var view: null                  // the popup's WebEngineView, parented to pageSlot
    readonly property Item pageSlot: slot
    readonly property var failure: view ? view.failure ?? null : null

    signal closeClicked()
    signal failurePicked(string action)     // an action on the popup's failure page (Main.failureAction)

    Item {
        id: slot
        anchors.fill: parent
        PageDialog { view: card.view }
        FailurePage { view: card.view; page: card.failure; onPicked: action => card.failurePicked(action) }
        // a key the page left unhandled: Esc is the way back
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
                event.accepted = true;
                card.closeClicked();
            }
        }
    }
}
