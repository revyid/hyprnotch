import QtQuick
import "../core"

//  One session action (Lock / Sleep / Logout / Restart / Shut Down).
//
//  macOS hold-to-confirm for destructive actions: a ring fills around
//  the glyph while you hold (~900 ms); release early and nothing
//  happens. Non-destructive actions fire on a plain tap.

Item {
    id: btn

    property string label: ""
    property string glyph: ""
    property color tint: Theme.accent
    property bool holdToConfirm: false
    signal fired()

    width: 60
    height: 64

    //  ── hold-to-confirm machinery ─────────────────────────────────
    property real holdProgress: 0

    //  Handler lives on the OWNER of holdProgress — a Canvas child has
    //  no holdProgress (v7 rule).
    onHoldProgressChanged: ringCanvas.requestPaint()

    scale: tapArea.pressed ? 0.90 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    Timer {
        id: holdTimer
        interval: 16
        repeat: true
        running: btn.holdToConfirm && tapArea.pressed
        onTriggered: {
            btn.holdProgress = Math.min(1, btn.holdProgress + interval / 900)
            if (btn.holdProgress >= 1) {
                stop()
                btn.holdProgress = 0
                btn.fired()
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 4

        Item {
            id: circle
            width: 42
            height: 42
            anchors.horizontalCenter: parent.horizontalCenter

            //  hold progress ring
            Canvas {
                id: ringCanvas
                anchors.centerIn: parent
                width: 50
                height: 50
                antialiasing: true
                visible: btn.holdProgress > 0.01

                onPaint: {
                    const ctx = ringCanvas.getContext("2d")
                    ctx.reset()
                    const cx = ringCanvas.width / 2, cy = ringCanvas.height / 2
                    ctx.lineWidth = 2.4
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.arc(cx, cy, cx - 2, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * btn.holdProgress)
                    ctx.strokeStyle = btn.tint.toString()
                    ctx.stroke()
                }
            }

            //  press fill
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: btn.holdToConfirm
                    ? Theme.withAlpha(btn.tint, btn.holdProgress * 0.85)
                    : (tapArea.containsMouse ? Theme.withAlpha(btn.tint, 0.20) : "transparent")

                Behavior on color { ColorAnimation { duration: 90 } }
            }

            //  danger glow as the hold completes
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: "transparent"
                border.width: 1
                border.color: tapArea.containsMouse ? Theme.withAlpha(btn.tint, 0.5) : Theme.withAlpha(Theme.ink, 0.10)
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            }

            Glyph {
                anchors.centerIn: parent
                size: 15
                colorVal: btn.holdProgress > 0.9 ? "#ffffff" : btn.tint
                glyph: btn.glyph

                Behavior on colorVal { ColorAnimation { duration: 120 } }
            }

            MouseArea {
                id: tapArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onPressed: if (btn.holdToConfirm) btn.holdProgress = 0
                onReleased: {
                    if (btn.holdToConfirm) {
                        //  released before the ring completed → cancel
                        if (btn.holdProgress < 1)
                            btn.holdProgress = 0
                    } else {
                        btn.fired()
                    }
                }
                onCanceled: if (btn.holdToConfirm) btn.holdProgress = 0
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            color: tapArea.containsMouse ? Theme.ink : Theme.muted
            font.family: Theme.uiFont
            font.pixelSize: 9
            font.weight: Font.Medium

            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    //  Canvas repaint hook — holdProgress is a plain property; the
    //  onHoldProgressChanged above lives on the Canvas.
}
