#pragma once

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QSize>
#include <QStringList>
#include <QVariant>
#include <QWindow>
#include <functional>
#include <qqmlintegration.h>

// Where the browser's windows lie, for Frost.qml and for several windows (PLAN.md 3.17): the screen's size (QScreen)
// and each window's position, workspace and address, asked of Hyprland's IPC socket (j/clients: this process's windows
// under the app's own class, matched to ours by title, the rest in the order they were shown). Refreshed on request
// only (a frosted surface opening, a window resizing or taking the focus, a quit), never polled. Offscreen (shots,
// engine checks) every window is a tiled window on this laptop's screen: (6, 44) on 1920x1080.
// askCursor asks where Hyprland's cursor is (j/cursorpos), for the peek's flick rule (PLAN.md 3.5).
// `texture` is the first window's blurred wallpaper; each window makes its own (Main.frostSource).
class Backdrop : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QSize screenSize READ screenSize NOTIFY changed)
    Q_PROPERTY(QPoint windowPos READ windowPos NOTIFY changed)
    Q_PROPERTY(QQuickItem *texture MEMBER m_texture NOTIFY textureChanged)
    // engine checks: the point askCursor answers offscreen; unset, it answers not found
    Q_PROPERTY(QVariant fakeCursor MEMBER m_fakeCursor)
    // engine checks: the j/clients list offscreen (a JSON array); set, the requests Hyprland would get go to `dispatched`
    Q_PROPERTY(QVariant fakeClients MEMBER m_fakeClients)
    // engine checks: the workspace id j/activeworkspace answers offscreen (with fakeClients set)
    Q_PROPERTY(QVariant fakeWorkspace MEMBER m_fakeWorkspace)
    Q_PROPERTY(QStringList dispatched MEMBER m_dispatched)
public:
    explicit Backdrop(QObject *parent = nullptr);

    QSize screenSize() const { return m_screenSize; }
    QPoint windowPos() const { return m_windowPos; }
    // True when an answer follows (`refreshed`); false outside Hyprland.
    Q_INVOKABLE bool refresh();
    // `window`'s place on its screen, as windowPos; windowPos for a window Hyprland has not listed
    Q_INVOKABLE QPoint posOf(QWindow *window) const;
    // The workspace `window` was on at the last answer, as movetoworkspacesilent takes it ("3", "name:web",
    // "special:scratch"); "" when unknown.
    Q_INVOKABLE QString workspaceOf(QWindow *window) const;
    // Moves each { window, workspace } of `placements` to its workspace without following it (movetoworkspacesilent,
    // hl.dsp.window.move with follow = false) once Hyprland lists every shown window of ours, asking every 100 ms for
    // up to 2 s; the windows it lists by then are moved.
    Q_INVOKABLE void place(const QVariantList &placements);
    // Gives `window` the focus (hl.dsp.focus): an activation request alone may only mark it urgent.
    Q_INVOKABLE void focus(QWindow *window);
    // Moves `window` to the workspace you are on when it is on another (without following it) and gives it the focus:
    // `browser` run again from another workspace brings the window to you, its pages still playing. False outside
    // Hyprland (nothing asked).
    Q_INVOKABLE bool bringHere(QWindow *window);
    // Answered by cursorAnswered: at once, not found, outside Hyprland; otherwise once Hyprland
    // answers, or not found after 500 ms.
    Q_INVOKABLE void askCursor();

protected:
    bool eventFilter(QObject *object, QEvent *event) override;

signals:
    void changed();
    void textureChanged();
    void refreshed();
    // `pos` is on the window's screen, in the same coordinates as windowPos
    void cursorAnswered(bool found, QPoint pos);

private:
    struct Place {
        QPoint pos;
        QString workspace;
        QString address;
    };
    struct Placing {
        QPointer<QWindow> window;       // a window closed while place() waits is gone from here, not dangling
        QString workspace;
    };
    QList<QWindow *> ours() const;
    void answered(const QByteArray &reply);
    QHash<QWindow *, Place> match(const QByteArray &reply) const;
    void placeStep();
    QPoint screenOrigin(QWindow *window) const;
    // one request to Hyprland's socket; `done` runs once, with what came back (empty on failure)
    bool ask(const QByteArray &command, std::function<void(const QByteArray &)> done);

    QSize m_screenSize{1920, 1080};
    QPoint m_windowPos{6, 44};
    QHash<QWindow *, Place> m_places;
    QPointer<QQuickItem> m_texture;
    QVariant m_fakeCursor;
    QVariant m_fakeClients;
    QVariant m_fakeWorkspace;
    QStringList m_dispatched;
    QList<Placing> m_placing;           // place()'s windows while it waits for them to be listed
    int m_placeTries = 0;
    // when each window was last shown (QEvent::Show): Hyprland lists a window hidden and shown again as a new one, last
    QHash<QWindow *, quint64> m_shown;
    quint64 m_shows = 0;
    bool m_asking = false;              // a j/clients request in flight
    bool m_again = false;               // asked again while one was in flight
};
