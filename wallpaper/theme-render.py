#!/usr/bin/env python3
"""Готовит цвета для waybar / kitty / alacritty / quickshell.

Два источника палитры:

    theme-render.py auto <картинка> [dark|light] [режим]
        цвета выводит matugen из обоев. Источник цвета выбираем сами —
        главный по площади хроматичный оттенок, а в нём самый насыщенный
        цвет (как Score в Monet, см. source_color): иначе matugen на тёплых
        и зелёных обоях подставлял синий.
        Режим (universal, vibrant, content, expressive, fidelity,
        monochrome, rainbow, neutral, fruit-salad) — см. FLAVOURS.
        universal = оригинальный Material You (tonalspot).

    theme-render.py named <id>
        цвета берутся из готовой схемы ~/.config/wallpaper/themes/<id>.json

Результат кладётся в ~/.cache/wallpaper/theme/: style.css, colors.json,
theme.conf, alacritty.toml. Раскладывает по конфигам theme-gen.sh.

    theme-render.py list
        список схем: id<TAB>название<TAB>тёмная|светлая
"""

import colorsys
import json
import os
import re
import subprocess
import sys

from PIL import Image

HOME = os.path.expanduser("~")
THEME_DIR = f"{HOME}/.cache/wallpaper/theme"
TPL_DIR = f"{HOME}/.config/wallpaper/templates"
SCHEMES_DIR = f"{HOME}/.config/wallpaper/themes"
EXPORT_CONFIG = f"{HOME}/.config/matugen/config-export.toml"

TEMPLATES = ("style.css", "colors.json", "theme.conf", "alacritty.toml", "wofi.css",
             "swaylock.conf")
TPL_FILES = {
    "style.css": "waybar.css",
    "colors.json": "quickshell.json",
    "theme.conf": "kitty.conf",
    "alacritty.toml": "alacritty.toml",
    "wofi.css": "wofi.css",
    "swaylock.conf": "swaylock.conf",
}

WHITE = (255, 255, 255)

# роли, которые обязаны быть в палитре (иначе шаблон останется с {{...}})
REQUIRED = (
    "bg", "surface", "surface_variant", "fg", "fg_dim", "outline", "outline_dim",
    "accent", "on_accent", "accent_container", "on_accent_container", "accent_fixed",
    "secondary", "on_secondary", "secondary_container", "on_secondary_container",
    "tertiary", "on_tertiary", "tertiary_container", "tertiary_fixed",
    "red", "on_red", "red_container", "inverse_accent",
    "ansi_black", "ansi_red", "ansi_green", "ansi_yellow",
    "ansi_blue", "ansi_magenta", "ansi_cyan", "ansi_white",
    "ansi_bright_black", "ansi_bright_red", "ansi_bright_green", "ansi_bright_yellow",
    "ansi_bright_blue", "ansi_bright_magenta", "ansi_bright_cyan", "ansi_bright_white",
)


# ── работа с цветом ─────────────────────────────────────────────────────────

def to_rgb(value):
    s = value.lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in rgb)


def mix(a, b, share):
    """share — доля цвета a (0..1), остальное — b."""
    a, b = to_rgb(a), to_rgb(b)
    return to_hex(tuple(a[i] * share + b[i] * (1 - share) for i in range(3)))


def luminance(rgb):
    rgb = to_rgb(rgb) if isinstance(rgb, str) else rgb

    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def on_color(base, *candidates):
    """Самый контрастный к base цвет из кандидатов."""
    return max(candidates, key=lambda c: contrast(base, c))


# ── палитра «из обоев» (matugen) ────────────────────────────────────────────

