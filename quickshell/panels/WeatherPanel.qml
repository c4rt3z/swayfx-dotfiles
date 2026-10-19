import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Погода — клик по модулю погоды в баре.
//
// Данные читаем из кэша ~/.cache/quickshell/weather.json: его обновляет
// scripts/weather.py (тот же скрипт кормит виджет в баре и настройки). Своего
// состояния панель не держит, кнопка «Обновить» просто зовёт скрипт.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property var dayNames: ({
        ru: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"],
        en: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        uk: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"],
        de: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    })

    property var w: ({})

    spacing: 12

    function dayName(iso) {
        if (!iso || iso.length < 10)
            return "";
        const d = new Date(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1,
                           Number(iso.slice(8, 10)));
        return (page.dayNames[Lang.code] || page.dayNames.en)[(d.getDay() + 6) % 7];
    }

    FileView {
        id: weatherView
        path: page.home + "/.cache/quickshell/weather.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                page.w = JSON.parse(raw || "{}").data || {};
            } catch (e) {
                page.w = ({});
            }
        }
    }

    Process {
        id: refreshProcess
        command: ["python3", page.home + "/.config/quickshell/scripts/weather.py", "refresh"]
        onExited: weatherView.reload()
    }

    // ── сейчас ─────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: nowRow.implicitHeight + 20
        radius: 8
        color: Colors.selected

        RowLayout {
            id: nowRow
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 14

            Label {
                text: page.w.icon || "\ue302"
                color: Colors.accent
                font.pixelSize: 38
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: page.w.ok
                          ? (page.w.temp + (page.w.unit || "°C"))
                          : "—"
                    color: Colors.text
                    font.pixelSize: 26
                    font.bold: true
                }

                Label {
                    text: page.w.ok ? (page.w.desc || "") : Lang.t("Погода недоступна")
                    color: Colors.text
                    font.pixelSize: 12
                }

                Label {
                    Layout.fillWidth: true
                    text: (page.w.city || "")
                          + (page.w.country ? ", " + page.w.country : "")
                          + (page.w.ok ? " · " + Lang.t("ощущается") + " " +
                             page.w.feels + (page.w.unit || "°C") : "")
                    color: Colors.dim
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Item {
                implicitWidth: 26
                implicitHeight: 26

                Label {
                    anchors.centerIn: parent
                    text: "\uF021"
                    color: refreshArea.containsMouse ? Colors.text : Colors.dim
                    font.pixelSize: 14
                }
                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: refreshProcess.running = true
                }
            }
        }
    }

    // ── подробности ────────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        rowSpacing: 6
        visible: page.w.ok === true

        Repeater {
            model: [
                { icon: "\uF043", label: Lang.t("Влажность"), value: (page.w.humidity ?? 0) + "%" },
                { icon: "\uF72E", label: Lang.t("Ветер"), value: (page.w.wind ?? 0) + " " + (page.w.wind_unit || "") },
                { icon: "\uF185", label: Lang.t("Восход"), value: page.w.sunrise || "—" },
                { icon: "\uF186", label: Lang.t("Закат"), value: page.w.sunset || "—" }
            ]

            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    spacing: 5
                    Label {
                        text: modelData.icon
                        color: Colors.muted
                        font.pixelSize: 10
                    }
                    Label {
                        text: modelData.label
                        color: Colors.dim
                        font.pixelSize: 10
                    }
                }
                Label {
                    text: modelData.value
                    color: Colors.text
                    font.pixelSize: 12
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colors.divider
        visible: page.w.ok === true
    }

    // ── прогноз ────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("На 5 дней")
        color: Colors.muted
        font.pixelSize: 11
        font.bold: true
        visible: page.w.ok === true && (page.w.days || []).length > 0
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.w.days || []

            delegate: Item {
                id: dayRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 32

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: modelData.today ? Colors.selected
                         : (dayHover.containsMouse ? Colors.selected : "transparent")
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    Label {
                        Layout.preferredWidth: 58
                        text: modelData.today ? Lang.t("Сегодня") : page.dayName(modelData.date)
                        color: modelData.today ? Colors.accent : Colors.text
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.preferredWidth: 42
                        text: modelData.date.slice(8, 10) + "." + modelData.date.slice(5, 7)
                        color: Colors.dim
                        font.pixelSize: 10
                    }

                    Label {
                        Layout.preferredWidth: 30
                        text: modelData.icon
                        color: Colors.accent
                        font.pixelSize: 17
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.desc
                        color: Colors.muted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Label {
                        text: modelData.min + "° … " + modelData.max + "°"
                        color: Colors.text
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: dayHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }
    }
}
