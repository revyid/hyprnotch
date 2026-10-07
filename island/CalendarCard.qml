import QtQuick
import "../core"
import "../services"

//  Calendar — hosted INSIDE the island body. Opens ONLY from the
//  clock/date click on the pill — never from the main pill body.
//  Month grid, today highlighted, first day of week configurable,
//  optional week numbers. The island silhouette is the surface; this
//  card only lays content out and reports its height.

Item {
    id: calWindow

    readonly property var cfg: Config.data.calendar
    readonly property int firstDayOffset: cfg.firstDayMonday ? 1 : 0

    //  Island contract
    property int prefWidth: 320
    implicitHeight: contentCol.implicitHeight + 24

    property date viewDate: new Date()

    //  Fresh month every time the island hosts the calendar
    property bool shown: UiState.activePopup === "calendar"
    onShownChanged: if (shown) viewDate = new Date()

    function prevMonth() {
        viewDate = new Date(viewDate.getFullYear(), viewDate.getMonth() - 1, 1)
    }
    function nextMonth() {
        viewDate = new Date(viewDate.getFullYear(), viewDate.getMonth() + 1, 1)
    }

    function monthName() {
        return Qt.formatDate(viewDate, "MMMM yyyy")
    }

    function dayNames() {
        //  Build 7 labels starting from the configured first day
        const names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        const out = []
        for (let i = 0; i < 7; ++i)
            out.push(names[(i + firstDayOffset) % 7])
        return out
    }

    function gridCells() {
        const y = viewDate.getFullYear(), m = viewDate.getMonth()
        const daysInMonth = new Date(y, m + 1, 0).getDate()
        const startDow = new Date(y, m, 1).getDay() //  0 = Sunday
        const lead = (startDow - firstDayOffset + 7) % 7
        const cells = []
        for (let i = 0; i < lead; ++i)
            cells.push({ day: 0 })
        for (let d = 1; d <= daysInMonth; ++d)
            cells.push({ day: d })
        const today = new Date()
        for (const c of cells)
            c.today = (c.day === today.getDate() && m === today.getMonth() && y === today.getFullYear())
        return cells
    }

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const dayNum = (t.getUTCDay() + 6) % 7
        t.setUTCDate(t.getUTCDate() - dayNum + 3)
        const firstThursday = new Date(Date.UTC(t.getUTCFullYear(), 0, 4))
        const fDayNum = (firstThursday.getUTCDay() + 6) % 7
        firstThursday.setUTCDate(firstThursday.getUTCDate() - fDayNum + 3)
        return 1 + Math.round((t - firstThursday) / 604800000)
    }

    //  One week number per grid row (the week of that row's first day).
    function rowWeeks() {
        if (!cfg.showWeekNumbers)
            return []
        const y = viewDate.getFullYear(), m = viewDate.getMonth()
        const daysInMonth = new Date(y, m + 1, 0).getDate()
        const startDow = new Date(y, m, 1).getDay()
        const lead = (startDow - firstDayOffset + 7) % 7
        const rows = Math.ceil((lead + daysInMonth) / 7)
        const out = []
        for (let r = 0; r < rows; ++r)
            out.push(isoWeek(new Date(y, m, 1 + r * 7 - lead)))
        return out
    }

    Column {
        id: contentCol
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 8

        //  ── Header ────────────────────────────────────────────────
        Row {
            width: parent.width
            height: 24

            Rectangle {
                width: 24; height: 24; radius: 8
                color: pvArea.containsMouse ? Theme.surfaceHi : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                Glyph { anchors.centerIn: parent; size: 11; colorVal: Theme.muted; glyph: Icons.chevronLeft }
                MouseArea {
                    id: pvArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: calWindow.prevMonth()
                }
            }

            Text {
                width: parent.width - 48
                anchors.verticalCenter: parent.verticalCenter
                text: calWindow.monthName()
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: 24; height: 24; radius: 8
                color: nxArea.containsMouse ? Theme.surfaceHi : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                Glyph { anchors.centerIn: parent; size: 11; colorVal: Theme.muted; glyph: Icons.chevronRight }
                MouseArea {
                    id: nxArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: calWindow.nextMonth()
                }
            }
        }

        //  ── Day names ─────────────────────────────────────────────
        Row {
            width: parent.width

            Item {
                width: calWindow.cfg.showWeekNumbers ? 20 : 0
                height: 1
                visible: calWindow.cfg.showWeekNumbers
            }

            Grid {
                width: parent.width - (calWindow.cfg.showWeekNumbers ? 20 : 0)
                columns: 7

                Repeater {
                    model: calWindow.dayNames()
                    Text {
                        required property string modelData
                        width: parent.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                    }
                }
            }
        }

        //  ── Grid ──────────────────────────────────────────────────
        Row {
            width: parent.width

            //  Week numbers (optional, config-driven)
            Column {
                visible: calWindow.cfg.showWeekNumbers
                width: visible ? 20 : 0
                spacing: 2

                Repeater {
                    model: calWindow.rowWeeks()

                    Item {
                        required property var modelData
                        width: 20
                        height: 28

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                        }
                    }
                }
            }

            Grid {
                width: parent.width - (calWindow.cfg.showWeekNumbers ? 20 : 0)
                columns: 7
                spacing: 2

                Repeater {
                    model: calWindow.gridCells()

                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 12) / 7
                        height: 28
                        radius: 8
                        color: modelData.today ? Theme.accent : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.day > 0 ? parent.modelData.day : ""
                            color: parent.modelData.today ? "#ffffff" : Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            font.weight: parent.modelData.today ? Font.Bold : Font.Medium
                        }
                    }
                }
            }
        }
    }
}
