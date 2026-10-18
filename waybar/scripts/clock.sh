#!/bin/sh
# Часы для waybar: «Октябрь 17 16:35».
#
# Почему не встроенный модуль clock: waybar форматирует время через C++ chrono,
# где нет спецификатора %OB (месяц в именительном падеже), а %B берёт месяц из
# локали процесса. Язык берём из настройки интерфейса
# (~/.config/quickshell/language): у русского — русские месяцы, у остальных —
# английские. Если локали нет, %OB вернёт пусто — тогда падаем на LC_TIME=C.
LANG_CODE=$(head -n1 "$HOME/.config/quickshell/language" 2>/dev/null | tr -d '[:space:]')
out=""
if [ -z "$LANG_CODE" ] || [ "$LANG_CODE" = ru ]; then
    out=$(LC_TIME=ru_RU.UTF-8 date +"%OB %d %H:%M" 2>/dev/null)
fi
[ -n "$out" ] || out=$(LC_TIME=C date +"%B %d %H:%M")
printf '%s\n' "$out"
