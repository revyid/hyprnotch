pragma Singleton

//  Hyprland bridge: sorted workspaces, focused workspace, running
//  toplevels (for the dock), and a small event feed consumers can bind to.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: hypr

    readonly property var workspaces: {
        const values = Hyprland.workspaces ? Hyprland.workspaces.values : []
        const sorted = values.slice()
        sorted.sort((a, b) => a.id - b.id)
        return sorted
    }

    readonly property int focusedWorkspaceId: {
        const mon = Hyprland.focusedMonitor
        if (mon && mon.activeWorkspace)
            return mon.activeWorkspace.id
        return -1
    }

    //  ── Smart workspace list (macOS-style minimalism) ─────────────
    //  Only workspaces that are ACTUALLY alive: the focused one plus any
    //  that hold windows. Idle empty workspaces never show, so a single
    //  desktop renders exactly one pill. The list is capped by
    //  island.maxVisibleWorkspaces — the active pill always survives the
    //  cap, an overflow pill ("+N") takes the last slot when it doesn't.
    readonly property var visibleWorkspaces: {
        const max = Math.max(1, Config.get("island.maxVisibleWorkspaces", 5))
        const all = workspaces
        const alive = []
        for (let i = 0; i < all.length; ++i) {
            const w = all[i]
            const wins = w.lastIpcObject && w.lastIpcObject.windows !== undefined
                ? w.lastIpcObject.windows : 0
            if (w.focused || wins > 0)
                alive.push(w)
        }
        if (alive.length <= max)
            return alive

        //  Cap: keep the first (max-1), then make room for the active one.
        let activeIn = -1
        for (let j = 0; j < alive.length; ++j)
            if (alive[j].focused) { activeIn = j; break }
        const kept = alive.slice(0, max - 1)
        if (activeIn >= max - 1) {
            kept.push(alive[activeIn])
            return kept
        }
        //  Active inside the kept slice — append an overflow marker pill.
        const overflow = alive.length - kept.length
        kept.push({ id: -1, name: "+" + overflow, overflowPill: true })
        return kept
    }

    function switchTo(id) {
        //  A previously-learned strategy is used straight away; otherwise
        //  start from strategy 1 and self-heal from there.
        switchStrategies(id, Math.max(1, goodStrategy))
    }

    //  Strategy that last PROVED to move the focus (1 = the Lua-API
    //  default). Learned once, reused for every later click.
    property int goodStrategy: 1

    //  Self-healing switch: after each attempt, check whether the focus
    //  actually moved. If not, escalate. Whichever wins is remembered,
    //  so the next click takes the working path immediately.
    //
    //  Strategy 1 — Lua Hyprland (0.56+ ships the hl.* Lua API; the k4
    //  build is one of them). The IPC socket evaluates EVERY dispatch
    //  request as
    //        return hl.dispatch(<raw request text>)
    //  so the text itself must BE a Lua expression producing a
    //  dispatcher object (wiki "Dispatchers": hl.dsp.*). A classic
    //  "workspace 2" is a Lua SYNTAX error there, and a bare quoted
    //  name fails with "hl.dispatch: expected a dispatcher" — exactly
    //  what the r21 log showed for our old quoted form.
    //  Strategy 2 — classic mainline text form (pre-Lua Hyprland).
    //  Strategy 3 — hyprctl, the compatibility contract every fork
    //  must keep; silent (no IPC warn spam) as the last resort.
    function switchStrategies(id, strategy) {
        if (strategy === 1)
            Hyprland.dispatch('hl.dsp.focus({ workspace = ' + id + ' })')
        else if (strategy === 2)
            Hyprland.dispatch("workspace " + id)
        else {
            ctlSwitch.command = ["hyprctl", "dispatch", "workspace", String(id)]
            ctlSwitch.running = true
        }
        verify.target = id
        verify.strategy = strategy
        verify.restart()
    }

    //  Fire-and-forget hyprctl runner for strategy 3.
    Process {
        id: ctlSwitch
        stdoutEnabled: false
        stderrEnabled: false
    }

    Timer {
        id: verify
        property int target: -1
        property int strategy: 1
        interval: 380

        onTriggered: {
            if (!hypr || target < 0)
                return
            if (hypr.focusedWorkspaceId === target) {
                if (strategy > 1) {
                    console.info("[Hypr] workspace switch via strategy", strategy)
                    hypr.goodStrategy = strategy
                }
                target = -1
                return
            }
            if (strategy < 3)
                hypr.switchStrategies(target, strategy + 1)
            else
                console.warn("[Hypr] workspace switch to", target,
                             "failed on all strategies")
        }
    }

    //  Running application classes, deduplicated — the dock uses this to
    //  show running indicators next to pinned / unpinned apps.
    readonly property var runningClasses: {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        const seen = {}
        const out = []
        for (let i = 0; i < list.length; ++i) {
            const cls = (list[i].appClass || "").toString()
            if (cls.length > 0 && !seen[cls]) {
                seen[cls] = true
                out.push(cls)
            }
        }
        return out
    }

    readonly property string focusedWindowTitle: {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < list.length; ++i)
            if (list[i].activated)
                return list[i].title || ""
        return ""
    }

    //  Class of the focused window — the dock uses it to mark the
    //  active app (white dot + brighter tile).
    readonly property string focusedClass: {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < list.length; ++i)
            if (list[i].activated)
                return (list[i].appClass || "").toString()
        return ""
    }

    //  ── Dispatch (Hyprland 0.56+ Lua API / classic mainline) ────
    //  Lua Hyprland evaluates every IPC dispatch request as
    //      return hl.dispatch(<raw request text>)
    //  so the text must BE a Lua expression producing a dispatcher
    //  (wiki "Dispatchers": `hl.dsp.*`, fed into `hl.dispatch()`).
    //  Translate the common mainline bind strings into hl.dsp.* calls;
    //  anything unknown passes through unchanged (still correct on
    //  pre-Lua mainline). Set config key hypr.luaDispatch = false to
    //  force the raw classic form everywhere.
    function luaNum(s) {
        const n = Number(s)
        return Number.isFinite(n) ? String(n) : "0"
    }

    function luaStr(s) {
        return "'" + String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"
    }

    function luaTranslate(args) {
        const parts = String(args).trim().split(/\s+/)
        const name = (parts[0] || "").toLowerCase()
        const rest = parts.slice(1).join(" ")
        switch (name) {
        case "exec":
            return rest.length > 0
                ? "hl.dsp.exec_cmd(" + luaStr(rest) + ")" : ""
        case "workspace":
            return "hl.dsp.focus({ workspace = " + luaNum(parts[1]) + " })"
        case "killactive":
            return "hl.dsp.window.close()"
        case "togglefloating":
            return "hl.dsp.window.float({ action = 'toggle' })"
        case "fullscreen":
            return "hl.dsp.window.fullscreen({ action = 'toggle' })"
        case "pin":
            return "hl.dsp.window.pin({ action = 'toggle' })"
        case "pseudo":
            return "hl.dsp.window.pseudo({ action = 'toggle' })"
        case "movetoworkspace":
            return "hl.dsp.window.move({ workspace = " + luaNum(parts[1]) + " })"
        case "movetoworkspacesilent":
            return "hl.dsp.window.move({ workspace = " + luaNum(parts[1])
                   + ", follow = false })"
        case "movefocus":
            return "hl.dsp.focus({ direction = " + luaStr(parts[1] || "l") + " })"
        case "focusmonitor":
            return "hl.dsp.focus({ monitor = " + luaStr(rest) + " })"
        case "togglespecialworkspace":
            return "hl.dsp.workspace.toggle_special(" + luaStr(parts[1] || "") + ")"
        case "reload":
            return "hl.dsp.reload_config()"
        default:
            return ""
        }
    }

    //  Fire-and-forget dispatch for custom bindings from Settings.
    function dispatch(args) {
        if (Config.get("hypr.luaDispatch", true)) {
            const lua = luaTranslate(args)
            if (lua.length > 0) {
                Hyprland.dispatch(lua)
                return
            }
        }
        Hyprland.dispatch(args)
    }
}
