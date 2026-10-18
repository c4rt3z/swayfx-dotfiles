#!/usr/bin/env bash
# install.sh — установка этих дотфайлов в ~/.config.
#
#   git clone https://github.com/c4rt3z/swayfx-dotfiles ~/swayfx-dotfiles
#   cd ~/swayfx-dotfiles && ./install.sh
#
# В начале скрипт спрашивает язык — русский или английский (тексты в таблицах
# RU и EN ниже); ключ --lang вопрос пропускает.
#
# Ключи:
#   --config-dir DIR   поставить в DIR вместо ~/.config (для проверки)
#   --dry-run          ничего не менять, только показать план
#   --yes              не задавать вопросов (соглашаться на всё)
#   --no-deps          не проверять и не ставить пакеты
#   --lang ru|en       язык вывода
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
LANG_SEL=""
SHOW_HELP=0

# ── тексты ──────────────────────────────────────────────────────────────────
# Ключи одинаковые, форматы — для printf (аргументы подставляются через %s).

declare -A RU=(
    [src_step]="Откуда ставим"
    [src_download]="рядом нет файлов дотфайлов — качаю архив с GitHub"
    [src_need_curl]="нужен curl (или клонируй репозиторий и запусти ./install.sh из него)"
    [src_failed]="не удалось скачать архив"
    [src_from]="исходники: %s"
    [src_to]="ставлю в:  %s"
    [root_no]="не запускай от root: конфиги должны принадлежать тебе, а не root"
    [no_home]="нет переменной HOME"
    [dep_step]="Зависимости"
    [dep_all]="всё на месте"
    [dep_missing]="не хватает:"
    [dep_pair]="%s  →  %s"
    [dep_pil]="python3-PIL"
    [dep_font]="шрифт JetBrainsMono Nerd"
    [dep_no_pacman]="pacman не найден — поставь пакеты сам (это набор для Arch/CachyOS)"
    [dep_ask]="Поставить их сейчас через pacman?"
    [dep_not_in_repo]="%s нет в репозиториях — поставь его сам (например из AUR)"
    [dep_skip]="пропускаю установку пакетов"
    [have_step]="Что уже есть в %s"
    [have_none]="конфликтов нет"
    [have_replace]="заменю: %s"
    [have_backup_to]="старое уедет в: %s"
    [have_done]="бэкап готов"
    [copy_step]="Ставлю файлы"
    [copy_will]="будет: %s → %s"
    [copy_ok]="%s"
    [keep_ok]="сохранил %s"
    [alt_ask]="Склонировать сторонние темы alacritty (~56 МБ; без них alacritty возьмёт свою)?"
    [alt_ok]="темы alacritty на месте"
    [alt_fail]="клон не удался — не страшно, alacritty возьмёт свою тему"
    [check_step]="Проверка"
    [check_sway_ok]="конфиг sway разбирается без ошибок"
    [check_sway_bad]="sway --validate ругается на конфиг: посмотри вывод вручную"
    [check_pillow]="python-pillow есть (нужен для превью обоев и иконок)"
    [done_head]="Готово. Осталось руками"
    [done_1]="Положи картинки и гифки в ~/Wallpapers (гифки анимируются сами)."
    [done_2]="Выйди из сеанса и зайди снова: environment.d/10-qt.conf читается при входе,"
    [done_2b]="через него Qt-приложения берут GTK-тему."
    [done_3]="Запусти sway — waybar и quickshell поднимутся сами (exec_always в"
    [done_3b]="~/.config/sway/config)."
    [done_4]="Покрась рабочий стол под обои:  ~/.config/wallpaper/wallpaper.sh random"
    [done_4b]="или готовой схемой, если обоев пока нет:  ~/.config/wallpaper/wallpaper.sh scheme nord"
    [done_5]="Клавиши яркости включаются один раз:  sudo bash ~/.config/sway/fix-backlight.sh"
    [done_6]="Дальше всё в настройках: Super+,   Поиск: Super+Space   Эмодзи: Super+."
    [done_issues]="Если что-то пошло не так — пиши в issues: %s"
    [done_backup]="Старые конфиги лежат в %s"
    [done_nothing]="Ставить было нечего — конфликтов с прежними конфигами не было."
    [err_flag]="неизвестный ключ: %s (см. --help / see --help)"
    [err_config_dir]="--config-dir требует путь"
    [err_lang]="язык не поддерживается: %s (есть ru и en)"
    [lang_prompt]="Язык / Language:  [1] English  [2] Русский  [Enter = %s] > "
    [help_1]="install.sh — установка дотфайлов в ~/.config"
    [help_2]="  git clone https://github.com/c4rt3z/swayfx-dotfiles ~/swayfx-dotfiles"
    [help_3]="  cd ~/swayfx-dotfiles && ./install.sh"
    [help_keys]="Ключи:"
    [help_k_config]="  --config-dir DIR   поставить в DIR вместо ~/.config (для проверки)"
    [help_k_dry]="  --dry-run          ничего не менять, только показать план"
    [help_k_yes]="  --yes              не задавать вопросов (соглашаться на всё)"
    [help_k_deps]="  --no-deps          не проверять и не ставить пакеты"
    [help_k_lang]="  --lang ru|en       язык вывода (иначе спросит при запуске)"
    [help_k_help]="  -h, --help         эта справка"
    [help_note]="Скрипт не требует root: конфиги принадлежат пользователю, а пакеты ставит через pacman (спросит пароль sudo) — и только те, которых не хватает. Всё, что лежало в ~/.config раньше, складывается в ~/.config-backup-<дата>."
)

