import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../components"
import "../singletons"

ColumnLayout {
    id: p

    property var d: UPower.displayDevice
    property bool ok: p.d !== null && p.d.ready

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
}
