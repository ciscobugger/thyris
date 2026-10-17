import QtQuick
import Browser

// The ground of a surface over the page: the desktop's frost, as Hyprland's xray blur gives the shell's
// panels. It shows the part of the blurred wallpaper (its window's Main.frostSource, made once per wallpaper;
// a texture serves only the window it is drawn in) lying under this item on the screen, `tint` over it, clipped
// to the rounded rect. One textured quad a frame; it follows the item as the item or any ancestor moves.
// Children draw over it.
ShaderEffect {
    id: frost

    property color tint: Theme.colPanelFrost
    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomRightRadius: radius
    property real bottomLeftRadius: radius

    // where the item lies on the screen; reading every ancestor's x and y re-evaluates it when one moves, and
    // windowPos when Hyprland answers where the windows are
    readonly property point screenPos: {
        for (let p = frost; p; p = p.parent)
            p.x + p.y;
        Backdrop.windowPos;
        const s = frost.mapToItem(null, 0, 0), at = Backdrop.posOf(frost.Window.window);
        return Qt.point(at.x + s.x, at.y + s.y);
    }

    readonly property Item source: frost.Window.window && frost.Window.window.frostSource ? frost.Window.window.frostSource : Backdrop.texture
    readonly property vector2d screen: Qt.vector2d(Backdrop.screenSize.width, Backdrop.screenSize.height)
    readonly property vector4d area: Qt.vector4d(screenPos.x / screen.x, screenPos.y / screen.y, width / screen.x, height / screen.y)
    readonly property vector2d itemSize: Qt.vector2d(width, height)
    readonly property vector4d radii: Qt.vector4d(topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius)
    // a vector, so the shader gets plain, unpremultiplied rgba
    readonly property vector4d tintColor: Qt.vector4d(tint.r, tint.g, tint.b, tint.a)
    readonly property real noise: 0.015     // Hyprland decoration:blur:noise
    // 0..1: how much of what Hyprland's window opacity (Theme.windowOpacity) lets through to be taken back out, so the
    // surface shows exactly its tint on the screen, as the shell's opaque notch does; 0 leaves it to the window's
    // opacity (the 15 % of a warm wallpaper read brown on the search card and bar, 2026-10-02)
    property real solid: 0
    readonly property real through: Math.max(0, Math.min(0.95, solid * (1 - Theme.windowOpacity)))

    fragmentShader: "../shaders/frost.frag.qsb"
    // the window may have moved since the last surface opened
    onVisibleChanged: if (visible) Backdrop.refresh()
}
