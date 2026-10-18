import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Приложения»: тёмная или светлая тема для GTK-, KDE- и Qt-программ.
//
// Своего состояния не держим — и выключателя тоже нет: тема приложений следует
// за темой обоев. Тёмные обои (тёмная палитра) — тёмные приложения, светлые —
// светлые. Так GTK, KDE и Qt выглядят одинаково и всегда в тон.
//
// Что за чем ходит: settings.ini в ~/.config/gtk-3.0 и gtk-4.0 плюс системная
// схема org.gnome.desktop.interface color-scheme; цвета — colors.css, его
// переписывает scripts/apps-theme.py из палитры обоев; KDE-схема —
// plasma-apply-colorscheme (BreezeDark/BreezeLight); Qt берёт цвета из GTK через
// QT_QPA_PLATFORMTHEME=gtk3 (проверено замером: без переменной Qt светлый).
// Всё это делает команда sync — её зовёт генератор темы после каждой смены обоев,
// а руками можно позвать кнопкой ниже. Скрипт же пишет сводку в
// ~/.cache/quickshell/apps-theme.json.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/apps-theme.py"
    readonly property string stateFile: home + "/.cache/quickshell/apps-theme.json"

    property bool dark: false
    property bool paletteDark: false
    property string gtkTheme: ""
    property string scheme: ""
    property string accent: "#888888"
    property string qtNote: ""
    property bool qt6ct: false

    spacing: 14

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            page.dark = j.dark === true;
            page.paletteDark = j.palette_dark === true;
            page.gtkTheme = j.gtk_theme || "";
            page.scheme = j.scheme || "";
            page.accent = j.accent || "#888888";
            page.qtNote = j.qt_note || "";
            page.qt6ct = j.qt6ct === true;
        } catch (e) {
        }
    }

    // пересобрать сводку (например, если тему меняли руками или в KDE)
    Component.onCompleted: Quickshell.execDetached(["python3", page.script, "build"])

    FileView {
        id: stateView
        path: page.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse(typeof text === "function" ? text() : text)
    }

    // одна строка-галочка
    component ToggleRow: Item {
        id: row

        property string title: ""
        property string note: ""
        property bool active: false
        signal toggled()

        Layout.fillWidth: true
        implicitHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: rowHover.containsMouse ? Colors.selected : "transparent"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            CheckBox {
                checked: row.active
            }

            Label {
                text: row.title
                font.pixelSize: 12
                color: Colors.text
            }

            Label {
                Layout.fillWidth: true
                text: row.note
                font.pixelSize: 10
                color: Qt.alpha(Colors.dim, 0.75)
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggled()
        }
    }

    Label {
        text: Lang.t("Тема приложений")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        ToggleRow {
            title: Lang.t("Тема приложений следует за обоями")
            note: (page.paletteDark ? Lang.t("тёмная") : Lang.t("светлая"))
                  + " · " + page.gtkTheme + " · " + page.scheme
            active: true
            onToggled: Quickshell.execDetached(["python3", page.script, "sync"])
        }
    }

    // цвета — не галочка, а действие: подтянуть палитру обоев прямо сейчас
    Rectangle {
        Layout.preferredWidth: applyLabel.implicitWidth + 20
        Layout.preferredHeight: 26
        radius: 5
        color: applyHover.containsMouse ? Colors.selected : "transparent"
        border.width: 1
        border.color: Colors.border

        Label {
            id: applyLabel
            anchors.centerIn: parent
            text: Lang.t("Применить сейчас")
            font.pixelSize: 11
            color: Colors.text
        }

        MouseArea {
            id: applyHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["python3", page.script, "sync"])
        }
    }

    Rectangle {
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        radius: 4
        color: page.accent
        border.width: 1
        border.color: Colors.border
    }

    Label {
        text: Lang.t("Что откуда берётся")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 20
        rowSpacing: 3

        Label {
            text: "GTK"
            font.pixelSize: 11
            color: Colors.dim
        }
        Label {
            text: page.gtkTheme + ", prefer-dark=" + (page.dark ? "true" : "false")
            font.pixelSize: 11
            color: Colors.text
        }

        Label {
            text: Lang.t("Цвета GTK")
            font.pixelSize: 11
            color: Colors.dim
        }
        Label {
            text: Lang.t("colors.css из палитры обоев (копия Breeze рядом: colors.css.breeze)")
            font.pixelSize: 11
            color: Colors.text
        }

        Label {
            text: "Qt"
            font.pixelSize: 11
            color: Colors.dim
        }
        Label {
            text: page.qt6ct
                  ? "qt6ct"
                  : Lang.t("цвета из GTK: QT_QPA_PLATFORMTHEME=gtk3 (environment.d, запуск quickshell и waybar, alacritty [env])")
            font.pixelSize: 11
            color: Colors.text
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Label {
            text: "KDE"
            font.pixelSize: 11
            color: Colors.dim
        }
        Label {
            text: Lang.t("схема BreezeDark или BreezeLight (plasma-apply-colorscheme)")
            font.pixelSize: 11
            color: Colors.text
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Тема пишется в ~/.config/gtk-3.0/settings.ini и gtk-4.0/settings.ini, ")
              + Lang.t("в системную схему org.gnome.desktop.interface color-scheme и в схему KDE. ")
              + Lang.t("Смена обоев перекрашивает всё сама; уже запущенные приложения ")
              + Lang.t("подхватят тему после перезапуска.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
