#!/usr/bin/env bash
# Слайд-шоу: обои меняются сами, без рук.
#
#   slideshow.sh on [минуты]   — включить (по умолчанию 15 минут)
#   slideshow.sh off           — выключить
#   slideshow.sh interval <м>  — сменить интервал
#   slideshow.sh toggle        — включить/выключить одним кликом
#   slideshow.sh status        — текущее состояние (JSON)
#   slideshow.sh next          — сменить обои прямо сейчас
#
# Состояние — ~/.config/wallpaper/slideshow.json. Его читает оболочка
# (shell.qml: FileView + Timer), поэтому таймер живёт в quickshell, а скрипт
# только пишет файл. Каждое действие печатает новый JSON, чтобы панель обоев
# показывала состояние сразу, не перечитывая файл.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="$HOME/.config/wallpaper/slideshow.json"
DEFAULT_MIN=15

state_json() { # state_json <on|off> <минуты>
    printf '{"on":%s,"minutes":%s}\n' "$1" "$2"
}

current() {
    if [ -f "$FILE" ]; then
        cat "$FILE"
    else
        state_json false "$DEFAULT_MIN"
    fi
}

cur_min() {
    local m
    m=$(jq -r '.minutes // empty' "$FILE" 2>/dev/null)
    case "$m" in
    '' | *[!0-9]*) m="$DEFAULT_MIN" ;;
    esac
    [ "$m" -lt 1 ] && m="$DEFAULT_MIN"
    echo "$m"
}

write() { # write <on|off> <минуты>
    mkdir -p "$(dirname "$FILE")"
    state_json "$1" "$2" >"$FILE.tmp.$$"
    mv "$FILE.tmp.$$" "$FILE"
    state_json "$1" "$2"
}

case "${1:-status}" in
on)
    m="${2:-$(cur_min)}"
    case "$m" in
    '' | *[!0-9]*) m="$DEFAULT_MIN" ;;
    esac
    write true "$m"
    ;;
off)
    write false "$(cur_min)"
    ;;
interval)
    m="${2:-$DEFAULT_MIN}"
    case "$m" in
    '' | *[!0-9]*) m="$DEFAULT_MIN" ;;
    esac
    on=false
    grep -q '"on":true' "$FILE" 2>/dev/null && on=true
    write "$on" "$m"
    ;;
toggle)
    if grep -q '"on":true' "$FILE" 2>/dev/null; then
        write false "$(cur_min)"
    else
        write true "$(cur_min)"
    fi
    ;;
next)
    "$HERE/wallpaper.sh" random >/dev/null 2>&1 || true
    current
    ;;
status)
    current
    ;;
*)
    echo "slideshow.sh: неизвестная команда '${1:-}'" >&2
    exit 1
    ;;
esac
