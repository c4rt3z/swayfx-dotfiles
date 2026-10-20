import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../singletons"

// Сайдбар: выезжает слева по Mod+B, занимает четверть экрана.
//
// Что внутри:
//   • плитки сессии (по две в ряд) — выключить, перезагрузить, выйти и прочее;
//   • снимки экрана: кнопки «область / окно / экран / с задержкой» и свежие
//     снимки с действиями (копировать, распознать текст, открыть, удалить);
//   • история буфера обмена — текст и картинки (её ведёт scripts/clipboard.py,
//     нас зовёт wl-paste на каждое новое выделение).
//
// Экраны не перекрываем: поверхность занимает только свою четверть, остальное
// окно остаётся рабочим столом.
PanelWindow {
    id: side

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string clipScript: home + "/.config/quickshell/scripts/clipboard.py"
    readonly property string shotScript: home + "/.config/quickshell/scripts/shot.py"
    readonly property string weatherScript: home + "/.config/quickshell/scripts/weather.py"

    // Ширина — доля экрана из настроек («Сайдбар» в меню), в разумных пределах:
    // на 1366 px при 24% — 360, на 2560 — 560.
    readonly property real preferredWidth: Math.max(360, Math.min(620,
        Math.round(screen.width * Sidebar.widthPercent / 100)))

    property var clips: []
    property var shots: []
    // «сейчас играет»: status|title|artist|artUrl
    property var track: ({ title: "", artist: "", art: "", status: "" })
    // погода для виджета: {icon, temp, desc, unit}
    property var weather: ({})
    // где бар waybar: панель встаёт под ним сверху или над ним снизу
    property string barPosition: "top"
    property var powerItems: [
        { icon: "\uF023", label: Lang.t("Заблокировать"), run: "lock", confirm: false },
        { icon: "\uF007", label: Lang.t("Смена пользователя"), run: "greeter", confirm: true },
        { icon: "\uF186", label: Lang.t("Сон"), run: "suspend", confirm: true },
        { icon: "\uF08B", label: Lang.t("Выйти из сессии"), run: "logout", confirm: true },
        { icon: "\uF01E", label: Lang.t("Перезагрузить"), run: "reboot", confirm: true },
        { icon: "\uF011", label: Lang.t("Выключить"), run: "poweroff", confirm: true }
    ]
    property int armed: -1
    property bool busy: false

    // Открытие-закрытие: список перечитываем каждый раз, чтобы он не устаревал.
    //
    // Пока идёт выезд, окно остаётся на экране (closing), иначе панель
    // пропадала бы мгновенно, не доиграв анимацию.
    visible: Sidebar.open || closing
    onVisibleChanged: {
        if (Sidebar.open) {
            closing = false;
            refresh();
            slide = 1;
        } else if (!closing) {
            closing = true;
            slide = 0;
        }
    }

    function readTrack(raw) {
        const parts = (raw || "").split("|");
        side.track = {
            status: parts[0] || "",
            title: (parts[1] || "").trim(),
            artist: (parts[2] || "").trim(),
            art: (parts[3] || "").trim()
        };
    }

    function readWeather(raw) {
        try {
            const data = JSON.parse(raw || "{}").data || {};
            side.weather = data && data.ok !== false ? data : ({});
        } catch (e) {
            side.weather = ({});
        }
    }

    function trackSource(url) {
        if (!url)
            return "";
        if (url.indexOf("file://") === 0 || url.indexOf("http") === 0)
            return url;
        if (url.charAt(0) === "/")
            return "file://" + url;
        return url;
    }

    FileView {
        path: side.home + "/.cache/quickshell/bar.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                side.barPosition = (JSON.parse(raw || "{}").position === "bottom")
                                   ? "bottom" : "top";
            } catch (e) {
                side.barPosition = "top";
            }
        }
    }

    Process {
        id: trackProcess
        command: ["sh", "-c",
            "playerctl metadata --format '{{status}}|{{title}}|{{artist}}|{{mpris:artUrl}}' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: side.readTrack(text)
        }
    }

    Process {
        id: weatherProcess
        command: ["python3", side.weatherScript, "state"]
        stdout: StdioCollector {
            onStreamFinished: side.readWeather(text)
        }
    }

    // трек обновляем часто, погоду — раз в десять минут
    Timer {
        interval: 5000
        repeat: true
        running: side.visible && Sidebar.widget("now")
        onTriggered: trackProcess.running = true
    }

    Timer {
        interval: 600000
        repeat: true
        running: side.visible && Sidebar.widget("weather")
        onTriggered: weatherProcess.running = true
    }

    function refresh() {
        clipsView.reload();
        shotsProcess.running = true;
        if (Sidebar.widget("now"))
            trackProcess.running = true;
        if (Sidebar.widget("weather"))
            weatherProcess.running = true;
    }

    function choosePower(index) {
        const item = powerItems[index];
        if (item.confirm && armed !== index) {
            armed = index;
            disarm.restart();
            return;
        }
        armed = -1;
        runPower(item.run);
    }

    function runPower(run) {
        if (run === "lock") {
            Quickshell.execDetached(["qs", "ipc", "call", "lock", "lock"]);
            Sidebar.hide();
        } else if (run === "greeter") {
            Quickshell.execDetached(["dbus-send", "--system", "--print-reply",
                "--dest=org.freedesktop.DisplayManager",
                "/org/freedesktop/DisplayManager/Seat0",
                "org.freedesktop.DisplayManager.Seat.SwitchToGreeter"]);
            Sidebar.hide();
        } else if (run === "suspend") {
            Quickshell.execDetached(["systemctl", "suspend"]);
            Sidebar.hide();
        } else if (run === "logout") {
            Quickshell.execDetached(["swaymsg", "exit"]);
        } else if (run === "reboot") {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (run === "poweroff") {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }

    function takeShot(mode) {
        shotsProcess.running = false;
        shotAction.command = ["python3", shotScript, mode];
        shotAction.running = true;
        busy = true;
    }

    function copyClip(id) {
        clipAction.command = ["python3", clipScript, "copy", id];
        clipAction.running = false;
        clipAction.running = true;
    }

    function removeClip(id) {
        clipAction.command = ["python3", clipScript, "remove", id];
        clipAction.running = false;
        clipAction.running = true;
    }

    function clearClips() {
        clipAction.command = ["python3", clipScript, "clear"];
        clipAction.running = false;
        clipAction.running = true;
    }

    function shotAction2(cmd, path) {
        shotAction.command = ["python3", shotScript, cmd, path];
        shotAction.running = true;
        busy = true;
    }

    // сторону выбирают в настройках: слева или справа
    anchors.left: Sidebar.side === "left"
    anchors.right: Sidebar.side === "right"
    anchors.top: true
    anchors.bottom: true
    // Сайдбар выезжает из-за края экрана. Двигается не поверхность, а
    // карточка внутри: сдвиг самой поверхности заставлял композитор
    // пересчитывать размытие под ней каждый кадр (10–15 fps), а
    // поверхность ещё и уезжала за экран.
    property real slide: 0
    property bool closing: false


    Behavior on slide {
        NumberAnimation {
            duration: Animations.sidebar ? 220 : 0
            easing.type: Easing.OutCubic
        }
    }

    // окно стоит на месте, карточка внутри едет
    margins.left: 8
    margins.right: 8
    margins.top: barPosition === "bottom" ? 8 : 42     // под баром waybar
    margins.bottom: barPosition === "bottom" ? 42 : 8

    exclusiveZone: -1
    focusable: true
    color: "transparent"
    implicitWidth: preferredWidth

    WlrLayershell.layer: WlrLayer.Overlay
    // Свой namespace — без размытия. Сайдбар большой (360×1200) и при выезде
    // двигается: блюр такого куска пересчитывался бы каждый кадр, композитор
    // упирался в 10–15 fps, а вместе с ним подвисали окна. Карточка и так
    // почти непрозрачная — размытие за ней не видно.
    WlrLayershell.namespace: "qs-sidebar"
    // клавиатуру забираем, только пока открыт: Esc должен доходить до нас
    WlrLayershell.keyboardFocus: Sidebar.open
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Timer {
        id: disarm
        interval: 3000
        onTriggered: side.armed = -1
    }

    // после выезда окно прячется совсем
    Timer {
        interval: 260
        repeat: false
        onTriggered: {
            if (!Sidebar.open)
                closing = false;
        }
    }

    // Пока открыт — раз в 2 секунды подтягиваем свежие снимки и буфер: снимок
    // мог родиться по Print, а выделение — скопироваться мимо сайдбара.
    Timer {
        interval: 2000
        repeat: true
        running: Sidebar.open
        onTriggered: side.refresh()
    }

    // история буфера: index.json меняет сам watcher, поэтому просто смотрим файл
    FileView {
        id: clipsView
        path: side.home + "/.cache/quickshell/clipboard/index.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                const parsed = JSON.parse(raw || "{}");
                side.clips = parsed.items || [];
            } catch (e) {
                side.clips = [];
            }
        }
    }

    Process {
        id: shotsProcess
        command: ["python3", side.shotScript, "list", "12"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    side.shots = (JSON.parse(this.text || "{}").items) || [];
                } catch (e) {
                    side.shots = [];
                }
            }
        }
    }

    Process {
        id: shotAction
        onExited: {
            side.busy = false;
            shotsProcess.running = true;
            clipsView.reload();
        }
    }

    Process {
        id: clipAction
        onExited: clipsView.reload()
    }

    Rectangle {
        id: chrome

        anchors.fill: parent
        radius: 10
        color: Colors.card
        border.width: 1
        border.color: Colors.border
        focus: true

        // выезд из-за края: сдвиг и лёгкое проявление
        opacity: slide
        transform: [
            Translate {
                x: Sidebar.side === "right"
                   ? (1 - slide) * side.preferredWidth
                   : -(1 - slide) * side.preferredWidth
            }
        ]

        Keys.onEscapePressed: Sidebar.hide()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ── заголовок ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Label {
                    text: "\uF0C9"
                    color: Colors.accent
                    font.pixelSize: 15
                }

                Label {
                    Layout.fillWidth: true
                    text: Lang.t("Панель")
                    color: Colors.text
                    font.pixelSize: 14
                    font.bold: true
                }

                Label {
                    id: clockLabel
                    text: Qt.formatDateTime(new Date(), "HH:mm")
                    color: Colors.dim
                    font.pixelSize: 13

                    Timer {
                        interval: 1000
                        repeat: true
                        running: side.visible
                        onTriggered: clockLabel.text = Qt.formatDateTime(new Date(), "HH:mm")
                    }
                }

                Item {
                    implicitWidth: 22
                    implicitHeight: 22

                    Label {
                        anchors.centerIn: parent
                        text: "\u00d7"
                        color: closeHover.containsMouse ? Colors.text : Colors.dim
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Sidebar.hide()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Colors.divider
            }

            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: content.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: content
                    width: scroller.width
                    spacing: 12

                    // ── сейчас играет ─────────────────────────────────────
                    // Обложка крупнее, название — полужирным, справа кнопка
                    // паузы: ею можно остановить трек, не открывая плеер.
                    Item {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("now") && side.track.title !== ""
                        implicitHeight: 62

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: nowHover.containsMouse ? Colors.selected : "transparent"
                            border.width: 1
                            border.color: nowHover.containsMouse ? Colors.accent : Colors.divider
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 10

                            Rectangle {
                                implicitWidth: 46
                                implicitHeight: 46
                                radius: 7
                                color: Colors.selected
                                clip: true
                                border.width: 1
                                border.color: Colors.divider

                                Image {
                                    anchors.fill: parent
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    source: side.trackSource(side.track.art)
                                    visible: source != ""
                                    sourceSize.width: 128
                                }

                                Label {
                                    anchors.centerIn: parent
                                    visible: side.trackSource(side.track.art) === ""
                                    text: "\uf001"
                                    color: Colors.dim
                                    font.pixelSize: 16
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: side.track.title
                                    color: Colors.text
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: side.track.artist !== ""
                                          ? side.track.artist : Lang.t("Неизвестный исполнитель")
                                    color: Colors.dim
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            // пауза/воспроизведение — отдельная кнопка поверх
                            // общей области клика (иначе открывался бы плеер)
                            Item {
                                implicitWidth: 26
                                implicitHeight: 26

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: playHover.containsMouse ? Colors.accent : "transparent"
                                }

                                Label {
                                    anchors.centerIn: parent
                                    text: side.track.status === "Playing" ? "\uf04b" : "\uf04c"
                                    color: playHover.containsMouse ? Colors.on_accent : Colors.muted
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: playHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["playerctl", "play-pause"])
                                }
                            }
                        }

                        MouseArea {
                            id: nowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "panel", "open", "music"])
                        }
                    }

                    // ── погода ────────────────────────────────────────────
                    // Крупная иконка, температура — полужирным, ниже город,
                    // «ощущается» и ветер.
                    Item {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("weather") && side.weather.icon !== undefined
                        implicitHeight: 62

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: weatherHover.containsMouse ? Colors.selected : "transparent"
                            border.width: 1
                            border.color: weatherHover.containsMouse ? Colors.accent : Colors.divider
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 12

                            Label {
                                text: side.weather.icon !== undefined ? side.weather.icon : ""
                                color: Colors.accent
                                font.pixelSize: 28
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Label {
                                        text: (side.weather.temp !== undefined ? side.weather.temp : "?")
                                              + " " + (side.weather.unit || "°C")
                                        color: Colors.text
                                        font.pixelSize: 20
                                        font.bold: true
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: side.weather.desc || ""
                                        color: Colors.dim
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: {
                                        const bits = [];
                                        if (side.weather.city)
                                            bits.push(side.weather.city);
                                        if (side.weather.feels !== undefined)
                                            bits.push(Lang.t("ощущается ") + side.weather.feels + "°");
                                        if (side.weather.wind !== undefined)
                                            bits.push(Lang.t("ветер ") + side.weather.wind
                                                      + " " + (side.weather.wind_unit || "м/с"));
                                        return bits.join(" · ");
                                    }
                                    color: Qt.alpha(Colors.dim, 0.85)
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: weatherHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "panel", "open", "weather"])
                        }
                    }

                    // ── сессия: по две плитки в ряд ────────────────────────
                    Label {
                        visible: Sidebar.widget("session")
                        text: Lang.t("Сессия")
                        color: Colors.muted
                        font.pixelSize: 11
                        font.bold: true
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("session")
                        columns: Sidebar.gridColumns
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: side.powerItems

                            delegate: Item {
                                id: powerTile

                                required property var modelData
                                required property int index

                                readonly property bool armedHere: side.armed === index

                                Layout.fillWidth: true
                                implicitHeight: Sidebar.labels ? 46 : 38

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: powerTile.armedHere ? Qt.alpha(Colors.red, 0.18)
                                         : (powerHover.containsMouse ? Colors.selected : "transparent")
                                    border.width: 1
                                    border.color: powerTile.armedHere ? Colors.red
                                                : (powerHover.containsMouse ? Colors.accent : Colors.divider)
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon
                                        color: powerTile.armedHere ? Colors.red
                                             : (modelData.run === "poweroff" ? Colors.red
                                             : (powerHover.containsMouse ? Colors.text : Colors.muted))
                                        font.pixelSize: 15
                                    }

                                    Label {
                                        // подписи можно выключить — останутся одни значки
                                        visible: Sidebar.labels || powerTile.armedHere
                                        Layout.alignment: Qt.AlignHCenter
                                        text: powerTile.armedHere ? Lang.t("ещё раз") : modelData.label
                                        color: powerTile.armedHere ? Colors.red
                                             : (powerHover.containsMouse ? Colors.text : Colors.muted)
                                        font.pixelSize: 10
                                    }
                                }

                                MouseArea {
                                    id: powerHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: if (side.armed !== powerTile.index) side.armed = -1
                                    onClicked: side.choosePower(powerTile.index)
                                }
                            }
                        }
                    }

                    // ── скриншоты ─────────────────────────────────────────
                    Label {
                        visible: Sidebar.widget("shots")
                        text: Lang.t("Снимки экрана")
                        color: Colors.muted
                        font.pixelSize: 11
                        font.bold: true
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("shots")
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: [
                                { icon: "\uF125", label: Lang.t("Область"), mode: "region" },
                                { icon: "\uF2D0", label: Lang.t("Окно"), mode: "window" },
                                { icon: "\uF108", label: Lang.t("Весь экран"), mode: "full" },
                                { icon: "\uF017", label: Lang.t("Через 3 с"), mode: "full 3" }
                            ]

                            delegate: Item {
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 38

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: shotHover.containsMouse ? Colors.selected : "transparent"
                                    border.width: 1
                                    border.color: shotHover.containsMouse ? Colors.accent : Colors.divider
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Label {
                                        text: modelData.icon
                                        color: shotHover.containsMouse ? Colors.accent : Colors.muted
                                        font.pixelSize: 13
                                    }
                                    Label {
                                        text: modelData.label
                                        color: shotHover.containsMouse ? Colors.text : Colors.muted
                                        font.pixelSize: 11
                                    }
                                }

                                MouseArea {
                                    id: shotHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        const parts = modelData.mode.split(" ");
                                        shotAction.command = ["python3", side.shotScript].concat(parts);
                                        shotAction.running = true;
                                        side.busy = true;
                                    }
                                }
                            }
                        }
                    }

                    // свежие снимки с действиями
                    GridLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("shots") && side.shots.length > 0
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: side.shots.slice(0, 6)

                            delegate: ColumnLayout {
                                id: shotCard

                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 74
                                    radius: 6
                                    color: Colors.selected
                                    border.width: 1
                                    border.color: Colors.divider
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        source: "file://" + modelData.path
                                        sourceSize.width: 320
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: side.shotAction2("copy", modelData.path)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.name.replace(/\.png$/, "").replace("_", " ")
                                        color: Colors.dim
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }

                                    Repeater {
                                        // распознавание текста из снимков убрали:
                                        // в сайдбаре оно только мешало, а текст
                                        // всё равно уходил в буфер обмена
                                        model: [
                                            { icon: "\uF0C5", act: "copy", tip: "копировать" },
                                            { icon: "\uF08E", act: "open", tip: "открыть" },
                                            { icon: "\uF1F8", act: "remove", tip: "удалить" }
                                        ]

                                        delegate: Label {
                                            required property var modelData
                                            text: modelData.icon
                                            color: shotIcon.containsMouse ? Colors.text : Colors.muted
                                            font.pixelSize: 11

                                            MouseArea {
                                                id: shotIcon
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                onClicked: side.shotAction2(modelData.act, shotCard.modelData.path)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── недавние уведомления ─────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("notifications") && Notifs.history.length > 0

                        Label {
                            Layout.fillWidth: true
                            text: Lang.t("Недавние уведомления")
                            color: Colors.muted
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Label {
                            text: Notifs.history.length
                            color: Colors.dim
                            font.pixelSize: 10
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("notifications") && Notifs.history.length > 0
                        spacing: 2

                        Repeater {
                            model: Notifs.history.slice(0, 12)

                            delegate: Item {
                                id: noteRow

                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 38

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: noteHover.containsMouse ? Colors.selected : "transparent"
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Label {
                                            Layout.fillWidth: true
                                            text: noteRow.modelData.app
                                                  || Lang.t("Система")
                                            color: Colors.accent
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: noteRow.modelData.summary !== ""
                                                  ? noteRow.modelData.summary
                                                  : noteRow.modelData.body
                                            color: Colors.text
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Label {
                                        text: "\uf0c5"
                                        color: noteHover.containsMouse ? Colors.accent : Colors.dim
                                        font.pixelSize: 11
                                    }
                                }

                                MouseArea {
                                    id: noteHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // щелчок копирует текст уведомления
                                    onClicked: {
                                        const text = noteRow.modelData.summary !== ""
                                                     ? noteRow.modelData.summary
                                                     : noteRow.modelData.body;
                                        if (text !== "")
                                            Quickshell.execDetached(["sh", "-c",
                                                "printf '%s' \"" + text.replace(/"/g, '\\"') + "\" | wl-copy"]);
                                    }
                                }
                            }
                        }
                    }

                    // ── буфер обмена ──────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("clipboard")

                        Label {
                            Layout.fillWidth: true
                            text: Lang.t("Буфер обмена") + (side.clips.length > 0 ? " · " + side.clips.length : "")
                            color: Colors.muted
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Label {
                            visible: side.clips.length > 0
                            text: Lang.t("очистить")
                            color: clearHover.containsMouse ? Colors.red : Colors.dim
                            font.pixelSize: 10

                            MouseArea {
                                id: clearHover
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                onClicked: side.clearClips()
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("clipboard") && side.clips.length === 0
                        text: Lang.t("Пусто: скопируйте что-нибудь — появится здесь")
                        color: Colors.dim
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: Sidebar.widget("clipboard")
                        spacing: 2

                        Repeater {
                            model: side.clips.slice(0, 30)

                            delegate: Item {
                                id: clipRow

                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: modelData.kind === "image" ? 44 : 30

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: clipHover.containsMouse ? Colors.selected : "transparent"
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 8

                                    Image {
                                        visible: modelData.kind === "image"
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 34
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        source: modelData.kind === "image" ? "file://" + modelData.path : ""
                                        sourceSize.width: 120
                                    }

                                    Label {
                                        visible: modelData.kind !== "image"
                                        text: "\uF0C1"
                                        color: Colors.muted
                                        font.pixelSize: 11
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        // место под крестик справа
                                        Layout.rightMargin: 20
                                        text: modelData.kind === "image"
                                              ? Lang.t("Картинка") + " · " + Math.round(modelData.size / 1024)
                                                + " " + Lang.t("КБ")
                                              : (modelData.preview || "")
                                        color: Colors.text
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: clipHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // клик по тексту копирует
                                    onClicked: side.copyClip(clipRow.modelData.id)
                                }

                                // Крестик — отдельной областью поверх строки. Если
                                // держать его внутри RowLayout, клик забирает
                                // общая MouseArea строки: она объявлена позже и
                                // лежит сверху, поэтому крестик «копировал» бы
                                // вместо удаления.
                                Label {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u00d7"
                                    color: clipRemove.containsMouse ? Colors.red : Colors.dim
                                    font.pixelSize: 14
                                    z: 2

                                    MouseArea {
                                        id: clipRemove
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: side.removeClip(clipRow.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 2
                    }
                }
            }
        }
    }
}
