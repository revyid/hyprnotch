import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

//  Power & battery — ONE menu, macOS System Settings DNA.
//
//  · Battery header: live %, state, watts, estimate-style bar
//  · Power profile segmented control (powerprofilesctl)
//  · Session grid: Lock / Sleep / Logout / Restart / Shut Down —
//    destructive actions use macOS hold-to-confirm (a ring fills
//    while you hold; release early = nothing happens)
//  · "About This Mac" entry at the bottom

Item {
    id: powerCard

    readonly property int pad: 14

    //  Island contract
    property int prefWidth: 380
    implicitHeight: inner.implicitHeight + pad * 2

    Column {
        id: inner
        x: powerCard.pad
        y: powerCard.pad
        width: parent.width - powerCard.pad * 2
        spacing: 12

        //  ── Battery header ────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: SysMon.batteryPresent ? 76 : 0
            radius: 14
            visible: SysMon.batteryPresent
            color: Theme.withAlpha(Theme.ink, 0.05)

            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                //  Ring gauge
                Item {
                    width: 52
                    height: 52
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: ring
                        anchors.fill: parent
                        antialiasing: true

                        onPaint: {
                            const ctx = ring.getContext("2d")
                            ctx.reset()
                            const cx = ring.width / 2, cy = ring.height / 2
                            const r = Math.min(cx, cy) - 4
                            ctx.lineWidth = 5
                            ctx.lineCap = "round"

                            //  track
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.strokeStyle = "rgba(255,255,255,0.08)"
                            ctx.stroke()

                            //  value arc
                            const frac = Math.min(1, Math.max(0, SysMon.batteryPct / 100))
                            const start = -Math.PI / 2
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, start, start + Math.PI * 2 * frac)
                            ctx.strokeStyle = SysMon.batteryCharging ? "#30d158"
                                : (SysMon.batteryPct <= 15 ? "#ff453a"
                                : (SysMon.batteryPct <= 30 ? "#ffd60a" : "#0a84ff"))
                            ctx.stroke()
                        }
                        Connections {
                            target: SysMon
                            function onBatteryPctChanged() { ring.requestPaint() }
                            function onBatteryChargingChanged() { ring.requestPaint() }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: SysMon.batteryPct + "%"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    width: parent.width - 64

                    Text {
                        text: SysMon.batteryCharging
                            ? "Charging · " + SysMon.formatWatts(SysMon.batteryWatts)
                            : (SysMon.batteryPct <= 15 ? "Low Battery" : "On Battery")
                        color: SysMon.batteryPct <= 15 && !SysMon.batteryCharging ? Theme.red : Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "Battery health managed by the system · " + SysMon.batteryPct + "% remaining"
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }
        }

        //  ── Power profile ─────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6
            visible: Power.profileAvailable

            Text {
                text: "Energy Mode"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 10
                color: Theme.withAlpha(Theme.ink, 0.06)

                Row {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 3

                    Repeater {
                        model: [
                            { id: "power-saver", label: "Low Power",  glyph: Icons.leaf,    tint: Theme.green },
                            { id: "balanced",    label: "Balanced",   glyph: Icons.balance, tint: Theme.blue },
                            { id: "performance", label: "High Power", glyph: Icons.gauge,   tint: Theme.orange }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 6) / 3
                            height: parent.height
                            radius: 8
                            color: Power.profile === modelData.id
                                ? Theme.withAlpha(modelData.tint, 0.25)
                                : (profArea.containsMouse ? Theme.surfaceHi : "transparent")
                            scale: profArea.pressed ? 0.95 : 1

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 11
                                    colorVal: Power.profile === modelData.id ? modelData.tint : Theme.muted
                                    glyph: modelData.glyph
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: Power.profile === modelData.id ? Theme.ink : Theme.muted
                                    font.family: Theme.uiFont
                                    font.pixelSize: 10
                                    font.weight: Power.profile === modelData.id ? Font.DemiBold : Font.Medium
                                }
                            }

                            MouseArea {
                                id: profArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Power.setProfile(modelData.id)
                                    Notifs.toast("Energy Mode", "Switched to " + modelData.label)
                                }
                            }
                        }
                    }
                }
            }
        }

        //  ── Session actions ───────────────────────────────────────
        Text {
            text: "Session"
            color: Theme.muted
            font.family: Theme.uiFont
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }

        Row {
            width: parent.width
            spacing: 8

            SessionButton {
                width: (parent.width - 32) / 5
                label: "Lock"
                glyph: Icons.lock
                tint: Theme.blue
                onFired: {
                    UiState.closeAll()
                    Power.lock()
                }
            }
            SessionButton {
                width: (parent.width - 32) / 5
                label: "Sleep"
                glyph: Icons.moon
                tint: Theme.purple
                onFired: {
                    UiState.closeAll()
                    Power.suspend()
                }
            }
            SessionButton {
                width: (parent.width - 32) / 5
                label: "Logout"
                glyph: Icons.logout
                tint: Theme.teal
                holdToConfirm: true
                onFired: Power.logout()
            }
            SessionButton {
                width: (parent.width - 32) / 5
                label: "Restart"
                glyph: Icons.refresh
                tint: Theme.yellow
                holdToConfirm: true
                onFired: Power.reboot()
            }
            SessionButton {
                width: (parent.width - 32) / 5
                label: "Shut Down"
                glyph: Icons.power
                tint: Theme.red
                holdToConfirm: true
                onFired: Power.shutdown()
            }
        }

        //  ── About entry ───────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 34
            radius: 10
            color: aboutArea.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.ink, 0.06)
            scale: aboutArea.pressed ? 0.97 : 1

            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 13
                    colorVal: Theme.ink
                    glyph: Icons.apple
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "About This Machine"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Item { width: parent.width - 190; height: 1 }

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 10
                    colorVal: Theme.muted
                    glyph: Icons.chevronRight
                }
            }

            MouseArea {
                id: aboutArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: UiState.openPopup("about")
            }
        }
    }
}
