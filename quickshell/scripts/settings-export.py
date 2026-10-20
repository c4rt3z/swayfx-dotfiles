#!/usr/bin/env python3
"""Экспорт и импорт настроек: переезд на другую машину одним файлом.

    settings-export.py export [файл]   — собрать все настройки в один JSON
    settings-export.py import [файл]   — разложить настройки по местам
    settings-export.py show            — что входит в экспорт

Состояние лежит в разных файлах (сайдбар, анимации, шрифты, погода, вид
бара, сон, язык, тема значков). Экспорт складывает их в один JSON, импорт
разворачивает обратно — ничего не теряется при переносе на другой компьютер.

По умолчанию файл: ~/.config/quickshell/export.json
"""
import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")
CFG = f"{HOME}/.config"
QS = f"{CFG}/quickshell"
DEFAULT = f"{QS}/export.json"

# файл настроек -> куда кладём при импорте
FILES = {
    "sidebar": f"{QS}/sidebar.json",
    "animations": f"{QS}/animations.json",
    "fonts": f"{QS}/fonts.json",
    "weather": f"{QS}/weather.json",
    "sleep": f"{QS}/sleep.json",
    "emoji": f"{QS}/emoji.json",
    "bar_mode": f"{CFG}/waybar/mode",
    "language": f"{QS}/language",
}


def collect():
    data = {"version": 1, "files": {}}
    for key, path in FILES.items():
        if not os.path.exists(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        if path.endswith(".json"):
            try:
                data["files"][key] = json.loads(text)
                continue
            except Exception:
                pass
        data["files"][key] = text.strip()
    return data


def restore(data):
    files = data.get("files") or {}
    count = 0
    for key, path in FILES.items():
        if key not in files:
            continue
        value = files[key]
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if path.endswith(".json"):
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(value, fh, ensure_ascii=False, indent=1)
                fh.write("\n")
        else:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(str(value) + "\n")
        count += 1
    return count


def main(argv):
    action = argv[0] if argv else "show"
    path = argv[1] if len(argv) > 1 else DEFAULT

    if action == "export":
        data = collect()
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
        print(json.dumps({"ok": True, "file": path,
                          "count": len(data["files"])}, ensure_ascii=False))
        return 0

    if action == "import":
        if not os.path.exists(path):
            print(json.dumps({"ok": False, "error": "нет файла"}, ensure_ascii=False))
            return 1
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        count = restore(data)
        print(json.dumps({"ok": True, "restored": count}, ensure_ascii=False))
        return 0

    if action == "show":
        print(json.dumps(collect(), ensure_ascii=False, indent=1))
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
