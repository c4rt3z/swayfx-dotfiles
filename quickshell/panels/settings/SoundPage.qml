import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"

// Раздел «Звук»: вывод, профили звуковой карты и эквалайзер.
//
// Эквалайзер — не свой, а EasyEffects: страница только показывает его пресеты,
// обход и состояние службы. Всё состояние читает scripts/audio.py (pactl и сам
// easyeffects), он же печатает новое состояние после каждого действия —
// поэтому список устройств и пресетов обновляется сам, без перезапуска.
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string script: home + "/.config/quickshell/scripts/audio.py"

    property var state: ({
        ok: false, sink: "", sinks: [], volume: 0, muted: false, cards: [],
        ee: { service: false, bypass: false, presets: [], preset: "" }
    })

    spacing: 14

    function apply(raw) {
        try {
            const data = JSON.parse((raw || "").trim() || "{}");
            if (data && data.ok)
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
        id: volumeSave
        interval: 250
        repeat: false
        onTriggered: page.call(["volume", String(Math.round(page.state.volume))])
    }

    Component.onCompleted: action.running = true

    // ── громкость ───────────────────────────────────────────────────────────
    Label {
        text: Lang.t("Громкость вывода")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Label {
            text: page.state.muted ? "\uf026" : "\uf028"
            color: page.state.muted ? Colors.red : (muteHover.containsMouse ? Colors.accent : Colors.text)
            font.pixelSize: 13

            MouseArea {
                id: muteHover
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: page.call(["mute", "toggle"])
            }
        }

        Slider {
            Layout.fillWidth: true
            from: 0
            to: 150
            value: page.state.volume
            onMoved: v => {
                page.state = Object.assign({}, page.state, { volume: Math.round(v) });
                volumeSave.restart();
            }
        }

        Label {
            text: Math.round(page.state.volume) + "%"
            color: Colors.text
            font.pixelSize: 11
        }
    }

    // ── устройства вывода ───────────────────────────────────────────────────
    Label {
        text: Lang.t("Устройство вывода")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.state.sinks

            delegate: Item {
                id: sinkRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 30

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "\uf028"
                        color: modelData.default ? Colors.accent : Colors.dim
                        font.pixelSize: 12
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.desc
                        color: modelData.default ? Colors.text : Colors.muted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Label {
                        visible: modelData.default
                        text: Lang.t("выбран")
                        color: Colors.accent
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.call(["sink", sinkRow.modelData.name])
                }
            }
        }
    }

    // ── эквалайзер (EasyEffects) ────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 30

        RowLayout {
            anchors.fill: parent
            spacing: 9

            CheckBox { checked: page.state.ee && page.state.ee.bypass === true }

            Label {
                Layout.fillWidth: true
                text: Lang.t("Обход эффектов (эквалайзер выключен)")
                color: Colors.text
                font.pixelSize: 12
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.call(["bypass",
                page.state.ee && page.state.ee.bypass ? "off" : "on"])
        }
    }

    // Служба EasyEffects: без неё ни пресеты, ни обход не действуют.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: "\uf1de"
            color: page.state.ee && page.state.ee.service ? Colors.accent : Colors.dim
            font.pixelSize: 12
        }

        Label {
            Layout.fillWidth: true
            text: page.state.ee && page.state.ee.service
                  ? Lang.t("Служба EasyEffects работает")
                  : Lang.t("Служба EasyEffects не запущена")
            color: Colors.text
            font.pixelSize: 12
        }

        Label {
            text: page.state.ee && page.state.ee.service
                  ? Lang.t("остановить") : Lang.t("запустить")
            color: eeHover.containsMouse ? Colors.accent : Colors.dim
            font.pixelSize: 11

            MouseArea {
                id: eeHover
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                onClicked: page.call(["ee",
                    page.state.ee && page.state.ee.service ? "stop" : "start"])
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: page.state.ee && page.state.ee.presets.length > 0
                  ? Lang.t("Пресеты эквалайзера")
                  : Lang.t("Пресетов нет — добавьте их в EasyEffects")
            font.pixelSize: 11
            font.bold: true
            color: Colors.dim
        }

        Label {
            text: Lang.t("обновить")
            color: refreshHover.containsMouse ? Colors.accent : Colors.dim
            font.pixelSize: 11

            MouseArea {
                id: refreshHover
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                onClicked: page.call(["state"])
            }
        }

        Label {
            text: Lang.t("открыть EasyEffects")
            color: openHover.containsMouse ? Colors.accent : Colors.dim
            font.pixelSize: 11

            MouseArea {
                id: openHover
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                onClicked: page.call(["open"])
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: page.state.ee ? page.state.ee.presets : []

            delegate: Item {
                id: presetRow

                required property var modelData

                readonly property bool current: page.state.ee
                                               && page.state.ee.preset === presetRow.modelData

                Layout.fillWidth: true
                implicitHeight: 28

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    text: (presetRow.current ? "\uf04b  " : "    ") + presetRow.modelData
                    color: presetRow.current ? Colors.accent
                           : (presetHover.containsMouse ? Colors.text : Colors.muted)
                    font.pixelSize: 12
                }

                MouseArea {
                    id: presetHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.call(["preset", presetRow.modelData])
                }
            }
        }
    }

    // ── профили звуковой карты ──────────────────────────────────────────────
    Label {
        Layout.fillWidth: true
        text: Lang.t("Профили звуковой карты")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
    }

    Repeater {
        model: page.state.cards

        delegate: ColumnLayout {
            id: cardBox

            required property var modelData

            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: cardBox.modelData.profiles

                delegate: Item {
                    id: profRow

                    required property var modelData

                    readonly property bool current: profRow.modelData.name === cardBox.modelData.profile

                    Layout.fillWidth: true
                    implicitHeight: 28

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        width: parent.width - 4
                        text: {
                            const mark = profRow.current ? "\uf04b  " : "    ";
                            const head = cardBox.modelData.desc !== ""
                                ? cardBox.modelData.desc + " · " : "";
                            return mark + head + profRow.modelData.desc;
                        }
                        color: profRow.modelData.available === false ? Qt.alpha(Colors.dim, 0.55)
                               : (profRow.current ? Colors.accent
                                  : (profHover.containsMouse ? Colors.text : Colors.muted))
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: profHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: profRow.modelData.available !== false
                        onClicked: page.call(["profile", cardBox.modelData.name,
                                              profRow.modelData.name])
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Эквалайзер и пресеты ведёт EasyEffects (easyeffects --service-mode); "
                     + "профили карты — pactl. Меняется всё сразу, без перезапуска.")
        font.pixelSize: 10
        color: Qt.alpha(Colors.dim, 0.8)
        wrapMode: Text.WordWrap
    }
}
