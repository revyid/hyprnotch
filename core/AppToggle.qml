import QtQuick
import Quickshell

//  macOS-style toggle switch. on/off, click area 44x28 — big enough
//  to hit, small enough to stay compact.
//
//  r28 micro-interaction: the knob SQUISHES like the real macOS switch —
//  it stretches wide when pushing right and narrows when pulling back,
//  while the travel eases out. Pointer feedback is captured through a
//  HoverHandler-free pressed alias so keyboard-driven toggles keep
//  their static geometry.

Rectangle {
    id: toggle

    property bool checked: false
    signal toggled()

    width: 44
    height: 26
    radius: 13
    color: checked ? Theme.accent : Theme.track
    border.width: 0

    //  true while the pointer is down on the switch — drives the squish.
    property bool pressFx: false

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        id: knob
        width: toggle.pressFx ? (toggle.checked ? 26 : 18) : 22
        height: 22
        radius: 11
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: toggle.checked ? toggle.width - width - 2 : 2

        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingType } }
        Behavior on width { NumberAnimation { duration: 180; easing.type: Theme.easingType } }
        scale: toggle.pressFx ? 1.05 : 1

        Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: toggle.pressFx = true
        onReleased: toggle.pressFx = false
        onCanceled: toggle.pressFx = false
        onClicked: toggle.toggled()
    }
}
