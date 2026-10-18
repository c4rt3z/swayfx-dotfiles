#!/usr/bin/env bash
# Присмотр за quickshell.
#
# Зачем: изредка «горячая» перезагрузка оболочки подвисает — старая копия
# конфигурации не отпускается, quickshell продолжает рисовать, но перестаёт
# отвечать на запросы (кнопки waybar перестают открывать панели). Скрипт
# проверяет связь и, если она мертва, перезапускает quickshell. Заодно
# поднимает его, если он упал.
#
# Запускается из sway в фоне:  watchdog.sh [интервал, сек]

set -u

INTERVAL="${1:-15}"
PANEL="panel"
PIDFILE="$HOME/.cache/wallpaper/watchdog.pid"

# чтобы из конфига sway не поднять второй экземпляр
mkdir -p "$(dirname "$PIDFILE")"
printf '%s' "$$" >"$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

start_qs() {
    swaymsg exec -- sh -c "pgrep -x qs >/dev/null || exec qs" >/dev/null 2>&1 || true
}

alive() {
    qs ipc --pid "$1" call "$PANEL" ping >/dev/null 2>&1
}

fails=0
while :; do
    # обои рисует quickshell; если sway заново поднял swaybg, он перекроет
    # слой обоев — гасим
    pkill -x swaybg 2>/dev/null

    pid="$(pgrep -x qs | head -1)"
    if [ -z "$pid" ]; then
        start_qs
        fails=0
    else
        age="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
        if alive "$pid"; then
            fails=0
        elif [ "${age:-0}" -gt 20 ]; then
            # оболочка пожила достаточно — значит, дело не в запуске
            fails=$((fails + 1))
            if [ "$fails" -ge 2 ]; then
                kill "$pid" 2>/dev/null
                sleep 1
                start_qs
                fails=0
            fi
        else
            fails=0
        fi
    fi
    sleep "$INTERVAL"
done
