#!/usr/bin/env bash
# Тема рабочего стола: цвета для waybar / kitty / alacritty / quickshell.
#
#   theme-gen.sh <файл обоев>    — применить текущий режим к этим обоям
#                                  (в режиме схемы обои цвета не меняют)
#   theme-gen.sh --mode auto     — цвета вывести из текущих обоев (matugen)
#   theme-gen.sh --mode <id>     — готовая схема из ~/.config/wallpaper/themes/
#   theme-gen.sh --flavour <тип> — тип схемы Material You и пересборка палитры
#                                  (universal, vibrant, content, expressive,
#                                  fidelity, monochrome, rainbow, neutral,
#                                  fruit-salad) — хранится в flavour
#   theme-gen.sh --variant dark|light — тёмная или светлая схема, пересборка
#   theme-gen.sh --list          — список схем
#   theme-gen.sh --current       — текущий режим
#
# Палитра для quickshell остаётся в кэше (colors.json) и подхватывается на лету.

set -u

RENDER="$HOME/.config/wallpaper/theme-render.py"
THEME="$HOME/.cache/wallpaper/theme"
CACHE="$HOME/.cache/wallpaper"
MODE_FILE="$CACHE/theme_mode"
APPLIED_FILE="$CACHE/theme_applied"
FLAVOUR_FILE="$HOME/.config/wallpaper/flavour"
mkdir -p "$THEME"

die() {
    echo "theme-gen: $*" >&2
    exit 1
}

# текущие обои — по указателю состояния (файлы current_<монитор> без расширения)
pick_current() {
    local f mon
    for f in "$CACHE"/current_*; do
        mon="${f##*/current_}"
        case "$mon" in
        *_src | *_name | *.*) continue ;;
        esac
        [ -s "$f" ] || continue
        head -n 1 "$f"
        return 0
    done
    return 1
}

# apply auto <обои> | apply named <id>
apply() {
    local kind="$1" arg="$2" mode_line accent

    if [ "$kind" = auto ]; then
        # тип схемы Material You и тёмное/светлое — из flavour
        local flavour mode
        flavour=""
        mode=""
        read -r flavour mode <"$FLAVOUR_FILE" 2>/dev/null || true
        [ -n "$flavour" ] || flavour="universal"
        [ -n "$mode" ] || mode="dark"
        python3 "$RENDER" auto "$arg" "$mode" "$flavour" >/dev/null \
            || die "не удалось вывести цвета из «$arg»"
        mode_line="auto $flavour"
    else
        python3 "$RENDER" named "$arg" >/dev/null || die "не удалось собрать схему «$arg»"
        mode_line="named $arg"
    fi

    # без полного набора файлов ничего не трогаем — бар не должен остаться без CSS
    for f in style.css colors.json theme.conf alacritty.toml wofi.css swaylock.conf; do
        [ -s "$THEME/$f" ] || die "не сгенерирован $f"
    done
    python3 -c "import json;json.load(open('$THEME/colors.json'))" 2>/dev/null || die "битый colors.json"

    # тема приложений (GTK, KDE, Qt) идёт за темой обоев: тёмная палитра —
    # тёмные приложения, светлая — светлые
    python3 "$HOME/.config/quickshell/scripts/apps-theme.py" sync >/dev/null 2>&1 || true

    # атомарная замена: потребитель никогда не видит наполовину записанный файл
    put() {
        local dst="$2"
        mkdir -p "$(dirname "$dst")"
        cp -f "$1" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst"
    }

    put "$THEME/style.css" "$HOME/.config/waybar/style.css"
    put "$THEME/theme.conf" "$HOME/.config/kitty/theme.conf"
    put "$THEME/alacritty.toml" "$HOME/.config/alacritty/wallpaper.toml"
    put "$THEME/wofi.css" "$HOME/.config/wofi/style.css"
    put "$THEME/swaylock.conf" "$HOME/.config/swaylock/config"

    printf '%s' "$mode_line" >"$APPLIED_FILE"

    # waybar перечитывает конфиг и CSS по SIGUSR2, kitty — тему по SIGUSR1
    pkill -USR2 -x waybar 2>/dev/null || true
    pkill -USR1 -x kitty 2>/dev/null || true

    # если waybar всё-таки упал (например, не понравился CSS) — поднимаем обратно,
    # чтобы пользователь не остался без панели
    sleep 0.6
    if ! pgrep -x waybar >/dev/null 2>&1; then
        (waybar >"$CACHE/waybar.log" 2>&1 &)
        echo "theme-gen: waybar перезапущен" >&2
    fi

    local accent
    accent=$(python3 -c "import json;print(json.load(open('$THEME/colors.json'))['accent'])" 2>/dev/null)
    echo "тема: акцент $accent ($mode_line)" >&2
}

