#!/usr/bin/env bash
# install.sh — установка этих дотфайлов в ~/.config.
#
#   git clone https://github.com/c4rt3z/swayfx-dotfiles ~/swayfx-dotfiles
#   cd ~/swayfx-dotfiles && ./install.sh
#
# Ключи:
#   --config-dir DIR   поставить в DIR вместо ~/.config (для проверки)
#   --dry-run          ничего не менять, только показать план
#   --yes              не задавать вопросов (соглашаться на всё)
#   --no-deps          не проверять и не ставить пакеты
#   -h, --help         эта справка
#
# Скрипт не требует root: конфиги принадлежат пользователю, а пакеты ставит
# через pacman (спросит пароль sudo) — и только те, которых не хватает.
# Всё, что лежало в ~/.config раньше, складывается в ~/.config-backup-<дата>.

set -euo pipefail

REPO_URL="https://github.com/c4rt3z/swayfx-dotfiles"

# ── что кладём в ~/.config ──────────────────────────────────────────────────
ITEMS=(sway quickshell waybar wallpaper alacritty kitty matugen
       gtk-3.0 gtk-4.0 swaylock wofi xsettingsd environment.d)

# ── команда → пакет в репозиториях Arch / CachyOS ───────────────────────────
# Проверяем именно команды: если sway пришёл из пакета sway, а не swayfx,
# всё равно всё в порядке — дотфайлы работают и на обычном sway.
DEPS=(
    "sway:swayfx"
    "waybar:waybar"
    "quickshell:quickshell"
    "python3:python"
    "jq:jq"
    "matugen:matugen"
    "grim:grim"
    "slurp:slurp"
    "wl-copy:wl-clipboard"
    "brightnessctl:brightnessctl"
    "playerctl:playerctl"
    "wpctl:wireplumber"
    "xdg-mime:xdg-utils"
    "swayidle:swayidle"
    "swaylock:swaylock-effects"
    "wofi:wofi"
    "ffmpeg:ffmpeg"
    "gsettings:glib2"
    "notify-send:libnotify"
)

# состояние машины, которое создаётся у каждого своё, — его не перетираем
KEEP=("quickshell/language" "quickshell/keys-default.json")

DRY=0
ASSUME_YES=0
SKIP_DEPS=0
CONFIG_DIR="$HOME/.config"

say() { printf '%s\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }
ok() { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
die() {
    printf '\033[31m  ✗ %s\033[0m\n' "$*" >&2
    exit 1
}

ask() { # ask "вопрос" → 0 если да
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    printf '\033[36m? %s [Y/n] \033[0m' "$1"
    read -r reply </dev/tty || reply=""
    case "${reply:-y}" in
    [YyДд]*) return 0 ;;
    *) return 1 ;;
    esac
}

ask_no() { # как ask, но по умолчанию «нет» (для необязательного и тяжёлого)
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    printf '\033[36m? %s [y/N] \033[0m' "$1"
    read -r reply </dev/tty || reply=""
    case "${reply:-n}" in
    [YyДд]*) return 0 ;;
    *) return 1 ;;
    esac
}

run() { # в dry-run только печатаем
    if [ "$DRY" = 1 ]; then
        printf '  будет: %s\n' "$*"
    else
        "$@"
    fi
}

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
    --config-dir)
        CONFIG_DIR="${2:?--config-dir требует путь}"
        shift 2
        ;;
    --dry-run) DRY=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --no-deps) SKIP_DEPS=1; shift ;;
    -h | --help) usage ;;
    *) die "неизвестный ключ: $1 (см. --help)" ;;
    esac
done

CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"

# ── откуда берём файлы ──────────────────────────────────────────────────────
step "Откуда ставим"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "$PWD")"
TMP=""
if [ ! -f "$SRC/sway/config" ]; then
    say "  рядом нет файлов дотфайлов — качаю архив с GitHub"
    command -v curl >/dev/null || die "нужен curl (или клонируй репозиторий и запусти ./install.sh из него)"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP"
    SRC="$TMP/swayfx-dotfiles-main"
    [ -f "$SRC/sway/config" ] || die "не удалось скачать архив"
fi
ok "исходники: $SRC"
ok "ставлю в:  $CONFIG_DIR"

[ "$(id -u)" = 0 ] && die "не запускай от root: конфиги должны принадлежать тебе, а не root"
[ -n "${HOME:-}" ] || die "нет переменной HOME"

