#!/usr/bin/env python3
"""Настройки панели waybar для меню настроек.

    bar-panel.py build              — пересобрать ~/.cache/quickshell/bar.json
    bar-panel.py toggle <модуль>    — включить/выключить модуль бара
    bar-panel.py blur <waybar|panels> — включить/выключить размытие
    bar-panel.py position top|bottom  — бар сверху или снизу
    bar-panel.py mode standard|floating|minimal — вид бара

Своего состояния не держим: модули живут прямо в ~/.config/waybar/config
(списки modules-left/center/right), размытие — в блоках layer_effects
в ~/.config/sway/config. Скрипт только переписывает эти конфиги, поэтому
настройки переживают перезапуск и не расходятся с реальностью.
"""
import json
import os
import re
import subprocess
import sys
from i18n import tr

HOME = os.path.expanduser("~")
BAR = f"{HOME}/.config/waybar/config"
SWAY = f"{HOME}/.config/sway/config"
STATE = f"{HOME}/.cache/quickshell/bar.json"
MODE = f"{HOME}/.config/waybar/mode"

# модуль -> (зона, подпись). Порядок здесь же задаёт порядок в баре.
MODULES = [
    ("custom/logo", "left", tr("Логотип")),
    ("custom/weather", "left", tr("Погода")),
    ("custom/title", "left", tr("Заголовок окна")),
    ("custom/clock", "left", tr("Часы")),
    ("sway/workspaces", "left", tr("Рабочие столы")),
    ("custom/center", "center", tr("Строка в центре")),
    ("network", "right", tr("Сеть")),
    ("memory", "right", tr("Память")),
    ("battery", "right", tr("Батарея")),
    ("backlight", "right", tr("Яркость")),
    ("pulseaudio", "right", tr("Звук")),
    ("sway/language", "right", tr("Раскладка")),
    ("tray", "right", tr("Лоток")),
    ("custom/power", "right", tr("Кнопка питания")),
]
ZONES = ("left", "center", "right")


def load_bar():
    with open(BAR, encoding="utf-8") as fh:
        return json.load(fh)


