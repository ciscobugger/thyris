#include "adblock.h"
#include "apps.h"
#include "disk.h"
#include "engine.h"
#include "enginecheck.h"
#include "facts.h"
#include "glide.h"
#include "instance.h"
#include "notch.h"
#include "passwords.h"
#include "picker.h"
#include "printing.h"
#include "shots.h"
#include "zen.h"
#include "chromeimport.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QLockFile>
#include <QQmlApplicationEngine>
#include <QSocketNotifier>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>
#ifdef BROWSER_CEF
#include "cef/pageitem.h"
#include "cef/runtime.h"
#else
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#endif
#include <csignal>
#include <cstdio>
#include <memory>
#include <optional>
#include <unistd.h>

// browser [--from <app>] [<address>]; a relative path is a file in the caller's working directory, which the running
// browser this may hand the address to does not share
static void readStart(const QStringList &args, QUrl &startUrl, QString &from) {
    for (qsizetype i = 1; i < args.size(); ++i) {
        if (args.at(i) == u"--from")
            from = args.value(++i);
        else if (startUrl.isEmpty())
            startUrl = QUrl::fromUserInput(args.at(i), QDir::currentPath());
    }
}

int main(int argc, char *argv[]) {
    // --zen-nss <mode> <dir>: Import from Zen's NSS helper (src/zen.cpp), a process of its own, before anything starts
    if (argc > 1 && qstrcmp(argv[1], "--zen-nss") == 0)
        return Zen::nssHelper(argc, argv);
    // no web channel message reaches a log, whatever QT_LOGGING_RULES says (Engine::quietChannel)
    Engine::quietChannel();
    // --shots <outdir> [scenario ...]: development renders (tools/shots). Offscreen, so no window ever
    // reaches the screen, and on a throwaway data dir, so the real threads and history stay untouched.
    const bool shotMode = argc > 1 && qstrcmp(argv[1], "--shots") == 0;
    // --check-engine [group ...]: keys and lifecycle against real web views (tools/check-engine), also offscreen and throwaway
    const bool checkMode = argc > 1 && qstrcmp(argv[1], "--check-engine") == 0;
    // Both also keep their own cache, so they never open the real browser's HTTP cache.
    std::optional<QTemporaryDir> shotData;
    // The user's own fonts (~/.local/share/fonts, where the SF Pro faces live) stay visible under the throwaway
    // data dir: fontconfig reads $XDG_DATA_HOME/fonts, and without the link shots and checks used a fallback face.
    const QString realData = qEnvironmentVariable("XDG_DATA_HOME", QDir::homePath() + QStringLiteral("/.local/share"));
    const auto keepUserFonts = [&] { QFile::link(realData + QStringLiteral("/fonts"), shotData->path() + QStringLiteral("/fonts")); };
    if (checkMode) {
        shotData.emplace();
        // without it Store and the profile would fall back to the real ~/.local/share/browser
        if (!shotData->isValid()) {
            std::fprintf(stderr, "browser --check-engine: cannot make a temporary data dir\n");
            return 2;
        }
        // OPSIS_CHECK_KEEP: the throwaway data dir stays after the run (the engine's cef.log, its Dictionaries/ and the rest)
        if (qEnvironmentVariableIsSet("OPSIS_CHECK_KEEP")) {
            shotData->setAutoRemove(false);
            std::fprintf(stderr, "browser --check-engine: data kept in %s\n", qPrintable(shotData->path()));
        }
        qputenv("QT_QPA_PLATFORM", "offscreen");
        keepUserFonts();
        qputenv("XDG_DATA_HOME", shotData->path().toLocal8Bit());
        qputenv("XDG_CACHE_HOME", (shotData->path() + QStringLiteral("/cache")).toLocal8Bit());
        // nor the user's config: fontconfig reads its fonts.conf from there, whose full hinting (this machine's since
        // 2026-09-18) made the Fonts check's two families measure 200 px alike, and a browser the checks start
        // (EngineCheck::launch) would read ~/.config/zen
        const QString config = shotData->path() + QStringLiteral("/config");
        if (!QDir().mkpath(config)) {
            std::fprintf(stderr, "browser --check-engine: cannot make a config dir\n");
            return 2;
        }
        qputenv("XDG_CONFIG_HOME", config.toLocal8Bit());
        // the single-instance socket (Instance) and the browsers the instance checks start stay in here too
        const QString runtime = shotData->path() + QStringLiteral("/runtime");
        if (!QDir().mkpath(runtime) || !QFile::setPermissions(runtime, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner)) {
            std::fprintf(stderr, "browser --check-engine: cannot make a runtime dir\n");
            return 2;
        }
        qputenv("XDG_RUNTIME_DIR", runtime.toLocal8Bit());
        // the loading checks' hosts (EngineCheck::serve): any name under .test is this machine, and none
        // under .invalid exists, so no check looks a name up on the network; media asks get fake devices,
        // so nothing the checks allow reaches a real microphone or camera
        // Chromium upgrades an http image on an https page to https (where the host has none, it fails): off
        // here, so the site panel's check can load one (PLAN.md 3.9, mixed content)
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", qgetenv("QTWEBENGINE_CHROMIUM_FLAGS")
                + " --host-resolver-rules=\"MAP *.invalid ~NOTFOUND, MAP *.test 127.0.0.1\" --use-fake-device-for-media-stream"
                // media plays into a silent sink: a check's page never sounds on the owner's speakers (2026-10-15)
                + " --disable-audio-output"
                + " --disable-features=AutoupgradeMixedContent");
        // No session bus, compositor or X server: a screen-share or passkey check can then reach no
        // portal picker, device or notification on the desktop. Offscreen needs none of them.
        for (const char *name : {"DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "DISPLAY"})
            qunsetenv(name);
        // tools/check-engine's private X server for Chromium (see there): not the desktop's
        if (!qEnvironmentVariableIsEmpty("CHECK_X_DISPLAY"))
            qputenv("DISPLAY", qgetenv("CHECK_X_DISPLAY"));
        qputenv("XDG_SESSION_TYPE", "tty");
        // the browsers the instance checks start (EngineCheck::launch) keep this run's folders, so a link they hand over
        // reaches this browser (the CEF build's normal start otherwise moves into opsis-cef below)
        qputenv("OPSIS_CHECK_CHILD", "1");
        Apps::dryRun = true;
        Picker::dryRun = true;
        Facts::dryRun = true;
        // print (PLAN.md 3.16): a stand-in printer, and a job to it is only recorded, as no check may reach CUPS
        Printing::dryRun = true;
        Printing::fakePrinters = {QStringLiteral("Check printer")};
        // the passwords checks bring a throwaway Secret Service of their own (EngineCheck::startKeyring)
        Passwords::noSessionBus = true;
        // the Zen import checks make up a Zen folder of their own (EngineCheck::zenProfile)
        Zen::noUserProfile = true;
        ChromeImport::noUserProfile = true;
        // a copy of what this process and the engine's write, so a check can say no password reached it
        EngineCheck::captureOutput();
        // Settings' Update now runs a script of the check's own, and spell check converts the check's own dictionary
        Adblock::checkMode = true;
        Engine::hunspellOverride = shotData->path() + QStringLiteral("/hunspell");
        // the real ~/Downloads is never written
        Disk::folderOverride = shotData->path() + QStringLiteral("/Downloads");
        // ad blocking on a filter list of the check's own: requests to ads.test refused, and div.check-ad hidden
        // on 127.0.0.1's pages only
        const QString lists = shotData->path() + QStringLiteral("/browser/adblock/lists");
        QFile list(lists + QStringLiteral("/check.txt"));
        if (!QDir().mkpath(lists) || !list.open(QIODevice::WriteOnly) || list.write("||ads.test^\n127.0.0.1##div.check-ad\n") < 0) {
            std::fprintf(stderr, "browser --check-engine: cannot write the check's filter list\n");
            return 2;
        }
    }
    if (shotMode) {
        shotData.emplace();
        if (argc < 3 || !shotData->isValid()) {
            std::fprintf(stderr, "usage: browser --shots <outdir> [scenario ...]\n");
            return 2;
        }
        qputenv("QT_QPA_PLATFORM", "offscreen");
        keepUserFonts();
        qputenv("XDG_DATA_HOME", shotData->path().toLocal8Bit());
        qputenv("XDG_CACHE_HOME", (shotData->path() + QStringLiteral("/cache")).toLocal8Bit());
        Disk::folderOverride = shotData->path() + QStringLiteral("/Downloads");
        // shots draw made-up logins, never the desktop keyring's, a made-up printer, never CUPS's, and a made-up Zen profile
        Passwords::noSessionBus = true;
        Zen::noUserProfile = true;
        ChromeImport::noUserProfile = true;
        Printing::dryRun = true;
        Printing::fakePrinters = {QStringLiteral("Brother_HL-L2350DW")};
        // Offscreen, Qt Quick would pick its software renderer, which draws no ShaderEffect (Frost.qml)
        // and no MultiEffect; the RHI renderer runs offscreen too.
        qputenv("QT_QUICK_BACKEND", "rhi");
    }

    // Mesa spoofs the GL vendor only for executables named chromium, chrome, code and a few Electron
    // apps: Skia's freedreno path is broken under ANGLE since Chromium 138 (mesa MR 36540).
    if (!qEnvironmentVariableIsSet("force_gl_vendor"))
        qputenv("force_gl_vendor", "angleisbroken");
    // With the threaded render loop the page stays black after a Hyprland workspace switch until
    // something on it repaints; the basic loop measured the same speed.
    if (!qEnvironmentVariableIsSet("QSG_RENDER_LOOP"))
        qputenv("QSG_RENDER_LOOP", "basic");
    // Site isolation, as Chrome: every site in a renderer process of its own. Chromium leaves it to the embedder and
    // Qt WebEngine does not ask for it, so it was off (chrome://process-internals: "Disabled", 2026-10-03): every site
    // opened from a page ran in that page's process, with no Spectre boundary between them, one crash took all of them,
    // and one heavy site grew the shared process past 5 GB in a 15-site test. OPSIS_SITE_ISOLATION=0 turns it off for a
    // benchmark A/B only.
    if (qgetenv("OPSIS_SITE_ISOLATION") != "0")
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", qgetenv("QTWEBENGINE_CHROMIUM_FLAGS") + " --site-per-process");
    // V8's first full collection at 32 MB of old space. V8 14.0 here starts at 256 MB, so a page kept up to ~300 MB of
    // garbage it never collected: Twitch 311 MB against 64 MB with it (2026-10-03). It costs nothing on Speedometer:
    // 19.3 with it, 19.3 without (offscreen, fresh process, quiet CPU, 2026-10-06); the 20 -> 17 of windowed runs was
    // background load. OPSIS_V8_OLD_SPACE=<mb> sets another size for an A/B. A --js-flags given in the environment is
    // replaced.
    const QByteArray space = qEnvironmentVariableIsEmpty("OPSIS_V8_OLD_SPACE") ? "32" : qgetenv("OPSIS_V8_OLD_SPACE");
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS",
            qgetenv("QTWEBENGINE_CHROMIUM_FLAGS") + " --js-flags=--preconfigured-old-space-size=" + space);
    // The raster path is GPU by default. OPSIS_GPU_FLAGS=1 adds the flags that only matter when Adreno/ANGLE is on
    // Chromium's blocklist; two of the three (gpu-rasterization, accelerated-2d-canvas) are already the default, so the
    // one that can move is --ignore-gpu-blocklist. Check chrome://gpu for "software" first; do not enable blind.
    if (qgetenv("OPSIS_GPU_FLAGS") == "1")
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", qgetenv("QTWEBENGINE_CHROMIUM_FLAGS")
                + " --ignore-gpu-blocklist --enable-gpu-rasterization --enable-accelerated-2d-canvas");
    // Any other V8 flag, appended last because Chromium takes the final --js-flags it is given:
    // OPSIS_JS_FLAGS=--future, for instance, replaces every --js-flags above without a rebuild.
    if (const QByteArray extra = qgetenv("OPSIS_JS_FLAGS"); !extra.isEmpty())
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", qgetenv("QTWEBENGINE_CHROMIUM_FLAGS") + " --js-flags=" + extra);

    // the browser: scheme (its pages, PLAN.md 3.17) and the spell check dictionaries' folder, before the engine starts
