import QtQuick
import "../core"
import "../services"

//  Plugin manager — the "Plugins" menu inside the island.
//
//  Lists every .qml found in the plugins folder (enabled AND disabled),
//  with a toggle per plugin and an Open button that jumps straight into
//  its island view. Drop-in files become rows here after a reload.

Item {
    id: pluginsCard

    //  Island contract
    property int prefWidth: 420
    implicitHeight: Math.max(120, body.height + 24)

    function fileNameOf(d) {
        return String(d.url || "").split("/").pop()
    }

    function activeIndexOf(d) {
        for (let i = 0; i < Plugins.active.length; ++i)
            if (Plugins.active[i] === d)
                return i
        return -1
    }

    Column {
        id: body
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 8

        //  ── Header ────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Plugins"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 78
                text: "drop .qml files into the plugins folder"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
            }

            Rectangle {
                id: reloadBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 22
                radius: 6
                color: reloadArea.containsMouse
                    ? Theme.withAlpha(Theme.accent, 0.25) : Theme.withAlpha(Theme.ink, 0.08)

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Glyph {
                    anchors.centerIn: parent
                    size: 12
                    colorVal: Theme.ink
                    glyph: "\uF2F1"   // refresh
                }
                MouseArea {
                    id: reloadArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Plugins.reload()
                }
            }
        }

        //  ── Rows: every discovered plugin ─────────────────────────
        Repeater {
            model: Plugins.plugins

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                height: 44
                radius: 10
                color: Theme.withAlpha(Theme.ink, 0.06)

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: 7
                        color: Theme.withAlpha(Theme.accent, row.modelData.enabled ? 0.22 : 0.08)

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Glyph {
                            anchors.centerIn: parent
                            size: 13
                            colorVal: Theme.accent
                            glyph: row.modelData.icon || Icons.plug
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: row.modelData.name || fileNameOf(row.modelData)
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: fileNameOf(row.modelData)
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                    }
                }

                //  Open (enabled plugins only) — jumps into its view
                Rectangle {
                    anchors.right: openToggle.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54
                    height: 24
                    radius: 12
                    visible: row.modelData.enabled
                    color: openArea.containsMouse
                        ? Theme.withAlpha(Theme.accent, 0.30) : Theme.withAlpha(Theme.accent, 0.16)

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "Open"
                        color: Theme.accent
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: openArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Plugins.open(pluginsCard.activeIndexOf(row.modelData))
                    }
                }

                AppToggle {
                    id: openToggle
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    checked: row.modelData.enabled
                    onToggled: Plugins.setDisabled(
                        pluginsCard.fileNameOf(row.modelData), !checked)
                }
            }
        }

        //  ── Empty state ───────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 64
            radius: 10
            color: Theme.withAlpha(Theme.ink, 0.04)
            visible: Plugins.plugins.length === 0

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No plugins yet"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Copy a .qml plugin into ~/.config/quickshell/hyprnotch/plugins\nthen press the refresh button above."
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
