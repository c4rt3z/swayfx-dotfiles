import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Pam
import "../components"
import "../singletons"

// Экран блокировки сессии: рисует его quickshell поверх всего (WlSessionLock).
//
//    Mod+Ctrl+L    — запереть сессию
//    Enter         — проверить пароль
//    Esc           — очистить поле
//
// Пароль проверяет PAM тем же сервисом, что и swaylock (/etc/pam.d/swaylock),
// цвета берёт из палитры темы, фон — текущие обои (движок держит их в
// ~/.cache/wallpaper/current.png, поэтому экран всегда совпадает с рабочим столом).
Item {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string wallpaper: home + "/.cache/wallpaper/current.png"

    property string timeText: "--:--"
    property string dateText: ""
    property int surfaceWidth: 0
    property int surfaceHeight: 0
    property real drift: 1
    property real shake: 0
    property string pendingPassword: ""

    // quickshell не выставляет размер контенту поверхности — приходит извне
    width: surfaceWidth
    height: surfaceHeight

    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Component.onCompleted: {
        root.tick();
        root.opacity = 1;
    }

    Component.onDestruction: pam.abort()

    // ── время и дата ─────────────────────────────────────────────────────────

    function tick() {
        const d = new Date();
        const pad = n => (n < 10 ? "0" : "") + n;
        root.timeText = pad(d.getHours()) + ":" + pad(d.getMinutes());
        const days = [Lang.t("воскресенье"), Lang.t("понедельник"), Lang.t("вторник"), Lang.t("среда"),
                      Lang.t("четверг"), Lang.t("пятница"), Lang.t("суббота")];
        const months = [Lang.t("января"), Lang.t("февраля"), Lang.t("марта"), Lang.t("апреля"), Lang.t("мая"), Lang.t("июня"),
                        Lang.t("июля"), Lang.t("августа"), Lang.t("сентября"), Lang.t("октября"), Lang.t("ноября"), Lang.t("декабря")];
        root.dateText = days[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()];
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.tick()
    }

    // ── фон: палитра + обои с медленным дрейфом ─────────────────────────────

    Rectangle { anchors.fill: parent; color: Colors.base }

    Image {
        id: bg
        anchors.centerIn: parent
        width: parent.width * 1.16
        height: parent.height * 1.16
        asynchronous: true
        cache: false
        fillMode: Image.PreserveAspectCrop
        source: root.wallpaper
        transform: Scale {
            origin.x: bg.width / 2
            origin.y: bg.height / 2
            xScale: root.drift
            yScale: root.drift
        }
    }

    // затемнение и виньетка: текст читается на любых обоях
    Rectangle { anchors.fill: parent; color: Colors.base; opacity: 0.62 }

    RadialGradient {
        anchors.fill: parent
        horizontalRadius: width * 0.8
        verticalRadius: height * 0.8
        gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 0.68; color: "#00000000" }
            GradientStop { position: 1; color: "#000000b3" }
        }
    }

    SequentialAnimation on drift {
        loops: Animation.Infinite
        NumberAnimation { to: 1.09; duration: 26000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 26000; easing.type: Easing.InOutSine }
    }

    // ── центр: часы, дата, пароль ────────────────────────────────────────────

    ColumnLayout {
        id: center
        anchors.centerIn: parent
        width: 560
        spacing: 18
        transform: Translate { x: root.shake }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.timeText
            color: Colors.text
            font.pixelSize: 104
            font.bold: true
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.dateText
            color: Colors.text
            opacity: 0.62
            font.pixelSize: 24
        }

        Rectangle {
            Layout.preferredWidth: 96
            Layout.preferredHeight: 2
            Layout.alignment: Qt.AlignHCenter
            color: Colors.accent
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            // подчёркивание поля: акцент, при ошибке — красное
            Rectangle {
                Layout.preferredWidth: 260
                Layout.preferredHeight: 2
                Layout.alignment: Qt.AlignHCenter
                color: Lock.messageIsError ? Colors.red : Colors.accent
            }

            // поле пароля + свой плейсхолдер (у TextInput нет placeholderTextColor)
            Item {
                Layout.preferredWidth: 260
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter

                TextInput {
                    id: field
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignHCenter
                    font.family: "JetBrains Mono"
                    font.pixelSize: 20
                    color: Colors.text
                    echoMode: TextInput.Password
                    passwordCharacter: "\u2022"
                    selectByMouse: false
                    onTextChanged: Lock.clearMessage()
                    onAccepted: root.submit()
                    Component.onCompleted: field.forceActiveFocus()

                    cursorDelegate: Rectangle {
                        width: 2
                        color: Colors.accent
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            field.clear();
                            event.accepted = true;
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: field.text === ""
                    text: Lang.t("пароль")
                    color: Colors.dim
                    opacity: 0.7
                    font.pixelSize: 20
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: Lock.message
                color: Lock.messageIsError ? Colors.red : Colors.text
                opacity: Lock.message === "" ? 0 : 0.85
                font.pixelSize: 14
            }

            // тонкая бегущая полоска, пока PAM проверяет пароль
            Item {
                Layout.preferredWidth: 140
                Layout.preferredHeight: 2
                Layout.alignment: Qt.AlignHCenter
                clip: true
                opacity: Lock.busy ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Rectangle {
                    width: 46
                    height: 2
                    color: Colors.accent
                    x: -46
                    NumberAnimation on x {
                        running: Lock.busy
                        from: -46
                        to: 140
                        duration: 900
                        loops: Animation.Infinite
                    }
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: Lang.t("enter — разблокировать · esc — очистить")
            color: Colors.text
            opacity: 0.45
            font.pixelSize: 13
        }
    }

    // ── проверка пароля ──────────────────────────────────────────────────────

    function submit() {
        if (Lock.busy)
            return;
        const password = field.text;
        if (password === "") {
            shakeAnim.restart();
            return;
        }
        Lock.checking();
        pendingPassword = password;
        field.clear();
        if (!pam.start()) {
            Lock.fail(Lang.t("не удалось начать проверку"));
            shakeAnim.restart();
        }
    }

    function accept() {
        // сначала гасим экран, и только потом отпускаем блокировку
        root.opacity = 0;
        unlockTimer.start();
    }

    Timer {
        id: unlockTimer
        interval: 240
        onTriggered: Lock.unlock()
    }

    SequentialAnimation on shake {
        id: shakeAnim
        NumberAnimation { to: 16; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { to: -16; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 9; duration: 60 }
        NumberAnimation { to: 0; duration: 80 }
    }

    PamContext {
        id: pam
        config: "swaylock"
        user: Quickshell.env("USER") ?? ""

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.accept();
            } else {
                Lock.fail(result === PamResult.MaxTries ? Lang.t("слишком много попыток") : Lang.t("неверный пароль"));
                shakeAnim.restart();
            }
        }
        onError: err => {
            Lock.fail(Lang.t("не удалось проверить пароль"));
            shakeAnim.restart();
        }
        // у сигнала pamMessage в QML нет параметров — состояние читаем из свойств
        onResponseRequiredChanged: {
            if (pam.responseRequired && pendingPassword !== "")
                pam.respond(pendingPassword);
        }
    }
}