# Режимы «Тип Material You»: имя в настройках -> тип схемы matugen.
# universal — оригинальный Material You: схема tonalspot, как в Monet.
FLAVOURS = {
    "universal": "scheme-tonal-spot",
    "vibrant": "scheme-vibrant",
    "content": "scheme-content",
    "expressive": "scheme-expressive",
    "fidelity": "scheme-fidelity",
    "monochrome": "scheme-monochrome",
    "rainbow": "scheme-rainbow",
    "neutral": "scheme-neutral",
    "fruit-salad": "scheme-fruit-salad",
}


def source_color(image):
    """Цвет-источник обоев по логике material-color-utilities (Score в Monet).

    Порядок такой же, как в оригинальном Material You:

    1. квантуем картинку;
    2. выбрасываем серое, почти чёрное и почти белое — иначе палитру
       задаёт фон, а не сам рисунок;
    3. строим гистограмму оттенков по площади со сглаживанием ±15°
       (HUE_SMOOTHING из material-color-utilities): так главный по площади
       оттенок побеждает мелкую, но очень яркую деталь;
    4. в победившем оттенке берём самый насыщенный цвет — он и есть источник.

    Поэтому зелёные обои дают зелёную палитру, а не синюю: matugen с
    «индексом 0» берёт самый крупный участок (у картинки с 71% почти чёрного
    фона он уходил в синее), а --prefer saturation — самую мелкую яркую точку.
    """
    try:
        im = Image.open(image).convert("RGB")
    except Exception:
        return None
    im.thumbnail((200, 200))
    total = im.width * im.height
    if not total:
        return None

    quant = im.quantize(colors=32, method=Image.MEDIANCUT)
    palette = quant.getpalette() or []
    cells = []
    for count, index in quant.getcolors() or []:
        try:
            r, g, b = palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2]
        except IndexError:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.20 or v < 0.18 or v > 0.96:
            continue
        cells.append((count / total, h * 360, s, v, (r, g, b)))
    if not cells:
        return None

    # гистограмма оттенков с треугольным окном ±15°
    window = 15
    hue_score = [0.0] * 361
    for share, hue, _s, _v, _rgb in cells:
        bucket = int(round(hue)) % 361
        for offset in range(-window, window + 1):
            weight = (window + 1 - abs(offset)) / (window + 1)
            hue_score[(bucket + offset) % 361] += share * weight
    best_hue = max(range(361), key=lambda i: hue_score[i])

    # в победившем оттенке — самый насыщенный цвет
    best = None
    for share, hue, s, _v, rgb in cells:
        delta = abs(((hue - best_hue + 180) % 360) - 180)
        if delta > window + 4:
            continue
        score = s * 1000 + share
        if best is None or score > best[0]:
            best = (score, rgb)
    return best[1] if best else None


