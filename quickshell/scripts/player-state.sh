#!/bin/sh
# Состояние плеера одной строкой для панели quickshell (разделитель — таб):
#
#   title  artist  album  length  artUrl  position  status  shuffle  loop
#
# Длительность и позиция — в микросекундах, как их отдаёт MPRIS.
# playerctl не понимает "\t" в формате (печатает буквально), поэтому таб
# подставляем сами.
set -u

TAB="$(printf '\t')"
fmt="{{title}}${TAB}{{artist}}${TAB}{{album}}${TAB}{{mpris:length}}${TAB}{{mpris:artUrl}}${TAB}{{position}}${TAB}{{status}}"

meta="$(playerctl metadata --format "$fmt" 2>/dev/null)"
[ -n "$meta" ] || exit 0

# Повтор и перемешка: плеер может их не поддерживать — тогда поля пустые,
# и панель гасит эти кнопки.
shuffle="$(playerctl shuffle 2>/dev/null)"
loop="$(playerctl loop 2>/dev/null)"

printf '%s%s%s%s%s\n' "$meta" "$TAB" "$shuffle" "$TAB" "$loop"
