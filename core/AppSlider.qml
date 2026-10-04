import QtQuick

//  Compact custom slider (no Controls dependency = predictable style).
//  Left-click / drag sets value; used for volume, brightness, media.

Rectangle {
    id: slider

    property real from: 0
    property real to: 100
    property real value: 50
    signal valueEdited(real newValue)

    height: 30
    radius: height / 2
    color: Theme.track

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
    }

    //  Thumb
    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(6, Math.min(slider.width - width - 6,
                slider.width * slider.frac - width / 2))
        visible: dragArea.containsMouse || dragArea.pressed

        Behavior on x { NumberAnimation { duration: 60 } }
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
