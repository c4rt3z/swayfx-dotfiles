import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"
import "../../singletons"

// Раздел «Панель»: какие модули показывать в баре waybar и размытие панелей.
//
// Своего состояния не держим — правда живёт в ~/.config/waybar/config и
// ~/.config/sway/config, правит их scripts/bar-panel.py, а сюда он пишет
// сводку в ~/.cache/quickshell/bar.json (панель читает файл и следит за ним).
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/bar-panel.py"
    readonly property string stateFile: home + "/.cache/quickshell/bar.json"

    property var modules: []
    property var blur: ({ waybar: true, panels: true })

    spacing: 14

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            page.modules = j.modules || [];
            page.blur = j.blur || { waybar: true, panels: true };
        } catch (e) {
        }
    }

    // пересобрать сводку из конфигов (на случай правок руками)
    Component.onCompleted: Quickshell.execDetached(["python3", page.script, "build"])

    FileView {
        id: stateView
        path: page.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse(typeof text === "function" ? text() : text)
    }

    readonly property var blurRows: [
        { key: "waybar", name: Lang.t("Панель waybar") },
        { key: "panels", name: Lang.t("Панели quickshell") }
    ]

    Label {
        text: Lang.t("Модули бара")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 28
        rowSpacing: 2

        Repeater {
            model: page.modules

            delegate: Item {
                id: modRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 26

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    CheckBox {
                        checked: modRow.modelData.on
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modRow.modelData.name
                        font.pixelSize: 12
                        color: modRow.modelData.on ? Colors.text : Colors.dim
                    }

                    Label {
                        text: modRow.modelData.zone === "left" ? Lang.t("слева")
                              : (modRow.modelData.zone === "center" ? Lang.t("центр") : Lang.t("справа"))
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.7)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "python3", page.script, "toggle", modRow.modelData.key
                    ])
                }
            }
        }
    }

    Label {
        text: Lang.t("Размытие")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 28
        rowSpacing: 2

        Repeater {
            model: page.blurRows

            delegate: Item {
                id: blurRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 26

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    CheckBox {
                        checked: page.blur[blurRow.modelData.key] !== false
                    }

                    Label {
                        Layout.fillWidth: true
                        text: blurRow.modelData.name
                        font.pixelSize: 12
                        color: Colors.text
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "python3", page.script, "blur", blurRow.modelData.key
                    ])
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Изменения применяются сразу: модули — в ~/.config/waybar/config, ")
              + Lang.t("размытие — в блоках layer_effects в ~/.config/sway/config.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
