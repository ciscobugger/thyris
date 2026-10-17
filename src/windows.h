#pragma once

#include <QObject>
#include <QString>
#include <QWindow>
#include <qqmlintegration.h>

// What QML cannot do for the browser's windows (PLAN.md 3.17): show a window under a Wayland app_id of its own (a
// sign-in in the notch), and carry a page's back history from one view into a new one (a page moved to another window).
class Windows : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    using QObject::QObject;

    // Qt 6.11 has no per-window app_id: its Wayland plugin sends QGuiApplication::desktopFileName() when a
    // window's xdg_toplevel is made, at each show (tested against a headless weston). So the name is
    // `appId` while `window` is shown, and the app's own again right after; a hidden and reshown window
    // takes the app's own unless shown through here again. "" is the app's own (a sign-in popup leaving the notch for
    // its own window): Backdrop then counts it as one of the app's windows again.
    Q_INVOKABLE void showAs(QWindow *window, const QString &appId);
    // The back and forward list of WebEngineView `view` (QWebEngineHistory's stream, which keeps each
    // entry's scroll and form state), base64; "" when `view` is not a web view.
    Q_INVOKABLE QString history(QObject *view) const;
    // Loads `history` (from history()) into `view`, a new WebEngineView, whose page then loads its current entry;
    // false when `view` is not a web view or `history` is empty.
    Q_INVOKABLE bool restore(QObject *view, const QString &history) const;
};
