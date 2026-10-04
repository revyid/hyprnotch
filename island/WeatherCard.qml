import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

//  Weather menu — the full picture, macOS Weather style.
//
//  Big current conditions, hourly strip, 5-day outlook, and a city
//  switcher (geocoding search) that persists via the Weather service.
//  The pill's tiny weather row opens this.

Item {
    id: weatherCard

    readonly property int pad: 14

    //  Island contract
    property int prefWidth: 420
    implicitHeight: inner.implicitHeight + pad * 2

    property bool searching: false

    function condText(code) {
        return Weather.describe(code)
    }

    Column {
        id: inner
        x: weatherCard.pad
        y: weatherCard.pad
        width: parent.width - weatherCard.pad * 2
        spacing: 12

        //  ── Header with city switcher ─────────────────────────────
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: Weather.place.length > 0 ? Weather.place : "Weather"
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.maximumWidth: parent.width - 90
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                width: 24; height: 24; radius: 12
                color: searchArea.containsMouse ? Theme.surfaceHi : "transparent"
                scale: searchArea.pressed ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                Glyph {
                    anchors.centerIn: parent
                    size: 11
                    colorVal: Theme.ink
                    glyph: Icons.search
                }
                MouseArea {
                    id: searchArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        searching = !searching
                        if (searching)
                            searchInput.forceActiveFocus()
                    }
                }
            }
            Rectangle {
                width: 24; height: 24; radius: 12
                color: refreshArea.containsMouse ? Theme.surfaceHi : "transparent"
                scale: refreshArea.pressed ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale { NumberAnimation { duration: Theme.animPress; easing.type: Easing.OutCubic } }

                Glyph {
                    anchors.centerIn: parent
                    size: 11
                    colorVal: Weather.loading ? Theme.accent : Theme.ink
                    glyph: Icons.refresh
                }
                RotationAnimation on rotation {
                    running: Weather.loading
                    from: 0; to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Weather.refresh()
                }
            }
        }

        //  ── Search box + results ──────────────────────────────────
        Column {
            width: parent.width
            spacing: 6
            visible: searching

            Rectangle {
                width: parent.width
                height: 30
                radius: 15
                color: Theme.withAlpha(Theme.ink, 0.08)
                border.width: searchInput.activeFocus ? 1 : 0
                border.color: Theme.accent

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 11
                        colorVal: Theme.muted
                        glyph: Icons.search
                    }
                    TextInput {
                        id: searchInput
                        width: parent.width - 40
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                        clip: true
                        enabled: !Weather.searching
                        onAccepted: Weather.search(text)

                        Text {
                            anchors.fill: parent
                            visible: searchInput.text.length === 0
                            text: "Search city…"
                            color: Theme.dim
                            font.family: searchInput.font.family
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Repeater {
                model: Weather.matches.slice(0, 5)

                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 30
                    radius: 8
                    color: matchArea.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.ink, 0.05)

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20
                        text: modelData.region.length > 0
                            ? modelData.name + " · " + modelData.region : modelData.name
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: matchArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Weather.setPlace(modelData.name, modelData.region,
                                             modelData.latitude, modelData.longitude)
                            searching = false
                        }
                    }
                }
            }

            Text {
                visible: Weather.searching
                text: "Searching…"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 9
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        //  ── Current conditions ────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 96
            radius: 14
            visible: Weather.ready
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.blue, 0.28) }
                GradientStop { position: 1.0; color: Theme.withAlpha(Theme.blue, 0.06) }
            }

            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 14

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 44
                    colorVal: Theme.yellow
                    glyph: Weather.current
                        ? Weather.icon(Weather.current.code, Weather.current.isDay) : ""
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    width: parent.width - 80

                    Text {
                        text: Weather.current ? Weather.current.temp + "°" : "—"
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 34
                        font.weight: Font.Light
                    }
                    Text {
                        text: Weather.current ? condText(Weather.current.code) : ""
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        text: Weather.daily.length > 0
                            ? "H " + Weather.daily[0].max + "°  ·  L " + Weather.daily[0].min + "°  ·  Feels " +
                              (Weather.current ? Weather.current.feels + "°" : "")
                            : ""
                        color: Theme.withAlpha(Theme.ink, 0.7)
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
        }

        //  ── Hourly strip ──────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 6
            visible: Weather.hourly.length > 0

            Repeater {
                model: Weather.hourly.slice(0, 7)

                delegate: Rectangle {
                    required property var modelData
                    width: (parent.width - 36) / 7
                    height: 78
                    radius: 10
                    color: index === 0 ? Theme.withAlpha(Theme.accent, 0.18) : Theme.withAlpha(Theme.ink, 0.06)

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Column {
                        anchors.fill: parent
                        anchors.topMargin: 8
                        spacing: 5

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.hour
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                        Glyph {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: 16
                            colorVal: modelData.isDay ? Theme.yellow : Theme.teal
                            glyph: Weather.icon(modelData.code, modelData.isDay)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.temp + "°"
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }

        //  ── 5-day outlook ─────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 4
            visible: Weather.daily.length > 0

            Repeater {
                model: Weather.daily.slice(0, 5)

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: dayArea.containsMouse ? Theme.withAlpha(Theme.ink, 0.07) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: index === 0 ? "Today" : modelData.date
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: index === 0 ? Font.DemiBold : Font.Medium
                    }

                    Glyph {
                        anchors.left: parent.left
                        anchors.leftMargin: parent.width * 0.42
                        anchors.verticalCenter: parent.verticalCenter
                        size: 14
                        colorVal: Theme.yellow
                        glyph: Weather.icon(modelData.code, true)
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: modelData.max + "°"
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                        Text {
                            text: modelData.min + "°"
                            color: Theme.dim
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: dayArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }

        //  ── Extras: humidity / wind ───────────────────────────────
        Row {
            width: parent.width
            spacing: 8
            visible: Weather.ready && Weather.current

            StatChip {
                glyph: Icons.drop
                text: Weather.current ? Weather.current.humidity + "% humidity" : ""
                tint: Theme.teal
            }
            StatChip {
                glyph: Icons.wind
                text: Weather.current ? Weather.current.wind + " km/h wind" : ""
                tint: Theme.blue
            }
            StatChip {
                glyph: Icons.location
                text: Weather.region
                tint: Theme.muted
            }
        }
    }
}
