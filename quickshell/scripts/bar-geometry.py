#!/usr/bin/env python3
"""Где в полосе waybar стоят кнопки — по настоящей геометрии, а не по курсору.

    bar-geometry.py <x_клика>   — x центра кнопки, ближайшей к клику

Смысл: виджет, открытый щелчком по кнопке бара, должен встать строго под
серединой этой кнопки. Позиция курсора для этого не годится — человек
нажимает не точно в середину, а мышь к тому же успевает уехать.

Как работает: снимаем полосу бара (grim) и ищем в ней «чернила» — колонки,
где текст иконок заметно отличается от фона. Фон у бара полупрозрачный и
меняется вместе с обоями, поэтому сравниваем не цвет, а разброс по
колонке: у колонки с текстом он большой, у пустой — почти нулевой.
Соседние колонки склеиваем в блоки (зазор меньше 18 px — это одна кнопка:
иконка и подпись), а из них выбираем блок, чей центр ближе всего к клику.

Координаты — логические, как у quickshell и как у вывода sway.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
BAR = f"{HOME}/.config/waybar/config"
# разрыв между кнопками: у модулей отступ 14 px с каждой стороны плюс
# разделитель, то есть между соседними надписями пусто больше 20 px
GAP = 18


def sway_json(kind):
    try:
        raw = subprocess.run(["swaymsg", "-t", kind], capture_output=True,
                             text=True, timeout=3).stdout
        return json.loads(raw or "null")
    except Exception:
        return None


def bar_config():
    try:
        with open(BAR, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def output_rect():
    """Прямоугольник вывода, на котором сейчас фокус (в логических пикселях)."""
    outs = sway_json("get_outputs") or []
    chosen = None
    for out in outs:
        if out.get("focused"):
            chosen = out
            break
    if chosen is None and outs:
        chosen = outs[0]
    if not chosen:
        return None
    rect = chosen.get("rect") or {}
    scale = chosen.get("scale", 1) or 1
    return {
        "x": int(rect.get("x", 0)),
        "y": int(rect.get("y", 0)),
        "w": int(rect.get("width", 1920) / scale),
        "h": int(rect.get("height", 1200) / scale),
    }


def strip_rect(cfg, out):
    """Прямоугольник полосы бара на экране."""
    height = int(cfg.get("height", 34))
    left = int(cfg.get("margin-left", 0))
    right = int(cfg.get("margin-right", 0))
    top = int(cfg.get("margin-top", 0))
    bottom = int(cfg.get("margin-bottom", 0))
    bottom_bar = cfg.get("position", "top") == "bottom"
    if bottom_bar:
        y = out["y"] + out["h"] - bottom - height
    else:
        y = out["y"] + top
    return {"x": out["x"] + left, "y": y,
            "w": max(1, out["w"] - left - right), "h": height}


def capture(rect):
    """Снимок полосы бара (PNG в памяти)."""
    geo = f"{rect['x']},{rect['y']} {rect['w']}x{rect['h']}"
    try:
        done = subprocess.run(["grim", "-g", geo, "-"], capture_output=True,
                              timeout=6)
        return done.stdout if done.returncode == 0 and done.stdout else b""
    except Exception:
        return b""


def ink_columns(png):
    """Колонки с «чернилами»: чем больше разброс, тем заметнее текст."""
    try:
        from io import BytesIO
        from PIL import Image, ImageStat
    except Exception:
        return []
    try:
        img = Image.open(BytesIO(png)).convert("L")
    except Exception:
        return []
    if img.width < 8 or img.height < 4:
        return []
    # разброс по каждой колонке: у пустого места он около нуля
    stat = ImageStat.Stat(img)
    # Stat считает по каналу целиком, поэтому считаем столбцы вручную
    pixels = img.load()
    cols = []
    for x in range(img.width):
        values = [pixels[x, y] for y in range(img.height)]
        mean = sum(values) / len(values)
        var = sum((v - mean) ** 2 for v in values) / len(values)
        cols.append(var ** 0.5)
    return cols


def blocks(cols, threshold=10.0):
    """Склеиваем колонки с чернилами в блоки (кнопки)."""
    out = []
    start = None
    last = None
    for x, value in enumerate(cols):
        if value >= threshold:
            if start is None:
                start = x
            last = x
        elif start is not None and x - last > GAP:
            out.append((start, last))
            start = None
    if start is not None:
        out.append((start, last))
    return out


def main(argv):
    if not argv:
        print("")
        return 0
    try:
        click = float(argv[0])
    except ValueError:
        print("")
        return 0

    cfg = bar_config()
    out = output_rect()
    if not out:
        print("")
        return 0
    rect = strip_rect(cfg, out)
    png = capture(rect)
    if not png:
        print("")
        return 0
    cols = ink_columns(png)
    if not cols:
        print("")
        return 0
    found = blocks(cols)
    if not found:
        print("")
        return 0

    # клик приходит в координатах экрана, а блоки — в координатах снимка
    local = click - rect["x"]
    best = None
    best_dist = None
    for start, end in found:
        center = (start + end) / 2.0
        dist = abs(center - local)
        if best_dist is None or dist < best_dist:
            best = center
            best_dist = dist
    if best is None:
        print("")
        return 0
    print(int(round(rect["x"] + best)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
