import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../singletons"
import "settings"

// Меню настроек дотфайлов: слева разделы, справа страница выбранного раздела.
//
// Открыть:  Mod+,  (см. ~/.config/sway/config)  либо вручную
//           qs ipc call panel open settings
//
// Разделы с ready: false пока только помечены «скоро» — наполняем по одному.
// Название дотфайлов и автор — в ~/.config/quickshell/settings.json.
ColumnLayout {
    id: panel

    property string section: "home"

    // высокая страница прокручивается внутри карточки, а не уезжает за её край
    readonly property real pageMaxHeight: Math.round(
        (Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1200) * 0.80)

    readonly property var sections: [
        { key: "home", name: Lang.t("Главная"), glyph: "\uf015", ready: true },
        { key: "appearance", name: Lang.t("Внешний вид"), glyph: "\uf1fc", ready: true },
        { key: "language", name: Lang.t("Язык"), glyph: "\uf1ab", ready: true },
        { key: "apps", name: Lang.t("Приложения"), glyph: "\uf108", ready: true },
        { key: "bar", name: Lang.t("Панель"), glyph: "\uf0c9", ready: true },
        { key: "sidebar", name: Lang.t("Сайдбар"), glyph: "\uf0db", ready: true },
        { key: "weather", name: Lang.t("Погода"), glyph: "\uf185", ready: true },
        { key: "keys", name: Lang.t("Клавиши"), glyph: "\uf11c", ready: true },
        { key: "languages", name: Lang.t("Раскладки"), glyph: "\uf0ac", ready: true },
        { key: "defaults", name: Lang.t("Приложения по умолчанию"), glyph: "\uf0ad", ready: true },
        { key: "services", name: Lang.t("Службы"), glyph: "\uf085", ready: true }
    ]

    spacing: 0

    RowLayout {
        id: body
        Layout.fillWidth: true
        spacing: 14

        implicitHeight: Math.max(sidebar.implicitHeight, pageScroll.height)

        // ── список разделов ─────────────────────────────────────────────────

        Column {
            id: sidebar
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 210
            spacing: 2

            Repeater {
                model: panel.sections

                delegate: Item {
                    id: entry
                    required property var modelData

                    width: sidebar.width
                    height: 30

                    readonly property bool active: panel.section === modelData.key
                    readonly property bool ready: modelData.ready

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: entry.active
                               ? Colors.selected
                               : (hover.containsMouse && entry.ready ? Colors.selected : "transparent")
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        text: entry.modelData.glyph
                        font.pixelSize: 13
                        color: entry.active
                               ? Colors.accent
                               : (entry.ready ? Colors.dim : Qt.alpha(Colors.dim, 0.45))
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 32
                        // длинные названия разделов не должны налезать на
                        // страницу справа: ширина по сайдбару + многоточие
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        elide: Text.ElideRight
                        text: entry.modelData.name
                        font.pixelSize: 12
                        color: entry.active
                               ? Colors.accent
                               : (entry.ready ? Colors.text : Qt.alpha(Colors.dim, 0.45))
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        text: Lang.t("скоро")
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.55)
                        visible: !entry.ready
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: entry.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (entry.ready)
                            panel.section = entry.modelData.key
                    }
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 1
            Layout.preferredHeight: body.implicitHeight
            color: Colors.border
        }

        // ── страница раздела ────────────────────────────────────────────────

        Flickable {
            id: pageScroll
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: Math.min(contentHeight, panel.pageMaxHeight)
            contentWidth: width
            contentHeight: page.item ? page.item.implicitHeight : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Loader {
                id: page
                width: pageScroll.width
                height: item ? item.implicitHeight : 0

                sourceComponent: {
                    if (panel.section === "home")
                        return homePage;
                    if (panel.section === "appearance")
                        return appearancePage;
                    if (panel.section === "apps")
                        return appsPage;
                    if (panel.section === "language")
                        return languagePage;
                    if (panel.section === "bar")
                        return barPage;
                    if (panel.section === "sidebar")
                        return sidebarPage;
                    if (panel.section === "weather")
                        return weatherPage;
                    if (panel.section === "sound")
                        return soundPage;
                    if (panel.section === "keys")
                        return keysPage;
                    if (panel.section === "languages")
                        return languagesPage;
                    if (panel.section === "defaults")
                        return defaultsPage;
                    if (panel.section === "services")
                        return servicesPage;
                    return null;
                }
            }
        }
    }

    // новая страница — с начала
    onSectionChanged: pageScroll.contentY = 0

    Component {
        id: homePage
        HomePage {}
    }

    Component {
        id: appearancePage
        AppearancePage {}
    }

    Component {
        id: appsPage
        AppsPage {}
    }

    Component {
        id: languagePage
        LanguagePage {}
    }

    Component {
        id: barPage
        PanelPage {}
    }

    Component {
        id: sidebarPage
        SidebarPage {}
    }

    Component {
        id: soundPage
        SoundPage {}
    }

    Component {
        id: weatherPage
        WeatherPage {}
    }

    Component {
        id: keysPage
        KeysPage {}
    }

    Component {
        id: languagesPage
        LanguagesPage {}
    }

    Component {
        id: defaultsPage
        DefaultAppsPage {}
    }

    Component {
        id: servicesPage
        ServicesPage {}
    }
}
