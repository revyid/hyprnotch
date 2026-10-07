import QtQuick
import "../core"
import "../services"

//  Notification center — hosted INSIDE the island body.
//  History list with clear-all / per-item dismiss / activate-on-click.
//  Opening it marks everything seen (the pill bell dot resets). Height
//  adapts to the list, capped so huge histories scroll instead of
//  eating the screen.

Item {
    id: ncWindow

    readonly property int pad: 12
    readonly property int maxBody: 320

    //  Island contract
    property int prefWidth: 360
    implicitHeight: notifColumn.implicitHeight + pad * 2

    //  Reading the center clears the unseen badge — macOS behavior.
    property bool shown: UiState.activePopup === "notifCenter"
    onShownChanged: if (shown) Notifs.markSeen()

    //  ── r28 UX: clear-all needs a beat ─────────────────────────
    //  One click used to erase the entire history. Now the first click
    //  arms the label ("sure?", red, 2.6s window), the second confirms.
    property bool clearArmed: false
    Timer {
        id: clearDisarm
        interval: 2600
        onTriggered: ncWindow.clearArmed = false
    }

    Column {
        id: notifColumn
        x: ncWindow.pad
        y: ncWindow.pad
        width: parent.width - ncWindow.pad * 2
        spacing: 8

        //  ── Header ────────────────────────────────────────────────
        Row {
            width: parent.width
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Item { width: parent.width - 130; height: 1 }

            Text {
                id: clearLabel
                anchors.verticalCenter: parent.verticalCenter
                text: ncWindow.clearArmed ? "sure? tap again" : "clear all"
                color: Notifs.history.length === 0 ? Theme.dim
                    : (ncWindow.clearArmed ? Theme.red : Theme.accent)
                font.family: Theme.uiFont
                font.pixelSize: 10
                font.weight: ncWindow.clearArmed ? Font.DemiBold : Font.Medium

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Notifs.history.length === 0)
                            return
                        if (!ncWindow.clearArmed) {
                            ncWindow.clearArmed = true
                            clearDisarm.restart()
                        } else {
                            ncWindow.clearArmed = false
                            clearDisarm.stop()
                            Notifs.clearAll()
                        }
                    }
                }
            }
        }

        //  ── Empty state ───────────────────────────────────────────
        Item {
            width: parent.width
            height: Notifs.history.length === 0 ? 64 : 0
            visible: Notifs.history.length === 0

            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
                size: 16
                colorVal: Theme.dim
                glyph: Icons.bell
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: "No notifications — you're all caught up"
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 10
            }
        }

        //  ── History list (scrolls past the cap) ───────────────────
        Flickable {
            width: parent.width
            height: Math.min(ncWindow.maxBody, listCol.implicitHeight)
            contentWidth: width
            contentHeight: listCol.implicitHeight
            clip: true
            interactive: contentHeight > height

            Column {
                id: listCol
                width: parent.width
                spacing: 6

                Repeater {
                    model: Notifs.history

                    delegate: Rectangle {
                        id: notifRow
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: Math.max(46, ncText.implicitHeight + ncSum.implicitHeight + ncHead.implicitHeight + 22)
                        radius: Theme.radiusTile
                        color: ncRowArea.containsMouse
                            ? Theme.withAlpha(Theme.ink, 0.10) : Theme.withAlpha(Theme.ink, 0.06)
                        scale: ncRowArea.pressed ? 0.98 : 1

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                        //  Row click = activate (default action / focus app)
                        MouseArea {
                            id: ncRowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notifRow.modelData.activate()
                        }

                        Row {
                            x: 10
                            y: 8
                            width: parent.width - 42
                            spacing: 8

                            Rectangle {
                                width: 22
                                height: 22
                                radius: 6
                                clip: true
                                color: Theme.track
                                anchors.verticalCenter: ncHead.verticalCenter

                                Image {
                                    anchors.fill: parent
                                    visible: notifRow.modelData.icon.length > 0
                                    source: visible ? notifRow.modelData.icon : ""
                                    sourceSize: Qt.size(parent.width * 2, parent.height * 2)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Glyph {
                                    anchors.centerIn: parent
                                    visible: notifRow.modelData.icon.length === 0
                                    size: 11
                                    colorVal: Theme.muted
                                    glyph: Icons.bell
                                }
                            }

                            Column {
                                width: parent.width - 30
                                spacing: 2

                                Row {
                                    id: ncHead
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        text: notifRow.modelData.app
                                        color: Theme.muted
                                        font.family: Theme.uiFont
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, parent.width - 40)
                                    }
                                    Text {
                                        text: Notifs.formatAge(notifRow.modelData.time)
                                        color: Theme.dim
                                        font.family: Theme.uiFont
                                        font.pixelSize: 9
                                    }
                                }

                                Text {
                                    id: ncSum
                                    width: parent.width
                                    text: notifRow.modelData.summary
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    visible: notifRow.modelData.summary.length > 0
                                }

                                Text {
                                    id: ncText
                                    width: parent.width
                                    text: notifRow.modelData.body
                                    color: Theme.muted
                                    font.family: Theme.uiFont
                                    font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    visible: notifRow.modelData.body.length > 0
                                }
                            }
                        }

                        //  Per-item dismiss
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 10
                            color: disArea.containsMouse ? Theme.red : "transparent"
                            scale: disArea.pressed ? 0.85 : 1

                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            Glyph {
                                anchors.centerIn: parent
                                size: 8
                                colorVal: disArea.containsMouse ? "#ffffff" : Theme.dim
                                glyph: Icons.close
                            }
                            MouseArea {
                                id: disArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notifRow.modelData.dismiss()
                            }
                        }

                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    }
                }
            }
        }
    }
}
