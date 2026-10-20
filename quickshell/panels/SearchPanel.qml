import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Мега-поиск (Super+Space): приложения, окна, файлы, калькулятор, интернет.
//
// Вся логика — в scripts/search-engine.py: она прощает опечатки и набранный
// не в той раскладке текст, считает арифметику, знает окна sway и файлы в
// домашних папках. Результат складывается в ~/.cache/quickshell/search-out.json,
// панель его показывает и запускает выбранную строку.
ColumnLayout {
    id: search

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string engine: home + "/.config/quickshell/scripts/search-engine.py"
    readonly property string indexer: home + "/.config/quickshell/scripts/files-index.py"
    readonly property string outFile: home + "/.cache/quickshell/search-out.json"

    property var rows: []
    property string query: ""
    property int selected: 0

    readonly property int rowHeight: 32
    readonly property int maxRows: 8

    spacing: 10

    function refresh() {
        Quickshell.execDetached(["python3", search.engine, search.query]);
    }

    function parse(raw) {
        try {
            let j = JSON.parse(raw || "{}");
            // ответ на прошлый запрос не применяем — иначе строки «отстают»
            if ((j.query || "") !== search.query.trim())
                return;
            search.rows = j.rows || [];
            search.selected = 0;
        } catch (e) {
        }
    }

    function move(step) {
        if (search.rows.length === 0)
            return;
        search.selected = Math.max(0, Math.min(search.rows.length - 1,
                                               search.selected + step));
    }

    function activate(index) {
        let r = search.rows[index >= 0 ? index : search.selected];
        if (!r)
            return;
        Quickshell.execDetached(["python3", search.engine, "--use", r.id || ""]);
        if (r.copy && r.copy !== "") {
            Quickshell.execDetached(["wl-copy", r.copy]);
        } else if (r.action && r.action !== "") {
            Quickshell.execDetached(["sh", "-c", r.action]);
        }
        Quickshell.execDetached(["qs", "ipc", "call", "panel", "close"]);
    }

    onQueryChanged: {
        search.selected = 0;
        search.refresh();
    }

    Component.onCompleted: {
        // индекс файлов обновляем при открытии — он дешёвый и живёт в фоне
        Quickshell.execDetached(["python3", search.indexer]);
        Quickshell.execDetached(["python3", search.engine, ""]);
        // поле ввода должно быть готово к печати сразу, без клика
        input.forceActiveFocus();
    }

    FileView {
        id: outView
        path: search.outFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: search.parse(typeof text === "function" ? text() : text)
    }

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

            // Поле с печатающимся текстом: символы проявляются по одному
            TypeInput {
                id: input
                anchors.fill: parent
                textColor: Colors.text
                fontPixelSize: 14
                placeholder: Lang.t("поиск: приложения, окна, файлы, 2+2*3, «:» эмодзи, «>» команда")
                onEdited: value => search.query = value
                onAccepted: search.activate(-1)

                onKeyPressed: (key, event) => {
                    switch (key) {
                    case Qt.Key_Down:
                    case Qt.Key_Tab:
                        search.move(1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Up:
                    case Qt.Key_Backtab:
                        search.move(-1);
                        event.accepted = true;
                        break;
                    case Qt.Key_PageDown:
                        search.move(search.maxRows);
                        event.accepted = true;
                        break;
                    case Qt.Key_PageUp:
                        search.move(-search.maxRows);
                        event.accepted = true;
                        break;
                    case Qt.Key_Home:
                        search.selected = 0;
                        event.accepted = true;
                        break;
                    case Qt.Key_End:
                        search.selected = search.rows.length - 1;
                        event.accepted = true;
                        break;
                    }
                }
            }
        }
    }

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(1, Math.min(search.rows.length, search.maxRows))
                               * search.rowHeight
        clip: true
        model: search.rows
        spacing: 1
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: row

            required property var modelData
            required property int index

            readonly property bool calc: row.modelData.kind === "calc"
                                        || row.modelData.kind === "translate"
            readonly property bool web: row.modelData.kind === "web"

            width: list.width
            height: search.rowHeight

            Rectangle {
                anchors.fill: parent
                color: (row.index === search.selected || rowHover.containsMouse)
                       ? Colors.selected : "transparent"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    text: row.modelData.title
                    font.pixelSize: row.calc ? 15 : 13
                    font.bold: row.calc
                    color: row.calc ? Colors.accent
                           : (row.web ? Colors.dim : Colors.text)
                    elide: Text.ElideRight
                }

                Label {
                    text: row.modelData.hint || ""
                    font.pixelSize: 10
                    color: Qt.alpha(Colors.dim, 0.8)
                    elide: Text.ElideRight
                    Layout.maximumWidth: 320
                }
            }

            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: search.selected = row.index
                onClicked: search.activate(row.index)
            }
        }
    }
}
