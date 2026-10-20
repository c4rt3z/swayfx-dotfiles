import QtQuick
import "../singletons"

// Поле ввода с плавной кареткой.
//
// Внутри — обычный TextInput: текст, выделение, буфер обмена и клавиши
// работают родным образом. Своя у нас только каретка — чтобы при вводе она
// не прыгала, а плавно переезжала на новое место (как в свежем Word).
//
//   TypeInput {
//       placeholder: "поиск…"
//       onEdited: value => query = value
//       onAccepted: activate()
//   }
Item {
    id: type

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property color textColor: Colors.text
    property color placeholderColor: Colors.dim
    property color caretColor: Colors.accent
    property int fontPixelSize: 13
    // сколько живёт каретка между морганиями, мс
    property int blinkInterval: 530
    // время переезда каретки, мс
    property int moveDuration: 130

    signal accepted()
    signal edited(string value)
    // клавиши, которые поле не обрабатывает само (стрелки, Tab)
    signal keyPressed(int key, var event)

    property bool caretVisible: true

    implicitHeight: 30
    implicitWidth: 200

    TextInput {
        id: input
        anchors.fill: parent
        verticalAlignment: TextInput.AlignVCenter
        color: type.textColor
        selectionColor: Colors.accent
        selectedTextColor: Colors.onAccent
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        selectByMouse: true
        // своей каретки не рисуем — она ниже, плавная
        cursorVisible: false
        onTextChanged: type.edited(text)
        onAccepted: type.accepted()

        Keys.onPressed: event => type.keyPressed(event.key, event)
    }

    // где сейчас каретка: ширина текста до позиции курсора
    TextMetrics {
        id: caretMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: input.text.substring(0, input.cursorPosition)
    }

    // Каретка: тонкая полоска сразу после текста, переезжает плавно.
    // Ничего не перекрывает — стоит после последней буквы.
    Rectangle {
        id: caret
        x: caretMetrics.width
        y: (parent.height - height) / 2
        width: 2
        height: type.fontPixelSize + 4
        color: type.caretColor
        visible: type.caretVisible && input.activeFocus

        Behavior on x {
            NumberAnimation {
                duration: type.moveDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Timer {
        id: blink
        interval: type.blinkInterval
        repeat: true
        onTriggered: type.caretVisible = !type.caretVisible
    }

    // подсказка, пока поле пусто. Смещена вправо от каретки, чтобы полоска
    // не наезжала на буквы.
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === ""
        text: type.placeholder
        color: type.placeholderColor
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        elide: Text.ElideRight
        width: parent.width
    }
}
