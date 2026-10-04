import QtQuick
import "../core"
import "../services"

//  One live graph — Canvas line + gradient fill, hairline grid, title
//  and live value overlaid. Plots `values` (oldest → newest) across
//  the width; the newest sample gets a glowing endpoint dot.

Item {
    id: graph

    property string title: ""
    property string detail: ""
    property color tint: Theme.accent
    property var values: []
    property real maxValue: 100

    //  Repaint whenever the data changes. The handler must live on THIS
    //  object (the owner of `values`) — a Canvas child has no `values`.
    onValuesChanged: canvas.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.withAlpha(Theme.ink, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.ink, 0.06)
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 1
        antialiasing: true

        onPaint: {
            const ctx = canvas.getContext("2d")
            ctx.reset()
            if (canvas.width < 10 || canvas.height < 10)
                return

            //  ── grid ──────────────────────────────────────────────
            ctx.strokeStyle = "rgba(255,255,255,0.05)"
            ctx.lineWidth = 1
            for (let g = 1; g <= 3; ++g) {
                const gy = Math.round(canvas.height * g / 4) + 0.5
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(canvas.width, gy)
                ctx.stroke()
            }

            const vals = graph.values
            if (vals.length < 2)
                return

            const max = graph.maxValue > 0 ? graph.maxValue : 100
            const step = canvas.width / (vals.length - 1)
            const pad = 4
            const usableH = canvas.height - pad * 2

            //  ── line ─────────────────────────────────────────────
            ctx.beginPath()
            for (let i = 0; i < vals.length; ++i) {
                const x = i * step
                const y = pad + usableH * (1 - Math.min(1, vals[i] / max))
                if (i === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }

            //  fill under the line
            ctx.lineTo((vals.length - 1) * step, canvas.height)
            ctx.lineTo(0, canvas.height)
            ctx.closePath()
            const fill = ctx.createLinearGradient(0, 0, 0, canvas.height)
            fill.addColorStop(0, Qt.rgba(graph.tint.r, graph.tint.g, graph.tint.b, 0.30))
            fill.addColorStop(1, Qt.rgba(graph.tint.r, graph.tint.g, graph.tint.b, 0.02))
            ctx.fillStyle = fill
            ctx.fill()

            //  stroke on top
            ctx.beginPath()
            for (let j = 0; j < vals.length; ++j) {
                const px = j * step
                const py = pad + usableH * (1 - Math.min(1, vals[j] / max))
                if (j === 0)
                    ctx.moveTo(px, py)
                else
                    ctx.lineTo(px, py)
            }
            ctx.strokeStyle = Qt.rgba(graph.tint.r, graph.tint.g, graph.tint.b, 0.9)
            ctx.lineWidth = 1.6
            ctx.stroke()

            //  endpoint dot
            const lastY = pad + usableH * (1 - Math.min(1, vals[vals.length - 1] / max))
            ctx.beginPath()
            ctx.arc((vals.length - 1) * step, lastY, 2.6, 0, Math.PI * 2)
            ctx.fillStyle = graph.tint.toString()
            ctx.fill()
        }

        onWidthChanged: canvas.requestPaint()
        onHeightChanged: canvas.requestPaint()
        Component.onCompleted: canvas.requestPaint()
    }

    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        spacing: 6

        Text {
            text: graph.title
            color: graph.tint
            font.family: Theme.uiFont
            font.pixelSize: 10
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: graph.detail
            color: Theme.muted
            font.family: Theme.uiFont
            font.pixelSize: 10
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
