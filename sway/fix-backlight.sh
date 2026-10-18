#!/usr/bin/env bash
# Разрешает менять яркость экрана из сессии: правило udev + правка прав на сейчас.
# Запускать один раз с правами root:
#
#     sudo bash ~/.config/sway/fix-backlight.sh
#
# После этого работают клавиши яркости и прокрутка по модулю яркости в waybar.
# Перезаход в сессию не нужен: группа wheel у пользователя уже активна.

set -eu

RULES=/etc/udev/rules.d/90-backlight.rules

cat >"$RULES" <<'EOF'
# Яркость экрана: запись для группы wheel (чтобы brightnessctl работал без root)
ACTION=="add|change", SUBSYSTEM=="backlight", RUN+="/bin/chgrp wheel /sys/class/backlight/%k/brightness"
ACTION=="add|change", SUBSYSTEM=="backlight", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"
EOF
udevadm control --reload-rules
echo "правило записано: $RULES"

# применяем сразу, не дожидаясь перезагрузки
for f in /sys/class/backlight/*/brightness; do
    [ -e "$f" ] || continue
    chgrp wheel "$f"
    chmod g+w "$f"
    echo "разрешено: $f"
done

# проверка от имени обычного пользователя (значение не меняем)
if [ -n "${SUDO_USER:-}" ]; then
    pct=$(brightnessctl -m | cut -d, -f4)
    if runuser -u "$SUDO_USER" -- brightnessctl set "$pct" >/dev/null 2>&1; then
        echo "проверка: $SUDO_USER может менять яркость — клавиши будут работать"
    else
        echo "проверка не прошла: клавиши яркости всё ещё без прав" >&2
        exit 1
    fi
fi
