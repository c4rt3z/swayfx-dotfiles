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
    property var pendingNet: null   // чей пароль сейчас спрашиваем
    property var attempt: null      // к чему подключаемся прямо сейчас
    property string psk: ""
    property string error: ""       // почему не получилось
    property bool busy: false

    spacing: 8

    onWifiChanged: if (p.wifi !== null) p.wifi.scannerEnabled = true
    Component.onCompleted: if (p.wifi !== null) p.wifi.scannerEnabled = true

    function connectTo(net: var): void {
        if (net.connected) {
            net.disconnect();
            p.formReset();
            return;
        }
        p.error = "";
        if (net.security === WifiSecurityType.Open) {
            p.pendingNet = null;
            p.attempt = net;
            p.busy = true;
            net.connect();
            timeout.restart();
        } else {
            p.pendingNet = net;
            p.attempt = null;
            p.busy = false;
            p.psk = "";
        }
    }

    function doConnect(): void {
        if (p.pendingNet === null || p.busy)
            return;
        p.error = "";
        p.busy = true;
        p.attempt = p.pendingNet;
        p.attempt.connectWithPsk(p.psk);
        timeout.restart();
    }

    // успех: убираем форму; пароль и ошибку тоже
    function formReset(): void {
        p.pendingNet = null;
        p.attempt = null;
        p.psk = "";
        p.error = "";
        p.busy = false;
        timeout.stop();
    }

    // поле не должно помнить пароль от прошлой сети
    onPendingNetChanged: if (pendingNet === null) pskInput.text = ""

    // NetworkManager сам говорит, почему не вышло: не тот пароль — так и пишем
    Connections {
        target: p.attempt
        ignoreUnknownSignals: true

        function onConnectionFailed(reason) {
            if (!p.busy)
                return;
            p.busy = false;
            timeout.stop();
            // сеть пропала не из-за пароля — так и скажем, иначе грешим на пароль
            p.error = (reason === ConnectionFailReason.WifiNetworkLost
                       || reason === ConnectionFailReason.Unknown)
                ? Lang.t("Не удалось подключиться")
                : Lang.t("Неверный пароль");
        }

        function onConnectedChanged() {
            if (p.attempt !== null && p.attempt.connected)
                p.formReset();
        }
    }

    // страховка: сигнал не пришёл — не держим «Подключение…» вечно
    Timer {
        id: timeout
        interval: 25000
        onTriggered: {
            if (!p.busy)
                return;
            p.busy = false;
            if (p.attempt === null || !p.attempt.connected)
                p.error = Lang.t("Не удалось подключиться");
        }
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
            border.color: p.error !== "" ? Colors.red
                        : (p.busy ? Colors.accent : Colors.border)

            TextInput {
                id: pskInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.text
                font.family: Fonts.panelFamily
                font.pixelSize: 12
                echoMode: TextInput.Password
                passwordCharacter: "\u2022"
                clip: true
                enabled: !p.busy
                onTextChanged: {
                    p.psk = text;
                    if (p.error !== "")
                        p.error = "";
                }
                onAccepted: p.doConnect()
            }
        }
        Rectangle {
            implicitWidth: 76
            implicitHeight: 28
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: p.busy ? Colors.border : Colors.accent

            Label {
                anchors.centerIn: parent
                text: p.busy ? Lang.t("Подключение…") : Lang.t("Войти")
                color: p.busy ? Colors.dim : Colors.text
                font.pixelSize: 12
            }
            MouseArea {
                anchors.fill: parent
                enabled: !p.busy
                onClicked: p.doConnect()
            }
        }
    }

    // ошибка подключения: красным, под полем пароля
    Label {
        Layout.fillWidth: true
        visible: p.error !== ""
        Layout.preferredHeight: visible ? implicitHeight : 0
        text: p.error
        color: Colors.red
        font.pixelSize: 11
        wrapMode: Text.Wrap
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
