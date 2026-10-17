import QtQuick
import "Recall.js" as Recall

// A line of plain text with the letters of `words` in DemiBold (PLAN.md 3.7: matched letters by weight, never
// colour), elided at the right as a Label is. One line of rich text, so the runs sit as one word would; the text is
// escaped first, so a page title is never read as markup. Rich text does not elide: the runs are cut to the width
// here, the one that does not fit elided.
Item {
    id: marked

    property string text
    property var words: []
    property int pixelSize: Theme.font.small
    property color color: Theme.colOnLayer0

    readonly property var runs: Recall.marks(text, words)
    FontMetrics { id: plain; font.family: Theme.font.main; font.pixelSize: marked.pixelSize; font.hintingPreference: Font.PreferNoHinting }
    FontMetrics { id: bold; font.family: Theme.font.main; font.pixelSize: marked.pixelSize; font.weight: Font.DemiBold; font.hintingPreference: Font.PreferNoHinting }
    function metrics(r) { return r.marked ? bold : plain }

    implicitWidth: Math.ceil(runs.reduce((w, r) => w + metrics(r).advanceWidth(r.text), 0))
    implicitHeight: plain.height
    clip: true

    readonly property string html: {
        const out = [];
        let used = 0;
        for (const r of runs) {
            const w = metrics(r).advanceWidth(r.text);
            const fits = used + w <= width + 0.5;
            const t = fits ? r.text : metrics(r).elidedText(r.text, Text.ElideRight, Math.max(0, width - used));
            const escaped = t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
            out.push(r.marked ? "<span style=\"font-weight:600\">" + escaped + "</span>" : escaped);
            if (!fits)
                break;
            used += w;
        }
        return "<span style=\"white-space:pre\">" + out.join("") + "</span>";
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.RichText
        elide: Text.ElideNone
        text: marked.html
        font.pixelSize: marked.pixelSize
        color: marked.color
    }
}
