import QtQuick
import "Asks.js" as Asks

// Shot mode only: takes a WebEngineView's place (the properties Main and the rail read) and paints a
// plain light page, so shots show real contrast against the chrome. Its colours are page content,
// not the browser's, so they are not Theme tokens.
Rectangle {
    id: page

    property string pageId
    property var profile
    property var session
    property url url
    readonly property var entry: { session.revision; return session.pages[pageId] ?? null }
    property string title: entry ? entry.title : ""
    property url icon: entry ? (Engine.iconRevision, Engine.keptIcon(String(entry.icon))) : ""
    property bool loading: false
    property int loadProgress: 100
    property bool canGoBack: true
    property bool canGoForward: false
    property int lifecycleState: 0
    property int recommendedState: 0
    property bool audioMuted: false
    // loading and security (PLAN.md 3.8), set by the shots
    property bool drawn: true
    property string waitingFor: ""
    property bool passwordFocused: false
    // passwords (PLAN.md 7), set by the shots: a login field with the page's focus
    property var loginField: null
    property bool loginFocused: false
    signal loginFailed(string text)
    function fillLogin() {}
    // asks (PLAN.md 3.8), queued by the shots as BrowserView queues them
    property var asks: []
    readonly property var ask: Asks.shown(asks)
    readonly property int askCount: Asks.order(asks).length
    readonly property var quietAsk: asks.find(a => a.quiet) ?? null
    property var inUse: []
    // Add to Thyris (BrowserView): set by the shots on a store page
    property string storeItem: ""
    readonly property bool extensionAsking: asks.some(a => a.kind === "extension")
    property var sites
    property bool closing: false
    function answer(a) { asks = asks.filter(x => x !== a) }
    function unquiet() { asks = asks.map(a => a === quietAsk ? Object.assign({}, a, { quiet: false }) : a) }
    // the page's dialog, file pick, popups and full screen (PLAN.md 3.8 8j-8m), set by the shots
    property var dialog: null
    property var choosing: null
    property var popup: null
    property int blockedPopups: 0
    property bool isFullScreen: false
    // failures and the page's process (PLAN.md 3.8 8f-8h), set by the shots
    property var failure: null
    property var questioned: null
    readonly property string failed: failure ? (failure.tone === "error" ? "certificate" : "error") : questioned ? "certificate" : ""
    onFailedChanged: session.update(pageId, { failed: failed })
    property bool reloadOnShow: false
    property real lastPid: 0
    property real renderProcessPid: 0
    property var sample: null
    property var stops: []
    signal closeWanted()
    signal reopenWanted()
    signal processStopped(string status, int code)
    // reader view (PLAN.md 3.9), set by the shots: whether the page has an article, and shows it
    property string article: ""
    property bool reader: false
    function probeArticle() {}
    signal printWanted()
    // where you stopped (PLAN.md 3.7): shots set the rows' records themselves
    property var restoreStop: null
    signal saveWanted(var ask)
    function retry() { failure = null }
    function leave() { failure = null }
    function continueCertificate() { failure = null }
    function answerDialog() { dialog = null }
    function blockDialogs() { dialog = null }
    function fullScreenCancelled() { isFullScreen = false }
    // for PageScrollBar: a long page repeats its text `repeats` times; shots set the scroll position
    property real zoomFactor: 1
    property int repeats: 1
    property point scrollPosition: Qt.point(0, 0)
    readonly property size contentsSize: Qt.size(width, Math.max(height, content.height + 80))
    property bool dark: false
    // the section strip (PLAN.md 3.19): shots set the page's answer to Recall.sections
    property var sections: null
    signal openRequested(var request)
    signal linkHovered(url hoveredUrl)
    signal leaveAlways(string url)
    signal asked(var ask)
    signal copyRequested(string text)
    signal closeAccepted()
    signal closeKept()
    signal selfClosed()
    function goBack() {}
    function goForward() {}
    function reload() {}
    function reloadAndBypassCache() {}
    function stop() {}
    function runJavaScript() {}
    function fallBackTo() {}
    function findText() {}

    color: dark ? "#111214" : "#fbfbfa"
    clip: true
    readonly property color ink: dark ? "#e3e5e8" : "#1f2328"
    readonly property color subtle: dark ? "#9198a1" : "#59636e"

    Column {
        id: content
        x: 48
        y: 40 - page.scrollPosition.y
        width: Math.min(760, parent.width - 96)
        spacing: 14

        Text {
            width: parent.width
            text: String(page.url).replace(/^https?:\/\//, "").split("/")[0]
            font.pixelSize: 14
            color: page.subtle
        }
        Rectangle { width: parent.width; height: 1; color: page.dark ? "#3d444d" : "#d8dde2" }
        Text {
            width: parent.width
            text: page.title
            wrapMode: Text.Wrap
            font.pixelSize: 28
            font.weight: Font.DemiBold
            color: page.ink
        }
        Repeater {
            // Qt's JS engine has no Array.flat
            model: [].concat(...Array(page.repeats).fill([
                "The ov02c10 probes on CSIPHY0, but data-lanes from the DT is ignored and the PHY is set up",
                "for 4 lanes. The v3 series on lore fixes it; see the link below.",
                "",
                "Steps: boot with the x1p42100 DTB, run cam -l, the sensor lists, capture is black.",
                "lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org",
                "",
                "Tested v3 on the Book4 Edge: capture works, 1928x1092 at 30 fps.",
                "",
            ]))
            Text {
                required property string modelData
                width: parent.width
                text: modelData
                font.pixelSize: 16
                color: page.ink
            }
        }
    }
}