# ── зависимости ─────────────────────────────────────────────────────────────
if [ "$SKIP_DEPS" = 0 ]; then
    step "Зависимости"
    missing_cmds=()
    missing_pkgs=()
    for entry in "${DEPS[@]}"; do
        cmd="${entry%%:*}"
        pkg="${entry##*:}"
        if command -v "$cmd" >/dev/null 2>&1; then
            continue
        fi
        missing_cmds+=("$cmd")
        missing_pkgs+=("$pkg")
    done

    if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import PIL' >/dev/null 2>&1; then
        missing_cmds+=("python3-PIL")
        missing_pkgs+=("python-pillow")
    fi
    # grep без -q: с -q он выходит на первом совпадении, fc-list получает
    # SIGPIPE, и из-за pipefail проверка врёт, что шрифта нет
    if ! fc-list 2>/dev/null | grep -i jetbrains >/dev/null; then
        missing_cmds+=("шрифт JetBrainsMono Nerd")
        missing_pkgs+=("ttf-jetbrains-mono-nerd")
    fi

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        ok "всё на месте"
    else
        say "  не хватает:"
        for i in "${!missing_pkgs[@]}"; do
            say "    ${missing_cmds[$i]}  →  ${missing_pkgs[$i]}"
        done

        if ! command -v pacman >/dev/null 2>&1; then
            warn "pacman не найден — поставь пакеты сам (это набор для Arch/CachyOS)"
        elif ask "Поставить их сейчас через pacman?"; then
            available=()
            for pkg in "${missing_pkgs[@]}"; do
                if pacman -Si "$pkg" >/dev/null 2>&1; then
                    available+=("$pkg")
                else
                    warn "$pkg нет в репозиториях — поставь его сам (например из AUR)"
                fi
            done
            if [ ${#available[@]} -gt 0 ]; then
                run sudo pacman -S --needed --noconfirm "${available[@]}"
            fi
        else
            warn "пропускаю установку пакетов"
        fi
    fi
fi

# ── бэкап того, что было ────────────────────────────────────────────────────
step "Что уже есть в $CONFIG_DIR"
BACKUP=""
need_backup=()
for item in "${ITEMS[@]}"; do
    [ -e "$CONFIG_DIR/$item" ] && need_backup+=("$item")
done

if [ ${#need_backup[@]} -eq 0 ]; then
    ok "конфликтов нет"
else
    BACKUP="$(dirname "$CONFIG_DIR")/.config-backup-$(date +%Y%m%d-%H%M%S)"
    say "  заменю: ${need_backup[*]}"
    say "  старое уедет в: $BACKUP"
    if [ "$DRY" = 0 ]; then
        mkdir -p "$BACKUP"
        for item in "${need_backup[@]}"; do
            cp -a "$CONFIG_DIR/$item" "$BACKUP/" 2>/dev/null || cp -ar "$CONFIG_DIR/$item" "$BACKUP/"
        done
    fi
    ok "бэкап готов"
fi

# ── копирование ─────────────────────────────────────────────────────────────
step "Ставлю файлы"
[ "$DRY" = 0 ] && mkdir -p "$CONFIG_DIR"
for item in "${ITEMS[@]}"; do
    src="$SRC/$item"
    [ -e "$src" ] || continue
    dst="$CONFIG_DIR/$item"

    if [ "$DRY" = 1 ]; then
        printf '  будет: %s → %s\n' "$item" "$dst"
    else
        rm -rf "$dst"
        cp -a "$src" "$dst"
        chmod +x "$dst"/*.sh 2>/dev/null || true
        chmod +x "$dst"/scripts/*.py 2>/dev/null || true
        ok "$item"
    fi
done

# восстановим состояние из бэкапа поверх свежих файлов
if [ -n "$BACKUP" ] && [ "$DRY" = 0 ]; then
    for rel in "${KEEP[@]}"; do
        if [ -e "$BACKUP/$rel" ]; then
            cp -a "$BACKUP/$rel" "$CONFIG_DIR/$rel" && ok "сохранил $rel"
        fi
    done
fi

# ── необязательное: темы alacritty ──────────────────────────────────────────
if [ "$DRY" = 0 ] && [ -d "$CONFIG_DIR/alacritty" ] && [ ! -d "$CONFIG_DIR/alacritty/themes" ] \
    && command -v alacritty >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    if ask_no "Склонировать сторонние темы alacritty (~56 МБ; без них alacritty возьмёт свою)?"; then
        git clone --depth 1 https://github.com/alacritty/alacritty-theme \
            "$CONFIG_DIR/alacritty/themes" >/dev/null 2>&1 \
            && ok "темы alacritty на месте" || warn "клон не удался — не страшно, alacritty возьмёт свою тему"
    fi
fi

# ── проверка конфига sway ───────────────────────────────────────────────────
step "Проверка"
if [ "$DRY" = 0 ] && command -v sway >/dev/null 2>&1; then
    if sway --validate -c "$CONFIG_DIR/sway/config" >/dev/null 2>&1; then
        ok "конфиг sway разбирается без ошибок"
    else
        warn "sway --validate ругается на конфиг: посмотри вывод вручную"
        sway --validate -c "$CONFIG_DIR/sway/config" || true
    fi
fi
if [ "$DRY" = 0 ] && command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import PIL' >/dev/null 2>&1; then
        ok "python-pillow есть (нужен для превью обоев и иконок)"
    fi
fi

# ── что дальше ──────────────────────────────────────────────────────────────
step "Готово. Осталось руками"
cat <<EOF
  1. Положи картинки и гифки в ~/Wallpapers (гифки анимируются сами).
  2. Выйди из сеанса и зайди снова: environment.d/10-qt.conf читается при
     входе, через него Qt-приложения берут GTK-тему.
  3. Запусти sway — waybar и quickshell поднимутся сами (exec_always в
     ~/.config/sway/config).
  4. Покрась рабочий стол под обои:
       ~/.config/wallpaper/wallpaper.sh random
     или готовой схемой без обоев:
       ~/.config/wallpaper/wallpaper.sh scheme nord
  5. Клавиши яркости включаются один раз:
       sudo bash ~/.config/sway/fix-backlight.sh
  6. Дальше всё в настройках: Super+,   Поиск: Super+Space   Эмодзи: Super+.

Если что-то пошло не так — пиши в issues: $REPO_URL/issues
EOF
if [ -n "$BACKUP" ]; then
    say "Старые конфиги лежат в $BACKUP"
else
    say "Ставить было нечего — конфликтов с прежними конфигами не было."
fi
