import QtQuick

// Counts, sizes, times and percentages: 12 px, tabular figures.
Label {
    font.pixelSize: Theme.font.smaller
    font.features: { "tnum": 1 }
    color: Theme.colSubtext
}
