import QtQuick
import QtWebEngine
import "Find.js" as Find
import "RailRows.js" as RailRows

// Find in page (PLAN.md 3.8 8e): one find, on the page on screen. Main opens it (Ctrl+F, `/`, the / prefix)
// where the address card is: the pinned rail's card, or the overlay's while the rail is folded (3.5);
// FindCard draws it. It closes with Esc or when you leave it; findText("") then leaves the current match
// selected, as Chromium ends a find. "Also in this task" counts the words on at most 3 of the thread's
// other live pages (Find.others) with Find.countScript, 200 ms after the last change.
QtObject {
    id: finder

    required property var session
    property var viewOf: id => null         // Main: a page's view, or null when it has none
    property bool live: true                // false in shots: stand-in pages answer no script
    property bool open: false
    property string where: "rail"           // "rail" (the pinned rail's card) or "peek" (the overlay's, folded)
    property var view: null                 // the page find is on
    property string text: ""                // kept after it closes, for the next Ctrl+F
    property bool matchCase: false
    property var result: null               // { matches, active } for `text` on `view`
    property var hits: []                   // "Also in this task": [{ pageId, title, icon, count }]
    property string skipped: ""             // the section's last line
    property string waiting: ""             // Main: the host of an ask that waits until find closes
    property bool jumping: false            // Main.findOn: moving to another page's first match, find stays open
    readonly property string count: Find.count(text, result)

    signal jumpTo(string pageId)            // a click on an "Also in this task" row

    function show(v, t, w) {
        if (open && view !== v)
            stopOn(view);
        view = v;
        where = w;
        if (t !== undefined)
            text = t;
        result = null;
        open = true;
        search();
        others();
    }
    function hide() {
        if (!open)
            return;
        open = false;
        stopOn(view);
        view = null;
        result = null;
        hits = [];
        skipped = "";
        round++;
        othersTimer.stop();
        othersLimit.stop();
    }
    // Esc: closed, and the keys go back to the page, where the match stays selected
    function dismiss() {
        const v = view;
        hide();
        if (v)
            v.forceActiveFocus();
    }
    function setText(t) {
        if (t === text)
            return;
        text = t;
        if (!open)
            return;
        search();
        if (t === "") {
            round++;
            hits = [];
            skipped = "";
            othersTimer.stop();
        } else {
            othersTimer.restart();
        }
    }
    // next, or previous (`back`); Chromium wraps, and the count shows it going back to 1
    function step(back) {
        if (open && text !== "")
            call(text, flags() | (back ? WebEngineView.FindBackward : 0));
    }
    function toggleCase() {
        matchCase = !matchCase;
        if (open && text !== "") {
            search();
            othersTimer.restart();
        }
    }

    function flags() { return matchCase ? WebEngineView.FindCaseSensitively : 0 }
    // Qt WebEngine takes the text it was last given as "find next", which keeps the count and the case of
    // that search: the same text again (a case change, a new document, Ctrl+F again) ends it first, and
    // the new search starts at the match that stays selected.
    property string sent: ""
    function search() {
        if (text === "")
            result = null;
        if (text !== "" && text === sent)
            stopOn(view);
        call(text, flags());
    }
    // A new findText finishes the one before it at once, reported as no matches from inside the call: only
    // what arrives afterwards is this search's answer.
    property bool calling: false
    function call(t, f) {
        calling = true;
        view.findText(t, f);
        calling = false;
        sent = t;
    }
    function stopOn(v) {
        sent = "";
        if (!v || v.lifecycleState !== WebEngineView.LifecycleState.Active)
            return;
        calling = true;
        v.findText("");
        calling = false;
    }
    property Connections page: Connections {
        target: finder.open ? finder.view : null
        ignoreUnknownSignals: true
        function onFindTextFinished(r) {
            if (!finder.calling)
                finder.result = { matches: r.numberOfMatches, active: r.activeMatch };
        }
        // a new document there: its matches
        function onLoadingChanged(request) {
            if (request && request.status === WebEngineView.LoadSucceededStatus && finder.text !== "")
                finder.search();
        }
    }

    // "Also in this task": the other pages as Find.others sorts them, the live ones asked; published when
    // all have answered, or after 1 s without the ones that have not.
    property int round: 0
    property var answers: []
    property int unanswered: 0
    property string skippedNext: ""
    property Timer othersTimer: Timer { interval: 200; onTriggered: finder.others() }
    property Timer othersLimit: Timer { interval: 1000; onTriggered: finder.publish() }
    // a page whose process stopped while unseen (reloadOnShow) is unloaded until opened
    function stateOf(id) {
        const v = viewOf(id);
        if (!v || String(v.url) === "" || v.reloadOnShow || v.lifecycleState === WebEngineView.LifecycleState.Discarded)
            return "unloaded";
        if (v.lifecycleState === WebEngineView.LifecycleState.Frozen)
            return "frozen";
        return v.failure ? "failed" : "live";
    }
    function others() {
        const p = view ? session.pages[view.pageId] : null;
        const t = p ? session.threadById(p.thread) : null;
        const r = ++round;
        othersLimit.stop();
        if (!live || !t || text === "") {
            hits = [];
            skipped = "";
            return;
        }
        const o = Find.others(t.pages.map(id => ({ id: id, state: stateOf(id), seen: session.pages[id].seen ?? session.pages[id].lastActive ?? 0 })), view.pageId);
        answers = o.search.map(id => ({ id: id, count: 0 }));
        unanswered = answers.length;
        skippedNext = Find.skipped(o.frozen, o.unloaded, o.capped);
        if (unanswered === 0) {
            publish();
            return;
        }
        othersLimit.restart();
        const script = Find.countScript(text, matchCase);
        for (const a of answers)
            viewOf(a.id).runJavaScript(script, WebEngineScript.ApplicationWorld, n => {
                if (r !== finder.round)
                    return;
                a.count = Number(n) || 0;
                if (--finder.unanswered === 0)
                    finder.publish();
            });
    }
    function publish() {
        othersLimit.stop();
        if (!open)
            return;
        hits = Find.also(answers).filter(a => session.pages[a.id]).map(a => {
            const q = session.pages[a.id];
            return { pageId: a.id, title: q.title || RailRows.named(q.url), icon: q.icon || "", count: a.count };
        });
        skipped = skippedNext;
    }
}
