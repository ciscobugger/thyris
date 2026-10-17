import QtQuick
import QtQml.Models
import QtWebChannel
import Browser.Cef

// Stands where Qt WebEngine's WebEngineView stands in Opsis's QML while both engines build from one tree
// (book4-edge/opsis-cef-port-plan.md): `import QtWebEngine` finds this folder before Qt's module (PageItem::registerQml),
// so the QML is the same file for both engines. The page is PageItem's. What PageItem does not do yet is declared
// below so the QML loads, and does nothing: each moves into PageItem with its slice and goes from here.
// The enums are Qt 6.11's, numbers and all (Lifecycle.js and Downloads.js count on them).
PageItem {
    enum ErrorDomain { NoErrorDomain = 0, InternalErrorDomain = 1, ConnectionErrorDomain = 2, CertificateErrorDomain = 3,
        HttpErrorDomain = 4, FtpErrorDomain = 5, DnsErrorDomain = 6, HttpStatusCodeDomain = 7 }
    enum Feature { MediaAudioCapture = 0, MediaVideoCapture = 1, MediaAudioVideoCapture = 2, Geolocation = 3,
        DesktopVideoCapture = 4, DesktopAudioVideoCapture = 5, Notifications = 6, ClipboardReadWrite = 7,
        LocalFontsAccess = 8 }
    enum FindFlags { FindBackward = 1, FindCaseSensitively = 2 }
    enum JavaScriptConsoleMessageLevel { InfoMessageLevel = 0, WarningMessageLevel = 1, ErrorMessageLevel = 2 }
    enum LifecycleState { Active = 0, Frozen = 1, Discarded = 2 }
    enum LoadStatus { LoadStartedStatus = 0, LoadStoppedStatus = 1, LoadSucceededStatus = 2, LoadFailedStatus = 3 }
    enum NavigationRequestAction { AcceptRequest = 0, IgnoreRequest = 255 }
    enum NavigationType { LinkClickedNavigation = 0, TypedNavigation = 1, FormSubmittedNavigation = 2,
        BackForwardNavigation = 3, ReloadNavigation = 4, OtherNavigation = 5, RedirectNavigation = 6 }
    enum NewViewDestination { NewViewInWindow = 0, NewViewInTab = 1, NewViewInDialog = 2, NewViewInBackgroundTab = 3 }
    enum PrintedPageOrientation { Portrait = 0, Landscape = 1 }
    enum PrintedPageSizeId { AnsiA = 0, Letter = 0, Legal = 1, Executive = 2, A0 = 3, A1 = 4, A2 = 5, A3 = 6, A4 = 7,
        A5 = 8, A6 = 9, A7 = 10, A8 = 11, A9 = 12, A10 = 13, B0 = 14, B1 = 15, B2 = 16, B3 = 17, B4 = 18, B5 = 19, B6 = 20,
        B7 = 21, B8 = 22, B9 = 23, B10 = 24, C5E = 25, EnvelopeC5 = 25, Comm10E = 26, Envelope10 = 26, DLE = 27,
        EnvelopeDL = 27, Folio = 28, AnsiB = 29, Ledger = 29, Tabloid = 30, Custom = 31, A3Extra = 32, A4Extra = 33,
        A4Plus = 34, A4Small = 35, A5Extra = 36, B5Extra = 37, JisB0 = 38, JisB1 = 39, JisB2 = 40, JisB3 = 41, JisB4 = 42,
        JisB5 = 43, JisB6 = 44, JisB7 = 45, JisB8 = 46, JisB9 = 47, JisB10 = 48, AnsiC = 49, AnsiD = 50, AnsiE = 51,
        LegalExtra = 52, LetterExtra = 53, LetterPlus = 54, LetterSmall = 55, TabloidExtra = 56, ArchA = 57, ArchB = 58,
        ArchC = 59, ArchD = 60, ArchE = 61, Imperial7x9 = 62, Imperial8x10 = 63, Imperial9x11 = 64, Imperial9x12 = 65,
        Imperial10x11 = 66, Imperial10x13 = 67, Imperial10x14 = 68, Imperial12x11 = 69, Imperial15x11 = 70,
        ExecutiveStandard = 71, Note = 72, Quarto = 73, Statement = 74, SuperA = 75, SuperB = 76, Postcard = 77,
        DoublePostcard = 78, Prc16K = 79, Prc32K = 80, Prc32KBig = 81, FanFoldUS = 82, FanFoldGerman = 83,
        FanFoldGermanLegal = 84, EnvelopeB4 = 85, EnvelopeB5 = 86, EnvelopeB6 = 87, EnvelopeC0 = 88, EnvelopeC1 = 89,
        EnvelopeC2 = 90, EnvelopeC3 = 91, EnvelopeC4 = 92, EnvelopeC6 = 93, EnvelopeC65 = 94, EnvelopeC7 = 95,
        Envelope9 = 96, Envelope11 = 97, Envelope12 = 98, Envelope14 = 99, EnvelopeMonarch = 100, EnvelopePersonal = 101,
        EnvelopeChou3 = 102, EnvelopeChou4 = 103, EnvelopeInvite = 104, EnvelopeItalian = 105, EnvelopeKaku2 = 106,
        EnvelopeKaku3 = 107, EnvelopePrc1 = 108, EnvelopePrc2 = 109, EnvelopePrc3 = 110, EnvelopePrc4 = 111,
        EnvelopePrc5 = 112, EnvelopePrc6 = 113, EnvelopePrc7 = 114, EnvelopePrc8 = 115, EnvelopePrc9 = 116,
        EnvelopePrc10 = 117, EnvelopeYou4 = 118, LastPageSize = 118 }
    enum RenderProcessTerminationStatus { NormalTerminationStatus = 0, AbnormalTerminationStatus = 1,
        CrashedTerminationStatus = 2, KilledTerminationStatus = 3 }
    enum WebAction { NoWebAction = -1, Back = 0, Forward = 1, Stop = 2, Reload = 3, Cut = 4, Copy = 5, Paste = 6, Undo = 7,
        Redo = 8, SelectAll = 9, ReloadAndBypassCache = 10, PasteAndMatchStyle = 11, OpenLinkInThisWindow = 12,
        OpenLinkInNewWindow = 13, OpenLinkInNewTab = 14, CopyLinkToClipboard = 15, DownloadLinkToDisk = 16,
        CopyImageToClipboard = 17, CopyImageUrlToClipboard = 18, DownloadImageToDisk = 19, CopyMediaUrlToClipboard = 20,
        ToggleMediaControls = 21, ToggleMediaLoop = 22, ToggleMediaPlayPause = 23, ToggleMediaMute = 24,
        DownloadMediaToDisk = 25, InspectElement = 26, ExitFullScreen = 27, RequestClose = 28, Unselect = 29,
        SavePage = 30, OpenLinkInNewBackgroundTab = 31, ViewSource = 32, ToggleBold = 33, ToggleItalic = 34,
        ToggleUnderline = 35, ToggleStrikethrough = 36, AlignLeft = 37, AlignCenter = 38, AlignRight = 39,
        AlignJustified = 40, Indent = 41, Outdent = 42, InsertOrderedList = 43, InsertUnorderedList = 44,
        ChangeTextDirectionLTR = 45, ChangeTextDirectionRTL = 46, WebActionCount = 47 }

    // ---- not PageItem's yet: kept as set, nothing done with them ----
    readonly property WebEngineSettings settings: WebEngineSettings {}      // slice 3
    property int webChannelWorld: 0                         // always Opsis's world on CEF

    property int recommendedState: 0
    property bool audioMuted: false                         // slice 2
    property bool recentlyAudible: false

    // Qt's error pages switch (BrowserView turns it off for an https attempt, so the attempt leaves no history entry)
    Connections {
        target: settings
        function onErrorPageEnabledChanged() { setErrorPages(settings.errorPageEnabled) }
    }
    signal selectClientCertificate(var selection)
    signal desktopMediaRequested(var request)
    // A screen share (PageItem.desktopCaptureRequested) as Qt's desktop media request. Chromium lists no screens or
    // windows of its own here: on Wayland the portal's picker chooses once the share is granted, so the request holds one
    // stand-in screen there (BrowserView reads one screen and no windows as the portal's picker) and none elsewhere
    // (offscreen, the checks: nothing found, only Cancel). Choosing a screen grants it; cancel() refuses it.
    readonly property Component desktopMediaComponent: Component {
        QtObject {
            property var permission
            readonly property ListModel screensModel: ListModel {}
            readonly property ListModel windowsModel: ListModel {}
            function selectScreen(index) { permission.grant(); destroy(5000) }
            function selectWindow(index) { permission.grant(); destroy(5000) }
            function cancel() { permission.deny(); destroy(5000) }
        }
    }
    onDesktopCaptureRequested: permission => {
        const request = desktopMediaComponent.createObject(this, { permission: permission });
        if (Qt.platform.pluginName === "wayland")
            request.screensModel.append({ display: "portal" });
        desktopMediaRequested(request);
    }
    signal webAuthUxRequested(var request)
    // Security keys: a request's steps from the engine (PageItem.webAuthnStep) as Qt's WebEngineWebAuthUxRequest; the
    // first asks (webAuthUxRequested), the rest change it, "end" lets it go
    property var webAuthnRequests: ({})
    readonly property Component webAuthnRequestComponent: Component { WebEngineWebAuthUxRequest {} }
    onWebAuthnStep: (request, step) => {
        let r = webAuthnRequests[request];
        const fresh = !r;
        if (fresh) {
            if (step.state === "end" || step.state === "done")
                return;
            r = webAuthnRequestComponent.createObject(this, { page: this, request: request });
            webAuthnRequests[request] = r;
        }
        r.take(step);
        if (fresh)
            webAuthUxRequested(r);
        if (step.state === "end") {
            delete webAuthnRequests[request];
            r.destroy(1000);
        }
    }

    // The page's side of a WebChannel, as Opsis uses it: its scripts call methods of the channel's objects (QWebChannel's
    // message type 6, invoke), which arrive here (PageItem.webChannelMessage); nothing goes back to the page.
    property var webChannel: null
    onWebChannelMessage: message => {
        let m = null;
        try { m = JSON.parse(message); } catch (e) { return; }
        if (!webChannel || !m || m.type !== 6)
            return;
        for (const o of webChannel.registeredObjects)
            if (o.WebChannel.id === m.object && typeof o[m.method] === "function") {
                o[m.method](...(m.args ?? []));
                return;
            }
    }

    function save(path, format) {}
}
