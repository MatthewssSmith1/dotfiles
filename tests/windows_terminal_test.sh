#!/usr/bin/env bash

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly MANAGED="$REPO_DIR/windows/terminal/managed-settings.json"
readonly APPLY="$REPO_DIR/windows/terminal/apply.ps1"

jq -e '
  keys == ["profileDefaults", "schemes"] and
  (.profileDefaults | keys == ["colorScheme", "cursorShape", "font", "padding", "scrollbarState", "useAcrylic"]) and
  (.profileDefaults.font | keys == ["face", "size"]) and
  (.schemes | length == 1) and
  (.schemes[0] | keys == [
    "background", "black", "blue", "brightBlack", "brightBlue", "brightCyan",
    "brightGreen", "brightPurple", "brightRed", "brightWhite", "brightYellow",
    "cursorColor", "cyan", "foreground", "green", "name", "purple", "red",
    "selectionBackground", "white", "yellow"
  ]) and
  (.schemes[0] == {
    "background": "#1A1B26",
    "black": "#1A1B26",
    "blue": "#7AA2F7",
    "brightBlack": "#414868",
    "brightBlue": "#7DA6FF",
    "brightCyan": "#0DB9D7",
    "brightGreen": "#B9F27C",
    "brightPurple": "#BB9AF7",
    "brightRed": "#FF7A93",
    "brightWhite": "#C0CAF5",
    "brightYellow": "#FF9E64",
    "cursorColor": "#C0CAF5",
    "cyan": "#449DAB",
    "foreground": "#A9B1D6",
    "green": "#9ECE6A",
    "name": "Omarchy Tokyo Night",
    "purple": "#AD8EE6",
    "red": "#F7768E",
    "selectionBackground": "#292E42",
    "white": "#A9B1D6",
    "yellow": "#E0AF68"
  })
' "$MANAGED" >/dev/null || fail 'managed Windows Terminal JSON shape or palette is invalid'
pass

# The script may touch only managed profile-default keys, their per-profile
# shadows, and schemes selected by name. Actions and keybindings stay manual.
grep -Fq '$managed.profileDefaults.PSObject.Properties' "$APPLY" || fail 'profile-default merge is missing'
grep -Fq '$live.profiles.defaults' "$APPLY" || fail 'profile defaults are not the merge target'
grep -Fq '$live.profiles.list' "$APPLY" || fail 'per-profile managed-key cleanup is missing'
grep -Fq '$live.schemes' "$APPLY" || fail 'scheme merge is missing'
if grep -E '^[[:space:]]*[^#].*\$live\.(actions|keybindings)' "$APPLY" >/dev/null; then
  fail 'merge script manages actions or keybindings'
fi
if grep -Fq 'windows/terminal/apply.ps1' "$DOTFILES"; then
  fail 'Windows Terminal is coupled to dotfiles'
fi
pass

# PowerShell adds behavioral fixture coverage when a compatible runtime exists.
powershell=""
if command -v pwsh >/dev/null 2>&1; then
  powershell="$(command -v pwsh)"
elif command -v powershell >/dev/null 2>&1; then
  powershell="$(command -v powershell)"
fi

if [[ -n "$powershell" ]]; then
  localapp="$TEST_ROOT/local-app-data"
  settings_dir="$localapp/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  settings="$settings_dir/settings.json"
  mkdir -p "$settings_dir"
  cat > "$settings" <<'JSON'
{
  "profiles": {
    "defaults": { "historySize": 1234 },
    "list": [
      { "guid": "{fixture-guid}", "name": "Fixture", "commandline": "ssh fixture", "colorScheme": "Old" }
    ]
  },
  "schemes": [
    { "name": "Unmanaged", "background": "#000000" },
    { "name": "Omarchy Tokyo Night", "background": "#FFFFFF" }
  ],
  "actions": [ { "command": "copy", "keys": "ctrl+c" } ],
  "keybindings": [ { "command": "paste", "keys": "ctrl+v" } ],
  "unrelated": { "preserve": true }
}
JSON
  before="$(sha256sum "$settings")"
  LOCALAPPDATA="$localapp" "$powershell" -NoProfile -File "$APPLY" -DryRun > "$TEST_ROOT/windows-terminal-dry-run.log"
  [[ "$(sha256sum "$settings")" == "$before" && ! -e "$settings.bak" ]] || fail 'Windows Terminal dry-run mutated fixture settings'
  LOCALAPPDATA="$localapp" "$powershell" -NoProfile -File "$APPLY" >/dev/null
  first="$(sha256sum "$settings")"
  LOCALAPPDATA="$localapp" "$powershell" -NoProfile -File "$APPLY" >/dev/null
  [[ "$(sha256sum "$settings")" == "$first" ]] || fail 'Windows Terminal merge is not idempotent'
  jq -e '
    .unrelated.preserve == true and
    (.actions == [{"command":"copy","keys":"ctrl+c"}]) and
    (.keybindings == [{"command":"paste","keys":"ctrl+v"}]) and
    (.profiles.list | length == 1) and
    (.profiles.list[0].guid == "{fixture-guid}") and
    (.profiles.list[0].commandline == "ssh fixture") and
    (.profiles.list[0] | has("colorScheme") | not) and
    ([.schemes[] | select(.name == "Unmanaged")] | length == 1) and
    ([.schemes[] | select(.name == "Omarchy Tokyo Night")] | length == 1)
  ' "$settings" >/dev/null || fail 'Windows Terminal merge did not preserve the unmanaged surface'
  pass
else
  printf 'SKIP: PowerShell unavailable; Windows Terminal fixture merge checks skipped\n'
fi

printf 'PASS: %s Windows Terminal test groups\n' "$TEST_COUNT"
