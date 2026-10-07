import QtQuick
import "../core"
import "../services"

//  Live notification banners — INSIDE the island window, hanging just
//  below the pill. Replaces the old separate PanelWindow: everything
//  notification-shaped now lives in the notch surface.
//
//  Each banner: app icon, app — summary, body, action buttons, and a
//  per-banner lifetime timer (paused while hovered). Clicking the body
//  activates the notification's default action (or dismisses it); the
//  ✕ discards. Banners drop in with a small spring and fade with the
//  whole stack.

Item {
    id: banners

    //  Set by IslandWindow to the width the banner stack should use.
    property real preferredWidth: 380
    property bool active: Notifs.banners.length > 0 && !UiState.expanded

    width: preferredWidth
    height: visible ? list.implicitHeight : 0
    visible: opacity > 0.01

    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Column {
        id: list
        anchors.top: parent.top
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.banners

            delegate: Item {
                id: broot
                required property var modelData
                readonly property var entry: modelData
                readonly property bool hovered: hoverArea.containsMouse

                width: list.width
                height: Math.max(52, row.implicitHeight + 20)

                //  Lifetime timer — paused on hover so reading doesn't
                //  make it vanish (macOS behavior).
                Timer {
                    id: life
                    interval: Notifs.duration
                    running: !Notifs.bannerHold && !broot.hovered
                    onTriggered: broot.entry.dismiss()
                }
                onHoveredChanged: if (!hovered && !Notifs.bannerHold) life.restart()

                //  Drop-in on a Translate so the Column's y layout wins.
                property real dropY: 0
                transform: Translate { y: broot.dropY }

                Component.onCompleted: dropAnim.restart()

                ParallelAnimation {
                    id: dropAnim
                    NumberAnimation { target: broot; property: "dropY"; from: -14; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.55 }
                }

                //  ── Background ───────────────────────────────────
                Rectangle {
                    id: card
                    anchors.fill: parent
                    radius: 16
                    color: Theme.withAlpha(Theme.islandBg, 0.96)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.ink, 0.10)
                }

                //  ── Body click / hover (under the buttons) ───────
                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: broot.entry.activate()
                }

                //  ── Content (renders above hoverArea) ────────────
                Row {
                    id: row
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 8
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.track

                        Image {
                            anchors.fill: parent
                            visible: broot.entry.icon.length > 0
                            source: visible ? broot.entry.icon : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Glyph {
                            anchors.centerIn: parent
                            visible: broot.entry.icon.length === 0
                            size: 15
                            colorVal: Theme.accent
                            glyph: Icons.bell
                        }
                    }

                    Column {
                        width: parent.width - 32 - 20 - 30
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: broot.entry.summary.length > 0
                                ? broot.entry.app + " — " + broot.entry.summary
                                : broot.entry.app
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: broot.entry.body.length > 0
                            text: broot.entry.body
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        //  Action buttons (up to 2)
                        Row {
                            spacing: 6
                            visible: Notifs.bodyActions(broot.entry.raw).length > 0

                            Repeater {
                                model: Notifs.bodyActions(broot.entry.raw)

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: actionText.implicitWidth + 14
                                    height: 18
                                    radius: 9
                                    color: actionArea.containsMouse
                                        ? Theme.withAlpha(Theme.accent, 0.25)
                                        : Theme.withAlpha(Theme.ink, 0.08)
                                    scale: actionArea.pressed ? 0.92 : 1

                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                                    Text {
                                        id: actionText
                                        anchors.centerIn: parent
                                        text: modelData.text
                                        color: Theme.ink
                                        font.family: Theme.uiFont
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                    }
                                    MouseArea {
                                        id: actionArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Notifs.invoke(broot.entry, modelData)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: closeArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.14) : "transparent"
                        scale: closeArea.pressed ? 0.85 : 1

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                        Glyph {
                            anchors.centerIn: parent
                            size: 9
                            colorVal: Theme.muted
                            glyph: Icons.close
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: broot.entry.dismiss()
                        }
                    }
                }
            }
        }
    }
}
