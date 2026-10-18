import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../singletons"

// Раздел «Внешний вид» меню настроек: схема оформления и обои.
//
// Начинка общая с панелью Mod+Shift+W — components/AppearanceSettings.qml.
// Сюда же дальше добавятся шрифт бара, прозрачность панелей и скругления.
ColumnLayout {
    id: page

    spacing: 12

    AppearanceSettings {
        id: appearance
        Layout.fillWidth: true
    }
}
