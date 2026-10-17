import QtQuick
import "TacitSymbolNames.js" as TacitSymbolNames

// The shell's MaterialSymbol: a name Tacit's symbols cover is drawn from them (the filled font when fill is on), the
// rest stay Material's.
Text {
    property real iconSize: Theme.font.small
    property real fill: 0
    readonly property bool tacit: Theme.tacitSymbols && TacitSymbolNames.names[text] === 1

    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    font.hintingPreference: Font.PreferNoHinting
    font.family: tacit ? (fill >= 0.5 ? Theme.tacitFill.name : Theme.tacitLine.name) : Theme.font.icons
    font.pixelSize: iconSize
    // Tacit's fonts have one weight: asking for more would make Qt embolden the outline
    font.weight: fill >= 0.5 && !tacit ? Font.DemiBold : Font.Normal
    font.variableAxes: tacit ? ({}) : ({ "FILL": fill >= 0.5 ? 1.0 : 0.0, "opsz": iconSize })
    color: Theme.inkSec
}
