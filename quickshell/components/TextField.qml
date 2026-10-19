import QtQuick
import "../singletons"

// Поле ввода для меню настроек: рамка, значок слева, плейсхолдер и
// крестик очистки. Своё, потому что в QtQuick готового TextField без
// оформления нет, а в панели поиска он уже нарисован вручную.
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

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: Colors.selected
        border.width: 1
        border.color: input.activeFocus ? Colors.accent : Colors.divider
    }

    Label {
        id: iconLabel
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: field.icon
        color: Colors.dim
        font.pixelSize: 12
    }

    // плейсхолдер лежит под полем ввода, а не поверх: иначе он перехватывал
    // бы щелчки мышью
    Label {
        id: hint
        anchors.left: iconLabel.right
        anchors.leftMargin: 8
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && !input.activeFocus
        text: field.placeholder
        color: Qt.alpha(Colors.dim, 0.85)
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    TextInput {
        id: input
        anchors.left: iconLabel.right
        anchors.leftMargin: 8
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: 8
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
        anchors.rightMargin: 8
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
