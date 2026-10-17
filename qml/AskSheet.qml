import QtQuick
import "Asks.js" as Asks

// The page's ask as a sheet docked out of the page's left edge, at the address card's height (the owner, 2026-10-16:
// the camera's ask in the card was hard to find and to read). Thyris's sheet silhouette (Cove, as Settings' sheet):
// the site above, the request large, its answers as big buttons, Site settings and the queue under them. It slides out
// of the edge as an ask arrives and back as the last one is answered. The card keeps the row's "camera?" mark only.
//   view, ask       the page's view and its shown ask (or null)
//   siteSettings(type)
Item {
    id: sheet

    property var view: null
    property var ask: null
    signal siteSettings(string type)
    readonly property alias section: section

    // the ask last shown, kept while the sheet slides back so it does not empty as it goes
    property var shown: null
    onAskChanged: if (ask) shown = ask
    property real slide: 0          // 0 in the edge .. 1 out
    states: State { when: sheet.ask !== null; PropertyChanges { sheet.slide: 1 } }
    transitions: Transition { Anim { property: "slide"; type: Anim.EmphasizedSmall } }

    width: 460
    height: column.implicitHeight
    visible: slide > 0.001
    transform: Translate { x: -(1 - sheet.slide) * (sheet.width + 24) }
    opacity: Math.min(1, sheet.slide * 1.6)

    Cove {
        anchors.fill: parent
        color: Theme.terminal
    }
    Column {
        id: column
        x: 26
        width: parent.width - 52
        topPadding: 20
        bottomPadding: 14
        // the site, in meta ink; the request under it says what it wants
        Row {
            width: parent.width
            spacing: 8
            // what it wants, as the page's row marks it (camera, microphone, location, screen)
            Symbol {
                readonly property var marks: sheet.shown && sheet.shown.kind === "permission" ? Asks.glyphs(sheet.shown.types) : []
                visible: marks.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: marks[0] ?? ""
                iconSize: 17
                color: Theme.inkMeta
            }
            Label {
                width: parent.width - 30
                text: sheet.shown ? sheet.shown.host || "This page" : ""
                elide: Text.ElideMiddle
                font.pixelSize: Theme.font.caption
                color: Theme.inkMeta
            }
        }
        AskSection {
            id: section
            large: true
            width: parent.width
            ask: sheet.ask ?? sheet.shown
            count: sheet.view ? sheet.view.askCount : 0
            // the site is above: the request reads "Wants to use your camera"
            pageHost: sheet.shown ? sheet.shown.host ?? "" : ""
            onSiteSettings: type => sheet.siteSettings(type)
            onAnswered: (choice, data) => {
                const keys = section.activeFocus;
                sheet.view.answer(sheet.ask, choice, data);
                if (keys)
                    Qt.callLater(() => { if (sheet.ask) section.focusFirst(); else if (sheet.view) sheet.view.forceActiveFocus() });
            }
        }
    }
}
