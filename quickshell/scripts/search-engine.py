#!/usr/bin/env python3
"""Мега-поиск для панели Super+Space: приложения, окна, файлы, калькулятор, интернет.

    search-engine.py tr("<запрос>")     — посчитать строки (JSON в stdout и в
                                      ~/.cache/quickshell/search-out.json)
    search-engine.py --use "<exec>" — запомнить выбранное (поднимает в следующий раз)
    search-engine.py --selftest     — прогнать примеры

Комфорт складывается из трёх вещей:

  • раскладка. Запрос и названия прогоняются через обе раскладки, поэтому
    «еудупкфь» находит Telegram — можно набрать не глядя на переключатель;
  • опечатки. Кроме точных совпадений работает нечёткий поиск по
    подпоследовательности и Левенштейн до двух правок: trlegram -> Telegram;
  • калькулятор. Если в строке арифметика (2+2*3, sqrt(16), 340*15%),
    ответ идёт первой строкой и копируется по Enter.
"""
import ast
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from i18n import tr, language

HOME = os.path.expanduser("~")
CACHE = f"{HOME}/.cache/quickshell"
OUT = f"{CACHE}/search-out.json"
APPS = f"{CACHE}/apps.json"
FILES = f"{CACHE}/files.txt"
WINDOWS = f"{CACHE}/windows.json"
HISTORY = f"{CACHE}/search-history.txt"
EMOJI = f"{CACHE}/emoji.json"

# ── раскладка ───────────────────────────────────────────────────────────────

ROWS = [
    ("qwertyuiop[]", tr("йцукенгшщзхъ")),
    ("asdfghjkl;'", tr("фывапролджэ")),
    ("zxcvbnm,./", tr("ячсмитьбю.")),
]
TO_RU, TO_EN = {}, {}
for _en, _ru in ROWS:
    for _lat, _cyr in zip(_en, _ru):
        TO_RU[_lat], TO_RU[_lat.upper()] = _cyr, _cyr.upper()
        TO_EN[_cyr], TO_EN[_cyr.upper()] = _lat, _lat.upper()


def norm(text):
    return re.sub(r"\s+", " ", (text or "").lower().replace(tr("ё"), tr("е"))).strip()


def to_ru(text):
    return "".join(TO_RU.get(c, c) for c in text)


def to_en(text):
    return "".join(TO_EN.get(c, c) for c in text)


def variants(token):
    """Все написания токена: как набрано и в обеих раскладках."""
    return [v for v in {token, to_en(token), to_ru(token)} if v]

# ── сравнение ───────────────────────────────────────────────────────────────


def lev(a, b, limit):
    """Левенштейн с ранним выходом: больше limit правок — не считаем."""
    if abs(len(a) - len(b)) > limit:
        return limit + 1
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        row_min = i
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
            row_min = min(row_min, cur[j])
        if row_min > limit:
            return limit + 1
        prev = cur
    return prev[-1]


def subseq(token, text):
    """Нечёткое совпадение по подпоследовательности, штраф за пропуски.

    Слишком размазанное совпадение не считаем: иначе chromium находится в
    случайном списке песен, просто потому что буквы нашлись вразброс.
    """
    pos, gap = -1, 0
    for ch in token:
        nxt = text.find(ch, pos + 1)
        if nxt < 0:
            return 0
        gap += nxt - pos - 1
        pos = nxt
    if gap > len(token) * 2 or pos > len(token) * 4:
        return 0
    return max(1, 600 - gap * 6 - pos)


def score(token, text, deep=True):
    """Насколько text подходит под токен. 0 — не подходит."""
    if not token or not text:
        return 0
    if text.startswith(token):
        return 1200 - len(text)
    for i, word in enumerate(text.split()):
        if word.startswith(token):
            return 1000 - i * 5 - len(text) // 4
    found = text.find(token)
    if found >= 0:
        return 800 - found
    fuzzy = subseq(token, text)
    if fuzzy:
        return fuzzy
    if not deep or len(token) < 3:
        return 0
    limit = 2 if len(token) >= 5 else 1
    for word in text.split():
        if len(word) >= 3 and abs(len(word) - len(token)) <= limit + 1:
            d = lev(token, word, limit)
            if d <= limit:
                return 500 - d * 150
    return 0


