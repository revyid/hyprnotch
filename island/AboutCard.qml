import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

//  About This Machine — macOS "About This Mac" window, island edition.
//
//  Big logo, device name, then quiet spec rows that reveal with a
//  staggered fade when the card opens. Everything is read live from
//  SysMon's one-shot identity probe (hostname, distro, kernel, CPU and
//  GPU models) plus RAM / disk / uptime counters.

Item {
    id: about

    readonly property int pad: 16

    //  Island contract
    property int prefWidth: 400
    implicitHeight: inner.implicitHeight + pad * 2

    //  Staggered reveal: bumped when shown, rows multiply it into their
    //  own delays.
    property bool shown: UiState.activePopup === "about"
    property int revealTick: 0
    onShownChanged: {
        if (shown) {
            revealTick = 0
            reveal.restart()
        }
    }

    SequentialAnimation {
        id: reveal
        NumberAnimation { target: about; property: "revealTick"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
    }

    function revealDelay(i) {
        return Math.max(0, Math.min(1, (revealTick * 3.2 - i * 0.18)))
    }

    Column {
        id: inner
        x: about.pad
        y: about.pad
        width: parent.width - about.pad * 2
        spacing: 12

        //  ── Hero ──────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 92

            opacity: about.revealDelay(0)
            transform: Translate { y: (1 - about.revealDelay(0)) * -10 }

            //  soft accent halo behind the logo
            Rectangle {
                anchors.centerIn: parent
                width: 84; height: 84; radius: 42
                color: Theme.withAlpha(Theme.accent, 0.14)

                Rectangle {
                    anchors.centerIn: parent
                    width: 64; height: 64; radius: 32
                    color: Theme.withAlpha(Theme.accent, 0.20)

                    Glyph {
                        anchors.centerIn: parent
                        size: 30
                        colorVal: Theme.ink
                        glyph: Icons.distro(SysMon.osId, SysMon.osIdLike)
                    }
                }
            }

            Column {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                width: parent.width

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: SysMon.hostName.length > 0 ? SysMon.hostName : "This Mac"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: SysMon.osName.length > 0 ? SysMon.osName : "Linux"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                }
            }
        }

        //  ── Spec rows ─────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 1

            AboutRow {
                width: parent.width
                label: "Chip"
                value: SysMon.cpuModel.length > 0 ? SysMon.cpuModel : "—"
                delay: about.revealDelay(1)
            }
            AboutRow {
                width: parent.width
                label: "Graphics"
                value: SysMon.gpuModel.length > 0 ? SysMon.gpuModel : "Integrated"
                delay: about.revealDelay(2)
            }
            AboutRow {
                width: parent.width
                label: "Memory"
                value: SysMon.formatGb(SysMon.memTotalGb)
                delay: about.revealDelay(3)
            }
            AboutRow {
                width: parent.width
                label: "Startup Disk"
                value: SysMon.formatGb(SysMon.diskTotalGb) + " — " + SysMon.diskPct + "% used"
                delay: about.revealDelay(4)
            }
            AboutRow {
                width: parent.width
                label: "Kernel"
                value: SysMon.kernelVer.length > 0 ? SysMon.kernelVer : "—"
                delay: about.revealDelay(5)
            }
            AboutRow {
                width: parent.width
                label: "Uptime"
                value: SysMon.uptime
                delay: about.revealDelay(6)
            }
            AboutRow {
                width: parent.width
                label: "Desktop"
                value: "Hyprland · HyprNotch"
                delay: about.revealDelay(7)
            }
        }

        //  ── Mini live bar footer ──────────────────────────────────
        Row {
            width: parent.width
            spacing: 12
            opacity: about.revealDelay(8)

            MiniStat {
                width: (parent.width - 24) / 2
                label: "CPU"
                pct: SysMon.cpuPct
                sub: SysMon.cpuPct + "%"
                glyph: Icons.chip
                tint: Theme.blue
                height: 44
            }
            MiniStat {
                width: (parent.width - 24) / 2
                label: "Memory"
                pct: SysMon.memPct
                sub: SysMon.formatGb(SysMon.memUsedGb)
                glyph: Icons.memory
                tint: Theme.purple
                height: 44
            }
        }
    }
}
