pragma Singleton
import QtQuick
import Quickshell

// Таймеры: их может быть несколько сразу.
//
// Живут отдельно от панели: панель можно закрыть, отсчёт продолжится, а по
// нулю прилетит уведомление. Подписи уведомления передаёт панель (их берёт
// Lang.qml), поэтому сам синглтон словари не читает.
//
//   Countdown.start(1500, "Таймер", "Время вышло")  — 25 минут в секундах
//   Countdown.pause(id); Countdown.resume(id); Countdown.stop(id)
Item {
    id: root

    // список таймеров: { id, totalSec, endsAt, paused, leftMs, clock,
    //                    progress, title, body, finished }
    property var timers: []
    property int nextId: 1
    readonly property int maxTimers: 6

    function start(seconds, t, b) {
        if (seconds <= 0)
            return -1;
        if (root.timers.length >= root.maxTimers)
            return -1;
        const total = Math.round(seconds);
        const timer = {
            id: root.nextId++,
            totalSec: total,
            title: t || "",
            body: b || "",
            endsAt: Date.now() + total * 1000,
            paused: false,
            leftMs: total * 1000,
            clock: root.clockOf(total),
            progress: 1,
            finished: false
        };
        root.timers = root.timers.concat([timer]);
        return timer.id;
    }

    function stop(id) {
        root.timers = root.timers.filter(t => t.id !== id);
    }

    function pause(id) {
        root.timers = root.timers.map(t => {
            if (t.id !== id || t.paused || t.finished)
                return t;
            return Object.assign({}, t, {
                paused: true,
                leftMs: Math.max(0, t.endsAt - Date.now())
            });
        });
    }

    function resume(id) {
        root.timers = root.timers.map(t => {
            if (t.id !== id || !t.paused)
                return t;
            return Object.assign({}, t, {
                paused: false,
                endsAt: Date.now() + t.leftMs
            });
        });
    }

    // «25:00» или «1:05:00» — как в будильниках
    function clockOf(seconds) {
        const s = Math.max(0, Math.round(seconds));
        const hh = Math.floor(s / 3600);
        const mm = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        if (hh > 0)
            return hh + ":" + String(mm).padStart(2, "0") + ":" + String(ss).padStart(2, "0");
        return mm + ":" + String(ss).padStart(2, "0");
    }

    Timer {
        id: tick
        interval: 250
        repeat: true
        running: root.timers.length > 0
        onTriggered: {
            const now = Date.now();
            const done = [];
            const list = root.timers.map(t => {
                if (t.paused || t.finished)
                    return t;
                const left = Math.max(0, t.endsAt - now);
                if (left === 0) {
                    done.push(t);
                    return Object.assign({}, t, {
                        leftMs: 0, endsAt: 0, finished: true,
                        clock: "00:00", progress: 0
                    });
                }
                return Object.assign({}, t, {
                    leftMs: left,
                    clock: root.clockOf(Math.ceil(left / 1000)),
                    progress: Math.max(0, Math.min(1, left / (t.totalSec * 1000)))
                });
            });
            root.timers = list;
            for (const t of done)
                Quickshell.execDetached(["notify-send", t.title, t.body]);
        }
    }
}
