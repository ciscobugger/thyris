import QtQuick
import QtTest
import "../qml/Failures.js" as Failures

// Failures.js: which page a failure shows and its wording (PLAN.md 3.8 8f-8i).
TestCase {
    name: "Failures"

    readonly property double at: new Date(2026, 8, 24, 14, 12).getTime()

    function failed(f) { return Failures.load(Object.assign({ at: at, domain: "connection", reachability: "online", watching: true, hosts: [] }, f)) }

    function test_offline() {
        const p = failed({ url: "https://lore.kernel.org/linux-media/", code: -106, name: "net::ERR_INTERNET_DISCONNECTED" });
        compare(p.kind, "offline");
        compare(p.title, "Can't reach lore.kernel.org");
        compare(p.body, ["This computer has no network connection.", "The page loads again by itself when the network is back."]);
        compare(p.actions.map(a => a.label), ["Try again"]);
        compare(p.code, "ERR_INTERNET_DISCONNECTED");
        compare(p.codeNote, "tried 14:12");
        compare(p.cardLine, "");
        compare(p.tone, "");
    }
    function test_offlineByTheBackend() {
        const p = failed({ url: "https://lore.kernel.org/", code: -105, name: "net::ERR_NAME_NOT_RESOLVED", reachability: "none" });
        compare(p.kind, "offline", "no network by the backend's account: not a name that doesn't exist");
        compare(p.code, "ERR_NAME_NOT_RESOLVED");
    }
    function test_offlineClaimsNoReloadWithoutABackend() {
        compare(failed({ url: "https://lore.kernel.org/", code: -106, watching: false }).body, ["This computer has no network connection."]);
    }
    function test_thisMachineIsNeverOffline() {
        compare(failed({ url: "http://localhost:8080/", code: -102, name: "net::ERR_CONNECTION_REFUSED", reachability: "none" }).kind, "connection");
    }

    function test_nameNotFound() {
        const p = failed({ url: "https://www.lore.kernl.org/all/", code: -105, name: "net::ERR_NAME_NOT_RESOLVED",
                           hosts: ["github.com", "lore.kernel.org", "lwn.net"] });
        compare(p.kind, "name");
        compare(p.title, "lore.kernl.org doesn't exist");
        compare(p.body, ["DNS has no address for this name."]);
        compare(p.actions.map(a => a.label), ["Did you mean lore.kernel.org?", "Search"]);
        compare(p.near, "lore.kernel.org");
        compare(p.search, "lore.kernl.org");
    }
    function test_nameNotFoundWithNothingNear() {
        compare(failed({ url: "https://qwzx.example/", code: -105, hosts: ["github.com"] }).actions.map(a => a.action), ["search"]);
    }
    function test_oneEdit_data() {
        return [
            { tag: "a letter dropped", a: "lore.kernl.org", b: "lore.kernel.org", near: true },
            { tag: "a letter added", a: "githubb.com", b: "github.com", near: true },
            { tag: "a letter changed", a: "lwm.net", b: "lwn.net", near: true },
            { tag: "two edits", a: "lroe.kernel.org", b: "lore.kernel.org", near: false },
            { tag: "the same name", a: "lwn.net", b: "lwn.net", near: false },
        ];
    }
    function test_oneEdit(data) {
        compare(Failures.oneEdit(data.a, data.b), data.near);
    }

    function test_noReply() {
        const p = failed({ url: "http://lore.kernel.org/", code: 0, domain: "", waited: 30 });
        compare(p.kind, "noReply");
        compare(p.title, "lore.kernel.org didn't answer");
        compare(p.body, ["No reply within 30 s."]);
        compare(p.actions.map(a => a.label), ["Try again"]);
        compare(p.code, "", "the browser stopped it: no Chromium error to name");
    }
    function test_chromiumTimeoutsReadAsNoReply() {
        const p = failed({ url: "http://lore.kernel.org/", code: -118, name: "net::ERR_CONNECTION_TIMED_OUT", waited: 131.4 });
        compare(p.body, ["No reply within 131 s."]);
        compare(p.code, "ERR_CONNECTION_TIMED_OUT");
    }
    function test_otherConnectionFailures() {
        const p = failed({ url: "http://127.0.0.1:8080/x", code: -102, name: "net::ERR_CONNECTION_REFUSED" });
        compare(p.kind, "connection");
        compare(p.title, "Can't reach 127.0.0.1:8080");
        compare(p.body, []);
    }
    function test_chromiumsHttpErrorsAreFailures() {
        const p = failed({ url: "https://github.com/x", code: -310, domain: "http", name: "net::ERR_TOO_MANY_REDIRECTS" });
        compare(p.kind, "connection");
        compare(p.code, "ERR_TOO_MANY_REDIRECTS");
    }
    function test_theBrowserAddsNothing_data() {
        return [
            { tag: "HTTP 404 with the site's page", code: 404, domain: "status" },
            { tag: "a stop, a download, a load put in its place", code: -3, domain: "internal" },
            { tag: "a certificate: its own page", code: -202, domain: "certificate" },
        ];
    }
    function test_theBrowserAddsNothing(data) {
        compare(failed({ url: "https://github.com/x", code: data.code, domain: data.domain }), null);
    }

    readonly property double apr12: new Date(2015, 3, 12).getTime()
    function cert(c) {
        return Failures.certificate(Object.assign({ url: "https://expired.badssl.com/", at: at, now: at, overridable: true,
            names: ["*.badssl.com", "badssl.com"], subject: "*.badssl.com", issuer: "COMODO RSA Domain Validation Secure Server CA",
            from: new Date(2015, 3, 9).getTime(), until: apr12, sha256: "ba:10:5c:3f" }, c));
    }
    function test_certificateExpired() {
        const p = cert({ type: -201 });
        compare(p.kind, "certificate");
        compare(p.title, "The certificate for expired.badssl.com expired");
        compare(p.body, ["It expired on 12 Apr 2015. Someone on this network could read or change what you send to this site."]);
        compare(p.actions.map(a => a.label), ["Go back"]);
        compare(p.details, ["Issued to *.badssl.com by COMODO RSA Domain Validation Secure Server CA",
                            "Valid 9 Apr 2015 - 12 Apr 2015 · SHA-256 ba:10:5c:3f"]);
        compare(p.code, "ERR_CERT_DATE_INVALID");
        compare(p.go, "Continue to expired.badssl.com once (not safe)");
        compare(p.cardLine, "Certificate expired");
        compare(p.tone, "error");
    }
    function test_certificateTitles_data() {
        return [
            { tag: "wrong name", type: -200, title: "The certificate is for *.badssl.com, not this site", go: true },
            { tag: "self-signed", type: -202, title: "No known authority signed this certificate", go: true },
            { tag: "revoked", type: -206, title: "The issuer revoked this certificate", go: false },
            { tag: "HSTS site", type: -201, overridable: false, title: "expired.badssl.com only allows secure connections, and this one isn't", go: false },
        ];
    }
    function test_certificateTitles(data) {
        const p = cert({ type: data.type, overridable: data.overridable ?? true });
        compare(p.title, data.title);
        compare(p.go !== "", data.go);
        compare(p.actions.map(a => a.label), ["Go back"]);
    }

    function test_stopped_data() {
        return [
            { tag: "Qt's killed", status: "killed", code: 0, how: "killed" },
            { tag: "SIGKILL, reported as crashed with the raw status", status: "crashed", code: 9, how: "killed" },
            { tag: "SIGSEGV", status: "crashed", code: 11, how: "crashed" },
            { tag: "caught by Chromium's handler: exit 250 (raw 64000)", status: "abnormal", code: 64000, how: "exited", exit: 250 },
            { tag: "exited 241, reported as crashed", status: "crashed", code: 61696, how: "exited", exit: 241 },
            { tag: "a plain exit code", status: "abnormal", code: 3, how: "exited", exit: 3 },
        ];
    }
    function test_stopped(data) {
        const s = Failures.stopped(data.status, data.code);
        compare(s.how, data.how);
        if (data.exit !== undefined)
            compare(s.code, data.exit);
    }
    function test_twice() {
        const now = at;
        verify(!Failures.twice([now], now));
        verify(Failures.twice([now - 9 * 60000, now], now));
        verify(!Failures.twice([now - 11 * 60000, now], now), "the first was more than 10 minutes ago");
    }

    function test_crashKilled() {
        const p = Failures.crash({ url: "https://www.youtube.com/watch?v=x", at: at, pid: 48211, how: "killed", code: 0,
                                   memory: { bytes: 1.1 * 1073741824, at: new Date(2026, 8, 24, 14, 31).getTime() },
                                   stop: { source: "systemd-oomd", at: new Date(2026, 8, 24, 14, 31).getTime() }, siblings: 2 });
        compare(p.title, "This page's process was stopped");
        compare(p.body, ["youtube.com was using about 1.1 GB (measured 14:31). The system stopped it because memory ran low. "
                         + "Two other pages shared its process. They are unloaded and load again when you open them."]);
        compare(p.actions.map(a => a.label), ["Reload"]);
        compare(p.details, ["killed · pid 48211 · journal: systemd-oomd, 14:31"]);
    }
    function test_crashSaysOnlyWhatWasMeasured() {
        const p = Failures.crash({ url: "https://www.youtube.com/", at: at, pid: 7, how: "killed", code: 0, memory: null, stop: null, siblings: 1 });
        compare(p.body, ["One other page shared its process. It is unloaded and loads again when you open it."], "no size, no cause");
        compare(p.details, ["killed · pid 7"]);
        compare(Failures.crash({ url: "https://a.org/", at: at, pid: 7, how: "killed", siblings: 0 }).body, []);
    }
    function test_crashWording() {
        compare(Failures.crash({ url: "https://a.org/", at: at, pid: 7, how: "crashed", siblings: 0 }).title, "This page crashed");
        const exited = Failures.crash({ url: "https://a.org/", at: at, pid: 7, how: "exited", code: 250, siblings: 0, twice: true });
        compare(exited.title, "The page's process exited with code 250");
        compare(exited.body, ["It stopped twice in 10 minutes."]);
        compare(exited.details, ["exited with code 250 · pid 7"]);
        verify(exited.twice);
        compare(Failures.crash({ url: "https://a.org/", at: at, pid: 7, how: "crashed", stop: { source: "kernel", at: at }, siblings: 0 }).body, [],
                "memory ran low is said only of a killed process");
    }

    function test_afterStart() {
        compare(Failures.afterStart(null, at).crashed, false, "a first start");
        compare(Failures.afterStart({ clean: true }, at).crashed, false);
        const s = Failures.afterStart({ clean: false, alive: at - 60000, page: "p1" }, at);
        verify(s.crashed);
        compare(s.at, at - 60000);
        compare(s.page, "p1");
        compare(s.leaveOut, "");
        compare(Failures.afterStart({ clean: false, alive: at, page: "p1", suspect: "p1" }, at).leaveOut, "p1",
                "it stopped again within a minute of opening that page");
    }
    function test_restore() {
        const p = Failures.restore({ at: new Date(2026, 8, 24, 14, 2).getTime(), pageId: "p1", title: "camss: CSIPHY0 lanes ignored #212" });
        compare(p.title, "The browser did not close cleanly at 14:02");
        compare(p.body, ["Your tasks are back. No page loads until you open it."]);
        compare(p.actions.map(a => a.label), ["Open camss: CSIPHY0 lanes ignored #212"]);
        compare(p.note, "That page was on screen when the browser stopped. If it stops the browser again, it stays closed next time.");
        const out = Failures.restore({ at: at, pageId: "", title: "", leftOut: "Vibin - wxoda" });
        compare(out.actions, []);
        compare(out.note, "Vibin - wxoda was open when the browser stopped twice, so it was left out. It is listed in History.");
        compare(Failures.restore({ at: at, pageId: "", title: "" }).note, "", "no page was on screen");
    }
}
