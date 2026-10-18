#!/usr/bin/env python3
"""Терминал по умолчанию и службы рабочего стола — данные для настроек.

    system-index.py build           — пересобрать ~/.cache/quickshell/system.json
    system-index.py setterm <cmd>   — сделать терминал по умолчанию
    system-index.py font +0.5|−0.5  — размер шрифта в конфиге терминала
    system-index.py restart <служба>— перезапустить службу
    system-index.py --selftest

Терминал. В ~/.config/sway/config он задан строкой «set $term alacritty», её и
переписываем: список терминалов смотрим по PATH, поэтому показываем только те,
что установлены. После правки зовём «swaymsg reload» (как и для раскладок) —
sway перечитает конфиг, бар при этом мигнёт.

Шрифт берём из конфига выбранного терминала (alacritty.toml, kitty.conf).
Файлы терминала пользовательские, тема пишет свои (wallpaper.toml), поэтому
размер здесь правится точечно — регуляркой по нужной строке.

Службы — это то, что запускает sway (exec в конфиге) плюс пара служб systemd
пользователя. Перезапускаем их тем же способом, каким они и запускаются, поэтому
в сводке рядом с каждой службой видно её команду.
"""

import json
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
CACHE = f"{HOME}/.cache/quickshell"
STATE = f"{CACHE}/system.json"
SWAY = f"{HOME}/.config/sway/config"

TERMINALS = [
    ("alacritty", "Alacritty"),
    ("kitty", "Kitty"),
    ("konsole", "Konsole"),
    ("foot", "Foot"),
    ("wezterm", "WezTerm"),
    ("xterm", "XTerm"),
]

FONT_MIN, FONT_MAX, FONT_STEP = 6.0, 28.0, 0.5

FONT_FILES = {
    "alacritty": (f"{HOME}/.config/alacritty/alacritty.toml", r"^size\s*=\s*([0-9.]+)",
                  "size = {}"),
    "kitty": (f"{HOME}/.config/kitty/kitty.conf", r"^font_size\s+([0-9.]+)",
              "font_size {}"),
}


def read_sway():
    try:
        with open(SWAY, encoding="utf-8") as fh:
            return fh.read()
    except Exception:
        return ""


def current_terminal():
    match = re.search(r"^\s*set\s+\$term\s+(\S+)", read_sway(), re.M)
    return match.group(1) if match else "alacritty"


def terminals():
    current = current_terminal()
    out = []
    for cmd, name in TERMINALS:
        installed = bool(shutil.which(cmd))
        out.append({
            "cmd": cmd,
            "name": name,
            "installed": installed,
            "current": cmd == current,
            # если выбранный терминал не установлен, показать его всё равно надо
            "visible": installed or cmd == current,
        })
    return [t for t in out if t["visible"]]


def font_info(term=None):
    term = term or current_terminal()
    if term not in FONT_FILES:
        return None
    path, pattern, template = FONT_FILES[term]
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except Exception:
        return None
    match = re.search(pattern, text, re.M)
    size = float(match.group(1)) if match else 0.0
    return {"path": path, "name": os.path.basename(path), "term": term,
            "size": size, "min": FONT_MIN, "max": FONT_MAX, "step": FONT_STEP}


def services():
    sway = read_sway()
    idle = ""
    for line in sway.splitlines():
        if re.match(r"\s*exec\s+swayidle\b", line):
            idle = re.sub(r"^\s*exec\s+", "", line).strip().strip('"')
            break
    if not idle:
        idle = "swayidle -w"

    items = [
        ("quickshell", "quickshell", "панели, поиск, эмодзи, окно блокировки",
         # pgrep-страховка: пока quickshell поднимался сам (watchdog), второй
         # экземпляр не нужен — иначе панели нарисуются дважды
         "pgrep -x qs", "pkill -x qs; sleep 1; pkill -x qs; sleep 1; "
                       "pgrep -x qs >/dev/null || setsid -f qs"),
        ("waybar", "waybar", "полоса сверху",
         "pgrep -x waybar",
         # bar поднимает sway из строки exec_always (там же и переменная окружения
         # для Qt), поэтому перезапуск — это перечитывание конфига sway
         "swaymsg reload"),
        ("swayidle", "swayidle", "блокировка и гашение экрана по времени",
         "pgrep -x swayidle",
         f"pkill -x swayidle; sleep 1; setsid -f {idle}"),
        ("playerctld", "playerctld", "какой плеер считается текущим",
         "pgrep -x playerctld", "pkill -x playerctld; sleep 1; setsid -f playerctld daemon"),
        ("wireplumber", "wireplumber", "звук (служба systemd)",
         "systemctl --user is-active --quiet wireplumber.service",
         "systemctl --user restart wireplumber.service"),
    ]

    out = []
    for key, name, note, check, restart in items:
        # команда проверки молчит, если служба не идёт, — смотрим только код возврата
        try:
            running = subprocess.run(["sh", "-c", check], capture_output=True,
                                     timeout=5).returncode == 0
        except Exception:
            running = False
        out.append({"id": key, "name": name, "note": note, "running": running,
                    "restart": restart})
    return out


