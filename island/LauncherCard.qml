import QtQuick
import Quickshell
import "../core"
import "../services"

//  App launcher — hosted INSIDE the island body, k4 style: the pill
//  grows into a search panel right under the clock.
//
//  Opened by pressing SUPER (bindr on SUPER_L — see sample-hyprland.conf)
//  or SUPER+D. Fuzzy filter over DesktopEntries (the same engine the
//  dock uses), 4-column grid with REAL app icons, arrow keys + Enter
//  run the selection, ESC closes. While hosted, the island window
//  holds the keyboard exclusively (see IslandWindow).

Item {
    id: launcherCard

    property var apps: []
    property string query: ""
    property int selected: 0

    //  Island contract
    property int prefWidth: 560
    implicitHeight: 430

    readonly property var filtered: {
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
        return out.slice(0, 24)
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
                }

                Keys.onUpPressed: {
                    if (launcherCard.selected > 0)
                        launcherCard.selected -= 1
                }
                Keys.onDownPressed: {
                    if (launcherCard.selected < launcherCard.filtered.length - 1)
                        launcherCard.selected += 1
                }
                Keys.onReturnPressed: launcherCard.run(launcherCard.filtered[launcherCard.selected] ? launcherCard.filtered[launcherCard.selected].entry : null)
                Keys.onEnterPressed: launcherCard.run(launcherCard.filtered[launcherCard.selected] ? launcherCard.filtered[launcherCard.selected].entry : null)

                Text {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: "Search apps…  (Enter to open, Esc to close)"
                    color: Theme.dim
                    font.family: searchInput.font.family
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                }
            }
        }

        //  ── App grid: real icons, 4 columns ───────────────────────
        Flickable {
            width: parent.width
            height: 350
            contentWidth: width
            contentHeight: appGrid.implicitHeight
            clip: true
            interactive: contentHeight > height

            Grid {
                id: appGrid
                width: parent.width
                columns: 4
                spacing: 8

                Repeater {
                    model: launcherCard.filtered

                    delegate: Item {
                        id: appCell
                        required property var modelData
                        required property int index
                        readonly property bool sel: launcherCard.selected === index

                        width: (parent.width - parent.spacing * 3) / 4
                        height: 76

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusTile
                            color: appCell.sel ? Theme.withAlpha(Theme.accent, 0.22)
                                : (cellArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.09) : "transparent")
                            border.width: appCell.sel ? 1 : 0
                            border.color: Theme.accent
                            scale: cellArea.pressed ? 0.94 : 1

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 5
                            width: parent.width - 10

                            Item {
                                width: 34
                                height: 34
                                anchors.horizontalCenter: parent.horizontalCenter

                                Image {
                                    anchors.fill: parent
                                    visible: appCell.modelData.icon.length > 0
                                    source: visible ? appCell.modelData.icon : ""
                                    sourceSize: Qt.size(68, 68)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    mipmap: true
                                    smooth: true
                                }
                                Glyph {
                                    anchors.centerIn: parent
                                    visible: appCell.modelData.icon.length === 0
                                    size: 20
                                    colorVal: Theme.muted
                                    glyph: Icons.window
                                }
                            }

                            Text {
                                width: parent.width
                                text: appCell.modelData.name
                                color: appCell.sel ? Theme.ink : Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: 9
                                font.weight: appCell.sel ? Font.DemiBold : Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcherCard.run(appCell.modelData.entry)
                            onContainsMouseChanged: if (containsMouse) launcherCard.selected = appCell.index
                        }
                    }
                }
            }
        }
    }
}
