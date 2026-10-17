import QtQuick

// The shell's colour animation (tacit-shell modules/common/widgets/CAnim.qml, from caelestia): colour changes
// ease on the slow-effects curve. Hover washes follow the pointer in 80 ms, as Files' rows do.
ColorAnimation {
    property bool hover: false
    duration: hover ? 80 : Theme.anim.expressiveSlowEffectsDuration
    easing.type: hover ? Easing.Linear : Easing.BezierSpline
    easing.bezierCurve: Theme.anim.expressiveSlowEffects
}
