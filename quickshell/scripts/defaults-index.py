#!/usr/bin/env python3
"""Приложения по умолчанию — данные для раздела настроек.

    defaults-index.py build                  — пересобрать ~/.cache/quickshell/defaults.json
    defaults-index.py set <задача> <прил.>   — поставить приложение по умолчанию
    defaults-index.py --selftest

Как в Windows: у каждой задачи (терминал, файловый менеджер, браузер, редактор,
картинки, видео, музыка, pdf, архивы, почта) своё приложение. Хранится это в двух
местах, и оба — системные, своего состояния скрипт не держит:

  * терминал, файловый менеджер и браузер — переменные в ~/.config/sway/config
    (set $term / $filemanager / $browser), их подставляет сам sway;
  * остальное — обработчики типов файлов в ~/.config/mimeapps.list, их пишет
    xdg-mime; по ним открываются файлы из проводника и ссылки из программ.

Откуда берутся кандидаты: список установленных приложений (apps-index.py,
~/.cache/quickshell/apps.json) с их MimeType и Categories. Приложению нужен
подходящий тип файла, а вес добавляет категория: так «Изображения» не
предлагают браузер, который тоже умеет открывать png.
"""

import json
import os
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
CACHE = f"{HOME}/.cache/quickshell"
STATE = f"{CACHE}/defaults.json"
APPS = f"{CACHE}/apps.json"
SWAY = f"{HOME}/.config/sway/config"
MIMEAPPS = f"{HOME}/.config/mimeapps.list"

# Задачи: id, название, где хранится выбор и что считать подходящим приложением.
TASKS = [
    {
        "id": "terminal",
        "name": "Терминал",
        "sway": "$term",
        "categories": ["TerminalEmulator"],
        "bins": ["alacritty", "kitty", "konsole", "foot", "wezterm", "xterm",
                 "gnome-terminal", "xfce4-terminal"],
    },
    {
        "id": "filemanager",
        "strict": True,
        "name": "Файловый менеджер",
        "sway": "$filemanager",
        "xdg": True,
        "mimes": ["inode/directory"],
        "categories": ["FileManager"],
    },
    {
        "id": "browser",
        "strict": True,
        "name": "Браузер",
        "sway": "$browser",
        "xdg": True,
        "mimes": ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"],
        "categories": ["WebBrowser"],
    },
    {
        "id": "editor",
        "name": "Текстовый редактор",
        "mimes": ["text/plain", "text/markdown", "text/x-python", "text/x-shellscript"],
        "categories": ["TextEditor"],
    },
    {
        "id": "image",
        "strict": True,
        "name": "Изображения",
        "mimes": ["image/png", "image/jpeg", "image/gif", "image/webp",
                  "image/svg+xml", "image/avif", "image/bmp"],
        "categories": ["Viewer", "Graphics", "Photography"],
    },
    {
        "id": "video",
        "name": "Видео",
        "mimes": ["video/mp4", "video/x-matroska", "video/webm", "video/mpeg",
                  "video/ogg"],
        "categories": ["Video", "Player"],
    },
    {
        "id": "audio",
        "name": "Музыка",
        "mimes": ["audio/mpeg", "audio/ogg", "audio/flac", "audio/x-wav", "audio/mp4"],
        "categories": ["Audio", "Music", "Player"],
    },
    {
        "id": "pdf",
        "strict": True,
        "name": "Документы PDF",
        "mimes": ["application/pdf", "application/epub+zip"],
        "categories": ["Viewer", "Office"],
    },
    {
        "id": "archive",
        "strict": True,
        "name": "Архивы",
        "mimes": ["application/zip", "application/x-tar", "application/x-7z-compressed",
                  "application/x-rar", "application/x-compressed-tar",
                  "application/gzip", "application/x-bzip2"],
        "categories": ["Archiving", "Compression"],
    },
    {
        "id": "mail",
        "strict": True,
        "name": "Почта",
        "mimes": ["x-scheme-handler/mailto", "message/rfc822"],
        "categories": ["Email"],
    },
]

DESKTOP_DIRS = [
    f"{HOME}/.local/share/applications",
    "/usr/local/share/applications",
    "/usr/share/applications",
]


def task(task_id):
    for item in TASKS:
        if item["id"] == task_id:
            return item
    return None


