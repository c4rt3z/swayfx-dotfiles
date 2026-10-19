import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../singletons"

// Календарь и таймер — клик по часам в waybar (или Mod+C).
//
// Месяц и таймер живут вместе: часы в баре отвечают за время, погода — за
// погоду (своя панель). Отсчёт таймера хранится в синглтоне Countdown, поэтому
// панель можно закрыть — по нулю придёт уведомление.
ColumnLayout {
    id: page

    // Месяцы и дни недели таблицей, а не локалью процесса: язык интерфейса
    // задаётся в настройках и может не совпадать с локалью.
    readonly property var monthNames: ({
        ru: ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
             "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"],
        en: ["January", "February", "March", "April", "May", "June",
             "July", "August", "September", "October", "November", "December"],
        uk: ["Січень", "Лютий", "Березень", "Квітень", "Травень", "Червень",
             "Липень", "Серпень", "Вересень", "Жовтень", "Листопад", "Грудень"],
        de: ["Januar", "Februar", "März", "April", "Mai", "Juni",
             "Juli", "August", "September", "Oktober", "November", "Dezember"]
    })
    // неделя с понедельника
    readonly property var dayNames: ({
        ru: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"],
        en: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        uk: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"],
        de: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    })

    property date shown: new Date()
    property var days: []
    // ручной ввод таймера: «25» — минуты, «25:30» — минуты и секунды, «1:05:00» — часы
    property string manual: ""

    readonly property var presets: [1, 3, 5, 10, 25, 45]

    spacing: 12

    function names(table) {
        return table[Lang.code] || table.en;
    }

    function monthTitle() {
        return names(page.monthNames)[page.shown.getMonth()] + " " + page.shown.getFullYear();
    }

    function buildDays() {
        const first = new Date(page.shown.getFullYear(), page.shown.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;       // Пн — первый столбец
        const today = new Date();
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === first.getMonth(),
                today: d.getFullYear() === today.getFullYear()
                       && d.getMonth() === today.getMonth()
                       && d.getDate() === today.getDate(),
                weekend: d.getDay() === 0 || d.getDay() === 6
            });
        }
        return out;
    }

    function shiftMonth(step) {
        page.shown = new Date(page.shown.getFullYear(), page.shown.getMonth() + step, 1);
    }

    function today() {
        page.shown = new Date();
        page.days = page.buildDays();
    }

    // «25» → 25 минут, «25:30» → 25 мин 30 с, «1:05:00» → час пять минут
    function parseTime(text) {
        const t = (text || "").trim().replace(",", ":");
        if (t === "")
            return 0;
        const parts = t.split(":").map(p => Number(p.trim()));
        if (parts.length === 0 || parts.length > 3)
            return -1;
        for (let i = 0; i < parts.length; i++)
            if (!isFinite(parts[i]) || parts[i] < 0)
                return -1;
        if (parts.length === 1)
            return Math.round(parts[0] * 60);
        if (parts.length === 2)
            return Math.round(parts[0] * 60 + parts[1]);
        return Math.round(parts[0] * 3600 + parts[1] * 60 + parts[2]);
    }

    function startManual() {
        const sec = page.parseTime(page.manual);
        if (sec <= 0)
            return;
        Countdown.start(sec, Lang.t("Таймер"), Lang.t("Время вышло"));
        page.manual = "";
    }

    onShownChanged: page.days = page.buildDays()
    Component.onCompleted: page.days = page.buildDays()

    // ── календарь ──────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            Layout.fillWidth: true
            text: page.monthTitle()
            color: Colors.text
            font.pixelSize: 14
            font.bold: true
        }

        Repeater {
            model: [
                { icon: "\uF0D9", step: -1 },
                { icon: "\uF0DA", step: 1 }
            ]

            delegate: Item {
                required property var modelData
                implicitWidth: 24
                implicitHeight: 24

                Label {
                    anchors.centerIn: parent
                    text: modelData.icon
                    color: hover.containsMouse ? Colors.text : Colors.dim
                    font.pixelSize: 12
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.shiftMonth(modelData.step)
                }
            }
        }

        Item {
            implicitWidth: todayLabel.implicitWidth + 12
            implicitHeight: 22

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: todayArea.containsMouse ? Colors.selected : "transparent"
            }
            Label {
                id: todayLabel
                anchors.centerIn: parent
                text: Lang.t("Сегодня")
                color: todayArea.containsMouse ? Colors.text : Colors.dim
                font.pixelSize: 11
            }
            MouseArea {
                id: todayArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: page.today()
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        columnSpacing: 2
        rowSpacing: 2

        Repeater {
            model: page.names(page.dayNames)

            delegate: Label {
                required property string modelData
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Colors.dim
                font.pixelSize: 11
            }
        }

        Repeater {
            model: page.days

            delegate: Item {
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 30

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 6
                    color: modelData.today ? Colors.accent
                         : (modelData.inMonth ? (cellHover.containsMouse ? Colors.selected : "transparent")
                                              : "transparent")
                }

                Label {
                    anchors.centerIn: parent
                    text: modelData.day
                    color: modelData.today ? Colors.onAccent
                         : (modelData.inMonth ? (modelData.weekend ? Colors.muted : Colors.text)
                                              : Qt.alpha(Colors.text, 0.25))
                    font.pixelSize: 12
                    font.bold: modelData.today
                }

                MouseArea {
                    id: cellHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }
    }

    // ── таймер ─────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colors.divider
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Label {
            Layout.fillWidth: true
            text: Lang.t("Таймер")
            color: Colors.text
            font.pixelSize: 13
            font.bold: true
        }

        Label {
            text: Countdown.clock
            color: Countdown.active ? (Countdown.paused ? Colors.muted : Colors.accent) : Colors.dim
            font.pixelSize: 16
            font.bold: true
        }
    }

    // полоса отсчёта
    Rectangle {
        Layout.fillWidth: true
        visible: Countdown.active
        implicitHeight: 3
        radius: 1.5
        color: Colors.track

        Rectangle {
            height: parent.height
            radius: parent.radius
            width: parent.width * Countdown.progress
            color: Colors.accent
        }
    }

    // ручной ввод: «25», «25:30» или «1:05:00»
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: !Countdown.active

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: 6
            color: Colors.base
            border.width: 1
            border.color: manualInput.activeFocus ? Colors.accent : Colors.border

            Label {
                anchors.fill: parent
                anchors.leftMargin: 9
                verticalAlignment: Text.AlignVCenter
                visible: manualInput.text === ""
                text: Lang.t("своё время: 25 или 1:30")
                color: Colors.dim
                font.pixelSize: 11
            }

            TextInput {
                id: manualInput
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: Fonts.panelFamily
                font.pixelSize: 12
                selectionColor: Colors.accent
                selectedTextColor: Colors.onAccent
                selectByMouse: true
                text: page.manual
                onTextChanged: page.manual = text
                onAccepted: page.startManual()

                cursorDelegate: Rectangle {
                    width: 2
                    color: Colors.accent
                }
            }
        }

        Item {
            implicitWidth: 64
            implicitHeight: 30

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: startHover.containsMouse ? Colors.selected : "transparent"
                border.width: 1
                border.color: (page.parseTime(page.manual) > 0) ? Colors.accent : Colors.divider
            }
            Label {
                anchors.centerIn: parent
                text: Lang.t("Старт")
                color: (page.parseTime(page.manual) > 0)
                       ? (startHover.containsMouse ? Colors.text : Colors.accent)
                       : Colors.dim
                font.pixelSize: 11
            }
            MouseArea {
                id: startHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: page.startManual()
            }
        }
    }

    // пресеты
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: !Countdown.active

        Repeater {
            model: page.presets

            delegate: Item {
                required property int modelData
                Layout.fillWidth: true
                implicitHeight: 30

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: presetArea.containsMouse ? Colors.selected : "transparent"
                    border.width: 1
                    border.color: presetArea.containsMouse ? Colors.accent : Colors.divider
                }
                Label {
                    anchors.centerIn: parent
                    text: modelData + " " + Lang.t("мин")
                    color: presetArea.containsMouse ? Colors.text : Colors.muted
                    font.pixelSize: 11
                }
                MouseArea {
                    id: presetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Countdown.start(modelData * 60, Lang.t("Таймер"),
                                               Lang.t("Время вышло"))
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: Countdown.active

        Repeater {
            model: [
                { icon: "\uF04B", label: Lang.t("Продолжить"), act: "resume" },
                { icon: "\uF04C", label: Lang.t("Пауза"), act: "pause" },
                { icon: "\uF00D", label: Lang.t("Сбросить"), act: "stop" }
            ]

            delegate: Item {
                required property var modelData
                visible: modelData.act === "stop"
                         || (modelData.act === "pause" && !Countdown.paused)
                         || (modelData.act === "resume" && Countdown.paused)
                Layout.fillWidth: true
                implicitHeight: 30

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: ctrlArea.containsMouse ? Colors.selected : "transparent"
                    border.width: 1
                    border.color: ctrlArea.containsMouse ? Colors.accent : Colors.divider
                }
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Label {
                        text: modelData.icon
                        color: Colors.muted
                        font.pixelSize: 11
                    }
                    Label {
                        text: modelData.label
                        color: ctrlArea.containsMouse ? Colors.text : Colors.muted
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: ctrlArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (modelData.act === "pause") Countdown.pause();
                        else if (modelData.act === "resume") Countdown.resume();
                        else Countdown.stop();
                    }
                }
            }
        }
    }
}
