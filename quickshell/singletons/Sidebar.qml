pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Состояние и настройки сайдбара — панели, которая выезжает по бинду (Mod+B).
//
// Отдельный синглтон, а не свойство панели: открывать и закрывать сайдбар
// умеют и бинд (через IPC), и Esc внутри самой панели, и блокировка экрана.
//
// Настройки лежат в ~/.config/quickshell/sidebar.json и правятся страницей
// «Сайдбар» (scripts/sidebar-settings.py). Файл читаем с watchChanges, поэтому
// изменения видны сразу: side — сторона, width — доля экрана, labels — подписи
// у кнопок, grid — 2x3 или 3x2 у плиток сессии, widgets — какие блоки показывать.
//
//   Sidebar.toggle(); Sidebar.show(); Sidebar.hide()
Item {
    id: root

    property bool open: false

    readonly property string file: (Quickshell.env("HOME") ?? "")
                                   + "/.config/quickshell/sidebar.json"
    readonly property string script: (Quickshell.env("HOME") ?? "")
                                     + "/.config/quickshell/scripts/sidebar-settings.py"

    // значения по умолчанию; файла может не быть вовсе
    property var cfg: ({
        side: "left",
        width: 24,
        labels: true,
        grid: "2x3",
        widgets: { weather: true, now: true, session: true, shots: true, clipboard: true }
    })

    readonly property string side: cfg.side === "right" ? "right" : "left"
    readonly property int widthPercent: Math.max(16, Math.min(40,
                                          Math.round(Number(cfg.width) || 24)))
    readonly property bool labels: cfg.labels !== false
    readonly property string grid: cfg.grid === "3x2" ? "3x2" : "2x3"
    readonly property int gridColumns: grid === "3x2" ? 3 : 2

    function widget(name) {
        const map = root.cfg.widgets || ({});
        return map[name] !== false;
    }

    function apply(raw) {
        // в этой версии quickshell text — метод, а не свойство
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
        root.cfg = {
            side: data.side === "right" ? "right" : "left",
            width: Number(data.width) || 24,
            labels: data.labels !== false,
            grid: data.grid === "3x2" ? "3x2" : "2x3",
            widgets: data.widgets || ({})
        };
    }

    function reload() {
        stateProcess.running = true;
    }

    // перечитать настройки после правки
    function apply_soon() {
        reloadTimer.restart();
    }

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }

    // Читаем состояние скриптом, а не через FileView: так одинаково работают
    // и старт, и правка из настроек (страница зовёт apply_soon()).
    Process {
        id: stateProcess
        command: ["python3", root.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    Component.onCompleted: root.reload()

    Timer {
        id: reloadTimer
        interval: 120
        repeat: false
        onTriggered: root.reload()
    }
}
