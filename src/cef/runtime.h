#pragma once

#include <QByteArray>
#include <QString>
#include <functional>

// CEF in the browser process (book4-edge/opsis-cef-port-plan.md). Started once, before QGuiApplication: its loop on a
// thread of its own (polled from Qt's loop every 1 ms it cost 0.75 of a core, 2026-10-06), pages drawn off-screen for
// PageItem, the sandbox on, and the page processes run from `browser-page` beside this executable.
namespace CefRuntime {
struct Options {
    QString dataPath;       // CEF's profile and its log (cef.log); this process's alone
    QByteArray switches;    // Chromium's, as on a command line: "--site-per-process --js-flags=..."
};
// False when CEF did not start: another process holds dataPath, or libcef's data files are not beside it.
bool start(int argc, char *argv[], const Options &options);
// Once every PageItem is gone and before QGuiApplication is: waits up to 3 s for their pages to close.
void stop();
// stop() where its scope ends
struct Stopper {
    ~Stopper() { stop(); }
};
// PageItem's count of pages open or opening, for stop
void pageOpening();
void pageClosed();
// stop() has begun: a page must not wait on the GUI thread any more
bool stopping();
// Options::dataPath as start() was given it: Chromium's user data folder (its Dictionaries/ among the rest)
QString dataPath();
// A second launch that reached Chromium's own singleton (two started at once, before either held Thyris's lock): its link,
// on the GUI thread, as one handed over to Thyris (Instance::opened). Chromium opened a plain Chrome window for it.
void onRelaunch(std::function<void(const QString &url)> handler);
}
