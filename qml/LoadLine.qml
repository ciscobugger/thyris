import QtQuick

// The 2 px loading line (PLAN.md 3.8): follows loadProgress smoothed (StandardSmall) and creeps to 12 %
// in the first 1.2 s so a slow server never looks dead; when loading ends it fills, holds 100 ms and
// fades out in 150 ms.
Item {
    id: line

    property var view: null
    // a certificate's page holds its load (PLAN.md 8g): nothing is loading as far as the line shows
    readonly property bool loading: view ? view.loading && !(view.failure && view.failure.held) : false
    readonly property real progress: view ? view.loadProgress / 100 : 0
    property bool active: false
    property real creep: 0
    // loadProgress as drawn. Only it is smoothed: the creep moves every frame, and a smoothed width
    // restarted every frame started a load at the last one's full width.
    property real fill: 0

    height: 2
    onLoadingChanged: {
        if (loading) {
            finish.stop();
            follow.stop();
            // a new load starts at 0, whatever the last one's loadProgress still reads
            fill = 0;
            bar.opacity = 1;
            active = true;
            creepIn.restart();
        } else if (active) {
            follow.stop();
            finish.restart();
        }
    }
    onProgressChanged: if (loading) { follow.to = progress; follow.restart() }
    onViewChanged: { finish.stop(); follow.stop(); creepIn.stop(); creep = 0.12; fill = progress; bar.opacity = 1; active = loading }

    NumberAnimation { id: creepIn; target: line; property: "creep"; from: 0; to: 0.12; duration: 1200 }
    Anim { id: follow; target: line; property: "fill"; type: Anim.StandardSmall }
    SequentialAnimation {
        id: finish
        Anim { target: line; property: "fill"; to: 1; type: Anim.StandardSmall }
        PauseAnimation { duration: 100 }
        Anim { target: bar; property: "opacity"; to: 0; type: Anim.FastEffects }
        PropertyAction { target: line; property: "active"; value: false }
    }

    Rectangle {
        id: bar
        visible: line.active
        height: 2
        radius: 1
        width: line.width * Math.max(line.creep, line.fill)
        color: Theme.transparentize(Theme.onSurface, 0.6)
    }
}
