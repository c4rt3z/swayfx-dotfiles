import QtQuick
import "../singletons"

// Поле ввода с «печатающимся» текстом: символы проявляются по одному.
//
// Внутри — обычный TextInput, поэтому ввод, курсор, выделение и буфер
// обмена остаются родными. Поверх поля живёт занавес: он закрывает часть
// строки, которая ещё не проявилась, так что текст набирается по буквам.
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
    property color fieldColor: Colors.base
    property color textColor: Colors.text
    property color placeholderColor: Colors.dim
    property color caretColor: Colors.accent
    property int fontPixelSize: 13
    // пауза между символами, мс; 0 — печатать мгновенно
    property int delay: 22
    property bool animate: true

    signal accepted()
    signal edited(string value)
    // клавиши, которые поле не обрабатывает само (стрелки, Tab)
    signal keyPressed(int key, var event)

    // сколько символов уже проявилось
    property string shown: ""
    property bool typing: false

    implicitHeight: 30
    implicitWidth: 200

    function retype() {
        if (!type.animate || type.delay <= 0) {
            type.shown = input.text;
            type.typing = false;
            return;
        }
        type.shown = "";
        type.typing = true;
        type.step();
    }

    function step() {
        const full = input.text;
        if (type.shown.length >= full.length) {
            type.shown = full;
            type.typing = false;
            return;
        }
        type.shown = full.substring(0, type.shown.length + 1);
        typeTimer.restart();
    }

    Timer {
        id: typeTimer
        interval: type.delay
        onTriggered: type.step()
    }

    TextInput {
        id: input
        anchors.fill: parent
        verticalAlignment: TextInput.AlignVCenter
        // сам текст не рисуем: за нами его показывает «занавес» с метриками
        color: "transparent"
        selectionColor: Colors.accent
        selectedTextColor: Colors.onAccent
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        selectByMouse: false
        onTextChanged: {
            type.edited(text);
            type.retype();
        }
        onAccepted: type.accepted()

        Keys.onPressed: event => type.keyPressed(event.key, event)

        cursorDelegate: Rectangle {
            width: 2
            color: type.caretColor
        }
    }

    // сколько места занимает проявившаяся часть строки
    TextMetrics {
        id: shownMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: type.shown
    }

    // и сколько — вся строка целиком
    TextMetrics {
        id: fullMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: input.text
    }

    // проявившийся текст
    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: type.shown
        color: type.textColor
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
    }

    // подсказка, пока поле пусто
    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && type.shown === ""
        text: type.placeholder
        color: type.placeholderColor
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        elide: Text.ElideRight
        width: parent.width
    }

    // занавес: закрывает ровно ту часть строки, которая ещё не проявилась
    // (не всё поле — иначе он закрыл бы и подсказку)
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: type.fontPixelSize + 8
        x: shownMetrics.width
        width: Math.max(0, fullMetrics.width - shownMetrics.width)
        color: type.fieldColor
    }
}
