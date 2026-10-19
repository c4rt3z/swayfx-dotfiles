import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../singletons"

// Выбор внешнего вида: схема оформления и обои.
//
// Показывает готовые схемы и миниатюры обоев из папки, фильтры по основному
// цвету и недавние. Клик по миниатюре ставит обои с переходом «круг» из точки
// клика, клик по схеме — перекрашивает бар, панели и терминалы.
//
// Список и превью готовит ~/.config/wallpaper/index-wallpapers.py,
// сами обои ставит WallpaperEngine через `qs ipc call wallpaper set`,
// цвета — ~/.config/wallpaper/theme-gen.sh.
//
// Используется в двух местах: как отдельная панель (panels/WallpaperPicker.qml,
// Mod+Shift+W) и как раздел «Внешний вид» в меню настроек.
ColumnLayout {
    id: picker

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string cacheDir: home + "/.cache/wallpaper"
    readonly property string indexer: home + "/.config/wallpaper/index-wallpapers.py"
    readonly property string cli: home + "/.config/wallpaper/wallpaper.sh"
    readonly property string themeGen: home + "/.config/wallpaper/theme-gen.sh"

    property var items: []
    property var recent: []
    property var schemes: [{ id: "auto", name: "Material You", accent: "" }]
    property string themeMode: "auto"
    property string flavour: "universal"
    property string variant: "dark"
    // типы схем Material You (matugen): как сильно палитра следует за обоями
    readonly property var flavours: [
        { id: "universal", name: Lang.t("Универсальный") },
        { id: "vibrant", name: Lang.t("Насыщенная") },
        { id: "content", name: Lang.t("Содержательная") },
        { id: "expressive", name: Lang.t("Выразительная") },
        { id: "fidelity", name: Lang.t("Точная") },
        { id: "monochrome", name: Lang.t("Монохромная") },
        { id: "rainbow", name: Lang.t("Радужная") }
    ]
    property string filter: "all"
    property string currentName: ""
    property string status: "" // пусто, пока всё в порядке; иначе — что не прочиталось
    property bool indexing: false

    readonly property var filters: [
        { key: "all", label: Lang.t("все") },
        { key: "recent", label: Lang.t("недавние") },
        { key: "red", label: Lang.t("красные") },
        { key: "orange", label: Lang.t("оранжевые") },
        { key: "yellow", label: Lang.t("жёлтые") },
        { key: "green", label: Lang.t("зелёные") },
        { key: "cyan", label: Lang.t("голубые") },
        { key: "blue", label: Lang.t("синие") },
        { key: "purple", label: Lang.t("фиолетовые") },
        { key: "pink", label: Lang.t("розовые") },
        { key: "mono", label: Lang.t("монохром") }
    ]

    // что показываем с учётом фильтра
    readonly property var visibleItems: {
        let list = picker.items;
        if (picker.filter === "recent") {
            let order = picker.recent;
            list = list.filter(it => order.indexOf(it.name) >= 0);
            list = list.slice().sort((a, b) => order.indexOf(a.name) - order.indexOf(b.name));
        } else if (picker.filter !== "all") {
            list = list.filter(it => it.bucket === picker.filter);
        }
        return list;
    }

    // Высота панели подстраивается под число миниатюр: при одной-двух
    // обоях не остаётся пустого места, при многих — до четырёх рядов и прокрутка.
    readonly property int cols: Math.max(1, Math.floor((picker.width > 0 ? picker.width : 744) / 150))
    readonly property int rows: Math.max(1, Math.min(4, Math.ceil(picker.visibleItems.length / cols)))
    readonly property real cellH: Math.round((picker.width > 0 ? picker.width / cols : 186) * 0.64)

    spacing: 10
    // высоту считает сам ColumnLayout: ручная формула не учитывала отступы
    // и обрезала страницу «Внешний вид» на пару десятков пикселей

    function baseName(p): string {
        let s = String(p || "");
        let i = s.lastIndexOf("/");
        return i >= 0 ? s.slice(i + 1) : s;
    }

    function refreshCurrent(): void {
        currentProc.running = false;
        currentProc.running = true;
    }

    // поставить обои; ox/oy — точка перехода в долях экрана
    function applyItem(it, ox, oy): void {
        if (!it || !it.path)
            return;
        let trans = "circle:" + ox.toFixed(3) + ":" + oy.toFixed(3);
        Quickshell.execDetached(["qs", "ipc", "call", "wallpaper", "set", "all", it.path, trans]);
        picker.currentName = it.name;
    }

    Component.onCompleted: {
        indexProc.running = true;
        schemesProc.running = true;
        refreshCurrent();
    }

    // Список и превью: индексатор отдаёт готовый JSON прямо в вывод,
    // поэтому ничего не читаем из файла (нет гонки с записью).
    Process {
        id: indexProc
        command: ["python3", picker.indexer, "--json"]
        onRunningChanged: picker.indexing = running
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = (this.text || "").trim();
                if (raw === "")
                    return;
                try {
                    let data = JSON.parse(raw);
                    picker.items = data.items || [];
                    picker.status = "";
                } catch (e) {
                    picker.status = Lang.t("список не прочитался");
                }
            }
        }
        onExited: picker.refreshCurrent()
    }

    // имя текущих обоев
    Process {
        id: currentProc
        command: ["qs", "ipc", "call", "wallpaper", "current"]
        stdout: StdioCollector {
            onStreamFinished: picker.currentName = picker.baseName((this.text || "").trim())
        }
    }

    // недавние (пишет state.sh при смене обоев)
    FileView {
        id: historyView
        path: picker.cacheDir + "/history"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            picker.recent = (raw || "").split("\n").filter(s => s.trim() !== "");
        }
    }

    // Готовые схемы оформления (сверху — Material You, дальше именованные)
    Process {
        id: schemesProc
        command: ["bash", picker.themeGen, "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = (this.text || "").split("\n").filter(s => s.trim() !== "");
                let list = [{ id: "auto", name: "Material You", accent: "" }];
                for (let i = 0; i < rows.length; i++) {
                    let p = rows[i].split("\t");
                    if (p.length >= 2)
                        list.push({ id: p[0], name: p[1], accent: p[3] || "" });
                }
                picker.schemes = list;
            }
        }
    }

    // какой режим выбран сейчас (пишет theme-gen.sh)
    FileView {
        id: modeView
        path: picker.cacheDir + "/theme_mode"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            let v = (raw || "").trim();
            if (v !== "")
                picker.themeMode = v;
        }
    }

    Label {
        text: Lang.t("Схема оформления")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    // Схемы оформления: клик меняет цвета бара и панелей, обои остаются
    Flow {
        id: schemesFlow
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: 2

        Repeater {
            model: picker.schemes

            delegate: Item {
                id: schemeItem
                required property var modelData
                width: chipRow.implicitWidth + 12
                height: 22
                readonly property bool active: picker.themeMode === modelData.id

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 2
                        color: modelData.id === "auto"
                            ? (schemeItem.active ? Colors.accent : "transparent")
                            : modelData.accent
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: schemeItem.active ? Colors.accent : (hoverS.containsMouse ? Colors.text : Colors.dim)
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: chipRow.implicitWidth
                    height: 1
                    color: Colors.accent
                    visible: schemeItem.active
                }

                MouseArea {
                    id: hoverS
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (picker.themeMode === modelData.id)
                            return;
                        picker.themeMode = modelData.id;
                        Quickshell.execDetached(["bash", picker.themeGen, "--mode", modelData.id]);
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    // Тип схемы Material You: меняет, насколько палитра следует за обоями.
    // Клик пишет ~/.config/wallpaper/flavour и пересобирает палитру заново.
    FileView {
        id: flavourView
        path: home + "/.config/wallpaper/flavour"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            let parts = (raw || "").trim().split(/\s+/);
            if (parts[0] !== "")
                picker.flavour = parts[0];
            if (parts.length > 1 && parts[1] !== "")
                picker.variant = parts[1];
        }
    }

    Label {
        text: Lang.t("Тип Material You")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Flow {
        id: flavourFlow
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: 2

        Repeater {
            model: picker.flavours

            delegate: Item {
                id: flavourItem
                required property var modelData
                width: flavourLabel.implicitWidth + 12
                height: 22
                readonly property bool active: picker.themeMode === "auto" && picker.flavour === modelData.id

                Label {
                    id: flavourLabel
                    anchors.centerIn: parent
                    text: modelData.name
                    font.pixelSize: 11
                    color: flavourItem.active ? Colors.accent : (flavourHover.containsMouse ? Colors.text : Colors.dim)
                }

                MouseArea {
                    id: flavourHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["bash", picker.themeGen, "--flavour", modelData.id])
                }
            }
        }
    }

    Label {
        text: Lang.t("Фон")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Row {
        spacing: 2

        Repeater {
            model: [
                { id: "dark", name: Lang.t("Тёмный") },
                { id: "light", name: Lang.t("Светлый") }
            ]

            delegate: Item {
                id: variantItem
                required property var modelData
                width: variantLabel.implicitWidth + 12
                height: 22
                readonly property bool active: picker.themeMode === "auto" && picker.variant === modelData.id

                Label {
                    id: variantLabel
                    anchors.centerIn: parent
                    text: modelData.name
                    font.pixelSize: 11
                    color: variantItem.active ? Colors.accent : (variantHover.containsMouse ? Colors.text : Colors.dim)
                }

                MouseArea {
                    id: variantHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["bash", picker.themeGen, "--variant", modelData.id])
                }
            }
        }
    }

    Label {
        text: Lang.t("Обои")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    // Фильтры по основному цвету
    Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: 2

        Repeater {
            model: picker.filters

            delegate: Item {
                required property var modelData
                width: chip.implicitWidth + 12
                height: 22
                readonly property bool active: picker.filter === modelData.key

                Label {
                    id: chip
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.active ? Colors.accent : (hover.containsMouse ? Colors.text : Colors.dim)
                    font.pixelSize: 11
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: chip.implicitWidth
                    height: 1
                    color: Colors.accent
                    visible: parent.active
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: picker.filter = modelData.key
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    // Миниатюры
    GridView {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: picker.rows * picker.cellH + 8

        clip: true
        cellWidth: picker.width > 0 ? picker.width / picker.cols : 186
        cellHeight: picker.cellH
        boundsBehavior: Flickable.StopAtBounds

        model: picker.visibleItems
        visible: picker.visibleItems.length > 0

        delegate: Item {
            required property var modelData

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: box
                anchors.fill: parent
                anchors.margins: 4
                radius: 6
                color: Colors.surface
                border.width: current ? 2 : 1
                border.color: current ? Colors.accent : (area.containsMouse ? Colors.muted : Colors.border)
                clip: true

                readonly property bool current: modelData.name === picker.currentName

                Image {
                    anchors.fill: parent
                    source: modelData.thumb ? "file://" + modelData.thumb : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                // подпись поверх нижнего края
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 20
                    color: Qt.rgba(0, 0, 0, 0.45)

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.video ? modelData.name + Lang.t("  (видео)") : modelData.name
                        color: Colors.text
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }
                }

                // метка текущих обоев
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 5
                    width: 7
                    height: 7
                    radius: 4
                    color: Colors.accent
                    visible: box.current
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        let g = area.mapToGlobal(area.width / 2, area.height / 2);
                        let sc = null;
                        let screens = Quickshell.screens;
                        for (let i = 0; i < screens.length; i++) {
                            let s = screens[i];
                            if (g.x >= s.x && g.x < s.x + s.width && g.y >= s.y && g.y < s.y + s.height) {
                                sc = s;
                                break;
                            }
                        }
                        let ox = 0.5;
                        let oy = 0.5;
                        if (sc) {
                            ox = (g.x - sc.x) / sc.width;
                            oy = (g.y - sc.y) / sc.height;
                        }
                        picker.applyItem(modelData, ox, oy);
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredHeight: 60
        verticalAlignment: Text.AlignTop
        wrapMode: Text.WordWrap
        visible: picker.visibleItems.length === 0 && !picker.indexing
        text: picker.items.length === 0
            ? Lang.t("В папке обоев пусто. Положите картинки в ~/Wallpapers — список подхватится сам.")
            : Lang.t("Под этот фильтр ничего не подходит.")
        color: Colors.dim
        font.pixelSize: 11
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    // Нижняя строка: счётчик и действия
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: {
                if (picker.status !== "")
                    return picker.status;
                if (picker.indexing)
                    return Lang.t("обновляю список…");
                if (picker.filter === "all" || picker.filter === "recent")
                    return Lang.t("обоев: ") + picker.items.length;
                return Lang.t("показано ") + picker.visibleItems.length + Lang.t(" из ") + picker.items.length;
            }
            color: picker.status !== "" ? Colors.red : Colors.dim
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Row {
            spacing: 10

            Label {
                text: picker.indexing ? Lang.t("обновляю…") : Lang.t("обновить")
                color: upd.containsMouse ? Colors.text : Colors.dim
                font.pixelSize: 11
                MouseArea {
                    id: upd
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: if (!picker.indexing) {
                        indexProc.running = true;
                    }
                }
            }

            Label {
                text: Lang.t("случайные")
                color: rnd.containsMouse ? Colors.accent : Colors.dim
                font.pixelSize: 11
                MouseArea {
                    id: rnd
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: Quickshell.execDetached(["bash", picker.cli, "random"])
                }
            }
        }
    }
}
