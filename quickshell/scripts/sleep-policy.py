#!/usr/bin/env python3
"""Сон по простою: как в Windows — отдельно от сети и от батареи.

    sleep-policy.py state                 — настройки и текущий источник питания
    sleep-policy.py set ac_minutes 30     — засыпать через 30 минут от сети (0 = никогда)
    sleep-policy.py set battery_minutes 0 — от батареи не засыпать
    sleep-policy.py watch                 — сторож: следит за простоем и усыпляет машину

Собственный сон не нужен: этим занимается logind (IdleAction=suspend). Мы его
не мешаем — блокируем только его собственный «сон по простою»
(systemd-inhibit --what=idle:sleep), а решаем сами: так можно задать разные
пороги для сети и для батареи и не засыпать вовсе.

Простой берём у logind (IdleSinceHint) — это то же самое, что считает swayidle.

Настройки: ~/.config/quickshell/sleep.json
"""
import json
import os
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
FILE = f"{HOME}/.config/quickshell/sleep.json"
DEFAULTS = {"ac_minutes": 0, "battery_minutes": 0}


def load():
    data = dict(DEFAULTS)
    try:
        with open(FILE, encoding="utf-8") as fh:
            saved = json.load(fh)
        if isinstance(saved, dict):
            for key in DEFAULTS:
                if key in saved:
                    try:
                        data[key] = max(0, min(600, int(saved[key])))
                    except (TypeError, ValueError):
                        pass
    except Exception:
        pass
    return data


def save(data):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    tmp = f"{FILE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, FILE)


def on_ac():
    """Питание от сети? Смотрим, есть ли внешний адаптер."""
    base = "/sys/class/power_supply"
    try:
        for name in os.listdir(base):
            path = os.path.join(base, name, "type")
            try:
                with open(path, encoding="utf-8") as fh:
                    if fh.read().strip() != "Mains":
                        continue
            except OSError:
                continue
            online = os.path.join(base, name, "online")
            try:
                with open(online, encoding="utf-8") as fh:
                    if fh.read().strip() == "1":
                        return True
            except OSError:
                pass
    except OSError:
        pass
    return False


def idle_seconds():
    """Сколько секунд nobody не трогал ввод (logind)."""
    session = os.environ.get("XDG_SESSION_ID") or ""
    if not session:
        return 0
    try:
        out = subprocess.run(
            ["loginctl", "show-session", session, "-p", "IdleSinceHint", "--value"],
            capture_output=True, text=True, timeout=4).stdout.strip()
    except Exception:
        return 0
    if not out or out.lower().startswith("n/a"):
        return 0
    try:
        stamp = time.mktime(time.strptime(out, "%Y-%m-%d %H:%M:%S"))
    except Exception:
        return 0
    return max(0, int(time.time() - stamp))


def state():
    data = load()
    ac = on_ac()
    return {
        "ok": True,
        "ac_minutes": data["ac_minutes"],
        "battery_minutes": data["battery_minutes"],
        "source": "ac" if ac else "battery",
        "idle_seconds": idle_seconds(),
    }


def watch():
    """Сторож: уснём, когда простой перевалит за порог для текущего питания."""
    while True:
        time.sleep(30)
        data = load()
        minutes = data["ac_minutes"] if on_ac() else data["battery_minutes"]
        if minutes <= 0:
            continue
        if idle_seconds() >= minutes * 60:
            subprocess.run(["systemctl", "suspend"], check=False)
            time.sleep(30)


def main(argv):
    if not argv or argv[0] == "state":
        print(json.dumps(state(), ensure_ascii=False))
        return 0
    if argv[0] == "set" and len(argv) >= 3:
        key, value = argv[1], argv[2]
        data = load()
        if key in ("ac_minutes", "battery_minutes"):
            try:
                data[key] = max(0, min(600, int(float(value))))
            except ValueError:
                return 2
        else:
            return 2
        save(data)
        print(json.dumps(state(), ensure_ascii=False))
        return 0
    if argv[0] == "watch":
        watch()
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
