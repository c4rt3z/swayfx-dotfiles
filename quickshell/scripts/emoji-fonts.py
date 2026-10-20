#!/usr/bin/env python3
"""Шрифт эмодзи для панели выбора.

    emoji-fonts.py list            — установленные эмодзи-шрифты (JSON)
    emoji-fonts.py set <имя>       — выбрать шрифт

Панель рисует эмодзи тем шрифтом, который выбран здесь. По умолчанию —
Noto Color Emoji: глифы Nerd Font покрывают не все эмодзи, и часть выглядит
квадратами или странными.

Настройка: ~/.config/quickshell/emoji.json
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
FILE = f"{HOME}/.config/quickshell/emoji.json"
DEFAULT = "Noto Color Emoji"


def installed():
    """Семейства шрифтов, где есть эмодзи или символы."""
    try:
        out = subprocess.run(["fc-list", ":", "family"], capture_output=True,
                             text=True, timeout=8).stdout
    except Exception:
        return [DEFAULT]
    names = set()
    for line in out.splitlines():
        for part in line.split(","):
            name = part.strip()
            low = name.lower()
            if any(k in low for k in ("emoji", "symbola", "twemoji", "noto color",
                                      "noto emoji", "openmoji", "joypixels")):
                names.add(name)
    if not names:
        names.add(DEFAULT)
    return sorted(names)


def current():
    try:
        with open(FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        name = str((data or {}).get("font") or "").strip()
        if name:
            return name
    except Exception:
        pass
    return DEFAULT


def save(name):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    tmp = f"{FILE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"font": name}, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, FILE)


def main(argv):
    if not argv or argv[0] == "list":
        print(json.dumps({"ok": True, "fonts": installed(), "current": current()},
                         ensure_ascii=False))
        return 0
    if argv[0] == "set" and len(argv) > 1:
        name = " ".join(argv[1:])
        if name not in installed():
            print(f"шрифт «{name}» не установлен", file=sys.stderr)
            return 2
        save(name)
        print(json.dumps({"ok": True, "fonts": installed(), "current": current()},
                         ensure_ascii=False))
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
