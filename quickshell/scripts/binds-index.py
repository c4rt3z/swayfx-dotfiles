#!/usr/bin/env python3
"""Горячие клавиши sway для меню настроек -> ~/.cache/quickshell/keys.json.

    binds-index.py                       — пересобрать список биндов
    binds-index.py edit <id> <сочетание> <команда>  — правка бинда (пусто = не менять)
    binds-index.py swap <id> <id>        — поменять сочетания двух биндов местами
    binds-index.py reset <id>            — вернуть сочетание и команду как было
    binds-index.py qt <id> <код> <моды> [dry]  — то же, но с нажатой клавиши
    binds-index.py --selftest

Разбираем ~/.config/sway/config: раскрываем переменные (set $mod Mod4 ...) для
показа, переводим имена клавиш на человеческий (Mod4 -> Super, Return -> Enter)
и раскладываем бинды по группам. Рядом с каждой строкой держим её исходный вид —
по нему и правим файл: меняем только сочетание или только команду, всё остальное
(отступ, -–to-code, комментарии) остаётся как есть. После правки зовём
«swaymsg reload» (как и раскладки), поэтому бар мигнёт.

Команда qt принимает код клавиши и модификаторы Qt — так настройки отдают
нажатие из окна «нажмите сочетание». Коды Qt здесь таблицей: свои символьные
имена в QML недоступны, а числа эти стабильны и в Qt5, и в Qt6.

Что не получилось, кладём в ~/.cache/quickshell/keys-result.json — настройки
показывают это человеку: «занято», «не понял клавишу», «устарело».
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import time

from i18n import tr

HOME = os.path.expanduser("~")
SWAY = f"{HOME}/.config/sway/config"
STATE = f"{HOME}/.cache/quickshell/keys.json"
RESULT = f"{HOME}/.cache/quickshell/keys-result.json"
DEFAULTS = f"{HOME}/.config/quickshell/keys-default.json"

KEY_NAMES = {
    "Mod4": "Super", "Mod1": "Alt", "Control": "Ctrl", "Return": "Enter",
    "Escape": "Esc", "BackSpace": "Backspace", "Next": "PgDn", "Prior": "PgUp",
    "comma": ",", "period": ".", "minus": "-", "equal": "=", "plus": "+",
    "slash": "/", "grave": "`", "apostrophe": "'", "semicolon": ";",
    "bracketleft": "[", "bracketright": "]", "backslash": "\\", "space": tr("Пробел"),
}
MEDIA_NAMES = {
    "XF86AudioRaiseVolume": tr("Громкость+"), "XF86AudioLowerVolume": tr("Громкость−"),
    "XF86AudioMute": tr("Тишина"), "XF86AudioPlay": tr("Плей/пауза"),
    "XF86AudioNext": tr("Следующий трек"), "XF86AudioPrev": tr("Прошлый трек"),
    "XF86MonBrightnessUp": tr("Яркость+"), "XF86MonBrightnessDown": tr("Яркость−"),
    "Print": tr("Снимок экрана"), "XF86AudioMicMute": tr("Микрофон"),
}

# как человек может написать модификатор -> как это зовёт sway
MOD_ALIASES = {
    "super": "Mod4", "mod4": "Mod4", "win": "Mod4", "meta": "Mod4", "logo": "Mod4",
    "alt": "Mod1", "mod1": "Mod1",
    "ctrl": "Control", "control": "Control",
    "shift": "Shift",
}
MOD_ORDER = ["Mod4", "Mod1", "Control", "Shift"]

# как человек может назвать клавишу -> имя клавиши у sway
KEY_ALIASES = {
    "enter": "Return", "return": "Return", "esc": "Escape", "escape": "Escape",
    "space": "space", "tab": "Tab", "backspace": "BackSpace", "delete": "Delete",
    "del": "Delete", "insert": "Insert", "ins": "Insert", "home": "Home", "end": "End",
    "pgup": "Prior", "pageup": "Prior", "prior": "Prior", "pgdn": "Next",
    "pagedown": "Next", "next": "Next",
    "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "print": "Print", "printscreen": "Print", "prtsc": "Print",
    "comma": "comma", "period": "period", "dot": "period", "minus": "minus",
    "equal": "equal", "plus": "plus", "slash": "slash", "grave": "grave",
    "apostrophe": "apostrophe", "semicolon": "semicolon",
    "bracketleft": "bracketleft", "bracketright": "bracketright",
    "backslash": "backslash", "pause": "Pause",
}

# коды клавиш Qt (Qt::Key_*) — те, что стоит ждать от «нажмите сочетание»
QT_KEYS = {
    0x01000000: "Escape", 0x01000001: "Tab", 0x01000003: "BackSpace",
    0x01000004: "Return", 0x01000005: "Return", 0x01000006: "Insert",
    0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print",
    0x01000010: "Home", 0x01000011: "End", 0x01000012: "Left",
    0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
    0x01000016: "Prior", 0x01000017: "Next",
    0x20: "space", 0x2c: "comma", 0x2e: "period", 0x2d: "minus", 0x3d: "equal",
    0x2f: "slash", 0x60: "grave", 0x27: "apostrophe", 0x3b: "semicolon",
    0x5b: "bracketleft", 0x5d: "bracketright", 0x5c: "backslash",
}
# сами модификаторы в качестве клавиши не берём — ждём «настоящую»
QT_MODIFIER_KEYS = {0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024}
QT_MODIFIERS = [("Mod4", 0x10000000), ("Mod1", 0x08000000),
                ("Control", 0x04000000), ("Shift", 0x02000000)]
# 0x01000030 — Qt::Key_F1, дальше по порядку до F12
QT_F1 = 0x01000030

# первый подходящий шаблон задаёт группу
GROUPS = [
    (r"quickshell|qs\s+ipc\s+call\s+lock", "Quickshell"),
    (r"swaylock", tr("Блокировка")),
    (r"brightnessctl", tr("Яркость")),
    (r"pactl|playerctl|wpctl|mediactl", tr("Звук и медиа")),
    (r"grim|slurp|swappy|screenshot", tr("Скриншоты")),
    (r"^exec\s+swaymsg\s+output|^exec\s+wdisplays", tr("Мониторы")),
    (r"^exec", tr("Запуск")),
    (r"^kill", tr("Окно")),
    (r"^focus", tr("Фокус")),
    (r"^move", tr("Перенос")),
    (r"^resize", tr("Размер")),
    (r"^layout|^split", tr("Раскладка")),
    (r"^workspace", tr("Рабочие столы")),
    (r"^output", tr("Мониторы")),
    (r"^input", tr("Ввод")),
    (r"^mode", tr("Режимы")),
    (r"^(reload|restart|exit)", "sway"),
]

OPTIONS = ("--to-code", "--no-repeat", "--release", "--locked", "--whole-window")

# знаки, которые человек может написать одной клавишей -> их имена у sway
PUNCT = {
    ",": "comma", ".": "period", "-": "minus", "=": "equal", "/": "slash",
    "`": "grave", "'": "apostrophe", ";": "semicolon", "[": "bracketleft",
    "]": "bracketright", "\\": "backslash",
}


def read_text(path=SWAY):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def read_vars(text):
    out = {}
    for m in re.finditer(r"^[ \t]*set[ \t]+(\$\w+)[ \t]+(.+?)[ \t]*$", text, re.M):
        out[m.group(1)] = m.group(2).strip()
    return out


def expand(text, variables):
    """Раскрывает $mod, $term и прочие переменные конфига (несколько проходов)."""
    for _ in range(6):
        new = re.sub(r"\$(\w+)", lambda m: variables.get("$" + m.group(1), m.group(0)), text)
        if new == text:
            break
        text = new
    return text


def pretty_keys(raw, variables):
    parts = []
    for key in expand(raw, variables).split("+"):
        name = MEDIA_NAMES.get(key, KEY_NAMES.get(key, key))
        parts.append(name.upper() if len(name) == 1 else name)
    return "+".join(parts)


def pretty_action(cmd):
    cmd = re.sub(r"\s+", " ", cmd).strip().replace(HOME, "~")
    if cmd.startswith("exec "):
        cmd = cmd[5:].strip()
    if cmd.startswith("qs ipc call lock lock"):
        cmd = tr("блокировка экрана")
    elif cmd.startswith("qs ipc call panel toggle "):
        cmd = tr("панель: ") + cmd[len("qs ipc call panel toggle "):]
    elif cmd.startswith("qs ipc call panel open "):
        cmd = tr("панель: ") + cmd[len("qs ipc call panel open "):]
    return cmd


def group_of(action):
    for pattern, name in GROUPS:
        if re.search(pattern, action):
            return name
    return tr("Прочее")


def defaults_key(order):
    """Ключ «как было» — порядковый номер бинда в конфиге.

    Ни сочетание, ни команда в ключ не входят: и то и другое человек правит, а
    снимок после правки должен по-прежнему находиться. Бинды в конфиге не
    добавляются и не удаляются (список только читают и правят на месте), так что
    номер — устойчивое имя строки.
    """
    return str(order)


def parse(text):
    """Все бинды конфига с их исходным видом."""
    variables = read_vars(text)
    items = []
    mode = ""
    for number, raw_line in enumerate(text.splitlines(), start=1):
        stripped = raw_line.strip()
        m = re.match(r"^mode\s+\"([^\"]*)\"\s*\{", stripped)
        if m:
            mode = m.group(1)
            continue
        if mode and stripped == "}":
            mode = ""
            continue
        if not stripped.startswith("bindsym"):
            continue
        indent = raw_line[:len(raw_line) - len(raw_line.lstrip())]
        body = stripped[len("bindsym"):].strip()
        options = []
        for opt in OPTIONS:
            while body.startswith(opt):
                options.append(opt)
                body = body[len(opt):].strip()
        if body.startswith("-"):  # флаги вроде --input-device, их не трогаем
            continue
        bits = body.split(None, 1)
        if len(bits) != 2:
            continue
        keys_raw = bits[0]
        cmd_raw = bits[1].rstrip()
        tail = raw_line[len(raw_line.rstrip()):]  # хвостовые пробелы строки
        if keys_raw.startswith("#"):
            continue
        action = pretty_action(expand(cmd_raw, variables))
        items.append({
            "id": f"b{number}",
            "line": number,
            "mode": mode,
            "indent": indent,
            "options": options,
            "keys_raw": keys_raw,
            "cmd_raw": cmd_raw,
            "tail": tail,
            "keys": pretty_keys(keys_raw, variables),
            "cmd": expand(cmd_raw, variables).replace(HOME, "~"),
            "action": action,
            "group": group_of(action),
            "default_key": defaults_key(len(items)),
        })
    return items


def load_defaults():
    try:
        with open(DEFAULTS, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_defaults(items):
    """Снимок «как было» делаем один раз: дальше он и есть точка возврата."""
    if os.path.exists(DEFAULTS):
        return
    data = {}
    for item in items:
        data.setdefault(item["default_key"], {"keys": item["keys_raw"],
                                              "cmd": item["cmd_raw"]})
    os.makedirs(os.path.dirname(DEFAULTS), exist_ok=True)
    with open(DEFAULTS, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)


def build():
    text = read_text()
    if not text:
        print(tr("не читается ~/.config/sway/config"), file=sys.stderr)
        return None
    items = parse(text)
    save_defaults(items)
    defaults = load_defaults()
    for item in items:
        was = defaults.get(item["default_key"])
        item["default_keys"] = pretty_keys(was["keys"], read_vars(text)) if was else item["keys"]
        item["default_keys_raw"] = was["keys"] if was else item["keys_raw"]
        item["changed"] = bool(was) and (was["keys"] != item["keys_raw"]
                                        or was["cmd"] != item["cmd_raw"])

    order = [name for _p, name in GROUPS] + [tr("Прочее")]
    items.sort(key=lambda i: (order.index(i["group"]) if i["group"] in order else 99,
                              i["keys"], i["line"]))
    state = {"items": items, "file": SWAY}
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False, indent=1)
    return items


def write_result(ok, **fields):
    data = {"ok": ok, "at": time.time()}
    data.update(fields)
    os.makedirs(os.path.dirname(RESULT), exist_ok=True)
    with open(RESULT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)


def normalize_combo(text):
    """«super+shift+e» -> («Mod4+Shift+e», "", "").

    Возвращает сочетание, беду и то, что её вызвало: незнакомую клавишу или
    пустоту. Сочетание без модификатора не берём — такую клавишу человек
    нажимает просто при печати.
    """
    text = (text or "").strip()
    if not text:
        return "", "empty", ""
    keys, mods = [], []
    for part in re.split(r"\s*\+\s*", text):
        if not part:
            continue
        low = part.lower()
        if low in MOD_ALIASES:
            mod = MOD_ALIASES[low]
            if mod not in mods:
                mods.append(mod)
            continue
        if low in KEY_ALIASES:
            keys.append(KEY_ALIASES[low])
            continue
        m = re.fullmatch(r"f([1-9]|1[0-2])", low)
        if m:
            keys.append("F" + m.group(1))
            continue
        if re.fullmatch(r"[a-z0-9]", low):
            keys.append(low)
            continue
        if re.fullmatch(r"xf86[a-z0-9]+", low):
            keys.append("XF86" + part[4:])
            continue
        if len(part) == 1 and part in PUNCT:  # «,» «.» «[» — знаем их имена
            keys.append(PUNCT[part])
            continue
        return "", "token", part
    if not keys or not mods:
        return "", "nomod", ""
    mods.sort(key=lambda m: MOD_ORDER.index(m) if m in MOD_ORDER else 9)
    return "+".join(mods + keys), "", ""


def combo_from_qt(key, mods):
    """Нажатие из QML -> сочетание в том виде, в каком его ждёт sway."""
    if key in QT_MODIFIER_KEYS or key == 0:
        return "", "nomod"
    if key in QT_KEYS:
        name = QT_KEYS[key]
    elif QT_F1 <= key <= QT_F1 + 11:
        name = "F" + str(key - QT_F1 + 1)
    elif 0x30 <= key <= 0x39:
        name = chr(key)
    elif 0x41 <= key <= 0x5a:
        name = chr(key).lower()
    else:
        return "", "key"
    mods_out = [name for name, flag in QT_MODIFIERS if mods & flag]
    if not mods_out:
        return "", "nomod"
    mods_out.sort(key=lambda m: MOD_ORDER.index(m) if m in MOD_ORDER else 9)
    return "+".join(mods_out + [name]), ""


def write_form(keys_raw, variables):
    """Сочетание в том виде, в каком его пишет сам конфиг: Mod4 -> $mod.

    Так правка не превращает одну строку в «Mod4+Return» рядом с соседними
    «$mod+...» — в файле остаётся один и тот же шаблон.
    """
    keys = expand(keys_raw, variables)
    shorthand = {}
    for name, value in variables.items():
        if value in MOD_ORDER:
            shorthand.setdefault(value, name)
    parts = []
    for part in keys.split("+"):
        parts.append(shorthand.get(part, part))
    return "+".join(parts)


def render(item, keys_raw=None, cmd_raw=None):
    keys = keys_raw if keys_raw is not None else item["keys_raw"]
    if cmd_raw is None:
        cmd, tail = item["cmd_raw"], item.get("tail", "")
    else:  # команду правят руками — лишние пробелы в конце уже не нужны
        cmd, tail = cmd_raw, ""
    head = f"{item['indent']}bindsym "
    if item["options"]:
        head += " ".join(item["options"]) + " "
    return f"{head}{keys} {cmd}{tail}"


def find(items, item_id):
    for item in items:
        if item["id"] == item_id:
            return item
    return None


def apply(items, changed, reload=False):
    """changed — {строка файла (1-based): новый текст}."""
    lines = read_text().splitlines()
    for number, new_line in changed.items():
        if number - 1 < 0 or number - 1 >= len(lines):
            return False
        lines[number - 1] = new_line
    with open(SWAY, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    if reload:
        subprocess.run(["swaymsg", "reload"], capture_output=True)
    build()
    return True


def apply_edit(item_id, combo, command, reload=True, dry=False):
    """Одна правка бинда: сочетание и/или команда.

    Пустая строка означает «не менять»: настройки присылают обе строки сразу, и
    трогаем мы только то, что человек действительно поменял. Пусто и там и там —
    это ошибка «нечего править». Режим dry только разбирает сочетание и отвечает
    им (так работает «нажмите сочетание»: подставляем нажатие в поле, а файл
    трогаем только после кнопки «сохранить»).
    """
    items = build() or []
    item = find(items, item_id)
    if not item:
        write_result(False, reason="stale", id=item_id)
        return 1
    combo, command = (combo or "").strip(), (command or "").strip()
    variables = read_vars(read_text())
    keys_raw, keys_pretty = item["keys_raw"], item["keys"]

    if combo:
        keys, problem, token = normalize_combo(combo)
        if problem:
            write_result(False, reason=problem, token=token, id=item_id)
            return 1
        whole = expand(keys, variables)
        # занято? тогда предлагаем поменять местами, а не затираем чужой бинд
        for other in items:
            if other["id"] != item_id and expand(other["keys_raw"], variables) == whole:
                write_result(False, reason="busy", id=item_id, busy_id=other["id"],
                             busy_keys=other["keys"], busy_cmd=other["cmd"])
                return 1
        keys_raw, keys_pretty = write_form(keys, variables), pretty_keys(keys, variables)

    cmd = re.sub(r"\s+", " ", command)
    if cmd.startswith("bindsym"):
        write_result(False, reason="command", id=item_id)
        return 1

    if dry:
        write_result(True, id=item_id, keys=keys_pretty, cmd=cmd or item["cmd"], dry=True)
        return 0
    if not combo and not cmd:
        write_result(False, reason="empty", id=item_id)
        return 1

    # команду передаём, только если она правда другая: иначе потеряются
    # пробелы в конце строки, к которым в конфиге никто не притрагивался
    new_cmd = cmd if (cmd and cmd != item["cmd_raw"]) else None
    if keys_raw == item["keys_raw"] and new_cmd is None:
        write_result(True, id=item_id, keys=keys_pretty, cmd=item["cmd"])
        return 0
    apply(items, {item["line"]: render(item, keys_raw=keys_raw, cmd_raw=new_cmd)},
          reload=reload)
    write_result(True, id=item_id, keys=keys_pretty, cmd=cmd or item["cmd"])
    return 0


def change_keys(item_id, combo, reload=True, raw=False):
    if raw:  # сочетание уже в том виде, в каком его пишет sway
        items = build() or []
        item = find(items, item_id)
        if not item:
            write_result(False, reason="stale", id=item_id)
            return 1
        apply(items, {item["line"]: render(item, keys_raw=combo)}, reload=reload)
        write_result(True, id=item_id, keys=combo)
        return 0
    return apply_edit(item_id, combo, "", reload=reload)


def change_command(item_id, command, reload=True):
    return apply_edit(item_id, "", command, reload=reload)


def qt_change(item_id, key, mods, dry=False):
    """Нажатие из окна настроек: Qt-код клавиши -> сочетание."""
    combo, problem = combo_from_qt(key, mods)
    if problem:
        write_result(False, reason=problem, id=item_id)
        return 1
    return apply_edit(item_id, combo, "", reload=not dry, dry=dry)


def swap(item_id, other_id, reload=True):
    items = build() or []
    item, other = find(items, item_id), find(items, other_id)
    if not item or not other:
        write_result(False, reason="stale", id=item_id)
        return 1
    variables = read_vars(read_text())
    apply(items, {item["line"]: render(item, keys_raw=write_form(other["keys_raw"], variables)),
                  other["line"]: render(other, keys_raw=write_form(item["keys_raw"], variables))},
          reload=reload)
    write_result(True, id=item_id, keys=other["keys_raw"], swapped=other_id)
    return 0


def reset(item_id, reload=True):
    items = build() or []
    item = find(items, item_id)
    if not item:
        write_result(False, reason="stale", id=item_id)
        return 1
    was = load_defaults().get(item["default_key"])
    if not was:
        write_result(False, reason="nodefault", id=item_id)
        return 1
    cmd = was["cmd"] if was["cmd"] != item["cmd_raw"] else None
    apply(items, {item["line"]: render(item, keys_raw=was["keys"], cmd_raw=cmd)},
          reload=reload)
    write_result(True, id=item_id, keys=was["keys"])
    return 0


def selftest():
    problems = []
    items = build()
    if not items:
        print("  ✗ список биндов пуст")
        return 1
    ids = [i["id"] for i in items]
    if len(ids) != len(set(ids)):
        problems.append("id биндов повторяются")
    for item in items:
        if not item["keys_raw"] or not item["cmd_raw"]:
            problems.append(f"у бинда {item['id']} пустое сочетание или команда")
        if item["cmd_raw"].startswith("bindsym"):
            problems.append(f"у бинда {item['id']} команда похожа на бинд")
    if not any(1 for i in items if i["mode"] and i["mode"] != ""):
        problems.append("не нашлось ни одного бинда внутри режима")

    # перебор сочетаний без записи в файл
    for text, want in [("super+shift+e", "Mod4+Shift+e"), ("Super+Return", "Mod4+Return"),
                       ("ctrl+alt+t", "Mod1+Control+t"), ("super+space", "Mod4+space"),
                       ("super+,", "Mod4+comma")]:
        got, problem, _token = normalize_combo(text)
        if got != want:
            problems.append(f"{text} -> {got} ({problem}), ждали {want}")
    for text in ("e", "super", "super+нечто"):
        got, problem, _token = normalize_combo(text)
        if got or not problem:
            problems.append(f"{text} приняли за сочетание: {got}")
    # нажатие из окна: Mod4+Shift+e
    got, problem = combo_from_qt(0x45, 0x10000000 | 0x02000000)
    if got != "Mod4+Shift+e":
        problems.append(f"нажатие Qt -> {got} ({problem})")
    got, problem = combo_from_qt(0x01000020, 0x02000000)  # только Shift держат
    if got or problem != "nomod":
        problems.append("модификатор приняли за клавишу")

    # правка туда-обратно не должна менять файл
    first, second = items[0], items[-1]
    with open(SWAY, encoding="utf-8") as fh:
        before = fh.read()
    change_keys(first["id"], "super+ctrl+alt+f9", reload=False)
    swap(first["id"], second["id"], reload=False)
    swap(first["id"], second["id"], reload=False)
    change_keys(first["id"], first["keys_raw"], reload=False, raw=True)
    with open(SWAY, encoding="utf-8") as fh:
        after = fh.read()
    if before != after:
        problems.append("правка сочетаний туда-обратно не вернула конфиг")
    if not load_defaults():
        problems.append("не записался снимок «как было»")

    if problems:
        for p in problems:
            print("  ✗", p)
        return 1
    groups = {}
    for item in items:
        groups.setdefault(item["group"], 0)
        groups[item["group"]] += 1
    print(f"  ✓ биндов: {len(items)} в {len(groups)} группах:",
          ", ".join(f"{g} {n}" for g, n in groups.items()))
    print("  ✓ пример:", items[0]["keys"], "->", items[0]["cmd"])
    return 0


def main(argv):
    if not argv or argv[0] == "build":
        return 0 if build() else 1
    if argv[0] == "edit" and len(argv) > 3:
        return apply_edit(argv[1], argv[2], argv[3])
    if argv[0] == "set" and len(argv) > 2:
        return change_keys(argv[1], argv[2])
    if argv[0] == "swap" and len(argv) > 2:
        return swap(argv[1], argv[2])
    if argv[0] == "cmd" and len(argv) > 2:
        return change_command(argv[1], " ".join(argv[2:]))
    if argv[0] == "reset" and len(argv) > 1:
        return reset(argv[1])
    if argv[0] == "qt" and len(argv) > 3:
        return qt_change(argv[1], int(argv[2]), int(argv[3]),
                         dry=len(argv) > 4 and argv[4] == "dry")
    if argv[0] == "--selftest":
        return selftest()
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
