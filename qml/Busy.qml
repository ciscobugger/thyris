import QtQuick

// The busy glyph in a favicon slot while a page loads; it turns only while shown.
Symbol {
    id: busy
    text: "progress_activity"
    iconSize: 14
    width: 16
    height: 16
    RotationAnimation on rotation {
        running: busy.visible
        from: 0; to: 360
        duration: 1000
        loops: Animation.Infinite
    }
}
