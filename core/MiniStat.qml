import QtQuick
import "../core"
import "../services"

//  One compact stat: glyph + label, thin bar, value underneath.
//  Used by the hover peek and the stats headers.

Item {
    id: stat

    property string label: ""
    property real pct: 0
    property string sub: ""
    property color tint: Theme.accent
    property string glyph: Icons.chip

    Column {
        anchors.fill: parent
        spacing: 4

        Row {
            spacing: 5
            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                size: 10
                colorVal: Theme.muted
                glyph: stat.glyph
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: stat.label
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }

        Item {
            width: parent.width
            height: 4
            Rectangle {
                anchors.fill: parent
                radius: 2
                color: Theme.track
            }
            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, stat.pct / 100))
                height: parent.height
                radius: 2
                color: stat.pct > 85 ? Theme.red : stat.tint

                Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            text: stat.sub
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 10
        }
    }
}
