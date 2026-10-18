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
from i18n import tr

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
        "kind": "calc", "title": fmt(value), "hint": f"считать: {raw.strip()}",
        "action": "", "copy": fmt(value), "id": "calc",
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
    out = []
    if re.match(r"^[\w.-]+\.[a-z]{2,}(/\S*)?$", q, re.I):
        out.append(make("web", f"Открыть {q}", tr("ссылка"),
                        f"xdg-open 'https://{q}'", "web:url", "", -50))
    out.append(make("web", f"Найти «{q}» в интернете", "DuckDuckGo",
                    f"xdg-open 'https://duckduckgo.com/?q={enc}'", "web:ddg", "", -50))
    out.append(make("web", f"«{q}» в Википедии", tr("Википедия"),
                    f"xdg-open 'https://ru.wikipedia.org/w/index.php?search={enc}'",
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
        boosts = {"app": 800, "action": 600, "win": 500, "file": 40}
        caps = {"app": 10, "action": 6, "win": 6, "file": 8}
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
    print(f"  итого: {len(checks) - bad} из {len(checks)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
