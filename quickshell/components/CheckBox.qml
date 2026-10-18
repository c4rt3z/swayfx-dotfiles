import QtQuick
import "../singletons"

// Квадратик-флажок для меню настроек: никаких пилюль, просто рамка,
// залитая акцентом, когда включено.
Rectangle {
    id: box

    property bool checked: false

    implicitWidth: 15
    implicitHeight: 15
    radius: 3
    color: box.checked ? Colors.accent : "transparent"
    border.width: 1
    border.color: box.checked ? Colors.accent : Colors.border
}
