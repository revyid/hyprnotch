import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

//  The Dynamic Island — the ONE window. k4 architecture:
//
//  · The layer surface is as tall as the screen and NEVER resizes.
//    The island Item animates INSIDE it with the signature OutBack
//    spring, staying centered: the pill never drifts while the body
//    morphs around it.
//  · FIVE morph states, all inside the pill (nothing ever pops out):
//      1. compact   — clock, weather, workspaces, status glyphs
//      2. peek      — hover glance: media, recent notifications,
//                     live stats, plugin chips
//      3. hud       — volume / brightness bars slide in under the
//                     pill when keys change them from anywhere
//      4. banner    — the island grows to hold incoming notification
//                     banners INSIDE its body (r16: they used to
//                     float as detached cards below the pill)
//      5. expanded  — a full card: control center, calendar, weather,
//                     notifications, launcher, stats, wallpaper,
//                     power, about, or a plugin view
//  · The input mask follows the island; with a view open a full-screen
//    hunter catches the outside click and closes it (k4's cazaClics).

PanelWindow {
    id: islandWindow

    readonly property var cfg: Config.data.island
    readonly property bool expanded: UiState.expanded
    readonly property bool launcherOpen: UiState.launcherOpen

    //  ── HUD state (inline) ────────────────────────────────────────
    readonly property bool hudActive: Config.get("hud.enabled", true)
        && !expanded && (Audio.hudOpen || Brightness.hudOpen)

    //  ── Banner state (inline) — notifications INSIDE the island ───
    //  While banners are alive and no view is open, the island itself
    //  grows to host them (macOS Dynamic Island behavior). Banner
    //  state beats peek: a notification takes over the body.
    readonly property bool bannerActive: !expanded && !hudActive
        && Notifs.banners.length > 0

    //  ── Peek state (hover glance) ─────────────────────────────────
    //  Armed shortly after the pointer settles on the pill, killed the
    //  moment it leaves — the delay keeps a fast pass-over from flashing.
    property bool peekActive: false
    readonly property bool peekWanted: cfg.peekEnabled && !expanded && !hudActive
        && !bannerActive && pillHover.hovered

    onPeekWantedChanged: {
        if (peekWanted)
            peekArm.restart()
        else {
            peekArm.stop()
            peekActive = false
        }
    }

    Timer {
        id: peekArm
        interval: 120
        onTriggered: islandWindow.peekActive = true
    }

    anchors.top: true
    anchors.left: true
    anchors.right: true

    //  Full-screen surface. Only the folded strip reserves desktop space;
    //  everything the island grows into floats over windows.
    color: "transparent"
    visible: cfg.enabled
    aboveWindows: true
    focusable: true

    implicitHeight: islandWindow.screen ? islandWindow.screen.height : 900
    exclusiveZone: cfg.pillHeight

    //  Keyboard: the launcher types, so it holds the keyboard exclusively
    //  while open (k4 grabKeyboard). The rest rely on OnDemand — a click
    //  on the island focuses it, which is all ESC needs.
    WlrLayershell.keyboardFocus: launcherOpen
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    //  ── Input mask ────────────────────────────────────────────────
    //  The island's region follows its animated geometry — banners now
    //  live inside the island body, so one region covers everything.
    //  With a view open, the whole surface joins the region so an
    //  outside tap has somewhere to land (closes the view, k4-style).
    mask: Region {
        item: island

        Region {
            item: islandWindow.expanded ? hunter : null
            intersection: Intersection.Combine
        }
    }

    //  ── Hunter: click-outside closes the open view ────────────────
    //  Declared BEFORE the island on purpose: the island stacks above
    //  and keeps every click aimed at it.
    Item {
        id: hunter
        anchors.fill: parent

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: UiState.closeAll()
        }
    }

    //  ── Clock text (1s refresh) ───────────────────────────────────
    property string timeText: ""
    property string dateText: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            islandWindow.timeText = Qt.formatTime(now, "HH:mm")
            islandWindow.dateText = Qt.formatDate(now, "ddd d MMM")
        }
    }

    //  ── Island geometry ───────────────────────────────────────────
    readonly property real pillBodyWidth: Math.max(180, pillRow.implicitWidth + 28)
    readonly property real pillFullWidth: pillBodyWidth + Theme.wing * 2

    readonly property bool pluginView: UiState.activePopup.indexOf("plugin:") === 0
    readonly property var pluginDescriptor: pluginView ? Plugins.descriptorForPopup(UiState.activePopup) : null

    //  The item currently claiming the expansion body.
    readonly property var viewItem: expanded ? (pluginView ? pluginLoader.item : viewLoader.item) : null

    readonly property real targetWidth: {
        if (expanded)
            return Math.max(pillFullWidth, (viewItem ? viewItem.prefWidth : 380) + Theme.wing * 2)
        if (hudActive)
            return Math.max(pillFullWidth, 320)
        if (peekActive)
            return Math.max(pillFullWidth, peekLoader.item ? peekLoader.item.prefWidth + Theme.wing * 2 : pillFullWidth)
        return pillFullWidth
    }

    readonly property real targetHeight: {
        if (expanded)
            return cfg.pillHeight + Math.max(80, viewItem ? viewItem.implicitHeight : 200)
        //  Banners unfold INSIDE the island body (r16).
        if (bannerActive)
            return cfg.pillHeight + bannerBody.height + 12
        //  HUD lives INSIDE the pill strip (k4): the notch just widens.
        if (hudActive)
            return cfg.pillHeight
        if (peekActive)
            return cfg.pillHeight + (peekLoader.item ? peekLoader.item.implicitHeight : 140)
        return cfg.pillHeight
    }

    //  ── THE ISLAND ────────────────────────────────────────────────
    Item {
        id: island

        //  Centered on the screen: x recomputes from width every frame,
        //  so the pill stays pinned while the body morphs around it.
        x: (parent.width - width) / 2
        y: 0
        width: islandWindow.targetWidth
        height: islandWindow.targetHeight

        //  The signature k4 spring (Theme tokens, verbatim k4 numbers).
        Behavior on width {
            NumberAnimation { duration: Theme.springWidth; easing.type: Easing.OutBack; easing.overshoot: Theme.springWidthOvershoot }
        }
        Behavior on height {
            NumberAnimation { duration: Theme.springHeight; easing.type: Easing.OutBack; easing.overshoot: Theme.springHeightOvershoot }
        }

        //  ESC closes whatever the island hosts (k4 hosts it once, at
        //  island level, so every current and future view inherits it).
        focus: true
        Keys.onPressed: function (ev) {
            if (ev.key === Qt.Key_Escape && UiState.expanded) {
                UiState.closeAll()
                ev.accepted = true
            }
        }

        //  Focus reclaim: when the item that held active focus dies
        //  (a view closes), the window loses active focus and ESC goes
        //  deaf until the next click. k4's fix: watch the window's
        //  activeFocusItem and pull focus back to the island whenever
        //  nobody holds it.
        readonly property var windowFocusItem: island.Window.activeFocusItem
        onWindowFocusItemChanged: if (!windowFocusItem) Qt.callLater(reclaimFocus)

        function reclaimFocus() {
            if (!island.Window.activeFocusItem)
                island.forceActiveFocus()
        }

        Component.onCompleted: island.forceActiveFocus()

        //  ── Swipe navigation (r25 rework): HOLD the mouse and DRAG
        //  horizontally — the open card follows the pointer (the morph),
        //  then either snaps back or commits to the previous / next
        //  notch page with a slide-and-spring handoff. The wheel is NOT
        //  a page switcher anymore: scrolling inside the launcher /
        //  clipboard lists used to fight the page deck and switch pages
        //  instead (r25 user report) — the wheel now belongs to the
        //  card under the cursor.
        //
        //  A DragHandler (not a MouseArea) on purpose: it takes only a
        //  passive grab first, so every click under it still lands, and
        //  the drag works even when it starts on top of a row or tile.
        property bool swipeArmed: false      // horizontal intent locked in
        property bool morphing: false        // commit animation in flight

        DragHandler {
            id: swipeDrag
            target: null
            acceptedButtons: Qt.LeftButton
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: !islandWindow.hudActive && !islandWindow.bannerActive
                && !islandWindow.morphing

            onActiveTranslationChanged: islandWindow.swipeFollow(swipeDrag.activeTranslation)
            onActiveChanged: {
                if (!active)
                    islandWindow.swipeRelease(swipeDrag.activeTranslation)
            }
        }

        function swipeFollow(p) {
            if (morphing)
                return
            if (!swipeArmed) {
                //  Horizontal intent must clearly beat vertical — a
                //  vertical drag stays a no-op (lists keep their drags).
                if (Math.abs(p.x) > 14 && Math.abs(p.x) > Math.abs(p.y) * 1.5)
                    swipeArmed = true
                else
                    return
            }
            //  Follow with resistance, capped so the card never flies off.
            const capped = Math.max(-180, Math.min(180, p.x * 0.62))
            morphLayer.x = capped
            morphLayer.rotation = capped * 0.012
            morphLayer.opacity = 1 - Math.min(0.45, Math.abs(capped) / 400)
        }

        function swipeRelease(p) {
            if (!swipeArmed || morphing) {
                swipeArmed = false
                return
            }
            swipeArmed = false
            if (Math.abs(p.x) > 95)
                commitSwipe(p.x < 0 ? 1 : -1)
            else
                swipeBack.restart()          // spring home, nothing happened
        }

        function commitSwipe(dir) {
            if (morphing)
                return
            morphing = true
            morphOut.dir = dir
            morphOut.restart()
        }

        //  Page changed from OUTSIDE the drag (keybind / IPC / pill) —
        //  never leave a half-morphed layer behind.
        property string morphGuardPage: UiState.activePopup
        onMorphGuardPageChanged: {
            if (!morphing) {
                morphLayer.x = 0
                morphLayer.rotation = 0
                morphLayer.opacity = 1
                swipeArmed = false
            }
        }

        //  Below threshold: the card springs home untouched.
        ParallelAnimation {
            id: swipeBack
            NumberAnimation { target: morphLayer; property: "x"; to: 0; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
            NumberAnimation { target: morphLayer; property: "rotation"; to: 0; duration: 240 }
            NumberAnimation { target: morphLayer; property: "opacity"; to: 1; duration: 160 }
        }

        //  Commit: slide out with the drag direction, swap the page,
        //  slide in from the other side — while the island's own width /
        //  height springs morph the geometry around the incoming card.
        SequentialAnimation {
            id: morphOut
            property int dir: 1

            ParallelAnimation {
                NumberAnimation { target: morphLayer; property: "x"; to: morphOut.dir * -170; duration: 140; easing.type: Easing.InQuad }
                NumberAnimation { target: morphLayer; property: "opacity"; to: 0; duration: 130; easing.type: Easing.InQuad }
                NumberAnimation { target: morphLayer; property: "scale"; to: 0.9; duration: 140; easing.type: Easing.InQuad }
            }
            ScriptAction { script: UiState.cyclePopup(morphOut.dir) }
            ParallelAnimation {
                NumberAnimation { target: morphLayer; property: "x"; from: morphOut.dir * 120; to: 0; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: morphLayer; property: "opacity"; from: 0; to: 1; duration: 220 }
                NumberAnimation { target: morphLayer; property: "scale"; from: 0.92; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
            }
            ScriptAction {
                script: {
                    morphLayer.rotation = 0
                    islandWindow.morphing = false
                }
            }
        }

        //  ── Silhouette: rounded body + inverted wings ─────────────
        IslandSilhouette {
            anchors.fill: parent
            wing: Theme.wing
            bodyRadius: Math.min(Theme.islandRadius, island.height / 2)
        }

        //  ── Pill strip: always visible, top of the island ─────────
        Item {
            id: pillStrip
            x: Theme.wing
            y: 0
            width: island.width - Theme.wing * 2
            height: islandWindow.cfg.pillHeight

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 12

                //  The HUD strip takes over the pill content while it
                //  flashes (k4 swaps in place instead of stacking).
                opacity: islandWindow.hudActive ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                //  ── Left: clock + date → calendar ────────────────
                MouseArea {
                    id: clockZone
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: clockText.implicitWidth + (dateText.visible ? dateText.implicitWidth + 6 : 0)
                    implicitHeight: islandWindow.cfg.pillHeight
                    cursorShape: Qt.PointingHandCursor
                    scale: clockZone.pressed ? 0.94 : 1

                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                    onClicked: {
                        if (islandWindow.cfg.clockOpensCalendar && Config.data.calendar.enabled)
                            UiState.togglePopup("calendar")
                        else
                            UiState.togglePopup("controlCenter")
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            id: clockText
                            anchors.verticalCenter: parent.verticalCenter
                            text: islandWindow.timeText
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            id: dateText
                            anchors.verticalCenter: parent.verticalCenter
                            visible: islandWindow.cfg.showDate
                            text: islandWindow.dateText
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                        }
                    }
                }

                //  ── Weather (tiny, macOS menu-bar style) → weather ─
                MouseArea {
                    id: weatherZone
                    visible: islandWindow.cfg.showWeather && Weather.ready
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: weatherRow.implicitWidth + 6
                    implicitHeight: islandWindow.cfg.pillHeight
                    cursorShape: Qt.PointingHandCursor
                    scale: weatherZone.pressed ? 0.94 : 1
                    hoverEnabled: true

                    Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                    onClicked: UiState.togglePopup("weather")

                    Row {
                        id: weatherRow
                        anchors.centerIn: parent
                        spacing: 4

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 12
                            colorVal: Weather.current && Weather.current.isDay ? Theme.yellow : Theme.teal
                            glyph: Weather.current ? Weather.icon(Weather.current.code, Weather.current.isDay) : ""
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.current ? Weather.current.temp + "°" : ""
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }

                //  ── Middle: smart workspaces ──────────────────────
                Row {
                    id: wsRow
                    visible: islandWindow.cfg.showWorkspaces
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: Hypr.visibleWorkspaces

                        delegate: Rectangle {
                            id: wsPill
                            required property var modelData
                            readonly property bool active: !modelData.overflowPill
                                && modelData.id === Hypr.focusedWorkspaceId
                            readonly property bool overflow: modelData.overflowPill === true

                            width: active ? 26 : (overflow ? 24 : 20)
                            height: 20
                            radius: 10
                            color: active ? Theme.accent
                                : (overflow ? Theme.withAlpha(Theme.ink, 0.08)
                                   : (wsArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.12) : "transparent"))
                            opacity: overflow ? 0.8 : 1.0
                            scale: wsArea.pressed ? 0.88 : 1

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on width { NumberAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: wsPill.overflow ? wsPill.modelData.name
                                    : (wsPill.modelData.id > 0 ? wsPill.modelData.id : wsPill.modelData.name)
                                color: wsPill.active ? "#ffffff" : Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 11
                                font.weight: wsPill.active ? Font.Bold : Font.Medium
                            }

                            MouseArea {
                                id: wsArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: wsPill.overflow ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: if (!wsPill.overflow) Hypr.switchTo(wsPill.modelData.id)
                            }
                        }
                    }
                }

                //  ── Right: bell (unseen) → notification center ────
                MouseArea {
                    id: bellZone
                    visible: Notifs.unseen > 0
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 20
                    implicitHeight: islandWindow.cfg.pillHeight
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: UiState.togglePopup("notifCenter")

                    //  Gentle attention pulse while something is unread.
                    SequentialAnimation on scale {
                        running: Notifs.unseen > 0 && !bellZone.pressed
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.18; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: 14
                        height: 14

                        Glyph {
                            anchors.centerIn: parent
                            size: 12
                            colorVal: Theme.ink
                            glyph: Icons.bell
                        }
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            width: 7; height: 7; radius: 3.5
                            color: Theme.red
                            border.width: 1
                            border.color: Theme.islandBg
                        }
                    }
                }

                //  ── Right: indicators → control center ───────────
                MouseArea {
                    id: statusZone
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: indicatorsRow.implicitWidth
                    implicitHeight: islandWindow.cfg.pillHeight
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: UiState.togglePopup("controlCenter")

                    Row {
                        id: indicatorsRow
                        anchors.centerIn: parent
                        spacing: 12

                        //  Audio (live: Pipewire) → power/battery zone below
                        Row {
                            visible: islandWindow.cfg.showAudio
                            spacing: 4
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 13
                                colorVal: Audio.muted ? Theme.red : Theme.ink
                                glyph: Icons.volumeIcon(Audio.volume, Audio.muted)
                            }
                            //  Fixed-width slot: the % text fades in on hover
                            //  WITHOUT widening the row — k4 rule: nothing the
                            //  island hosts may resize the island's own pill.
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 14
                                Text {
                                    anchors.centerIn: parent
                                    visible: statusZone.containsMouse
                                    opacity: visible ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                    text: Audio.muted ? "muted" : Audio.volume + "%"
                                    color: Theme.muted
                                    font.family: Theme.uiFont
                                    font.pixelSize: 10
                                }
                            }
                        }

                        //  Mic (live: Pipewire source)
                        Glyph {
                            visible: islandWindow.cfg.showMic
                            anchors.verticalCenter: parent.verticalCenter
                            size: 13
                            colorVal: Audio.micMuted ? Theme.red : Theme.ink
                            glyph: Audio.micMuted ? Icons.micSlash : Icons.mic
                        }

                        //  Network (live: NetworkManager)
                        Glyph {
                            visible: islandWindow.cfg.showNetwork
                            anchors.verticalCenter: parent.verticalCenter
                            size: 13
                            colorVal: (Net.wifiSsid.length > 0 || Net.wired) ? Theme.ink
                                : (Net.wifiEnabled ? Theme.yellow : Theme.red)
                            glyph: Net.wifiSsid.length > 0 ? Icons.wifiIcon(Net.connectedLevel)
                                : (Net.wired ? Icons.plug : Icons.wifiOff)
                        }

                        //  Battery (live: sysfs) → power menu
                        MouseArea {
                            id: batteryZone
                            visible: islandWindow.cfg.showBattery && SysMon.batteryPresent
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: batteryRow.implicitWidth + 4
                            implicitHeight: islandWindow.cfg.pillHeight
                            cursorShape: Qt.PointingHandCursor
                            scale: batteryZone.pressed ? 0.94 : 1
                            hoverEnabled: true

                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                            onClicked: UiState.togglePopup("power")

                            Row {
                                id: batteryRow
                                anchors.centerIn: parent
                                spacing: 4

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 14
                                    colorVal: SysMon.batteryCharging ? Theme.green
                                        : (SysMon.batteryPct <= 15 ? Theme.red : Theme.ink)
                                    glyph: Icons.batteryIcon(SysMon.batteryPct, SysMon.batteryCharging)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: SysMon.batteryPct + "%"
                                    color: Theme.muted
                                    font.family: Theme.uiFont
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            //  ── HUD strip (k4): volume / brightness INSIDE the pill ──
            //  The pill widens, the clock rows fade out, and a slim
            //  track replaces them — click or drag to set the level.
            Item {
                anchors.fill: parent
                visible: islandWindow.hudActive
                opacity: visible ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        colorVal: Theme.ink
                        glyph: Audio.hudOpen
                            ? Icons.volumeIcon(Audio.volume, Audio.muted)
                            : Icons.sun
                    }

                    Item {
                        id: hudTrack
                        anchors.verticalCenter: parent.verticalCenter
                        width: 170
                        height: 18

                        readonly property real pct: Audio.hudOpen
                            ? (Audio.muted ? 0 : Audio.volume / 100)
                            : Brightness.level / 100

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.track
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(6, hudTrack.pct * hudTrack.width)
                            height: 6
                            radius: 3
                            color: Theme.ink

                            Behavior on width { NumberAnimation { duration: 60 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            function apply(mx) {
                                const v = Math.max(0, Math.min(1, mx / hudTrack.width)) * 100
                                if (Audio.hudOpen)
                                    Audio.setVolume(Math.round(v))
                                else
                                    Brightness.setLevel(Math.round(v))
                            }
                            onPressed: (m) => apply(m.x)
                            onPositionChanged: (m) => {
                                if (pressed) apply(m.x)
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        text: Audio.hudOpen
                            ? (Audio.muted ? "—" : Audio.volume + "%")
                            : Brightness.level + "%"
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            //  Hover peek: see islandWindow.peekWanted — the handler
            //  only feeds the binding; the width spring does the rest.
            HoverHandler {
                id: pillHover
                acceptedButtons: Qt.NoButton
            }
        }

        //  ── Expansion body: hosts peek / the active view ──────────
        //  Clipped so content is revealed as the island grows (k4
        //  reads this as the view unfolding out of the pill).
        Item {
            id: expansion
            x: Theme.wing
            y: islandWindow.cfg.pillHeight
            width: island.width - Theme.wing * 2
            height: island.height - islandWindow.cfg.pillHeight
            clip: true

            //  ── Morph layer (r25): the drag-follow / page-handoff
            //  transform lives HERE, on a dedicated wrapper, so the
            //  banners and the peek keep their own private animations.
            Item {
                id: morphLayer
                anchors.fill: parent
                transformOrigin: Item.Center

                //  ── popup view (built-in cards) ───────────────────
                Loader {
                    id: viewLoader
                    anchors.fill: parent
                    active: UiState.expanded && !islandWindow.pluginView

                    sourceComponent: UiState.activePopup === "calendar" ? calComp
                        : UiState.activePopup === "notifCenter" ? notifComp
                        : UiState.activePopup === "launcher" ? launcherComp
                        : UiState.activePopup === "stats" ? statsComp
                        : UiState.activePopup === "weather" ? weatherComp
                        : UiState.activePopup === "wallpaper" ? wallpaperComp
                        : UiState.activePopup === "power" ? powerComp
                        : UiState.activePopup === "about" ? aboutComp
                        : UiState.activePopup === "plugins" ? pluginsComp
                        : UiState.activePopup === "containers" ? containersComp
                        : UiState.activePopup === "agent" ? agentComp
                        : UiState.activePopup === "clipboard" ? clipboardComp
                        : ccComp

                    opacity: active ? 1 : 0
                    y: active ? 0 : -16
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }

                //  ── popup view (plugin) — loads the plugin file itself ─
                Loader {
                    id: pluginLoader
                    anchors.fill: parent
                    active: islandWindow.pluginView
                    source: active && islandWindow.pluginDescriptor
                        ? islandWindow.pluginDescriptor.url : ""

                    opacity: active ? 1 : 0
                    y: active ? 0 : -16
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }

            //  ── Notification banners: INSIDE the island body ──────
            BannersRow {
                id: bannerBody
                anchors.top: parent.top
                width: parent.width
                preferredWidth: parent.width
                visible: islandWindow.bannerActive
                opacity: visible ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            //  ── Peek glance (hover) ───────────────────────────────
            Loader {
                id: peekLoader
                anchors.fill: parent
                active: islandWindow.peekActive && !islandWindow.bannerActive

                sourceComponent: PeekView {}

                opacity: active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }
    }

    //  ══════════════════════════════════════════════════════════════
    //  The views that live inside the island. Each one is a plain
    //  card Item: prefWidth names its natural width, implicitHeight
    //  reports its content height — the island reads both and springs
    //  to fit. One occupant at a time (UiState arbitrates).
    //  ══════════════════════════════════════════════════════════════

    Component {
        id: ccComp
        ControlCenterCard {}
    }

    Component {
        id: calComp
        CalendarCard {}
    }

    Component {
        id: notifComp
        NotifCenterCard {}
    }

    Component {
        id: launcherComp
        LauncherCard {}
    }

    Component {
        id: statsComp
        StatsCard {}
    }

    Component {
        id: weatherComp
        WeatherCard {}
    }

    Component {
        id: wallpaperComp
        WallpaperCard {}
    }

    Component {
        id: powerComp
        PowerCard {}
    }

    Component {
        id: aboutComp
        AboutCard {}
    }

    Component {
        id: pluginsComp
        PluginsCard {}
    }

    Component {
        id: containersComp
        ContainersCard {}
    }

    Component {
        id: agentComp
        AgentCard {}
    }

    Component {
        id: clipboardComp
        ClipboardCard {}
    }
}
