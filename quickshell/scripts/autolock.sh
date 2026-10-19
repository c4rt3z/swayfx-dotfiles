#!/bin/sh
# Автоблокировка по простою — тумблер в панели батареи (клик по значку заряда).
#
#   autolock.sh status   — on|off
#   autolock.sh toggle   — переключить
#
# Сама блокировка: swayidle по простою зовёт idle-lock.sh, а тот смотрит на
# флаг ~/.config/quickshell/no-auto-lock: файл есть — блокировки нет. Так
# переключение действует сразу, без перезапуска swayidle.
#
# Единственная тонкость: если swayidle был запущен ещё со старой командой
# (строку exec перечитывают только при перезаходе в сеанс), перезапускаем его
# здесь — иначе тумблер заработал бы лишь после перезахода.
FLAG="$HOME/.config/quickshell/no-auto-lock"

restart_idle() {
    pid="$(pgrep -x swayidle | head -1)"
    [ -n "$pid" ] || return 0
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null \
        | grep -q "qs ipc call lock lock" || return 0
    kill "$pid" 2>/dev/null
    sleep 0.3
    setsid -f swayidle -w \
        timeout 300 "sh $HOME/.config/quickshell/scripts/idle-lock.sh" \
        timeout 600 'swaymsg "output * power off"' \
        resume 'swaymsg "output * power on"' \
        before-sleep 'qs ipc call lock lock' >/dev/null 2>&1
}

state() {
    if [ -f "$FLAG" ]; then echo off; else echo on; fi
}

case "${1:-status}" in
status) state ;;
toggle)
    if [ -f "$FLAG" ]; then rm -f "$FLAG"; else touch "$FLAG"; fi
    restart_idle
    state
    ;;
*)
    echo "autolock.sh status|toggle" >&2
    exit 1
    ;;
esac
