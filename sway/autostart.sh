#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id - u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Ждём, пока elogind создаст runtime dir
sleep 1

# Запускаем звук только если ещё не запущен
if ! pgrep -x pipewire > /dev/null; then
    pipewire &
    sleep 2
    wireplumber &
    sleep 1
    pipewire-pulse &
fi
