// Панели quickshell для кнопок waybar.
// Управление:  qs ipc call panel toggle <имя>
// Имена панелей: volume | brightness | network | memory | battery | wallpaper
//                 | launcher | power | music | settings | emoji | search
//                 | calendar
// Сайдбар (буфер обмена, снимки, сессия): qs ipc call sidebar toggle  (Mod+B)
// Лаунчер (замена wofi) открывается на Mod+A: qs ipc call panel open launcher
// Блокировка экрана: qs ipc call lock lock|unlock   (Mod+Ctrl+L, см. lock/LockScreen.qml)
// Меню сессии: qs ipc call panel open power        (кнопка питания в углу waybar)
// Плеер:       qs ipc call panel open music         (клик по играющему треку в баре)
// Настройки:   qs ipc call panel open settings      (Mod+, — меню настроек дотфайлов)
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "panels"
import "singletons"
import "lock"
import "wallpaper"
import "sidebar"
import "toasts"

ShellRoot {
    id: root

    property string activePanel: ""
    // раздел настроек: открывается и обычным Mod+, и по ссылке
    // qs ipc call settings open weather
    property string settingsSection: "home"

    // Где курсор. sway его не отдаёт, поэтому «ловим» сами: панель эмодзи —
    // это прозрачная поверхность во весь экран, и композитор, как только она
    // появится под указателем, сразу пришлёт его координаты (см. pointerWatch
    // в PanelWindow ниже). Карточка встаёт слева-сверху от курсора, то есть
    // справа-снизу от него, как в Windows.
    // Если события почему-то нет — через 150 мс падаем на прямоугольник
    // активного окна, который пишет scripts/emoji-anchor.py.
    property bool pointerKnown: false
    // позицию дал сам указатель (а не запасной таймер): как только это так,
    // положение замирает — карточка за курсором не бегает
    property bool pointerHit: false
    property real pointerX: 0
    property real pointerY: 0

    // Виджет открыли кнопкой waybar: карточка должна встать не к правому краю
    // экрана, а по центру этой кнопки. Центр кнопки — там, где был курсор в
    // момент щелчка, поэтому позицию ловим тем же способом, что и у эмодзи
    // (полноэкранная прозрачная поверхность), только карточку ставим по центру
    // курсора и сразу под баром.
    property bool panelFromBar: false

    onActivePanelChanged: {
        if (activePanel === "emoji" || root.panelFromBar) {
            root.pointerKnown = false;
            root.pointerHit = false;
        }
        if (activePanel === "")
            root.panelFromBar = false;
    }

    Timer {
        id: nudgeCursor
        interval: 90
        repeat: false
        onTriggered: Quickshell.execDetached(["sh", "-c",
            "swaymsg 'seat - cursor move 1 0' >/dev/null 2>&1; " +
            "sleep 0.12; swaymsg 'seat - cursor move -1 0' >/dev/null 2>&1"])
    }

    // Куда ставить выбор эмодзи, если позиция курсора неизвестна: прямоугольник
    // активного окна (пишет scripts/emoji-anchor.py, его же дёргает бинд
    // Super+. перед открытием панели).
    property var anchor: ({})

    FileView {
        id: anchorView
        path: (Quickshell.env("HOME") ?? "") + "/.cache/quickshell/emoji-anchor.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                root.anchor = JSON.parse(raw || "{}");
            } catch (e) {
                root.anchor = ({});
            }
        }
    }

    IpcHandler {
        target: "panel"

        function toggle(name: string): void {
            root.panelFromBar = false;
            root.activePanel = (root.activePanel === name) ? "" : name;
        }
        function open(name: string): void {
            root.panelFromBar = false;
            root.activePanel = name;
        }
        // виджет бара: qs ipc call panel bar volume — встанет под своей кнопкой
        function bar(name: string): void {
            root.panelFromBar = true;
            root.activePanel = name;
            // sway не шлёт pointer-enter новой поверхности, пока мышь не
            // двинется, а после щелчка по бару она стоит. Сдвигаем курсор на
            // пиксель и возвращаем: полноэкранная поверхность получает
            // координаты, карточка встаёт по центру кнопки.
            nudgeCursor.restart();
        }
        function close(): void {
            root.panelFromBar = false;
            root.activePanel = "";
        }
        // проверка связи: qs ipc call panel ping
        function ping(): string {
            return "ok";
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            Lock.lock();
        }
        function unlock(): void {
            Lock.unlock();
        }
        function ping(): string {
            return "ok";
        }
    }

    // Таймер: им же удобно заводить отсчёт с бинда
    //   qs ipc call timer start 1500   (секунды)
    IpcHandler {
        target: "timer"

        function start(seconds: int): void {
            Countdown.start(seconds, Lang.t("Таймер"), Lang.t("Время вышло"));
        }
        function pause(): void {
            Countdown.pause();
        }
        function resume(): void {
            Countdown.resume();
        }
        function stop(): void {
            Countdown.stop();
        }
        function left(): string {
            return Countdown.clock;
        }
        function ping(): string {
            return "ok";
        }
    }

    // Сайдбар (Mod+B): своя поверхность слева, поэтому отдельный обработчик, а
    // не имя среди панелей.
    IpcHandler {
        target: "sidebar"

        function toggle(): void {
            Sidebar.toggle();
        }
        function open(): void {
            Sidebar.show();
        }
        function close(): void {
            Sidebar.hide();
        }
        function ping(): string {
            return "ok";
        }
    }

    // Ссылка на раздел настроек (deep-link):
    //   qs ipc call settings open weather
    // Разделы: home, appearance, language, apps, bar, weather, keys, languages,
    //          defaults, services
    IpcHandler {
        target: "settings"

        function open(section: string): void {
            root.settingsSection = section;
            root.activePanel = "settings";
        }
        function ping(): string {
            return root.settingsSection;
        }
    }

    // История буфера обмена. Отдельного пакета не требуем: wl-paste сам зовёт
    // наш скрипт на каждое новое выделение (текст или картинку), тот кладёт
    // элемент в ~/.cache/quickshell/clipboard/.
    Process {
        command: ["sh", "-c",
            "command -v wl-paste >/dev/null 2>&1 && exec wl-paste --watch python3 "
            + (Quickshell.env("HOME") ?? "") + "/.config/quickshell/scripts/clipboard.py store"]
        running: true
    }

    // Сайдбар не должен висеть поверх замка
    Connections {
        target: Lock
        function onLockedChanged() {
            if (Lock.locked)
                Sidebar.hide();
        }
    }

    // Экран блокировки: quickshell держит его поверх всего (ext-session-lock).
    // Рисует lock/LockScreen.qml, цвета — из палитры темы.
    // WlSessionLockSurface — обязательный дочерний элемент: именно он создаёт
    // запирающую поверхность на каждый экран (документация quickshell).
    WlSessionLock {
        id: sessionLock
        locked: Lock.locked
        WlSessionLockSurface {
            id: lockSurface
            // без цвета quickshell заливает поверхность белым
            color: Colors.base
            // размер контенту передаём сами: quickshell его не выставляет
            LockScreen {
                surfaceWidth: lockSurface.width
                surfaceHeight: lockSurface.height
                screenName: lockSurface.screen ? lockSurface.screen.name : ""
            }
        }
    }

    PanelWindow {
        id: win
        // loader.item === null, если имя панели неизвестно — тогда не показываем пустую карточку
        visible: root.activePanel !== "" && loader.item !== null

        // Обычные панели висят справа сверху. Лаунчер — по центру экрана,
        // плеер — по центру сверху, ровно под треком в баре, настройки — ровно
        // по центру экрана (обе оси), эмодзи — карточка у курсора.
        // По горизонтали центрирует сам композитор: right не привязан, как и
        // top для настроек — композитор центрирует ту ось, что свободна.
        readonly property bool centered: root.activePanel === "launcher"
                                         || root.activePanel === "music"
                                         || root.activePanel === "settings"
                                         || root.activePanel === "search"
                                         || root.activePanel === "calendar"
                                         || root.activePanel === "weather"
                                         || root.activePanel === "switcher"
        // эмодзи и виджеты бара: поверхность во весь экран, карточка внутри —
        // у курсора (у эмодзи справа снизу от него, у виджетов — по центру)
        readonly property bool overlay: root.activePanel !== ""
                                        && (root.activePanel === "emoji"
                                            || root.panelFromBar)
        // виджет открыт кнопкой бара: карточка встаёт по центру кнопки
        readonly property bool barAnchor: win.overlay && root.activePanel !== "emoji"
        // настройки: центр по обеим осям
        readonly property bool centering: root.activePanel === "settings"

        anchors.top: win.overlay ? true : !win.centering
        anchors.bottom: win.overlay
        anchors.left: win.overlay
        anchors.right: win.overlay ? true : !win.centered
        margins.top: win.overlay ? 0
                     : (root.activePanel === "launcher"
                        ? Math.max(40, (screenHeight - win.implicitHeight) / 2)
                        : (root.activePanel === "search" ? win.spotlightTop : 40))
        margins.bottom: 0
        margins.left: 0
        margins.right: win.overlay ? 0 : 8

        readonly property real screenHeight: Quickshell.screens.length > 0
                                             ? Quickshell.screens[0].height : 1200
        readonly property real screenWidth: Quickshell.screens.length > 0
                                            ? Quickshell.screens[0].width : 1920

        // Spotlight в macOS: окно поиска не вплотную к бару, а заметно ниже —
        // примерно на четверть экрана.
        readonly property real spotlightTop: Math.max(40, Math.round(screenHeight * 0.22))

        // 8 пикселей внутрь от угла активного окна — запасной вариант, если
        // позицию курсора узнать не получилось.
        readonly property real anchorRight: root.anchor.w !== undefined
                                            ? Math.max(8, screenWidth - (root.anchor.x + root.anchor.w) - 8)
                                            : 8
        readonly property real anchorBottom: root.anchor.h !== undefined
                                             ? Math.max(8, screenHeight - (root.anchor.y + root.anchor.h) - 8)
                                             : 8
        exclusiveZone: -1
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        // Панель эмодзи — та же поверхность qs-panel, но растянута на весь
        // экран. Чтобы блюр лёг только под карточку, а не под весь рабочий
        // стол, у "qs-panel" включён blur_ignore_transparent (см. layer_effects
        // в ~/.config/sway/config).
        WlrLayershell.namespace: "qs-panel"
        // клавиатуру забирает любая панель, кроме галереи обоев: только так
        // Esc дойдёт до панели, а не до окна под ней. Закрылась — композитор
        // вернёт фокус тому окну, где он был.
        WlrLayershell.keyboardFocus: (root.activePanel !== ""
                                      && root.activePanel !== "wallpaper")
                                     ? WlrKeyboardFocus.Exclusive
                                     : WlrKeyboardFocus.OnDemand

        // ширина карточки панели (у эмодзи поверхность во весь экран, поэтому
        // размеры окна и размеры карточки — разные вещи)
        readonly property real contentWidth: root.activePanel === "settings" ? 980
                                             : (root.activePanel === "wallpaper" ? 768
                                             : (root.activePanel === "launcher" ? 620
                                             : (root.activePanel === "music" ? 880
                                             : (root.activePanel === "emoji" ? 470
                                             : (root.activePanel === "search" ? 680
                                             : ((root.activePanel === "calendar" || root.activePanel === "weather") ? 420
                                             : (root.activePanel === "switcher" ? 700 : 380)))))))
        implicitWidth: win.overlay ? win.screenWidth : win.contentWidth
        // у эмодзи поверхность во весь экран: только так композитор скажет,
        // где курсор
        implicitHeight: win.overlay ? win.screenHeight : body.implicitHeight + 24

        function titleFor(n: string): string {
            if (n === "volume") return Lang.t("Громкость и микрофон");
            if (n === "brightness") return Lang.t("Яркость");
            if (n === "network") return Lang.t("Сеть");
            if (n === "memory") return Lang.t("Память и процессор");
            if (n === "battery") return Lang.t("Батарея");
            if (n === "wallpaper") return Lang.t("Обои и темы");
            if (n === "launcher") return Lang.t("Запуск приложений");
            if (n === "power") return Lang.t("Сессия");
            if (n === "music") return Lang.t("Плеер");
            if (n === "settings") return Lang.t("Настройки");
            if (n === "emoji") return Lang.t("Эмодзи");
            if (n === "search") return Lang.t("Поиск");
            if (n === "calendar") return Lang.t("Календарь и таймер");
            if (n === "weather") return Lang.t("Погода");
            if (n === "switcher") return Lang.t("Переключение окон");
            return "";
        }

        // Курсор: поверхность панели эмодзи появляется под указателем, и
        // композитор присылает его координаты — запоминаем и ставим карточку
        // слева-сверху от них. Клик мимо карточки закрывает панель.
        MouseArea {
            id: pointerWatch
            anchors.fill: parent
            enabled: win.overlay
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons

            // Позиция берётся один раз: карточка встаёт у курсора и дальше за
            // ним не бегает, даже если человек водит мышью.
            function note() {
                if (root.pointerHit)
                    return;
                root.pointerX = pointerWatch.mouseX;
                root.pointerY = pointerWatch.mouseY;
                root.pointerHit = true;
                root.pointerKnown = true;
            }

            onEntered: note()
            onPositionChanged: note()
            onClicked: {
                // contains() в Qt6 принимает только QPointF, поэтому сравниваем
                // координаты числами
                const mx = pointerWatch.mouseX;
                const my = pointerWatch.mouseY;
                if (mx < chrome.x || mx > chrome.x + chrome.width
                        || my < chrome.y || my > chrome.y + chrome.height)
                    root.activePanel = "";
            }
        }

        // указатель молчит — через 400 мс берём угол активного окна. Если после
        // этого указатель всё-таки отзовётся, положение поправится: карточка
        // прыгнет к курсору один раз и там останется.
        Timer {
            interval: 400
            repeat: false
            running: win.overlay && !root.pointerKnown
            onTriggered: {
                if (root.pointerHit)
                    return;
                root.pointerX = win.barAnchor ? win.screenWidth / 2
                                              : win.screenWidth - win.anchorRight;
                root.pointerY = win.barAnchor ? 44
                                              : win.screenHeight - win.anchorBottom;
                root.pointerKnown = true;
            }
        }

        Rectangle {
            id: chrome
            // эмодзи: сама поверхность во весь экран прозрачная, а карточка
            // висит у курсора
            readonly property bool floating: win.overlay

            width: chrome.floating ? win.contentWidth : win.width
            height: chrome.floating ? body.implicitHeight + 24 : win.height
            // виджет бара — по центру своей кнопки, эмодзи — справа снизу от
            // курсора
            x: chrome.floating
               ? (win.barAnchor
                  ? Math.max(8, Math.min(root.pointerX - chrome.width / 2,
                                         win.screenWidth - chrome.width - 8))
                  : Math.max(8, Math.min(root.pointerX + 18,
                                         win.screenWidth - chrome.width - 8)))
               : 0
            y: chrome.floating
               ? (win.barAnchor
                  ? Math.max(8, Math.min(root.pointerY + 2,
                                         win.screenHeight - chrome.height - 8))
                  : Math.max(8, Math.min(root.pointerY + 18,
                                         win.screenHeight - chrome.height - 8)))
               : 0
            // пока курсор не пойман, карточку не показываем: иначе она мигнёт
            // в левом верхнем углу
            visible: !chrome.floating || root.pointerKnown

            radius: 10
            color: Colors.card
            border.width: 1
            border.color: Colors.border

            // Esc закрывает любую панель, кроме галереи обоев: там Escape не
            // должен выкидывать человека из выбора. Клавиша доходит и когда
            // фокус в поле ввода — Esc поля не перехватывают, событие
            // всплывает к этому прямоугольнику.
            focus: true

            Keys.onEscapePressed: {
                if (root.activePanel !== "" && root.activePanel !== "wallpaper")
                    root.activePanel = "";
            }

            ColumnLayout {
                id: body
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: win.titleFor(root.activePanel)
                        color: Colors.text
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item {
                        implicitWidth: 22
                        implicitHeight: 22

                        Label {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            color: closeArea.containsMouse ? Colors.text : Colors.dim
                            font.pixelSize: 16
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.activePanel = ""
                        }
                    }
                }

                Loader {
                    id: loader
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    // раздел из ссылки (qs ipc call settings open weather)
                    onItemChanged: if (item && item.section !== undefined)
                                       item.section = root.settingsSection
                    sourceComponent: {
                        if (root.activePanel === "volume") return volumeComp;
                        if (root.activePanel === "brightness") return brightComp;
                        if (root.activePanel === "network") return netComp;
                        if (root.activePanel === "memory") return memComp;
                        if (root.activePanel === "battery") return batComp;
                        if (root.activePanel === "wallpaper") return wallComp;
                        if (root.activePanel === "launcher") return launchComp;
                        if (root.activePanel === "power") return powerComp;
                        if (root.activePanel === "music") return musicComp;
                        if (root.activePanel === "settings") return settingsComp;
                        if (root.activePanel === "emoji") return emojiComp;
                        if (root.activePanel === "search") return searchComp;
                        if (root.activePanel === "calendar") return calendarComp;
                        if (root.activePanel === "weather") return weatherComp;
                        if (root.activePanel === "switcher") return switcherComp;
                        return null;
                    }
                }

                Component { id: volumeComp; VolumePanel {} }
                Component { id: brightComp; BrightnessPanel {} }
                Component { id: netComp; NetworkPanel {} }
                Component { id: memComp; MemoryPanel {} }
                Component { id: batComp; BatteryPanel {} }
                Component { id: wallComp; WallpaperPicker {} }
                Component { id: launchComp; LauncherPanel {} }
                Component { id: powerComp; PowerPanel {} }
                Component { id: musicComp; MusicPanel {} }
                Component { id: settingsComp; SettingsPanel {} }
                Component { id: emojiComp; EmojiPanel {} }
                Component { id: searchComp; SearchPanel {} }
                Component { id: calendarComp; CalendarPanel {} }
                Component { id: weatherComp; WeatherPanel {} }
                Component { id: switcherComp; SwitcherPanel {} }
            }
        }
    }

    // Обои: рисуются на слое Background вместо swaybg
    WallpaperEngine {}

    // Сайдбар: своя поверхность слева, открывается по Mod+B (qs ipc call sidebar toggle)
    Sidebar {}

    // Тосты: уведомления приложений (quickshell — сам демон уведомлений)
    ToastStack {}
}
