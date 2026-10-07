import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../core"
import "../services"
import "../island"

//  HyprNotch Settings — the customization hub.
//  Every widget, popup section, quick action and dock pin is edited
//  here and applied live through Config.set(). Nothing needs a restart.

Window {
    id: settingsWindow

    visible: UiState.settingsOpen
    onVisibleChanged: {
        if (visible) {
            Config.save()
            Podman.refresh()
            aboutProbe.running = true      //  cold identity read for About
        }
    }

    width: 980
    height: 640
    minimumWidth: 820
    minimumHeight: 540
    title: "HyprNotch Settings"
    color: "#101012"

    //  ══════════════════════════════════════════════════════════════
    //  Shared inline building blocks
    //  ══════════════════════════════════════════════════════════════

    component SectionLabel: Text {
        color: Theme.muted
        font.family: Theme.uiFont
        font.pixelSize: 10
        font.weight: Font.DemiBold
        bottomPadding: 2
    }

    component SwitchRow: Rectangle {
        id: switchRow
        property string title: ""
        property string sub: ""
        property bool checked: false
        signal flipped()
        width: parent ? parent.width : 0
        height: 40
        radius: Theme.radiusSmall
        color: Theme.surface

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            text: switchRow.title
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 12
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12 + switchRow.title.length * 7 + 14
            text: switchRow.sub
            color: Theme.dim
            font.family: Theme.uiFont
            font.pixelSize: 10
        }
        AppToggle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 12
            checked: switchRow.checked
            onToggled: switchRow.flipped()
        }
    }

    component SliderRow: Rectangle {
        id: sliderRow
        property string title: ""
        property string sub: ""
        property real value: 0
        property real from: 0
        property real to: 100
        property string suffix: ""
        property int decimals: 0
        signal edited(real v)
        width: parent ? parent.width : 0
        height: 46
        radius: Theme.radiusSmall
        color: Theme.surface

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            text: sliderRow.title
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 12
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12 + sliderRow.title.length * 7 + 14
            visible: sliderRow.sub !== ""
            text: sliderRow.sub
            color: Theme.dim
            font.family: Theme.uiFont
            font.pixelSize: 10
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 12
            text: (sliderRow.decimals > 0
                       ? sliderRow.value.toFixed(sliderRow.decimals)
                       : Math.round(sliderRow.value)) + sliderRow.suffix
            color: Theme.accent
            font.family: Theme.uiFont
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        AppSlider {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            width: parent.width - 24
            height: 14
            from: sliderRow.from
            to: sliderRow.to
            value: sliderRow.value
            onValueEdited: (v) => sliderRow.edited(v)
        }
    }

    component FieldRow: Rectangle {
        id: fieldRow
        property string label: ""
        property alias text: innerField.text
        property alias placeholder: innerField.placeholderText
        signal committed(string value)
        width: parent ? parent.width : 0
        height: 40
        radius: Theme.radiusSmall
        color: Theme.surface

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            width: 110
            text: fieldRow.label
            color: Theme.muted
            font.family: Theme.uiFont
            font.pixelSize: 11
        }
        TextField {
            id: innerField
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 128
            anchors.right: parent.right
            anchors.rightMargin: 12
            height: 30
            font.family: Theme.uiFont
            font.pixelSize: 11
            color: Theme.ink
            placeholderTextColor: Theme.dim
            background: Rectangle {
                radius: Theme.radiusSmall
                color: Theme.surfaceHi
                border.width: innerField.activeFocus ? 1 : 0
                border.color: Theme.accent
            }
            onAccepted: fieldRow.committed(innerField.text)
            onActiveFocusChanged: if (!activeFocus) fieldRow.committed(innerField.text)
        }
    }

    component GlyphPick: Row {
        id: glyphPick
        property string chosen: ""
        signal userPicked(string g)
        //  Fires ONLY on a real user click — writing config from
        //  onChosenChanged looped forever (chosen <- config <- chosen).
        spacing: 4

        readonly property var presets: [
            "\uF120", "\uF07B", "\uF26C", "\uF001", "\uF0F3", "\uF186",
            "\uF030", "\uF03D", "\uF013", "\uF073", "\uF1EB", "\uF11B"
        ]

        Repeater {
            model: glyphPick.presets
            delegate: Rectangle {
                required property var modelData
                width: 22; height: 22; radius: 6
                color: glyphPick.chosen === modelData ? Theme.accent : Theme.track
                Glyph {
                    anchors.centerIn: parent
                    size: 10
                    colorVal: "#ffffff"
                    glyph: parent.modelData
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        //  Only the signal: the config write-back updates
                        //  `chosen` through its binding. Writing chosen here
                        //  too re-entered the same property mid-notification
                        //  — the second reported binding loop.
                        glyphPick.userPicked(parent.modelData)
                    }
                }
            }
        }
    }

    //  ── Keybind capture state (Settings → Keybinds) ─────────────
    //  Lives on the window root so the inline KeyRow component and the
    //  page delegates share one capture session: exactly one row
    //  listens for a chord at a time.
    property string capturingAction: ""
    property string capMods: ""
    property string capKey: ""
    property string capMsg: ""

    //  Dock pin editor state (Settings → Dock → Pinned apps)
    property bool addPinOpen: false
    property var addPinResults: []

    //  One row per island action: folded state shows the current chord,
    //  capturing state turns the row into a live key catcher. The focus
    //  Item grabs activeFocus the moment the row enters capture mode and
    //  decodes events through Hotkeys.modsFromEvent / keyName.
    component KeyRow: Rectangle {
        id: keyRow
        property string action: ""
        property string title: ""
        property string sub: ""
        property var chord: null
        property string status: ""          // "set" | "busy" | "fail"
        property bool capturing: false
        signal startCapture()
        signal clearChord()
        signal cancelCapture()
        signal commitChord(string mods, string key)

        width: parent ? parent.width : 0
        height: keyRow.capturing ? 98 : 50
        radius: Theme.radiusSmall
        color: keyRow.capturing ? Theme.surfaceHi : Theme.surface
        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        Item {
            id: catcher
            anchors.fill: parent
            focus: keyRow.capturing
            Keys.onPressed: (e) => {
                e.accepted = true
                if (!keyRow.capturing)
                    return
                if (e.key === Qt.Key_Escape) {
                    keyRow.cancelCapture()
                    return
                }
                const mods = Hotkeys.modsFromEvent(e)
                if (e.key === Qt.Key_Shift || e.key === Qt.Key_Control
                    || e.key === Qt.Key_Alt || e.key === Qt.Key_Meta) {
                    settingsWindow.capMods = mods.join(" ")
                    settingsWindow.capKey = ""
                    settingsWindow.capMsg = mods.length > 0
                        ? (mods.join(" + ") + " + …  —  now the main key")
                        : "hold a modifier — Super / Ctrl / Alt / Shift"
                    return
                }
                if (mods.length === 0) {
                    settingsWindow.capMods = ""
                    settingsWindow.capKey = ""
                    settingsWindow.capMsg = "add a modifier — Super / Ctrl / Alt / Shift"
                    return
                }
                const k = Hotkeys.keyName(e)
                if (k.length === 0) {
                    settingsWindow.capKey = ""
                    settingsWindow.capMsg = "that key is not supported — try another"
                    return
                }
                settingsWindow.capMods = mods.join(" ")
                settingsWindow.capKey = k
                settingsWindow.capMsg = ""
            }
        }
        onCapturingChanged: {
            if (capturing)
                catcher.forceActiveFocus()
        }

        //  ── folded layout ─────────────────────────────────────────
        Row {
            visible: !keyRow.capturing
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            spacing: 10

            Column {
                spacing: 1
                Text {
                    text: keyRow.title
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    text: keyRow.sub
                    color: Theme.dim
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
        }

        Row {
            visible: !keyRow.capturing
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 12
            spacing: 8

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyRow.status === "busy"
                size: 11
                colorVal: Theme.yellow
                glyph: Icons.warning
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyRow.status === "busy"
                text: "taken by another program"
                color: Theme.yellow
                font.family: Theme.uiFont
                font.pixelSize: 9
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyRow.status === "fail"
                text: "apply failed"
                color: Theme.red
                font.family: Theme.uiFont
                font.pixelSize: 9
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: chipLabel.width + 20
                height: 26
                radius: 13
                color: keyRow.chord ? Theme.track : "transparent"
                border.width: keyRow.chord ? 0 : 1
                border.color: Theme.track
                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: keyRow.chord ? Hotkeys.chordLabel(keyRow.chord) : "unbound"
                    color: keyRow.chord ? Theme.ink : Theme.dim
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 26; radius: 6
                color: keyEditArea.containsMouse ? Theme.surfaceHi : Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "Edit"
                    color: "#ffffff"
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: keyEditArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: keyRow.startCapture()
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyRow.chord !== null
                width: 26; height: 26; radius: 6
                color: keyClearArea.containsMouse ? "#5c1a16" : Theme.track
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: keyRow.chord ? Theme.muted : "transparent"
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                }
                MouseArea {
                    id: keyClearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: keyRow.clearChord()
                }
            }
        }

        //  ── capturing layout ──────────────────────────────────────
        Column {
            visible: keyRow.capturing
            anchors.fill: parent
            anchors.margins: 10
            spacing: 7

            Row {
                spacing: 8
                Text {
                    text: "Press the new chord for " + keyRow.title
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    text: settingsWindow.capMsg
                    color: Theme.accent
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }

            Row {
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: previewLabel.width + 20
                    height: 26
                    radius: 13
                    color: Theme.withAlpha(Theme.accent, 0.16)
                    Text {
                        id: previewLabel
                        anchors.centerIn: parent
                        text: settingsWindow.capKey.length > 0
                            ? (settingsWindow.capMods + " + " + settingsWindow.capKey)
                            : (settingsWindow.capMods.length > 0
                                ? settingsWindow.capMods + " + …"
                                : "waiting…")
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: settingsWindow.capKey.length > 0
                    width: 54; height: 26; radius: 6
                    color: keySaveArea.containsMouse ? Theme.surfaceHi : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        color: "#ffffff"
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: keySaveArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: keyRow.commitChord(settingsWindow.capMods, settingsWindow.capKey)
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54; height: 26; radius: 6
                    color: keyCancelArea.containsMouse ? Theme.surfaceHi : Theme.track
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: keyCancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: keyRow.cancelCapture()
                    }
                }
            }

            Text {
                text: "Esc cancels · needs at least one modifier · chords used by another action are rejected"
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  Layout: sidebar + page
    //  ══════════════════════════════════════════════════════════════

    readonly property var navItems: [
        { key: "general",    label: "General",        glyph: Icons.sliders },
        { key: "island",     label: "Island",         glyph: Icons.desktop },
        { key: "control",    label: "Control Center", glyph: Icons.chart },
        { key: "actions",    label: "Quick Actions",  glyph: Icons.bolt },
        { key: "keys",       label: "Keybinds",       glyph: Icons.keyboard },
        { key: "dock",       label: "Dock",           glyph: Icons.window },
        { key: "notifs",     label: "Notifications",  glyph: Icons.bell },
        { key: "calendar",   label: "Calendar",       glyph: Icons.calendar },
        { key: "wallpapers", label: "Wallpapers",     glyph: Icons.image },
        { key: "plugins",    label: "Plugins",        glyph: Icons.plug },
        { key: "podman",     label: "Containers",     glyph: Icons.cubes },
        { key: "agent",      label: "AI Agent",       glyph: Icons.robot },
        { key: "about",      label: "About",          glyph: Icons.circleCheck }
    ]

    Row {
        anchors.fill: parent

        //  ── Sidebar ───────────────────────────────────────────────
        Rectangle {
            width: 190
            height: parent.height
            color: "#141416"

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                Row {
                    spacing: 8
                    leftPadding: 6
                    topPadding: 4
                    bottomPadding: 10

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        colorVal: Theme.accent
                        glyph: Icons.desktop
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "HyprNotch"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                Repeater {
                    model: settingsWindow.navItems

                    delegate: Rectangle {
                        id: navItem
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 32
                        radius: Theme.radiusSmall
                        color: UiState.settingsPage === navItem.modelData.key
                            ? Theme.surfaceHi : "transparent"

                        Rectangle {
                            width: 3
                            height: 14
                            radius: 1.5
                            color: Theme.accent
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: UiState.settingsPage === navItem.modelData.key
                        }

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            size: 12
                            colorVal: UiState.settingsPage === navItem.modelData.key
                                ? Theme.ink : Theme.muted
                            glyph: navItem.modelData.glyph
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 36
                            text: navItem.modelData.label
                            color: UiState.settingsPage === navItem.modelData.key
                                ? Theme.ink : Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: UiState.settingsPage === navItem.modelData.key
                                ? Font.DemiBold : Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: UiState.settingsPage = navItem.modelData.key
                        }
                    }
                }
            }
        }

        //  ── Page area ─────────────────────────────────────────────
        Item {
            width: parent.width - 190
            height: parent.height

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: pageLoader.item ? (pageLoader.item.implicitHeight || pageLoader.item.height) + 48 : 0
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Loader {
                    id: pageLoader
                    x: 24
                    y: 24
                    width: parent ? parent.width - 48 : 0
                    sourceComponent: {
                        switch (UiState.settingsPage) {
                        case "island":     return islandPage
                        case "control":    return controlPage
                        case "actions":    return actionsPage
                        case "keys":       return keybindsPage
                        case "dock":       return dockPage
                        case "notifs":     return notifsPage
                        case "calendar":   return calendarPage
                        case "wallpapers": return wallpapersPage
                        case "plugins":    return pluginsPage
                        case "podman":     return podmanPage
                        case "agent":      return agentPage
                        case "about":      return aboutPage
                        default:           return generalPage
                        }
                    }
                }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  Pages
    //  ══════════════════════════════════════════════════════════════

    //  ── General ───────────────────────────────────────────────────
    Component {
        id: generalPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "ACCENT COLOR" }

            Rectangle {
                width: parent.width
                height: 52
                radius: Theme.radiusSmall
                color: Theme.surface

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8

                    Repeater {
                        model: ["#0a84ff", "#bf5af2", "#ff375f", "#ff9f0a", "#30d158", "#64d2ff", "#8e8e93"]
                        delegate: Rectangle {
                            required property var modelData
                            width: 26; height: 26; radius: 13
                            color: modelData
                            border.width: Theme.accent === modelData ? 2 : 0
                            border.color: Theme.ink
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Config.set("general.accent", parent.modelData)
                                    Theme.accent = parent.modelData
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 8
                        text: Config.data.general.accent
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                }
            }

            SectionLabel { text: "BEHAVIOR"; topPadding: 10 }

            SwitchRow {
                title: "Animations"
                sub: "smooth motion across the shell"
                checked: Config.get("general.animations", true)
                onFlipped: Config.set("general.animations", !Config.data.general.animations)
            }
        }
    }

    //  ── Island ────────────────────────────────────────────────────
    Component {
        id: islandPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "PILL" }

            SwitchRow {
                title: "Enabled"
                sub: "show the island pill (works with or without the dock)"
                checked: Config.data.island.enabled
                onFlipped: Config.set("island.enabled", !Config.data.island.enabled)
            }
            SwitchRow {
                title: "Launcher"
                sub: "the app grid + command search — Super+Space by default; off = the chord does nothing"
                checked: Config.get("launcher.enabled", true)
                onFlipped: Config.set("launcher.enabled",
                                      !Config.get("launcher.enabled", true))
            }
            SliderRow {
                title: "Pill height"
                from: 28; to: 52
                value: Config.data.island.pillHeight
                suffix: " px"
                onEdited: (v) => Config.set("island.pillHeight", Math.round(v))
            }

            SectionLabel { text: "LEFT ZONE"; topPadding: 10 }

            SwitchRow {
                title: "Show date next to the clock"
                checked: Config.data.island.showDate
                onFlipped: Config.set("island.showDate", !Config.data.island.showDate)
            }
            SwitchRow {
                title: "Clock opens the calendar"
                sub: "calendar never opens from the main pill body"
                checked: Config.data.island.clockOpensCalendar
                onFlipped: Config.set("island.clockOpensCalendar", !Config.data.island.clockOpensCalendar)
            }

            SectionLabel { text: "MIDDLE ZONE"; topPadding: 10 }

            SwitchRow {
                title: "Show workspaces"
                checked: Config.data.island.showWorkspaces
                onFlipped: Config.set("island.showWorkspaces", !Config.data.island.showWorkspaces)
            }

            SectionLabel { text: "RIGHT ZONE"; topPadding: 10 }

            SwitchRow {
                title: "Audio indicator"
                checked: Config.data.island.showAudio
                onFlipped: Config.set("island.showAudio", !Config.data.island.showAudio)
            }
            SwitchRow {
                title: "Microphone indicator"
                checked: Config.data.island.showMic
                onFlipped: Config.set("island.showMic", !Config.data.island.showMic)
            }
            SwitchRow {
                title: "Network indicator"
                checked: Config.data.island.showNetwork
                onFlipped: Config.set("island.showNetwork", !Config.data.island.showNetwork)
            }
            SwitchRow {
                title: "Battery indicator"
                checked: Config.data.island.showBattery
                onFlipped: Config.set("island.showBattery", !Config.data.island.showBattery)
            }

            SectionLabel { text: "MEDIA"; topPadding: 10 }

            SwitchRow {
                title: "Audio visualizer (cava)"
                sub: "spectrum in the pill, peek and media tile while music plays — " + Cava.status
                checked: Config.get("island.cava", true)
                onFlipped: Config.set("island.cava", !Config.get("island.cava", true))
            }
        }
    }

    //  ── Control Center ────────────────────────────────────────────
    Component {
        id: controlPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "POPUP" }

            SwitchRow {
                title: "Enabled"
                sub: "opens from the right zone of the pill"
                checked: Config.data.controlCenter.enabled
                onFlipped: Config.set("controlCenter.enabled", !Config.data.controlCenter.enabled)
            }
            SliderRow {
                title: "Popup width"
                from: 300; to: 440
                value: Config.data.controlCenter.width
                suffix: " px"
                onEdited: (v) => Config.set("controlCenter.width", Math.round(v))
            }
            SliderRow {
                title: "Tile columns"
                from: 2; to: 4
                value: Config.data.controlCenter.tileColumns
                suffix: ""
                onEdited: (v) => Config.set("controlCenter.tileColumns", Math.round(v))
            }

            SectionLabel { text: "SECTIONS — toggle and reorder (applies live)"; topPadding: 10 }

            readonly property var sectionLabels: ({
                toggles: "Connection toggles", system: "System (About · Monitor · Wallpaper)",
                sliders: "Sliders (brightness · volume · mic)",
                media: "Media player", stats: "System stats", quickActions: "Quick actions",
                weather: "Weather", plugins: "Plugins row", tasks: "Tasks",
                focus: "Focus Timer"
            })

            Repeater {
                model: Config.data.controlCenter.sections

                delegate: Rectangle {
                    id: sectionRow
                    required property string modelData
                    required property int index
                    width: parent ? parent.width : 0
                    height: 38
                    radius: Theme.radiusSmall
                    color: Theme.surface

                    readonly property bool isOn: Config.data.controlCenter.sectionEnabled[sectionRow.modelData] !== false

                    AppToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        checked: sectionRow.isOn
                        onToggled: Config.set("controlCenter.sectionEnabled." + sectionRow.modelData,
                                              !Config.data.controlCenter.sectionEnabled[sectionRow.modelData])
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 64
                        text: (sectionRow.index + 1) + ". " + controlPageSectionLabels(sectionRow.modelData)
                        color: sectionRow.isOn ? Theme.ink : Theme.dim
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        spacing: 4

                        Rectangle {
                            width: 24; height: 24; radius: 6
                            color: upArea.containsMouse ? Theme.surfaceHi : Theme.track
                            Glyph { anchors.centerIn: parent; size: 9; colorVal: Theme.ink; glyph: Icons.arrowUp }
                            MouseArea {
                                id: upArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.moveItem("controlCenter.sections", sectionRow.index, sectionRow.index - 1)
                            }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 6
                            color: downArea.containsMouse ? Theme.surfaceHi : Theme.track
                            Glyph { anchors.centerIn: parent; size: 9; colorVal: Theme.ink; glyph: Icons.arrowDown }
                            MouseArea {
                                id: downArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.moveItem("controlCenter.sections", sectionRow.index, sectionRow.index + 1)
                            }
                        }
                    }
                }
            }
        }
    }

    function controlPageSectionLabels(key) {
        const map = {
            toggles: "Connection toggles", system: "System (About · Monitor · Wallpaper)",
            sliders: "Sliders (brightness · volume · mic)",
            media: "Media player", stats: "System stats", quickActions: "Quick actions",
            weather: "Weather", plugins: "Plugins row", tasks: "Tasks",
            focus: "Focus Timer"
        }
        return map[key] || key
    }

    //  ── Quick Actions ─────────────────────────────────────────────
    Component {
        id: actionsPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "QUICK ACTIONS — edit, enable, disable, add your own" }

            Repeater {
                model: Config.data.quickActions || []

                delegate: Rectangle {
                    id: actionEdit
                    required property var modelData
                    required property int index
                    //  Stale index during removals can point past the array.
                    readonly property var qa: Config.data.quickActions[index] || null
                    width: parent ? parent.width : 0
                    height: 118
                    radius: Theme.radiusSmall
                    color: Theme.surface

                    Row {
                        x: 12; y: 10
                        width: parent.width - 24
                        spacing: 10

                        AppToggle {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: actionEdit.modelData.enabled !== false
                            onToggled: settingsWindow.updateQuickAction(actionEdit.index, "enabled",
                                !(Config.data.quickActions[actionEdit.index].enabled !== false))
                        }

                        Column {
                            width: parent.width - 56
                            spacing: 6

                            Row {
                                spacing: 6
                                width: parent.width

                                Rectangle {
                                    width: 28; height: 28; radius: 8
                                    color: Theme.surfaceHi
                                    anchors.verticalCenter: parent.verticalCenter
                                    Glyph {
                                        anchors.centerIn: parent
                                        size: 13
                                        colorVal: Theme.ink
                                        glyph: actionEdit.qa && typeof actionEdit.qa.glyph === "string" ? actionEdit.qa.glyph : Icons.circle
                                    }
                                }
                                TextField {
                                    id: labelField
                                    width: parent.width - 180
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: actionEdit.qa && typeof actionEdit.qa.label === "string" ? actionEdit.qa.label : ""
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    selectByMouse: true
                                    background: Rectangle {
                                        radius: 6; color: Theme.surfaceHi
                                        border.width: labelField.activeFocus ? 1 : 0
                                        border.color: Theme.accent
                                    }
                                    onEditingFinished: settingsWindow.updateQuickAction(actionEdit.index, "label", text)
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 6
                                    color: delAct.containsMouse ? Theme.red : Theme.track
                                    anchors.verticalCenter: parent.verticalCenter
                                    Glyph { anchors.centerIn: parent; size: 10; colorVal: "#ffffff"; glyph: Icons.trash }
                                    MouseArea {
                                        id: delAct; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: settingsWindow.removeQuickAction(actionEdit.index)
                                    }
                                }
                            }

                            TextField {
                                id: cmdField
                                width: parent.width - 60
                                height: 26
                                text: actionEdit.qa && typeof actionEdit.qa.command === "string" ? actionEdit.qa.command : ""
                                enabled: actionEdit.qa ? actionEdit.qa.builtin === "" : false
                                color: Theme.muted
                                font.family: "monospace"
                                font.pixelSize: 10
                                selectByMouse: true
                                placeholderText: actionEdit.qa && actionEdit.qa.builtin !== ""
                                    ? "built-in action — pick a custom command by adding a new action"
                                    : "shell command to run"
                                background: Rectangle {
                                    radius: 6; color: Theme.surfaceHi
                                    border.width: cmdField.activeFocus ? 1 : 0
                                    border.color: Theme.accent
                                    opacity: parent.enabled ? 1 : 0.5
                                }
                                onEditingFinished: settingsWindow.updateQuickAction(actionEdit.index, "command", text)
                            }

                            GlyphPick {
                                chosen: actionEdit.qa ? actionEdit.qa.glyph : ""
                                onUserPicked: (g) => settingsWindow.updateQuickAction(actionEdit.index, "glyph", g)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 150; height: 32
                radius: Theme.radiusSmall
                color: addAction.containsMouse ? Theme.surfaceHi : Theme.track
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph { anchors.verticalCenter: parent.verticalCenter; size: 11; colorVal: Theme.ink; glyph: Icons.plus }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add action"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: addAction; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsWindow.addQuickAction()
                }
            }
        }
    }

    //  ── Keybinds — every island chord, editable live ──────────────
    Component {
        id: keybindsPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "ISLAND ACTIONS" }

            Text {
                text: "Click Edit and press the new combination. Chords apply the moment you save; the old bind is removed automatically and your own non-Notch chords are never touched."
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                width: parent.width
                bottomPadding: 4
            }

            Repeater {
                model: Hotkeys.actions

                delegate: KeyRow {
                    id: keyDelegate
                    //  Hotkeys.actions is a plain STRING list (the r24
                    //  user report "kedetec jumlah, tpi kosong": the
                    //  summary counted 19 applied, but every row read
                    //  `modelData.action` — which is undefined on a
                    //  string — so titles, chords and the Edit flow all
                    //  rendered empty/dead). modelData IS the action id.
                    readonly property string actionId: String(modelData)
                    readonly property var meta: Hotkeys.labels[actionId]
                        ? Hotkeys.labels[actionId] : { title: actionId, sub: "" }

                    action: actionId
                    title: meta.title
                    sub: meta.sub
                    chord: Hotkeys.map[actionId] || null
                    status: (Hotkeys.applyStatus && Hotkeys.applyStatus[actionId])
                        ? Hotkeys.applyStatus[actionId] : ""
                    capturing: settingsWindow.capturingAction === actionId

                    onStartCapture: {
                        settingsWindow.capturingAction = actionId
                        settingsWindow.capMods = ""
                        settingsWindow.capKey = ""
                        settingsWindow.capMsg = "press a combination  —  Esc cancels"
                    }
                    onClearChord: Hotkeys.clearBinding(actionId)
                    onCancelCapture: settingsWindow.capturingAction = ""
                    onCommitChord: (mods, key) => {
                        const res = Hotkeys.setBinding(actionId, mods, key)
                        if (res.ok) {
                            settingsWindow.capturingAction = ""
                        } else {
                            const other = (Hotkeys.labels[res.conflict]
                                && Hotkeys.labels[res.conflict].title)
                                ? Hotkeys.labels[res.conflict].title : res.conflict
                            settingsWindow.capMsg = "already used by " + other
                        }
                    }
                }
            }

            //  r24: the apply summary is deliberately small and quiet —
            //  it auto-clears after 8 s (Hotkeys.autoClear) and only
            //  shouts (yellow) when something is actually wrong.
            SectionLabel { text: "STATUS"; topPadding: 10 }

            Rectangle {
                width: parent.width
                height: 30
                radius: Theme.radiusSmall
                color: Theme.surface

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    width: parent.width - 190
                    text: Hotkeys.lastSummary.length > 0 ? Hotkeys.lastSummary : "keybinds applied at launch"
                    color: Hotkeys.hyprctlMissing || Hotkeys.applierMissing || Hotkeys.bindsMissing
                        ? Theme.yellow : Theme.dim
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    width: 110; height: 28; radius: 6
                    color: reapplyArea.containsMouse ? Theme.surfaceHi : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Re-apply"
                        color: "#ffffff"
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: reapplyArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hotkeys.apply()
                    }
                }
            }

            SectionLabel { text: "NOTES"; topPadding: 10 }

            Text {
                text: "· k4 Lua fork — every edit rewrites ~/.config/hypr/config/hyprnotch.lua, so bindings survive hyprctl reload.\n" +
                      "· Classic config — binds are runtime-only: after a manual hyprctl reload press Re-apply, or run\n" +
                      "   quickshell ipc -p ~/.config/quickshell/hyprnotch/shell.qml call notch applyKeys\n" +
                      "· A chord held by another program shows the warning badge and is skipped — HyprNotch never hijacks your keys."
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Rectangle {
                width: 220; height: 34
                radius: Theme.radiusSmall
                color: resetKeysArea.containsMouse ? "#5c1a16" : Theme.withAlpha(Theme.red, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: "Reset to factory chords"
                    color: Theme.red
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: resetKeysArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hotkeys.resetToDefaults()
                }
            }
        }
    }

    //  ── Dock — the hyprland-dock port ──────────────────────────────
    Component {
        id: dockPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "DOCK — hyprland-dock by nick-friedrich, ported" }

            SwitchRow {
                title: "Enabled"
                sub: "the dock and the pill are independent — both can be on"
                checked: Config.data.dock.enabled
                onFlipped: Config.set("dock.enabled", !Config.data.dock.enabled)
            }

            SectionLabel { text: "AUTO-HIDE"; topPadding: 10 }

            SwitchRow {
                title: "Auto-hide"
                sub: "hide until the pointer touches the screen edge — toggle also lives in the dock's right-click menu"
                checked: Config.data.dock.autoHide
                onFlipped: Config.set("dock.autoHide", !Config.data.dock.autoHide)
            }
            SliderRow {
                title: "Hide delay"
                from: 0; to: 1500
                value: Config.data.dock.hideDelay
                suffix: " ms"
                onEdited: (v) => Config.set("dock.hideDelay", Math.round(v))
            }
            SwitchRow {
                title: "Primary display only"
                sub: "off = the dock shows on every monitor"
                checked: Config.data.dock.primaryOnly
                onFlipped: Config.set("dock.primaryOnly", !Config.data.dock.primaryOnly)
            }

            SectionLabel { text: "BEHAVIOR"; topPadding: 10 }

            //  Click action — upstream focus-or-launch vs always launch
            Rectangle {
                width: parent ? parent.width : 0
                height: 46
                radius: Theme.radiusSmall
                color: Theme.surface

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: "Click action"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    spacing: 4

                    Repeater {
                        model: [
                            { k: "focus-or-launch", label: "Focus or launch" },
                            { k: "launch",          label: "Always launch" }
                        ]
                        delegate: Rectangle {
                            id: clickSeg
                            required property var modelData
                            readonly property bool sel:
                                Config.data.dock.clickAction === clickSeg.modelData.k
                            width: 116; height: 26
                            radius: 6
                            color: sel ? Theme.accent : Theme.track
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: parent.sel ? "#ffffff" : Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: parent.sel ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.set("dock.clickAction", clickSeg.modelData.k)
                            }
                        }
                    }
                }
            }
            SliderRow {
                title: "Magnification amount"
                from: 1.0; to: 2.5
                decimals: 2
                value: Config.data.dock.magnification
                suffix: "\u00d7"
                onEdited: (v) => Config.set("dock.magnification", v)
            }
            SliderRow {
                title: "Magnification radius"
                sub: "distance over which nearby icons magnify"
                from: 40; to: 220
                value: Config.data.dock.magnificationRadius
                suffix: " px"
                onEdited: (v) => Config.set("dock.magnificationRadius", Math.round(v))
            }

            SectionLabel { text: "POSITION"; topPadding: 10 }

            Rectangle {
                width: parent ? parent.width : 0
                height: 46
                radius: Theme.radiusSmall
                color: Theme.surface

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: "Screen edge"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    spacing: 4

                    Repeater {
                        model: [
                            { k: "left",   label: "Left" },
                            { k: "bottom", label: "Bottom" },
                            { k: "right",  label: "Right" },
                            { k: "top",    label: "Top" }
                        ]
                        delegate: Rectangle {
                            id: posSeg
                            required property var modelData
                            readonly property bool sel:
                                Config.data.dock.position === posSeg.modelData.k
                            width: 56; height: 26
                            radius: 6
                            color: sel ? Theme.accent : Theme.track
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: parent.sel ? "#ffffff" : Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 11
                                font.weight: parent.sel ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.set("dock.position", posSeg.modelData.k)
                            }
                        }
                    }
                }
            }
            SwitchRow {
                title: "Full length"
                sub: "stretch the dock along the whole screen edge"
                checked: Config.data.dock.fullLength
                onFlipped: Config.set("dock.fullLength", !Config.data.dock.fullLength)
            }
            SwitchRow {
                title: "Reserve screen space"
                sub: "tiled windows stop beside the dock — auto-hidden docks always overlay"
                checked: Config.data.dock.reserveSpace
                onFlipped: Config.set("dock.reserveSpace", !Config.data.dock.reserveSpace)
            }

            SectionLabel { text: "APPEARANCE"; topPadding: 10 }

            SliderRow {
                title: "Icon size"
                from: 32; to: 96
                value: Config.data.dock.iconSize
                suffix: " px"
                onEdited: (v) => Config.set("dock.iconSize", Math.round(v))
            }
            SliderRow {
                title: "Distance from screen edge"
                from: 0; to: 40
                value: Config.data.dock.margin
                suffix: " px"
                onEdited: (v) => Config.set("dock.margin", Math.round(v))
            }
            SliderRow {
                title: "Background opacity"
                sub: "the frosted bar material — compositor blur sits under it"
                from: 0; to: 1
                decimals: 2
                value: Config.data.dock.backgroundOpacity
                suffix: ""
                onEdited: (v) => Config.set("dock.backgroundOpacity", v)
            }
            SwitchRow {
                title: "Frosted blur"
                sub: "compositor blur behind the frosted bar — applied when the shell starts (start.sh)"
                checked: Config.data.dock.blur !== false
                onFlipped: Config.set("dock.blur", Config.data.dock.blur === false)
            }

            SectionLabel { text: "PINNED APPS"; topPadding: 10 }

            Text {
                width: parent ? parent.width : 0
                text: "Also managed live from the dock itself: right-click an icon for Add Application / Remove from Dock, and drag pinned icons to reorder. Everything below writes the same config keys and applies instantly."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                leftPadding: 12
            }

            //  ── Current pins ─────────────────────────────────────────
            Column {
                width: parent ? parent.width : 0
                spacing: 4

                Repeater {
                    model: Config.data.dock.pinned || []

                    delegate: Rectangle {
                        id: pinRow
                        required property var modelData
                        required property int index
                        //  Read the applications model first so this
                        //  binding re-runs once the async desktop-entry
                        //  scan lands (the DockItem trick).
                        readonly property var apps: DesktopEntries.applications.values || []
                        readonly property var entry: {
                            const modelRevision = pinRow.apps.length
                            void modelRevision
                            return DesktopEntries.byId(pinRow.modelData)
                        }

                        width: parent ? parent.width : 0
                        height: 44
                        radius: Theme.radiusSmall
                        color: pinArea.containsMouse ? Theme.surfaceHi : Theme.surface

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            spacing: 10

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24
                                asynchronous: true
                                source: pinRow.entry && pinRow.entry.icon
                                    ? Quickshell.iconPath(pinRow.entry.icon, true)
                                    : Quickshell.iconPath("application-x-executable", true)
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 420
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: pinRow.entry && pinRow.entry.name
                                        ? pinRow.entry.name : pinRow.modelData
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: pinRow.modelData
                                    color: Theme.dim
                                    font.family: Theme.uiFont
                                    font.pixelSize: 9
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            spacing: 4

                            Rectangle {
                                width: 26; height: 26; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: pinUp.containsMouse ? Theme.surfaceHi : Theme.track
                                opacity: pinUp.enabled ? 1 : 0.35
                                Glyph { anchors.centerIn: parent; size: 9; colorVal: Theme.ink; glyph: Icons.arrowUp }
                                MouseArea {
                                    id: pinUp; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: pinRow.index > 0
                                    onClicked: Config.moveItem("dock.pinned", pinRow.index, pinRow.index - 1)
                                }
                            }
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: pinDown.containsMouse ? Theme.surfaceHi : Theme.track
                                opacity: pinDown.enabled ? 1 : 0.35
                                Glyph { anchors.centerIn: parent; size: 9; colorVal: Theme.ink; glyph: Icons.arrowDown }
                                MouseArea {
                                    id: pinDown; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: pinRow.index < (Config.data.dock.pinned || []).length - 1
                                    onClicked: Config.moveItem("dock.pinned", pinRow.index, pinRow.index + 1)
                                }
                            }
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: pinDel.containsMouse ? Theme.red : Theme.track
                                Glyph { anchors.centerIn: parent; size: 10; colorVal: "#ffffff"; glyph: Icons.trash }
                                MouseArea {
                                    id: pinDel; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: settingsWindow.removeDockPin(pinRow.index)
                                }
                            }
                        }

                        MouseArea {
                            id: pinArea
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }

                Text {
                    visible: (Config.data.dock.pinned || []).length === 0
                    width: parent ? parent.width : 0
                    text: "No pinned apps — the dock shows running apps only. Add some below, or right-click any icon on the dock."
                    color: Theme.dim
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    leftPadding: 12
                    topPadding: 4
                }
            }

            //  ── Add application picker ───────────────────────────────
            Rectangle {
                width: parent ? parent.width : 0
                height: 38
                radius: Theme.radiusSmall
                color: addPinArea.containsMouse ? Theme.surfaceHi : Theme.surface
                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 11
                        colorVal: Theme.ink
                        glyph: Icons.plus
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: addPinOpen ? "Hide the picker" : "Add application…"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: addPinArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        addPinOpen = !addPinOpen
                        addPinResults = []
                        addPinSearch.text = ""
                        if (addPinOpen)
                            addPinSearch.forceActiveFocus()
                    }
                }
            }

            Column {
                visible: addPinOpen
                width: parent ? parent.width : 0
                spacing: 4

                TextField {
                    id: addPinSearch
                    width: parent.width - 24
                    height: 30
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    placeholderText: "search applications by name or id…"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    selectByMouse: true
                    background: Rectangle {
                        radius: 6
                        color: Theme.surfaceHi
                        border.width: addPinSearch.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }
                    onTextChanged: addPinResults = settingsWindow.dockSearchResults(text)
                }

                Repeater {
                    model: addPinResults

                    delegate: Rectangle {
                        id: pinResult
                        required property var modelData
                        width: parent ? parent.width - 24 : 0
                        height: 34
                        radius: 6
                        anchors.left: parent ? parent.left : undefined
                        anchors.leftMargin: 12
                        color: pinAddArea.containsMouse ? Theme.surfaceHi : Theme.surface

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            spacing: 8

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20
                                asynchronous: true
                                source: pinResult.modelData.icon
                                    ? Quickshell.iconPath(pinResult.modelData.icon, true)
                                    : Quickshell.iconPath("application-x-executable", true)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 400
                                text: pinResult.modelData.name + "  ·  " + pinResult.modelData.id
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                elide: Text.ElideMiddle
                            }
                        }

                        MouseArea {
                            id: pinAddArea; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                settingsWindow.addDockPin(pinResult.modelData.id)
                                addPinResults = settingsWindow.dockSearchResults(addPinSearch.text)
                            }
                        }
                    }
                }

                Text {
                    visible: addPinSearch.text.length > 0 && addPinResults.length === 0
                    text: "no matching applications"
                    color: Theme.dim
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    leftPadding: 12
                }
            }

            Rectangle {
                id: resetPinsBtn
                property bool armed: false
                width: 190; height: 32
                radius: Theme.radiusSmall
                color: resetPinsBtn.armed ? Theme.red
                       : (resetPinsMa.containsMouse ? Theme.surfaceHi : Theme.track)
                Behavior on color { ColorAnimation { duration: 140 } }
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph { anchors.verticalCenter: parent.verticalCenter; size: 11; colorVal: Theme.ink; glyph: Icons.trash }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: resetPinsBtn.armed ? "Click again to confirm" : "Reset Dock Items"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: resetPinsMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (resetPinsBtn.armed) {
                            resetPinsBtn.armed = false
                            dockResetDisarm.stop()
                            Config.setList("dock.pinned",
                                JSON.parse(JSON.stringify(Config.defaults.dock.pinned)))
                        } else {
                            resetPinsBtn.armed = true
                            dockResetDisarm.restart()
                        }
                    }
                }
                Timer {
                    id: dockResetDisarm
                    interval: 3000
                    onTriggered: resetPinsBtn.armed = false
                }
            }
        }
    }

    //  ── Notifications ─────────────────────────────────────────────
    Component {
        id: notifsPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "BANNERS" }

            SwitchRow {
                title: "Enabled"
                sub: "macOS-style banners, top-right"
                checked: Config.data.notifications.enabled
                onFlipped: Config.set("notifications.enabled", !Config.data.notifications.enabled)
            }
            SliderRow {
                title: "Banner duration"
                from: 2; to: 15
                value: Config.data.notifications.duration
                suffix: " s"
                onEdited: (v) => Config.set("notifications.duration", Math.round(v))
            }
            SliderRow {
                title: "Max stacked banners"
                from: 1; to: 6
                value: Config.data.notifications.maxVisible
                suffix: ""
                onEdited: (v) => Config.set("notifications.maxVisible", Math.round(v))
            }

            SectionLabel { text: "MODE"; topPadding: 10 }

            SwitchRow {
                title: "Do Not Disturb"
                sub: "banners silenced, history keeps everything"
                checked: Config.data.notifications.dnd
                onFlipped: Config.set("notifications.dnd", !Config.data.notifications.dnd)
            }
        }
    }

    //  ── Calendar ──────────────────────────────────────────────────
    Component {
        id: calendarPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "CALENDAR — opens ONLY from the clock/date click" }

            SwitchRow {
                title: "Enabled"
                checked: Config.data.calendar.enabled
                onFlipped: Config.set("calendar.enabled", !Config.data.calendar.enabled)
            }
            SwitchRow {
                title: "Week starts on Monday"
                checked: Config.data.calendar.firstDayMonday
                onFlipped: Config.set("calendar.firstDayMonday", !Config.data.calendar.firstDayMonday)
            }
            SwitchRow {
                title: "Show week numbers"
                checked: Config.data.calendar.showWeekNumbers
                onFlipped: Config.set("calendar.showWeekNumbers", !Config.data.calendar.showWeekNumbers)
            }
        }
    }

    //  ── Containers (Podman) ───────────────────────────────────────
    Component {
        id: podmanPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "PODMAN CONTAINERS" }

            SwitchRow {
                title: "Enabled"
                checked: Config.data.podman.enabled
                onFlipped: Config.set("podman.enabled", !Config.data.podman.enabled)
            }

            Rectangle {
                width: 150; height: 32
                radius: Theme.radiusSmall
                color: refreshBtn.containsMouse ? Theme.surfaceHi : Theme.track
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph { anchors.verticalCenter: parent.verticalCenter; size: 11; colorVal: Theme.ink; glyph: Icons.arrowUp }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Refresh"; color: Theme.ink; font.family: Theme.uiFont; font.pixelSize: 11 }
                }
                MouseArea {
                    id: refreshBtn; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Podman.refresh()
                }
            }

            Repeater {
                model: Podman.available ? Podman.containers : []

                delegate: Rectangle {
                    id: containerRow
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    height: 44
                    radius: Theme.radiusSmall
                    color: Theme.surface

                    readonly property bool running: modelData.state === "running"

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        width: parent.width - 220
                        spacing: 1

                        Text {
                            width: parent.width
                            text: containerRow.modelData.names
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: containerRow.modelData.image
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: parent.width - 200
                        width: 56; height: 18; radius: 9
                        color: containerRow.running
                            ? Theme.withAlpha(Theme.green, 0.18)
                            : Theme.withAlpha(Theme.red, 0.15)
                        Text {
                            anchors.centerIn: parent
                            text: containerRow.modelData.state
                            color: containerRow.running ? Theme.green : Theme.red
                            font.family: Theme.uiFont
                            font.pixelSize: 8
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        spacing: 4

                        Rectangle {
                            width: 30; height: 24; radius: 6
                            color: startBtn.containsMouse ? Theme.surfaceHi : Theme.track
                            Glyph { anchors.centerIn: parent; size: 9; colorVal: Theme.green; glyph: Icons.play }
                            MouseArea {
                                id: startBtn; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: containerRow.running
                                    ? Podman.stop(containerRow.modelData.names)
                                    : Podman.start(containerRow.modelData.names)
                            }
                        }
                        Rectangle {
                            width: 30; height: 24; radius: 6
                            color: logsBtn.containsMouse ? Theme.surfaceHi : Theme.track
                            Glyph { anchors.centerIn: parent; size: 9; colorVal: Theme.ink; glyph: Icons.terminal }
                            MouseArea {
                                id: logsBtn; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Podman.fetchLogs(containerRow.modelData.names)
                            }
                        }
                    }
                }
            }

            Text {
                visible: !Podman.available
                width: parent.width
                text: "Podman not found on this system. Install it to manage containers here."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 11
            }

            Rectangle {
                visible: Podman.logs.length > 0
                width: parent.width
                height: 180
                radius: Theme.radiusSmall
                color: "#0b0b0d"

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: logsText.implicitHeight
                    clip: true

                    Text {
                        id: logsText
                        width: parent.width
                        text: Podman.logs
                        color: Theme.muted
                        font.family: "monospace"
                        font.pixelSize: 9
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }

    //  ── AI Agent ──────────────────────────────────────────────────
    Component {
        id: agentPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "AI AGENT — status · usage · config" }

            //  ── Status & usage (r24: the notch card is status-only, so
            //  the full picture lives here too) ──────────────────────
            Rectangle {
                width: parent.width
                height: 64
                radius: Theme.radiusSmall
                color: Theme.surface

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10; radius: 5
                        color: Agent.status === "ready" ? Theme.green
                            : Agent.status === "running" ? Theme.accent
                            : Agent.status === "disabled" ? Theme.dim
                            : Theme.red
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Status: " + Agent.status
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: Agent.runs + " runs · last: "
                                  + (Agent.lastRun.length > 0 ? Agent.lastRun : "never")
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                        }
                    }
                }
            }

            SwitchRow {
                title: "Enabled"
                sub: "off = the notch card and every keybind politely report 'disabled'"
                checked: Config.data.agent.enabled
                onFlipped: Config.set("agent.enabled", !Config.data.agent.enabled)
            }

            FieldRow {
                label: "Command"
                text: Config.data.agent.command
                placeholder: "e.g. hermes"
                onCommitted: (v) => Config.set("agent.command", v.trim())
            }

            //  ── Runner mode (r25): command CLI or the user's own script
            readonly property var agentModes: [
                { k: "command", label: "Command" },
                { k: "script",  label: "My script" }
            ]

            Row {
                width: parent.width
                height: 26
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Runner mode"
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                }
                Item { width: 8; height: 1 }

                Repeater {
                    model: agentModes

                    delegate: Rectangle {
                        id: agentModeChip
                        required property var modelData
                        readonly property bool sel: (Config.get("agent.mode", "command")) === modelData.k
                        width: agentModeLabel.implicitWidth + 20
                        height: 24
                        radius: 12
                        color: sel ? Theme.accent : Theme.surface
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            id: agentModeLabel
                            anchors.centerIn: parent
                            text: agentModeChip.modelData.label
                            color: agentModeChip.sel ? "#ffffff" : Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            font.weight: agentModeChip.sel ? Font.DemiBold : Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.set("agent.mode", agentModeChip.modelData.k)
                        }
                    }
                }
            }

            FieldRow {
                label: "Script"
                text: Config.get("agent.script", "")
                placeholder: "default: ~/.config/hyprnotch/agent.sh"
                onCommitted: (v) => Config.set("agent.script", v.trim())
            }

            //  Create the agent script template (never overwrites)
            Rectangle {
                width: 250; height: 32
                radius: Theme.radiusSmall
                color: agentTplArea.containsMouse ? Theme.surfaceHi : Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: "Create agent script template"
                    color: "#ffffff"
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: agentTplArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Agent.createScriptTemplate()
                }
            }

            Text {
                text: "My script mode runs your script with the prompt as $1 — point it at any backend (aichat, sgpt, ollama, a curl call). The template lists common options."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                text: "The notch card for the agent is a status/usage viewer only — starting prompts is optional and lives here."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 240
                radius: Theme.radiusSmall
                color: "#0b0b0d"

                Flickable {
                    id: chatFlick
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: width
                    contentHeight: chatColumn.implicitHeight
                    clip: true

                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                    Column {
                        id: chatColumn
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: Agent.messages

                            delegate: Text {
                                required property var modelData
                                width: chatColumn.width
                                text: modelData.role === "user"
                                    ? "> " + modelData.text
                                    : modelData.text
                                color: modelData.role === "user" ? Theme.accent : Theme.muted
                                font.family: modelData.role === "user" ? Theme.uiFont : "monospace"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                        }

                        Text {
                            visible: Agent.thinking
                            text: "…"
                            color: Theme.dim
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 32
                spacing: 8

                TextField {
                    id: agentInput
                    width: parent ? parent.width : 0 - 76
                    height: 32
                    placeholderText: "Ask the agent…"
                    enabled: !Agent.thinking
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    placeholderTextColor: Theme.dim
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border.width: agentInput.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }
                    onAccepted: {
                        Agent.send(agentInput.text)
                        agentInput.text = ""
                    }
                }

                Rectangle {
                    width: 68; height: 32
                    radius: Theme.radiusSmall
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Send"
                        color: "#ffffff"
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Agent.send(agentInput.text)
                            agentInput.text = ""
                        }
                    }
                }
            }
        }
    }

    //  ── Wallpapers — the awww/swww picker, full-window edition ─────
    Component {
        id: wallpapersPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "WALLPAPER — awww / swww, with live transitions" }

            //  The island card, reused whole. It lays itself out from
            //  prefWidth; 720 gives the thumbnail grid four columns.
            Rectangle {
                width: parent.width
                height: islandWp.implicitHeight + 24
                radius: Theme.radiusSmall
                color: Theme.surface

                WallpaperCard {
                    id: islandWp
                    x: 12; y: 12
                    width: parent.width - 24
                    prefWidth: parent.width - 24
                }
            }

            Row {
                spacing: 8

                Rectangle {
                    width: 210; height: 34
                    radius: Theme.radiusSmall
                    color: wpOpenArea.containsMouse ? Theme.surfaceHi : Theme.track
                    Text {
                        anchors.centerIn: parent
                        text: "Open picker in the island"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: wpOpenArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsWindow.visible = false
                            UiState.openPopup("wallpaper")
                        }
                    }
                }
            }
        }
    }

    //  ── Plugins — the k4 manager: rows that unfold ─────────────────
    //  Closed, a row says the minimum: icon, name, where it came from
    //  and whether it is on. Unfolded (click the row, not the toggle)
    //  it says the rest: full path, the width it asks the island for,
    //  and buttons to open it live or rescan the folder.
    Component {
        id: pluginsPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "PLUGINS — drop .qml files into ~/.config/quickshell/hyprnotch/plugins/" }

            Repeater {
                model: pluginsPageRows()

                delegate: Rectangle {
                    id: pluginRow
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    height: pluginBody.implicitHeight + 18
                    radius: Theme.radiusSmall
                    color: pluginRow.opened ? Theme.surfaceHi
                        : (pluginHover.containsMouse ? Theme.surfaceHi : Theme.surface)
                    Behavior on color { ColorAnimation { duration: 140 } }

                    property bool opened: false
                    readonly property bool isEnabled: !Plugins.isDisabled(pluginRow.modelData.file)

                    Column {
                        id: pluginBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 9
                        spacing: 10

                        //  ── what is always visible ──
                        Row {
                            width: parent.width
                            height: 34
                            spacing: 11

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 13
                                colorVal: Theme.dim
                                glyph: Icons.chevronRight
                                rotation: pluginRow.opened ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30; height: 30; radius: 8
                                color: pluginRow.isEnabled ? Theme.withAlpha(Theme.accent, 0.16) : Theme.track
                                Glyph {
                                    anchors.centerIn: parent
                                    size: 13
                                    colorVal: pluginRow.isEnabled ? Theme.ink : Theme.dim
                                    glyph: pluginRow.modelData.icon
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 120
                                spacing: 1

                                Text {
                                    text: pluginRow.modelData.name
                                    color: pluginRow.isEnabled ? Theme.ink : Theme.dim
                                    font.family: Theme.uiFont
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    visible: !pluginRow.opened
                                    text: pluginRow.modelData.loaded
                                        ? pluginRow.modelData.file + " · " + pluginRow.modelData.prefWidth + "px"
                                        : pluginRow.modelData.file + " · disabled"
                                    color: Theme.dim
                                    font.family: Theme.uiFont
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            //  The switch. Same one the island obeys.
                            AppToggle {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: pluginRow.isEnabled
                                onToggled: Plugins.setDisabled(pluginRow.modelData.file, pluginRow.isEnabled)
                            }
                        }

                        //  ── what unfolds ──
                        Column {
                            width: parent.width
                            visible: pluginRow.opened
                            spacing: 8

                            Rectangle { width: parent.width; height: 1; color: Theme.withAlpha(Theme.ink, 0.06) }

                            Text {
                                text: pluginRow.modelData.loaded
                                    ? "Loaded from ~/.config/quickshell/hyprnotch/plugins/" + pluginRow.modelData.file
                                        + " — asks the island for " + pluginRow.modelData.prefWidth + "px of width."
                                    : "Not loaded — it was switched off, so the shell never instantiates it. Flip the switch to bring it back."
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                width: parent.width
                            }

                            Row {
                                spacing: 8
                                visible: pluginRow.modelData.loaded

                                Rectangle {
                                    width: 150; height: 30; radius: 6
                                    color: pOpenArea.containsMouse ? Theme.track : Theme.withAlpha(Theme.accent, 0.16)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Open in the island"
                                        color: Theme.accent
                                        font.family: Theme.uiFont
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: pOpenArea; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const act = Plugins.active
                                            for (let i = 0; i < act.length; ++i)
                                                if (act[i].file === pluginRow.modelData.file) {
                                                    Plugins.open(i)
                                                    return
                                                }
                                        }
                                    }
                                }
                                Rectangle {
                                    width: 110; height: 30; radius: 6
                                    color: pRescanArea.containsMouse ? Theme.track : Theme.withAlpha(Theme.ink, 0.07)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Rescan folder"
                                        color: Theme.ink
                                        font.family: Theme.uiFont
                                        font.pixelSize: 10
                                    }
                                    MouseArea {
                                        id: pRescanArea; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Plugins.reload()
                                    }
                                }
                            }
                        }
                    }

                    //  The click that unfolds, UNDER the inner controls so
                    //  the toggle and buttons keep their own clicks (k4 trick).
                    MouseArea {
                        id: pluginHover
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pluginRow.opened = !pluginRow.opened
                    }
                }
            }

            Text {
                visible: pluginsPageRows().length === 0
                text: "No plugins yet.\nDrop a .qml file with a `name` property into\n~/.config/quickshell/hyprnotch/plugins/"
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                topPadding: 20
            }
        }
    }

    function pluginsPageRows() {
        //  Reads through Config + Plugins so the Repeater model refreshes
        //  whenever either changes (the delegate index binding re-evaluates
        //  on revision bumps).
        const host = Config.get("plugins.disabled", [])
        void host
        void Plugins.revision
        const list = []
        const seen = {}
        for (let i = 0; i < Plugins.plugins.length; ++i) {
            const p = Plugins.plugins[i]
            seen[p.file] = true
            list.push({ file: p.file, name: p.name, icon: p.icon,
                        prefWidth: p.prefWidth, loaded: true })
        }
        const dis = Config.get("plugins.disabled", [])
        for (let j = 0; j < dis.length; ++j)
            if (!seen[dis[j]])
                list.push({ file: dis[j], name: dis[j], icon: "\uF023",
                            prefWidth: 0, loaded: false })
        return list
    }

    //  ── About — "About This Mac", island edition ──────────────────
    Component {
        id: aboutPage

        Column {
            width: parent ? parent.width : 0
            spacing: 14

            //  ── hero ──
            Row {
                width: parent.width
                spacing: 14

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56; height: 56; radius: 28
                    color: Theme.withAlpha(Theme.accent, 0.16)
                    Glyph {
                        anchors.centerIn: parent
                        size: 24
                        colorVal: Theme.ink
                        glyph: Icons.distro(SysMon.osId, SysMon.osIdLike)
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "HyprNotch"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }
                    Text {
                        text: settingsWindow.aboutValue("build") + " · A macOS-style Dynamic Island for Hyprland."
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                }
            }

            //  ── the three groups, two columns ──
            Row {
                width: parent.width
                spacing: 24

                Column {
                    width: (parent.width - 24) / 2
                    spacing: 14

                    AboutGroup {
                        width: parent.width
                        title: "Machine"
                        glyph: Icons.laptop
                        rows: [
                            { k: "Name",         v: settingsWindow.aboutValue("host") },
                            { k: "User",         v: settingsWindow.aboutValue("user") },
                            { k: "System",       v: settingsWindow.aboutValue("distro") },
                            { k: "Architecture", v: settingsWindow.aboutValue("arch") },
                            { k: "Kernel",       v: settingsWindow.aboutValue("kernel") },
                            { k: "Uptime",       v: SysMon.uptime }
                        ]
                    }
                }

                Column {
                    width: (parent.width - 24) / 2
                    spacing: 14

                    AboutGroup {
                        width: parent.width
                        title: "Desktop"
                        glyph: Icons.desktop
                        rows: [
                            { k: "Compositor", v: settingsWindow.aboutValue("hyprland") },
                            { k: "Session",    v: settingsWindow.aboutValue("session") },
                            { k: "Shell",      v: settingsWindow.aboutValue("shell") },
                            { k: "Framework",  v: settingsWindow.aboutValue("quickshell") }
                        ]
                    }

                    AboutGroup {
                        width: parent.width
                        title: "The notch"
                        glyph: Icons.circleCheck
                        rows: [
                            { k: "Build",    v: settingsWindow.aboutValue("build") },
                            { k: "License",  v: "MIT — (c) 2026 revyid" },
                            { k: "Source",   v: "github.com/revyid/hyprnotch" },
                            { k: "Config",   v: Config.filePath }
                        ]
                    }
                }
            }

            //  ── doors into the island pages ──
            Row {
                spacing: 8

                Rectangle {
                    width: 190; height: 34
                    radius: Theme.radiusSmall
                    color: aboutMonArea.containsMouse ? Theme.surfaceHi : Theme.track
                    Text {
                        anchors.centerIn: parent
                        text: "Open System Monitor"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: aboutMonArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsWindow.visible = false
                            UiState.openPopup("stats")
                        }
                    }
                }
                Rectangle {
                    width: 190; height: 34
                    radius: Theme.radiusSmall
                    color: aboutWpArea.containsMouse ? Theme.surfaceHi : Theme.track
                    Text {
                        anchors.centerIn: parent
                        text: "Wallpaper picker"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: aboutWpArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsWindow.visible = false
                            UiState.openPopup("wallpaper")
                        }
                    }
                }
            }

            SectionLabel { text: "DANGER ZONE"; topPadding: 12 }

            Rectangle {
                width: 200; height: 34
                radius: Theme.radiusSmall
                color: resetArea.containsMouse ? "#5c1a16" : Theme.withAlpha(Theme.red, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: "Reset all settings"
                    color: Theme.red
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: resetArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.resetToDefaults()
                }
            }
        }
    }

    //  A group of label/value rows, k4 AcercaDe style: quiet rótulos on
    //  the left, live values on the right, one hairline above.
    component AboutGroup: Column {
        id: aboutGroup

        property string title: ""
        property string glyph: ""
        property var rows: []

        width: parent ? parent.width : 0
        spacing: 6

        Row {
            spacing: 6
            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                size: 12
                colorVal: Theme.muted
                glyph: aboutGroup.glyph
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: aboutGroup.title
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        Repeater {
            model: aboutGroup.rows

            delegate: Row {
                id: aboutRowItem
                required property var modelData
                width: parent ? parent.width : 0
                spacing: 8

                Text {
                    width: 110
                    text: aboutRowItem.modelData.k
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                }
                Text {
                    width: parent.width - 118
                    text: aboutRowItem.modelData.v
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    //  One sh probe answers the whole page in key=value lines (k4's
    //  cold-read trick): nothing here polls, so About costs nothing.
    property var aboutInfo: ({})

    function aboutValue(key) {
        const v = aboutInfo[key]
        return v !== undefined && String(v).length > 0 ? String(v) : "-"
    }

    Process {
        id: aboutProbe
        command: ["sh", "-c",
            'echo "host=$(uname -n)"' + "\n" +
            'echo "user=$(id -un 2>/dev/null)"' + "\n" +
            '. /etc/os-release 2>/dev/null && echo "distro=$PRETTY_NAME"' + "\n" +
            'echo "arch=$(uname -m)"' + "\n" +
            'echo "kernel=$(uname -r)"' + "\n" +
            'echo "session=${XDG_CURRENT_DESKTOP:-$XDG_SESSION_TYPE}"' + "\n" +
            'echo "shell=${SHELL:-}"' + "\n" +
            'command -v hyprctl >/dev/null 2>&1 && echo "hyprland=$(hyprctl version 2>/dev/null | head -n 1)"' + "\n" +
            'command -v quickshell >/dev/null 2>&1 && echo "quickshell=$(quickshell --version 2>/dev/null | head -n 1)"' + "\n" +
            'cat "$HOME/.config/quickshell/hyprnotch/VERSION" 2>/dev/null | sed "s/^/build=/"']
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {}
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; ++i) {
                    const eq = lines[i].indexOf("=")
                    if (eq > 0)
                        next[lines[i].substring(0, eq)] = lines[i].substring(eq + 1)
                }
                settingsWindow.aboutInfo = next
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  Helpers for list editing + small info lookups
    //  ══════════════════════════════════════════════════════════════

    function updateQuickAction(index, key, value) {
        const arr = JSON.parse(JSON.stringify(Config.data.quickActions))
        if (index < 0 || index >= arr.length)
            return
        //  No-op guard: writing an identical value reassigns Config.data,
        //  recreates every delegate, drops the focused TextField's focus,
        //  and focus loss fires editingFinished again — the binding loop
        //  the runtime log caught. Same value → same config → no write.
        if (arr[index][key] === value)
            return
        arr[index][key] = value
        Config.setList("quickActions", arr)
    }

    function removeQuickAction(index) {
        const arr = JSON.parse(JSON.stringify(Config.data.quickActions))
        if (index < 0 || index >= arr.length)
            return
        arr.splice(index, 1)
        Config.setList("quickActions", arr)
    }

    function addQuickAction() {
        const arr = JSON.parse(JSON.stringify(Config.data.quickActions))
        arr.push({
            id: "custom-" + Date.now(),
            label: "New action",
            glyph: "\uF111",
            command: "",
            builtin: "",
            enabled: true
        })
        Config.setList("quickActions", arr)
    }

    //  ── Dock pin management — Settings side (r23) ──────────────────
    //  The dock itself still owns right-click → Add/Remove and drag to
    //  reorder; this editor mirrors dock.pinned for people who prefer
    //  doing it in one window. Writes go through the same config keys,
    //  so both stay in sync live.
    function removeDockPin(index) {
        const arr = (Config.data.dock.pinned || []).slice()
        if (index < 0 || index >= arr.length)
            return
        arr.splice(index, 1)
        Config.setList("dock.pinned", arr)
    }

    function addDockPin(desktopId) {
        const id = String(desktopId || "")
        if (id.length === 0)
            return
        const arr = (Config.data.dock.pinned || []).slice()
        if (arr.indexOf(id) >= 0)
            return
        arr.push(id)
        Config.setList("dock.pinned", arr)
    }

    //  First matches for the Add-application search. noDisplay entries
    //  and already-pinned ids are skipped; empty query → no results.
    function dockSearchResults(query) {
        const needle = String(query || "").toLowerCase().trim()
        const pins = Config.data.dock.pinned || []
        const apps = DesktopEntries.applications.values || []
        const out = []
        if (needle.length === 0)
            return out
        for (let i = 0; i < apps.length && out.length < 6; ++i) {
            const a = apps[i]
            if (!a || a.noDisplay)
                continue
            const id = String(a.id || "")
            if (pins.indexOf(id) >= 0)
                continue
            const name = String(a.name || "").toLowerCase()
            if (name.indexOf(needle) >= 0 || id.toLowerCase().indexOf(needle) >= 0)
                out.push(a)
        }
        return out
    }

    //  Pin management moved INTO the dock itself (Swift-Dock model):
    //  right-click an icon for Keep in Dock / Remove, drag icons to
    //  reorder.  Pins persist to config.json dock.pinned.  Settings →
    //  Dock only offers Reset Dock Items.
}
