#!/usr/bin/env python3
"""Проверка целостности дотфайлов: doctor.

    doctor.py            — всё проверить и напечатать отчёт
    doctor.py --quiet    — только итог (код возврата: 0 — всё в порядке)

Проверяем то, что обычно разъезжается при правках и переездах на другую
машину:

  • словари переводов: одинаковый набор ключей;
  • выбранные шрифты и тема значков установлены;
  • скрипты quickshell на месте и исполняемые;
  • синглтоны quickshell прописаны в qmldir;
  • состояние (сайдбар, анимации, шрифты, погода, бар, сон) — валидный JSON;
  • модули waybar, которые мы сами включали, есть в конфиге.
"""
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
CFG = f"{HOME}/.config"
QS = f"{CFG}/quickshell"

STATE_FILES = (
    f"{QS}/sidebar.json",
    f"{QS}/animations.json",
    f"{QS}/fonts.json",
    f"{QS}/weather.json",
    f"{QS}/sleep.json",
    f"{QS}/emoji.json",
    f"{CFG}/waybar/mode",
    f"{QS}/language",
)

ok_count = 0
fail_count = 0


def good(msg):
    global ok_count
    ok_count += 1
    print(f"  \033[32m✓\033[0m {msg}")


def bad(msg):
    global fail_count
    fail_count += 1
    print(f"  \033[31m✗\033[0m {msg}")


def note(msg):
    print(f"  \033[33m•\033[0m {msg}")


def check_translations():
    print("Переводы")
    base = os.path.join(QS, "i18n")
    try:
        with open(os.path.join(base, "en.json"), encoding="utf-8") as fh:
            en = set(json.load(fh).keys())
    except Exception as exc:
        bad(f"не читается en.json: {exc}")
        return
    for code in ("uk", "de"):
        path = os.path.join(base, f"{code}.json")
        try:
            with open(path, encoding="utf-8") as fh:
                keys = set(json.load(fh).keys())
        except Exception as exc:
            bad(f"{code}.json: {exc}")
            continue
        missing = en - keys
        extra = keys - en
        if missing:
            bad(f"{code}.json: нет {len(missing)} ключей "
                f"({', '.join(sorted(missing)[:3])}…)")
        elif extra:
            note(f"{code}.json: {len(extra)} лишних ключей")
        else:
            good(f"{code}.json: ключи совпадают ({len(keys)})")


def fc_list():
    try:
        out = subprocess.run(["fc-list", ":", "family"], capture_output=True,
                             text=True, timeout=10).stdout
    except Exception:
        return set()
    names = set()
    for line in out.splitlines():
        for part in line.split(","):
            if part.strip():
                names.add(part.strip())
    return names


def check_fonts(families):
    print("Шрифты и значки")
    try:
        with open(f"{QS}/fonts.json", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = {}
    for key in ("ui", "waybar", "panels"):
        name = str(data.get(key) or "").strip()
        if not name:
            note(f"шрифт {key} не задан — берётся JetBrainsMono Nerd Font")
            continue
        if name in families:
            good(f"шрифт {key}: {name}")
        else:
            bad(f"шрифт {key} не установлен: {name}")
    try:
        out = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface",
                               "icon-theme"], capture_output=True, text=True,
                              timeout=5).stdout.strip().strip("'")
    except Exception:
        out = ""
    if not out:
        note("тема значков не выбрана")
    else:
        # темы значков лежат в папках, а не в списке шрифтов
        folders = (f"{HOME}/.local/share/icons", f"{HOME}/.icons", "/usr/share/icons")
        if any(os.path.isdir(os.path.join(d, out)) for d in folders):
            good(f"тема значков: {out}")
        else:
            bad(f"тема значков не установлена: {out}")


def check_scripts():
    print("Скрипты")
    folder = f"{QS}/scripts"
    if not os.path.isdir(folder):
        bad("нет папки со скриптами")
        return
    total = 0
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith((".py", ".sh")):
            continue
        total += 1
        path = os.path.join(folder, fn)
        # .py запускаем через python3, а вот шелл-скрипты — напрямую
        if fn.endswith(".sh") and not os.access(path, os.X_OK):
            bad(f"{fn} не исполняемый")
    if total:
        good(f"скриптов на месте: {total}")


def check_singletons():
    print("Синглтоны quickshell")
    folder = f"{QS}/singletons"
    try:
        with open(os.path.join(folder, "qmldir"), encoding="utf-8") as fh:
            text = fh.read()
    except Exception as exc:
        bad(f"не читается qmldir: {exc}")
        return
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith(".qml"):
            continue
        if fn not in text:
            bad(f"{fn} не прописан в qmldir")
    good("qmldir в порядке")


def check_state():
    print("Состояние")
    for path in STATE_FILES:
        name = os.path.basename(path)
        if not os.path.exists(path):
            note(f"{name}: пока нет (создастся сама)")
            continue
        if path.endswith(".json"):
            try:
                with open(path, encoding="utf-8") as fh:
                    json.load(fh)
                good(f"{name}: корректный JSON")
            except Exception as exc:
                bad(f"{name}: битый JSON — {exc}")
        else:
            good(f"{name}: есть")


def check_bar():
    print("Панель waybar")
    try:
        with open(f"{CFG}/waybar/config", encoding="utf-8") as fh:
            cfg = json.load(fh)
    except Exception as exc:
        bad(f"не читается waybar/config: {exc}")
        return
    modules = []
    for zone in ("left", "center", "right"):
        modules += cfg.get(f"modules-{zone}", [])
    wanted = {"custom/weather", "custom/clock", "custom/power"}
    missing = wanted - set(modules)
    if missing:
        note("модули выключены: " + ", ".join(sorted(missing)))
    else:
        good(f"модулей в панели: {len(modules)}")


def check_sway():
    print("Вспомогательные файлы")
    wanted = [
        f"{QS}/scripts/idle-lock.sh",
        f"{QS}/scripts/shot.py",
        f"{QS}/scripts/clipboard.py",
        f"{QS}/scripts/switcher.py",
        f"{QS}/scripts/weather.py",
        f"{QS}/scripts/apps-index.py",
        f"{QS}/scripts/search-engine.py",
        f"{QS}/scripts/autolock.sh",
        f"{QS}/scripts/sleep-policy.py",
        f"{CFG}/wallpaper/wallpaper.sh",
        f"{CFG}/wallpaper/theme-gen.sh",
        f"{CFG}/wallpaper/slideshow.sh",
        f"{CFG}/sway/fix-backlight.sh",
    ]
    missing = [p for p in wanted if not os.path.exists(p)]
    for path in missing:
        bad("нет файла: " + path.replace(HOME, "~"))
    if not missing:
        good(f"все на месте ({len(wanted)})")


def main():
    print("\n\033[1mПроверка дотфайлов\033[0m\n")
    families = fc_list()
    check_translations()
    check_fonts(families)
    check_scripts()
    check_singletons()
    check_state()
    check_bar()
    check_sway()
    print()
    if fail_count:
        print(f"\033[31mпроблем: {fail_count}\033[0m, "
              f"в порядке: {ok_count}")
        return 1
    print(f"\033[32mвсё в порядке\033[0m ({ok_count} проверок)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
