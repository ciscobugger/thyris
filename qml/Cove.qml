import QtQuick
import QtQuick.Shapes

// A sheet docked into the page area's left edge, drawn as one silhouette with what it docks to: the body rounded on its
// free side, a concave cove above and below that flares it into the edge, so nothing meets the edge with a seam (Tacit's
// DockedRect, edge "left", tacit-shell modules/common/widgets). Fill the body box; the coves reach `fillet` px past it.
Item {
    id: cove
    property real cornerRadius: 20
    property real fillet: 18
    property color color: Theme.terminal

    Shape {
        x: 0
        y: -cove.fillet
        width: cove.width
        height: cove.height + 2 * cove.fillet
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: cove.color
            strokeWidth: -1
            PathSvg {
                // along the edge u (down), away from it v (right): the cove into the body, its free corners, the cove out
                path: {
                    const W = cove.height, H = cove.width, s = cove.fillet, r = Math.min(cove.cornerRadius, H / 2, W / 2);
                    const p = (u, v) => v + " " + u;
                    const arc = (rad, sweep, u, v) => "A " + rad + " " + rad + " 0 0 " + sweep + " " + p(u, v);
                    return "M " + p(0, 0) + " " + arc(s, 0, s, s) + " L " + p(s, H - r) + " " + arc(r, 1, s + r, H)
                        + " L " + p(s + W - r, H) + " " + arc(r, 1, s + W, H - r) + " L " + p(s + W, s) + " " + arc(s, 0, 2 * s + W, 0) + " Z";
                }
            }
        }
    }
}
