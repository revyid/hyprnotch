import QtQuick
import Quickshell.Io
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
                            ? (Agent.mode === "script"
                                ? "the script below does not exist yet"
                                : "the command below was not found in PATH")
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
                    { glyph: Icons.terminal, label: "Runner",
                      value: Agent.mode === "script" ? Agent.scriptPath : Agent.command },
                    { glyph: Icons.sliders,  label: "Mode",
                      value: Agent.mode === "script" ? "own script" : "command" },
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

        //  ── Settings (r25): self-config, including your own script ─
        //  "di agent, buat setting gitu, ntah setting gimana, ntah
        //  konfigurasi sendiri pake script sendri" — the card now
        //  carries a compact runner editor: pick the mode, edit the
        //  command inline, or generate + use your own agent script.
        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "SETTINGS"
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
            }

            Row {
                spacing: 6

                Repeater {
                    model: [
                        { k: "command", label: "Command" },
                        { k: "script",  label: "My script" }
                    ]

                    delegate: Rectangle {
                        id: modeChip
                        required property var modelData
                        readonly property bool sel: Agent.mode === modelData.k
                        width: modeChipLabel.implicitWidth + 20
                        height: 24
                        radius: 12
                        color: sel ? Theme.accent : Theme.withAlpha(Theme.ink, 0.08)
                        scale: modeChipArea.pressed ? 0.94 : 1

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                        Text {
                            id: modeChipLabel
                            anchors.centerIn: parent
                            text: modeChip.modelData.label
                            color: modeChip.sel ? "#ffffff" : Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            font.weight: modeChip.sel ? Font.DemiBold : Font.Medium
                        }
                        MouseArea {
                            id: modeChipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.set("agent.mode", modeChip.modelData.k)
                        }
                    }
                }
            }

            //  command mode: edit the CLI inline
            Row {
                visible: Agent.mode === "command"
                width: parent.width
                spacing: 6

                Rectangle {
                    width: parent.width - 62
                    height: 30
                    radius: Theme.radiusSmall
                    color: Theme.withAlpha(Theme.ink, 0.08)
                    border.width: cmdInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextInput {
                        id: cmdInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: Agent.command
                        color: Theme.ink
                        font.family: "monospace"
                        font.pixelSize: 11
                        clip: true

                        Keys.onPressed: (ev) => {
                            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                                Config.set("agent.command", text.trim())
                                focus = false
                                ev.accepted = true
                            }
                        }
                    }
                }
                Rectangle {
                    width: 56; height: 30; radius: Theme.radiusSmall
                    color: cmdApplyArea.containsMouse ? Theme.surfaceHi : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        color: "#ffffff"
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: cmdApplyArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set("agent.command", cmdInput.text.trim())
                    }
                }
            }

            //  script mode: path + template generator + copy path
            Row {
                visible: Agent.mode === "script"
                width: parent.width
                spacing: 6

                Rectangle {
                    width: parent.width - 138
                    height: 30
                    radius: Theme.radiusSmall
                    color: Theme.withAlpha(Theme.ink, 0.06)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: Agent.scriptPath
                        color: Theme.ink
                        font.family: "monospace"
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }
                }
                Rectangle {
                    width: 74; height: 30; radius: Theme.radiusSmall
                    color: scriptNewArea.containsMouse ? Theme.surfaceHi : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "New"
                        color: "#ffffff"
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: scriptNewArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Agent.createScriptTemplate()
                    }
                }
                Rectangle {
                    width: 58; height: 30; radius: Theme.radiusSmall
                    color: scriptCopyArea.containsMouse ? Theme.surfaceHi : Theme.track
                    Text {
                        anchors.centerIn: parent
                        text: "Copy"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: scriptCopyArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            copyProc.command = ["sh", "-c",
                                "printf %s " + Agent.shQuote(Agent.scriptPath) + " | wl-copy"]
                            copyProc.running = true
                        }
                    }
                }

                Process {
                    id: copyProc
                    command: []
                    onExited: Notifs.toast("Agent", "script path copied",
                                           "paste it into your editor")
                }
            }

            Text {
                width: parent.width
                text: Agent.mode === "script"
                    ? "Your script receives the prompt as $1 and prints the answer. Create it from the template, then edit it with any editor."
                    : "Type the CLI to run (e.g. hermes, aichat, sgpt). Switch to My script to plug in your own runner."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
                wrapMode: Text.WordWrap
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
