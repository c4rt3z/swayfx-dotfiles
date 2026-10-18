// Обои на слое Background — по окну на каждый монитор.
//
// Два слоя (A и B) с переходами: затухание, шторка и круг из точки клика.
// Картинки (jpg/png/webp/gif/bmp/avif) и видео (mp4/mkv/mov/webm).
//
// Управление:
//   qs ipc call wallpaper set <монитор|all> <файл> [fade|wipe|circle|circle:x:y|random]
//   qs ipc call wallpaper get [монитор]
//
// Файл обоев можно просто перетащить на рабочий стол.
// Состояние (что где стоит) хранит ~/.config/wallpaper/state.sh,
// цвета из обоев генерирует ~/.config/wallpaper/theme-gen.sh.

import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../singletons"

ShellRoot {
    id: engineRoot

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string cacheDir: home + "/.cache/wallpaper"
    readonly property string fallbackWallpaper: home + "/Wallpapers/wall.png"
    readonly property string stateScript: home + "/.config/wallpaper/state.sh"
    readonly property string themeScript: home + "/.config/wallpaper/theme-gen.sh"
    readonly property string gifScript: home + "/.config/wallpaper/gif-cache.sh"

    property var engines: ({})

    function register(name, win) {
        let m = Object.assign({}, engines);
        m[name] = win;
        engines = m;
    }
    function unregister(name) {
        let m = Object.assign({}, engines);
        delete m[name];
        engines = m;
    }
    function apply(target, path, transition) {
        if (!path)
            return;
        for (let n in engines) {
            if (target === "all" || target === "" || target === n)
                engines[n].apply(path, transition);
        }
    }
    function query(target) {
        if (target && target !== "all" && engines[target])
            return engines[target].currentPath;
        for (let n in engines)
            return engines[n].currentPath;
        return "";
    }

    IpcHandler {
        target: "wallpaper"

        function set(target: string, path: string, transition: string): void {
            engineRoot.apply(target, path, transition);
        }
        function get(target: string): string {
            return engineRoot.query(target);
        }
        function current(): string {
            return engineRoot.query("");
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: win

                required property var modelData
                screen: modelData

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: Colors.base
                focusable: false
                exclusionMode: ExclusionMode.Ignore

                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background

                readonly property string monName: win.screen ? win.screen.name : "default"
                readonly property real pxScale: win.screen && win.screen.devicePixelRatio ? win.screen.devicePixelRatio : 1
                readonly property string statePath: engineRoot.cacheDir + "/current_" + win.monName
                readonly property int fadeMs: 700
                readonly property int maskMs: 1100

                property string currentPath: ""   // что выбрал пользователь (гифка — исходник)
                property string currentMedia: ""  // что реально нарисовано (гифка — mp4 из кеша)
                property int active: 0 // 0 — слой A, 1 — слой B
                property string mediaA: ""
                property string mediaB: ""
                property bool videoA: false
                property bool videoB: false
                property real progress: 1.0
                property int ttype: 0 // 0 затухание, 1 шторка, 2 круг
                property real originX: 0.5
                property real originY: 0.5
                property bool wipeVertical: false
                property bool animating: false
                property int incoming: 1
                property bool pendingStart: false
                // переход, ждущий готовности файла (сборка гифки, загрузка картинки)
                property string pendingSource: ""
                property string pendingTrans: ""
                property bool pendingImmediate: false

                // радиус круга, который накрывает весь экран из точки перехода
                readonly property real circleRadius: {
                    let w = width;
                    let h = height;
                    if (w <= 0 || h <= 0)
                        return 2000;
                    let cx = originX * w;
                    let cy = originY * h;
                    let d1 = Math.sqrt(cx * cx + cy * cy);
                    let d2 = Math.sqrt((w - cx) * (w - cx) + cy * cy);
                    let d3 = Math.sqrt(cx * cx + (h - cy) * (h - cy));
                    let d4 = Math.sqrt((w - cx) * (w - cx) + (h - cy) * (h - cy));
                    return Math.max(Math.max(d1, d2), Math.max(d3, d4));
                }

                Component.onCompleted: {
                    engineRoot.register(win.monName, win);
                    restoreProc.running = true;
                }
                Component.onDestruction: engineRoot.unregister(win.monName)

                // --- восстановление обоев при запуске оболочки ---
                Process {
                    id: restoreProc
                    command: ["bash", engineRoot.stateScript, "get", win.monName]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let p = (this.text || "").trim();
                            if (p !== "") {
                                win.apply(p, "", true);
                            } else {
                                win.apply(engineRoot.fallbackWallpaper, "", true);
                                // первый запуск: темы ещё нет — генерируем из запасных обоев
                                Quickshell.execDetached(["bash", engineRoot.themeScript, engineRoot.fallbackWallpaper]);
                            }
                        }
                    }
                }

                // Переход стартует не по часам, а когда входящий файл готов:
                // иначе маска проедет по пустому слою, и смена обоев выглядит
                // как рывок (или не выглядит вовсе). Опрос — страховка на случай,
                // если сигнал готовности не придёт; 5 с — предел ожидания.
                Timer {
                    id: readyGuard
                    interval: 120
                    repeat: true
                    property int ticks: 0
                    onTriggered: {
                        ticks++;
                        if (win.incomingReady() || ticks > 42) {
                            stop();
                            win.startTransition();
                        }
                    }
                }

                NumberAnimation {
                    id: anim
                    target: win
                    property: "progress"
                    from: 0.0
                    to: 1.0
                    duration: win.ttype === 0 ? win.fadeMs : win.maskMs
                    easing.type: Easing.InOutCubic
                    onFinished: win.finishTransition()
                }

                function isVideo(p) {
                    let lp = String(p).toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") || lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                function isGif(p) {
                    return String(p).toLowerCase().endsWith(".gif");
                }

                // готов ли входящий слой к показу
                function incomingReady() {
                    if (win.incoming === 0 ? win.videoA : win.videoB) {
                        let l = win.incoming === 0 ? videoLoaderA : videoLoaderB;
                        return l.item !== null && l.item.ready === true;
                    }
                    let st = win.incoming === 0 ? imgA.status : imgB.status;
                    return st === Image.Ready || st === Image.Error;
                }

                // мгновенная установка без перехода (старт, восстановление)
                function showMedia(media) {
                    let p = String(media);
                    let v = win.isVideo(p);
                    if (win.active === 0) {
                        win.mediaA = p;
                        win.videoA = v;
                    } else {
                        win.mediaB = p;
                        win.videoB = v;
                    }
                    win.currentMedia = p;
                    win.animating = false;
                    win.pendingStart = false;
                    win.progress = 1.0;
                    win.incoming = win.active;
                    if (v)
                        win.playSlot(win.active);
                }

                // Выбор обоев. path — то, что выбрал пользователь; для гифки это
                // исходник, а рисовать будем собранный из неё mp4 (см. gifProc).
                // immediate — восстановление при старте, без перехода.
                function apply(path, transition, immediate) {
                    if (!path)
                        return;
                    let p = String(path).replace(/^file:\/\//, "");
                    if (immediate !== true && p === win.currentPath && !win.animating)
                        return;

                    win.currentPath = p;
                    win.pendingImmediate = immediate === true;
                    win.pendingTrans = win.pendingImmediate ? ""
                        : (transition === undefined || transition === null ? "" : String(transition));

                    if (!win.pendingImmediate) {
                        // состояние и цвета считаем по исходному файлу, а не по mp4
                        Quickshell.execDetached(["bash", engineRoot.stateScript, "set", win.monName, p]);
                        Quickshell.execDetached(["bash", engineRoot.themeScript, p]);
                    }

                    if (win.isGif(p)) {
                        win.pendingSource = p;
                        gifProc.command = ["bash", engineRoot.gifScript, p];
                        gifProc.running = true;
                        return;
                    }
                    win.pendingSource = "";
                    if (win.pendingImmediate)
                        win.showMedia(p);
                    else
                        win.render(p, win.pendingTrans);
                }

                // собственно переход: media — файл, который показываем
                function render(media, transition) {
                    let p = String(media);

                    // тип перехода
                    let spec = transition === undefined || transition === null ? "" : String(transition);
                    let t = Math.floor(Math.random() * 3);
                    let ox = -1;
                    let oy = -1;
                    if (spec.indexOf("circle") === 0) {
                        t = 2;
                        let parts = spec.split(":");
                        if (parts.length >= 3) {
                            ox = parseFloat(parts[1]);
                            oy = parseFloat(parts[2]);
                        }
                    } else if (spec === "wipe") {
                        t = 1;
                    } else if (spec === "fade") {
                        t = 0;
                    }
                    win.ttype = t;
                    win.wipeVertical = Math.random() < 0.5;
                    if (ox >= 0 && oy >= 0 && !isNaN(ox) && !isNaN(oy)) {
                        win.originX = Math.max(0, Math.min(1, ox));
                        win.originY = Math.max(0, Math.min(1, oy));
                    } else {
                        win.originX = 0.15 + Math.random() * 0.7;
                        win.originY = 0.15 + Math.random() * 0.7;
                    }

                    // новый файл уходит на второй слой, старый остаётся под ним
                    win.incoming = win.active === 0 ? 1 : 0;
                    let v = win.isVideo(p);
                    if (win.incoming === 0) {
                        win.mediaA = p;
                        win.videoA = v;
                    } else {
                        win.mediaB = p;
                        win.videoB = v;
                    }
                    win.currentMedia = p;

                    win.animating = true;
                    win.pendingStart = true;
                    win.progress = 0.0;
                    readyGuard.ticks = 0;
                    readyGuard.restart();
                    if (v)
                        win.playSlot(win.incoming);
                }

                // переход стартует, когда файл готов (или по таймеру-страховке)
                function startTransition() {
                    if (!win.pendingStart)
                        return;
                    win.pendingStart = false;
                    readyGuard.stop();
                    win.progress = 0.0;
                    anim.restart();
                }

                function finishTransition() {
                    win.animating = false;
                    win.active = win.incoming;
                    win.progress = 1.0;
                    if (win.active === 0) {
                        win.stopSlot(1);
                        win.mediaB = "";
                        win.videoB = false;
                    } else {
                        win.stopSlot(0);
                        win.mediaA = "";
                        win.videoA = false;
                    }
                }

                function playSlot(slot) {
                    let l = slot === 0 ? videoLoaderA : videoLoaderB;
                    if (l.item && l.item.play)
                        l.item.play();
                }
                function stopSlot(slot) {
                    let l = slot === 0 ? videoLoaderA : videoLoaderB;
                    if (l.item && l.item.stop)
                        l.item.stop();
                }

                // Гифка → mp4. Скрипт печатает путь к готовому видео; если не
                // собралось (нет ffmpeg) — показываем саму гифку первым кадром.
                Process {
                    id: gifProc

                    stdout: StdioCollector {
                        onStreamFinished: {
                            if (win.pendingSource === "")
                                return;
                            let media = (this.text || "").trim().split("\n")[0];
                            if (media === "" || !media.startsWith("/"))
                                media = win.pendingSource;
                            let src = win.pendingSource;
                            win.pendingSource = "";
                            if (win.pendingImmediate)
                                win.showMedia(media);
                            else if (win.currentPath === src)
                                win.render(media, win.pendingTrans);
                        }
                    }
                }

                Component {
                    id: videoLayerA
                    Item {
                        id: vitemA
                        anchors.fill: parent
                        // готовность видео для перехода: ждём, пока файл откроется
                        property bool ready: false
                        function play() {
                            playerA.play();
                        }
                        function stop() {
                            playerA.stop();
                        }

                        MediaPlayer {
                            id: playerA
                            source: win.videoA && win.mediaA ? "file://" + win.mediaA : ""
                            videoOutput: outA
                            loops: MediaPlayer.Infinite
                            onSourceChanged: vitemA.ready = false
                            onMediaStatusChanged: {
                                if (mediaStatus === MediaPlayer.EndOfMedia) {
                                    // страховка к loops: гоняем заново с начала
                                    playerA.setPosition(0);
                                    playerA.play();
                                } else if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
                                    vitemA.ready = true;
                                    if (win.videoA && win.mediaA !== "")
                                        playerA.play();
                                }
                            }
                        }
                        VideoOutput {
                            id: outA
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Component {
                    id: videoLayerB
                    Item {
                        id: vitemB
                        anchors.fill: parent
                        property bool ready: false
                        function play() {
                            playerB.play();
                        }
                        function stop() {
                            playerB.stop();
                        }

                        MediaPlayer {
                            id: playerB
                            source: win.videoB && win.mediaB ? "file://" + win.mediaB : ""
                            videoOutput: outB
                            loops: MediaPlayer.Infinite
                            onSourceChanged: vitemB.ready = false
                            onMediaStatusChanged: {
                                if (mediaStatus === MediaPlayer.EndOfMedia) {
                                    playerB.setPosition(0);
                                    playerB.play();
                                } else if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
                                    vitemB.ready = true;
                                    if (win.videoB && win.mediaB !== "")
                                        playerB.play();
                                }
                            }
                        }
                        VideoOutput {
                            id: outB
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    // --- слой A ---
                    Item {
                        id: layerA
                        anchors.fill: parent
                        readonly property bool isIncoming: win.incoming === 0

                        z: isIncoming ? 2 : 1
                        visible: win.mediaA !== ""
                        opacity: !win.animating ? 1.0 : (win.ttype === 0 ? (isIncoming ? win.progress : 1.0 - win.progress) : 1.0)

                        layer.enabled: win.animating && win.ttype !== 0 && isIncoming && win.progress < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: maskA
                            maskThresholdMin: 0.0
                            maskThresholdMax: 1.0
                            maskSpreadAtMin: 0.0
                            maskSpreadAtMax: 0.0
                        }

                        Image {
                            id: imgA
                            anchors.fill: parent
                            source: win.mediaA !== "" && !win.videoA ? "file://" + win.mediaA : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: Math.ceil(layerA.width * win.pxScale)
                            sourceSize.height: Math.ceil(layerA.height * win.pxScale)
                            onStatusChanged: {
                                if (win.pendingStart && win.incoming === 0 && (status === Image.Ready || status === Image.Error))
                                    win.startTransition();
                            }
                        }

                        Loader {
                            id: videoLoaderA
                            anchors.fill: parent
                            active: win.videoA && win.mediaA !== ""
                            visible: win.videoA
                            sourceComponent: videoLayerA
                        }
                    }

                    // --- слой B ---
                    Item {
                        id: layerB
                        anchors.fill: parent
                        readonly property bool isIncoming: win.incoming === 1

                        z: isIncoming ? 2 : 1
                        visible: win.mediaB !== ""
                        opacity: !win.animating ? 1.0 : (win.ttype === 0 ? (isIncoming ? win.progress : 1.0 - win.progress) : 1.0)

                        layer.enabled: win.animating && win.ttype !== 0 && isIncoming && win.progress < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: maskB
                            maskThresholdMin: 0.0
                            maskThresholdMax: 1.0
                            maskSpreadAtMin: 0.0
                            maskSpreadAtMax: 0.0
                        }

                        Image {
                            id: imgB
                            anchors.fill: parent
                            source: win.mediaB !== "" && !win.videoB ? "file://" + win.mediaB : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: Math.ceil(layerB.width * win.pxScale)
                            sourceSize.height: Math.ceil(layerB.height * win.pxScale)
                            onStatusChanged: {
                                if (win.pendingStart && win.incoming === 1 && (status === Image.Ready || status === Image.Error))
                                    win.startTransition();
                            }
                        }

                        Loader {
                            id: videoLoaderB
                            anchors.fill: parent
                            active: win.videoB && win.mediaB !== ""
                            visible: win.videoB
                            sourceComponent: videoLayerB
                        }
                    }

                    // --- маски переходов: белая фигура, её непрозрачность задаёт раскрытие ---
                    Item {
                        id: maskA
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerA.layer.enabled

                        Rectangle {
                            color: "white"
                            antialiasing: true
                            readonly property real rr: win.circleRadius * win.progress
                            x: win.ttype === 2 ? win.originX * maskA.width - rr : 0
                            y: win.ttype === 2 ? win.originY * maskA.height - rr : 0
                            width: win.ttype === 2 ? 2 * rr : (win.wipeVertical ? maskA.width : maskA.width * win.progress)
                            height: win.ttype === 2 ? 2 * rr : (win.wipeVertical ? maskA.height * win.progress : maskA.height)
                            radius: win.ttype === 2 ? rr : 0
                        }
                    }

                    Item {
                        id: maskB
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerB.layer.enabled

                        Rectangle {
                            color: "white"
                            antialiasing: true
                            readonly property real rr: win.circleRadius * win.progress
                            x: win.ttype === 2 ? win.originX * maskB.width - rr : 0
                            y: win.ttype === 2 ? win.originY * maskB.height - rr : 0
                            width: win.ttype === 2 ? 2 * rr : (win.wipeVertical ? maskB.width : maskB.width * win.progress)
                            height: win.ttype === 2 ? 2 * rr : (win.wipeVertical ? maskB.height * win.progress : maskB.height)
                            radius: win.ttype === 2 ? rr : 0
                        }
                    }
                }

                // перетаскивание файла на рабочий стол меняет обои
                DropArea {
                    anchors.fill: parent

                    onEntered: drag => {
                        if (!drag.hasUrls && !drag.hasText)
                            return;
                        if (typeof drag.acceptProposedAction === "function")
                            drag.acceptProposedAction();
                        drag.accepted = true;
                    }

                    onDropped: drop => {
                        let raw = "";
                        if (drop.hasUrls && drop.urls.length > 0) {
                            raw = String(drop.urls[0]);
                        } else if (drop.hasText && drop.text) {
                            raw = String(drop.text).trim().split("\n")[0];
                        }
                        if (raw === "")
                            return;
                        let p = decodeURIComponent(raw.replace(/^file:\/\//, "")).trim();
                        if (p === "")
                            return;
                        let nx = win.width > 0 ? Math.max(0, Math.min(1, drop.x / win.width)) : 0.5;
                        let ny = win.height > 0 ? Math.max(0, Math.min(1, drop.y / win.height)) : 0.5;
                        win.apply(p, "circle:" + nx.toFixed(3) + ":" + ny.toFixed(3));
                    }
                }
            }
        }
    }
}
