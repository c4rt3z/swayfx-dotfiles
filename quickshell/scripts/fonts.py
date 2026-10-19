#!/usr/bin/env python3
"""Шрифты интерфейса — как в KDE: общий шрифт и переопределения для панелей и бара.

    fonts.py list              — все семейства из fontconfig (JSON)
    fonts.py state             — текущие настройки и итоговые шрифты (JSON)
    fonts.py set ui=<шрифт> [panels=<шрифт>] [waybar=<шрифт>]
    fonts.py reset [ui|panels|waybar|all]

Настройки лежат в ~/.config/quickshell/fonts.json; пустая строка — «как общий».
Панели quickshell перечитывают файл сами (singletons/Fonts.qml), а для waybar
пересобираем CSS через theme-gen.sh: шаблон подставляет {{font}}.

Шрифт должен содержать иконки Nerd Font, иначе значки в баре и панелях
превратятся в квадраты — об этом предупреждает страница настроек.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
PATH = f"{HOME}/.config/quickshell/fonts.json"
DEFAULT = "JetBrainsMono Nerd Font"
# что стоит в GTK, пока мы туда не вмешивались (восстанавливаем при сбросе)
GTK_FALLBACK = "Noto Sans 10"


def load():
    data = {}
    try:
        with open(PATH, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}
    return {
        "ui": str(data.get("ui") or ""),
        "panels": str(data.get("panels") or ""),
        "waybar": str(data.get("waybar") or ""),
        "gtk_backup": str(data.get("gtk_backup") or GTK_FALLBACK),
    }


def save(data):
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    tmp = f"{PATH}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, PATH)


def family(data, target):
    """Итоговый шрифт: своё значение, иначе общий, иначе стандартный."""
    if target in ("panels", "waybar"):
        return data[target] or data["ui"] or DEFAULT
    return data["ui"] or DEFAULT


def gtk_font(name):
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface",
                    "font-name", name], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def waybar_restart():
    """Пересобрать CSS бара с новым шрифтом (theme-gen копирует и шлёт SIGUSR2)."""
    mode_file = f"{HOME}/.cache/wallpaper/theme_mode"
    mode = "auto"
    try:
        with open(mode_file, encoding="utf-8") as fh:
            mode = fh.read().strip() or "auto"
    except Exception:
        pass
    subprocess.run([f"{HOME}/.config/wallpaper/theme-gen.sh", "--mode", mode],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def apply(data, touched):
    if "ui" in touched or "gtk" in touched:
        if data["ui"]:
            gtk_font(f"{data['ui']} 10")
        else:
            gtk_font(data["gtk_backup"])
    if "waybar" in touched or "ui" in touched:
        waybar_restart()


def state():
    data = load()
    return {
        "ui": data["ui"],
        "panels": data["panels"],
        "waybar": data["waybar"],
        "resolved": {
            "ui": family(data, "ui"),
            "panels": family(data, "panels"),
            "waybar": family(data, "waybar"),
        },
        "default": DEFAULT,
        "file": PATH,
    }


def font_list():
    try:
        out = subprocess.run(["fc-list", ":", "family"], check=True,
                             capture_output=True, text=True).stdout
    except Exception:
        out = ""
    names = set()
    for line in out.splitlines():
        for name in line.split(","):
            name = name.strip()
            if name and not name.startswith("."):
                names.add(name)
    return sorted(names, key=lambda s: (s.lower(), s))


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    what = argv[0]

    if what == "list":
        print(json.dumps({"fonts": font_list()}, ensure_ascii=False))
        return 0

    if what == "state":
        print(json.dumps(state(), ensure_ascii=False))
        return 0

    if what == "set":
        data = load()
        touched = set()
        for arg in argv[1:]:
            if "=" not in arg:
                continue
            key, value = arg.split("=", 1)
            if key not in ("ui", "panels", "waybar"):
                continue
            if not data["ui"] and not data["gtk_backup"]:
                data["gtk_backup"] = GTK_FALLBACK
            data[key] = value.strip()
            touched.add(key)
        save(data)
        apply(data, touched)
        print(json.dumps(state(), ensure_ascii=False))
        return 0

    if what == "reset":
        target = argv[1] if len(argv) > 1 else "all"
        data = load()
        touched = {"ui"}
        if target in ("ui", "all"):
            data["ui"] = ""
        if target in ("panels", "all"):
            data["panels"] = ""
        if target in ("waybar", "all"):
            data["waybar"] = ""
        save(data)
        apply(data, touched)
        print(json.dumps(state(), ensure_ascii=False))
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
