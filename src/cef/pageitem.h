#pragma once

#include <QColor>
#include <QHash>
#include <QJSValue>
#include <QList>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QRectF>
#include <QSizeF>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <functional>
#include <memory>
#include "include/cef_base.h"
#include "requests.h"
#include "scripts.h"

class PageClient;
class DevToolsBridge;
class PermissionRequest;
class AuthRequest;
class PageFrames;
class QJsonObject;
class QMimeData;
class QQmlEngine;

// A page drawn by CEF (book4-edge/opsis-cef-port-plan.md, slice 0). CEF renders it off-screen, in its GPU process,
// and hands each frame to this process on CEF's UI thread. On an OpenGL scene graph the frame stays on the graphics
// chip: a dmabuf, imported and copied there into one of three textures the scene graph shares
// (Qt::AA_ShareOpenGLContexts), the newest finished one drawn (0.26-0.41 of a core for a busy 1920x1080 page at
// 60 fps, against 0.75 through memory, 2026-10-06). On any other scene graph (offscreen: software), and with
// OPSIS_CEF_FRAMES=cpu, the pixels come through memory. A frame arrives only when the page changed, so a page at
// rest draws nothing.
// Input (slice 1): the pointer, the wheel, keys and text input go to the page as Chromium takes them (src/cef/input.h);
// a key the page leaves unhandled goes on to the parent item, as Qt WebEngine's view hands it on, so Opsis's own keys
// (KeyMap.js's P keys) work as before. A page's own pop-up (a select's list) is drawn where the page puts it. Drags:
// files, links and text dropped on the page from other apps, and a drag that starts in the page (an image, a link, a
// page's own draggable element) as a system drag that other apps and the page itself can take.
// Its properties, signals and functions have the names and meanings of Qt WebEngine's WebEngineView, which it stands
// in for under Opsis's QML (src/cef/shim) until the checks pass on CEF.
class PageItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    // loadingChanged carries the load as Qt WebEngine's loading info does: { status (0 started, 1 stopped, 2 succeeded,
    // 3 failed), url, errorCode (Chromium's net error, 0 for none), errorString, errorDomain (0 none, 1 internal),
    // isErrorPage, isDownload }
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int loadProgress READ loadProgress NOTIFY loadProgressChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY canGoBackChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY canGoForwardChanged)
    // the page's favicon, by the address the page gives for it
    Q_PROPERTY(QUrl icon READ icon NOTIFY iconChanged)
    Q_PROPERTY(qreal zoomFactor READ zoomFactor WRITE setZoomFactor NOTIFY zoomFactorChanged)
    // The profile (the shim's WebEngineProfile): its userScripts run in every page on it. Not CEF's yet (slice 3).
    Q_PROPERTY(QObject *profile READ profile WRITE setProfile NOTIFY profileChanged)
    // this page's own scripts, over the profile's
    Q_PROPERTY(ScriptCollection *userScripts READ userScripts CONSTANT)
    // the document's size and the main frame's scroll position, in the page's CSS px, told by a script of Opsis's in
    // every document (the "opsis" world; one report a frame at most)
    Q_PROPERTY(QSizeF contentsSize READ contentsSize NOTIFY contentsSizeChanged)
    Q_PROPERTY(QPointF scrollPosition READ scrollPosition NOTIFY scrollPositionChanged)
    // frames stay on the graphics chip; known once the item is in a window
    Q_PROPERTY(bool shared READ shared NOTIFY sharedChanged)
    // the page is in full screen (the Fullscreen API), as its handler allowed (fullScreenRequested)
    Q_PROPERTY(bool isFullScreen READ isFullScreen NOTIFY isFullScreenChanged)
    // the back/forward list (history.items), after each main-frame load
    Q_PROPERTY(PageHistory *history READ history CONSTANT)
    // the process the page runs in (as the system numbers it, outside the sandbox), 0 until it says; a new one after a
    // crash, a reload or a move to another site's process
    Q_PROPERTY(qint64 renderProcessPid READ renderProcessPid NOTIFY renderProcessPidChanged)
    // the page's process has stopped answering (Chromium's hang monitor); the page says so, and waitForPage gives it more
    // time or endAndReload ends the process and loads the page again
    Q_PROPERTY(bool unresponsive READ unresponsive NOTIFY unresponsiveChanged)
    // Qt's LifecycleState: 0 active, 1 frozen (kept as active here), 2 discarded: the page closes (its process and
    // memory freed) and keeps its address, title and back/forward list; active again, it is made anew from that list
    // (Opsis's history patch) or loads its address afresh
    Q_PROPERTY(int lifecycleState READ lifecycleState WRITE setLifecycleState NOTIFY lifecycleStateChanged)
    // DevTools, as Qt WebEngine's devToolsView: set, Chromium's DevTools front end loads in that view and inspects this
    // page (DevToolsBridge); cleared, they close. On DevTools' view, inspectedView is the page they inspect.
    Q_PROPERTY(PageItem *devToolsView READ devToolsView WRITE setDevToolsView NOTIFY devToolsViewChanged)
    Q_PROPERTY(PageItem *inspectedView READ inspectedView NOTIFY inspectedViewChanged)
    // the ground drawn where the page sets none, as Qt WebEngine's; read when the page is made (DevTools' view: their dark)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY backgroundColorChanged)
    // for the checks: the DevTools relay's { connected, document, inspected }, empty while DevTools are closed
    Q_PROPERTY(QVariantMap devToolsState READ devToolsState NOTIFY devToolsStateChanged)
