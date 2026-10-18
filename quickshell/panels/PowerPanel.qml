import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../singletons"

// Меню сессии: открывается кнопкой питания в правом углу waybar.
//
// Опасные действия (перезапуск, выключение, выход, сон) просят второго
// нажатия — случайный клик не должен гасить машину.
ColumnLayout {
    id: power

    readonly property string home: Quickshell.env("HOME") ?? ""

    property var items: [
        { icon: "\uF023", label: Lang.t("Заблокировать"), run: "lock", confirm: false },
        { icon: "\uF007", label: Lang.t("Смена пользователя"), run: "greeter", confirm: true },
        { icon: "\uF186", label: Lang.t("Сон"), run: "suspend", confirm: true },
        { icon: "\uF08B", label: Lang.t("Выйти из сессии"), run: "logout", confirm: true },
        { icon: "\uF01E", label: Lang.t("Перезагрузить"), run: "reboot", confirm: true },
        { icon: "\uF011", label: Lang.t("Выключить"), run: "poweroff", confirm: true },
    ]
    property int armed: -1

    function close() {
        Quickshell.execDetached(["qs", "ipc", "call", "panel", "close"]);
    }

    function choose(index) {
        const item = power.items[index];
        if (item.confirm && power.armed !== index) {
            power.armed = index;
            disarmTimer.start();
            return;
        }
        power.armed = -1;
        execute(item.run);
    }

    function execute(run) {
        if (run === "lock") {
            Quickshell.execDetached(["qs", "ipc", "call", "lock", "lock"]);
            power.close();
        } else if (run === "greeter") {
            Quickshell.execDetached(["dbus-send", "--system", "--print-reply",
                "--dest=org.freedesktop.DisplayManager",
                "/org/freedesktop/DisplayManager/Seat0",
                "org.freedesktop.DisplayManager.Seat.SwitchToGreeter"]);
            power.close();
        } else if (run === "suspend") {
            Quickshell.execDetached(["systemctl", "suspend"]);
            power.close();
        } else if (run === "logout") {
            Quickshell.execDetached(["swaymsg", "exit"]);
        } else if (run === "reboot") {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (run === "poweroff") {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }

    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: power.armed = -1
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: power.items

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool armedHere: power.armed === index
                readonly property bool danger: modelData.confirm === true

                Layout.fillWidth: true
                implicitHeight: 34

                Rectangle {
                    anchors.fill: parent
                    color: row.armedHere ? Colors.selected : "transparent"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: power.armed = -1
                    onClicked: power.choose(row.index)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Label {
                        text: modelData.icon
                        color: row.armedHere ? Colors.red : Colors.accent
                        font.pixelSize: 14
                    }

                    Label {
                        Layout.fillWidth: true
                        text: row.armedHere ? modelData.label + Lang.t(" — нажмите ещё раз")
                                             : modelData.label
                        color: row.armedHere ? Colors.red : Colors.text
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
