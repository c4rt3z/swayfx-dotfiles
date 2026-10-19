pragma Singleton
import QtQuick

// Состояние сайдбара — панели, которая выезжает слева по бинду (Mod+B).
//
// Отдельный синглтон, а не свойство панели: открывать и закрывать сайдбар
// умеют и бинд (через IPC), и Esc внутри самой панели, и блокировка экрана.
//
//   Sidebar.toggle(); Sidebar.show(); Sidebar.hide()
Item {
    id: root

    property bool open: false

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }
}
