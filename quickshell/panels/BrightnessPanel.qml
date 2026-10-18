import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

ColumnLayout {
    id: p

    property int percent: 0

    spacing: 10

    Process {
        id: getProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",");
                if (parts.length >= 4) {
                    const v = parseInt(parts[3], 10);
                    if (!isNaN(v)) p.percent = v;
                }
            }
        }
    }

    Process { id: setProc }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!getProc.running && !slider.dragging) getProc.running = true
    }

    Label {
        Layout.fillWidth: true
        text: Lang.t("Подсветка экрана")
        color: Colors.dim
        font.pixelSize: 11
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Slider {
            id: slider
            Layout.fillWidth: true
            from: 1
            to: 100
            value: p.percent
            onMoved: (v) => {
                p.percent = Math.round(v);
                setProc.running = false;
                setProc.command = ["brightnessctl", "set", p.percent + "%"];
                setProc.running = true;
            }
        }
        Label {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: p.percent + "%"
            color: Colors.text
            font.pixelSize: 13
            font.bold: true
        }
    }
}
