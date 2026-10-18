import QtQuick
import QtQuick.Layouts
import "../components"
import "../singletons"

// Громкость вывода и микрофон — в одной панели (кнопка звука в waybar).
ColumnLayout {
    spacing: 12

    AudioPanel {
        sectionTitle: Lang.t("Вывод")
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    AudioPanel {
        sectionTitle: Lang.t("Микрофон")
        forSource: true
    }
}
