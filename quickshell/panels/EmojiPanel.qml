import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Выбор эмодзи (Super+., как в Windows). Клик кладёт эмодзи в буфер обмена
// и закрывает панель. Поиск — по английскому названию и по русским словам
// (список готовит scripts/emoji-index.py).
ColumnLayout {
    id: emoji

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string indexer: home + "/.config/quickshell/scripts/emoji-index.py"
    // свой шрифт эмодзи: ~/.config/quickshell/emoji.json
    property string emojiFont: "Noto Color Emoji"

    FileView {
        path: home + "/.config/quickshell/emoji.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const raw = typeof text === "function" ? text() : text;
                const data = JSON.parse(raw || "{}");
                if (data && data.font)
                    emoji.emojiFont = data.font;
            } catch (e) {
            }
        }
    }
    readonly property string cacheFile: home + "/.cache/quickshell/emoji.json"

    property var items: []
    property string query: ""
    property string hoveredName: ""
    property string copied: ""

    readonly property var results: {
        let q = emoji.query.trim().toLowerCase();
        if (q === "")
            return emoji.items;
        return emoji.items.filter(i => i.search.indexOf(q) >= 0);
    }

    spacing: 10

    function copy(glyph) {
        if (!glyph)
            return;
        Quickshell.execDetached(["wl-copy", glyph]);
        emoji.copied = glyph;
        Quickshell.execDetached(["qs", "ipc", "call", "panel", "close"]);
    }

    Process {
        id: indexProc
        command: ["python3", emoji.indexer]
        Component.onCompleted: running = true
    }

    // панель открывается на Super+. — печатать в неё надо сразу, без клика
    Component.onCompleted: emojiInput.forceActiveFocus()

    FileView {
        id: cacheView
        path: emoji.cacheFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                let j = JSON.parse(raw || "{}");
                emoji.items = j.items || [];
            } catch (e) {
            }
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
                visible: emojiInput.text === ""
                text: Lang.t("поиск: огонь, heart, ракета…")
                color: Colors.dim
                font.pixelSize: 13
            }

            TextInput {
                id: emojiInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: Fonts.panelFamily
                font.pixelSize: 14
                selectionColor: Colors.accent
                selectedTextColor: Colors.onAccent
                selectByMouse: false
                onTextChanged: emoji.query = text
                onAccepted: emoji.copy(emoji.results.length > 0 ? emoji.results[0].e : "")

                cursorDelegate: Rectangle {
                    width: 2
                    color: Colors.accent
                }

                Keys.onEscapePressed: Quickshell.execDetached(
                    ["qs", "ipc", "call", "panel", "close"])
            }
        }
    }

    GridView {
        id: grid

        Layout.fillWidth: true
        Layout.preferredHeight: 372
        clip: true
        cellWidth: 42
        cellHeight: 42
        model: emoji.results
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: cell

            required property var modelData

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                color: cellHover.containsMouse ? Colors.selected : "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: cell.modelData.e
                // эмодзи рисуем отдельным шрифтом: в Nerd Font половина глифов
                // отсутствует, и они выглядят квадратами
                font.family: emoji.emojiFont
                font.pixelSize: 22
            }

            MouseArea {
                id: cellHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: emoji.hoveredName = cell.modelData.name
                onExited: emoji.hoveredName = ""
                onClicked: emoji.copy(cell.modelData.e)
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: emoji.hoveredName !== ""
              ? emoji.hoveredName
              : (emoji.results.length + Lang.t(" эмодзи · Enter копирует верхний, ")
                 + Lang.t("клик — скопировать и закрыть"))
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        elide: Text.ElideRight
    }
}
