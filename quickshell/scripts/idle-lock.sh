#!/bin/sh
# Блокировка по простою: этот скрипт зовёт swayidle (timeout 300).
# Файл-флаг ~/.config/quickshell/no-auto-lock выключает автоблокировку —
# его ставит тумблер в панели батареи. Блокировка перед сном работает всегда.
[ -f "$HOME/.config/quickshell/no-auto-lock" ] && exit 0
exec qs ipc call lock lock
