#!/usr/bin/env bash
# Гифка → mp4 для движка обоев.
#
# Зачем: Qt не анимирует gif в обычном Image (показывает первый кадр), а
# AnimatedImage держит в памяти все кадры — для 1280×720×50 это ~180 МБ.
# Поэтому гифку один раз перегоняем в mp4 и играем штатным видеотрактом
# (поток, ~20 МБ), он же умеет бесшовный цикл.
#
#   gif-cache.sh <гифка> [ширина] [высота]
#
# Ширина и высота — экран в пикселях. Если они заданы, гифка масштабируется
# под экран здесь, один раз, фильтром lanczos: получается резче (и без мыла
# от растягивания мелкой гифки видеокартой). Без размеров — как есть.
#
# Качество: CRF 19 + сохраняем хрому 4:4:4 — у гифок с дизерингом она иначе
# расползается цветными блоками, из-за которых обои кажутся «шакальными».
#
# Кеш: ~/.cache/wallpaper/gif/<отпечаток-гифки>[_<ш>x<в>].mp4
# Отпечаток — хеш содержимого, а не путь: движок обоев играет копию из кеша
# (~/.cache/wallpaper/current_<монитор>.gif), панель выбора обоев греет кеш по
# исходному файлу, и без общего отпечатка одна гифка кодировалась бы дважды.
# Пересобирается, если гифка новее кеша или изменилась версия кодировщика.

set -u

src="${1:-}"
[ -f "$src" ] || { echo "gif-cache.sh: нет файла '$src'" >&2; exit 1; }

w="${2:-0}"
h="${3:-0}"
case "$w" in '' | *[!0-9]*) w=0 ;; esac
case "$h" in '' | *[!0-9]*) h=0 ;; esac
if [ "$w" -le 0 ] || [ "$h" -le 0 ]; then
    w=0
    h=0
fi

cache="$HOME/.cache/wallpaper/gif"
key="$(sha1sum "$src" 2>/dev/null | cut -c1-20)"
[ -n "$key" ] || key="$(printf '%s' "$src" | sed 's|[^A-Za-z0-9]\+|_|g; s|^_*||; s|_*$||')"
[ "$w" -gt 0 ] && key="${key}_${w}x${h}"
out="$cache/$key.mp4"
stamp="$cache/.version"

# версия кодировщика: поменялись настройки — старый кеш не подходит
version=3
mkdir -p "$cache"
if [ ! -f "$stamp" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$version" ]; then
    rm -f "$cache"/*.mp4
    printf '%s' "$version" >"$stamp"
fi

if [ -s "$out" ] && [ "$out" -nt "$src" ]; then
    printf '%s\n' "$out"
    exit 0
fi

# размер не задан, а под экран уже собрано — берём готовое: движок обоев и
# панель выбора обоев делят один кеш, иначе гифка кодируется дважды
if [ "$w" -eq 0 ]; then
    for f in "$cache/$key"_*.mp4; do
        if [ -s "$f" ] && [ "$f" -nt "$src" ]; then
            printf '%s\n' "$f"
            exit 0
        fi
    done
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "gif-cache.sh: нет ffmpeg" >&2; exit 2; }

scale=()
if [ "$w" -gt 0 ]; then
    scale=(-vf "scale=${w}:${h}:force_original_aspect_ratio=increase:flags=lanczos,crop=${w}:${h}")
fi

if nice -n 10 ffmpeg -y -v error -i "$src" -an "${scale[@]}" \
        -c:v libx264 -preset medium -crf 19 -tune animation \
        -pix_fmt yuv444p -movflags +faststart "$out" >/dev/null 2>&1 && [ -s "$out" ]; then
    printf '%s\n' "$out"
    exit 0
fi

rm -f "$out"
echo "gif-cache.sh: не удалось собрать '$src'" >&2
exit 3
