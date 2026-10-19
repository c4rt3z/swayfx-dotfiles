import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../components"
import "../singletons"

ColumnLayout {
    id: p

    property var d: UPower.displayDevice
    property bool ok: p.d !== null && p.d.ready
    // автоблокировка по простою: включена, пока нет файла-флага
    property bool autoLock: true

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string lockFlag: home + "/.config/quickshell/no-auto-lock"


    spacing: 9

    function stateText(): string {
        if (p.d === null) return "—";
        if (p.d.state === UPowerDeviceState.Charging) return Lang.t("заряжается");
        if (p.d.state === UPowerDeviceState.Discharging) return Lang.t("разряжается");
        if (p.d.state === UPowerDeviceState.FullyCharged) return Lang.t("заряжена");
        if (p.d.state === UPowerDeviceState.Empty) return Lang.t("разряжена");
        if (p.d.state === UPowerDeviceState.PendingCharge) return Lang.t("ожидает зарядки");
        if (p.d.state === UPowerDeviceState.PendingDischarge) return Lang.t("ожидает разряда");
        return "—";
    }

    function fmtTime(sec: double): string {
        if (!isFinite(sec) || sec <= 0) return "—";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return h + Lang.t(" ч ") + m + Lang.t(" мин");
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            Layout.fillWidth: true
            text: p.ok ? (p.d.model || Lang.t("Батарея")) : Lang.t("Батарея не найдена")
            color: Colors.accent
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Label {
            text: p.ok ? Math.round(p.d.percentage * 100) + "%" : "—"
            color: Colors.text
            font.pixelSize: 15
            font.bold: true
        }
    }

    Bar {
        Layout.fillWidth: true
        barHeight: 6
        value: p.ok ? p.d.percentage : 0
        fillColor: (p.ok && p.d.percentage <= 0.15)
            ? Colors.red
            : (p.ok && p.d.state === UPowerDeviceState.Charging ? Colors.dim : Colors.accent)
    }

    Label {
        Layout.fillWidth: true
        text: p.ok ? p.stateText() : "—"
        color: Colors.accent
        font.pixelSize: 11
    }

    Label {
        Layout.fillWidth: true
        text: p.ok && p.d.state === UPowerDeviceState.Charging
            ? Lang.t("до полного: ") + p.fmtTime(p.d.timeToFull)
            : Lang.t("осталось: ") + p.fmtTime(p.d.timeToEmpty)
        color: Colors.dim
        font.pixelSize: 11
    }

    Label {
        Layout.fillWidth: true
        text: (p.ok ? p.d.energy.toFixed(1) + " / " + p.d.energyCapacity.toFixed(1) + Lang.t(" Вт·ч") : "—")
            + (p.ok ? "   ·   " + Math.abs(p.d.changeRate).toFixed(1) + Lang.t(" Вт") : "")
        color: Colors.dim
        font.pixelSize: 11
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colors.divider
    }

    // Автоблокировка по простою (swayidle, 5 минут). Тумблер ставит или снимает
    // файл-флаг — перезапускать swayidle не нужно, скрипт проверяет флаг сам.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                Layout.fillWidth: true
                text: Lang.t("Автоблокировка по простою")
                color: Colors.text
                font.pixelSize: 11
            }
            Label {
                Layout.fillWidth: true
                text: p.autoLock ? Lang.t("включена, 5 мин") : Lang.t("выключена")
                color: p.autoLock ? Colors.dim : Colors.muted
                font.pixelSize: 10
            }
        }

        Item {
            implicitWidth: 38
            implicitHeight: 20

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: p.autoLock ? Qt.alpha(Colors.accent, 0.35) : Colors.track
                border.width: 1
                border.color: p.autoLock ? Colors.accent : Colors.border
            }
            Rectangle {
                width: 14
                height: 14
                radius: 7
                y: 3
                x: p.autoLock ? parent.width - 17 : 3
                color: p.autoLock ? Colors.accent : Colors.dim
                Behavior on x { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    p.autoLock = !p.autoLock;
                    lockToggle.running = true;
                }
            }
        }
    }

    FileView {
        id: lockFlagView
        path: p.lockFlag
        watchChanges: true
        onLoaded: p.autoLock = false
        onLoadFailed: p.autoLock = true
        onFileChanged: reload()
    }

    // Тумблер: скрипт ставит/снимает флаг и, если swayidle ещё держит старую
    // команду из конфига, перезапускает его — иначе переключатель начинал бы
    // работать только после перезахода в сеанс.
    Process {
        id: lockToggle
        command: ["sh", p.home + "/.config/quickshell/scripts/autolock.sh", "toggle"]
        onExited: lockFlagView.reload()
    }
}
