import QtQuick
import Quickshell

//  macOS-style toggle switch. on/off, click area 44x28 — big enough
//  to hit, small enough to stay compact.

Rectangle {
    id: toggle

    property bool checked: false
    signal toggled()

    width: 44
    height: 26
    radius: 13
    color: checked ? Theme.accent : Theme.track
    border.width: 0

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        id: knob
        width: 22
        height: 22
        radius: 11
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: toggle.checked ? toggle.width - width - 2 : 2

        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingType } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled()
    }
}
