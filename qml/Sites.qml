import QtQuick
import Browser
import "PageState.js" as PageState

// Lasting per-site choices (PLAN.md 3.8, 3.9), by origin, persisted to sites.json:
// origin -> { choices: { type: "allow" | "block" }, asked: { type: ms } }. Types are Asks.js's (camera,
// microphone, location, notifications, clipboard, pointer, fonts, screen) and "app:<scheme>" for links
// to other apps, and the site panel's own (Site.js): sound and popups, ads ("allow"), slash ("off") and zoom
// (a factor). The site panel sets the choices; asks follow them, and note what a site
// asked for, which the panel lists. A private window's (PLAN.md 3.14) starts as a copy of these and is
// `offTheRecord`: what it sets and notes stays in memory.
QtObject {
    id: sites

    property var entries: ({})
    property int revision: 0
    property bool offTheRecord: false
    property Timer saveTimer: Timer { interval: 1000; onTriggered: sites.save() }

    // "allow", "block" or "" (ask)
    function choice(origin, type) {
        const e = entries[origin];
        return e && e.choices && e.choices[type] ? e.choices[type] : "";
    }
    // Settings > Pages (PLAN.md 3.15): the zoom of a site with none of its own
    property real defaultZoom: 1
    function zoom(origin) { return Number(choice(origin, "zoom")) || defaultZoom }
    // the default zoom is no choice
    function setZoom(origin, z) { setChoice(origin, "zoom", Math.abs(z - defaultZoom) < 0.001 ? "" : z) }
    // the hosts whose pages the ad blocker leaves alone (the site panel's Allow)
    function adsAllowed() {
        const hosts = [];
        for (const o in entries) {
            const h = PageState.hostOf(o);
            if (choice(o, "ads") === "allow" && h && hosts.indexOf(h) < 0)
                hosts.push(h);
        }
        return hosts;
    }
    // "" goes back to asking
    function setChoice(origin, type, value) {
        const e = entries[origin] ?? { choices: {}, asked: {} };
        if (value)
            e.choices[type] = value;
        else
            delete e.choices[type];
        entries[origin] = e;
        changed();
    }
    function noteAsked(origin, types) {
        if (!origin)
            return;
        const e = entries[origin] ?? { choices: {}, asked: {} };
        for (const t of types)
            e.asked[t] = Date.now();
        entries[origin] = e;
        changed();
    }
    function changed() {
        revision++;
        saveTimer.restart();
    }
    function save() {
        if (!offTheRecord)
            Store.save("sites", entries);
    }
    function load() {
        entries = Store.load("sites") ?? {};
        revision++;
    }
}
