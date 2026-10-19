#!/usr/bin/env python3
"""Звук: устройства, профили, громкость и эквалайзер (EasyEffects).

    audio.py state                     — всё состояние одной строкой JSON
    audio.py sink <устройство>         — сделать устройство выводом по умолчанию
    audio.py profile <карта> <профиль> — профиль звуковой карты
    audio.py volume <0..150>           — громкость вывода
    audio.py mute on|off|toggle        — выключить/включить звук
    audio.py ee start|stop             — запустить/остановить службу EasyEffects
    audio.py preset <имя>              — загрузить пресет эквалайзера
    audio.py bypass on|off|toggle      — обход эффектов
    audio.py open                      — открыть окно EasyEffects

Эквалайзер не свой: пресеты, обход и служба — это всё EasyEffects
(easyeffects --service-mode). Пресеты лежат в ~/.local/share/easyeffects/output;
если список пуст, страница «Звук» предлагает открыть EasyEffects и добавить их
там (или скачать набор из сообщества — ссылка в README).

Состояние читаем из pactl (-f json) и самого easyeffects, ничего своего не
храним: так панель не расходится с системами.
"""
import json
import os
import re
import signal
import subprocess
import sys

HOME = os.path.expanduser("~")
EE = "com.github.wwmm.easyeffects"
PRESET_DIRS = (
    f"{HOME}/.local/share/easyeffects/output",
    "/usr/share/easyeffects/output",
)
ENV = dict(os.environ, LC_ALL="C")


def run(args, timeout=4):
    """Запустить команду и вернуть stdout (пусто, если что-то пошло не так)."""
    try:
        done = subprocess.run(args, capture_output=True, text=True,
                              timeout=timeout, env=ENV)
        return done.stdout or ""
    except Exception:
        return ""


def pactl_json(what):
    raw = run(["pactl", "-f", "json", "list", what])
    try:
        data = json.loads(raw or "[]")
    except Exception:
        return []
    return data if isinstance(data, list) else [data]


def ee_running():
    return bool(run(["pgrep", "-x", "easyeffects"]).strip())


def ee_service():
    """Служба EasyEffects (клиент общается с ней по DBus)."""
    if ee_running():
        return True
    subprocess.Popen(["setsid", "-f", "easyeffects", "--service-mode"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    return True


def ee_stop():
    subprocess.run(["pkill", "-x", "easyeffects"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ee_presets():
    """Имена пресетов вывода. Спрашиваем сам easyeffects, иначе — файлы."""
    if ee_running():
        out = run(["easyeffects", "--presets"], timeout=6)
        names = []
        section = ""
        for line in out.splitlines():
            low = line.strip().lower()
            if not low:
                continue
            if "presets" in low:
                section = "out" if low.startswith("output") else (
                    "in" if low.startswith("input") else section)
                continue
            if section == "out":
                names.append(line.strip())
        if names:
            return names
    names = []
    for folder in PRESET_DIRS:
        try:
            for name in sorted(os.listdir(folder)):
                if name.endswith(".json"):
                    names.append(name[:-5])
        except OSError:
            continue
    return names


def ee_current():
    """Какой вывод и пресет загружены сейчас."""
    if not ee_running():
        return {"service": False, "bypass": False, "presets": [], "preset": ""}
    raw = run(["easyeffects", "--last-loaded-presets"], timeout=6)
    preset = ""
    for line in raw.splitlines():
        if line.strip().lower().startswith("output:"):
            preset = line.split(":", 1)[1].strip()
    bypass_raw = run(["easyeffects", "--bypass", "3"], timeout=6).strip()
    return {
        "service": True,
        "bypass": bypass_raw == "1",
        "presets": ee_presets(),
        "preset": preset,
    }


def sinks():
    default = run(["pactl", "get-default-sink"]).strip()
    out = []
    for item in pactl_json("sinks"):
        name = item.get("name") or ""
        volume = item.get("volume") or {}
        percent = 0
        for channel in volume.values():
            if isinstance(channel, dict) and "value_percent" in channel:
                try:
                    percent = int(str(channel["value_percent"]).rstrip("%"))
                except ValueError:
                    percent = 0
                break
        out.append({
            "name": name,
            "desc": item.get("description") or name,
            "default": name == default,
            "volume": percent,
            "muted": bool(item.get("mute")),
        })
    return out, default


def cards():
    out = []
    for item in pactl_json("cards"):
        profiles = []
        for key, value in (item.get("profiles") or {}).items():
            if not isinstance(value, dict):
                continue
            desc = value.get("description")
            if not desc or desc == "(null)":
                desc = key
            profiles.append({
                "name": key,
                "desc": desc,
                "available": value.get("available", True),
            })
        out.append({
            "name": item.get("name") or "",
            "desc": item.get("description") or "",
            "profile": item.get("active_profile") or "",
            "profiles": profiles,
        })
    return out


def state():
    list_, default = sinks()
    default_sink = next((s for s in list_ if s["name"] == default), None)
    return {
        "ok": True,
        "sink": default,
        "sinks": list_,
        "volume": default_sink["volume"] if default_sink else 0,
        "muted": default_sink["muted"] if default_sink else False,
        "cards": cards(),
        "ee": ee_current(),
    }


def main(argv):
    if not argv or argv[0] == "state":
        print(json.dumps(state(), ensure_ascii=False))
        return 0

    cmd = argv[0]

    if cmd == "sink" and len(argv) > 1:
        run(["pactl", "set-default-sink", argv[1]])
    elif cmd == "profile" and len(argv) > 2:
        run(["pactl", "set-card-profile", argv[1], argv[2]])
    elif cmd == "volume" and len(argv) > 1:
        try:
            value = max(0, min(150, int(float(argv[1]))))
        except ValueError:
            return 2
        run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{value}%"])
    elif cmd == "mute" and len(argv) > 1:
        how = argv[1]
        if how == "toggle":
            run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"])
        else:
            run(["pactl", "set-sink-mute", "@DEFAULT_SINK@",
                 "1" if how == "on" else "0"])
    elif cmd == "ee" and len(argv) > 1:
        if argv[1] == "start":
            ee_service()
            return 0
        if argv[1] == "stop":
            ee_stop()
        else:
            return 2
    elif cmd == "preset" and len(argv) > 1:
        ee_service()
        name = " ".join(argv[1:])
        run(["easyeffects", "--load-preset", name], timeout=12)
    elif cmd == "bypass" and len(argv) > 1:
        how = argv[1]
        if not ee_running():
            ee_service()
        if how == "toggle":
            code = "1" if run(["easyeffects", "--bypass", "3"],
                              timeout=6).strip() != "1" else "2"
        else:
            code = "1" if how == "on" else "2"
        run(["easyeffects", "--bypass", code], timeout=6)
    elif cmd == "open":
        subprocess.Popen(["setsid", "-f", "easyeffects"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return 0
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 1

    print(json.dumps(state(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
