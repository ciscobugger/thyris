import QtQuick
import QtWebEngine
import Browser
import "Downloads.js" as Downloads
import "RailRows.js" as RailRows

// Downloads (PLAN.md 3.8 8d). Every file goes to `folder` without a dialog. Main hands each of the
// profile's downloads here with the page that started it; this keeps its record in the session
// (Downloads.js), runs its row's actions, and writes the file's origin on it when it lands. Requests live
// for this run only: Qt WebEngine cancels what is still coming when it quits, so Retry on a record without
// one loads its address again in Main's hidden fetcher view. An http file from an https page is not
// accepted (Qt deletes the request) and Keep fetches it the same way: pausing it at once instead races a
// small file, which lands before the pause takes hold.
QtObject {
    id: downloader

    required property var session
    // Settings > Downloads (PLAN.md 3.15): Main's, Disk.downloads unless a folder is set
    property string folder: Disk.downloads
    property var requests: ({})         // record id -> WebEngineDownloadRequest, this run's
    property var listed: []             // pages whose several downloads are listed in place
    property var fetchQueue: []         // record ids waiting on the fetcher, the first loading
    // the address the fetcher loads; "" while it has none (Main's fetcher exists only then)
    property string fetchUrl: ""
    // a file of this run still coming, not paused (the fetcher's too): quitting would cancel it (Main.lastWindowGone)
    readonly property bool coming: { session.revision; return session.downloads.some(d => d.state === "running") }
    signal started(string id)           // a download that goes ahead (not a held one): Main's notice while folded

    // `pageId`: the page whose view started it ("" for none); `viewUrl`: that view's address (an attached
    // popup's own, not its opener's), "" when you typed the address; `fetched`: it came from the fetcher.
    // Returns its record's id, "" for none.
    function requested(request, pageId, viewUrl, fetched) {
        const now = Date.now();
        const retried = fetched ? session.downloadById(fetchQueue[0] ?? "") : null;
        // its record was removed while the fetcher loaded it
        if (fetched && !retried) {
            request.cancel();
            nextFetch();
            return "";
        }
        const p = session.pages[pageId] ?? null;
        const t = p && p.thread ? session.threadById(p.thread) : null;
        const url = String(request.url);
        const held = !fetched && Downloads.insecure(url, viewUrl);
        if (request.downloadDirectory !== downloader.folder)
            request.downloadDirectory = downloader.folder;
        const fields = { url: url, file: request.downloadFileName, path: request.downloadDirectory + "/" + request.downloadFileName,
                         total: request.totalBytes > 0 ? request.totalBytes : -1, received: 0, left: -1, state: held ? "blocked" : "running",
                         reason: "", warn: "", started: now, finished: 0, opened: 0 };
        let id = "";
        if (retried) {
            id = retried.id;
            session.updateDownload(id, fields);
            nextFetch();
        } else {
            id = session.addDownload(Object.assign(fields, { page: pageId, from: !p ? null : { title: p.title || RailRows.untitled(p.url), icon: p.icon || "",
                                                                                        always: p.thread === "", url: p.url, thread: t ? t.title : "" } }));
        }
        if (held)
            return id;
        requests[id] = request;
        request.stateChanged.connect(() => downloader.changed(id));
        request.isPausedChanged.connect(() => downloader.changed(id));
        request.accept();
        started(id);
        ticker.start();
        pages();
        return id;
    }

    // The request's state, in its record.
    function changed(id) {
        const r = requests[id], d = session.downloadById(id);
        if (!r || !d)
            return;
        const S = WebEngineDownloadRequest;
        if (r.state === S.DownloadInProgress) {
            session.updateDownload(id, { state: r.isPaused ? "paused" : "running", reason: "" });
        } else if (r.state === S.DownloadCompleted) {
            session.updateDownload(id, { state: "done", received: r.receivedBytes, total: r.totalBytes > 0 ? r.totalBytes : r.receivedBytes, left: -1,
                                         finished: Date.now(), warn: Downloads.runsAsProgram(d.file) ? "program" : "" });
            delete requests[id];
            const from = d.from ?? {};
            // a private window's file keeps no record of where it came from (PLAN.md 3.14)
            if (!session.offTheRecord)
                Disk.mark(d.path, { "user.xdg.origin.url": d.url, "user.xdg.referrer.url": from.url ?? "", "user.browser.thread": from.thread ?? "" });
            schedule();
        } else if (r.state === S.DownloadCancelled) {
            delete requests[id];
            session.removeDownload(id);
        } else if (r.state === S.DownloadInterrupted) {
            session.updateDownload(id, { state: "failed", reason: Downloads.reason(r.interruptReason), left: -1 });
        }
        pages();
    }

    // What has come and how long the rest will take, every 500 ms while anything is coming: the rail is
    // rebuilt once a tick for all of them. The rate is smoothed so the time left does not jump with each sample.
    property var samples: ({})
    property Timer ticker: Timer {
        interval: 500
        repeat: true
        onTriggered: downloader.tick()
    }
    function tick() {
        const now = Date.now();
        let coming = false, moved = false;
        for (const id in requests) {
            const r = requests[id], d = session.downloadById(id);
            if (!d || d.state !== "running")
                continue;
            coming = true;
            const got = r.receivedBytes, total = r.totalBytes;
            const s = samples[id] ?? { at: now, got: got, rate: 0 };
            const dt = (now - s.at) / 1000;
            if (dt > 0)
                s.rate = s.rate > 0 ? 0.7 * s.rate + 0.3 * (got - s.got) / dt : (got - s.got) / dt;
            s.at = now;
            s.got = got;
            samples[id] = s;
            moved = session.updateDownload(id, { received: got, total: total > 0 ? total : -1, left: total > 0 && s.rate > 0 ? (total - got) / s.rate : -1 }, true) || moved;
        }
        if (moved)
            session.revision++;
        if (!coming)
            ticker.stop();
    }

    // A row's action (Downloads.actions), or a click on it: "open" on a finished one.
    function act(id, action) {
        const d = session.downloadById(id), r = requests[id] ?? null;
        if (!d)
            return;
        switch (action) {
        case "pause":
            if (r) r.pause();
            break;
        case "resume":
            if (r) resume(id, r);
            break;
        case "cancel":
            if (r) r.cancel();
            else session.removeDownload(id);
            break;
        case "retry":
            if (r && r.state === WebEngineDownloadRequest.DownloadInterrupted) {
                session.updateDownload(id, { state: "running", reason: "" });
                resume(id, r);
            } else if (!r) {
                fetch(d);
            }
            break;
        case "remove":
            // cancelling an interrupted request leaves its part-file (<name>.download), so it goes here
            if (r) {
                r.cancel();
                delete requests[id];
            }
            Disk.remove(d.path + ".download");
            session.removeDownload(id);
            break;
        case "open":
            Apps.open(d.path);
            session.updateDownload(id, { opened: Date.now() });
            schedule();
            break;
        case "show":
            Apps.reveal(d.path);
            break;
        case "keep":
            if (d.state === "blocked")
                fetch(d);
            else
                session.updateDownload(id, { warn: "" });
            break;
        case "delete":
            Disk.remove(d.path);
            session.removeDownload(id);
            break;
        }
        pages();
    }
    function resume(id, r) {
        delete samples[id];
        r.resume();
        ticker.start();
    }
    // a click on "3 downloads": they are listed in place, or folded back into it
    function toggleListed(pageId) {
        listed = listed.indexOf(pageId) >= 0 ? listed.filter(p => p !== pageId) : listed.concat([pageId]);
    }

    // A page closed or filed: a file it held back as insecure goes with it, never fetched.
    function pageGone(pageId) {
        for (const d of session.downloads.slice())
            if (d.page === pageId && d.state === "blocked")
                act(d.id, "cancel");
        listed = listed.filter(p => p !== pageId);
    }

    // Retry without a request (it failed in an earlier run), or Keep on a held one: the fetcher loads the
    // address, one at a time, and the download that answers takes the record's place. A page that loads
    // instead has no file there.
    function fetch(d) {
        if (fetchQueue.indexOf(d.id) >= 0)
            return;
        session.updateDownload(d.id, { state: "running", reason: "", received: 0, total: -1, left: -1 });
        fetchQueue = fetchQueue.concat([d.id]);
        if (fetchQueue.length === 1)
            fetchUrl = d.url;
    }
    // Main's fetcher: its load ended with no download
    function fetchFailed(reason) {
        const id = fetchQueue[0];
        if (id)
            session.updateDownload(id, { state: "failed", reason: reason });
        nextFetch();
    }
    function nextFetch() {
        fetchQueue = fetchQueue.slice(1);
        // not from inside the fetcher's own signal; through "", so each address gets a fresh view, even the same one again
        Qt.callLater(() => {
            const d = downloader.session.downloadById(downloader.fetchQueue[0] ?? "");
            downloader.fetchUrl = "";
            if (d)
                downloader.fetchUrl = d.url;
        });
    }

    // Each page's `downloading` (Lifecycle.js: it stays live) and the folded thread's rolled-up ↓.
    function pages() {
        const coming = new Set(session.downloads.filter(d => d.state === "running" || d.state === "paused").map(d => d.page));
        for (const id in session.pages)
            if (!!session.pages[id].downloading !== coming.has(id))
                session.update(id, { downloading: coming.has(id) });
    }

    // A row leaves 10 min after its file was opened, and a finished one Downloads.keepLanded after it landed: the rail is
    // rebuilt when the next one is due.
    property Timer expiry: Timer {
        onTriggered: { downloader.session.revision++; downloader.schedule() }
    }
    function schedule() {
        const now = Date.now();
        const due = session.downloads.filter(d => d.opened && now - d.opened < Downloads.keepOpened).map(d => d.opened + Downloads.keepOpened - now)
            .concat(session.downloads.filter(d => d.state === "done" && d.warn !== "program" && d.finished && !Downloads.landed(d, now))
                                     .map(d => d.finished + Downloads.keepLanded - now));
        if (due.length === 0) {
            expiry.stop();
            return;
        }
        expiry.interval = Math.max(1000, Math.min(...due) + 100);
        expiry.restart();
    }
}
