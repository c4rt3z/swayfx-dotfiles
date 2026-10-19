import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Погода»: источник, город, ключ OpenWeather и единицы.
//
// Своего состояния нет: всё живёт в ~/.config/quickshell/weather.json, его
// читает scripts/weather.py — тот же скрипт кормит виджет в баре и строку в
// панели календаря. Сохранили — скрипт сбрасывает кэш, и бар подхватит новое
// на следующем обновлении (модуль обновляется раз в 15 минут, кнопка
// «Обновить» в календаре — сразу).
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/weather.py"

    property var weather: ({})
    property var settings: ({})
    property var found: []
    property string cityEdit: ""
    property string keyEdit: ""
    property string query: ""
    property bool searching: false

    spacing: 14

    function reload() {
        stateProcess.running = true;
    }

    function apply() {
        const args = ["python3", script, "set",
                      "city=" + (page.cityEdit.trim() || page.settings.city || ""),
                      "api_key=" + page.keyEdit.trim(),
                      "provider=" + (page.settings.provider || "auto"),
                      "units=" + (page.settings.units || "metric")];
        saveProcess.command = args;
        saveProcess.running = true;
    }

    function setProvider(provider) {
        page.settings = Object.assign({}, page.settings, { provider: provider });
        page.apply();
    }

    function setUnits(units) {
        page.settings = Object.assign({}, page.settings, { units: units });
        page.apply();
    }

    function chooseCity(item) {
        page.cityEdit = item.name;
        page.found = [];
        page.query = "";
        page.apply();
    }

    Component.onCompleted: page.reload()

    Process {
        id: stateProcess
        command: ["python3", page.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text || "{}");
                    page.weather = parsed.data || {};
                    page.settings = parsed.settings || {};
                } catch (e) {
                    page.weather = ({});
                    page.settings = ({});
                }
                page.cityEdit = page.settings.city || page.weather.city || "";
            }
        }
    }

    Process {
        id: saveProcess
        onExited: {
            reloadLater.restart();
        }
    }

    Timer {
        id: reloadLater
        interval: 600
        onTriggered: page.reload()
    }

    Process {
        id: searchProcess
        command: ["python3", page.script, "search", page.query]
        stdout: StdioCollector {
            onStreamFinished: {
                page.searching = false;
                try {
                    page.found = (JSON.parse(this.text || "{}").items) || [];
                } catch (e) {
                    page.found = [];
                }
            }
        }
    }

    // ── как есть сейчас ─────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 54
        radius: 8
        color: Colors.selected
        border.width: 1
        border.color: Colors.divider

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            Label {
                text: page.weather.icon || "\ue302"
                color: Colors.accent
                font.pixelSize: 22
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    text: page.weather.ok
                          ? (page.weather.temp + (page.weather.unit || "°C") + " · " + (page.weather.desc || ""))
                          : Lang.t("Погода недоступна")
                    color: Colors.text
                    font.pixelSize: 13
                    font.bold: true
                }

                Label {
                    text: (page.weather.city || "") +
                          (page.weather.source ? " · " + page.weather.source : "")
                    color: Colors.dim
                    font.pixelSize: 10
                }
            }

            Label {
                text: Lang.t("Обновить")
                color: refreshArea.containsMouse ? Colors.text : Colors.dim
                font.pixelSize: 11

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: {
                        refreshProcess.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: refreshProcess
        command: ["python3", page.script, "refresh"]
        onExited: page.reload()
    }

    // ── источник ────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Источник")
        color: Colors.muted
        font.pixelSize: 11
        font.bold: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { key: "auto", label: Lang.t("Авто") },
                { key: "openweather", label: "OpenWeather" },
                { key: "openmeteo", label: "open-meteo" }
            ]

            delegate: Item {
                id: providerTile

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 32

                readonly property bool active: (page.settings.provider || "auto") === modelData.key

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: providerTile.active ? Colors.accent : "transparent"
                    border.width: 1
                    border.color: providerTile.active ? Colors.accent
                                                : (pickHover.containsMouse ? Colors.accent : Colors.divider)
                }

                Label {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: providerTile.active ? Colors.onAccent
                         : (pickHover.containsMouse ? Colors.text : Colors.muted)
                    font.pixelSize: 11
                }

                MouseArea {
                    id: pickHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.setProvider(modelData.key)
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Без ключа работает open-meteo — ни регистрации, ни ключа не нужно. Ключ OpenWeather включает их данные.")
        color: Colors.dim
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // ── город ───────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Город")
        color: Colors.muted
        font.pixelSize: 11
        font.bold: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 6
            color: Colors.base
            border.width: 1
            border.color: cityInput.activeFocus ? Colors.accent : Colors.border

            TextInput {
                id: cityInput

                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                selectionColor: Colors.accent
                selectedTextColor: Colors.onAccent
                selectByMouse: true
                text: page.cityEdit
                onTextChanged: page.cityEdit = text
                onAccepted: page.apply()

                cursorDelegate: Rectangle {
                    width: 2
                    color: Colors.accent
                }
            }
        }

        Item {
            implicitWidth: 74
            implicitHeight: 32

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: findHover.containsMouse ? Colors.selected : "transparent"
                border.width: 1
                border.color: Colors.divider
            }
            Label {
                anchors.centerIn: parent
                text: Lang.t("Найти")
                color: findHover.containsMouse ? Colors.text : Colors.muted
                font.pixelSize: 11
            }
            MouseArea {
                id: findHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    page.query = page.cityEdit.trim();
                    if (page.query === "")
                        return;
                    page.searching = true;
                    searchProcess.command = ["python3", page.script, "search", page.query];
                    searchProcess.running = true;
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: page.found.length > 0

        Repeater {
            model: page.found

            delegate: Item {
                id: cityRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 28

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: cityHover.containsMouse ? Colors.selected : "transparent"
                }

                Label {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                          + (modelData.admin ? ", " + modelData.admin : "")
                          + (modelData.country ? ", " + modelData.country : "")
                    color: cityHover.containsMouse ? Colors.text : Colors.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: cityHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.chooseCity(cityRow.modelData)
                }
            }
        }
    }

    Label {
        visible: page.searching
        text: Lang.t("ищем…")
        color: Colors.dim
        font.pixelSize: 11
    }

    // ── ключ ────────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Ключ OpenWeather")
        color: Colors.muted
        font.pixelSize: 11
        font.bold: true
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 6
        color: Colors.base
        border.width: 1
        border.color: keyInput.activeFocus ? Colors.accent : Colors.border

        TextInput {
            id: keyInput

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.text
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            selectionColor: Colors.accent
            selectedTextColor: Colors.onAccent
            selectByMouse: true
            echoMode: TextInput.Password
            text: page.keyEdit
            onTextChanged: page.keyEdit = text
            onAccepted: page.apply()

            cursorDelegate: Rectangle {
                width: 2
                color: Colors.accent
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Ключ бесплатный: openweathermap.org/api → Current Weather Data. Он хранится локально в weather.json.")
        color: Colors.dim
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // ── единицы ─────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Единицы измерения")
        color: Colors.muted
        font.pixelSize: 11
        font.bold: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { key: "metric", label: "°C · м/с" },
                { key: "imperial", label: "°F · mph" }
            ]

            delegate: Item {
                id: unitTile

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 32

                readonly property bool active: (page.settings.units || "metric") === modelData.key

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: unitTile.active ? Colors.accent : "transparent"
                    border.width: 1
                    border.color: unitTile.active ? Colors.accent
                                                : (unitHover.containsMouse ? Colors.accent : Colors.divider)
                }

                Label {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: unitTile.active ? Colors.onAccent
                         : (unitHover.containsMouse ? Colors.text : Colors.muted)
                    font.pixelSize: 11
                }

                MouseArea {
                    id: unitHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.setUnits(modelData.key)
                }
            }
        }
    }

    // сохранить ключ/город по кнопке — на случай, если Enter не нажали
    Item {
        Layout.fillWidth: true
        implicitHeight: 32

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: saveHover.containsMouse ? Colors.selected : "transparent"
            border.width: 1
            border.color: saveHover.containsMouse ? Colors.accent : Colors.divider
        }

        Label {
            anchors.centerIn: parent
            text: Lang.t("Сохранить")
            color: saveHover.containsMouse ? Colors.text : Colors.muted
            font.pixelSize: 11
        }

        MouseArea {
            id: saveHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: page.apply()
        }
    }
}
