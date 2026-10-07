import QtQuick
import QtQuick.Controls
import Quickshell
import "../core"
import "../services"

//  Launcher = the island's COMMAND PALETTE (r16 rework).
//
//  One search box over everything the notch can do, mouse optional,
//  with a FILTER MENU on top (r24): All | Actions | Apps — "di
//  launcher itu ada menu untuk show app aja". The Apps tab is the
//  plain application grid, no palette rows.
//
//    · ACTIONS — every island view and switch (control center,
//      calendar, notifications, weather, stats, wallpaper, power,
//      about, plugins, settings, DND, containers, agent, clipboard,
//      screenshot, record, night light, dock, plugin reload, keybind
//      re-apply, quick toggles…). Each row shows the chord that
//      triggers it, read live from Settings → Keybinds.
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

    //  r24 filter menu: "all" (actions then apps) | "actions" | "apps".
    readonly property var filters: ["all", "actions", "apps"]
    property string filter: "all"

    //  Island contract
    property int prefWidth: 560
    implicitHeight: 466

    //  ── Inline calculator (r28) ───────────────────────────────────
    //  Type any arithmetic expression and the launcher prepends a
    //  result row — Enter or click copies it. NO eval(): a tiny
    //  recursive-descent parser over a strict charset (digits, + - * /
    //  % ^ parens, dot) so an expression can never execute anything —
    //  it can only do math. Full-consumption + finite checks reject
    //  garbage; the value is round-tripped through Math.round(1e10)
    //  to hide float dust (0.1+0.2 → 0.3).
    function calcEvaluate(src) {
        const trimmed = String(src).trim()
        //  internal whitespace means the user is SEARCHING, not doing
        //  math — "3+4 5" must never become 3+45 = 48.
        if (/\s/.test(trimmed))
            return null
        const s = trimmed
        if (s.length === 0 || s.length > 60)
            return null
        //  charset gate WITHOUT a regex class: "(" inside a character
        //  class confuses naive bracket scanners (including our own
        //  validator), and indexOf() is just as strict.
        const ALLOWED = "0123456789+-*/%^()."
        for (let c = 0; c < s.length; ++c)
            if (ALLOWED.indexOf(s[c]) < 0)
                return null
        if (s.indexOf("0") < 0 && s.indexOf("1") < 0 && s.indexOf("2") < 0
                && s.indexOf("3") < 0 && s.indexOf("4") < 0 && s.indexOf("5") < 0
                && s.indexOf("6") < 0 && s.indexOf("7") < 0 && s.indexOf("8") < 0
                && s.indexOf("9") < 0)
            return null

        let pos = 0
        function peek() { return pos < s.length ? s[pos] : "" }

        function parseExpr() {
            let v = parseTerm()
            while (peek() === "+" || peek() === "-") {
                const op = s[pos++]
                const r = parseTerm()
                v = op === "+" ? v + r : v - r
            }
            return v
        }
        function parseTerm() {
            let v = parseFactor()
            while (peek() === "*" || peek() === "/" || peek() === "%") {
                const op = s[pos++]
                const r = parseFactor()
                if (op === "*") v = v * r
                else if (r === 0) return NaN
                else v = op === "/" ? v / r : v % r
            }
            return v
        }
        function parseFactor() {
            if (peek() === "-") { pos++; return -parseFactor() }
            if (peek() === "+") { pos++; return parseFactor() }
            let v = parsePrimary()
            if (peek() === "^") {
                pos++
                v = Math.pow(v, parseFactor())      //  right-assoc: 2^3^2 = 512
            }
            return v
        }
        function parsePrimary() {
            if (peek() === "(") {
                pos++
                const v = parseExpr()
                if (peek() !== ")")
                    return NaN
                pos++
                return v
            }
            const start = pos
            while (pos < s.length && ((s[pos] >= "0" && s[pos] <= "9") || s[pos] === "."))
                pos++
            if (pos === start)
                return NaN
            const num = parseFloat(s.substring(start, pos))
            return isNaN(num) ? NaN : num
        }

        try {
            const v = parseExpr()
            if (pos !== s.length || !isFinite(v))
                return null
            return Math.round(v * 1e10) / 1e10
        } catch (e) {
            return null
        }
    }

    //  Result copy: the value can only contain [0-9+-*/%^().] — no
    //  quotes, no letters, no shell metacharacters beyond a leading
    //  dash that echo/wl-copy treat as data — so single-quoting is a
    //  complete injection guard.
    function copyCalc(v) {
        const t = String(v)
        Power.run("echo '" + t + "' | wl-copy >/dev/null 2>&1")
        calcFlash.restart()
        Notifs.toast("Launcher", "Result copied", "= " + t)
    }

    property bool calcCopied: false
    Timer {
        id: calcFlash
        interval: 1800
        onTriggered: launcherCard.calcCopied = false
    }

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
        { act: "podman",        icon: Icons.server,    title: "Containers",        sub: "podman containers in the notch" },
        { act: "agent",         icon: Icons.robot,     title: "AI Agent",          sub: "agent status and usage" },
        { act: "clipboard",     icon: "\uF0EA",        title: "Clipboard History", sub: "win + v · paste anything back" },
        { act: "screenshot",    icon: Icons.camera,    title: "Screenshot",        sub: "capture a region or screen" },
        { act: "record",        icon: Icons.video,     title: "Screen Recording",  sub: "start / stop wf-recorder" },
        { act: "quickToggles",  icon: Icons.sliders,   title: "Quick Toggles",     sub: "per-feature switches" },
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
        const f = launcherCard.filter

        //  Math first (r28): a typed expression becomes a result row on
        //  top — All and Actions tabs only, never the pure Apps grid.
        if (f !== "apps" && query.trim().length > 0) {
            const res = calcEvaluate(query)
            if (res !== null)
                out.push({ kind: "calc", icon: Icons.copy, title: "= " + res,
                           sub: calcCopied ? "copied to clipboard ✓" : "Enter to copy the result",
                           hint: "calculator", value: res })
        }

        if (f !== "apps") {
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
        }

        if (f === "apps" || query.trim().length > 0) {
            //  Apps tab = the show-apps-only menu (cap raised so the
            //  whole grid is actually browsable); All tab keeps the
            //  old behavior of apps appearing once the user types.
            const cap = f === "apps" ? 100 : 30
            const shown = filteredApps.slice(0, cap)
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
        if (e.kind === "calc") {
            calcCopied = true
            copyCalc(e.value)
            return
        }
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
        case "containers":
            UiState.openPopup("containers")
            break
        case "agent":
            UiState.openPopup("agent")
            break
        case "clipboard":
            UiState.openPopup("clipboard")
            break
        case "quickToggles":
            UiState.controlCenterPane = "features"
            UiState.openPopup("controlCenter")
            break
        case "screenshot":
            UiState.closeAll()
            Power.screenshot()
            break
        case "record":
            UiState.closeAll()
            Power.record()
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
            filter = "all"
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

                //  Keyboard via the UNIVERSAL Keys.onPressed pattern
                //  (same as IslandWindow / SettingsWindow). Convenience
                //  handlers proved unportable: the user's Quickshell
                //  build rejected Keys.onPageDownPressed with
                //  "Cannot assign to non-existent property" while
                //  accepting its PageUp twin (r17 crash). Explicit
                //  event.key checks never lie across Qt builds.
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
                    switch (event.key) {
                    case Qt.Key_Up:
                        launcherCard.move(-1)
                        event.accepted = true
                        break
                    case Qt.Key_Down:
                        launcherCard.move(1)
                        event.accepted = true
                        break
                    case Qt.Key_PageUp:
                        for (let i = 0; i < 6; ++i) launcherCard.move(-1)
                        event.accepted = true
                        break
                    case Qt.Key_PageDown:
                        for (let i = 0; i < 6; ++i) launcherCard.move(1)
                        event.accepted = true
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        launcherCard.activate(launcherCard.selected)
                        event.accepted = true
                        break
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: "Search actions and apps, or type math…  (Up/Down select · Enter run · Esc close)"
                    color: Theme.dim
                    font.family: searchInput.font.family
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                }
            }
        }

        //  ── Filter menu (r24): All / Actions / Apps ───────────────
        //  "Apps" IS the show-apps-only menu: the whole application
        //  grid, no palette rows, no typing needed.
        Row {
            width: parent.width
            height: 26
            spacing: 6

            Repeater {
                model: [
                    { k: "all",     label: "All" },
                    { k: "actions", label: "Actions" },
                    { k: "apps",    label: "Apps" }
                ]

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool sel: launcherCard.filter === modelData.k
                    width: 66
                    height: 24
                    radius: 12
                    color: sel ? Theme.accent : Theme.withAlpha(Theme.ink, 0.08)

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    scale: chipArea.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: chip.sel ? "#ffffff" : Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: chip.sel ? Font.DemiBold : Font.Medium
                    }
                    MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            launcherCard.filter = chip.modelData.k
                            launcherCard.selected = 0
                            launcherCard.firstSelectable()
                        }
                    }
                }
            }

            Item { width: 4; height: 1 }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: launcherCard.filter === "apps"
                    ? filteredApps.length + " apps"
                    : (query.length > 0 ? "" : "type to search · Up/Down · Enter")
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
            }
        }

        //  ── Palette list: virtualized rows, keyboard-followed ─────
        ListView {
            id: list
            width: parent.width
            height: 322
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
                    text: String(rowRoot.modelData.label || "").toUpperCase()
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
                                : String(rowRoot.modelData.icon || "")
                        }
                    }

                    Column {
                        width: parent.width - 26 - 10 - (rowHint.implicitWidth > 0 ? rowHint.implicitWidth + 12 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: rowRoot.modelData.title || ""
                            color: rowRoot.sel ? Theme.ink : (rowArea.containsMouse ? Theme.ink : Theme.muted)
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: rowRoot.sel ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: rowRoot.modelData.sub || ""
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
