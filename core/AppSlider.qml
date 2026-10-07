import QtQuick

//  Compact custom slider (no Controls dependency = predictable style).
//  Left-click / drag sets value; used for volume, brightness, media.
//
//  r28 micro-interactions: the thumb is now ALWAYS on (small when
//  idle, growing on hover/drag so the target reveals itself), the fill
//  carries a subtle lighter head while dragging, and the whole track
//  brightens on hover — every state animated, nothing jumps.

Rectangle {
    id: slider

    property real from: 0
    property real to: 100
    property real value: 50
    signal valueEdited(real newValue)

    height: 30
    radius: height / 2
    color: dragArea.containsMouse || dragArea.pressed
        ? Theme.withAlpha(Theme.ink, 0.14) : Theme.track

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    //  Filled portion
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(parent.height, parent.width * slider.frac)
        height: parent.height
        radius: parent.height / 2
        color: slider.value <= slider.from ? Theme.track : Theme.accent

        Behavior on width { NumberAnimation { duration: 60 } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    //  Thumb — always visible, grows toward the pointer
    Rectangle {
        width: dragArea.pressed ? 18 : (dragArea.containsMouse ? 16 : 10)
        height: width
        radius: width / 2
        color: "#ffffff"
        border.width: dragArea.pressed ? 3 : 0
        border.color: Theme.withAlpha(Theme.accent, 0.55)
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(6, Math.min(slider.width - width - 6,
                slider.width * slider.frac - width / 2))

        Behavior on x { NumberAnimation { duration: 60 } }
        Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on border.width { NumberAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        function apply(mouse) {
            const frac = Math.max(0, Math.min(1, mouse.x / slider.width))
            slider.valueEdited(slider.from + frac * (slider.to - slider.from))
        }

        onPressed: (mouse) => apply(mouse)
        onPositionChanged: (mouse) => { if (pressed) apply(mouse) }
        onWheel: (wheel) => {
            const step = (slider.to - slider.from) / 25
            slider.valueEdited(slider.value + (wheel.angleDelta.y > 0 ? step : -step))
        }
    }
}
