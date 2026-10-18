pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Язык интерфейса панелей.
//
// Русский — исходный язык: подписи в QML написаны по-русски, и t() возвращает
// строку как есть, если перевода нет. Словари лежат в
// ~/.config/quickshell/i18n/<код>.json: ключ — русская строка, значение —
// перевод. Текущий язык — в ~/.config/quickshell/language (одно слово).
//
// Если в словаре языка строки нет, берём английскую (i18n/en.json) и только
// потом русскую. Так словарь можно пополнять постепенно: непереведённое место
// будет на английском, а не на русском посреди чужого языка.
//
// Ничего не перезапускаем: файлы под наблюдением, поэтому смена языка сразу
// меняет подписи в открытых панелях.
Item {
    id: root

    property string code: "ru"

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string langPath: home + "/.config/quickshell/language"
    readonly property string dictDir: home + "/.config/quickshell/i18n"

    // для настроек: код и как язык называется на нём самом.
    // Добавить язык — положить i18n/<код>.json и дописать строку сюда.
    readonly property var languages: [
        { code: "ru", name: "Русский" },
        { code: "en", name: "English" },
        { code: "uk", name: "Українська" },
        { code: "de", name: "Deutsch" }
    ]

    // словарь текущего языка: { "Оригинал": "Translation" }
    property var dict: ({})
    // английский — запасной: чего нет в словаре языка, берём оттуда
    property var fallback: ({})

    FileView {
        path: root.langPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            let value = (raw || "").trim().split("\n")[0].trim();
            if (value !== "")
                root.code = value;
        }
    }

    FileView {
        id: dictView
        path: root.dictDir + "/" + root.code + ".json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                root.dict = JSON.parse(raw || "{}");
            } catch (e) {
                root.dict = ({});
            }
        }
    }

    FileView {
        id: fallbackView
        path: root.dictDir + "/en.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            try {
                root.fallback = JSON.parse(raw || "{}");
            } catch (e) {
                root.fallback = ({});
            }
        }
    }

    function t(text) {
        if (!text || root.code === "ru")
            return text;
        let value = root.dict[text];
        if (value === undefined || value === "")
            value = root.fallback[text];
        return (value === undefined || value === "") ? text : value;
    }
}
