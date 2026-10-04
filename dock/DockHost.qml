pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../services"

//  ─────────────────────────────────────────────────────────────────
//  DockHost — port of nick-friedrich/hyprland-dock DockHost.qml.
//
//  Upstream reads/writes a standalone ~/.config/hyprland-dock/dock.json
//  (FileView + live reload).  Hyprnotch keeps ONE config document for
//  the whole shell: the settings object below is a reactive view over
//  services/Config.qml's dock section (~/.config/hyprnotch/config.json),
//  and pin/reorder/auto-hide writes go through Config.set()/setList()
//  so Settings → Dock and the dock itself always agree.  Keys and
//  defaults follow upstream exactly.
//  ─────────────────────────────────────────────────────────────────

Item {
    id: root

    readonly property var cfg: Config.data.dock || {}
    readonly property bool dockEnabled: cfg.enabled !== false
    readonly property bool primaryOnly: cfg.primaryOnly === true
    readonly property string primaryName:
        primaryOnly && Quickshell.screens.length > 0
            ? Quickshell.screens[0].name : ""

    function num(value, fallback) {
        const n = Number(value)
        return value === undefined || value === null || isNaN(n) ? fallback : n
    }

    //  Same shape as upstream's dock.json document.
    readonly property var settings: ({
        iconSize: num(cfg.iconSize, 42),
        magnification: num(cfg.magnification, 1.2),
        magnificationRadius: num(cfg.magnificationRadius, 95),
        margin: num(cfg.margin, 10),
        backgroundOpacity: num(cfg.backgroundOpacity, 0.88),
        position: typeof cfg.position === "string" ? cfg.position : "bottom",
        fullLength: cfg.fullLength === true,
        reserveSpace: cfg.reserveSpace !== false,
        autoHide: cfg.autoHide === true,
        hideDelay: num(cfg.hideDelay, 800),
        clickAction: typeof cfg.clickAction === "string" ? cfg.clickAction : "focus-or-launch",
        pinned: pins()
    })

    function pins() {
        const raw = cfg.pinned
        const out = []
        if (raw && raw.length !== undefined)
            for (let i = 0; i < raw.length; ++i)
                if (typeof raw[i] === "string")
                    out.push(raw[i])
        return out
    }

    function savePinned(pinned) {
        Config.setList("dock.pinned", pinned)
    }

    function reorderPinned(from, to) {
        const current = pins()
        if (from === to || from < 0 || to < 0
            || from >= current.length || to >= current.length)
            return

        const next = current.slice()
        const moved = next.splice(from, 1)[0]
        next.splice(to, 0, moved)

        savePinned(next)
    }

    function pinApplication(desktopId) {
        if (!desktopId || pins().indexOf(desktopId) >= 0) return

        const next = pins().slice()
        next.push(desktopId)
        savePinned(next)
    }

    function unpinApplication(desktopId) {
        const index = pins().indexOf(desktopId)
        if (index < 0) return

        const next = pins().slice()
        next.splice(index, 1)
        savePinned(next)
    }

    function setAutoHide(enabled) {
        Config.set("dock.autoHide", enabled)
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Dock {
                required property var modelData
                screen: modelData
                settings: root.settings
                screenEnabled: root.dockEnabled
                    && (!root.primaryOnly || modelData.name === root.primaryName)
                onReorderRequested: (from, to) => root.reorderPinned(from, to)
                onPinRequested: desktopId => root.pinApplication(desktopId)
                onUnpinRequested: desktopId => root.unpinApplication(desktopId)
                onAutoHideRequested: enabled => root.setAutoHide(enabled)
                onSettingsRequested: Power.openSettings("dock")
            }
        }
    }
}
