import QtQuick
import QtQuick.Effects

// The first start (~/book4-edge/thyris-migration-plan.md): bring one browser's things over (or a password manager's
// file), then make Thyris the default. One page over the whole window, in the installer's composition as FailurePage
// has it: everything on the middle line, a light display headline, one sentence in the secondary ink with its cause in
// the main ink, the rows, the verbs (the way forward on the right, in sand) and what happens next. Every word that
// informs is at least the secondary ink (APCA Lc 75 and up for small text). `phase`: "arrive" (one source chosen from
// the list: arrows move the choice, Enter takes the way forward), "bringing" (each kind counting up; one may wait on the
// keyring or fail with its reason) or "done" (the figures, the sites that ask again, what stayed and why).
// Mock stage: the shots feed it sample data; nothing opens it yet.
FocusScope {
    id: welcome

    property string phase: ""
    // [{ name, profile, email, kind: "chromium" | "firefox" | "file", icon or glyph,
    //    counts: { passwords, bookmarks, tabs, sites }, bring: { passwords, bookmarks, history, tabs, sites } }]
    property var sources: []
    property string keyringName: "keyring"   // what the desktop calls it: "KWallet" on KDE
    // "" (the first start: browsers and a file) or "file" (Settings > Import: a password manager's file alone)
    property string mode: ""
    // why the file chosen did not work, in the page's words; "" for none
    property string notice: ""
    // the service a file came from once read ("Bitwarden"), "" when its header named none
    property string fileFrom: ""
    readonly property bool fileRoute: !!source && source.kind === "file"
    // how to get a password manager's file, per service (the steps as the services' own menus name them, 2026-10)
    property var exportGuide: [
        { service: "Google Password Manager", steps: "passwords.google.com › Settings › Export passwords" },
        { service: "Apple Passwords", steps: "Passwords on a Mac › File › Export All Passwords" },
        { service: "Bitwarden", steps: "Tools › Export vault, as .csv" },
        { service: "1Password", steps: "File › Export, then CSV" },
        { service: "Firefox", steps: "about:logins › ··· › Export passwords" }]
    property int chosen: 0
    property var kinds: []          // [{ label, done, total, waiting: "keyring" | "", failed: reason | "" }]
    // a browser's: { from, sitesCame (the sites its cookies came for), google (one of them is Google's), figures: [{ value,
    //   label, place }], stayed: [{ what, why, link }] }
    // a file's: { file: true, from (the service, or "the file"), added, kept, stayed (what was left out and why) }
    property var result: null
    signal picked(string action)

    anchors.fill: parent
    visible: phase !== ""
    focus: true
    // shown, it has the keys: Enter, Esc and the arrows are the page's
    onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)

    readonly property var source: sources[chosen] ?? null
    readonly property string browserName: source ? source.name.replace(/^Google /, "") : ""
    readonly property string sourceName: source ? browserName + (source.profile ? " · " + source.profile : "") : ""
    readonly property int browsers: sources.filter(s => s.kind !== "file").length
    readonly property var waitingKind: kinds.find(k => k.waiting) ?? null
    property bool keyed: false      // a key moved the choice: the focus ring shows from then on

    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
    function strong(s) { return `<span style="color:${Theme.inkMain}; font-weight:500">${esc(s)}</span>`; }
    function count(n) { return Number(n).toLocaleString(Qt.locale(), "f", 0); }
    function plural(n, one, many) { return count(n) + " " + (n === 1 ? one : many); }
    function factsOf(s) {
        if (s.kind === "file")
            return "Bitwarden, 1Password, Apple Passwords, Google and most others save one";
        const c = s.counts, out = [];
        if (c.passwords) out.push(plural(c.passwords, "password", "passwords"));
        if (c.bookmarks) out.push(plural(c.bookmarks, "bookmark", "bookmarks"));
        if (c.tabs) out.push(plural(c.tabs, "open tab", "open tabs"));
        if (c.sites) out.push("signed in to " + plural(c.sites, "site", "sites"));
        return out.map(f => f.replace(/ /g, "\u00a0")).join("  ·  ");   // a fact never breaks inside
    }
    function nameList(names) {
        return names.length <= 1 ? names.join("") : names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
    }
    // a switch of what comes over, for source `i`, kept in its `bring` (on unless false)
    function setBring(i, key, on) {
        const list = sources.slice();
        list[i] = Object.assign({}, list[i], { bring: Object.assign({}, list[i].bring ?? {}, { [key]: on }) });
        sources = list;
    }
    function choose(i) {
        if (i >= 0 && i < sources.length)
            chosen = i;
    }

    Keys.onUpPressed: { keyed = true; choose(chosen - 1) }
    Keys.onDownPressed: { keyed = true; choose(chosen + 1) }
    Keys.onReturnPressed: forward()
    Keys.onEnterPressed: forward()
    Keys.onEscapePressed: { if (phase !== "bringing") picked("close") }
    function forward() {
        if (phase === "arrive")
            picked(source && source.kind === "file" ? "file" : "bring");
        else if (phase === "done")
            picked(result && result.file ? "delete" : "default");
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.terminal
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
    }

    // Tacit's wordmark: the name in spaced capitals, the plain word for it under
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 44
        spacing: 4
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "THYRIS"
            font.pixelSize: 14
            font.letterSpacing: 7
            weight: 560
            color: Theme.inkSec
        }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: "browser"; font.pixelSize: 13; color: Theme.inkSec }
    }

    // a line that acts: the secondary ink, the main ink and an underline hovered
    component TextLink: Item {
        id: link
        property string text
        property int size: 16
        signal picked()
        width: linkText.implicitWidth
        height: 24
        Label {
            id: linkText
            anchors.verticalCenter: parent.verticalCenter
            text: link.text
            font.pixelSize: link.size
            font.underline: linkArea.containsMouse
            color: linkArea.containsMouse ? Theme.inkMain : Theme.inkSec
        }
        MouseArea { id: linkArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: link.picked() }
    }
    // what comes over, one switch each: TextButton's look (32 px, radius 12, the faint wash and hairline), a check when on
    component Chip: Item {
        id: chip
        property string label
        property bool on: true
        signal toggled(bool on)
        width: chipRow.implicitWidth + 20
        height: 30
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.checked: on
        Rectangle {
            anchors.fill: parent
            radius: Theme.rounding.small
            color: chip.on ? Theme.transparentize(Theme.onSurface, 0.9) : "transparent"
            border.width: 1
            border.color: Theme.transparentize(Theme.outlineVariant, chip.on ? 0.4 : 0.2)
        }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Symbol { visible: chip.on; anchors.verticalCenter: parent.verticalCenter; text: "check"; iconSize: 16; color: Theme.inkMain }
            Label { anchors.verticalCenter: parent.verticalCenter; text: chip.label; font.pixelSize: 14; color: chip.on ? Theme.inkMain : Theme.inkSec }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.toggled(!chip.on) }
    }
    // a row of the arrive list: an icon (an app's, or a glyph on a raised square), the name, its facts (wrapping, never
    // cut), and the choice mark: one source is chosen, as in a list of options
    component SourceRow: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool isChosen: welcome.chosen === index
        width: parent ? parent.width : 0
        height: Math.max(72, text.implicitHeight + 28)
        Accessible.role: Accessible.RadioButton
        Accessible.name: modelData.name + (modelData.profile ? ", " + modelData.profile : "") + ". " + welcome.factsOf(modelData)
        Accessible.checked: isChosen
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: row.isChosen ? Theme.rowCurrent : rowArea.containsMouse ? Theme.rowHover : "transparent"
        }
        Rectangle {
            visible: row.isChosen && welcome.keyed && welcome.activeFocus
            anchors { fill: parent; margins: -2 }
            radius: 20
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
        }
        Image {
            visible: !!row.modelData.icon
            x: 16
            y: row.height > 72 ? text.y : (row.height - height) / 2
            width: 40
            height: 40
            source: row.modelData.icon ?? ""
            sourceSize: Qt.size(80, 80)
            smooth: true
            mipmap: true
        }
        Rectangle {
            visible: !!row.modelData.glyph
            x: 16
            y: row.height > 72 ? text.y : (row.height - height) / 2
            width: 40
            height: 40
            radius: 12
            color: Theme.raised
            Symbol { anchors.centerIn: parent; text: row.modelData.glyph ?? ""; iconSize: 22; color: Theme.inkMain }
        }
        Column {
            id: text
            x: 74
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 64
            spacing: 4
            Label {
                width: parent.width
                textFormat: Text.RichText
                text: welcome.esc(row.modelData.name) + (row.modelData.profile ? `<span style="color:${Theme.inkSec}; font-weight:450">  ·  ${welcome.esc(row.modelData.profile)}</span>` : "")
                      + (row.modelData.email ? `<span style="color:${Theme.inkSec}; font-weight:450">  ·  ${welcome.esc(row.modelData.email)}</span>` : "")
                font.pixelSize: 17
                weight: 560
                color: Theme.inkMain
            }
            Label {
                width: parent.width
                text: welcome.factsOf(row.modelData)
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                font.pixelSize: 15
                lineHeight: 1.15
                color: Theme.inkSec
            }
            // the chosen browser: what comes over, all on unless switched off
            Flow {
                visible: row.isChosen && row.modelData.kind !== "file"
                width: parent.width
                topPadding: 8
                spacing: 8
                Repeater {
                    // the kinds this source can bring (the Firefox family's tabs, not yet the Chrome family's)
                    model: row.isChosen && row.modelData.kind !== "file"
                           ? (row.modelData.chips ?? [["passwords", "Passwords"], ["bookmarks", "Bookmarks"], ["history", "History"], ["tabs", "Tabs"], ["sites", "Sign-ins"]]) : []
                    delegate: Chip {
                        required property var modelData
                        label: modelData[1]
                        on: (row.modelData.bring ?? {})[modelData[0]] ?? true
                        onToggled: on => welcome.setBring(row.index, modelData[0], on)
                    }
                }
            }
        }
        Symbol {
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            text: row.isChosen ? "radio_button_checked" : "radio_button_unchecked"
            iconSize: 22
            color: row.isChosen ? Theme.primary : Theme.inkSec
        }
        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: welcome.choose(row.index) }
    }

    Column {
        id: block
        width: Math.max(0, Math.min(720, parent.width - 96))
        x: Math.round((parent.width - width) / 2)
        // a little above the middle, by its own height: a tall list (the file's guide) never runs off the bottom
        y: Math.max(110, Math.round((parent.height - height) * 0.42))

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 28
            font.family: Theme.font.display
            font.pixelSize: 46
            font.letterSpacing: 0.5
            weight: 300
            color: Theme.inkMain
            text: welcome.phase === "arrive" ? (welcome.mode === "file" ? "Bring passwords from a file" : "Bring your things over")
                : welcome.phase === "bringing" ? (welcome.fileRoute ? "Bringing " + (welcome.fileFrom ? welcome.fileFrom + "'s passwords" : "the passwords") + " over"
                                                                    : "Bringing " + welcome.sourceName + " over")
                : welcome.result ? "Brought over from " + welcome.result.from : ""
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
            text: {
                if (welcome.phase === "arrive" && welcome.mode === "file")
                    return "Export a file from " + welcome.strong("your password manager") + " and choose it here.";
                if (welcome.phase === "arrive") {
                    const n = welcome.browsers;
                    if (n === 0)
                        return "Thyris found " + welcome.strong("no other browser") + " here. A password manager's file brings your passwords.";
                    return "Thyris found " + welcome.strong(["one browser", "two browsers", "three browsers", "four browsers"][n - 1] ?? welcome.count(n) + " browsers")
                           + " here. Bring one over and you stay signed in.";
                }
                if (welcome.phase === "bringing" && welcome.fileRoute && !welcome.waitingKind)
                    return "Each login goes into your " + welcome.esc(welcome.keyringName) + " as if you had saved it here; " + welcome.strong("none is replaced") + ".";
                if (welcome.phase === "bringing")
                    return welcome.waitingKind ? welcome.strong("Waiting for your " + welcome.keyringName) + ": unlock it in the window it opened. The rest goes on meanwhile."
                                               : welcome.strong(welcome.browserName + " can stay open") + ", and you can keep working.";
                const r = welcome.result;
                if (!r)
                    return "";
                if (r.file) {
                    const came = r.added > 0 ? welcome.strong(welcome.count(r.added) + (r.added === 1 ? " password is in Thyris now" : " passwords are in Thyris now"))
                                               + ", ready in the Fill row when you sign in."
                                             : welcome.strong("No new passwords") + " came from it.";
                    const had = r.kept > 0 ? " " + welcome.count(r.kept) + (r.kept === 1 ? " login you already had stayed as it was." : " logins you already had stayed as they were.") : "";
                    return came + had;
                }
                // which sites take the cookies again cannot be known here: how many came, and that a few may ask
                const google = r.google ? " Google may also email you about a new sign-in on Linux; that's Thyris." : "";
                return r.sitesCame > 0 ? welcome.strong("Sign-ins for " + welcome.plural(r.sitesCame, "site", "sites") + " came over") + ", so most of them keep you signed in; a few may ask you once more." + google
                                       : "What you picked came over." + google;
            }
        }

        // arrive: one source, chosen from the browsers found and a password manager's file (a file alone needs no choice)
        Item { width: 1; height: welcome.phase === "arrive" && welcome.mode !== "file" ? 32 : 0 }
        Column {
            visible: welcome.phase === "arrive" && welcome.mode !== "file"
            width: parent.width
            spacing: 4
            Repeater {
                model: welcome.phase === "arrive" ? welcome.sources : []
                delegate: SourceRow {}
            }
        }

        // a password manager's file chosen: where each service keeps its export, so the file is easy to get
        Item { width: 1; height: guide.visible ? 22 : 0 }
        Column {
            id: guide
            visible: welcome.phase === "arrive" && !!welcome.source && welcome.source.kind === "file" && welcome.exportGuide.length > 0
            width: Math.min(parent.width, 620)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Label { text: "Where to get the file"; font.pixelSize: 15; weight: 560; color: Theme.inkMain }
            Repeater {
                model: guide.visible ? welcome.exportGuide : []
                delegate: Row {
                    required property var modelData
                    spacing: 16
                    Label { width: 190; text: modelData.service; font.pixelSize: 15; color: Theme.inkMain }
                    Label { width: guide.width - 206; text: modelData.steps; wrapMode: Text.Wrap; elide: Text.ElideNone; font.pixelSize: 15; color: Theme.inkSec }
                }
            }
        }

        // bringing: each kind counting up, the strip in sand while it moves, plain once done; a kind waits or fails in words
        Item { width: 1; height: welcome.phase === "bringing" ? 38 : 0 }
        Column {
            visible: welcome.phase === "bringing"
            width: Math.min(parent.width, 600)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18
            Repeater {
                model: welcome.phase === "bringing" ? welcome.kinds : []
                delegate: Column {
                    id: kind
                    required property var modelData
                    readonly property bool finished: !modelData.failed && !modelData.waiting && modelData.done >= modelData.total
                    width: parent.width
                    spacing: 9
                    Item {
                        width: parent.width
                        height: 22
                        Label { text: kind.modelData.label; font.pixelSize: 17; color: Theme.inkMain }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Symbol {
                                visible: !!kind.modelData.failed
                                anchors.verticalCenter: parent.verticalCenter
                                text: "error"
                                iconSize: 18
                                color: Theme.inkMain
                            }
                            Label {
                                text: kind.modelData.failed ? "Not brought: " + kind.modelData.failed
                                    : kind.modelData.waiting ? (kind.modelData.waiting === "keyring" ? "Waiting for the " + welcome.keyringName : kind.modelData.waiting)
                                    : kind.finished ? welcome.count(kind.modelData.total)
                                    : welcome.count(kind.modelData.done) + " of " + welcome.count(kind.modelData.total)
                                font.pixelSize: 16
                                font.features: { "tnum": 1 }
                                color: kind.finished || kind.modelData.failed ? Theme.inkMain : Theme.inkSec
                            }
                            Symbol {
                                visible: kind.finished
                                anchors.verticalCenter: parent.verticalCenter
                                text: "check"
                                iconSize: 18
                                color: Theme.inkMain
                            }
                            TextLink {
                                visible: !!kind.modelData.failed
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Try again"
                                onPicked: welcome.picked("retry:" + kind.modelData.label)
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 3
                        Rectangle { anchors.fill: parent; radius: 1.5; color: Theme.stripAhead }
                        Rectangle {
                            width: kind.modelData.failed ? 0 : parent.width * Math.min(1, kind.modelData.done / Math.max(1, kind.modelData.total))
                            height: parent.height
                            radius: 1.5
                            color: kind.finished ? Theme.stripPast : Theme.stripFill
                        }
                    }
                }
            }
        }

        // done: the figures as type (value over label), then what stayed behind, why, and a way to see which
        Item { width: 1; height: welcome.phase === "done" ? (welcome.result && welcome.result.file ? 14 : 34) : 0 }
        TextLink {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: welcome.phase === "done" && !!welcome.result && welcome.result.file && welcome.result.added > 0
            text: "See them in Passwords"
            onPicked: welcome.picked("open:Passwords")
        }
        Row {
            visible: welcome.phase === "done" && !(welcome.result && welcome.result.file)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 56
            Repeater {
                model: welcome.phase === "done" && welcome.result ? welcome.result.figures : []
                delegate: Column {
                    required property var modelData
                    spacing: 2
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: welcome.count(modelData.value)
                        font.family: Theme.font.display
                        font.pixelSize: 32
                        font.features: { "tnum": 1 }
                        weight: 400
                        color: Theme.inkMain
                    }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.pixelSize: 15; color: Theme.inkSec }
                    Item { width: 1; height: 4 }
                    TextLink {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !!modelData.place
                        size: 15
                        text: "in " + (modelData.place ?? "")
                        onPicked: welcome.picked("open:" + modelData.place)
                    }
                }
            }
        }
        Item { width: 1; height: welcome.phase === "done" && welcome.result && welcome.result.stayed.length ? 34 : 0 }
        Column {
            visible: welcome.phase === "done" && !!welcome.result && welcome.result.stayed.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: welcome.result && welcome.result.file ? "Left out of the file" : "Stayed in " + (welcome.result ? welcome.result.from : "")
                font.pixelSize: 15
                weight: 560
                color: Theme.inkMain
            }
            Repeater {
                model: welcome.phase === "done" && welcome.result ? welcome.result.stayed : []
                delegate: Row {
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    readonly property bool linked: !(welcome.result && welcome.result.file)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.RichText
                        text: `<span style="color:${Theme.inkMain}">${welcome.esc(modelData.what)}</span> · ${welcome.esc(modelData.why)}`
                        font.pixelSize: 15
                        color: Theme.inkSec
                    }
                    TextLink { visible: parent.linked; anchors.verticalCenter: parent.verticalCenter; size: 15; text: modelData.link ?? "Show which"; onPicked: welcome.picked("show:" + modelData.what) }
                }
            }
        }

        Item { width: 1; height: welcome.notice !== "" && welcome.phase === "arrive" ? 26 : 0 }
        Row {
            visible: welcome.notice !== "" && welcome.phase === "arrive"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Symbol { anchors.verticalCenter: parent.verticalCenter; text: "error"; iconSize: 18; color: Theme.inkMain }
            Label { anchors.verticalCenter: parent.verticalCenter; text: welcome.notice; font.pixelSize: 16; color: Theme.inkMain }
        }
        Item { width: 1; height: welcome.phase === "bringing" ? 34 : 40 }
        Item {
            visible: welcome.phase !== "bringing"
            width: parent.width
            height: verbs.height
            Row {
                id: verbs
                anchors.horizontalCenter: parent.horizontalCenter
                layoutDirection: Qt.RightToLeft
                spacing: 14
                Slab {
                    text: welcome.phase === "done" ? (welcome.result && welcome.result.file ? "Delete the file" : "Make Thyris your default")
                        : welcome.source && welcome.source.kind === "file" ? "Choose the file" : "Bring " + welcome.sourceName + " over"
                    tone: "default"
                    onPicked: welcome.forward()
                }
                Slab {
                    text: welcome.phase === "arrive" ? (welcome.mode === "file" ? "Not now" : "Start fresh")
                        : welcome.result && welcome.result.file ? "Keep the file" : "Not now"
                    onPicked: welcome.picked(welcome.phase === "arrive" ? (welcome.mode === "file" ? "close" : "fresh")
                                             : welcome.result && welcome.result.file ? "keep" : "later")
                }
            }
        }
        Item { width: 1; height: welcome.phase === "bringing" ? 0 : 18 }
        // what happens next: trust first, on its own line in the main ink, then the one thing the system will ask
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: welcome.phase === "arrive" && !!welcome.source
            text: "Everything stays on this computer."
            font.pixelSize: 16
            weight: 560
            color: Theme.inkMain
        }
        Item { width: 1; height: welcome.phase === "arrive" ? 4 : 0 }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 16
            lineHeight: 1.25
            color: Theme.inkSec
            visible: text !== ""
            text: {
                if (welcome.phase === "arrive" && welcome.source) {
                    if (welcome.source.kind === "file")
                        return "The file holds your passwords in plain text, so Thyris offers to delete it afterwards.";
                    if (welcome.source.kind === "firefox")
                        return "If " + welcome.browserName + " has a main password, Thyris asks you for it once.";
                    return "Your " + welcome.keyringName + " asks once, so Thyris can read the passwords " + welcome.browserName + " saved.";
                }
                if (welcome.phase === "done" && welcome.result && welcome.result.file)
                    return "The file still holds your passwords in plain text. Deleting it removes it from this computer.";
                if (welcome.phase === "done" && welcome.result && welcome.result.tabsCame > 0)
                    return "Your " + welcome.result.from.replace(/ · .*$/, "") + " windows are in the rail on the left, one task each.";
                return "";
            }
        }
        // a file's logins go in within seconds, and the keyring takes them one by one: nothing to stop there
        TextLink {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: welcome.phase === "bringing" && !welcome.fileRoute
            text: "Stop, and keep what came over"
            onPicked: welcome.picked("stop")
        }
    }
}
