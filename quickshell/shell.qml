// Панели quickshell для кнопок waybar.
// Управление:  qs ipc call panel toggle <имя>
// Имена панелей: volume | brightness | network | memory | battery | wallpaper
//                 | launcher | power | music | settings | emoji
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

ShellRoot {
    id: root

    property string activePanel: ""

    // Куда ставить выбор эмодзи: справа снизу от активного окна, как в Windows.
    // Положение курсора sway не отдаёт, поэтому берём прямоугольник окна, в
    // котором человек печатает: его пишет scripts/emoji-anchor.py (его же
    // дёргает бинд Super+. перед открытием панели), а панель читает файл.
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
            root.activePanel = (root.activePanel === name) ? "" : name;
        }
        function open(name: string): void {
            root.activePanel = name;
        }
        function close(): void {
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
            }
        }
    }

    PanelWindow {
        id: win
        // loader.item === null, если имя панели неизвестно — тогда не показываем пустую карточку
        visible: root.activePanel !== "" && loader.item !== null

        // Обычные панели висят справа сверху. Лаунчер — по центру экрана,
        // плеер — по центру сверху, ровно под треком в баре, настройки — по
        // центру по горизонтали и на всю высоту контента.
        // По горизонтали центрирует сам композитор: right не привязан.
        readonly property bool centered: root.activePanel === "launcher"
                                         || root.activePanel === "music"
                                         || root.activePanel === "settings"
                                         || root.activePanel === "emoji"
                                         || root.activePanel === "search"
        anchors.top: !win.atCursor
        anchors.bottom: win.atCursor
        anchors.right: !win.centered || win.atCursor
        margins.top: root.activePanel === "launcher"
                     ? Math.max(40, (screenHeight - win.implicitHeight) / 2)
                     : (root.activePanel === "search" ? win.spotlightTop : 40)
        margins.bottom: win.anchorBottom
        margins.right: win.atCursor ? win.anchorRight : 8

        // эмодзи — справа снизу от окна, остальные центрированные панели
        // композитор центрирует сам
        readonly property bool atCursor: root.activePanel === "emoji"

        readonly property real screenHeight: Quickshell.screens.length > 0
                                             ? Quickshell.screens[0].height : 1200
        readonly property real screenWidth: Quickshell.screens.length > 0
                                            ? Quickshell.screens[0].width : 1920

        // Spotlight в macOS: окно поиска не вплотную к бару, а заметно ниже —
        // примерно на четверть экрана.
        readonly property real spotlightTop: Math.max(40, Math.round(screenHeight * 0.22))

        // 8 пикселей внутрь от угла окна, но не за экран
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
        WlrLayershell.namespace: "qs-panel"
        // клавиатуру забирает любая панель, кроме галереи обоев: только так
        // Esc дойдёт до панели, а не до окна под ней. Закрылась — композитор
        // вернёт фокус тому окну, где он был.
        WlrLayershell.keyboardFocus: (root.activePanel !== ""
                                      && root.activePanel !== "wallpaper")
                                     ? WlrKeyboardFocus.Exclusive
                                     : WlrKeyboardFocus.OnDemand

        implicitWidth: root.activePanel === "settings" ? 980
                       : (root.activePanel === "wallpaper" ? 768
                       : (root.activePanel === "launcher" ? 620
                       : (root.activePanel === "music" ? 880
                       : (root.activePanel === "emoji" ? 470
                       : (root.activePanel === "search" ? 680 : 380)))))
        implicitHeight: body.implicitHeight + 24

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
            return "";
        }

        Rectangle {
            anchors.fill: parent
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
            }
        }
    }

    // Обои: рисуются на слое Background вместо swaybg
    WallpaperEngine {}
}
