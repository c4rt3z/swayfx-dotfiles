import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Внешний вид» меню настроек: схема оформления, обои и шрифты.
//
// Начинка обоев общая с панелью Mod+Shift+W — components/AppearanceSettings.qml.
// Шрифты — только здесь: в окне выбора обоев им не место.
//
// Настройки пишет scripts/fonts.py в ~/.config/quickshell/fonts.json. Панели
// читают файл через singletons/Fonts.qml и меняются сразу, waybar — после
// пересборки CSS (её делает сам скрипт).
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property var targets: [
        { key: "ui", title: Lang.t("Все интерфейсы") },
        { key: "panels", title: Lang.t("Панели quickshell") },
        { key: "waybar", title: Lang.t("Waybar") }
    ]

    // какой список шрифтов раскрыт ("" — все свёрнуты)
    property string fontTarget: ""
    property string fontFilter: ""
    property var fonts: []
    property string current: ""

    readonly property var shownFonts: {
        const q = page.fontFilter.trim().toLowerCase();
        if (q === "")
            return page.fonts;
        return page.fonts.filter(n => n.toLowerCase().indexOf(q) >= 0);
    }

    spacing: 12

    function resolved(key) {
        if (key === "waybar")
            return Fonts.waybarFamily;
        if (key === "panels")
            return Fonts.panelFamily;
        return Fonts.ui !== "" ? Fonts.ui : Fonts.defaultFamily;
    }

    function isDefault(key) {
        if (key === "waybar")
            return Fonts.waybar === "";
        if (key === "panels")
            return Fonts.panels === "";
        return Fonts.ui === "";
    }

    function openFonts(key) {
        page.fontTarget = page.fontTarget === key ? "" : key;
        page.fontFilter = "";
    }

    function applyFont(name) {
        if (page.fontTarget === "" || name === "")
            return;
        page.current = name;
        setProcess.command = ["python3", page.home + "/.config/quickshell/scripts/fonts.py",
                              "set", page.fontTarget + "=" + name];
        setProcess.running = true;
        page.fontTarget = "";
    }

    function resetFonts() {
        page.current = "";
        setProcess.command = ["python3", page.home + "/.config/quickshell/scripts/fonts.py", "reset"];
        setProcess.running = true;
    }

    Component.onCompleted: listProcess.running = true

    Process {
        id: listProcess
        command: ["python3", page.home + "/.config/quickshell/scripts/fonts.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    page.fonts = Array.isArray(data.fonts) ? data.fonts : [];
                } catch (e) {
                    page.fonts = [];
                }
            }
        }
    }

    Process {
        id: setProcess
        onExited: {
            // Fonts.qml сам увидит изменение файла; список можно не перечитывать
            page.current = "";
        }
    }

    AppearanceSettings {
        id: appearance
        Layout.fillWidth: true
    }

    // ── Шрифты ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 10

        Label {
            text: Lang.t("Шрифты")
            color: Colors.text
            font.pixelSize: 13
            font.bold: true
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colors.divider
        }
        Label {
            text: Lang.t("fontconfig")
            color: Colors.dim
            font.pixelSize: 10
        }
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Lang.t("Шрифт должен содержать иконки Nerd Font, иначе значки в панелях и баре станут квадратами. Меняется сразу, без перезапуска.")
        color: Colors.dim
        font.pixelSize: 10
    }

    // Repeater в Layout не участвует в расчёте implicitHeight — оборачиваем
    // в обычный Column, иначе страница «Внешний вид» обрезается снизу.
    Item {
        id: fontsBlock
        Layout.fillWidth: true
        implicitHeight: fontSections.implicitHeight

        Column {
            id: fontSections
            width: parent.width
            spacing: 6

            Repeater {
                model: page.targets

                delegate: ColumnLayout {
                    id: fontSection

                    required property var modelData

                    width: fontSections.width
                    spacing: 4

            Item {
                Layout.fillWidth: true
                implicitHeight: 34

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: rowHover.containsMouse || page.fontTarget === fontSection.modelData.key
                           ? Colors.selected : Colors.base
                    border.width: 1
                    border.color: page.fontTarget === fontSection.modelData.key
                                  ? Colors.accent : Colors.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Label {
                        Layout.preferredWidth: 170
                        text: fontSection.modelData.title
                        color: Colors.text
                        font.pixelSize: 11
                    }

                    Label {
                        Layout.fillWidth: true
                        text: page.resolved(fontSection.modelData.key)
                              + (page.isDefault(fontSection.modelData.key)
                                 ? "  ·  " + Lang.t("по умолчанию") : "")
                        color: page.isDefault(fontSection.modelData.key) ? Colors.dim : Colors.accent
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Label {
                        text: page.fontTarget === fontSection.modelData.key ? "\uF077" : "\uF078"
                        color: Colors.dim
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.openFonts(fontSection.modelData.key)
                }
            }

            // раскрытый список: поиск и прокрутка
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: page.fontTarget === fontSection.modelData.key

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 6
                    color: Colors.base
                    border.width: 1
                    border.color: filterInput.activeFocus ? Colors.accent : Colors.border

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        verticalAlignment: Text.AlignVCenter
                        visible: filterInput.text === ""
                        text: Lang.t("поиск шрифта")
                        color: Colors.dim
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: filterInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.text
                        font.family: Fonts.panelFamily
                        font.pixelSize: 11
                        selectionColor: Colors.accent
                        selectedTextColor: Colors.onAccent
                        selectByMouse: true
                        text: page.fontFilter
                        onTextChanged: page.fontFilter = text

                        cursorDelegate: Rectangle {
                            width: 2
                            color: Colors.accent
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 240
                    radius: 7
                    color: Colors.base
                    border.width: 1
                    border.color: Colors.border
                    clip: true

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        spacing: 1
                        model: page.shownFonts
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: fontRow

                            required property string modelData

                            width: ListView.view.width
                            height: 26

                            readonly property bool chosen: page.resolved(page.fontTarget) === modelData

                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: fontRow.chosen ? Colors.selected
                                     : (fontHover.containsMouse ? Colors.selected : "transparent")
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 7
                                spacing: 6

                                Label {
                                    Layout.fillWidth: true
                                    text: fontRow.modelData
                                    font.family: fontRow.modelData
                                    font.pixelSize: 12
                                    color: fontRow.chosen ? Colors.accent : Colors.text
                                    elide: Text.ElideRight
                                }
                                Label {
                                    visible: fontRow.chosen
                                    text: "\uF00C"
                                    color: Colors.accent
                                    font.pixelSize: 10
                                }
                                Label {
                                    text: Lang.t("Аа Бб 123")
                                    font.family: fontRow.modelData
                                    font.pixelSize: 10
                                    color: Colors.dim
                                }
                            }

                            MouseArea {
                                id: fontHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: page.applyFont(fontRow.modelData)
                            }
                        }
                    }
                }
            }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Item {
            implicitWidth: 120
            implicitHeight: 28

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: resetHover.containsMouse ? Colors.selected : "transparent"
                border.width: 1
                border.color: resetHover.containsMouse ? Colors.accent : Colors.border
            }
            Label {
                anchors.centerIn: parent
                text: Lang.t("Сбросить шрифты")
                color: resetHover.containsMouse ? Colors.text : Colors.dim
                font.pixelSize: 10
            }
            MouseArea {
                id: resetHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: page.resetFonts()
            }
        }

        Label {
            Layout.fillWidth: true
            text: Lang.t("сброс вернёт JetBrainsMono Nerd Font") + "  ·  " + Fonts.defaultFamily
            color: Colors.dim
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