declare -A EN=(
    [src_step]="Where the files come from"
    [src_download]="no dotfiles next to the script — downloading the archive from GitHub"
    [src_need_curl]="curl is required (or clone the repository and run ./install.sh from it)"
    [src_failed]="could not download the archive"
    [src_from]="sources:    %s"
    [src_to]="installing:  %s"
    [root_no]="do not run as root: the configs must belong to you, not to root"
    [no_home]="HOME is not set"
    [dep_step]="Dependencies"
    [dep_all]="everything is already installed"
    [dep_missing]="missing:"
    [dep_pair]="%s  →  %s"
    [dep_pil]="python3-PIL"
    [dep_font]="JetBrainsMono Nerd font"
    [dep_no_pacman]="pacman not found — install the packages yourself (this set is for Arch/CachyOS)"
    [dep_ask]="Install them now with pacman?"
    [dep_not_in_repo]="%s is not in the repositories — install it yourself (AUR, for instance)"
    [dep_skip]="skipping package installation"
    [have_step]="What is already in %s"
    [have_none]="no conflicts"
    [have_replace]="replacing: %s"
    [have_backup_to]="the old files go to: %s"
    [have_done]="backup is ready"
    [copy_step]="Copying files"
    [copy_will]="would copy: %s → %s"
    [copy_ok]="%s"
    [keep_ok]="kept %s"
    [alt_ask]="Clone the third-party alacritty themes (~56 MB; without them alacritty uses its own)?"
    [alt_ok]="alacritty themes are in place"
    [alt_fail]="the clone failed — no big deal, alacritty will use its own theme"
    [check_step]="Checks"
    [check_sway_ok]="the sway config parses without errors"
    [check_sway_bad]="sway --validate complains about the config: check its output"
    [check_pillow]="python-pillow is present (needed for wallpaper previews and icons)"
    [done_head]="Done. What is left to do by hand"
    [done_1]="Put images and .gif files into ~/Wallpapers (gifs animate on their own)."
    [done_2]="Log out and back in: environment.d/10-qt.conf is read at login — that is"
    [done_2b]="how Qt apps pick up the GTK theme."
    [done_3]="Start sway — waybar and quickshell come up on their own (exec_always in"
    [done_3b]="~/.config/sway/config)."
    [done_4]="Paint everything from the wallpaper:  ~/.config/wallpaper/wallpaper.sh random"
    [done_4b]="or use a ready-made scheme if you have no wallpapers yet:  ~/.config/wallpaper/wallpaper.sh scheme nord"
    [done_5]="Brightness keys need one-time rights:  sudo bash ~/.config/sway/fix-backlight.sh"
    [done_6]="Everything else lives in the settings: Super+,   Search: Super+Space   Emoji: Super+."
    [done_issues]="If something went wrong, open an issue: %s"
    [done_backup]="Your old configs are in %s"
    [done_nothing]="Nothing to back up — no conflicts with your previous configs."
    [err_flag]="unknown flag: %s (see --help / см. --help)"
    [err_config_dir]="--config-dir needs a path"
    [err_lang]="unsupported language: %s (ru and en are available)"
    [lang_prompt]="Language / Язык:  [1] English  [2] Русский  [Enter = %s] > "
    [help_1]="install.sh — installs these dotfiles into ~/.config"
    [help_2]="  git clone https://github.com/c4rt3z/swayfx-dotfiles ~/swayfx-dotfiles"
    [help_3]="  cd ~/swayfx-dotfiles && ./install.sh"
    [help_keys]="Keys:"
    [help_k_config]="  --config-dir DIR   install into DIR instead of ~/.config (for testing)"
    [help_k_dry]="  --dry-run          change nothing, just print the plan"
    [help_k_yes]="  --yes              never ask, agree to everything"
    [help_k_deps]="  --no-deps          skip the package check"
    [help_k_lang]="  --lang ru|en       output language (otherwise it asks on start)"
    [help_k_help]="  -h, --help         this help"
    [help_note]="The script never needs root: the configs belong to you, and packages are installed with pacman (it will ask for the sudo password) — only the missing ones. Anything that was in ~/.config before is moved to ~/.config-backup-<date>."
)

