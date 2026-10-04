import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../core"
import "../services"

//  One dock icon — REAL macOS anatomy:
//
//  · A real application icon (theme-resolved URL) with a soft drop
//    shadow — no gray tile behind it, icons float like Big Sur+.
//  · Icons WITHOUT a resolvable image fall back to a subtle glass
//    tile + glyph (legacy custom pins).
//  · The running dot lives UNDER the icon: white = focused, dim =
//    merely running.
//  · Magnification: `size` grows from the Dock's neighbor falloff,
//    baseline stays glued to the shelf.
//  · Click: press-squish + launch bounce (two decaying hops).
//  · Tooltip floats above with the app name.
//
//  NOT readonly `size`: it carries a Behavior (animations write to it).

Item {
    id: dockIcon

    property bool isApp: true
    property string iconSource: ""
    property string glyphChar: ""
    property string label: ""
    property bool running: false
    property bool active: false
    property int iconSize: 44
    property real grow: 0
    property int index: -1
    signal clicked()

    //  NOT readonly: it carries a Behavior (animations write to it).
    property real size: iconSize + grow

    width: size
    height: size + 9          //  headroom for the running dot below
    Layout.alignment: Qt.AlignBottom

    Behavior on size { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    //  ── Launch bounce ─────────────────────────────────────────────
    //  Two decaying hops, macOS style. Runs from Dock on a real launch
    //  click; never loops, never fights the size animation (different
    //  property — a translate, not the layout size).
    property real bounceY: 0

    SequentialAnimation {
        id: bounceAnim

        NumberAnimation { target: dockIcon; property: "bounceY"; to: -dockIcon.size * 0.32; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: dockIcon; property: "bounceY"; to: 0; duration: 170; easing.type: Easing.InQuad }
        NumberAnimation { target: dockIcon; property: "bounceY"; to: -dockIcon.size * 0.16; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: dockIcon; property: "bounceY"; to: 0; duration: 140; easing.type: Easing.InQuad }

        onStopped: dockIcon.bounceY = 0
    }

    function bounce() { bounceAnim.restart() }

    transform: Translate { y: dockIcon.bounceY }

    scale: hoverArea.pressed ? 0.88 : 1
    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

    //  ── The icon ──────────────────────────────────────────────────
    Item {
        id: iconSlot
        width: dockIcon.size
        height: dockIcon.size
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        //  Real app icon — floats free, drop shadow underneath.
        Image {
            id: appIcon
            anchors.fill: parent
            visible: dockIcon.iconSource.length > 0 && status !== Image.Error
            source: dockIcon.iconSource
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
        }

        MultiEffect {
            anchors.fill: appIcon
            source: appIcon
            visible: appIcon.visible
            autoPaddingEnabled: false
            shadowEnabled: true
            shadowBlur: 0.55
            shadowVerticalOffset: 5
            shadowHorizontalOffset: 0
            shadowColor: Theme.withAlpha("#000000", 0.55)
            shadowScale: 1.02
        }

        //  Fallback glass tile for pins without a resolvable icon.
        Rectangle {
            anchors.fill: parent
            radius: dockIcon.size * 0.24
            visible: dockIcon.glyphChar.length > 0
            color: hoverArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.16)
                : (dockIcon.active ? Theme.withAlpha(Theme.ink, 0.12) : Theme.withAlpha(Theme.ink, 0.08))
            border.width: 1
            border.color: Theme.withAlpha(Theme.ink, hoverArea.containsMouse ? 0.20 : 0.10)

            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.withAlpha(Theme.ink, 0.08) }
                    GradientStop { position: 0.5; color: "transparent" }
                }
            }

            Glyph {
                anchors.centerIn: parent
                size: parent.width * 0.46
                colorVal: dockIcon.active ? Theme.accent : Theme.ink
                glyph: dockIcon.glyphChar
            }
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dockIcon.clicked()
            onContainsMouseChanged: dockIcon.tileHovered(containsMouse)
        }
    }

    //  ── Running dot, under the tile (macOS position) ──────────────
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: dockIcon.active ? 6 : 4
        height: dockIcon.active ? 6 : 4
        radius: 3
        color: dockIcon.active ? Theme.ink : Theme.withAlpha(Theme.ink, 0.55)
        visible: dockIcon.running || dockIcon.active
        opacity: visible ? 1 : 0

        Behavior on width { NumberAnimation { duration: Theme.animFast } }
        Behavior on height { NumberAnimation { duration: Theme.animFast } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    //  ── Tooltip ───────────────────────────────────────────────────
    Rectangle {
        id: tip
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        width: tipText.implicitWidth + 16
        height: 22
        radius: 7
        color: Theme.withAlpha(Theme.islandBg, 0.95)
        border.width: 1
        border.color: Theme.withAlpha(Theme.ink, 0.12)
        visible: hoverArea.containsMouse && label.length > 0
        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.85

        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

        Text {
            id: tipText
            anchors.centerIn: parent
            text: dockIcon.label
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 10
        }
    }

    //  Report hover to the Dock (magnification source of truth)
    signal tileHovered(bool hovered)
}
