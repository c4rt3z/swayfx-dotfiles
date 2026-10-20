#!/usr/bin/env python3
"""Значки (icon packs) и курсоры: что установлено и как это применить.

    icons-cursors.py list            — установленные темы и текущие (JSON)
    icons-cursors.py set icons <имя> — выбрать тему значков
    icons-cursors.py set cursors <имя> — выбрать тему курсоров

Темы значков ищутся в ~/.local/share/icons и /usr/share/icons (папка с
index.theme), курсоры — те же папки, но с каталогом cursors. Переключение
делаем через gsettings: это то, чем пользуются GTK-приложения; Qt-приложения
у нас оформлены через qt5ct/qt6ct, их настройки живут отдельно.

Список не храним: он каждый раз снимается с диска, а текущие темы читаются
из gsettings.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
ICON_DIRS = (f"{HOME}/.local/share/icons", f"{HOME}/.icons", "/usr/share/icons")


def gsettings_get(key):
    try:
        out = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", key],
                             capture_output=True, text=True, timeout=4).stdout.strip()
        return out.strip("'")
    except Exception:
        return ""


def gsettings_set(key, value):
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", key, value],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def gtk_set_cursor(name, size=24):
    """Прописать курсор в settings.ini GTK.

    Это главное: GTK читает курсор из своего settings.ini, а не из gsettings
    (gsettings отдаёт его через портал, и то не всегда). Если в ini тема
    закреплена, выбор в настройках молча ничего не меняет.
    """
    for version in ("gtk-3.0", "gtk-4.0"):
        path = f"{HOME}/.config/{version}/settings.ini"
        try:
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        out = []
        seen = set()
        for line in lines:
            key = line.split("=", 1)[0].strip()
            if key == "gtk-cursor-theme-name":
                out.append(f"gtk-cursor-theme-name={name}")
                seen.add(key)
            elif key == "gtk-cursor-theme-size":
                out.append(f"gtk-cursor-theme-size={size}")
                seen.add(key)
            else:
                out.append(line)
        if "gtk-cursor-theme-name" not in seen:
            out.append(f"gtk-cursor-theme-name={name}")
        if "gtk-cursor-theme-size" not in seen:
            out.append(f"gtk-cursor-theme-size={size}")
        try:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("\n".join(out).rstrip("\n") + "\n")
        except OSError:
            pass


def themes():
    """Имя темы -> есть ли в ней курсоры."""
    found = {}
    for folder in ICON_DIRS:
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            path = os.path.join(folder, name)
            if not os.path.isdir(path):
                continue
            if not os.path.exists(os.path.join(path, "index.theme")):
                continue
            has_cursor = os.path.isdir(os.path.join(path, "cursors")) \
                or os.path.exists(os.path.join(path, "cursor.theme"))
            if name in found:
                found[name] = found[name] or has_cursor
            else:
                found[name] = has_cursor
    return found


def state():
    found = themes()
    icons = sorted(found.keys())
    cursors = sorted(name for name, has in found.items() if has)
    if not cursors:
        cursors = list(icons)
    return {
        "ok": True,
        "icons": icons,
        "cursors": cursors,
        "current_icon": gsettings_get("icon-theme"),
        "current_cursor": gsettings_get("cursor-theme"),
    }


def main(argv):
    if not argv or argv[0] == "list":
        print(json.dumps(state(), ensure_ascii=False))
        return 0

    if argv[0] == "set" and len(argv) >= 3:
        what, name = argv[1], " ".join(argv[2:])
        if what == "icons":
            gsettings_set("icon-theme", name)
        elif what == "cursors":
            gsettings_set("cursor-theme", name)
            try:
                size = int(gsettings_get("cursor-size") or 24)
            except ValueError:
                size = 24
            gtk_set_cursor(name, size)
        else:
            return 2
        print(json.dumps(state(), ensure_ascii=False))
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
