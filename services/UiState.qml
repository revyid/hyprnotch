pragma Singleton

//  Central UI state: which view the island is hosting. Exactly one at a
//  time — opening one closes the others, k4 style. Every interface
//  (control center, calendar, notifications, launcher, weather, stats,
//  wallpaper, power, about, plugins) lives INSIDE the island pill:
//  UiState only names the occupant, IslandWindow does the expanding.
//
//  Plugin views are named "plugin:<index-in-Plugins.active>".

import QtQuick
import Quickshell

Singleton {
    id: ui

    //  none → folded pill; anything else → the island grows to host it.
    readonly property var popups: [
        "none", "controlCenter", "calendar", "notifCenter", "launcher",
        "weather", "stats", "wallpaper", "power", "about", "plugins"
    ]

    property string activePopup: "none"

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

    function togglePopup(name) {
        if (!isValid(name))
            return
        activePopup = (activePopup === name) ? "none" : name
    }

    function openPopup(name) {
        if (!isValid(name))
            return
        activePopup = name
    }

    function closeAll() {
        activePopup = "none"
    }
}
