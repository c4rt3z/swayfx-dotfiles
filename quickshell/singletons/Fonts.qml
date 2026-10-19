pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Шрифты интерфейса: общий и переопределения для панелей и waybar.
//
// Настройки — в ~/.config/quickshell/fonts.json (пишет scripts/fonts.py,
// страница «Внешний вид»). Файл читаем с watchChanges: выбор шрифта в настройках
// применяется сразу, без перезапуска оболочки.
//
// Пустая строка = «взять общий шрифт»; если и общий пуст — стандартный
// JetBrainsMono Nerd Font (в нём есть иконки, которые рисует бар).
Item {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string configPath: home + "/.config/quickshell/fonts.json"
    readonly property string defaultFamily: "JetBrainsMono Nerd Font"

    property string ui: ""
    property string panels: ""
    property string waybar: ""

    // тексты в панелях quickshell
    readonly property string panelFamily: panels !== "" ? panels
                                         : (ui !== "" ? ui : defaultFamily)
    // CSS waybar (сам CSS собирает theme-render.py, здесь — для подсказок)
    readonly property string waybarFamily: waybar !== "" ? waybar
                                          : (ui !== "" ? ui : defaultFamily)

    function parse(raw) {
        let data = ({});
        try {
            const parsed = JSON.parse(raw || "{}");
            if (parsed && typeof parsed === "object")
                data = parsed;
        } catch (e) {
            data = ({});
        }
        root.ui = String(data.ui || "");
        root.panels = String(data.panels || "");
        root.waybar = String(data.waybar || "");
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        onLoaded: root.parse(file.text())
        onLoadFailed: root.parse("")
        onFileChanged: reload()
    }
}
