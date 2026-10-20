import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Лаунчер (Mod+A) — замена `wofi --show drun` и `wofi --show run`.
//
//   • поиск приложений по названию, описанию и id (все слова запроса должны найтись)
//   • строка «>команда» или запрос без совпадений — запуск команды через sh -c
//   • стрелки/Tab — выбор, Enter — запустить, Esc — закрыть, мышь тоже работает
//
// Список приложений готовит ~/.config/quickshell/scripts/apps-index.py
// (кладёт JSON в ~/.cache/quickshell/apps.json, панель читает файл и следит за ним).
ColumnLayout {
    id: launcher

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string indexer: home + "/.config/quickshell/scripts/apps-index.py"
    readonly property string cacheFile: home + "/.cache/quickshell/apps.json"

    // Свои пункты: панели quickshell в общем списке приложений
    readonly property var builtins: [
        {
            id: "qs-settings",
            name: Lang.t("Настройки"),
            comment: Lang.t("меню настроек дотфайлов (Super+,)"),
            exec: "qs ipc call panel open settings",
            icon: "",
            terminal: false,
            panel: true,
            search: Lang.t("настройки settings параметры конфиг дотфайлы dotfiles")
        },
        {
            id: "qs-emoji",
            name: Lang.t("Эмодзи"),
            comment: Lang.t("выбор эмодзи (Super+.)"),
            exec: "qs ipc call panel open emoji",
            icon: "",
            terminal: false,
            panel: true,
            search: Lang.t("эмодзи смайлы emoji smileys символы")
        }
    ]

    property var apps: []
    property string query: ""
    property int selected: 0
    property bool loading: true

    readonly property int rowHeight: 34
    readonly property int maxRows: 9

    // ── поиск ──────────────────────────────────────────────────────────────

    // все слова запроса должны найтись; где слово стоит в начале строки поиска —
    // та строка выше (так «fire» поднимает Firefox, а не «Firewall Applet»)
    function matchApps(q) {
        if (q === "")
            return launcher.apps.slice(0, 60);
        let terms = q.split(/\s+/).filter(t => t !== "");
        let out = [];
        for (let i = 0; i < launcher.apps.length; i++) {
            let a = launcher.apps[i];
            let score = 0;
            let ok = true;
            for (let t = 0; t < terms.length; t++) {
                let pos = a.search.indexOf(terms[t]);
                if (pos < 0) {
                    ok = false;
                    break;
                }
                score += pos + (pos === 0 ? -1000 : 0);
            }
            if (ok)
                out.push({ app: a, score: score });
        }
        out.sort((x, y) => (x.score - y.score) || x.app.name.localeCompare(y.app.name));
        return out.slice(0, 60).map(r => r.app);
    }

    // что показываем: приложения, а при «>» или без совпадений — ещё и запуск команды
    readonly property var results: {
        let q = launcher.query.trim();
        if (q.startsWith(">")) {
            let cmd = q.slice(1).trim();
            return [{ run: true, name: cmd, comment: Lang.t("выполнить команду"), icon: "", exec: cmd }]
                .concat(launcher.matchApps(cmd.toLowerCase()));
        }
        let matched = launcher.matchApps(q.toLowerCase());
        if (q !== "" && matched.length === 0)
            return [{ run: true, name: q, comment: Lang.t("выполнить команду"), icon: "", exec: q }];
        return matched;
    }

    function move(step) {
        let n = launcher.results.length;
        if (n === 0)
            return;
        launcher.selected = Math.max(0, Math.min(n - 1, launcher.selected + step));
    }

    function activate(index) {
        let r = launcher.results[index >= 0 ? index : launcher.selected];
        if (!r || !r.exec)
            return;
        Quickshell.execDetached(["sh", "-c", r.exec]);
        // пункты-панели (настройки, эмодзи) открывают окно сами — панель им
        // закрывать нельзя, иначе она закроет только что открытое
        if (!r.panel)
            Quickshell.execDetached(["qs", "ipc", "call", "panel", "close"]);
    }

    function close() {
        Quickshell.execDetached(["qs", "ipc", "call", "panel", "close"]);
    }

    function readCache(raw) {
        raw = (raw || "").trim();
        if (raw === "")
            return;
        try {
            let j = JSON.parse(raw);
            if (j && j.items && j.items.length > 0) {
                launcher.apps = launcher.builtins.concat(j.items);
                launcher.loading = false;
            }
        } catch (e) {
        }
    }

    onQueryChanged: launcher.selected = 0

    Component.onCompleted: input.forceActiveFocus()

    // ── данные ─────────────────────────────────────────────────────────────

    // кэш читаем сразу (панель открывается мгновенно), а индекс пересобираем в фоне,
    // чтобы подхватывались только что установленные приложения
    FileView {
        id: cacheView
        path: launcher.cacheFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: launcher.readCache(typeof text === "function" ? text() : text)
    }

    Process {
        id: indexProc
        command: ["python3", launcher.indexer]
        onExited: if (launcher.apps.length === 0) launcher.loading = false
        Component.onCompleted: running = true
    }

    // ── строка поиска ──────────────────────────────────────────────────────

    Rectangle {
        id: searchBox
        Layout.fillWidth: true
        implicitHeight: 36
        color: Colors.surface
        border.width: 1
        border.color: hover.hovered ? Colors.divider : Colors.border

        HoverHandler {
            id: hover
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            // Поле с печатающимся текстом
            TypeInput {
                id: input
                anchors.fill: parent
                textColor: Colors.text
                placeholderColor: Colors.dim
                fontPixelSize: 13
                placeholder: Lang.t("поиск приложений, или > команда")
                onEdited: value => launcher.query = value
                onAccepted: launcher.activate(-1)
            }        }
    }

    // ── список ─────────────────────────────────────────────────────────────

    Item {
        Layout.fillWidth: true
        implicitHeight: launcher.results.length === 0
                        ? 58
                        : Math.min(launcher.results.length, launcher.maxRows) * launcher.rowHeight

        ListView {
            id: list
            anchors.fill: parent
            model: launcher.results
            clip: true
            currentIndex: launcher.selected
            interactive: launcher.results.length > launcher.maxRows
            boundsBehavior: Flickable.StopAtBounds
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                readonly property bool isRun: modelData.run === true
                readonly property bool current: index === launcher.selected
                readonly property bool hasIcon: !isRun && modelData.icon !== ""

                width: list.width
                height: launcher.rowHeight
                color: current ? Colors.selected : "transparent"

                // акцентная полоска у выбранной строки — вместо «пилюль»
                Rectangle {
                    visible: row.current
                    width: 2
                    height: row.height
                    color: Colors.accent
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: launcher.selected = row.index
                    onClicked: launcher.activate(row.index)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Item {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20

                        Image {
                            anchors.centerIn: parent
                            visible: row.hasIcon
                            source: row.hasIcon ? "file://" + row.modelData.icon : ""
                            sourceSize.width: 20
                            sourceSize.height: 20
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: !row.hasIcon
                            text: row.isRun ? "$" : row.modelData.name.charAt(0).toUpperCase()
                            color: row.current ? Colors.accent : Colors.dim
                            font.pixelSize: 13
                        }
                    }

                    Label {
                        text: row.modelData.name
                        color: row.current ? Colors.accent : Colors.text
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.maximumWidth: 300
                    }

                    Label {
                        Layout.fillWidth: true
                        text: row.modelData.comment
                        color: Colors.dim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Label {
                        visible: row.current
                        text: "enter"
                        color: Colors.dim
                        font.pixelSize: 11
                    }
                }
            }
        }

        Label {
            anchors.centerIn: parent
            visible: launcher.results.length === 0
            text: launcher.loading && launcher.apps.length === 0
                  ? Lang.t("собираю список приложений…")
                  : Lang.t("ничего не найдено")
            color: Colors.dim
            font.pixelSize: 13
        }
    }
}
