#!/bin/sh
# Текст песни для панели плеера (quickshell).
#
#   lyrics.sh "<название>" "<исполнитель>"
#
# Источник — lrclib.net: открытый API текстов, ключ не нужен, умеет
# синхронизированный (LRC) текст. Результат кэшируется в
# ~/.cache/quickshell/lyrics/; если синхронизации нет, отдаётся простой текст.
# Пустой вывод — текста нет.
#
# Внимание: название и исполнитель уходят в lrclib. Чтобы этого не было —
# удалите или переименуйте этот файл (панель покажет «источник отключён»).
set -u

title="${1:-}"
artist="${2:-}"
[ -n "$title" ] || exit 1

CACHE="$HOME/.cache/quickshell/lyrics"
mkdir -p "$CACHE"
key="$(printf '%s|%s' "$title" "$artist" | md5sum | cut -d' ' -f1)"
file="$CACHE/$key.lrc"
[ -s "$file" ] && { cat "$file"; exit 0; }

out="$(curl -sS --max-time 12 -G "https://lrclib.net/api/get" \
    --data-urlencode "track_name=$title" \
    --data-urlencode "artist_name=$artist" \
    -H 'User-Agent: quickshell-music-panel/1.0' 2>/dev/null)"
[ -n "$out" ] || exit 0

synced="$(printf '%s' "$out" | jq -r '.syncedLyrics // empty' 2>/dev/null)"
plain="$(printf '%s' "$out" | jq -r '.plainLyrics // empty' 2>/dev/null)"

if [ -n "$synced" ] && [ "$synced" != "null" ]; then
    printf '%s\n' "$synced" >"$file"
else
    printf '%s\n' "$plain" >"$file"
fi
cat "$file"