# ── вывод ───────────────────────────────────────────────────────────────────
t() { # t <ключ> [аргументы для printf]
    local key="$1"
    shift
    local fmt
    if [ "$LANG_SEL" = "en" ]; then
        fmt="${EN[$key]:-}"
    else
        fmt="${RU[$key]:-}"
    fi
    if [ $# -gt 0 ]; then
        printf "$fmt" "$@"
    else
        printf '%s' "$fmt"
    fi
}

step() { printf '\n\033[1m== %s\033[0m\n' "$(t "$@")"; }
ok() { printf '\033[32m  ✓ %s\033[0m\n' "$(t "$@")"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$(t "$@")"; }
die() {
    printf '\033[31m  ✗ %s\033[0m\n' "$(t "$@")" >&2
    exit 1
}
info() { printf '  %s\n' "$(t "$@")"; }
line() { printf '%s\n' "$(t "$@")"; }

ask() { # ask <ключ> … — вопрос с ответом по умолчанию «да»
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    printf '\033[36m? %s [Y/n] \033[0m' "$(t "$@")"
    local reply=""
    read -r reply </dev/tty || reply=""
    case "${reply:-y}" in
    [YyДд]*) return 0 ;;
    *) return 1 ;;
    esac
}

ask_no() { # как ask, но по умолчанию «нет» (для необязательного и тяжёлого)
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    printf '\033[36m? %s [y/N] \033[0m' "$(t "$@")"
    local reply=""
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

# ── язык ────────────────────────────────────────────────────────────────────
choose_lang() { # choose_lang 1 — не спрашивать (для --help)
    local silent="${1:-}"
    if [ -n "$LANG_SEL" ]; then
        case "$LANG_SEL" in
        ru | RU | ru_* | рус*) LANG_SEL=ru ;;
        en | EN | en_* | англ*) LANG_SEL=en ;;
        *) die err_lang "$LANG_SEL" ;;
        esac
        return 0
    fi

    # по умолчанию — по локали: русская локаль → русский, иначе английский
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    ru* | uk* | be* | kk* | ky* | uz* | az*) LANG_SEL=ru ;;
    *) LANG_SEL=en ;;
    esac

    [ -n "$silent" ] && return 0
    [ "$ASSUME_YES" = 1 ] && return 0

    local answer=""
    printf '\033[36m%s\033[0m' "$(t lang_prompt "$LANG_SEL")"
    read -r answer </dev/tty || answer=""
    case "$answer" in
    1 | en | EN | English | english | англ*) LANG_SEL=en ;;
    2 | ru | RU | Русский | русский | Р | р) LANG_SEL=ru ;;
    *) : ;;
    esac
}

usage() {
    line help_1
    line help_2
    line help_3
    printf '\n'
    line help_keys
    line help_k_config
    line help_k_dry
    line help_k_yes
    line help_k_deps
    line help_k_lang
    line help_k_help
    printf '\n'
    line help_note
    exit 0
}

# ── разбор ключей ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
    --config-dir)
        CONFIG_DIR="${2:-}"
        shift 2 || shift
        ;;
    --dry-run)
        DRY=1
        shift
        ;;
    --yes)
        ASSUME_YES=1
        shift
        ;;
    --no-deps)
        SKIP_DEPS=1
        shift
        ;;
    --lang)
        LANG_SEL="${2:-}"
        shift 2 || shift
        ;;
    -h | --help)
        SHOW_HELP=1
        shift
        ;;
    *)
        # язык ещё не выбран — текст ошибки двуязычный
        printf '\033[31m  ✗ %s\033[0m\n' "$(t err_flag "$1")" >&2
        exit 1
        ;;
    esac
done

if [ "$SHOW_HELP" = 1 ]; then
    choose_lang 1
    usage
fi

choose_lang
[ -n "$CONFIG_DIR" ] || die err_config_dir
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"

# ── откуда берём файлы ──────────────────────────────────────────────────────
step src_step
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "$PWD")"
TMP=""
if [ ! -f "$SRC/sway/config" ]; then
    info src_download
    command -v curl >/dev/null || die src_need_curl
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP"
    SRC="$TMP/swayfx-dotfiles-main"
    [ -f "$SRC/sway/config" ] || die src_failed
fi
ok src_from "$SRC"
ok src_to "$CONFIG_DIR"

[ "$(id -u)" = 0 ] && die root_no
[ -n "${HOME:-}" ] || die no_home

