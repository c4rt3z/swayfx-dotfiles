import QtQuick
import "../singletons"

// Поле ввода для меню настроек. Сделано по образцу обычной кнопки списка
// разделов: та же высота (30), та же иконка слева (отступ 9) и тот же отступ
// под текст (32), тот же шрифт. Выглядит как ещё одна кнопка — только в неё
// вводят.
Item {
    id: field

    property alias text: input.text
    property string placeholder: ""
    property string icon: "\uf002"

    signal accepted()
    signal edited(string value)

    implicitHeight: 30
    implicitWidth: 200

    function clear() {
        input.text = "";
    }

    function focusInput() {
        input.forceActiveFocus();
    }

    // подложка и рамка — как у строк списка разделов
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: input.activeFocus ? Colors.selected
               : (hover.containsMouse ? Colors.selected : "transparent")
        border.width: input.activeFocus ? 1 : 0
        border.color: Colors.accent
    }

    // зона наведения — под полем ввода, чтобы не мешать кликам
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: -1
    }

    Label {
        id: iconLabel
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: field.icon
        font.pixelSize: 13
        color: input.activeFocus ? Colors.accent : Colors.dim
    }

    // плейсхолдер — под полем ввода, иначе он перехватывал бы щелчки
    Label {
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && !input.activeFocus
        text: field.placeholder
        color: Qt.alpha(Colors.dim, 0.85)
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        font.family: Fonts.panelFamily
        font.pixelSize: 12
        color: Colors.text
        selectionColor: Colors.accent
        selectedTextColor: Colors.onAccent
        selectByMouse: true
        onTextChanged: field.edited(text)
        onAccepted: field.accepted()

        cursorDelegate: Rectangle {
            width: 2
            color: Colors.accent
        }
    }

    Label {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text !== ""
        text: "\u00d7"
        color: clearHover.containsMouse ? Colors.red : Colors.dim
        font.pixelSize: 13

        MouseArea {
            id: clearHover
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                field.clear();
                field.focusInput();
            }
        }
    }
}
