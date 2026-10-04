import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

//  Wallpaper picker — swww under the hood.
//
//  A scrolling grid of real thumbnails, one tap to apply (with swww
//  transition), a transition-style selector, a custom-folder path and
//  a refresh. The current wallpaper carries a check ring.

Item {
    id: wpCard

    readonly property int pad: 14
    readonly property int thumbW: 104
    readonly property int thumbH: 62

    //  Island contract
    property int prefWidth: 420
    implicitHeight: inner.implicitHeight + pad * 2

    readonly property var transitions: [
        { id: "grow",   label: "Grow" },
        { id: "outer",  label: "Outer" },
        { id: "wipe",   label: "Wipe" },
        { id: "fade",   label: "Fade" },
        { id: "simple", label: "Simple" },
        { id: "random", label: "Random" }
    ]

    Column {
        id: inner
        x: wpCard.pad
        y: wpCard.pad
        width: parent.width - wpCard.pad * 2
        spacing: 10

        //  ── Header ────────────────────────────────────────────────
        RowLayout {
            width: parent.width
            spacing: 8

            Glyph {
                size: 13
                colorVal: Theme.accent
                glyph: Icons.image
            }
            Text {
                text: "Wallpaper"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                text: Wallpaper.available ? "" : "· swww not found"
                color: Theme.orange
                font.family: Theme.uiFont
                font.pixelSize: 9
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                width: 24; height: 24; radius: 12
                color: folderArea.containsMouse ? Theme.surfaceHi : "transparent"
                scale: folderArea.pressed ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                Glyph {
                    anchors.centerIn: parent
                    size: 11
                    colorVal: Theme.ink
                    glyph: Icons.folder
                }
                MouseArea {
                    id: folderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Wallpaper.openFolder()
                }
            }
            Rectangle {
                width: 24; height: 24; radius: 12
                color: rescanArea.containsMouse ? Theme.surfaceHi : "transparent"
                scale: rescanArea.pressed ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                Glyph {
                    anchors.centerIn: parent
                    size: 11
                    colorVal: Theme.ink
                    glyph: Icons.refresh
                }
                RotationAnimation on rotation {
                    running: Wallpaper.scanning
                    from: 0; to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
                MouseArea {
                    id: rescanArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Wallpaper.scan()
                }
            }
        }

        //  ── Transition selector ───────────────────────────────────
        Row {
            width: parent.width
            spacing: 5

            Repeater {
                model: wpCard.transitions

                delegate: Rectangle {
                    required property var modelData
                    width: tLabel.implicitWidth + 16
                    height: 20
                    radius: 10
                    color: Wallpaper.transition === modelData.id
                        ? Theme.withAlpha(Theme.accent, 0.30)
                        : (tArea.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.ink, 0.07))
                    border.width: Wallpaper.transition === modelData.id ? 1 : 0
                    border.color: Theme.accent
                    scale: tArea.pressed ? 0.92 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                    Text {
                        id: tLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: Wallpaper.transition === modelData.id ? Theme.ink : Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                        font.weight: Wallpaper.transition === modelData.id ? Font.DemiBold : Font.Medium
                    }
                    MouseArea {
                        id: tArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set("wallpaper.transition", modelData.id)
                    }
                }
            }
        }

        //  ── Thumbnail grid ────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: Math.min(300, Math.max(80, gridHeight()))
            radius: 10
            color: Theme.withAlpha(Theme.ink, 0.04)

            function gridHeight() {
                const n = Wallpaper.files.length
                if (n === 0)
                    return 80
                const cols = Math.max(1, Math.floor((wpCard.prefWidth - wpCard.pad * 2 - 10) / (wpCard.thumbW + 8)))
                const rows = Math.ceil(n / cols)
                return rows * (wpCard.thumbH + 8) + 16
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                contentWidth: width
                contentHeight: grid.implicitHeight

                Grid {
                    id: grid
                    width: parent.width
                    columns: Math.max(1, Math.floor((width + 8) / (wpCard.thumbW + 8)))
                    spacing: 8

                    Repeater {
                        model: Wallpaper.files

                        delegate: Item {
                            id: thumb
                            required property string modelData
                            readonly property bool current: Wallpaper.current === modelData

                            width: wpCard.thumbW
                            height: wpCard.thumbH + 14

                            Rectangle {
                                id: frame
                                width: wpCard.thumbW
                                height: wpCard.thumbH
                                radius: 8
                                clip: true
                                color: Theme.track
                                border.width: thumb.current ? 2 : (thumbArea.containsMouse ? 1 : 0)
                                border.color: thumb.current ? Theme.accent : Theme.withAlpha(Theme.ink, 0.35)

                                scale: thumbArea.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }
                                Behavior on border.width { NumberAnimation { duration: Theme.animFast } }
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                                Image {
                                    anchors.fill: parent
                                    source: thumb.modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }

                                //  check badge on the current one
                                Rectangle {
                                    visible: thumb.current
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 4
                                    width: 16; height: 16; radius: 8
                                    color: Theme.accent

                                    Glyph {
                                        anchors.centerIn: parent
                                        size: 8
                                        colorVal: "#ffffff"
                                        glyph: Icons.check
                                    }
                                }

                                MouseArea {
                                    id: thumbArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Wallpaper.apply(thumb.modelData)
                                }
                            }

                            Text {
                                anchors.top: frame.bottom
                                anchors.topMargin: 2
                                width: wpCard.thumbW
                                text: Wallpaper.fileName(thumb.modelData)
                                color: thumb.current ? Theme.ink : Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 8
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: Wallpaper.files.length === 0
                text: Wallpaper.scanning ? "Scanning…" : "No wallpapers found\n(drop files in ~/Pictures)"
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Text {
            visible: !Wallpaper.available
            text: "Install swww to enable live transitions:  paru -S swww"
            color: Theme.dim
            font.family: Theme.uiFont
            font.pixelSize: 9
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
