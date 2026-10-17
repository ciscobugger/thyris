import QtQuick
import Browser
import "Settings.js" as Settings
import "Site.js" as Site

// What Settings sets (PLAN.md 3.15), persisted to settings.json and applied at once: `changed(key)` tells Main, which
// applies it to every window and profile. The first window's, for every window, a private one's too: these are no
// browsing data. Also the clear of browsing data waiting on its undo, so leaving the page does not cancel it, and
// the list update's last failure, which stays until an update succeeds.
QtObject {
    id: prefs

    property var values: ({})
    property int revision: 0
    signal changed(string key)
    property Timer saveTimer: Timer { interval: 500; onTriggered: prefs.save() }
    function save() { Store.save("settings", values) }

    function get(key) {
        revision;
        return values[key] !== undefined ? values[key] : Settings.defaults[key];
    }
    // a default is no value: it is dropped from the file
    function set(key, v) {
        const next = Object.assign({}, values);
        if (JSON.stringify(v) === JSON.stringify(Settings.defaults[key]))
            delete next[key];
        else
            next[key] = v;
        values = next;
        revision++;
        saveTimer.restart();
        changed(key);
    }
    function load() {
        const v = Store.load("settings");
        values = v && typeof v === "object" ? v : {};
        revision++;
    }

    // Clear browsing data (Settings > Privacy): `what` ("history", "cookies" or "cache") is done once the undo's 6 s
    // are over, by Main on `clearDue`; Undo drops it.
    property var clearing: null             // { what, left }
    signal clearDue(string what)
    property Timer clearTimer: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            const c = prefs.clearing;
            if (!c) {
                stop();
                return;
            }
            if (c.left > 1) {
                prefs.clearing = { what: c.what, left: c.left - 1 };
                return;
            }
            stop();
            prefs.clearing = null;
            prefs.clearDue(c.what);
        }
    }
    function startClear(what) {
        if (clearing)
            return;
        clearing = { what: what, left: Site.undoSeconds };
        clearTimer.restart();
    }
    function undoClear() {
        clearTimer.stop();
        clearing = null;
    }
}
