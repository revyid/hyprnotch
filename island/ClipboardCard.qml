import QtQuick
import QtQuick.Controls
import Quickshell
import "../core"
import "../services"

//  Clipboard history — the Win+V panel (r24).
//
//  Search box on top, history rows below: click a row to put that
//  entry back on the clipboard, the trash glyph deletes it, the broom
//  in the header wipes everything. Backed by cliphist (see
//  services/Clipboard.qml); when the tools are missing the card shows
//  an honest install hint instead of a fake empty list.

Item {
    id: clipCard

    //  Island contract
    property int prefWidth: 460
    implicitHeight: Math.max(150, body.height + 24)

    property bool shown: UiState.activePopup === "clipboard"
    onShownChanged: {
        Clipboard.panelOpen = shown
        if (shown) {
            Clipboard.query = ""
            Clipboard.refresh()
            searchInput.forceActiveFocus()
        }
    }

    readonly property var rows: {
        const q = Clipboard.query.toLowerCase()
        const all = Clipboard.entries
        if (q.length === 0)
            return all
        const out = []
        for (let i = 0; i < all.length; ++i)
            if (all[i].preview.toLowerCase().indexOf(q) >= 0)
                out.push(all[i])
        return out
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
                glyph: "\uF0EA"   // clipboard
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "Clipboard"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 96
                anchors.verticalCenter: parent.verticalCenter
                text: Clipboard.available
                    ? Clipboard.entries.length + " items stored"
                    : "history unavailable"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
            }

            Rectangle {
                id: wipeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 22
                radius: 6
                color: wipeArea.containsMouse
                    ? Theme.withAlpha(Theme.red, 0.3) : Theme.withAlpha(Theme.ink, 0.08)

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Glyph {
                    anchors.centerIn: parent
                    size: 12
                    colorVal: Theme.ink
                    glyph: "\uF1F8"   // trash
                }
                MouseArea {
                    id: wipeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.wipe()
                }
            }
        }

        //  ── Search ────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 32
            radius: Theme.radiusSmall
            color: Theme.withAlpha(Theme.ink, 0.08)
            border.width: searchInput.activeFocus ? 1 : 0
            border.color: Theme.accent

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                size: 11
                colorVal: Theme.muted
                glyph: Icons.search
            }
            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                text: Clipboard.query
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 12
                clip: true

                onTextChanged: Clipboard.query = text
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape) {
                        UiState.closeAll()
                        event.accepted = true
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: "Search the history…"
                    color: Theme.dim
                    font.family: searchInput.font.family
                    font.pixelSize: 12
                    verticalAlignment: TextInput.AlignVCenter
                }
            }
        }

        //  ── Missing tools → honest hint ───────────────────────────
        Rectangle {
            width: parent.width
            height: 54
            radius: 10
            color: Theme.withAlpha(Theme.yellow, 0.10)
            visible: !Clipboard.available

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
                    width: clipCard.prefWidth - 60
                    text: Clipboard.missingTool.length > 0
                        ? "Clipboard history needs '" + Clipboard.missingTool
                          + "'. Install it (Arch: paru -S " + Clipboard.missingTool
                          + ") and restart HyprNotch."
                        : "Clipboard history is switched off — enable it in the quick toggles."
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }
        }

        //  ── History rows ──────────────────────────────────────────
        ListView {
            id: list
            width: parent.width
            height: Math.min(320, Math.max(2, clipCard.rows.length) * 38 + 8)
            clip: true
            visible: Clipboard.available
            boundsBehavior: Flickable.StopAtBounds
            model: clipCard.rows
            reuseItems: true
            spacing: 3
            ScrollIndicator.vertical: ScrollIndicator {}

            Text {
                anchors.centerIn: parent
                visible: Clipboard.available && clipCard.rows.length === 0
                text: Clipboard.busy ? "reading history…" : "nothing copied yet — copy something"
                color: Theme.dim
                font.family: Theme.uiFont
                font.pixelSize: 11
            }

            delegate: Rectangle {
                id: clipRow
                required property var modelData
                required property int index

                width: list.width
                height: 35
                radius: 8
                color: clipArea.containsMouse
                    ? Theme.withAlpha(Theme.accent, 0.16) : Theme.withAlpha(Theme.ink, 0.06)
                scale: clipArea.pressed ? 0.98 : 1

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    width: 16
                    height: 16

                    Glyph {
                        anchors.centerIn: parent
                        size: 11
                        colorVal: clipRow.modelData.binary ? Theme.accent : Theme.muted
                        glyph: clipRow.modelData.binary ? Icons.image : "\uF0EA"
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: delBtn.left
                    anchors.rightMargin: 6
                    text: clipRow.modelData.preview
                    color: Theme.ink
                    font.family: clipRow.modelData.binary ? Theme.uiFont : "monospace"
                    font.pixelSize: clipRow.modelData.binary ? 10 : 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Rectangle {
                    id: delBtn
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    width: 20
                    height: 20
                    radius: 5
                    color: delArea.containsMouse ? Theme.withAlpha(Theme.red, 0.35) : "transparent"

                    Glyph {
                        anchors.centerIn: parent
                        size: 9
                        colorVal: delArea.containsMouse ? Theme.red : Theme.dim
                        glyph: Icons.close
                    }
                    MouseArea {
                        id: delArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Clipboard.remove(clipRow.modelData.idx)
                    }
                }

                MouseArea {
                    id: clipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.copy(clipRow.modelData.idx)
                }
            }
        }
    }
}
