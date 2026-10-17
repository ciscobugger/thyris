#include "glide.h"

#include <QCoreApplication>
#include <QWheelEvent>
#include <cmath>

static constexpr qreal decay = 0.998;       // a millisecond, as GlideWheel
static constexpr qreal slowest = 0.02;      // px a millisecond: slower than this the glide ends
static constexpr qreal fastEnough = 0.1;    // px a millisecond at the End: slower than this nothing glides
static constexpr quint64 recent = 60;       // ms of the touch read for its speed: fingers that rested first glide none

Glide::Glide(QObject *parent) : QObject(parent) {
    m_timer.setTimerType(Qt::PreciseTimer);
    m_timer.setInterval(16);
    connect(&m_timer, &QTimer::timeout, this, &Glide::tick);
}

bool Glide::eventFilter(QObject *watched, QEvent *event) {
    switch (event->type()) {
    case QEvent::Wheel: {
        // the window's own delivery only (each item it reaches passes through here too), and not what this sends
        if (m_sending || !watched->isWindowType())
            return false;
        auto *wheel = static_cast<QWheelEvent *>(event);
        switch (wheel->phase()) {
        case Qt::NoScrollPhase:
        case Qt::ScrollMomentum:
            stop();
            return false;
        case Qt::ScrollBegin:
            stop();
            m_steps.clear();
            return false;
        case Qt::ScrollUpdate:
            m_steps.append({wheel->timestamp(), QPointF(wheel->pixelDelta())});
            if (const QPoint p = wheel->pixelDelta(), a = wheel->angleDelta(); qMax(qAbs(p.x()), qAbs(p.y())) >= 2)
                m_angleRatio = qAbs(p.y()) >= qAbs(p.x()) ? qAbs(qreal(a.y()) / p.y()) : qAbs(qreal(a.x()) / p.x());
            while (m_steps.size() > 1 && m_steps.first().at + recent < wheel->timestamp())
                m_steps.removeFirst();
            return false;
        case Qt::ScrollEnd: {
            // the End comes twice: the second finds the glide going, or nothing to glide
            if (m_gliding)
                return true;
            QPointF moved;
            quint64 first = wheel->timestamp();
            for (const Step &s : std::as_const(m_steps))
                if (s.at + recent >= wheel->timestamp()) {
                    moved += s.delta;
                    first = qMin(first, s.at);
                }
            m_steps.clear();
            const QPointF velocity = moved / qMax<qreal>(qreal(wheel->timestamp() - first), 16);
            if (std::hypot(velocity.x(), velocity.y()) < fastEnough)
                return false;
            m_window = qobject_cast<QWindow *>(watched);
            m_pos = wheel->position();
            m_global = wheel->globalPosition();
            m_modifiers = wheel->modifiers();
            m_inverted = wheel->inverted();
            m_device = wheel->pointingDevice();
            m_velocity = velocity;
            m_rest = {};
            m_gliding = true;
            m_clock.start();
            m_timer.start();
            // held: the gesture ends when the glide does
            return true;
        }
        }
        return false;
    }
    case QEvent::MouseButtonPress:
    case QEvent::KeyPress:
    case QEvent::TouchBegin:
        stop();
        return false;
    default:
        return false;
    }
}

void Glide::tick() {
    if (!m_window) {
        m_gliding = false;
        m_timer.stop();
        return;
    }
    const qint64 dt = qMax<qint64>(1, m_clock.restart());
    m_velocity *= std::pow(decay, qreal(dt));
    if (std::hypot(m_velocity.x(), m_velocity.y()) < slowest) {
        stop();
        return;
    }
    m_rest += m_velocity * qreal(dt);
    const QPoint pixels = m_rest.toPoint();
    m_rest -= pixels;
    if (!pixels.isNull())
        send(Qt::ScrollUpdate, pixels);
}

void Glide::stop() {
    if (!m_gliding)
        return;
    m_gliding = false;
    m_timer.stop();
    if (m_window)
        send(Qt::ScrollEnd, {});
}

void Glide::send(Qt::ScrollPhase phase, QPoint pixels) {
    // angleDelta as the touch's own steps carried it: the engines scroll by angleDelta (Qt WebEngine, and PageItem on CEF),
    // and the fixed 3x this sent made the page drop to a quarter of the fingers' speed when they lifted (2026-10-07,
    // measured: Qt makes 12x from this touchpad's pixels)
    QWheelEvent wheel(m_pos, m_global, pixels, (QPointF(pixels) * m_angleRatio).toPoint(), Qt::NoButton, m_modifiers, phase, m_inverted,
                      Qt::MouseEventSynthesizedByApplication, m_device);
    m_sending = true;
    QCoreApplication::sendEvent(m_window, &wheel);
    m_sending = false;
}
