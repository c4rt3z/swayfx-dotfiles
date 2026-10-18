"""Перевод строк в скриптах — тем же словарём, что и панели.

Строки в скриптах написаны по-русски (русский — исходный язык интерфейса),
переводы лежат в ~/.config/quickshell/i18n/<код>.json, где ключ — русская
строка. Текущий язык — в ~/.config/quickshell/language. Если перевода нет,
берём английский (i18n/en.json), и только потом оставляем строку как есть, —
поэтому словарь можно пополнять постепенно.

Скрипты бывают и долгоживущими (центр waybar), поэтому язык перечитываем, если
файл языка изменился: смена языка подхватывается без перезапуска бара.

    from i18n import tr
    print(tr("Ничего не играет"))
"""
import json
import os

HOME = os.path.expanduser("~")
LANG_FILE = f"{HOME}/.config/quickshell/language"
DICT_DIR = f"{HOME}/.config/quickshell/i18n"


def language():
    try:
        with open(LANG_FILE, encoding="utf-8") as fh:
            first = fh.read().strip().splitlines()[0].strip()
        return first or "ru"
    except Exception:
        return "ru"


def _load(code):
    if code == "ru":
        return {}
    try:
        with open(f"{DICT_DIR}/{code}.json", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _stamp():
    try:
        return os.stat(LANG_FILE).st_mtime_ns
    except Exception:
        return 0


CODE = language()
ENGLISH = _load("en")
DICT = _load(CODE)
_STAMP = _stamp()


def _refresh():
    """Перечитать язык, если файл языка поменялся (скрипт может работать долго)."""
    global CODE, DICT, _STAMP
    stamp = _stamp()
    if stamp == _STAMP:
        return
    _STAMP = stamp
    CODE = language()
    DICT = _load(CODE)


def tr(text):
    """Перевод строки. Нет перевода — вернётся то же самое."""
    if not text:
        return text
    _refresh()
    if CODE == "ru":
        return text
    value = DICT.get(text)
    if value is None or value == "":
        value = ENGLISH.get(text)
    return text if value is None or value == "" else value
