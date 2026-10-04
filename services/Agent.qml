pragma Singleton

//  AI agent bridge (Hermes or any other CLI tool).
//
//  r24: the notch card for this service is a STATUS / USAGE viewer,
//  not a chat launcher ("agent ai itu bukan buat mulai atau apa gitu,
//  tpi cuma liat statusnya gitu, usage, dll"). So this singleton now
//  tracks what a status panel needs:
//    · available — is the configured binary actually installed?
//    · enabled   — the Settings feature switch
//    · runs / lastRun / lastPrompt / lastOutput — usage stats that
//      survive restarts (stored in the config document)
//  send() still works for the optional test prompt in Settings →
//  AI Agent, and the agent plugin, but nothing in the notch pushes
//  the user to start a conversation.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: agent

    property var messages: []        //  [{role: "user"|"agent", text: "..."}]
    property bool thinking: false

    readonly property bool enabled: Config.get("agent.enabled", true)
    readonly property string command: Config.get("agent.command", "hermes")

    //  Usage/status (persisted through Config so numbers survive)
    readonly property int runs: {
        const n = Config.get("agent.usage.runs", 0)
        return typeof n === "number" ? n : 0
    }
    readonly property string lastRun: Config.get("agent.usage.lastRun", "")
    readonly property string lastPrompt: Config.get("agent.usage.lastPrompt", "")
    readonly property string lastOutput: Config.get("agent.usage.lastOutput", "")

    //  Binary probe — updated by Power's startup bin sweep and its own
    //  fallback probe below (covers shells that load before Power).
    property bool binaryAvailable: false

    //  Status summary for the notch card: one of ready / disabled /
    //  missing / busy.
    readonly property string status: !enabled ? "disabled"
        : thinking ? "running"
        : !binaryAvailable ? "not installed"
        : "ready"

    function markBinary(ok) {
        binaryAvailable = ok
    }

    function send(prompt) {
        const p = (prompt || "").trim()
        if (p.length === 0 || thinking)
            return
        if (!enabled) {
            const copy = messages.slice()
            copy.push({ role: "agent",
                        text: "Agent is disabled — turn it on in Settings → AI Agent." })
            messages = copy.slice(-60)
            return
        }
        const cmd = command + " " + p.replace(/'/g, "'\\''")
        const copy = messages.slice()
        copy.push({ role: "user", text: p })
        messages = copy
        thinking = true
        //  Usage stats: count the run, stamp the time, keep the prompt
        //  for the status panel.
        Config.set("agent.usage", {
            runs: runs + 1,
            lastRun: Qt.formatDateTime(new Date(), "ddd d MMM yyyy HH:mm"),
            lastPrompt: p.length > 120 ? p.substring(0, 120) + "…" : p,
            lastOutput: lastOutput
        })
        runCmd.command = ["sh", "-c", "command -v " + command + " >/dev/null 2>&1 && " + cmd + " 2>&1 || echo AGENT_MISSING"]
        runCmd.running = true
    }

    Process {
        id: runCmd
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                let out
                if (t === "AGENT_MISSING") {
                    out = "Command not found: " + agent.command
                    agent.binaryAvailable = false
                } else {
                    out = t.length > 0 ? t : "(no output)"
                    agent.binaryAvailable = true
                }
                const copy = agent.messages.slice()
                copy.push({ role: "agent", text: out })
                agent.messages = copy.slice(-60)
                agent.thinking = false
                //  Record the reply head for the status panel.
                const u = Config.get("agent.usage", {}) || {}
                Config.set("agent.usage", {
                    runs: typeof u.runs === "number" ? u.runs : 0,
                    lastRun: typeof u.lastRun === "string" ? u.lastRun : "",
                    lastPrompt: typeof u.lastPrompt === "string" ? u.lastPrompt : "",
                    lastOutput: out.length > 160 ? out.substring(0, 160) + "…" : out
                })
            }
        }
    }

    //  Own binary probe at startup (does not fork a shell — checks
    //  PATH once via the same trick Power uses; cheap and silent).
    Process {
        id: binProbe
        command: ["sh", "-c", "command -v " + command + " >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: agent.binaryAvailable = (text.trim() === "yes")
        }
    }

    function clear() {
        messages = []
        thinking = false
    }

    Component.onCompleted: binProbe.running = true
}
