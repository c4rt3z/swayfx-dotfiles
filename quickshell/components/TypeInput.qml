import QtQuick
import "../singletons"

// Поле ввода с плавной кареткой и мягким появлением букв.
//
// Внутри — обычный TextInput, поэтому ввод, выделение и буфер обмена
// остаются родными; текст мы рисуем сами, чтобы буквы могли проявляться
// по одной.
//
//   • каретка своя, плавно переезжает на новое место (как в свежем Word);
//   • новая буква проявляется мягким fade, а удалённая — гаснет;
//   • ничего не перекрывается: буквы стоят на своих местах, каретка —
//     сразу после последней буквы.
//
// Буквы выравниваются по шагу шрифта, поэтому эффект работает только для
// моноширинного шрифта. Если шрифт пропорциональный, текст рисуется родным
// способом (без анимации) — чтобы буквы не наезжали друг на друга.
Item {
    id: type

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property color textColor: Colors.text
    property color placeholderColor: Colors.dim
    property color caretColor: Colors.accent
    property color selectionColor: Colors.onAccent
    property int fontPixelSize: 13
    // сколько живёт каретка между морганиями, мс
    property int blinkInterval: 530
    // время переезда каретки, мс
    property int moveDuration: 130
    // длительность проявления и затухания буквы, мс
    property int fadeDuration: 150

    signal accepted()
    signal edited(string value)
    // клавиши, которые поле не обрабатывает само (стрелки, Tab)
    signal keyPressed(int key, var event)

    property bool caretVisible: true
    property bool monospace: true
    property real advance: 8
    property string oldText: ""

    implicitHeight: 30
    implicitWidth: 200

    // выделение: родные границы поля
    function inSelection(index) {
        const start = input.selectionStart;
        const end = input.cursorPosition;
        if (start < 0 || end < 0 || start === end)
            return false;
        return index >= Math.min(start, end) && index < Math.max(start, end);
    }

    // применить новый текст: новые буквы проявляются, удалённые гаснут
    function applyText(newText) {
        const old = type.oldText;
        type.oldText = newText;
        if (!type.monospace)
            return;

        const common = Math.min(old.length, newText.length);

        // пропавшие буквы — в призраки, они гаснут на своих местах
        if (newText.length < old.length) {
            for (let i = newText.length; i < old.length; i++) {
                ghostModel.append({ ch: old.charAt(i), pos: i * type.advance });
            }
            ghostTimer.restart();
        }

        // оставшиеся обновляем на месте
        for (let i = 0; i < common; i++) {
            if (charModel.count > i)
                charModel.setProperty(i, "ch", newText.charAt(i));
        }
        // новые буквы — с нулевой прозрачностью, чтобы мягко проявиться
        for (let i = common; i < newText.length; i++) {
            charModel.append({ ch: newText.charAt(i), pos: i * type.advance,
                               fresh: true });
        }
        // лишние строки убираем
        while (charModel.count > newText.length)
            charModel.remove(charModel.count - 1);
    }

    TextInput {
        id: input
        anchors.fill: parent
        verticalAlignment: TextInput.AlignVCenter
        // текст рисуем сами (по буквам), ввод и выделение — родные
        color: type.monospace ? "transparent" : type.textColor
        selectionColor: Colors.accent
        selectedTextColor: Colors.onAccent
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        selectByMouse: true
        cursorVisible: false
        onTextChanged: type.applyText(text)
        onAccepted: type.accepted()

        Keys.onPressed: event => type.keyPressed(event.key, event)
    }

    // ширина одного символа: у моноширинного шрифта она одинаковая
    TextMetrics {
        id: narrowMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: "i"
    }

    TextMetrics {
        id: wideMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: "W"
    }

    Component.onCompleted: {
        type.monospace = Math.abs(narrowMetrics.width - wideMetrics.width) < 0.6;
        type.advance = narrowMetrics.width;
    }

    // буквы основного текста
    ListModel { id: charModel }

    Repeater {
        id: charRepeater
        model: charModel

        delegate: Text {
            id: charItem

            required property string ch
            required property real pos
            required property bool fresh

            x: charItem.pos
            y: (type.height - height) / 2
            text: charItem.ch
            color: type.inSelection(charItem.index) ? type.selectionColor : type.textColor
            font.family: Fonts.panelFamily
            font.pixelSize: type.fontPixelSize
            // новая буква проявляется мягко
            opacity: charItem.fresh ? 0 : 1

            NumberAnimation on opacity {
                id: appear
                from: 0
                to: 1
                duration: type.fadeDuration
                easing.type: Easing.OutCubic
                running: charItem.fresh
            }
        }
    }

    // исчезающие буквы
    ListModel { id: ghostModel }

    Repeater {
        id: ghostRepeater
        model: ghostModel

        delegate: Text {
            required property string ch
            required property real pos

            x: ghostItem.pos
            y: (type.height - height) / 2
            text: ghostItem.ch
            color: type.textColor
            font.family: Fonts.panelFamily
            font.pixelSize: type.fontPixelSize

            NumberAnimation on opacity {
                id: fade
                from: 1
                to: 0
                duration: type.fadeDuration
                easing.type: Easing.InCubic
            }
        }
    }

    // через полсекунды призраков убираем совсем
    Timer {
        id: ghostTimer
        interval: type.fadeDuration + 40
        repeat: false
        onTriggered: ghostModel.clear()
    }

    // где сейчас каретка
    TextMetrics {
        id: caretMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: input.text.substring(0, input.cursorPosition)
    }

    Rectangle {
        id: caret
        x: type.monospace
           ? Math.min(type.advance * input.cursorPosition, type.width)
           : caretMetrics.width
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
