#!/usr/bin/env bash
# Обои из командной строки.
#
#   wallpaper.sh list [фильтр]      — список файлов (фильтр: red|green|blue|mono|...)
#   wallpaper.sh random [фильтр]    — случайные обои
#   wallpaper.sh next | prev        — следующее / предыдущее по списку
#   wallpaper.sh set <файл> [переход]  — поставить конкретный файл
#   wallpaper.sh theme [файл]       — перекрасить в текущем режиме оформления
#   wallpaper.sh scheme [id|list]   — выбрать схему оформления (list — список схем)
#   wallpaper.sh index              — обновить список и превью
#
# Переходы: fade | wipe | circle | circle:X:Y (доли экрана) | random

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="$HOME/.cache/wallpaper"
INDEX="$CACHE/index.json"
STATE="$HERE/state.sh"
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Wallpapers}"

build_index() {
    python3 "$HERE/index-wallpapers.py" "$WALLPAPER_DIR" >/dev/null 2>&1 || true
}

list_paths() {
    local filter="${1:-}"
    [ -f "$INDEX" ] || build_index
    [ -f "$INDEX" ] || return 0
    if [ -n "$filter" ]; then
        jq -r --arg b "$filter" '.items[] | select(.bucket == $b) | .path' "$INDEX"
    else
        jq -r '.items[].path' "$INDEX"
    fi
}

current_path() {
    local mon
    mon=$(swaymsg -t get_outputs 2>/dev/null | jq -r '[.[] | select(.focused)][0].name' 2>/dev/null)
    [ -z "$mon" ] && mon=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
    [ -n "$mon" ] && cat "$CACHE/current_$mon" 2>/dev/null
}

apply() { # apply <файл> [переход]
    local file="$1"
    local trans="${2:-random}"
    [ -f "$file" ] || { echo "wallpaper.sh: нет файла '$file'" >&2; exit 1; }
    qs ipc call wallpaper set all "$file" "$trans" >/dev/null 2>&1 || {
        echo "wallpaper.sh: quickshell не отвечает" >&2
        exit 1
    }
    echo "$(basename "$file")"
}

case "${1:-}" in
list)
    list_paths "${2:-}"
    ;;
index)
    build_index
    jq -r '"обоев: \(.items | length)"' "$INDEX" 2>/dev/null
    ;;
random)
    mapfile -t all < <(list_paths "${2:-}")
    [ "${#all[@]}" -eq 0 ] && { echo "wallpaper.sh: список обоев пуст" >&2; exit 1; }
    cur="$(current_path)"
    pick=""
    for _ in 1 2 3 4 5 6; do
        pick="${all[$((RANDOM % ${#all[@]}))]}"
        [ "$pick" != "$cur" ] && break
    done
    apply "$pick" random
    ;;
next | prev)
    mapfile -t all < <(list_paths "${2:-}")
    n="${#all[@]}"
    [ "$n" -eq 0 ] && { echo "wallpaper.sh: список обоев пуст" >&2; exit 1; }
    cur="$(current_path)"
    cur_name="$(basename "$cur" 2>/dev/null)"
    idx=-1
    for i in "${!all[@]}"; do
        [ "$(basename "${all[$i]}")" = "$cur_name" ] && idx=$i && break
    done
    if [ "$1" = "next" ]; then
        idx=$(((idx + 1) % n))
    else
        idx=$(((idx <= 0 ? n : idx) - 1))
    fi
    apply "${all[$idx]}" random
    ;;
set)
    apply "${2:-}" "${3:-random}"
    ;;
theme)
    img="${2:-$(current_path)}"
    [ -f "$img" ] || { echo "wallpaper.sh: нет файла '$img'" >&2; exit 1; }
    "$HERE/theme-gen.sh" "$img"
    ;;
scheme)
    if [ -z "${2:-}" ] || [ "$2" = "list" ]; then
        "$HERE/theme-gen.sh" --list
        echo
        echo "текущий режим: $("$HERE/theme-gen.sh" --current)"
    else
        "$HERE/theme-gen.sh" --mode "$2"
    fi
    ;;
*)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
