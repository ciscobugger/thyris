pragma Singleton
import QtQuick
import Browser

// Mirror of the shell's Appearance.qml, limited to the roles this app uses, fed by ThemeSource from
// the same matugen output. Formulas are copied from modules/common/functions/ColorUtils.qml.
QtObject {
    id: theme

    readonly property var m3: ThemeSource.colors
    function role(name, fallback) { return theme.m3[name] ?? fallback }

    readonly property color background: role("background", "#141313")
    // m3 prefix as in the shell: a property named onBackground next to `background` reads as a
    // signal handler and evaluates to black, which made colOnLayer0 text black on the dark rail.
    readonly property color m3onBackground: role("on_background", "#e6e1e1")
    readonly property color surfaceContainerLow: role("surface_container_low", "#1c1b1b")
    readonly property color surfaceContainer: role("surface_container", "#201f1f")
    readonly property color surfaceContainerHigh: role("surface_container_high", "#2b2a2a")
    readonly property color surfaceContainerLowest: role("surface_container_lowest", "#0e0e0e")
    readonly property color onSurface: role("on_surface", "#e6e1e1")
    readonly property color onSurfaceVariant: role("on_surface_variant", "#cac4c4")
    readonly property color outlineVariant: role("outline_variant", "#484646")
    readonly property color primary: role("primary", "#e9bda8")
    readonly property color error: role("error", "#ffb4ab")

    // Appearance.colors roles
    readonly property color colSubtext: onSurfaceVariant
    readonly property color colOnLayer0: m3onBackground
    readonly property color colOnSurface: onSurface
    readonly property color colOutlineVariant: outlineVariant
    // floating surfaces: the pinned rail's own ground at 88 % over the blurred wallpaper. The shell's
    // surfaceContainerHigh at 76 % let the warm wallpaper through and greyed the text (2026-09-28).
    readonly property color colPanelFrost: transparentize(terminal, 0.12)
    // The rail over the page wears the Settings side menu (tacit-settings.qml: surfaceContainerLowest at 50 % on
    // surfaceContainerHigh at 76 %). Drawn opaque: Hyprland's 0.85 rule already lets 15 % of the blur through, about
    // Settings' 12 %; the 88 % frost on top of it showed twice that and read brown (2026-09-29).
    readonly property color colRailGlass: {
        const c = over(transparentize(surfaceContainerLowest, 0.5), transparentize(surfaceContainerHigh, 0.24));
        return Qt.rgba(c.r, c.g, c.b, 1);
    }
    // The docked rail (PLAN.md 3.19) is Settings' side slab (tacit-settings.qml): surfaceContainerLowest at 50 % with a
    // 1 px onSurface hairline at 7 %, on the window's terminal ground. Lifted over the page it wears colRailGlass.
    readonly property color colRailSlab: transparentize(surfaceContainerLowest, 0.5)
    readonly property color colRailSlabEdge: transparentize(onSurface, 0.93)
    // the shell's colShadow (m3shadow at 30 %), for StyledRectangularShadow-like lifts
    readonly property color colShadow: transparentize(role("shadow", "#000000"), 0.7)
    // The section strip under the page (PLAN.md 3.19). At rest, on the window's ground: onSurface 9 % ahead, 18 % past, the
    // current one filling with primary at 55 %. Risen into a light page's foot it takes the page's tones: the shadow role
    // at 7 % and 16 %, the light scheme's accent (inverse_primary), names in outline, the current one in outlineVariant.
    // A dark page keeps the rest tones, its current name in onSurfaceVariant.
    readonly property color outline: role("outline", "#9b8e88")
    readonly property color inversePrimary: role("inverse_primary", "#71594e")
    readonly property color stripAhead: transparentize(onSurface, 0.91)
    readonly property color stripPast: transparentize(onSurface, 0.82)
    readonly property color stripFill: transparentize(primary, 0.45)
    readonly property color stripAheadLight: transparentize(role("shadow", "#000000"), 0.93)
    readonly property color stripPastLight: transparentize(role("shadow", "#000000"), 0.84)
    readonly property color stripFillLight: transparentize(inversePrimary, 0.45)
    readonly property color colLayer2: solveOverlayColor(surfaceContainerLow, surfaceContainer, 1 - ThemeSource.contentTransparency)
    readonly property color colOnLayer2: onSurface

    // Window ground shared with Code, the Claude app and foot: the terminal background.
    readonly property color terminal: ThemeSource.terminalBackground
    // The one switch for the window's glass: Hyprland's rule `opacity 0.85 0.77` for class browser (as
    // for zen) makes the whole window this opaque over its blurred wallpaper, so the app draws itself
    // opaque, and shot mode lays the wallpaper over the window at 1 - windowOpacity to show the same.
    // Without the rule set it to 1: the window is then plain opaque terminal.
    readonly property real windowOpacity: 0.85
    // Rows: current as the Claude app's rail; hover as Files' rows (10 %); pressed while the button is held on one
    readonly property color rowCurrent: transparentize(onSurface, 0.86)
    readonly property color rowHover: transparentize(onSurface, 0.90)
    readonly property color rowPressed: transparentize(onSurface, 0.78)
    // An unloaded row's title dims to 50 % only where that keeps 4.5:1 on the terminal ground (PLAN.md 3.18).
    readonly property bool dimTextReadable: contrast(colOnLayer0, 0.5, terminal) >= 4.5

    readonly property QtObject rounding: QtObject {
        readonly property int verysmall: 8
        readonly property int small: 12
        readonly property int normal: 17
        readonly property int large: 23
        readonly property int verylarge: 30
        readonly property int slab: 14      // the docked rail's slab, as Settings' side slab
    }
    // Tacit's own symbols (~/dev/tacit-icons), as the shell's Fonts.qml: a line font and a filled one, typed by name
    // like Material Symbols; a name they don't cover stays Material's
    readonly property FontLoader tacitLine: FontLoader { source: Qt.resolvedUrl("../assets/fonts/TacitSymbols.ttf") }
    readonly property FontLoader tacitFill: FontLoader { source: Qt.resolvedUrl("../assets/fonts/TacitSymbolsFill.ttf") }
    readonly property bool tacitSymbols: tacitLine.status === FontLoader.Ready && tacitFill.status === FontLoader.Ready
    readonly property QtObject font: QtObject {
        // the shell's faces (illogical-impulse config.json appearance.fonts): Tacit Sans, the system's own font, since
        // 2026-10-01 ("we have our font tacit now"); before it the browser drew SF Pro Rounded (2026-09-28).
        // Not hinted anywhere (Label, fields, metrics; 2026-10-02, as the shell): letters as designed, grey edges.
        // the browser's lists and rows: Tacit Sans Compact, the same face 7 % narrower (Tacit Sans read stretched in the
        // rail, owner 2026-10-01); titles keep the shell's face
        readonly property string main: "Tacit Sans Compact"
        // titles of 22 px and up: Tacit Sans Display, the face cut for titles (as the shell's)
        readonly property string display: "Tacit Sans Display"
        readonly property string titleFamily: ThemeSource.fonts.title ?? "Tacit Sans"   // font.title is the 18 px size
        readonly property string monospace: ThemeSource.fonts.monospace ?? "Tacit Code"
        readonly property string icons: "Material Symbols Rounded"
        // 450 with full hinting (owner's pick at true size, 2026-10-02): Regular read weak in Tacit Sans Compact
        readonly property var mainAxes: ({ "wght": 450, "wdth": 100 })
        // one step up from the first scale (2026-10-01, as the shell): 12-15 became 13-16 for this 142 PPI panel
        readonly property int smaller: 13
        // the rail's small grey text, as the approved render has it (PLAN.md 3.19): its words, labels and status line
        readonly property int tiny: 12
        readonly property int caption: 14
        readonly property int body: 15
        readonly property int small: 16
        readonly property int normal: 16
        readonly property int large: 17
        readonly property int title: 18
    }
    // Motion: the shell's tokens (tacit-shell Appearance.animationCurves, from caelestia), the ones Files moves
    // with. Every animation goes through Anim or CAnim (PLAN.md 6).
    readonly property QtObject anim: QtObject {
        readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // 350 ms
        readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // 500 ms
        readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1] // 650 ms
        readonly property var expressiveFastEffects: [0.31, 0.94, 0.34, 1.00, 1, 1] // 150 ms
        readonly property var expressiveDefaultEffects: [0.34, 0.80, 0.34, 1.00, 1, 1] // 200 ms
        readonly property var expressiveSlowEffects: [0.34, 0.88, 0.34, 1.00, 1, 1] // 300 ms
        readonly property var emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property var standard: [0.2, 0, 0, 1, 1, 1]
        readonly property int expressiveFastSpatialDuration: 350
        readonly property int expressiveDefaultSpatialDuration: 500
        readonly property int expressiveSlowSpatialDuration: 650
        readonly property int expressiveFastEffectsDuration: 150
        readonly property int expressiveDefaultEffectsDuration: 200
        readonly property int expressiveSlowEffectsDuration: 300
        readonly property int smallDuration: 200
        readonly property int normalDuration: 400
        readonly property int largeDuration: 600
        readonly property int extraLargeDuration: 1000
    }

    function transparentize(color, percentage) {
        const c = Qt.color(color);
        return Qt.rgba(c.r, c.g, c.b, c.a * (1 - percentage));
    }
    function mix(color1, color2, percentage) {
        const c1 = Qt.color(color1), c2 = Qt.color(color2);
        return Qt.rgba(percentage * c1.r + (1 - percentage) * c2.r, percentage * c1.g + (1 - percentage) * c2.g,
                       percentage * c1.b + (1 - percentage) * c2.b, percentage * c1.a + (1 - percentage) * c2.a);
    }
    // `top` laid over `bottom`, both translucent, as one colour (a Frost tint of two layers)
    function over(top, bottom) {
        const t = Qt.color(top), b = Qt.color(bottom);
        const a = t.a + b.a * (1 - t.a);
        const ch = (x, y) => a > 0 ? (x * t.a + y * b.a * (1 - t.a)) / a : 0;
        return Qt.rgba(ch(t.r, b.r), ch(t.g, b.g), ch(t.b, b.b), a);
    }
    // Tacit's kit (the shell's modules/common/Tacit.qml, 2026-10-08), measured on Opsis's own window ground: inks by
    // APCA contrast (emphasis by brightness, never by opacity); colour by meaning (the accent for the default, safe
    // action and a cause, the error role for an action that risks something); a slab raised from the ground. All of
    // it follows the wallpaper's palette.
    function apcaLc(text, ground) {
        const y = c => {
            const q = Qt.color(c);
            const v = 0.2126729 * Math.pow(q.r, 2.4) + 0.7151522 * Math.pow(q.g, 2.4) + 0.0721750 * Math.pow(q.b, 2.4);
            return v > 0.022 ? v : v + Math.pow(0.022 - v, 1.414);
        };
        const yt = y(text), yb = y(ground);
        if (yb > yt) {
            const s = (Math.pow(yb, 0.56) - Math.pow(yt, 0.57)) * 1.14;
            return s < 0.1 ? 0 : (s - 0.027) * 100;
        }
        const s = (Math.pow(yb, 0.65) - Math.pow(yt, 0.62)) * 1.14;
        return s > -0.1 ? 0 : (s + 0.027) * 100;
    }
    function inkFor(lc) {
        const ground = terminal, ink = m3onBackground;
        const far = Qt.color(ground).hslLightness < 0.5 ? "#ffffff" : "#000000";
        const at = t => t <= 1 ? mix(ink, ground, t) : mix(far, ink, t - 1);
        let lo = 0, hi = 2;
        for (let i = 0; i < 18; i++) {
            const mid = (lo + hi) / 2;
            if (Math.abs(apcaLc(at(mid), ground)) < lc)
                lo = mid;
            else
                hi = mid;
        }
        return at(hi);
    }
    readonly property color inkMain: inkFor(92)
    readonly property color inkSec: mix(inkMain, inkFor(75), 0.25)
    readonly property color inkMeta: mix(inkFor(75), inkFor(60), 0.4)
    readonly property color inkFaint: inkFor(46)
    readonly property color accent: primary
    readonly property color onAccent: role("on_primary", "#422b20")
    readonly property color risk: error
    readonly property color raised: mix(inkMain, terminal, 0.11)
    readonly property color raisedHot: mix(inkMain, terminal, 0.17)
    // `fg` toward `bg` as far as it keeps APCA Lc `lc` on `bg`: a quieter line in the same ink
    function quieter(fg, bg, lc) {
        let lo = 0, hi = 1;
        for (let i = 0; i < 16; i++) {
            const mid = (lo + hi) / 2;
            if (Math.abs(apcaLc(mix(fg, bg, mid), bg)) >= lc)
                hi = mid;
            else
                lo = mid;
        }
        return mix(fg, bg, hi);
    }

    // WCAG contrast ratio of `fg` drawn at `alpha` over the opaque `bg`
    function contrast(fg, alpha, bg) {
        const f = Qt.color(fg), b = Qt.color(bg);
        const lin = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        const lum = (r, g, bl) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(bl);
        const l1 = lum(alpha * f.r + (1 - alpha) * b.r, alpha * f.g + (1 - alpha) * b.g, alpha * f.b + (1 - alpha) * b.b);
        const l2 = lum(b.r, b.g, b.b);
        return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
    }
    function solveOverlayColor(baseColor, targetColor, overlayOpacity) {
        const bc = Qt.color(baseColor), tc = Qt.color(targetColor);
        const invA = 1.0 - overlayOpacity;
        const clamp01 = v => Math.max(0, Math.min(1, v));
        return Qt.rgba(clamp01((tc.r - bc.r * invA) / overlayOpacity), clamp01((tc.g - bc.g * invA) / overlayOpacity),
                       clamp01((tc.b - bc.b * invA) / overlayOpacity), overlayOpacity);
    }
}