def score_query(tokens, text, text_alt, deep=True):
    """Сумма по токенам: не подошёл хотя бы один — строка не наша."""
    if not tokens or not text:
        return 0
    total = 0
    for token in tokens:
        best = 0
        for form in variants(token):
            best = max(best, score(form, text, deep), score(form, text_alt, deep))
        if best <= 0:
            return 0
        total += best
    return total

# ── калькулятор ─────────────────────────────────────────────────────────────

MATH = {
    "sqrt": math.sqrt, "log": math.log10, "lg": math.log10, "ln": math.log,
    "sin": math.sin, "cos": math.cos, "tan": math.tan, "abs": abs,
    "round": round, "floor": math.floor, "ceil": math.ceil, "exp": math.exp,
    "fact": math.factorial, "min": min, "max": max,
    "pi": math.pi, "e": math.e,
}
CALC_RE = re.compile(r"^[\s0-9a-zA-Z_+\-*/^%().,]+$")


def fmt(value):
    if isinstance(value, float):
        if value.is_integer() and abs(value) < 1e15:
            return str(int(value))
        return f"{value:.8g}"
    return str(value)


def _eval(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.Name) and node.id in MATH:
        return MATH[node.id]
    if isinstance(node, ast.UnaryOp):
        val = _eval(node.operand)
        return -val if isinstance(node.op, ast.USub) else val
    if isinstance(node, ast.BinOp):
        a, b = _eval(node.left), _eval(node.right)
        if isinstance(node.op, ast.Add):
            return a + b
        if isinstance(node.op, ast.Sub):
            return a - b
        if isinstance(node.op, ast.Mult):
            return a * b
        if isinstance(node.op, ast.Div):
            return a / b
        if isinstance(node.op, ast.FloorDiv):
            return a // b
        if isinstance(node.op, ast.Mod):
            return a % b
        if isinstance(node.op, ast.Pow):
            return a ** b
        raise ValueError
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
        args = [_eval(a) for a in node.args]
        if node.func.id not in MATH:
            raise ValueError
        return MATH[node.func.id](*args)
    raise ValueError


def calc_row(raw):
    """Арифметика в строке поиска -> строка с ответом."""
    expr = raw.strip()
    if not CALC_RE.match(expr):
        return None
    if not re.search(r"\d", expr):
        return None
    if not re.search(r"[+\-*/^%]|\b(sqrt|log|lg|ln|sin|cos|tan|abs|round|floor|ceil|exp|fact|min|max)\b", expr):
        return None
    expr = expr.lstrip("=").strip().replace(",", ".")
    expr = re.sub(r"(\d+(?:\.\d+)?)\s*%", r"(\1/100)", expr)  # 340*15%
    try:
        tree = ast.parse(expr.replace("^", "**"), mode="eval")
        value = _eval(tree.body)
    except Exception:
        return None
    if isinstance(value, complex) or value != value:
        return None
    return {
        "kind": "calc", "title": fmt(value), "hint": tr("считать: ") + raw.strip(),
        "action": "", "copy": fmt(value), "id": "calc",
    }

# ── перевод, единицы, валюты ────────────────────────────────────────────────
#
# Всё это — та же строка поиска, без интернета для единиц и с интернетом для
# перевода и валют. Ответы кэшируем: набор «привет» не должен каждый раз ходить
# в сеть, а курсы валют живут шесть часов.

TR_CACHE = f"{CACHE}/translate.json"
RATES_CACHE = f"{CACHE}/rates.json"

# валюта: как её пишут -> код, и код -> значок для ответа
CUR = {
    "$": "USD", "usd": "USD", "доллар": "USD", "доллары": "USD", "долларов": "USD",
    "€": "EUR", "eur": "EUR", "евро": "EUR",
    "₽": "RUB", "rub": "RUB", "руб": "RUB", "рубль": "RUB", "рубля": "RUB", "рублей": "RUB",
    "₴": "UAH", "uah": "UAH", "гривна": "UAH", "гривны": "UAH", "гривен": "UAH",
    "byn": "BYN", "zł": "PLN", "pln": "PLN", "злотый": "PLN", "злотых": "PLN",
    "£": "GBP", "gbp": "GBP", "фунт": "GBP", "фунтов": "GBP",
    "¥": "CNY", "cny": "CNY", "юань": "CNY", "юаней": "CNY",
    "jpy": "JPY", "иена": "JPY", "йена": "JPY", "kzt": "KZT", "тенге": "KZT",
    "try": "TRY", "лира": "TRY", "chf": "CHF", "cad": "CAD", "aud": "AUD",
    "btc": "BTC", "eth": "ETH", "usdt": "USDT",
}
CUR_SIGN = {"USD": "$", "EUR": "€", "RUB": "₽", "UAH": "₴", "GBP": "£", "CNY": "¥",
            "JPY": "¥", "PLN": "zł", "KZT": "₸", "TRY": "₺"}

