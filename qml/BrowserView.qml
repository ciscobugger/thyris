import QtQuick
import QtWebChannel
import QtWebEngine
import "Asks.js" as Asks
import "Failures.js" as Failures
import "Logins.js" as Logins
import "PageMenu.js" as PageMenu
import "PageState.js" as PageState
import "Reader.js" as Reader
import "RailRows.js" as RailRows
import "Recall.js" as Recall

// One page. The C++ interceptor refuses ad requests; on each main-frame navigation this sets the
// page's uBlock scriptlets (main world, before the page's own scripts) and element hiding.
WebEngineView {
    id: view

    property string pageId
    property QtObject adblock
    property var session
    property var visits     // the History model (WebEngineView owns "history")
    property var sites      // lasting per-site choices (Sites.qml)
    property var certificates   // Main's certificates continued past, shared by every page (continueCertificate)

    // A link or script asked for a new page; Main files it in this page's thread.
    signal openRequested(var request)
    // A link on an Always site led to another site; it opens as a new thread instead (PLAN.md 3.12).
    signal leaveAlways(string url)
    signal asked(var ask)                   // a new ask for the card (not a quiet one)
    signal copyRequested(string text)       // Copy link in an external-app ask
    signal closeAccepted()                  // requestClose() passed the page's "Leave this page?"
    signal closeKept()                      // Stay at the "Leave this page?" of a close
    signal selfClosed()                     // the page called window.close() (an attached popup closes on it)
    signal closeWanted()                    // Go back on a failure with nothing to go back to
    signal zoomWanted(int steps)            // Ctrl and the wheel, or a pinch, over the page (PageItem.zoomGesture)
    signal processStopped(string status, int code)  // renderProcessTerminated; `lastPid` was the process
    signal saveWanted(var ask)              // Save at a private window's "Save to the main profile?" (PLAN.md 3.14)
    signal loginFailed(string text)         // a login not saved or not filled, in the card's words (Logins.failed)
    signal printWanted()                    // the page called window.print() (PLAN.md 3.16)
    signal gone()                           // the view is being destroyed (a PDF it was making never comes)
    Component.onDestruction: {
        if (iconHeld !== "")
            Engine.iconUnloaded(iconHeld, false)
        gone()
    }

    // Every link to another app's scheme reaches onNavigationRequested, which refuses it and asks
    // "Open in <app>?" instead; nothing launches without that ask.
    settings.unknownUrlSchemePolicy: WebEngineSettings.AllowAllUnknownUrlSchemes
    // getDisplayMedia is refused outright without it; the screen-share ask decides
    settings.screenCaptureEnabled: true
    // a PDF shows in Chromium's viewer, as a page (PLAN.md 3.17); with plugins off the engine downloads it
    settings.pluginsEnabled: true
    // Print's Backgrounds is Off until you choose On (PLAN.md 3.16); Qt's default prints them
    settings.printElementBackgrounds: false

    onNavigationRequested: request => {
        if (Asks.external(String(request.url))) {
            request.reject();
            askExternal(String(request.url));
            return;
        }
        if (!request.isMainFrame)
            return
        if (request.navigationType === WebEngineNavigationRequest.FormSubmittedNavigation) {
            formSentAt = Date.now();
            if (armedLogin && Date.now() - armedLogin.at < 5000)
                takeArmed();
        }
        if (request.navigationType === WebEngineNavigationRequest.RedirectNavigation) {
            loadingHost = RailRows.split(String(request.url)).host
            attemptAnswers()
        } else {
            typedLoad = request.navigationType === WebEngineNavigationRequest.TypedNavigation
            navigationType = request.navigationType
        }
        if (request.navigationType === WebEngineNavigationRequest.LinkClickedNavigation
                && session.leavesAlways(pageId, String(request.url))) {
            rejected = String(request.url)
            request.reject()
            view.leaveAlways(String(request.url))
            return
        }
        // Continue lasts for one page load (PLAN.md 8g), but the engine lets a host it was told to accept
        // through until the browser quits: every later load there shows the certificate's page again
        const host = PageState.hostOf(String(request.url))
        const accepted = certificates && /^https:/i.test(String(request.url)) ? certificates.accepted[host] : undefined
        // A form sent from the page let past this host's certificate goes on: its data cannot be sent again
        // after a refusal (Continue could only load the address).
        const form = request.navigationType === WebEngineNavigationRequest.FormSubmittedNavigation
            || request.navigationType === WebEngineNavigationRequest.FormResubmittedNavigation
        const sent = form && questioned !== null && PageState.hostOf(String(url)) === host
        if (accepted && continuing !== host && !sent && request.navigationType !== WebEngineNavigationRequest.RedirectNavigation) {
            rejected = String(request.url)
            request.reject()
            // an https attempt falls back to http, as for any certificate that fails
            if (fallback !== "") {
                const http = fallback
                endAttempt()
                Qt.callLater(() => view.url = http)
                return
            }
            failure = Object.assign({}, accepted, { url: String(request.url), at: Date.now(), key: String(request.url) + " " + Date.now(),
                                                    committed: false, under: covered(), navigation: request.navigationType })
            return
        }
        loadingUrl = String(request.url)
        replyTimer.restart()
        applyCosmetics(request.url)
    }
    onNewWindowRequested: request => view.openRequested(request)
    // A main-frame navigation refused above: its LoadStarted (it still comes, before ERR_ABORTED) replaces
    // no document.
    property string rejected: ""
    // The last main-frame load was typed or the browser's own (Main sets url), not one the page started: a
    // download it turns into has no page behind it, so it is never held as insecure (PLAN.md 8d).
    property bool typedLoad: false
    // the last main-frame navigation's type (not a redirect's), for what a new load keeps
    property int navigationType: WebEngineNavigationRequest.OtherNavigation

    // a new view whose first load stops or fails without a page reports no address; the page keeps its own
    onUrlChanged: {
        if (String(url) !== "")
            session.update(pageId, { url: String(url) })
        // the page's own address change (history.pushState) leaves the article; a link to a heading in it does not
        if (reader && String(url).split("#")[0] !== readerAt)
            toggleReader(null, () => {})
        if (!loading && article !== "" && String(url).split("#")[0] !== articleAt) {
            article = ""
            if (visible) {
                probeArticle()
                articleAgain.restart()
            }
        }
        // the page's own address change (pushState) may bring other headings
        if (readsSections && visible && !loading)
            sectionsSoon.restart()
    }
    // the title the browser keeps: none for Chromium's stand-in of a data:, about:blank or view-source: address
    readonly property string pageTitle: RailRows.pageTitle(title, String(url))
    onTitleChanged: {
        const t = RailRows.pageTitle(title, String(url))
        session.update(pageId, { title: t })
        visits.retitle(String(url), t)
    }
    onIconChanged: {
        session.update(pageId, { icon: String(icon) })
        visits.reicon(String(url), String(icon))
        // the copy every favicon is drawn from, saved while this view is live (Engine.keepIcon)
        if (iconHeld !== "") {
            Engine.iconUnloaded(iconHeld, false)
            iconHeld = ""
        }
        if (lifecycleState === WebEngineView.LifecycleState.Discarded)
            holdIcon()
        else
            Engine.keepIcon(String(icon))
    }
    // the address Engine counts this view as holding while it is unloaded: Qt's favicon provider must not be asked for
    // it then (it crashed in WebContentsAdapter::icon())
    property string iconHeld: ""
    function holdIcon() {
        iconHeld = String(icon)
        Engine.iconUnloaded(iconHeld, true)
    }
    onRecentlyAudibleChanged: session.update(pageId, { audible: recentlyAudible })
    // the mute as last reported: Qt 6.11 drops it when it discards the page, without audioMutedChanged
    property bool mutedBefore: false
    onAudioMutedChanged: {
        mutedBefore = audioMuted
        if (!audioMuted)
            siteMuted = false
        session.update(pageId, { muted: audioMuted })
    }
    onLoadingChanged: request => {
        session.update(pageId, { loading: view.loading && !held })
        if (renderProcessPid > 0)
            lastPid = renderProcessPid
        if (request.status === WebEngineView.LoadStartedStatus) {
            // a link to another app starts no page load of its own, nor does a refused one: their asks
            // are on this one
            if (!Asks.external(String(request.url)) && String(request.url) !== rejected) {
                newLoad(String(request.url))
                sections = null
            }
            rejected = ""
            loadingHost = RailRows.split(String(request.url)).host
            loadingUrl = String(request.url)
            loadStartedAt = Date.now()
            replyTimer.restart()
            slow = false
            slowTimer.restart()
            sitePending = true
            attemptWaits = false
            // another load took the https attempt's place
            if (fallback !== "" && PageState.hostOf(String(request.url)) !== PageState.hostOf(fallback))
                endAttempt()
            return
        }
        // a load that replaced no document: one that turned into a download (LoadStopped, isDownload), or one
        // that ended before a document of its own committed (stopped, no reply)
        const kept = keptLoad
        keptLoad = null
        const ownDocument = request.status === WebEngineView.LoadSucceededStatus || request.isErrorPage
        if (kept && (request.isDownload || sitePending && !ownDocument))
            keepLoad(kept)
        slowTimer.stop()
        slow = false
        replyTimer.stop()
        continuing = ""
        // a load that ends without a document of its own leaves the page's zoom as it was
        if (sitePending && ownDocument)
            committed(String(url))
        sitePending = false
        // the load a certificate held is over, answered or not
        if (certificateError) {
            certificateError = null
            if (held)
                failure = Object.assign({}, failure, { held: false })
        }
        if (request.status === WebEngineView.LoadSucceededStatus) {
            visits.visit(String(request.url), title)
            failure = null
            if (visible) {
                probeArticle()
                articleAgain.restart()
                sectionsSoon.restart()
            }
            if (restoreScroll)
                scrollBack(restoreScroll)
            else if (restoreStop && String(url) === restoreStop.url)
                runJavaScript(Recall.restore(restoreStop), WebEngineScript.ApplicationWorld)
        }
        restoreScroll = null
        restoreStop = null
        if (request.status === WebEngineView.LoadSucceededStatus || request.isErrorPage)
            drawn = true
        const loadFailed = request.status === WebEngineView.LoadFailedStatus && !request.isDownload
        if (fallback !== "") {
            const http = fallback
            endAttempt()
            // a stop keeps what shows, and an HTTP status is the site's own page (an empty body commits an
            // empty one). Other failures commit nothing with the error page off (ERR_EMPTY_RESPONSE, measured),
            // so ERR_TOO_MANY_REDIRECTS and the like fall back as a connection does.
            if (!loadFailed || request.errorCode === -3 || request.errorDomain === WebEngineView.HttpStatusCodeDomain)
                return
            // a name that does not resolve, or a computer without a network, fails the same over http: the
            // page says so for the https address, and Try again tries https first again
            const f = failureOf(request)
            if (f && (f.kind === "offline" || f.kind === "name")) {
                failure = Object.assign(f, { committed: false, fallback: http, under: covered() })
                return
            }
            view.url = http
            return
        }
        if (!loadFailed)
            return
        if (backAfterReject && request.errorDomain === WebEngineView.CertificateErrorDomain) {
            backAfterReject = false
            canGoBack ? goBack() : view.closeWanted()
            return
        }
        const f = failureOf(request)
        if (f)
            failure = Object.assign(f, { committed: request.isErrorPage })
        else if (request.errorDomain === WebEngineView.CertificateErrorDomain && failure && failure.kind === "certificate")
            failure = Object.assign({}, failure, { committed: request.isErrorPage })
        else if (request.errorCode !== -3)
            failure = null      // the site's own page (an HTTP status); ERR_ABORTED (a stop) keeps what shows
    }

    // A page moved from another window loads its restored entry and goes back to the scroll its record has, if any,
    // unless the entry brought it back already.
    property var restoreScroll: null        // [x, y]
    function scrollBack(xy) {
        const x = Number(xy[0]) || 0, y = Number(xy[1]) || 0
        runJavaScript("if (Math.abs(scrollX - " + x + ") > 1 || Math.abs(scrollY - " + y + ") > 1) scrollTo(" + x + ", " + y + ")",
                      WebEngineScript.ApplicationWorld)
    }

    // Where you stopped (PLAN.md 3.7, Recall.js): asked of the page when you leave it and before it unloads; `done`
    // gets the record (null at the top of the page, undefined when the page gave no answer). A page loaded afresh
    // (a thread brought back, a closed page reopened, a start) goes back there once it has loaded (`restoreStop`).
    function captureStop(done) {
        const at = String(url)
        runJavaScript(Recall.capture, WebEngineScript.ApplicationWorld, answer => done(Recall.stop(answer, at, Date.now())))
    }
    property var restoreStop: null

    // The page's sections, for the strip under it (PLAN.md 3.19, Recall.sections), read in the browser's script world
    // while it is on screen: once a load has succeeded, when it comes on screen, and 300 ms after its document changes
    // size or address. Main sets `readsSections` for a main window's pages; a private window's read none.
    property bool readsSections: false
    property var sections: null

    // The page's own right-click menu (PLAN.md 3.20 #8, PageMenu.js), which Main draws for its pages; elsewhere (a
    // sign-in popup) the engine's. `at`: where, in the view.
    property bool ownMenu: false
    signal menuWanted(var request, point at)
    onContextMenuRequested: request => {
        if (!ownMenu)
            return;
        request.accepted = true;
        menuWanted(PageMenu.request(request), request.position ?? Qt.point(request.x, request.y));
    }
    function readSections() {
        if (!readsSections || !visible)
            return
        const at = String(url)
        runJavaScript(Recall.sections, WebEngineScript.ApplicationWorld, answer => { if (String(url) === at) sections = Recall.readSections(answer) })
    }
    Timer { id: sectionsSoon; interval: 300; onTriggered: view.readSections() }
    onContentsSizeChanged: if (readsSections && visible) sectionsSoon.restart()

    // The browser's own page for a failure (PLAN.md 3.8 8f-8h, Failures.js), which FailurePage draws over
    // this view: a load that failed or got no reply, a certificate the engine questions, the page's process
    // gone. It stays until a load succeeds. `committed`: the engine's error page is this view's entry (else
    // the page before it is still here, under it); `held`: a certificate error waits on its page's answer.
    property var failure: null
    readonly property bool held: failure !== null && failure.held === true
    // a certificate continued past this page load, for the card's ! and its second line
    readonly property var questioned: failure === null && certificates && /^https:/i.test(String(url)) ? certificates.accepted[PageState.hostOf(String(url))] ?? null : null
    // what a failure that commits nothing covers: the engine's error page of an earlier one, still this
    // view's entry, whose failure shows again when you go back
    function covered() { return failure ? (failure.committed ? failure : failure.under ?? null) : null }
    // the rail row's !: in the error tone for a certificate
    readonly property string failed: failure ? (failure.tone === "error" ? "certificate" : "error") : questioned ? "certificate" : ""
    onFailedChanged: session.update(pageId, { failed: failed })
    property var certificateError: null     // the deferred WebEngineCertificateError the page answers
    property string continuing: ""          // the host a Continue lets through, until its load ends
    property bool backAfterReject: false
    function failureOf(request) {
        const hosts = [];
        for (const u in visits.entries) {
            const h = Failures.bareHost(u);
            if (h && hosts.indexOf(h) < 0)
                hosts.push(h);
        }
        const domains = { [WebEngineView.ConnectionErrorDomain]: "connection", [WebEngineView.DnsErrorDomain]: "dns",
                          [WebEngineView.CertificateErrorDomain]: "certificate", [WebEngineView.HttpErrorDomain]: "http",
                          [WebEngineView.HttpStatusCodeDomain]: "status", [WebEngineView.InternalErrorDomain]: "internal" };
        return Failures.load({ url: String(request.url), at: Date.now(), code: request.errorCode, domain: domains[request.errorDomain] ?? "",
                               name: request.errorString, reachability: Facts.reachability, watching: Facts.watching, hosts: hosts,
                               waited: (Date.now() - loadStartedAt) / 1000 });
    }

    // A certificate the engine questions (PLAN.md 8g): the load waits on the page's answer. A frame's is
    // refused (the frame fails), and so is an https attempt's (it falls back to http).
    onCertificateError: error => {
        const host = PageState.hostOf(String(error.url));
        if (!error.isMainFrame || fallback !== "") {
            error.rejectCertificate();
            return;
        }
        if (continuing === host) {
            error.acceptCertificate();
            return;
        }
        error.defer();
        certificateError = error;
        replyTimer.stop();
        slowTimer.stop();
        slow = false;
        const now = Date.now();
        failure = Object.assign(Failures.certificate(Object.assign({ url: String(error.url), at: now, now: now, type: error.type, overridable: error.overridable },
                                                                   Facts.certificate(error))), { held: true, committed: false, under: covered() });
        session.update(pageId, { loading: false });
    }

    // The failure page's actions (Main.failureAction). Try again: the failed address again (https first if
    // it was typed), or a reload where the engine's error page holds it.
    function retry() {
        const f = failure;
        if (!f)
            return;
        if (f.kind === "unresponsive") {
            endAndReload();
            return;
        }
        if (f.fallback)
            fallBackTo(f.fallback);
        if (f.committed || String(url) === f.url)
            reload();
        else
            url = f.url;
    }
    // A refused Back or Forward goes on to its own entry, not to a new one at the end.
    function continueCertificate() {
        const f = failure;
        if (!f || f.kind !== "certificate" || f.go === "")
            return;
        const host = PageState.hostOf(f.url);
        certificates.accept(host, Object.assign({}, f, { held: false, under: null }));
        continuing = host;
        if (!certificateError) {
            const offset = f.navigation === WebEngineNavigationRequest.BackForwardNavigation ? entryOffset(f.url) : 0;
            if (offset !== 0)
                goBackOrForward(offset);
            else
                url = f.url;
            return;
        }
        const e = certificateError;
        certificateError = null;
        failure = Object.assign({}, f, { held: false });
        e.acceptCertificate();
    }
    // The history entry nearest the current one at `u` (back first on a tie), as an offset; 0 for none.
    function entryOffset(u) {
        const m = history.items;
        let best = 0;
        for (let i = 0; i < m.rowCount(); i++) {
            const at = m.index(i, 0), o = m.data(at, 258);     // WebEngineHistoryModel's OffsetRole
            if (o !== 0 && String(m.data(at, 256)) === u && (best === 0 || Math.abs(o) < Math.abs(best) || Math.abs(o) === Math.abs(best) && o < 0))
                best = o;
        }
        return best;
    }
    // Go back (`button`), or Alt+Left on a failure: the certificate refused, to the page before the one
    // that failed; with nothing before it the button closes the page.
    function leave(button) {
        const f = failure;
        if (certificateError) {
            const e = certificateError;
            certificateError = null;
            backAfterReject = true;
            e.rejectCertificate();
            return;
        }
        if (f && !f.committed && String(url) !== f.url) {
            failure = f.under ?? null;
            return;
        }
        if (canGoBack)
            goBack();
        else if (button)
            view.closeWanted();
    }

    // No reply within 30 s (PLAN.md 8f): the browser stops the load and says so. An https attempt whose https
    // side has not answered (attemptAnswered) falls back to http after 3 s, so a host that takes the connection
    // and never answers costs 3 s. A reply shows as progress past the engine's first 10 % (0 to 70 at the
    // reply, measured). Not while a certificate holds the load.
    property int replyLimit: 30000
    readonly property int attemptLimit: 3000
    property string loadingUrl: ""
    property double loadStartedAt: 0
    Timer {
        id: replyTimer
        interval: view.fallback !== "" && !view.attemptAnswered ? view.attemptLimit : view.replyLimit
        onTriggered: {
            if (!view.loading || view.loadProgress > 10 || view.held)
                return;
            if (view.fallback !== "" && !view.attemptAnswered) {
                const http = view.fallback;
                view.endAttempt();
                view.url = http;
                return;
            }
            view.failure = Object.assign(Failures.load({ url: view.loadingUrl, at: Date.now(), code: 0, waited: view.replyLimit / 1000 }),
                                         { committed: false, under: view.covered() });
            view.stop();
        }
    }

    // The page's process (PLAN.md 8h): its pid while it runs (renderProcessPid reads 0 once it is gone, and
    // Qt does not signal every change), its memory as Main samples it, and when it stopped.
    property real lastPid: 0
    property var sample: null               // { pid, bytes, at, cgroup }
    property var stops: []
    property bool reloadOnShow: false       // stopped while unseen: it loads again when opened
    onRenderProcessPidChanged: if (renderProcessPid > 0) lastPid = renderProcessPid

    // https-first (PLAN.md 3.8): Main calls fallBackTo() before loading a typed address's https attempt;
    // if the attempt fails short of an answer from the site, the plain http address loads instead. The
    // attempt runs without an error page, so a failure commits no history entry (Back never lands on
    // it) and the old page stays on screen.
    property string fallback: ""
    property bool errorPages: true          // errorPageEnabled outside an attempt
    property bool attemptWaits: false       // the attempt's load has not started: Stay at "Leave this page?" stops it
    // The attempt's https side answers: a TLS handshake of the browser's own with its host completed (the engine
    // reports no connection), or the site redirected the load or asked for a sign-in or a client certificate.
    // From then on the attempt waits as long as any load, and no reply is the no-reply page, not an http load
    // that sends the request (and a password) again unencrypted.
    property bool attemptAnswered: false
    property var attemptTls: null           // { host, port } the handshake was asked with
    function fallBackTo(httpUrl) {
        if (fallback === "")
            errorPages = settings.errorPageEnabled
        fallback = httpUrl
        attemptWaits = true
        attemptAnswered = false
        settings.errorPageEnabled = false
        const port = /^http:\/\/(?:[^\/?#@]*@)?[^\/:?#]*:(\d+)/i.exec(httpUrl)
        attemptTls = { host: PageState.hostOf(httpUrl), port: port ? Number(port[1]) : 443 }
        Facts.lookUpTls(attemptTls.host, attemptTls.port)
    }
    function endAttempt() {
        fallback = ""
        attemptWaits = false
        attemptAnswered = false
        settings.errorPageEnabled = errorPages
    }
    function attemptAnswers() {
        if (fallback === "" || attemptAnswered)
            return
        attemptAnswered = true
        if (replyTimer.running)
            replyTimer.restart()
    }
    Connections {
        target: Facts
        function onTlsFound(host, port, tls) {
            if (view.attemptTls && host === view.attemptTls.host && port === view.attemptTls.port && Object.keys(tls).length > 0)
                view.attemptAnswers()
        }
    }

    // Loading (PLAN.md 3.8). `drawn` once the view's first load has made progress, or ended on a page or
    // an error page: until then Main keeps the terminal ground over it. A stop or a failed https attempt
    // also reports 100 %, with nothing drawn. A load still under 30 % after 8 s names the host it waits for.
    property bool drawn: false
    onLoadProgressChanged: {
        if (loadProgress > 0 && loadProgress < 100)
            drawn = true
        // a load that replaced a pending one reports 10 before anything commits (measured); 100 can come
        // before a load ends with no document, which the end handles
        if (loadProgress > 10 && loadProgress < 100 && sitePending)
            committed(loadingUrl)
    }
    // The load's own document committed: it takes its site's zoom and sound, and what the page before it
    // captured ended with that page.
    function committed(u) {
        applySite(u)
        endUse()
    }
    property string loadingHost: ""
    property bool slow: false
    readonly property string waitingFor: slow && loading && loadProgress < 30 ? loadingHost : ""
    Timer { id: slowTimer; interval: 8000; onTriggered: view.slow = true }

    // "Passwords typed here are sent unencrypted" (PLAN.md 3.8 8b): while this page is on screen over
    // plain http with the keys (not while you type in the rail or another app), whether a password field
    // has the focus (same-origin frames and shadow roots included), asked from the browser's script world,
    // where the page can neither see nor fake the answer.
    property bool passwordFocused: false
    Timer {
        interval: 250
        repeat: true
        running: view.visible && view.activeFocus && PageState.insecure(String(view.url))
        onRunningChanged: if (!running) view.passwordFocused = false
        onTriggered: view.runJavaScript("(() => { let d = document, e = d.activeElement; for (;;) {"
            + " if (e && e.shadowRoot && e.shadowRoot.activeElement) e = e.shadowRoot.activeElement;"
            + " else if (e && /^I?FRAME$/.test(e.tagName)) { try { d = e.contentDocument } catch (x) { return false } e = d && d.activeElement }"
            + " else break }"
            + " return !!e && e.tagName === 'INPUT' && e.type === 'password' })()",
            WebEngineScript.ApplicationWorld, focused => view.passwordFocused = focused === true)
    }

    // Passwords (PLAN.md 7, Logins.js): the browser's script world tells, over this channel, which only that world can
    // reach, when a login field of the page takes or leaves the focus and when a login form is sent. `loginField`:
    // { origin, role } while one has the focus; a field left for the next one (user name to password) does not clear it
    // in between. `loginFocused`: while the page also has the keys, as the password note.
    webChannel: loginChannel
    webChannelWorld: WebEngineScript.ApplicationWorld
    WebChannel {
        id: loginChannel
        registeredObjects: [loginSink, swipeSink]
    }
    // A sideways touchpad swipe (Swipe.js, Main's swipe cue): how far it went where nothing under the pointer scrolls
    // that way, from the fingers going down (PageItem.touchpadGesture) to 40 ms after they lift, for the page's last
    // steps on their way (Glide's momentum after the lift counts no further); then swipeEnded, and Main goes back or forward with it. Qt WebEngine has no touchpadGesture.
    property real swipeX: 0
    property bool swipeFingers: false
    signal swipeEnded()
    QtObject {
        id: swipeSink
        WebChannel.id: "swipe"
        function free(dx) {
            if (view.swipeFingers || swipeLate.running)
                view.swipeX += dx;
        }
    }
    Connections {
        target: view
        ignoreUnknownSignals: true
        function onZoomGesture(steps) { view.zoomWanted(steps) }
        // The page's process stopped answering (CEF's page only, 2026-10-24): its failure page offers Wait and Reload,
        // and goes when the process answers again, waits, or is ended
        function onUnresponsiveChanged() {
            if (view.unresponsive)
                view.failure = Object.assign(Failures.unresponsive({ url: String(view.url), at: Date.now() }), { committed: true });
            else if (view.failure && view.failure.kind === "unresponsive")
                view.failure = null;
        }
        function onTouchpadGesture(down) {
            if (down) {
                // fingers back within the late steps' wait: the swipe before them still counts
                if (swipeLate.running) {
                    swipeLate.stop();
                    view.swipeEnded();
                }
                view.swipeX = 0;
            }
            view.swipeFingers = down;
            if (!down)
                swipeLate.restart();
        }
    }
    Timer { id: swipeLate; interval: 40; onTriggered: view.swipeEnded() }
    QtObject {
        id: loginSink
        WebChannel.id: "logins"
        function field(text) {
            const m = Logins.parse(text, Asks.originOf(String(view.url)));
            if (!m)
                return;
            if (m.role === "code") {
                loginBlur.stop();
                view.loginField = null;
                view.codeField = true;
            } else if (m.role) {
                loginBlur.stop();
                view.codeField = false;
                view.loginField = { origin: m.origin, role: m.role };
            } else {
                loginBlur.restart();
            }
        }
        function submitted(text) {
            view.armedLogin = null;
            view.offerSave(Logins.parse(text, Asks.originOf(String(view.url))));
        }
        function armed(text) {
            const m = Logins.parse(text, Asks.originOf(String(view.url)));
            view.armedLogin = m && m.password ? { login: m, at: Date.now() } : null;
            // the form's load can be asked for before this message comes (CEF hands the navigation over at once)
            if (view.armedLogin && Date.now() - view.formSentAt < 2000)
                view.takeArmed();
        }
    }
    property var loginField: null
    readonly property bool loginFocused: loginField !== null && activeFocus
    // your Enter or click on a login form (Logins.js armed): its login, for 5 s; a form submission that starts a load of
    // the page in that time offers it (onNavigationRequested), as the submitted message would when it is not lost, in
    // whichever order the two come
    property var armedLogin: null
    property double formSentAt: 0
    function takeArmed() {
        const sent = armedLogin.login;
        armedLogin = null;
        formSentAt = 0;
        offerSave(sent);
    }
    // a one-time code's field has the focus (Logins.js role "code"): the notch's sign-in offers a code from your phone
    property bool codeField: false
    Timer { id: loginBlur; interval: 150; onTriggered: { view.loginField = null; view.codeField = false } }
    // A login sent: "Save password for <host>?" in the card, unless the keyring holds it already with this password (a
    // locked keyring cannot say, and is not asked to unlock for it) or no keyring answers. A private window sends none.
    function offerSave(m) {
        if (!m || !m.password || profile.offTheRecord || Passwords.state !== "ready")
            return;
        const offer = () => {
            asks = asks.filter(a => a.kind !== "password");
            enqueue({ kind: "password", origin: m.origin, host: RailRows.split(m.origin).host, user: m.user || "", password: m.password });
        };
        const have = Logins.saved(Passwords.entries, m.origin, m.user || "");
        if (!have) {
            offer();
            return;
        }
        Passwords.secret(have.id, true, secret => { if (secret !== m.password) offer() });
    }
    // Fill: the saved login `entry` into the page's login form, while the page is at its origin; `done(failure)`, "" when
    // it filled
    function fillLogin(entry, done) {
        if (entry.origin !== Asks.originOf(String(url))) {
            done("form");
            return;
        }
        Passwords.secret(entry.id, false, (secret, failure) => {
            if (secret === undefined) {
                done(failure);
                return;
            }
            runJavaScript(Logins.fill(entry.origin, entry.user, secret), WebEngineScript.ApplicationWorld, filled => done(filled === true ? "" : "form"));
        });
    }

    // Reader view (PLAN.md 3.9, Reader.js): whether the page has an article (`article`: "yes", "none" or "" before it was
    // asked: after a load of the page on screen, and 2 s later if none for what the page adds by script; when a page comes
    // on screen; when the site panel or Ctrl+Alt+R asks), and whether it shows it in place of its body (`reader`, at the
    // address `readerAt`). The page's own load or address ends it; a reload or a link out takes the page's body with its
    // document. `articleAt`: the address (without its #) `article` was found for; the page's own pushState to another is
    // asked again, as a load is.
    property string article: ""
    property string articleAt: ""
    property bool reader: false
    property string readerAt: ""
    Timer { id: articleAgain; interval: 2000; onTriggered: if (view.article === "none") view.probeArticle() }
    onVisibleChanged: {
        if (visible && article === "" && !loading && String(url) !== "")
            probeArticle()
        if (visible && readsSections)
            sectionsSoon.restart()
    }
    function probeArticle() {
        const at = String(url)
        runJavaScript(Readability.readerable + "\n" + Reader.probe, WebEngineScript.ApplicationWorld, answer => {
            if (String(view.url) === at && (answer === "yes" || answer === "none")) {
                view.article = answer
                view.articleAt = at.split("#")[0]
            }
        })
    }
    // Into the article or back to the page. `theme`: Reader.theme's colours and faces (Main's, from Theme); `done(state)`:
    // "on", "off", or "none" when the page has no article.
    function toggleReader(theme, done) {
        const at = String(url)
        if (reader) {
            reader = false
            runJavaScript(Reader.leave, WebEngineScript.ApplicationWorld, () => done("off"))
            return
        }
        runJavaScript(Readability.script + "\n" + Reader.enter(theme), WebEngineScript.ApplicationWorld, answer => {
            if (String(view.url) !== at)
                return
            view.article = answer === "on" ? "yes" : "none"
            view.reader = answer === "on"
            view.readerAt = at.split("#")[0]
            view.articleAt = view.readerAt
            done(answer === "on" ? "on" : "none")
        })
    }
    onPrintRequested: view.printWanted()

    // Per site (PLAN.md 3.9): its zoom, and its sound when blocked. Qt keeps a view's zoom and mute across
    // navigations, to other sites too (probed), so each new document takes its own site's at its commit (the
    // reply's progress, for the address loading then: `url` can still read the page before it), and the page
    // before it keeps its zoom while the load waits.
    property bool sitePending: false
    function applySite(u) {
        sitePending = false
        const origin = Asks.originOf(u)
        zoomFactor = sites.zoom(origin)
        muteForSite(sites.choice(origin, "sound") === "block")
    }
    // Sound Blocked mutes the page, and a site without it unmutes what it muted; a mute of yours stays.
    property bool siteMuted: false
    function muteForSite(block) {
        if (block && !audioMuted) {
            audioMuted = true
            siteMuted = true
        } else if (!block && siteMuted) {
            audioMuted = false
        }
    }

    // The site panel's Allowed (Adblock.setAllowed) gets no element hiding or scriptlets: cosmetic() is empty.
    // The last page's are removed one by one, never with userScripts.clear(): Qt 6.11's clearAllScripts drops
    // the view's script list but keeps its observer, which reads the missing list at the next cross-site
    // navigation and crashes (UserResourceControllerHost::WebContentsObserverHelper::RenderFrameHostChanged).
    function applyCosmetics(url) {
        for (const name of ["adblock-scriptlets", "adblock-hide"])
            for (const script of userScripts.find(name))
                userScripts.remove(script)
        if (!adblock || !adblock.ready)
            return
        const c = adblock.cosmetic(String(url), profile)
        if (c.script) {
            // only frames of this host run them: not other hosts' embeds (video, payment, sign-in), nor
            // the old page's new frames after a navigation that never commits (a download, a 204)
            const host = ((/^[a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?([^\/:?#]+)/i.exec(String(url)) ?? [])[1] ?? "").toLowerCase()
            const s = WebEngine.script()
            s.name = "adblock-scriptlets"
            s.sourceCode = "if (location.hostname === " + JSON.stringify(host) + ") {\n" + c.script + "\n}"
            s.injectionPoint = WebEngineScript.DocumentCreation
            s.worldId = WebEngineScript.MainWorld
            s.runsOnSubFrames = true
            userScripts.insert(s)
        }
        if (c.css) {
            const s = WebEngine.script()
            s.name = "adblock-hide"
            s.sourceCode = "(() => { const s = document.createElement('style'); s.textContent = "
                + JSON.stringify(c.css) + "; (document.head || document.documentElement).appendChild(s); })()"
            s.injectionPoint = WebEngineScript.DocumentReady
            s.worldId = WebEngineScript.ApplicationWorld
            s.runsOnSubFrames = true
            userScripts.insert(s)
        }
    }

    // Asks (PLAN.md 3.8, Asks.js): this page's queue in arrival order, the one the card shows, and the
    // answers given for this page load ("origin type" -> "allow" | "deny"), which Allow once and Deny
    // last for. A new load starts them afresh and drops the old document's asks.
    property var asks: []
    readonly property var ask: Asks.shown(asks)
    readonly property int askCount: Asks.order(asks).length
    readonly property var quietAsk: asks.find(a => a.quiet) ?? null
    property var thisLoad: ({})
    property int askSerial: 0
    property var inUse: []                  // allowed this load and using hardware: the card's glyphs
    property var answered: []               // permission requests granted or denied this load
    property var pendingApps: []            // links waiting for Apps.lookUp: { url, origin, scheme }
    onAskChanged: session.update(pageId, { needsYou: ask !== null, asking: Asks.word(ask) })

    // Pages and memory's Unload or the memory net found a field edited in this document (Main.unloadPage): it stays live,
    // and its row says so
    property bool editedKept: false

    // `to`: the address the load is for.
    function newLoad(to) {
        // the engine keeps a decision for the view across a reload or a same-origin load; the next load asks
        // afresh. A reset also ends what the grant was capturing (measured), and Qt says nothing between the
        // response and the commit, so it cannot wait to see whether the load turns into a download. A load of
        // another origin keeps no grant once it commits (measured), so it resets nothing: the page captures on,
        // with its glyphs, until that load's document replaces it (committed()), and a load that ends without
        // one (a file, a stop) gives the grants back.
        const reset = Asks.originOf(to) === Asks.originOf(String(url));
        if (reset) {
            for (const r of answered)
                r.reset();
            endUse();
        }
        // "Save password for <host>?" lasts through the load its form started and what the site does next by itself
        // (a redirect, a script's location), and goes with a load of yours: a link, an address, back or a reload
        const T = WebEngineNavigationRequest;
        const keepsLogin = navigationType === T.FormSubmittedNavigation || navigationType === T.OtherNavigation;
        const kept = a => a.kind === "leave" || a.kind === "password" && keepsLogin;
        keptLoad = { thisLoad: thisLoad, asks: asks.filter(a => !kept(a)), pendingApps: pendingApps, pickedFiles: pickedFiles,
                     dialogs: dialogs, dialogsBlocked: dialogsBlocked, blockedPopups: blockedPopups, answered: reset ? [] : answered,
                     reader: reader, article: article, articleAt: articleAt, editedKept: editedKept };
        // a new document has no article found yet, and shows its own body
        reader = false;
        article = "";
        articleAt = "";
        editedKept = false;
        answered = [];
        thisLoad = {};
        pendingApps = [];
        asks = asks.filter(kept);
        loginBlur.stop();
        loginField = null;
        codeField = false;
        // Chromium drops the old document's dialog and file chooser with it
        dialog = null;
        dialogs = 0;
        dialogsBlocked = false;
        blockedPopups = 0;
        dropPick();
        pickedFiles = {};
    }
    // What newLoad set aside, until the load ends. One that replaced no document left its page as it was:
    // that page load's asks (still waiting in Chromium) and answers come back; what the reset ended is
    // asked for again, and answered from them.
    property var keptLoad: null
    function keepLoad(k) {
        thisLoad = Object.assign({}, k.thisLoad, thisLoad);
        answered = k.answered.concat(answered);
        asks = k.asks.concat(asks);
        pendingApps = k.pendingApps.concat(pendingApps);
        pickedFiles = k.pickedFiles;
        dialogs = k.dialogs;
        dialogsBlocked = k.dialogsBlocked;
        blockedPopups = k.blockedPopups;
        reader = k.reader;
        article = k.article;
        articleAt = k.articleAt;
        editedKept = k.editedKept;
    }
    // a page without its renderer has nothing left waiting on an answer. Discarding a page (unloading it,
    // or clearing its site's data) ends its process too, as a normal exit: that is no stop.
    onRenderProcessTerminated: (status, code) => {
        if (lifecycleState === WebEngineView.LifecycleState.Discarded)
            return;
        asks = [];
        dialog = null;
        dropPick();
        replyTimer.stop();
        const now = Date.now();
        stops = stops.filter(t => now - t < 600000).concat([now]);
        session.update(pageId, { loading: false });
        view.processStopped(status === WebEngineView.KilledTerminationStatus ? "killed" : status === WebEngineView.CrashedTerminationStatus ? "crashed"
                            : status === WebEngineView.AbnormalTerminationStatus ? "abnormal" : "normal", code);
    }
    onLifecycleStateChanged: {
        const unloaded = lifecycleState === WebEngineView.LifecycleState.Discarded
        if (unloaded && iconHeld === "")
            holdIcon()
        else if (!unloaded && iconHeld !== "") {
            Engine.iconUnloaded(iconHeld, false)
            iconHeld = ""
        }
        if (!unloaded)
            return
        asks = []
        if (mutedBefore && !audioMuted)
            audioMuted = true
    }

    function enqueue(a) {
        a.id = ++askSerial;
        asks = Asks.add(asks, a);
        if (!a.quiet)
            view.asked(a);
    }
    function remove(a) { asks = asks.filter(x => x !== a) }
    function replace(a, b) { asks = asks.map(x => x === a ? b : x) }
    // the bell at the card's right: the quiet ask comes out
    function unquiet() {
        const a = quietAsk;
        if (a)
            replace(a, Object.assign({}, a, { quiet: false }));
    }
    function use(types) {
        const more = types.filter(t => Asks.glyphs([t]).length > 0 && inUse.indexOf(t) < 0);
        if (more.length === 0)
            return;
        inUse = inUse.concat(more);
        session.update(pageId, { capturing: Asks.glyphs(inUse)[0] });
    }
    function endUse() {
        if (inUse.length === 0)
            return;
        inUse = [];
        session.update(pageId, { capturing: "" });
    }

    // What an answer does: AskSection's choice (Asks.view) and its data ({ picked, <field>: text }).
    function answer(a, choice, data) {
        if (asks.indexOf(a) < 0)
            return;
        const d = data ?? {};
        switch (a.kind) {
        case "permission":
            decide(a.origin, a.types, choice === "allow" ? "allow" : "deny");
            return;
        case "signin":
        case "proxy":
            if (choice === "signin")
                a.request.dialogAccept(d.user ?? "", d.password ?? "");
            else
                a.request.dialogReject();
            resumeLoad();
            break;
        case "certificate":
            if (choice === "send" && (d.picked ?? 0) < a.options.length - 1)
                a.selection.select(d.picked ?? 0);
            else
                a.selection.selectNone();
            resumeLoad();
            break;
        case "leave":
            if (choice === "leave") {
                a.request.dialogAccept();
            } else {
                a.request.dialogReject();
                // the load it asked for never starts, and a typed address's https attempt goes with it
                if (attemptWaits)
                    endAttempt();
                if (closing)
                    view.closeKept();
                closing = false;
            }
            break;
        case "passkey":
            // the request's next state replaces the ask, or ends it
            if (choice === "pin")
                a.request.setPin(d.pin ?? "");
            else if (choice === "account")
                a.request.setSelectedAccount(a.options[d.picked ?? 0]);
            else if (choice === "retry")
                a.request.retry();
            else {
                a.request.cancel();
                break;
            }
            return;
        case "screen": {
            if (choice !== "share") {
                a.media.cancel();
                break;
            }
            const i = d.picked ?? 0, screens = a.media.screensModel, windows = a.media.windowsModel;
            if (i < a.screens || a.picker)
                a.media.selectScreen(screens.index(a.picker ? 0 : i, 0));
            else
                a.media.selectWindow(windows.index(i - a.screens, 0));
            // chosen here, so the capture permission that may follow needs no second ask
            thisLoad[a.origin + " screen"] = "allow";
            use(["screen"]);
            break;
        }
        case "external":
            if (choice === "open")
                Apps.open(a.url);
            else if (choice === "copy")
                view.copyRequested(a.url);
            else
                thisLoad[a.origin + " app:" + a.scheme] = "deny";
            break;
        case "save":
            if (choice === "save")
                view.saveWanted(a);
            break;
        case "password":
            if (choice === "save")
                Passwords.save(a.origin, a.user, a.password, (ok, failure) => { if (!ok) view.loginFailed(Logins.failed("save", failure)) });
            break;
        }
        remove(a);
    }
    // An answer for this page load settles every waiting permission ask it covers.
    function decide(origin, types, value) {
        for (const t of types)
            thisLoad[origin + " " + t] = value;
        const keep = [];
        for (const a of asks) {
            const p = a.kind === "permission" && a.origin === origin ? Asks.preset(a.types, t => thisLoad[origin + " " + t] ?? "") : "";
            if (p === "") {
                keep.push(a);
                continue;
            }
            for (const r of a.requests)
                settle(r, p);
            if (p === "allow")
                use(a.types);
        }
        asks = keep;
    }

    function settle(r, p) {
        p === "allow" ? r.grant() : r.deny();
        answered = answered.concat([r]);
    }

    function permissionTypes(t) {
        switch (t) {
        case WebEnginePermission.PermissionType.MediaAudioCapture: return ["microphone"];
        case WebEnginePermission.PermissionType.MediaVideoCapture: return ["camera"];
        case WebEnginePermission.PermissionType.MediaAudioVideoCapture: return ["microphone", "camera"];
        case WebEnginePermission.PermissionType.DesktopVideoCapture:
        case WebEnginePermission.PermissionType.DesktopAudioVideoCapture: return ["screen"];
        case WebEnginePermission.PermissionType.MouseLock: return ["pointer"];
        case WebEnginePermission.PermissionType.Notifications: return ["notifications"];
        case WebEnginePermission.PermissionType.Geolocation: return ["location"];
        case WebEnginePermission.PermissionType.ClipboardReadWrite: return ["clipboard"];
        case WebEnginePermission.PermissionType.LocalFontsAccess: return ["fonts"];
        }
        return [];
    }
    onPermissionRequested: permission => {
        const types = permissionTypes(permission.permissionType);
        const origin = Asks.originOf(String(permission.origin));
        if (types.length === 0) {
            permission.deny();
            return;
        }
        sites.noteAsked(origin, types);
        const p = Asks.preset(types, t => thisLoad[origin + " " + t] ?? sites.choice(origin, t));
        if (p !== "") {
            settle(permission, p);
            if (p === "allow")
                use(types);
            return;
        }
        const a = { kind: "permission", origin: origin, host: RailRows.split(origin).host, types: types, requests: [permission],
                    sound: permission.permissionType === WebEnginePermission.PermissionType.DesktopAudioVideoCapture, quiet: false };
        if (types[0] !== "notifications") {
            enqueue(a);
            return;
        }
        // made without a click from you: only the quiet bell (the frame's activation reaches the top frame)
        runJavaScript("navigator.userActivation.isActive", WebEngineScript.ApplicationWorld, active => {
            if (!permission.isValid)
                return;
            a.quiet = active !== true;
            enqueue(a);
        });
    }

    // A sign-in (a 401's load stays at 0 % until answered, measured) or a client certificate holds the
    // load: no reply is due, and nothing is "Waiting for" the host, until it is answered.
    function holdLoad() {
        replyTimer.stop();
        slowTimer.stop();
        slow = false;
    }
    function resumeLoad() {
        if (!loading)
            return;
        replyTimer.restart();
        slowTimer.restart();
    }
    onAuthenticationDialogRequested: request => {
        request.accepted = true;
        holdLoad();
        const proxy = request.type === AuthenticationDialogRequest.AuthenticationTypeProxy;
        const url = String(request.url);
        if (!proxy && Asks.originOf(url) === Asks.originOf(loadingUrl))
            attemptAnswers();
        enqueue({ kind: proxy ? "proxy" : "signin", origin: Asks.originOf(url), host: proxy ? request.proxyHost : RailRows.split(url).host,
                  secure: !PageState.insecure(url), request: request });
    }

    onSelectClientCertificate: selection => {
        holdLoad();
        const certs = selection.certificates, options = [];
        for (let i = 0; i < certs.length; i++)
            options.push(Asks.certLabel(certs[i].subject, certs[i].issuer, certs[i].expiryDate));
        const origin = Asks.tlsOrigin(String(selection.host));
        if (origin === Asks.originOf(loadingUrl))
            attemptAnswers();
        enqueue({ kind: "certificate", origin: origin, host: RailRows.split(origin).host, options: options.concat(["No certificate"]),
                  selection: selection });
    }

    // Before you leave is the browser's ask. Alert, confirm and prompt are the page's own voice (PLAN.md
    // 8j), which PageDialog draws over this page: { type, message, text (prompt's default), says, block
    // (from the second in a page load, the offer to block the rest), request }. Blocked, the rest of this
    // page load's dialogs return at once, as Cancel.
    property var dialog: null
    property int dialogs: 0
    property bool dialogsBlocked: false
    onJavaScriptDialogRequested: request => {
        request.accepted = true;
        const u = String(url);
        if (request.type === JavaScriptDialogRequest.DialogTypeBeforeUnload) {
            enqueue({ kind: "leave", origin: Asks.originOf(u), host: RailRows.split(u).host, request: request });
            return;
        }
        if (dialogsBlocked) {
            request.dialogReject();
            return;
        }
        dialogs++;
        dialog = { type: request.type === JavaScriptDialogRequest.DialogTypeAlert ? "alert" : request.type === JavaScriptDialogRequest.DialogTypeConfirm ? "confirm" : "prompt",
                   message: request.message, text: request.defaultText, says: PageState.says(u), site: PageState.pageHost(u) || "This page",
                   block: dialogs > 1 ? PageState.blockMore(u) : "", request: request };
    }
    function answerDialog(ok, text) {
        const d = dialog;
        if (!d)
            return;
        dialog = null;
        if (ok)
            d.request.dialogAccept(text ?? "");
        else
            d.request.dialogReject();
    }
    function blockDialogs() {
        dialogsBlocked = true;
        answerDialog(false);
    }

    // A file input (PLAN.md 8l) picks in the shell's Files window (Picker), and the card says "Choosing
    // files in Files" until the pick ends; one that ends with nothing chosen changes nothing on the page.
    // Files takes no rules, so only the input's count is applied here. A save picker is refused.
    // Chromium empties an input when its chooser is cancelled, so a cancelled pick gives the input its last
    // files again, which the page does not see as a change. Inputs are told apart by a number the browser's
    // script world gives the focused element (the input, or the button that opened it).
    property var choosing: null             // { request, mode, input } while Files is open for this page
    property var pickedFiles: ({})          // input -> the paths it last got, this page load
    // The document that asked is going: its pick ends as with nothing chosen (onFinished answers the page), so
    // the next file input can pick, though Files stays open for it and what it hands back goes nowhere.
    function dropPick() {
        if (choosing)
            Picker.cancel();
    }
    onFileDialogRequested: request => {
        request.accepted = true;
        const mode = request.mode === FileDialogRequest.FileModeOpenMultiple ? "multiple" : request.mode === FileDialogRequest.FileModeUploadFolder ? "folder"
                   : request.mode === FileDialogRequest.FileModeSave ? "save" : "one";
        if (mode === "save" || !Picker.pick(PageState.pickLabel(mode, PageState.pageHost(String(url))))) {
            request.dialogReject();
            return;
        }
        const c = { request: request, mode: mode, input: "" };
        choosing = c;
        runJavaScript("(() => { const e = document.activeElement; if (!e) return '';"
            + " if (!e.__browserPick) e.__browserPick = String(window.__browserPicks = (window.__browserPicks || 0) + 1);"
            + " return e.__browserPick })()", WebEngineScript.ApplicationWorld, key => c.input = String(key ?? ""));
    }
    Connections {
        target: view.choosing ? Picker : null
        function onFinished(paths) {
            const c = view.choosing, files = PageState.pickedFor(c.mode, paths), last = c.input ? view.pickedFiles[c.input] : undefined;
            view.choosing = null;
            if (files.length > 0) {
                c.request.dialogAccept(files);
                if (c.input)
                    view.pickedFiles[c.input] = files;
            } else if (last && !c.request.rejectKeepsFiles) {
                // Qt WebEngine's reject empties the input: its last files again (CEF's keeps them)
                c.request.dialogAccept(last);
            } else {
                c.request.dialogReject();
            }
        }
    }

    // Page full screen (PLAN.md 8m): Main follows isFullScreen with the window. A popup's page has none.
    onFullScreenRequested: request => holder ? request.reject() : request.accept()

    // Popups (PLAN.md 8k): the attached popup window this page opened (Main's), and the ones refused this
    // page load because they came without a click from you.
    property var popup: null
    property int blockedPopups: 0
    // Main.retire: the view that opened this one's page with openIn, how many views this one opened that
    // way are still open, whether it is closed and kept only for them, and what goes with it (the popup
    // window it sits in; null for itself).
    property var openedBy: null
    property int opened: 0
    property bool parked: false
    property var holder: null
    // Main.closePage: the page's beforeunload runs first ("Leave this page?" if it has one and had
    // input), then closeAccepted. A page that answers neither within 1 s closes anyway.
    property bool closing: false
    function requestClose() {
        answerDialog(false);
        closing = true;
        closeLimit.restart();
        triggerWebAction(WebEngineView.RequestClose);
    }
    onWindowCloseRequested: {
        if (!closing) {
            view.selfClosed();
            return;
        }
        closing = false;
        closeLimit.stop();
        view.closeAccepted();
    }
    Timer {
        id: closeLimit
        interval: 1000
        onTriggered: if (view.closing && !view.asks.some(a => a.kind === "leave")) { view.closing = false; view.closeAccepted() }
    }

    onWebAuthUxRequested: request => {
        request.stateChanged.connect(() => passkeyChanged(request));
        enqueue(passkey({ kind: "passkey", origin: Asks.originOf(String(url)),
                          host: request.relyingPartyId || RailRows.split(String(url)).host, request: request }));
    }
    function passkey(a) {
        const r = a.request, pin = r.pinRequest, S = WebEngineWebAuthUxRequest.WebAuthUxState;
        const F = WebEngineWebAuthUxRequest.RequestFailureReason, E = WebEngineWebAuthUxRequest.PinEntryError;
        const state = r.state === S.SelectAccount ? "SelectAccount" : r.state === S.CollectPin ? "CollectPin"
                    : r.state === S.RequestFailed ? "RequestFailed" : r.state === S.Cancelled || r.state === S.Completed ? "done" : "touch";
        const failure = ({ [F.Timeout]: "Timeout", [F.KeyNotRegistered]: "KeyNotRegistered", [F.KeyAlreadyRegistered]: "KeyAlreadyRegistered",
                           [F.SoftPinBlock]: "SoftPinBlock", [F.HardPinBlock]: "HardPinBlock", [F.UserConsentDenied]: "UserConsentDenied" })[r.requestFailureReason] ?? "";
        const pinError = ({ [E.WrongPin]: "WrongPin", [E.TooShort]: "TooShort", [E.InvalidCharacters]: "InvalidCharacters",
                            [E.SameAsCurrentPin]: "SameAsCurrentPin" })[pin.error] ?? "";
        return Object.assign({}, a, { state: state, options: r.userNames, failure: failure, pinError: pinError, attempts: pin.remainingAttempts,
                                      minPin: pin.minPinLength, pinReason: pin.reason === WebEngineWebAuthUxRequest.PinEntryReason.Challenge ? "Challenge" : "Set" });
    }
    function passkeyChanged(request) {
        const a = asks.find(x => x.request === request);
        if (!a)
            return;
        const b = passkey(a);
        if (b.state === "done")
            remove(a);
        else
            replace(a, b);
    }

    // Screen share (desktopMediaRequested): the screens and windows Chromium lists, which fill in as it
    // finds them. On Wayland a single screen and no windows stand for the portal's own picker.
    onDesktopMediaRequested: request => {
        const origin = Asks.originOf(String(url));
        // the site panel's lasting Block refuses it with no picker, as onPermissionRequested refuses the rest
        if (sites.choice(origin, "screen") === "block") {
            request.cancel();
            return;
        }
        enqueue({ kind: "screen", origin: origin, host: RailRows.split(String(url)).host, media: request, options: [], screens: 0 });
        relabel();
    }
    readonly property var mediaAsk: asks.find(a => a.kind === "screen") ?? null
    function relabel() {
        const a = mediaAsk;
        if (!a)
            return;
        const s = a.media.screensModel, w = a.media.windowsModel, options = [];
        for (let i = 0; i < s.rowCount(); i++)
            options.push("Entire screen · " + s.data(s.index(i, 0), 0));
        for (let i = 0; i < w.rowCount(); i++)
            options.push("Window · " + w.data(w.index(i, 0), 0));
        replace(a, Object.assign({}, a, { options: options, screens: s.rowCount(),
                                          picker: Qt.platform.pluginName === "wayland" && s.rowCount() === 1 && w.rowCount() === 0 }));
    }
    Connections {
        target: view.mediaAsk ? view.mediaAsk.media.screensModel : null
        function onRowsInserted() { view.relabel() }
        function onRowsRemoved() { view.relabel() }
        function onModelReset() { view.relabel() }
        function onDataChanged() { view.relabel() }
    }
    Connections {
        target: view.mediaAsk ? view.mediaAsk.media.windowsModel : null
        function onRowsInserted() { view.relabel() }
        function onRowsRemoved() { view.relabel() }
        function onModelReset() { view.relabel() }
        function onDataChanged() { view.relabel() }
    }

    // A link to another app's scheme: a lasting choice opens or refuses it at once, else the card asks
    // once the default app is known.
    function askExternal(url) {
        const origin = Asks.originOf(String(view.url)), scheme = Asks.scheme(url);
        sites.noteAsked(origin, ["app:" + scheme]);
        const p = thisLoad[origin + " app:" + scheme] ?? sites.choice(origin, "app:" + scheme);
        if (p === "allow")
            Apps.open(url);
        if (p !== "")
            return;
        pendingApps = pendingApps.concat([{ url: url, origin: origin, scheme: scheme }]);
        Apps.lookUp(scheme);
    }
    Connections {
        target: Apps
        function onFound(scheme, name) {
            const ready = view.pendingApps.filter(p => p.scheme === scheme);
            if (ready.length === 0)
                return;
            view.pendingApps = view.pendingApps.filter(p => p.scheme !== scheme);
            for (const p of ready)
                view.enqueue({ kind: "external", origin: p.origin, host: RailRows.split(String(view.url)).host, url: p.url, scheme: scheme, app: name });
        }
    }
}
