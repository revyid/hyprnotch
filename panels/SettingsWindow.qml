import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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
        property real value: 0
        property real from: 0
        property real to: 100
        property string suffix: ""
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
            anchors.right: parent.right
            anchors.rightMargin: 12
            text: Math.round(sliderRow.value) + sliderRow.suffix
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

    //  ══════════════════════════════════════════════════════════════
    //  Layout: sidebar + page
    //  ══════════════════════════════════════════════════════════════

    readonly property var navItems: [
        { key: "general",    label: "General",        glyph: Icons.sliders },
        { key: "island",     label: "Island",         glyph: Icons.desktop },
        { key: "control",    label: "Control Center", glyph: Icons.chart },
        { key: "actions",    label: "Quick Actions",  glyph: Icons.bolt },
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
                weather: "Weather", plugins: "Plugins row", tasks: "Tasks"
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
            weather: "Weather", plugins: "Plugins row", tasks: "Tasks"
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

    //  ── Dock ──────────────────────────────────────────────────────
    Component {
        id: dockPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "DOCK — runs together with the island pill" }

            SwitchRow {
                title: "Enabled"
                sub: "the dock and the pill are independent — both can be on"
                checked: Config.data.dock.enabled
                onFlipped: Config.set("dock.enabled", !Config.data.dock.enabled)
            }
            SwitchRow {
                title: "Auto-hide"
                sub: "hide when unused, wake from the bottom edge"
                checked: Config.data.dock.autoHide
                onFlipped: Config.set("dock.autoHide", !Config.data.dock.autoHide)
            }
            SwitchRow {
                title: "Show running apps"
                checked: Config.data.dock.showRunning
                onFlipped: Config.set("dock.showRunning", !Config.data.dock.showRunning)
            }
            SwitchRow {
                title: "Magnify on hover"
                checked: Config.data.dock.magnify
                onFlipped: Config.set("dock.magnify", !Config.data.dock.magnify)
            }
            SliderRow {
                title: "Icon size"
                from: 28; to: 60
                value: Config.data.dock.iconSize
                suffix: " px"
                onEdited: (v) => Config.set("dock.iconSize", Math.round(v))
            }
            SliderRow {
                title: "Dock height"
                from: 44; to: 84
                value: Config.data.dock.dockHeight
                suffix: " px"
                onEdited: (v) => Config.set("dock.dockHeight", Math.round(v))
            }

            SectionLabel { text: "PINNED APPS — label, icon, command"; topPadding: 10 }

            Repeater {
                model: Config.data.dock.pinned

                delegate: Rectangle {
                    id: pinEdit
                    required property var modelData
                    required property int index
                    //  Stale index during removals can point past the array.
                    readonly property var pin: Config.data.dock.pinned[index] || null
                    width: parent ? parent.width : 0
                    height: 96
                    radius: Theme.radiusSmall
                    color: Theme.surface

                    Row {
                        x: 12; y: 10
                        width: parent.width - 24
                        spacing: 10

                        Rectangle {
                            width: 30; height: 30; radius: 8
                            color: Theme.surfaceHi
                            anchors.verticalCenter: parent.verticalCenter
                            Glyph {
                                anchors.centerIn: parent
                                size: 14
                                colorVal: Theme.ink
                                glyph: Config.data.dock.pinned[pinEdit.index].glyph
                            }
                        }

                        Column {
                            width: parent.width - 90
                            spacing: 6

                            Row {
                                spacing: 6
                                width: parent.width
                                TextField {
                                    id: pinLabelField
                                    width: parent.width / 2 - 3
                                    height: 26
                                    text: Config.data.dock.pinned[pinEdit.index].label
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 11
                                    selectByMouse: true
                                    background: Rectangle {
                                        radius: 6; color: Theme.surfaceHi
                                        border.width: pinLabelField.activeFocus ? 1 : 0
                                        border.color: Theme.accent
                                    }
                                    onEditingFinished: settingsWindow.updatePin(pinEdit.index, "label", text)
                                }
                                TextField {
                                    id: pinCmdField
                                    width: parent.width / 2 - 3
                                    height: 26
                                    text: Config.data.dock.pinned[pinEdit.index].command
                                    color: Theme.muted
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    selectByMouse: true
                                    placeholderText: "command (empty = try the label as a binary)"
                                    background: Rectangle {
                                        radius: 6; color: Theme.surfaceHi
                                        border.width: pinCmdField.activeFocus ? 1 : 0
                                        border.color: Theme.accent
                                    }
                                    onEditingFinished: settingsWindow.updatePin(pinEdit.index, "command", text)
                                }
                            }

                            GlyphPick {
                                chosen: pinEdit.pin ? pinEdit.pin.glyph : ""
                                onUserPicked: (g) => settingsWindow.updatePin(pinEdit.index, "glyph", g)
                            }
                        }

                        Rectangle {
                            width: 26; height: 26; radius: 6
                            color: delPin.containsMouse ? Theme.red : Theme.track
                            anchors.verticalCenter: parent.verticalCenter
                            Glyph { anchors.centerIn: parent; size: 10; colorVal: "#ffffff"; glyph: Icons.trash }
                            MouseArea {
                                id: delPin; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsWindow.removePin(pinEdit.index)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 150; height: 32
                radius: Theme.radiusSmall
                color: addPin.containsMouse ? Theme.surfaceHi : Theme.track
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph { anchors.verticalCenter: parent.verticalCenter; size: 11; colorVal: Theme.ink; glyph: Icons.plus }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add pinned app"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: addPin; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsWindow.addPin()
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

            SectionLabel { text: "AI AGENT — Hermes or any CLI chat tool" }

            SwitchRow {
                title: "Enabled"
                checked: Config.data.agent.enabled
                onFlipped: Config.set("agent.enabled", !Config.data.agent.enabled)
            }

            FieldRow {
                label: "Command"
                text: Config.data.agent.command
                placeholder: "e.g. hermes"
                onCommitted: (v) => Config.set("agent.command", v.trim())
            }

            Text {
                text: "The prompt is appended as the last argument. Output streams back here."
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 9
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

    //  ── Wallpapers — the swww picker, full-window edition ─────────
    Component {
        id: wallpapersPage

        Column {
            width: parent ? parent.width : 0
            spacing: 8

            SectionLabel { text: "WALLPAPER — swww, with live transitions" }

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
                        glyph: Icons.apple
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

                    settingsWindow.AboutGroup {
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

                    settingsWindow.AboutGroup {
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

                    settingsWindow.AboutGroup {
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

    function updatePin(index, key, value) {
        const arr = JSON.parse(JSON.stringify(Config.data.dock.pinned))
        if (index < 0 || index >= arr.length)
            return
        //  Same no-op guard as updateQuickAction: identical writes are
        //  the seed of the recreate → focus-loss → re-edit loop.
        if (arr[index][key] === value)
            return
        arr[index][key] = value
        Config.setList("dock.pinned", arr)
    }

    function removePin(index) {
        const arr = JSON.parse(JSON.stringify(Config.data.dock.pinned))
        if (index < 0 || index >= arr.length)
            return
        arr.splice(index, 1)
        Config.setList("dock.pinned", arr)
    }

    function addPin() {
        const arr = JSON.parse(JSON.stringify(Config.data.dock.pinned))
        arr.push({ label: "New app", glyph: "\uF111", command: "" })
        Config.setList("dock.pinned", arr)
    }
}
