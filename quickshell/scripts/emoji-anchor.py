#!/usr/bin/env python3
"""Прямоугольник активного окна — чтобы выбор эмодзи вставал справа снизу.

Панель эмодзи открывается биндом Super+. (и из лаунчера). Бинд сначала зовёт
этот скрипт: пока панель ещё не показана, активное окно — то, в котором
человек печатает, то есть как раз то, от которого Windows отсчитывает
позицию своей палитры эмодзи. Скрипт кладёт его границы в

    ~/.cache/quickshell/emoji-anchor.json

    {"x": 0, "y": 40, "w": 1920, "h": 1160}

Панель читает файл (shell.qml) и ставит себя нижним правым углом к нижнему
правому углу окна. Положение курсора sway через IPC не отдаёт, поэтому окно
активного приложения — самое близкое, что есть.

Если активного окна нет (пустой рабочий стол) — берём прямоугольник
активного монитора: панель встанет в правый нижний угол экрана.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
STATE = f"{HOME}/.cache/quickshell/emoji-anchor.json"

FALLBACK = {"x": 0, "y": 0, "w": 0, "h": 0}


def sway(args):
    try:
        raw = subprocess.run(["swaymsg", "-t"] + args, capture_output=True,
                             text=True, timeout=2).stdout
        return json.loads(raw or "null")
    except Exception:
        return None


def focused_rect(node):
    """Первый прямоугольник в дереве, помеченный focused — это и есть окно,
    в которое человек печатает (слои панелей quickshell в дерево не попадают)."""
    for side in ("nodes", "floating_nodes"):
        for child in node.get(side) or []:
            found = focused_rect(child)
            if found:
                return found
    if node.get("focused") and node.get("rect"):
        if node.get("app_id") or node.get("window_properties"):
            return node["rect"]
    return None


def output_rect():
    for out in sway(["get_outputs"]) or []:
        if out.get("focused") or out.get("active"):
            return out.get("rect")
    return None


def write(rect):
    data = FALLBACK if not rect else {
        "x": int(rect.get("x", 0)), "y": int(rect.get("y", 0)),
        "w": int(rect.get("width", 0)), "h": int(rect.get("height", 0)),
    }
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    return data


def main(argv):
    if argv and argv[0] == "--show":
        print(json.dumps(write(focused_rect(sway(["get_tree"]) or {}) or output_rect()),
                         ensure_ascii=False))
        return 0
    write(focused_rect(sway(["get_tree"]) or {}) or output_rect())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
