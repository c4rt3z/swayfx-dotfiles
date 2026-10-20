import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Сайдбар»: сторона, ширина, подписи, сетка плиток и виджеты.
//
// Своего состояния страница не держит: правда в ~/.config/quickshell/sidebar.json,
// пишет её scripts/sidebar-settings.py, а Sidebar читает файл с watchChanges.
// Поэтому после каждого щелчка просто перечитываем состояние.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/sidebar-settings.py"

    property var cfg: ({
        side: "left", width: 24, labels: true, grid: "2x3",
        widgets: { weather: true, now: true, session: true, shots: true,
                   clipboard: true, notifications: true }
    })
    property int widthValue: 24

    spacing: 14

    function apply(raw) {
        try {
            const data = JSON.parse((raw || "").trim() || "{}");
            if (!data || typeof data !== "object")
                return;
            page.cfg = data;
            page.widthValue = Math.round(Number(data.width) || 24);
        } catch (e) {
        }
    }

    function set(key, value) {
        change.command = ["python3", page.script, "set", key, String(value)];
        change.running = true;
    }

    function widget(name) {
        const map = page.cfg.widgets || ({});
        return map[name] !== false;
    }

    Timer {
        id: widthSave
        interval: 250
        repeat: false
        onTriggered: page.set("width", page.widthValue)
    }

    Process {
        id: change
        command: ["python3", page.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                page.apply(text);
                Sidebar.apply_soon();
            }
        }
    }

    Component.onCompleted: change.running = true

    // ── сторона ─────────────────────────────────────────────────────────────
    Label { text: Lang.t("Сторона экрана"); font.pixelSize: 11; font.bold: true; color: Colors.dim }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { key: "left", name: Lang.t("Слева"), icon: "\uf060" },
                { key: "right", name: Lang.t("Справа"), icon: "\uf061" }
            ]

            delegate: Item {
                id: sideRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 34

                readonly property bool current: page.cfg.side === modelData.key

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: sideRow.current ? Colors.selected : "transparent"
                    border.width: 1
                    border.color: sideRow.current ? Colors.accent
                                : (sideHover.containsMouse ? Colors.border : Colors.divider)
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7

                    Label {
                        text: modelData.icon
                        color: sideRow.current ? Colors.accent : Colors.muted
                        font.pixelSize: 12
                    }
                    Label {
                        text: modelData.name
                        color: sideRow.current ? Colors.text : Colors.muted
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: sideHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.set("side", modelData.key)
                }
            }
        }
    }

    // ── ширина ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Label {
            text: Lang.t("Ширина")
            font.pixelSize: 11
            font.bold: true
            color: Colors.dim
        }

        Slider {
            Layout.fillWidth: true
            from: 16
            to: 40
            value: page.widthValue
            onMoved: v => {
                page.widthValue = Math.round(v);
                widthSave.restart();
            }
        }

        Label {
            text: page.widthValue + "%"
            color: Colors.text
            font.pixelSize: 11
        }
    }

    // ── подписи и сетка ─────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        implicitHeight: 30

        RowLayout {
            anchors.fill: parent
            spacing: 9

            CheckBox { checked: page.cfg.labels !== false }
            Label {
                Layout.fillWidth: true
                text: Lang.t("Подписи у кнопок сессии")
                color: Colors.text
                font.pixelSize: 12
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: page.set("labels", page.cfg.labels === false)
        }
    }

    Label {
        text: Lang.t("Сетка плиток сессии")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { key: "2x3", name: "2 × 3", note: Lang.t("две в ряд") },
                { key: "3x2", name: "3 × 2", note: Lang.t("три в ряд") }
            ]

            delegate: Item {
                id: gridRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 34

                readonly property bool current: page.cfg.grid === modelData.key

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: gridRow.current ? Colors.selected : "transparent"
                    border.width: 1
                    border.color: gridRow.current ? Colors.accent
                                : (gridHover.containsMouse ? Colors.border : Colors.divider)
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7
                    Label {
                        text: modelData.name
                        color: gridRow.current ? Colors.text : Colors.muted
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Label {
                        text: modelData.note
                        color: Colors.dim
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    id: gridHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.set("grid", modelData.key)
                }
            }
        }
    }

    // ── виджеты ─────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Виджеты")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: [
                { key: "weather", name: Lang.t("Погода"), icon: "\uf185" },
                { key: "now", name: Lang.t("Сейчас играет"), icon: "\uf001" },
                { key: "session", name: Lang.t("Кнопки сессии"), icon: "\uf011" },
                { key: "shots", name: Lang.t("Снимки экрана"), icon: "\uf03e" },
                { key: "clipboard", name: Lang.t("Буфер обмена"), icon: "\uf0c5" },
            { key: "notifications", name: Lang.t("Недавние уведомления"), icon: "\uf0a3" }
            ]

            delegate: Item {
                id: widgetRow

                required property var modelData

                readonly property bool on: page.widget(modelData.key)

                Layout.fillWidth: true
                implicitHeight: 30

                RowLayout {
                    anchors.fill: parent
                    spacing: 9

                    CheckBox { checked: widgetRow.on }
                    Label {
                        text: modelData.icon
                        color: widgetRow.on ? Colors.accent : Colors.dim
                        font.pixelSize: 12
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: Colors.text
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.set("widget." + modelData.key, !widgetRow.on)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Item {
            implicitWidth: 130
            implicitHeight: 28

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: resetHover.containsMouse ? Colors.selected : "transparent"
                border.width: 1
                border.color: resetHover.containsMouse ? Colors.accent : Colors.divider
            }

            Label {
                anchors.centerIn: parent
                text: Lang.t("Сбросить")
                color: resetHover.containsMouse ? Colors.text : Colors.muted
                font.pixelSize: 11
            }

            MouseArea {
                id: resetHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    change.command = ["python3", page.script, "reset"];
                    change.running = true;
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: Lang.t("Виджеты можно двигать только включением; порядок — погода, трек, сессия, снимки, буфер.")
            color: Colors.dim
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }
    }
}
