import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Приложения по умолчанию»: у каждой задачи своё приложение — как в
// Windows. Терминал, файловый менеджер и браузер лежат переменными в
// ~/.config/sway/config (set $term / $filemanager / $browser), остальные задачи —
// обработчики типов файлов в ~/.config/mimeapps.list (по ним открываются файлы
// из проводника и ссылки из программ).
//
// Своего состояния страница не держит: список задач с кандидатами готовит
// scripts/defaults-index.py (~/.cache/quickshell/defaults.json), он же и меняет
// выбор. Размер шрифта терминала приходит из system-index.py (system.json).
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/defaults-index.py"
    readonly property string stateFile: home + "/.cache/quickshell/defaults.json"
    readonly property string systemFile: home + "/.cache/quickshell/system.json"

    property var tasks: []
    property var font: null
    property string opened: ""

    spacing: 12

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            page.tasks = j.tasks || [];
        } catch (e) {
        }
    }

    function run(args) {
        Quickshell.execDetached(["python3", page.script].concat(args));
    }

    Component.onCompleted: page.run(["build"])

    FileView {
        id: stateView

        path: page.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse(typeof text === "function" ? text() : text)
    }

    FileView {
        id: systemView

        path: page.systemFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                page.font = (JSON.parse(typeof text === "function" ? text() : text) || {}).font || null;
            } catch (e) {
                page.font = null;
            }
        }
    }

    // ── задача ─────────────────────────────────────────────────────────────

    component TaskRow: ColumnLayout {
        id: task

        required property var modelData

        readonly property bool opened: page.opened === task.modelData.id
        readonly property var current: task.modelData.current || {}
        readonly property var candidates: task.modelData.candidates || []

        Layout.fillWidth: true
        spacing: 2

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 6
            color: task.opened ? Colors.selected
                               : (taskHover.containsMouse ? Colors.selected : "transparent")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Label {
                    Layout.preferredWidth: 150
                    text: Lang.t(task.modelData.name)
                    font.pixelSize: 12
                    color: task.opened ? Colors.accent : Colors.text
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    text: task.current.name || Lang.t("не выбрано")
                    font.pixelSize: 12
                    color: task.current.name ? Colors.text : Qt.alpha(Colors.dim, 0.7)
                    elide: Text.ElideRight
                }

                Label {
                    text: task.opened ? Lang.t("свернуть") : Lang.t("изменить")
                    font.pixelSize: 10
                    color: Qt.alpha(Colors.dim, 0.75)
                }
            }

            MouseArea {
                id: taskHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.opened = task.opened ? "" : task.modelData.id
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.bottomMargin: 4
            visible: task.opened
            spacing: 1

            Repeater {
                model: task.candidates

                delegate: Rectangle {
                    required property var modelData

                    readonly property bool active: modelData.current === true

                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 5
                    color: active ? Colors.selected
                                  : (rowHover.containsMouse ? Colors.selected : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18

                            Image {
                                anchors.centerIn: parent
                                visible: modelData.icon !== ""
                                source: modelData.icon !== "" ? "file://" + modelData.icon : ""
                                sourceSize.width: 18
                                sourceSize.height: 18
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: modelData.icon === ""
                                text: modelData.name.charAt(0).toUpperCase()
                                font.pixelSize: 12
                                color: Colors.dim
                            }
                        }

                        Label {
                            text: modelData.name
                            font.pixelSize: 12
                            color: active ? Colors.accent : Colors.text
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.note
                            font.pixelSize: 10
                            color: Qt.alpha(Colors.dim, 0.75)
                            elide: Text.ElideRight
                        }

                        Label {
                            text: active ? Lang.t("по умолчанию") : ""
                            font.pixelSize: 10
                            color: Qt.alpha(Colors.dim, 0.7)
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.run(["set", task.modelData.id, modelData.id])
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: task.candidates.length === 0
                text: Lang.t("нет приложений, которые умеют открывать такие файлы")
                font.pixelSize: 10
                color: Qt.alpha(Colors.dim, 0.75)
                wrapMode: Text.WordWrap
            }

            // у терминала тут же и кегль: терминал выбран выше, а печатает он
            // размером из своего конфига (alacritty.toml, kitty.conf)
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 30
                radius: 5
                color: "transparent"
                border.width: 1
                border.color: Colors.border
                visible: task.modelData.id === "terminal" && page.font !== null

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 6
                    spacing: 8

                    Label {
                        text: Lang.t("Размер шрифта")
                        font.pixelSize: 11
                        color: Colors.dim
                    }

                    Label {
                        Layout.fillWidth: true
                        text: page.font ? (page.font.size.toFixed(1) + "  (" + page.font.min + "–" + page.font.max + ")") : ""
                        font.pixelSize: 11
                        color: Colors.accent
                    }

                    Repeater {
                        model: ["-", "+"]

                        delegate: Rectangle {
                            required property string modelData

                            width: 26
                            height: 20
                            radius: 4
                            color: page.font && ((modelData === "-" && page.font.size <= page.font.min)
                                                || (modelData === "+" && page.font.size >= page.font.max))
                                   ? Colors.base : Colors.surface
                            border.width: 1
                            border.color: Colors.border

                            Label {
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.pixelSize: 12
                                color: Colors.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(
                                    ["python3", page.home + "/.config/quickshell/scripts/system-index.py",
                                     "font", parent.modelData + page.font.step])
                            }
                        }
                    }
                }
            }

            // терминал, файловый менеджер и браузер записаны в двух местах: если
            // ссылки/папки открывает не то приложение, что стоит выше, — говорим
            Label {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: !!(task.modelData.xdg && task.modelData.xdg.differs)
                text: Lang.t("ссылки и папки открывает ") + (task.modelData.xdg ? task.modelData.xdg.name : "")
                font.pixelSize: 10
                color: Qt.alpha(Colors.dim, 0.8)
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── страница ───────────────────────────────────────────────────────────

    Label {
        Layout.fillWidth: true
        text: Lang.t("Приложения по умолчанию")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.tasks

            delegate: TaskRow {}
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Терминал, файловый менеджер и браузер записаны в ~/.config/sway/config (set $term, $filemanager, $browser) — при смене sway перечитывает конфиг. Остальные задачи — обработчики типов файлов в ~/.config/mimeapps.list: по ним открываются файлы из проводника и ссылки из программ.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
