import QtQuick

//  Nerd Font glyph. Pass `glyph` (from Icons) — everything else optional.

Text {
    id: root

    property string glyph: "\uF111"
    property color colorVal: Theme.ink
    property real size: 14

    font.family: Theme.iconFont
    font.pixelSize: size
    color: colorVal
    text: root.glyph
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    renderType: Text.NativeRendering
}