#ifdef BROWSER_CEF
    // The CEF build never opens the Qt WebEngine build's data (book4-edge/opsis-cef-port-plan.md): outside the checks and the
    // shots, which have folders of their own, all it keeps is under opsis-cef, and so it is an instance of its own.
    if (!checkMode && !shotMode && !qEnvironmentVariableIsSet("OPSIS_CHECK_CHILD")) {
        const QString own = realData + QStringLiteral("/opsis-cef");
        QDir().mkpath(own);
        QFile::link(realData + QStringLiteral("/fonts"), own + QStringLiteral("/fonts"));
        qputenv("XDG_DATA_HOME", own.toLocal8Bit());
        qputenv("XDG_CACHE_HOME", (qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + QStringLiteral("/.cache"))
                                   + QStringLiteral("/opsis-cef")).toLocal8Bit());
    }
#endif
    // Tacit's text standard (~/book4-edge/tacit-text-plan.md): the engine's Skia, patched in Opsis's own CEF build, blends
    // glyph edges with TACIT_TEXT_GAMMA and TACIT_TEXT_CONTRAST, which its processes inherit from here. The session sets
    // them once for every renderer; without that, the owner's pick of 2026-10-02 (gamma 2.2, Chromium's contrast).
    if (qEnvironmentVariableIsEmpty("TACIT_TEXT_GAMMA"))
        qputenv("TACIT_TEXT_GAMMA", "2.2");
    Engine::prepare();
