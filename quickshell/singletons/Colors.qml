pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Палитра темы: готовая схема из ~/.config/wallpaper/themes либо цвета из обоев.
// Файл статический: цвета приходят из colors.json и обновляются на лету,
// без перезагрузки оболочки. Собирает — ~/.config/wallpaper/theme-render.py
Item {
    id: root

    readonly property string palettePath: (Quickshell.env("HOME") ?? "") + "/.cache/wallpaper/theme/colors.json"

    // запасная палитра, пока JSON не прочитан
    property var p: ({
        base: "#2e3440",
        surface: "#22272f",
        border: "#3a4553",
        text: "#cfd8d2",
        accent: "#9da9a0",
        onAccent: "#2e3440",
        red: "#bf616a"
    })

    // поверхности
    readonly property color base: p.base || "#2e3440"
    readonly property color surface: p.surface || "#22272f"
    readonly property color border: p.border || "#3a4553"

    // текст
    readonly property color text: p.text || "#cfd8d2"
    readonly property color dim: Qt.alpha(text, 0.5)

    // акцент
    readonly property color accent: p.accent || "#9da9a0"
    readonly property color onAccent: p.onAccent || "#2e3440"

    // тревога
    readonly property color red: p.red || "#bf616a"

    // производные
    readonly property color card: Qt.alpha(base, 0.75)
    readonly property color divider: Qt.alpha(accent, 0.22)
    readonly property color track: Qt.alpha(accent, 0.25)
    readonly property color muted: Qt.alpha(accent, 0.55)
    readonly property color selected: Qt.alpha(accent, 0.12)

    FileView {
        path: root.palettePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            raw = (raw || "").trim();
            if (raw === "") return;
            try {
                let j = JSON.parse(raw);
                if (j && j.base && j.accent && j.text) root.p = j;
            } catch (e) {
            }
        }
    }
}
