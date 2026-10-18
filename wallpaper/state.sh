#!/usr/bin/env bash
# Состояние обоев: что стоит на каждом мониторе, плюс история.
#
#   state.sh set <монитор> <файл>   — запомнить обои для монитора
#                                     (картинка копируется в кэш, видео — нет)
#   state.sh get <монитор>          — вывести текущий файл для монитора
#   state.sh history [N]            — история имён (свежие сверху)
#
# Кэш: ~/.cache/wallpaper/

set -u

CACHE="$HOME/.cache/wallpaper"
mkdir -p "$CACHE"

case "${1:-}" in
set)
    MON="${2:-}"
    SRC="${3:-}"
    if [ -z "$MON" ] || [ -z "$SRC" ] || [ ! -e "$SRC" ]; then
        echo "state.sh set: нет файла '$SRC'" >&2
        exit 1
    fi
    NAME=$(basename "$SRC")
    EXT="${NAME##*.}"
    case "$EXT" in
    mp4 | MP4 | mkv | MKV | mov | MOV | webm | WEBM)
        # видео не копируем — оно может быть большим
        DEST="$SRC"
        ;;
    *)
        DEST="$CACHE/current_${MON}.${EXT}"
        cp -f "$SRC" "$DEST" 2>/dev/null || DEST="$SRC"
        ;;
    esac
    printf '%s' "$DEST" >"$CACHE/current_$MON"
    printf '%s' "$SRC" >"$CACHE/current_${MON}_src"
    printf '%s' "$NAME" >"$CACHE/current_${MON}_name"
    # заодно снимок для темы и превью пикера
    if [ "$EXT" != "gif" ] && [ "$EXT" != "GIF" ]; then
        cp -f "$SRC" "$CACHE/current.png" 2>/dev/null || true
    fi
    # история
    HIST="$CACHE/history"
    if [ -f "$HIST" ]; then
        grep -v -F -x "$NAME" "$HIST" >"$HIST.tmp" 2>/dev/null || true
        printf '%s\n' "$NAME" | cat - "$HIST.tmp" >"$HIST"
        rm -f "$HIST.tmp"
    else
        printf '%s\n' "$NAME" >"$HIST"
    fi
    # обои рисует quickshell; если от прошлой настройки остался swaybg,
    # он перекроет слой обоев — гасим, чтобы смена была видна сразу
    pkill -x swaybg 2>/dev/null || true
    ;;
get)
    MON="${2:-}"
    [ -n "$MON" ] && [ -f "$CACHE/current_$MON" ] && cat "$CACHE/current_$MON"
    ;;
history)
    [ -f "$CACHE/history" ] && head -n "${2:-60}" "$CACHE/history"
    ;;
*)
    echo "usage: state.sh {set <монитор> <файл> | get <монитор> | history [N]}" >&2
    exit 1
    ;;
esac
