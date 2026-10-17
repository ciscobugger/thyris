import QtQuick
import QtTest
import "../qml/KeyMap.js" as KeyMap

// KeyMap.js: the R and P key classes (PLAN.md 5).
TestCase {
    name: "KeyMap"

    function allSeqs(list) { return list.reduce((all, k) => all.concat(k.seqs), []) }

    function test_sequenceNames() {
        compare(KeyMap.sequence(Qt.Key_B, Qt.ControlModifier), "Ctrl+B");
        compare(KeyMap.sequence(Qt.Key_PageDown, Qt.ControlModifier | Qt.ShiftModifier), "Ctrl+Shift+PgDown");
        compare(KeyMap.sequence(Qt.Key_Backtab, Qt.ControlModifier | Qt.ShiftModifier), "Ctrl+Shift+Tab");
        compare(KeyMap.sequence(Qt.Key_Left, Qt.AltModifier), "Alt+Left");
        compare(KeyMap.sequence(Qt.Key_F5, Qt.ShiftModifier), "Shift+F5");
        compare(KeyMap.sequence(Qt.Key_3, Qt.AltModifier | Qt.KeypadModifier), "Alt+3");
        compare(KeyMap.sequence(Qt.Key_Escape, Qt.NoModifier), "Esc");
        compare(KeyMap.sequence(Qt.Key_Shift, Qt.ShiftModifier), "", "a modifier alone is no key");
    }

    function test_pageFirstKeys() {
        compare(KeyMap.pageKey(Qt.Key_B, Qt.ControlModifier).action, "fold");
        compare(KeyMap.pageKey(Qt.Key_D, Qt.ControlModifier | Qt.ShiftModifier).action, "keepInAlways");
        compare(KeyMap.pageKey(Qt.Key_4, Qt.AltModifier).arg, 4);
        compare(KeyMap.pageKey(Qt.Key_Escape, Qt.NoModifier).action, "stop");
        compare(KeyMap.pageKey(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier).action, "hardReload");
        compare(KeyMap.pageKey(Qt.Key_B, Qt.NoModifier), null, "plain letters are the page's");
        compare(KeyMap.pageKey(Qt.Key_Down, Qt.AltModifier), null, "Alt+Down is the select's");
        compare(KeyMap.pageKey(Qt.Key_D, Qt.ControlModifier).action, "save", "Ctrl+D saves, page first: Meet's Ctrl+D mutes");
        // PLAN.md 5: print and reader view are page-first (Docs prints with its own Ctrl+P)
        compare(KeyMap.pageKey(Qt.Key_P, Qt.ControlModifier).action, "print");
        compare(KeyMap.pageKey(Qt.Key_R, Qt.ControlModifier | Qt.AltModifier).action, "reader");
        compare(KeyMap.pageKey(Qt.Key_R, Qt.ControlModifier).action, "reload", "Ctrl+R still reloads");
        verify(allSeqs(KeyMap.reserved).indexOf("Ctrl+P") < 0, "not a reserved key");
    }

    // PLAN.md 3.7 and 5: Earlier's views are page-first keys
    function test_earlierKeys() {
        const e = (key, mods) => { const k = KeyMap.pageKey(key, mods); return k ? k.action + ":" + k.arg : "" };
        compare(e(Qt.Key_H, Qt.ControlModifier), "earlier:history");
        compare(e(Qt.Key_J, Qt.ControlModifier), "earlier:downloads");
        compare(e(Qt.Key_O, Qt.ControlModifier | Qt.ShiftModifier), "earlier:saved");
        compare(KeyMap.pageKey(Qt.Key_O, Qt.ControlModifier), null, "Ctrl+O (open file) is not Saved");
    }

    function test_findKeys() {
        compare(KeyMap.pageKey(Qt.Key_F, Qt.ControlModifier).action, "find", "Ctrl+F is page first");
        compare(KeyMap.typedKey("/", Qt.NoModifier).action, "find");
        compare(KeyMap.typedKey("/", Qt.ShiftModifier).action, "find", "Shift+7 on a Swedish keyboard");
        compare(KeyMap.typedKey("/", Qt.ControlModifier), null);
        compare(KeyMap.typedKey("/", Qt.AltModifier), null);
        compare(KeyMap.typedKey("f", Qt.NoModifier), null, "other letters are the page's");
    }

    function test_siteKeys() {
        compare(KeyMap.pageKey(Qt.Key_I, Qt.ControlModifier).action, "site", "Ctrl+I is page first: it sets italics in a rich text field");
        compare(KeyMap.pageKey(Qt.Key_Plus, Qt.ControlModifier).action, "zoomIn", "Ctrl+Plus, as on a Swedish keyboard");
        compare(KeyMap.pageKey(Qt.Key_Plus, Qt.ControlModifier | Qt.ShiftModifier).action, "zoomIn", "Ctrl+Shift+= on a US keyboard");
        compare(KeyMap.pageKey(Qt.Key_Equal, Qt.ControlModifier).action, "zoomIn");
        compare(KeyMap.pageKey(Qt.Key_Plus, Qt.ControlModifier | Qt.KeypadModifier).action, "zoomIn", "the keypad's +");
        compare(KeyMap.pageKey(Qt.Key_Minus, Qt.ControlModifier).action, "zoomOut");
        compare(KeyMap.pageKey(Qt.Key_0, Qt.ControlModifier).action, "zoomReset");
        compare(KeyMap.pageKey(Qt.Key_Minus, Qt.NoModifier), null, "a plain - is the page's");
    }

    function test_ctrlKAndCtrlEBelongToSites() {
        for (const s of ["Ctrl+K", "Ctrl+E"]) {
            verify(allSeqs(KeyMap.reserved).indexOf(s) < 0, s);
            verify(allSeqs(KeyMap.pageFirst).indexOf(s) < 0, s);
        }
    }

    function test_classesDoNotOverlap() {
        const r = allSeqs(KeyMap.reserved), p = allSeqs(KeyMap.pageFirst);
        compare(r.filter(s => p.indexOf(s) >= 0), []);
        compare(new Set(r).size, r.length, "no R sequence twice");
        compare(new Set(p).size, p.length, "no P sequence twice");
    }

    // every P sequence round-trips through the event form
    function test_pageSequencesAreMatchable() {
        const keys = { Left: Qt.Key_Left, Right: Qt.Key_Right, PgUp: Qt.Key_PageUp, PgDown: Qt.Key_PageDown, Esc: Qt.Key_Escape, F5: Qt.Key_F5,
                       Plus: Qt.Key_Plus, Minus: Qt.Key_Minus, Del: Qt.Key_Delete };
        const mods = { Ctrl: Qt.ControlModifier, Alt: Qt.AltModifier, Shift: Qt.ShiftModifier };
        for (const s of allSeqs(KeyMap.pageFirst)) {
            const parts = s.split("+"), name = parts.pop();
            const key = keys[name] ?? name.charCodeAt(0);
            const m = parts.reduce((a, p) => a | mods[p], 0);
            compare(KeyMap.sequence(key, m), s);
        }
    }

    // PLAN.md 5: Settings, the key list, clear browsing data and Pages and memory are page-first keys; / is Shift+7 on a
    // Swedish keyboard, so Ctrl+/ comes as Ctrl+Shift+/ there
    function test_ownPageKeys() {
        compare(KeyMap.pageKey(Qt.Key_Comma, Qt.ControlModifier).action, "settings");
        compare(KeyMap.pageKey(Qt.Key_Comma, Qt.ControlModifier).arg, undefined);
        compare(KeyMap.pageKey(Qt.Key_Slash, Qt.ControlModifier).arg, "keys");
        compare(KeyMap.pageKey(Qt.Key_Slash, Qt.ControlModifier | Qt.ShiftModifier).arg, "keys");
        compare(KeyMap.pageKey(Qt.Key_Delete, Qt.ControlModifier | Qt.ShiftModifier).arg, "clear");
        compare(KeyMap.pageKey(Qt.Key_Escape, Qt.ShiftModifier).action, "pages");
        compare(KeyMap.pageKey(Qt.Key_Escape, 0).action, "stop", "Esc alone still stops");
    }

    // PLAN.md 5: Ctrl+N and Ctrl+Shift+N are the browser's, whatever has the keys
    function test_windowKeysAreReserved() {
        compare(KeyMap.reserved.find(k => k.seqs.indexOf("Ctrl+N") >= 0).action, "newWindow");
        compare(KeyMap.reserved.find(k => k.seqs.indexOf("Ctrl+Shift+N") >= 0).action, "privateWindow");
        compare(KeyMap.pageKey(Qt.Key_N, Qt.ControlModifier | Qt.ShiftModifier), null, "not a page-first key");
    }
}
