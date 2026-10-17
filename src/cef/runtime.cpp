#include "runtime.h"

#include "pageitem.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStringList>
#include <QThread>
#include <atomic>
#include <string>
#include "include/cef_app.h"
#include "include/cef_scheme.h"
#include "include/cef_request_context.h"
#include "include/cef_version.h"

namespace {
class App : public CefApp, public CefBrowserProcessHandler {
public:
    explicit App(QStringList switches) : m_switches(std::move(switches)) {}
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
    // browser:// (Opsis's own pages, Engine's OwnPagesCef), as Qt WebEngine's scheme: a host, secure (no "Not secure"),
    // local (a web page cannot load or open these addresses). The same in the page processes (pageprocess.cpp).
    void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
        registrar->AddCustomScheme("browser", CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE | CEF_SCHEME_OPTION_LOCAL);
    }
    // The browser process's command line; Chromium hands the page processes what is theirs of it. A switch given
    // twice keeps its last value, as on Chromium's own command line; feature lists add to CEF's own.
    void OnBeforeCommandLineProcessing(const CefString &process, CefRefPtr<CefCommandLine> line) override {
        if (!process.empty())
            return;
        // No scroll animation, as Qt WebEngine (its ScrollAnimatorEnabled follows --enable-smooth-scrolling, off unless
        // given): animated, a touchpad's steps lagged its fingers and the page turned late (2026-10-08, the owner's hand
        // replayed: 72-83 % of it moved, turns 9-68 ms; with this 100 %, 3-4 ms, as Qt WebEngine). --enable-smooth-scrolling
        // in the switches brings it back.
        if (!m_switches.contains(QStringLiteral("--enable-smooth-scrolling")))
            line->AppendSwitch("disable-smooth-scrolling");
        // No back-forward cache for now: a page Back or Forward brings back from it reports no load (no OnLoadStart or
        // OnLoadEnd), and Opsis, waiting for one, kept a refused certificate's page over the page Go back had reached
        // (2026-10-09). Telling those loads would keep the quick Back; until then BackForwardCache in --enable-features in
        // the switches brings it back.
        if (!m_switches.filter(QStringLiteral("--enable-features=")).join(u',').contains(u"BackForwardCache"))
            line->AppendSwitchWithValue("disable-features", line->HasSwitch("disable-features")
                                            ? line->GetSwitchValue("disable-features").ToString() + ",BackForwardCache" : "BackForwardCache");
        // No calls to Google that Thyris has no use for (network audit 2026-10-14, book4-edge/cef-pgo/audit): AI Mode's
        // eligibility check at every start (www.google.com; its button belongs to Chrome's address bar, not shown here)
        // and the network time check (clients2.google.com).
        const std::string unused = "AimEnabled,NetworkTimeServiceQuerying";
        line->AppendSwitchWithValue("disable-features", line->HasSwitch("disable-features")
                                        ? line->GetSwitchValue("disable-features").ToString() + "," + unused : unused);
        // Cameras through PipeWire (xdg-desktop-portal's Camera), where libcamera's cameras are: the Book4's, and Intel
        // laptops' MIPI cameras (IPU6, IPU7), which have no V4L2 webcam of their own; USB webcams come that way too
        // (2026-10-16). Chromium has it off by default.
        line->AppendSwitchWithValue("enable-features", line->HasSwitch("enable-features")
                                       ? line->GetSwitchValue("enable-features").ToString() + ",WebRtcPipeWireCamera" : "WebRtcPipeWireCamera");
        // Pages dark, as Tacit is (it has no light mode since 2026-10-07): prefers-color-scheme, form controls and scroll
        // bars follow Chromium's own theme, which SetChromeColorScheme (pageitem.cpp, followDesktop) does not reach, and
        // every page reported light on Tacit's dark (2026-10-17, a test page and YouTube). Not read from Qt: the engine
        // starts before the QGuiApplication (main.cpp), when Qt has no colour scheme to tell.
        line->AppendSwitch("force-dark-mode");
        // HTTP sign-in (and a proxy's) to PageClient::GetAuthCredentials, Thyris's card: without this CEF hands it to
        // Chrome's login dialog, which has no window here, and the page waited unasked (2026-10-15)
        line->AppendSwitch("disable-chrome-login-prompt");
        for (const QString &s : std::as_const(m_switches)) {
            if (!s.startsWith(u"--"))
                continue;
            const qsizetype equals = s.indexOf(u'=');
            const std::string name = s.mid(2, equals < 0 ? -1 : equals - 2).toStdString();
            std::string value = equals < 0 ? std::string() : s.mid(equals + 1).toStdString();
            if ((name == "enable-features" || name == "disable-features") && line->HasSwitch(name))
                value = line->GetSwitchValue(name).ToString() + "," + value;
            if (equals < 0)
                line->AppendSwitch(name);
            else
                line->AppendSwitchWithValue(name, value);
        }
    }

