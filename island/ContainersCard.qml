import QtQuick
import "../core"
import "../services"

//  Containers — the podman manager INSIDE the notch (r24).
//
//  "trus containers ini, ada menunya harusnya di notch itu" — so here
//  it is: every container (running or stopped) with state dot + status,
//  and an inline action row per container (start / stop / restart /
//  logs). Tapping a row expands it; logs render in a monospace box.
//  Podman missing → honest hint, not a blank card.

Item {
    id: contCard

    //  Island contract
    property int prefWidth: 460
    implicitHeight: Math.max(150, body.height + 24)

    property int expandedIndex: -1

    property bool shown: UiState.activePopup === "containers"
    onShownChanged: if (shown) {
        expandedIndex = -1
        Podman.refresh()
    }

    readonly property int runningCount: {
        let n = 0
        for (let i = 0; i < Podman.containers.length; ++i) {
            const s = String(Podman.containers[i].state || "").toLowerCase()
            if (s === "running" || s.indexOf("up ") === 0)
                ++n
        }
        return n
    }

    function stateColor(s) {
        const t = String(s || "").toLowerCase()
        if (t === "running" || t.indexOf("up ") === 0) return Theme.green
        if (t === "paused") return Theme.yellow
        if (t === "exited" || t === "created" || t === "dead") return Theme.dim
        return Theme.muted
    }

    Column {
        id: body
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 8

        //  ── Header ────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 24

            Glyph {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: 13
                colorVal: Theme.accent
                glyph: Icons.cubes
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "Containers"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 104
                anchors.verticalCenter: parent.verticalCenter
                text: Podman.available
                    ? contCard.runningCount + " of " + Podman.containers.length + " running"
                    : "podman not found"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
            }

            Rectangle {
                id: refreshBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 22
                radius: 6
                color: refreshArea.containsMouse
                    ? Theme.withAlpha(Theme.accent, 0.25) : Theme.withAlpha(Theme.ink, 0.08)

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Glyph {
                    anchors.centerIn: parent
                    size: 12
                    colorVal: Theme.ink
                    glyph: Icons.refresh
                }
                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Podman.refresh()
                }
            }
        }

        //  ── Podman missing → honest hint ──────────────────────────
        Rectangle {
            width: parent.width
            height: 54
            radius: 10
            color: Theme.withAlpha(Theme.yellow, 0.10)
            visible: !Podman.available

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                spacing: 8

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 13
                    colorVal: Theme.yellow
                    glyph: Icons.warning
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: contCard.prefWidth - 60
                    text: "Podman is not installed. Install it (Arch: paru -S podman) to manage containers from the notch."
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }
        }

        //  ── Container rows ────────────────────────────────────────
        Repeater {
            model: Podman.containers

            delegate: Rectangle {
                id: contRow
                required property var modelData
                required property int index

                readonly property bool isOpen: contCard.expandedIndex === index
                readonly property bool isRunning:
                    String(modelData.state || "").toLowerCase() === "running"
                    || String(modelData.state || "").toLowerCase().indexOf("up ") === 0

                width: parent ? parent.width : 0
                height: 40 + (isOpen ? 96 : 0)
                radius: 10
                clip: true
                color: rowArea.containsMouse && !isOpen
                    ? Theme.withAlpha(Theme.ink, 0.09) : Theme.withAlpha(Theme.ink, 0.06)

                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Column {
                    x: 10
                    y: 6
                    width: parent.width - 20
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9; height: 9; radius: 4.5
                            color: contCard.stateColor(contRow.modelData.state)
                        }

                        Column {
                            width: parent.width - 20 - actBtn.width
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: contRow.modelData.names
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: contRow.modelData.image
                                color: Theme.dim
                                font.family: Theme.uiFont
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: actBtn
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 5
                            color: chevArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.14) : "transparent"

                            Glyph {
                                anchors.centerIn: parent
                                size: 10
                                colorVal: Theme.muted
                                glyph: contRow.isOpen ? Icons.chevronDown : Icons.chevronRight
                            }
                            MouseArea {
                                id: chevArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: contCard.expandedIndex =
                                    (contRow.isOpen ? -1 : contRow.index)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: contRow.modelData.status
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    //  ── Inline actions (expanded) ─────────────────
                    Row {
                        width: parent.width
                        height: 26
                        spacing: 6
                        visible: contRow.isOpen

                        Rectangle {
                            width: 66; height: 24
                            radius: 6
                            color: startArea.containsMouse ? Theme.withAlpha(Theme.green, 0.3) : Theme.withAlpha(Theme.ink, 0.1)
                            Text {
                                anchors.centerIn: parent
                                text: contRow.isRunning ? "Restart" : "Start"
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: startArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: contRow.isRunning
                                    ? Podman.restart(contRow.modelData.id)
                                    : Podman.start(contRow.modelData.id)
                            }
                        }

                        Rectangle {
                            width: 56; height: 24
                            radius: 6
                            visible: contRow.isRunning
                            color: stopArea.containsMouse ? Theme.withAlpha(Theme.red, 0.3) : Theme.withAlpha(Theme.ink, 0.1)
                            Text {
                                anchors.centerIn: parent
                                text: "Stop"
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: stopArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Podman.stop(contRow.modelData.id)
                            }
                        }

                        Rectangle {
                            width: 56; height: 24
                            radius: 6
                            color: logsArea.containsMouse ? Theme.withAlpha(Theme.accent, 0.3) : Theme.withAlpha(Theme.ink, 0.1)
                            Text {
                                anchors.centerIn: parent
                                text: "Logs"
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: logsArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Podman.fetchLogs(contRow.modelData.id)
                            }
                        }
                    }

                    //  ── Logs box (expanded) ───────────────────────
                    Rectangle {
                        width: parent.width
                        height: 46
                        radius: 6
                        color: "#0b0b0d"
                        visible: contRow.isOpen

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 6
                            contentWidth: width
                            contentHeight: logText.implicitHeight
                            clip: true

                            Text {
                                id: logText
                                width: parent.width
                                text: Podman.logsFor === contRow.modelData.id
                                    ? (Podman.logs.length > 0 ? Podman.logs : "no logs")
                                    : "tap Logs to fetch the last 80 lines"
                                visible: contRow.isOpen
                                color: Podman.logsFor === contRow.modelData.id
                                    && Podman.logs.length > 0 ? "#9ad1a2" : Theme.dim
                                font.family: "monospace"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    //  Click anywhere on the (non-expanded) row toggles it;
                    //  when expanded, the inner buttons handle themselves.
                    onClicked: {
                        if (!contRow.isOpen)
                            contCard.expandedIndex = contRow.index
                    }
                    //  Don't steal hover from inner buttons when open.
                    enabled: !contRow.isOpen
                }
            }
        }

        //  ── Empty state ───────────────────────────────────────────
        Text {
            width: parent.width
            visible: Podman.available && Podman.containers.length === 0
            text: Podman.busy ? "reading containers…" : "no containers — podman ps -a is empty"
            color: Theme.dim
            font.family: Theme.uiFont
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
