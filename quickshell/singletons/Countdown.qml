pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Обратный отсчёт для таймера в панели календаря.
//
// Живёт отдельно от панели: панель можно закрыть, отсчёт продолжится, а по
// нулю прилетит уведомление. Подписи уведомления передаёт панель (их берёт
// Lang.qml), поэтому сам синглтон словари не читает.
//
//   Countdown.start(1500, "Таймер", "Время вышло")   — 25 минут в секундах
//   Countdown.pause(); Countdown.resume(); Countdown.stop()
Item {
    id: root

    property int totalSec: 0        // сколько задали
    property real endsAt: 0         // когда закончится (Date.now()), 0 — не идёт
    property bool paused: false
    property real leftMs: 0         // остаток в миллисекундах
    property bool finished: false   // отсчёт закончился и ждёт сброса
    property string title: ""
    property string body: ""

    readonly property bool active: endsAt > 0
    readonly property bool running: active && !paused
    readonly property int leftSec: Math.max(0, Math.ceil(leftMs / 1000))
    readonly property real progress: totalSec > 0
        ? Math.max(0, Math.min(1, leftMs / (totalSec * 1000))) : 0
    // «25:00» или «1:05:00» — как в будильниках
    readonly property string clock: {
        const s = leftSec;
        const hh = Math.floor(s / 3600);
        const mm = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        if (hh > 0)
            return hh + ":" + String(mm).padStart(2, "0") + ":" + String(ss).padStart(2, "0");
        return mm + ":" + String(ss).padStart(2, "0");
    }

    function start(seconds, t, b) {
        if (seconds <= 0)
            return;
        totalSec = Math.round(seconds);
        title = t || "";
        body = b || "";
        finished = false;
        paused = false;
        leftMs = totalSec * 1000;
        endsAt = Date.now() + leftMs;
        tick.restart();
    }

    function pause() {
        if (!active || paused)
            return;
        leftMs = Math.max(0, endsAt - Date.now());
        paused = true;
        tick.stop();
    }

    function resume() {
        if (!active || !paused)
            return;
        endsAt = Date.now() + leftMs;
        paused = false;
        tick.restart();
    }

    function stop() {
        tick.stop();
        endsAt = 0;
        paused = false;
        finished = false;
        leftMs = 0;
        totalSec = 0;
    }

    Timer {
        id: tick
        interval: 250
        repeat: true
        running: root.active && !root.paused
        onTriggered: {
            root.leftMs = Math.max(0, root.endsAt - Date.now());
            if (root.leftMs > 0)
                return;
            root.endsAt = 0;
            root.paused = false;
            root.finished = true;
            root.leftMs = 0;
            Quickshell.execDetached(["notify-send", root.title, root.body]);
        }
    }
}
