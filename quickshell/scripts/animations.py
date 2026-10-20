#!/usr/bin/env python3
"""Анимации: окна (swayfx) и панели quickshell.

    animations.py state                 — текущие настройки (JSON)
    animations.py set window_ms 180     — длительность появления окон
    animations.py set panels true       — панели quickshell (fade + масштаб)
    animations.py set sidebar true      — выезд сайдбара
    animations.py set toasts true       — появление уведомлений

Длительность окон — это swayfx: команда `animation_duration_ms` (0…5000 мс,
0 — выключено). Её можно менять на ходу, поэтому применяем сразу через
swaymsg, а не только записываем в конфиг.

Остальное — QML: панели, сайдбар и тосты читают файл
~/.config/quickshell/animations.json (singletons/Animations.qml, watchChanges),
поэтому изменения применяются сразу, без перезапуска оболочки.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
FILE = f"{HOME}/.config/quickshell/animations.json"

DEFAULTS = {
    "window_ms": 180,
    "panels": True,
    "sidebar": True,
    "toasts": True,
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
    if "window_ms" in saved:
        try:
            data["window_ms"] = max(0, min(5000, int(saved["window_ms"])))
        except (TypeError, ValueError):
            pass
    for key in ("panels", "sidebar", "toasts"):
        if key in saved:
            data[key] = bool(saved[key])
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


def apply_window(ms):
    """Длительность анимации окон — прямо в работающий sway."""
    subprocess.run(["swaymsg", "animation_duration_ms", str(ms)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main(argv):
    if not argv or argv[0] == "state":
        print(json.dumps(load(), ensure_ascii=False))
        return 0

    if argv[0] == "set" and len(argv) >= 3:
        key, value = argv[1], " ".join(argv[2:])
        data = load()
        if key == "window_ms":
            try:
                data["window_ms"] = max(0, min(5000, int(float(value))))
            except ValueError:
                return 2
            apply_window(data["window_ms"])
        elif key in ("panels", "sidebar", "toasts"):
            data[key] = truthy(value)
        else:
            return 2
        save(data)
        print(json.dumps(data, ensure_ascii=False))
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
