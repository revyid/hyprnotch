pragma Singleton

//  Hyprland bridge: sorted workspaces, focused workspace, running
//  toplevels (for the dock), and a small event feed consumers can bind to.

import QtQuick
import Quickshell
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
        dispatch("workspace " + id)
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

    //  ── Dispatch (k4 / Lua-fork compatible) ─────────────────────
    //  Mainline Hyprland wants  dispatch workspace 2.
    //  The k4 Lua fork wraps the request verbatim into Lua:
    //      return hl.dispatch(workspace 2)      <- syntax error
    //  so the args must be a valid Lua argument LIST. Quoting every
    //  token keeps the intent readable by both worlds:
    //      return hl.dispatch("workspace", 2)   <- works on k4
    //  On mainline Hyprland set config key hypr.luaDispatch = false.
    function luaArgs(s) {
        const parts = String(s).trim().split(/\s+/)
        const out = []
        for (let i = 0; i < parts.length; ++i) {
            const p = parts[i]
            if (p.length === 0)
                continue
            if ((p.charAt(0) === '"' && p.charAt(p.length - 1) === '"')
                || (p.charAt(0) === "'" && p.charAt(p.length - 1) === "'"))
                out.push(p)
            else
                out.push('"' + p.replace(/"/g, '\\"') + '"')
        }
        return out.join(", ")
    }

    //  Fire-and-forget dispatch for custom bindings from Settings.
    function dispatch(args) {
        if (Config.get("hypr.luaDispatch", true))
            Hyprland.dispatch(luaArgs(args))
        else
            Hyprland.dispatch(args)
    }
}
