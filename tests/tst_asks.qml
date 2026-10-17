import QtQuick
import QtTest
import Browser
import "../qml"
import "../qml/Asks.js" as Asks
import "../qml/RailRows.js" as RailRows

// Asks.js and Sites.qml: the ask queue, its wording and the remembered choices (PLAN.md 3.8, 11).
TestCase {
    name: "Asks"

    Component { id: sitesComponent; Sites {} }

    function init() { Store.files = {} }

    function permission(id, origin, types, quiet) {
        return { id: id, kind: "permission", origin: origin, host: origin.replace(/^https?:\/\//, ""), types: types, requests: ["r" + id], quiet: !!quiet };
    }

    function test_orderPutsPageBlockingAsksFirstThenArrival() {
        const asks = [
            { id: 1, kind: "external", url: "magnet:?x" },
            permission(2, "https://meet.google.com", ["camera"]),
            { id: 3, kind: "leave" },
            { id: 4, kind: "claude" },
            { id: 5, kind: "signin" },
        ];
        compare(Asks.order(asks).map(a => a.id), [3, 5, 4, 2, 1], "leave and sign-in > Claude > permission > external app");
        compare(Asks.shown(asks).id, 3);
        compare(Asks.shown([]), null);
    }

    function test_quietAsksWaitOutsideTheQueue() {
        const asks = [permission(1, "https://news.example", ["notifications"], true)];
        compare(Asks.shown(asks), null, "a notification ask made without a click shows only the bell");
        compare(Asks.order(asks).length, 0);
        asks.push(permission(2, "https://meet.google.com", ["camera"]));
        compare(Asks.shown(asks).id, 2);
        compare(Asks.order(asks).length, 1, "the bell is not counted in 1 of N");
    }

    function test_permissionsFromOneOriginMergeIntoOneSentence() {
        let asks = Asks.add([], permission(1, "https://meet.google.com", ["microphone"]));
        asks = Asks.add(asks, permission(2, "https://meet.google.com", ["camera"]));
        compare(asks.length, 1);
        compare(asks[0].types, ["microphone", "camera"]);
        compare(asks[0].requests, ["r1", "r2"], "one answer settles both requests");
        compare(Asks.view(asks[0], "meet.google.com").lines[0].text, "Wants to use your microphone and camera");
        asks = Asks.add(asks, permission(3, "https://meet.google.com", ["camera"]));
        compare(asks[0].types, ["microphone", "camera"], "a type asked again is not repeated");
        asks = Asks.add(asks, permission(4, "https://docs.google.com", ["clipboard"]));
        compare(asks.length, 2, "another origin queues apart");
        asks = Asks.add(asks, permission(5, "https://meet.google.com", ["notifications"], true));
        compare(asks.length, 3, "a quiet ask does not ride along with a loud one");
    }

    function test_externalLinkAlreadyWaitingIsNotAskedTwice() {
        let asks = Asks.add([], { id: 1, kind: "external", url: "magnet:?xt=1" });
        asks = Asks.add(asks, { id: 2, kind: "external", url: "magnet:?xt=1" });
        compare(asks.length, 1);
        asks = Asks.add(asks, { id: 3, kind: "external", url: "magnet:?xt=2" });
        compare(asks.length, 2);
    }

    function test_preset_data() {
        return [
            { tag: "nothing decided: ask", decided: {}, types: ["camera"], want: "" },
            { tag: "allowed this load", decided: { camera: "allow" }, types: ["camera"], want: "allow" },
            { tag: "denied this load", decided: { camera: "deny" }, types: ["camera"], want: "deny" },
            { tag: "blocked lastingly", decided: { camera: "block" }, types: ["camera"], want: "deny" },
            { tag: "one of two allowed: ask", decided: { camera: "allow" }, types: ["microphone", "camera"], want: "" },
            { tag: "one of two refused: refuse", decided: { camera: "allow", microphone: "block" }, types: ["microphone", "camera"], want: "deny" },
            { tag: "both allowed", decided: { camera: "allow", microphone: "allow" }, types: ["microphone", "camera"], want: "allow" },
        ];
    }
    function test_preset(data) {
        compare(Asks.preset(data.types, t => data.decided[t] ?? ""), data.want);
    }

    function test_wording_data() {
        const signin = { kind: "signin", host: "router.lan", secure: false };
        return [
            { tag: "microphone", ask: permission(1, "https://meet.google.com", ["microphone"]), lines: ["Wants to use your microphone"],
              buttons: ["Allow once", "Deny"], negative: "deny" },
            { tag: "location", ask: permission(1, "https://maps.example", ["location"]), lines: ["Wants to know your location"] },
            { tag: "camera and location", ask: permission(1, "https://maps.example", ["camera", "location"]),
              lines: ["Wants to use your camera and know your location"] },
            { tag: "three", ask: permission(1, "https://maps.example", ["notifications", "location", "clipboard"]),
              lines: ["Wants to show notifications, know your location and see what you copy"] },
            { tag: "screen with sound", ask: Object.assign(permission(1, "https://meet.google.com", ["screen"]), { sound: true }),
              lines: ["Wants to share your screen and its sound"] },
            { tag: "an embed names itself", ask: permission(1, "https://zoom.us", ["camera"]), page: "example.com",
              lines: ["zoom.us wants to use your camera"] },
            { tag: "sign-in over http", ask: signin, lines: ["Sign in to router.lan"], notes: ["Sent without encryption"],
              buttons: ["Sign in", "Cancel"], fields: ["User", "Pass"], submit: "signin" },
            { tag: "sign-in over https", ask: Object.assign({}, signin, { secure: true }), notes: [] },
            { tag: "proxy names the proxy", ask: { kind: "proxy", host: "proxy.lokal:3128", secure: false },
              lines: ["Sign in to the proxy proxy.lokal:3128"], notes: [] },
            { tag: "client certificate", ask: { kind: "certificate", host: "vpn.lokal", options: ["abdul · Sectigo · 2027", "No certificate"] },
              page: "vpn.lokal", lines: ["Wants a certificate to identify you"], options: ["abdul · Sectigo · 2027", "No certificate"],
              buttons: ["Send", "Cancel"], negative: "cancel" },
            { tag: "before you leave, fixed wording", ask: { kind: "leave", host: "github.com" },
              lines: ["Leave this page?", "github.com has changes that may not be saved."], buttons: ["Leave", "Stay"], negative: "stay" },
            { tag: "passkey, touch", ask: { kind: "passkey", host: "github.com", state: "touch" }, page: "github.com",
              lines: ["Wants to use a passkey", "Touch your security key"], buttons: ["Cancel"] },
            { tag: "passkey, PIN", ask: { kind: "passkey", host: "github.com", state: "CollectPin", pinReason: "Challenge", pinError: "WrongPin", attempts: 2 },
              page: "github.com", fields: ["Key PIN"], notes: ["Wrong PIN · 2 tries left"], submit: "pin" },
            { tag: "passkey failed", ask: { kind: "passkey", host: "github.com", state: "RequestFailed", failure: "Timeout" }, page: "github.com",
              lines: ["Wants to use a passkey", "The security key didn't answer in time"], buttons: ["Try again", "Cancel"] },
            { tag: "screen share lists", ask: { kind: "screen", host: "meet.google.com", options: ["Entire screen · eDP-1", "Window · foot"] },
              page: "meet.google.com", lines: ["Wants to share your screen"], options: ["Entire screen · eDP-1", "Window · foot"], buttons: ["Share", "Cancel"] },
            { tag: "screen share in the portal's picker", ask: { kind: "screen", host: "meet.google.com", picker: true, options: ["x"] },
              page: "meet.google.com", lines: ["Wants to share your screen", "Choose what to share in the picker"], options: [] },
            { tag: "external app", ask: { kind: "external", host: "webtorrent.io", scheme: "magnet", app: "qBittorrent" }, page: "webtorrent.io",
              lines: ["Wants to open a magnet: link in qBittorrent", "(default app for magnet:)"], buttons: ["Open", "Cancel"] },
            { tag: "external app, a vowel", ask: { kind: "external", host: "x.org", scheme: "irc", app: "HexChat" }, page: "x.org",
              lines: ["Wants to open an irc: link in HexChat", "(default app for irc:)"] },
            { tag: "no app for the scheme", ask: { kind: "external", host: "webtorrent.io", scheme: "magnet", app: "" }, page: "webtorrent.io",
              lines: ["No app opens magnet: links"], buttons: ["Copy link", "Cancel"], negative: "cancel" },
        ];
    }
    function test_wording(data) {
        const v = Asks.view(data.ask, data.page ?? data.ask.host);
        if (data.lines)
            compare(v.lines.map(l => l.text), data.lines);
        if (data.notes)
            compare(v.notes, data.notes);
        if (data.buttons)
            compare(v.buttons.map(b => b.label), data.buttons);
        if (data.fields)
            compare(v.fields.map(f => f.label), data.fields);
        if (data.options)
            compare(v.options, data.options);
        if (data.negative)
            compare(v.negative, data.negative);
        if (data.submit)
            compare(v.submit, data.submit);
        verify(v.buttons.length > 0, "every ask can be answered");
        verify(v.buttons.some(b => b.choice === v.negative), "Esc picks one of its buttons");
    }

    function test_externalSchemes() {
        verify(Asks.external("magnet:?xt=urn:btih:abc"));
        verify(Asks.external("mailto:someone@example.org"));
        verify(Asks.external("zoommtg://zoom.us/join?confno=1"));
        verify(!Asks.external("https://example.org/"));
        verify(!Asks.external("view-source:https://example.org/"));
        verify(!Asks.external("data:text/html,x"));
        verify(!Asks.external("about:blank"));
        verify(!Asks.external("javascript:void(0)"));
        verify(!Asks.external("relative/path"), "no scheme is no app");
        compare(Asks.scheme("MAGNET:?x"), "magnet");
    }

    function test_originOf() {
        compare(Asks.originOf("https://Meet.Google.com/xqz-bnkt-pwe?authuser=0"), "https://meet.google.com");
        compare(Asks.originOf("http://user:pw@router.lan:8080/admin"), "http://router.lan:8080", "not the user:pass@");
        compare(Asks.originOf("data:text/html,x"), "");
    }

    // WebEngineClientCertificateSelection.host has no scheme: "//vpn.lokal:443"
    function test_tlsOrigin() {
        compare(Asks.tlsOrigin("//VPN.lokal:443"), "https://vpn.lokal");
        compare(Asks.tlsOrigin("//vpn.lokal:8443"), "https://vpn.lokal:8443");
        compare(Asks.tlsOrigin("//vpn.lokal:4430"), "https://vpn.lokal:4430");
        compare(Asks.tlsOrigin("//[::1]:443"), "https://[::1]");
        compare(Asks.tlsOrigin("vpn.lokal"), "https://vpn.lokal");
        compare(Asks.tlsOrigin(""), "");
        // its host is the card's, so the ask does not name itself
        for (const [host, page] of [["//vpn.lokal:443", "https://vpn.lokal/login"], ["//vpn.lokal:8443", "https://vpn.lokal:8443/"]]) {
            const h = RailRows.split(Asks.tlsOrigin(host)).host;
            compare(h, RailRows.split(page).host);
            compare(Asks.view({ kind: "certificate", host: h, options: ["No certificate"] }, RailRows.split(page).host).lines[0].text,
                    "Wants a certificate to identify you");
        }
    }

    function test_certLabel() {
        compare(Asks.certLabel("abdul", "Sectigo", new Date(2027, 2, 1)), "abdul · Sectigo · 2027");
        compare(Asks.certLabel("abdul", "", null), "abdul");
    }

    function test_useGlyphsMostTellingFirst() {
        compare(Asks.glyphs(["location", "microphone", "camera"]), ["videocam", "mic", "location_on"]);
        compare(Asks.glyphs(["notifications"]), [], "notifications use nothing on this machine");
        compare(Asks.glyphs(["screen", "microphone"])[0], "screen_share");
    }

    function test_sitesRememberChoicesByOrigin() {
        const s = createTemporaryObject(sitesComponent, this);
        compare(s.choice("https://meet.google.com", "camera"), "");
        s.setChoice("https://meet.google.com", "camera", "allow");
        s.setChoice("https://meet.google.com", "app:zoommtg", "block");
        compare(s.choice("https://meet.google.com", "camera"), "allow");
        compare(s.choice("http://meet.google.com", "camera"), "", "another scheme is another origin");
        s.save();
        const t = createTemporaryObject(sitesComponent, this);
        t.load();
        compare(t.choice("https://meet.google.com", "camera"), "allow", "kept across a restart");
        compare(t.choice("https://meet.google.com", "app:zoommtg"), "block");
        t.setChoice("https://meet.google.com", "camera", "");
        compare(t.choice("https://meet.google.com", "camera"), "", "cleared back to asking");
    }

    function test_sitesNoteWhatWasAsked() {
        const s = createTemporaryObject(sitesComponent, this);
        s.noteAsked("https://meet.google.com", ["microphone", "camera"]);
        verify(s.entries["https://meet.google.com"].asked.camera > 0, "the site panel lists what a site asked for");
        compare(s.choice("https://meet.google.com", "camera"), "", "asking is not a choice");
        s.noteAsked("", ["camera"]);
        compare(Object.keys(s.entries).length, 1, "a page without an origin notes nothing");
    }
}
