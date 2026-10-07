import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

//  Control Center — hosted INSIDE the island body, macOS style.
//
//  A pane system that owns the whole expansion: the main pane holds the
//  config-driven sections (connectivity tiles, weather, audio, media,
//  quick actions, tasks); Wi-Fi and Bluetooth open their own
//  manager panes inside the same body, exactly like macOS expands into
//  a detail view. Pane switches fade + slide, the island height settles
//  with the k4 spring — the card itself only reports geometry.
//
//  Section order and visibility come from Config.data.controlCenter, so
//  everything stays enable/disable/reorder-able from Settings.

Item {
    id: ccWindow

    readonly property var cfg: Config.data.controlCenter
    readonly property int pad: 14

    //  Which detail pane is on: "main" | "wifi" | "bluetooth"
    property string pane: "main"

    //  Island contract: the island reads prefWidth to pick its width and
    //  implicitHeight to size the expansion body. There is no card
    //  background here on purpose — the island silhouette behind IS the
    //  card surface (one black island, k4 style).
    property int prefWidth: cfg.width
    implicitHeight: innerColumn.implicitHeight + pad * 2

    //  ── Scanner / discovery lifecycle: radios only burn while their
    //     list is actually on screen.
    property bool shown: UiState.activePopup === "controlCenter"
    onShownChanged: {
        if (shown) {
            //  Opened from the pill / a keybind / IPC / the launcher:
            //  honor the pane the opener asked for (the Quick Toggles
            //  keybind sets controlCenterPane = "features").
            pane = UiState.controlCenterPane
            UiState.controlCenterPane = "main"
        } else {
            pane = "main"
            Net.scanning = false
            Bluetooth.discoveryWanted = false
        }
    }
    onPaneChanged: {
        Net.scanning = (pane === "wifi") && shown
        Bluetooth.discoveryWanted = (pane === "bluetooth") && shown
    }

    Column {
        id: innerColumn
        x: ccWindow.pad
        y: ccWindow.pad
        width: parent.width - ccWindow.pad * 2
        spacing: 10

                //  ── Header: back chevron when inside a detail pane ─
                Item {
                    width: parent.width
                    height: 26

                    Rectangle {
                        id: backBtn
                        visible: ccWindow.pane !== "main"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11
                        color: backArea.containsMouse ? Theme.track : "transparent"
                        Glyph {
                            anchors.centerIn: parent
                            size: 10
                            colorVal: Theme.ink
                            glyph: Icons.chevronLeft
                        }
                        MouseArea {
                            id: backArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ccWindow.pane = "main"
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: ccWindow.pane !== "main" ? 30 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on anchors.leftMargin { NumberAnimation { duration: Theme.animFast } }
                        text: ccWindow.pane === "wifi" ? "Wi-Fi"
                            : ccWindow.pane === "bluetooth" ? "Bluetooth"
                            : ccWindow.pane === "features" ? "Quick Toggles"
                            : "Control Center"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            width: 26; height: 26; radius: 8
                            color: maBell.containsMouse ? Theme.surfaceHi : "transparent"
                            Glyph {
                                anchors.centerIn: parent
                                size: 13
                                colorVal: Notifs.unseen > 0 ? Theme.accent : Theme.muted
                                glyph: Icons.bell
                            }
                            MouseArea {
                                id: maBell
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: UiState.togglePopup("notifCenter")
                            }
                        }

                        Rectangle {
                            width: 26; height: 26; radius: 8
                            color: maGear.containsMouse ? Theme.surfaceHi : "transparent"
                            Glyph {
                                anchors.centerIn: parent
                                size: 13
                                colorVal: Theme.muted
                                glyph: Icons.gear
                            }
                            MouseArea {
                                id: maGear
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    UiState.activePopup = "none"
                                    Power.openSettings()
                                }
                            }
                        }
                    }
                }

                //  ── The pane: slides/fades in on every switch ──────
                //  r28 FIX: "features" was MISSING from this chain since
                //  r24 — featuresComp existed but never loaded, so the
                //  Quick Toggles keybind, the launcher action and the
                //  IPC alias all opened the MAIN pane instead. This
                //  branch is why Super+A finally shows the switches.
                Loader {
                    id: paneLoader
                    width: parent.width
                    sourceComponent: ccWindow.pane === "wifi" ? wifiComp
                        : ccWindow.pane === "bluetooth" ? btComp
                        : ccWindow.pane === "features" ? featuresComp
                        : mainComp

                    onSourceComponentChanged: {
                        paneFade.restart()
                        paneSlide.restart()
                    }

                    NumberAnimation {
                        id: paneFade
                        target: paneLoader
                        property: "opacity"
                        from: 0; to: 1
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        id: paneSlide
                        target: paneLoader
                        property: "x"
                        from: 26; to: 0
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                    Component.onCompleted: {
                        paneFade.start()
                        paneSlide.start()
                    }
                }
    }

    //  ══════════════════════════════════════════════════════════════
    //  MAIN PANE — config-driven sections
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: mainComp

        Column {
            width: parent ? parent.width : 0
            spacing: 10

            Repeater {
                model: ccWindow.cfg.sections

                Loader {
                    id: secLoader
                    required property string modelData
                    required property int index
                    readonly property bool isOn: ccWindow.cfg.sectionEnabled[modelData] !== false
                    readonly property bool hasData: (modelData !== "weather" || Weather.ready)
                        && (modelData !== "focus" || Config.get("focus.enabled", true))
                    width: parent ? parent.width : 0
                    visible: isOn && hasData
                    sourceComponent: !isOn || !hasData ? null
                        : modelData === "toggles" ? togglesComp
                        : modelData === "system" ? systemSectionComp
                        : modelData === "weather" ? weatherComp
                        : modelData === "sliders" ? slidersComp
                        : modelData === "media" ? mediaComp
                        : modelData === "focus" ? focusComp
                        : modelData === "quickActions" ? actionsComp
                        : modelData === "plugins" ? pluginsSectionComp
                        : modelData === "tasks" ? tasksComp
                        : null

                    //  ── r28 staggered entrance: each section fades and
                    //  lifts in with a per-index beat, so an open reads
                    //  as one motion instead of a wall that pops. The
                    //  beat is capped so deep stacks never feel slow.
                    opacity: 0
                    transform: Translate { id: secEnter; y: 10 }

                    Component.onCompleted: secEnterAnim.restart()

                    SequentialAnimation {
                        id: secEnterAnim
                        PauseAnimation { duration: 36 * Math.min(8, secLoader.index) }
                        ParallelAnimation {
                            NumberAnimation { target: secLoader; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
                            NumberAnimation { target: secEnter; property: "y"; from: 10; to: 0; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }

    //  ── System: the discoverable doors to the machine pages ───────
    //  The island hosts an About This Device card, a live monitor and a
    //  wallpaper picker — but a popup nobody can find is dead weight.
    //  Plain rows, macOS System Settings style, one tap each. r28: the
    //  Quick Toggles door is back (it silently vanished from this list)
    //  and routes into the features pane like the keybind does.
    Component {
        id: systemSectionComp

        Rectangle {
            width: parent ? parent.width : 0
            height: 4 * 38 + 12
            radius: Theme.radiusTile
            color: Theme.surfaceHi

            Column {
                x: 10; y: 6
                width: parent.width - 20
                spacing: 0

                Repeater {
                    model: [
                        { key: "about",     glyph: Icons.distro(SysMon.osId, SysMon.osIdLike),  label: "About This Device",
                            sub: SysMon.osName.length > 0 ? SysMon.osName : "Hyprland · HyprNotch" },
                        { key: "stats",     glyph: Icons.chart,  label: "System Monitor",
                            sub: "CPU " + SysMon.cpuPct + "% · RAM " + SysMon.memPct + "%" },
                        { key: "wallpaper", glyph: Icons.image,  label: "Wallpaper",
                            sub: Wallpaper.available ? (Wallpaper.current.length > 0 ? Wallpaper.fileName(Wallpaper.current) : "Pick an image") : Wallpaper.tool + " not found" },
                        { key: "toggles",   glyph: Icons.sliders, label: "Quick Toggles",
                            sub: "switch whole features on or off" }
                    ]

                    delegate: Rectangle {
                        id: sysRow
                        required property var modelData
                        width: parent.width
                        height: 38
                        radius: 8
                        color: sysArea.containsMouse ? Theme.track : "transparent"
                        scale: sysArea.pressed ? 0.98 : 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            spacing: 10

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24; radius: 7
                                color: Theme.withAlpha(Theme.accent, 0.18)
                                Glyph {
                                    anchors.centerIn: parent
                                    size: 11
                                    colorVal: Theme.accent
                                    glyph: sysRow.modelData.glyph
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                Text {
                                    text: sysRow.modelData.label
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: sysRow.modelData.sub
                                    color: Theme.muted
                                    font.family: Theme.uiFont
                                    font.pixelSize: 9
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            text: "›"
                            color: Theme.dim
                            font.family: Theme.uiFont
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: sysArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (sysRow.modelData.key === "toggles") {
                                    UiState.controlCenterPane = "features"
                                    ccWindow.pane = "features"
                                } else {
                                    UiState.openPopup(sysRow.modelData.key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    //  ── Connectivity tiles: macOS 2x2, Wi-Fi / BT open details ────

    //  ── Plugins: count + manage entry (opens the manager view) ────
    Component {
        id: pluginsSectionComp

        Rectangle {
            width: parent ? parent.width : 0
            height: 46
            radius: Theme.radiusTile
            color: Theme.surfaceHi

            scale: pluginsArea.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                spacing: 10

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 15
                    colorVal: Theme.accent
                    glyph: Icons.plug
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Plugins"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Plugins.active.length === 1
                        ? "1 active" : Plugins.active.length + " active"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "Manage ›"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 11
            }

            MouseArea {
                id: pluginsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: UiState.openPopup("plugins")
            }
        }
    }

    Component {
        id: togglesComp

        GridLayout {
            width: parent ? parent.width : 0
            columns: ccWindow.cfg.tileColumns || 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: [
                    { key: "wifi",  glyph: Net.wifiEnabled ? Icons.wifiIcon(Net.connectedLevel) : Icons.wifiOff,
                      label: "Wi-Fi", sub: Net.wifiEnabled ? (Net.wifiSsid.length > 0 ? Net.wifiSsid : "On") : "Off",
                      isOn: Net.wifiEnabled, detail: true },
                    { key: "bt",    glyph: Icons.bluetooth,
                      label: "Bluetooth",
                      sub: !Bluetooth.available ? "No adapter"
                         : (!Bluetooth.powered ? "Off"
                         : (Bluetooth.connectedCount > 0 ? Bluetooth.connectedCount + " connected" : "On")),
                      isOn: Bluetooth.powered, detail: true },
                    { key: "dnd",   glyph: Icons.bellSlash, label: "Focus", sub: Notifs.dnd ? "On" : "Off",
                      isOn: Notifs.dnd, detail: false },
                    { key: "night", glyph: Icons.moon, label: "Night Light", sub: Power.nightActive ? "On" : "Off",
                      isOn: Power.nightActive, detail: false }
                ]

                Rectangle {
                    id: tile
                    required property var modelData
                    Layout.fillWidth: true
                    height: 56
                    radius: Theme.radiusTile
                    color: tile.modelData.isOn ? Theme.accent : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    scale: tileArea.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 10

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            colorVal: tile.modelData.isOn ? "#ffffff" : Theme.ink
                            glyph: tile.modelData.glyph
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: tile.modelData.label
                                color: "#ffffff"
                                font.family: Theme.uiFont
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: tile.modelData.sub ? tile.modelData.sub : ""
                                color: Theme.withAlpha("#ffffff", 0.75)
                                font.family: Theme.uiFont
                                font.pixelSize: 9
                                width: ccWindow.cfg.width / (ccWindow.cfg.tileColumns || 2) - 76
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Glyph {
                        visible: tile.modelData.detail
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        size: 9
                        colorVal: Theme.withAlpha("#ffffff", 0.55)
                        glyph: Icons.chevronRight
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tile.modelData.key === "wifi")         ccWindow.pane = "wifi"
                            else if (tile.modelData.key === "bt")      ccWindow.pane = "bluetooth"
                            else if (tile.modelData.key === "dnd")     Notifs.toggleDnd()
                            else if (tile.modelData.key === "night")   Power.toggleNight()
                        }
                    }
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  WEATHER — realtime card (Open-Meteo), HIG materials
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: weatherComp

        Rectangle {
            width: parent ? parent.width : 0
            height: 104
            radius: Theme.radiusTile
            color: Theme.surfaceHi

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                //  Head row is a plain Item, NOT a Row: the H/L column
                //  must hug the right edge, and Row children may not use
                //  anchors.left/right/horizontalCenter/fill/centerIn
                //  ("Cannot specify anchors for items inside Row.
                //  Row will not function." — 5x per relayout in r21).
                Item {
                    id: weatherHead
                    width: parent.width
                    height: Math.max(30, tempNow.implicitHeight)

                    Glyph {
                        id: weatherGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        size: 30
                        colorVal: Weather.current && Weather.current.isDay ? Theme.yellow : Theme.purple
                        glyph: Weather.current ? Weather.icon(Weather.current.code, Weather.current.isDay) : ""
                    }

                    Text {
                        id: tempNow
                        anchors.left: weatherGlyph.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.current ? Weather.current.temp + "°" : "--°"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                    }

                    Column {
                        anchors.left: tempNow.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: Weather.current ? Weather.describe(Weather.current.code) : ""
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            text: Weather.place + (Weather.region.length > 0 ? " · " + Weather.region : "")
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            width: ccWindow.cfg.width - 210
                            elide: Text.ElideRight
                        }
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.right: parent.right
                            text: Weather.daily.length > 0
                                ? "H:" + Weather.daily[0].max + "°  L:" + Weather.daily[0].min + "°" : ""
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                        }
                        Text {
                            anchors.right: parent.right
                            text: Weather.current ? "Feels " + Weather.current.feels + "°" : ""
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                        }
                    }
                }

                //  ── Hourly strip: next 7 slots ─────────────────────
                Row {
                    width: parent.width
                    spacing: Math.max(2, (parent.width - 7 * 30) / 6)

                    Repeater {
                        model: Weather.hourly

                        Column {
                            required property var modelData
                            width: 30
                            spacing: 3

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.modelData.hour
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 9
                            }
                            Glyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 13
                                colorVal: Theme.teal
                                glyph: Weather.icon(parent.modelData.code, parent.modelData.isDay)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.modelData.temp + "°"
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  WI-FI MANAGER — realtime network list, connect with password
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: wifiComp

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            //  Master switch
            Item {
                width: parent.width
                height: 30

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        colorVal: Net.wifiEnabled ? Theme.accent : Theme.muted
                        glyph: Net.wifiEnabled ? Icons.wifi : Icons.wifiOff
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wi-Fi"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                AppToggle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Net.wifiEnabled
                    onToggled: Net.toggleWifi()
                }
            }

            //  Scanner status (live: NetworkManager notifies)
            Row {
                visible: Net.wifiEnabled && Net.scanning
                width: parent.width
                height: visible ? 16 : 0
                spacing: 8

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 11
                    colorVal: Theme.muted
                    glyph: Icons.spinner
                    RotationAnimation on rotation {
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1200
                        running: Net.scanning
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Scanning for networks…"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.separator
            }

            //  Network list
            Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: Net.networks

                    Column {
                        id: netEntry
                        required property var modelData
                        width: parent ? parent.width : 0
                        spacing: 4

                        Rectangle {
                            width: parent.width
                            height: 38
                            radius: Theme.radiusSmall
                            color: netRow.containsMouse || Net.pskTarget === netEntry.modelData
                                ? Theme.surfaceHi : "transparent"

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 16
                                    colorVal: netEntry.modelData.connected ? Theme.accent : Theme.ink
                                    glyph: Net.strengthIcon(netEntry.modelData)
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 96
                                    Text {
                                        width: parent.width
                                        text: netEntry.modelData.name
                                        color: Theme.ink
                                        font.family: Theme.uiFont
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: Net.statusText(netEntry.modelData)
                                        color: netEntry.modelData.connected ? Theme.accent : Theme.muted
                                        font.family: Theme.uiFont
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 9
                                    colorVal: Theme.muted
                                    glyph: Icons.lock
                                    visible: Net.isSecure(netEntry.modelData)
                                }
                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 11
                                    colorVal: Theme.accent
                                    glyph: Icons.circleCheck
                                    visible: netEntry.modelData.connected
                                }
                            }

                            MouseArea {
                                id: netRow
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Net.activate(netEntry.modelData)
                            }
                        }

                        //  Inline password form for secured networks
                        Rectangle {
                            visible: Net.pskTarget === netEntry.modelData
                            width: parent.width
                            height: visible ? 74 : 0
                            radius: Theme.radiusSmall
                            color: Theme.surfaceHi

                            Column {
                                visible: Net.pskTarget === netEntry.modelData
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                TextField {
                                    id: pskField
                                    width: parent.width
                                    height: 28
                                    echoMode: TextInput.Password
                                    placeholderText: "Password for " + (netEntry.modelData ? netEntry.modelData.name : "")
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    color: Theme.ink
                                    placeholderTextColor: Theme.dim
                                    focus: Net.pskTarget === netEntry.modelData
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: Theme.track
                                        border.width: pskField.activeFocus ? 1 : 0
                                        border.color: Theme.accent
                                    }
                                    onAccepted: Net.submitPsk()
                                }

                                Row {
                                    anchors.right: parent.right
                                    spacing: 6

                                    Rectangle {
                                        width: 64; height: 22; radius: 11
                                        color: Theme.track
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: Theme.ink
                                            font.family: Theme.uiFont
                                            font.pixelSize: 10
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Net.cancelPsk()
                                        }
                                    }

                                    Rectangle {
                                        width: 72; height: 22; radius: 11
                                        color: Theme.accent
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Connect"
                                            color: "#ffffff"
                                            font.family: Theme.uiFont
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Net.submitPsk()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                //  Empty / off states
                Text {
                    width: parent.width
                    height: 36
                    visible: !Net.wifiEnabled
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "Wi-Fi is off — turn it on to see networks"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
                Text {
                    width: parent.width
                    height: 36
                    visible: Net.wifiEnabled && !Net.scanning && Net.networks.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No networks around"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }

            //  Rescan
            Item {
                width: parent.width
                height: Net.wifiEnabled ? 20 : 0
                visible: Net.wifiEnabled

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Net.scanning ? "scanning…" : "rescan"
                    color: Theme.accent
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Net.rescan()
                    }
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  BLUETOOTH MANAGER — realtime devices, pair / trust / connect
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: btComp

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            Item {
                width: parent.width
                height: 30

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        colorVal: Bluetooth.powered ? Theme.accent : Theme.muted
                        glyph: Icons.bluetooth
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                AppToggle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Bluetooth.powered
                    onToggled: Bluetooth.toggle()
                }
            }

            //  Discovery status (live from the adapter)
            Row {
                visible: Bluetooth.powered && Bluetooth.discovering
                width: parent.width
                height: visible ? 16 : 0
                spacing: 8

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 11
                    colorVal: Theme.muted
                    glyph: Icons.spinner
                    RotationAnimation on rotation {
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1200
                        running: Bluetooth.discovering
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Discovering devices…"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.separator
            }

            Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: Bluetooth.devices

                    Rectangle {
                        id: btEntry
                        required property var modelData
                        width: parent ? parent.width : 0
                        height: 38
                        radius: Theme.radiusSmall
                        color: btRow.containsMouse ? Theme.surfaceHi : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 15
                                colorVal: btEntry.modelData.connected ? Theme.accent : Theme.ink
                                glyph: Icons.btDeviceIcon(btEntry.modelData.icon)
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 90
                                Text {
                                    width: parent.width
                                    text: btEntry.modelData.name
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: Bluetooth.deviceStatus(btEntry.modelData)
                                    color: btEntry.modelData.connected ? Theme.accent : Theme.muted
                                    font.family: Theme.uiFont
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 11
                                colorVal: Theme.accent
                                glyph: Icons.circleCheck
                                visible: btEntry.modelData.connected
                            }
                        }

                        MouseArea {
                            id: btRow
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Bluetooth.activate(btEntry.modelData)
                        }
                    }
                }

                Text {
                    width: parent.width
                    height: 36
                    visible: !Bluetooth.available
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No Bluetooth adapter found"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
                Text {
                    width: parent.width
                    height: 36
                    visible: Bluetooth.available && !Bluetooth.powered
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "Bluetooth is off — turn it on to manage devices"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
                Text {
                    width: parent.width
                    height: 36
                    visible: Bluetooth.available && Bluetooth.powered && Bluetooth.devices.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No devices yet — make one discoverable and it shows up here"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  Section components
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: slidersComp

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            //  Brightness
            Row {
                visible: Brightness.available
                width: parent.width
                spacing: 10
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 14
                    colorVal: Theme.yellow
                    glyph: Icons.sun
                }
                AppSlider {
                    width: parent.width - 24
                    value: Brightness.level
                    onValueEdited: (v) => Brightness.setLevel(Math.round(v))
                }
            }

            //  Volume
            Row {
                width: parent.width
                spacing: 10
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 14
                    colorVal: Audio.muted ? Theme.red : Theme.muted
                    glyph: Icons.volumeIcon(Audio.volume, Audio.muted)
                }
                AppSlider {
                    width: parent.width - 24
                    value: Audio.volume
                    onValueEdited: (v) => Audio.setVolume(Math.round(v))
                }
            }

            //  Microphone
            Row {
                width: parent.width
                height: 24
                spacing: 10
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 14
                    colorVal: Audio.micMuted ? Theme.red : Theme.muted
                    glyph: Audio.micMuted ? Icons.micSlash : Icons.mic
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Audio.micMuted ? "Microphone muted" : "Microphone on"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                }
                Item { width: parent.width - 160; height: 1 }
                AppToggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: !Audio.micMuted
                    onToggled: Audio.toggleMic()
                }
            }
        }
    }

    Component {
        id: mediaComp

        Rectangle {
            id: mediaTile
            width: parent ? parent.width : 0
            readonly property bool showCava: Media.playing && Cava.enabled
            height: visible && Media.hasPlayer ? (showCava ? 128 : 108) : 0
            radius: Theme.radiusTile
            color: Theme.surfaceHi
            visible: Media.hasPlayer

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: 42; height: 42; radius: 8
                        color: Theme.track
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: Media.artUrl.length > 0
                            source: Media.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Glyph {
                            anchors.centerIn: parent
                            size: 16
                            colorVal: Theme.muted
                            glyph: Icons.music
                            visible: Media.artUrl.length === 0
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.spacing * 3 - 42 - 110
                        spacing: 2
                        Text {
                            width: parent.width
                            text: Media.title
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: Media.artist
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Repeater {
                            model: [
                                { g: Icons.backward, fn: () => Media.previous() },
                                { g: Media.playing ? Icons.pause : Icons.play, fn: () => Media.playPause() },
                                { g: Icons.forward, fn: () => Media.next() }
                            ]
                            Rectangle {
                                required property var modelData
                                width: 30; height: 30; radius: 15
                                color: mbArea.containsMouse ? Theme.track : "transparent"
                                anchors.verticalCenter: parent.verticalCenter
                                Glyph {
                                    anchors.centerIn: parent
                                    size: 12
                                    colorVal: Theme.ink
                                    glyph: parent.modelData.g
                                }
                                MouseArea {
                                    id: mbArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.modelData.fn()
                                }
                            }
                        }
                    }
                }

                //  ── Live spectrum (r25): "cava pas musicnya idup" —
                //  real cava frames when the binary exists, a smooth
                //  synthetic fallback otherwise; flat when paused.
                CavaBars {
                    width: parent.width
                    visible: mediaTile.showCava
                    maxHeight: 18
                    barWidth: 4
                    gap: 5
                }

                //  ── Live + SEEKABLE progress (r28): the bar was a
                //  read-only strip; now players that support MPRIS seek
                //  take click/drag on the track (14px hit target — the
                //  3px bar was impossible to grab). While scrubbing the
                //  fill follows the pointer and the linear tick easing
                //  steps aside so the head never lags the hand.
                Column {
                    width: parent.width
                    spacing: 2

                    Item {
                        id: seekTrack
                        width: parent.width
                        height: 14

                        property bool scrubbing: false
                        property real scrubFrac: 0
                        readonly property real frac: scrubbing ? scrubFrac : Media.progress

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.track
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(4, seekTrack.frac * seekTrack.width)
                            height: 4
                            radius: 2
                            color: Media.canSeek ? Theme.accent : Theme.withAlpha(Theme.accent, 0.5)

                            Behavior on width {
                                enabled: !seekTrack.scrubbing
                                NumberAnimation { duration: 900; easing.type: Easing.Linear }
                            }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width,
                                    seekTrack.frac * parent.width - width / 2))
                            width: 9
                            height: 9
                            radius: 4.5
                            color: "#ffffff"
                            visible: Media.canSeek
                            opacity: seekTrack.scrubbing || seekArea.containsMouse ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                            scale: seekTrack.scrubbing ? 1.25 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            enabled: Media.canSeek
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            function fracAt(mx) {
                                return Math.max(0, Math.min(1, mx / seekTrack.width))
                            }

                            onPressed: (m) => {
                                seekTrack.scrubbing = true
                                seekTrack.scrubFrac = fracAt(m.x)
                            }
                            onPositionChanged: (m) => {
                                if (pressed)
                                    seekTrack.scrubFrac = fracAt(m.x)
                            }
                            onReleased: (m) => {
                                Media.seek(fracAt(m.x) * Media.length)
                                seekTrack.scrubbing = false
                            }
                            onCanceled: seekTrack.scrubbing = false
                        }
                    }

                    Item {
                        width: parent.width
                        height: 11

                        Text {
                            anchors.left: parent.left
                            text: Media.formatTime(seekTrack.scrubbing
                                ? seekTrack.scrubFrac * Media.length : Media.livePosition)
                            color: seekTrack.scrubbing ? Theme.ink : Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                        Text {
                            anchors.right: parent.right
                            text: Media.length > 0 ? "-" + Media.formatTime(Media.length - Media.livePosition) : ""
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }

    Component {
        id: actionsComp

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            readonly property var enabledActions: {
                const all = Config.data.quickActions || []
                const out = []
                for (let i = 0; i < all.length; ++i) {
                    const a = all[i] || {}
                    //  Normalize: saved JSON can hand us QVariantMap values —
                    //  force plain strings so Glyph/Text get real strings.
                    out.push({
                        id:       typeof a.id === "string"       ? a.id       : "",
                        label:    typeof a.label === "string"    ? a.label    : "",
                        glyph:    typeof a.glyph === "string" && a.glyph.length > 0 ? a.glyph : Icons.circle,
                        command:  typeof a.command === "string"  ? a.command  : "",
                        builtin:  typeof a.builtin === "string"  ? a.builtin  : "",
                        enabled:  a.enabled !== false
                    })
                }
                return out
            }

            GridLayout {
                width: parent.width
                columns: 4
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: parent.parent.enabledActions

                    Rectangle {
                        id: actionCell
                        required property var modelData
                        Layout.fillWidth: true
                        height: 48
                        radius: Theme.radiusTile
                        color: qaArea.containsMouse ? Theme.surfaceHi
                            : (modelData.builtin === "dnd" && Notifs.dnd
                               || modelData.builtin === "night" && Power.nightActive
                               || modelData.builtin === "record" && Power.recording)
                              ? Theme.withAlpha(Theme.accent, 0.14) : Theme.track

                        scale: qaArea.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Glyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 14
                                colorVal: actionCell.modelData.builtin === "dnd" && Notifs.dnd
                                          || actionCell.modelData.builtin === "night" && Power.nightActive
                                    ? Theme.accent : Theme.ink
                                glyph: actionCell.modelData.glyph
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: actionCell.modelData.label
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 8
                                width: actionCell.width - 6
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            id: qaArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ccWindow.runAction(actionCell.modelData)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: tasksComp

        Column {
            width: parent ? parent.width : 0
            spacing: 6

            Row {
                width: parent.width
                height: 18
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Tasks"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Item { width: parent.width - 90; height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "clear done"
                    color: Tasks.items.filter(i => i.done).length > 0 ? Theme.accent : "transparent"
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Tasks.clearDone()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: Tasks.items

                    //  Item, NOT a Row: the text hangs off the circle and
                    //  the trash glyph hugs the right edge — both need
                    //  horizontal anchors, which Row children may not use.
                    Item {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 22

                        Rectangle {
                            id: checkCircle
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; radius: 7
                            color: parent.modelData.done ? Theme.accent : "transparent"
                            border.width: 1.5
                            border.color: parent.modelData.done ? Theme.accent : Theme.track
                            Glyph {
                                anchors.centerIn: parent
                                size: 8
                                colorVal: "#ffffff"
                                glyph: Icons.check
                                visible: parent.parent.modelData.done
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Tasks.toggle(parent.parent.index)
                            }
                        }

                        Text {
                            anchors.left: checkCircle.right
                            anchors.leftMargin: 8
                            anchors.right: delGlyph.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.text
                            color: parent.modelData.done ? Theme.muted : Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.strikeout: parent.modelData.done
                            elide: Text.ElideRight
                        }

                        Glyph {
                            id: delGlyph
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            size: 10
                            colorVal: delArea.containsMouse ? Theme.red : Theme.dim
                            glyph: Icons.trash
                            visible: delArea.containsMouse
                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Tasks.remove(parent.parent.index)
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 30
                spacing: 8

                TextField {
                    id: taskInput
                    width: parent.width - 40
                    height: 30
                    placeholderText: "Add a task…"
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    color: Theme.ink
                    placeholderTextColor: Theme.dim
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.surfaceHi
                        border.width: taskInput.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }
                    onAccepted: {
                        Tasks.add(taskInput.text)
                        taskInput.text = ""
                    }
                }

                Rectangle {
                    width: 32; height: 30
                    radius: Theme.radiusSmall
                    color: addArea.containsMouse ? Theme.surfaceHi : Theme.track
                    Glyph {
                        anchors.centerIn: parent
                        size: 11
                        colorVal: Theme.ink
                        glyph: Icons.plus
                    }
                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Tasks.add(taskInput.text)
                            taskInput.text = ""
                        }
                    }
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  FOCUS TIMER (r28) — pomodoro-grade countdown, state lives in
    //  services/FocusTimer.qml. Preset chips start a session right
    //  away, the big button starts / pauses, reset returns to the full
    //  preset. The pill chip (IslandWindow) mirrors the countdown while
    //  the notch is closed, and the service raises a toast on finish.
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: focusComp

        Rectangle {
            id: focusTile
            width: parent ? parent.width : 0
            height: focusCol.implicitHeight + 20
            radius: Theme.radiusTile
            color: Theme.surfaceHi

            Column {
                id: focusCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                //  header: label + live state
                Item {
                    width: parent.width
                    height: 16

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 12
                            colorVal: Theme.purple
                            glyph: Icons.hourglass
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Focus"
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: FocusTimer.running ? ("running · " + FocusTimer.completions + " done")
                            : (FocusTimer.remaining < FocusTimer.totalSeconds ? "paused" : "ready")
                        color: FocusTimer.running ? Theme.green : Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                    }
                }

                //  dial + transport, progress strip underneath
                Item {
                    width: parent.width
                    height: 40

                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Theme.track
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: Math.max(3, focusTile.width * FocusTimer.progress - 20)
                        height: 3
                        radius: 1.5
                        color: Theme.purple

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.Linear } }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        text: FocusTimer.label()
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 8

                        //  start / pause — the big transport button
                        Rectangle {
                            width: 64
                            height: 30
                            radius: 15
                            color: FocusTimer.running ? Theme.withAlpha(Theme.yellow, 0.18) : Theme.withAlpha(Theme.purple, 0.22)
                            scale: fPlayArea.pressed ? 0.93 : 1

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 5
                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 10
                                    colorVal: FocusTimer.running ? Theme.yellow : Theme.purple
                                    glyph: FocusTimer.running ? Icons.pause : Icons.play
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: FocusTimer.running ? "Pause"
                                        : (FocusTimer.remaining < FocusTimer.totalSeconds ? "Resume" : "Start")
                                    color: FocusTimer.running ? Theme.yellow : Theme.purple
                                    font.family: Theme.uiFont
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }
                            MouseArea {
                                id: fPlayArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: FocusTimer.toggle()
                            }
                        }

                        //  reset
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: fResetArea.containsMouse ? Theme.track : Theme.withAlpha(Theme.ink, 0.06)
                            scale: fResetArea.pressed ? 0.88 : 1

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            Glyph {
                                anchors.centerIn: parent
                                size: 11
                                colorVal: Theme.muted
                                glyph: Icons.refresh
                            }
                            MouseArea {
                                id: fResetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: FocusTimer.reset()
                            }
                        }
                    }
                }

                //  preset chips — each starts a session right away; the
                //  service refuses to re-arm mid-run, so a stray tap can
                //  never shorten a live countdown.
                Row {
                    width: parent.width
                    height: 22
                    spacing: 6

                    Repeater {
                        model: [5, 15, 25, 50]

                        Rectangle {
                            id: presetChip
                            required property var modelData
                            readonly property bool sel: !FocusTimer.running
                                && FocusTimer.totalSeconds === modelData * 60
                            width: 44
                            height: 22
                            radius: 11
                            color: sel ? Theme.withAlpha(Theme.purple, 0.3) : Theme.withAlpha(Theme.ink, 0.07)
                            scale: presetArea.pressed ? 0.9 : 1

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: presetChip.modelData + "m"
                                color: presetChip.sel ? Theme.ink : Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: presetChip.sel ? Font.DemiBold : Font.Medium
                            }
                            MouseArea {
                                id: presetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: FocusTimer.start(presetChip.modelData)
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "tap a preset to start now"
                        color: Theme.dim
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                    }
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  FEATURES PANE (r24) — the per-feature enable/disable switches,
    //  now a menu INSIDE the notch ("buat jadi di menu mana gitu dong,
    //  atau toggle"). Every switch writes the same config keys the
    //  old Settings-only toggles used, and every reader (UiState
    //  gates, Notifs, Podman, Agent, dock, HUD) reacts instantly.
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: featuresComp

        Column {
            width: parent ? parent.width : 0
            spacing: 6

            Text {
                width: parent.width
                text: "Switch whole features on or off. Off means the pill zone, the keybind, the swipe deck and the launcher all skip it."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: [
                    { key: "controlCenter.enabled",  glyph: Icons.sliders,   label: "Control Center" },
                    { key: "launcher.enabled",       glyph: Icons.search,    label: "Launcher (Win+Space)" },
                    { key: "notifications.enabled",  glyph: Icons.bell,      label: "Notifications" },
                    { key: "calendar.enabled",       glyph: Icons.calendar,  label: "Calendar" },
                    { key: "island.showWeather",     glyph: Icons.cloud,     label: "Weather" },
                    { key: "podman.enabled",         glyph: Icons.cubes,     label: "Containers (podman)" },
                    { key: "agent.enabled",          glyph: Icons.robot,     label: "AI Agent" },
                    { key: "clipboard.enabled",      glyph: "\uF0EA",       label: "Clipboard History" },
                    { key: "plugins.enabled",        glyph: Icons.cubes,     label: "Plugins" },
                    { key: "dock.enabled",           glyph: Icons.desktop,   label: "Dock" },
                    { key: "hud.enabled",            glyph: Icons.volumeHigh,label: "Volume / Brightness HUD" },
                    { key: "island.peekEnabled",     glyph: Icons.mouseIcon, label: "Hover Peek" },
                    { key: "focus.enabled",          glyph: Icons.hourglass, label: "Focus Timer" },
                    { key: "tasks.enabled",          glyph: Icons.tasks,     label: "Tasks" }
                ]

                delegate: Rectangle {
                    id: featRow
                    required property var modelData
                    width: parent ? parent.width : 0
                    height: 34
                    radius: 8
                    color: Theme.withAlpha(Theme.ink, 0.06)

                    readonly property bool on: Config.get(modelData.key, true)

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        spacing: 9

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 6
                            color: Theme.withAlpha(Theme.accent, 0.15)
                            Glyph {
                                anchors.centerIn: parent
                                size: 10
                                colorVal: Theme.accent
                                glyph: featRow.modelData.glyph
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: featRow.modelData.label
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                        }
                    }

                    //  ── the switch ────────────────────────────────
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        width: 34
                        height: 20
                        radius: 10
                        color: featRow.on ? Theme.accent : Theme.withAlpha(Theme.ink, 0.18)

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: featRow.on ? parent.width - width - 2 : 2
                            width: 16
                            height: 16
                            radius: 8
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.set(featRow.modelData.key, !featRow.on)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set(featRow.modelData.key, !featRow.on)
                    }
                }
            }

            //  Escape hatch: if the user switches off the control
            //  center while standing in it, the pill closes; tell them
            //  how to get back BEFORE they do it.
            Text {
                width: parent.width
                text: "Closed the Control Center by accident? Launcher (Super+Space) → Control Center, or Super+C, reopens it."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }
        }
    }

    //  ── Quick action dispatch ─────────────────────────────────────
    function runAction(action) {
        switch (action.builtin) {
        case "dnd":      Notifs.toggleDnd();    return
        case "night":    Power.toggleNight();   return
        case "lock":     UiState.activePopup = "none"; Power.lock(); return
        case "record":   Power.record();        return
        case "terminal": Power.openTerminal();  return
        case "files":    Power.openFiles();     return
        case "settings": Power.openSettings();  return
        case "stats":    UiState.openPopup("stats");     return
        case "wallpaper":UiState.openPopup("wallpaper"); return
        case "power":    UiState.openPopup("power");     return
        case "about":    UiState.openPopup("about");     return
        case "weather":  UiState.openPopup("weather");   return
        }
        if (action.builtin === "screenshot" || action.id === "screenshot") {
            Power.screenshot()
            return
        }
        if (action.command && action.command.length > 0)
            Power.run(action.command)
    }
}
