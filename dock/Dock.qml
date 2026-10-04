import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../core"
import "../services"

//  ─────────────────────────────────────────────────────────────────
//  THE DOCK — a faithful port of 0-ss/Swift-Dock (macdock v2) into
//  HyprNotch.  https://github.com/0-ss/Swift-Dock
//
//  Everything that makes Swift-Dock feel like the macOS dock lives
//  here, unchanged in behavior:
//    · pinned apps from real .desktop entries (real icons)
//    · running-but-unpinned apps join after a separator
//    · running indicator dots + launch bounce animation
//    · hover tooltips, left-click focus/cycle-or-launch,
//      middle-click new window, right-click glass context menu
//      (open windows, Keep in Dock / Remove, New Window, Quit)
//    · drag pinned icons to reorder — the others slide aside
//    · Trash item (trash:///) and live window preview cells
//    · cosine pointer-follow magnification wave
//    · smart auto-hide driven by hyprctl (hides only while a tiled
//      window occupies the workspace), reveal from the screen edge
//    · Liquid Glass shader refraction (dock/GlassSurface.qml +
//      dock/liquidglass.frag, same upstream technique)
//    · click-through input mask — only the bar itself takes input,
//      never the invisible strip around it
//
//  Differences from upstream, all deliberate:
//    · settings live in ~/.config/hyprnotch/config.json (services/
//      Config.qml) and are edited in Settings → Dock, not in a
//      separate preferences window; "Dock Preferences…" in the menu
//      opens that page
//    · pins persist into config.json (dock.pinned, .desktop ids)
//    · the wallpaper the glass refracts comes from services/
//      Wallpaper.qml (awww/swww/hyprpaper auto-detection)
//    · dark mode is fixed (HyprNotch is a dark shell) and the accent
//      follows the island accent
// ─────────────────────────────────────────────────────────────────

