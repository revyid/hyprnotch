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
        { action: "podman",        mods: "SUPER", key: "P" }
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
        podman:        { title: "Containers",      sub: "podman manager page" }
    })

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
    //  was loaded from — quickshell always runs the synced copy, so
    //  `quickshell ipc -p <raiz>/shell.qml` targets THIS instance.
    readonly property string raiz: {
        const u = Qt.resolvedUrl("../shell.qml").toString()
        const p = u.replace(/^file:\/\//, "").replace(/\/shell\.qml$/, "")
        return decodeURIComponent(p)
    }
    readonly property string probePath: raiz + "/scripts/apply-keys.sh"

    property var applyStatus: ({})          // action -> "set" | "busy" | "fail"
    property string lastSummary: ""
    property string luaPath: ""             // "" = not a Lua fork / not written
    property bool hyprctlMissing: false
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
        luaPath = ""
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (line.length === 0)
                continue
            if (line.indexOf("NOHYPRCTL") === 0) {
                hyprctlMissing = true
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
        if (hyprctlMissing) bits.push("hyprctl not found — binds not applied")
        else bits.push(applied + " applied")
        if (busy > 0) bits.push(busy + " taken by other programs")
        if (failed > 0) bits.push(failed + " failed")
        if (cleared > 0) bits.push(cleared + " stale removed")
        if (luaPath.length > 0) bits.push("saved to " + luaPath.split("/").pop())
        else if (!hyprctlMissing) bits.push("runtime only (classic config)")
        lastSummary = bits.join(" · ")
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
