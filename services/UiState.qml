pragma Singleton

//  Central UI state: which view the island is hosting. Exactly one at a
//  time — opening one closes the others, k4 style. Every interface
//  (control center, calendar, notifications, launcher, weather, stats,
//  wallpaper, power, about, plugins, containers, agent, clipboard) lives
//  INSIDE the island pill: UiState only names the occupant, IslandWindow
//  does the expanding.
//
//  Plugin views are named "plugin:<index-in-Plugins.active>".
//
//  r24: swipePages + cyclePopup() power the page deck. r25: the deck
//  moves by HOLD-DRAG only (IslandWindow's DragHandler + morph) — the
//  scroll wheel no longer switches pages, it belongs to whatever list
//  the cursor is over (launcher, clipboard, notifications).

import QtQuick
import Quickshell

Singleton {
    id: ui

    //  none → folded pill; anything else → the island grows to host it.
    readonly property var popups: [
        "none", "controlCenter", "calendar", "notifCenter", "launcher",
        "weather", "stats", "wallpaper", "power", "about", "plugins",
        "containers", "agent", "clipboard"
    ]

    //  The swipe order — the hold-drag page deck. Only pages that
    //  pass isValid + featureAllows participate (a switched-off feature
    //  is skipped, never a dead end).
    readonly property var swipePages: [
        "controlCenter", "notifCenter", "calendar", "launcher", "stats",
        "weather", "wallpaper", "containers", "agent", "clipboard",
        "power", "about", "plugins"
    ]

    property string activePopup: "none"

    //  Which pane the control center opens into ("main" | "wifi" |
    //  "bluetooth" | "features"). The quick-toggles keybind/door sets
    //  this before opening the control center.
    property string controlCenterPane: "main"

    readonly property bool expanded: activePopup !== "none"

    //  Compatibility shim for older code paths: the launcher is now just
    //  another island view, so launcherOpen derives from activePopup.
    readonly property bool launcherOpen: activePopup === "launcher"
    property bool settingsOpen: false
    property string settingsPage: "general"

    function isValid(name) {
        if (popups.indexOf(name) >= 0)
            return true
        if (name.indexOf("plugin:") === 0)
            return Plugins.descriptorForPopup(name) !== null
        return false
    }

    //  ── Per-feature gates (r23, extended r24) ─────────────────────
    //  Settings can switch whole features off; the toggles used to be
    //  write-only (r23 user report: "enable/disable per fitur ga
    //  fungsi"). Every popup entry now respects its feature's
    //  enabled flag, so a switched-off view can never open — from the
    //  pill, a keybind, IPC, a swipe, or a plugin.
    function featureAllows(name) {
        if (name === "controlCenter")
            return Config.get("controlCenter.enabled", true)
        if (name === "launcher")
            return Config.get("launcher.enabled", true)
        if (name === "notifCenter")
            return Config.get("notifications.enabled", true)
        if (name === "calendar")
            return Config.get("calendar.enabled", true)
        if (name === "weather")
            return Config.get("island.showWeather", true)
        if (name === "plugins")
            return Config.get("plugins.enabled", true)
        if (name === "containers")
            return Config.get("podman.enabled", true)
        if (name === "agent")
            return Config.get("agent.enabled", true)
        if (name === "clipboard")
            return Config.get("clipboard.enabled", true)
        return true
    }

    function togglePopup(name) {
        if (!isValid(name) || !featureAllows(name))
            return
        activePopup = (activePopup === name) ? "none" : name
    }

    function openPopup(name) {
        if (!isValid(name) || !featureAllows(name))
            return
        activePopup = name
    }

    //  ── Hold-drag page deck (r24 swipe, r25 hold-drag only) ──────
    //  dir = +1 (next page, drag left) | -1 (previous, drag right).
    //  From the folded pill, a drag just opens the first/last page.
    function cyclePopup(dir) {
        const pages = []
        for (let i = 0; i < swipePages.length; ++i) {
            const p = swipePages[i]
            if (isValid(p) && featureAllows(p))
                pages.push(p)
        }
        if (pages.length === 0)
            return
        let idx = pages.indexOf(activePopup)
        if (idx < 0)
            idx = (dir > 0) ? -1 : 0          // folded → enter at the edge
        idx = (idx + dir + pages.length) % pages.length
        const next = pages[idx]
        if (!isValid(next) || !featureAllows(next))
            return
        activePopup = next
    }

    function closeAll() {
        activePopup = "none"
        controlCenterPane = "main"
    }
}
