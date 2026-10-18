#!/usr/bin/env python3
"""Заголовок активного окна — левый край waybar, перед датой и временем.

Подписываемся на события sway (без опроса). Подписка обязательно включает
workspace: при переходе на пустой стол событий окна не приходит вообще, и в
модуле оставался бы заголовок прошлого окна. Если подписка оборвалась (reload
или перезапуск sway) — подключаемся заново.

Печатаем строку только при изменении: waybar читает stdout построчно. Пустая
строка прячет модуль (hide-empty-text в конфиге). Вывод экранируется — waybar
разбирает его как Pango-разметку, и «&» или «<» в заголовке сломали бы label.
"""
import json
import re
import subprocess
import sys
import time
from xml.sax.saxutils import escape

# Невидимые служебные символы: Telegram, например, суёт в заголовок bidi-маркеры.
INVISIBLE = re.compile("[\u200b-\u200f\u202a-\u202e\u2066-\u2069]")


def write_line(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def focused_title():
    """Заголовок активного окна (пустая строка, если фокуса нет)."""
    try:
        raw = subprocess.run(["swaymsg", "-t", "get_tree"], capture_output=True,
                             text=True, timeout=2).stdout
        tree = json.loads(raw)
    except Exception:
        return ""
    best = {"depth": -1, "name": ""}

    def walk(node, depth):
        # окно — это контейнер со shell (xdg_shell/xwayland) и признаком фокуса
        if node.get("focused") and node.get("shell") and node.get("name"):
            if depth > best["depth"]:
                best["depth"] = depth
                best["name"] = node["name"]
        for key in ("nodes", "floating_nodes"):
            for child in node.get(key) or []:
                walk(child, depth + 1)

    walk(tree, 0)
    return INVISIBLE.sub("", best["name"]).strip()


def emit(line, last):
    """Печатает строку, если она изменилась; возвращает новое «последнее»."""
    if line == last:
        return last
    write_line(line)
    return line


def main():
    last = None
    while True:
        try:
            proc = subprocess.Popen(["swaymsg", "-t", "subscribe", "-m",
                                     '["window","workspace"]'],
                                    stdout=subprocess.PIPE, text=True)
        except Exception:
            time.sleep(2)
            continue
        last = emit(escape(focused_title()), last)
        for line in proc.stdout:
            try:
                json.loads(line)
            except Exception:
                continue
            last = emit(escape(focused_title()), last)
        time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except BrokenPipeError:
        sys.exit(0)
