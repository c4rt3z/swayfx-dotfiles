import QtQuick
import "../singletons"

// Полоска-индикатор. value: 0..1
Item {
    id: b

    property real value: 0
    property color fillColor: Colors.accent
    property color trackColor: Colors.track
    property real barHeight: 6

    implicitHeight: barHeight
    implicitWidth: 200

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: b.barHeight
        radius: b.barHeight / 2
        color: b.trackColor

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, b.value))
            height: parent.height
            radius: parent.radius
            color: b.fillColor
        }
    }
}
