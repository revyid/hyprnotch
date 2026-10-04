import QtQuick
import "../core"

//  One macOS-About spec row: quiet label on the left, value on the
//  right, hairline separator underneath. Fades + slides in with the
//  staggered reveal driven by AboutCard.

Item {
    id: row

    property string label: ""
    property string value: ""
    property real delay: 1

    height: 30

    opacity: delay
    transform: Translate { x: (1 - row.delay) * -14 }

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: Theme.muted
        font.family: Theme.uiFont
        font.pixelSize: 11
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: row.value
        color: Theme.ink
        font.family: Theme.uiFont
        font.pixelSize: 11
        font.weight: Font.Medium
        elide: Text.ElideMiddle
        width: parent.width * 0.62
        horizontalAlignment: Text.AlignRight
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.withAlpha(Theme.ink, 0.05)
    }
}
