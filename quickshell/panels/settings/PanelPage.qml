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
    property string position: "top"
    property string mode: "standard"

    spacing: 14

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            page.modules = j.modules || [];
            page.blur = j.blur || { waybar: true, panels: true };
            page.position = j.position === "bottom" ? "bottom" : "top";
            page.mode = j.mode || "standard";
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

    readonly property var positionRows: [
        { key: "top", name: Lang.t("Сверху"), icon: "\\uf062" },
        { key: "bottom", name: Lang.t("Снизу"), icon: "\\uf063" }
    ]

    readonly property var modeRows: [
        { key: "standard", name: Lang.t("Сплошной") },
        { key: "floating", name: Lang.t("Плавающий") },
        { key: "minimal", name: Lang.t("Без фона") }
    ]

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
        text: Lang.t("Положение бара")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: page.positionRows

            delegate: Item {
                id: posRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 32

                readonly property bool current: page.position === modelData.key

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: posRow.current ? Colors.selected : "transparent"
                    border.width: 1
                    border.color: posRow.current ? Colors.accent
                                : (posHover.containsMouse ? Colors.border : Colors.divider)
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7

                    Label {
                        text: posRow.modelData.icon
                        color: posRow.current ? Colors.accent : Colors.muted
                        font.pixelSize: 11
                    }
                    Label {
                        text: posRow.modelData.name
                        color: posRow.current ? Colors.text : Colors.muted
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: posHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "python3", page.script, "position", posRow.modelData.key
                    ])
                }
            }
        }
    }

    Label {
        text: Lang.t("Вид бара")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    // Кнопки вида бара крупные: в каждой — миниатюра, как полоса будет
    // выглядеть. Миниатюра учитывает и вид (сплошная, островок, без
    // подложки), и положение: полоска снизу, если бар внизу.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: page.modeRows

            delegate: Item {
                id: modeRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 78

                readonly property bool current: page.mode === modelData.key

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: modeRow.current ? Colors.selected : "transparent"
                    border.width: 1
                    border.color: modeRow.current ? Colors.accent
                                : (modeHover.containsMouse ? Colors.border : Colors.divider)
                }

                // ── миниатюра полосы ───────────────────────────────────
                Item {
                    id: miniArea

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    height: 38

                    // «экран» под миниатюрой
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Qt.alpha(Colors.bg, 0.35)
                        border.width: 1
                        border.color: Colors.divider
                    }

                    Rectangle {
                        id: miniBar

                        // плавающий — короткий островок с полями по бокам,
                        // остальные — во всю ширину
                        width: modeRow.modelData.key === "floating"
                               ? parent.width * 0.74
                               : parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        // сверху или снизу — как положение бара
                        y: page.position === "bottom"
                           ? parent.height - height - 3
                           : 3
                        height: 15
                        radius: modeRow.modelData.key === "floating" ? 8 : 0
                        color: modeRow.modelData.key === "minimal"
                               ? "transparent" : Colors.accent
                        border.width: modeRow.modelData.key === "minimal" ? 1 : 0
                        border.color: Qt.alpha(Colors.accent, 0.55)

                        // модули: точки-разделители
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            spacing: 5

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: 7
                                    height: 3
                                    radius: 1
                                    color: Qt.alpha(Colors.bg, 0.6)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                Label {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modeRow.modelData.name
                    color: modeRow.current ? Colors.text : Colors.muted
                    font.pixelSize: 11
                }

                MouseArea {
                    id: modeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "python3", page.script, "mode", modeRow.modelData.key
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
