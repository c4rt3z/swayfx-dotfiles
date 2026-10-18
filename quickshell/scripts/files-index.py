#!/usr/bin/env python3
"""Индекс файлов для мега-поиска -> ~/.cache/quickshell/files.txt.

Смотрим только домашние папки, где файлы и правда ищут руками, и ограничиваем
глубину: полный обход $HOME — это минуты и мегабайты мусора. Скрипт дешёвый,
поэтому панель поиска запускает его раз в несколько часов.
"""
import os
import sys
import time
from i18n import tr

HOME = os.path.expanduser("~")
STATE = f"{HOME}/.cache/quickshell/files.txt"

ROOTS = [
    ("Desktop", 3), ("Documents", 4), ("Downloads", 4), ("Pictures", 4),
    ("Videos", 3), ("Music", 3), ("Projects", 4), ("Wallpapers", 4),
    (".config", 3), (tr("Загрузки"), 4), (tr("Документы"), 4), (tr("Изображения"), 4),
]
SKIP = {".git", "node_modules", "__pycache__", ".cache", ".cargo", ".rustup",
        ".local", ".mozilla", ".thunderbird", "site-packages", ".venv", "venv"}
LIMIT = 25000


def main():
    found = []
    for rel, depth in ROOTS:
        base = os.path.join(HOME, rel)
        if not os.path.isdir(base):
            continue
        root_depth = base.count(os.sep)
        for current, dirs, files in os.walk(base):
            if current.count(os.sep) - root_depth >= depth:
                dirs[:] = []
            dirs[:] = [d for d in dirs if d not in SKIP and not d.startswith(".cache")]
            for name in files:
                if name.startswith(".") and not name.endswith(".conf"):
                    continue
                found.append(os.path.join(current, name))
                if len(found) >= LIMIT:
                    break
            if len(found) >= LIMIT:
                break
        if len(found) >= LIMIT:
            break

    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        fh.write("\n".join(found))
    print(f"файлов в индексе: {len(found)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
