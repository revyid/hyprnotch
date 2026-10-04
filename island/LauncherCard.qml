import QtQuick
import QtQuick.Controls
import Quickshell
import "../core"
import "../services"

//  Launcher = the island's COMMAND PALETTE (r16 rework).
//
//  One search box over everything the notch can do, mouse optional:
//
//    · ACTIONS — every island view and switch (control center,
//      calendar, notifications, weather, stats, wallpaper, power,
//      about, plugins, settings, DND, containers, night light, dock,
//      plugin reload, keybind re-apply…). Each row shows the chord
//      that triggers it, read live from Settings → Keybinds.
//    · APPLICATIONS — the DesktopEntries grid the launcher always had.
//
//  Full keyboard flow: type to filter, Up/Down (or Ctrl+J/K, PageUp/
//  PageDown) to move, Enter to run, Esc to close. The island window
//  holds the keyboard exclusively while the launcher is hosted.

Item {
    id: launcherCard

    property var apps: []
    property string query: ""
    property int selected: 0

    //  Island contract
    property int prefWidth: 560
    implicitHeight: 434

    //  ── Every island action, palette-ready ────────────────────────
    //  `act` doubles as the Hotkeys action id where one exists, so the
    //  chord column always matches what the keybinds editor shows.
    readonly property var actions: [
        { act: "controlCenter", icon: Icons.sliders,   title: "Control Center",    sub: "toggles · sliders · media" },
        { act: "notifications", icon: Icons.bell,      title: "Notifications",     sub: "history and banners" },
        { act: "calendar",      icon: Icons.calendar,  title: "Calendar",          sub: "this month at a glance" },
        { act: "stats",         icon: Icons.chart,     title: "System Monitor",    sub: "CPU · memory · network · disk" },
        { act: "weather",       icon: Icons.cloud,     title: "Weather",           sub: "current + forecast" },
        { act: "wallpaper",     icon: Icons.image,     title: "Wallpaper",         sub: "picker · transitions · folder" },
        { act: "power",         icon: Icons.power,     title: "Power & Battery",   sub: "modes · lock · session" },
        { act: "about",         icon: Icons.info,      title: "About This Device", sub: "machine · distro · build" },
        { act: "plugins",       icon: Icons.cubes,     title: "Plugins",           sub: "manage installed plugins" },
        { act: "settings",      icon: Icons.gear,      title: "Settings",          sub: "the full settings window" },
        { act: "dnd",           icon: Icons.bellSlash, title: "Do Not Disturb",    sub: "silence banners instantly" },
        { act: "podman",        icon: Icons.server,    title: "Containers",        sub: "podman manager page" },
        { act: "agent",         icon: Icons.robot,     title: "AI Agent",          sub: "agent settings page" },
        { act: "nightLight",    icon: Icons.moon,      title: "Night Light",       sub: "warm the screen" },
        { act: "dock",          icon: Icons.desktop,   title: "Toggle Dock",       sub: "show or hide the dock" },
        { act: "reloadPlugins", icon: Icons.refresh,   title: "Reload Plugins",    sub: "rescan the plugin folder" },
        { act: "applyKeys",     icon: Icons.keyboard,  title: "Re-apply Keybinds", sub: "after a hyprctl reload" }
    ]

    //  ── Flat palette model: header / action / header / apps ───────
    readonly property var entries: {
        const q = query.toLowerCase().split(" ").filter(function (s) { return s.length > 0 })
        const hit = function (hay) {
            if (q.length === 0)
                return true
            for (let j = 0; j < q.length; ++j)
                if (hay.indexOf(q[j]) < 0)
                    return false
            return true
        }

        const out = []

        const acts = []
        for (let a = 0; a < actions.length; ++a) {
            const act = actions[a]
            if (hit((act.title + " " + act.sub).toLowerCase()))
                acts.push(act)
        }
        if (acts.length > 0) {
            out.push({ kind: "header", label: "Actions" })
            for (let i = 0; i < acts.length; ++i)
                out.push({ kind: "action", act: acts[i].act, icon: acts[i].icon,
                           title: acts[i].title, sub: acts[i].sub,
                           hint: Hotkeys.chordLabel(Hotkeys.bindingFor(acts[i].act)) })
        }

        if (query.trim().length > 0) {
            const shown = filteredApps.slice(0, 30)
            if (shown.length > 0) {
                out.push({ kind: "header", label: "Applications" })
                for (let s = 0; s < shown.length; ++s)
                    out.push({ kind: "app", icon: shown[s].icon,
                               title: shown[s].name, sub: shown[s].id, entry: shown[s].entry })
            }
        }

        return out
    }

    onEntriesChanged: {
        if (selected >= entries.length || entries[selected] === undefined
            || entries[selected].kind === "header")
            firstSelectable()
    }

    function firstSelectable() {
        selected = nextSelectable(0, 1)
    }

    //  Nearest selectable index starting FROM idx, stepping by dir.
    function nextSelectable(idx, dir) {
        let i = idx
        while (i >= 0 && i < entries.length) {
            if (entries[i] && entries[i].kind !== "header")
                return i
            i += dir
        }
        return idx >= 0 && idx < entries.length && entries[idx] && entries[idx].kind !== "header" ? idx : 0
    }

    function move(dir) {
        let i = selected + dir
        while (i >= 0 && i < entries.length) {
            if (entries[i] && entries[i].kind !== "header") {
                selected = i
                return
            }
            i += dir
        }
    }

    function activate(idx) {
        const e = entries[idx]
        if (!e || e.kind === "header")
            return
        if (e.kind === "action")
            runAction(e)
        else
            run(e.entry)
    }

    //  ── Actions runner — the whole notch, keyboard-driven ─────────
    function runAction(e) {
        switch (e.act) {
        case "controlCenter":
        case "calendar":
        case "notifications":
        case "weather":
        case "stats":
        case "wallpaper":
        case "power":
        case "about":
        case "plugins":
            UiState.openPopup(e.act)
            break
        case "settings":
            UiState.closeAll()
            Power.openSettings()
            break
        case "podman":
            UiState.closeAll()
            Power.openSettings("podman")
            break
        case "agent":
            UiState.closeAll()
            Power.openSettings("agent")
            break
        case "dnd":
            Notifs.toggleDnd()
            break
        case "nightLight":
            Power.toggleNight()
            break
        case "dock":
            Config.set("dock.enabled", !Config.data.dock.enabled)
            break
        case "reloadPlugins":
            Plugins.reload()
            break
        case "applyKeys":
            Hotkeys.apply()
            break
        }
    }

    //  ── Apps (unchanged engine) ───────────────────────────────────
    readonly property var filteredApps: {
        const q = query.toLowerCase().split(" ").filter(function (s) { return s.length > 0 })
        const out = []
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const hay = (a.name + " " + a.id).toLowerCase()
            let hit = q.length === 0
            for (let j = 0; j < q.length && !hit; ++j)
                if (hay.indexOf(q[j]) < 0)
                    break
                else if (j === q.length - 1)
                    hit = true
            if (hit)
                out.push(a)
        }
        return out
    }

    //  Fresh scan every time the island hosts the launcher
    property bool shown: UiState.activePopup === "launcher"
    onShownChanged: {
        if (shown) {
            query = ""
            selected = 0
            scanApps()
            searchInput.forceActiveFocus()
        }
    }

    function scanApps() {
        const rows = []
        const list = DesktopEntries.applications.values
        for (let i = 0; i < list.length; ++i) {
            const e = list[i]
            if (e.noDisplay)
                continue
            rows.push({
                name: e.name || String(e.id),
                id: String(e.id || "").toLowerCase().replace(/\.desktop$/, ""),
                icon: Quickshell.iconPath(e.icon, true),
                entry: e
            })
        }
        rows.sort(function (a, b) {
            return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
        })
        apps = rows
    }

    function run(entry) {
        if (!entry)
            return
        UiState.closeAll()
        try { entry.execute() } catch (e) {
            console.warn("launcher: execute failed:", e)
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        //  ── Search field ─────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 40
            radius: Theme.radiusSmall
            color: Theme.withAlpha(Theme.ink, 0.08)
            border.width: searchInput.activeFocus ? 1 : 0
            border.color: Theme.accent

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                size: 13
                colorVal: Theme.muted
                glyph: Icons.search
            }
            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 34
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                text: launcherCard.query
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 13
                clip: true
                focus: true

                onTextChanged: {
                    launcherCard.query = text
                    launcherCard.selected = 0
                    launcherCard.firstSelectable()
                }

                Keys.onUpPressed: launcherCard.move(-1)
                Keys.onDownPressed: launcherCard.move(1)
                Keys.onPageUpPressed: {
                    for (let i = 0; i < 6; ++i) launcherCard.move(-1)
                }
                Keys.onPageDownPressed: {
                    for (let i = 0; i < 6; ++i) launcherCard.move(1)
                }
                Keys.onReturnPressed: launcherCard.activate(launcherCard.selected)
                Keys.onEnterPressed: launcherCard.activate(launcherCard.selected)

                Text {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: "Search actions and apps…  (Up/Down select · Enter run · Esc close)"
                    color: Theme.dim
                    font.family: searchInput.font.family
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                }
            }
        }

        //  ── Palette list: virtualized rows, keyboard-followed ─────
        ListView {
            id: list
            width: parent.width
            height: 350
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: launcherCard.entries
            reuseItems: true
            spacing: 2
            ScrollIndicator.vertical: ScrollIndicator {}

            //  Keep the selection on screen as the user arrows around.
            Connections {
                target: launcherCard
                function onSelectedChanged() {
                    list.positionViewAtIndex(launcherCard.selected, ListView.Contain)
                }
            }

            delegate: Item {
                id: rowRoot
                required property var modelData
                required property int index
                readonly property bool isHeader: modelData.kind === "header"
                readonly property bool sel: launcherCard.selected === index

                width: list.width
                height: isHeader ? 26 : 44

                //  ── Section header ───────────────────────────────
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    visible: rowRoot.isHeader
                    text: rowRoot.modelData.label.toUpperCase()
                    color: Theme.dim
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }

                //  ── Action / app row ─────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    visible: !rowRoot.isHeader
                    radius: Theme.radiusTile
                    color: rowRoot.sel ? Theme.withAlpha(Theme.accent, 0.22)
                        : (rowArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.09) : "transparent")
                    border.width: rowRoot.sel ? 1 : 0
                    border.color: Theme.accent
                    scale: rowArea.pressed ? 0.98 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    visible: !rowRoot.isHeader
                    spacing: 10

                    Item {
                        width: 26
                        height: 26
                        anchors.verticalCenter: parent.verticalCenter

                        //  Apps carry a themed icon URL; actions carry a
                        //  nerd-font glyph — never feed a glyph to Image.
                        readonly property bool useImg: rowRoot.modelData.kind === "app"
                            && String(rowRoot.modelData.icon || "").length > 0

                        Image {
                            anchors.fill: parent
                            visible: parent.useImg
                            source: visible ? rowRoot.modelData.icon : ""
                            sourceSize: Qt.size(52, 52)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            mipmap: true
                        }
                        Glyph {
                            anchors.centerIn: parent
                            visible: !parent.useImg
                            size: 13
                            colorVal: rowRoot.sel ? Theme.ink : Theme.accent
                            glyph: rowRoot.modelData.kind === "app" ? Icons.window
                                : rowRoot.modelData.icon
                        }
                    }

                    Column {
                        width: parent.width - 26 - 10 - (rowHint.implicitWidth > 0 ? rowHint.implicitWidth + 12 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: rowRoot.modelData.title
                            color: rowRoot.sel ? Theme.ink : (rowArea.containsMouse ? Theme.ink : Theme.muted)
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: rowRoot.sel ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: rowRoot.modelData.sub
                            color: Theme.dim
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: rowHint
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowRoot.modelData.hint !== undefined ? rowRoot.modelData.hint : ""
                        visible: text.length > 0
                        color: rowRoot.sel ? Theme.ink : Theme.dim
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    enabled: !rowRoot.isHeader
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcherCard.activate(rowRoot.index)
                    onContainsMouseChanged: {
                        if (containsMouse && !rowRoot.isHeader)
                            launcherCard.selected = rowRoot.index
                    }
                }
            }
        }
    }
}