Item {
    id: dockRoot

    //  ── CONFIG — Swift-Dock's section, mapped onto config.json ────
    readonly property var cfg: Config.data.dock
    readonly property int iconSize: cfg.iconSize
    readonly property real magnification: cfg.magnification
    readonly property bool magnificationEnabled: cfg.magnify
    readonly property int spacing: cfg.spacing
    readonly property int hPad: 10
    readonly property int topPad: 8
    readonly property int bottomPad: 9            // room under icons (dots live here)
    readonly property int cornerRadius: cfg.cornerRadius
    readonly property int margin: cfg.edgeMargin
    readonly property real glassOpacity: cfg.glassOpacity
    readonly property string hideMode: cfg.hideMode
    readonly property int hideDelay: cfg.hideDelay
    readonly property bool showTrash: cfg.showTrash
    readonly property bool showLabels: cfg.showLabels
    readonly property bool showIndicators: cfg.showIndicators
    readonly property bool bounceOnLaunch: cfg.bounce
    readonly property bool showThumbs: cfg.showThumbs
    readonly property string monitor:
        cfg.primaryOnly && Quickshell.screens.length > 0
            ? Quickshell.screens[0].name : ""

    //  Swift-Dock's default pin set — unknown ids are skipped by
    //  rebuild(), so this list is safe on any machine.  Keep in sync
    //  with services/Config.qml dock defaults.
    readonly property var defaultPinned: [
        "org.gnome.Nautilus", "org.kde.dolphin", "thunar",
        "firefox", "zen", "chromium", "google-chrome",
        "kitty", "com.mitchellh.ghostty", "Alacritty", "foot",
        "code", "discord", "spotify", "steam", "obsidian"
    ]

    //  Pins are .desktop id strings (Swift-Dock model).  Legacy glyph
    //  entries from older builds are filtered out defensively.
    readonly property var pinned: {
        const raw = cfg.pinned
        const out = []
        if (raw && raw.length !== undefined)
            for (let i = 0; i < raw.length; ++i)
                if (typeof raw[i] === "string")
                    out.push(raw[i])
        return out
    }

    readonly property real effMag: magnificationEnabled ? magnification : 1
    readonly property int bgHeight: iconSize + topPad + bottomPad
    readonly property int sepWidth: 9
    readonly property real magRadius: (iconSize + spacing) * 2.6
    readonly property int menuRoom: 300
    readonly property int windowHeight:
        Math.ceil(margin + bgHeight + iconSize * (effMag - 1) + 72 + menuRoom)

    property var items: []
    property int appCount: 0
    property int sepCount: 0
    readonly property real totalW0:
        Math.max(0, appCount * (iconSize + spacing)
                   + sepCount * (sepWidth + spacing) - spacing)
    property var launching: ({})
    property var knownKeys: ({})
    property string lastSig: ""

    //  ── LOGIC ─────────────────────────────────────────────────────
    function openPrefs() {
        Power.openSettings("dock")
    }

    function resetPins() {
        Config.setList("dock.pinned", defaultPinned.slice())
        rebuild()
    }

    function lookup(appId) {
        if (!appId) return null
        var e = DesktopEntries.byId(appId)
        if (!e && DesktopEntries.heuristicLookup)
            e = DesktopEntries.heuristicLookup(appId)
        return e
    }

    function keyOf(appId) {
        var e = lookup(appId)
        return (e ? e.id : appId).toLowerCase()
    }

    //  Stable ids so a window's preview cell isn't rebuilt on every refresh
    property var winIdList: []
    property int winIdNext: 1
    function winIdFor(tl) {
        for (var i = 0; i < winIdList.length; i++)
            if (winIdList[i].tl === tl) return winIdList[i].id
        var id = winIdNext++
        winIdList.push({ tl: tl, id: id })
        return id
    }

    function iconSrc(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable")
        if (icon.charAt(0) === "/") return "file://" + icon
        return Quickshell.iconPath(icon, "application-x-executable")
    }

    //  Bumped (debounced) whenever windows open, close or change focus
    property int windowTick: 0
    Timer { id: tickDebounce; interval: 120; onTriggered: dockRoot.windowTick++ }

    //  The window an unpinned app is represented by: focused, else first
    function thumbWindow(key) {
        var w = windowsFor(key)
        for (var i = 0; i < w.length; i++) if (w[i].activated) return w[i]
        return w.length > 0 ? w[0] : null
    }

    function windowsFor(key) {
        var out = []
        var tls = ToplevelManager.toplevels.values
        for (var i = 0; i < tls.length; i++)
            if (tls[i].appId && keyOf(tls[i].appId) === key) out.push(tls[i])
        return out
    }

    function activate(item, forceNew) {
        if (item.kind === "win") { if (item.tl) item.tl.activate(); return }
        if (item.special === "trash") {
            Quickshell.execDetached(["xdg-open", "trash:///"])
            return
        }
        var wins = windowsFor(item.key)
        if (wins.length > 0 && !forceNew) {
            var idx = -1
            for (var i = 0; i < wins.length; i++) if (wins[i].activated) idx = i
            wins[(idx + 1) % wins.length].activate()
            return
        }
        if (item.entry) {
            var L = {}
            for (var k in launching) L[k] = launching[k]
            L[item.key] = Date.now()
            launching = L
            try { item.entry.execute() } catch (err) {
                console.warn("dock: launch failed:", err)
            }
            pruneTimer.restart()
        }
    }

    function togglePin(item) {
        var out = [], found = false
        for (var i = 0; i < pinned.length; i++) {
            var id = String(pinned[i]).replace(/\.desktop$/, "")
            if (id.toLowerCase() === item.key) { found = true; continue }
            out.push(pinned[i])
        }
        if (!found && item.entry) out.push(item.entry.id)
        Config.setList("dock.pinned", out)
        rebuild()
    }

    function reorderPinned(from, to) {
        var vis = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (it.kind === "app" && it.pinned && !it.special) vis.push(it)
            else break
        }
        if (from < 0 || from >= vis.length) return
        var moved = vis.splice(from, 1)[0]
        vis.splice(Math.max(0, Math.min(to, vis.length)), 0, moved)

        var out = [], have = {}
        for (var v = 0; v < vis.length; v++) {
            out.push(vis[v].entry.id)
            have[vis[v].key] = true
        }
        for (var p = 0; p < pinned.length; p++) {
            var id = String(pinned[p]).replace(/\.desktop$/, "")
            if (!have[id.toLowerCase()]) out.push(pinned[p])
        }
        Config.setList("dock.pinned", out)
        rebuild()
    }

    function menuFor(item) {
        var m = []
        if (item.kind === "win") {
            m.push({ kind: "item", label: "Show", run: function () { activate(item, false) } })
            m.push({ kind: "item", label: "Close",
                     run: function () { if (item.tl) item.tl.close() } })
            m.push({ kind: "sep" })
            m.push({ kind: "item", label: "Dock Preferences\u2026", run: function () { dockRoot.openPrefs() } })
            return m
        }
        if (item.special === "trash") {
            m.push({ kind: "item", label: "Open", run: function () { activate(item, false) } })
            m.push({ kind: "sep" })
            m.push({ kind: "item", label: "Dock Preferences\u2026", run: function () { dockRoot.openPrefs() } })
            return m
        }
        var wins = windowsFor(item.key)
        if (wins.length > 0) {
            for (var i = 0; i < wins.length && i < 8; i++) {
                (function (w) {
                    var t = w.title && w.title.length > 0 ? w.title : item.name
                    m.push({ kind: "item", label: (w.activated ? "\u2713  " : "") + t,
                             run: function () { w.activate() } })
                })(wins[i])
            }
            m.push({ kind: "sep" })
        }
        if (item.entry) {
            m.push({ kind: "item", label: item.pinned ? "Remove from Dock" : "Keep in Dock",
                     run: function () { togglePin(item) } })
            m.push({ kind: "item", label: wins.length > 0 ? "New Window" : "Open",
                     run: function () { activate(item, true) } })
        }
        if (wins.length > 0) {
            m.push({ kind: "sep" })
            m.push({ kind: "item", label: "Quit", run: function () {
                var ws = windowsFor(item.key)
                for (var j = 0; j < ws.length; j++) ws[j].close()
            } })
        }

        m.push({ kind: "sep" })
        m.push({ kind: "item", label: "Dock Preferences\u2026", run: function () { dockRoot.openPrefs() } })

        return m
    }

    function rebuild() {
        var tls = ToplevelManager.toplevels.values
        var running = {}
        var runOrder = []
        for (var i = 0; i < tls.length; i++) {
            var id = tls[i].appId
            if (!id) continue
            var k = keyOf(id)
            if (!running[k]) { running[k] = true; runOrder.push({ key: k, appId: id }) }
        }

        var L = {}, now = Date.now(), changed = false
        for (var lk in launching) {
            if (!running[lk] && now - launching[lk] < 8000) L[lk] = launching[lk]
            else changed = true
        }
        if (changed) launching = L

        var list = [], seen = {}
        for (var p = 0; p < pinned.length; p++) {
            var e = DesktopEntries.byId(String(pinned[p]).replace(/\.desktop$/, ""))
            if (!e) continue
            var ek = e.id.toLowerCase()
            if (seen[ek]) continue
            seen[ek] = true
            list.push({ kind: "app", key: ek, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true })
        }

        var extras = []
        for (var r = 0; r < runOrder.length; r++)
            if (!seen[runOrder[r].key]) extras.push(runOrder[r])
        if (extras.length > 0 && list.length > 0) list.push({ kind: "sep" })
        for (var x = 0; x < extras.length; x++) {
            var e2 = lookup(extras[x].appId)
            list.push({ kind: "app", key: extras[x].key,
                        name: e2 ? e2.name : extras[x].appId,
                        icon: e2 ? e2.icon : extras[x].appId.toLowerCase(),
                        entry: e2, running: true, pinned: false })
        }

        //  Window previews: one cell per open window, next to the Trash
        var winItems = [], liveWins = []
        if (showThumbs) {
            for (var w = 0; w < tls.length; w++) {
                var tl = tls[w]
                if (!tl.appId) continue
                var e3 = lookup(tl.appId)
                var wid = winIdFor(tl)
                liveWins.push(tl)
                winItems.push({ kind: "win", key: "win:" + wid, tl: tl,
                                name: e3 ? e3.name : tl.appId,
                                icon: e3 ? e3.icon : tl.appId.toLowerCase(),
                                entry: null, running: false, pinned: false })
            }
        }
        var keep = []
        for (var wi = 0; wi < winIdList.length; wi++)
            if (liveWins.indexOf(winIdList[wi].tl) >= 0) keep.push(winIdList[wi])
        winIdList = keep

        if (showTrash || winItems.length > 0) {
            list.push({ kind: "sep" })
            for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj])
        }
        if (showTrash && winItems.length > 0) list.push({ kind: "sep" })
        if (showTrash) {
            list.push({ kind: "app", key: "__trash", name: "Trash", icon: "user-trash",
                        entry: null, running: false, pinned: true, special: "trash" })
        }

        var firstBuild = (lastSig === "")
        var nowKeys = {}, nA = 0, nS = 0, sig = []
        for (var n = 0; n < list.length; n++) {
            var it = list[n]
            it.nA = nA; it.nS = nS
            if (it.kind === "sep") nS++; else nA++
            if (it.kind !== "sep") {
                it.fresh = !firstBuild && !knownKeys[it.key]
                nowKeys[it.key] = true
            }
            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.icon || ""))
        }
        appCount = nA
        sepCount = nS
        knownKeys = nowKeys

        var s = sig.join("|")
        if (s !== lastSig) { lastSig = s; items = list }
    }

    //  ── SMART HIDE — which monitors have a non-floating window on
    //  their active workspace (hyprctl queries + Hyprland events) ────
    property var busyMonitors: ({})
    property var monData: []
    property bool refreshPending: false

    function refreshBusy() {
        if (!cfg.enabled) return
        if (monProc.running || clientProc.running) { refreshPending = true; return }
        monProc.running = true
    }

    function computeBusy(clients) {
        var busy = {}
        for (var m = 0; m < monData.length; m++) {
            var mon = monData[m]
            var ids = [mon.activeWorkspace ? mon.activeWorkspace.id : -999]
            if (mon.specialWorkspace && mon.specialWorkspace.id !== 0)
                ids.push(mon.specialWorkspace.id)
            for (var c = 0; c < clients.length; c++) {
                var cl = clients[c]
                if (cl.floating || !cl.mapped || cl.hidden) continue
                if (cl.monitor !== mon.id) continue
                if (ids.indexOf(cl.workspace.id) >= 0) { busy[mon.name] = true; break }
            }
        }
        busyMonitors = busy
    }

    Process {
        id: monProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { dockRoot.monData = JSON.parse(text) } catch (err) { }
                clientProc.running = true
            }
        }
    }
    Process {
        id: clientProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { dockRoot.computeBusy(JSON.parse(text)) } catch (err) { }
                if (dockRoot.refreshPending) {
                    dockRoot.refreshPending = false
                    monProc.running = true
                }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            busyDebounce.restart()
            tickDebounce.restart()
        }
    }
    Timer { id: busyDebounce; interval: 60; onTriggered: dockRoot.refreshBusy() }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            dockRoot.rebuild()
            settle.restart()
            tickDebounce.restart()
        }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { dockRoot.rebuild() }
    }
    Connections {
        target: Config
        function onDataChanged() { dockRoot.rebuild() }
    }
    Timer { id: settle; interval: 350; onTriggered: dockRoot.rebuild() }
    Timer { id: pruneTimer; interval: 8200; onTriggered: dockRoot.rebuild() }

    Component.onCompleted: {
        rebuild()
        refreshBusy()
    }

    //  ───────────── UI ─────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: dockRoot.cfg.enabled
                     && (dockRoot.monitor === "" || modelData.name === dockRoot.monitor)

            anchors { left: true; right: true; bottom: true }
            implicitHeight: dockRoot.windowHeight
            color: "transparent"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: dockRoot.hideMode === "never"
                           ? dockRoot.bgHeight + dockRoot.margin : 0

            WlrLayershell.namespace: "hyprnotch-dock"

            mask: Region { item: maskItem }

            Item {
                id: ui
                anchors.fill: parent

                property real mx: 0
                Behavior on mx { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                property bool revealed: false
                property var menuItem: null
                property var menuModel: []
                property real menuCx: 0
                readonly property bool menuOpen: menuItem !== null
                readonly property bool wantsHide: dockRoot.hideMode === "always"
                    || (dockRoot.hideMode === "smart"
                        && dockRoot.busyMonitors[win.modelData.name] === true)
                property bool dragging: false
                property int dragIndex: -1
                property int dragTarget: -1
                property string dragKey: ""
                property real dragPressX: 0
                property real dragDelta: 0
                property real dragShiftW: 0
                property bool justDragged: false

                function pinnedCount() {
                    var n = 0
                    for (var i = 0; i < dockRoot.items.length; i++) {
                        var it = dockRoot.items[i]
                        if (it.kind === "app" && it.pinned && !it.special) n++
                        else break
                    }
                    return n
                }
                function naturalCenter(i) {
                    var c = rep.itemAt(i)
                    return c ? row.mapToItem(ui, c.x + c.width / 2, 0).x : 0
                }
                function beginDrag(index, key, pressX, shiftW) {
                    menuItem = null
                    dragIndex = index
                    dragTarget = index
                    dragKey = key
                    dragPressX = pressX
                    dragDelta = 0
                    dragShiftW = shiftW
                    dragging = true
                }
                function dragUpdate(absX) {
                    dragDelta = absX - dragPressX
                    var center = naturalCenter(dragIndex) + dragDelta
                    var P = pinnedCount(), t = 0
                    for (var j = 0; j < P; j++) {
                        if (j === dragIndex) continue
                        if (naturalCenter(j) < center) t++
                    }
                    dragTarget = t
                }
                function shiftFor(i) {
                    if (dragIndex < i && i <= dragTarget) return -dragShiftW
                    if (dragTarget <= i && i < dragIndex) return dragShiftW
                    return 0
                }
                function endDrag() {
                    var from = dragIndex, to = dragTarget
                    dragging = false
                    dragKey = ""
                    dragIndex = -1
                    dragTarget = -1
                    dragDelta = 0
                    justDragged = true
                    Qt.callLater(function () { ui.justDragged = false })
                    if (to !== from) dockRoot.reorderPinned(from, to)
                }

                readonly property bool tucked:
                    wantsHide && !revealed && !menuOpen && !dragging
                readonly property real refLeft: (width - dockRoot.totalW0) / 2
                readonly property real activeTop:
                    height - dockRoot.margin - dockRoot.bgHeight
                    - dockRoot.iconSize * (dockRoot.effMag - 1) - 12
                readonly property bool active:
                    dragging || (hh.hovered && hh.point.position.y > activeTop && !tucked)
                property real strength: active ? 1 : 0
                Behavior on strength { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                HoverHandler {
                    id: hh
                    onPointChanged: if (hovered && !ui.dragging) ui.mx = point.position.x
                    onHoveredChanged: {
                        if (hovered) { hideTimer.stop(); ui.revealed = true }
                        else hideTimer.restart()
                    }
                }
                Timer {
                    id: hideTimer
                    interval: dockRoot.hideDelay
                    onTriggered: if (!ui.dragging) ui.revealed = false
                }

                //  ── Liquid Glass backdrop: wallpaper + the live windows
                //  behind the Dock, in screen coordinates.  Built from
                //  per-window captures (never a screen grab) so the dock
                //  can't refract itself.  See dock/GlassBackdrop.qml.
                Loader {
                    id: glassBackdrop
                    active: glassFx.ready
                    sourceComponent: GlassBackdrop {
                        x: 0
                        y: -(win.modelData.height - ui.height)
                        screenW: win.modelData.width
                        screenH: win.modelData.height
                        screenName: win.modelData.name || ""
                        zoneTop: win.modelData.height - ui.height - 48
                        live: glassFx.ready && !ui.tucked
                    }
                }

                Item {
                    id: maskItem
                    x: ui.menuOpen ? 0 : dock.x
                    width: ui.menuOpen ? ui.width : dock.width
                    y: ui.menuOpen ? 0
                       : (ui.tucked ? ui.height - 3
                          : (hh.hovered ? ui.activeTop : dock.y))
                    height: ui.height - y
                }

                Item {
                    id: dock
                    width: row.width + dockRoot.hPad * 2
                    height: dockRoot.bgHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ui.height - dockRoot.margin - height
                       + (ui.tucked ? height + dockRoot.margin + 6 : 0)
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    //  ── Liquid Glass: real-time refraction of the backdrop
                    //  (dock/GlassSurface.qml + liquidglass.frag) ─────────
                    GlassSurface {
                        id: glassFx
                        anchors.centerIn: parent
                        backdropItem: glassBackdrop.item
                        glassW: dock.width
                        glassH: dock.height
                        glassX: dock.x
                        glassY: dock.y
                        screenH: win.modelData.height
                        winH: ui.height
                        radius: dockRoot.cornerRadius
                        tint: dockRoot.glassOpacity
                        active: dockRoot.cfg.enabled && dockRoot.cfg.liquid
                    }

                    //  Frosted fallback while the shader is unavailable —
                    //  steps aside the moment the glass compiles.
                    Rectangle {
                        visible: !glassFx.ready
                        anchors.fill: parent
                        radius: dockRoot.cornerRadius
                        color: Qt.rgba(0.10, 0.10, 0.11, dockRoot.glassOpacity)
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.45)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Math.max(0, parent.radius - 1)
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.22)
                        }
                    }

                    Row {
                        id: row
                        spacing: dockRoot.spacing
                        height: dockRoot.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: dockRoot.bottomPad

                        Repeater {
                            id: rep
                            model: dockRoot.items

                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool canDrag:
                                    !isSep && modelData.pinned === true && !modelData.special
                                readonly property bool isDragged:
                                    ui.dragging && modelData.key === ui.dragKey

                                //  App cells always show their plain icon; only window
                                //  cells show a live preview (with the app icon as a
                                //  badge), grouped next to the Trash
                                readonly property var thumbWin:
                                    (!isSep && modelData.kind === "win") ? modelData.tl : null
                                readonly property bool useThumb: thumbWin !== null
                                readonly property bool thumbReady:
                                    useThumb && (sv.hasContent === undefined || sv.hasContent === true)

                                property real dx: {
                                    if (!ui.dragging || isSep) return 0
                                    if (isDragged) return ui.dragDelta
                                    return ui.shiftFor(index)
                                }
                                Behavior on dx {
                                    enabled: !cell.isDragged
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                transform: Translate { x: cell.dx }
                                z: isDragged ? 100 : 0
                                opacity: isDragged ? 0.92 : 1

                                property real appear: modelData.fresh ? 0 : 1
                                Behavior on appear { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                Component.onCompleted: Qt.callLater(function () { cell.appear = 1 })

                                readonly property real c0:
                                    modelData.nA * (dockRoot.iconSize + dockRoot.spacing)
                                    + modelData.nS * (dockRoot.sepWidth + dockRoot.spacing)
                                    + (isSep ? dockRoot.sepWidth : dockRoot.iconSize) / 2
                                readonly property real s: {
                                    if (isSep) return 1
                                    var dist = Math.abs(ui.mx - ui.refLeft - cell.c0)
                                    var R = dockRoot.magRadius
                                    var f = dist < R ? 0.5 * (1 + Math.cos(Math.PI * dist / R)) : 0
                                    return 1 + (dockRoot.effMag - 1) * f * ui.strength
                                }

                                width: isSep ? dockRoot.sepWidth : dockRoot.iconSize * s * appear
                                height: dockRoot.iconSize

                                Rectangle {
                                    visible: cell.isSep
                                    width: 1
                                    height: dockRoot.iconSize * 0.85
                                    anchors.centerIn: parent
                                    color: Qt.rgba(1, 1, 1, 0.28)
                                }

                                Image {
                                    id: img
                                    visible: false
                                    property real lift: 0
                                    width: dockRoot.iconSize * cell.s * cell.appear
                                    height: width
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: lift
                                    source: cell.isSep ? "" : dockRoot.iconSrc(cell.modelData.icon)
                                    sourceSize: Qt.size(
                                        Math.ceil(dockRoot.iconSize * dockRoot.magnification * 1.25),
                                        Math.ceil(dockRoot.iconSize * dockRoot.magnification * 1.25))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                }
                                MultiEffect {
                                    visible: !cell.isSep && !cell.thumbReady
                                    source: img
                                    anchors.fill: img
                                    shadowEnabled: true
                                    shadowColor: "black"
                                    shadowOpacity: 0.32
                                    shadowBlur: 0.55
                                    shadowVerticalOffset: 3
                                    brightness: ma.pressed ? -0.3 : 0.0
                                }

                                //  ── Window thumbnail (same box as the icon, so
                                //  magnification just works) ─────────────────────
                                Item {
                                    id: th
                                    anchors.fill: img
                                    //  Kept (almost) opaque while loading so the
                                    //  capture isn't paused by the renderer
                                    visible: cell.useThumb
                                    opacity: cell.thumbReady ? 1 : 0.01

                                    Rectangle {      // soft drop shadow
                                        x: sv.x
                                        y: sv.y + 3
                                        width: sv.width
                                        height: sv.height
                                        radius: 5
                                        color: Qt.rgba(0, 0, 0, 0.32)
                                    }
                                    ScreencopyView {
                                        id: sv
                                        anchors.centerIn: parent
                                        captureSource: cell.thumbWin
                                        live: !ui.tucked   // only capture while the dock is on screen
                                        readonly property real ar:
                                            (implicitWidth > 0 && implicitHeight > 0)
                                                ? implicitWidth / implicitHeight : 4 / 3
                                        width: Math.min(th.width, th.height * ar)
                                        height: width / ar
                                    }
                                    Rectangle {      // thin frame + pressed dimming
                                        anchors.fill: sv
                                        radius: 3
                                        color: ma.pressed ? Qt.rgba(0, 0, 0, 0.3) : "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.28)
                                    }
                                }
                                //  Small app icon in the corner, so you can tell
                                //  which app the window belongs to
                                Image {
                                    id: badge
                                    visible: cell.thumbReady
                                    width: img.width * 0.46
                                    height: width
                                    x: img.x + img.width - width + 3
                                    y: img.y + img.height - height + 3
                                    source: img.source
                                    sourceSize: Qt.size(
                                        Math.ceil(dockRoot.iconSize * dockRoot.magnification * 0.6),
                                        Math.ceil(dockRoot.iconSize * dockRoot.magnification * 0.6))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                Rectangle {
                                    visible: !cell.isSep && cell.modelData.running
                                             && dockRoot.showIndicators
                                    width: 4; height: 4; radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                }

                                SequentialAnimation {
                                    running: !cell.isSep && dockRoot.bounceOnLaunch
                                             && dockRoot.launching[cell.modelData.key] !== undefined
                                    loops: Animation.Infinite
                                    NumberAnimation { target: img; property: "lift"
                                                      to: dockRoot.iconSize * 0.4
                                                      duration: 260; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"
                                                      to: 0
                                                      duration: 260; easing.type: Easing.InQuad }
                                    onRunningChanged: if (!running) img.lift = 0
                                }

                                Rectangle {
                                    id: tip
                                    visible: opacity > 0
                                    opacity: (dockRoot.showLabels && !cell.isSep && ma.containsMouse
                                              && !ma.pressed && !ui.menuOpen && !ui.dragging) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    z: 10
                                    width: label.implicitWidth + 22
                                    height: label.implicitHeight + 10
                                    radius: 8
                                    color: Qt.rgba(0.12, 0.12, 0.13, 0.72)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height - img.height - img.lift - height - 10

                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        text: cell.isSep ? ""
                                              : ((cell.modelData.kind === "win" && cell.modelData.tl
                                                  && cell.modelData.tl.title)
                                                 ? cell.modelData.tl.title : cell.modelData.name)
                                        color: "white"
                                        font.pixelSize: 13
                                        font.family: Theme.uiFont
                                    }
                                }

                                MouseArea {
                                    id: ma
                                    visible: !cell.isSep
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: -dockRoot.bottomPad
                                    width: cell.width
                                    height: img.height + dockRoot.bottomPad
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    property real pressX: 0

                                    onPressed: mouse => {
                                        if (mouse.button === Qt.LeftButton)
                                            pressX = ma.mapToItem(ui, mouse.x, 0).x
                                    }
                                    onPositionChanged: mouse => {
                                        if (!cell.canDrag || !(pressedButtons & Qt.LeftButton)) return
                                        var ax = ma.mapToItem(ui, mouse.x, 0).x
                                        if (!ui.dragging) {
                                            if (Math.abs(ax - pressX) < 8) return
                                            ui.beginDrag(cell.index, cell.modelData.key,
                                                         pressX, cell.width + dockRoot.spacing)
                                        }
                                        if (cell.isDragged) ui.dragUpdate(ax)
                                    }
                                    onReleased: mouse => {
                                        if (ui.dragging && cell.isDragged) ui.endDrag()
                                    }
                                    onClicked: mouse => {
                                        if (ui.justDragged) return
                                        if (mouse.button === Qt.RightButton) {
                                            ui.menuCx = cell.mapToItem(ui, cell.width / 2, 0).x
                                            ui.menuModel = dockRoot.menuFor(cell.modelData)
                                            ui.menuItem = cell.modelData
                                        } else {
                                            dockRoot.activate(cell.modelData,
                                                              mouse.button === Qt.MiddleButton)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 50
                    visible: ui.menuOpen
                    enabled: ui.menuOpen
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.menuItem = null
                }

                Rectangle {
                    id: menu
                    z: 60
                    visible: opacity > 0
                    opacity: ui.menuOpen ? 1 : 0
                    scale: ui.menuOpen ? 1 : 0.96
                    transformOrigin: Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    width: 230
                    height: menuCol.height + 10
                    x: Math.max(8, Math.min(ui.width - width - 8, ui.menuCx - width / 2))
                    y: ui.height - dockRoot.margin - dockRoot.bgHeight
                       - dockRoot.iconSize * (dockRoot.effMag - 1) - 14 - height
                    radius: 10
                    color: Qt.rgba(0.14, 0.14, 0.15, 0.62)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)

                    Column {
                        id: menuCol
                        x: 5
                        y: 5
                        width: parent.width - 10

                        Repeater {
                            model: ui.menuModel

                            delegate: Item {
                                id: mi
                                required property var modelData
                                readonly property bool isSep: modelData.kind === "sep"
                                width: menuCol.width
                                height: isSep ? 9 : 26

                                Rectangle {
                                    visible: mi.isSep
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 6
                                    width: parent.width - 12
                                    height: 1
                                    color: Qt.rgba(1, 1, 1, 0.14)
                                }
                                Rectangle {
                                    visible: !mi.isSep && mia.containsMouse
                                    anchors.fill: parent
                                    radius: 5
                                    color: Theme.accent
                                }
                                Text {
                                    visible: !mi.isSep
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    text: mi.isSep ? "" : mi.modelData.label
                                    color: "white"
                                    font.pixelSize: 13
                                    font.family: Theme.uiFont
                                }
                                MouseArea {
                                    id: mia
                                    anchors.fill: parent
                                    enabled: !mi.isSep
                                    hoverEnabled: true
                                    onClicked: {
                                        var run = mi.modelData.run
                                        ui.menuItem = null
                                        if (run) run()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
