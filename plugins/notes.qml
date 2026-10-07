import QtQuick
import "../core"
import "../services"

//  Notes — a HyprNotch plugin: one sticky note persisted to the
//  user config under "plugin.notes.text". Demonstrates the Config
//  API from a plugin (read via Config.get, debounced write via
//  Config.set).

Item {
    id: root

    //  ── plugin contract ───────────────────────────────────────────
    readonly property string name: "Notes"
    readonly property string icon: "\uF249"
    readonly property bool enabled: true
    property Component compact: compactComp
    property Component view: viewComp

    //  ── state ─────────────────────────────────────────────────────
    property string text: Config.get("plugin.notes.text", "")

    function save() {
        Config.set("plugin.notes.text", root.text)
    }

    //  ── peek chip ─────────────────────────────────────────────────
    Component {
        id: compactComp

        Item {
            implicitHeight: 20

            Row {
                anchors.centerIn: parent
                spacing: 5

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 10
                    colorVal: Theme.yellow
                    glyph: root.icon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.text.length > 0 ? root.text.split("\n")[0] : "empty note"
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: 90
                }
            }
        }
    }

    //  ── island view ───────────────────────────────────────────────
    Component {
        id: viewComp

        Item {
            property int prefWidth: 320
            implicitHeight: 150

            Column {
                anchors.fill: parent
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 6

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 11
                        colorVal: Theme.yellow
                        glyph: root.icon
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Sticky Note"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: saveTimer.running ? "saving…" : "saved"
                        color: Theme.dim
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 104
                    radius: 10
                    color: Theme.withAlpha(Theme.yellow, 0.10)
                    border.width: noteEdit.activeFocus ? 1 : 0
                    border.color: Theme.yellow

                    TextEdit {
                        id: noteEdit
                        anchors.fill: parent
                        anchors.margins: 8
                        text: root.text
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                        wrapMode: TextEdit.Wrap
                        clip: true
                        onTextChanged: {
                            root.text = text
                            saveTimer.restart()
                        }

                        Text {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: noteEdit.text.length === 0
                            text: "Write something…"
                            color: Theme.dim
                            font.family: noteEdit.font.family
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 700
        onTriggered: root.save()
    }
}
