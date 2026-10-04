import QtQuick
import "../core"
import "../services"

//  The HOVER PEEK — what the notch shows when you brush it, before any
//  click. macOS reads this as "the island noticing you":
//
//      · media mini (if a player is running) with live progress
//      · the two most recent notifications (tap → activate)
//      · live CPU / RAM mini bars + network rate
//      · plugin chips, one per installed plugin
//
//  Everything is a tappable shortcut into its full island view. The
//  island reads prefWidth + implicitHeight (the same contract as the
//  popup cards) and springs to fit.

Item {
    id: peek

    readonly property int pad: 12
    readonly property int rowGap: 8

    //  Island contract
    property int prefWidth: 460
    implicitHeight: body.height + pad * 2

    //  ── sizing logic ──────────────────────────────────────────────
    readonly property bool hasMedia: Media.hasPlayer
    readonly property bool showCava: Media.playing && Cava.enabled
    readonly property int notifRows: Math.min(Notifs.history.length, 2)
    readonly property bool showNotifs: notifRows > 0
    readonly property bool showStats: Config.get("island.peekEnabled", true)
    readonly property bool hasPlugins: Plugins.active.length > 0

    function heightOf(rows) {
        let h = 0
        if (hasMedia) h += 46 + rowGap
        if (showNotifs) h += notifRows * 34 + (notifRows - 1) * 4 + rowGap
        if (showStats) h += 40 + rowGap
        if (hasPlugins) h += 26 + rowGap
        return h
    }

    Column {
        id: body
        x: peek.pad
        y: peek.pad
        width: parent.width - peek.pad * 2
        spacing: peek.rowGap

        //  ── Media mini ────────────────────────────────────────────
        Item {
            visible: peek.hasMedia
            width: parent.width
            height: visible ? 46 : 0

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Theme.withAlpha(Theme.ink, 0.07)
            }

            //  Background tap → control center. Declared BEFORE the row
            //  so the play button (deeper, later) wins its own clicks.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: UiState.openPopup("controlCenter")
            }

            Row {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10

                //  Cover art (or glyph fallback)
                Rectangle {
                    width: 30
                    height: 30
                    radius: 6
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.track

                    Image {
                        anchors.fill: parent
                        visible: Media.artUrl.length > 0
                        source: visible ? Media.artUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Glyph {
                        anchors.centerIn: parent
                        visible: Media.artUrl.length === 0
                        size: 14
                        colorVal: Theme.muted
                        glyph: Icons.music
                    }
                }

                Column {
                    width: parent.width - 30 - 32 - 20 - (peek.showCava ? 78 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: Media.title
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Item {
                        width: parent.width
                        height: 3
                        Rectangle {
                            anchors.fill: parent
                            radius: 1.5
                            color: Theme.track
                        }
                        Rectangle {
                            width: parent.width * Math.min(1, Math.max(0, Media.progress))
                            height: parent.height
                            radius: 1.5
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.Linear } }
                        }
                    }
                    Text {
                        width: parent.width
                        text: Media.artist
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                //  ── Live spectrum (r25): only while actually playing ──
                CavaBars {
                    visible: peek.showCava
                    opacity: visible ? 1 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    maxHeight: 22
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: playArea.containsMouse ? Theme.surfaceHi : "transparent"
                    scale: playArea.pressed ? 0.88 : 1

                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Glyph {
                        anchors.centerIn: parent
                        size: 13
                        colorVal: Theme.ink
                        glyph: Media.playing ? Icons.pause : Icons.play
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Media.playPause()
                    }
                }
            }
        }

        //  ── Recent notifications (top 2) ──────────────────────────
        Repeater {
            model: peek.showNotifs ? Notifs.history.slice(0, peek.notifRows) : []

            delegate: Item {
                id: notifEntry
                required property var modelData
                readonly property var entry: modelData
                width: parent.width
                height: 34

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: notifRowArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.10) : Theme.withAlpha(Theme.ink, 0.06)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.track

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                visible: entry.icon.length > 0
                                source: visible ? entry.icon : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Glyph {
                                anchors.centerIn: parent
                                visible: entry.icon.length === 0
                                size: 11
                                colorVal: Theme.muted
                                glyph: Icons.bell
                            }
                        }

                        Column {
                            width: parent.width - 20 - 30 - 24
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: entry.summary.length > 0 ? entry.app + " — " + entry.summary : entry.app
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: entry.body.length > 0
                                text: entry.body
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notifs.formatAge(entry.time)
                            color: Theme.dim
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                    }

                    MouseArea {
                        id: notifRowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Notifs.markSeen()
                            entry.activate()
                        }
                    }
                }
            }
        }

        //  ── Live stats mini row ───────────────────────────────────
        Item {
            visible: peek.showStats
            width: parent.width
            height: visible ? 40 : 0

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Theme.withAlpha(Theme.ink, 0.07)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 14

                    MiniStat {
                        label: "CPU"
                        pct: SysMon.cpuPct
                        sub: SysMon.cpuPct + "%"
                        width: (parent.width - 28 - (SysMon.batteryPresent ? 74 : 0)) / 2
                    }
                    MiniStat {
                        label: "MEM"
                        pct: SysMon.memPct
                        sub: SysMon.formatGb(SysMon.memUsedGb)
                        width: (parent.width - 28 - (SysMon.batteryPresent ? 74 : 0)) / 2
                    }
                    Column {
                        visible: SysMon.batteryPresent
                        width: 74
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Row {
                            spacing: 4
                            Glyph {
                                size: 11
                                anchors.verticalCenter: parent.verticalCenter
                                colorVal: SysMon.batteryCharging ? Theme.green : Theme.muted
                                glyph: Icons.batteryIcon(SysMon.batteryPct, SysMon.batteryCharging)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: SysMon.batteryPct + "%"
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }
                        Text {
                            text: SysMon.batteryCharging ? SysMon.formatWatts(SysMon.batteryWatts) : "discharging"
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 8
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: UiState.openPopup("stats")
            }
        }

        //  ── Plugin chips ──────────────────────────────────────────
        Row {
            visible: peek.hasPlugins
            width: parent.width
            height: visible ? 22 : 0
            spacing: 6

            Repeater {
                model: Plugins.active

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: chipRow.implicitWidth + 18
                    height: 22
                    radius: 11
                    color: chipArea.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.ink, 0.08)
                    scale: chipArea.pressed ? 0.93 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 5
                        Glyph {
                            size: 10
                            anchors.verticalCenter: parent.verticalCenter
                            colorVal: Theme.accent
                            glyph: modelData.icon
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Plugins.open(index)
                    }
                }
            }
        }
    }
}
