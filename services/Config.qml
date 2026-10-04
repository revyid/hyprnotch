pragma Singleton

//  HyprNotch configuration service — the customization core.
//
//  Everything the shell can do is driven by one JSON document stored at
//  ~/.config/hyprnotch/config.json. Every widget, popup, tile, slider,
//  quick action and dock entry reads from here, and the Settings window
//  writes through Config.set(), so the whole UI updates live.
//
//  Reactivity model: `data` is a single `var` property. set() never
//  mutates in place — it clones, applies, and reassigns, so every
//  binding like `Config.data.dock.iconSize` re-evaluates instantly.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: config

    //  ── Defaults ──────────────────────────────────────────────────
    readonly property var defaults: ({
        general: {
            accent: "#0a84ff",
            animations: true,
            cfgVersion: 6
        },
        island: {
            enabled: true,
            showDate: true,
            showWeather: true,
            showWorkspaces: true,
            showAudio: true,
            showMic: true,
            showNetwork: true,
            showBattery: true,
            pillHeight: 34,
            clockOpensCalendar: true,
            maxVisibleWorkspaces: 5,
            peekEnabled: true
        },
        controlCenter: {
            enabled: true,
            width: 360,
            tileColumns: 2,
            sections: ["toggles", "system", "weather", "sliders", "media", "quickActions", "plugins", "tasks"],
            sectionEnabled: {
                toggles: true, system: true, weather: true, sliders: true, media: true,
                quickActions: true, plugins: true, tasks: true
            }
        },
        quickActions: [
            { id: "dnd",       label: "Do Not Disturb", glyph: "\uF1F6", command: "", builtin: "dnd",        enabled: true },
            { id: "night",     label: "Night Light",    glyph: "\uF186", command: "", builtin: "night",      enabled: true },
            { id: "screenshot",label: "Screenshot",     glyph: "\uF030", command: "sh -c 'command -v grimblast >/dev/null && grimblast save area || (command -v grim >/dev/null && grim -g \"$(slurp)\" ~/Pictures/shot.png)'", builtin: "", enabled: true },
            { id: "record",    label: "Record",         glyph: "\uF03D", command: "", builtin: "record",     enabled: true },
            { id: "terminal",  label: "Terminal",       glyph: "\uF120", command: "", builtin: "terminal",   enabled: true },
            { id: "files",     label: "Files",          glyph: "\uF07B", command: "", builtin: "files",      enabled: true },
            { id: "wallpaper", label: "Wallpaper",      glyph: "\uF03E", command: "", builtin: "wallpaper",   enabled: true },
            { id: "stats",     label: "System Stats",   glyph: "\uF080", command: "", builtin: "stats",       enabled: true },
            { id: "power",     label: "Power & Battery",glyph: "\uF011", command: "", builtin: "power",       enabled: true },
            { id: "lock",      label: "Lock",           glyph: "\uF023", command: "", builtin: "lock",        enabled: true },
            { id: "about",     label: "About This Mac", glyph: "\uF179", command: "", builtin: "about",       enabled: true },
            { id: "settings",  label: "Settings",       glyph: "\uF013", command: "", builtin: "settings",   enabled: true }
        ],
        dock: {
            enabled: true,
            //  nick-friedrich/hyprland-dock behavior model (port):
            //  autoHide = hide until the pointer touches the screen edge
            //  (toggle also lives in the dock's right-click menu),
            //  reserveSpace = tiled windows stop beside the dock.
            autoHide: false,
            hideDelay: 800,
            iconSize: 42,
            magnification: 1.2,
            magnificationRadius: 95,
            margin: 10,
            backgroundOpacity: 0.88,
            position: "bottom",
            fullLength: false,
            reserveSpace: true,
            clickAction: "focus-or-launch",
            //  r24: the Liquid Glass shader is gone (user request) — the
            //  bar is a translucent frosted surface blurred by the
            //  compositor (layerrule blur, namespace hyprnotch-dock).
            //  blur=false turns the compositor blur back off.
            blur: true,
            primaryOnly: false,
            //  .desktop ids — unknown ids are skipped, so this list is
            //  safe on any machine.  Managed live from the dock itself
            //  (right-click → Add Application / Remove, drag to reorder).
            pinned: [
                "org.gnome.Nautilus", "org.kde.dolphin", "thunar",
                "firefox", "zen", "chromium", "google-chrome",
                "kitty", "com.mitchellh.ghostty", "Alacritty", "foot",
                "code", "discord", "spotify", "steam", "obsidian"
            ]
        },
        calendar: {
            enabled: true,
            firstDayMonday: true,
            showWeekNumbers: false
        },
        notifications: {
            enabled: true,
            dnd: false,
            duration: 5,
            maxVisible: 3
        },
        wallpaper: {
            enabled: true,
            dir: "",
            transition: "grow",
            duration: 0.8
        },
        plugins: {
            enabled: true,
            disabled: []
        },
        hud: {
            enabled: true,
            timeout: 1600
        },
        launcher: {
            enabled: true
        },
        //  ── Clipboard history (r24) ──────────────────────────────────
        //  Backed by cliphist (wl-clipboard): start.sh launches the
        //  store daemon; the notch panel reads/wipes the history.
        clipboard: {
            enabled: true,
            maxPreview: 90
        },
        //  Chord map is managed by services/Hotkeys.qml — defaults live
        //  there; saved edits land under keybinds.map and win. An entry
        //  { mods:"", key:"" } means the user deliberately unbound it.
        keybinds: {
            map: {}
        },
        tasks: {
            enabled: true
        },
        podman: {
            enabled: true
        },
        agent: {
            enabled: true,
            command: "hermes",
            useShell: true
        },
        system: {
            pollSeconds: 3
        }
    })

    //  ── Live document ─────────────────────────────────────────────
    property var data: JSON.parse(JSON.stringify(defaults))
    property bool loaded: false

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") && Quickshell.env("XDG_CONFIG_HOME").length > 0)
        ? Quickshell.env("XDG_CONFIG_HOME") : homeDir + "/.config"
    readonly property string filePath: configDir + "/hyprnotch/config.json"

    //  ── Read helpers ──────────────────────────────────────────────
    function get(path, fallback) {
        const parts = path.split(".")
        let node = data
        for (let i = 0; i < parts.length; ++i) {
            if (node === undefined || node === null || node[parts[i]] === undefined)
                return fallback
            node = node[parts[i]]
        }
        return node
    }

    //  ── Write (clone → apply → reassign → schedule save) ─────────
    function set(path, value) {
        const parts = path.split(".")
        const copy = JSON.parse(JSON.stringify(data))
        let node = copy
        for (let i = 0; i < parts.length - 1; ++i) {
            if (node[parts[i]] === undefined || typeof node[parts[i]] !== "object")
                node[parts[i]] = {}
            node = node[parts[i]]
        }
        node[parts[parts.length - 1]] = value
        data = copy
        saveTimer.restart()
    }

    //  Convenience for whole-array replacements (sections order, quick
    //  actions, dock pins...). Assigning a NEW array keeps reactivity.
    function setList(path, arrayValue) {
        set(path, arrayValue)
    }

    function moveItem(arrayPath, from, to) {
        if (to < 0)
            return
        const arr = JSON.parse(JSON.stringify(get(arrayPath, [])))
        if (from < 0 || from >= arr.length || to >= arr.length)
            return
        const item = arr.splice(from, 1)[0]
        arr.splice(to, 0, item)
        setList(arrayPath, arr)
    }

    //  ── Persistence ───────────────────────────────────────────────
    FileView { id: store; path: config.filePath; blockLoading: true }

    Process {
        id: mkDir
        command: ["mkdir", "-p", config.configDir + "/hyprnotch"]
        running: true
        onExited: config.load()
    }

    Timer {
        id: saveTimer
        interval: 400
        running: false
        repeat: false
        onTriggered: config.save()
    }

    function load() {
        const raw = store.text()
        let disk = null
        if (raw && raw.length > 0) {
            try {
                disk = JSON.parse(raw)
                data = deepMerge(JSON.parse(JSON.stringify(defaults)), disk)
            } catch (e) {
                //  Unreadable config: keep factory defaults, do not crash.
                console.warn("[Config] corrupt config.json, using defaults:", e)
            }
        }
        //  One-shot migrations.
        //  v2: older saved configs froze stale dock/peek flags, which could
        //      leave the dock invisible and the hover peek dead. Restore the
        //      intended defaults once, and make sure the plugins section
        //      exists in the control center.
        //  v3: the System section (About This Device / Monitor / Wallpaper
        //      entries) did not exist yet — inject it after the toggles.
        //  v4: the dock became the Swift-Dock port — hideMode replaces the
        //      autoHide flag, and pins are .desktop id strings (legacy
        //      {label,glyph,command} pins are dropped for Swift-Dock's set).
        //  v5: the dock became the hyprland-dock (nick-friedrich) port —
        //      hideMode collapses back into the autoHide flag (smart and
        //      always map to true, never to false) and edgeMargin renames
        //      to margin.  The Swift-Dock-only knobs (spacing, cornerRadius,
        //      labels/indicators/bounce/trash/thumbs, magnify) are no longer
        //      read — stale keys simply sit unused in the file.
        //  v6: Liquid Glass removed by user request ("remove liquid glass,
        //      ganti blur frost") — dock.liquid/glassOpacity are dropped
        //      and replaced by dock.blur; the clipboard feature section
        //      gains its enabled flag.
        const ver = (disk && disk.general && disk.general.cfgVersion) || 1
        if (ver < 2) {
            data.dock.enabled = true
            data.island.peekEnabled = true
            if (data.controlCenter.sections.indexOf("plugins") < 0)
                data.controlCenter.sections.push("plugins")
        }
        if (ver < 3) {
            const at = data.controlCenter.sections.indexOf("toggles")
            if (at >= 0)
                data.controlCenter.sections.splice(at + 1, 0, "system")
            else
                data.controlCenter.sections.unshift("system")
        }
        if (ver < 4) {
            data.dock.hideMode = data.dock.autoHide === true ? "always" : "smart"
            const cleanPins = Array.isArray(data.dock.pinned)
                ? data.dock.pinned.filter(function (p) { return typeof p === "string" })
                : []
            if (cleanPins.length === 0)
                data.dock.pinned = JSON.parse(JSON.stringify(defaults.dock.pinned))
            else
                data.dock.pinned = cleanPins
        }
        if (ver < 5) {
            data.dock.autoHide = data.dock.hideMode !== "never"
            if (typeof data.dock.edgeMargin === "number")
                data.dock.margin = Math.max(0, Math.min(60, data.dock.edgeMargin))
            if (typeof data.dock.iconSize !== "number")
                data.dock.iconSize = 42
            const v5pins = Array.isArray(data.dock.pinned)
                ? data.dock.pinned.filter(function (p) { return typeof p === "string" })
                : []
            if (v5pins.length === 0)
                data.dock.pinned = JSON.parse(JSON.stringify(defaults.dock.pinned))
            else
                data.dock.pinned = v5pins
        }
        if (ver < 6) {
            delete data.dock.liquid
            delete data.dock.glassOpacity
            if (typeof data.dock.blur !== "boolean")
                data.dock.blur = true
            if (!data.clipboard || typeof data.clipboard !== "object")
                data.clipboard = JSON.parse(JSON.stringify(defaults.clipboard))
            if (typeof data.clipboard.enabled !== "boolean")
                data.clipboard.enabled = true
        }
        data.general.cfgVersion = 6
        loaded = true
        Theme.accent = data.general.accent || "#0a84ff"
    }

    function save() {
        try {
            store.setText(JSON.stringify(data, null, 2))
        } catch (e) {
            console.warn("[Config] save failed:", e)
        }
    }

    function deepMerge(base, extra) {
        for (const key in extra) {
            if (Array.isArray(extra[key])) {
                base[key] = extra[key]
            } else if (extra[key] && typeof extra[key] === "object") {
                if (!base[key] || typeof base[key] !== "object")
                    base[key] = {}
                deepMerge(base[key], extra[key])
            } else {
                base[key] = extra[key]
            }
        }
        return base
    }

    function resetToDefaults() {
        data = JSON.parse(JSON.stringify(defaults))
        saveTimer.restart()
    }

    onLoaded: theme.accent = data.general.accent || "#0a84ff"
}
