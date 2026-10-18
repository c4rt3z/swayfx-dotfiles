import QtQuick
import "../singletons"

// Кнопка-глиф (Nerd Font) для панелей: подсвечивается при наведении,
// гаснет, если действие недоступно (available: false) — например, плеер
// не умеет повтор или перемешку.
Item {
    id: btn

    property string glyph: ""
    property int glyphSize: 15
    // включённое состояние (повтор/перемешка активны) — горит акцентом
    property bool active: false
    property bool available: true
    property color tint: Colors.text

    signal clicked()

    readonly property alias hovered: ma.containsMouse

    implicitWidth: 30
    implicitHeight: 30
    opacity: btn.available ? 1 : 0.32

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Colors.selected
        opacity: btn.hovered && btn.available ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    Label {
        anchors.centerIn: parent
        text: btn.glyph
        font.pixelSize: btn.glyphSize
        color: btn.active ? Colors.accent
                          : (btn.hovered && btn.available ? Colors.accent : btn.tint)
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (btn.available) btn.clicked()
    }
}
