#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QTimer>
#include <QWindow>

class QPointingDevice;

// Touchpad momentum (2026-10-01, "scroll is not smooth like Zen"): Hyprland and libinput give a touchpad's scroll as
// pixel steps with Begin, Update and End phases and no momentum, so a page stopped dead when the fingers lifted, where
// Firefox glides on. At the End this holds the gesture open and goes on sending the window Update steps at the speed
// the fingers left with, slowing as Files' GlideWheel does (0.998 a millisecond), then ends it; a new touch, a click
// or a key ends it at once. A mouse wheel (no phases) is left alone.
class Glide : public QObject {
    Q_OBJECT
public:
    explicit Glide(QObject *parent = nullptr);
    bool eventFilter(QObject *watched, QEvent *event) override;
    bool gliding() const { return m_gliding; }

private:
    void tick();
    void stop();
    void send(Qt::ScrollPhase phase, QPoint pixels);

    struct Step {
        quint64 at;
        QPointF delta;
    };
    QList<Step> m_steps;                // the touch's last steps, for the speed it ends with
    QPointer<QWindow> m_window;
    QPointF m_pos;
    QPointF m_global;
    Qt::KeyboardModifiers m_modifiers;
    bool m_inverted = false;
    const QPointingDevice *m_device = nullptr;
    QPointF m_velocity;                 // px a millisecond
    QPointF m_rest;                     // the fraction of a pixel not sent yet
    qreal m_angleRatio = 12;            // angleDelta a pixel, as the touch's own steps carried it (QtWayland: 12)
    QElapsedTimer m_clock;
    QTimer m_timer;
    bool m_gliding = false;
    bool m_sending = false;
};
