pragma Singleton

//  AI agent bridge (Hermes or anything else). The command is fully
//  user-configurable: Config.data.agent.command + the user's prompt are
//  joined and run through `sh -c`, stdout streams back into the chat.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: agent

    property var messages: []        //  [{role: "user"|"agent", text: "..."}]
    property bool thinking: false

    readonly property string command: Config.get("agent.command", "hermes")

    function send(prompt) {
        const p = (prompt || "").trim()
        if (p.length === 0 || thinking)
            return
        const copy = messages.slice()
        copy.push({ role: "user", text: p })
        messages = copy
        thinking = true

        const cmd = command + " " + p.replace(/'/g, "'\\''")
        runCmd.command = ["sh", "-c", cmd + " 2>&1"]
        runCmd.running = true
    }

    Process {
        id: runCmd
        stdout: StdioCollector {
            onStreamFinished: {
                const copy = agent.messages.slice()
                copy.push({ role: "agent", text: text.trim().length > 0 ? text.trim() : "(no output)" })
                agent.messages = copy.slice(-60)
                agent.thinking = false
            }
        }
    }

    function clear() {
        messages = []
        thinking = false
    }
}
