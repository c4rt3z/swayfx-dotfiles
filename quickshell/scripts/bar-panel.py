#!/usr/bin/env python3
"""Настройки панели waybar для меню настроек.

    bar-panel.py build              — пересобрать ~/.cache/quickshell/bar.json
    bar-panel.py toggle <модуль>    — включить/выключить модуль бара
    bar-panel.py blur <waybar|panels> — включить/выключить размытие

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

# модуль -> (зона, подпись). Порядок здесь же задаёт порядок в баре.
MODULES = [
    ("custom/logo", "left", tr("Логотип")),
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
    state = {"modules": items, "blur": blur_state()}
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
    if argv[0] == "blur" and len(argv) > 1:
        toggle_blur(argv[1])
        write_state()
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
