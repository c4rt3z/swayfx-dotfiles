import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Панель плеера: слева обложка, трек и кнопки управления, справа текст песни.
// Открывается кликом по играющему треку в центре waybar.
//
// Данные — playerctl (scripts/player-state.sh), текст — scripts/lyrics.sh
// (lrclib.net: синхронизированный LRC, когда он есть у трека).
ColumnLayout {
    id: music

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string stateScript: home + "/.config/quickshell/scripts/player-state.sh"
    readonly property string lyricsScript: home + "/.config/quickshell/scripts/lyrics.sh"

    // ── трек ────────────────────────────────────────────────────────────────
    property string title: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    property real lengthSec: 0
    property real positionSec: 0     // последнее, что отдал плеер
    property real basePos: 0         // якорь: позиция из свежего обновления плеера
    property double baseMs: 0        // когда этот якорь пришёл (Date.now())
    property real shownPos: 0        // что показываем: якорь + локальные часы
    property string status: ""
    property string shuffle: ""
    property string loop: ""

    readonly property bool hasTrack: title !== ""
    readonly property bool playing: status === "Playing"
    readonly property bool canLoop: loop !== ""
    readonly property bool canShuffle: shuffle !== ""

    // ── текст песни ─────────────────────────────────────────────────────────
    property string lyricsKey: ""
    property var lyrics: []
    property bool lyricsSynced: false
    property int currentLine: -1
    property string lyricsState: "loading"
    property bool lyricsEnabled: false
    property double lastScrollMs: 0   // когда пользователь листал текст сам

    // ── помощники ───────────────────────────────────────────────────────────

    // playerctl принимает команды с аргументами («loop Playlist»), поэтому
    // строку разбиваем: иначе playerctl получит её одной штукой и не поймёт.
    function cmd(action) {
        Quickshell.execDetached(["playerctl"].concat(action.split(" ")));
    }

    function seekToRatio(ratio) {
        const sec = Math.max(0, Math.min(1, ratio)) * music.lengthSec;
        music.basePos = sec;
        music.baseMs = Date.now();
        music.shownPos = sec;
        Quickshell.execDetached(["playerctl", "position", String(Math.round(sec))]);
    }

    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec || 0));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    // ── разбор данных плеера ────────────────────────────────────────────────

    function parse(raw) {
        const parts = raw.split("\t");
        if (parts.length < 7)
            return;
        music.title = parts[0] || "";
        music.artist = parts[1] || "";
        music.album = parts[2] || "";
        // длительность и позиция приходят в микросекундах
        music.lengthSec = (parseFloat(parts[3]) || 0) / 1000000;
        music.artUrl = parts[4] || "";
        music.status = parts[6] || "";
        music.shuffle = parts[7] || "";
        music.loop = parts[8] || "";
        music.positionSec = (parseFloat(parts[5]) || 0) / 1000000;
        music.anchor(music.positionSec);

        const key = music.title + "|" + music.artist;
        if (key !== music.lyricsKey) {
            music.lyricsKey = key;
            music.loadLyrics();
        }
        music.updateLine();
    }

    // Позиция MPRIS приходит рывками: limusic обновляет её раз в ~3 секунды, а
    // между обновлениями значение замирает. Поэтому каждое новое значение
    // принимаем как «столько было в момент обновления» и дальше считаем время
    // локальными часами. Замороженное значение игнорируем — иначе подсветка
    // откатывалась бы назад и болталась вверх-вниз, вместо того чтобы идти вниз.
    // Резкий скачок (±1.5 с) — это перемотка или смена трека: тогда прыгаем.
    function anchor(sec) {
        // baseMs === 0 — якоря ещё нет: тогда «то же значение» ничего не значит,
        // иначе на позиции ровно 0 (начало трека) часы уходили в бесконечность.
        const hadAnchor = music.baseMs > 0;
        if (hadAnchor && music.basePos === sec)
            return;
        const estimate = music.basePos + (Date.now() - music.baseMs) / 1000;
        music.basePos = sec;
        music.baseMs = Date.now();
        if (!hadAnchor || Math.abs(sec - estimate) > 1.5 || !music.playing)
            music.shownPos = sec;
    }

    // Часы панели: пока играет, позиция идёт вперёд и только вперёд. Назад её
    // сдвигает лишь anchor (перемотка) или смена трека.
    function tick() {
        if (music.playing && music.baseMs > 0) {
            const estimate = music.basePos + (Date.now() - music.baseMs) / 1000;
            if (estimate > music.shownPos)
                music.shownPos = music.lengthSec > 0
                                 ? Math.min(music.lengthSec, estimate)
                                 : estimate;
        }
        music.updateLine();
    }

    // плеер пропал (закрыли плеер или встал на стоп) — чистим панель,
    // иначе останутся висеть данные последнего трека
    function clearTrack() {
        if (!music.hasTrack)
            return;
        music.title = "";
        music.artist = "";
        music.album = "";
        music.artUrl = "";
        music.lengthSec = 0;
        music.positionSec = 0;
        music.basePos = 0;
        music.baseMs = 0;
        music.shownPos = 0;
        music.status = "";
        music.shuffle = "";
        music.loop = "";
        music.lyrics = [];
        music.lyricsSynced = false;
        music.currentLine = -1;
        music.lyricsKey = "";
        music.lyricsState = "none";
    }

    // ── текст песни ─────────────────────────────────────────────────────────

    // "[01:23.45]строка" -> секунды; строки без метки считаем простым текстом
    function parseLyrics(raw) {
        const out = [];
        raw.split("\n").forEach(line => {
            line = line.trim();
            if (line === "")
                return;
            const m = line.match(/^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/);
            if (m)
                out.push({ t: parseInt(m[1], 10) * 60 + parseFloat(m[2]), text: m[3].trim() });
            else
                out.push({ t: -1, text: line });
        });
        music.lyrics = out;
        music.lyricsSynced = out.some(l => l.t >= 0);
        music.lyricsState = out.length > 0 ? "ok" : "none";
        music.updateLine();
        // после раскладки строк доводим текст до текущей: иначе видно прыжок
        // от начала песни
        Qt.callLater(function() { music.updateLine(); });
    }

    function loadLyrics() {
        music.lyrics = [];
        music.lyricsSynced = false;
        music.currentLine = -1;
        if (!music.lyricsEnabled) {
            music.lyricsState = "off";
            return;
        }
        music.lyricsState = "loading";
        lyricsProc.command = ["sh", music.lyricsScript, music.title, music.artist];
        lyricsProc.running = true;
    }

    // подсвечиваем строку по текущей позиции
    function updateLine() {
        let idx = -1;
        for (let i = 0; i < music.lyrics.length; i++) {
            if (music.lyrics[i].t >= 0 && music.lyrics[i].t <= music.shownPos)
                idx = i;
        }
        music.currentLine = idx;

        // ведём текст за песней, но не мешаем, если пользователь листает сам
        if (idx < 0 || Date.now() - music.lastScrollMs < 4000)
            return;
        // ищем делегат именно с этим номером: в children лежит ещё и Repeater
        const kids = lyricsColumn.children;
        let item = null;
        for (let k = 0; k < kids.length; k++) {
            if (kids[k].index === idx) {
                item = kids[k];
                break;
            }
        }
        if (!item)
            return;
        const target = item.y + item.height / 2 - lyricsView.height / 2;
        lyricsView.contentY = Math.max(0, Math.min(target,
            Math.max(0, lyricsView.contentHeight - lyricsView.height)));
    }

    // ── источники данных ────────────────────────────────────────────────────

    Process {
        id: pollProc
        command: [music.stateScript]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (raw === "")
                    music.clearTrack();
                else
                    music.parse(raw);
            }
        }
    }

    // Опрос плеера. Чаще, чем раз в секунду: позиция MPRIS обновляется рывками
    // (у limusic раз в ~3 с), и чем раньше мы поймаем новое значение, тем точнее
    // подсветка. Панель открыта не всегда, так что это не накладно.
    Timer {
        interval: 400
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!pollProc.running) pollProc.running = true
    }

    // Часы панели: полоска и подсветка идут ровно, а не рывками опроса.
    Timer {
        interval: 150
        running: music.hasTrack
        repeat: true
        onTriggered: music.tick()
    }

    Process {
        id: lyricsProc
        stdout: StdioCollector { onStreamFinished: music.parseLyrics(text) }
    }

    // если скрипт текстов удалили — панель честно скажет, что источник отключён
    FileView {
        path: music.lyricsScript
        onFileChanged: reload()
        onLoaded: music.lyricsEnabled = true
    }

    // ── интерфейс ───────────────────────────────────────────────────────────

    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        // ── левая часть: обложка, трек, управление ──────────────────────────
        ColumnLayout {
            // ширину держим жёстко: иначе колонка растягивается на пол-панели
            Layout.preferredWidth: 240
            Layout.minimumWidth: 240
            Layout.maximumWidth: 240
            spacing: 8

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 240

                Rectangle {
                    id: artBox
                    anchors.fill: parent
                    radius: 8
                    color: Colors.surface
                    border.width: 1
                    border.color: Colors.border
                    clip: true

                    Image {
                        id: artImage
                        anchors.fill: parent
                        asynchronous: true
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        source: music.artUrl
                        visible: status === Image.Ready
                    }

                    // пока обложки нет — буква трека (или нота, если не играет)
                    Label {
                        anchors.centerIn: parent
                        visible: artImage.status !== Image.Ready
                        text: music.hasTrack ? music.title.charAt(0).toUpperCase() : "\u266A"
                        color: Colors.dim
                        font.pixelSize: music.hasTrack ? 64 : 34
                    }

                    // наведение: притемняем и показываем «пауза/продолжить»
                    Rectangle {
                        anchors.fill: parent
                        radius: artBox.radius
                        color: Colors.base
                        opacity: artArea.containsMouse && music.hasTrack ? 0.45 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: artArea.containsMouse && music.hasTrack
                        text: music.playing ? "\uF04C" : "\uF04B"
                        color: Colors.text
                        font.pixelSize: 34
                    }
                }

                MouseArea {
                    id: artArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (music.hasTrack) music.cmd("play-pause")
                }
            }

            Label {
                Layout.fillWidth: true
                text: music.hasTrack ? music.title : Lang.t("Ничего не играет")
                color: music.hasTrack ? Colors.text : Colors.dim
                font.pixelSize: 16
                font.bold: true
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                visible: music.artist !== ""
                text: music.artist
                color: Colors.text
                opacity: 0.8
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                visible: music.album !== ""
                text: music.album
                color: Colors.dim
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            // полоска трека: клик — перемотка, при наведении появляется бегунок
            Item {
                id: seek
                Layout.fillWidth: true
                implicitHeight: 18

                readonly property real ratio: music.lengthSec > 0
                                              ? Math.max(0, Math.min(1, music.shownPos / music.lengthSec))
                                              : 0

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Colors.track
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: seekTrack.width * seek.ratio
                    height: 4
                    radius: 2
                    color: Colors.accent
                }
                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: Colors.text
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(seek.width - width, seek.width * seek.ratio - width / 2))
                    visible: seekArea.containsMouse
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: mouse => music.seekToRatio(mouse.x / width)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: music.fmtTime(music.shownPos)
                    color: Colors.dim
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: music.fmtTime(music.lengthSec)
                    color: Colors.dim
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                IconButton {
                    glyph: "\uF049"
                    available: music.hasTrack
                    onClicked: music.cmd("previous")
                }

                // пауза/продолжить — акцентная кнопка, она тут главная
                Item {
                    implicitWidth: 38
                    implicitHeight: 30
                    opacity: music.hasTrack ? 1 : 0.35

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: Colors.accent
                        opacity: playArea.containsMouse && music.hasTrack ? 0.85 : 1
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: music.playing ? "\uF04C" : "\uF04B"
                        color: Colors.onAccent
                        font.pixelSize: 17
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (music.hasTrack) music.cmd("play-pause")
                    }
                }

                IconButton {
                    glyph: "\uF050"
                    available: music.hasTrack
                    onClicked: music.cmd("next")
                }
                IconButton {
                    glyph: "\uF04D"
                    available: music.hasTrack
                    onClicked: music.cmd("stop")
                }

                Item { implicitWidth: 6 }

                // повтор: None -> Playlist -> Track -> None
                IconButton {
                    id: loopBtn
                    glyph: "\uF01E"
                    active: music.canLoop && music.loop !== "None"
                    available: music.hasTrack && music.canLoop
                    onClicked: music.cmd(music.loop === "None" ? "loop Playlist"
                                        : (music.loop === "Playlist" ? "loop Track" : "loop None"))
                }

                // вперемешку
                IconButton {
                    id: shufBtn
                    glyph: "\uF074"
                    active: music.shuffle === "On"
                    available: music.hasTrack && music.canShuffle
                    onClicked: music.cmd("shuffle Toggle")
                }
            }

            // высота зарезервирована, чтобы от подсказки ничего не прыгало
            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                horizontalAlignment: Text.AlignHCenter
                text: loopBtn.hovered && !loopBtn.available ? Lang.t("плеер не отдаёт повтор")
                      : (shufBtn.hovered && !shufBtn.available ? Lang.t("плеер не отдаёт перемешку") : "")
                color: Colors.dim
                opacity: 0.7
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Colors.divider
        }

        // ── правая часть: текст песни ───────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: Lang.t("Текст")
                    color: Colors.dim
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: music.lyrics.length > 0
                    text: music.lyricsSynced ? Lang.t("синхронизирован") : Lang.t("без тайминга")
                    color: music.lyricsSynced ? Colors.accent : Colors.dim
                    opacity: 0.8
                    font.pixelSize: 10
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: lyricsView
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    // высоту берём у колонки: у Flickable она не всегда считается сам
                    contentHeight: lyricsColumn.height
                    boundsBehavior: Flickable.StopAtBounds
                    // Пользователь полистал — не дёргаем текст несколько секунд.
                    // Следим только за действиями мышью: автопрокрутка тоже шлёт
                    // movementStarted и сама себя блокировала.
                    onDraggingChanged: if (dragging) music.lastScrollMs = Date.now()
                    onFlickStarted: music.lastScrollMs = Date.now()

                    WheelHandler {
                        onWheel: event => {
                            music.lastScrollMs = Date.now();
                            const max = Math.max(0, lyricsView.contentHeight - lyricsView.height);
                            lyricsView.contentY = Math.max(0, Math.min(max,
                                lyricsView.contentY - event.angleDelta.y / 3));
                            event.accepted = true;
                        }
                    }

                    Column {
                        id: lyricsColumn
                        width: lyricsView.width
                        spacing: 6

                        Repeater {
                            model: music.lyrics

                            delegate: Label {
                                required property var modelData
                                required property int index

                                width: lyricsColumn.width
                                text: modelData.text
                                wrapMode: Text.Wrap
                                color: index === music.currentLine ? Colors.accent : Colors.text
                                // спето — притушено, текущая — акцентом, впереди — светлее
                                opacity: modelData.t < 0 ? 0.8
                                         : (index === music.currentLine ? 1
                                         : (index < music.currentLine ? 0.4 : 0.85))
                                font.pixelSize: index === music.currentLine ? 15 : 12.5
                                font.bold: index === music.currentLine
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }
                        }
                    }
                }

                // края текста растворяются в панели
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 22
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Colors.card }
                        GradientStop { position: 1.0; color: Qt.alpha(Colors.base, 0) }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 22
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(Colors.base, 0) }
                        GradientStop { position: 1.0; color: Colors.card }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: music.lyrics.length === 0
                    text: !music.hasTrack ? Lang.t("Ничего не играет")
                          : (music.lyricsState === "loading" ? Lang.t("ищу текст…")
                          : (music.lyricsState === "off" ? Lang.t("источник текстов отключён")
                          : Lang.t("текст не найден")))
                    color: Colors.dim
                    font.pixelSize: 12
                }
            }
        }
    }
}
