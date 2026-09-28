#!/usr/bin/env python3
"""Offline theme selection. Native state is authority; our JSON is observation."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "dotfiles/theme"
# Omarchy v4 uses these fixed paths, even when XDG_STATE_HOME is overridden.
NATIVE = HOME / ".local/state/omarchy/current"
THEMES = Path(__file__).resolve().parent.parent / "themes"
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
REVIEWED = {
    "catppuccin": {"plugin": "catppuccin/nvim", "name": "catppuccin", "colorscheme": "catppuccin-nvim"},
    "everforest": {"plugin": "neanias/everforest-nvim", "name": "everforest-nvim", "colorscheme": "everforest", "background": "soft"},
    "tokyo-night": {"plugin": "folke/tokyonight.nvim", "name": "tokyonight.nvim", "colorscheme": "tokyonight-night"},
}


def catalog():
    data = json.loads((THEMES / "catalog.json").read_text())
    if data["version"] != 1 or set(data["supported"]) != set(REVIEWED):
        raise ValueError("unsupported theme catalog")
    for slug, spec in data["supported"].items():
        if not SLUG.fullmatch(slug) or slug not in data["eligible"]:
            raise ValueError("invalid supported theme")
        if spec["colors"] != f"{slug}/colors.toml":
            raise ValueError("invalid palette path")
        if spec["neovim"] != REVIEWED[slug]:
            raise ValueError(f"unreviewed Neovim mapping: {slug}")
        colors = tomllib.loads((THEMES / spec["colors"]).read_text())
        for key in ("background", "foreground", "accent"):
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", colors[key]):
                raise ValueError(f"invalid {slug} palette: {key}")
    return data


def native_snapshot(data):
    # Read-lock the existing native staging lock without creating anything in
    # read-only status/check. Native releases it before invoking user hooks.
    path = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "omarchy-theme-set.lock"
    try:
        lock = path.open("rb")
    except FileNotFoundError:
        return stable_snapshot(data)
    with lock:
        fcntl.flock(lock, fcntl.LOCK_SH)
        return stable_snapshot(data)


def stable_snapshot(data):
    # Native staging briefly removes current/theme. Retry a coherent read; old
    # hook event arguments are deliberately ignored. No lock inversion with the
    # native theme command, which holds its own lock during staging.
    for _ in range(20):
        try:
            name = (NATIVE / "theme.name").read_text().strip()
            if not SLUG.fullmatch(name):
                raise ValueError("invalid native theme name")
            files = {key: hashlib.sha256((NATIVE / "theme" / key).read_bytes()).hexdigest()
                     for key in ("colors.toml", "neovim.lua")}
            if name == (NATIVE / "theme.name").read_text().strip():
                result = {"version": 1, "host": "omarchy", "theme": name,
                          "supported": name in data["supported"], "inputs": files}
                if result == native_snapshot_once(data):
                    return result
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    raise ValueError("native theme state unavailable or changing; retry after theme selection")


def native_snapshot_once(data):
    name = (NATIVE / "theme.name").read_text().strip()
    return {"version": 1, "host": "omarchy", "theme": name,
            "supported": name in data["supported"],
            "inputs": {key: hashlib.sha256((NATIVE / "theme" / key).read_bytes()).hexdigest()
                       for key in ("colors.toml", "neovim.lua")}}


def read_state():
    try:
        return json.loads((STATE / "current.json").read_text())
    except (FileNotFoundError, ValueError):
        return None


def hook_error():
    try:
        return (STATE / "hook-error").read_text().strip() or "native theme hook failed"
    except FileNotFoundError:
        return None


def sync(data):
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / "sync.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        snapshot = native_snapshot(data)
        if snapshot != read_state():
            fd, temporary = tempfile.mkstemp(prefix=".current-", dir=STATE)
            try:
                with os.fdopen(fd, "w") as output:
                    json.dump(snapshot, output, indent=2)
                    output.write("\n")
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(temporary, STATE / "current.json")
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        return snapshot


def report(snapshot, fresh, data):
    print(f"host: omarchy\ntheme: {snapshot['theme']}")
    print("support: " + ("reviewed" if snapshot["supported"] else
                          "unsupported; personal Neovim falls back to Tokyo Night"))
    print("synchronization: " + ("current" if fresh else "stale or absent; run dotfiles-theme sync"))
    hook = CONFIG / "omarchy/hooks/theme-set.d/90-dotfiles-theme"
    print("native-hook: " + ("installed" if hook.is_file() and os.access(hook, os.X_OK) else
                             "absent; apply desktop for native-event synchronization"))
    failure = hook_error()
    if failure:
        print("native-hook-error: " + failure)
    nvim = CONFIG / "nvim-matt/lua/config/dotfiles_theme.lua"
    if nvim.is_file():
        selected = snapshot["theme"] if snapshot["supported"] else "tokyo-night"
        plugin = data["supported"][selected]["neovim"]["name"]
        plugin_path = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "nvim-matt/lazy" / plugin
        print("neovim: " + ("native-state watcher; restart pre-integration sessions once" if plugin_path.is_dir()
                           else "plugin absent; run dotfiles.sh apply nvim"))
    else:
        print("neovim: personal integration absent")
    print("opencode: " + ("native system theme; restart session if native reload does not retint it"
                           if shutil.which("opencode") else "absent"))
    print("herdr: " + ("native terminal palette; reconnect if existing session retains colors"
                        if shutil.which("herdr") else "absent"))
    print("bash/starship: native terminal palette and native prompt settings")


def main():
    host, *args = sys.argv[1:]
    command = args[0] if args else "status"
    if command in ("-h", "--help"):
        print("usage: dotfiles-theme [list | set <slug> | status]\nInternal lifecycle: sync | check")
        return 0
    if command not in ("list", "set", "status", "sync", "check") or len(args) != (2 if command == "set" else (0 if not args else 1)):
        raise ValueError("usage: dotfiles-theme [list | set <slug> | status]")
    data = catalog()
    if command == "list":
        print("\n".join(sorted(data["supported"])))
        return 0
    if command == "set" and args[1] not in data["supported"]:
        raise ValueError(f"unsupported theme: {args[1]}; see dotfiles-theme list")
    if host == "ubuntu":
        selection = CONFIG / "dotfiles/local/theme"
        value = selection.read_text().strip() if selection.exists() else "tokyo-night"
        valid = value in data["supported"]
        print(f"host: ubuntu\ntheme: {value if valid else 'tokyo-night'}" +
              (" (fallback; invalid local selection)" if not valid else ""))
        print("integration: pending Ubuntu phase; application configuration unchanged")
        return 2 if command in ("set", "sync") else 1
    if command == "set":
        # Never hold the synchronization lock while the native command runs its hook.
        subprocess.run(["omarchy", "theme", "set", args[1]], check=True)
    if command in ("sync", "set"):
        snapshot = sync(data)
    else:
        snapshot = native_snapshot(data)
    fresh = snapshot == read_state()
    failure = hook_error()
    if command == "check":
        if not fresh:
            print("theme synchronization stale or absent; run dotfiles-theme sync", file=sys.stderr)
        if failure:
            print(failure, file=sys.stderr)
        return 0 if fresh and not failure else 1
    if command == "sync":
        return 0
    report(snapshot, fresh, data)
    return 0 if fresh and snapshot["supported"] and not failure else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"dotfiles-theme: {error}", file=sys.stderr)
        sys.exit(2)