def save_bar(cfg):
    with open(BAR, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def bar_mode():
    """standard — сплошной, floating — островок, minimal — без подложки."""
    try:
        with open(MODE, encoding="utf-8") as fh:
            mode = fh.read().strip()
    except OSError:
        mode = "standard"
    return mode if mode in ("standard", "floating", "minimal") else "standard"


def bar_position():
    try:
        return load_bar().get("position", "top")
    except Exception:
        return "top"


def margins_for(mode, position):
    """Плавающий бар не прилипает к краям."""
    if mode == "floating":
        return {"margin-left": 8, "margin-right": 8,
                "margin-top": 6 if position == "top" else 0,
                "margin-bottom": 6 if position == "bottom" else 0}
    return {"margin-left": 0, "margin-right": 0,
            "margin-top": 0, "margin-bottom": 0}


def reload_waybar():
    subprocess.run(["pkill", "-SIGUSR2", "-x", "waybar"], check=False)


CSS = f"{HOME}/.config/waybar/style.css"


def patch_css(mode):
    """Поправить вид бара прямо в style.css.

    Вид бара — это фон и скругление в CSS. Пересобирать всю тему ради двух
    строк смысла нет (matugen считает палитру заново и может не сойтись), так
    что меняем только нужные строки, а если файла нет — просим theme-gen.
    """
    try:
        with open(CSS, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return False
    block = re.search(r"(window#waybar\s*\{)(.*?)(\})", text, re.S)
    if not block:
        return False
    body = block.group(2)
    color = re.search(r"background:\s*([^;]+);", body)
    color = color.group(1).strip() if color else "alpha(#000000, 0.75)"
    if mode == "minimal":
        color = "transparent"
    radius = "14px" if mode == "floating" else "0"
    if re.search(r"background:[^;]+;", body):
        body = re.sub(r"background:[^;]+;", f"background: {color};", body, count=1)
    else:
        body = f"\n    background: {color};" + body
    if re.search(r"border-radius:[^;]+;", body):
        body = re.sub(r"border-radius:[^;]+;", f"border-radius: {radius};", body, count=1)
    else:
        body += f"\n    border-radius: {radius};"
    text = text[:block.start(2)] + body + text[block.end(2):]
    try:
        with open(CSS, "w", encoding="utf-8") as fh:
            fh.write(text)
    except OSError:
        return False
    return True


def rebuild_css():
    """Пересобрать style.css целиком: вид бара — это CSS (фон и радиус)."""
    mode = "auto"
    try:
        with open(f"{HOME}/.cache/wallpaper/theme_mode", encoding="utf-8") as fh:
            mode = fh.read().strip() or "auto"
    except OSError:
        pass
    subprocess.run([f"{HOME}/.config/wallpaper/theme-gen.sh", "--mode", mode],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def enabled():
    """Модуль -> зона, в которой он сейчас стоит."""
    cfg = load_bar()
    out = {}
    for zone in ZONES:
        for key in cfg.get(f"modules-{zone}", []):
            out[key] = zone
    return out


def blur_state():
    state = {"waybar": True, "panels": True}
    try:
        with open(SWAY, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return state
    for ns, key in (("waybar", "waybar"), ("qs-panel", "panels")):
        m = re.search(r'layer_effects\s+"%s"\s*\{(.*?)\}' % re.escape(ns), text, re.S)
        if m:
            state[key] = "blur disable" not in m.group(1)
    return state


def write_state():
    on = enabled()
    items = []
    for key, zone, name in MODULES:
        items.append({"key": key, "zone": zone, "name": name, "on": key in on})
    for key, zone in on.items():  # чужие модули (допишу сам) тоже показываем
        if not any(k == key for k, _z, _n in MODULES):
            items.append({"key": key, "zone": zone, "name": key, "on": True})
    state = {"modules": items, "blur": blur_state(),
             "position": bar_position(), "mode": bar_mode()}
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False, indent=1)
    return state


def toggle(key):
    cfg = load_bar()
    on = enabled()
    if key in on:
        del on[key]
    else:
        on[key] = next((z for k, z, _n in MODULES if k == key), "right")
    # порядок внутри зоны — как в MODULES, чтобы модуль вставал на своё место
    for zone in ZONES:
        known = [k for k, z, _n in MODULES if z == zone and on.get(k) == zone]
        other = [k for k, z in on.items() if z == zone and k not in known]
        cfg[f"modules-{zone}"] = known + other
    with open(BAR, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    subprocess.run(["pkill", "-SIGUSR2", "-x", "waybar"], check=False)


def set_position(position):
    cfg = load_bar()
    cfg["position"] = "bottom" if position == "bottom" else "top"
    cfg.update(margins_for(bar_mode(), cfg["position"]))
    save_bar(cfg)
    reload_waybar()
    write_state()


def set_mode(mode):
    if mode not in ("standard", "floating", "minimal"):
        return 1
    os.makedirs(os.path.dirname(MODE), exist_ok=True)
    with open(MODE, "w", encoding="utf-8") as fh:
        fh.write(mode + "\n")
    cfg = load_bar()
    cfg.update(margins_for(mode, cfg.get("position", "top")))
    save_bar(cfg)
    if not patch_css(mode):
        rebuild_css()
    reload_waybar()
    write_state()
    return 0


def toggle_blur(which):
    ns = "qs-panel" if which == "panels" else "waybar"
    try:
        with open(SWAY, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        print(tr("не читается конфиг sway"), file=sys.stderr)
        return 1
    pat = re.compile(r'(layer_effects\s+"%s"\s*\{(?:(?!\}).)*?blur\s+)(enable|disable)'
                     % re.escape(ns), re.S)
    if not pat.search(text):
        print(f'в конфиге sway нет блока layer_effects "{ns}"', file=sys.stderr)
        return 1
    new = "disable" if "blur enable" in pat.search(text).group(0) else "enable"
    with open(SWAY, "w", encoding="utf-8") as fh:
        fh.write(pat.sub(lambda m: m.group(1) + new, text, count=1))
    subprocess.run(["swaymsg", "layer_effects", ns, f"blur {new}"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


def main(argv):
    if not argv or argv[0] == "build":
        write_state()
        return 0
    if argv[0] == "toggle" and len(argv) > 1:
        toggle(argv[1])
        write_state()
        return 0
    if argv[0] == "position" and len(argv) > 1:
        set_position(argv[1])
        return 0

    if argv[0] == "mode" and len(argv) > 1:
        return set_mode(argv[1])

    if argv[0] == "blur" and len(argv) > 1:
        toggle_blur(argv[1])
        write_state()
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
