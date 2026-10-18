#!/usr/bin/env python3
"""Спектр-визуализатор для waybar.

Читает монитор текущего sink'а через parec, считает БПФ по кадрам и печатает
по строке на кадр (waybar custom-модуль без interval читает stdout построчно).
Когда звука нет — печатает пустую строку, и модуль прячется (hide-empty-text).
"""
import os
import subprocess
import sys
import time

import numpy as np

RATE = 48000
CHANNELS = 2
SAMPLE_BYTES = 2          # s16le
FFT_SIZE = 2048           # ~23 кадра/с
FRAME = FFT_SIZE * CHANNELS * SAMPLE_BYTES
BARS = 12
BLOCKS = "▁▂▃▄▅▆▇█"       # 8 уровней высоты
GAP = "\u2009"            # тонкий пробел: столбики читаются по отдельности
F_MIN, F_MAX = 45.0, 15000.0
DB_FLOOR, DB_CEIL = -70.0, -6.0
DECAY = 0.72              # насколько быстро падают столбики
SILENCE = 0.02


def default_monitor():
    try:
        out = subprocess.run(["pactl", "get-default-sink"], capture_output=True,
                             text=True, timeout=2).stdout.strip()
        if out:
            return out + ".monitor"
    except Exception:
        pass
    return "@DEFAULT_MONITOR@"


def spawn_capture():
    return subprocess.Popen(
        ["parec", "--device=" + default_monitor(), "--format=s16le",
         "--rate=%d" % RATE, "--channels=%d" % CHANNELS, "--latency-msec=40"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def band_edges():
    edges = np.geomspace(F_MIN, F_MAX, BARS + 1)
    bin_hz = RATE / FFT_SIZE
    return np.clip((edges / bin_hz).astype(int), 0, FFT_SIZE // 2 - 1)


def main():
    window = np.hanning(FFT_SIZE)
    norm = window.sum() / 2.0
    edges = band_edges()
    levels = np.zeros(BARS)
    proc = spawn_capture()
    idle = True

    while True:
        data = proc.stdout.read(FRAME)
        if data is None or len(data) < FRAME:
            proc.kill()
            proc.wait()
            time.sleep(0.5)
            levels[:] = 0.0
            proc = spawn_capture()
            continue

        x = np.frombuffer(data, dtype="<i2").reshape(-1, CHANNELS)
        x = x.mean(axis=1).astype(np.float64) / 32768.0
        spec = np.abs(np.fft.rfft(x * window)) / norm
        db = 20.0 * np.log10(spec + 1e-9)

        cur = np.empty(BARS)
        for i in range(BARS):
            cur[i] = db[edges[i]:max(edges[i + 1], edges[i] + 1)].max()
        cur = np.clip((cur - DB_FLOOR) / (DB_CEIL - DB_FLOOR), 0.0, 1.0)
        levels = np.maximum(cur, levels * DECAY)

        if levels.max() < SILENCE:
            levels[:] = 0.0
            if not idle:
                sys.stdout.write("\n")
                sys.stdout.flush()
                idle = True
            continue

        idle = False
        sys.stdout.write(GAP.join(BLOCKS[min(7, int(v * 7.999))] for v in levels) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except BrokenPipeError:
        # пайп закрылся (waybar перезапустил модуль) — выходим без трейсбека
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        sys.exit(0)