def matugen_palette(image, mode, flavour):
    if not os.path.isfile(EXPORT_CONFIG):
        raise RuntimeError(f"нет {EXPORT_CONFIG} — matugen не сможет отдать палитру")

    scheme = FLAVOURS.get(flavour, FLAVOURS["universal"])

    # источник цвета выбираем сами — см. source_color
    seed = source_color(image)
    if seed is not None:
        source = ["color", "hex", "#%02x%02x%02x" % seed]
    else:
        # в картинке нет хроматичных цветов: пусть matugen возьмёт
        # самый насыщенный из своих кандидатов (не самый крупный)
        source = ["image", image, "--prefer", "saturation"]

    cmd = [
        "nice", "-n", "15", "matugen", "-c", EXPORT_CONFIG, "-j", "hex",
        "-m", mode, "-t", scheme,
    ] + source + ["-q"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "matugen не смог разобрать картинку")
    try:
        data = json.loads(res.stdout)
    except ValueError:
        raise RuntimeError("matugen вернул не JSON")

    def role(name):
        try:
            return data["colors"][name]["default"]["color"]
        except KeyError:
            raise RuntimeError(f"в палитре нет роли {name}")

    red = role("error")
    return {
        "bg": role("surface_container"),
        "surface": role("surface"),
        "surface_variant": role("surface_variant"),
        "fg": role("on_surface"),
        "fg_dim": role("on_surface_variant"),
        "outline": role("outline"),
        "outline_dim": role("outline_variant"),
        "accent": role("primary"),
        "on_accent": role("on_primary"),
        "accent_container": role("primary_container"),
        "on_accent_container": role("on_primary_container"),
        "accent_fixed": role("primary_fixed"),
        "secondary": role("secondary"),
        "on_secondary": role("on_secondary"),
        "secondary_container": role("secondary_container"),
        "on_secondary_container": role("on_secondary_container"),
        "tertiary": role("tertiary"),
        "on_tertiary": role("on_tertiary"),
        "tertiary_container": role("tertiary_container"),
        "tertiary_fixed": role("tertiary_fixed"),
        "red": red,
        "on_red": role("on_error"),
        "red_container": role("error_container"),
        "inverse_accent": role("inverse_primary"),
        "ansi_black": role("surface_variant"),
        "ansi_red": red,
        "ansi_green": role("primary"),
        "ansi_yellow": role("tertiary"),
        "ansi_blue": role("secondary"),
        "ansi_magenta": role("primary_container"),
        "ansi_cyan": role("secondary_container"),
        "ansi_white": role("on_surface_variant"),
        "ansi_bright_black": role("outline"),
        "ansi_bright_red": role("error_container"),
        "ansi_bright_green": role("primary_fixed"),
        "ansi_bright_yellow": role("tertiary_fixed"),
        "ansi_bright_blue": role("secondary_fixed"),
        "ansi_bright_magenta": role("inverse_primary"),
        "ansi_bright_cyan": role("tertiary_container"),
        "ansi_bright_white": role("on_surface"),
    }


# ── палитра готовой схемы ───────────────────────────────────────────────────

def scheme_palette(theme_id):
    path = os.path.join(SCHEMES_DIR, f"{theme_id}.json")
    if not os.path.isfile(path):
        raise RuntimeError(f"нет схемы {theme_id} ({path})")
    with open(path, encoding="utf-8") as f:
        t = json.load(f)

    def col(key):
        try:
            return t[key]
        except KeyError:
            raise RuntimeError(f"в схеме {theme_id} нет цвета «{key}»")

    bg, fg = col("bg"), col("fg")
    accent, accent2, accent3 = col("accent"), col("accent2"), col("accent3")
    ansi = t.get("ansi", {})
    missing = [k for k in ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
               if k not in ansi]
    if missing:
        raise RuntimeError(f"в схеме {theme_id} нет цветов ansi: {', '.join(missing)}")
    ansi_bright = t.get("ansi_bright", {})

    pal = {
        "bg": bg,
        "surface": col("bg_soft"),
        "surface_variant": mix(fg, bg, 0.08),
        "fg": fg,
        "fg_dim": t.get("fg_dim") or mix(fg, bg, 0.62),
        "outline": mix(fg, bg, 0.42),
        "outline_dim": mix(fg, bg, 0.26),
        "accent": accent,
        "on_accent": on_color(accent, bg, fg),
        "accent_container": mix(accent, bg, 0.32),
        "on_accent_container": mix(accent, fg, 0.55),
        "accent_fixed": mix(accent, to_hex(WHITE), 0.28),
        "secondary": accent2,
        "on_secondary": on_color(accent2, bg, fg),
        "secondary_container": mix(accent2, bg, 0.32),
        "on_secondary_container": mix(accent2, fg, 0.55),
        "tertiary": accent3,
        "on_tertiary": on_color(accent3, bg, fg),
        "tertiary_container": mix(accent3, bg, 0.32),
        "tertiary_fixed": mix(accent3, to_hex(WHITE), 0.28),
        "red": ansi["red"],
        "on_red": on_color(ansi["red"], bg, fg),
        "red_container": mix(ansi["red"], bg, 0.38),
        "inverse_accent": mix(accent, fg, 0.35),
    }

    # обычные цвета терминала — из схемы, яркие — из схемы, если заданы,
    # иначе светлее обычных на четверть
    for name in ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"):
        pal[f"ansi_{name}"] = ansi[name]
        pal[f"ansi_bright_{name}"] = ansi_bright.get(name) or mix(ansi[name], to_hex(WHITE), 0.25)
    pal["ansi_bright_black"] = ansi_bright.get("black") or pal["fg_dim"]
    pal["ansi_bright_white"] = ansi_bright.get("white") or mix(fg, to_hex(WHITE), 0.3)
    return pal


