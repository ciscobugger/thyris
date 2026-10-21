import QtQuick
import QtQuick.Effects
import Browser
import "Logins.js" as Logins
import "Settings.js" as Settings
import "Site.js" as Site

// Settings (PLAN.md 3.15, browser://settings, Ctrl+,) docked from the rail (owner 2026-10-15): the rail turns to its
// settings face (SettingsRail: back to the pages, the search, the sections) and the section opens as a sheet docked out
// of the rail's edge over the page you were on, which stays in sight under a veil of the window's ground, so a change
// to it (zoom, fonts) shows at once. The sheet lies level with the section's row; it opens with one sentence of what the
// section is set to, its cause in the accent, then the rows on the sheet's ground (no tiles, no hairlines). A row says
// what it is (15 px) and what it holds, its control at the right edge: a switch for on and off, up to three choices side
// by side, more in a list under the row, − value + in one ring, rings for what it does. Changes apply at once; there is
// no Save button. Settings.js lists the rows and their wording, Prefs keeps the values and Main applies them. Esc folds
// a list, then ends an edit, then leaves a view, then empties the search, then leaves Settings. In the search Up and
// Down walk the sections, Tab goes on into the rows.
OwnPage {
    id: settings

    required property var prefs
    property var sites: null
    property var adblock: null
    property var profile: null              // the main profile: its fonts, extensions and default languages
    property var siteData: null             // the main profile's cookie list
    property var engineFonts: ({})          // the engine's own families and sizes, before Settings set any
    property var defaultLanguages: []       // the engine's own languages, before Settings set any
    property string folder: Disk.downloads  // where downloads go (Main's: the folder set while it is one)
    // Import from Zen: what the import running brought so far (Main's zenRun), and Import picked
    property var zenRun: null
    signal importWanted()
    // Passwords from a file, another browser: Welcome takes it from here
    signal passwordFileWanted()
    signal browserImportWanted()
    // shots: what the rows show, laid over what the page reads (no profile, no ad blocker there)
    property var shotState: null

    // the page's own state: the view in place ("", "fonts", "allowed", "clear"), the filter, the row whose
    // choices are out, the row edited in place and its text, and what Files is picking for
    property string sub: ""
    // the section shown while nothing is searched for
    property string section: "search"
    property string filter: ""
    property string expand: ""
    property string editing: ""
    property string editText: ""
    property string picking: ""
    // bumped when something the bindings cannot see changed: the profile's fonts, the dictionaries, the extensions
    property int tick: 0

    title: "Settings"
    visible: view !== null
    // Main: a page lies under the sheet; the rail draws the settings face (folded, this page draws it at its left); the
    // current row's top in it, in this page's frame; the face's search there
    property bool behind: false
    property bool railFace: true
    property real anchorY: 0
    property Item railSearch: null
    signal leaveWanted()
    function leave() { leaveWanted() }
    first: railFace && railSearch ? railSearch : pageFace.search
    outsideFirst: railFace ? railSearch : null
    bare: true
    ground: Theme.transparentize(Theme.terminal, behind ? 1 - 0.62 * appear : 0)

    // The sheet: docked at the page area's left edge (the rail's), or folded at the face's; 600 px at most. Its first line
    // sits level with the current row; a sheet taller than that leaves room for moves up, and one taller than the page
    // scrolls its rows inside it.
    readonly property int faceWidth: railFace ? 0 : 300
    readonly property int sheetX: faceWidth
    readonly property int sheetWidth: Math.max(300, Math.min(600, width - sheetX - 48))
    readonly property int padTop: 26
    readonly property int padBottom: 30
    // taller than the page, it runs from the page's top to its foot
    readonly property real fitHeight: Math.min(rowsHeight + padTop + padBottom, height)
    readonly property real fitY: Math.max(0, Math.min((railFace ? anchorY : pageFace.y + pageFace.anchorY) + 18 - padTop - 11, height - fitHeight))
    // Opened, the veil and the sheet fade in (`appear`); a section after another glides the sheet to its row and size,
    // its rows fading in (`fresh`)
    property real sheetY: fitY
    property real sheetHeight: fitHeight
    property bool settled: false
    Behavior on sheetY { enabled: settings.settled; Anim { type: Anim.DefaultSpatial } }
    Behavior on sheetHeight { enabled: settings.settled; Anim { type: Anim.DefaultSpatial } }
    property real appear: 0
    property real fresh: 1
    NumberAnimation on appear { id: appearIn; running: false; from: 0; to: 1; duration: Theme.anim.expressiveDefaultEffectsDuration; easing.type: Easing.OutCubic }
    NumberAnimation on fresh { id: freshIn; running: false; from: 0; to: 1; duration: Theme.anim.expressiveDefaultEffectsDuration; easing.type: Easing.OutCubic }
    onFoldChanged: if (settled) freshIn.restart()
    frameOpacity: appear * fresh
    frameX: sheetX
    frameWidth: sheetWidth
    frameBottom: Math.max(0, height - sheetY - sheetHeight + padBottom)
    bareTop: sheetY + padTop
    columnX: 20
    columnWidth: sheetWidth - 40
    onSectionChanged: { flick.contentY = 0; scanZen() }
    // the sites and tabs Import offers to bring, counted from a copy of Zen's files whenever the section shows
    function scanZen() {
        if (visible && section === "import" && !shotState)
            Zen.scan();
    }
    onPressedOutside: expand = ""
    onVisibleChanged: {
        revealed = {};
        zenPrimary = "";
        settled = false;
        appear = visible ? 0 : 1;
        if (visible) {
            appearIn.restart();
            Qt.callLater(() => settings.settled = settings.visible);
            scanZen();
            Apps.lookUpDefault();
            if (!shotState)
                Passwords.refresh();
        }
    }
    // Saved passwords (PLAN.md 3.15): what Show brought out of the keyring ({ id: { secret } or { failure } }) and the
    // password an Edit holds, only while the page shows them; never saved anywhere
    property var revealed: ({})
    property string editSecret: ""
    onSubChanged: { revealed = {}; flick.contentY = 0 }
    onEditingChanged: if (!editing.startsWith("login:")) editSecret = ""
    // Zen's primary password as typed, while its passwords wait for it (the rows are made again as the state changes)
    property string zenPrimary: ""

    readonly property var extensionManager: profile ? profile.extensionManager ?? null : null
    // the extensions installed in the profile (not the engine's own, its PDF viewer's); the manager's list tells no change
    // (no notify), so it is read again on its signals
    property var extensions: []
    function readExtensions() {
        extensions = extensionManager ? extensionManager.extensions.filter(e => e.isInstalled)
            .map(e => ({ id: e.id, name: e.name, enabled: e.isEnabled, error: e.error })) : [];
    }
    onExtensionManagerChanged: readExtensions()
    readonly property var state: {
        tick;
        prefs.revision;
        const sitesNow = sites ? (sites.revision, sites.entries) : {};
        const langs = prefs.get("languages").length > 0 ? prefs.get("languages") : defaultLanguages;
        const s = {
            engine: prefs.get("engine"), defaultBrowser: Apps.isDefault, folder: folder, home: Engine.home,
            zoom: prefs.get("zoom"), fonts: Object.assign({}, engineFonts, profile ? Engine.fonts(profile) : {}), minimumFont: prefs.get("minimumFont"),
            languages: langs, spellCheck: prefs.get("spellCheck"), dictionaries: Engine.dictionaries(langs),
            allowed: sites ? Object.keys(sitesNow).filter(o => sites.choice(o, "ads") === "allow").sort() : [],
            // Sites: every origin with a choice of its own
            siteChoices: Object.keys(sitesNow).filter(o => Object.keys(sitesNow[o].choices || {}).length > 0).sort()
                .map(o => ({ origin: o, host: o.replace(/^https?:\/\//, ""), summary: Settings.siteSummary(sitesNow[o]) })),
            lists: adblock ? adblock.lists : [], updating: adblock ? adblock.updating : false, listFailure: prefs.get("listFailure"), listUpdated: prefs.get("listUpdated"),
            thirdPartyCookies: prefs.get("thirdPartyCookies"), httpsFirst: prefs.get("httpsFirst"),
            // only Clear browsing data shows these, and every cookie a page sets changes the count
            cookies: sub === "clear" && siteData ? (siteData.revision, siteData.allCookies()) : 0, clearing: sub === "clear" ? prefs.clearing : null,
            extensions: extensions,
            extensionsInstall: extensionManager !== null,
            passwords: { state: Passwords.state, entries: Passwords.entries, removing: Passwords.removing, revealed: revealed },
            zen: { profile: Zen.profile.path ? Zen.profile : null, browser: Zen.browser, state: Zen.state, wrong: Zen.wrong, logins: Zen.logins, run: zenRun,
                   sites: Zen.sites, tabs: Zen.tabs, cookies: prefs.get("zenCookies"), openTabs: prefs.get("zenTabs"),
                   last: prefs.get("zenImport"), failure: prefs.get("zenFailure") },
            versions: Engine.versions, now: Date.now(),
        };
        return shotState ? Object.assign(s, shotState) : s;
    }
    readonly property var rows: Settings.rows(state, sub, filter)
    // what the page draws: the section's rows, or with words searched for (or in a view) all that are left
    // the fold the section belongs to (Settings.folds): its members' rows, each member's name over its run where it has
    // several
    readonly property var fold: Settings.foldOf(section)
    readonly property var shown: filter !== "" || sub !== "" ? rows.filter(r => r.kind !== "back")
        : rows.filter(r => fold.members.indexOf(r.section) >= 0 && (r.kind !== "head" || fold.members.length > 1))
    // the rows in runs, each on a tile: a section's name (searching) or a key group starts one, a note closes one under it
    readonly property var blocks: {
        const out = [];
        let at = null;
        const open = title => { at = { title: title, rows: [], note: "" }; out.push(at); };
        for (const r of shown) {
            if (r.kind === "head" || r.kind === "group")
                open(r.label);
            else if (r.kind === "note") {
                if (!at)
                    open("");
                at.note = at.note ? at.note + "\n" + r.label : r.label;
                at = null;
            } else {
                if (!at)
                    open("");
                at.rows.push(r);
            }
        }
        return out;
    }
    // the folds in the side list: those with rows that hold the words searched for
    readonly property var sections: (filter === "" || sub !== "" ? Settings.folds
        : Settings.folds.filter(f => rows.some(r => r.kind === "head" && f.members.indexOf(r.section) >= 0))).map(f => f.key)
    // a fold shows from its first member; a member is shown in its fold
    function openSection(name) {
        filter = "";
        sub = "";
        expand = "";
        editing = "";
        const f = Settings.folds.find(f => f.key === name);
        section = f ? f.members[0] : name;
    }
    function stepSection(by) {
        const at = sections.indexOf(fold.key), next = sections[Math.max(0, Math.min(sections.length - 1, at + by))];
        if (next)
            openSection(next);
    }
    // the section that holds the row a target belongs to ("own:zoom:plus": Pages) shown, when it is not
    function reach(name) {
        if (sub !== "" || filter !== "" || target(name))
            return;
        const key = name.replace(/^own:/, "");
        const row = rows.find(r => r.section && r.kind !== "head" && (key === r.key || key.startsWith(r.key + ":") || key.startsWith(r.key + "=")));
        if (row && row.section !== section) {
            section = row.section;
            layout();
        }
    }
    Connections {
        target: settings.extensionManager
        ignoreUnknownSignals: true
        // Qt 6.11 installs an extension disabled (measured): one installed here is meant to run
        function onInstallFinished(extension) {
            if (extension.isInstalled && !extension.isEnabled && extension.error === "")
                settings.extensionManager.setExtensionEnabled(extension, true);
            settings.readExtensions();
        }
        function onUninstallFinished() { settings.readExtensions() }
        function onLoadFinished() { settings.readExtensions() }
        function onUnloadFinished() { settings.readExtensions() }
    }
    Connections {
        target: Engine
        function onConverted() { settings.tick++ }
    }
    Connections {
        target: settings.prefs
        function onChanged(key) { if (key === "fonts") Qt.callLater(() => settings.tick++) }
    }
    // Zen's passwords wait for its primary password: the keys go to the field that asks for it
    Connections {
        target: Zen
        function onStateChanged() {
            if (Zen.state !== "password")
                settings.zenPrimary = "";
            if (Zen.state !== "password" || !settings.visible)
                return;
            Qt.callLater(() => {
                const t = settings.target("own:zen-primary:input");
                if (t) {
                    t.forceActiveFocus(Qt.TabFocusReason);
                    settings.reveal(t);
                }
            });
        }
    }

    // browser://settings/<section>: that section (a fold's name or one of its members'), as a link or the address card asks
    readonly property string addressed: view ? ((/^browser:\/\/settings\/([a-z]+)/i.exec(String(view.url)) ?? [])[1] ?? "").toLowerCase() : ""
    onAddressedChanged: if (addressed !== "") show(addressed)
    // Main: Ctrl+/ at Keys, Ctrl+Shift+Delete at Clear browsing data, Ctrl+, where it was
    function show(name) {
        if (!name)
            return;
        expand = "";
        editing = "";
        filter = "";
        if (name === "clear") {
            section = "privacy";
            sub = "clear";
            // after the page has taken the keys (OwnPage.take, queued as its view got them)
            Qt.callLater(() => { const t = target("own:clear:history:action"); if (t) t.forceActiveFocus(Qt.TabFocusReason) });
            return;
        }
        sub = "";
        const f = Settings.folds.find(f => f.key === name);
        if (f)
            section = f.members[0];
        else if (Settings.order.indexOf(name) >= 0) {
            section = name;
            // a member after the fold's first: its run at the top (Ctrl+/ at Keys)
            if (fold.members.indexOf(name) > 0)
                Qt.callLater(() => settings.toRun(name));
        }
    }
    function toRun(name) {
        layout();
        const run = runs.itemAt(blocks.findIndex(b => b.title === Settings.titles[name]));
        if (run)
            flick.contentY = Math.max(0, Math.min(run.y, flick.contentHeight - flick.height));
    }
    // "head:<section>" shows that section
    function scrollTo(name) {
        if (name.startsWith("head:"))
            show(name.slice(5));
    }

    back: mods => {
        if (expand !== "") {
            const k = expand;
            expand = "";
            refocus("own:" + k);
        } else if (editing !== "") {
            const k = editing;
            editing = "";
            refocus("own:" + k);
        } else if (sub !== "") {
            const k = sub;
            sub = "";
            refocus("own:" + k);
        } else if (filter !== "") {
            filter = "";
            first.forceActiveFocus();
        } else if (!mods) {
            leave();
        } else {
            // Shift+Esc and the like are Main's (Pages and memory)
            return false;
        }
        return true;
    }

    // What the rows do. Extensions: On and Off enable it, Remove uninstalls it.
    function choose(key, v) {
        expand = "";
        if (key.startsWith("ext:")) {
            const info = extensionManager ? extensionManager.extensions.find(e => e.id === key.slice(4)) : undefined;
            if (info === undefined)
                return;
            if (v === "remove")
                extensionManager.uninstallExtension(info);
            else
                extensionManager.setExtensionEnabled(info, v === "on");
            readExtensions();
            return;
        }
        prefs.set(key, v);
    }
    function step(key, delta) {
        if (key === "zoom")
            prefs.set("zoom", Site.zoomStep(state.zoom, delta));
        else if (key === "fontSize")
            prefs.set("fonts", Object.assign({}, prefs.get("fonts"), { size: Settings.stepIn(Settings.fontSizes, state.fonts.size, delta) }));
        else if (key === "minimumFont")
            prefs.set("minimumFont", Settings.stepIn(Settings.minimumSizes, state.minimumFont, delta));
    }
    function act(key) {
        if (key === "defaultBrowser")
            Apps.makeDefault();
        else if (key === "update" && adblock)
            adblock.update();
        else if (key.startsWith("allowed:"))
            sites.setChoice(key.slice(8), "ads", "");
        else if (key.startsWith("forget:") && sites) {
            const origin = key.slice(7), e = sites.entries[origin];
            for (const type of Object.keys((e && e.choices) || {}))
                sites.setChoice(origin, type, "");
        }
        else if (key.startsWith("clear:"))
            prefs.startClear(key.slice(6));
        else if (key === "undo")
            prefs.undoClear();
        else if (key === "install")
            pick("extension");
        else if (key.startsWith("undelete:"))
            Passwords.keep(key.slice(9));
        else if (key === "zen")
            importWanted();
        else if (key === "passwordFile")
            passwordFileWanted();
        else if (key === "browserImport")
            browserImportWanted();
    }
    // A saved password's Show (Hide once shown), Edit and Delete. Show and Edit read it from the keyring, which may ask
    // to unlock it first; what did not come out says why under the login.
    function showSecret(id) {
        if (revealed[id] && revealed[id].secret !== undefined) {
            revealed = Object.assign({}, revealed, { [id]: undefined });
            return;
        }
        Passwords.secret(id, false, (secret, failure) => {
            if (settings.visible)
                settings.revealed = Object.assign({}, settings.revealed, { [id]: secret !== undefined ? { secret: secret } : { failure: failure } });
        });
    }
    function editLogin(row) {
        expand = "";
        Passwords.secret(row.id, false, (secret, failure) => {
            if (!settings.visible)
                return;
            if (secret === undefined) {
                settings.revealed = Object.assign({}, settings.revealed, { [row.id]: { failure: failure } });
                return;
            }
            settings.edit(row.key, row.value);
            settings.editSecret = secret;
            Qt.callLater(() => { const t = settings.target("own:" + row.key + ":user"); if (t) { t.forceActiveFocus(); t.selectAll() } });
        });
    }
    // Done: the user name and password as edited (a password left empty keeps the saved one)
    function commitLogin(row) {
        const user = editText.trim(), secret = editSecret;
        editing = "";
        revealed = Object.assign({}, revealed, { [row.id]: undefined });
        Passwords.edit(row.id, user, secret, (ok, failure) => {
            if (!ok && settings.visible)
                settings.revealed = Object.assign({}, settings.revealed, { [row.id]: { failure: failure, what: "save" } });
        });
    }
    function openView(key) {
        expand = "";
        editing = "";
        // the section whose row opens it, for ‹ and the side list
        const from = rows.find(r => r.key === key && r.section);
        if (from)
            section = from.section;
        sub = key;
    }
    function edit(key, text) {
        expand = "";
        editing = key;
        editText = text;
    }
    // a font's family ("" is the engine's own) or the languages, typed
    function commit(key, text) {
        editing = "";
        if (key === "languages")
            prefs.set("languages", Settings.languages(text));
        else if (key.startsWith("font:"))
            prefs.set("fonts", Object.assign({}, prefs.get("fonts"), { [key.slice(5)]: text.trim() }));
    }
    // Files picks the Downloads folder, or an extension's folder or .zip (PLAN.md 3.15), as it picks for file inputs
    function pick(what) {
        if (Picker.pick(what === "folder" ? "Downloads folder · select it, then Choose" : "An extension's folder or .zip · select it, then Choose"))
            picking = what;
    }
    Connections {
        target: settings.picking !== "" ? Picker : null
        function onFinished(paths) {
            const what = settings.picking, path = paths[0] ?? "";
            settings.picking = "";
            if (what === "folder" && path && Facts.isFolder(path))
                settings.prefs.set("folder", path);
            else if (what === "extension" && path && settings.extensionManager)
                settings.extensionManager.installExtension(path);
        }
    }

    // Tacit Settings' roles the rest of the browser has no use for
    readonly property color onPrimary: Theme.role("on_primary", "#452b1e")
    readonly property color outline: Theme.role("outline", "#948f8f")
    readonly property color highest: Theme.role("surface_container_highest", "#353534")
    FontMetrics {
        id: chipMetrics
        font.family: Theme.font.main
        font.pixelSize: Theme.font.caption
    }

    // the sheet, one silhouette with the rail (or, folded, with the face this page draws), on the window's own ground
    under: [
        Rectangle {
            visible: !settings.railFace
            width: settings.faceWidth
            height: settings.height
            color: Theme.terminal
        },
        Cove {
            x: settings.sheetX
            y: settings.sheetY
            width: settings.sheetWidth
            height: settings.sheetHeight
            opacity: settings.appear
            color: Theme.terminal
        }
    ]
    // folded: the settings face at the page's left, as the rail draws it docked
    side: SettingsRail {
        id: pageFace
        visible: !settings.railFace
        y: 18
        width: settings.faceWidth
        height: settings.height - y
        settings: settings
    }

    // ── the sheet's rows: its opening line, then the rows in runs, a member's name over its run where there are several
    // the opening sentence as markup: the parts Settings.lead gives, the cause in the accent
    readonly property string leadMarkup: Settings.lead(fold, state, behind).map(p => {
        const t = String(p[0]).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return p[1] ? "<font color='" + Theme.accent + "'>" + t + "</font>" : t;
    }).join("")
    Item {
        id: mark
        width: settings.columnWidth
        height: settings.sub !== "" ? 70 : settings.filter !== "" ? 26 : settings.leadMarkup !== "" ? leadText.implicitHeight + 4 : 0
        // a section: what it is set to now, in one sentence
        Label {
            id: leadText
            visible: settings.sub === "" && settings.filter === ""
            x: 16
            width: parent.width - 32
            text: settings.leadMarkup
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            lineHeight: 1.25
            font.pixelSize: Theme.font.large
            color: Theme.inkMain
        }
        // a view in place: ‹ and its section's name to go back, the view's name under it
        OwnHit {
            visible: settings.sub !== ""
            name: "own:back"
            scope: settings
            x: 6
            y: -4
            radius: Theme.rounding.verysmall
            width: backText.implicitWidth + 36
            height: 28
            onActivated: keyed => { const k = settings.sub; settings.sub = ""; if (keyed) settings.refocus("own:" + k) }
            Symbol {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "chevron_left"
                iconSize: 18
            }
            Label {
                id: backText
                x: 26
                anchors.verticalCenter: parent.verticalCenter
                text: settings.fold.title
                font.pixelSize: Theme.font.caption
                color: Theme.inkSec
            }
        }
        Label {
            visible: settings.sub !== ""
            x: 16
            y: 32
            width: parent.width - 32
            text: settings.rows.length > 0 && settings.rows[0].kind === "back" ? settings.rows[0].label : ""
            font.pixelSize: 22
            font.family: Theme.font.display
            weight: Font.Medium
            color: Theme.inkMain
        }
        // searching: what was looked for, or that nothing holds it
        Label {
            visible: settings.sub === "" && settings.filter !== ""
            x: 16
            width: parent.width - 32
            text: settings.blocks.length > 0 ? "Settings with “" + settings.filter + "”" : "No setting holds “" + settings.filter + "”"
            font.pixelSize: Theme.font.body
            color: Theme.inkSec
        }
    }

    Repeater {
        id: runs
        model: settings.visible ? settings.blocks : []
        delegate: Column {
            id: block
            required property var modelData
            required property int index
            // a list out over the rows under it draws over the runs after this one
            z: modelData.rows.some(r => r.key === settings.expand) ? 2 : 0
            width: settings.columnWidth
            topPadding: index > 0 ? 22 : mark.height > 0 ? 14 : 0
            Label {
                visible: block.modelData.title !== ""
                x: 16
                width: parent.width - 32
                height: 24
                text: block.modelData.title
                font.pixelSize: Theme.font.smaller
                weight: Font.Medium
                color: Theme.inkMeta
            }
            Column {
                id: tileRows
                visible: block.modelData.rows.length > 0
                width: parent.width
                Repeater {
                    model: block.modelData.rows
                    delegate: Item {
                        id: rowHolder
                        required property var modelData
                        z: modelData.key === settings.expand ? 2 : 0
                        width: tileRows.width
                        height: rowLoader.height
                        Loader {
                            id: rowLoader
                            readonly property var row: rowHolder.modelData
                            width: parent.width
                            sourceComponent: ({ choice: choiceKind, step: stepKind, pair: pairKind, action: actionKind, link: linkKind, field: fieldKind,
                                                pick: linkKind, login: loginKind, secret: secretKind, identity: identityKind })[rowHolder.modelData.kind] ?? null
                        }
                    }
                }
            }
            Label {
                visible: block.modelData.note !== ""
                x: 16
                width: parent.width - 32
                topPadding: 6
                text: block.modelData.note
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                lineHeight: 1.2
                font.pixelSize: Theme.font.smaller
                color: Theme.inkSec
            }
        }
    }

    // ── the parts rows are made of (modules/settings: SettingRow, Toggle, ChoiceRow, StepperRow, TextButton, LineField)
    // what a row is (15 px) and, when it says more, what it means or holds (13 px)
    component RowText: Column {
        property string label
        property string detail
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Label {
            width: parent.width
            text: parent.label
            font.pixelSize: Theme.font.body
            wrapMode: Text.Wrap
            color: Theme.inkMain
        }
        Label {
            visible: parent.detail !== ""
            width: parent.width
            text: parent.detail
            font.pixelSize: Theme.font.smaller
            color: Theme.inkSec
            wrapMode: Text.Wrap
            maximumLineCount: 3
        }
    }
    // the whole row as the target, inset 4 px so its wash keeps inside the tile's corners
    component RowHit: OwnHit {
        scope: settings
        anchors.fill: parent
        anchors.margins: 4
        radius: Theme.rounding.small
    }
    // a ring, as Slab's quiet one (1 px of the main ink at 30 %, 32 px, 14 px words); `forward`, the way forward a row
    // recommends (Make default): the accent's ring, its word Medium
    component RowButton: OwnHit {
        property alias label: buttonText.text
        property bool forward: false
        scope: settings
        outlined: true
        outline: forward ? Theme.transparentize(Theme.accent, 0.25) : Theme.transparentize(Theme.inkMain, 0.7)
        radius: height / 2
        width: buttonText.implicitWidth + (forward ? 40 : 32)
        height: 32
        Label {
            id: buttonText
            anchors.centerIn: parent
            font.pixelSize: Theme.font.caption
            weight: parent.forward ? Font.Medium : Theme.font.mainAxes.wght
            color: parent.forward ? Theme.inkMain : Theme.inkSec
        }
    }
    // a glyph button, as the stepper's
    component GlyphButton: OwnHit {
        property alias glyph: glyphText.text
        scope: settings
        radius: height / 2
        width: 30
        height: 30
        Symbol {
            id: glyphText
            anchors.centerIn: parent
            iconSize: 18
            color: Theme.colOnLayer0
        }
    }
    // Tacit Settings' switch (modules/settings/Toggle.qml): on is the primary track with a dark knob, off a dark track
    // with a grey knob and an outline
    component Toggle: Item {
        property bool checked
        width: 40
        height: 24
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: parent.checked ? Theme.primary : settings.highest
            border.width: 1
            border.color: parent.checked ? Qt.rgba(1, 1, 1, 0.06) : settings.outline
            Behavior on color { CAnim {} }
        }
        Rectangle {
            x: parent.checked ? parent.width - width - 2 : 2
            y: 2
            width: 20
            height: 20
            radius: 10
            color: parent.checked ? settings.onPrimary : settings.outline
            Behavior on x { Anim { type: Anim.FastSpatial } }
            Behavior on color { CAnim {} }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.55)
                shadowVerticalOffset: 2
                shadowBlur: 0.4
            }
        }
    }
    // Tacit Settings' LineField: a box for words typed in a row
    component Field: Rectangle {
        property alias input: fieldInput
        property string placeholder
        signal edited(string text)
        signal accepted()
        width: 260
        height: 32
        radius: Theme.rounding.small
        color: Theme.transparentize(Theme.colLayer2, 0.2)
        border.width: 1
        border.color: fieldInput.activeFocus ? Theme.primary : Theme.transparentize(Theme.outlineVariant, 0.4)
        TextInput {
            id: fieldInput
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            font.family: Theme.font.main
            font.hintingPreference: Font.PreferNoHinting
            font.pixelSize: Theme.font.caption
            font.variableAxes: Theme.font.mainAxes
            passwordCharacter: "•"
            color: Theme.colOnLayer0
            selectionColor: Theme.transparentize(Theme.primary, 0.6)
            selectedTextColor: Theme.colOnLayer0
            selectByMouse: true
            renderType: Text.NativeRendering
            onTextEdited: parent.edited(text)
            Keys.onReturnPressed: parent.accepted()
            Keys.onEnterPressed: parent.accepted()
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: fieldInput.text.length === 0
                text: parent.parent.placeholder
                font.pixelSize: Theme.font.caption
                color: Theme.colSubtext
            }
        }
    }

    // One of a few. On and Off is a switch, the row its target. Up to three choices that fit in about half the row sit
    // side by side; more is the row naming the current one, which lays the list out under it, over the rows below.
    // An extension's row is a switch with Remove beside it.
    Component {
        id: choiceKind
        Item {
            id: choiceRow
            readonly property var row: parent.row
            readonly property var options: Settings.choices(row.key)
            readonly property bool ext: row.key.startsWith("ext:")
            readonly property var onOff: {
                const on = options.find(o => o.label === "On"), off = options.find(o => o.label === "Off");
                return on && off && (ext || options.length === 2) ? { on: on.value, off: off.value } : null;
            }
            readonly property real chipsWidth: options.reduce((w, o) => w + chipMetrics.advanceWidth(o.label) + 28, 0)
            readonly property bool inline: !onOff && options.length <= 3 && chipsWidth <= width * 0.55
            readonly property bool out: settings.expand === row.key
            readonly property bool failed: ext && row.picked !== "on" && row.picked !== "off"
            // the switch moves first, the setting follows once it has (the rows are made again when a setting changes)
            property bool flipped: false
            readonly property bool checked: onOff !== null && ((row.picked === onOff.on) !== flipped)
            function flip(keyed) {
                if (flipTimer.running)
                    return;
                flipped = true;
                flipTimer.keyed = keyed;
                flipTimer.start();
            }
            Timer {
                id: flipTimer
                property bool keyed: false
                interval: Theme.anim.expressiveFastSpatialDuration
                onTriggered: {
                    const key = choiceRow.row.key, keyed = flipTimer.keyed;
                    settings.choose(key, choiceRow.row.picked === choiceRow.onOff.on ? choiceRow.onOff.off : choiceRow.onOff.on);
                    if (keyed)
                        settings.refocus("own:" + key);
                }
            }
            width: parent.width
            height: Math.max(choiceText.detail !== "" ? 62 : 48, choiceText.implicitHeight + 24)
            // on and off
            RowHit {
                visible: choiceRow.onOff !== null
                name: visible ? "own:" + choiceRow.row.key : ""
                onActivated: keyed => choiceRow.flip(keyed)
            }
            // more than three: the whole row opens the list
            RowHit {
                visible: choiceRow.onOff === null && !choiceRow.inline
                name: visible ? "own:" + choiceRow.row.key : ""
                picked: choiceRow.out
                onActivated: keyed => {
                    const key = choiceRow.row.key, was = choiceRow.out;
                    settings.editing = "";
                    settings.expand = was ? "" : key;
                    if (keyed)
                        settings.refocus(was ? "own:" + key : "own:" + key + "=" + String(choiceRow.row.picked));
                }
            }
            RowText {
                id: choiceText
                width: parent.width - 48 - choiceRight.width
                label: choiceRow.row.label
                detail: choiceRow.failed ? String(choiceRow.row.picked) : ""
            }
            Row {
                id: choiceRight
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 4
                RowButton {
                    visible: choiceRow.ext
                    name: visible ? "own:" + choiceRow.row.key + ":remove" : ""
                    label: "Remove"
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: settings.choose(choiceRow.row.key, "remove")
                }
                Item {
                    visible: choiceRow.ext
                    width: 8
                    height: 1
                }
                Toggle {
                    visible: choiceRow.onOff !== null
                    anchors.verticalCenter: parent.verticalCenter
                    checked: choiceRow.checked
                }
                Repeater {
                    model: choiceRow.inline ? choiceRow.options : []
                    delegate: OwnHit {
                        required property var modelData
                        name: "own:" + choiceRow.row.key + "=" + String(modelData.value)
                        scope: settings
                        picked: choiceRow.row.picked === modelData.value
                        outlined: !picked
                        outline: Theme.transparentize(Theme.inkMain, 0.7)
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: chipText.implicitWidth + 28
                        height: 30
                        onActivated: keyed => {
                            const key = choiceRow.row.key;
                            settings.choose(key, modelData.value);
                            if (keyed)
                                settings.refocus("own:" + key + "=" + String(modelData.value));
                        }
                        Label {
                            id: chipText
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            font.pixelSize: Theme.font.caption
                            color: parent.picked ? Theme.inkMain : Theme.inkSec
                        }
                    }
                }
                // the current choice; the row lays the others out under it
                Label {
                    visible: choiceRow.onOff === null && !choiceRow.inline
                    anchors.verticalCenter: parent.verticalCenter
                    text: choiceRow.row.value
                    font.pixelSize: Theme.font.body
                    color: choiceRow.out ? Theme.inkMain : Theme.inkSec
                }
            }
            // the list, under the row's right end, over what lies below
            Rectangle {
                visible: choiceRow.out
                anchors { right: parent.right; rightMargin: 8; top: parent.bottom; topMargin: 2 }
                width: 240
                height: choiceList.height + 12
                radius: Theme.rounding.small
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.transparentize(Theme.outlineVariant, 0.3)
                Column {
                    id: choiceList
                    x: 6
                    y: 6
                    width: parent.width - 12
                    Repeater {
                        model: choiceRow.out ? choiceRow.options : []
                        delegate: OwnHit {
                            required property var modelData
                            name: "own:" + choiceRow.row.key + "=" + String(modelData.value)
                            scope: settings
                            picked: choiceRow.row.picked === modelData.value
                            radius: Theme.rounding.small
                            width: choiceList.width
                            height: 36
                            onActivated: keyed => {
                                const key = choiceRow.row.key;
                                settings.choose(key, modelData.value);
                                if (keyed)
                                    settings.refocus("own:" + key);
                            }
                            Label {
                                x: 12
                                width: parent.width - 48
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.label
                                font.pixelSize: Theme.font.caption
                            }
                            Symbol {
                                visible: parent.picked
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: "check"
                                iconSize: 18
                                color: Theme.primary
                            }
                        }
                    }
                }
            }
        }
    }
    // − value +, as Tacit Settings' stepper
    Component {
        id: stepKind
        Item {
            id: stepRow
            readonly property var row: parent.row
            width: parent.width
            height: 48
            RowText {
                width: parent.width - 48 - stepper.width
                label: stepRow.row.label
            }
            // − value + in one quiet ring
            Rectangle {
                anchors { fill: stepper; margins: -2 }
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.transparentize(Theme.inkMain, 0.7)
            }
            Row {
                id: stepper
                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 0
                GlyphButton {
                    name: "own:" + stepRow.row.key + ":minus"
                    glyph: "remove"
                    onActivated: keyed => { settings.step(stepRow.row.key, -1); if (keyed) settings.refocus(name) }
                }
                Label {
                    // fits "100 %" and "16 px", so the minus of every stepper on a page lines up
                    width: 64
                    height: 30
                    horizontalAlignment: Text.AlignHCenter
                    text: stepRow.row.value
                    font.pixelSize: Theme.font.body
                    font.features: { "tnum": 1 }
                    weight: Font.Medium
                    color: Theme.inkMain
                }
                GlyphButton {
                    name: "own:" + stepRow.row.key + ":plus"
                    glyph: "add"
                    onActivated: keyed => { settings.step(stepRow.row.key, 1); if (keyed) settings.refocus(name) }
                }
            }
        }
    }
    // About's tile, as Tacit Settings' About opens: the name set in type (no Opsis mark yet), its version, what it is
    // built on
    Component {
        id: identityKind
        Column {
            readonly property var row: parent.row
            width: parent.width
            padding: 20
            spacing: 4
            Label {
                width: parent.width - 40
                text: parent.row.label
                font.pixelSize: 30
                font.family: Theme.font.display
                weight: Font.Medium
            }
            Label {
                width: parent.width - 40
                text: parent.row.value
                font.pixelSize: 15
                color: Theme.colSubtext
            }
            Label {
                visible: text !== ""
                width: parent.width - 40
                topPadding: 4
                text: parent.row.detail
                font.pixelSize: Theme.font.smaller
                color: Theme.colSubtext
            }
        }
    }
    // what something is: the value at the right edge, or under the label when it is too long for it; a key list row
    // names the keys at the right
    Component {
        id: pairKind
        Item {
            id: pairRow
            readonly property var row: parent.row
            readonly property bool keys: row.key.startsWith("key:")
            readonly property bool under: !keys && pairValue.implicitWidth > width * 0.45
            width: parent.width
            height: Math.max(pairText.detail !== "" ? 62 : 48, pairText.implicitHeight + 24, under ? 0 : pairValue.implicitHeight + 24)
            RowText {
                id: pairText
                width: parent.width - 32 - (pairRow.under ? 0 : pairValue.width + 16)
                label: pairRow.row.label
                detail: pairRow.under ? pairRow.row.value : ""
            }
            Label {
                id: pairValue
                visible: !pairRow.under
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, Math.round(parent.width * (pairRow.keys ? 0.4 : 0.45)))
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                text: pairRow.row.value
                font.pixelSize: pairRow.keys ? Theme.font.caption : Theme.font.body
                font.features: { "tnum": 1 }
                color: pairRow.keys ? Theme.inkMain : Theme.inkSec
            }
        }
    }
    // something to do: what it is and what it last did, the button that does it (Make default, Update now, Clear,
    // Remove, Choose, Undo, Import); `plain`, the row itself is the action (Undo)
    Component {
        id: actionKind
        Item {
            id: actionRow
            readonly property var row: parent.row
            width: parent.width
            height: Math.max(actionText.detail !== "" ? 62 : 48, actionText.implicitHeight + 24)
            RowHit {
                visible: actionRow.row.plain === true
                name: visible ? "own:" + actionRow.row.key : ""
                onActivated: keyed => settings.act(actionRow.row.key)
            }
            RowText {
                id: actionText
                width: parent.width - 48 - (actionButton.visible ? actionButton.width : 0)
                label: actionRow.row.label
                detail: actionRow.row.plain === true ? "" : actionRow.row.detail || actionRow.row.value || ""
            }
            RowButton {
                id: actionButton
                visible: actionRow.row.plain !== true && actionRow.row.action !== ""
                name: visible ? "own:" + actionRow.row.key + ":action" : ""
                label: actionRow.row.action
                forward: actionRow.row.key === "defaultBrowser" && actionRow.row.action === "Make default"
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                onActivated: keyed => { settings.act(actionRow.row.key); if (keyed) settings.refocus(name) }
            }
        }
    }
    // a count or a value and › (a view in place), or a folder picked in Files: the row is the target
    Component {
        id: linkKind
        Item {
            id: linkRow
            readonly property var row: parent.row
            width: parent.width
            height: 48
            RowHit {
                name: "own:" + linkRow.row.key
                onActivated: keyed => {
                    const r = linkRow.row;
                    if (r.kind === "pick") {
                        settings.pick(r.key);
                        return;
                    }
                    settings.openView(r.key);
                    if (keyed)
                        settings.refocus("own:back");
                }
            }
            // the value says what is there; a view with nothing to say has the chevron, a folder Files' glyph
            readonly property bool glyphed: row.kind === "pick" || row.value === ""
            RowText {
                width: parent.width - 60 - linkValue.width
                label: linkRow.row.label
            }
            Label {
                id: linkValue
                anchors { right: parent.right; rightMargin: linkRow.glyphed ? 42 : 16; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, Math.round(parent.width * 0.5))
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: linkRow.row.value
                font.pixelSize: Theme.font.body
                color: Theme.inkSec
            }
            Symbol {
                visible: linkRow.glyphed
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: linkRow.row.kind === "pick" ? "folder_open" : "chevron_right"
                iconSize: 18
                color: Theme.inkMeta
            }
        }
    }
    // a value edited in place: the languages, a font's family with the installed families that hold the words typed
    Component {
        id: fieldKind
        Item {
            id: fieldRow
            readonly property var row: parent.row
            readonly property bool editing: settings.editing === row.key
            readonly property bool font: row.key.startsWith("font:")
            readonly property var offered: editing && font ? Settings.families(Engine.families(row.key === "font:fixed"), settings.editText) : []
            width: parent.width
            height: editing && font ? 56 + familyFlow.height : 48
            RowHit {
                visible: !fieldRow.editing
                name: visible ? "own:" + fieldRow.row.key : ""
                onActivated: keyed => {
                    settings.edit(fieldRow.row.key, fieldRow.row.value);
                    Qt.callLater(() => { editBox.input.forceActiveFocus(); editBox.input.selectAll() });
                }
            }
            RowText {
                anchors.verticalCenter: undefined
                y: Math.round((48 - implicitHeight) / 2)
                width: parent.width - 48 - (fieldRow.editing ? editBox.width : fieldValue.width)
                label: fieldRow.row.label
            }
            Label {
                id: fieldValue
                visible: !fieldRow.editing
                anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: 14 }
                width: Math.min(implicitWidth, Math.round(parent.width * 0.5))
                horizontalAlignment: Text.AlignRight
                text: fieldRow.row.value
                font.pixelSize: Theme.font.body
                color: Theme.inkSec
            }
            Field {
                id: editBox
                visible: fieldRow.editing
                anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 8 }
                width: Math.round(parent.width * 0.5)
                input.objectName: "own:" + fieldRow.row.key + ":input"
                input.text: settings.editText
                onEdited: text => settings.editText = text
                onAccepted: { settings.commit(fieldRow.row.key, input.text); settings.refocus("own:" + fieldRow.row.key) }
            }
            // a font: the engine's own (Default) and the families that hold the words typed, at most 5
            Flow {
                id: familyFlow
                visible: fieldRow.editing && fieldRow.font
                x: 12
                y: 48
                width: parent.width - 24
                spacing: 4
                Repeater {
                    model: fieldRow.font && fieldRow.editing ? [{ family: "", label: "Default" }].concat(fieldRow.offered.map(f => ({ family: f, label: f }))) : []
                    delegate: OwnHit {
                        required property var modelData
                        name: "own:" + fieldRow.row.key + "=" + modelData.family
                        scope: settings
                        outlined: true
                        radius: Theme.rounding.small
                        width: familyText.implicitWidth + 24
                        height: 30
                        onActivated: keyed => { settings.commit(fieldRow.row.key, modelData.family); if (keyed) settings.refocus("own:" + fieldRow.row.key) }
                        Label {
                            id: familyText
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            font.pixelSize: Theme.font.caption
                        }
                    }
                }
            }
        }
    }
    // a saved password: the host, its user name under it, Show and glyph buttons for Edit and Delete; shown, the password
    // (or why it did not come out) on a third line. Edit lays out User and Password fields in the row, with Done; Enter
    // is Done, Esc leaves it.
    Component {
        id: loginKind
        Item {
            id: loginRow
            readonly property var row: parent.row
            readonly property bool editing: settings.editing === row.key
            readonly property var shown: row.shown
            width: parent.width
            height: editing ? 172 : shown ? 84 : 62
            Column {
                visible: !loginRow.editing
                x: 16
                y: 12
                width: parent.width - 48 - loginActions.width
                spacing: 2
                Label {
                    width: parent.width
                    text: loginRow.row.label
                    elide: Text.ElideLeft
                    font.pixelSize: Theme.font.body
                }
                Label {
                    width: parent.width
                    text: loginRow.row.value
                    font.pixelSize: Theme.font.smaller
                    color: Theme.colSubtext
                }
                // the password, which you can select to copy with the keys (a click, then Ctrl+A and Ctrl+C), or why it
                // did not come out or was not saved. Not with the mouse: Qt Quick copies a mouse selection into the
                // primary selection, which every client of the display can read and clipboard managers keep.
                TextInput {
                    visible: loginRow.shown !== null
                    width: parent.width
                    height: 22
                    readOnly: true
                    selectByMouse: false
                    clip: true
                    text: !loginRow.shown ? "" : loginRow.shown.secret !== undefined ? loginRow.shown.secret
                                                                                      : Logins.failed(loginRow.shown.what ?? "show", loginRow.shown.failure)
                    font.family: Theme.font.main
                    font.hintingPreference: Font.PreferNoHinting
                    font.pixelSize: loginRow.shown && loginRow.shown.secret !== undefined ? Theme.font.body : Theme.font.smaller
                    font.variableAxes: Theme.font.mainAxes
                    color: loginRow.shown && loginRow.shown.secret !== undefined ? Theme.colOnLayer0 : Theme.colSubtext
                    selectionColor: Theme.transparentize(Theme.primary, 0.6)
                    selectedTextColor: Theme.colOnLayer0
                    renderType: Text.NativeRendering
                }
            }
            Row {
                id: loginActions
                visible: !loginRow.editing
                anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 16 }
                spacing: 4
                RowButton {
                    name: visible ? "own:" + loginRow.row.key : ""
                    label: loginRow.shown && loginRow.shown.secret !== undefined ? "Hide" : "Show"
                    onActivated: keyed => { settings.showSecret(loginRow.row.id); if (keyed) settings.refocus(name) }
                }
                GlyphButton {
                    name: visible ? "own:" + loginRow.row.key + ":edit" : ""
                    glyph: "edit"
                    onActivated: settings.editLogin(loginRow.row)
                }
                GlyphButton {
                    name: visible ? "own:" + loginRow.row.key + ":delete" : ""
                    glyph: "delete"
                    onActivated: keyed => {
                        const r = loginRow.row;
                        Passwords.removeLater(r.id);
                        if (keyed)
                            settings.refocus("own:undelete:" + r.id + ":action");
                    }
                }
            }
            Column {
                visible: loginRow.editing
                x: 16
                y: 12
                width: parent.width - 28
                spacing: 8
                Label {
                    width: parent.width
                    height: 22
                    text: loginRow.row.label
                    elide: Text.ElideLeft
                    font.pixelSize: Theme.font.body
                }
                Item {
                    width: parent.width
                    height: 32
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "User"
                        font.pixelSize: Theme.font.caption
                        color: Theme.colSubtext
                    }
                    Field {
                        x: 96
                        width: parent.width - 96
                        input.objectName: "own:" + loginRow.row.key + ":user"
                        input.text: loginRow.editing ? settings.editText : ""
                        onEdited: text => settings.editText = text
                        onAccepted: { settings.commitLogin(loginRow.row); settings.refocus("own:" + loginRow.row.key) }
                    }
                }
                Item {
                    width: parent.width
                    height: 32
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        font.pixelSize: Theme.font.caption
                        color: Theme.colSubtext
                    }
                    Field {
                        x: 96
                        width: parent.width - 96
                        input.objectName: "own:" + loginRow.row.key + ":password"
                        input.echoMode: TextInput.Password
                        input.text: loginRow.editing ? settings.editSecret : ""
                        onEdited: text => settings.editSecret = text
                        onAccepted: { settings.commitLogin(loginRow.row); settings.refocus("own:" + loginRow.row.key) }
                    }
                }
                Item {
                    width: parent.width
                    height: 30
                    RowButton {
                        name: loginRow.editing ? "own:" + loginRow.row.key + ":done" : ""
                        label: "Done"
                        anchors.right: parent.right
                        onActivated: keyed => { settings.commitLogin(loginRow.row); if (keyed) settings.refocus("own:" + loginRow.row.key) }
                    }
                }
            }
        }
    }
    // Zen's primary password (Import, while its passwords wait): typed in the row's box, Import and Skip after it; Enter
    // is Import. The text stays in the field until it is sent.
    Component {
        id: secretKind
        Item {
            id: secretRow
            readonly property var row: parent.row
            width: parent.width
            height: 56
            function send() {
                const primary = settings.zenPrimary;
                settings.zenPrimary = "";
                if (secretBox.input.activeFocus)
                    settings.forceActiveFocus();
                Zen.unlock(primary);
            }
            RowText {
                width: parent.width - 48 - secretRight.width
                label: secretRow.row.label
            }
            Row {
                id: secretRight
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 6
                Field {
                    id: secretBox
                    width: 220
                    input.objectName: "own:" + secretRow.row.key + ":input"
                    input.echoMode: TextInput.Password
                    input.text: settings.zenPrimary
                    placeholder: "Zen's primary password"
                    onEdited: text => settings.zenPrimary = text
                    onAccepted: secretRow.send()
                }
                RowButton {
                    name: "own:" + secretRow.row.key + ":import"
                    label: "Import"
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: keyed => { secretRow.send(); if (keyed) settings.refocus("own:zen:action") }
                }
                RowButton {
                    name: "own:" + secretRow.row.key + ":skip"
                    label: "Skip"
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: keyed => { Zen.skip(); if (keyed) settings.refocus("own:zen:action") }
                }
            }
        }
    }
}
