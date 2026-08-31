#!/usr/bin/env python3

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "manifests/desktop-shortcuts.json"
def output_paths(root=ROOT):
    root = Path(root)
    return {
        "xcompose": root / "packages/omarchy/desktop/.config/dotfiles/omarchy/XCompose",
        "menu": root / "packages/omarchy/desktop/.config/dotfiles/omarchy/menu-shortcuts.jsonc",
        "helper": root / "packages/omarchy/desktop/.local/bin/dotfiles-omarchy-compose-shortcut",
        "binding": root / "packages/omarchy/desktop/.config/dotfiles/omarchy/hypr/bindings.lua",
    }


OUTPUTS = output_paths()

SAFE_SLUG = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")
COMPOSE_KEY = re.compile(r"(?:[A-Za-z0-9]|space)")
SOURCES = {"managed", "host", "omarchy"}


def _exact_fields(value, fields, description):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise ValueError(f"invalid {description} fields")


def _single_line(value, description):
    if not isinstance(value, str) or not value.strip() or "\n" in value or "\r" in value:
        raise ValueError(f"invalid {description}")


def _safe_slug(value, description):
    if not isinstance(value, str) or not SAFE_SLUG.fullmatch(value):
        raise ValueError(f"invalid {description}")


def _compose_key(value, description):
    if not isinstance(value, str) or not COMPOSE_KEY.fullmatch(value):
        raise ValueError(f"invalid {description}; use 'space' or one ASCII letter/digit")


def sequence_for(shortcut, groups_by_id):
    return ("Multi_key", groups_by_id[shortcut["group"]]["prefix"], shortcut["key"])


def native_references(data):
    validate_manifest(data)
    groups_by_id = {group["id"]: group for group in data["groups"]}
    return [
        (item["source"], item["id"], *sequence_for(item, groups_by_id))
        for item in data["shortcuts"]
        if item["source"] != "managed"
    ]


def validate_manifest(data):
    _exact_fields(
        data,
        {"_instructions", "version", "menu", "binding", "groups", "shortcuts"},
        "manifest",
    )
    if type(data["version"]) is not int or data["version"] != 2:
        raise ValueError("unsupported manifest version")
    _single_line(data["_instructions"], "manifest instructions")

    menu = data["menu"]
    _exact_fields(menu, {"id", "icon", "label", "aliases"}, "menu")
    _safe_slug(menu["id"], "menu ID")
    _single_line(menu["icon"], "menu icon")
    _single_line(menu["label"], "menu label")
    if not isinstance(menu["aliases"], list):
        raise ValueError("invalid menu aliases")
    for alias in menu["aliases"]:
        _safe_slug(alias, "menu alias")
    if len(menu["aliases"]) != len(set(menu["aliases"])):
        raise ValueError("duplicate menu alias")

    binding = data["binding"]
    _exact_fields(binding, {"keys", "description"}, "binding")
    _single_line(binding["keys"], "binding keys")
    _single_line(binding["description"], "binding description")

    groups = data["groups"]
    shortcuts = data["shortcuts"]
    if not isinstance(groups, list) or not isinstance(shortcuts, list):
        raise ValueError("groups and shortcuts must be lists")

    for group in groups:
        _exact_fields(group, {"id", "name", "prefix"}, "group")
        _safe_slug(group["id"], "group ID")
        _single_line(group["name"], "group name")
        _compose_key(group["prefix"], "group prefix")
        if group["id"] == "manage":
            raise ValueError("group ID conflicts with management action")

    group_ids = [group["id"] for group in groups]
    group_names = [group["name"] for group in groups]
    if len(group_ids) != len(set(group_ids)):
        raise ValueError("duplicate group ID")
    if len(group_names) != len(set(group_names)):
        raise ValueError("duplicate group name")
    groups_by_id = {group["id"]: group for group in groups}

    for shortcut in shortcuts:
        if not isinstance(shortcut, dict):
            raise ValueError("invalid shortcut fields")
        source = shortcut.get("source")
        if not isinstance(source, str) or source not in SOURCES:
            raise ValueError("invalid shortcut source")
        expected = {"id", "group", "key", "label", "source"}
        if source == "managed":
            expected.add("output")
        _exact_fields(shortcut, expected, "shortcut")
        _safe_slug(shortcut["id"], "shortcut ID")
        if shortcut["group"] not in groups_by_id:
            raise ValueError("shortcut references unknown group")
        _compose_key(shortcut["key"], "shortcut key")
        _single_line(shortcut["label"], "shortcut label")
        if source == "managed":
            _single_line(shortcut["output"], "shortcut output")

    shortcut_ids = [shortcut["id"] for shortcut in shortcuts]
    if len(shortcut_ids) != len(set(shortcut_ids)):
        raise ValueError("duplicate shortcut ID")
    routes = [(shortcut["group"], shortcut["key"]) for shortcut in shortcuts]
    if len(routes) != len(set(routes)):
        raise ValueError("duplicate shortcut route")
    sequences = [sequence_for(shortcut, groups_by_id) for shortcut in shortcuts]
    if len(sequences) != len(set(sequences)):
        raise ValueError("duplicate Compose sequence")
    prefixes = [group["prefix"] for group in groups]
    if len(prefixes) != len(set(prefixes)):
        raise ValueError("duplicate group prefix")
    return data


