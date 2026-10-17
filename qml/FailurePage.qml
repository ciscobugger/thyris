import QtQuick

// The browser's own page for a failure, or for the restore after a crash (PLAN.md 3.8 8f-8i; the facts are
// Failures.js'): drawn in QML on the opaque terminal ground over the page area, never a web view, which
// stays under it untouched. In Tacit's language (the shell's Activity, 2026-10-08): a headline (30 px, one
// line; 40 px DemiBold for a certificate), one sentence whose cause is in sand, then the verbs, the
// recommended one filled in sand. What the browser knows picks the words and the verbs (offline: the network;
// a near name: go there; no answer: wait; a certificate: back). The technical facts wait under a quiet
// line. It takes the keys whenever its page is given them: Tab and Backtab start at the recommended verb,
// Enter picks; the page keys it leaves (Esc stops, Ctrl+R, Alt+Left) go on to Main.
FocusScope {
    id: failure

    property var view: null                  // the page whose failure shows; null for the restore page
    property var page: null                  // a Failures.js page
    signal picked(string action)

    anchors.fill: parent
    z: 6
    visible: page !== null

    // the technical facts, under "Details"; opened per failure, closed for the next one
    property bool open: false
    readonly property string key: page ? page.key : ""
    onKeyChanged: open = false
    readonly property var facts: {
        if (!page)
            return [];
        const out = page.details.slice();
        if (page.code !== "")
            out.push(page.code + (page.codeNote !== "" ? " · " + page.codeNote : ""));
        return out;
    }
    // what the page says: { alarm, headline, cause, rest, verbs: [{ label, action, tone }], hint }: the default verb
    // first (tone "default": Enter takes it); `hint`, one quiet sentence under the buttons, says what Enter does
    readonly property var say: {
        const p = page;
        if (!p)
            return null;
        const first = text => { const m = /^(.*?[.?!])(\s.*)?$/.exec(text ?? ""); return m ? [m[1], m[2] ?? ""] : [text ?? "", ""]; };
        const retry = { label: "Try again", action: "retry", tone: "default" };
        if (p.kind === "offline")
            return { headline: "You're offline", cause: "This computer has no network connection.",
                     rest: p.body.length > 1 ? " The page comes back by itself when it reconnects." : "",
                     verbs: [retry], hint: "↵ loads it once more." };
        if (p.kind === "name")
            return p.near ? { headline: "Did you mean " + p.near + "?", cause: p.search, rest: " has no address on the internet. You have been to " + p.near + " before.",
                              verbs: [{ label: "Go to " + p.near, action: "near", tone: "default" }, { label: "Search for " + p.search, action: "search" }],
                              hint: "↵ goes to " + p.near + ", the site you have been to." }
                          : { headline: p.search + " doesn't exist", cause: p.search, rest: " has no address on the internet.",
                              verbs: [{ label: "Search for " + p.search, action: "search", tone: "default" }], hint: "↵ searches for it with your search engine." };
        if (p.kind === "noReply")
            return { headline: p.host + " isn't answering", cause: p.body[0] ?? "", rest: " The site may be down or overloaded.",
                     verbs: [retry], hint: "↵ asks the site once more." };
        if (p.kind === "certificate") {
            const [cause, rest] = first(p.body[0]);
            // a certificate that ran out years ago: the site is likely left alone
            const year = Number((/(\d{4})\.$/.exec(cause) ?? [])[1] ?? 0);
            const old = year > 0 && new Date().getFullYear() - year >= 2 ? " A certificate this old usually means nobody looks after the site any more." : "";
            return { alarm: true, headline: p.title, cause: cause, rest: rest + old,
                     verbs: [{ label: "Go back", action: "back", tone: "default" }].concat(p.go !== "" ? [{ label: "Continue anyway", action: "continue", tone: "risk" }] : []),
                     hint: "↵ goes back to the page you came from." + (p.go !== "" ? " Continuing lets them read what you type." : "") };
        }
        const [cause, rest] = first(p.body.join(" "));
        const hints = { retry: "↵ loads it once more.", reload: "↵ starts this page again.", open: "↵ opens the page that was on screen." };
        return { headline: p.title, cause: cause, rest: rest,
                 verbs: p.actions.map((a, i) => Object.assign({}, a, { tone: i === 0 ? "default" : "" })),
                 hint: p.actions.length > 0 ? (hints[p.actions[0].action] ?? "") : "" };
    }
    readonly property var defaultVerb: say ? (say.verbs.find(v => v.tone === "default") ?? null) : null

    onPageChanged: {
        if (page && view && view.activeFocus)
            Qt.callLater(take);
        else if (!page && activeFocus && view)
            view.forceActiveFocus();
    }
    Connections {
        target: failure.view
        function onActiveFocusChanged() { if (failure.view.activeFocus && failure.page) Qt.callLater(failure.take) }
    }
    function take() {
        if (page)
            failure.forceActiveFocus();
    }
    function focusables() {
        const out = [];
        for (let i = 0; i < buttons.count; i++)
            out.push(buttons.itemAt(i));
        if (detailsLink.visible)
            out.push(detailsLink);
        return out;
    }
    function move(delta) {
        const f = focusables();
        if (f.length === 0)
            return;
        const at = f.findIndex(x => x.activeFocus);
        f[at < 0 ? 0 : (at + delta + f.length) % f.length].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    Keys.onPressed: event => {
        // Enter takes the default verb, the one that shows its key
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && failure.defaultVerb) {
            failure.picked(failure.defaultVerb.action);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Tab)
            move(1);
        else if (event.key === Qt.Key_Backtab)
            move(-1);
        else
            return;
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.terminal
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: failure.take()
            onWheel: wheel => wheel.accepted = true
        }
    }

    // a line that acts: the meta ink, full ink hovered, the focus ring for keys
    component TextLink: Item {
        id: link
        property string text
        property string glyph: ""
        signal picked()
        width: linkText.implicitWidth + (glyph ? 18 : 0)
        height: 24
        Keys.onReturnPressed: link.picked()
        Keys.onEnterPressed: link.picked()
        Keys.onSpacePressed: link.picked()
        Rectangle {
            visible: link.activeFocus
            anchors { fill: parent; leftMargin: -4; rightMargin: -4 }
            radius: Theme.rounding.verysmall
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
        }
        Label {
            id: linkText
            anchors.verticalCenter: parent.verticalCenter
            text: link.text
            font.pixelSize: 15
            color: linkArea.containsMouse ? Theme.inkMain : Theme.inkMeta
            Behavior on color { CAnim { hover: true } }
        }
        Symbol {
            visible: link.glyph !== ""
            x: linkText.implicitWidth + 2
            anchors.verticalCenter: parent.verticalCenter
            text: link.glyph
            iconSize: 16
            color: linkText.color
        }
        MouseArea { id: linkArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: link.picked() }
    }

    Column {
        id: block
        // the installer's composition (setup.qml, 2026-10-08): everything on the middle line, a light display headline,
        // the sentence in the secondary ink, the rings under it
        width: Math.max(0, Math.min(720, parent.width - 96))
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.27)

        Label {
            width: parent.width
            text: failure.say ? failure.say.headline : ""
            horizontalAlignment: Text.AlignHCenter
            // one line: a long one shrinks rather than cuts
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 28
            font.family: Theme.font.display
            font.pixelSize: 46
            font.letterSpacing: 0.5
            weight: 300
            color: Theme.inkMain
        }
        Item { width: 1; height: 16 }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            textFormat: Text.RichText
            font.pixelSize: 18
            lineHeight: 1.3
            color: Theme.inkSec
            function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
            // the cause in the main ink, as the installer names the disk
            text: !failure.say ? "" : (failure.say.cause !== "" ? `<span style="color:${Theme.inkMain}; font-weight:500">${esc(failure.say.cause)}</span>` : "")
                  + esc(failure.say.rest)
        }
        Item { width: 1; height: 40 }
        // the way forward on the right, the other way left of it, as in the installer; keys still start at the default
        Item {
            width: parent.width
            height: verbRow.height
            Row {
                id: verbRow
                anchors.horizontalCenter: parent.horizontalCenter
                layoutDirection: Qt.RightToLeft
                spacing: 14
                Repeater {
                id: buttons
                model: failure.say ? failure.say.verbs : []
                delegate: Slab {
                    required property var modelData
                    text: modelData.label
                    tone: modelData.tone ?? ""
                    key: modelData.tone === "default" ? "↵" : ""
                    // the page moves the keys itself (move()), not Qt's tab chain
                    activeFocusOnTab: false
                    onPicked: failure.picked(modelData.action)
                }
                }
            }
        }
        Item { width: 1; height: hintText.visible ? 16 : 0 }
        Label {
            id: hintText
            visible: text !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: failure.say ? failure.say.hint : ""
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 15
            color: Theme.inkMeta
        }
        // the restore page: why that page is offered
        Item { width: 1; height: noteText.visible ? 22 : 0 }
        Label {
            id: noteText
            visible: failure.page !== null && failure.page.note !== ""
            width: parent.width
            text: failure.page ? failure.page.note : ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 17
            lineHeight: 1.15
            color: Theme.inkSec
        }

        Item { width: 1; height: detailsLink.visible ? 30 : 0 }
        TextLink {
            id: detailsLink
            anchors.horizontalCenter: parent.horizontalCenter
            visible: failure.facts.length > 0
            text: failure.page && failure.page.kind === "certificate" ? "Certificate details" : "Details"
            glyph: failure.open ? "expand_less" : "expand_more"
            onPicked: failure.open = !failure.open
        }
        // technical lines read badly centred: a narrower block on the middle line, its lines left-aligned
        Column {
            id: factsBlock
            visible: failure.open && failure.facts.length > 0
            width: Math.min(parent.width, 560)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 10
            spacing: 4
            Repeater {
                model: failure.facts
                delegate: Label {
                    required property string modelData
                    width: factsBlock.width
                    text: modelData.replace(/:/g, ":\u200b")
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    font.pixelSize: 15
                    color: Theme.inkMeta
                }
            }
        }
    }
}
