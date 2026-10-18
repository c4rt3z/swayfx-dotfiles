import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"
import "../../singletons"

// Раздел «Языки»: раскладки клавиатуры.
//
// Сверху — включённые, в том порядке, в каком их гоняет Alt+Shift: клик делает
// раскладку активной. Ниже — поиск по всем раскладкам, которые знает xkb
// (около сотни): клик включает или выключает.
//
// Своего состояния не держим: список раскладок живёт прямо в
// ~/.config/sway/config (строка xkb_layout внутри input type:keyboard),
// правит его scripts/layouts-index.py, а сюда он пишет сводку в
// ~/.cache/quickshell/layouts.json.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/layouts-index.py"
    readonly property string stateFile: home + "/.cache/quickshell/layouts.json"

    property var enabled: []
    property var available: []
    property int active: 0
    property string options: ""
    property string query: ""

    spacing: 14

    // сколько строк списка показываем: панель высокая, но не на весь экран
    readonly property int shown: 16

    readonly property var found: {
        let q = page.query.trim().toLowerCase();
        if (q === "")
            return page.available.slice(0, page.shown);
        return page.available.filter(l => l.name.toLowerCase().indexOf(q) >= 0
                                          || l.code === q).slice(0, page.shown);
    }

    function isOn(code) {
        for (let i = 0; i < page.enabled.length; ++i)
            if (page.enabled[i].code === code)
                return true;
        return false;
    }

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            page.enabled = j.enabled || [];
            page.available = j.available || [];
            page.active = j.active || 0;
            page.options = j.options || "";
        } catch (e) {
        }
    }

    // пересобрать сводку (например, если конфиг правили руками)
    Component.onCompleted: Quickshell.execDetached(["python3", page.script, "build"])

    FileView {
        id: stateView
        path: page.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse(typeof text === "function" ? text() : text)
    }

    Label {
        text: Lang.t("Включены")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Column {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.enabled

            delegate: Item {
                id: onRow

                required property var modelData
                required property int index

                readonly property bool current: onRow.index === page.active

                width: parent.width
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: onRow.current
                           ? Colors.selected
                           : (onHover.containsMouse ? Colors.selected : "transparent")
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    CheckBox {
                        checked: true
                    }

                    Label {
                        Layout.fillWidth: true
                        text: onRow.modelData.name + "  (" + onRow.modelData.code + ")"
                        font.pixelSize: 12
                        color: onRow.current ? Colors.accent : Colors.text
                        elide: Text.ElideRight
                    }

                    Label {
                        text: onRow.current ? Lang.t("активна") : Lang.t("сделать активной")
                        font.pixelSize: 10
                        color: onRow.current ? Colors.accent : Qt.alpha(Colors.dim, 0.7)
                    }
                }

                MouseArea {
                    id: onHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "python3", page.script, "switch", onRow.modelData.code
                    ])
                }
            }
        }
    }

    Label {
        text: Lang.t("Добавить или убрать")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 32
        color: Colors.surface
        border.width: 1
        border.color: addHover.hovered ? Colors.divider : Colors.border

        HoverHandler {
            id: addHover
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10

            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: addInput.text === ""
                text: Lang.t("найди язык: english, de, ukrainian, japanese…")
                color: Colors.dim
                font.pixelSize: 12
            }

            TextInput {
                id: addInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                selectByMouse: false
                onTextChanged: page.query = text
                onAccepted: if (page.found.length > 0)
                    Quickshell.execDetached([
                        "python3", page.script, "toggle", page.found[0].code
                    ])

                cursorDelegate: Rectangle {
                    width: 2
                    color: Colors.accent
                }
            }
        }
    }

    Column {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.found

            delegate: Item {
                id: addRow

                required property var modelData

                readonly property bool on: page.isOn(addRow.modelData.code)

                width: parent.width
                height: 26

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: addHoverRow.containsMouse ? Colors.selected : "transparent"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    CheckBox {
                        checked: addRow.on
                    }

                    Label {
                        Layout.fillWidth: true
                        text: addRow.modelData.name
                        font.pixelSize: 12
                        color: addRow.on ? Colors.text : Colors.dim
                        elide: Text.ElideRight
                    }

                    Label {
                        text: addRow.modelData.code
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.7)
                    }
                }

                MouseArea {
                    id: addHoverRow
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "python3", page.script, "toggle", addRow.modelData.code
                    ])
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Раскладки пишутся в строку xkb_layout в ~/.config/sway/config, поэтому ")
              + Lang.t("при включении и выключении sway перезагружает конфиг (бар мигнёт) — ")
              + Lang.t("зато раскладку сразу видят все устройства. Переключение активной — ")
              + (page.options !== "" ? page.options : Lang.t("настраивается в конфиге")) + ". "
              + Lang.t("Последнюю раскладку выключить нельзя. Показано ") + page.found.length
              + Lang.t(" из ") + page.available.length + Lang.t(" — уточни запрос, если нужного языка не видно.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
