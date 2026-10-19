#!/usr/bin/env python3
"""Список окон для переключателя (Alt+Tab).

    switcher.py list            — окна верхнего уровня: id, app, title, workspace
    switcher.py focus <id>      — перейти к окну (и на его рабочий стол)
    switcher.py next [prev]     — сразу следующее (предыдущее) окно

Окна берём из swaymsg -t get_tree: слоистые панели quickshell туда не попадают,
а порядок обхода совпадает с порядком в дереве — то есть с порядком на экране.
"""
import json
import subprocess
import sys


def sway(*args):
    return subprocess.run(["swaymsg", *args], check=True, capture_output=True, text=True).stdout


def views(node, out, workspace=""):
    """Рекурсивно собираем листовые окна; контейнеры и скретчпад пропускаем."""
    if not isinstance(node, dict):
        return
    name = node.get("name") or ""
    if name.startswith("__"):
        return
    if node.get("pid") and node.get("type") == "con" and not node.get("nodes"):
        app = node.get("app_id") or ""
        props = node.get("window_properties") or {}
        if not app:
            app = props.get("class") or props.get("instance") or ""
        title = (node.get("name") or "").strip()
        for ch in ("\u200e", "\u200f", "\u202a", "\u202b", "\u202c", "\u2066", "\u2067", "\u2068", "\u2069"):
            title = title.replace(ch, "")
        if title or app:
            out.append({
                "id": node.get("id"),
                "app": str(app),
                "title": str(title),
                "workspace": workspace,
                "focused": bool(node.get("focused")),
            })
        return
    for child in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
        views(child, out, workspace)


def window_list():
    tree = json.loads(sway("-t", "get_tree", "--raw"))
    out = []
    for output in tree.get("nodes") or []:
        for ws in output.get("nodes") or []:
            if (ws.get("name") or "").startswith("__"):
                continue
            name = ws.get("name") or ""
            for child in (ws.get("nodes") or []) + (ws.get("floating_nodes") or []):
                views(child, out, name)
    return out


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    what = argv[0]

    if what == "list":
        print(json.dumps({"windows": window_list()}, ensure_ascii=False))
        return 0

    if what == "focus":
        if len(argv) < 2:
            return 1
        sway(f"[con_id={argv[1]}]", "focus")
        return 0

    if what in ("next", "prev"):
        windows = window_list()
        if not windows:
            return 0
        current = next((i for i, w in enumerate(windows) if w["focused"]), -1)
        step = -1 if what == "prev" else 1
        target = windows[(current + step) % len(windows)]
        sway(f"[con_id={target['id']}]", "focus")
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
