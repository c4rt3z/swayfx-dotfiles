import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Службы»: что запускает рабочий стол и как это перезапустить.
//
// Своего состояния нет: список и команды перезапуска собирает
// scripts/system-index.py из ~/.config/sway/config (там они и живут), он же
// пишет сюда сводку ~/.cache/quickshell/system.json. Перезапуск — его команда
// restart: она запускает ту же строку, которой службу поднимает sway, поэтому
// список не разъедется с конфигом.
//
// quickshell и waybar перезапускаются через setsid: новый процесс не должен
// умереть вместе со старым, когда тот закроет свой сеанс.
ColumnLayout {
    id: page

    readonly property string sleepScript: (Quickshell.env("HOME") ?? "")
                                        + "/.config/quickshell/scripts/sleep-policy.py"
    property var sleepState: ({ ac_minutes: 0, battery_minutes: 0, source: "ac" })
    property string sleepKey: "ac_minutes"
    property int sleepValue: 0

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/system-index.py"
    readonly property string stateFile: home + "/.cache/quickshell/system.json"

    property var services: []

    spacing: 14

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            page.services = j.services || [];
        } catch (e) {
        }
    }

    function run(args) {
        Quickshell.execDetached(["python3", page.script].concat(args));
    }

    Component.onCompleted: {
        page.run(["build"]);
        sleepProc.running = true;
    }

    FileView {
        id: stateView

        path: page.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse(typeof text === "function" ? text() : text)
    }

    Label {
        text: Lang.t("Службы рабочего стола")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.services

            delegate: Item {
                id: row

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 34

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: rowHover.containsMouse ? Colors.selected : "transparent"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    // точка состояния: работает — акцент, стоит — притушено
                    Rectangle {
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 4
                        color: row.modelData.running ? Colors.accent : Qt.alpha(Colors.dim, 0.4)
                    }

                    Label {
                        text: row.modelData.name
                        font.pixelSize: 12
                        color: Colors.text
                    }

                    Label {
                        Layout.fillWidth: true
                        text: Lang.t(row.modelData.note)
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.75)
                        elide: Text.ElideRight
                    }

                    Label {
                        text: row.modelData.running ? Lang.t("работает") : Lang.t("остановлена")
                        font.pixelSize: 10
                        color: row.modelData.running
                               ? Qt.alpha(Colors.dim, 0.8)
                               : Qt.alpha(Colors.red, 0.9)
                    }

                    Rectangle {
                        implicitWidth: restartLabel.implicitWidth + 16
                        implicitHeight: 22
                        radius: 4
                        color: restartHover.containsMouse ? Colors.selected : "transparent"
                        border.width: 1
                        border.color: Colors.border

                        Label {
                            id: restartLabel
                            anchors.centerIn: parent
                            text: Lang.t("перезапустить")
                            font.pixelSize: 10
                            color: Colors.text
                        }

                        MouseArea {
                            id: restartHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.run(["restart", row.modelData.id])
                        }
                    }
                }

                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Перезапуск идёт той же командой, которой службу поднимает sway, — она видна в ~/.config/sway/config. quickshell после перезапуска открывает панели заново, поэтому окно настроек закроется.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    // ── сон по простою ─────────────────────────────────────────────────────
    Label {
        text: Lang.t("Сон по простою")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Process {
        id: sleepProc
        command: ["python3", page.sleepScript, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    page.sleepState = data;
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: sleepSetProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.sleepState = JSON.parse(text || "{}");
                } catch (e) {
                }
            }
        }
    }

    Repeater {
        model: [
            { key: "ac_minutes", name: Lang.t("От сети"), hint: Lang.t("минут до сна") },
            { key: "battery_minutes", name: Lang.t("От батареи"), hint: Lang.t("минут до сна") }
        ]

        delegate: Item {
            id: sleepRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 30

            RowLayout {
                anchors.fill: parent
                spacing: 8

                Label {
                    Layout.preferredWidth: 92
                    text: sleepRow.modelData.name
                    color: Colors.text
                    font.pixelSize: 12
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 120
                    value: Number(page.sleepState[sleepRow.modelData.key]) || 0
                    onMoved: v => {
                        const state = Object.assign({}, page.sleepState);
                        state[sleepRow.modelData.key] = Math.round(v);
                        page.sleepState = state;
                        sleepSave.restart();
                    }
                }

                Label {
                    Layout.preferredWidth: 96
                    text: (Number(page.sleepState[sleepRow.modelData.key]) || 0)
                          + Lang.t(" мин")
                          + (Number(page.sleepState[sleepRow.modelData.key]) === 0
                             ? Lang.t(" (не спит)") : "")
                    color: Colors.dim
                    font.pixelSize: 10
                }
            }
        }
    }

    Timer {
        id: sleepSave
        interval: 300
        repeat: false
        onTriggered: {
            sleepSetProc.command = ["python3", page.sleepScript, "set",
                                    page.sleepKey, String(page.sleepValue)];
            sleepSetProc.running = false;
            sleepSetProc.running = true;
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Как в Windows: отдельно для сети и для батареи. 0 — не засыпать "
                     + "вовсе. Свой сон logind не мешает: мы блокируем его и решаем сами "
                     + "(scripts/sleep-policy.py), простой считаем так же, как swayidle.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
