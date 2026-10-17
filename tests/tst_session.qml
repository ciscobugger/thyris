import QtQuick
import QtTest
import Browser
import "../qml"

// Session.qml: threads, pages, closing and filing, prediction, persistence.
TestCase {
    name: "Session"

    Component { id: sessionComponent; Session {} }

    function init() { Store.files = {} }
    function make() { return createTemporaryObject(sessionComponent, this) }

    // a session with one thread of `titles.length` pages; returns [session, threadId, pageIds]
    function withThread(title, titles) {
        const s = make();
        const t = s.newThread(title);
        const ids = titles.map(pt => {
            const id = s.addPage(t, "https://example.org/" + encodeURIComponent(pt), "");
            s.update(id, { title: pt });
            return id;
        });
        return [s, t, ids];
    }

    function test_newThreadGoesFirst() {
        const s = make();
        const a = s.newThread("a"), b = s.newThread("b");
        compare(s.threads.map(t => t.id), [b, a]);
        compare(s.threadById(a).earlier, false);
    }

    function test_addPageAppendsOrFollowsOpener() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        const child = s.addPage(t, "https://example.org/child", ids[0]);
        compare(s.threadById(t).pages, [ids[0], child, ids[1]]);
        compare(s.pages[child].state, "unloaded");
        compare(s.pages[child].thread, t);
    }

    function test_activateSetsCurrentAndUnfiles() {
        const [s, t, ids] = withThread("t", ["one"]);
        s.threadById(t).earlier = true;
        s.activate(ids[0]);
        compare(s.currentPage, ids[0]);
        compare(s.current.id, ids[0]);
        compare(s.currentThread.id, t);
        compare(s.threadById(t).earlier, false);
    }

    function test_updateBumpsRevisionOnlyOnChange() {
        const [s, t, ids] = withThread("t", ["one"]);
        const r = s.revision;
        s.update(ids[0], { title: "one" });
        compare(s.revision, r);
        s.update(ids[0], { title: "uno" });
        compare(s.revision, r + 1);
    }

    function test_closePageInMultiPageThread() {
        const [s, t, ids] = withThread("t", ["one", "two", "three"]);
        s.activate(ids[2]);
        s.update(ids[0], { lastActive: 300 });
        s.update(ids[1], { lastActive: 100 });
        const gone = s.closePage(ids[2]);
        compare(gone, [ids[2]]);
        compare(s.threadById(t).pages, [ids[0], ids[1]]);
        verify(!(ids[2] in s.pages));
        compare(s.currentPage, ids[0], "the most recently used page of the same thread takes over");
        compare(s.closed[s.closed.length - 1].url, "https://example.org/three");
        compare(s.threadById(t).earlier, false);
    }

    // PLAN.md 3.12: a single page you close is simply closed; nothing is filed.
    function test_closingAThreadOfOneJustClosesIt() {
        const [s, t, ids] = withThread("t", ["only"]);
        s.activate(ids[0]);
        compare(s.closePage(ids[0]), [ids[0]]);
        compare(s.threadById(t), null, "the thread goes with its page");
        verify(!(ids[0] in s.pages));
        compare(s.currentPage, "");
        compare(s.filedThreads().length, 0);
        const again = s.reopenClosed();
        compare(s.pages[again].url, "https://example.org/only", "Ctrl+Shift+T brings it back");
        compare(s.threadById(s.pages[again].thread).pages, [again], "as a thread of one");
    }

    // PLAN.md 8, phase 1 check: closing twenty single pages files nothing
    function test_closingTwentySinglePagesFilesNothing() {
        const s = make();
        const ids = [];
        for (let i = 0; i < 20; i++)
            ids.push(s.addPage(s.newThread("page " + i), "https://example.org/" + i, ""));
        for (const id of ids)
            s.closePage(id);
        compare(s.threads.length, 0);
        compare(s.filedThreads().length, 0);
    }

    function test_closingDownToOnePageLeavesAThreadOfOne() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.closePage(ids[1]);
        compare(s.threadById(t).pages, [ids[0]]);
        s.closePage(ids[0]);
        compare(s.threadById(t), null, "then it closes like any single page");
        compare(s.filedThreads().length, 0);
    }

    function test_fileThreadFilesOnlyMultiPageThreads() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.activate(ids[0]);
        s.update(ids[0], { state: "live", audible: true });
        compare(s.fileThread(t), ids);
        const filed = s.threadById(t);
        compare(filed.earlier, true);
        verify(filed.filedAt > 0);
        compare(s.pages[ids[0]].state, "unloaded", "its views go, so its pages show unloaded when it comes back");
        compare(s.pages[ids[0]].audible, false);
        compare(s.currentPage, "");
        const solo = s.newThread("solo");
        const p = s.addPage(solo, "https://example.org/solo", "");
        compare(s.fileThread(solo), [p], "Ctrl+Shift+W on a thread of one closes it");
        compare(s.threadById(solo), null);
    }

    function test_earlierIsMostRecentlyFiledFirst() {
        const s = make();
        const made = ["a", "b", "c"].map(n => {
            const t = s.newThread(n);
            s.addPage(t, "https://example.org/" + n + "1", "");
            s.addPage(t, "https://example.org/" + n + "2", "");
            return t;
        });
        s.fileThread(made[1]);
        s.threadById(made[1]).filedAt = 100;
        s.fileThread(made[0]);
        s.threadById(made[0]).filedAt = 300;
        s.fileThread(made[2]);
        s.threadById(made[2]).filedAt = 200;
        compare(s.filedThreads().map(t => t.title), ["a", "c", "b"]);
    }

    function test_fileThreadMovesToAnotherOpenThread() {
        const s = make();
        const a = s.newThread("a"), b = s.newThread("b");
        const pa = s.addPage(a, "https://a.example/", ""), pb = s.addPage(b, "https://b.example/", "");
        s.activate(pa);
        s.activate(pb);
        compare(s.fileThread(b), [pb]);
        compare(s.currentPage, pa);
    }

    function test_restoreThreadComesBackFirstAmongOpenThreads() {
        const s = make();
        const a = s.newThread("a");
        const pa = [s.addPage(a, "https://a.example/1", ""), s.addPage(a, "https://a.example/2", "")];
        const b = s.newThread("b");
        s.addPage(b, "https://b.example/", "");
        s.fileThread(a);
        s.newThread("c");
        s.restoreThread(a, pa[0]);
        compare(s.threads[0].id, a);
        compare(s.threadById(a).earlier, false);
        compare(s.threadById(a).pages, pa, "whole");
        compare(s.currentPage, pa[0], "with the page asked for current");
    }

    function test_restoreThreadOpensItsLastPage() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.update(ids[0], { lastActive: 100 });
        s.update(ids[1], { lastActive: 200 });
        s.fileThread(t);
        s.restoreThread(t);
        compare(s.threadById(t).earlier, false);
        compare(s.currentPage, ids[1]);
    }

    function test_reopenClosedReturnsToItsThread() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.closePage(ids[1]);
        const again = s.reopenClosed();
        compare(s.pages[again].url, "https://example.org/two");
        compare(s.pages[again].thread, t);
        compare(s.reopenClosed(), "", "nothing left to reopen");
    }

    function test_reopenClosedMakesAThreadWhenItsThreadIsGone() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.closePage(ids[1]);
        s.threads = [];
        const again = s.reopenClosed();
        compare(s.threads.length, 1);
        compare(s.threads[0].title, "two");
        compare(s.pages[again].thread, s.threads[0].id);
    }

    // PLAN.md 3.17: an untitled data:, file: or about:blank page brought back names its thread by kind, never by the address
    function test_reopenedUntitledPagesNameTheirThreadByKind() {
        const s = make();
        const urls = ["data:text/html,<p>open sesame</p>", "file:///home/abdul/S2MM006.txt", "about:blank"];
        for (const url of urls)
            s.closePage(s.addPage(s.newThread("x"), url, ""));
        const names = [];
        for (let i = 0; i < urls.length; i++)
            names.push(s.threadById(s.pages[s.reopenClosed()].thread).title);
        compare(names, ["Blank page", "File /home/abdul/S2MM006.txt", "data: page · 18 B"]);
        const w = other(s, "w2");
        w.addPage(w.newThread("data:text/html,<p>open sesame</p>"), "data:text/html,<p>open sesame</p>", "");
        page(w, w.newThread("kept"), "kept");
        w.closeWindow("kept", {});
        const n = other(s, "w3");
        n.restoreWindow(s.takeWindow());
        compare(n.openThreads().map(t => t.title).sort(), ["data: page · 18 B", "kept"], "a closed window's single pages too");
    }

    function test_mostRecentPageSkipsFiledThreads() {
        const s = make();
        const a = s.newThread("a"), b = s.newThread("b");
        const pa = s.addPage(a, "https://a.example/", ""), pb = s.addPage(b, "https://b.example/", "");
        s.update(pa, { lastActive: 100 });
        s.update(pb, { lastActive: 200 });
        s.threadById(b).earlier = true;
        compare(s.mostRecentPage(), pa);
        compare(s.mostRecentPage(b), pb, "within a thread, filed or not");
    }

    function test_predictThreadBySharedWords() {
        const s = make();
        const cam = s.newThread("x1p42100 camera");
        s.update(s.addPage(cam, "https://lists.libcamera.org/", ""), { title: "Re: softisp AGC starves on GPU" });
        const flights = s.newThread("Flights ARN - MGQ");
        s.update(s.addPage(flights, "https://www.flysas.com/", ""), { title: "SAS · Stockholm - Mogadishu" });
        compare(s.predictThread("softisp agc cpu mode"), cam);
        compare(s.predictThread("mogadishu flights"), flights);
        compare(s.predictThread("Åre ski rental"), "", "no shared word: a new thread");
        compare(s.predictThread("ab"), "", "words under three letters are ignored");
    }

    function test_predictThreadSkipsFiledThreads() {
        const s = make();
        const cam = s.newThread("camera");
        s.addPage(cam, "https://example.org/", "");
        s.threadById(cam).earlier = true;
        compare(s.predictThread("camera"), "");
    }

    function test_predictThreadTieGoesToCurrent() {
        const s = make();
        const a = s.newThread("camera one"), b = s.newThread("camera two");
        const pa = s.addPage(a, "https://a.example/", "");
        s.addPage(b, "https://b.example/", "");
        s.activate(pa);
        compare(s.predictThread("camera"), a, "b is newer and listed first, but a is current");
    }

    // PLAN.md 3.3: a thread is predicted once it shares two typed words (the only one, for one word)
    function camAndFlights() {
        const s = make();
        const cam = s.newThread("x1p42100 camera");
        s.update(s.addPage(cam, "https://lists.libcamera.org/", ""), { title: "Re: softisp AGC starves on GPU" });
        const flights = s.newThread("Flights ARN - MGQ");
        s.update(s.addPage(flights, "https://www.flysas.com/", ""), { title: "SAS · Stockholm - Mogadishu" });
        return [s, cam, flights];
    }

    function test_predictThreshold() {
        const [s, cam, flights] = camAndFlights();
        compare(s.predictThread("mogadishu"), flights, "one word, and it is shared");
        compare(s.predictThread("weather mogadishu "), "", "one of two finished words is under the threshold");
        compare(s.predictThread("weather mogadishu"), "", "a matching last word counts in full");
        compare(s.predictThread("mogadishu weath"), flights, "a last word still being typed does not count until it matches");
        compare(s.predictThread("mogadishu weather "), "", "once finished it counts");
        compare(s.predictThread("softisp agc cpu mode"), cam, "two shared words are enough however many are typed");
    }

    function test_predictionDoesNotFlickerWhileTyping() {
        const [s, cam] = camAndFlights();
        const text = "softisp agc cpu mode";
        let shown = "", flips = 0;
        for (let i = 1; i <= text.length; i++) {
            const next = s.predictThread(text.slice(0, i), shown);
            if (next !== shown)
                flips++;
            shown = next;
        }
        compare(shown, cam);
        compare(flips, 1, "the line changes once, when the threshold is crossed");
    }

    function test_predictTieKeepsTheShownThread() {
        const s = make();
        const a = s.newThread("camera one"), b = s.newThread("camera two");
        const pa = s.addPage(a, "https://a.example/", "");
        s.addPage(b, "https://b.example/", "");
        s.activate(pa);
        compare(s.predictThread("camera", b), b, "the bar already shows b; a tie does not move it to the current thread");
        compare(s.predictThread("camera two", a), b, "a higher score does");
    }

    function test_stopWordsAndUrlPartsNeverPredict() {
        const s = make();
        const t = s.newThread("How to fix the camera");
        s.update(s.addPage(t, "https://www.example.com/och/att", ""), { title: "Det som inte går" });
        compare(s.predictThread("how the "), "");
        compare(s.predictThread("och att det som "), "", "Swedish stop words");
        compare(s.predictThread("https www com "), "");
        compare(s.sharedWords("fix the camera", t), ["fix", "camera"]);
    }

    function test_trailKeepsPagesLeft() {
        const [s, t, ids] = withThread("t", ["v2 patch", "other"]);
        s.update(ids[0], { url: "https://example.org/v3" });
        s.update(ids[0], { url: "https://example.org/v3" });
        compare(s.threadById(t).trail.map(e => e.title), ["v2 patch"], "left once, by navigation");
        s.closePage(ids[1]);
        compare(s.threadById(t).trail.map(e => e.title), ["other", "v2 patch"], "closing leaves a page too, newest first");
        s.update(ids[0], { title: "v3 patch" });
        s.update(ids[0], { url: "https://example.org/v2%20patch" });
        compare(s.threadById(t).trail.map(e => e.url), ["https://example.org/v3", "https://example.org/other", "https://example.org/v2%20patch"]);
    }

    function test_saveAndLoad() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.activate(ids[1]);
        s.update(ids[1], { state: "live" });
        s.save();
        const r = make();
        verify(r.load());
        compare(r.threads.map(x => x.id), [t]);
        compare(r.currentPage, ids[1]);
        compare(r.pages[ids[1]].title, "two");
        compare(r.pages[ids[1]].state, "unloaded", "nothing is loaded after a restart");
    }

    // PLAN.md 8d: records survive a restart; Qt WebEngine cancelled what was still coming, so those failed
    // ("browser closed", Retry fetches again), and a held insecure file was never wanted
    function test_downloadsAfterARestart() {
        const [s, t, ids] = withThread("t", ["one"]);
        s.addDownload({ page: ids[0], file: "done.bin", state: "done", total: 10, received: 10 });
        const coming = s.addDownload({ page: ids[0], file: "coming.bin", state: "running", total: 10, received: 4, left: 3 });
        s.addDownload({ page: ids[0], file: "paused.bin", state: "paused" });
        s.addDownload({ page: ids[0], file: "held.run", state: "blocked" });
        s.update(ids[0], { downloading: true });
        s.save();
        const r = make();
        r.load();
        compare(r.downloads.map(d => d.file + " " + d.state), ["done.bin done", "coming.bin failed", "paused.bin failed"]);
        compare(r.downloadById(coming).reason, "browser closed");
        compare(r.downloadById(coming).left, -1);
        compare(r.pages[ids[0]].downloading, false);
    }
    // a progress tick neither puts off the save nor redraws: it says whether anything changed, and
    // Downloader's tick bumps revision once for all its files
    function test_quietDownloadUpdates() {
        const [s, t, ids] = withThread("t", ["one"]);
        const id = s.addDownload({ page: ids[0], file: "f" });
        s.saveTimer.stop();
        const rev = s.revision;
        verify(s.updateDownload(id, { received: 5 }, true));
        compare(s.revision, rev);
        verify(!s.saveTimer.running);
        verify(!s.updateDownload(id, { received: 5 }, true), "nothing changed");
        s.updateDownload(id, { state: "done" });
        verify(s.saveTimer.running);
        s.removeDownload(id);
        compare(s.downloads.length, 0);
    }

    function test_loadDropsThreadsWithMissingOrNoPages() {
        Store.save("threads", {
            threads: [
                { id: "ok", title: "ok", pages: ["p1"], lastActive: 1, earlier: false },
                { id: "missing", title: "missing", pages: ["p1", "gone"], lastActive: 1, earlier: false },
                { id: "empty", title: "empty", pages: [], lastActive: 1, earlier: false },
            ],
            pages: { p1: { id: "p1", thread: "ok", url: "https://example.org/", title: "", icon: "", lastActive: 1, state: "live" } },
            closed: [],
            currentPage: "nope",
        });
        const s = make();
        verify(s.load());
        compare(s.threads.map(t => t.id), ["ok"]);
        compare(s.currentPage, "p1", "an unknown current page falls back to the most recent one");
    }

    function test_addPageToAGoneThreadMakesNoPage() {
        const s = make();
        compare(s.addPage("gone", "https://example.org/", ""), "");
        compare(Object.keys(s.pages), []);
    }

    function test_loadDropsPagesNothingHolds() {
        Store.save("threads", {
            threads: [{ id: "t", title: "t", pages: ["p1"], lastActive: 1, earlier: false }],
            pages: { p1: { id: "p1", thread: "t", url: "https://example.org/", title: "", icon: "", lastActive: 1 },
                     a1: { id: "a1", thread: "", url: "https://mail.example/", title: "", icon: "", lastActive: 1 },
                     orphan: { id: "orphan", thread: "t", url: "https://example.org/x", title: "", icon: "", lastActive: 2 } },
            always: ["a1"], closed: [], currentPage: "p1",
        });
        const s = make();
        s.load();
        compare(Object.keys(s.pages).sort(), ["a1", "p1"]);
    }

    function test_loadWithoutFile() {
        verify(!make().load());
    }

    function test_ctrlShiftTReopensAFiledThread() {
        const [s, t, ids] = withThread("camera", ["one", "two"]);
        s.fileThread(t);
        compare(s.reopenName(), "camera");
        compare(s.reopenClosed(), s.mostRecentPage(t));
        compare(s.threadById(t).earlier, false);
        compare(s.reopenName(), "", "nothing left to reopen");
    }

    function test_reopenSkipsAThreadRestoredSinceFiling() {
        const [s, t, ids] = withThread("camera", ["one", "two", "three"]);
        s.closePage(ids[1]);
        s.fileThread(t);
        s.restoreThread(t);
        compare(s.reopenName(), "two", "the filed entry is stale; the closed page is next");
    }

    function test_setOpenAndActivateReopensTheCurrentThread() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.setOpen(t, false);
        compare(s.threadById(t).open, false);
        s.activate(ids[1]);
        compare(s.threadById(t).open, undefined, "showing a page opens its thread again");
    }

    // PLAN.md 3.12 and 5 (Mouse): links join the opener's thread right after it, in the order opened
    function test_openerJoining() {
        const [s, t, ids] = withThread("t", ["issue", "other"]);
        const a = s.addFromOpener(ids[0], "https://example.org/a", "example.org");
        const b = s.addFromOpener(ids[0], "https://example.org/b", "example.org");
        compare(s.threadById(t).pages, [ids[0], a, b, ids[1]]);
        compare(s.pages[a].opener, ids[0]);
        const c = s.addFromOpener(a, "https://example.org/c", "example.org");
        compare(s.threadById(t).pages, [ids[0], a, c, b, ids[1]], "a link from a child goes right after that child");
        verify(s.learned.threads);
    }

    function test_threadOfOneBecomesAThreadWhenALinkJoins() {
        const s = make();
        const t = s.newThread("example.org");
        const p = s.addPage(t, "https://example.org/", "");
        compare(s.threadById(t).pages.length, 1);
        const q = s.addFromOpener(p, "https://example.org/next", "example.org");
        compare(s.threadById(t).pages, [p, q]);
        compare(s.threads.length, 1, "no new thread: it joined");
    }

    function test_linkFromAnAlwaysSiteStartsAThreadOfOne() {
        const s = make();
        const cell = s.addAlways("https://mail.google.com/", "Gmail", "");
        const p = s.addFromOpener(cell, "https://lwn.net/", "lwn.net");
        const t = s.threadById(s.pages[p].thread);
        compare(t.title, "lwn.net");
        compare(t.pages, [p]);
        compare(s.always, [cell]);
    }

    function test_leavesAlways() {
        const s = make();
        const cell = s.addAlways("https://mail.google.com/", "Gmail", "");
        verify(!s.leavesAlways(cell, "https://mail.google.com/mail/u/0/#inbox"), "its own site stays in the cell");
        verify(s.leavesAlways(cell, "https://lwn.net/Articles/1/"));
        verify(s.leavesAlways(cell, "https://calendar.google.com/"), "another host of the same domain has a cell of its own");
        verify(!s.leavesAlways(cell, "javascript:void(0)"));
        const [s2, t, ids] = withThread("t", ["x"]);
        verify(!s2.leavesAlways(ids[0], "https://lwn.net/"), "only Always pages");
    }

    function test_keepInAlwaysMovesAThreadOfOne() {
        const s = make();
        const t = s.newThread("github.com");
        const p = s.addPage(t, "https://github.com/linux-msm/linux", "");
        compare(s.keepInAlways(p), p);
        compare(s.always, [p]);
        compare(s.pages[p].thread, "");
        compare(s.threadById(t), null, "the tab moved into the cell");
        verify(s.learned.always);
    }

    function test_keepInAlwaysLeavesAThreadsPageInPlace() {
        const [s, t, ids] = withThread("t", ["one", "two"]);
        s.update(ids[0], { url: "https://docs.qt.io/qt-6/qml.html", icon: "i" });
        const cell = s.keepInAlways(ids[0]);
        verify(cell !== ids[0]);
        compare(s.pages[cell].url, "https://docs.qt.io/");
        compare(s.pages[cell].title, "docs.qt.io");
        compare(s.threadById(t).pages, ids, "the thread keeps its page");
        compare(s.keepInAlways(ids[0]), cell, "one cell per site");
    }

    function test_removeAndMoveAlways() {
        const s = make();
        const a = s.addAlways("https://a.example/", "a", ""), b = s.addAlways("https://b.example/", "b", ""),
              c = s.addAlways("https://c.example/", "c", "");
        s.moveAlways(c, -1);
        compare(s.always, [a, c, b]);
        s.moveAlways(a, -1);
        compare(s.always, [a, c, b], "the first cell does not move left");
        s.activate(c);
        compare(s.removeAlways(c), [c]);
        compare(s.always, [a, b]);
        verify(!(c in s.pages));
        compare(s.currentPage, "", "the most recent thread page takes over; there is none, so the empty state");
    }

    // threads given as [title, pageCount], listed in that order; returns [session, threads]
    function rail(spec) {
        const s = make();
        const made = [];
        for (const [title, n] of spec.slice().reverse()) {
            const t = s.newThread(title);
            for (let i = 0; i < n; i++)
                s.update(s.addPage(t, "https://example.org/" + title + "/" + i, ""), { title: title + i });
            made.unshift(t);
        }
        return [s, made];
    }
    function titles(s, t) { return s.threadById(t).pages.map(id => s.pages[id].title) }

    function test_movePageBetweenThreads() {
        const [s, [a, b]] = rail([["a", 3], ["b", 2]]);
        const a1 = s.threadById(a).pages[1];
        s.movePage(a1, b, s.threadById(b).pages[1]);
        compare(titles(s, a), ["a0", "a2"]);
        compare(titles(s, b), ["b0", "a1", "b1"]);
        compare(s.pages[a1].thread, b);
        s.movePage(a1, b, "");
        compare(titles(s, b), ["b0", "b1", "a1"], "to the end");
        s.movePage(s.threadById(b).pages[0], b, s.threadById(b).pages[2]);
        compare(titles(s, b), ["b1", "b0", "a1"], "within a thread");
    }

    function test_movingTheLastPageOutRemovesTheThread() {
        const [s, [a, b]] = rail([["a", 1], ["b", 2]]);
        const p = s.threadById(a).pages[0];
        s.movePage(p, a, "");
        compare(s.threadById(a).pages, [p], "onto its own thread of one: nothing happens");
        s.movePage(p, b, "");
        compare(s.threadById(a), null);
        compare(titles(s, b), ["b0", "b1", "a0"]);
    }

    function test_splitPageMakesAThreadOfOneWhereDropped() {
        const [s, [a, b, c]] = rail([["a", 2], ["b", 2], ["c", 1]]);
        const a1 = s.threadById(a).pages[1];
        s.splitPage(a1, c);
        compare(s.openThreads().map(t => t.pages.map(id => s.pages[id].title).join()), ["a0", "b0,b1", "a1", "c0"]);
        compare(s.threadById(s.pages[a1].thread).title, "a1", "named after its page");
        const c0 = s.threadById(c).pages[0];
        s.splitPage(c0, a);
        compare(s.openThreads()[0].id, c, "a thread of one simply moves");
        s.splitPage(c0, "");
        compare(s.openThreads()[s.openThreads().length - 1].id, c, "\"\" places it after the open threads");
    }

    function test_splitPageStaysAboveEarlier() {
        const [s, [a, b]] = rail([["a", 2], ["b", 2]]);
        s.fileThread(b);
        s.splitPage(s.threadById(a).pages[0], "");
        compare(s.threads.map(t => t.earlier), [false, false, true]);
    }

    function test_splitFrom() {
        const [s, [a, b]] = rail([["a", 4], ["b", 1]]);
        const pages = s.threadById(a).pages.slice();
        compare(s.splitFrom(pages[0]), "", "from the first page there is nothing to split");
        const n = s.splitFrom(pages[2]);
        compare(titles(s, a), ["a0", "a1"]);
        compare(titles(s, n), ["a2", "a3"]);
        compare(s.openThreads().map(t => t.id), [a, n, b], "right below the thread it came from");
        compare(s.pages[pages[3]].thread, n);
    }

    // past a thread's edge a page joins the thread drawn next to it (PLAN.md 3.19: tasks, Put away, Pages)
    function test_shiftPageJoinsTheNeighbourPastTheEdge() {
        const [s, [a, b, c]] = rail([["a", 2], ["b", 2], ["c", 1]]);
        s.setOpen(a, true);
        s.setOpen(b, true);
        const b0 = s.threadById(b).pages[0];
        s.shiftPage(b0, 1);
        compare(titles(s, b), ["b1", "b0"]);
        s.shiftPage(b0, 1);
        compare(titles(s, c), ["b0", "c0"], "past the bottom edge: the start of the thread below");
        s.shiftPage(b0, -1);
        compare(titles(s, b), ["b1", "b0"], "past the top edge: the end of the task drawn above");
        const a0 = s.threadById(a).pages[0];
        s.shiftPage(a0, -1);
        compare(titles(s, a), ["a0", "a1"], "nothing above the first task");
        // folded or open, a task is drawn in its place: the page moving down from y joins z, below it
        const [t, [x, y, z]] = rail([["x", 2], ["y", 2], ["z", 1]]);
        t.setOpen(y, true);
        const y1 = t.threadById(y).pages[1];
        t.shiftPage(y1, 1);
        compare(titles(t, z), ["y1", "z0"], "below y is z, as drawn");
    }

    function test_moveThreadAndRailOrder() {
        const [s, [a, b, c]] = rail([["a", 2], ["b", 1], ["c", 2]]);
        s.moveThread(c, a);
        s.setOpen(a, true);
        s.setOpen(c, true);
        compare(s.openThreads().map(t => t.id), [c, a, b]);
        compare(s.railOrder().map(id => s.pages[id].title), ["c0", "c1", "a0", "a1", "b0"]);
        s.fileThread(a);
        compare(s.railOrder().map(id => s.pages[id].title), ["c0", "c1", "b0"], "filed threads are not in rail order");
    }
    // PLAN.md 3.20: the order is the rail's as drawn, which is the threads' own: an open task by its pages, a folded one
    // by its last-seen page
    function test_railOrderIsTheDrawnOrder() {
        const [s, [a, b, c, d]] = rail([["a", 1], ["b", 2], ["c", 2], ["d", 1]]);
        s.activate(s.threadById(b).pages[1]);
        s.activate(s.threadById(c).pages[1]);
        s.pages[s.threadById(b).pages[1]].lastActive += 1000;
        compare(s.drawnThreads().map(t => t.id), [a, b, c, d]);
        compare(s.railOrder().map(id => s.pages[id].title), ["a0", "b0", "b1", "c0", "c1", "d0"], "every task open");
        s.setOpen(b, false);
        compare(s.railOrder().map(id => s.pages[id].title), ["a0", "b1", "c0", "c1", "d0"], "b, folded, by its last-seen page");
        // the page on screen leaving a task does not fold it
        s.activate(s.threadById(a).pages[0]);
        compare(s.isOpen(s.threadById(c)), true);
        compare(s.drawnThreads().map(t => t.id), [a, b, c, d], "in the same places");
    }

    // Back on a page a link opened, with no history of its own, goes to its opener while both are in one thread
    function test_backToTheOpener() {
        const [s, [a]] = rail([["a", 1]]);
        const from = s.threadById(a).pages[0];
        const link = s.addFromOpener(from, "https://example.org/link", "link");
        const typed = s.addPage(a, "https://example.org/typed", "");
        compare(s.backTo(link), from);
        compare(s.backTo(typed), "", "a page you opened yourself has none");
        compare(s.backTo(from), "");
        s.splitPage(link, "");
        compare(s.backTo(link), "", "moved to another thread, none");
    }

    function test_nearThreadWraps() {
        const [s, [a, b, c]] = rail([["a", 1], ["b", 1], ["c", 1]]);
        s.activate(s.threadById(b).pages[0]);
        compare(s.nearThread(1).id, c);
        compare(s.nearThread(-1).id, a);
        s.activate(s.threadById(c).pages[0]);
        compare(s.nearThread(1).id, a);
    }

    function test_closeOthers() {
        const [s, [a]] = rail([["a", 3]]);
        const [p0, p1, p2] = s.threadById(a).pages;
        s.activate(p0);
        compare(s.closeOthers(p1), [p0, p2]);
        compare(s.threadById(a).pages, [p1]);
        compare(s.currentPage, p1);
    }

    function test_renameIgnoresBlank() {
        const [s, [a]] = rail([["a", 2]]);
        s.rename(a, "  Camera work ");
        compare(s.threadById(a).title, "Camera work");
        s.rename(a, "  ");
        compare(s.threadById(a).title, "Camera work");
    }

    function test_activateMarksWhenThePreviousPageWasLastSeen() {
        const [s, [a]] = rail([["a", 2]]);
        const [p0, p1] = s.threadById(a).pages;
        s.activate(p0);
        compare(s.pages[p0].seen, undefined);
        s.activate(p1);
        verify(s.pages[p0].seen >= s.pages[p0].lastActive);
    }

    function test_addAlwaysOncePerSite() {
        const s = make();
        const a = s.addAlways("https://mail.google.com/", "Gmail", "");
        compare(s.addAlways("https://mail.google.com/mail/u/0/", "Gmail", ""), a);
        compare(s.always, [a]);
        compare(s.pages[a].thread, "");
        compare(s.learned.always, true);
        s.activate(a);
        compare(s.currentPage, a, "an Always page has no thread and still activates");
        compare(s.closePage(a), [], "and is not closed from the rail");
    }

    function test_learnedThreadsOnceAThreadHasTwoPages() {
        const [s] = withThread("t", ["one"]);
        compare(s.learned.threads, false);
        s.addPage(s.threads[0].id, "https://example.org/2", "");
        compare(s.learned.threads, true);
    }

    function test_alwaysAndLearnedSurviveARestart() {
        const s = make();
        const a = s.addAlways("https://github.com/", "GitHub", "");
        s.save();
        const r = make();
        r.load();
        compare(r.always, [a]);
        compare(r.learned.always, true);
    }

    // PLAN.md 3.17: a window not the first has a Session of its own over the first one's lists
    function other(first, id) { return createTemporaryObject(sessionComponent, this, { windowId: id, shared: first }) }
    function page(s, t, title) {
        const id = s.addPage(t, "https://example.org/" + encodeURIComponent(title), "");
        s.update(id, { title: title });
        return id;
    }

    function test_threadsBelongToOneWindowTheRestIsShared() {
        const [s, t, ids] = withThread("x1p42100 camera", ["[PATCH v3] camss: CSIPHY0 lanes", "camss: CSIPHY0 lanes ignored"]);
        const w = other(s, "w2");
        const u = w.newThread("Flights ARN - MGQ");
        const flights = page(w, u, "SAS · Stockholm - Mogadishu");
        verify(s.threads === w.threads && s.pages === w.pages && s.always === w.always && s.closed === w.closed && s.downloads === w.downloads,
               "one set of lists");
        compare(s.threadById(u).window, "w2");
        compare(s.openThreads().map(x => x.id), [t]);
        compare(w.openThreads().map(x => x.id), [u]);
        compare(w.railOrder(), [flights]);
        s.pages[ids[0]].lastActive -= 1000;
        compare(w.mostRecentPage(), flights, "the most recent page among this window's threads");
        compare(s.mostRecentPage(), ids[1]);
        compare(w.predictThread("csiphy lanes x1p42100", ""), "", "Ctrl+T predicts among this window's threads only");
        compare(s.predictThread("csiphy lanes x1p42100", ""), t);
        s.activate(ids[1]);
        w.activate(flights);
        compare(s.currentPage, ids[1], "each window has its own current page");
        compare(w.currentPage, flights);
        // Earlier is every window's
        s.fileThread(t);
        compare(w.filedThreads().map(x => x.id), [t]);
        w.restoreThread(t);
        compare(s.threadById(t).window, "w2", "restored from Earlier into the window that asked");
        compare(w.openThreads().map(x => x.id), [t, u]);
    }

    function test_onlyTheFirstWindowWritesTheFile() {
        const s = make();
        const w = other(s, "w2");
        const before = s.revision;
        w.newThread("t");
        compare(w.revision, s.revision);
        verify(s.revision > before, "a change in any window redraws every window");
        verify(s.saveTimer.running);
        verify(!w.saveTimer.running, "the other window's Session never saves");
        w.saveSoon();
        verify(!w.saveTimer.running);
    }

    function test_closingAWindowFilesItsThreadsAndCtrlShiftTBringsItBack() {
        const s = make();
        s.newThread("first window's");
        const w = other(s, "w2");
        const task = w.newThread("x1p42100 camera");
        const taskPages = [page(w, task, "[PATCH v3]"), page(w, task, "Issue #212")];
        const single = w.newThread("single");
        const lone = page(w, single, "Momsdeklaration - Skatteverket");
        w.update(lone, { from: "foot" });
        w.activate(lone);
        const stop = { url: w.pages[lone].url, heading: "Momsdeklaration", index: 2, offset: 30, x: 0, y: 900, at: 1 };
        w.setStopped(lone, stop);
        const order = w.openThreads().map(x => x.id);
        const gone = w.closeWindow("Momsdeklaration - Skatteverket", { railPinned: false, railWidth: 280, width: 1000, height: 700 });
        compare(gone.sort(), taskPages.concat([lone]).sort(), "every page's view goes");
        verify(s.threadById(task).earlier, "a multi-page thread is filed under Earlier");
        compare(s.threadById(single), null, "a single page goes to closed pages");
        compare(s.pages[lone], undefined);
        compare(w.openThreads(), []);
        compare(w.currentPage, "");
        const c = s.closed;
        compare(c[c.length - 2].url, "https://example.org/" + encodeURIComponent("Momsdeklaration - Skatteverket"));
        compare(c[c.length - 1].title, "Momsdeklaration - Skatteverket");
        compare(s.reopenName(), "the window Momsdeklaration - Skatteverket", "Ctrl+Shift+T names the window");
        compare(s.reopenClosed(), "", "reopening a window is Main's");
        // Ctrl+Shift+T in the first window
        const entry = s.takeWindow();
        verify(entry !== null);
        compare(entry.state.width, 1000);
        compare(entry.state.railPinned, false);
        compare(entry.singles.length, 1);
        verify(!s.closed.some(e => e.closedWith === entry.window || e.window === entry.window), "its entries leave the closed list");
        const n = other(s, "w3");
        n.restoreWindow(entry);
        const back = n.openThreads();
        compare(back.length, 2);
        compare(back[1].id, task, "in its rail order");
        verify(!s.threadById(task).earlier);
        compare(s.threadById(task).window, "w3");
        compare(s.threadById(task).pages, taskPages);
        compare(back[0].pages.length, 1, "the single page as a thread of one");
        compare(n.pages[n.currentPage].url, "https://example.org/" + encodeURIComponent("Momsdeklaration - Skatteverket"),
                "the page it showed is on screen");
        compare(n.pages[n.currentPage].from, "foot");
        compare(n.pages[n.currentPage].stopped, stop, "back where you stopped on it (PLAN.md 3.7)");
        verify(order.length === 2);
        compare(s.openThreads().map(x => x.title), ["first window's"], "the first window keeps its own");
        compare(s.takeWindow(), null);
    }

    // Clear browsing data (Settings > Privacy, PLAN.md 3.15): the closed pages go, a closed window's single pages too;
    // filed threads stay, and the window comes back with those
    function test_clearingClosedPages() {
        const s = make();
        s.addPage(s.newThread("closed page"), "https://example.org/closed", "");
        s.closePage(s.threads[0].pages[0]);
        const w = other(s, "w2");
        const task = w.newThread("task");
        page(w, task, "one");
        page(w, task, "two");
        page(w, w.newThread("single"), "lone");
        w.closeWindow("two", {});
        compare(s.closedPages().length, 2);
        s.clearClosedPages();
        compare(s.closedPages(), []);
        verify(s.threadById(task).earlier, "the filed thread stays");
        const entry = s.takeWindow();
        verify(entry !== null, "the window can come back");
        compare(entry.singles, []);
        const n = other(s, "w3");
        n.restoreWindow(entry);
        compare(n.openThreads().map(t => t.id), [task], "with its filed thread alone");
    }

    function test_aClosedWindowIsNotReopenedOnceNothingOfItIsLeft() {
        const s = make();
        s.addPage(s.newThread("closed page"), "https://example.org/closed", "");
        s.closePage(s.threads[0].pages[0]);
        const w = other(s, "w2");
        const task = w.newThread("task");
        page(w, task, "one");
        page(w, task, "two");
        w.closeWindow("two", {});
        compare(s.reopenName(), "the window two");
        s.restoreThread(task);
        compare(s.reopenName(), "https://example.org/closed", "its thread came back from Earlier: the entry before it is next");
        compare(s.takeWindow(), null);
    }

    function test_aThreadDraggedOntoAnotherWindowsRailMovesThere() {
        const s = make();
        const filed = s.newThread("filed");
        page(s, filed, "x");
        page(s, filed, "y");
        s.fileThread(filed);
        const mine = s.newThread("mine");
        page(s, mine, "a");
        const w = other(s, "w2");
        const t = w.newThread("moved");
        page(w, t, "one");
        page(w, t, "two");
        s.adoptThread(t, "");
        compare(s.threadById(t).window, "");
        compare(s.openThreads().map(x => x.id), [mine, t], "after the open threads when dropped below them");
        compare(w.openThreads(), []);
        s.adoptThread(t, mine);
        compare(s.openThreads().map(x => x.id), [t, mine], "before the thread it was dropped on");
    }

    function test_windowsSurviveARestart() {
        const s = make();
        const w = other(s, "w2");
        const a = page(s, s.newThread("first"), "a");
        const u = w.newThread("second");
        const b = page(w, u, "b");
        page(w, u, "c");
        s.activate(a);
        w.activate(b);
        s.windowRecords = () => [{ id: "", railPinned: true, width: 1280, height: 800, currentPage: s.currentPage },
                                 { id: "w2", railPinned: false, railWidth: 260, width: 900, height: 600, currentPage: w.currentPage, workspace: "3" }];
        s.save();
        const r = make();
        verify(r.load());
        compare(r.loadedWindow.width, 1280);
        compare(r.loadedWindows.length, 1);
        compare(r.loadedWindows[0].workspace, "3");
        compare(r.openThreads().map(x => x.title), ["first"]);
        compare(r.currentPage, a);
        const r2 = other(r, "w2");
        compare(r2.openThreads().map(x => x.id), [u], "each window's threads come back to it");
        verify(r2.ownOrAlways(b));
        verify(!r.ownOrAlways(b));
        // a record gone (a file from before several windows, or a window lost): its threads are the first window's
        s.windowRecords = () => [{ id: "" }];
        s.save();
        const r3 = make();
        r3.load();
        compare(r3.openThreads().length, 2);
        compare(r3.loadedWindows, []);
    }

    function test_sharedWords() {
        const [s, t] = withThread("x1p42100 camera", ["Re: softisp AGC starves on GPU"]);
        compare(s.sharedWords("softisp agc cpu mode", t), ["softisp", "agc"]);
        compare(s.sharedWords("flights", t), []);
    }

    // PLAN.md 3.14: a private window's Session shares no list and writes nothing, whatever changes in it
    function test_aPrivateWindowsSessionIsNeverSaved() {
        const main = make();
        main.newThread("main thread");
        const s = createTemporaryObject(sessionComponent, this, { windowId: "private-1", offTheRecord: true });
        const t = s.newThread("Flights ARN - MGQ");
        const id = s.addPage(t, "https://www.flysas.com/", "");
        s.activate(id);
        s.closePage(id);
        verify(!s.saveTimer.running, "a change starts no save");
        s.saveSoon();
        s.save();
        compare(Store.files.threads, undefined, "and a save writes nothing");
        compare(main.threads.length, 1, "the main window's threads are not its");
        compare(s.closed.length, 1, "its closed pages are its own, for its Ctrl+Shift+T");
        compare(main.closed.length, 0);
    }
}
