import QtQuick
import QtQuick.Layouts
import "../singletons"

// Список тем значков или курсоров: что установлено и что выбрано сейчас.
//
// Данные приходят снаружи (страница «Внешний вид» читает их скриптом
// icons-cursors.py), компонент только рисует список и сообщает о выборе.
ColumnLayout {
    id: root

    property string title: ""
    property var items: []
    property string current: ""
    property int maxRows: 8

    signal picked(string name)

    spacing: 6

    Label {
        text: root.title
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    // обычный Column с заданной высотой: Repeater внутри ColumnLayout не
    // участвует в расчёте implicitHeight, и список схлопнулся бы в ноль
    Column {
        Layout.fillWidth: true
        spacing: 1
        height: Math.min(root.items.length, root.maxRows) * 26

        Repeater {
            model: root.items.slice(0, root.maxRows)

            delegate: Item {
                id: themeRow

                required property var modelData

                readonly property bool current: root.current === themeRow.modelData

                width: parent.width
                height: 26

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: themeRow.current ? Colors.selected
                           : (themeHover.containsMouse ? Colors.selected : "transparent")
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    text: (themeRow.current ? "\uf04b  " : "    ") + themeRow.modelData
                    color: themeRow.current ? Colors.accent
                           : (themeHover.containsMouse ? Colors.text : Colors.muted)
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: themeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(themeRow.modelData)
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.items.length > root.maxRows
        text: Lang.t("…и ещё ") + (root.items.length - root.maxRows)
        color: Colors.dim
        font.pixelSize: 10
    }
}