def load_manifest(path=MANIFEST):
    return validate_manifest(json.loads(Path(path).read_text()))


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def render(data):
    validate_manifest(data)
    menu = data["menu"]
    binding = data["binding"]
    shortcuts = data["shortcuts"]
    groups_by_id = {group["id"]: group for group in data["groups"]}

    xcompose = "\n".join(
        f'<{sequence[0]}> <{sequence[1]}> <{sequence[2]}> : {json.dumps(item["output"], ensure_ascii=False)}'
        for item in shortcuts
        if item["source"] == "managed"
        for sequence in [sequence_for(item, groups_by_id)]
    ) + "\n"

    menu_lines = [
        f'  {compact(menu["id"])}: '
        f'{compact({"icon": menu["icon"], "label": menu["label"], "aliases": menu["aliases"]})},'
    ]
    for group in data["groups"]:
        route = f'{menu["id"]}.{group["id"]}'
        menu_lines.append(f'  {compact(route)}: {compact({"label": f"{group["name"]} ({group["prefix"]})"})},')
        for item in (item for item in shortcuts if item["group"] == group["id"]):
            action = f'"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut" {item["id"]}'
            menu_lines.append(
                f'  {compact(route + "." + item["key"])}: '
                f'{compact({"label": item["label"], "action": action})},'
            )
    menu_lines.append(
        f'  {compact(menu["id"] + ".manage")}: '
        f'{compact({"label": "Manage shortcuts...", "action": "dotfiles-shortcuts manage"})},'
    )
    menu_fragment = "\n".join(menu_lines) + "\n"

    cases = "\n".join(
        f'  {item["id"]}) sequence=({" ".join(sequence_for(item, groups_by_id))}) ;;'
        for item in shortcuts
    )
    helper = f'''#!/usr/bin/env bash

set -Eeuo pipefail

case "${{1:-}}" in
{cases}
  *)
    printf 'dotfiles-omarchy-compose-shortcut: unknown shortcut: %s\\n' "${{1:-}}" >&2
    exit 64
    ;;
esac

command -v wtype >/dev/null 2>&1 || {{
  printf 'dotfiles-omarchy-compose-shortcut: wtype is unavailable\\n' >&2
  exit 127
}}

exec wtype -s 180 -k "${{sequence[0]}}" -k "${{sequence[1]}}" -k "${{sequence[2]}}"
'''
    binding_fragment = (
        f'o.bind({compact(binding["keys"])}, {compact(binding["description"])}, '
        f'{compact("omarchy-menu toggle " + menu["id"])})\n'
    )
    return {"xcompose": xcompose, "menu": menu_fragment, "helper": helper, "binding": binding_fragment}