public:
    explicit PageItem(QQuickItem *parent = nullptr);
    ~PageItem() override;
    // For a QML engine: PageItem as Browser.Cef's, and src/cef/shim found as the QtWebEngine module before Qt's own.
    static void registerQml(QQmlEngine *engine);
    // pages kept open after their item went, for downloads still coming (PageClient::close): closed now (CefRuntime::stop)
    static void closeKept();
    // the page's history with its entries' state, for another view (Windows::history), and that restored here before
    // this view has loaded anything (Windows::restore); both need Opsis's CEF build
    QString historyData();
    bool restoreHistory(const QString &data);
    // Qt's errorPageEnabled as the shim's settings say it: off, a failed main-frame load commits nothing (needs Opsis's
    // CEF build, errorpages-patch.py)
    Q_INVOKABLE void setErrorPages(bool on);
    // The page as a PDF at `path` (Printing::toPdf): paper in inches as portrait, margins in inches on every side, pages
    // `from`-`to` (1-based; from 0 for all), the page's backgrounds or not. pdfPrintingFinished answers.
    void printToPdf(const QString &path, const QSizeF &paper, bool landscape, qreal margin, int from, int to, bool backgrounds);
    // Security keys (book4-edge/cef-pgo/webauthn-patch.py): an answer to the engine's request `request` ("pin", "account"
    // with its index, "retry", "cancel"); webAuthnStep brings the request's steps. Both need Opsis's CEF build
    // (webAuthnBridge). The checks' virtual authenticator goes in through devtoolsCall (the DevTools WebAuthn domain).
    Q_INVOKABLE void webAuthnAnswer(int request, const QString &op, const QString &value = QString());
    Q_PROPERTY(bool webAuthnBridge READ webAuthnBridge CONSTANT)
    bool webAuthnBridge() const;
    void noteBrowser(int id);         // the page's browser made: its security-key steps come here
    Q_PROPERTY(QString lastWebAuthnAnswer READ lastWebAuthnAnswer)
    QString lastWebAuthnAnswer() const { return m_lastWebAuthnAnswer; }
    Q_INVOKABLE void devtoolsCall(const QString &method, const QVariantMap &params = {});
    // This view as spare DevTools: their front end loads now on a relay with no page, and a page given this view as its
    // devToolsView takes them as they are, loaded (DevToolsBridge's spare)
    Q_INVOKABLE void prepareDevTools();

    QUrl url() const { return m_url; }
    void setUrl(const QUrl &url);
    QString title() const { return m_title; }
    bool loading() const { return m_loading; }
    int loadProgress() const { return m_progress; }
    bool canGoBack() const { return m_canGoBack; }
    bool canGoForward() const { return m_canGoForward; }
    QUrl icon() const { return m_icon; }
    qreal zoomFactor() const { return m_zoom; }
    void setZoomFactor(qreal factor);
    QObject *profile() const { return m_profile; }
    void setProfile(QObject *profile);
    ScriptCollection *userScripts() const { return m_userScripts; }
    QSizeF contentsSize() const { return m_contentsSize; }
    QPointF scrollPosition() const { return m_scrollPosition; }
    bool shared() const { return m_shared; }
    qint64 renderProcessPid() const { return m_renderPid; }
    bool unresponsive() const { return m_unresponsive; }
    void setUnresponsive(bool on);
    int lifecycleState() const { return m_lifecycle; }
    void setLifecycleState(int state);
    bool isFullScreen() const { return m_fullScreen; }
    PageHistory *history() const { return m_history; }
    PageItem *devToolsView() const { return m_devToolsView; }
    void setDevToolsView(PageItem *view);
    PageItem *inspectedView() const { return m_inspectedView; }
    QVariantMap devToolsState() const;
    QColor backgroundColor() const { return m_background; }
    void setBackgroundColor(const QColor &color) { if (m_background != color) { m_background = color; emit backgroundColorChanged(); } }
    // the page's frames that have arrived
    Q_INVOKABLE int frames() const { return m_arrived; }
    // the last frame that arrived has the item's size: after a resize, the page is on screen at its new size
    Q_INVOKABLE bool frameFits() const;
    Q_INVOKABLE void goBack();
    // to the entry `offset` away (history.items' offset); with an engine without Opsis's navigation patch, one step only
    Q_INVOKABLE void goBackOrForward(int offset);
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void reload();
    Q_INVOKABLE void waitForPage();
    Q_INVOKABLE void endAndReload();
    // Qt WebEngine's loadHtml: `html` as the document at `baseUrl` (its origin, cookies and storage), no request sent
    // for it; with no base, a page of its own at about:blank
    Q_INVOKABLE void loadHtml(const QString &html, const QUrl &baseUrl = QUrl());
    Q_INVOKABLE void reloadAndBypassCache();
    Q_INVOKABLE void stop();
    // Runs `script` in the page; `callback(value)` gets what it evaluates to, as JSON carries it (undefined when it
    // threw or the page has gone). As WebEngineView's: (script), (script, callback), (script, world) or (script, world,
    // callback). World 0 is the page's own; any other is Opsis's own world in the main frame ("opsis"), which the page's
    // scripts cannot see.
    Q_INVOKABLE void runJavaScript(const QString &script, const QJSValue &worldOrCallback = QJSValue(),
                                   const QJSValue &callback = QJSValue());
    // As WebEngineView's, for the actions Opsis uses (its WebAction numbers): Back, Forward, Stop, Reload, the edits on
    // the focused frame, the image last right-clicked saved or its address copied, InspectElement (the element last
    // right-clicked, in DevTools), and RequestClose: the page's unload handlers ("Leave this page?") run, then
    // windowCloseRequested if it may close (PageClient::DoClose).
    Q_INVOKABLE void triggerWebAction(int action);
    // the page leaves full screen (Esc, or Opsis leaving it for another page)
    Q_INVOKABLE void fullScreenCancelled();
    // Find in the page (Qt's findText): the same text again goes to the next match (flags: 1 backward, 2 match case);
    // "" stops, leaving the current match selected. The count comes in findTextFinished, and to `callback` as found.
    Q_INVOKABLE void findText(const QString &text, int flags = 0, const QJSValue &callback = QJSValue());
    // the misspelled word in the field last right-clicked, replaced
    Q_INVOKABLE void replaceMisspelledWord(const QString &replacement);

