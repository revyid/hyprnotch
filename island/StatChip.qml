import QtQuick
import "../core"

//  Tiny rounded chip: glyph + short text (temps, uptime, counters).

Rectangle {
    id: chip

    property string glyph: ""
    property string text: ""
    property color tint: Theme.muted

    width: chipRow.implicitWidth + 16
    height: 20
    radius: 10
    color: Theme.withAlpha(Theme.ink, 0.08)

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            size: 10
            colorVal: chip.tint
            glyph: chip.glyph
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 9
            font.weight: Font.Medium
        }
    }
}
