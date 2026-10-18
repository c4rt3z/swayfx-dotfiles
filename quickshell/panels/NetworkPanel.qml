import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import "../components"
import "../singletons"

ColumnLayout {
    id: p

    readonly property var wifi: {
        const ds = Networking.devices.values;
        for (let i = 0; i < ds.length; i++) {
            if (ds[i].type === DeviceType.Wifi) return ds[i];
        }
        return null;
    }
    property var pendingNet: null
    property string psk: ""

    spacing: 8

    onWifiChanged: if (p.wifi !== null) p.wifi.scannerEnabled = true
    Component.onCompleted: if (p.wifi !== null) p.wifi.scannerEnabled = true

    function connectTo(net: var): void {
        if (net.connected) {
            net.disconnect();
        } else if (net.security === WifiSecurityType.Open) {
            net.connect();
        } else {
            p.pendingNet = net;
            p.psk = "";
        }
    }

    function doConnect(): void {
        if (p.pendingNet === null) return;
        p.pendingNet.connectWithPsk(p.psk);
        p.pendingNet = null;
    }

    // Состояние и выключатель
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Label {
                text: "Wi-Fi"
                color: Colors.accent
                font.pixelSize: 12
            }
            Label {
                Layout.fillWidth: true
                text: p.wifi === null
                    ? Lang.t("адаптер не найден")
                    : (p.wifi.connected ? Lang.t("подключено") : Lang.t("не подключено"))
                color: Colors.dim
                font.pixelSize: 11
            }
        }

        Rectangle {
            implicitWidth: 38
            implicitHeight: 18
            radius: 9
            color: Networking.wifiEnabled ? Colors.accent : Colors.track

            Rectangle {
                width: 12
                height: 12
                radius: 6
                y: 3
                x: Networking.wifiEnabled ? parent.width - width - 3 : 3
                color: Networking.wifiEnabled ? Colors.onAccent : Colors.accent
                Behavior on x { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }
    }

    // Ввод пароля
    Label {
        Layout.fillWidth: true
        topPadding: 2
        visible: p.pendingNet !== null
        Layout.preferredHeight: visible ? implicitHeight : 0
        text: Lang.t("Пароль: ") + (p.pendingNet !== null ? p.pendingNet.name : "")
        color: Colors.dim
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: p.pendingNet !== null
        Layout.preferredHeight: visible ? implicitHeight : 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: Colors.border

            TextInput {
                id: pskInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                echoMode: TextInput.Password
                passwordCharacter: "\u2022"
                clip: true
                onTextChanged: p.psk = text
                onAccepted: p.doConnect()
            }
        }
        Rectangle {
            implicitWidth: 76
            implicitHeight: 28
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: Colors.accent

            Label {
                anchors.centerIn: parent
                text: Lang.t("Войти")
                color: Colors.text
                font.pixelSize: 12
            }
            MouseArea {
                anchors.fill: parent
                onClicked: p.doConnect()
            }
        }
    }

    Label {
        Layout.fillWidth: true
        topPadding: 2
        text: Lang.t("Сети")
        color: Colors.dim
        font.pixelSize: 11
    }

    Repeater {
        model: p.wifi !== null ? p.wifi.networks : null

        delegate: Rectangle {
            required property var modelData

            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 26 : 0
            implicitHeight: 26
            radius: 6
            visible: modelData.name !== ""
            color: modelData.connected ? Colors.selected : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: modelData.name
                    color: modelData.connected ? Colors.text : Colors.accent
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Label {
                    text: Math.round((modelData.signalStrength || 0) * 100) + "%"
                    color: Colors.dim
                    font.pixelSize: 11
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: p.connectTo(modelData)
            }
        }
    }
}
