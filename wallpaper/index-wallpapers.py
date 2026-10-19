#!/usr/bin/env python3
"""Индексатор обоев: миниатюры и доминирующий цвет.

Сканирует папку обоев (по умолчанию ~/Wallpapers, переопределяется
переменной WALLPAPER_DIR), делает для каждой картинки миниатюру в
~/.cache/wallpaper/thumbs/ и определяет основной оттенок — по нему в панели
выбора работают фильтры.

Результат: ~/.cache/wallpaper/index.json
Пересобираются только изменившиеся файлы (по mtime и размеру).

    index-wallpapers.py [папка ...]
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache", "wallpaper")
THUMBS = os.path.join(CACHE, "thumbs")
INDEX = os.path.join(CACHE, "index.json")
GIF_SCRIPT = os.path.join(HOME, ".config", "wallpaper", "gif-cache.sh")

# размер экрана определяем один раз за запуск
_SCREEN = None

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".avif", ".gif", ".tif", ".tiff"}
VIDEO_EXT = {".mp4", ".mkv", ".mov", ".webm"}

THUMB_W = 320
THUMB_QUALITY = 82

# оттенок -> название группы (используется в фильтрах панели)
BUCKETS = [
    (20, "red"),
    (45, "orange"),
    (70, "yellow"),
    (160, "green"),
    (200, "cyan"),
    (255, "blue"),
    (290, "purple"),
    (345, "pink"),
    (361, "red"),
]


def bucket_for_hue(hue: float) -> str:
    for limit, name in BUCKETS:
        if hue < limit:
            return name
    return "mono"


def analyze_image(path: str):
    """Возвращает (оттенок-группа, PIL.Image) или (None, None)."""
    try:
        im = Image.open(path)
        im.draft("RGB", (THUMB_W, THUMB_W))  # быстрая распаковка jpeg
        im = im.convert("RGB")
    except Exception:
        return None, None

    small = im.copy()
    small.thumbnail((64, 64))

    # доминирующий оттенок: считаем пиксели по корзинам, взвешивая насыщенность
    import colorsys

    weights = [0.0] * 12
    colored = 0
    total = 0
    pixels = small.load()
    for y in range(small.height):
        for x in range(small.width):
            r, g, b = pixels[x, y]
            total += 1
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < 0.16 or v < 0.10 or (v > 0.97 and s < 0.12):
                continue  # серое / чёрное / белое
            colored += 1
            weights[min(11, int(h * 12))] += s * v

    if total == 0 or colored / total < 0.06:
        return "mono", im

    best = max(range(12), key=lambda i: weights[i])
    return bucket_for_hue((best + 0.5) * 30.0), im


def video_poster(path: str):
    """Кадр из видео во временный файл (или None)."""
    if not shutil.which("ffmpeg"):
        return None
    tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
    tmp.close()
    for seek in ("1", "0"):
        r = subprocess.run(
            ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
             "-ss", seek, "-i", path, "-frames:v", "1", "-q:v", "3", tmp.name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if r.returncode == 0 and os.path.getsize(tmp.name) > 0:
            return tmp.name
    os.unlink(tmp.name)
    return None


def make_thumb(im, dst: str):
    t = im.copy()
    t.thumbnail((THUMB_W, 100000))
    t.save(dst, "JPEG", quality=THUMB_QUALITY)


def screen_size():
    """Экран в пикселях (или None).

    Движок обоев кеширует гифки под размер экрана, и панель обоев должна
    прогревать тот же файл: иначе одна и та же гифка кодируется дважды —
    один раз здесь, другой раз при показе.
    """
    global _SCREEN
    if _SCREEN is not None:
        return _SCREEN or None
    _SCREEN = (0, 0)
    if shutil.which("swaymsg"):
        try:
            out = subprocess.run(["swaymsg", "-t", "get_outputs"],
                                 capture_output=True, text=True, timeout=3).stdout
            for o in json.loads(out):
                if not o.get("focused"):
                    continue
                mode = o.get("current_mode") or {}
                if mode.get("width") and mode.get("height"):
                    _SCREEN = (int(mode["width"]), int(mode["height"]))
                    break
        except Exception:
            pass
    return _SCREEN or None


def gif_video(path: str):
    """Готовит mp4 из гифки (кеш ~/.cache/wallpaper/gif) и возвращает путь.

    Гифки движок обоев играет видеотрактом: Qt не анимирует gif в Image,
    а AnimatedImage держит в памяти все кадры. Собираем заранее, чтобы
    в момент клика по миниатюре всё было готово.
    """
    if not os.path.exists(GIF_SCRIPT):
        return None
    cmd = ["bash", GIF_SCRIPT, path]
    size = screen_size()
    if size:
        cmd += [str(size[0]), str(size[1])]
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = (r.stdout or "").strip()
    return out if r.returncode == 0 and out and os.path.exists(out) else None


def load_index() -> dict:
    try:
        with open(INDEX, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            return {it["path"]: it for it in data["items"]}
    except Exception:
        pass
    return {}


def scan(dirs):
    found = []
    for d in dirs:
        d = os.path.expanduser(d)
        if not os.path.isdir(d):
            continue
        for root, subdirs, files in os.walk(d):
            subdirs[:] = [s for s in subdirs if not s.startswith(".")]
            for name in sorted(files):
                if name.startswith("."):
                    continue
                ext = os.path.splitext(name)[1].lower()
                if ext in IMAGE_EXT or ext in VIDEO_EXT:
                    found.append(os.path.join(root, name))
    return found


def main():
    argv = sys.argv[1:]
    as_json = "--json" in argv
    dirs = [a for a in argv if not a.startswith("-")]
    if not dirs:
        dirs = [os.environ.get("WALLPAPER_DIR") or os.path.join(HOME, "Wallpapers")]
    os.makedirs(THUMBS, exist_ok=True)

    old = load_index()
    items = []
    changed = False
    errors = 0

    for path in scan(dirs):
        try:
            st = os.stat(path)
        except OSError:
            continue
        key = hashlib.sha1(path.encode("utf-8")).hexdigest()[:16]
        thumb = os.path.join(THUMBS, key + ".jpg")
        ext = os.path.splitext(path)[1].lower()
        is_video = ext in VIDEO_EXT

        # гифку заранее перегоняем в mp4: движок обоев играет её видео
        if ext == ".gif":
            gif_video(path)

        prev = old.get(path)
        fresh = (
            prev
            and prev.get("mtime") == int(st.st_mtime)
            and prev.get("size") == st.st_size
            and os.path.exists(thumb)
        )
        if fresh:
            items.append(prev)
            continue

        src = video_poster(path) if is_video else path
        bucket, im = analyze_image(src) if src else (None, None)
        if src is None or bucket is None:
            errors += 1
            if prev:
                items.append(prev)
            continue
        try:
            make_thumb(im, thumb)
        except Exception:
            errors += 1
            continue
        if is_video:
            os.unlink(src)

        items.append({
            "path": path,
            "name": os.path.basename(path),
            "dir": os.path.dirname(path),
            "thumb": thumb,
            "bucket": bucket,
            "video": is_video,
            "mtime": int(st.st_mtime),
            "size": st.st_size,
        })
        changed = True

    # подчищаем превью исчезнувших файлов
    alive = {os.path.basename(it["thumb"]) for it in items if it.get("thumb")}
    for f in os.listdir(THUMBS):
        if f not in alive:
            try:
                os.unlink(os.path.join(THUMBS, f))
            except OSError:
                pass

    items.sort(key=lambda it: it["name"].lower())
    payload = {"dirs": dirs, "items": items}
    with open(INDEX + ".tmp", "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    os.replace(INDEX + ".tmp", INDEX)

    if as_json:
        # для панели выбора обоев: список забирается прямо из вывода
        json.dump(payload, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return

    print(f"обоев: {len(items)}" + (f", не удалось прочитать: {errors}" if errors else "")
          + ("" if changed else " (без изменений)"))


if __name__ == "__main__":
    main()
