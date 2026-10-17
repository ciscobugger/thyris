import QtQuick
import Browser
import "Processes.js" as Processes
import "RailRows.js" as RailRows

// Pages and memory (PLAN.md 3.17, browser://pages, Shift+Esc or > Pages and memory), drawn over its page as OwnPage
// frames it: the browser's own processes, then each page process with its memory and its pages, then the pages with
// no process, in the site panel's row style. A page's row shows it (in its window); Unload unloads a page 30 min unseen
// would (not on screen, nothing holding it live, no ask waiting). Measured from /proc every 10 s while it is on screen
// (Processes.js says what).
OwnPage {
    id: pages

    // Main, the window this page is in: its memoryPages() (the profile's pages, as Processes.rows takes them), and its
    // show() and unloadPage() for what the rows ask. Not functions handed in as properties: in the release build three
    // arrow functions Main gave this page answered undefined without running (2026-10-01, Qt 6.11.2's qmlcachegen).
    property var owner: null
    property bool live: true                // false in shots: the shots set `measured`
    property var measured: ({ pages: [], processes: [], at: 0 })

    title: "Pages and memory"
    visible: view !== null
    readonly property var rows: Processes.rows(measured.pages, measured.processes, measured.at)

    function sample() {
        measured = { pages: owner ? owner.memoryPages() : [], processes: Facts.processes(), at: Date.now() };
    }
    Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: pages.visible && pages.live
        onTriggered: pages.sample()
    }
    function unload(id) {
        // the page is asked first (Main.unloadPage), and its process ends as it unloads: measured again once it has
        if (owner)
            owner.unloadPage(id, () => Qt.callLater(sample));
    }

    header: Label {
        width: pages.columnWidth
        height: 24
        x: 12
        text: pages.rows.length > 0 ? pages.rows[0].label : ""
        font.pixelSize: Theme.font.caption
        color: Theme.colSubtext
    }

    Repeater {
        model: pages.visible ? pages.rows.slice(1) : []
        delegate: Loader {
            required property var modelData
            required property int index
            readonly property var row: modelData
            readonly property bool atTop: index === 0
            width: pages.columnWidth
            sourceComponent: ({ head: headKind, process: processKind, page: pageKind })[modelData.kind] ?? null
        }
    }
    Item { width: 1; height: 16 }

    // a section: the browser's processes, a page process or the pages without one, and its memory
    Component {
        id: headKind
        Item {
            readonly property var row: parent.row
            objectName: row.key
            width: parent.width
            height: parent.atTop ? 32 : 52
            Label {
                anchors.bottom: parent.bottom
                height: 32
                width: parent.width - 24 - headValue.implicitWidth
                text: parent.row.label
                font.pixelSize: Theme.font.small
                weight: Font.DemiBold
            }
            Label {
                id: headValue
                anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom }
                height: 32
                text: parent.row.value
                font.pixelSize: Theme.font.caption
                font.features: { "tnum": 1 }
                color: Theme.colSubtext
            }
        }
    }
    Component {
        id: processKind
        Item {
            readonly property var row: parent.row
            width: parent.width
            height: 32
            Label {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: parent.row.label
                font.pixelSize: Theme.font.body
            }
            Label {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: parent.row.value
                font.pixelSize: Theme.font.caption
                font.features: { "tnum": 1 }
                color: Theme.colSubtext
            }
        }
    }
    // a page: favicon, title and its state; a click shows it; Unload where 30 min unseen would unload it
    Component {
        id: pageKind
        Item {
            id: pageRow
            readonly property var row: parent.row
            width: parent.width
            height: 32
            OwnHit {
                name: "own:" + pageRow.row.key
                scope: pages
                width: parent.width - (unloadHit.visible ? unloadHit.width + 8 : 0)
                height: 32
                onActivated: if (pages.owner) pages.owner.show(pageRow.row.ref)
                Image {
                    id: favicon
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    sourceSize: Qt.size(32, 32)
                    source: (Engine.iconRevision, Engine.keptIcon(String(pageRow.row.icon)))
                    visible: status === Image.Ready
                }
                // the globe, or the browser's own glyph for its pages and files, as in the rail
                Symbol {
                    anchors.centerIn: favicon
                    width: 16
                    visible: !favicon.visible
                    text: RailRows.card(pageRow.row.url ?? "", "").glyph || "language"
                    iconSize: 16
                }
                Label {
                    x: 36
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 48 - pageState.implicitWidth
                    text: pageRow.row.label
                    font.pixelSize: Theme.font.body
                }
                Label {
                    id: pageState
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: pageRow.row.value
                    font.pixelSize: Theme.font.caption
                    color: Theme.colSubtext
                }
            }
            OwnHit {
                id: unloadHit
                visible: pageRow.row.unload
                name: "own:" + pageRow.row.key + ":unload"
                scope: pages
                // its text ends where the values do, as Settings' actions
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                width: unloadText.implicitWidth + 16
                height: 26
                onActivated: keyed => { pages.unload(pageRow.row.ref); if (keyed) pages.refocus("own:" + pageRow.row.key) }
                Label {
                    id: unloadText
                    anchors.centerIn: parent
                    text: "Unload"
                    font.pixelSize: Theme.font.caption
                    color: Theme.colOnLayer0
                }
            }
        }
    }
}