#ifdef BROWSER_CEF
    // Chromium's switches are the ones made up above; offscreen there is no compositor or graphics chip for Chromium
    // either, and it draws in software as the window does
    QByteArray switches = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
    if (checkMode && !qEnvironmentVariableIsEmpty("CHECK_X_DISPLAY"))
        switches += " --ozone-platform=x11 --disable-gpu";
    else if (checkMode || shotMode)
        switches += " --ozone-platform=headless --disable-gpu";
    // uBlock Origin Lite, when tools/update-ubol has put it here: Chromium blocks with its rules, as in Chrome, and Opsis's
    // own blocker stands aside (2026-10-08: the owner's YouTube starts as fast as in their Chrome with it). The checks and
    // shots keep testing Opsis's own.
    const QString ubol = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/browser/extensions/ubol");
    if (!checkMode && !shotMode && QFile::exists(ubol + QStringLiteral("/manifest.json"))) {
        switches += " --load-extension=" + QFile::encodeName(ubol);
        Adblock::extensionBlocks = true;
    }
    // A link for a browser already running on this profile goes to it before this process starts an engine of its own:
    // started anyway, Chromium's own singleton handed the link to that browser's engine, which opened a plain Chrome
    // window for it (2026-10-08), and where there was no display the engine did not start at all.
    if (!checkMode) {
        QCoreApplication probe(argc, argv);
        Instance running(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/browser"));
        if (running.running()) {
            QUrl url;
            QString caller, title;
            readStart(probe.arguments(), url, caller);
            if (!url.isEmpty() && caller.isEmpty())
                caller = Instance::caller(&title);
            switch (running.start(url, caller, url.isEmpty() ? QString() : Instance::context(title))) {
            case Instance::HandedOff:
                return 0;
            case Instance::Queued:
                std::fprintf(stderr, "browser: the running browser has not answered yet; it opens the link when it does\n");
                return 0;
            case Instance::NoAnswer:
                std::fprintf(stderr, "browser: the running browser did not take the link\n");
                return 1;
            default:
                break;      // it quit meanwhile: this one starts (Instance below takes the lock again)
            }
        }
    }
    if (!CefRuntime::start(argc, argv, {QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                                            + QStringLiteral("/browser/cef"), switches})) {
        std::fprintf(stderr, "browser: CEF did not start\n");
        return 2;
    }
    // the scene graph's GL context shares its textures with the pages' (PageItem)
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
#else
    QtWebEngineQuick::initialize();
#endif
    // The single-instance lock (Instance), declared before the application so that it is let go after Chromium has
    // shut down, which ~QGuiApplication runs: a browser started as this one quits never opens the profile while this
    // one's Chromium still writes it.
    std::unique_ptr<QLockFile> profileLock;
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("browser"));
#ifdef BROWSER_CEF
    // CEF stops once the QML engine and its pages have gone, and before the application has
    const CefRuntime::Stopper stopCef;
    // a window class of its own on the desktop, so the Qt WebEngine build's Backdrop never takes these windows for its own
    // OPSIS_APP_ID: another Wayland app id, for an instance a capture places on a headless output by a window rule that
    // must not take the owner's own windows (2026-10-15)
    app.setDesktopFileName(qEnvironmentVariableIsSet("OPSIS_APP_ID") ? qEnvironmentVariable("OPSIS_APP_ID")
                           : checkMode || shotMode ? QStringLiteral("browser") : QStringLiteral("browser-cef"));
