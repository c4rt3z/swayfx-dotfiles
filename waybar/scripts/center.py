#!/usr/bin/env python3
"""Центральный модуль waybar — музыка.

Что показывает:
  * играет            ->  ♪ Артист — Трек;
  * пауза             ->  то же, но притушено (Pango alpha);
  * нечего играть     ->  «ничего не играет» притушено.

Заголовок окна здесь больше не живёт — он вынесен в левый край бара
(scripts/window-title.py).

Источник — MPRIS через playerctl (опрос). Строка печатается только при
изменении: waybar custom-модуль читает stdout построчно. Вывод экранируется:
waybar разбирает его как Pango-разметку, поэтому dim() собирает разметку уже
после escape().
"""
import subprocess
import sys
import threading
import time
from xml.sax.saxutils import escape
from i18n import tr

POLL = 0.5              # период опроса плеера, с
RENDER = 0.2            # период отрисовки, с
ICON = "\U000F075A"     # музыкальная нота (Nerd Font)
DASH = "—"
# строку берём на каждой отрисовке: i18n перечитывает язык, если файл
# языка изменился, поэтому бар не надо перезапускать после смены языка
def nothing():
    return tr("ничего не играет")
DIM_ALPHA = "60%"       # насколько притушить паузу и «ничего не играет»

lock = threading.Lock()
# status = None, пока не пришёл первый опрос: до этого ничего не печатаем,
# иначе на старте мелькало бы «ничего не играет».
state = {"status": None, "track": ""}


def write_line(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def dim(text):
    return '<span alpha="' + DIM_ALPHA + '">' + text + "</span>"


def run_quiet(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return ""


def parse_player(out):
    """Строка playerctl -> (состояние, «Артист — Трек») или None, если данных нет."""
    parts = out.rstrip("\n").split("\t")
    if len(parts) < 3:
        return None
    status = parts[0].strip()
    artist, title = parts[1].strip(), parts[2].strip()
    if artist and title:
        track = artist + " " + DASH + " " + title
    else:
        track = title or artist
    return status, track


def active_player_state():
    """Состояние активного плеера.

    Как во встроенном модуле mpris: сначала спрашиваем playerctld (он сам решает,
    какой плеер «текущий»). Если демона нет, а плееров несколько, playerctl без
    -p ругается — тогда перебираем список и берём тот, что играет.
    """
    fmt = ["metadata", "--format", "{{status}}\t{{artist}}\t{{title}}"]
    for args in (["-p", "playerctld"], []):
        res = parse_player(run_quiet(["playerctl"] + args + fmt))
        if res is not None:
            return res
    for name in run_quiet(["playerctl", "-l"]).split():
        res = parse_player(run_quiet(["playerctl", "-p", name] + fmt))
        if res is not None and res[0]:
            return res
    return "", ""


def watch_player():
    while True:
        status, track = active_player_state()
        with lock:
            state["status"] = status
            state["track"] = track
        time.sleep(POLL)


def main():
    threading.Thread(target=watch_player, daemon=True).start()

    last = None
    while True:
        with lock:
            status, track = state["status"], state["track"]
        if status is None:            # первый опрос ещё не пришёл
            time.sleep(RENDER)
            continue
        if track and status == "Playing":
            line = ICON + " " + escape(track)
        elif track:
            line = dim(ICON + " " + escape(track))
        else:
            line = dim(nothing())
        if line != last:
            write_line(line)
            last = line
        time.sleep(RENDER)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except BrokenPipeError:
        sys.exit(0)
