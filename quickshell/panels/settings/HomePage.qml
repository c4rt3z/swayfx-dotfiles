import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../singletons"
import "../../singletons"

// Главная страница меню настроек: чьи это дотфайлы и что за система.
//
// Название, автор, описание и ссылка на репозиторий берутся из
// ~/.config/quickshell/settings.json — правь там, страница перечитает файл сама.
// Сведения о системе собирает scripts/system-info.sh (ключ<TAB>значение).
ColumnLayout {
    id: page

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string metaPath: home + "/.config/quickshell/settings.json"
    readonly property string sysInfoScript: home + "/.config/quickshell/scripts/system-info.sh"

    // значения, пока JSON не прочитан
    property string dotfilesName: Lang.t("Дотфайлы")
    property string author: ""
    property string repo: ""
    property string description: ""

    property var info: []
    property bool scanning: true

    spacing: 16

    // ── шапка ───────────────────────────────────────────────────────────────

    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        Label {
            text: "\uf303"
            font.pixelSize: 44
            color: Colors.accent
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            Label {
                Layout.fillWidth: true
                text: page.dotfilesName
                font.pixelSize: 22
                font.bold: true
                color: Colors.accent
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: page.description
                font.pixelSize: 12
                color: Colors.dim
                visible: page.description !== ""
                elide: Text.ElideRight
            }

            RowLayout {
                spacing: 14

                Label {
                    text: page.author
                    font.pixelSize: 12
                    color: Colors.text
                    visible: page.author !== ""
                }

                Label {
                    text: page.repo
                    font.pixelSize: 12
                    color: repoArea.containsMouse ? Colors.accent : Colors.dim
                    visible: page.repo !== ""

                    MouseArea {
                        id: repoArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["xdg-open", page.repo])
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.border
    }

    // ── система ─────────────────────────────────────────────────────────────

    Label {
        text: Lang.t("Система")
        font.pixelSize: 11
        font.bold: true
        color: Colors.dim
        visible: page.info.length > 0
    }

    Repeater {
        model: page.info

        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 12

            Label {
                Layout.preferredWidth: 118
                text: modelData.k
                font.pixelSize: 12
                color: Colors.dim
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: modelData.v
                font.pixelSize: 12
                color: Colors.text
                elide: Text.ElideRight
            }
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        verticalAlignment: Text.AlignTop
        text: page.scanning ? Lang.t("собираю сведения…") : Lang.t("сведения о системе не собрались")
        color: Colors.dim
        font.pixelSize: 12
        visible: page.info.length === 0
    }

    // ── данные ──────────────────────────────────────────────────────────────

    FileView {
        id: metaView
        path: page.metaPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            raw = (raw || "").trim();
            if (raw === "")
                return;
            try {
                let j = JSON.parse(raw);
                page.dotfilesName = j.dotfilesName || page.dotfilesName;
                page.author = j.author || "";
                page.repo = j.repo || "";
                page.description = j.description || "";
            } catch (e) {
                page.description = Lang.t("settings.json не читается — проверьте запятые");
            }
        }
    }

    Process {
        id: infoProc
        command: ["sh", page.sysInfoScript]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                let lines = (this.text || "").split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let p = lines[i].split("\t");
                    if (p.length >= 2 && p[0].trim() !== "")
                        out.push({ k: p[0].trim(), v: p[1] });
                }
                page.info = out;
                page.scanning = false;
            }
        }
    }

    Component.onCompleted: infoProc.running = true
}