#else
    app.setDesktopFileName(QStringLiteral("browser"));
#endif
    // a touchpad's scroll glides on after the fingers lift (Glide)
    Glide glide;
    app.installEventFilter(&glide);

    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/browser");
    const QStringList args = app.arguments();
    if (shotMode) {
        Shots shots(args.at(2), args.mid(3), dataDir);
        shots.start();
        return app.exec();
    }
    QUrl startUrl;
    QString from;
    if (!checkMode)
        readStart(args, startUrl, from);
    QString callerTitle;
    if (!startUrl.isEmpty() && from.isEmpty())
        from = Instance::caller(&callerTitle);
    const QString context = startUrl.isEmpty() ? QString() : Instance::context(callerTitle);
    Instance instance(dataDir);
    CefRuntime::onRelaunch([&instance](const QString &url) { emit instance.opened(QUrl(url), QString(), QString()); });
    switch (instance.start(startUrl, from, context)) {
    case Instance::HandedOff:
        return 0;
    case Instance::Queued:
        std::fprintf(stderr, "browser: the running browser has not answered yet; it opens the link when it does\n");
        return 0;
    case Instance::NoAnswer:
        std::fprintf(stderr, "browser: the running browser did not take the link\n");
        return 1;
    case Instance::Failed:
        std::fprintf(stderr, "browser: cannot listen on %s; links from other apps will not reach this browser\n", qPrintable(instance.path()));
        break;
    }
    // Ctrl+L in the notch (src/notch.*): the main profile's socket for the shell's address sheet. Check mode leaves it
    // off, so the checks reach no shell; the notch group turns it on with a stand-in.
    Notch notch(Instance::socketPath(dataDir, QStringLiteral("notch-")));
    // and the one a sign-in popup is shown in the notch by (NotchSignin.qml); off in check mode as well (the signin group)
    Notch signin(Instance::socketPath(dataDir, QStringLiteral("signin-")), QStringLiteral("signin"));
    if (!checkMode) {
        notch.listen();
        signin.listen();
    }
    EngineCheck engineCheck;
    // the external-app checks' schemes: were Qt to launch one itself, the check hears of it, not the desktop
    if (checkMode)
        for (const char *scheme : {"browsercheck", "browsercheckapp"})
            QDesktopServices::setUrlHandler(QString::fromLatin1(scheme), &engineCheck, "qtLaunched");

    // Declared before the QML engine so it outlives the profile that calls its interceptor.
    Adblock adblock(dataDir + QStringLiteral("/adblock"));
    QQmlApplicationEngine engine;
