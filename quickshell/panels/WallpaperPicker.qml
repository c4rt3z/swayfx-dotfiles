import QtQuick
import QtQuick.Layouts
import "../components"

// Панель «Обои и темы» (Mod+Shift+W).
//
// Отдельное окно для быстрой смены обоев и схемы. Начинка общая с разделом
// «Внешний вид» в меню настроек — components/AppearanceSettings.qml.
ColumnLayout {
    spacing: 0
    implicitHeight: appearance.implicitHeight

    AppearanceSettings {
        id: appearance
        Layout.fillWidth: true
    }
}
