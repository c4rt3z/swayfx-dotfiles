import QtQuick
import "../singletons"

// Ползунок. Значение задаётся снаружи через value, наружу отдаёт сигнал moved(v).
Item {
    id: s

    property real value: 0
    property real from: 0
    property real to: 100
    property color fillColor: Colors.accent
    property color trackColor: Colors.track
    property color handleColor: Colors.text
    property alias dragging: ma.dragging

    signal moved(real v)

    implicitHeight: 26
    implicitWidth: 200

    function ratio(): real {
        if (s.to === s.from) return 0;
        return Math.max(0, Math.min(1, (s.value - s.from) / (s.to - s.from)));
    }

    function applyAt(mx: real): void {
        const w = Math.max(1, s.width);
        s.moved(s.from + (s.to - s.from) * Math.max(0, Math.min(1, mx / w)));
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: s.trackColor

        Rectangle {
            width: parent.width * s.ratio()
            height: parent.height
            radius: parent.radius
            color: s.fillColor
        }
    }

    Rectangle {
        width: 12
        height: 12
        radius: 6
        color: s.handleColor
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(s.width - width, s.width * s.ratio() - width / 2))
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true

        // Своя метка тяги, а не MouseArea.pressed: если отпустить кнопку вне панели,
        // событие отпускания теряется и Qt навсегда считает кнопку зажатой —
        // именно из-за этого ползунок "прилипал" к курсору.
        property bool dragging: false

        onPressed: (mouse) => {
            ma.dragging = true;
            s.applyAt(mouse.x);
        }
        onPositionChanged: (mouse) => {
            if (ma.dragging && ma.containsMouse) s.applyAt(mouse.x);
        }
        onReleased: ma.dragging = false
        onCanceled: ma.dragging = false
    }

    // Страховка на случай потерянного отпускания: как только курсор ушёл с ползунка,
    // тяга прекращается (с небольшим запасом времени).
    Timer {
        interval: 250
        running: ma.dragging
        repeat: true
        onTriggered: if (!ma.containsMouse) ma.dragging = false
    }
}
