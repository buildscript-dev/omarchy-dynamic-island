import QtQuick
import QtQuick.Shapes

// The notch silhouette. A body hanging from the top screen edge with
// rounded bottom corners (rb), plus two concave "ears" (rt) where it meets
// the top edge — the fillet that makes a MacBook notch look milled out of
// the bezel instead of pasted on top of it.
//
//        ______________________________________
//       ╲  ←rt                          rt→  ╱      y = 0
//        │                                  │
//        │                                  │
//         ╲___rb____________________rb_____╱        y = bodyHeight
//
// The item is bodyWidth + 2·rt wide; the body starts at x = rt.
Shape {
  id: shape

  property real bodyWidth: 200
  property real bodyHeight: 26
  property real rb: 10
  property real rt: 6
  property color fillColor: "black"

  readonly property real _rb: Math.max(0, Math.min(rb, bodyHeight / 2, bodyWidth / 2))
  readonly property real _rt: Math.max(0, Math.min(rt, bodyHeight - _rb))

  width: bodyWidth + 2 * _rt
  height: bodyHeight
  preferredRendererType: Shape.CurveRenderer
  asynchronous: false

  ShapePath {
    fillColor: shape.fillColor
    strokeWidth: -1
    strokeColor: "transparent"

    startX: 0
    startY: 0

    // Left ear: concave fillet from the top edge down into the body side.
    PathArc {
      x: shape._rt
      y: shape._rt
      radiusX: shape._rt
      radiusY: shape._rt
      direction: PathArc.Clockwise
    }
    PathLine { x: shape._rt; y: shape.bodyHeight - shape._rb }
    // Bottom-left corner.
    PathArc {
      x: shape._rt + shape._rb
      y: shape.bodyHeight
      radiusX: shape._rb
      radiusY: shape._rb
      direction: PathArc.Counterclockwise
    }
    PathLine { x: shape._rt + shape.bodyWidth - shape._rb; y: shape.bodyHeight }
    // Bottom-right corner.
    PathArc {
      x: shape._rt + shape.bodyWidth
      y: shape.bodyHeight - shape._rb
      radiusX: shape._rb
      radiusY: shape._rb
      direction: PathArc.Counterclockwise
    }
    PathLine { x: shape._rt + shape.bodyWidth; y: shape._rt }
    // Right ear.
    PathArc {
      x: shape.bodyWidth + 2 * shape._rt
      y: 0
      radiusX: shape._rt
      radiusY: shape._rt
      direction: PathArc.Clockwise
    }
    PathLine { x: 0; y: 0 }
  }
}
