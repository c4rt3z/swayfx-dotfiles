#!/usr/bin/env bash
# Гифка → mp4 для движка обоев.
#
# Зачем: Qt не анимирует gif в обычном Image (показывает первый кадр), а
# AnimatedImage держит в памяти все кадры — для 1280×720×50 это ~180 МБ.
# Поэтому гифку один раз перегоняем в mp4 и играем штатным видеотрактом
# (поток, ~20 МБ), он же умеет бесшовный цикл.
#
#   gif-cache.sh <гифка>   — печатает путь к mp4, собирая его при необходимости
#
# Кеш: ~/.cache/wallpaper/gif/<путь-через-подчёркивания>.mp4
# Пересобирается, если гифка новее кеша.

set -u

src="${1:-}"
[ -f "$src" ] || { echo "gif-cache.sh: нет файла '$src'" >&2; exit 1; }

cache="$HOME/.cache/wallpaper/gif"
key="$(printf '%s' "$src" | sed 's|[^A-Za-z0-9]\+|_|g; s|^_*||; s|_*$||')"
out="$cache/$key.mp4"

if [ -s "$out" ] && [ "$out" -nt "$src" ]; then
    printf '%s\n' "$out"
    exit 0
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "gif-cache.sh: нет ffmpeg" >&2; exit 2; }

mkdir -p "$cache"
if nice -n 10 ffmpeg -y -v error -i "$src" -an \
        -c:v libx264 -preset veryfast -crf 25 -pix_fmt yuv420p \
        -movflags +faststart "$out" >/dev/null 2>&1 && [ -s "$out" ]; then
    printf '%s\n' "$out"
    exit 0
fi

rm -f "$out"
echo "gif-cache.sh: не удалось собрать '$src'" >&2
exit 3
