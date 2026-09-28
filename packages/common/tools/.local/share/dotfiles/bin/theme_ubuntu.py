"""Ubuntu adapters. Publish complete generations; never write through Stow links."""
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import tomllib


def encoded(value):
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def regular(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
        raise ValueError(f"not a user-owned regular file: {path}")


def directory(path):
    # Permit ordinary group-writable user homes, but never follow directory links.
    if not path.is_absolute():
        raise ValueError(f"expected absolute path: {path}")
    for parent in reversed((path, *path.parents)):
        if parent.exists() or parent.is_symlink():
            if parent.is_symlink() or not parent.is_dir():
                raise ValueError(f"unsafe generated-output parent: {parent}")
        else:
            parent.mkdir(mode=0o700)
    if path.stat().st_uid != os.geteuid():
        raise ValueError(f"directory is not user-owned: {path}")


def atomic(path, text):
    directory(path.parent)
    if path.exists() or path.is_symlink():
        regular(path)
        if path.read_text() == text:
            return
    fd, temporary = tempfile.mkstemp(prefix=".theme-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def selection(config, supported):
    path = config / "dotfiles/local/theme"
    try:
        regular(path)
        value = path.read_text()
        if value in {slug + "\n" for slug in supported}:
            return value.strip(), None
        return "tokyo-night", "invalid local selection"
    except FileNotFoundError:
        return "tokyo-night", "no local selection"
    except (OSError, ValueError):
        return "tokyo-night", "invalid local selection"


# Reviewed against OpenCode 1.18.32 packages/tui/src/theme/index.ts.
OPENCODE_COLORS = {
    "primary": "accent", "secondary": "magenta", "accent": "accent",
    "error": "red", "warning": "yellow", "success": "green", "info": "blue",
    "text": "foreground", "textMuted": "dark_foreground",
    "selectedListItemText": "background", "background": "background",
    "backgroundPanel": "dark_background", "backgroundElement": "lighter_background",
    "backgroundMenu": "lighter_background", "border": "muted",
    "borderActive": "accent", "borderSubtle": "selection",
    "diffAdded": "green", "diffRemoved": "red", "diffContext": "foreground",
    "diffHunkHeader": "cyan", "diffHighlightAdded": "bright_green",
    "diffHighlightRemoved": "bright_red", "diffAddedBg": "dark_background",
    "diffRemovedBg": "dark_background", "diffContextBg": "background",
    "diffLineNumber": "dark_foreground", "diffAddedLineNumberBg": "dark_background",
    "diffRemovedLineNumberBg": "dark_background", "markdownText": "foreground",
    "markdownHeading": "accent", "markdownLink": "blue", "markdownLinkText": "cyan",
    "markdownCode": "green", "markdownBlockQuote": "yellow", "markdownEmph": "yellow",
    "markdownStrong": "bright_foreground", "markdownHorizontalRule": "muted",
    "markdownListItem": "blue", "markdownListEnumeration": "cyan",
    "markdownImage": "blue", "markdownImageText": "cyan", "markdownCodeBlock": "foreground",
    "syntaxComment": "dark_foreground", "syntaxKeyword": "magenta",
    "syntaxFunction": "blue", "syntaxVariable": "foreground", "syntaxString": "green",
    "syntaxNumber": "orange", "syntaxType": "cyan", "syntaxOperator": "cyan",
    "syntaxPunctuation": "foreground",
}

# All CustomThemeColors fields in Herdr v0.8.2 src/config/theme.rs.
HERDR_COLORS = {
    "accent": "accent", "panel_bg": "background", "sidebar_bg": "dark_background",
    "active_row_bg": "lighter_background", "selection_bg": "selection",
    "surface0": "lighter_background", "surface1": "selection", "surface_dim": "dark_background",
    "overlay0": "muted", "overlay1": "dark_foreground", "text": "foreground",
    "subtext0": "dark_foreground", "mauve": "magenta", "green": "green",
    "yellow": "yellow", "red": "red", "blue": "blue", "teal": "cyan", "peach": "orange",
}


def outputs(repo, colors, slug):
    for value in colors.values():
        if value != "dark" and not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise ValueError("invalid portable palette")
    tui = json.loads((repo / "packages/common/opencode/.config/dotfiles/opencode/tui.jsonc").read_text())
    tui["theme"] = "dotfiles-host"
    herdr = (repo / "packages/ubuntu/herdr/.config/herdr/config.toml").read_text()
    base = tomllib.loads(herdr)
    custom = {key: colors[value] for key, value in HERDR_COLORS.items()}
    # Transform only the reviewed theme tables and ui.accent; retain every other byte.
    herdr, count = re.subn(r'(?ms)^\[theme\]\n.*?(?=^\[terminal\])',
                          '[theme]\nname = "catppuccin"\nauto_switch = false\n\n[theme.custom]\n' +
                          ''.join(f'{key} = "{value}"\n' for key, value in custom.items()) + '\n', herdr)
    herdr, accent_count = re.subn(r'(?m)^accent = "blue"$', f'accent = "{colors["accent"]}"', herdr)
    parsed = tomllib.loads(herdr)
    parsed.pop("theme")
    parsed["ui"]["accent"] = base["ui"]["accent"]
    base.pop("theme")
    if count != 1 or accent_count != 1 or parsed != base:
        raise ValueError("Herdr baseline no longer matches the reviewed theme derivation")
    starship = (repo / "packages/upstream/starship/.config/starship.toml").read_text()
    starship = starship.replace("cyan", colors["accent"])
    # Explicitly color the directory too; its implicit Starship default was ANSI cyan.
    starship = starship.replace("[directory]\n", f'[directory]\nstyle = "bold {colors["accent"]}"\n')
    tomllib.loads(starship)
    return {
        "opencode-theme.json": encoded({"theme": {k: colors[v] for k, v in OPENCODE_COLORS.items()}}),
        "opencode-tui.json": encoded(tui),
        "herdr.toml": herdr,
        "starship.toml": starship,
        "accent": colors["accent"] + "\n",
        "selection": slug + "\n",
    }


def current_matches(current, expected):
    try:
        return (current.is_symlink() and re.fullmatch(r"generation-[\w-]+", os.readlink(current)) and
                all(not (current / key).is_symlink() and (current / key).read_text() == value
                    for key, value in expected.items()))
    except OSError:
        return False


def link(path, target):
    directory(path.parent)
    if path.is_symlink() and os.readlink(path) == str(target):
        return
    if path.exists() or path.is_symlink():
        raise ValueError(f"generated theme link conflicts with existing path: {path}")
    path.symlink_to(target)


def run(command, args, data, themes, config, state):
    # Read an existing lock only: status/check must never create state.
    if command in ("status", "check"):
        try:
            lock = (state / "ubuntu/sync.lock").open("rb")
        except FileNotFoundError:
            pass
        else:
            with lock:
                fcntl.flock(lock, fcntl.LOCK_SH)
                return run_locked(command, args, data, themes, config, state)
    return run_locked(command, args, data, themes, config, state)


def run_locked(command, args, data, themes, config, state):
    repo = next(parent for parent in Path(__file__).resolve().parents if (parent / "manifests/areas.tsv").is_file())
    selected, reason = selection(config, data["supported"])
    slug = args[1] if command == "set" else selected
    colors = tomllib.loads((themes / data["supported"][slug]["colors"]).read_text())
    expected = outputs(repo, colors, slug)
    root = state / "ubuntu"
    current = root / "current"
    theme_link = config / "opencode/themes/dotfiles-host.json"
    target = current / "opencode-theme.json"
    opencode = (Path.home() / ".local/share/dotfiles/bin/opencode-launch").is_file()

    def fresh():
        return current_matches(current, expected) and (not opencode or
                (theme_link.is_symlink() and os.readlink(theme_link) == str(target)))

    if command in ("set", "sync"):
        directory(root)
        lock_path = root / "sync.lock"
        if lock_path.exists() or lock_path.is_symlink():
            regular(lock_path)
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            # A sync waiting behind set must consume the latest selection.
            if command == "sync":
                slug, reason = selection(config, data["supported"])
                colors = tomllib.loads((themes / data["supported"][slug]["colors"]).read_text())
                expected = outputs(repo, colors, slug)
            selection_path = config / "dotfiles/local/theme"
            if command == "set":
                directory(selection_path.parent)
                if selection_path.exists() or selection_path.is_symlink():
                    regular(selection_path)
            if current.exists() or current.is_symlink():
                if not current.is_symlink() or not re.fullmatch(r"generation-[\w-]+", os.readlink(current)):
                    raise ValueError(f"unexpected generation pointer: {current}")
            previous = os.readlink(current) if current.is_symlink() else None
            if not current_matches(current, expected):
                generation = Path(tempfile.mkdtemp(prefix="generation-", dir=root))
                for name, content in expected.items():
                    atomic(generation / name, content)
                runtime = Path.home() / ".local/share/mise/installs/aqua-ogulcancelik-herdr/0.8.2/herdr"
                if runtime.is_file() and (Path.home() / ".config/herdr/config.toml").is_file():
                    with tempfile.TemporaryDirectory(prefix="validate-", dir=root) as temporary_home:
                        env = dict(os.environ, HOME=temporary_home, HERDR_CONFIG_PATH=str(generation / "herdr.toml"),
                                   XDG_CONFIG_HOME=temporary_home, XDG_STATE_HOME=temporary_home,
                                   XDG_DATA_HOME=temporary_home, XDG_CACHE_HOME=temporary_home)
                        checked = subprocess.run([str(runtime), "config", "check"], env=env,
                                                 capture_output=True, text=True, timeout=15)
                        if checked.returncode:
                            raise ValueError("generated Herdr config failed validation: " +
                                             (checked.stderr or checked.stdout or str(checked.returncode)).strip())
                if opencode:
                    link(theme_link, target)
                temporary = root / ".current"
                if temporary.is_symlink():
                    temporary.unlink()
                temporary.symlink_to(generation.name)
                os.replace(temporary, current)
            elif opencode:
                link(theme_link, target)
            if command == "set":
                try:
                    atomic(selection_path, slug + "\n")
                except (OSError, ValueError):
                    # A failed selection write must not leave the published palette changed.
                    if previous is None:
                        current.unlink(missing_ok=True)
                    else:
                        temporary = root / ".rollback"
                        temporary.symlink_to(previous)
                        os.replace(temporary, current)
                    raise
                reason = None
            synchronized = fresh()
        # Retain previous generations: existing processes may have resolved their paths.
    else:
        synchronized = fresh()
    print(f"host: ubuntu\ntheme: {slug}" + (f" (fallback; {reason})" if reason else ""))
    print("synchronization: " + ("current" if synchronized else "stale or absent; run dotfiles-theme sync"))
    print("neovim: selection watcher when personal nvim is deployed; restart pre-integration instances once")
    print("opencode: explicit palette in both named profiles; quit and restart existing sessions" +
          ("" if opencode else "; managed launcher absent"))
    print("herdr: managed launcher uses explicit UI palette; reload-config then reconnect; pre-integration servers need restart")
    print("bash/starship: next prompt in integrated shells; open a new shell once after deployment")
    return 0 if synchronized else 1
