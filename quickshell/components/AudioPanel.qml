import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../singletons"

// Общая панель для вывода (sink) и ввода (source).
ColumnLayout {
    id: p

    property bool forSource: false
    property string sectionTitle: ""

    readonly property var node: p.forSource ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property bool ready: p.node !== null && p.node.audio !== null

    spacing: 9

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    PwNodePeakMonitor {
        id: peaks
        node: p.node
        enabled: true
    }

    Label {
        Layout.fillWidth: true
        visible: p.sectionTitle !== ""
        text: p.sectionTitle
        color: Colors.text
        font.pixelSize: 12
        font.bold: true
    }

    Label {
        Layout.fillWidth: true
        text: p.ready ? (p.node.nickname || p.node.description || p.node.name) : Lang.t("устройство не найдено")
        color: Colors.dim
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Slider {
            Layout.fillWidth: true
            from: 0
            to: 150
            value: p.ready ? p.node.audio.volume * 100 : 0
            fillColor: p.ready && p.node.audio.muted ? Colors.red : Colors.accent
            onMoved: (v) => {
                if (!p.ready) return;
                p.node.audio.volume = v / 100;
                if (v > 0 && p.node.audio.muted) p.node.audio.muted = false;
            }
        }
        Label {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: (p.ready ? Math.round(p.node.audio.volume * 100) : 0) + "%"
            color: Colors.text
            font.pixelSize: 13
            font.bold: true
        }
    }

    Bar {
        Layout.fillWidth: true
        barHeight: 2
        value: peaks.peak
        fillColor: Colors.muted
        trackColor: Colors.surface
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: p.ready && p.node.audio.muted ? Colors.red : Colors.border

        Label {
            anchors.centerIn: parent
            text: p.ready && p.node.audio.muted ? Lang.t("Вернуть звук") : Lang.t("Без звука")
            color: p.ready && p.node.audio.muted ? Colors.red : Colors.accent
            font.pixelSize: 12
        }
        MouseArea {
            anchors.fill: parent
            onClicked: { if (p.ready) p.node.audio.muted = !p.node.audio.muted; }
        }
    }

    Label {
        Layout.fillWidth: true
        topPadding: 2
        text: p.forSource ? Lang.t("Устройства ввода") : Lang.t("Устройства вывода")
        color: Colors.dim
        font.pixelSize: 11
    }

    Repeater {
        model: Pipewire.nodes

        delegate: Rectangle {
            required property var modelData

            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 26 : 0
            implicitHeight: 26
            radius: 6
            visible: !modelData.isStream
                && ((modelData.type & PwNodeType.Audio) !== 0)
                && (p.forSource
                    ? ((modelData.type & PwNodeType.Source) !== 0)
                    : ((modelData.type & PwNodeType.Sink) !== 0))
            color: (modelData === p.node) ? Colors.selected : "transparent"

            Label {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.nickname || modelData.description || modelData.name
                color: (modelData === p.node) ? Colors.text : Colors.accent
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (p.forSource) Pipewire.preferredDefaultAudioSource = modelData;
                    else Pipewire.preferredDefaultAudioSink = modelData;
                }
            }
        }
    }
}
