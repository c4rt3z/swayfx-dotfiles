#!/usr/bin/env python3
"""Скриншоты и их история — для биндов и сайдбара.

    shot.py full [задержка]   — весь экран (задержка в секундах)
    shot.py region            — область: выделяем мышью (slurp)
    shot.py window            — активное окно
    shot.py list [N]          — свежие снимки (JSON для сайдбара)
    shot.py copy <файл>       — положить снимок в буфер обмена
    shot.py ocr <файл>        — распознать текст (tesseract) и положить в буфер
    shot.py open <файл>       — открыть в просмотрщике (xdg-open)
    shot.py remove <файл>     — удалить снимок

Снимки лежат в ~/Pictures/Screenshots (папку берём у xdg-user-dir). Каждый
снимок сразу уходит в буфер обмена и показывается уведомлением — подписи
переводим тем же словарём, что и панели.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import tr  # noqa: E402


def pictures_dir():
    """Папка снимков: ~/Pictures/Screenshots, имя Pictures — из xdg-user-dir."""
    base = ""
    try:
        r = subprocess.run(["xdg-user-dir", "PICTURES"], capture_output=True, timeout=3)
        base = (r.stdout or b"").decode("utf-8", "replace").strip()
    except Exception:
        base = ""
    if not base or base.endswith("/Pictures") and not os.path.isdir(base):
        base = os.path.expanduser("~/Pictures")
    path = os.path.join(base, "Screenshots")
    os.makedirs(path, exist_ok=True)
    return path


def have(cmd):
    return shutil.which(cmd) is not None


def notify(title, body, icon=""):
    args = ["notify-send"]
    if icon and os.path.exists(icon):
        args += ["-i", icon]
    args += [title, body]
    try:
        subprocess.Popen(args)
    except Exception:
        pass


def focused_geometry():
    """Геометрия активного окна в виде «x,y wxh» — для grim -g."""
    try:
        r = subprocess.run(["swaymsg", "-t", "get_tree"], capture_output=True, timeout=3)
        tree = json.loads((r.stdout or b"").decode("utf-8", "replace"))
    except Exception:
        return ""

    def walk(node):
        if node.get("focused") and node.get("pid"):
            return node
        for child in list(node.get("nodes") or []) + list(node.get("floating_nodes") or []):
            found = walk(child)
            if found:
                return found
        return None

    node = walk(tree)
    if not node:
        return ""
    rect = node.get("rect") or {}
    win = node.get("window_rect") or {}
    w = win.get("width", 0)
    h = win.get("height", 0)
    if w <= 0 or h <= 0:
        w, h = rect.get("width", 0), rect.get("height", 0)
    if w <= 0 or h <= 0:
        return ""
    x = rect.get("x", 0) + win.get("x", 0)
    y = rect.get("y", 0) + win.get("y", 0)
    return f"{x},{y} {w}x{h}"


def grab(geometry, path):
    """grim в файл. Пустая geometry — весь экран."""
    if not have("grim"):
        notify(tr("Скриншот"), tr("нет grim — установите grim"))
        return False
    cmd = ["grim"]
    if geometry:
        cmd += ["-g", geometry]
    cmd.append(path)
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=30)
    except Exception:
        return False
    return r.returncode == 0 and os.path.exists(path)


def copy_image(path):
    if not have("wl-copy"):
        return False
    try:
        with open(path, "rb") as fh:
            subprocess.run(["wl-copy", "--type", "image/png"], input=fh.read(), timeout=10)
        return True
    except Exception:
        return False


def cmd_shot(mode, delay=0):
    if delay > 0:
        time.sleep(delay)
    geometry = ""
    if mode == "region":
        if not have("slurp"):
            notify(tr("Скриншот"), tr("нет slurp — установите slurp"))
            return 1
        try:
            r = subprocess.run(["slurp"], capture_output=True, timeout=300)
        except Exception:
            return 1
        geometry = (r.stdout or b"").decode("utf-8", "replace").strip()
        if r.returncode != 0 or not geometry:
            return 1                     # человек передумал — молчим
    elif mode == "window":
        geometry = focused_geometry()
        if not geometry:
            return 1
    elif mode != "full":
        print(__doc__.strip(), file=sys.stderr)
        return 2

    path = os.path.join(pictures_dir(), time.strftime("%Y-%m-%d_%H-%M-%S") + ".png")
    if not grab(geometry, path):
        return 1
    copy_image(path)
    notify(tr("Скриншот"), tr("Снимок сохранён и скопирован") + ": " + os.path.basename(path), path)
    print(path)
    return 0


def cmd_list(count=24):
    folder = pictures_dir()
    try:
        names = [n for n in os.listdir(folder) if n.lower().endswith((".png", ".jpg", ".jpeg"))]
    except Exception:
        names = []
    files = []
    for name in names:
        path = os.path.join(folder, name)
        try:
            st = os.stat(path)
        except Exception:
            continue
        files.append({"path": path, "name": name, "ts": int(st.st_mtime), "size": st.st_size})
    files.sort(key=lambda f: f["ts"], reverse=True)
    files = files[:count]
    print(json.dumps({"items": files, "dir": folder, "count": len(files)}, ensure_ascii=False))
    return 0


def ocr_langs():
    """tesseract --list-langs: русский берём, только если он установлен."""
    try:
        r = subprocess.run(["tesseract", "--list-langs"], capture_output=True, timeout=5)
        out = ((r.stdout or b"") + (r.stderr or b"")).decode("utf-8", "replace")
    except Exception:
        return ""
    langs = [l.strip() for l in out.splitlines()[1:] if l.strip()]
    pick = []
    for code in ("rus", "eng"):
        if code in langs:
            pick.append(code)
    return "+".join(pick)


def cmd_ocr(path):
    if not os.path.exists(path):
        return 1
    if not have("tesseract"):
        notify(tr("Распознавание текста"), tr("нет tesseract — установите tesseract"))
        return 1
    langs = ocr_langs() or "eng"
    try:
        r = subprocess.run(["tesseract", path, "-", "-l", langs],
                           capture_output=True, timeout=120)
    except Exception:
        return 1
    if r.returncode != 0:
        return 1
    text = re.sub(r"\n{3,}", "\n\n", (r.stdout or b"").decode("utf-8", "replace")).strip()
    if not text:
        notify(tr("Распознавание текста"), tr("текст на снимке не найден"), path)
        return 1
    try:
        subprocess.run(["wl-copy"], input=text.encode("utf-8"), timeout=10)
    except Exception:
        return 1
    notify(tr("Распознавание текста"), tr("текст скопирован в буфер"), path)
    print(text)
    return 0


def cmd_copy(path):
    if not os.path.exists(path):
        return 1
    if copy_image(path):
        notify(tr("Скриншот"), tr("Снимок в буфере обмена"), path)
        return 0
    return 1


def cmd_remove(path):
    try:
        os.remove(path)
        return 0
    except Exception:
        return 1


def cmd_open(path):
    if not os.path.exists(path):
        return 1
    for exe in ("xdg-open",):
        if have(exe):
            try:
                subprocess.Popen([exe, path])
                return 0
            except Exception:
                return 1
    return 1


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    if cmd in ("full", "region", "window"):
        delay = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else 0
        return cmd_shot(cmd, delay)
    if cmd == "list":
        count = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else 24
        return cmd_list(count)
    if cmd == "copy" and len(argv) > 2:
        return cmd_copy(argv[2])
    if cmd == "ocr" and len(argv) > 2:
        return cmd_ocr(argv[2])
    if cmd == "open" and len(argv) > 2:
        return cmd_open(argv[2])
    if cmd == "remove" and len(argv) > 2:
        return cmd_remove(argv[2])
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
