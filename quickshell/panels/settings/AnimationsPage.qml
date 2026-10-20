import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Анимации»: окна (swayfx), панели, сайдбар и уведомления.
//
// Состояние — в ~/.config/quickshell/animations.json, правит его
// scripts/animations.py. Длительность окон применяется сразу через
// `swaymsg animation_duration_ms` (0 — выключить), остальное читает
// Animations.qml, поэтому переключатели действуют без перезапуска.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/animations.py"

    property var state: ({ window_ms: 180, panels: true, sidebar: true, toasts: true })

    spacing: 14

    function apply(raw) {
        try {
            const data = JSON.parse((raw || "").trim() || "{}");
            if (data && typeof data === "object")
                page.state = data;
        } catch (e) {
        }
    }

    function call(args) {
        action.command = ["python3", page.script].concat(args);
        action.running = false;
        action.running = true;
    }

    Process {
        id: action
        command: ["python3", page.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: page.apply(text)
        }
    }

    Timer {
        id: windowSave
        interval: 250
        repeat: false
        onTriggered: page.call(["window_ms", String(Math.round(page.state.window_ms))])
    }

    Component.onCompleted: action.running = true

    // ── окна ────────────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Окна")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Label {
            text: Lang.t("Появление и закрытие")
            color: Colors.text
            font.pixelSize: 12
        }

        Slider {
            Layout.fillWidth: true
            from: 0
            to: 800
            value: Number(page.state.window_ms) || 0
            onMoved: v => {
                page.state = Object.assign({}, page.state, { window_ms: Math.round(v) });
                windowSave.restart();
            }
        }

        Label {
            text: Math.round(Number(page.state.window_ms) || 0) + Lang.t(" мс")
            color: Colors.text
            font.pixelSize: 11
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Это swayfx: окна проявляются и гаснут. 0 мс — без анимации, "
                     + "дольше 500 мс — уже тяжело для глаза.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }

    // ── панели, сайдбар, уведомления ───────────────────────────────────────
    Label {
        text: Lang.t("Панели и окошки")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Repeater {
        model: [
            { key: "panels", name: Lang.t("Панели: проявление и лёгкий масштаб") },
            { key: "sidebar", name: Lang.t("Сайдбар: выезд из-за края") },
            { key: "toasts", name: Lang.t("Уведомления: выезд справа") }
        ]

        delegate: Item {
            id: animRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 30

            RowLayout {
                anchors.fill: parent
                spacing: 9

                CheckBox { checked: page.state[animRow.modelData.key] !== false }

                Label {
                    Layout.fillWidth: true
                    text: animRow.modelData.name
                    color: Colors.text
                    font.pixelSize: 12
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.call([animRow.modelData.key,
                                      page.state[animRow.modelData.key] === false])
            }
        }
    }
}