signals:
    // a step of a security-key request of this page's: { state: touch | pin | accounts | failed | done | end, rp, ... }
    void webAuthnStep(int request, const QVariantMap &step);
    // printToPdf's file written (or not), as Qt WebEngine's
    void pdfPrintingFinished(const QString &filePath, bool success);
    // the page called print() (window.print, any frame's), as Qt WebEngine's
    void printRequested();
    void urlChanged();
    void titleChanged();
    void loadingChanged(const QVariantMap &info);
    void loadProgressChanged();
    void canGoBackChanged();
    void canGoForwardChanged();
    void iconChanged();
    void zoomFactorChanged();
    void profileChanged();
    void contentsSizeChanged();
    void scrollPositionChanged();
    void sharedChanged();
    void isFullScreenChanged();
    // a findText's result: { numberOfMatches, activeMatch (1 for the first, 0 with none) }
    void findTextFinished(const QVariantMap &result);
    // the page went into full screen or left it; the handler accepts or rejects
    void fullScreenRequested(FullScreenRequest *request);
    // the link under the pointer, or an empty one
    void linkHovered(const QUrl &hoveredUrl);
    // a right click: { x, y, linkUrl, selectedText, mediaUrl, mediaType, isContentEditable, misspelledWord }. No menu
    // is shown unless Opsis shows one.
    void contextMenuRequested(const QVariantMap &request);
    // A navigation about to start, in the main frame or a frame (a frame's only for an address another app may
    // take): the handler may reject it. It runs while the page waits, as Qt WebEngine's does.
    void navigationRequested(NavigationRequest *request);
    // the page asks for a new page or window; the handler may open it in a new view (request.openIn), while the page waits
    void newWindowRequested(NewWindowRequest *request);
    // the page called window.close()
    void windowCloseRequested();
    // alert(), confirm(), prompt(), or "Leave this page?" (beforeunload): the page waits for the answer
    void javaScriptDialogRequested(DialogRequest *request);
    // a file input asks for files; the page waits for the answer
    void fileDialogRequested(FileRequest *request);
    // a certificate the engine questions for a load; the load waits while the handler holds it (error.defer())
    void certificateError(CertificateError *error);
    // a camera, microphone, screen, location, notifications, clipboard, fonts or pointer-lock ask; the page waits for
    // permission.grant() or deny(), now or later
    void permissionRequested(PermissionRequest *permission);
    // a screen share (types 4, 5): the shim asks it as Qt's desktopMediaRequested; granted, Chromium opens the portal's
    // own picker for what to share
    void desktopCaptureRequested(PermissionRequest *permission);
    // a site (HTTP sign-in) or a proxy asks for a user name and password; the load waits for the answer
    void authenticationDialogRequested(AuthRequest *request);
    // a WebChannel message one of Opsis's scripts sent from the page (qt.webChannelTransport in Opsis's world), for the
    // shim's webChannel
    void webChannelMessage(const QString &message);
    // a touchpad's fingers down on it (a gesture began over the page) and lifted, for a sideways swipe back or forward
    void touchpadGesture(bool fingersDown);
    // Ctrl and the wheel, or a touchpad pinch, over the page: zoom it this many steps (+ in, - out). Chrome zooms in its
    // own browser layer before the page sees the wheel; CEF's off-screen view never does, so Opsis steps its site zoom
    void zoomGesture(int steps);
    void renderProcessPidChanged();
    void unresponsiveChanged();
    void lifecycleStateChanged();
    void devToolsViewChanged();
    void inspectedViewChanged();
    void devToolsStateChanged();
    void backgroundColorChanged();
    // the page's process ended under it, as Qt WebEngine reports it: status 1 abnormal, 2 crashed, 3 killed (the memory
    // killer too), with the exit code or signal. The last frame stays on screen until Opsis covers it or reloads.
    void renderProcessTerminated(int status, int code);

