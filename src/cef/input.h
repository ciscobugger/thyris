#pragma once

#include <QPoint>
#include <QPointF>
#include <Qt>
#include "include/internal/cef_types_wrappers.h"

class QKeyEvent;
class QWheelEvent;

// Qt's input as CEF takes it for an off-screen page (book4-edge/opsis-cef-port-plan.md, slice 1).
namespace Input {
uint32_t modifiers(Qt::KeyboardModifiers keys, Qt::MouseButtons buttons);
CefMouseEvent mouse(QPointF pos, Qt::KeyboardModifiers keys, Qt::MouseButtons buttons);
// A key as Chromium's Linux path makes it: Windows' virtual key for Qt's key (what the page sees as keyCode), the
// keyboard's own code for the physical key (`code`), and the text for a character event.
CefKeyEvent key(const QKeyEvent *event, cef_key_event_type_t type);
// the text a key types for its character event (Enter's carriage return even without Qt's text)
QString keyText(const QKeyEvent *event);
// what a wheel event scrolls by, in px, as Qt WebEngine reckons it (web_event_factory.cpp): angleDelta in ticks of 120,
// each wheelScrollLines lines of 20 px, for a touchpad's steps too (Qt makes their angleDelta about 3x the pixels). Taking
// the touchpad's pixels as they were scrolled a third less than the Qt build (2026-10-07, "scroll speed is slow in cef").
QPointF wheelPixels(const QWheelEvent *event);
}
