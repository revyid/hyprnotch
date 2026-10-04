import QtQuick
import QtQuick.Shapes

//  The island silhouette: rounded body + two INVERTED corner wings that
//  melt it into the screen edge — the signature macOS Dynamic Island shape.
//
//  Ported from the original island path: `u` runs along the edge, `v` goes
//  into the screen. For a top-edge island: x = u, y = v.
//
//  Needs 2*(wing + radius) of length so the path closes: g is clamped by
//  w/6 and r by w/3 - g, exactly like the original.

Shape {
    id: silhouette

    //  How much each inverted corner bites inward from the ends.
    property real wing: 16

    //  Corner rounding of the body's two outer corners.
    property real bodyRadius: 20

    property color fill: Theme.islandBg

    //  CurveRenderer would drop the inverted corners — antialias with MSAA.
    antialiasing: true
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    ShapePath {
        id: trace

        fillColor: silhouette.fill
        strokeWidth: 0
        strokeColor: "transparent"

        readonly property real w: silhouette.width
        readonly property real h: silhouette.height
        readonly property real g: Math.max(0, Math.min(silhouette.wing, trace.h / 2, trace.w / 6))
        readonly property real r: Math.max(0, Math.min(silhouette.bodyRadius, trace.h / 2, trace.w / 3 - trace.g))

        startX: 0
        startY: 0

        //  inverted corner, start side
        PathArc {
            x: trace.g
            y: trace.g
            radiusX: trace.g
            radiusY: trace.g
            direction: PathArc.Clockwise
        }

        PathLine { x: trace.g; y: trace.h - trace.r }

        //  body corner, same side
        PathArc {
            x: trace.g + trace.r
            y: trace.h
            radiusX: trace.r
            radiusY: trace.r
            direction: PathArc.Counterclockwise
        }

        PathLine { x: trace.w - trace.g - trace.r; y: trace.h }

        //  body corner, other side
        PathArc {
            x: trace.w - trace.g
            y: trace.h - trace.r
            radiusX: trace.r
            radiusY: trace.r
            direction: PathArc.Counterclockwise
        }

        PathLine { x: trace.w - trace.g; y: trace.g }

        //  inverted corner, end side
        PathArc {
            x: trace.w
            y: 0
            radiusX: trace.g
            radiusY: trace.g
            direction: PathArc.Clockwise
        }

        PathLine { x: 0; y: 0 }
    }
}
