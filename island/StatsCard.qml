import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

//  System stats — a REAL monitor, not a row of bars.
//
//  macOS Activity Monitor DNA: dark card, colored live graphs with
//  gradient fills, per-core strip, network throughput and a small
//  process-style legend. All data comes from SysMon's realtime probes
//  (2 s cadence, 60 samples of history per chart).
//
//  Lives INSIDE the island; opened from the peek stats row, the
//  "System Stats" quick action, or `notch stats` IPC.

Item {
    id: stats

    readonly property int pad: 14
    readonly property int graphH: 84

    //  Island contract
    property int prefWidth: 430
    implicitHeight: inner.implicitHeight + pad * 2

    Column {
        id: inner
        x: stats.pad
        y: stats.pad
        width: parent.width - stats.pad * 2
        spacing: 12

        //  ── Header ────────────────────────────────────────────────
        RowLayout {
            width: parent.width
            spacing: 8

            Glyph {
                size: 13
                colorVal: Theme.accent
                glyph: Icons.chart
            }
            Text {
                text: "System Stats"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }

            StatChip {
                glyph: Icons.thermometer
                text: SysMon.cpuTemp > 0 ? SysMon.cpuTemp + "°C" : "—"
                tint: SysMon.cpuTemp > 85 ? Theme.red : (SysMon.cpuTemp > 65 ? Theme.orange : Theme.teal)
            }
            StatChip {
                glyph: Icons.leaf
                text: SysMon.uptime
                tint: Theme.muted
            }
        }

        //  ── CPU graph ─────────────────────────────────────────────
        StatGraph {
            width: parent.width
            height: stats.graphH
            title: "CPU"
            detail: SysMon.cpuPct + "%"
            tint: Theme.blue
            values: SysMon.cpuHist
            maxValue: 100
        }

        //  ── Per-core strip ────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 3
            visible: SysMon.cpuCores.length > 0

            Repeater {
                model: SysMon.cpuCores

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: (parent.width - (parent.spacing * (parent.children.length - 1))) / parent.children.length
                    height: 5

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Theme.track
                    }
                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, modelData / 100))
                        height: parent.height
                        radius: 2
                        color: modelData > 85 ? Theme.red : Theme.blue
                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        //  ── Memory graph ──────────────────────────────────────────
        StatGraph {
            width: parent.width
            height: stats.graphH
            title: "Memory"
            detail: SysMon.formatGb(SysMon.memUsedGb) + " / " + SysMon.formatGb(SysMon.memTotalGb)
            tint: Theme.purple
            values: SysMon.memHist
            maxValue: 100
        }

        //  ── Network graph (auto-scale) ────────────────────────────
        StatGraph {
            width: parent.width
            height: stats.graphH
            title: "Network"
            detail: SysMon.formatKb(SysMon.netRxKb) + "  ↓   " + SysMon.formatKb(SysMon.netTxKb) + "  ↑"
            tint: Theme.teal
            values: SysMon.netHist
            maxValue: Math.max(256, stats.peak(SysMon.netHist) * 1.2)
        }

        //  ── Disk + swap summary ───────────────────────────────────
        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: (parent.width - 10) / 2
                height: 54
                radius: 10
                color: Theme.withAlpha(Theme.ink, 0.06)

                Column {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 5

                    Row {
                        spacing: 6
                        Glyph { size: 11; colorVal: Theme.muted; glyph: Icons.hdd; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Disk  " + SysMon.diskPct + "%"
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                        Text {
                            text: SysMon.formatGb(SysMon.diskUsedGb) + " / " + SysMon.formatGb(SysMon.diskTotalGb)
                            color: Theme.dim
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                    }
                    Item {
                        width: parent.width
                        height: 4
                        Rectangle { anchors.fill: parent; radius: 2; color: Theme.track }
                        Rectangle {
                            width: parent.width * Math.min(1, SysMon.diskPct / 100)
                            height: parent.height
                            radius: 2
                            color: SysMon.diskPct > 90 ? Theme.red : Theme.yellow
                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }

            Rectangle {
                width: (parent.width - 10) / 2
                height: 54
                radius: 10
                color: Theme.withAlpha(Theme.ink, 0.06)

                Column {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 5

                    Row {
                        spacing: 6
                        Glyph { size: 11; colorVal: Theme.muted; glyph: Icons.memory; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: SysMon.swapPct > 0 ? "Swap  " + SysMon.swapPct + "%" : "Swap  clean"
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }
                    Text {
                        text: SysMon.osName.length > 0 ? SysMon.osName : SysMon.kernelVer
                        color: Theme.dim
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }
        }
    }

    function peak(arr) {
        let m = 0
        for (let i = 0; i < arr.length; ++i)
            if (arr[i] > m)
                m = arr[i]
        return m
    }
}
