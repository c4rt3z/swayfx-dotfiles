import QtQuick
import "../singletons"

// Поле ввода с плавной кареткой и мягким появлением букв.
//
// Внутри — обычный TextInput, поэтому ввод, выделение и буфер обмена
// остаются родными; текст мы рисуем сами, чтобы буквы могли проявляться
// по одной.
//
//   • каретка своя, плавно переезжает на новое место (как в свежем Word);
//   • новая буква проявляется мягким fade, удалённая — гаснет;
//   • ничего не перекрывается: буквы стоят на своих местах (ширины берём
//     по метрикам, поэтому работает и с пропорциональным шрифтом).
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
    property string oldText: ""
    // строка, для которой меряем ширины букв
    property string probeText: ""

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

    // ширина буквы: у пропорционального шрифта у каждой своя
    function charWidth(i) {
        const item = widthProbe.itemAt(i);
        return item ? item.width : type.advance;
    }

    // применить новый текст: новые буквы проявляются, удалённые гаснут
    function applyText(newText) {
        const old = type.oldText;
        type.oldText = newText;
        type.probeText = newText;

        const common = Math.min(old.length, newText.length);

        // пропавшие буквы — в призраки, они гаснут на своих местах
        if (newText.length < old.length) {
            let gx = 0;
            for (let i = 0; i < newText.length; i++)
                gx += type.charWidth(i);
            for (let i = newText.length; i < old.length; i++) {
                ghostModel.append({ ch: old.charAt(i), pos: gx });
                gx += type.charWidth(i);
            }
            ghostTimer.restart();
        }

        // оставшиеся обновляем на месте
        for (let i = 0; i < common; i++) {
            if (charModel.count > i)
                charModel.setProperty(i, "ch", newText.charAt(i));
        }

        // новые буквы — с нулевой прозрачностью, чтобы мягко проявиться
        let pos = 0;
        for (let i = 0; i < common; i++)
            pos += type.charWidth(i);
        for (let i = common; i < newText.length; i++) {
            charModel.append({ ch: newText.charAt(i), pos: pos });
            pos += type.charWidth(i);
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
        color: "transparent"
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

    // ширина одного символа — запасной вариант, если метрики ещё не готовы
    TextMetrics {
        id: narrowMetrics
        font.family: Fonts.panelFamily
        font.pixelSize: type.fontPixelSize
        text: "i"
    }

    Component.onCompleted: type.advance = narrowMetrics.width

    // скрытые метрики каждой буквы: по ним считаем позиции символов
    Repeater {
        id: widthProbe
        model: type.probeText

        delegate: TextMetrics {
            font.family: Fonts.panelFamily
            font.pixelSize: type.fontPixelSize
            text: modelData
        }
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

            x: charItem.pos
            y: (type.height - height) / 2
            text: charItem.ch
            color: type.inSelection(charItem.index) ? type.selectionColor : type.textColor
            font.family: Fonts.panelFamily
            font.pixelSize: type.fontPixelSize

            // Новая буква проявляется с нуля: анимация ведёт своё свойство,
            // а прозрачность следует за ним.
            property real shade: 0
            opacity: charItem.shade

            Component.onCompleted: appear.start()

            NumberAnimation {
                id: appear
                target: charItem
                property: "shade"
                from: 0
                to: 1
                duration: type.fadeDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    // исчезающие буквы
    ListModel { id: ghostModel }

    Repeater {
        id: ghostRepeater
        model: ghostModel

        delegate: Text {
            id: ghostItem

            required property string ch
            required property real pos

            x: ghostItem.pos
            y: (type.height - height) / 2
            text: ghostItem.ch
            color: type.textColor
            font.family: Fonts.panelFamily
            font.pixelSize: type.fontPixelSize

            // Буква гаснет на своём месте и только потом убирается
            property real shade: 1
            opacity: ghostItem.shade

            Component.onCompleted: fade.start()

            NumberAnimation {
                id: fade
                target: ghostItem
                property: "shade"
                from: 1
                to: 0
                duration: type.fadeDuration
                easing.type: Easing.InCubic
            }
        }
    }

    // через fadeDuration призраков убираем совсем
    Timer {
        id: ghostTimer
        interval: type.fadeDuration + 40
        repeat: false
        onTriggered: ghostModel.clear()
    }

    // где сейчас каретка: сумма ширин букв до позиции курсора
    property real caretX: {
        let x = 0;
        for (let i = 0; i < input.cursorPosition; i++)
            x += type.charWidth(i);
        return x;
    }

    Rectangle {
        id: caret
        x: Math.min(type.caretX, type.width)
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
