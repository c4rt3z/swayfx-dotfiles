pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Всплывающие уведомления: quickshell сам выступает демоном уведомлений
// (org.freedesktop.Notifications), поэтому отдельный dunst/swaync не нужен.
//
// Здесь только приём и список живых тостов; как они выглядят и когда гаснут —
// toasts/ToastStack.qml. Приложение запускается один раз на сессию, а если
// оболочка перезапустится, keepOnReload сохранит очередь.
Item {
    id: root

    // живые тосты: { n: Notification, key: строка }
    property var live: []

    // история последних уведомлений — её показывает сайдбар
    property var history: []
    readonly property int maxHistory: 24

    // больше четырёх карточек одновременно держать незачем
    readonly property int maxVisible: 4

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true

        onNotification: notification => root.push(notification)
    }

    function push(n) {
        if (!n)
            return;
        // помечаем «занято»: иначе сервер сам закроет уведомление по таймауту
        // раньше, чем мы успеем его показать
        n.tracked = true;
        const entry = { n: n, key: "n" + n.id + "-" + Date.now() };
        const list = root.live.filter(e => e.n !== n);
        list.unshift(entry);
        root.live = list.slice(0, root.maxVisible);
        // в историю кладём текст: сам объект уведомления живёт недолго
        root.history = [{
            app: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            time: Date.now()
        }].concat(root.history).slice(0, root.maxHistory);
        n.closed.connect(function () {
            root.remove(n);
        });
    }

    // Уведомление сначала гаснет (этим занимается тост), и только потом
    // уходит из списка — иначе карточка исчезала бы мгновенно.
    function remove(n) {
        root.live = root.live.map(e => e.n === n
                                      ? Object.assign({}, e, { leaving: true })
                                      : e);
        leaveTimer.restart();
    }

    Timer {
        id: leaveTimer
        interval: 280
        repeat: false
        onTriggered: root.live = root.live.filter(e => !e.leaving);
    }

    // Esc в панелях и кнопка в тосте зовут это
    function drop(n) {
        root.remove(n);
        if (n)
            n.dismiss();
    }

    function clear() {
        const list = root.live.slice();
        root.live = [];
        for (const e of list)
            e.n.dismiss();
    }
}