case "${1:-}" in
--list)
    python3 "$RENDER" list
    ;;
--current)
    cat "$MODE_FILE" 2>/dev/null || echo auto
    ;;
--mode)
    MODE="${2:-}"
    [ -n "$MODE" ] || die "нужен режим: --mode auto|<id>"
    if [ "$MODE" = auto ]; then
        IMG=$(pick_current) || IMG="$CACHE/current.png"
        [ -s "$IMG" ] || die "не нашёл текущих обоев"
        apply auto "$IMG"
    else
        apply named "$MODE"
    fi
    printf '%s' "$MODE" >"$MODE_FILE"
    ;;
--flavour)
    FLAV="${2:-}"
    case "$FLAV" in
    universal | vibrant | content | expressive | fidelity | monochrome | rainbow | neutral | fruit-salad) ;;
    *) die "нужен тип: universal|vibrant|content|expressive|fidelity|monochrome|rainbow|neutral|fruit-salad" ;;
    esac
    # тёмное/светлое оставляем как было
    MODE_NOW=""
    if [ -s "$FLAVOUR_FILE" ]; then read -r _ MODE_NOW <"$FLAVOUR_FILE" || true; fi
    [ -n "$MODE_NOW" ] || MODE_NOW="dark"
    printf '%s %s\n' "$FLAV" "$MODE_NOW" >"$FLAVOUR_FILE"
    IMG=$(pick_current) || IMG="$CACHE/current.png"
    [ -s "$IMG" ] || die "не нашёл текущих обоев"
    apply auto "$IMG"
    printf 'auto' >"$MODE_FILE"
    printf '%s' "$FLAV"
    ;;
--variant)
    VAR="${2:-}"
    case "$VAR" in
    dark | light) ;;
    *) die "нужен вариант: --variant dark|light" ;;
    esac
    # тип схемы оставляем как был
    FLAV_NOW=""
    if [ -s "$FLAVOUR_FILE" ]; then read -r FLAV_NOW _ <"$FLAVOUR_FILE" || true; fi
    [ -n "$FLAV_NOW" ] || FLAV_NOW="universal"
    printf '%s %s\n' "$FLAV_NOW" "$VAR" >"$FLAVOUR_FILE"
    IMG=$(pick_current) || IMG="$CACHE/current.png"
    [ -s "$IMG" ] || die "не нашёл текущих обоев"
    apply auto "$IMG"
    printf 'auto' >"$MODE_FILE"
    printf '%s' "$VAR"
    ;;
"")
    echo "usage: theme-gen.sh <файл-обоев> | --mode auto|<id> | --flavour <тип> | --variant dark|light | --list | --current" >&2
    exit 1
    ;;
*)
    IMG="$1"
    [ -f "$IMG" ] || die "нет файла: '$IMG'"
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo auto)
    if [ "$MODE" = auto ]; then
        apply auto "$IMG"
    else
        # выбрана схема: обои цвета не меняют, но при первом запуске
        # (или после чистки кэша) тему надо поставить
        if [ "$(cat "$APPLIED_FILE" 2>/dev/null)" != "named $MODE" ]; then
            apply named "$MODE"
        fi
    fi
    ;;
esac
