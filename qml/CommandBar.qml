import QtQuick
import QtQuick.Effects

// A new page (Ctrl+T, PLAN.md 3.3, 3.20): a card centred over the page, the input on top, then where the page
// will go; Tab flips between the predicted thread and a new one. The rail stays as it is while you type (no
// placeholder row: it would open the predicted task and move the rows). With no page open (3.4) the card is the
// page: no scrim, and it cannot be closed.
Item {
    id: bar

    required property var session
    required property var omni
    required property Item host             // the page area
    property bool resident: false           // no page open anywhere
    property bool opened: false
    property string target: ""              // "" = new thread
    property bool targetChosen: false       // after one Tab the choice sticks for this bar
    property var rows: []
    property int current: 0
    // as in the address card: only a pointer move after the bar opened makes a row current
    property var pointerAt: null
    function pointed(i, p) {
        const moved = pointerAt !== null && Math.abs(p.x - pointerAt.x) + Math.abs(p.y - pointerAt.y) > 0.5;
        pointerAt = p;
        if (moved)
            current = i;
    }
    readonly property string text: input.text
    readonly property string mode: omni.mode(input.text)
    // Esc keeps the text for 30 s in case the bar comes back
    property string kept: ""
    property double keptAt: 0

    signal go(string url, string thread, string name, bool background, string fallback)
    signal switchTo(string pageId)
    signal restore(string threadId)
    signal reopen(string closedId)          // a closed page @ found (PLAN.md 3.7)
    signal forgetRow(var row)               // Shift+Delete on a history row, a closed page or an Earlier thread
    signal undo()                           // Undo on "Forgot <title> · Undo"
    // Main's notice ({ text, action, kind }): a forget's undo shows on @'s last line (PLAN.md 3.7 7a)
    property var notice: null
    signal pageAction(string name)
    signal findOnPage(string text)          // the / prefix: find on the page on screen
    signal askPraxis(string question)       // the ? prefix: Praxis answers (Main.askPraxis)
    signal dismissed()

    parent: host
    anchors.fill: parent
    z: 20
    visible: opacity > 0
    opacity: opened ? 1 : 0
    Behavior on opacity { Anim { type: Anim.FastEffects } }

    // `thread`: New page here (a thread header's menu) fixes the destination
    function show(text, thread) {
        const again = text === undefined && kept !== "" && Date.now() - keptAt < 30000;
        targetChosen = !!thread;
        target = thread ?? "";
        input.text = text ?? (again ? kept : "");
        kept = "";
        refresh();
        pointerAt = null;
        opened = true;
        input.forceActiveFocus();
        input.cursorPosition = input.length;
    }
    function hide() {
        if (!opened)
            return;
        opened = false;
        dismissed();
    }
    // Esc, the scrim or focus elsewhere; with no page open the card stays
    function dismiss() {
        if (resident || !opened)
            return;
        kept = input.text;
        keptAt = Date.now();
        hide();
    }
    function refresh() {
        const typed = input.text.trim() !== "";
        rows = typed ? omni.suggest(input.text, session.currentPage, "bar") : omni.startRows();
        // with nothing typed Enter does nothing; Down picks a row
        current = typed && rows.length > 0 && rows[0].kind !== "label" ? 0 : -1;
        // omni.mode, not `mode`: that binding may not have caught up inside onTextChanged
        if (!targetChosen)
            target = omni.mode(input.text) === "" ? session.predictThread(input.text, target) : "";
    }
    // Tab: the predicted thread against a new thread; nothing to flip to when no thread is predicted
    function flip() {
        if (mode !== "")
            return;
        const next = target !== "" ? "" : session.predictThread(input.text, "");
        if (next === target)
            return;
        targetChosen = true;
        target = next;
    }
    function step(delta) {
        let i = current;
        do
            i += delta;
        while (i >= 0 && i < rows.length && rows[i].kind === "label");
        if (i >= 0 && i < rows.length)
            current = i;
    }
    // Enter opens and shows; Alt+Enter opens in the background; Shift+Enter opens it as a new task, whatever the line
    // says (PLAN.md 3.20). With no page open the card stays: what opens a page hides it, and a background open is shown;
    // / finds nothing then. Import from Zen (3.4) opens Settings at Import, where it runs.
    function activate(row, background, newTask) {
        if (!row || row.kind === "label" || row.kind === "stub" || row.kind === "find" && resident)
            return;
        if (row.kind === "import") {
            pageAction("import");
            return;
        }
        if (!resident)
            hide();
        if (row.kind === "find") {
            findOnPage(row.text);
            return;
        }
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
        else
            go(row.url, newTask ? "" : target, row.name, background && !resident, row.fallback ?? "");
    }
    // Shift+Delete: a history row; in @ also a closed page or an Earlier thread, with the undo on the last line
    function forget() {
        const row = rows[current];
        if (row && (row.kind === "history" || row.kind === "closed" || row.kind === "earlier")) {
            forgetRow(row);
            refresh();
        }
    }

    // what Tab would switch to
    readonly property string other: {
        session.revision;
        if (!bar.opened || mode !== "")
            return "";
        if (target !== "")
            return "new task";
        const alt = session.threadById(session.predictThread(input.text, ""));
        return alt ? alt.title : "";
    }
    // the destination line: a lead in colSubtext and a name in DemiBold
    readonly property var dest: {
        session.revision;
        if (mode !== "")
            return { lead: omni.modeLine(mode), name: "" };
        const t = session.threadById(target);
        if (t)
            return { lead: "New page in ", name: t.title || "this task" };
        if (targetChosen && input.text.trim() !== "")
            return { lead: "New task: ", name: input.text.trim() };
        if (resident && input.text === "")
            return { lead: "New task, named after the first page you open", name: "" };
        return { lead: "New task", name: "" };
    }
    // the line crossfades (120 ms) between two copies
    property bool destFlip: false
    readonly property string destKey: dest.lead + "\n" + dest.name
    onDestKeyChanged: {
        const back = destFlip ? destA : destB;
        back.lead = dest.lead;
        back.name = dest.name;
        destFlip = !destFlip;
    }
    Component.onCompleted: { destA.lead = dest.lead; destA.name = dest.name }

    // scrim: the terminal tone at 15 %, a plain rectangle over the page only; none when there is no page
    Rectangle {
        anchors.fill: parent
        color: Theme.transparentize(Theme.terminal, bar.resident ? 1 : 0.85)
        MouseArea { anchors.fill: parent; onClicked: bar.dismiss() }
    }

    component DestLine: Row {
        property string lead
        property string name
        visible: opacity > 0
        Behavior on opacity { Anim { type: Anim.FastEffects } }
        Label {
            id: leadText
            text: parent.lead
            font.pixelSize: Theme.font.caption
            color: Theme.colSubtext
        }
        Label {
            width: Math.min(implicitWidth, parent.width - leadText.width)
            text: parent.name
            font.pixelSize: Theme.font.caption
            weight: Font.DemiBold
            color: Theme.colOnSurface
        }
    }

    // the notch's sheet's lift: soft, low (the shell's colShadow)
    RectangularShadow {
        x: card.x; y: card.y; width: card.width; height: card.height
        radius: card.radius
        blur: 30
        offset: Qt.vector2d(0, 12)
        color: Theme.colShadow
        visible: card.visible && card.opacity > 0
        opacity: card.opacity
        cached: true
    }
    Frost {
        id: card
        // 680 wide, as the notch's sheet the owner chose the size of (2026-10-02; was 880)
        width: Math.min(680, parent.width - 120)
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.26) + (bar.opened ? 0 : 6)
        Behavior on y { Anim { type: Anim.StandardSmall } }
        height: head.height + (list.count > 0 ? list.height + 16 : 0) + (jumpFoot.visible ? jumpFoot.height : 0)
        Behavior on height { Anim { type: Anim.StandardSmall } }
        radius: Theme.rounding.large
        // the notch's own surface, opaque: the 88 % panel frost let the wallpaper through and read brown (2026-10-02)
        tint: Theme.surfaceContainerHigh
        solid: 1
        clip: true
        MouseArea { anchors.fill: parent }

        Column {
            id: head
            width: parent.width
            bottomPadding: 10

            // the input line never moves; results grow down
            Item {
                width: parent.width
                height: 60
                Symbol {
                    anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                    width: 20
                    text: "search"
                    iconSize: 20
                }
                TextInput {
                    id: input
                    anchors { left: parent.left; right: parent.right; leftMargin: 52; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    clip: true
                    font.family: Theme.font.main
                    font.hintingPreference: Font.PreferNoHinting
                    font.pixelSize: Theme.font.title
                    font.variableAxes: Theme.font.mainAxes
                    color: Theme.colOnLayer0
                    selectionColor: Theme.transparentize(Theme.primary, 0.6)
                    selectedTextColor: Theme.colOnLayer0
                    selectByMouse: true
                    renderType: Text.NativeRendering
                    onTextChanged: if (bar.opened) bar.refresh()
                    onActiveFocusChanged: if (!activeFocus) bar.dismiss()

                    Label {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        visible: input.text.length === 0
                        text: "Search or enter address"
                        font.pixelSize: Theme.font.title
                        color: Theme.colSubtext
                    }

                    Keys.onPressed: event => {
                        // hidden, it may still hold the focus: its keys do nothing
                        if (!bar.opened)
                            return;
                        if (event.key === Qt.Key_Escape)
                            bar.dismiss();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            bar.activate(bar.rows[bar.current], (event.modifiers & Qt.AltModifier) !== 0, (event.modifiers & Qt.ShiftModifier) !== 0);
                        else if (event.key === Qt.Key_Down)
                            bar.step(1);
                        else if (event.key === Qt.Key_Up)
                            bar.step(-1);
                        else if (event.key === Qt.Key_Tab)
                            bar.flip();
                        else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier))
                            bar.forget();
                        else
                            return;
                        event.accepted = true;
                    }
                }
            }

            // where the page will go
            Item {
                width: parent.width
                height: 22
                Symbol {
                    anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                    width: 16
                    text: "subdirectory_arrow_right"
                    iconSize: 16
                }
                Item {
                    anchors { left: parent.left; leftMargin: 52; right: tabHint.visible ? tabHint.left : parent.right; rightMargin: 12; top: parent.top; bottom: parent.bottom }
                    DestLine { id: destA; width: parent.width; anchors.verticalCenter: parent.verticalCenter; opacity: bar.destFlip ? 0 : 1 }
                    DestLine { id: destB; width: parent.width; anchors.verticalCenter: parent.verticalCenter; opacity: bar.destFlip ? 1 : 0 }
                }
                Row {
                    id: tabHint
                    readonly property string key: bar.mode === "jump" ? "Esc" : bar.mode === "" && bar.other !== "" ? "Tab" : ""
                    visible: key !== ""
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    KeyCap { key: tabHint.key; label: "" ; anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        width: Math.min(implicitWidth, 180)
                        text: bar.mode === "" ? bar.other : ""
                        font.pixelSize: Theme.font.smaller
                        color: Theme.colSubtext
                    }
                }
            }
            // the words that made the prediction
            Label {
                readonly property var words: { bar.session.revision; return bar.opened && bar.mode === "" && bar.target !== "" ? bar.session.sharedWords(input.text, bar.target) : [] }
                visible: words.length > 0
                x: 52
                width: parent.width - 72
                height: 20
                text: "shares: " + words.join(", ")
                font.pixelSize: Theme.font.smaller
                color: Theme.colSubtext
            }
        }


        Rectangle {
            visible: list.count > 0
            anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: 20; rightMargin: 20 }
            height: 1
            color: Theme.transparentize(Theme.onSurface, 0.94)
        }
        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 9; leftMargin: 8; rightMargin: 8 }
            height: Math.min(contentHeight, 8 * 40 + 2 * 28)
            interactive: contentHeight > height
            clip: true
            // the row draws `bar.current`; the view's own highlight, an invisible item, would glide after its current
            // item at 400 px/s for seconds after each change, a frame each time
            highlightFollowsCurrentItem: false
            model: bar.rows
            delegate: SuggestionRow {
                current: index === bar.current
                rowHeight: 40
                titleSize: Theme.font.body
                detailSize: Theme.font.smaller
                enterMark: true
                onHovered: at => bar.pointed(index, at)
                onPicked: bar.activate(modelData, false)
            }
        }

        // @ (PLAN.md 3.7 7a): what Enter does, and Shift+Delete, under a hairline; a forget's undo takes its place
        JumpFoot {
            id: jumpFoot
            visible: bar.mode === "jump"
            anchors.bottom: parent.bottom
            width: parent.width
            notice: bar.notice
            onUndo: bar.undo()
        }
    }

    // with no page open: what Ctrl+Shift+T would bring back
    Label {
        readonly property string name: { bar.session.revision; return bar.resident ? bar.session.reopenName() : "" }
        visible: name !== ""
        x: card.x + 4
        y: card.y + card.height + 20
        text: "Ctrl+Shift+T reopens " + name
        font.pixelSize: Theme.font.caption
        color: Theme.colSubtext
    }
}
