#!/bin/sh
# Данные для панели «Память и процессор» — один запуск вместо трёх.
# Секции разделены маркерами, которые разбирает MemoryPanel.qml.
cat /proc/meminfo

echo ---PS---
ps -eo rss,comm --sort=-rss | head -7

# /proc/stat снимаем дважды: загрузку процессора можно посчитать только по
# разнице двух замеров, иначе панель первые секунды показывала бы 0%.
echo ---STAT---
grep '^cpu' /proc/stat
sleep 0.3
echo ---STAT2---
grep '^cpu' /proc/stat

echo ---EXTRA---
printf 'load %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"

for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = k10temp ] && printf 'temp %s\n' "$(cat "$h/temp1_input")"
done

awk -F: '/cpu MHz/ { s += $2; n++ } END { if (n > 0) printf "freq %.0f\n", s / n }' /proc/cpuinfo