# единицы: имя -> (величина, множитель к основной единице величины)
LEN = {"mm": 0.001, "мм": 0.001, "cm": 0.01, "см": 0.01, "m": 1, "м": 1, "метр": 1,
       "метра": 1, "метров": 1, "km": 1000, "км": 1000, "километр": 1000,
       "in": 0.0254, "inch": 0.0254, "дюйм": 0.0254, "дюйма": 0.0254, "дюймов": 0.0254,
       "дюйме": 0.0254, "дюймах": 0.0254,
       "ft": 0.3048, "foot": 0.3048, "feet": 0.3048, "фут": 0.3048, "фута": 0.3048,
       "футов": 0.3048, "футах": 0.3048, "yd": 0.9144, "ярд": 0.9144, "ярдов": 0.9144,
       "ярдах": 0.9144, "mi": 1609.344, "mile": 1609.344, "miles": 1609.344,
       "миля": 1609.344, "мили": 1609.344, "миль": 1609.344, "миле": 1609.344,
       "милях": 1609.344, "метрах": 1, "сантиметрах": 0.01, "километрах": 1000,
       "километров": 1000, "сантиметр": 0.01, "сантиметра": 0.01, "сантиметров": 0.01}
MASS = {"g": 1, "г": 1, "грамм": 1, "грамма": 1, "граммов": 1, "kg": 1000, "кг": 1000,
        "килограмм": 1000, "килограмма": 1000, "килограммов": 1000, "t": 1000000,
        "т": 1000000, "тонна": 1000000, "тонны": 1000000, "тонн": 1000000,
        "oz": 28.349523125, "унция": 28.349523125, "унций": 28.349523125,
        "унциях": 28.349523125, "граммах": 1, "килограммах": 1000, "тоннах": 1000000,
        "lb": 453.59237, "lbs": 453.59237, "фунт": 453.59237, "фунта": 453.59237,
        "фунтов": 453.59237, "фунтах": 453.59237}
VOL = {"ml": 0.001, "мл": 0.001, "l": 1, "л": 1, "литр": 1, "литра": 1, "литров": 1,
       "gal": 3.785411784, "галлон": 3.785411784, "галлона": 3.785411784,
       "pint": 0.473176473, "пинта": 0.473176473, "литрах": 1, "миллилитрах": 0.001,
       "галлонах": 3.785411784}
SPEED = {"kmh": 1, "кмч": 1, "км/ч": 1, "kph": 1, "mph": 1.609344, "миль/ч": 1.609344}
DATA = {"b": 1 / 8000000, "kb": 0.001, "кб": 0.001, "mb": 1, "мб": 1, "gb": 1000,
        "гб": 1000, "tb": 1000000, "тб": 1000000}
AREA = {"m2": 1, "м2": 1, "м²": 1, "km2": 1000000, "км2": 1000000, "км²": 1000000,
        "ha": 10000, "га": 10000, "acre": 4046.8564224, "акр": 4046.8564224}
TIME = {"s": 1, "сек": 1, "секунда": 1, "секунд": 1, "min": 60, "мин": 60, "минута": 60,
        "минут": 60, "минутах": 60, "h": 3600, "ч": 3600, "час": 3600, "часа": 3600,
        "часов": 3600, "часах": 3600, "секундах": 1,
        "day": 86400, "сутки": 86400, "день": 86400, "дней": 86400, "днях": 86400}
TEMP = {"c": "c", "°c": "c", "цельсий": "c", "celsius": "c", "градус": "c", "градусов": "c",
        "f": "f", "°f": "f", "фаренгейт": "f", "fahrenheit": "f",
        "k": "k", "кельвин": "k", "kelvin": "k"}

TEMP_SIGN = {"c": "°C", "f": "°F", "k": "K"}

UNITS = {}
for name, factor in LEN.items():
    UNITS[name] = ("длина", factor)
for name, factor in MASS.items():
    UNITS[name] = ("масса", factor)
for name, factor in VOL.items():
    UNITS[name] = ("объём", factor)
