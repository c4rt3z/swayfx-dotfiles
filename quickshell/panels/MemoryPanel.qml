import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../singletons"

// Память и процессор: обе кнопки в waybar ведут сюда.
ColumnLayout {
    id: p

    // память
    property real total: 0
    property real used: 0
    property real avail: 0
    property real swapTotal: 0
    property real swapUsed: 0
    property var topProcs: []

    // процессор
    property real cpuUsage: 0
    property var cores: []
    property real cpuTemp: 0
    property string cpuLoad: ""
    property string cpuFreq: ""
    property var prev: null

    readonly property string home: Quickshell.env("HOME") ?? ""

    spacing: 9

    Process {
        id: stats
        command: [p.home + "/.config/quickshell/scripts/mem-cpu.sh"]
        stdout: StdioCollector {
            onStreamFinished: p.parse(text)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!stats.running) stats.running = true
    }

    function parse(t: string): void {
        const iPs = t.indexOf("---PS---");
        const iStat = t.indexOf("---STAT---");
        const iStat2 = t.indexOf("---STAT2---");
        const iExtra = t.indexOf("---EXTRA---");
        if (iPs < 0 || iStat < 0 || iExtra < 0) return;
        parseMem(t.slice(0, iPs), t.slice(iPs + 8, iStat));
        parseStat(t.slice(iStat + 10, iStat2 < 0 ? iExtra : iStat2),
                  iStat2 < 0 ? "" : t.slice(iStat2 + 11, iExtra));
        parseExtra(t.slice(iExtra + 11));
    }

    // ------------------------------------------------------------- память
    function parseMem(mem: string, ps: string): void {
        const info = {};
        mem.split("\n").forEach(function (l) {
            const m = l.match(/^(\w+):\s+(\d+)\s*kB/);
            if (m) info[m[1]] = parseInt(m[2], 10) / 1048576.0;
        });
        p.total = info.MemTotal || 0;
        p.avail = info.MemAvailable || 0;
        p.used = p.total - p.avail;
        p.swapTotal = info.SwapTotal || 0;
        p.swapUsed = p.swapTotal - (info.SwapFree || 0);

        const rows = [];
        ps.trim().split("\n").forEach(function (l, i) {
            if (i === 0) return;               // шапка ps
            const m = l.trim().match(/^(\d+)\s+(.+)$/);
            if (m) rows.push({ rss: parseInt(m[1], 10) / 1024.0, name: m[2] });
        });
        p.topProcs = rows;
    }

    // ----------------------------------------------------------- процессор
    function parseCpu(t: string): var {
        const list = [];
        t.split("\n").forEach(function (l) {
            const m = l.match(/^cpu(\d*)\s+(.*)$/);
            if (!m) return;
            const vals = m[2].trim().split(/\s+/).map(Number);
            let total = 0;
            for (let i = 0; i < vals.length; i++) total += vals[i];
            const idle = vals[3] + (vals[4] || 0);
            list.push({ name: m[1] === "" ? "all" : m[1], idle: idle, total: total });
        });
        return list;
    }

    // загрузка по разнице двух замеров /proc/stat
    function usageOf(prev: var, cur: var): var {
        const list = [];
        for (let i = 0; i < cur.length && i < prev.length; i++) {
            const dt = cur[i].total - prev[i].total;
            const di = cur[i].idle - prev[i].idle;
            list.push({
                name: cur[i].name,
                usage: dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0
            });
        }
        return list;
    }

    function parseStat(t1: string, t2: string): void {
        const a = parseCpu(t1);
        if (a.length === 0) return;
        const b = parseCpu(t2);
        let list = null;
        if (b.length === a.length && b.length > 0) {
            list = usageOf(a, b);          // оба замера из текущего запуска скрипта
            p.prev = b;
        } else if (p.prev !== null && p.prev.length === a.length) {
            list = usageOf(p.prev, a);     // разница с прошлым запуском
            p.prev = a;
        } else {
            p.prev = a;
        }
        if (list !== null) {
            p.cores = list;
            p.cpuUsage = list[0].usage;
        }
    }

    function parseExtra(t: string): void {
        t.split("\n").forEach(function (l) {
            const m = l.match(/^(\w+)\s+(.+)$/);
            if (!m) return;
            if (m[1] === "load") p.cpuLoad = m[2].trim().replace(/\s+/g, "   ");
            else if (m[1] === "temp") p.cpuTemp = parseInt(m[2], 10) / 1000;
            else if (m[1] === "freq") p.cpuFreq = m[2].trim() + " MHz";
        });
    }

    // ---------------------------------------------------------------- вид
    RowLayout {
        Layout.fillWidth: true

        Label {
            Layout.fillWidth: true
            text: Lang.t("Занято")
            color: Colors.accent
            font.pixelSize: 12
        }
        Label {
            text: p.used.toFixed(2) + " / " + p.total.toFixed(2) + " GB"
            color: Colors.text
            font.pixelSize: 12
            font.bold: true
        }
    }

    Bar {
        Layout.fillWidth: true
        barHeight: 6
        value: p.total > 0 ? p.used / p.total : 0
        fillColor: (p.total > 0 && p.used / p.total > 0.85) ? Colors.red : Colors.accent
    }

    Label {
        Layout.fillWidth: true
        text: Math.round(p.total > 0 ? p.used / p.total * 100 : 0) + Lang.t("%   ·   свободно ")
            + p.avail.toFixed(2) + " GB   ·   swap " + p.swapUsed.toFixed(2) + "/" + p.swapTotal.toFixed(2) + " GB"
        color: Colors.dim
        font.pixelSize: 11
    }

    Label {
        Layout.fillWidth: true
        topPadding: 3
        text: Lang.t("По процессам")
        color: Colors.dim
        font.pixelSize: 11
    }

    Repeater {
        model: p.topProcs

        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: modelData.name
                color: Colors.accent
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Label {
                text: modelData.rss.toFixed(0) + " MB"
                color: Colors.dim
                font.pixelSize: 11
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.topMargin: 3
        color: Colors.border
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2

        Label {
            Layout.fillWidth: true
            text: Lang.t("Процессор")
            color: Colors.accent
            font.pixelSize: 12
        }
        Label {
            text: Math.round(p.cpuUsage * 100) + "%"
            color: Colors.text
            font.pixelSize: 13
            font.bold: true
        }
    }

    Bar {
        Layout.fillWidth: true
        barHeight: 6
        value: p.cpuUsage
        fillColor: p.cpuUsage > 0.85 ? Colors.red : Colors.accent
    }

    Label {
        Layout.fillWidth: true
        text: (p.cpuTemp > 0 ? p.cpuTemp.toFixed(0) + " °C" : "—")
            + "   ·   " + (p.cpuFreq !== "" ? p.cpuFreq : "—")
            + "   ·   load " + (p.cpuLoad !== "" ? p.cpuLoad : "—")
        color: Colors.dim
        font.pixelSize: 11
    }

    Label {
        Layout.fillWidth: true
        topPadding: 3
        text: Lang.t("Ядра")
        color: Colors.dim
        font.pixelSize: 11
    }

    Repeater {
        model: p.cores

        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 8
            visible: modelData.name !== "all"
            Layout.preferredHeight: visible ? implicitHeight : 0

            Label {
                Layout.preferredWidth: 30
                text: "cpu" + modelData.name
                color: Colors.dim
                font.pixelSize: 10
            }
            Bar {
                Layout.fillWidth: true
                barHeight: 4
                value: modelData.usage
                fillColor: modelData.usage > 0.85 ? Colors.red : Colors.muted
            }
            Label {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round(modelData.usage * 100) + "%"
                color: Colors.accent
                font.pixelSize: 10
            }
        }
    }
}
