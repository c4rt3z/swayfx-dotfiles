#!/usr/bin/env python3
"""Раскладки клавиатуры для меню настроек.

    layouts-index.py build            — пересобрать ~/.cache/quickshell/layouts.json
    layouts-index.py toggle <код>     — включить/выключить раскладку
    layouts-index.py switch <код|next> — сделать раскладку активной
    layouts-index.py --selftest       — проверки

Своего состояния не держим: набор раскладок живёт прямо в ~/.config/sway/config
(строка xkb_layout внутри блока input type:keyboard), порядок строки задаёт
порядок переключения Alt+Shift. Скрипт только переписывает эту строку и
применяет её.

Две тонкости, проверенные на этом стенде (sway 1.12, 18.10.2026):

  * применять набор через `swaymsg input type:keyboard xkb_layout` нельзя:
    sway отвечает success, но в списке устройств остаётся одна раскладка
    (русская пропадала). Поэтому включение и выключение переписывают конфиг
    и перезагружают его через `swaymsg reload`;
  * переключение активной раскладки — наоборот, на лету и без перезагрузки:
    `swaymsg input type:keyboard xkb_switch_layout <номер>`. Список оно не
    трогает, поэтому им можно пользоваться свободно.
"""
import json
import os
import re
import subprocess
import sys
from i18n import tr

HOME = os.path.expanduser("~")
SWAY = f"{HOME}/.config/sway/config"
STATE = f"{HOME}/.cache/quickshell/layouts.json"
RULES = "/usr/share/X11/xkb/rules/evdev.lst"
SYMBOLS = "/usr/share/X11/xkb/symbols"
NAME_RE = re.compile(r'name\[Group1\]\s*=\s*"([^"]+)"')
# файлы с именем, но всё-таки не раскладки
SKIP = {"empty", "trans"}

# Порядок для списка «добавить»: сначала то, что обычно ищут, потом остальное
# по алфавиту. Список кодов — из xkb (evdev.lst), не выдуманный.
COMMON = [
    "us", "ru", "ua", "by", "kz", "de", "fr", "es", "it", "pl", "tr", "cz",
    "sk", "nl", "pt", "gb", "gr", "il", "rs", "fi", "se", "no", "dk", "jp",
    "kr", "cn", "ge", "am", "az", "uz", "th", "vn", "br", "ch", "hu", "ro",
    "bg", "ee", "lv", "lt", "md", "ar", "in",
]

LAYOUT_RE = re.compile(r'^([ \t]*)xkb_layout[ \t]+"([^"]*)"', re.M)


def read_config():
    with open(SWAY, encoding="utf-8") as fh:
        return fh.read()


def enabled_codes(text):
    """Список кодов из строки xkb_layout — в том порядке, как переключается."""
    match = LAYOUT_RE.search(text)
    if not match:
        return []
    return [code.strip() for code in match.group(2).split(",") if code.strip()]


def write_enabled(codes):
    """Переписать строку xkb_layout и применить её перезагрузкой sway."""
    text = read_config()
    value = ", ".join(codes)
    replacement = 'xkb_layout "' + value + '"'

    if LAYOUT_RE.search(text):
        text = LAYOUT_RE.sub(lambda m: m.group(1) + replacement, text, count=1)
    else:
        # строки нет (кто-то убрал) — дописываем в блок клавиатуры
        text = text.replace("input type:keyboard {",
                            'input type:keyboard {\n    ' + replacement, 1)
    with open(SWAY, "w", encoding="utf-8") as fh:
        fh.write(text)
    apply()


def apply():
    """Перезагрузка конфига: только так новый набор раскладок доезжает до всех
    устройств. Побочный эффект — waybar перезапускается (это строка
    exec_always в конфиге), поэтому дёргаем только по делу."""
    try:
        subprocess.run(["swaymsg", "reload"], capture_output=True, text=True,
                       timeout=5)
    except Exception:
        pass


def keyboards():
    try:
        raw = subprocess.run(["swaymsg", "-t", "get_inputs"], capture_output=True,
                             text=True, timeout=3).stdout
        return [i for i in json.loads(raw or "[]") if i.get("type") == "keyboard"]
    except Exception:
        return []


def active_index(codes):
    """Номер активной раскладки. У беспроводного приёмника и кнопок питания
    список бывает пустой, поэтому берём первое устройство, где раскладок
    столько же, сколько мы включили."""
    for board in keyboards():
        names = board.get("xkb_layout_names") or []
        if len(names) == len(codes):
            index = board.get("xkb_active_layout_index") or 0
            return index if 0 <= index < max(1, len(codes)) else 0
    boards = keyboards()
    if boards:
        return boards[0].get("xkb_active_layout_index") or 0
    return 0


