#!/usr/bin/env python3
"""Правила окон: какое окно где живёт.

    window-rules.py list              — правила и список приложений (JSON)
    window-rules.py add <app> <стол>  — добавить правило
    window-rules.py remove <id>       — убрать правило
    window-rules.py apply             — перегенерировать файл для sway

Правила хранятся в ~/.config/quickshell/window-rules.json, а для sway
переписывается ~/.config/sway/window-rules — его подключает include в
sway/config. Так правила применяет сам sway (никаких фоновых процессов и
опросов дерева окон).

Правило: {"id": "firefox-2", "app": "firefox", "workspace": 2, "floating": false}
— приложение app (имя процесса или часть заголовка) всегда на столе workspace,
плавающим или нет. Поле app можно оставить пустым, чтобы правило било по
любому окну.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
FILE = f"{HOME}/.config/quickshell/window-rules.json"
SWAY_INCLUDE = f"{HOME}/.config/sway/window-rules"


def load():
    try:
        with open(FILE, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = {}
    rules = data.get("rules")
    return rules if isinstance(rules, list) else []


def save(rules):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    tmp = f"{FILE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"rules": rules}, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, FILE)


def running_apps():
    """Приложения, которые сейчас запущены (для подсказки в настройках)."""
    names = set()
    try:
        out = subprocess.run(["swaymsg", "-t", "get_tree"], capture_output=True,
                             text=True, timeout=4).stdout
        data = json.loads(out or "null")
    except Exception:
        data = None
    if not data:
        return []
    def walk(node):
        app = node.get("app_id") or ""
        if not app:
            props = node.get("window_properties") or {}
            app = props.get("class") or ""
        if app:
            names.add(app)
        for child in node.get("nodes", []) or []:
            walk(child)
    walk(data)
    return sorted(names)


def criteria(rule):
    """Критерий sway для правила."""
    app = str(rule.get("app") or "").strip()
    if not app:
        return "[all]"
    return f'[app_id="^{app}$"]'


def apply():
    """Перегенерировать файл, который подключает sway."""
    lines = [
        "# Правила окон. Файл переписывается скриптом",
        "# quickshell/scripts/window-rules.py — правьте правила в настройках",
        "# или через window-rules.py, руками не нужно.",
        "",
    ]
    for rule in load():
        crit = criteria(rule)
        workspace = rule.get("workspace")
        if workspace:
            lines.append(f"for_window {crit} move to workspace {int(workspace)}")
        if rule.get("floating"):
            lines.append(f"for_window {crit} floating enable")
        else:
            lines.append(f"for_window {crit} floating disable")
    text = "\n".join(lines) + "\n"
    try:
        os.makedirs(os.path.dirname(SWAY_INCLUDE), exist_ok=True)
        with open(SWAY_INCLUDE, "w", encoding="utf-8") as fh:
            fh.write(text)
    except OSError as exc:
        print(f"не записать {SWAY_INCLUDE}: {exc}", file=sys.stderr)
        return 1
    return 0


def main(argv):
    if not argv or argv[0] == "list":
        print(json.dumps({"ok": True, "rules": load(), "apps": running_apps()},
                         ensure_ascii=False))
        return 0

    if argv[0] == "add" and len(argv) >= 3:
        app = argv[1].strip()
        try:
            workspace = int(argv[2])
        except ValueError:
            workspace = 0
        rules = load()
        rid = f"{app or 'all'}-{workspace}"
        rules = [r for r in rules if r.get("id") != rid]
        rules.append({"id": rid, "app": app, "workspace": workspace,
                      "floating": False})
        save(rules)
        apply()
        print(json.dumps({"ok": True, "rules": rules}, ensure_ascii=False))
        return 0

    if argv[0] == "remove" and len(argv) >= 2:
        rules = [r for r in load() if r.get("id") != argv[1]]
        save(rules)
        apply()
        print(json.dumps({"ok": True, "rules": rules}, ensure_ascii=False))
        return 0

    if argv[0] == "apply":
        return apply()

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