# ── зависимости ─────────────────────────────────────────────────────────────
if [ "$SKIP_DEPS" = 0 ]; then
    step dep_step
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
        missing_cmds+=("$(t dep_pil)")
        missing_pkgs+=("python-pillow")
    fi
    # grep без -q: с -q он выходит на первом совпадении, fc-list получает
    # SIGPIPE, и из-за pipefail проверка врёт, что шрифта нет
    if ! fc-list 2>/dev/null | grep -i jetbrains >/dev/null; then
        missing_cmds+=("$(t dep_font)")
        missing_pkgs+=("ttf-jetbrains-mono-nerd")
    fi

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        ok dep_all
    else
        info dep_missing
        for i in "${!missing_pkgs[@]}"; do
            printf '    %s\n' "$(t dep_pair "${missing_cmds[$i]}" "${missing_pkgs[$i]}")"
        done

        if ! command -v pacman >/dev/null 2>&1; then
            warn dep_no_pacman
        elif ask dep_ask; then
            available=()
            for pkg in "${missing_pkgs[@]}"; do
                if pacman -Si "$pkg" >/dev/null 2>&1; then
                    available+=("$pkg")
                else
                    warn dep_not_in_repo "$pkg"
                fi
            done
            if [ ${#available[@]} -gt 0 ]; then
                run sudo pacman -S --needed --noconfirm "${available[@]}"
            fi
        else
            warn dep_skip
        fi
    fi
fi

# ── бэкап того, что было ────────────────────────────────────────────────────
step have_step "$CONFIG_DIR"
BACKUP=""
need_backup=()
for item in "${ITEMS[@]}"; do
    [ -e "$CONFIG_DIR/$item" ] && need_backup+=("$item")
done

if [ ${#need_backup[@]} -eq 0 ]; then
    ok have_none
else
    BACKUP="$(dirname "$CONFIG_DIR")/.config-backup-$(date +%Y%m%d-%H%M%S)"
    info have_replace "${need_backup[*]}"
    info have_backup_to "$BACKUP"
    if [ "$DRY" = 0 ]; then
        mkdir -p "$BACKUP"
        for item in "${need_backup[@]}"; do
            cp -a "$CONFIG_DIR/$item" "$BACKUP/" 2>/dev/null || cp -ar "$CONFIG_DIR/$item" "$BACKUP/"
        done
    fi
    ok have_done
fi

# ── копирование ─────────────────────────────────────────────────────────────
step copy_step
[ "$DRY" = 0 ] && mkdir -p "$CONFIG_DIR"
for item in "${ITEMS[@]}"; do
    src="$SRC/$item"
    [ -e "$src" ] || continue
    dst="$CONFIG_DIR/$item"

    if [ "$DRY" = 1 ]; then
        printf '  %s\n' "$(t copy_will "$item" "$dst")"
    else
        rm -rf "$dst"
        cp -a "$src" "$dst"
        chmod +x "$dst"/*.sh 2>/dev/null || true
        chmod +x "$dst"/scripts/*.py 2>/dev/null || true
        ok copy_ok "$item"
    fi
done

# восстановим состояние из бэкапа поверх свежих файлов
if [ -n "$BACKUP" ] && [ "$DRY" = 0 ]; then
    for rel in "${KEEP[@]}"; do
        if [ -e "$BACKUP/$rel" ]; then
            cp -a "$BACKUP/$rel" "$CONFIG_DIR/$rel" && ok keep_ok "$rel"
        fi
    done
fi

# ── необязательное: темы alacritty ──────────────────────────────────────────
if [ "$DRY" = 0 ] && [ -d "$CONFIG_DIR/alacritty" ] && [ ! -d "$CONFIG_DIR/alacritty/themes" ] \
    && command -v alacritty >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    if ask_no alt_ask; then
        git clone --depth 1 https://github.com/alacritty/alacritty-theme \
            "$CONFIG_DIR/alacritty/themes" >/dev/null 2>&1 \
            && ok alt_ok || warn alt_fail
    fi
fi

# ── проверка конфига sway ───────────────────────────────────────────────────
step check_step
if [ "$DRY" = 0 ] && command -v sway >/dev/null 2>&1; then
    if sway --validate -c "$CONFIG_DIR/sway/config" >/dev/null 2>&1; then
        ok check_sway_ok
    else
        warn check_sway_bad
        sway --validate -c "$CONFIG_DIR/sway/config" || true
    fi
fi
if [ "$DRY" = 0 ] && command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import PIL' >/dev/null 2>&1; then
        ok check_pillow
    fi
fi

# ── что дальше ──────────────────────────────────────────────────────────────
step done_head
info done_1
info done_2
info done_2b
info done_3
info done_3b
info done_4
info done_4b
info done_5
info done_6
printf '\n'
line done_issues "$REPO_URL/issues"
if [ -n "$BACKUP" ]; then
    line done_backup "$BACKUP"
else
    line done_nothing
fi