def switch(code):
    """Сделать раскладку активной. На лету, конфиг не трогаем."""
    codes = enabled_codes(read_config())
    if not codes:
        return False
    if code == "next":
        index = (active_index(codes) + 1) % len(codes)
    elif code in codes:
        index = codes.index(code)
    else:
        return False
    subprocess.run(["swaymsg", "input", "type:keyboard", "xkb_switch_layout",
                    str(index)], capture_output=True, text=True, timeout=3)
    return True


def toggle(code):
    """Включить или выключить раскладку. Последнюю выключить не даём: иначе
    печатать будет некуда."""
    codes = enabled_codes(read_config())
    if code in codes:
        if len(codes) <= 1:
            return False
        codes = [c for c in codes if c != code]
    else:
        codes.append(code)
    write_enabled(codes)
    return True


def extra_layouts(known):
    """Раскладки, которых нет в evdev.lst, но которые лежат в /usr/share/X11/xkb
    (так живёт eu — EurKEY). Название берём из самого файла: строка
    name[Group1] = "EurKEY (US)". Файлы без такого имени (compose, pc, level3,
    capslock…) пропускаем — это не раскладки."""
    out = []
    try:
        for name in sorted(os.listdir(SYMBOLS)):
            if name.startswith(".") or name in known or name in SKIP:
                continue
            path = os.path.join(SYMBOLS, name)
            if not os.path.isfile(path):
                continue
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    found = NAME_RE.search(fh.read())
            except Exception:
                continue
            if found:
                out.append({"code": name, "name": found.group(1).strip()})
    except Exception:
        pass
    return out


def all_layouts():
    """Все раскладки xkb с человеческими названиями (из evdev.lst плюс то, что
    лежит в symbols отдельными файлами)."""
    common, rest = [], []
    try:
        with open(RULES, encoding="utf-8", errors="replace") as fh:
            inside = False
            for line in fh:
                if line.startswith("!"):
                    inside = line.startswith("! layout")
                    continue
                if not inside:
                    continue
                parts = line.split(None, 1)
                if len(parts) != 2:
                    continue
                item = {"code": parts[0], "name": parts[1].strip()}
                (common if item["code"] in COMMON else rest).append(item)
    except Exception:
        pass
    common.sort(key=lambda i: COMMON.index(i["code"]))
    rest.sort(key=lambda i: i["name"].lower())
    listed = {item["code"] for item in common + rest}
    extra = extra_layouts(listed)
    extra.sort(key=lambda i: i["name"].lower())
    return common + rest + extra


def name_of(code):
    for item in all_layouts():
        if item["code"] == code:
            return item["name"]
    return code


def write_state():
    text = read_config()
    codes = enabled_codes(text)
    index = active_index(codes)
    options = ""
    match = re.search(r'xkb_options[ \t]+"([^"]*)"', text)
    if match:
        options = match.group(1)
    available = all_layouts()
    names = {item["code"]: item["name"] for item in available}
    state = {
        "enabled": [{"code": c, "name": names.get(c, c)} for c in codes],
        "active": index if index < len(codes) else 0,
        "options": options,
        "available": available,
    }
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False)
    return state


def selftest():
    """Проверки без правки конфига."""
    problems = []
    text = read_config()
    codes = enabled_codes(text)
    if not codes:
        problems.append(tr("в конфиге нет строки xkb_layout"))
    if codes and any(c != c.strip() or " " in c for c in codes):
        problems.append(tr("в кодах раскладок остались пробелы: ") + repr(codes))
    known = {item["code"] for item in all_layouts()}
    if not known:
        problems.append(tr("не прочитался список раскладок xkb"))
    for code in codes:
        if code not in known:
            problems.append(tr("неизвестный код раскладки: ") + code)
    # переписывание строки не должно её портить
    if re.sub(r'"[^"]*"', '""', text) != re.sub(
            r'"[^"]*"', '""', LAYOUT_RE.sub(lambda m: m.group(1) + 'xkb_layout ""',
                                            text, count=1)):
        problems.append(tr("замена строки xkb_layout задевает что-то лишнее"))

    state = write_state()
    if len(state["enabled"]) != len(codes):
        problems.append(tr("сводка разошлась с конфигом"))

    if problems:
        for p in problems:
            print("  ✗", p)
        return 1
    print(tr("  ✓ раскладки в конфиге:"), ", ".join(codes))
    print(tr("  ✓ активная:"), state["enabled"][state["active"]]["name"] if state["enabled"] else "—")
    print(tr("  ✓ всего доступно в xkb:"), len(state["available"]))
    print(tr("  ✓ опции переключения:"), state["options"] or "—")
    return 0


def main(argv):
    if not argv or argv[0] == "build":
        write_state()
        return 0
    if argv[0] == "toggle" and len(argv) > 1:
        ok = toggle(argv[1])
        write_state()
        if not ok:
            print(tr("последнюю раскладку выключить нельзя"), file=sys.stderr)
            return 1
        return 0
    if argv[0] == "switch" and len(argv) > 1:
        ok = switch(argv[1])
        write_state()
        return 0 if ok else 1
    if argv[0] == "--selftest":
        return selftest()
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
