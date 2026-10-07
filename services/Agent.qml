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

    //  ── Self-config (r25: "konfigurasi sendiri pake script sendri") ─
    //  mode "command" runs the CLI from the PATH (as before); mode
    //  "script" hands the prompt as $1 to the user's own script —
    //  default ~/.config/hyprnotch/agent.sh — which they can point at
    //  any backend. A template generator lives below so the file can
    //  be created straight from the notch card.
    readonly property string mode: Config.get("agent.mode", "command") === "script" ? "script" : "command"
    readonly property string scriptPath: {
        const saved = String(Config.get("agent.script", ""))
        if (saved.length > 0)
            return saved
        return Config.configDir + "/hyprnotch/agent.sh"
    }

    function shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

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
        runWasScript = (mode === "script")
        const check = runWasScript
            ? "test -f " + shQuote(scriptPath)
            : "command -v " + command + " >/dev/null 2>&1"
        const run = runWasScript
            ? "sh " + shQuote(scriptPath) + " " + shQuote(p)
            : command + " " + p.replace(/'/g, "'\\''")
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
        runCmd.command = ["sh", "-c", check + " && " + run + " 2>&1 || echo AGENT_MISSING"]
        runCmd.running = true
    }

    property bool runWasScript: false

    Process {
        id: runCmd
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                let out
                if (t === "AGENT_MISSING") {
                    out = agent.runWasScript
                        ? "Agent script not found: " + agent.scriptPath
                        : "Command not found: " + agent.command
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

    //  ── Binary / script probe ────────────────────────────────────
    //  Re-runs whenever the runner config changes (mode, command,
    //  script path) so "not installed" never lies about the CURRENT
    //  configuration. One cheap command -v / test -f per probe.
    function probe() {
        if (binProbe.running)
            return
        binProbe.command = ["sh", "-c",
            mode === "script"
                ? "test -f " + shQuote(scriptPath) + " && echo yes || echo no"
                : "command -v " + command + " >/dev/null 2>&1 && echo yes || echo no"]
        binProbe.running = true
    }

    Process {
        id: binProbe
        command: []
        stdout: StdioCollector {
            onStreamFinished: agent.binaryAvailable = (text.trim() === "yes")
        }
    }

    onModeChanged: probe()
    onCommandChanged: probe()
    onScriptPathChanged: probe()

    //  ── Template generator (r25) ──────────────────────────────────
    //  Writes the agent script (chmod +x) straight from the notch
    //  card / Settings, so "konfigurasi sendiri pake script sendri"
    //  is one click. Never overwrites an existing script.
    readonly property string scriptTemplate:
        "#!/bin/sh\n" +
        "#  HyprNotch agent runner - edit freely, it is YOUR script.\n" +
        "#  Invoked as: agent.sh \"<prompt>\" - print the answer to stdout.\n" +
        "#  Plug in any backend you like, e.g.\n" +
        "#    exec aichat \"$1\"\n" +
        "#    exec sgpt \"$1\"\n" +
        "#    exec ollama run llama3.2 \"$1\"\n" +
        "PROMPT=\"${1:-}\"\n" +
        "if command -v aichat >/dev/null 2>&1; then exec aichat \"$PROMPT\"; fi\n" +
        "if command -v sgpt   >/dev/null 2>&1; then exec sgpt \"$PROMPT\"; fi\n" +
        "if command -v ollama >/dev/null 2>&1; then exec ollama run llama3.2 \"$PROMPT\"; fi\n" +
        "echo \"no AI CLI found - edit this script to plug in your own\"\n"

    function createScriptTemplate() {
        mkScriptCmd.command = ["sh", "-c",
            "mkdir -p " + shQuote(Config.configDir + "/hyprnotch") +
            " && if [ ! -f " + shQuote(scriptPath) + " ]; then printf %s " + shQuote(scriptTemplate) + " > " + shQuote(scriptPath) + "; fi" +
            " && chmod +x " + shQuote(scriptPath) +
            " && echo done"]
        mkScriptCmd.running = true
    }

    Process {
        id: mkScriptCmd
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "done") {
                    agent.probe()
                    Notifs.toast("Agent", "agent script ready", agent.scriptPath)
                } else {
                    Notifs.toast("Agent", "could not create the script", agent.scriptPath)
                }
            }
        }
    }

    function clear() {
        messages = []
        thinking = false
    }

    Component.onCompleted: probe()
}
