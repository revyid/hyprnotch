import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

//  macOS-style dock with REAL application icons.
//
//  Icons come from the system: Quickshell's icon theme engine resolves
//  each window class through DesktopEntries (.desktop id, StartupWMClass
//  and theme icon names) — the same three-pass strategy k4 uses, so
//  Firefox looks like Firefox instead of a nerd-font glyph.
//
//  Model = pinned entries (real apps by .desktop id, legacy glyph pins
//  still supported) + every running app not already pinned. Clicking a
//  pinned app focuses it if it runs, otherwise launches it via its
//  desktop entry. Unpinned running apps click to focus.
//
//  The macOS anatomy lives in DockIcon: shadowed icon, no tile, running
//  dot BELOW, magnification wave, launch bounce, tooltip.

Item {
    id: dockRoot

    readonly property var cfg: Config.data.dock
    readonly property int iconSize: cfg.iconSize
    readonly property int dockHeight: cfg.dockHeight

    //  Headroom above the icon row: magnified icons rise into this.
    readonly property int headroom: Math.round(iconSize * 0.55) + 12

    //  ── Magnification source of truth ─────────────────────────────
    property int hoverIndex: -1

    Timer {
        id: hoverReset
        interval: 90
        onTriggered: dockRoot.hoverIndex = -1
    }

    function noteHover(i, hovered) {
        if (hovered) {
            hoverReset.stop()
            hoverIndex = i
        } else if (hoverIndex === i) {
            hoverReset.restart()
        }
    }

    function magnifyFor(i) {
        if (!cfg.magnify || hoverIndex < 0)
            return 0
        const d = Math.abs(i - hoverIndex)
        if (d > 2)
            return 0
        const falloff = [1.0, 0.45, 0.16]
        return falloff[d] * iconSize * 0.5
    }

    //  ── DesktopEntries helpers ────────────────────────────────────
    function findEntry(idLower) {
        if (!idLower || idLower.length === 0)
            return null
        const apps = DesktopEntries.applications.values
        const bare = String(idLower).toLowerCase().replace(/\.desktop$/, "")
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const aid = String(a.id || "").toLowerCase().replace(/\.desktop$/, "")
            if (aid === bare)
                return a
        }
        return null
    }

    //  Window class → icon URL, three passes from cheap to expensive
    //  (k4's exact strategy: theme name, lowercase, desktop entries).
    function iconForClass(cls) {
        const id = String(cls || "")
        if (id.length === 0)
            return ""
        let r = Quickshell.iconPath(id, true)
        if (r)
            return r
        r = Quickshell.iconPath(id.toLowerCase(), true)
        if (r)
            return r
        const apps = DesktopEntries.applications.values
        const bajo = id.toLowerCase()
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const suyo = String(a.id || "").toLowerCase()
            if (suyo === bajo || suyo.indexOf(bajo) !== -1
                || String(a.name || "").toLowerCase() === bajo) {
                const p = Quickshell.iconPath(a.icon, true)
                if (p)
                    return p
            }
        }
        return ""
    }

    function nameForClass(cls) {
        const bajo = String(cls || "").toLowerCase()
        if (bajo.length === 0)
            return "Window"
        const e = findEntry(bajo)
        if (e && e.name)
            return e.name
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const suyo = String(a.id || "").toLowerCase()
            if (suyo === bajo || suyo.indexOf(bajo) !== -1)
                return a.name || cls
        }
        return cls
    }

    //  ── Pinned model: ids (new) + legacy {label,glyph,command} ────
    //  An empty config falls back to SUGGESTED pins: the first installed
    //  entry per common category, so a fresh install shows real icons
    //  without any setup.
    readonly property var suggestedPins: {
        const cats = [
            ["firefox", "zen-browser", "librewolf", "chromium", "brave-browser", "org.chromium.Chromium", "vivaldi-stable", "microsoft-edge"],
            ["org.gnome.Nautilus", "dolphin", "thunar", "nemo", "pcmanfm"],
            ["kitty", "alacritty", "foot", "wezterm", "org.wezfurlong.wezterm", "konsole", "gnome-terminal"],
            ["code", "code-oss", "Visual Studio Code", "sublime_text"],
            ["spotify", "com.spotify.Client", "rhythmbox", "elisa"]
        ]
        const out = []
        const apps = DesktopEntries.applications.values
        for (let c = 0; c < cats.length; ++c) {
            for (let i = 0; i < apps.length; ++i) {
                const aid = String(apps[i].id || "").toLowerCase()
                if (cats[c].indexOf(aid) >= 0) {
                    out.push(aid)
                    break
                }
            }
        }
        return out
    }

    readonly property var pinnedModel: {
        const raw = cfg.pinned
        const list = (raw && raw.length > 0) ? raw : suggestedPins
        const out = []
        for (let i = 0; i < list.length; ++i) {
            const p = list[i]
            if (typeof p === "string") {
                const e = findEntry(p)
                if (e) {
                    out.push({
                        kind: "app",
                        id: String(e.id || "").toLowerCase().replace(/\.desktop$/, ""),
                        name: e.name || p,
                        icon: Quickshell.iconPath(e.icon, true),
                        cls: String(e.startupClass || p).toLowerCase()
                    })
                } else {
                    //  id without an entry: resolve by theme icon
                    const ic = iconForClass(p)
                    if (ic.length > 0)
                        out.push({ kind: "app", id: p, name: nameForClass(p), icon: ic, cls: p.toLowerCase() })
                }
            } else if (p && typeof p === "object" && p.id !== undefined) {
                const e2 = findEntry(String(p.id))
                if (e2)
                    out.push({
                        kind: "app",
                        id: String(e2.id || "").toLowerCase().replace(/\.desktop$/, ""),
                        name: p.label || e2.name || p.id,
                        icon: Quickshell.iconPath(e2.icon, true),
                        cls: String(e2.startupClass || p.id).toLowerCase()
                    })
            } else if (p && typeof p === "object" && p.label !== undefined) {
                //  legacy glyph pin — still first-class
                out.push({
                    kind: "cmd",
                    name: p.label,
                    glyph: p.glyph || Icons.circle,
                    command: p.command || ""
                })
            }
        }
        return out
    }

    function classClaimedByPinned(cls) {
        const bajo = String(cls || "").toLowerCase()
        for (let i = 0; i < pinnedModel.length; ++i) {
            const p = pinnedModel[i]
            if (p.kind !== "app")
                continue
            if (p.id === bajo || p.cls === bajo || nameForClass(bajo).toLowerCase() === String(p.name).toLowerCase())
                return true
        }
        return false
    }

    //  ── Running (unpinned) model ──────────────────────────────────
    readonly property var runningApps: {
        const out = []
        if (!cfg.showRunning)
            return out
        const classes = Hypr.runningClasses
        for (let i = 0; i < classes.length; ++i) {
            const cls = classes[i]
            if (classClaimedByPinned(cls))
                continue
            out.push({
                cls: cls,
                name: nameForClass(cls),
                icon: iconForClass(cls)
            })
        }
        return out
    }

    readonly property bool dividerVisible: cfg.showRunning
        && runningApps.length > 0 && pinnedModel.length > 0

    //  ── Dock window ───────────────────────────────────────────────
    PanelWindow {
        id: dockWindow

        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        color: "transparent"
        exclusiveZone: dockRoot.cfg.autoHide ? -1 : dockRoot.dockHeight + 10
        visible: dockRoot.cfg.enabled
        implicitHeight: dockRoot.dockHeight + dockRoot.headroom

        Rectangle {
            id: tray
            height: dockRoot.dockHeight + dockRoot.headroom
            width: dockRow.implicitWidth + 28
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dockRoot.cfg.autoHide
                ? (dockRevealed || dockHover.containsMouse ? 6 : -tray.height - 8)
                : 6
            radius: 24
            //  Same material as the notch itself (r16): the solid island
            //  fill instead of a watery translucent gray — the dock and
            //  the pill now read as one system.
            color: Theme.islandBg
            border.width: 1
            border.color: Theme.withAlpha(Theme.ink, 0.12)

            Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingType } }

            //  Glass read: vertical sheen + top hairline gloss
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.withAlpha(Theme.ink, 0.16) }
                    GradientStop { position: 0.12; color: Theme.withAlpha(Theme.ink, 0.05) }
                    GradientStop { position: 0.55; color: "transparent" }
                    GradientStop { position: 1.0; color: Theme.withAlpha(Theme.ink, 0.03) }
                }
            }
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 1
                radius: 1
                color: Theme.withAlpha(Theme.ink, 0.22)
            }

            MouseArea {
                id: dockHover
                anchors.fill: parent
                hoverEnabled: true
            }

            RowLayout {
                id: dockRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                spacing: 10

                //  ── Pinned launchers ──────────────────────────────
                Repeater {
                    id: pinnedRepeater
                    model: dockRoot.pinnedModel

                    delegate: DockIcon {
                        id: pin
                        required property var modelData
                        required property int index
                        iconSize: dockRoot.iconSize
                        isApp: pin.modelData.kind === "app"
                        iconSource: pin.isApp ? (pin.modelData.icon || "") : ""
                        glyphChar: pin.isApp ? "" : (pin.modelData.glyph || Icons.circle)
                        label: pin.modelData.name
                        running: dockRoot.cfg.showRunning
                            && (Hypr.runningClasses.indexOf(pin.modelData.cls || pin.modelData.name.toLowerCase()) >= 0
                                || Hypr.focusedClass === (pin.modelData.cls || pin.modelData.name.toLowerCase()))
                        active: dockRoot.cfg.showRunning && Hypr.focusedClass === (pin.modelData.cls || pin.modelData.name.toLowerCase())
                        grow: dockRoot.magnifyFor(pin.index)
                        onTileHovered: function (h) { dockRoot.noteHover(pin.index, h) }
                        onClicked: {
                            if (pin.isApp) {
                                pin.bounce()
                                dockRoot.launchApp(pin.modelData)
                            } else {
                                pin.bounce()
                                dockRoot.launch(pin.modelData)
                            }
                        }
                    }
                }

                //  Divider between pinned and running windows
                Rectangle {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 9
                    width: 1
                    height: dockRoot.iconSize - 8
                    color: Theme.withAlpha(Theme.ink, 0.18)
                    visible: dockRoot.dividerVisible
                }

                //  ── Running (unpinned) windows — real icons ───────
                Repeater {
                    id: runRepeater
                    model: dockRoot.runningApps

                    delegate: DockIcon {
                        id: run
                        required property var modelData
                        required property int index
                        readonly property int flatIndex: pinnedRepeater.count + (dockRoot.dividerVisible ? 1 : 0) + run.index
                        iconSize: dockRoot.iconSize
                        isApp: true
                        iconSource: run.modelData.icon || ""
                        glyphChar: run.modelData.icon.length > 0 ? "" : Icons.window
                        label: run.modelData.name
                        running: true
                        active: run.modelData.cls === Hypr.focusedClass
                        grow: dockRoot.magnifyFor(run.flatIndex)
                        onTileHovered: function (h) { dockRoot.noteHover(run.flatIndex, h) }
                        onClicked: Hypr.dispatch("focuswindow class:" + run.modelData.cls)
                    }
                }
            }
        }
    }

    //  ── Wake-up strip for auto-hide ───────────────────────────────
    PanelWindow {
        id: wakeStrip

        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        color: "transparent"
        exclusiveZone: -1
        visible: dockRoot.cfg.enabled && dockRoot.cfg.autoHide && !dockRevealed
        implicitHeight: 4

        MouseArea {
            id: wakeArea
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: if (containsMouse) dockRevealed = true
        }
    }

    property bool dockRevealed: false

    Timer {
        id: tuckTimer
        interval: 600
        onTriggered: dockRoot.dockRevealed = false
    }

    onDockRevealedChanged: if (dockRevealed) tuckTimer.stop()

    //  Keep the dock out when the cursor leaves it
    Timer {
        interval: 250
        running: dockRoot.cfg.enabled && dockRoot.cfg.autoHide
        repeat: true
        onTriggered: {
            if (dockRoot.dockRevealed && !dockHover.containsMouse && !wakeArea.containsMouse)
                tuckTimer.restart()
        }
    }

    //  ── Launch helpers ────────────────────────────────────────────
    function launchApp(pin) {
        //  Running → focus its window; else execute the desktop entry.
        const cls = pin.cls || pin.id
        if (Hypr.runningClasses.indexOf(cls) >= 0) {
            Hypr.dispatch("focuswindow class:" + cls)
            return
        }
        const e = findEntry(pin.id)
        if (e) {
            try { e.execute() } catch (err) { console.warn("dock: launch failed:", err) }
            return
        }
        if (pin.command && pin.command.length > 0)
            Power.run(pin.command)
    }

    function launch(pin) {
        if (pin.command && pin.command.length > 0) {
            Power.run(pin.command)
            return
        }
        //  Guess a command from the label: "Terminal" → terminal binary
        const guess = pin.name.toLowerCase()
        Power.run(`sh -c 'command -v ${guess} >/dev/null && exec ${guess} || echo "hyprnotch: no command for ${pin.name}" &'`)
    }
}
