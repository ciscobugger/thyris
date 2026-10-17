import QtQuick

// The shell's StyledText defaults.
Text {
    // Set weight, not font.weight: it drives both the wght axis (which would otherwise pin 450) and
    // font.weight for static fonts.
    property int weight: Theme.font.mainAxes.wght

    // native glyphs, letters as designed (no hinting), as the shell (2026-10-02, the owner's "fully macOS"): grey
    // edges blended in linear light by the patched Qt Quick in ~/dev/tacit-text
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    font.hintingPreference: Font.PreferNoHinting
    font.family: Theme.font.main
    font.pixelSize: Theme.font.small
    font.variableAxes: Object.assign({}, Theme.font.mainAxes, { "wght": weight })
    font.weight: weight === Theme.font.mainAxes.wght ? Font.Normal : weight
    color: Theme.colOnLayer0
    elide: Text.ElideRight
    // page titles and URLs are page-controlled: never read them as markup
    textFormat: Text.PlainText
}
