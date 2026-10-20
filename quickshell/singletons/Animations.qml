pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Включены ли анимации панелей, сайдбара и уведомлений.
//
// Настройки живут в ~/.config/quickshell/animations.json, их правит
// scripts/animations.py. Файл читаем с watchChanges, поэтому переключатель
// в настройках действует сразу, без перезапуска оболочки.
//
// Длительность анимации окон — это swayfx (`animation_duration_ms`), там же
// скрипт применяет её к работающему sway.
//
//   Animations.panels; Animations.sidebar; Animations.toasts
Item {
    id: root

    readonly property string file: (Quickshell.env("HOME") ?? "")
                                   + "/.config/quickshell/animations.json"

    property bool panels: true
    property bool sidebar: true
    property bool toasts: true
    property int windowMs: 180

    function apply(raw) {
        if (typeof raw === "function")
            raw = raw();
        let data = null;
        try {
            data = JSON.parse((raw || "").trim() || "{}");
        } catch (e) {
            data = null;
        }
        if (!data || typeof data !== "object")
            return;
        root.panels = data.panels !== false;
        root.sidebar = data.sidebar !== false;
        root.toasts = data.toasts !== false;
        const ms = Math.round(Number(data.window_ms));
        root.windowMs = isNaN(ms) ? 180 : ms;
    }

    FileView {
        id: settingsView
        path: root.file
        watchChanges: true
        onLoaded: root.apply(text)
        onFileChanged: settingsView.reload()
        onLoadFailed: root.apply("{}")
    }
}
