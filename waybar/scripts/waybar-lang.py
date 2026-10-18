#!/usr/bin/env python3
"""Подписи в конфиге waybar — на языке интерфейса.

    waybar-lang.py apply   — привести ~/.config/waybar/config к текущему языку
    waybar-lang.py --selftest

Русский — исходный язык (как и в quickshell): в словарях
~/.config/quickshell/i18n/<код>.json ключ — русская строка, значение — перевод.

Замена обратима. Сначала все известные переводы возвращаются к русским строкам,
потом подставляется нужный язык, поэтому повторный запуск ничего не портит, а
переключение туда-обратно работает в обе стороны и не зависит от того, на каком
языке конфиг сейчас.

Иконки в конфиге приклеены к словам («󰖪  Disconnected»), поэтому заменяем по
вхождению слова, а не по целому значению. Короткие строки и ключи с фигурными
скобками (форматы вида «{volume}%») пропускаем — их переводить нечего.
"""

import json
import re
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG = f"{HOME}/.config/waybar/config"
LANG_FILE = f"{HOME}/.config/quickshell/language"
DICT_DIR = f"{HOME}/.config/quickshell/i18n"
MIN_LEN = 4


def language():
    try:
        with open(LANG_FILE, encoding="utf-8") as fh:
            first = fh.read().strip().splitlines()[0].strip()
        return first or "ru"
    except Exception:
        return "ru"


def load_dicts():
    """{код языка: {русская строка: перевод}} — все словари сразу: по ним
    переводы возвращаются к русскому."""
    out = {}
    try:
        names = sorted(os.listdir(DICT_DIR))
    except Exception:
        return out
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(f"{DICT_DIR}/{name}", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception:
            continue
        if isinstance(data, dict):
            out[name[:-5]] = data
    return out


def usable(key, value):
    return (isinstance(value, str) and value and len(key) >= MIN_LEN
            and "{" not in key and "}" not in key and "{" not in value)


# Подписи в конфиге — это значения ключей format-* (например
# "format-disconnected": "  нет сети"). Ищем ровно их, чтобы не задеть ни ключи,
# ни списки модулей: в них тоже строки, и слово «light» внутри «backlight»
# когда-то превращало модуль в «backсветлая».
LABEL_RE = re.compile(r'("format-(?!icons)[a-z-]+"\s*:\s*")((?:[^"\\]|\\.)*)(")', re.M)


def replace_in_labels(text, pairs):
    def sub(match):
        value = match.group(2)
        for needle, replacement in pairs:
            if needle in value:
                value = value.replace(needle, replacement)
        return match.group(1) + value + match.group(3)

    return LABEL_RE.sub(sub, text)


def translate(text, dicts, code):
    """Сначала к русскому, потом к нужному языку. Возвращает новую строку."""
    # Длинные строки раньше коротких: «Disconnected» должно сработать до
    # «connected», иначе от него останется огрызок «Dis».
    back = [(value, key) for data in dicts.values() for key, value in data.items()
            if usable(key, value)]
    back.sort(key=lambda pair: -len(pair[0]))
    text = replace_in_labels(text, back)

    if code != "ru":
        # нет строки в словаре языка — берём английскую (как и в Lang.qml)
        pairs = dict(dicts.get(code) or {})
        if code != "en":
            for key, value in (dicts.get("en") or {}).items():
                pairs.setdefault(key, value)
        forward = [(key, value) for key, value in pairs.items()
                   if usable(key, value)]
        forward.sort(key=lambda pair: -len(pair[0]))
        text = replace_in_labels(text, forward)
    return text


def apply():
    code = language()
    dicts = load_dicts()
    try:
        with open(CONFIG, encoding="utf-8") as fh:
            text = fh.read()
    except Exception as exc:
        print(f"waybar-lang: не прочитал {CONFIG}: {exc}", file=sys.stderr)
        return 1

    new = translate(text, dicts, code)
    if new == text:
        return 0
    with open(CONFIG, "w", encoding="utf-8") as fh:
        fh.write(new)
    # конфиг waybar перечитывает по SIGUSR2
    subprocess.run(["pkill", "-SIGUSR2", "-x", "waybar"], capture_output=True)
    return 0


def selftest():
    problems = []
    dicts = load_dicts()
    if "en" not in dicts:
        problems.append("нет словаря i18n/en.json")

    sample = '  "network": {\n    "format-disconnected": "\U000f05aa  нет сети"\n  },\n'
    english = translate(sample, dicts, "en")
    if "Disconnected" not in english:
        problems.append(f"нет сети → Disconnected не сработало: {english!r}")
    back = translate(english, dicts, "ru")
    if back != sample:
        problems.append(f"обратный перевод не совпал:\n    было {sample!r}\n    стало {back!r}")

    # идемпотентность
    again = translate(english, dicts, "en")
    if again != english:
        problems.append("повторный перевод меняет строку")

    # формат-строки не трогаем
    fmt = '    "format": "{icon} {volume}%"\n'
    if translate(fmt, dicts, "en") != fmt:
        problems.append("тронул формат со скобками")

    if problems:
        for p in problems:
            print("  ✗", p)
        return 1
    print("  ✓ словарей:", ", ".join(sorted(dicts)))
    print("  ✓ нет сети →", english.split("  ")[-1].strip().rstrip('"'))
    print("  ✓ обратный перевод и повтор — без изменений")
    print("  ✓ формат-строки со скобками не тронуты")
    return 0


def main(argv):
    if not argv or argv[0] == "apply":
        return apply()
    if argv[0] == "--selftest":
        return selftest()
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
