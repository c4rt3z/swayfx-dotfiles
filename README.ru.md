# swayfx-dotfiles

English version — [README.md](README.md).

Полностью готовый рабочий стол на SwayFX для CachyOS/Arch: панели **quickshell**
поверх **sway**, бар на **waybar** и тема **Material You**, которая собирается из
обоев — GTK, Qt, KDE, терминалы, бар и панели следуют ей и переключаются между
светлым и тёмным видом вместе с обоями.

![Рабочий стол](quickshell/docs/preview.jpg)

![Настройки](quickshell/docs/settings.jpg)

## Что внутри

```
~/.config/
├── sway/           конфиг композитора (SwayFX), автостарт, скрипт для яркости
├── quickshell/     оболочка: панели, настройки, поиск, экран блокировки, обои
│   ├── panels/       лаунчер, эмодзи, музыка, звук, яркость, выбор обоев,
│   │                 настройки (10 разделов: вид, язык, приложения, панель,
│   │                 клавиши, раскладки, приложения по умолчанию, службы…)
│   ├── scripts/      python: движок поиска, индексы приложений/биндов/раскладок
│   ├── i18n/         языки интерфейса: ru (исходный), en, uk, de
│   ├── lock/         экран блокировки (вместо swaylock)
│   └── docs/         скриншоты
├── waybar/         бар и его скрипты (заголовок окна, часы, медиацентр, раскладка)
├── wallpaper/      обои → палитра → все приложения (движок темы)
├── alacritty/      конфиг терминала (шрифт, прозрачность, тема Qt через env)
├── kitty/          то же для kitty
├── gtk-3.0/        GTK-темы, собранные из палитры
├── gtk-4.0/
├── swaylock/       запасной экран блокировки
├── wofi/           запасной лаунчер
├── xsettingsd/     GTK-настройки для программ вне GNOME
├── matugen/        конфиг, которым палитра вытаскивается из обоев
├── environment.d/  Qt-программы берут тему из GTK (QT_QPA_PLATFORMTHEME=gtk3)
├── install.sh      установщик: пакеты, бэкап, раскладка по ~/.config
├── LICENSE         MIT
└── .gitignore      белый список — в репозиторий идёт только рабочий стол
```

## Что нужно

* **CachyOS / Arch** со `swayfx` (SwayFX 0.6+, sway 1.12+) — обычный sway тоже
  подойдёт, просто блюр, тени и скругление углов останутся без эффекта
* `waybar`, `quickshell` (0.3.2+), `python3` с **Pillow**, `jq`
* шрифт **JetBrainsMono Nerd Font** — единственный, который используется
* терминалы: `alacritty` и/или `kitty`
* остальное, что зовёт конфиг: `wofi`, `grim`, `slurp`, `wl-clipboard`,
  `brightnessctl`, `playerctl`, `wireplumber` (wpctl), `xdg-utils` (xdg-mime),
  `matugen`, `ffmpeg`, `gsettings` (glib2), `swayidle`, `swaylock-effects`
  (запасная блокировка)
