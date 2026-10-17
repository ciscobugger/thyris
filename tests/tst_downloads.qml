import QtQuick
import QtTest
import Browser
import "../qml"
import "../qml/Downloads.js" as Downloads

// Downloads.js: a download's words, its row's parts and where it shows (PLAN.md 3.8 8d).
TestCase {
    name: "Downloads"

    Component { id: sessionComponent; Session {} }

    function init() { Store.files = {} }

    // today at hh:mm
    function at(h, m) { const d = new Date(); d.setHours(h, m, 0, 0); return d.getTime() }
    function record(fields) {
        return Object.assign({ id: "d", page: "", url: "https://example.org/f", file: "camss-v3.mbox", path: "/tmp/camss-v3.mbox", total: 8.4e6,
                               received: 0, left: -1, state: "running", reason: "", warn: "", started: 0, finished: 0, opened: 0, from: null }, fields);
    }

    // the shell's sizes (end4-pC services/Voice.qml)
    function test_sizes() {
        compare(Downloads.size(12), "12 B");
        compare(Downloads.size(188000), "188 kB");
        compare(Downloads.size(2.1e6), "2.1 MB");
        compare(Downloads.size(85e6), "85 MB");
        compare(Downloads.size(1.2e9), "1.2 GB");
    }

    function test_sizeOfTheTotalInItsUnit() {
        compare(Downloads.sizeOf(2.1e6, 8.4e6), "2.1 of 8.4 MB");
        compare(Downloads.sizeOf(12e6, 85e6), "12 of 85 MB");
        compare(Downloads.sizeOf(4e8, 1.2e9), "0.4 of 1.2 GB");
        compare(Downloads.sizeOf(20000, 640000), "20 of 640 kB");
        compare(Downloads.sizeOf(2.1e6, -1), "2.1 MB", "total unknown");
    }

    function test_timeLeft() {
        compare(Downloads.duration(12.4), "12 s");
        compare(Downloads.duration(0.2), "1 s");
        compare(Downloads.duration(240), "4 min");
        compare(Downloads.duration(4800), "1 h 20 min");
        compare(Downloads.duration(7200), "2 h");
    }

    function test_finishedAt() {
        const now = at(15, 0);
        compare(Downloads.finishedAt(at(14, 20), now), "14:20");
        const monday = new Date(now - 3 * 86400000);
        compare(Downloads.finishedAt(monday.getTime(), now), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][monday.getDay()]);
        compare(Downloads.finishedAt(new Date(2026, 8, 3, 9, 0).getTime(), new Date(2026, 8, 24, 9, 0).getTime()), "3 Sep");
    }

    // Qt WebEngine has no Safe Browsing verdict: only types that run as programs are marked
    function test_programsByName_data() {
        return [
            { tag: "AppImage", file: "flash-tool.AppImage", program: true },
            { tag: "run", file: "driver.run", program: true },
            { tag: "sh in capitals", file: "INSTALL.SH", program: true },
            { tag: "desktop", file: "app.desktop", program: true },
            { tag: "tarball", file: "qdl-2.3.tar.gz", program: false },
            { tag: "a .sh inside the name", file: "notes.sh.txt", program: false },
        ];
    }
    function test_programsByName(data) {
        compare(Downloads.runsAsProgram(data.file), data.program);
    }

    function test_insecureIsHttpFromAnHttpsPage_data() {
        return [
            { tag: "http file, https page", file: "http://driver.example/driver.run", page: "https://vendor.example/", insecure: true },
            { tag: "http file, http page", file: "http://driver.example/driver.run", page: "http://vendor.example/", insecure: false },
            { tag: "https file", file: "https://driver.example/driver.run", page: "https://vendor.example/", insecure: false },
            { tag: "this machine", file: "http://127.0.0.1:8000/driver.run", page: "https://vendor.example/", insecure: false },
            { tag: "localhost", file: "http://localhost:8000/x", page: "https://vendor.example/", insecure: false },
            { tag: "a blob", file: "blob:https://vendor.example/1234", page: "https://vendor.example/", insecure: false },
        ];
    }
    function test_insecureIsHttpFromAnHttpsPage(data) {
        compare(Downloads.insecure(data.file, data.page), data.insecure);
    }

    // Chromium's interrupt reasons (WebEngineDownloadRequest keeps its numbers)
    function test_reasons() {
        compare(Downloads.reason(20), "network");
        compare(Downloads.reason(22), "network");
        compare(Downloads.reason(30), "server");
        compare(Downloads.reason(3), "disk full");
        compare(Downloads.reason(2), "no permission");
        compare(Downloads.reason(34), "sign-in needed");
        compare(Downloads.reason(36), "forbidden");
        compare(Downloads.reason(999), "download error");
    }

    // the frames of 8d: at rest "camss-v3.mbox 40 %"; with the pointer on it the size, time left and bar
    function test_running() {
        const v = Downloads.parts(record({ received: 3.36e6, left: 12 }), 0);
        compare(v.glyph, "download");
        compare(v.detail, "40 %");
        compare(v.info, "3.4 of 8.4 MB · 12 s");
        compare(v.progress, 0.4);
        compare(v.note, "");
    }
    function test_runningWithoutATotalOrARate() {
        const v = Downloads.parts(record({ total: -1, received: 2.1e6 }), 0);
        compare(v.detail, "2.1 MB");
        compare(v.info, "2.1 MB");
        compare(v.progress, -1, "no bar without a total");
        compare(Downloads.parts(record({ received: 1e6 }), 0).info, "1.0 of 8.4 MB", "no time before there is a rate");
    }
    function test_paused() {
        const v = Downloads.parts(record({ state: "paused", received: 2.1e6, left: 30 }), 0);
        compare(v.detail, "Paused");
        compare(v.info, "2.1 of 8.4 MB · Paused");
    }
    function test_finished() {
        const v = Downloads.parts(record({ state: "done", received: 8.4e6, finished: at(14, 20) }), at(15, 0));
        compare(v.glyph, "check");
        compare(v.detail, "");
        compare(v.info, "8.4 MB · 14:20");
    }
    function test_failuresAndWarnings() {
        const failed = Downloads.parts(record({ state: "failed", reason: "network" }), 0);
        compare(failed.note, "Failed: network");
        compare(failed.failed, "error", "in the error tone");
        compare(failed.glyph, "warning");
        const program = Downloads.parts(record({ state: "done", warn: "program", file: "flash-tool.AppImage" }), 0);
        compare(program.note, "Runs as a program.");
        compare(program.failed, "", "a warning is not an error");
        compare(Downloads.parts(record({ state: "blocked" }), 0).note, "Blocked: insecure download");
    }

    function test_actions() {
        const labels = s => Downloads.actions(s).map(a => a.label).join(", ");
        compare(labels("running"), "Pause, Cancel");
        compare(labels("paused"), "Resume, Cancel");
        compare(labels("done"), "Open, Show in Files");
        compare(labels("failed"), "Retry, Remove");
        compare(labels("program"), "Keep, Delete");
        compare(labels("blocked"), "Keep");
        compare(Downloads.status(record({ state: "done", warn: "program" })), "program");
        compare(Downloads.status(record({ state: "done", warn: "" })), "done", "kept");
    }
    function test_waitingRowsShowTheirActionsAlways() {
        verify(Downloads.waits("failed") && Downloads.waits("program") && Downloads.waits("blocked"));
        verify(!Downloads.waits("running") && !Downloads.waits("paused") && !Downloads.waits("done"));
    }

    // under its page; in the Downloads group when the page has no row; gone 10 min after the file was opened
    function test_place() {
        const s = createTemporaryObject(sessionComponent, this);
        const t = s.newThread("t");
        const p = s.addPage(t, "https://example.org/", "");
        const cell = s.addAlways("https://mail.example/", "Mail", "");
        const now = 100 * 60000;
        compare(Downloads.place(record({ page: p }), s, now), "page");
        compare(Downloads.place(record({ page: cell }), s, now), "group", "an Always site has no row");
        compare(Downloads.place(record({ page: "closed" }), s, now), "group", "a closed page");
        compare(Downloads.place(record({ page: p, state: "done", opened: now - 9 * 60000 }), s, now), "page");
        compare(Downloads.place(record({ page: p, state: "done", opened: now - 10 * 60000 }), s, now), "", "10 min after it was opened");
        compare(Downloads.place(record({ page: "closed", state: "done", opened: now - 11 * 60000 }), s, now), "");
    }
    function test_filingTakesTheFilesOutSaveOneComing() {
        const s = createTemporaryObject(sessionComponent, this);
        const t = s.newThread("t");
        const p = s.addPage(t, "https://example.org/", "");
        s.addPage(t, "https://example.org/2", "");
        s.fileThread(t);
        compare(Downloads.place(record({ page: p, state: "done" }), s, 0), "");
        compare(Downloads.place(record({ page: p, state: "failed" }), s, 0), "");
        compare(Downloads.place(record({ page: p, state: "running" }), s, 0), "group");
        compare(Downloads.place(record({ page: p, state: "paused" }), s, 0), "group");
    }

    function test_summary() {
        const list = [record({ total: 1e6, received: 1e6, state: "done" }), record({ total: 2e6, received: 0.2e6 }), record({ total: 2e6, received: 0.8e6 })];
        const v = Downloads.summary(list);
        compare(v.title, "3 downloads · 40 %", "all their bytes");
        compare(v.glyph, "download");
        const done = Downloads.summary([record({ state: "done", received: 8.4e6 }), record({ state: "done", received: 8.4e6 })]);
        compare(done.title, "2 downloads");
        compare(done.glyph, "check");
    }

    // a row in the Downloads group names the page it came from: "from [G] Always" for an Always site
    function test_groupRowSaysWhereItCameFrom() {
        const always = Downloads.row(record({ from: { title: "(12) Inbox - Gmail", icon: "g.png", always: true } }), 2, true, 0);
        compare(always.from, "Pinned");
        compare(always.icon, "g.png");
        const closed = Downloads.row(record({ from: { title: "Releases · qdl", icon: "", always: false } }), 2, true, 0);
        compare(closed.from, "Releases · qdl");
        compare(Downloads.row(record({ from: { title: "x", always: false } }), 2, false, 0).from, "", "under its page, nothing to say");
    }
}
