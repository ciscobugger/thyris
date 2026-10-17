import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import QtQuick.Pdf
import QtQuick.Window
import QtWebEngine
import Browser
import "Print.js" as Print

// Print (PLAN.md 3.16; Ctrl+P, > Print): a card in the Ctrl+T card's place and material (frost, radius 23), over a 15 %
// scrim on the page, as you called it up. On the left the page's preview, its PDF (Printing.toPdf) drawn by QtPdf at
// radius 12, and its pages under it; on the right "Print <title>" and the rows in the site panel's style, each ›
// listing its choices in place (‹ goes back). A change makes a new preview 300 ms later. Save writes the PDF into the
// downloads folder, which Main lists under the page as a download (saved); Print sends it to a CUPS printer and the
// card closes, "Sent to <printer>" then in the address card (notice). Keys: Tab or Down and Backtab or Up move, Enter
// or Space picks, Left and Right turn the preview's pages, Enter anywhere else saves or prints, Esc goes back, then
// cancels.
FocusScope {
    id: card

    required property Item host             // the page area
    property bool live: true                // false in shots: no PDF is made, they set `preview`
    property string folder: ""              // where Save puts the PDF (Main's downloadFolder)
    property bool opened: false
    property var view: null                 // the page's BrowserView
    property string pageId: ""
    property string title: ""
    property string pageHost: ""            // the page's host, for a page with no title
    property var settings: Print.defaults()
    property string sub: ""                 // the row whose choices are listed in place
    property var printers: []               // CUPS's
    property int page: 1                    // the page the preview shows
    property string preview: ""             // the preview's file
    property bool previewFailed: false
    // the preview's document, while there is a file (an empty source fails to open)
    readonly property var doc: { preview; return sheets.count > 0 && sheets.itemAt(0) ? sheets.itemAt(0).doc : null }
    readonly property int count: doc && doc.status === PdfDocument.Ready ? doc.pageCount : 0
    readonly property var facts: ({ printers: printers, page: page, count: count })

    signal saved(string pageId, string path)
    signal notice(string text, int ms)      // for the address card: "Sent to <printer>", or why nothing was
    signal dismissed(bool keys)             // closed; `keys`: it had them, and the page takes them back

    parent: host
    anchors.fill: parent
    z: 21
    visible: opacity > 0
    opacity: opened ? 1 : 0
    Behavior on opacity { Anim { type: Anim.FastEffects } }

    // `v`: the BrowserView on screen, `id` its page
    function show(v, id, name, host) {
        view = v;
        pageId = id;
        title = name;
        pageHost = host;
        settings = Print.defaults();
        sub = "";
        page = 1;
        previewFailed = false;
        opened = true;
        card.forceActiveFocus();
        Printing.findPrinters();
        // a print that follows a change of the page's backgrounds setting can come before the page has it (measured):
        // the first preview then waits as a change does
        if (backgrounds())
            later.restart();
        else
            render();
    }
    function hide() {
        if (!opened)
            return;
        const keys = card.activeFocus;
        opened = false;
        sub = "";
        later.stop();
        queued = queued.filter(q => q.kind !== "preview");
        // the document goes before its file
        const shown = preview;
        preview = "";
        if (shown && live)
            Printing.remove(shown);
        dismissed(keys);
    }
    // Esc on the rows, the scrim, Cancel
    function back() {
        if (sub !== "") {
            const key = sub;
            card.forceActiveFocus();
            sub = "";
            refocus("print:" + key);
        } else {
            hide();
        }
    }
    function set(key, value) {
        settings = Object.assign({}, settings, { [key]: value });
        backgrounds();
        // the destination and the pages change what is sent, not the preview
        if (key !== "destination" && key !== "pages")
            later.restart();
    }
    // Backgrounds, as the page's printElementBackgrounds (Chromium reads it when it prints); true when it changed
    function backgrounds() {
        const on = settings.backgrounds === "on";
        if (!live || !view || view.settings.printElementBackgrounds === on)
            return false;
        view.settings.printElementBackgrounds = on;
        return true;
    }
    // A row's ›, or one of its choices picked. The rows change under the one clicked, which goes with them, so this runs
    // here and not in the row. `keyed`: picked with the keys, which then go to the choice picked, or back to the row.
    function openRow(key, keyed) {
        const picked = settings[key];
        sub = key;
        if (keyed)
            refocus("print:" + key + "=" + picked);
    }
    function pick(key, value, keyed) {
        set(key, value);
        sub = "";
        if (keyed)
            refocus("print:" + key);
    }
    function turn(delta) {
        page = Math.max(1, Math.min(count, page + delta));
    }
    onCountChanged: if (count > 0 && page > count) page = count

    // One PDF at a time: Chromium refuses a print while another runs. `job`: { kind ("preview", "save", "print"), view,
    // path, options, serial }; what is asked for meanwhile waits in `queued`, in order: every Save and Print, and the
    // newest preview in place of an older one. A job keeps its own view: the card may be open on another page by the
    // time a queued Save runs. A Save's file is named when it runs, once the one before it has landed, so two Saves never
    // take one name.
    property var job: null
    property var queued: []
    property int serial: 0
    Timer { id: later; interval: 300; onTriggered: card.render() }
    function render() {
        if (!live || !view)
            return;
        serial++;
        run({ kind: "preview", view: view, path: Printing.previewPath(), options: Print.options(settings, 0), serial: serial });
    }
    function run(j) {
        if (job) {
            queued = queued.filter(q => j.kind !== "preview" || q.kind !== "preview").concat([j]);
            return;
        }
        if (j.kind === "save")
            j.path = Disk.unique(j.folder, j.name);
        job = j;
        if (!Printing.toPdf(j.view, j.path, j.options))
            finished(j.path, false);
    }
    Connections {
        target: card.job ? card.job.view : null
        function onPdfPrintingFinished(filePath, success) { card.finished(filePath, success) }
        // a view closed or unloaded while Chromium makes its PDF never answers
        function onGone() { card.viewGone(card.job.view) }
        function onLifecycleStateChanged() {
            if (card.job.view.lifecycleState === WebEngineView.LifecycleState.Discarded)
                card.viewGone(card.job.view);
        }
    }
    // its jobs fail (a Save saying so) and the next one runs, once the view has gone
    function viewGone(v) {
        const path = job.path;
        queued = queued.filter(q => q.view !== v && q.view !== null);
        Qt.callLater(() => card.finished(path, false));
    }
    // the page loading another document: the card was for the one that goes
    Connections {
        target: card.opened ? card.view : null
        function onLoadingChanged(request) { if (request.status === WebEngineView.LoadStartedStatus) card.hide() }
    }
    function finished(path, ok) {
        const j = job;
        if (!j || j.path !== path)
            return;
        job = null;
        if (j.kind === "preview") {
            if (!opened || j.serial !== serial || j.view !== view || !ok) {
                Printing.remove(path);
                if (opened && j.serial === serial && j.view === view)
                    previewFailed = true;
            } else {
                const old = preview;
                preview = path;
                previewFailed = false;
                if (old)
                    Printing.remove(old);
            }
        } else if (j.kind === "save") {
            if (ok)
                saved(j.pageId, path);
            else
                notice(Print.notSaved, 4000);
        } else if (j.kind === "print") {
            if (ok) {
                sending = Object.assign({}, sending, { [path]: true });
                Printing.send(j.printer, path, j.title, j.paper);
            } else {
                Printing.remove(path);
                notice(Print.notSent(Print.notMade), 4000);
            }
        }
        if (queued.length > 0) {
            const q = queued[0];
            queued = queued.slice(1);
            run(q);
        }
    }
    // Save or Print: the PDF made afresh with the page range, then saved or sent; the card closes
    function commit() {
        if (!opened || !view)
            return;
        const c = settings, options = Print.options(c, page);
        if (c.destination === Print.savePdf)
            run({ kind: "save", view: view, path: "", folder: folder, name: Print.fileName(title, pageHost), options: options, pageId: pageId });
        else
            run({ kind: "print", view: view, path: Printing.previewPath(), options: options, printer: c.destination, title: title || pageHost, paper: c.paper });
        hide();
    }
    // the jobs this card sent that CUPS has not answered yet, by their files (every window's card hears every answer)
    property var sending: ({})
    Connections {
        target: Printing
        function onPrintersFound(names, defaultName) { card.printers = names }
        function onSendDone(printer, path, error) {
            if (!card.sending[path])
                return;
            const left = Object.assign({}, card.sending);
            delete left[path];
            card.sending = left;
            Printing.remove(path);
            card.notice(error ? Print.notSent(error) : Print.sent(printer), error ? 4000 : 3000);
        }
    }

    // the targets, in order: "print:<key>" a row, "print:<key>=<value>" a choice, and back, the preview's pages and the
    // buttons; the checks click through them
    function targets(item, out) {
        const list = out ?? [];
        for (const c of (item ?? frame).children) {
            if (!c.visible)
                continue;
            if (c.objectName.startsWith("print:"))
                list.push(c);
            targets(c, list);
        }
        return list;
    }
    function target(name) { return targets().find(t => t.objectName === name) ?? null }
    function move(delta) {
        const all = targets().filter(t => t.enabled);
        if (all.length === 0)
            return;
        const at = all.findIndex(t => t.activeFocus);
        all[at < 0 ? (delta > 0 ? 0 : all.length - 1) : (at + delta + all.length) % all.length].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    // after a pick with the keys the rows change under the focused one: the keys go to `name`
    function refocus(name) {
        Qt.callLater(() => {
            const t = target(name);
            if (t && card.activeFocus)
                t.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    Keys.onPressed: event => {
        if (!opened)
            return;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down)
            move(1);
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up)
            move(-1);
        else if (event.key === Qt.Key_Left)
            turn(-1);
        else if (event.key === Qt.Key_Right)
            turn(1);
        else if (event.key === Qt.Key_Escape)
            back();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            commit();
        else
            return;
        event.accepted = true;
    }

    // scrim: the terminal tone at 15 %, a plain rectangle over the page only
    Rectangle {
        anchors.fill: parent
        color: Theme.transparentize(Theme.terminal, 0.85)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.hide(); onWheel: wheel => wheel.accepted = true }
    }

    Frost {
        id: frame
        readonly property int boxWidth: 248
        readonly property int boxHeight: 340
        width: Math.min(880, parent.width - 120)
        height: 20 + boxHeight + 8 + 28 + 16
        x: Math.round((parent.width - width) / 2)
        y: Math.max(12, Math.min(Math.round(parent.height * 0.26), parent.height - height - 12)) + (card.opened ? 0 : 6)
        Behavior on y { Anim { type: Anim.StandardSmall } }
        radius: Theme.rounding.large
        MouseArea { anchors.fill: parent; onPressed: card.forceActiveFocus() }

        // the page as it prints: its PDF's page on paper, radius 12; a 5 % wash until the first one comes
        Item {
            id: box
            x: 20
            y: 20
            width: frame.boxWidth
            height: frame.boxHeight
            Rectangle {
                anchors.fill: parent
                visible: card.count === 0
                radius: Theme.rounding.small
                color: Theme.transparentize(Theme.onSurface, 0.95)
                Busy { anchors.centerIn: parent; visible: !card.previewFailed }
                Label {
                    anchors { left: parent.left; right: parent.right; margins: 16; verticalCenter: parent.verticalCenter }
                    visible: card.previewFailed
                    text: "No preview: " + Print.notMade
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.font.caption
                    color: Theme.colSubtext
                }
            }
            // the page's size fitted into the box
            readonly property size fitted: {
                const s = card.count > 0 ? card.doc.pagePointSize(card.page - 1) : Qt.size(0, 0);
                const k = s.width > 0 ? Math.min(width / s.width, height / s.height) : 0;
                return Qt.size(Math.round(s.width * k), Math.round(s.height * k));
            }
            // made anew for each preview, so the image has its document and source together from the start (a document
            // whose source changes under an image makes it warn of the two in conflict)
            Repeater {
                id: sheets
                model: card.preview ? [card.preview] : []
                delegate: Item {
                    id: sheet
                    required property string modelData
                    readonly property alias doc: pdf
                    anchors.centerIn: parent
                    width: box.fitted.width
                    height: box.fitted.height
                    visible: card.count > 0
                    layer.enabled: visible
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: sheetMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                    PdfDocument { id: pdf; source: "file://" + sheet.modelData }
                    // paper: the page's own ground, not a Theme colour
                    Rectangle { anchors.fill: parent; color: "#ffffff" }
                    PdfPageImage {
                        anchors.fill: parent
                        document: pdf
                        source: pdf.source
                        currentFrame: card.page - 1
                        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                        fillMode: Image.PreserveAspectFit
                    }
                    Item {
                        id: sheetMask
                        visible: false
                        width: sheet.width
                        height: sheet.height
                        layer.enabled: true
                        Rectangle { anchors.fill: parent; radius: Theme.rounding.small; color: "black" }
                    }
                }
            }
        }
        // ‹ 1 of 3 ›
        Row {
            visible: card.count > 0
            anchors { horizontalCenter: box.horizontalCenter; top: box.bottom; topMargin: 8 }
            height: 28
            spacing: 4
            OwnHit {
                name: "print:previous"
                enabled: card.page > 1
                opacity: enabled ? 1 : 0.38
                scope: card
                width: 28
                height: 28
                onActivated: card.turn(-1)
                Symbol { anchors.centerIn: parent; text: "chevron_left"; iconSize: 16 }
            }
            Label {
                width: 64
                height: 28
                horizontalAlignment: Text.AlignHCenter
                text: card.page + " of " + card.count
                font.pixelSize: Theme.font.caption
                font.features: { "tnum": 1 }
                color: Theme.colSubtext
            }
            OwnHit {
                name: "print:next"
                enabled: card.page < card.count
                opacity: enabled ? 1 : 0.38
                scope: card
                width: 28
                height: 28
                onActivated: card.turn(1)
                Symbol { anchors.centerIn: parent; text: "chevron_right"; iconSize: 16 }
            }
        }

        Item {
            id: side
            x: box.x + box.width + 28
            y: 20
            width: frame.width - x - 20
            height: frame.height - 40
            Label {
                id: heading
                width: parent.width
                height: 28
                text: Print.heading(card.title)
                font.pixelSize: Theme.font.small
                weight: Font.DemiBold
                color: Theme.colOnSurface
            }
            // the rows, or a row's choices in place
            Flickable {
                id: rows
                anchors { top: heading.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: buttons.top; bottomMargin: 12 }
                contentHeight: rowColumn.height
                interactive: contentHeight > height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: ThinScrollBar {}
                Column {
                    id: rowColumn
                    width: rows.width
                    // a row: label 14 px left, value 13 px colSubtext right, and ›
                    Repeater {
                        model: card.sub === "" ? Print.keys : []
                        delegate: OwnHit {
                            required property string modelData
                            name: "print:" + modelData
                            scope: card
                            width: rowColumn.width
                            height: 32
                            onActivated: keyed => card.openRow(modelData, keyed)
                            Label {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16 - rowValue.width - 28
                                text: Print.labels[parent.modelData]
                                font.pixelSize: Theme.font.body
                            }
                            Label {
                                id: rowValue
                                anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                                width: Math.min(implicitWidth, parent.width * 0.6)
                                text: Print.value(parent.modelData, card.settings, card.facts)
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: Theme.font.caption
                                color: Theme.colSubtext
                            }
                            Symbol {
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                text: "chevron_right"
                                iconSize: 16
                            }
                        }
                    }
                    // ‹ and the row's name, then its choices, the picked one on the current row's wash
                    OwnHit {
                        visible: card.sub !== ""
                        name: "print:back"
                        scope: card
                        width: rowColumn.width
                        height: 32
                        onActivated: card.back()
                        Symbol { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "chevron_left"; iconSize: 16 }
                        Label {
                            x: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: Print.labels[card.sub] ?? ""
                            font.pixelSize: Theme.font.body
                            weight: Font.DemiBold
                        }
                    }
                    Item {
                        visible: card.sub !== ""
                        width: rowColumn.width
                        height: 9
                        Rectangle { y: 4; width: parent.width; height: 1; color: Theme.transparentize(Theme.outlineVariant, 0.7) }
                    }
                    Repeater {
                        model: card.sub !== "" ? Print.choices(card.sub, card.facts) : []
                        delegate: OwnHit {
                            required property var modelData
                            name: "print:" + card.sub + "=" + modelData.value
                            picked: card.settings[card.sub] === modelData.value
                            scope: card
                            width: rowColumn.width
                            height: 32
                            onActivated: keyed => card.pick(card.sub, modelData.value, keyed)
                            Label {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16
                                text: parent.modelData.label
                                font.pixelSize: Theme.font.body
                            }
                        }
                    }
                }
            }
            Row {
                id: buttons
                anchors { right: parent.right; bottom: parent.bottom }
                spacing: 8
                TextButton { objectName: "print:cancel"; label: "Cancel"; onPicked: card.hide() }
                TextButton { objectName: "print:commit"; label: Print.button(card.settings); onPicked: card.commit() }
            }
        }
    }
}
