import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Переключатель окон: Alt+Tab.
//
// Список окон отдаёт scripts/switcher.py (swaymsg -t get_tree). Панель
// открывается с выбранным следующим окном — как классический Alt+Tab: одно
// нажатие и Enter переключает на соседнее, стрелки листают дальше.
//
// Фокус забирает сама панель (клавиатура у неё эксклюзивная), поэтому
// стрелки и Enter ловит корневой элемент.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""

    property var windows: []
    property int selected: 0

    spacing: 8

    focus: true

    function appIcon(app) {
        const a = String(app || "").toLowerCase();
        if (a.indexOf("firefox") >= 0 || a.indexOf("chrom") >= 0 || a.indexOf("zen") >= 0)
            return "\uf0ac";
        if (a.indexOf("telegram") >= 0)
            return "\uf2c6";
        if (a.indexOf("term") >= 0 || a.indexOf("kitty") >= 0 || a.indexOf("alacritty") >= 0
                || a.indexOf("foot") >= 0 || a.indexOf("wezterm") >= 0)
            return "\uf120";
        if (a.indexOf("code") >= 0 || a.indexOf("codium") >= 0)
            return "\uf121";
        if (a.indexOf("spotify") >= 0 || a.indexOf("music") >= 0)
            return "\uf001";
        if (a.indexOf("mpv") >= 0 || a.indexOf("vlc") >= 0)
            return "\uf03d";
        if (a.indexOf("thunar") >= 0 || a.indexOf("nautilus") >= 0 || a.indexOf("dolphin") >= 0)
            return "\uf07b";
        return "\uf2d0";
    }

    function move(step) {
        if (page.windows.length === 0)
            return;
        page.selected = (page.selected + step + page.windows.length) % page.windows.length;
        strip.positionViewAtIndex(page.selected, ListView.Center);
    }

    function activate(index) {
        const i = index >= 0 ? index : page.selected;
        const w = page.windows[i];
        if (!w)
            return;
        // сначала закрываем панель: композитор вернёт фокус старому окну,
        // и только потом sway переключится на выбранное
        Quickshell.execDetached(["sh", "-c",
            "qs ipc call panel close; sleep 0.12; swaymsg '[con_id=" + w.id + "] focus'"]);
    }

    function load(raw) {
        let list = [];
        try {
            const data = JSON.parse(raw || "{}");
            list = Array.isArray(data.windows) ? data.windows : [];
        } catch (e) {
            list = [];
        }
        page.windows = list;
        // по умолчанию — следующее за активным, как Alt+Tab
        const focused = list.findIndex(w => w.focused);
        page.selected = list.length > 1 ? (focused + 1 + list.length) % list.length
                                        : Math.max(0, focused);
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Right:
        case Qt.Key_Down:
        case Qt.Key_Tab:
            page.move(1);
            event.accepted = true;
            break;
        case Qt.Key_Left:
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            page.move(-1);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            page.activate(-1);
            event.accepted = true;
            break;
        default:
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const n = event.key - Qt.Key_1;
                if (n < page.windows.length) {
                    page.selected = n;
                    page.activate(n);
                }
                event.accepted = true;
            }
        }
    }

    Component.onCompleted: {
        page.forceActiveFocus();
        windowsProcess.running = true;
    }

    Process {
        id: windowsProcess
        command: ["python3", page.home + "/.config/quickshell/scripts/switcher.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: page.load(text)
        }
    }

    // ── шапка ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: page.windows.length > 0
        spacing: 8

        Label {
            text: "\uf108"
            color: Colors.accent
            font.pixelSize: 13
        }

        Label {
            Layout.fillWidth: true
            text: Lang.t("Переключение окон")
            color: Colors.text
            font.pixelSize: 13
            font.bold: true
        }

        Label {
            text: page.windows.length
            color: Colors.dim
            font.pixelSize: 11
        }
    }

    // ── список окон ───────────────────────────────────────────────────────
    ListView {
        id: strip

        Layout.fillWidth: true
        Layout.preferredHeight: page.windows.length === 0
                             ? 34
                             : Math.min(page.windows.length, 8) * 46 + 6
        visible: page.windows.length > 0
        orientation: ListView.Vertical
        spacing: 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.windows

        delegate: Item {
            id: card

            required property var modelData
            required property int index

            width: strip.width
            height: 44

            readonly property bool current: page.selected === card.index

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: card.current ? Colors.selected : "transparent"
                border.width: 1
                border.color: card.current ? Colors.accent : "transparent"
            }

            // слева — полоска активного окна
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: card.current ? 22 : 0
                radius: 1.5
                color: Colors.accent
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Label {
                    text: page.appIcon(card.modelData.app)
                    color: card.current ? Colors.accent : Colors.muted
                    font.pixelSize: 15
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Label {
                            text: card.modelData.app || Lang.t("окно")
                            color: card.current ? Colors.text : Colors.muted
                            font.pixelSize: 11
                            font.bold: card.current
                            elide: Text.ElideRight
                        }

                        Label {
                            text: card.modelData.focused ? Lang.t("активное") : ""
                            color: Colors.accent
                            font.pixelSize: 9
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: card.modelData.title || ""
                        color: card.current ? Colors.text : Qt.alpha(Colors.dim, 0.9)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Label {
                    text: card.modelData.workspace || ""
                    color: Qt.alpha(Colors.dim, 0.7)
                    font.pixelSize: 10
                }

                Label {
                    text: (card.index + 1)
                    color: card.current ? Colors.accent : Qt.alpha(Colors.dim, 0.6)
                    font.pixelSize: 10
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: page.selected = card.index
                onClicked: page.activate(card.index)
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: page.windows.length === 0
        text: Lang.t("Нет открытых окон")
        color: Colors.dim
        font.pixelSize: 12
    }

    // ── подсказка ──────────────────────────────────────────────────────────
    Label {
        Layout.fillWidth: true
        visible: page.windows.length > 0
        text: Lang.t("↑ ↓ выбрать") + "  ·  " + Lang.t("Enter перейти") + "  ·  "
              + Lang.t("1–9 сразу") + "  ·  Esc " + Lang.t("закрыть")
        color: Qt.alpha(Colors.dim, 0.8)
        font.pixelSize: 9
    }
}
