import QtQuick
import "Settings.js" as Settings

// The rail's face while Settings is open (owner 2026-10-15, "docked from the rail"): the way back to the pages as the
// rail's top slab (Esc), the search, then the sections as Praxis's rows (inset 8 r 8 wash, the current one 10 % with the
// sand tick, a count at the right where a section holds some), About apart under them. The section opens as the sheet
// docked out of the rail's edge, level with its row (SettingsPage). Drawn by the rail, or folded by Settings itself.
Item {
    id: face

    required property var settings
    readonly property alias search: searchInput
    // where the sheet lines up: the current section's row, or the search's while words are searched for
    readonly property real anchorY: {
        if (settings.filter !== "")
            return searchRow.y;
        const i = settings.sections.filter(k => k !== "about").indexOf(settings.fold.key);
        return i >= 0 ? list.y + i * 36 : settings.fold.key === "about" ? about.y : searchRow.y;
    }

    // ‹ Settings: back to the page under the sheet
    Item {
        id: backSlab
        objectName: "settingsBack"
        x: 10
        width: parent.width - 20
        height: 36
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: backArea.pressed ? Theme.rowPressed : backArea.containsMouse ? Theme.transparentize(Theme.onSurface, 0.9) : Theme.transparentize(Theme.onSurface, 0.94)
            Behavior on color { CAnim { hover: true } }
        }
        Symbol {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_back"
            iconSize: 17
        }
        Label {
            x: 34
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            font.pixelSize: Theme.font.body
            weight: Font.Medium
            color: Theme.inkMain
        }
        Label {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: "Esc"
            font.pixelSize: Theme.font.smaller
            color: Theme.inkMeta
        }
        MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: face.settings.leave() }
    }

    // the search: a row like the sections', its words typed in place; the keys land here when Settings opens
    Item {
        id: searchRow
        y: backSlab.height + 12
        width: parent.width
        height: 36
        Rectangle {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
            radius: 8
            // washed as the current row while words are searched for; the caret alone says it has the keys
            color: face.settings.filter !== "" ? Theme.transparentize(Theme.onSurface, 0.9)
                 : searchArea.containsMouse ? Theme.transparentize(Theme.onSurface, 0.95) : Theme.transparentize(Theme.onSurface, 1)
            Behavior on color { CAnim { hover: true } }
        }
        Rectangle {
            visible: face.settings.filter !== ""
            x: 8
            y: 10
            width: 3
            height: 16
            radius: 1.5
            color: Theme.accent
        }
        Symbol {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "search"
            iconSize: 17
            color: searchInput.activeFocus ? Theme.inkMain : Theme.inkMeta
        }
        MouseArea { id: searchArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.IBeamCursor; onPressed: searchInput.forceActiveFocus() }
        TextInput {
            id: searchInput
            objectName: "own:filter"
            anchors { left: parent.left; leftMargin: 44; right: clearSearch.visible ? clearSearch.left : parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            clip: true
            text: face.settings.filter
            font.family: Theme.font.main
            font.hintingPreference: Font.PreferNoHinting
            font.pixelSize: Theme.font.body
            font.variableAxes: Theme.font.mainAxes
            color: Theme.inkMain
            selectionColor: Theme.transparentize(Theme.primary, 0.6)
            selectedTextColor: Theme.colOnLayer0
            selectByMouse: true
            renderType: Text.NativeRendering
            onTextEdited: { face.settings.expand = ""; face.settings.editing = ""; face.settings.filter = text }
            Keys.onReturnPressed: face.settings.move(1)
            Keys.onEnterPressed: face.settings.move(1)
            // Up and Down walk the sections; searching, they go on into what was found, as Tab does
            Keys.onUpPressed: face.settings.filter === "" && face.settings.sub === "" ? face.settings.stepSection(-1) : face.settings.move(-1)
            Keys.onDownPressed: face.settings.filter === "" && face.settings.sub === "" ? face.settings.stepSection(1) : face.settings.move(1)
            Keys.onTabPressed: face.settings.move(1)
            Keys.onBacktabPressed: face.settings.move(-1)
            Keys.onEscapePressed: event => { if (!face.settings.back(event.modifiers)) event.accepted = false }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: searchInput.text.length === 0
                text: "Search"
                font.pixelSize: Theme.font.body
                color: Theme.inkMeta
            }
        }
        // what was typed, gone in one press
        MouseArea {
            id: clearSearch
            visible: face.settings.filter !== ""
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 24
            height: 24
            cursorShape: Qt.PointingHandCursor
            onClicked: { face.settings.filter = ""; searchInput.forceActiveFocus() }
            Symbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 16
                color: Theme.inkMeta
            }
        }
    }

    // a section as a row of Praxis's rail (modules/claude/SessionList.qml)
    component FoldRow: Item {
        id: row
        property string foldKey
        readonly property var fold: Settings.folds.find(f => f.key === foldKey)
        readonly property bool current: face.settings.filter === "" && face.settings.fold.key === foldKey
        readonly property string count: Settings.foldCount(fold, face.settings.state)
        objectName: "side:" + foldKey
        width: face.width
        height: 36
        Rectangle {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
            radius: 8
            color: row.current ? Theme.transparentize(Theme.onSurface, 0.9)
                 : rowArea.containsMouse ? Theme.transparentize(Theme.onSurface, 0.95) : Theme.transparentize(Theme.onSurface, 1)
            Behavior on color { CAnim { hover: true } }
        }
        Rectangle {
            visible: row.current
            x: 8
            y: 10
            width: 3
            height: 16
            radius: 1.5
            color: Theme.accent
        }
        Symbol {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            text: row.fold.glyph
            iconSize: 17
            fill: row.current ? 1 : 0
            color: row.current ? Theme.inkMain : Theme.inkMeta
        }
        Label {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 44 - (countText.visible ? countText.width + 30 : 20)
            text: row.fold.title
            font.pixelSize: Theme.font.body
            weight: row.current ? Font.Medium : Theme.font.mainAxes.wght
            color: row.current || rowArea.containsMouse ? Theme.inkMain : Theme.inkSec
        }
        Label {
            id: countText
            visible: row.count !== ""
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            text: row.count
            font.pixelSize: Theme.font.smaller
            color: Theme.inkMeta
        }
        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: face.settings.openSection(row.foldKey) }
    }
    Column {
        id: list
        y: searchRow.y + searchRow.height + 8
        width: parent.width
        Repeater {
            // searching: the sections that hold what was found
            model: face.settings.sections.filter(k => k !== "about")
            delegate: FoldRow {
                required property string modelData
                foldKey: modelData
            }
        }
    }
    // About apart, a quiet line under the sections
    Item {
        id: about
        readonly property string foldKey: "about"
        readonly property bool current: face.settings.filter === "" && face.settings.fold.key === "about"
        objectName: "side:about"
        visible: face.settings.sections.indexOf("about") >= 0
        y: list.y + list.height + 10
        width: parent.width
        height: 32
        Rectangle {
            visible: about.current
            x: 8
            y: 8
            width: 3
            height: 16
            radius: 1.5
            color: Theme.accent
        }
        Label {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            text: "About Thyris"
            font.pixelSize: Theme.font.smaller
            color: about.current || aboutArea.containsMouse ? Theme.inkMain : Theme.inkMeta
        }
        MouseArea { id: aboutArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: face.settings.openSection("about") }
    }
}
