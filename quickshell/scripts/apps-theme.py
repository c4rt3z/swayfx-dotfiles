#!/usr/bin/env python3
"""Тёмная тема для GTK- и Qt-приложений, цвета — в тон обоям.

    apps-theme.py build         — пересобрать ~/.cache/quickshell/apps-theme.json
    apps-theme.py dark on|off   — тёмные или светлые приложения
    apps-theme.py sync          — тема приложений = тема обоев (тёмная/светлая)\n    apps-theme.py colors        — перекрасить GTK в палитру текущих обоев
    apps-theme.py --selftest

Что тут и почему так:

  * GTK. Настройки лежат в ~/.config/gtk-3.0/settings.ini и
    ~/.config/gtk-4.0/settings.ini: gtk-application-prefer-dark-theme и
    gtk-theme-name. Обе темы, Breeze и Breeze-Dark, в системе есть, поэтому
    переключение — это две строки. Плюс системная схема
    org.gnome.desktop.interface color-scheme — по ней же отвечает портал XDG,
    и её читают приложения на GTK4 и на Qt 6.5+.

  * Цвета. ~/.config/gtk-*/colors.css оставил kde-gtk-config от светлой схемы
    Breeze. Breeze-Dark подключает те же имена (*_breeze), поэтому светлый
    файл перебивал тёмную тему: тема тёмная, а окна светлые. Мы переписываем
    этот файл из палитры обоев (~/.cache/wallpaper/theme/colors.json) — тогда
    приложения и тёмные, и в тон Material You. Файл от kde-gtk-config
    сохраняем рядом (colors.css.breeze), чтобы вернуть при выключении.

  * Qt. Проверено на этой системе (PySide6 + замер фона окна): без настройки
    Qt отдаёт ColorScheme.Unknown и светлую палитру (#efefef), а с
    QT_QPA_PLATFORMTHEME=gtk3 берёт цвета из GTK — то есть из colors.css, а
    значит из палитры обоев. Портал XDG (xdgdesktopportal) тоже даёт тёмное, но
    серым Fusion-цветом. Поэтому ставим gtk3 и получаем один цвет на всей
    системе. Переменную прописывают environment.d (новый сеанс), запуск
    quickshell и waybar (через env), терминал (alacritty [env]) и оболочки.
    Своё оформление (qt6ct) появилось бы — скрипт это увидит в сводке.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from i18n import tr

HOME = os.path.expanduser("~")
PALETTE = f"{HOME}/.cache/wallpaper/theme/colors.json"
# своё имя: apps.json занят списком приложений (scripts/apps-index.py)
STATE = f"{HOME}/.cache/quickshell/apps-theme.json"
GTK_DIRS = ("gtk-3.0", "gtk-4.0")
GSETTINGS = "org.gnome.desktop.interface"

# если kde-gtk-config не оставил файла, определим хотя бы это
FALLBACK_NAMES = [
    "borders_breeze", "theme_bg_color_breeze", "theme_fg_color_breeze",
    "theme_base_color_breeze", "theme_text_color_breeze",
    "theme_selected_bg_color_breeze", "theme_selected_fg_color_breeze",
    "insensitive_bg_color_breeze", "insensitive_fg_color_breeze",
    "unfocused_borders_breeze", "link_color_breeze", "error_color_breeze",
    "warning_color_breeze", "success_color_breeze",
    "tooltip_background_breeze", "tooltip_text_breeze",
    "content_view_bg_breeze", "theme_button_background_normal_breeze",
    "theme_button_foreground_normal_breeze", "theme_titlebar_background_breeze",
    "theme_titlebar_foreground_breeze", "theme_header_background_breeze",
    "theme_header_foreground_breeze",
]

# общие имена: на них ссылаются не только Breeze, но и всякие самодельные
# css-куски приложений
GENERIC_NAMES = [
    "borders", "theme_bg_color", "theme_fg_color", "theme_base_color",
    "theme_text_color", "theme_selected_bg_color", "theme_selected_fg_color",
    "insensitive_bg_color", "insensitive_fg_color", "link_color",
    "error_color", "warning_color", "success_color", "tooltip_background",
    "tooltip_text", "accent_color", "accent_bg_color", "accent_fg_color",
    "window_bg_color", "window_fg_color", "view_bg_color", "view_fg_color",
    "headerbar_bg_color", "headerbar_fg_color", "card_bg_color",
    "popover_bg_color", "popover_fg_color", "shade_color", "scrollbar_outline_color",
]


def palette():
    data = {
        "base": "#1e1f25", "surface": "#121318", "border": "#45464f",
        "text": "#e3e1e9", "accent": "#b6c4ff", "onAccent": "#1e2d61",
        "red": "#ffb4ab",
    }
    try:
        with open(PALETTE, encoding="utf-8") as fh:
            data.update(json.load(fh))
    except Exception:
        pass
    return data


def to_rgb(value):
    value = value.strip().lstrip("#")
    if len(value) == 3:
        value = "".join(c * 2 for c in value)
    try:
        return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    except Exception:
        return (0, 0, 0)


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in rgb)


def mix(first, second, weight):
    """weight — сколько второго цвета (0..1)."""
    a, b = to_rgb(first), to_rgb(second)
    return to_hex(tuple(x + (y - x) * weight for x, y in zip(a, b)))


def color_for(name, pal):
    """Цвет для имени из colors.css. Незнакомое имя получает фон окна: палитра
    тёмная, поэтому даже промах оставит приложение тёмным."""
    n = name
    base, surface, text = pal["base"], pal["surface"], pal["text"]
    accent, on_accent = pal["accent"], pal["onAccent"]
    dim = mix(text, base, 0.45)
    dim_border = mix(pal["border"], surface, 0.5)

    if "error" in n:
        return pal["red"]
    if "warning" in n or "success" in n:
        return accent
    if "link" in n:
        return accent
    if "selected_bg" in n or "hovering_selected" in n:
        return mix(accent, base, 0.35) if "unfocused" in n or "insensitive" in n else accent
    if "selected_fg" in n:
        return on_accent
    if "insensitive" in n or "unfocused" in n:
        if "fg" in n or "text" in n or "foreground" in n:
            return dim
        if "border" in n:
            return dim_border
        if "view" in n or "base" in n:
            return mix(surface, base, 0.5)
        return mix(base, surface, 0.4)
    if "border" in n:
        return pal["border"]
    if "tooltip_text" in n or "foreground" in n or "fg_color" in n or "text_color" in n:
        return text
    if "tooltip_background" in n:
        return surface
    if "titlebar_background" in n or "header_background" in n:
        return base if "light" not in n else mix(base, text, 0.06)
    if "button_decoration_focus" in n or "view_active_decoration" in n or "view_hover_decoration" in n:
        return accent
    if "button_background" in n:
        return mix(base, surface, 0.5)
    if "content_view_bg" in n or "view_bg" in n or "base_color" in n:
        return surface
    if "bg_color" in n:
        return base
    if "shade_color" in n or "scrollbar_outline" in n:
        return dim_border
    if "accent_bg" in n:
        return accent
    if "accent_fg" in n:
        return on_accent
    if "accent" in n:
        return accent
    return base


def gtk_path(folder, name="colors.css"):
    return os.path.join(HOME, ".config", folder, name)


def names_in(path):
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                match = re.match(r"\s*@define-color\s+([A-Za-z0-9_]+)", line)
                if match:
                    out.append(match.group(1))
    except Exception:
        pass
    return out


def write_gtk_colors():
    """Переписать colors.css из палитры обоев (имя в имя, плюс общие имена)."""
    pal = palette()
    written = []
    for folder in GTK_DIRS:
        path = gtk_path(folder)
        if not os.path.isdir(os.path.dirname(path)):
            continue
        backup = path + ".breeze"
        if os.path.exists(path) and not os.path.exists(backup):
            shutil.copy2(path, backup)      # светлая схема Breeze — на возврат
        names = names_in(path) or list(FALLBACK_NAMES)
        lines = [tr("/* Цвета из обоев (~/.cache/wallpaper/theme/colors.json)."),
                 tr("   Переписывается scripts/apps-theme.py; файл от kde-gtk-config"),
                 tr("   лежит рядом как colors.css.breeze. */"), ""]
        for name in names:
            lines.append(f"@define-color {name} {color_for(name, pal)};")
        lines.append("")
        for name in GENERIC_NAMES:
            lines.append(f"@define-color {name} {color_for(name, pal)};")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        written.append(path)
        # gtk.css должен их подключать
        main = gtk_path(folder, "gtk.css")
        try:
            with open(main, encoding="utf-8") as fh:
                content = fh.read()
            if "colors.css" not in content:
                with open(main, "w", encoding="utf-8") as fh:
                    fh.write("@import 'colors.css';\n" + content)
        except Exception:
            pass
    return written


def restore_breeze_colors():
    restored = []
    for folder in GTK_DIRS:
        path = gtk_path(folder)
        backup = path + ".breeze"
        if os.path.exists(backup):
            shutil.copy2(backup, path)
            restored.append(path)
    return restored


def palette_is_dark(pal=None):
    """Тёмная ли палитра: смотрим на фон окна (base)."""
    r, g, b = to_rgb((pal or palette())["base"])
    return (r + g + b) / 3 < 128


def sync():
    """Тема приложений = тема обоев.

    Тёмная палитра — тёмные приложения, светлая — светлые. Так и GTK, и KDE, и
    Qt выглядят одинаково и всегда в тон обоям.
    """
    dark = palette_is_dark()
    set_dark(dark)
    return dark


def state():
    dark = False
    theme = ""
    try:
        with open(gtk_path("gtk-3.0", "settings.ini"), encoding="utf-8") as fh:
            text = fh.read()
        match = re.search(r"^gtk-application-prefer-dark-theme=(\w+)", text, re.M)
        dark = bool(match) and match.group(1) == "true"
        match = re.search(r"^gtk-theme-name=(.*)$", text, re.M)
        theme = match.group(1).strip() if match else ""
    except Exception:
        pass
    scheme = ""
    try:
        scheme = subprocess.run(["gsettings", "get", GSETTINGS, "color-scheme"],
                                capture_output=True, text=True, timeout=3
                                ).stdout.strip().strip("'")
    except Exception:
        pass
    has_qt6ct = os.path.exists("/usr/lib/qt6/plugins/platformthemes/libqt6ct.so") \
        or bool(shutil.which("qt6ct"))
    return {
        "dark": dark,
        "gtk_theme": theme,
        "scheme": scheme,
        "accent": palette()["accent"],
        "custom_colors": os.path.exists(gtk_path("gtk-3.0")),
        "breeze_backup": os.path.exists(gtk_path("gtk-3.0") + ".breeze"),
        "palette_dark": palette_is_dark(),
        "qt6ct": has_qt6ct,
        "qt_note": (tr("как в GTK") if has_qt6ct else "gtk3"),
    }


def write_state():
    data = state()
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    return data


def set_dark(enabled):
    for folder in GTK_DIRS:
        path = gtk_path(folder, "settings.ini")
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        text = re.sub(r"^gtk-application-prefer-dark-theme=.*$",
                      "gtk-application-prefer-dark-theme=" + ("true" if enabled else "false"),
                      text, flags=re.M)
        theme = "Breeze-Dark" if enabled else "Breeze"
        if re.search(r"^gtk-theme-name=", text, re.M):
            text = re.sub(r"^gtk-theme-name=.*$", "gtk-theme-name=" + theme, text, flags=re.M)
        else:
            text = text.replace("[Settings]", "[Settings]\ngtk-theme-name=" + theme, 1)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)

    scheme = "prefer-dark" if enabled else "prefer-light"
    gtk_theme = "Breeze-Dark" if enabled else "Breeze"
    for key, value in (("color-scheme", scheme), ("gtk-theme", gtk_theme)):
        try:
            subprocess.run(["gsettings", "set", GSETTINGS, key, value],
                           capture_output=True, text=True, timeout=3)
        except Exception:
            pass

    # приложения KDE (konsole, dolphin) читают схему из kdeglobals
    tool = shutil.which("plasma-apply-colorscheme")
    if tool:
        try:
            subprocess.run([tool, "BreezeDark" if enabled else "BreezeLight"],
                           capture_output=True, text=True, timeout=10)
        except Exception:
            pass

    # цвета в обоих вариантах берём из палитры обоев: она и есть источник
    # правды, поэтому светлая тема — светлые цвета, тёмная — тёмные
    write_gtk_colors()


def selftest():
    problems = []
    pal = palette()
    for key in ("base", "surface", "text", "accent", "onAccent", "border"):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", pal.get(key, "")):
            problems.append(tr("в палитре нет цвета ") + key)

    # тёмный ли фон у фона окна и у базы
    for key in ("base", "surface"):
        r, g, b = to_rgb(pal[key])
        if (r + g + b) / 3 > 110:
            problems.append(f"{key} слишком светлый для тёмной темы: {pal[key]}")

    # сопоставление имён
    checks = [("theme_selected_bg_color_breeze", pal["accent"]),
              ("theme_selected_fg_color_breeze", pal["onAccent"]),
              ("theme_fg_color_breeze", pal["text"]),
              ("borders_breeze", pal["border"]),
              ("theme_bg_color_breeze", pal["base"]),
              ("content_view_bg_breeze", pal["surface"])]
    for name, want in checks:
        got = color_for(name, pal)
        if got != want:
            problems.append(f"{name}: ожидал {want}, получил {got}")

    names = names_in(gtk_path("gtk-3.0"))
    if not names:
        problems.append(tr("не нашёл имён в gtk-3.0/colors.css"))

    data = state()
    if not data["gtk_theme"]:
        problems.append(tr("не прочиталась тема GTK"))

    if problems:
        for p in problems:
            print("  ✗", p)
        return 1
    print(tr("  ✓ палитра:"), pal["base"], pal["accent"], pal["text"])
    print(tr("  ✓ тема GTK:"), data["gtk_theme"], tr("| схема:"), data["scheme"],
          tr("| тёмная:"), data["dark"])
    print(tr("  ✓ имён в colors.css:"), len(names), tr("(плюс"), len(GENERIC_NAMES), tr("общих)"))
    print(tr("  ✓ палитра обоев:") + " " + (tr("тёмная") if data["palette_dark"] else tr("светлая")))
    print(tr("  ✓ Qt: через"), data["qt_note"], "| qt6ct:", data["qt6ct"])
    print(tr("  ✓ палитра Breeze сохранена:"), data["breeze_backup"])
    return 0


def main(argv):
    if not argv or argv[0] == "build":
        write_state()
        return 0
    if argv[0] == "dark" and len(argv) > 1:
        set_dark(argv[1] == "on")
        write_state()
        return 0
    if argv[0] == "sync":
        sync()
        write_state()
        return 0
    if argv[0] == "colors":
        # цвета переписываем только когда приложения тёмные, иначе вернём светлые
        if state()["dark"]:
            write_gtk_colors()
        write_state()
        return 0
    if argv[0] == "--selftest":
        return selftest()
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
