import QtQuick
import QtTest
import "../qml/Reader.js" as Reader

// Reader.js: the article's page in the browser's colours and faces (PLAN.md 3.9). The swap itself runs in a page, in
// tools/check-engine reader.
TestCase {
    name: "Reader"

    readonly property var tokens: ({ ground: Qt.rgba(0.1, 0.1, 0.1, 1), ink: Qt.rgba(0.9, 0.9, 0.9, 1), subtext: Qt.rgba(0.8, 0.8, 0.8, 1),
                                     hairline: Qt.rgba(0.3, 0.3, 0.3, 0.3), wash: Qt.rgba(0.9, 0.9, 0.9, 0.05), selection: Qt.rgba(0.9, 0.7, 0.6, 0.4),
                                     font: "SF Pro Rounded", title: "Readex Pro", mono: "JetBrainsMono Nerd Font" })

    function test_theme() {
        const t = Reader.theme(tokens);
        compare(t.ground, "rgba(26, 26, 26, 1)");
        compare(t.hairline, "rgba(77, 77, 77, 0.3)");
        compare(t.dark, true);
        compare(Reader.theme(Object.assign({}, tokens, { ground: Qt.rgba(0.98, 0.98, 0.97, 1) })).dark, false);
    }

    // OwnPage's frame: the 680 px column at 28 %, the title in Readex Pro 18 px 54 px down; the root scrollbar hidden
    function test_css() {
        const css = Reader.css(Reader.theme(tokens));
        verify(css.indexOf("margin-left: max(40px, min(28vw, calc(100vw - 720px)))") >= 0);
        verify(css.indexOf("width: min(680px,") >= 0);
        verify(css.indexOf("padding: 54px 0 96px") >= 0);
        verify(css.indexOf("font: 400 18px/24px \"Readex Pro\"") >= 0);
        verify(css.indexOf("\"SF Pro Rounded\", sans-serif") >= 0);
        verify(css.indexOf("html { background: rgba(26, 26, 26, 1) !important; scrollbar-width: none !important; color-scheme: dark }") === 0);
        verify(css.indexOf("::selection { background: rgba(230, 179, 153, 0.4)") >= 0);
        verify(!/box-shadow|border-left/.test(css), "no shadows, no accent stripes");
    }

    // the scripts carry the theme as data, never as code
    function test_enter() {
        const s = Reader.enter(Object.assign({}, tokens, { font: "x\"; alert(1); \"" }));
        verify(s.indexOf("const css = \"") > 0);
        verify(s.indexOf("alert(1); \\\"") > 0, "a family's quotes stay inside the string");
        verify(s.indexOf("serializer: e => e") > 0, "Readability hands back nodes, not HTML to parse again");
        verify(Reader.leave.indexOf("scrollTo(s.x, s.y)") > 0);
    }
}
