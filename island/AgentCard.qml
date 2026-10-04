import QtQuick
import "../core"
import "../services"

//  AI Agent — STATUS panel, not a chat launcher (r24).
//
//  "agent ai itu bukan buat mulai atau apa gitu, tpi cuma liat
//  statusnya gitu, usage, dll juga itu" — the card answers exactly
//  three questions at a glance:
//    · is the agent on and installed?      (status row)
//    · what command does it run?           (command row)
//    · how much has it been used?          (usage rows)
//  Starting a conversation lives in Settings → AI Agent (optional
//  test prompt); the notch only observes.

Item {
    id: agentCard

    //  Island contract
    property int prefWidth: 440
    implicitHeight: Math.max(150, body.height + 24)

    property bool shown: UiState.activePopup === "agent"
    onShownChanged: if (shown)
        agentCard.flashProbe()

    //  Re-probe the binary each open so "not installed" never lies.
    function flashProbe() {
        //  Agent re-probes itself on completion of its own timer; we
        //  just nudge the display through a property read.
        void Agent.status
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

            Glyph {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: 13
                colorVal: Theme.accent
                glyph: Icons.robot
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "AI Agent"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 92
                anchors.verticalCenter: parent.verticalCenter
                text: "status · usage"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
            }

            Rectangle {
                id: gearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 22
                radius: 6
                color: gearArea.containsMouse
                    ? Theme.withAlpha(Theme.accent, 0.25) : Theme.withAlpha(Theme.ink, 0.08)

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Glyph {
                    anchors.centerIn: parent
                    size: 12
                    colorVal: Theme.ink
                    glyph: Icons.gear
                }
                MouseArea {
                    id: gearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        UiState.closeAll()
                        Power.openSettings("agent")
                    }
                }
            }
        }

        //  ── Status row ────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 46
            radius: 10
            color: Theme.withAlpha(Theme.ink, 0.06)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                spacing: 9

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: Agent.status === "ready" ? Theme.green
                        : Agent.status === "running" ? Theme.accent
                        : Agent.status === "disabled" ? Theme.dim
                        : Theme.red

                    SequentialAnimation on scale {
                        running: Agent.status === "running"
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.35; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: Agent.status === "ready" ? "Ready"
                            : Agent.status === "running" ? "Running…"
                            : Agent.status === "disabled" ? "Disabled"
                            : "Not installed"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: Agent.status === "not installed"
                            ? "the command below was not found in PATH"
                            : Agent.status === "disabled"
                              ? "enable it in the quick toggles or Settings"
                            : "agent binary found — watching usage"
                        color: Theme.dim
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                    }
                }
            }
        }

        //  ── Config rows ───────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: [
                    { glyph: Icons.terminal, label: "Command",
                      value: Agent.command },
                    { glyph: Icons.check,    label: "Enabled",
                      value: Agent.enabled ? "yes" : "no" }
                ]

                delegate: Row {
                    id: cfgRow
                    required property var modelData
                    width: parent.width
                    height: 24
                    spacing: 8

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 6
                        color: Theme.withAlpha(Theme.accent, 0.15)
                        Glyph {
                            anchors.centerIn: parent
                            size: 9
                            colorVal: Theme.accent
                            glyph: cfgRow.modelData.glyph
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                        text: cfgRow.modelData.label
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 178
                        text: cfgRow.modelData.value
                        color: Theme.ink
                        font.family: "monospace"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }

        //  ── Usage rows ────────────────────────────────────────────
        Text {
            text: "USAGE"
            color: Theme.dim
            font.family: Theme.uiFont
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: [
                    { label: "Total runs",     value: String(Agent.runs) },
                    { label: "Last run",       value: Agent.lastRun.length > 0 ? Agent.lastRun : "never" },
                    { label: "Last prompt",    value: Agent.lastPrompt.length > 0 ? Agent.lastPrompt : "—" },
                    { label: "Last output",    value: Agent.lastOutput.length > 0 ? Agent.lastOutput : "—" }
                ]

                delegate: Row {
                    id: usageRow
                    required property var modelData
                    width: parent.width
                    height: 20
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120
                        text: usageRow.modelData.label
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 128
                        text: usageRow.modelData.value
                        color: Theme.ink
                        font.family: "monospace"
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
