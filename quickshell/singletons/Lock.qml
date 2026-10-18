pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Блокировка экрана. Запирает/отпирает quickshell (WlSessionLock), экран рисует
// lock/LockScreen.qml. Клавиша: Mod+Ctrl+L (или авто-блокировка по таймауту).
//
//   Lock.lock()    — запереть сессию
//   Lock.unlock()  — отпереть
//   Lock.fail()    — сообщение об ошибке + тряска экрана
Item {
    id: root

    property bool locked: false
    property bool busy: false
    property int attempts: 0
    property string message: ""
    property bool messageIsError: false

    readonly property string stateFile: (Quickshell.env("HOME") ?? "")
                                       + "/.cache/quickshell/lock.state"

    // сбрасываем всё при новом запирании, чтобы не светить прошлую ошибку
    onLockedChanged: if (locked) reset()

    function reset() {
        busy = false;
        attempts = 0;
        message = "";
        messageIsError = false;
    }

    // Протокол блокировки намеренно оставляет экран запертым, если клиент упал:
    // сессию нельзя вывести из-под замка. Флаг на диске нужен, чтобы
    // перезапущенный quickshell (watchdog поднимает его за ~15 с) запрёл сессию
    // снова — тогда её можно отпереть паролем, а не перезапускать сессию.
    function lock() {
        locked = true;
        Quickshell.execDetached(["sh", "-c", "date +%s > '" + stateFile + "'"]);
    }

    function unlock() {
        locked = false;
        Quickshell.execDetached(["sh", "-c", "rm -f '" + stateFile + "'"]);
    }

    function fail(msg) {
        busy = false;
        attempts += 1;
        message = msg;
        messageIsError = true;
    }

    function note(msg) {
        busy = false;
        message = msg;
        messageIsError = false;
    }

    function checking() {
        busy = true;
        message = "";
        messageIsError = false;
    }

    function clearMessage() {
        message = "";
        messageIsError = false;
    }

    // восстановление: сессия осталась запертой после падения quickshell
    Process {
        id: restoreProc
        command: ["sh", "-c", "if [ -f '" + stateFile + "' ]; then "
                  + "echo $(( $(date +%s) - $(cat '" + stateFile + "') )); fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const age = parseInt((text || "").trim(), 10);
                if (!isNaN(age) && age >= 0 && age < 1800)
                    root.locked = true;
            }
        }
        Component.onCompleted: running = true
    }
}