for name, factor in SPEED.items():
    UNITS[name] = ("скорость", factor)
for name, factor in DATA.items():
    UNITS[name] = ("данные", factor)
for name, factor in AREA.items():
    UNITS[name] = ("площадь", factor)
for name, factor in TIME.items():
    UNITS[name] = ("время", factor)
for name, kind in TEMP.items():
    UNITS[name] = ("температура", kind)

CONV_RE = re.compile(r"^\s*(-?\d+(?:[.,]\d+)?)\s*([^\s0-9]+)\s*(?:в|to|in|=>|->|→)\s*([^\s0-9]+)\s*$",
                     re.IGNORECASE)


def read_cache(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def write_cache(path, data):
    try:
        os.makedirs(CACHE, exist_ok=True)
        tmp = f"{path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        pass


def fmt_num(value):
    """Число по-русски: пробел между тысячами, запятая в дробной части."""
    if abs(value - round(value)) < 1e-9 and abs(value) < 1e15:
        text = f"{int(round(value)):,}".replace(",", " ")
        return text
    if abs(value) >= 1000:
        text = f"{value:,.2f}".replace(",", " ").replace(".", ",")
    else:
        text = f"{value:.4g}".replace(".", ",")
    return text


def _get_json(url, timeout):
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _translate_mymemory(text, target):
    """MyMemory: без ключа, лимит на день, но работает почти везде."""
    source = "ru" if re.search(r"[а-яёіїєґ]", text, re.IGNORECASE) else "en"
    if source == target:
        return ""
    try:
        data = _get_json("https://api.mymemory.translated.net/get?" + urllib.parse.urlencode({
            "q": text, "langpair": source + "|" + target}), 6)
        out = ((data.get("responseData") or {}).get("translatedText") or "").strip()
    except Exception:
        return ""
    # сервис отвечает подсказками про лимит прямо в поле перевода
    if not out or "MYMEMORY WARNING" in out.upper():
        return ""
    return out


def _translate_google(text, target):
    """Открытый эндпоинт Google; на некоторых адресах отдаёт 429."""
    try:
        query = urllib.parse.urlencode({"client": "gtx", "sl": "auto", "tl": target,
                                        "dt": "t", "q": text})
        data = _get_json("https://translate.googleapis.com/translate_a/single?" + query, 4)
        return "".join(part[0] for part in (data[0] or []) if part and part[0])
    except Exception:
        return ""


def translate(text, target):
    """Перевод с кэшем в ~/.cache/quickshell: сначала MyMemory, потом Google."""
    cache = read_cache(TR_CACHE)
    key = target + "|" + text
    if key in cache:
        return str(cache[key])
    out = _translate_mymemory(text, target) or _translate_google(text, target)
    if out:
        cache[key] = out
        if len(cache) > 800:
            cache = dict(list(cache.items())[-400:])
        write_cache(TR_CACHE, cache)
    return out


def translate_row(raw):
    """«*текст» — перевод: русский -> английский, всё прочее -> язык интерфейса."""
    text = (raw or "").strip()
    if not text.startswith("*"):
        return None
    src = text[1:].strip()
    if len(src) < 2:
        return None
    target = "en" if re.search(r"[а-яёіїєґ]", src, re.IGNORECASE) else language()
    if target not in ("ru", "en", "uk", "de"):
        target = "ru"
    out = translate(src, target)
    if not out:
        return None
    return {
        "kind": "translate", "title": out,
        "hint": tr("перевод") + " · " + target.upper(),
        "action": "", "copy": out, "id": "translate:" + out,
    }


def rates():
    """Курсы к USD: open.er-api.com, без ключа; обновляем раз в 6 часов."""
    cache = read_cache(RATES_CACHE)
    if cache.get("rates") and time.time() - float(cache.get("fetched") or 0) < 6 * 3600:
        return cache["rates"]
    try:
        with urllib.request.urlopen("https://open.er-api.com/v6/latest/USD",
                                    timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        table = data.get("rates") or {}
        if table:
            write_cache(RATES_CACHE, {"fetched": time.time(), "rates": table})
            return table
    except Exception:
        pass
    return cache.get("rates") or {}


def _temp_to_celsius(value, kind):
    if kind == "c":
        return value
    if kind == "f":
        return (value - 32) * 5 / 9
    return value - 273.15


def _celsius_to(value, kind):
    if kind == "c":
        return value
    if kind == "f":
        return value * 9 / 5 + 32
    return value + 273.15


def convert_row(raw):
    """"100 usd в rub", "10 км в милях", "70 f to c" -> строка с ответом."""
    m = CONV_RE.match(raw or "")
    if not m:
        return None
    value = float(m.group(1).replace(",", "."))
    src, dst = m.group(2).strip().lower(), m.group(3).strip().lower()

    cur_a, cur_b = CUR.get(src.lstrip(".")), CUR.get(dst.lstrip("."))
    if cur_a and cur_b and cur_a != cur_b:
        table = rates()
        ra, rb = table.get(cur_a), table.get(cur_b)
        if not ra or not rb:
            return None
        result = value / float(ra) * float(rb)
        sign = CUR_SIGN.get(cur_b, "")
        shown = (fmt_num(result) + " " + (sign or cur_b)).strip()
        return {
            "kind": "calc", "title": shown,
            "hint": tr("валюта: ") + f"{fmt_num(value)} {cur_a} → {cur_b}",
            "action": "", "copy": f"{fmt_num(result)} {cur_b}", "id": "conv:" + shown,
        }

    unit_a, unit_b = UNITS.get(src), UNITS.get(dst)
    if not unit_a or not unit_b or unit_a[0] != unit_b[0]:
        return None
    if unit_a[0] == "температура":
        result = _celsius_to(_temp_to_celsius(value, unit_a[1]), unit_b[1])
        shown = fmt_num(result) + " " + TEMP_SIGN.get(unit_b[1], "")
    else:
        result = value * unit_a[1] / unit_b[1]
        shown = fmt_num(result) + " " + dst
    return {
        "kind": "calc", "title": shown,
        "hint": tr("перевести: ") + f"{fmt_num(value)} {src} → {dst}",
        "action": "", "copy": shown, "id": "conv:" + shown,
    }


# ── источники ───────────────────────────────────────────────────────────────


def make(kind, title, hint, action, ident, text, boost, copy=""):
    return {
        "kind": kind, "title": title, "hint": hint, "action": action, "id": ident,
        "copy": copy, "text": text, "text_alt": to_en(text), "boost": boost,
    }


def app_items():
    try:
        with open(APPS, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return []
    out = []
    for a in data.get("items", []):
        text = norm(" ".join([a.get("name", ""), a.get("comment", ""),
                              a.get("id", ""), a.get("search", "")]))
        out.append(make("app", a.get("name", ""), a.get("comment", ""),
                        a.get("exec", ""), a.get("exec", ""), text, 60))
        # действия из .desktop: «GIMP — открыть как…», «Steam — Big Picture»
        for act in a.get("actions") or []:
            act_text = norm(" ".join([a.get("name", ""), act.get("name", ""),
                                      act.get("id", "")]))
            out.append(make("appaction", act.get("name", ""), a.get("name", ""),
                            act.get("exec", ""),
                            "act:" + a.get("id", "") + ":" + act.get("id", ""),
                            act_text, 20))
    return out


# Свои действия: панели quickshell и то, что обычно нужно с клавиатуры
ACTIONS = [
    (tr("Настройки"), tr("меню настроек дотфайлов"), "qs ipc call panel open settings",
     tr("настройки settings конфиг дотфайлы")),
    (tr("Эмодзи"), tr("выбор эмодзи"), "qs ipc call panel open emoji", tr("эмодзи смайлы emoji")),
    (tr("Обои и темы"), tr("обои и Material You"), "qs ipc call panel open wallpaper",
     tr("обои темы wallpaper material you")),
    (tr("Плеер"), tr("текущий трек"), "qs ipc call panel open music", tr("музыка плеер трек music")),
    (tr("Громкость"), tr("громкость и микрофон"), "qs ipc call panel open volume",
     tr("громкость звук volume звука")),
    (tr("Яркость"), tr("яркость экрана"), "qs ipc call panel open brightness",
     tr("яркость экран backlight")),
    (tr("Сеть"), tr("сеть и wi-fi"), "qs ipc call panel open network", tr("сеть wifi wi-fi network")),
    (tr("Снимок экрана"), tr("весь экран в ~/Pictures"), "sh -c 'grim ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png'",
     tr("скриншот снимок screenshot")),
    (tr("Снимок области"), tr("выделить область"), "sh -c 'grim -g \"$(slurp)\" ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png'",
     tr("скриншот область screenshot")),
    (tr("Заблокировать"), tr("экран блокировки"), "qs ipc call lock lock", tr("блокировка lock экран")),
    (tr("Сессия"), tr("выход, перезагрузка, выключение"), "qs ipc call panel open power",
     tr("выключить перезагрузка выход питание session")),
]


def action_items():
    out = []
    for i, (title, hint, action, keys) in enumerate(ACTIONS):
        out.append(make("action", title, hint, action, "action:" + str(i),
                        norm(title + " " + keys), 50))
    return out


def window_items():
    """Окна sway. Список обновляем не чаще раза в 30 с, иначе он дорогой."""
    fresh = os.path.exists(WINDOWS) and time.time() - os.path.getmtime(WINDOWS) < 30
    if not fresh:
        try:
            raw = subprocess.run(["swaymsg", "-t", "get_tree"], capture_output=True,
                                 text=True, timeout=2).stdout
            tree = json.loads(raw)
            found = []
            _walk(tree, found)
            os.makedirs(CACHE, exist_ok=True)
            with open(WINDOWS, "w", encoding="utf-8") as fh:
                json.dump(found, fh, ensure_ascii=False)
        except Exception:
            pass
    try:
        with open(WINDOWS, encoding="utf-8") as fh:
            wins = json.load(fh)
    except Exception:
        return []
    out = []
    for w in wins:
        app = w.get("app", "")
        out.append(make("win", w.get("name", ""), (tr("окно · ") + app).strip(" ·"),
                        f"swaymsg [con_id={w.get('id')}] focus", "win:" + str(w.get("id")),
                        norm(w.get("name", "") + " " + app), 40))
    return out


def _walk(node, out):
    for side in ("nodes", "floating_nodes"):
        for child in node.get(side) or []:
            _walk(child, out)
    name = node.get("name")
    app = node.get("app_id") or (node.get("window_properties") or {}).get("class") or ""
    if name and (node.get("app_id") or node.get("window_properties")):
        out.append({"id": node.get("id"), "name": name, "app": app})


def file_items():
    if not os.path.exists(FILES):
        return []
    out = []
    with open(FILES, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            path = line.strip()
            if not path:
                continue
            rel = path[len(HOME) + 1:] if path.startswith(HOME + "/") else path
            folder = os.path.dirname(rel) or "~"
            out.append(make("file", os.path.basename(path), tr("файл · ") + folder,
                            'xdg-open "' + path + '"', "file:" + rel,
                            norm(os.path.basename(path) + " " + rel), 20))
    return out


def emoji_items(query):
    try:
        with open(EMOJI, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return []
    needle = norm(query.lstrip(":"))
    out = []
    for e in data.get("items", []):
        if needle and needle not in e.get("search", ""):
            continue
        out.append(make("emoji", e["e"], e.get("name", ""), "", "emoji:" + e["e"],
                        norm(e.get("search", "")), 0, copy=e["e"]))
        if len(out) >= 40:
            break
    return out


def web_items(raw):
    q = raw.strip()
    if len(q) < 2:
        return []
    from urllib.parse import quote_plus
    enc = quote_plus(q)
    # википедия — на языке интерфейса
    wiki = {"en": "en", "uk": "uk", "de": "de"}.get(language(), "ru")
    out = []
    if re.match(r"^[\w.-]+\.[a-z]{2,}(/\S*)?$", q, re.I):
        out.append(make("web", tr("Открыть") + " " + q, tr("ссылка"),
                        f"xdg-open 'https://{q}'", "web:url", "", -50))
    out.append(make("web", tr("Найти в интернете") + ": " + q, "DuckDuckGo",
                    f"xdg-open 'https://duckduckgo.com/?q={enc}'", "web:ddg", "", -50))
    out.append(make("web", q + " — " + tr("Википедия"), tr("Википедия"),
                    f"xdg-open 'https://{wiki}.wikipedia.org/w/index.php?search={enc}'",
                    "web:wiki", "", -50))
    return out


def history_boost(item):
    try:
        with open(HISTORY, encoding="utf-8") as fh:
            lines = fh.read().splitlines()[-400:]
    except Exception:
        return 0
    seen = lines.count(item["id"])
    return 400 if seen == 1 else (700 if seen > 1 else 0)

# ── сборка ответа ───────────────────────────────────────────────────────────


def build(raw):
    query = norm(raw)
    rows = []
    calc = calc_row(raw)
    if calc:
        rows.append(calc)
    conv = convert_row(raw)
    if conv:
        rows.append(conv)
    trans = translate_row(raw)
    if trans:
        rows.append(trans)

    if query.startswith(">"):
        cmd = raw.strip()[1:].strip()
        if cmd:
            rows.append(make("cmd", cmd, tr("выполнить команду"), cmd, "cmd:" + cmd, "", 0))
        return rows

    if query.startswith(":"):
        return rows + emoji_items(query)

    items = app_items() + action_items() + window_items() + file_items()
    tokens = query.split()
    if tokens:
        # Приложения важнее окон, окна важнее файлов: в Spotlight файл не должен
        # перебивать программу. И не больше горсти строк одного вида, чтобы
        # список не превращался в свалку однотипных файлов.
        boosts = {"app": 800, "action": 600, "appaction": 400, "win": 500, "file": 40}
        caps = {"app": 10, "action": 6, "appaction": 4, "win": 6, "file": 8}
        scored = []
        for item in items:
            deep = item["kind"] != "file"       # файлам опечатки не нужны
            s = score_query(tokens, item["text"], item["text_alt"], deep)
            if s > 0:
                extra = boosts.get(item["kind"], 0) + history_boost(item)
                scored.append((s + extra, item))
        scored.sort(key=lambda pair: -pair[0])
        used = {}
        for _s, item in scored:
            kind = item["kind"]
            if used.get(kind, 0) >= caps.get(kind, 8):
                continue
            used[kind] = used.get(kind, 0) + 1
            rows.append(item)
            if len(rows) >= 36:
                break
    else:
        # пустой запрос: сразу показываем то, что обычно нужно с клавиатуры
        rows += action_items()
        rows += window_items()[:6]
    rows += web_items(raw)
    return rows


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    if argv[0] == "--selftest":
        return selftest()
    if argv[0] == "--use":
        if len(argv) > 1 and argv[1]:
            os.makedirs(CACHE, exist_ok=True)
            with open(HISTORY, "a", encoding="utf-8") as fh:
                fh.write(argv[1] + "\n")
        return 0

    start = time.time()
    rows = build(argv[0])
    elapsed = (time.time() - start) * 1000
    payload = {"query": argv[0].strip(), "rows": rows}
    os.makedirs(CACHE, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False)
    print(json.dumps(payload, ensure_ascii=False))
    print(f"[{elapsed:.0f} мс, строк {len(rows)}]", file=sys.stderr)
    return 0


def selftest():
    checks = [
        (tr("еудупкфь"), "Telegram"),      # набрано в русской раскладке
        ("trlegram", "Telegram"),      # опечатка
        ("fireox", "Firefox"),         # опечатка
        (tr("настройки"), tr("Настройки")),    # русский запрос
        ("2+2*3", "8"),                # калькулятор
        ("sqrt(16)", "4"),
        ("340*15%", "51"),
        (tr("обои"), tr("Обои и темы")),       # своё действие
        ("screenshot", tr("Снимок")),
        ("alacritty", "Alacritty"),    # приложение важнее одноимённого файла
        ("10 " + tr("км") + " " + tr("в") + " милях", tr("милях")),   # единицы
        ("70 f to c", "°C"),           # температура
        ("steam big picture", "Big Picture"),   # действие из .desktop
    ]
    bad = 0
    for query, want in checks:
        rows = build(query)
        titles = [r["title"] for r in rows[:6]]
        hit = titles[0] if titles else ""
        ok = any(want.lower() in t.lower() for t in titles[:2])
        if not ok:
            bad += 1
        print(f"  {tr('ок ') if ok else tr('МИМО')} {query:12} -> {titles[:4]}")
    # перевод ходит в сеть — проверяем отдельно и не считаем провалом офлайн
    if translate("привет", "en"):
        rows = build("*" + tr("привет"))
        titles = [r["title"] for r in rows[:3]]
        ok = bool(titles) and titles[0].lower() != ("*" + tr("привет")).lower()
        print(f"  {tr('ок ') if ok else tr('МИМО')} *{tr('привет'):12} -> {titles[:2]}")
        if not ok:
            bad += 1
        print(f"  итого: {len(checks) + 1 - bad} из {len(checks) + 1}")
    else:
        print(f"  итого: {len(checks) - bad} из {len(checks)} "
              f"({tr('перевод пропущен: нет сети')})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
