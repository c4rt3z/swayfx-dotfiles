import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Клавиши»: все бинды из ~/.config/sway/config одной таблицей
// «сочетание — команда» (то, что действительно лежит в файле) и правка прямо тут.
//
// Список готовит scripts/binds-index.py: раскрывает $mod/$term для показа,
// переводит имена клавиш на человеческий, раскладывает бинды по группам. Он же
// и правит файл — меняет только сочетание или только команду, всё остальное
// (отступ, --to-code, комментарии, соседние строки) остаётся как есть, а после
// правки sway перечитывает конфиг.
//
// Заодно скрипт держит снимок «как было» (~/.config/quickshell/keys-default.json),
// поэтому у изменённого бинда появляется кнопка «как было».
//
// Что не получилось (занято, не понял клавишу), скрипт кладёт в
// ~/.cache/quickshell/keys-result.json — оттуда и берём сообщение.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string indexer: home + "/.config/quickshell/scripts/binds-index.py"
    readonly property string cacheFile: home + "/.cache/quickshell/keys.json"
    readonly property string resultFile: home + "/.cache/quickshell/keys-result.json"

    property var items: []
    property string query: ""

    property string editing: ""      // id бинда, который правим ("" — никто)
    property string editKeys: ""     // поле «сочетание» в правке
    property string editCmd: ""      // поле «команда» в правке
    property bool capturing: false   // ждём нажатия клавиш
    property var notice: null        // ответ скрипта на последнюю правку
    // время заведения страницы: ответы скрипта старше него не показываем,
    // иначе при открытии настроек всплыла бы чужая старая ошибка
    property real noticeAt: Date.now() / 1000

    readonly property var results: {
        let q = page.query.trim().toLowerCase();
        if (q === "")
            return page.items;
        return page.items.filter(i => (i.keys + " " + i.cmd + " " + i.action + " " + i.group)
                                        .toLowerCase().indexOf(q) >= 0);
    }

    // Заголовки групп вставляем в список сами: у ListView section.* заголовок
    // может отставать от строки на одну группу.
    readonly property var rows: {
        let out = [];
        let last = "";
        for (let i = 0; i < page.results.length; i++) {
            let it = page.results[i];
            if (it.group !== last) {
                out.push({ header: it.group });
                last = it.group;
            }
            out.push(it);
        }
        return out;
    }

    readonly property var edited: {
        for (let i = 0; i < page.items.length; i++)
            if (page.items[i].id === page.editing)
                return page.items[i];
        return null;
    }

    spacing: 12

    function run(args) {
        Quickshell.execDetached(["python3", page.indexer].concat(args));
    }

    function openEdit(item) {
        page.editing = item.id;
        page.editKeys = item.keys;
        page.editCmd = item.cmd;
        page.capturing = false;
        page.notice = null;
    }

    function messageFor(n) {
        if (!n)
            return "";
        if (n.ok)
            return n.swapped ? Lang.t("поменяли местами")
                 : (n.dry ? "" : Lang.t("сохранил"));
        if (n.reason === "busy")
            return Lang.t("сочетание занято: ") + (n.busy_keys || "") + "  " + (n.busy_cmd || "");
        if (n.reason === "token")
            return Lang.t("не понял клавишу ") + "«" + (n.token || "") + "»";
        if (n.reason === "nomod")
            return Lang.t("нужен модификатор: Super, Ctrl или Alt");
        if (n.reason === "empty")
            return Lang.t("нечего править");
        if (n.reason === "command")
            return Lang.t("команду пишут без слова bindsym");
        if (n.reason === "nodefault")
            return Lang.t("возвращать нечего: снимок «как было» не нашёлся");
        if (n.reason === "stale")
            return Lang.t("список устарел — открой раздел заново");
        return "";
    }

    Process {
        id: indexProc
        command: ["python3", page.indexer]
        Component.onCompleted: running = true
    }

    FileView {
        id: cacheView
        path: page.cacheFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                let j = JSON.parse(raw || "{}");
                page.items = j.items || [];
            } catch (e) {
            }
        }
    }

    FileView {
        id: resultView
        path: page.resultFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            let j = null;
            try {
                j = JSON.parse(raw || "{}");
            } catch (e) {
                return;
            }
            if (!j || !j.at || j.at <= page.noticeAt)
                return;
            page.noticeAt = j.at;
            page.notice = j;
            // «нажмите сочетание» только подставляет нажатое в поле, файл не трогает
            if (j.ok && j.dry && j.id === page.editing)
                page.editKeys = j.keys || page.editKeys;
        }
    }

    Rectangle {
        id: searchBox
        Layout.fillWidth: true
        implicitHeight: 36
        color: Colors.surface
        border.width: 1
        border.color: searchHover.hovered ? Colors.divider : Colors.border

        HoverHandler {
            id: searchHover
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyInput.text === ""
                text: Lang.t("поиск: workspace, яркость, Super+Shift…")
                color: Colors.dim
                font.pixelSize: 13
            }

            TextInput {
                id: keyInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: Fonts.panelFamily
                font.pixelSize: 14
                selectionColor: Colors.accent
                selectedTextColor: Colors.onAccent
                selectByMouse: false
                onTextChanged: page.query = text

                cursorDelegate: Rectangle {
                    width: 2
                    color: Colors.accent
                }

                Keys.onEscapePressed: {
                    keyInput.text = "";
                    page.query = "";
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: page.results.length + Lang.t(" из ") + page.items.length + Lang.t(" биндов")
              + Lang.t(" · клик по сочетанию или команде — правка")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
    }

    // ── правка бинда ───────────────────────────────────────────────────────
    // Отдельной карточкой над списком, а не под строкой: так она не уезжает за
    // край списка и всегда видно, что именно меняешь.

    Loader {
        id: editCard

        Layout.fillWidth: true
        active: page.editing !== ""
        visible: active

        sourceComponent: Rectangle {
            implicitHeight: editColumn.implicitHeight + 20
            radius: 6
            color: Colors.surface
            border.width: 1
            border.color: Colors.border

            // Esc в поле возвращает к списку, а не закрывает всё окно настроек
            Keys.onEscapePressed: {
                if (page.capturing)
                    page.capturing = false;
                else
                    page.editing = "";
                event.accepted = true;
            }

            // Пока человек «нажимает сочетание», клавиши забираем себе. Старые
            // бинды при этом срабатывают как обычно — про это написано рядом.
            Item {
                id: captureItem

                anchors.fill: parent
                focus: page.capturing

                Keys.onPressed: (event) => {
                    if (event.isAutoRepeat) {
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        page.capturing = false;
                        event.accepted = true;
                        return;
                    }
                    page.run(["qt", page.editing, String(event.key), String(event.modifiers), "dry"]);
                    event.accepted = true;
                }
            }

            ColumnLayout {
                id: editColumn

                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: Lang.t("правка") + ": " + (page.edited ? page.edited.group : "")
                        font.pixelSize: 11
                        font.bold: true
                        color: Colors.accent
                    }

                    Label {
                        Layout.fillWidth: true
                        text: page.edited ? page.edited.keys_raw : ""
                        font.family: Fonts.panelFamily
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.8)
                        elide: Text.ElideRight
                    }

                    Label {
                        text: Lang.t("как было")
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.85)
                        visible: page.edited ? page.edited.changed === true : false

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.run(["reset", page.editing])
                        }
                    }

                    Label {
                        text: Lang.t("закрыть")
                        font.pixelSize: 10
                        color: Qt.alpha(Colors.dim, 0.85)

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                page.capturing = false;
                                page.editing = "";
                            }
                        }
                    }
                }

                // сочетание
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        Layout.preferredWidth: 74
                        text: Lang.t("сочетание")
                        font.pixelSize: 11
                        color: Colors.dim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 5
                        color: Colors.base
                        border.width: 1
                        border.color: page.capturing ? Colors.accent : Colors.border

                        TextInput {
                            id: keysField

                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            visible: !page.capturing
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.text
                            font.family: Fonts.panelFamily
                            font.pixelSize: 13
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.onAccent
                            selectByMouse: false
                            text: page.editKeys
                            onTextChanged: page.editKeys = text

                            cursorDelegate: Rectangle {
                                width: 2
                                color: Colors.accent
                            }

                            onAccepted: page.run(["edit", page.editing, page.editKeys, page.editCmd])

                            Component.onCompleted: if (page.edited)
                                forceActiveFocus()
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            visible: page.capturing
                            text: Lang.t("нажмите сочетание (Esc — отмена)")
                            font.pixelSize: 12
                            color: Colors.accent
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 86
                        implicitHeight: 30
                        radius: 5
                        color: captureHover.hovered ? Colors.selected : Colors.surface
                        border.width: 1
                        border.color: page.capturing ? Colors.accent : Colors.border

                        Label {
                            anchors.centerIn: parent
                            text: page.capturing ? Lang.t("жду") : Lang.t("нажать")
                            font.pixelSize: 11
                            color: page.capturing ? Colors.accent : Colors.text
                        }

                        HoverHandler {
                            id: captureHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                page.capturing = !page.capturing;
                                if (page.capturing)
                                    captureItem.forceActiveFocus();
                            }
                        }
                    }
                }

                // команда
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        Layout.preferredWidth: 74
                        text: Lang.t("команда")
                        font.pixelSize: 11
                        color: Colors.dim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 5
                        color: Colors.base
                        border.width: 1
                        border.color: Colors.border

                        TextInput {
                            id: cmdField

                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.text
                            font.family: Fonts.panelFamily
                            font.pixelSize: 13
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.onAccent
                            selectByMouse: false
                            text: page.editCmd
                            onTextChanged: page.editCmd = text

                            cursorDelegate: Rectangle {
                                width: 2
                                color: Colors.accent
                            }

                            onAccepted: page.run(["edit", page.editing, page.editKeys, page.editCmd])
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 86
                        implicitHeight: 30
                        radius: 5
                        color: saveHover.hovered ? Colors.selected : Colors.surface
                        border.width: 1
                        border.color: Colors.border

                        Label {
                            anchors.centerIn: parent
                            text: Lang.t("сохранить")
                            font.pixelSize: 11
                            color: Colors.text
                        }

                        HoverHandler {
                            id: saveHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.run(["edit", page.editing, page.editKeys, page.editCmd])
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        Layout.fillWidth: true
                        text: page.messageFor(page.notice)
                        font.pixelSize: 10
                        color: page.notice && page.notice.ok
                               ? Qt.alpha(Colors.accent, 0.9) : Colors.red
                        elide: Text.ElideRight
                    }

                    // чужое сочетание не отбираем молча — предлагаем обмен
                    Label {
                        visible: !!(page.notice && page.notice.reason === "busy")
                        text: Lang.t("поменять местами")
                        font.pixelSize: 10
                        color: Colors.accent

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.run(["swap", page.editing, page.notice.busy_id])
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: Lang.t("Сочетание пишут как Super+Shift+e (можно и Mod4+Shift+e), команду — как в конфиге sway. Пока идёт запись, старые сочетания срабатывают как обычно.")
                    font.pixelSize: 10
                    color: Qt.alpha(Colors.dim, 0.8)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.preferredHeight: 380
        clip: true
        model: page.rows
        spacing: 1
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: keyRow

            required property var modelData

            readonly property bool isHeader: keyRow.modelData.header !== undefined
            readonly property bool isEditing: !isHeader && keyRow.modelData.id === page.editing

            width: list.width
            height: keyRow.isHeader ? 26 : 24

            Label {
                visible: keyRow.isHeader
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: keyRow.isHeader ? keyRow.modelData.header : ""
                font.pixelSize: 11
                font.bold: true
                color: Qt.alpha(Colors.accent, 0.9)
            }

            Rectangle {
                anchors.fill: parent
                visible: !keyRow.isHeader
                radius: 4
                color: keyRow.isEditing ? Colors.selected
                                        : (keyHover.containsMouse ? Colors.selected : "transparent")
            }

            MouseArea {
                id: keyHover
                anchors.fill: parent
                enabled: !keyRow.isHeader
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.openEdit(keyRow.modelData)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                visible: !keyRow.isHeader
                spacing: 10

                Label {
                    Layout.preferredWidth: 168
                    text: keyRow.isHeader ? "" : keyRow.modelData.keys
                    font.pixelSize: 12
                    font.bold: true
                    color: Colors.accent
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    text: keyRow.isHeader ? "" : keyRow.modelData.cmd
                    font.family: Fonts.panelFamily
                    font.pixelSize: 11
                    color: keyHover.containsMouse ? Colors.text : Colors.dim
                    elide: Text.ElideRight
                }

                // у изменённого бинда — вернуть как было
                Label {
                    visible: !keyRow.isHeader && keyRow.modelData.changed === true
                    text: "↺"
                    font.pixelSize: 13
                    color: Colors.accent

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.run(["reset", keyRow.modelData.id])
                    }
                }
            }

        }
    }
}