def build():
    data = {
        "term": current_terminal(),
        "terminals": terminals(),
        "font": font_info(),
        "services": services(),
        "sway_conf": SWAY,
    }
    os.makedirs(CACHE, exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    return data


def set_term(cmd):
    known = {name for name, _ in TERMINALS}
    if cmd not in known:
        print(f"system-index: неизвестный терминал «{cmd}»", file=sys.stderr)
        return 1
    if not shutil.which(cmd):
        print(f"system-index: {cmd} не установлен", file=sys.stderr)
        return 1
    text = read_sway()
    new, count = re.subn(r"^(\s*set\s+\$term\s+)\S+", r"\g<1>" + cmd, text, count=1, flags=re.M)
    if count == 0:
        print("system-index: в конфиге sway нет строки «set $term»", file=sys.stderr)
        return 1
    with open(SWAY, "w", encoding="utf-8") as fh:
        fh.write(new)
    subprocess.run(["swaymsg", "reload"], capture_output=True)
    build()
    return 0


def set_font(value):
    info = font_info()
    if not info:
        print("system-index: для этого терминала размер негде взять", file=sys.stderr)
        return 1
    if value.startswith(("+", "-")):
        size = info["size"] + float(value)
    else:
        size = float(value)
    size = max(FONT_MIN, min(FONT_MAX, round(size, 1)))
    path, pattern, template = FONT_FILES[info["term"]]
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    line = template.format(size)
    if re.search(pattern, text, re.M):
        text = re.sub(pattern, line.replace("\\", "\\\\"), text, count=1, flags=re.M)
    else:
        text = text.rstrip("\n") + "\n" + line + "\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    build()
    return 0


def restart(name):
    for item in services():
        if item["id"] == name:
            subprocess.Popen(["sh", "-c", item["restart"]], start_new_session=True)
            return 0
    print(f"system-index: нет службы «{name}»", file=sys.stderr)
    return 1


def selftest():
    problems = []
    data = build()
    if not data["term"]:
        problems.append("не понял терминал по умолчанию")
    if not any(t["installed"] for t in data["terminals"]):
        problems.append("не нашёл ни одного установленного терминала")
    if not any(t["current"] for t in data["terminals"]):
        problems.append("текущий терминал потерялся в списке")
    if len(data["services"]) < 4:
        problems.append("служб меньше четырёх")
    if not any(s["name"] == "quickshell" for s in data["services"]):
        problems.append("в списке нет quickshell")
    if data["font"] and not (FONT_MIN <= data["font"]["size"] <= FONT_MAX):
        problems.append(f"размер шрифта вне диапазона: {data['font']}")
    # проверка записи шрифта без порчи файла: правим размер и возвращаем
    if data["font"]:
        path = data["font"]["path"]
        with open(path, encoding="utf-8") as fh:
            before = fh.read()
        set_font("+0.5")
        set_font("-0.5")
        with open(path, encoding="utf-8") as fh:
            after = fh.read()
        if before != after:
            problems.append("правка шрифта туда-обратно не вернула файл")

    if problems:
        for p in problems:
            print("  ✗", p)
        return 1
    print("  ✓ терминал:", data["term"], "| установлено:",
          ", ".join(t["name"] for t in data["terminals"] if t["installed"]))
    print("  ✓ шрифт:", (f"{data['font']['name']} {data['font']['size']}"
                         if data["font"] else "нет конфига"))
    print("  ✓ службы:", ", ".join(f"{s['name']}{'' if s['running'] else '(стоп)'}"
                                  for s in data["services"]))
    return 0


def main(argv):
    if not argv or argv[0] == "build":
        build()
        return 0
    if argv[0] == "setterm" and len(argv) > 1:
        return set_term(argv[1])
    if argv[0] == "font" and len(argv) > 1:
        return set_font(argv[1])
    if argv[0] == "restart" and len(argv) > 1:
        return restart(argv[1])
    if argv[0] == "--selftest":
        return selftest()
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
