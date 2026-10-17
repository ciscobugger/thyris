import QtQuick
import QtQuick.Effects
import "PageState.js" as PageState
import "RailRows.js" as RailRows

// Ctrl+L or a click on the rail's address (PLAN.md 3.2): the address card lifts out of its rail slot and
// grows into the Ctrl+T card's place over the page, in address mode. It morphs from `from` (the rail
// slot, or the folded edge's handle) on emphasized, its contents fading in over the last 150 ms; closing
// fades them out first, then it shrinks back. Enter loads here, Alt+Enter opens a new page in this
// thread, Esc or the scrim puts it back.
Item {
    id: field

    required property var session
    required property var omni
    required property Item host              // the page area: the scrim covers it, the card centres on it
    property var view: null                  // the current page's WebEngineView
    property var origin: null                // () => { x, y, width, height, radius, rest, ground } in this item's coordinates
    property string waiting: ""              // host of an ask that arrived while typing
    property bool editing: false             // open or opening
    readonly property bool out: editing || morph > 0
    property var rows: []
    property int current: 0
    // Rows that come under a resting pointer (the card opening, rows swapping per keystroke) report it too:
    // only a move after the card opened makes a row current, so Enter stays on row 1.
    property var pointerAt: null
    function pointed(i, p) {
        const moved = pointerAt !== null && Math.abs(p.x - pointerAt.x) + Math.abs(p.y - pointerAt.y) > 0.5;
        pointerAt = p;
        if (moved)
            current = i;
    }
    property bool touched: false             // typed into since Ctrl+L
    readonly property bool typed: touched && input.text.trim() !== ""
    readonly property string mode: typed ? omni.mode(input.text) : ""

    // load into the current page; `fallback`: the plain http address if https cannot connect (PLAN.md 3.8)
    signal navigate(string url, string fallback)
    signal openHere(string url, string name, string fallback) // Alt+Enter: a new page in this thread
    signal switchTo(string pageId)
    signal restore(string threadId)
    signal reopen(string closedId)           // a closed page @ found (PLAN.md 3.7)
    signal forgetRow(var row)                // Shift+Delete on a history row, a closed page or an Earlier thread
    signal undo()                            // Undo on "Forgot <title> · Undo"
    property var notice: null                // Main's notice: a forget's undo shows on @'s last line
    signal pageAction(string name)           // reload, print, reader, copy, markdown, always, close
    signal findOnPage(string text)           // the / prefix: find takes the card's place
    signal askPraxis(string question)        // the ? prefix: Praxis answers (Main.askPraxis)

    // on a failure (PLAN.md 8f-8h) the address that failed, with the card's "!"
    readonly property var failure: view ? view.failure ?? null : null
    // the browser's own pages as PLAN.md 3.17's table gives them, without the "/" the engine adds (browser://settings)
    readonly property string url: view ? (failure ? failure.url : String(view.url).replace(/^(browser:\/\/[a-z]+)\/$/i, "$1")) : ""
    readonly property bool insecure: !failure && PageState.insecure(url)
    readonly property bool warned: insecure || failure !== null || (view ? view.questioned ?? null : null) !== null
    readonly property bool errorTone: insecure || (view ? view.questioned ?? null : null) !== null || failure !== null && failure.tone === "error"

    anchors.fill: parent
    z: 30
    visible: out

    // 0 on its origin, 1 in place. The rest content (favicon, host, path) leaves in the first 120 ms, and
    // `frame` takes the card from its origin's look (tone, no hairline) to its own in the same 120 ms.
    property real morph: 0
    property real restOpacity: 0
    property real frame: 0
    property real bodyOpacity: 0
    property var from: ({ x: 0, y: 0, width: 0, height: 40, radius: Theme.rounding.small, rest: false, ground: Theme.terminal })
    readonly property int travel: Theme.anim.expressiveDefaultSpatialDuration
    // 680 wide, as the notch's sheet the owner chose the size of (2026-10-02; was 880)
    readonly property real toWidth: Math.min(680, host.width - 120)
    readonly property real toX: host.x + Math.round((host.width - toWidth) / 2)
    readonly property real toY: host.y + Math.round(host.height * 0.26)
    // rows change height (StandardSmall) once the card is in place; on the way it follows the morph
    property real fullHeight: body.implicitHeight
    Behavior on fullHeight { enabled: field.morph === 1; Anim { type: Anim.StandardSmall } }

    ParallelAnimation {
        id: openAnim
        Anim { target: field; property: "morph"; to: 1; type: Anim.DefaultSpatial }
        Anim { target: field; property: "restOpacity"; to: 0; type: Anim.FastEffects }
        Anim { target: field; property: "frame"; to: 1; type: Anim.FastEffects }
        SequentialAnimation {
            PauseAnimation { duration: field.travel - Theme.anim.expressiveFastEffectsDuration }
            Anim { target: field; property: "bodyOpacity"; to: 1; type: Anim.FastEffects }
        }
    }
    SequentialAnimation {
        id: closeAnim
        Anim { target: field; property: "bodyOpacity"; to: 0; type: Anim.FastEffects }
        ParallelAnimation {
            Anim { target: field; property: "morph"; to: 0; type: Anim.DefaultSpatial }
            SequentialAnimation {
                PauseAnimation { duration: field.travel - Theme.anim.expressiveFastEffectsDuration }
                ParallelAnimation {
                    Anim { target: field; property: "restOpacity"; to: field.from.rest ? 1 : 0; type: Anim.FastEffects }
                    Anim { target: field; property: "frame"; to: 0; type: Anim.FastEffects }
                }
            }
        }
    }

    // Ctrl+L: the current URL, all selected; with text: that text typed, caret at the end.
    property bool setting: false
    function open(text) {
        if (origin)
            from = origin();
        if (morph === 0) {
            restOpacity = from.rest ? 1 : 0;
            frame = 0;
        }
        setting = true;
        editing = true;
        pointerAt = null;
        touched = text !== undefined;
        input.text = text ?? url;
        setting = false;
        refresh();
        input.forceActiveFocus();
        // all of it selected with the caret at its start, so a long address shows from its site, not its tail (2026-10-09)
        if (text === undefined)
            input.select(input.length, 0);
        else
            input.cursorPosition = input.length;
        closeAnim.stop();
        openAnim.restart();
    }
    // back to the slot; the focus stays where it went
    function close() {
        if (!editing)
            return;
        if (origin)
            from = origin();
        openAnim.stop();
        closeAnim.restart();
        editing = false;
    }
    function cancel() {
        close();
        if (view)
            view.forceActiveFocus();
    }
    // Shots: the morph held at `p` of the way out, as one frame of the animation; `rest` 1 is the frame
    // where the rail card's contents are still (or again) all there.
    function pose(p, rest) {
        openAnim.stop();
        closeAnim.stop();
        if (origin)
            from = origin();
        morph = p;
        restOpacity = from.rest ? (rest ?? 0) : 0;
        frame = 1 - (rest ?? 0);
        bodyOpacity = 0;
    }
    // reads the text itself: `typed` may not have caught up inside onTextChanged
    function refresh() {
        rows = touched && input.text.trim() !== "" ? omni.suggest(input.text, session.currentPage, "address") : omni.pageRows(session.currentPage);
        current = -1;
        step(1);
    }
    function step(delta) {
        let i = current;
        do
            i += delta;
        while (i >= 0 && i < rows.length && rows[i].kind === "label");
        if (i >= 0 && i < rows.length)
            current = i;
    }
    // Enter loads here; Alt+Enter opens a new page in this thread.
    function activate(row, alt) {
        if (!row || row.kind === "label" || row.kind === "stub")
            return;
        if (row.kind === "find") {
            findOnPage(row.text);
            return;
        }
        cancel();
        if (row.kind === "praxis") {
            askPraxis(row.text);
            return;
        }
        if (row.kind === "page")
            switchTo(row.pageId);
        else if (row.kind === "earlier")
            restore(row.threadId);
        else if (row.kind === "closed")
            reopen(row.closedId);
        else if (row.kind === "action")
            pageAction(row.action);
        else if (alt)
            openHere(row.url, row.name, row.fallback ?? "");
        else
            navigate(row.url, row.fallback ?? "");
    }
    // Shift+Delete on a history row; in @ also a closed page or an Earlier thread (PLAN.md 3.7)
    function forget() {
        const row = rows[current];
        if (row && typed && (row.kind === "history" || row.kind === "closed" || row.kind === "earlier")) {
            forgetRow(row);
            refresh();
        }
    }

    // scrim: the terminal tone at 15 %, over the page only, as behind the Ctrl+T card
    Rectangle {
        parent: field.host
        anchors.fill: parent
        z: 19
        visible: field.out
        opacity: field.morph
        color: Theme.transparentize(Theme.terminal, 0.85)
        MouseArea { anchors.fill: parent; enabled: field.editing; onClicked: field.cancel() }
    }

    // the notch's sheet's lift: soft, low (the shell's colShadow), coming with the card
    RectangularShadow {
        x: card.x; y: card.y; width: card.width; height: card.height
        z: card.z
        radius: card.radius
        blur: 30
        offset: Qt.vector2d(0, 12)
        color: Theme.colShadow
        opacity: field.morph
        visible: field.out
        cached: true
    }
    Frost {
        id: card
        x: field.from.x + (field.toX - field.from.x) * field.morph
        y: field.from.y + (field.toY - field.from.y) * field.morph
        width: field.from.width + (field.toWidth - field.from.width) * field.morph
        height: field.from.height + (field.fullHeight - field.from.height) * field.morph
        radius: field.from.radius + (Theme.rounding.large - field.from.radius) * field.morph
        // It starts as the glass of the ground it lifts off (the rail's, under the rest content's own 5 % wash, or the
        // handle on it) and becomes the notch's own surface, opaque, as the Ctrl+T bar: the 88 % panel frost let the
        // wallpaper through and read brown (2026-10-02).
        tint: Theme.mix(Theme.surfaceContainerHigh, field.from.ground, field.frame)
        solid: field.frame
        clip: true
        MouseArea { anchors.fill: parent }

        // what the rail's card showed, leaving with it
        AddressField {
            width: field.from.width
            enabled: false
            visible: field.restOpacity > 0
            opacity: field.restOpacity
            omni: field.omni
            view: field.view
        }

        // laid out at the card's final width, so nothing reflows while it grows; stays visible at
        // opacity 0, as a hidden item cannot hold the focus
        Column {
            id: body
            width: field.toWidth
            opacity: field.bodyOpacity

            // the full URL wraps onto up to 4 lines, so it reads without sideways scrolling
            Item {
                id: head
                width: parent.width
                height: Math.max(60, scroller.height + 34)

                Image {
                    id: favicon
                    x: 22
                    y: scroller.y + (input.lineHeight - 16) / 2
                    width: 16; height: 16
                    sourceSize: Qt.size(32, 32)
                    source: field.view ? (Engine.iconRevision, Engine.keptIcon(String(field.view.icon))) : ""
                    visible: status === Image.Ready && !field.warned && !field.typed
                }
                // typing: the search glyph, as the bar and the notch's sheet; the page's favicon until then
                Symbol {
                    anchors.centerIn: favicon
                    width: 20
                    visible: !favicon.visible
                    text: field.typed ? "search" : field.warned ? "warning" : RailRows.card(field.url, "").glyph || "language"
                    fill: RailRows.filled(text)
                    iconSize: 20
                    color: field.errorTone ? Theme.error : Theme.colSubtext
                }

                Flickable {
                    id: scroller
                    x: 52
                    width: parent.width - 52 - 20
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.min(input.contentHeight, 4 * input.lineHeight)
                    contentHeight: input.contentHeight
                    interactive: false
                    clip: true
                    // keep the caret in view past 4 lines
                    function follow(r) {
                        if (r.y < contentY)
                            contentY = r.y;
                        else if (r.y + r.height > contentY + height)
                            contentY = r.y + r.height - height;
                    }

                    TextEdit {
                        id: input
                        readonly property real lineHeight: lineCount > 0 ? contentHeight / lineCount : 22
                        width: scroller.width
                        // an address breaks evenly at the edge (at its hyphens it left ragged lines); words typed stay whole
                        wrapMode: /\s/.test(text) ? TextEdit.Wrap : TextEdit.WrapAnywhere
                        font.family: Theme.font.main
                        font.hintingPreference: Font.PreferNoHinting
                        font.pixelSize: Theme.font.title
                        font.variableAxes: Theme.font.mainAxes
                        color: Theme.colOnLayer0
                        selectionColor: Theme.transparentize(Theme.primary, 0.78)
                        selectedTextColor: Theme.colOnLayer0
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        renderType: Text.NativeRendering
                        onCursorRectangleChanged: scroller.follow(cursorRectangle)
                        onTextChanged: {
                            if (!field.editing || field.setting)
                                return;
                            // a pasted line break would make a second line of address
                            if (/[\r\n]/.test(text)) {
                                text = text.replace(/[\r\n]+/g, " ");
                                cursorPosition = length;
                                return;
                            }
                            field.touched = true;
                            field.refresh();
                        }
                        // the window losing focus (switching to another app) is not leaving the card
                        onActiveFocusChanged: if (!activeFocus && field.editing && Window.active) field.close()
                        Keys.onPressed: event => {
                            if (!field.editing)
                                return;
                            if (event.key === Qt.Key_Escape)
                                field.cancel();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                field.activate(field.rows[field.current], (event.modifiers & Qt.AltModifier) !== 0);
                            else if (event.key === Qt.Key_Down)
                                field.step(1);
                            else if (event.key === Qt.Key_Up)
                                field.step(-1);
                            else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier))
                                field.forget();
                            else if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
                                return;
                            event.accepted = true;
                        }
                    }
                }
            }

            Rectangle {
                visible: list.count > 0
                x: 20
                width: parent.width - 40
                height: 1
                color: Theme.transparentize(Theme.onSurface, 0.94)
            }
            Item { width: 1; height: list.count > 0 ? 6 : 0 }
            ListView {
                id: list
                x: 8
                width: parent.width - 16
                // whatever the card's other lines leave above the window's foot
                height: Math.min(contentHeight, 8 * 40 + 3 * 28, field.host.height * 0.8 - 24 - head.height - footer.height - 17)
                interactive: contentHeight > height
                clip: true
                // the row draws `field.current`; the view's own highlight, an invisible item, would glide after its
                // current item at 400 px/s for seconds after each change, a frame each time
                highlightFollowsCurrentItem: false
                model: field.rows
                delegate: SuggestionRow {
                    current: index === field.current
                    rowHeight: 40
                    titleSize: Theme.font.body
                    detailSize: Theme.font.smaller
                    // untouched, row 1 already reads "↵ Reload this page"
                    enterMark: field.typed
                    onHovered: at => field.pointed(index, at)
                    onPicked: field.activate(modelData, false)
                }
            }
            Item { width: 1; height: list.count > 0 ? 8 : 0 }

            Column {
                id: footer
                width: parent.width
                bottomPadding: 4
                // @: what Enter does and Shift+Delete, as on the new-page card (PLAN.md 3.7 7a)
                JumpFoot {
                    visible: field.mode === "jump"
                    width: parent.width
                    notice: field.notice
                    onUndo: field.undo()
                }
                // typing: where Enter and Alt+Enter put the page
                Item {
                    visible: field.mode !== "jump"
                    width: parent.width
                    height: 36
                    Row {
                        visible: field.typed && field.mode === ""
                        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                        spacing: 18
                        KeyCap { key: "↵"; label: "here" }
                        KeyCap { key: "Alt ↵"; label: "new page" }
                    }
                    KeyCap {
                        visible: field.mode !== "jump"
                        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                        key: "Esc"
                        label: "back"
                    }
                    // Shift+Delete on a history row: its undo for 6 s (PLAN.md 3.7), as @'s last line has it
                    JumpFoot {
                        anchors.fill: parent
                        visible: field.typed && field.mode === ""
                        jump: false
                        notice: field.notice
                        onUndo: field.undo()
                    }
                    // the only place the prefixes are taught; in a prefix, what it does
                    Row {
                        visible: !field.typed && field.mode === ""
                        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                        spacing: 18
                        KeyCap { key: "/"; label: "find" }
                        KeyCap { key: ">"; label: "actions" }
                        KeyCap { key: "?"; label: "ask"; visible: field.omni.praxisHere }
                        KeyCap { key: "@"; label: "jump" }
                    }
                    Label {
                        visible: field.mode !== ""
                        anchors { left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 96; verticalCenter: parent.verticalCenter }
                        text: field.omni.modeLine(field.mode)
                        elide: Text.ElideRight
                        font.pixelSize: Theme.font.smaller
                        color: Theme.colSubtext
                    }
                }
                // an ask waits until the typing is done
                Label {
                    visible: field.waiting !== ""
                    x: 20
                    width: parent.width - 40
                    height: 28
                    text: field.waiting + " is asking  ·  after this"
                    font.pixelSize: Theme.font.smaller
                    color: Theme.colOnSurface
                }
            }
        }
    }
}
