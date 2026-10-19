#!/usr/bin/env python3
"""История буфера обмена для сайдбара.

Отдельный пакет не нужен: содержимое кладёт сюда сам wl-paste. sway запускает
`wl-paste --watch clipboard.py store`, и нас зовут на каждое новое выделение.
wl-clipboard и так требуется бару, так что лишних зависимостей нет.

    clipboard.py store          — принять текущее выделение (зовёт wl-paste)
    clipboard.py list           — история для сайдбара (JSON)
    clipboard.py copy <id>      — вернуть элемент в буфер и поднять наверх
    clipboard.py remove <id>    — убрать элемент
    clipboard.py clear          — очистить историю

Кэш: ~/.cache/quickshell/clipboard/ — index.json, картинки в images/, текст в
texts/. В панель отдаём только метаданные: содержимое картинок бывает тяжёлым.
"""
import hashlib
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
DIR = f"{HOME}/.cache/quickshell/clipboard"
IMAGES = f"{DIR}/images"
TEXTS = f"{DIR}/texts"
INDEX = f"{DIR}/index.json"

MAX_ITEMS = 120        # сколько элементов истории держим
MAX_TEXT = 400_000     # очень длинный текст обрезаем, чтобы кэш не пух
PREVIEW = 160          # сколько символов показываем в списке


def load():
    try:
        with open(INDEX, encoding="utf-8") as fh:
            data = json.load(fh)
        items = data.get("items") if isinstance(data, dict) else None
        if isinstance(items, list):
            return items
    except Exception:
        pass
    return []


def save(items):
    os.makedirs(DIR, exist_ok=True)
    tmp = INDEX + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"items": items}, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, INDEX)


def write_atomic(path, data):
    """Пишем через .tmp и переименовываем: панель не должна поймать полуфайл."""
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)


def wl(args, data=None):
    """Прогон wl-paste/wl-copy. None — команды нет или она отвалилась."""
    try:
        return subprocess.run(["wl-paste"] + (args or []), input=data,
                              capture_output=True, timeout=5)
    except Exception:
        return None


def mime_types():
    r = wl(["--list-types"])
    if not r or r.returncode != 0:
        return []
    return [t for t in (r.stdout or b"").decode("utf-8", "replace").split() if t]


def preview_of(text):
    """Однострочная выжимка: первая непустая строка, обрезанная по ширине."""
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line[:PREVIEW] + ("…" if len(line) > PREVIEW else "")
    return ""


def store():
    """Принять текущее выделение. Зовётся wl-paste на каждое изменение."""
    types = mime_types()
    kind, mime, content = None, "", b""

    # картинку предпочитаем тексту: в буфере часто лежит и то и другое
    images = [t for t in types if t.startswith("image/")]
    if images:
        mime = "image/png" if "image/png" in images else sorted(images)[0]
        r = wl(["--type", mime])
        if r and r.returncode == 0 and r.stdout:
            kind, content = "image", r.stdout

    if kind is None:
        r = wl([])                      # текст: wl-paste сам выберет тип
        if r and r.returncode == 0 and r.stdout:
            kind, content = "text", r.stdout[:MAX_TEXT]

    if kind is None:
        return 1

    # одинаковый текст с разным числом переводов строки — один и тот же элемент
    key = content.rstrip(b"\r\n") if kind == "text" else content
    ident = hashlib.sha1(key).hexdigest()[:16]
    items = [it for it in load() if it.get("id") != ident]   # повторы — наверх

    if kind == "image":
        os.makedirs(IMAGES, exist_ok=True)
        ext = mimetypes.guess_extension(mime) or ".png"
        path = f"{IMAGES}/{ident}{ext}"
        write_atomic(path, content)
        preview, lines = "", 0
    else:
        os.makedirs(TEXTS, exist_ok=True)
        path = f"{TEXTS}/{ident}.txt"
        write_atomic(path, content)
        text = content.decode("utf-8", "replace")
        preview, lines = preview_of(text), text.count("\n") + 1

    items.insert(0, {
        "id": ident, "kind": kind, "path": path, "mime": mime,
        "preview": preview, "lines": lines, "size": len(content),
        "ts": int(time.time()),
    })
    prune(items)
    save(items)
    return 0


def prune(items):
    """Держим только MAX_ITEMS последних, файлы выкинутых удаляем."""
    for old in items[MAX_ITEMS:]:
        try:
            os.remove(old.get("path", ""))
        except Exception:
            pass
    del items[MAX_ITEMS:]


def cmd_list():
    items = load()
    print(json.dumps({"items": items, "count": len(items)}, ensure_ascii=False))
    return 0


def find(items, ident):
    for i, it in enumerate(items):
        if it.get("id") == ident:
            return i, it
    return -1, None


def cmd_copy(ident):
    items = load()
    i, item = find(items, ident)
    if item is None:
        return 1
    path = item.get("path", "")
    if not os.path.exists(path):
        cmd_remove(ident)
        return 1
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        if item.get("kind") == "image":
            mime = item.get("mime") or mimetypes.guess_type(path)[0] or "image/png"
            subprocess.run(["wl-copy", "--type", mime], input=data, timeout=5)
        else:
            subprocess.run(["wl-copy"], input=data, timeout=5)
    except Exception:
        return 1
    # элемент уходит наверх: сторожил его watcher увидит тот же id и не задвоит
    items.pop(i)
    item["ts"] = int(time.time())
    items.insert(0, item)
    save(items)
    return 0


def cmd_remove(ident):
    items = load()
    i, item = find(items, ident)
    if item is None:
        return 1
    try:
        os.remove(item.get("path", ""))
    except Exception:
        pass
    items.pop(i)
    save(items)
    return 0


def cmd_clear():
    shutil.rmtree(IMAGES, ignore_errors=True)
    shutil.rmtree(TEXTS, ignore_errors=True)
    save([])
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    if cmd == "store":
        return store()
    if cmd == "list":
        return cmd_list()
    if cmd == "copy" and len(argv) > 2:
        return cmd_copy(argv[2])
    if cmd == "remove" and len(argv) > 2:
        return cmd_remove(argv[2])
    if cmd == "clear":
        return cmd_clear()
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