    // A page's downloads all go ahead, as with Qt WebEngine: Chromium otherwise holds a page's second automatic download
    // behind a permission prompt, and Alloy style shows that only while the page is on screen, so a page in the
    // background (and every page in the offscreen checks) lost its later files silently (2026-10-09). Opsis lists every
    // file under the page that sent it.
    // Pop-ups likewise: Chromium refused one opened without a click before CEF asked Opsis (OnBeforePopup), so Opsis
    // never knew of it (no count, no Allow); now every one comes to Opsis, which refuses or opens it (Main.qml,
    // PageState.newWindow, the site panel's Pop-ups), as with Qt WebEngine.
    void OnContextInitialized() override {
        CefRequestContext::GetGlobalContext()->SetContentSetting(CefString(), CefString(), CEF_CONTENT_SETTING_TYPE_AUTOMATIC_DOWNLOADS,
                                                                 CEF_CONTENT_SETTING_VALUE_ALLOW);
        CefRequestContext::GetGlobalContext()->SetContentSetting(CefString(), CefString(), CEF_CONTENT_SETTING_TYPE_POPUPS,
                                                                 CEF_CONTENT_SETTING_VALUE_ALLOW);
        noDictionaryFetch(CefRequestContext::GetGlobalContext());
    }
    // Chromium's spell check starts on, for the system's language, and fetches that dictionary from Google when the
    // profile has none (en-GB-10-2.bdic from redirector.gvt1.com at the first start, 2026-10-15). Off here; Thyris turns it
    // on for the languages it has dictionaries for (the shim's WebEngineProfile, Engine::convert puts them in place).
    static void noDictionaryFetch(CefRefPtr<CefRequestContext> context) {
        CefRefPtr<CefValue> off = CefValue::Create();
        off->SetBool(false);
        CefString error;
        if (!context->SetPreference("browser.enable_spellchecking", off, error))
            std::fprintf(stderr, "browser: spell check not turned off: %s\n", error.ToString().c_str());
    }

private:
    QStringList m_switches;
    IMPLEMENT_REFCOUNTING(App);
};

std::atomic<int> pages{0};
std::atomic<bool> halting{false};
}

namespace {
QString &startedDataPath() {
    static QString path;
    return path;
}
}

bool CefRuntime::start(int argc, char *argv[], const Options &options) {
    startedDataPath() = options.dataPath;
    // As main.cpp does for Qt WebEngine: Skia's freedreno path is broken under ANGLE (mesa MR 36540), and Mesa spoofs
    // the GL vendor only for the executables it knows by name. The GPU process inherits it.
    if (!qEnvironmentVariableIsSet("force_gl_vendor"))
        qputenv("force_gl_vendor", "angleisbroken");
    QDir().mkpath(options.dataPath);
    const QString dir = QFileInfo(QFile::symLinkTarget(QStringLiteral("/proc/self/exe"))).absolutePath();

    CefSettings settings;
    settings.multi_threaded_message_loop = true;
    settings.windowless_rendering_enabled = true;
    settings.no_sandbox = false;
    settings.log_severity = LOGSEVERITY_WARNING;
    CefString(&settings.browser_subprocess_path) = (dir + QStringLiteral("/browser-page")).toStdString();
    CefString(&settings.root_cache_path) = options.dataPath.toStdString();
    CefString(&settings.log_file) = (options.dataPath + QStringLiteral("/cef.log")).toStdString();
    // Chrome's own product token, version reduced as Chrome sends it, and nothing after it: WhatsApp Web read a trailing
    // "Thyris/0.1" as the browser's version and refused it ("works with Google Chrome 100+", 2026-10-15; as Brave, which
    // sends no token of its own). Thyris is named in the client hints' brand list, which comes from the engine.
    CefString(&settings.user_agent_product) = "Chrome/" + std::to_string(CHROME_VERSION_MAJOR) + ".0.0.0";
    return CefInitialize(CefMainArgs(argc, argv), settings,
                         new App(QProcess::splitCommand(QString::fromLocal8Bit(options.switches))), nullptr);
}

void CefRuntime::stop() {
    halting = true;
    PageItem::closeKept();
    for (int waited = 0; pages > 0 && waited < 3000; waited += 10)
        QThread::msleep(10);
    CefShutdown();
}

void CefRuntime::pageOpening() { ++pages; }
void CefRuntime::pageClosed() { --pages; }
QString CefRuntime::dataPath() {
    return startedDataPath();
}

bool CefRuntime::stopping() { return halting; }
