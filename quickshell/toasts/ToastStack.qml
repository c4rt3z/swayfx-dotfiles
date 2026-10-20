import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../components"
import "../singletons"

// Стопка тостов справа сверху, под баром.
//
// Уведомления принимает singletons/Notifs.qml (он же демон
// org.freedesktop.Notifications). Здесь только показ: карточка на уведомление,
// свой таймер на каждое (важные — критичные — не гаснут сами, пока их не
// закроют), кнопки действий из уведомления, если приложение их прислало.
//
// Клавиатуру не забираем вовсе: тосты не должны мешать печати в окнах.
PanelWindow {
    id: stack

    color: "transparent"

    anchors.top: true
    anchors.right: true
    margins.top: 44
    margins.right: 10

    implicitWidth: 360
    implicitHeight: column.implicitHeight
    visible: Notifs.live.length > 0

    exclusiveZone: -1
    focusable: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 8

        Repeater {
            model: Notifs.live

            delegate: Item {
                id: toast

                required property var modelData

                // n — само уведомление, живёт в Notifs.qml
                readonly property var note: toast.modelData.n
                readonly property bool critical: toast.note
                    && toast.note.urgency === NotificationUrgency.Critical

                Layout.fillWidth: true
                implicitHeight: card.height

                property bool held: false

                // таймер: критичные висят до закрытия, обычные — сколько просило
                // приложение (обычно 5 секунд), но не меньше трёх
                Timer {
                    id: life
                    running: !toast.held && !toast.critical
                    interval: (toast.note && toast.note.expireTimeout > 0)
                              ? Math.max(3000, toast.note.expireTimeout) : 5000
                    onTriggered: Notifs.drop(toast.note)
                }

                Rectangle {
                    id: card

                    width: parent.width
                    height: body.implicitHeight + 18
                    radius: 9
                    color: Colors.card
                    border.width: 1
                    border.color: toast.critical ? Colors.red : Colors.border

                    // Появление: карточка выезжает справа и проявляется.
                    // appear стартует нулём, а при появлении уведомления
                    // переключается в единицу — Behavior дорисовывает движение.
                    property real appear: 0
                    Component.onCompleted: appear = 1

                    // уходящее уведомление уезжает обратно вправо и гаснет
                    opacity: toast.modelData.leaving ? 0 : appear
                    x: (toast.modelData.leaving ? 1 : (1 - appear)) * 46

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Animations.toasts ? 200 : 0
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: Animations.toasts ? 240 : 0
                            easing.type: Easing.OutCubic
                        }
                    }

                    ColumnLayout {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 9
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Image {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                sourceSize.width: 36
                                sourceSize.height: 36
                                visible: source != ""
                                source: toast.note
                                    ? Quickshell.iconPath(toast.note.appIcon
                                                          || toast.note.desktopEntry,
                                                          "dialog-information")
                                    : ""
                            }

                            Label {
                                Layout.fillWidth: true
                                text: (toast.note && toast.note.appName)
                                      || Lang.t("Уведомление")
                                color: Colors.dim
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            Item {
                                implicitWidth: 18
                                implicitHeight: 18

                                Label {
                                    anchors.centerIn: parent
                                    text: "\uf00d"
                                    color: closeArea.containsMouse ? Colors.text : Colors.dim
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: closeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: Notifs.drop(toast.note)
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: toast.note && toast.note.summary !== ""
                            text: toast.note ? toast.note.summary : ""
                            color: toast.critical ? Colors.red : Colors.text
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: toast.note && toast.note.body !== ""
                            text: toast.note ? toast.note.body : ""
                            color: Colors.muted
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        // действия из уведомления: «Открыть», «Ответить» и прочее
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: actions.count > 0

                            Repeater {
                                id: actions
                                model: toast.note ? toast.note.actions : []

                                delegate: Item {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 24

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 6
                                        color: actionArea.containsMouse ? Colors.selected : "transparent"
                                        border.width: 1
                                        border.color: actionArea.containsMouse
                                                      ? Colors.accent : Colors.divider
                                    }
                                    Label {
                                        anchors.centerIn: parent
                                        text: modelData.text || ""
                                        color: actionArea.containsMouse ? Colors.text : Colors.muted
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    MouseArea {
                                        id: actionArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            modelData.invoke();
                                            Notifs.drop(toast.note);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    onEntered: toast.held = true
                    onExited: toast.held = false
                }
            }
        }
    }
}
