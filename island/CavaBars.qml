import QtQuick
import "../core"
import "../services"

//  CavaBars (r25) — the notch's audio spectrum, fed by services/Cava.qml.
//  A slim row of rounded bars growing from the bottom edge, accent
//  colored, with per-bar opacity following the level. Anything hosting
//  it decides visibility (usually Cava.active — i.e. only while a
//  player is actually playing).
//
//  Reusable knobs: count (defaults to the service's bar count),
//  barWidth, maxHeight, gap, and mono (ink instead of accent).

Row {
    id: cavaBars

    property int count: Cava.count
    property real barWidth: 3
    property int maxHeight: 20
    property real gap: 2
    property bool mono: false

    width: count * barWidth + (count - 1) * gap
    height: maxHeight
    spacing: gap

    Repeater {
        model: cavaBars.count

        Rectangle {
            id: bar

            required property int index

            readonly property real val: {
                const list = Cava.bars
                if (!list || index >= list.length)
                    return 0
                return Math.max(0, Math.min(1, list[index]))
            }

            width: cavaBars.barWidth
            radius: cavaBars.barWidth / 2
            anchors.bottom: parent.bottom
            color: cavaBars.mono ? Theme.ink : Theme.accent
            opacity: 0.4 + 0.6 * val
            height: 2 + val * (cavaBars.maxHeight - 2)

            Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
}
