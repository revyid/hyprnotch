pragma Singleton

//  HyprNotch keybind service — every island shortcut is data, not code.
//
//  The chord for each action lives in config.json under keybinds.map and
//  is edited live in Settings → Keybinds. This service turns that map
//  into real Hyprland binds by running scripts/apply-keys.sh, which:
//    · unbinds only binds carrying our IPC signature (never your chords),
//    · registers the requested set (keys taken by OTHER programs stay
//      alone and are reported as conflicts),
//    · rewrites ~/.config/hypr/config/hyprnotch.lua on k4 Lua forks so
//      edits survive `hyprctl reload`.
//
//  Startup: applies ~1.5 s after launch, then re-applies once more at
//  ~5.5 s — the k4 fork re-applies its config asynchronously and can
//  wipe runtime binds registered a moment earlier (r14 lesson).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: hotkeys

    //  ── The actions and their factory chords ─────────────────────
    //  Launcher is Super+Space (a plain chord — no release-bind magic,
    //  no fork quirks). Super+D is gone from the defaults; re-add it
    //  here in Settings if you miss it.
    //  r24 batch (user: "keybind ini aku mau kamu set set sekalian,
    //  kyk screenshot, dll"): Print = screenshot, Shift+Print = screen
    //  recording, Super+V = clipboard history (Win+V), Super+U =
    //  containers, Super+Y = AI agent status, Super+A = quick toggles.
    readonly property var defaults: [
        { action: "launcher",      mods: "SUPER", key: "SPACE" },
        { action: "controlCenter", mods: "SUPER", key: "C" },
        { action: "calendar",      mods: "SUPER", key: "K" },
        { action: "notifications", mods: "SUPER", key: "N" },
        { action: "weather",       mods: "SUPER", key: "W" },
        { action: "stats",         mods: "SUPER", key: "T" },
        { action: "wallpaper",     mods: "SUPER", key: "G" },
        { action: "power",         mods: "SUPER", key: "E" },
        { action: "about",         mods: "SUPER", key: "I" },
        { action: "plugins",       mods: "SUPER", key: "O" },
        { action: "settings",      mods: "SUPER", key: "S" },
        { action: "dnd",           mods: "SUPER", key: "B" },
        { action: "podman",        mods: "SUPER", key: "P" },
        { action: "clipboard",     mods: "SUPER", key: "V" },
        { action: "screenshot",    mods: "",      key: "PRINT" },
        { action: "record",        mods: "SHIFT", key: "PRINT" },
        { action: "containers",    mods: "SUPER", key: "U" },
        { action: "agent",         mods: "SUPER", key: "Y" },
        { action: "quickToggles",  mods: "SUPER", key: "A" }
    ]

    readonly property var labels: ({
        launcher:      { title: "Launcher",        sub: "app grid + command search" },
        controlCenter: { title: "Control Center",  sub: "toggles, sliders, media" },
        calendar:      { title: "Calendar",        sub: "monthly calendar" },
        notifications: { title: "Notifications",   sub: "notification center" },
        weather:       { title: "Weather",         sub: "forecast panel" },
        stats:         { title: "System Monitor",  sub: "CPU, memory, network, disks" },
        wallpaper:     { title: "Wallpaper",       sub: "wallpaper picker" },
        power:         { title: "Power & Battery", sub: "power modes, session" },
        about:         { title: "About",           sub: "about this device" },
        plugins:       { title: "Plugins",         sub: "plugin manager" },
        settings:      { title: "Settings",        sub: "the settings window" },
        dnd:           { title: "Do Not Disturb",  sub: "silence banners" },
        podman:        { title: "Containers",      sub: "podman manager page" },
        clipboard:     { title: "Clipboard",       sub: "clipboard history (Win+V)" },
        screenshot:    { title: "Screenshot",      sub: "capture a region or screen" },
        record:        { title: "Screen Recording",sub: "start / stop wf-recorder" },
        containers:    { title: "Containers Panel",sub: "podman containers in the notch" },
        agent:         { title: "AI Agent Status", sub: "agent status and usage" },
        quickToggles:  { title: "Quick Toggles",   sub: "per-feature switches panel" }
    })

    //  The action list Settings → Keybinds renders. r23 shipped this
    //  page binding `model: Hotkeys.actions` WITHOUT the property ever
    //  existing — the Repeater got `undefined` and the page showed zero
    //  rows (the user's "keybind kedetec 0"). Derived from the map so
    //  user-added entries also appear.
    readonly property var actions: {
        const out = []
        for (let i = 0; i < defaults.length; ++i)
            out.push(defaults[i].action)
        for (const a in map)
            if (out.indexOf(a) < 0)
                out.push(a)
        return out
    }

    //  ── Effective map: saved chords win, defaults fill the rest ──
    //  A saved entry may legitimately be { mods:"", key:"" } (user
    //  cleared it) — that must survive, hence the undefined check and
    //  not a truthiness check.
    readonly property var map: {
        const base = defaultMap()
        const saved = (Config.data.keybinds && Config.data.keybinds.map)
            ? Config.data.keybinds.map : {}
        const out = {}
        for (const a in base)
            out[a] = (saved[a] !== undefined && saved[a] !== null) ? saved[a] : base[a]
        for (const s in saved)
            if (!(s in base) && saved[s])
                out[s] = saved[s]
        return out
    }

    function defaultMap() {
        const m = {}
        for (let i = 0; i < defaults.length; ++i) {
            const d = defaults[i]
            m[d.action] = { mods: d.mods, key: d.key }
        }
        return m
    }

    function bindingFor(action) {
        const b = map[action]
        return (b && b.key && String(b.key).length > 0) ? b : null
    }

    //  "SUPER + SPACE" — pretty label for chips and capture previews.
    function chordLabel(b) {
        if (!b || !b.key || String(b.key).length === 0)
            return "unbound"
        const mods = String(b.mods || "").split(/\s+/)
        let out = ""
        for (let i = 0; i < mods.length; ++i) {
            if (mods[i].length === 0)
                continue
            out += (out.length > 0 ? " + " : "") + mods[i]
        }
        return out + (out.length > 0 ? " + " : "") + String(b.key)
    }

    //  ── Writes ────────────────────────────────────────────────────
    function setBinding(action, mods, key) {
        const copy = JSON.parse(JSON.stringify(map))
        for (const other in copy) {
            if (other === action)
                continue
            const b = copy[other]
            if (b && b.key && String(b.key).toLowerCase() === String(key).toLowerCase()
                && String(b.mods || "") === String(mods))
                return { ok: false, conflict: other }
        }
        copy[action] = { mods: String(mods), key: String(key) }
        Config.set("keybinds.map", copy)
        apply()
        return { ok: true, conflict: "" }
    }

    function clearBinding(action) {
        const copy = JSON.parse(JSON.stringify(map))
        copy[action] = { mods: "", key: "" }
        Config.set("keybinds.map", copy)
        apply()
    }

    function resetToDefaults() {
        Config.set("keybinds.map", defaultMap())
        apply()
    }

    //  ── Applying ─────────────────────────────────────────────────
    //  Install folder = the folder holding the shell.qml this service
    //  was loaded from. Quickshell exposes it DIRECTLY as
    //  Quickshell.shellDir (verified in the vendored source:
    //  src/core/qmlglobal.hpp — "The full path to the root directory
    //  of your shell"). The old Qt.resolvedUrl trick broke on this
    //  user's build: it returned a `qs:@qs/...` resource URL, the
    //  file:// strip was a no-op, and the probe path became the
    //  literal string "qs:@qs/scripts/apply-keys.sh" — the applier
    //  never ran and the summary read "applier script missing" (r24
    //  user report). shellDir needs no URL gymnastics at all.
    readonly property string raiz: {
        let p = String(Quickshell.shellDir || "")
        if (p.length === 0) {
            const u = Qt.resolvedUrl("../shell.qml").toString()
            if (u.indexOf("file://") === 0)
                p = decodeURIComponent(u.replace(/^file:\/\//, "").replace(/\/shell\.qml$/, ""))
            else if (u.indexOf("/") === 0)
                p = decodeURIComponent(u.replace(/\/shell\.qml$/, ""))
            else {
                //  Last resort: the standard quickshell install location.
                const xdg = Quickshell.env("XDG_CONFIG_HOME")
                p = (xdg && xdg.length > 0 ? xdg : Quickshell.env("HOME") + "/.config")
                    + "/quickshell/hyprnotch"
            }
        }
        return p
    }
    readonly property string probePath: raiz + "/scripts/apply-keys.sh"

    property var applyStatus: ({})          // action -> "set" | "busy" | "fail"
    property string lastSummary: ""
    property string luaPath: ""             // "" = not a Lua fork / not written
    property bool hyprctlMissing: false
    property bool applierMissing: false     // script never ran (bad sync?)
    property bool bindsMissing: false       // hyprctl gave no bind list
    property bool rerunPending: false

    function apply() {
        if (applyProc.running) {
            rerunPending = true
            return
        }
        const args = ["sh", probePath, raiz]
        let count = 0
        for (const action in map) {
            const b = map[action]
            if (!b || !b.key || String(b.key).length === 0)
                continue
            args.push(String(b.mods || "") + "|" + String(b.key) + "|" + String(action))
            ++count
        }
        if (count === 0) {
            lastSummary = "no chords configured"
            return
        }
        applyStatus = ({})
        applyProc.command = args
        applyProc.running = true
    }

    function parseResult(text) {
        const lines = String(text).split("\n")
        const st = {}
        let applied = 0, busy = 0, failed = 0, cleared = 0
        hyprctlMissing = false
        applierMissing = false
        bindsMissing = false
        luaPath = ""
        //  A healthy run ALWAYS prints at least "LUA none". Empty output
        //  means the script never ran at all (missing file, failed sync,
        //  bad path) — the old code just reported a useless "0 applied"
        //  here (r23 user report: "keybind kedetec 0").
        if (String(text).trim().length === 0) {
            applierMissing = true
            //  Keep it SHORT (user: "di minimalisir ajala") - one small
            //  line, basename only; the full path stays in probePath.
            lastSummary = "keybind applier missing - re-run start.sh ("
                          + probePath.split("/").pop() + ")"
            autoClear.restart()
            return
        }
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (line.length === 0)
                continue
            if (line.indexOf("NOHYPRCTL") === 0) {
                hyprctlMissing = true
                continue
            }
            if (line.indexOf("NOBINDS") === 0) {
                bindsMissing = true
                continue
            }
            if (line.indexOf("UNBOUND") === 0 || line.indexOf("CANTUNBIND") === 0) {
                ++cleared
                continue
            }
            if (line.indexOf("LUA ") === 0) {
                const p = line.substring(4)
                luaPath = (p === "none") ? "" : p
                continue
            }
            const parts = line.split(" ")
            if (parts[0] === "SET" || parts[0] === "BUSY" || parts[0] === "FAIL") {
                const action = parts[parts.length - 1]
                st[action] = parts[0].toLowerCase()
                if (parts[0] === "SET") ++applied
                else if (parts[0] === "BUSY") ++busy
                else ++failed
            }
        }
        applyStatus = st
        const bits = []
        if (bindsMissing)
            bits.push("hyprctl returned no bind list — is HYPRLAND_INSTANCE_SIGNATURE set in this session?")
        else if (hyprctlMissing) bits.push("hyprctl not found — binds not applied")
        else bits.push(applied + " applied")
        if (busy > 0) bits.push(busy + " taken by other programs")
        if (failed > 0) bits.push(failed + " failed")
        if (cleared > 0) bits.push(cleared + " stale removed")
        if (luaPath.length > 0) bits.push("saved to " + luaPath.split("/").pop())
        else if (!hyprctlMissing && !bindsMissing) bits.push("runtime only (classic config)")
        lastSummary = bits.join(" · ")
        autoClear.restart()
    }

    //  The one-line apply summary is feedback, not furniture - it
    //  fades away after a few seconds so the keybinds page stays
    //  clean (r24 user request: minimize the status noise).
    Timer {
        id: autoClear
        interval: 8000
        onTriggered: hotkeys.lastSummary = ""
    }

    Process {
        id: applyProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: hotkeys.parseResult(text)
        }
        onExited: {
            if (hotkeys.rerunPending) {
                hotkeys.rerunPending = false
                hotkeys.apply()
            }
        }
    }

    //  ── Startup: apply late, then re-assert once (k4 async wipe) ──
    Timer {
        id: bootTimer
        running: true
        repeat: false
        interval: 1500
        onTriggered: {
            hotkeys.apply()
            wipeTimer.restart()
        }
    }
    Timer {
        id: wipeTimer
        interval: 4000
        onTriggered: hotkeys.apply()
    }

    //  ── Key-event decoding for the capture editor ────────────────
    function modsFromEvent(e) {
        const m = e.modifiers
        const out = []
        if (m & Qt.MetaModifier) out.push("SUPER")
        if (m & Qt.ControlModifier) out.push("CTRL")
        if (m & Qt.AltModifier) out.push("ALT")
        if (m & Qt.ShiftModifier) out.push("SHIFT")
        return out
    }

    function keyName(e) {
        const k = e.key
        if (k >= Qt.Key_A && k <= Qt.Key_Z)
            return String.fromCharCode(k)
        if (k >= Qt.Key_0 && k <= Qt.Key_9)
            return String.fromCharCode(k)
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35)
            return "F" + (k - Qt.Key_F1 + 1)
        if (k === Qt.Key_Space) return "SPACE"
        if (k === Qt.Key_Return || k === Qt.Key_Enter) return "Return"
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) return "Tab"
        if (k === Qt.Key_Print) return "Print"
        if (k === Qt.Key_Insert) return "Insert"
        if (k === Qt.Key_Home) return "Home"
        if (k === Qt.Key_End) return "End"
        if (k === Qt.Key_PageUp) return "Prior"
        if (k === Qt.Key_PageDown) return "Next"
        if (k === Qt.Key_Up) return "Up"
        if (k === Qt.Key_Down) return "Down"
        if (k === Qt.Key_Left) return "Left"
        if (k === Qt.Key_Right) return "Right"
        if (k === Qt.Key_CapsLock) return "Caps_Lock"
        if (k === Qt.Key_NumLock) return "Num_Lock"
        if (k === Qt.Key_ScrollLock) return "Scroll_Lock"
        if (k === Qt.Key_Pause) return "Pause"
        if (k === Qt.Key_Comma) return "comma"
        if (k === Qt.Key_Period) return "period"
        if (k === Qt.Key_Slash) return "slash"
        if (k === Qt.Key_Backslash) return "backslash"
        if (k === Qt.Key_Semicolon) return "semicolon"
        if (k === Qt.Key_Apostrophe) return "apostrophe"
        if (k === Qt.Key_BracketLeft) return "bracketleft"
        if (k === Qt.Key_BracketRight) return "bracketright"
        if (k === Qt.Key_Minus) return "minus"
        if (k === Qt.Key_Equal) return "equal"
        if (k === Qt.Key_Grave) return "grave"
        return ""
    }
}
