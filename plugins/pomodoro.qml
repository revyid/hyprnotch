import QtQuick
import "../core"
import "../services"

//  Pomodoro — a HyprNotch plugin.
//
//  The root exposes the plugin contract (name, icon, prefWidth,
//  compact, view); state lives HERE, so the peek chip and the full
//  view always agree on the clock. When a session ends the plugin
//  pushes a toast through the island's own notification pipeline.

Item {
    id: root

    //  ── plugin contract ───────────────────────────────────────────
    readonly property string name: "Pomodoro"
    readonly property string icon: "\uF252"
    readonly property bool enabled: true
    property Component compact: compactComp
    property Component view: viewComp

    //  ── state ─────────────────────────────────────────────────────
    property int workMin: 25
    property int breakMin: 5
    property int remainSec: workMin * 60
    property bool running: false
    property bool resting: false

    function fmt(s) {
        const m = Math.floor(s / 60)
        const r = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
    }

    function toggle() {
        running = !running
    }

    function reset() {
        running = false
        resting = false
        remainSec = workMin * 60
    }

    Timer {
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: {
            root.remainSec -= 1
            if (root.remainSec <= 0) {
                root.running = false
                Notifs.toast("Pomodoro", root.resting
                    ? "Break over — back to work!"
                    : "Pomodoro complete — take a " + root.breakMin + " minute break")
                root.resting = !root.resting
                root.remainSec = (root.resting ? root.breakMin : root.workMin) * 60
            }
        }
    }

    //  ── peek chip (about 20 px tall) ──────────────────────────────
    Component {
        id: compactComp

        Item {
            implicitHeight: 20

            Row {
                anchors.centerIn: parent
                spacing: 5

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 10
                    colorVal: root.resting ? Theme.green : Theme.orange
                    glyph: root.icon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.running ? root.fmt(root.remainSec) : (root.resting ? "break" : "focus")
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }
            }
        }
    }

    //  ── island view (root must declare prefWidth + implicitHeight) ─
    Component {
        id: viewComp

        Item {
            property int prefWidth: 300
            implicitHeight: 170

            Column {
                anchors.fill: parent
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.resting ? "Break" : "Focus"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.fmt(root.remainSec)
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 42
                    font.weight: Font.Light
                }

                Item {
                    width: parent.width
                    height: 5

                    Rectangle {
                        anchors.fill: parent
                        radius: 2.5
                        color: Theme.track
                    }
                    Rectangle {
                        width: parent.width * (1 - root.remainSec / ((root.resting ? root.breakMin : root.workMin) * 60))
                        height: parent.height
                        radius: 2.5
                        color: root.resting ? Theme.green : Theme.orange
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Rectangle {
                        width: 34; height: 24; radius: 12
                        color: Theme.withAlpha(Theme.accent, 0.22)
                        scale: playBtn.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        Glyph {
                            anchors.centerIn: parent
                            size: 11
                            colorVal: Theme.ink
                            glyph: root.running ? Icons.pause : Icons.play
                        }
                        MouseArea {
                            id: playBtn
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle()
                        }
                    }
                    Rectangle {
                        width: 34; height: 24; radius: 12
                        color: Theme.withAlpha(Theme.ink, 0.10)
                        scale: resetBtn.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        Glyph {
                            anchors.centerIn: parent
                            size: 11
                            colorVal: Theme.muted
                            glyph: Icons.refresh
                        }
                        MouseArea {
                            id: resetBtn
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.reset()
                        }
                    }
                }
            }
        }
    }
}