#ifdef BROWSER_CEF
    PageItem::registerQml(&engine);
#endif
    engine.setInitialProperties({
        {QStringLiteral("dataDir"), dataDir},
        {QStringLiteral("startUrl"), startUrl},
        {QStringLiteral("startFrom"), from},
        {QStringLiteral("startContext"), context},
        {QStringLiteral("instance"), QVariant::fromValue<QObject *>(&instance)},
        {QStringLiteral("notch"), QVariant::fromValue<QObject *>(&notch)},
        {QStringLiteral("signinNotch"), QVariant::fromValue<QObject *>(&signin)},
        {QStringLiteral("adblock"), QVariant::fromValue(&adblock)},
        {QStringLiteral("engineCheck"), QVariant::fromValue<QObject *>(checkMode ? &engineCheck : nullptr)},
    });
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); },
                     Qt::QueuedConnection);
    engine.loadFromModule("Browser", "Main");
    // OPSIS_TERM_QUITS, for training the engine's speed profile (~/book4-edge/opsis-beat-chrome-plan.md stage 2):
    // SIGTERM quits as Ctrl+Q does, so the browser ends through here and its profile is written at exit
    static int termPipe[2] = {-1, -1};
    if (qEnvironmentVariableIsSet("OPSIS_TERM_QUITS") && ::pipe(termPipe) == 0) {
        std::signal(SIGTERM, [](int) { const char c = 0; (void)!::write(termPipe[1], &c, 1); });
        auto *term = new QSocketNotifier(termPipe[0], QSocketNotifier::Read, &app);
        QObject::connect(term, &QSocketNotifier::activated, &engine, [&engine] {
            if (!engine.rootObjects().isEmpty())
                QMetaObject::invokeMethod(engine.rootObjects().constFirst(), "quitAll");
        });
    }
    const int code = app.exec();
    // quit however it quit (Main.quitAll closes it first): a link sent from now on waits for the next browser
    instance.close();
    profileLock = instance.takeLock();
    return code;
}
