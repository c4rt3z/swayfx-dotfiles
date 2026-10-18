import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Язык»: на каком языке подписи панелей.
//
// Русский — исходный язык: подписи в QML написаны по-русски, а переводы лежат
// рядом в ~/.config/quickshell/i18n/<код>.json (ключ — русская строка, см.
// singletons/Lang.qml). Выбранный язык хранится одной строкой в
// ~/.config/quickshell/language. Lang следит за обоими файлами, поэтому подписи
// меняются сразу, без перезапуска оболочки.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string langFile: home + "/.config/quickshell/language"

    spacing: 14

    Label {
        text: Lang.t("Язык интерфейса")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Column {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: Lang.languages

            delegate: Item {
                id: langRow

                required property var modelData

                readonly property bool current: langRow.modelData.code === Lang.code

                width: parent.width
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: langRow.current
                           ? Colors.selected
                           : (langHover.containsMouse ? Colors.selected : "transparent")
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    CheckBox {
                        checked: langRow.current
                    }

                    Label {
                        Layout.fillWidth: true
                        text: langRow.modelData.name + "  (" + langRow.modelData.code + ")"
                        font.pixelSize: 12
                        color: langRow.current ? Colors.accent : Colors.text
                    }

                    Label {
                        text: langRow.current ? Lang.t("выбран") : ""
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.7)
                    }
                }

                MouseArea {
                    id: langHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        "sh", "-c",
                        "printf '%s\\n' " + langRow.modelData.code + " > " + page.langFile
                        + " && python3 " + page.home
                        + "/.config/waybar/scripts/waybar-lang.py apply"
                    ])
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Переводы лежат в ~/.config/quickshell/i18n: файл на язык, ключ — русская строка. Новый язык — положить <код>.json и дописать его в singletons/Lang.qml. Чего нет в словаре языка, берётся из английского — словарь можно пополнять по частям. Язык меняется сразу и в панелях, и в подписях waybar (часы, «ничего не играет», состояние сети).")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
