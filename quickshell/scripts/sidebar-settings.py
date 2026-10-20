#!/usr/bin/env python3
"""Настройки сайдбара: сторона, ширина, подписи, сетка и виджеты.

    sidebar-settings.py state                    — текущие настройки (JSON)
    sidebar-settings.py set side right           — сторона: left|right
    sidebar-settings.py set width 26             — доля ширины экрана, 16..40
    sidebar-settings.py set labels false         — подписи у кнопок
    sidebar-settings.py set grid 3x2             — сетка сессии: 2x3|3x2
    sidebar-settings.py set widget.weather false — включить/выключить виджет
    sidebar-settings.py reset                    — вернуть значения по умолчанию

Правда живёт в ~/.config/quickshell/sidebar.json. Сайдбар читает файл сам
(singletons/Sidebar.qml, watchChanges), поэтому после set ничего перезапускать
не нужно — достаточно, чтобы файл изменился.
"""
import json
import os
import sys

HOME = os.path.expanduser("~")
FILE = f"{HOME}/.config/quickshell/sidebar.json"

DEFAULTS = {
    "side": "left",
    "width": 24,
    "labels": True,
    "grid": "2x3",
    "widgets": {
        "weather": True,
        "now": True,
        "session": True,
        "shots": True,
        "clipboard": True,
        "notifications": True,
    },
}


def load():
    data = json.loads(json.dumps(DEFAULTS))
    try:
        with open(FILE, encoding="utf-8") as fh:
            saved = json.load(fh)
    except Exception:
        return data
    if not isinstance(saved, dict):
        return data
    for key in ("side", "width", "labels", "grid"):
        if key in saved:
            data[key] = saved[key]
    widgets = saved.get("widgets")
    if isinstance(widgets, dict):
        for key in data["widgets"]:
            if key in widgets:
                data["widgets"][key] = bool(widgets[key])
    return data


def save(data):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    tmp = f"{FILE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, FILE)


def truthy(value):
    return str(value).strip().lower() in ("1", "true", "yes", "on", "да")


def main(argv):
    if not argv or argv[0] == "state":
        print(json.dumps(load(), ensure_ascii=False))
        return 0

    if argv[0] == "reset":
        save(json.loads(json.dumps(DEFAULTS)))
        print(json.dumps(load(), ensure_ascii=False))
        return 0

    if argv[0] == "set" and len(argv) >= 3:
        key, value = argv[1], " ".join(argv[2:])
        data = load()
        if key == "side":
            data["side"] = "right" if value.strip().lower() == "right" else "left"
        elif key == "width":
            try:
                data["width"] = max(16, min(40, int(float(value))))
            except ValueError:
                return 2
        elif key == "labels":
            data["labels"] = truthy(value)
        elif key == "grid":
            data["grid"] = "3x2" if value.strip() == "3x2" else "2x3"
        elif key.startswith("widget."):
            name = key.split(".", 1)[1]
            if name not in data["widgets"]:
                return 2
            data["widgets"][name] = truthy(value)
        else:
            return 2
        save(data)
        print(json.dumps(data, ensure_ascii=False))
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