* `plasma-apply-colorscheme` (plasma-workspace) — только чтобы красить KDE-программы
* по желанию: [alacritty-theme](https://github.com/alacritty/alacritty-theme) —
  `git clone https://github.com/alacritty/alacritty-theme ~/.config/alacritty/themes`

## Установка

> **Установщик пока сырой.** На чистой системе он ещё не проверялся, так что
> сюрпризы возможны. Начните с плана — `./install.sh --dry-run` — и не удаляйте
> бэкап `~/.config-backup-<дата>`, который он сделает. О поломках пишите в
> [issues](https://github.com/c4rt3z/swayfx-dotfiles/issues).

Всё скучное делает установщик: проверяет пакеты, делает бэкап того, что у вас
уже было, и раскладывает файлы по `~/.config`:

```sh
git clone https://github.com/c4rt3z/swayfx-dotfiles ~/swayfx-dotfiles
cd ~/swayfx-dotfiles
./install.sh
```

Сначала он спросит язык вывода (русский или английский, по умолчанию — по вашей
локали). От root он отказывается работать (конфиги должны остаться вашими),
недостающие пакеты ставит через `pacman` (спросит пароль sudo), а всё, что
заменяет, уносит в `~/.config-backup-<дата>/`. Ключи:

| ключ | что делает |
| --- | --- |
| `--dry-run` | показать план и ничего не менять |
| `--yes` | не задавать вопросов |
| `--no-deps` | не проверять пакеты |
| `--lang ru\|en` | язык вывода, иначе спросит |
| `--config-dir DIR` | поставить в DIR вместо `~/.config` |

Если хочется одной строкой (исходники скрипт скачает сам):

```sh
curl -fsSL https://github.com/c4rt3z/swayfx-dotfiles/raw/main/install.sh | bash
```

Руками, если так удобнее — весь `~/.config` это git-репозиторий, поэтому
клонируйте его в сторону и переносите папки (не клонируйте поверх своего
`~/.config`):

```sh
git clone https://github.com/c4rt3z/swayfx-dotfiles ~/swayfx-dotfiles
cd ~/swayfx-dotfiles
cp -r sway quickshell waybar wallpaper alacritty kitty matugen \
      gtk-3.0 gtk-4.0 swaylock wofi xsettingsd environment.d ~/.config/
```

Дальше — любым из двух способов:

1. положите обои в `~/Wallpapers` (любые картинки и `.gif` — они анимируются);
2. **перезайдите в сеанс** — `environment.d/10-qt.conf` читается при входе,
   именно так Qt-программы узнают про тему GTK;
3. запустите sway: бар и quickshell поднимутся сами (`exec_always` в `sway/config`);
4. раскрасьте всё из обоев: `~/.config/wallpaper/wallpaper.sh random` или панель
   обоев (`Super+Shift+W`); обоев пока нет? работает и готовая схема:
   `~/.config/wallpaper/wallpaper.sh scheme nord`;
5. клавишам яркости нужны права один раз: `sudo bash ~/.config/sway/fix-backlight.sh`.

### Обновление

Клон — это обычный git-репозиторий: обновите его и запустите установщик снова.
Он уносит в бэкап то, что заменяет, и сохраняет ваше личное — язык интерфейса и
снимок «как было» для горячих клавиш:

```sh
cd ~/swayfx-dotfiles
git pull
./install.sh
```

## Тема

```
обои ──► wallpaper/theme-gen.sh ──► ~/.cache/wallpaper/theme/colors.json
              │                          (палитра Material You)
              ├── gtk-3.0/gtk-4.0  colors.css, settings.ini
              ├── alacritty, kitty         wallpaper.toml / theme.conf
              ├── waybar                   style.css
              ├── quickshell               Colors.qml читает colors.json
              └── swaylock, wofi           та же палитра
```

`apps-theme.py sync` вдобавок переключает приложения между светлым и тёмным: по
яркости палитры выбирается светлый или тёмный вариант GTK, Qt и KDE, поэтому на
светлых обоях программы светлые, на тёмных — тёмные. То же можно сделать руками в
разделе **Внешний вид**.

## Настройки (`Super+,`)

Одно окно quickshell, десять разделов — всё пишется прямо в конфиги:

| Раздел | Что делает |
| --- | --- |
| Главная | сводка по системе и ссылка на репозиторий |
| Внешний вид | обои, набор цветов, светлое/тёмное для всех программ |
| Язык | язык интерфейса (ru, en, uk, de) и регион |
| Приложения | тема программ, сводка GTK/Qt/KDE |
| Панель | модули waybar: что показывать и где |
| Клавиши | все бинды sway в виде «сочетание — команда» с перебиндом |
| Раскладки | раскладки клавиатуры: включить, выключить, выбрать активную |
| Приложения по умолчанию | своё приложение под каждую задачу, как в Windows (терминал, файловый менеджер, браузер, редактор, изображения, видео, музыка, PDF, архивы, почта) |
| Службы | quickshell, waybar, swayidle, playerctld, wireplumber: состояние и перезапуск |

### Перебинд клавиш

Раздел **Клавиши** показывает бинды ровно так, как они записаны в
`~/.config/sway/config`. Щёлкните строку, поменяйте сочетание (набрать руками или
нажать **нажать** и нажать нужное) и/или команду, затем сохраните. Скрипт меняет
только эту часть строки — отступ, флаги, комментарии и соседние строки остаются
как были — и перечитывает конфиг sway. Занятое сочетание молча не отбирается:
настройки предложат поменять бинды местами. Любой бинд можно вернуть как было
(«как было»); снимок для этого лежит в `~/.config/quickshell/keys-default.json`
(создаётся при первом запуске, в репозиторий не входит).

## Поиск (`Super+Space`)

Как Spotlight, опущен на четверть экрана ниже бара. Ищет по приложениям, окнам,
файлам в домашних папках и считает арифметику (`340*15%`). Запрос в неверной
раскладке сопоставляется с правильной, одна-две опечатки прощаются
(`trlegram` → Telegram). Enter запускает первую строку, `Ctrl+1…9` — нужную.

## Языки

Исходный язык — русский: строки написаны по-русски и переводятся через
`~/.config/quickshell/i18n/<код>.json` (если перевода нет — английский, потом
русский). В комплекте `en`, `uk`, `de`. Чтобы добавить свой: положите рядом
`<код>.json` и допишите код в `singletons/Lang.qml` и в
`waybar/scripts/waybar-lang.py` (он переводит тексты модулей бара). Переключение
применяется сразу, перезапускать ничего не надо.

## Горячие клавиши

`Mod` — это <kbd>Super</kbd>. Полный список ровно в том виде, в каком он лежит в
`sway/config`:

**Quickshell**

| Сочетание | Команда |
| --- | --- |
| `Super+.` | `exec sh -c 'python3 $HOME/.config/quickshell/scripts/emoji-anchor.py; qs ipc call panel toggle emoji'` |

**Блокировка**

| Сочетание | Команда |
| --- | --- |
| `Super+Ctrl+Shift+L` | `exec swaylock --config ~/.config/swaylock/config` |

**Яркость**

| Сочетание | Команда |
| --- | --- |
| `Яркость+` | `exec brightnessctl set +5%` |
| `Яркость−` | `exec brightnessctl set 5%-` |

**Звук и медиа**

| Сочетание | Команда |
| --- | --- |
| `XF86AudioPause` | `exec playerctl -p playerctld play-pause` |
| `XF86AudioStop` | `exec playerctl -p playerctld stop` |
| `Громкость+` | `exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` |
| `Громкость−` | `exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-` |
| `Микрофон` | `exec wpctl set-source-mute \@DEFAULT_SOURCE@ toggle` |
| `Плей/пауза` | `exec playerctl -p playerctld play-pause` |
| `Прошлый трек` | `exec playerctl -p playerctld previous` |
| `Следующий трек` | `exec playerctl -p playerctld next` |
| `Тишина` | `exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |

**Скриншоты**

| Сочетание | Команда |
| --- | --- |
| `Super+Shift+S` | `exec sh -c 'grim -g "$(slurp)" - \| wl-copy'` |
| `Снимок экрана` | `exec sh -c 'grim "$HOME/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png"'` |

**Окно**

| Сочетание | Команда |
| --- | --- |
| `Super+Q` | `kill` |

**Фокус**

| Сочетание | Команда |
| --- | --- |
| `Super+Ctrl+Пробел` | `focus mode_toggle` |
| `Super+Down` | `focus down` |
| `Super+H` | `focus left` |
| `Super+J` | `focus down` |
| `Super+K` | `focus up` |
| `Super+L` | `focus right` |
| `Super+Left` | `focus left` |
| `Super+P` | `focus parent` |
| `Super+Right` | `focus right` |
| `Super+Up` | `focus up` |

**Перенос**

| Сочетание | Команда |
| --- | --- |
| `Super+Shift+-` | `move scratchpad` |
| `Super+Shift+0` | `move container to workspace number 10` |
| `Super+Shift+1` | `move container to workspace number 1` |
| `Super+Shift+2` | `move container to workspace number 2` |
| `Super+Shift+3` | `move container to workspace number 3` |
| `Super+Shift+4` | `move container to workspace number 4` |
| `Super+Shift+5` | `move container to workspace number 5` |
| `Super+Shift+6` | `move container to workspace number 6` |
| `Super+Shift+7` | `move container to workspace number 7` |
| `Super+Shift+8` | `move container to workspace number 8` |
| `Super+Shift+9` | `move container to workspace number 9` |
| `Super+Shift+Down` | `move down` |
| `Super+Shift+H` | `move left` |
| `Super+Shift+J` | `move down` |
| `Super+Shift+K` | `move up` |
| `Super+Shift+L` | `move right` |
| `Super+Shift+Left` | `move left` |
| `Super+Shift+Right` | `move right` |
| `Super+Shift+Up` | `move up` |

**Размер**

| Сочетание | Команда |
| --- | --- |
| `Down` | `resize grow height 10px` |
| `H` | `resize shrink width 10px` |
| `J` | `resize grow height 10px` |
| `K` | `resize shrink height 10px` |
| `L` | `resize grow width 10px` |
| `Left` | `resize shrink width 10px` |
| `Right` | `resize grow width 10px` |
| `Up` | `resize shrink height 10px` |

**Раскладка**

| Сочетание | Команда |
| --- | --- |
| `Super+G` | `splith` |
| `Super+M` | `layout tabbed` |
| `Super+S` | `layout stacking` |
| `Super+V` | `splitv` |
| `Super+Z` | `layout toggle split` |

**Рабочие столы**

| Сочетание | Команда |
| --- | --- |
| `Super+0` | `workspace number 10` |
| `Super+1` | `workspace number 1` |
| `Super+2` | `workspace number 2` |
| `Super+3` | `workspace number 3` |
| `Super+4` | `workspace number 4` |
| `Super+5` | `workspace number 5` |
| `Super+6` | `workspace number 6` |
| `Super+7` | `workspace number 7` |
| `Super+8` | `workspace number 8` |
| `Super+9` | `workspace number 9` |

**Режимы**

| Сочетание | Команда |
| --- | --- |
| `Enter` | `mode "default"` |
| `Esc` | `mode "default"` |
| `Super+R` | `mode "resize"` |

**sway**

| Сочетание | Команда |
| --- | --- |
| `Super+Shift+C` | `reload` |

**Прочее**

| Сочетание | Команда |
| --- | --- |
| `Super+,` | `exec qs ipc call panel toggle settings` |
| `Super+-` | `scratchpad show` |
| `Super+A` | `exec qs ipc call panel open launcher` |
| `Super+B` | `exec firefox` |
| `Super+Ctrl+L` | `exec qs ipc call lock lock` |
| `Super+Ctrl+W` | `exec ~/.config/wallpaper/wallpaper.sh random` |
| `Super+E` | `exec dolphin` |
| `Super+Enter` | `exec alacritty` |
| `Super+F` | `fullscreen` |
| `Super+Shift+A` | `exec wofi --show drun` |
| `Super+Shift+E` | `exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -B 'Yes, exit sway' 'swaymsg exit'` |
| `Super+Shift+W` | `exec qs ipc call panel toggle wallpaper` |
| `Super+Shift+Пробел` | `floating toggle` |
| `Super+W` | `floating toggle` |
| `Super+Пробел` | `exec qs ipc call panel toggle search` |

## Мелочи

* Оформление SwayFX — в конце `sway/config`: рамок нет, отступы 8 внутри и 4 до
  краёв, скруглённые углы, тени и блюр, в том числе под waybar и под панелями
  quickshell (`layer_effects`). `blur_ignore_transparent` не даёт панели эмодзи
  размыть весь экран: её поверхность во весь экран, а блюр остаётся только под
  карточкой.
* GIF-обои анимируются движком обоев в quickshell, кадры кэшируются
  (`wallpaper/gif-cache.sh`).
* Панель обоев, поиск и экран блокировки — окна quickshell, поэтому сломавшуюся
  оболочку лечит `pkill -x qs && qs`; `watchdog.sh` поднимает её сам, если она
  упадёт.
* Папка обоев пуста — так и написано в панели, положите картинки в `~/Wallpapers`.
* `.gitignore` — белый список: публикуются только папки из «Что внутри», всё
  остальное в `~/.config` (почта, мессенджеры, ключи, состояние KDE) остаётся
  личным.

## Благодарности

Движок темы, панели, скрипты и переводы — [c4rt3z](https://github.com/c4rt3z).
Построено на [swayfx](https://github.com/Will-Lem/swayfx),
[quickshell](https://quickshell.org), [waybar](https://github.com/Alexays/Waybar) и
[matugen](https://github.com/InioX/matugen).

Идеи и вдохновение:

* [ilyamiro/serpantinum](https://github.com/ilyamiro/serpantinum) — ориентир для
  оболочки в целом: десктоп на quickshell с панелями, поиском и менеджером тем,
  а не просто дотфайлы.
* [luisbocanegra/kde-material-you-colors](https://github.com/luisbocanegra/kde-material-you-colors) —
  идея «обои → палитра Material You → все приложения», набор вариантов схемы
  (vibrant, monochrome, neutral, fruit-salad…) и подход с шаблонами.
* [Material Color Utilities](https://github.com/material-foundation/material-color-utilities)
  от Google — математика цвета Material You, здесь она работает через matugen.
* Готовые схемы: [Catppuccin](https://github.com/catppuccin/catppuccin),
  [Nord](https://www.nordtheme.com/), [Dracula](https://draculatheme.com/),
  [Gruvbox](https://github.com/morhetz/gruvbox),
  [Everforest](https://github.com/sainnhe/everforest),
  [Kanagawa](https://github.com/rebelot/kanagawa.nvim),
  [Tokyo Night](https://github.com/folke/tokyonight.nvim),
  [Rosé Pine](https://github.com/rose-pine/rose-pine-theme) и
  [One Dark](https://github.com/atom/one-dark-syntax) — у каждой своя лицензия.
* [JetBrains Mono](https://www.jetbrains.com/lp/mono/) с патчами
  [Nerd Fonts](https://www.nerdfonts.com/) — единственный шрифт здесь.

## Лицензия

[MIT](LICENSE) © 2026 c4rt3z. Берите, меняйте, публикуйте — только сохраните
копирайт. Сторонние схемы и склонированные темы alacritty остаются под своими
лицензиями.