# ── рендер ──────────────────────────────────────────────────────────────────

def render(palette):
    for name in REQUIRED:
        if name not in palette:
            raise RuntimeError(f"в палитре нет цвета «{name}»")
    missing = [n for n in palette if not palette[n].startswith("#")]
    if missing:
        raise RuntimeError(f"цвета без #: {', '.join(missing)}")

    # Тень текста считаем от светлоты фона: на светлой палитре она даёт тёмный
    # ореол вокруг тёмных букв и текст становится грязным — там её выключаем.
    palette = dict(palette)
    palette["text_shadow"] = (
        "none" if luminance(to_rgb(palette["bg"])) > 0.5
        else "0 1px 2px rgba(0, 0, 0, 0.55)"
    )

    out = {}
    for target, tpl in TPL_FILES.items():
        with open(os.path.join(TPL_DIR, tpl), encoding="utf-8") as f:
            text = f.read()
        text = re.sub(r"\{\{\s*([a-z_]+)\s*\}\}",
                      lambda m: palette.get(m.group(1), m.group(0)), text)
        left = re.findall(r"\{\{[^}]*\}\}", text)
        if left:
            raise RuntimeError(f"{tpl}: не подставлены цвета: {', '.join(sorted(set(left)))}")
        out[target] = text

    # colors.json должен быть валидным JSON — на нём висит палитра панелей
    json.loads(out["colors.json"])
    return out


def write(out):
    os.makedirs(THEME_DIR, exist_ok=True)
    for name, text in out.items():
        tmp = f"{THEME_DIR}/{name}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, f"{THEME_DIR}/{name}")


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    what = argv[0]

    try:
        if what == "list":
            rows = []
            for fn in sorted(os.listdir(SCHEMES_DIR)) if os.path.isdir(SCHEMES_DIR) else []:
                if not fn.endswith(".json"):
                    continue
                try:
                    with open(os.path.join(SCHEMES_DIR, fn), encoding="utf-8") as f:
                        t = json.load(f)
                except ValueError:
                    continue
                rows.append((fn[:-5], t.get("name", fn[:-5]), t.get("variant", "dark"), t.get("accent", "")))
            rows.sort(key=lambda r: r[1].lower())
            for r in rows:
                print("\t".join(r))
            return 0

        if what == "named":
            if len(argv) < 2:
                raise RuntimeError("нужно имя схемы: theme-render.py named <id>")
            palette = scheme_palette(argv[1])
            source = f"схема {argv[1]}"
        elif what == "auto":
            if len(argv) < 2:
                raise RuntimeError("нужна картинка: theme-render.py auto <файл>")
            image = argv[1]
            if not os.path.isfile(image):
                raise RuntimeError(f"нет файла {image}")
            mode = argv[2] if len(argv) > 2 else "dark"
            flavour = argv[3] if len(argv) > 3 else "universal"
            if flavour.startswith("scheme-"):
                flavour = flavour[len("scheme-"):]
            palette = matugen_palette(image, mode, flavour)
            source = f"обои {os.path.basename(image)} [{flavour}]"
        else:
            raise RuntimeError(f"неизвестная команда «{what}»")

        write(render(palette))
    except RuntimeError as err:
        print(f"theme-render: {err}", file=sys.stderr)
        return 1

    print(palette["accent"], file=sys.stderr)
    print(source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
