#!/bin/sh
# Сводка о системе для главной страницы меню настроек quickshell.
#
# Печатает по строке на пункт:  ключ<TAB>значение.
# Всё, что не удалось узнать, просто не печатается — страница показывает то,
# что есть, без «неизвестно».

key() {
    printf '%s\t%s\n' "$1" "$2"
}

first_line() {
    head -n 1
}

# ── язык ─────────────────────────────────────────────────────────────────────
# Ключи (ОС, Ядро, …) переводит панель через Lang.t, а значения собираются здесь —
# поэтому единицы измерения берём из того же файла языка.

lang=$(head -n 1 "$HOME/.config/quickshell/language" 2>/dev/null | tr -d '[:space:]')
[ -n "$lang" ] || lang=ru

case "$lang" in
en) u_gib="GiB"; u_of="of"; u_hz="Hz"; u_day="d"; u_hour="h"; u_min="min" ;;
uk) u_gib="ГіБ"; u_of="з"; u_hz="Гц"; u_day="д"; u_hour="год"; u_min="хв" ;;
de) u_gib="GiB"; u_of="von"; u_hz="Hz"; u_day="T"; u_hour="Std"; u_min="Min" ;;
*) u_gib="ГиБ"; u_of="из"; u_hz="Гц"; u_day="д"; u_hour="ч"; u_min="мин" ;;
esac

# ── система ──────────────────────────────────────────────────────────────────

os=$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
[ -n "$os" ] || os=$(uname -s)
key "ОС" "$os"

key "Ядро" "$(uname -r)"

board=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
[ -n "$board" ] || board=$(hostname 2>/dev/null)
[ -n "$board" ] && key "Машина" "$board"

# ── железо ───────────────────────────────────────────────────────────────────

cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
[ -n "$cpu" ] || cpu=$(uname -m)
key "Процессор" "$cpu"

gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | first_line \
      | sed 's/.*: //; s/ (rev .*)//; s/\[[^]]*\]//g; s/  */ /g; s/ $//')
[ -n "$gpu" ] && key "Видео" "$gpu"

mem=$(awk -v u="$u_gib" '/^MemTotal/ {printf "%.1f %s", $2 / 1048576, u}' /proc/meminfo 2>/dev/null)
[ -n "$mem" ] && key "Память" "$mem"

disk=$(df -h / 2>/dev/null | awk -v w="$u_of" 'NR==2 {print $3 " " w " " $2 "  (" $5 ")"}')
[ -n "$disk" ] && key "Диск" "$disk"

# ── окружение ────────────────────────────────────────────────────────────────

screen=$(swaymsg -t get_outputs 2>/dev/null | python3 -c '
import json, sys
hz_unit = sys.argv[1] if len(sys.argv) > 1 else "Гц"
try:
    outs = json.load(sys.stdin)
except Exception:
    sys.exit()
for o in outs:
    if not o.get("focused"):
        continue
    model = (o.get("make", "") + " " + o.get("model", "")).strip()
    mode = o.get("current_mode") or {}
    w, h = mode.get("width"), mode.get("height")
    hz = mode.get("refresh")
    size = "%sx%s" % (w, h) if w and h else ""
    rate = " @ %d %s" % (round(hz / 1000), hz_unit) if hz else ""
    print("%s%s%s%s" % (model, " — " if model and size else "", size, rate))
    break
' "$u_hz")
[ -n "$screen" ] && key "Экран" "$screen"

compositor=$(swaymsg -t get_version 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit()
hr = d.get("human_readable", "")
orig = d.get("sway_original_version", "")
if orig and hr and hr != orig:
    print("SwayFX %s (sway %s)" % (hr, orig))
elif hr or orig:
    print("sway %s" % (hr or orig))
')
[ -n "$compositor" ] && key "Композитор" "$compositor"

bar=$(waybar --version 2>/dev/null | sed 's/^Waybar v//')
[ -n "$bar" ] && key "Панель" "waybar $bar"

shell=$(qs --version 2>/dev/null | sed -n 's/.*Quickshell \([0-9][0-9.]*\).*/\1/p')
[ -n "$shell" ] && key "Оболочка" "quickshell $shell"

[ -n "${SHELL:-}" ] && key "Shell" "$(basename "$SHELL")"

# ── время работы и пакеты ────────────────────────────────────────────────────

secs=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
if [ -n "$secs" ]; then
    d=$((secs / 86400))
    h=$(((secs % 86400) / 3600))
    m=$(((secs % 3600) / 60))
    if [ "$d" -gt 0 ]; then
        uptime_str="$d $u_day $h $u_hour"
    elif [ "$h" -gt 0 ]; then
        uptime_str="$h $u_hour $m $u_min"
    else
        uptime_str="$m $u_min"
    fi
    key "Включён" "$uptime_str"
fi

pkgs=$(pacman -Qq 2>/dev/null | wc -l)
[ "${pkgs:-0}" -gt 0 ] && key "Пакетов" "$pkgs"