protected:
    void componentComplete() override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    bool event(QEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dragMoveEvent(QDragMoveEvent *event) override;
    void dragLeaveEvent(QDragLeaveEvent *event) override;
    void dropEvent(QDropEvent *event) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;

private:
    friend class PageClient;
    // opens the page once the item has a window and a size (in the next event loop turn, so a new window's openIn can
    // claim the view first)
    void open();
    void openNow();
    // a page CEF made for a new window (PageClient::OnBeforePopup), on the GUI thread: this view takes it
    CefRefPtr<PageClient> adopt();
    // DevTools (setDevToolsView): the relay, the views on either side, where the last right-click was (the page's px)
    void fromDevTools(const QByteArray &message, qint64 id);
    DevToolsBridge *m_bridge = nullptr;
    DevToolsBridge *m_spare = nullptr;  // on spare DevTools' view: their relay, until a page takes it
    QPointer<PageItem> m_devToolsView;
    QPointer<PageItem> m_inspectedView;
    QPointF m_menuPoint;
    QColor m_background = Qt::white;
    QSize m_lastFrame;                  // the last frame's size in pixels (frameFits)
    void answered(int call, bool done, const QByteArray &json);
    void click(QMouseEvent *event, bool up, int count);
    // a key the page left unhandled: the parent item gets it, as Qt WebEngine's view hands it on
    void unhandledKey(int cefType, int nativeCode);
    void editableFocused(bool on) { m_editable = on; }   // PageClient: a text field or editable element has the focus
    bool m_editable = false;
    // what Opsis's script in the page reports (scroll, size)
    void bridged(const QJsonObject &message);
    // the clipboard through this window: a copy in the page onto the desktop's, the desktop's into the page as a paste
    void copiedInPage(const QJsonObject &said);
    bool pasteFromDesktop(bool plain);
    // the profile's scripts and this page's into the page
    void syncScripts();
    // a drag the page started: as a system drag (QDrag), then where it ended back to the page
    void startDrag(QMimeData *data, const QImage &image, QPoint hotspot, int allowed);
    // OPSIS_CEF_TRACE: how long a click and a switch to this page take to reach the screen, on stderr. `painted`: when
    // CEF handed the frame over (steady clock, ns); `swapped`: the window drew.
    void traceFrame(qint64 painted);
    void traceResized(QSize got);
    void refreshFrame();       // OPSIS_CEF_TRACE: the first frame of a new size, and how long it took
    void traceSwapped();
    // The page's beat (CEF's external begin frames), with OPSIS_CEF_BEAT=1 only: CEF draws the page when this asks, once
    // each time the window has put a frame on the screen (frameSwapped), and from m_beat while the window rests. It kept
    // scrolling on the screen's time, but CEF stamps such a frame with the moment the ask arrived, a few ms off each
    // time, and video then dropped frames (2026-10-08: 1080p VP9, 5-27 of ~350 against none on CEF's own clock). CEF's own
    // clock stays the default; what made it jitter, its capture dropping frames that came early, is fixed in Opsis's CEF
    // build (cef-tacit-osr-capture.patch).
    void beginFrame();
    void windowBeat();
    void beatTick();
    // the page drew or was touched: the beat stays quick for a while
    void busy();

    QUrl m_url;
    QString m_restore;      // a history to restore once the page is made (restoreHistory)
    bool m_errorPages = true;   // setErrorPages, for a client made later
    bool m_restorePending = false;  // this page is made for a history, so it starts on no address
    QString m_title;
    QString m_lastWebAuthnAnswer;      // the checks': "<request> <op>", never the PIN
    bool m_loading = false;
    qint64 m_renderPid = 0;
    bool m_unresponsive = false;
    int m_lifecycle = 0;
    QUrl m_givenUrl;            // loadHtml before the page is made: handed to its client in openNow
    QByteArray m_givenHtml;
    QHash<quint64, QPointer<QObject>> m_prompts;     // permission prompts the engine may still drop, by its prompt id
    int m_progress = 0;
    bool m_canGoBack = false;
    bool m_canGoForward = false;
    QUrl m_icon;
    qreal m_zoom = 1;
    QPointer<QObject> m_profile;
    ScriptCollection *m_userScripts;
    QSizeF m_contentsSize;
    QPointF m_scrollPosition;
    QPointF m_wheelRest;
    bool m_wheelBegun = false;      // a touchpad gesture has sent its Began step (wheelEvent)
    QPoint m_wheelLast;             // the gesture's last step that moved, for the 1 px its End carries
    bool m_fingersDown = false;     // between a touchpad gesture's Begin and its End or Glide's first step
    qreal m_zoomRest = 0;           // Ctrl+wheel toward the next zoom step (120 a notch)
    qreal m_pinchRest = 0;          // a pinch's scale toward the next zoom step
    QTimer m_beat;
    // after the window's size settles, a fresh frame at the new size (PageItem::refreshFrame): CEF sends a frame only
    // when the page changes, and the one for the last size of a resize can be missed while its capture switches size
    QTimer m_refresh;
    int m_refreshes = 0;
    qint64 m_lastBegin = 0, m_lastBusy = 0;     // ns, steady clock
    qint64 m_resizedAt = 0;             // ns: the last size change the engine has not answered yet (traced)
    QSize m_resizeTarget;               // its frames' size in pixels
    int m_lastCall = 0;
    QHash<int, QJSValue> m_calls;       // runJavaScript's callbacks, by the call's number
    QList<QKeyEvent *> m_keys;          // keys sent to the page, until it says it left one unhandled
    QList<qint64> m_keySent;            // when each of m_keys went to the page (ns, nowNs)
    qint64 m_loadStarted = 0;           // when the page's latest load started (ns)
    QRectF m_imeRect;                   // where the text being composed is
    QRectF m_popupRect;                 // the page's own pop-up (a select's list), where the page puts it
    bool m_popupShown = false;
    int m_dropOperation = -1;           // what the page under a drag would do with it (CEF's DragOperation); -1 not said yet
    int m_dragAsked = 0;                // the drag's enter and moves the page has not answered yet
    std::function<void()> m_heldDrop;   // a drop before the page answered them, sent when it has (or after 500 ms)
    void dropAnswered(int operation);   // PageClient: the page says what it would do with the drag
    bool m_shared = false;
    bool m_fullScreen = false;
    PageHistory *m_history = new PageHistory(this);
    bool m_opening = false;             // openNow() is queued
    int m_arrived = 0;
    void frameArrived();                // PageClient: a frame has come (m_arrived)
    // A resize's hold (geometryChange): the frame on screen stays, 1:1 at its own size, until the page has laid itself out
    // for the new size and two frames have come since, or for 150 ms. CEF's frames in between are the old picture
    // stretched to the new size, and showed as a stretched page while a window opened beside it (2026-10-17; Chrome
    // keeps its old frame at its own size meanwhile).
    bool m_holding = false;
    int m_holdFrom = -1;                // m_arrived when the page reported its new layout; -1 until it has
    QTimer m_holdLimit;
    void endHold();
    void fullScreenChanged(bool on, const QUrl &origin);   // PageClient: the page went into full screen or out
    void found(int matches, int active);                    // PageClient: a find's final count
    QString m_findText;                                     // the text the page's matches are for
    QJSValue m_findCallback;
    QUrl m_menuImage;                   // the image the last right-click was on, for its menu's actions
    qint64 m_traceClick = 0, m_traceClickFrame = -1, m_traceClickQueued = 0;     // OPSIS_CEF_TRACE, ns
    qint64 m_traceShow = 0, m_traceShowFrame = -1;
    bool m_traceShowDrawn = false;
    // OPSIS_CEF_TRACE pacing while page frames flow: window frames, those that showed no new page frame (repeats), page
    // frames replaced before one was shown (skipped), the longest wait between two page frames
    int m_paceSeen = 0, m_paceSwaps = 0, m_paceRepeats = 0, m_paceSkipped = 0;
    qint64 m_paceSince = 0, m_paceLastFrame = 0, m_paceWorst = 0;
    qint64 m_paceLastWheel = 0, m_paceWheelWorst = 0;   // the longest wait between two scroll steps sent to the page
    int m_paceWheels = 0;
    QPointF m_paceSums;     // x: the touchpad's pixels, y: Qt's angleDelta, both summed (as magnitudes) over the second
    qreal m_paceSent = 0;   // what went to the page, px
    CefRefPtr<PageClient> m_client;
    std::shared_ptr<PageFrames> m_frames;
    std::shared_ptr<PageFrames> m_popupFrames;
};

// Browser.Cef's CefProfiles (a QML singleton): a profile's engine preferences under Chromium's names, read and set on
// CEF's UI thread, and its HTTP cache cleared. The shim's WebEngineProfile (languages, spell check, the cache) and
// Engine (fonts) stand on it. A profile here is the shim's object; a private one has its own request context.
class CefProfiles : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    static CefProfiles *get();
    // a preference's value: bool, int, double, string or a list of strings; null where the name is not one, or CEF's
    // thread does not answer within a second
    Q_INVOKABLE QVariant preference(QObject *profile, const QString &name) const;
    Q_INVOKABLE QVariantMap preferences(QObject *profile, const QStringList &names) const;
    // null or undefined puts it back to Chromium's default
    Q_INVOKABLE void setPreference(QObject *profile, const QString &name, const QVariant &value);
    Q_INVOKABLE void clearHttpCache(QObject *profile);
    // Chromium's user data folder (its Dictionaries/ among the rest)
    Q_INVOKABLE QString dataPath() const;
signals:
    void httpCacheCleared(QObject *profile);
};