def load_apps():
    try:
        with open(APPS, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return []
    items = data.get("items", []) if isinstance(data, dict) else data
    return items or []


def binary(exec_line):
    """Первое слово команды без пути: /usr/lib/firefox/firefox -> firefox."""
    if not exec_line:
        return ""
    first = exec_line.split()[0]
    return os.path.basename(first)


def sway_var(name):
    try:
        with open(SWAY, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return ""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "set" and parts[1] == name:
            return parts[2]
    return ""


def sway_set(name, value):
    try:
        with open(SWAY, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return False
    done = False
    for i, line in enumerate(lines):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "set" and parts[1] == name:
            lines[i] = f"set {name} {value}"
            done = True
            break
    if not done:
        return False
    with open(SWAY, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return True


def xdg_default(mime):
    """Что назначено на тип файла сейчас (по mimeapps.list и системным файлам)."""
    if not shutil.which("xdg-mime"):
        return ""
    try:
        out = subprocess.run(["xdg-mime", "query", "default", mime],
                             capture_output=True, text=True, timeout=10)
    except Exception:
        return ""
    return out.stdout.strip()


def xdg_set(desktop, mimes):
    """Назначить приложение обработчиком типов. desktop — id с «.desktop»."""
    if not shutil.which("xdg-mime"):
        return False
    for mime in mimes:
        subprocess.run(["xdg-mime", "default", desktop, mime], capture_output=True)
    # xdg-mime молчит об ошибках, поэтому проверяем, что назначение встало
    return xdg_default(mimes[0]) == desktop


def desktop_name(desktop_id):
    """Название приложения по .desktop: сначала список приложений, потом сам файл."""
    desktop_id = desktop_id.removesuffix(".desktop")
    for app in load_apps():
        if app["id"] == desktop_id:
            return app["name"]
    for folder in DESKTOP_DIRS:
        path = os.path.join(folder, desktop_id + ".desktop")
        if not os.path.exists(path):
            continue
        try:
            inside = False
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.rstrip("\n")
                    if line.startswith("["):
                        inside = line.strip() == "[Desktop Entry]"
                        continue
                    if inside and line.startswith("Name="):
                        return line.split("=", 1)[1].strip()
        except OSError:
            continue
    return desktop_id


def candidates(spec):
    """Подходящие приложения задачи: по типам файлов и категориям."""
    out = []
    for app in load_apps():
        mimes = [m for m in app.get("mime", "").split(";") if m]
        cats = [c for c in app.get("categories", "").split(";") if c]
        exe = binary(app.get("exec", ""))
        score = 0

        if spec.get("bins"):
            # терминал: категория TerminalEmulator или само имя программы.
            # Имя сверяем обязательно: у консольных программ (btop, vim) в Exec
            # стоит тот же терминал, и по одному Exec их не отличить.
            if any(c in spec["categories"] for c in cats):
                score += 3
            elif exe in spec["bins"] and app["name"].strip().lower() == exe:
                score += 3
            # терминалы обычно ничего не открывают, поэтому MimeType не смотрим
        else:
            if any(m in mimes for m in spec["mimes"]):
                score += 3
            if any(c in spec["categories"] for c in cats):
                score += 2
            elif spec.get("strict"):
                # тип файла совпал, а по категории приложение чужое
                # (VSCodium умеет inode/directory, но файловый менеджер из него
                # так себе) — в строгих задачах такие не показываем
                continue
            # браузер умеет открывать почти всё — в чужих задачах он лишний
            if "WebBrowser" in cats and spec["id"] != "browser":
                score -= 4

        if score <= 0:
            continue
        out.append({
            "id": app["id"],
            "name": app["name"],
            "icon": app.get("icon", ""),
            "exec": app.get("exec", ""),
            "bin": exe,
            "note": app.get("comment", ""),
            "score": score,
        })

    out.sort(key=lambda a: (-a["score"], a["name"].lower()))
    return out


def build_task(spec):
    apps = candidates(spec)
    current_id, current_name = "", ""

    sway_value = sway_var(spec["sway"]) if spec.get("sway") else ""
    if sway_value:
        current_name = sway_value
        for app in apps:
            if app["bin"] == sway_value or app["exec"].split()[0] == sway_value:
                current_id, current_name = app["id"], app["name"]
                break

    xdg_id = xdg_default(spec["mimes"][0]) if spec.get("mimes") else ""
    if spec.get("mimes") and not sway_value:
        current_id = xdg_id.removesuffix(".desktop")
        current_name = desktop_name(xdg_id)

    for app in apps:
        app["current"] = app["id"] == current_id or (
            not current_id and app["bin"] == sway_value and sway_value != "")

    item = dict(spec)
    item.pop("bins", None)
    item["store"] = ("sway " + spec["sway"]) if spec.get("sway") else "mimeapps.list"
    item["current"] = {"id": current_id, "name": current_name,
                       "cmd": sway_value or xdg_id}
    item["candidates"] = apps
    item["mimes"] = spec.get("mimes", [])

    # терминал, файловый менеджер и браузер могут быть записаны в двух местах —
    # если разошлись, честно показываем, чем откроются ссылки/папки
    if spec.get("sway") and spec.get("xdg"):
        item["xdg"] = {"id": xdg_id.removesuffix(".desktop"),
                       "name": desktop_name(xdg_id),
                       "differs": bool(xdg_id) and xdg_id.removesuffix(".desktop") != current_id}
    return item


def build():
    data = {
        "tasks": [build_task(spec) for spec in TASKS],
        "sway_conf": SWAY,
        "mimeapps": MIMEAPPS,
    }
    os.makedirs(CACHE, exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    return data


def set_default(task_id, app_id):
    spec = task(task_id)
    if not spec:
        print(f"defaults-index: нет задачи «{task_id}»", file=sys.stderr)
        return 1
    found = None
    for app in load_apps():
        if app["id"] == app_id:
            found = app
            break
    if not found:
        print(f"defaults-index: нет приложения «{app_id}»", file=sys.stderr)
        return 1

    exe = binary(found.get("exec", ""))
    if spec.get("sway"):
        if not exe:
            print(f"defaults-index: у «{app_id}» непонятная команда запуска",
                  file=sys.stderr)
            return 1
        if not shutil.which(exe):
            print(f"defaults-index: {exe} не установлен", file=sys.stderr)
            return 1
        if not sway_set(spec["sway"], exe):
            print(f"defaults-index: в конфиге sway нет строки «set {spec['sway']}»",
                  file=sys.stderr)
            return 1
    if spec.get("mimes"):
        if not xdg_set(found["id"] + ".desktop", spec["mimes"]):
            print(f"defaults-index: xdg-mime не принял «{found['id']}»",
                  file=sys.stderr)
            return 1
    if spec.get("sway"):
        subprocess.run(["swaymsg", "reload"], capture_output=True)
    build()
    return 0


def selftest():
    problems = []
    data = build()
    tasks = {t["id"]: t for t in data["tasks"]}

    if len(tasks) != len(TASKS):
        problems.append("задач меньше, чем описано")
    for name in ("terminal", "filemanager", "browser", "editor", "image"):
        item = tasks.get(name)
        if not item:
            problems.append(f"нет задачи «{name}»")
        elif not item["candidates"] and name != "mail":
            problems.append(f"для задачи «{name}» нет подходящих приложений")
    if not tasks["terminal"]["current"]["name"]:
        problems.append("не понял терминал по умолчанию")
    if any(c["id"] == "firefox" for c in tasks["image"]["candidates"]):
        problems.append("в «Изображениях» оказался браузер")
    if not tasks["browser"]["candidates"]:
        problems.append("в «Браузере» пусто")
    if not all("current" in a for a in tasks["editor"]["candidates"]):
        problems.append("у кандидатов нет пометки «текущий»")

    # запись без порчи: ставим то, что уже стоит, и сравниваем файл до/после
    term = tasks["terminal"]["current"]
    for app in tasks["terminal"]["candidates"]:
        if app["bin"] == term["cmd"]:
            with open(SWAY, encoding="utf-8") as fh:
                before = fh.read()
            set_default("terminal", app["id"])
            with open(SWAY, encoding="utf-8") as fh:
                after = fh.read()
            if before != after:
                problems.append("set terminal зачем-то переписал конфиг sway")
            break

    if problems:
        for p in problems:
            print("  ✗", p)
        return 1
    print("  ✓ задач:", len(tasks), "| терминал:",
          tasks["terminal"]["current"]["name"])
    for tid, item in tasks.items():
        names = ", ".join(a["name"] for a in item["candidates"][:4]) or "нет кандидатов"
        print(f"  ✓ {tid:12} {names}")
    return 0


def main(argv):
    if not argv or argv[0] == "build":
        build()
        return 0
    if argv[0] == "set" and len(argv) > 2:
        return set_default(argv[1], argv[2])
    if argv[0] == "--selftest":
        return selftest()
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
