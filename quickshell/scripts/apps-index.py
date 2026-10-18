#!/usr/bin/env python3
"""Список приложений для лаунчера quickshell (замена wofi --show drun).

    apps-index.py            — собрать список и положить в кэш
    apps-index.py --stdout   — напечатать JSON (так его зовёт панель)

Формат: {"items": [{"id", "name", "comment", "exec", "terminal", "icon", "search"}]}
"""

import json
import os
import re
import sys

HOME = os.path.expanduser("~")
CACHE = f"{HOME}/.cache/quickshell/apps.json"
SWAY_CONFIG = f"{HOME}/.config/sway/config"

# каталоги .desktop: чем раньше, тем приоритетнее (XDG)
DATA_DIRS = [
    os.path.join(os.environ.get("XDG_DATA_HOME", f"{HOME}/.local/share"), "applications"),
]
for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
    if d:
        DATA_DIRS.append(os.path.join(d, "applications"))
DATA_DIRS += [
    "/var/lib/flatpak/exports/share/applications",
    f"{HOME}/.local/share/flatpak/exports/share/applications",
]

# темы иконок: сначала та, что настроена в GTK, потом общие
ICON_THEMES = ["breeze", "breeze-dark", "Adwaita", "hicolor", "Papirus", "Papirus-Dark"]
ICON_ROOTS = [f"{HOME}/.local/share/icons", f"{HOME}/.icons", "/usr/share/icons"]
ICON_SIZES = ["64", "48", "32", "128", "256", "96", "24", "22", "16"]

# поля Exec, которые нужно выкинуть (%f, %U и т.п.)
FIELD_CODE = re.compile(r"\s*%[fFuUdDnNickvm]")


def locale_variants():
    """ru_RU.UTF-8 -> ['ru_RU', 'ru'] — порядок поиска Name[ru] и т.п."""
    raw = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or ""
    raw = raw.split(".")[0].split("@")[0]
    if not raw:
        return []
    out = [raw]
    if "_" in raw:
        out.append(raw.split("_")[0])
    return out


LANGS = locale_variants()


def localised(entry, key):
    for lang in LANGS:
        v = entry.get(f"{key}[{lang}]")
        if v:
            return v
    return entry.get(key, "")


def parse_desktop(path):
    """Читает только секцию [Desktop Entry]."""
    entry = {}
    inside = False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("["):
                    inside = line.strip() == "[Desktop Entry]"
                    continue
                if not inside or not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                if k not in entry:  # первое значение выигрывает
                    entry[k] = v.strip()
    except OSError:
        return None
    return entry


def truthy(v):
    return str(v).strip().lower() == "true"


def terminal_command():
    """Каким терминалом запускать Terminal=true (берём $term из конфига sway)."""
    term = "alacritty"
    try:
        with open(SWAY_CONFIG, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r"\s*set\s+\$term\s+(\S+)", line)
                if m:
                    term = m.group(1)
                    break
    except OSError:
        pass
    return term


def clean_exec(exec_line, terminal):
    cmd = FIELD_CODE.sub("", exec_line).strip()
    cmd = re.sub(r"\s+", " ", cmd)
    if not cmd:
        return ""
    if terminal:
        cmd = f"{terminal_command()} -e {cmd}"
    return cmd


def resolve_icon(name, icon_files):
    """Icon= в .desktop — либо путь, либо имя в теме иконок."""
    if not name:
        return ""
    if name.startswith("/"):
        return name if os.path.isfile(name) else ""
    base = re.sub(r"\.(png|svg|xpm|ico)$", "", name)
    if base in icon_files:
        return icon_files[base]
    # org.kde.dolphin -> dolphin (в темах иконок имена иногда без префикса)
    if "." in base:
        tail = base.rsplit(".", 1)[-1]
        if tail in icon_files:
            return icon_files[tail]
    return ""


def build_icon_index():
    """Один проход по темам иконок: имя -> путь (лучший размер)."""
    index = {}
    for theme in ICON_THEMES:
        for root in ICON_ROOTS:
            base = os.path.join(root, theme)
            if not os.path.isdir(base):
                continue
            # 1) известные размерные каталоги
            for size in ICON_SIZES:
                for sub in (f"apps/{size}", f"{size}x{size}/apps", "apps/scalable",
                            "scalable/apps", f"apps/{size}x{size}", "apps", ""):
                    d = os.path.join(base, sub)
                    if not os.path.isdir(d):
                        continue
                    try:
                        names = os.listdir(d)
                    except OSError:
                        continue
                    for fn in names:
                        key, ext = os.path.splitext(fn)
                        if ext not in (".png", ".svg", ".xpm"):
                            continue
                        if key not in index:  # тема/размер выше по списку выигрывает
                            index[key] = os.path.join(d, fn)
    # последний шанс — pixmaps
    for root in ("/usr/share/pixmaps", f"{HOME}/.local/share/pixmaps"):
        if not os.path.isdir(root):
            continue
        for fn in os.listdir(root):
            key, ext = os.path.splitext(fn)
            if ext in (".png", ".svg", ".xpm") and key not in index:
                index[key] = os.path.join(root, fn)
    return index


def collect(icon_files):
    """Собирает приложения: одинаковый id из более приоритетного каталога выигрывает."""
    seen = {}
    for d in DATA_DIRS:
        if not os.path.isdir(d):
            continue
        for root, dirs, files in os.walk(d):
            dirs[:] = [x for x in dirs if not x.startswith(".")]
            for fn in files:
                if not fn.endswith(".desktop"):
                    continue
                path = os.path.join(root, fn)
                rel = os.path.relpath(path, d)
                app_id = rel[:-len(".desktop")].replace("/", "-")
                if app_id in seen:
                    continue
                entry = parse_desktop(path)
                if not entry:
                    continue
                if entry.get("Type", "Application") != "Application":
                    continue
                if truthy(entry.get("NoDisplay")) or truthy(entry.get("Hidden")):
                    continue
                name = localised(entry, "Name").strip()
                exec_line = entry.get("Exec", "").strip()
                if not name or not exec_line:
                    continue
                terminal = truthy(entry.get("Terminal"))
                cmd = clean_exec(exec_line, terminal)
                if not cmd:
                    continue
                generic = localised(entry, "GenericName").strip()
                comment = localised(entry, "Comment").strip()
                icon = resolve_icon(entry.get("Icon", "").strip(), icon_files)
                seen[app_id] = {
                    "id": app_id,
                    "name": name,
                    "comment": comment or generic,
                    "exec": cmd,
                    "terminal": terminal,
                    "icon": icon,
                    # чем приложение умеет открывать файлы и к какой категории
                    # себя относит — по этому настройки собирают список
                    # кандидатов для «приложений по умолчанию»
                    "mime": entry.get("MimeType", "").strip(),
                    "categories": entry.get("Categories", "").strip(),
                    "search": " ".join(x for x in (name, generic, comment, app_id)).lower(),
                }
    items = sorted(seen.values(), key=lambda a: a["name"].casefold())
    return {"items": items}


def main():
    data = collect(build_icon_index())
    raw = json.dumps(data, ensure_ascii=False, indent=None)
    if "--stdout" in sys.argv:
        print(raw)
        return 0
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = f"{CACHE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(raw)
    os.replace(tmp, CACHE)
    print(f"приложений: {len(data['items'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
