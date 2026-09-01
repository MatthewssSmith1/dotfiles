#!/usr/bin/env bash
# Native desktop ownership and Ubuntu validation-only behavior.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
install_fake_stow "$fake_bin"
cat > "$fake_bin/stat" <<'SCRIPT'
#!/usr/bin/env bash
if [[ -n "${DOTFILES_TEST_BAD_OWNER_PATH:-}" && "$1" == -c && "$2" == %u && "${*: -1}" == "$DOTFILES_TEST_BAD_OWNER_PATH" ]]; then
  printf '%s\n' "$((EUID + 1))"
  exit 0
fi
exec /usr/bin/stat "$@"
SCRIPT
chmod 0755 "$fake_bin/stat"
CAPTURE_PATH_PREFIX="$fake_bin"

for command_name in omarchy-shell hyprctl omarchy-theme-switcher omarchy-theme-set; do
  printf '#!/usr/bin/env bash\nprintf "%%s:%%s\\n" "${0##*/}" "$*" >> "$HOME/desktop-command.trace"\nexit 99\n' > "$fake_bin/$command_name"
  chmod 0755 "$fake_bin/$command_name"
done

readonly INPUT_REL='.config/hypr/input.lua'
readonly FRAGMENT_REL='.config/dotfiles/omarchy/hypr/input.lua'
readonly XCOMPOSE_REL='.XCompose'
readonly ALIASES_REL='.config/dotfiles/omarchy/XCompose'
readonly BINDINGS_REL='.config/hypr/bindings.lua'
readonly BINDINGS_FRAGMENT_REL='.config/dotfiles/omarchy/hypr/bindings.lua'
readonly MENU_FRAGMENT_REL='.config/dotfiles/omarchy/menu-shortcuts.jsonc'
readonly SHELL_REL='.config/omarchy/shell.json'
readonly MENU_REL='.config/omarchy/extensions/omarchy-menu.jsonc'
readonly SWITCHER_REL='.local/bin/dotfiles-omarchy-theme-switcher'
readonly COMPOSE_SHORTCUT_REL='.local/bin/dotfiles-omarchy-compose-shortcut'
readonly SHORTCUTS_REL='.local/bin/dotfiles-shortcuts'
readonly MENU_ADAPTER_REL='.local/libexec/dotfiles-omarchy-theme-switcher/omarchy-menu-images'
readonly MENU_PLUGIN_REL='.config/omarchy/plugins/matt.menu'
readonly BEGIN='-- >>> dotfiles desktop input >>>'
readonly END='-- <<< dotfiles desktop input <<<'
readonly XCOMPOSE_BEGIN='# >>> dotfiles desktop xcompose >>>'
readonly XCOMPOSE_END='# <<< dotfiles desktop xcompose <<<'
readonly BINDINGS_BEGIN='-- >>> dotfiles desktop bindings >>>'
readonly BINDINGS_END='-- <<< dotfiles desktop bindings <<<'
readonly MENU_BEGIN='  // >>> dotfiles desktop menu theme >>>'
readonly MENU_END='  // <<< dotfiles desktop menu theme <<<'

prepare_native_desktop() {
  local name="$1" root home stock
  root="$(make_host "desktop-$name" linux omarchy 4)"
  home="$(new_home "desktop-$name")"
  mkdir -p "$root/usr/share/omarchy/config/hypr" "$root/usr/share/omarchy/config/omarchy/extensions" \
    "$root/usr/share/omarchy/default" \
    "$home/.config/hypr" "$home/.config/omarchy/extensions"
  printf '4.0.0.alpha\n' > "$root/usr/share/omarchy/version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/usr/bin/omarchy"
  chmod 0755 "$root/usr/bin/omarchy"
  stock="$root/usr/share/omarchy/config/hypr/input.lua"
  printf '%s\n' '-- stock input' 'hl.config({ input = {} })' > "$stock"
  cp "$stock" "$home/$INPUT_REL"
  chmod 0640 "$home/$INPUT_REL"
  printf '%s\n' '-- stock personal bindings' > "$home/$BINDINGS_REL"
  chmod 0640 "$home/$BINDINGS_REL"
  cat > "$home/$XCOMPOSE_REL" <<XCOMPOSE
# Include fast emoji access
include "/usr/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "PRIVATE-NAME-$name"
<Multi_key> <space> <e> : "PRIVATE-EMAIL-$name"
XCOMPOSE
  printf '%s\n' '<Multi_key> <space> <space> : "—"' > "$root/usr/share/omarchy/default/xcompose"
  chmod 0640 "$home/$XCOMPOSE_REL"
  cat > "$home/$SHELL_REL" <<'JSON'
{
  "version": 1,
  "idle": { "screensaver": 150, "lock": 300 },
  "bar": { "layout": { "left": [{ "id": "omarchy.menu" }], "center": [], "right": [{ "id": "omarchy.tailscale" }] } },
  "plugins": [{ "id": "fixture", "options": { "nested": true } }],
  "unrelated": { "array": [3, 1, 2] }
}
JSON
  chmod 0640 "$home/$SHELL_REL"
  printf '%s\n' '{' '  // Stock personal menu extension.' '}' > "$root/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc"
  cp "$root/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc" "$home/$MENU_REL"
  record_pacman_ownership "$root" 'omarchy 4.0.1-1' /usr/share/omarchy/version /usr/bin/omarchy
  record_pacman_ownership "$root" 'omarchy-settings 4.0.1-1' /usr/share/omarchy/config/hypr/input.lua \
    /usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc
  printf '%s\t%s\n' "$root" "$home"
}

read -r native home < <(prepare_native_desktop lifecycle)
stock="$native/usr/share/omarchy/config/hypr/input.lua"
stock_hash="$(sha256sum "$stock")"
cp -a "$home/$INPUT_REL" "$TEST_ROOT/input.original"
cp -a "$home/$XCOMPOSE_REL" "$TEST_ROOT/xcompose.original"
cp -a "$home/$BINDINGS_REL" "$TEST_ROOT/bindings.original"
cp -a "$home/$SHELL_REL" "$TEST_ROOT/shell.original"
cp -a "$home/$MENU_REL" "$TEST_ROOT/menu.original"
: > "$FAKE_STOW_TRACE"

# Generated payloads are exact and every managed/native route replays only its
# Compose sequence.
fragment="$REPO_DIR/packages/omarchy/desktop/$FRAGMENT_REL"
aliases="$REPO_DIR/packages/omarchy/desktop/$ALIASES_REL"
bindings_fragment="$REPO_DIR/packages/omarchy/desktop/$BINDINGS_FRAGMENT_REL"
compose_shortcut="$REPO_DIR/packages/omarchy/desktop/$COMPOSE_SHORTCUT_REL"
expected_fragment=$'hl.config({\n  input = {\n    touchpad = {\n      natural_scroll = true,\n    },\n  },\n})'
expected_aliases=$'<Multi_key> <space> <a> : "AGENTS.md"\n<Multi_key> <p> <b> : "Continue discussing with me briefly."\n<Multi_key> <p> <d> : "Continue discussing with me, focussing on points we have yet to agree on."\n<Multi_key> <p> <p> : "Write an implementation plan for this; put it in a temporary *.md file outside this repo."\n<Multi_key> <p> <t> : "What do you think/recommend? Discuss with me."'
[[ "$(< "$fragment")" == "$expected_fragment" ]] || fail 'desktop fragment is not exact'
[[ "$(< "$aliases")" == "$expected_aliases" ]] || fail 'desktop Compose aliases are not exact'
[[ "$(< "$bindings_fragment")" == 'o.bind("SUPER + SHIFT + K", "Personal shortcuts", "omarchy-menu toggle shortcuts")' ]] ||
  fail 'desktop shortcut binding is not exact'
[[ "$(find "$REPO_DIR/packages/omarchy/desktop" -type f | wc -l)" == 12 &&
  ! -e "$REPO_DIR/packages/omarchy/desktop/$MENU_REL" ]] || fail 'desktop package payload inventory is not exact'
plugin="$REPO_DIR/packages/omarchy/desktop/$MENU_PLUGIN_REL"
jq -e '.id == "matt.menu" and .omarchy.clonedFrom == "omarchy.menu"' "$plugin/manifest.json" >/dev/null ||
  fail 'desktop menu clone manifest is not exact'
grep -Fq 'Style.space(420)' "$plugin/Menu.qml" || fail 'desktop menu clone width is not 420'
! grep -Fq 'maxRowsHeight' "$plugin/Menu.qml" || fail 'desktop menu clone retains the starting height ceiling'
"$REPO_DIR/scripts/generate-desktop-shortcuts" || fail 'desktop shortcut generated files are stale'
cat > "$fake_bin/wtype" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WTYPE_TRACE"
SCRIPT
chmod 0755 "$fake_bin/wtype"
WTYPE_TRACE="$TEST_ROOT/wtype.trace"
export WTYPE_TRACE
for shortcut_id in space-a space-e space-n space-space p-b p-d p-p p-t; do PATH="$fake_bin:$PATH" "$compose_shortcut" "$shortcut_id"; done
[[ "$(< "$WTYPE_TRACE")" == $'-s 180 -k Multi_key -k space -k a\n-s 180 -k Multi_key -k space -k e\n-s 180 -k Multi_key -k space -k n\n-s 180 -k Multi_key -k space -k space\n-s 180 -k Multi_key -k p -k b\n-s 180 -k Multi_key -k p -k d\n-s 180 -k Multi_key -k p -k p\n-s 180 -k Multi_key -k p -k t' ]] ||
  fail 'desktop shortcut helper dispatch differs'
! grep -Eqi 'clipboard|wl-copy|xclip|-k[[:space:]]+(enter|return)' "$compose_shortcut" "$WTYPE_TRACE" ||
  fail 'desktop shortcut helper touches the clipboard or sends Enter'
if PATH="$fake_bin:$PATH" "$compose_shortcut" unknown >/dev/null 2>&1; then fail 'desktop shortcut helper accepted an unknown ID'; fi
rm "$fake_bin/wtype"
! grep -Eq 'kb_(layout|variant|options)|sensitivity|accel_profile|repeat_|numlock|scroll_factor|drag_3fg|disable_while_typing' "$fragment" ||
  fail 'desktop fragment contains non-natural-scroll input behavior'
if command -v luac >/dev/null 2>&1; then
  luac -p "$fragment" || fail 'desktop fragment has invalid Lua syntax'
else
  printf 'SKIP: luac unavailable; exact Lua fragment structure was checked\n'
fi
if command -v xkbcli >/dev/null 2>&1; then
  xkbcli compile-compose --locale en_US.UTF-8 --test "$aliases" || fail 'desktop Compose aliases have invalid syntax'
else
  printf 'SKIP: xkbcli unavailable; exact Compose aliases were checked\n'
fi
pass

# Every native reference is required for apply/check, but outputs remain private.
for missing in space-e space-n space-space; do
  read -r refs_host refs_home < <(prepare_native_desktop "missing-$missing")
  if [[ "$missing" == space-space ]]; then
    rm "$refs_host/usr/share/omarchy/default/xcompose"
  else
    sed -i "/<${missing#space-}>/d" "$refs_home/$XCOMPOSE_REL"
  fi
  expect_failure 'desktop shortcut native' "$refs_home" "$refs_host" "$DOTFILES" apply desktop
  [[ ! -e "$refs_home/.local/state/dotfiles/v2/desktop.json" ]] || fail "missing $missing reference wrote ownership"
done
! grep -Rqs 'PRIVATE-NAME-lifecycle\|PRIVATE-EMAIL-lifecycle' "$REPO_DIR/manifests" "$REPO_DIR/packages/omarchy/desktop" ||
  fail 'native shortcut output leaked into repository payloads'
pass

# Deliberate removal does not require either native-reference source to survive.
read -r remove_refs_host remove_refs_home < <(prepare_native_desktop remove-missing-native-refs)
expect_success "$remove_refs_home" "$remove_refs_host" "$DOTFILES" apply desktop
rm "$remove_refs_home/$XCOMPOSE_REL" "$remove_refs_host/usr/share/omarchy/default/xcompose"
expect_success "$remove_refs_home" "$remove_refs_host" "$DOTFILES" remove desktop
[[ ! -e "$remove_refs_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$remove_refs_home/$SHORTCUTS_REL" ]] ||
  fail 'missing native references stranded desktop removal'
pass

# Native-compatible top-level multiline, partial, submenu, provider, and target
# entries are adopted and retained byte-for-byte around the managed block.
read -r menu_host menu_home < <(prepare_native_desktop menu-unrelated)
cat > "$menu_home/$MENU_REL" <<'JSONC'
{
  // Existing default override with only one field.
  "about": {
    "label": "Partial override",
  },
  "personal": {
    "icon": "P",
    "label": "Personal submenu",
    "aliases": ["mine",],
  },
  "style.font": {
    "provider": "fonts"
  },
  "personal.link": {
    "target": "style"
  },
  "shortcuts2": {
    "label": "Unrelated prefix"
  },
}
JSONC
cp "$menu_home/$MENU_REL" "$TEST_ROOT/menu-unrelated.original"
expect_success "$menu_home" "$menu_host" "$DOTFILES" apply desktop
for preserved in 'Partial override' 'Personal submenu' '"provider": "fonts"' '"target": "style"' 'Unrelated prefix'; do
  grep -Fq "$preserved" "$menu_home/$MENU_REL" || fail "menu adoption lost unrelated content: $preserved"
done
expect_success "$menu_home" "$menu_host" "$DOTFILES" remove desktop
assert_same "$menu_home/$MENU_REL" "$TEST_ROOT/menu-unrelated.original"
pass

# Missing managed menu content does not strand the remaining package links or
# ownership state during deliberate removal.
read -r missing_menu_host missing_menu_home < <(prepare_native_desktop missing-menu-remove)
expect_success "$missing_menu_home" "$missing_menu_host" "$DOTFILES" apply desktop
rm "$missing_menu_home/$MENU_REL"
expect_success "$missing_menu_home" "$missing_menu_host" "$DOTFILES" remove desktop
[[ ! -e "$missing_menu_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$missing_menu_home/$FRAGMENT_REL" ]] ||
  fail 'missing-menu removal retained desktop ownership'
pass

# Common Lua quoting and spacing variants cannot hide an unmanaged competing
# binding from first adoption.
binding_case=0
for competing_binding in \
  "o.bind('SUPER + SHIFT + K', 'Other', 'other')" \
  '  hl.bind ( "SUPER + SHIFT + K", "Other", "other" )'; do
  ((binding_case += 1))
  read -r binding_host binding_home < <(prepare_native_desktop "binding-conflict-$binding_case")
  printf '%s\n' "$competing_binding" >> "$binding_home/$BINDINGS_REL"
  expect_failure 'already contain an unmanaged SUPER + SHIFT + K' "$binding_home" "$binding_host" "$DOTFILES" apply desktop
  [[ ! -e "$binding_home/.local/state/dotfiles/v2/desktop.json" ]] || fail 'binding conflict wrote desktop ownership'
done
pass

# Older valid desktop state is incomplete for check/remove but apply can adopt
# the regular stock menu and atomically expand the same version-2 record.
read -r old_host old_home < <(prepare_native_desktop old-state-expansion)
expect_success "$old_home" "$old_host" "$DOTFILES" apply desktop
old_state="$old_home/.local/state/dotfiles/v2/desktop.json"
cp "$old_host/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc" "$old_home/$MENU_REL"
jq '.version = 2 | .attachments |= map_values({id,origin,before_sha256}) |
  del(.attachments[".config/omarchy/extensions/omarchy-menu.jsonc"]) |
  del(.resources[".config/omarchy/shell.json"].fields["/bar/layout/left/0/id"])' "$old_state" > "$old_home/old-state.json"
mv -fT "$old_home/old-state.json" "$old_state"
modify_json="$old_home/.config/omarchy/old-shell.json"
jq '.bar.layout.left[0].id = "omarchy.menu"' "$old_home/$SHELL_REL" > "$modify_json"
mv -fT "$modify_json" "$old_home/$SHELL_REL"
expect_failure 'attachment set differs' "$old_home" "$old_host" "$DOTFILES" check desktop
expect_failure 'attachment set differs' "$old_home" "$old_host" "$DOTFILES" remove desktop
expect_success "$old_home" "$old_host" "$DOTFILES" apply desktop
jq -e '.version == 3 and (.attachments | length) == 4 and
  .resources[".config/omarchy/shell.json"].fields["/bar/layout/left/0/id"] == {
    type:"string", original:"omarchy.menu", managed:"matt.menu"
  }' "$old_state" >/dev/null || fail 'apply did not expand old desktop state'
expect_success "$old_home" "$old_host" "$DOTFILES" check desktop
# Retry recovers if migration stopped after activating the cloned widget but
# before publishing expanded state.
jq 'del(.resources[".config/omarchy/shell.json"].fields["/bar/layout/left/0/id"])' \
  "$old_state" > "$old_home/interrupted-state.json"
mv -fT "$old_home/interrupted-state.json" "$old_state"
expect_success "$old_home" "$old_host" "$DOTFILES" apply desktop
expect_success "$old_home" "$old_host" "$DOTFILES" check desktop
pass

# An exactly generated version-1 menu remains owned drift: check reports it,
# apply upgrades only its managed block, and unrelated bytes survive.
legacy_menu_repo="$(copy_repo_fixture desktop-legacy-menu)"
read -r legacy_menu_host legacy_menu_home < <(prepare_native_desktop legacy-menu)
expect_success "$legacy_menu_home" "$legacy_menu_host" "$legacy_menu_repo/dotfiles.sh" apply desktop
legacy_menu_state="$legacy_menu_home/.local/state/dotfiles/v2/desktop.json"
jq '.version = 2 | .attachments |= map_values({id,origin,before_sha256})' "$legacy_menu_state" > "$legacy_menu_home/v2-state.json"
mv -fT "$legacy_menu_home/v2-state.json" "$legacy_menu_state"
cat > "$legacy_menu_home/$MENU_REL" <<'JSONC'
{
  // >>> dotfiles desktop menu theme >>>
  "style.theme": {"icon":"󰸌","label":"Theme","aliases":["theme","themes"],"action":"theme=$(\"$HOME/.local/bin/dotfiles-omarchy-theme-switcher\"); [[ -n $theme ]] && omarchy-theme-set \"$theme\""},
  "shortcuts": {"icon":"󰌌","label":"Shortcuts","aliases":["shortcut","shortcuts"]},
  "shortcuts.space": {"label":"Space"},
  "shortcuts.space.a": {"label":"a · AGENTS.md","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" space-a"},
  "shortcuts.prompts": {"label":"p · Prompts"},
  "shortcuts.prompts.b": {"label":"b · Continue briefly","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-b"},
  "shortcuts.prompts.d": {"label":"d · Discuss unresolved points","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-d"},
  "shortcuts.prompts.t": {"label":"t · Ask for recommendation","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-t"},
  // <<< dotfiles desktop menu theme <<<
  "unrelated.keep": {"action":"keep"}
}
JSONC
cp -a "$legacy_menu_home/$MENU_REL" "$TEST_ROOT/legacy-menu.exact"
legacy_generated_menu="$legacy_menu_repo/packages/omarchy/desktop/$MENU_FRAGMENT_REL"
cp -a "$legacy_generated_menu" "$TEST_ROOT/legacy-generated-menu.valid"
sed -i 's/AGENTS.md/Tampered generated target/' "$legacy_generated_menu"
legacy_live_hash="$(sha256sum "$legacy_menu_home/$MENU_REL")"
DOTFILES_SHORTCUTS_MIGRATE_STATE=1 capture "$legacy_menu_home" "$legacy_menu_host" "$legacy_menu_repo/dotfiles.sh" apply desktop
((TEST_RC != 0)) || fail 'legacy live attachment activated stale-generator migration relaxation'
assert_contains "$TEST_OUTPUT" 'desktop shortcut generated files are stale'
[[ "$(sha256sum "$legacy_menu_home/$MENU_REL")" == "$legacy_live_hash" ]] ||
  fail 'legacy stale-generator misuse changed the live menu'
cp -a "$TEST_ROOT/legacy-generated-menu.valid" "$legacy_generated_menu"
expect_failure 'differs from the current managed version' "$legacy_menu_home" "$legacy_menu_host" "$legacy_menu_repo/dotfiles.sh" check desktop
expect_success "$legacy_menu_home" "$legacy_menu_host" "$legacy_menu_repo/dotfiles.sh" apply desktop
grep -Fq '"shortcuts.manage"' "$legacy_menu_home/$MENU_REL" || fail 'legacy menu was not upgraded'
grep -Fq '"unrelated.keep"' "$legacy_menu_home/$MENU_REL" || fail 'legacy menu upgrade lost unrelated content'
expect_success "$legacy_menu_home" "$legacy_menu_host" "$legacy_menu_repo/dotfiles.sh" check desktop
cp "$TEST_ROOT/legacy-menu.exact" "$legacy_menu_home/$MENU_REL"
sed -i 's/"label":"Space"/"label":"Changed"/' "$legacy_menu_home/$MENU_REL"
cp -a "$legacy_menu_home/$MENU_REL" "$TEST_ROOT/legacy-menu.modified"
expect_failure 'partial, malformed, duplicate, or modified' "$legacy_menu_home" "$legacy_menu_host" "$legacy_menu_repo/dotfiles.sh" apply desktop
assert_same "$legacy_menu_home/$MENU_REL" "$TEST_ROOT/legacy-menu.modified"
pass

# Exact known legacy menu content with ownership state is removable directly.
read -r legacy_remove_host legacy_remove_home < <(prepare_native_desktop legacy-menu-remove)
expect_success "$legacy_remove_home" "$legacy_remove_host" "$DOTFILES" apply desktop
legacy_remove_state="$legacy_remove_home/.local/state/dotfiles/v2/desktop.json"
jq '.version = 2 | .attachments |= map_values({id,origin,before_sha256})' "$legacy_remove_state" > "$legacy_remove_home/v2-state.json"
mv -fT "$legacy_remove_home/v2-state.json" "$legacy_remove_state"
cat > "$legacy_remove_home/$MENU_REL" <<'JSONC'
{
  // >>> dotfiles desktop menu theme >>>
  "style.theme": {"icon":"󰸌","label":"Theme","aliases":["theme","themes"],"action":"theme=$(\"$HOME/.local/bin/dotfiles-omarchy-theme-switcher\"); [[ -n $theme ]] && omarchy-theme-set \"$theme\""},
  "shortcuts": {"icon":"󰌌","label":"Shortcuts","aliases":["shortcut","shortcuts"]},
  "shortcuts.space": {"label":"Space"},
  "shortcuts.space.a": {"label":"a · AGENTS.md","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" space-a"},
  "shortcuts.prompts": {"label":"p · Prompts"},
  "shortcuts.prompts.b": {"label":"b · Continue briefly","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-b"},
  "shortcuts.prompts.d": {"label":"d · Discuss unresolved points","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-d"},
  "shortcuts.prompts.t": {"label":"t · Ask for recommendation","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-t"},
  // <<< dotfiles desktop menu theme <<<
  "unrelated.legacy-remove": {"action":"keep"}
}
JSONC
expect_success "$legacy_remove_home" "$legacy_remove_host" "$DOTFILES" remove desktop
grep -Fq '"unrelated.legacy-remove"' "$legacy_remove_home/$MENU_REL" || fail 'legacy menu removal lost unrelated content'
! grep -Fq "$MENU_BEGIN" "$legacy_remove_home/$MENU_REL" || fail 'legacy menu removal retained managed markers'
pass

# Native XCompose with Omarchy's include/name/email must remain a regular host
# baseline before adoption.
for kind in missing symlink; do
  read -r bad_host bad_home < <(prepare_native_desktop "xcompose-$kind")
  if [[ "$kind" == missing ]]; then
    rm "$bad_home/$XCOMPOSE_REL"
  else
    mv "$bad_home/$XCOMPOSE_REL" "$bad_home/xcompose-target"
    ln -s xcompose-target "$bad_home/$XCOMPOSE_REL"
  fi
  expect_failure 'XCompose baseline is missing or not a regular file' "$bad_home" "$bad_host" "$DOTFILES" apply desktop
  [[ ! -e "$bad_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$bad_home/$ALIASES_REL" ]] ||
    fail "$kind XCompose refusal wrote desktop ownership"
done
pass

# Concurrent replacement of a refreshed regular menu is never overwritten;
# retained intent state makes a subsequent deliberate retry safe.
read -r menu_race_host menu_race_home < <(prepare_native_desktop menu-race)
expect_success "$menu_race_home" "$menu_race_host" "$DOTFILES" apply desktop
printf '%s\n' '{' '  "before.race": {"action":"before"}' '}' > "$menu_race_home/$MENU_REL"
hold="$TEST_ROOT/menu-race-hold"
mkdir "$hold"
HOME="$menu_race_home" PATH="$fake_bin:$PATH" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$menu_race_host" \
  DOTFILES_TEST_HOLD_AT=lean-before-attachment-rename DOTFILES_TEST_HOLD_DIR="$hold" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  "$DOTFILES" apply desktop > "$TEST_ROOT/menu-race.log" 2>&1 &
child=$!
wait_for_file "$hold/lean-before-attachment-rename.ready"
printf '%s\n' '{' '  "concurrent.race": {"action":"keep"}' '}' > "$menu_race_home/$MENU_REL.replacement"
mv -fT "$menu_race_home/$MENU_REL.replacement" "$menu_race_home/$MENU_REL"
: > "$hold/lean-before-attachment-rename.release"
if wait "$child"; then fail 'concurrent menu replacement unexpectedly succeeded'; fi
assert_contains "$(< "$TEST_ROOT/menu-race.log")" 'changed concurrently; refusing overwrite'
grep -Fq 'concurrent.race' "$menu_race_home/$MENU_REL" || fail 'concurrent menu replacement was overwritten'
expect_success "$menu_race_home" "$menu_race_host" "$DOTFILES" apply desktop
expect_success "$menu_race_home" "$menu_race_host" "$DOTFILES" remove desktop
pass

# Concurrent replacement after removal construction is detected before rename.
read -r remove_race_host remove_race_home < <(prepare_native_desktop menu-remove-race)
expect_success "$remove_race_home" "$remove_race_host" "$DOTFILES" apply desktop
cp -a "$remove_race_home/$MENU_REL" "$TEST_ROOT/menu-remove-race.managed"
rm "$remove_race_home/$INPUT_REL" "$remove_race_home/$XCOMPOSE_REL"
hold="$TEST_ROOT/menu-remove-race-hold"
mkdir "$hold"
HOME="$remove_race_home" PATH="$fake_bin:$PATH" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$remove_race_host" \
  DOTFILES_TEST_HOLD_AT=lean-before-attachment-remove DOTFILES_TEST_HOLD_DIR="$hold" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  "$DOTFILES" remove desktop > "$TEST_ROOT/menu-remove-race.log" 2>&1 &
child=$!
wait_for_file "$hold/lean-before-attachment-remove.ready"
cp "$TEST_ROOT/menu-remove-race.managed" "$remove_race_home/$MENU_REL.replacement"
mv -fT "$remove_race_home/$MENU_REL.replacement" "$remove_race_home/$MENU_REL"
: > "$hold/lean-before-attachment-remove.release"
if wait "$child"; then fail 'concurrent menu removal replacement unexpectedly succeeded'; fi
assert_contains "$(< "$TEST_ROOT/menu-remove-race.log")" 'changed concurrently; refusing overwrite'
assert_same "$remove_race_home/$MENU_REL" "$TEST_ROOT/menu-remove-race.managed"
assert_file "$remove_race_home/.local/state/dotfiles/v2/desktop.json"
expect_success "$remove_race_home" "$remove_race_host" "$DOTFILES" remove desktop
pass

# Edited pre-adoption input is rejected by apply and check before any ownership,
# package link, JSON update, or stock-file mutation.
read -r conflict_host conflict_home < <(prepare_native_desktop adoption-conflict)
printf '%s\n' '-- user edit' >> "$conflict_home/$INPUT_REL"
cp -a "$conflict_home/$INPUT_REL" "$TEST_ROOT/conflict-input"
cp -a "$conflict_home/$SHELL_REL" "$TEST_ROOT/conflict-shell"
for verb in apply check; do
  expect_failure 'omarchy refresh config hypr/input.lua' "$conflict_home" "$conflict_host" "$DOTFILES" "$verb" desktop
  assert_same "$conflict_home/$INPUT_REL" "$TEST_ROOT/conflict-input"
  assert_same "$conflict_home/$SHELL_REL" "$TEST_ROOT/conflict-shell"
  [[ ! -e "$conflict_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$conflict_home/$FRAGMENT_REL" ]] ||
    fail "$verb wrote desktop ownership during adoption refusal"
done
pass

# Stock input must belong to the same-version omarchy-settings package.
for kind in wrong-owner mismatched-version; do
  read -r bad_host bad_home < <(prepare_native_desktop "settings-$kind")
  metadata="$bad_host/var/lib/dotfiles-test/pacman-owners.tsv"
  if [[ "$kind" == wrong-owner ]]; then
    sed -i '\#^/usr/share/omarchy/config/hypr/input.lua# s/omarchy-settings/omarchy/' "$metadata"
    expected='not owned by omarchy-settings'
  else
    sed -i '\#^/usr/share/omarchy/config/hypr/input.lua# s/4.0.1-1/4.0.2-1/' "$metadata"
    expected='does not exactly match authoritative Omarchy'
  fi
  expect_failure "$expected" "$bad_home" "$bad_host" "$DOTFILES" apply desktop
  [[ ! -e "$bad_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$bad_home/$ALIASES_REL" ]] ||
    fail "$kind settings refusal wrote desktop ownership"
done
pass

# First apply records both origins, updates JSON before package/attachment, keeps
# native files regular and modes stable, and converges without shell commands.
expect_success "$home" "$native" "$DOTFILES" apply desktop
state="$home/.local/state/dotfiles/v2/desktop.json"
assert_file "$state"
jq -e '
  .version == 3 and .area == "desktop" and .profile == "omarchy" and
  (.attachments | keys) == [".XCompose", ".config/hypr/bindings.lua", ".config/hypr/input.lua", ".config/omarchy/extensions/omarchy-menu.jsonc"] and
  .resources[".config/omarchy/shell.json"].fields["/idle/screensaver"].original == 150 and
  .resources[".config/omarchy/shell.json"].fields["/idle/lock"].original == 300 and
  .resources[".config/omarchy/shell.json"].fields["/bar/layout/left/0/id"] == {
    type:"string", original:"omarchy.menu", managed:"matt.menu"
  }
' "$state" >/dev/null || fail 'desktop state does not contain complete origins'
assert_file "$home/$INPUT_REL"
assert_file "$home/$SHELL_REL"
[[ -L "$home/$FRAGMENT_REL" && -L "$home/$ALIASES_REL" && -L "$home/$BINDINGS_FRAGMENT_REL" &&
  -L "$home/$MENU_FRAGMENT_REL" && -L "$home/$COMPOSE_SHORTCUT_REL" && -L "$home/$SHORTCUTS_REL" &&
  -L "$home/$MENU_PLUGIN_REL/Menu.qml" &&
  -f "$home/$MENU_REL" && ! -L "$home/$MENU_REL" && -L "$home/$SWITCHER_REL" && -L "$home/$MENU_ADAPTER_REL" &&
  "$(stat -c %a "$home/$INPUT_REL")" == 640 &&
  "$(stat -c %a "$home/$XCOMPOSE_REL")" == 640 && "$(stat -c %a "$home/$SHELL_REL")" == 640 ]] ||
  fail 'desktop apply changed regular-file or mode contracts'
[[ "$(readlink -f "$home/$SHORTCUTS_REL")" == "$REPO_DIR/packages/omarchy/desktop/$SHORTCUTS_REL" ]] ||
  fail 'desktop shortcut launcher does not resolve to the repository payload'
grep -Fq '"style.theme": {"icon":"󰸌"' "$home/$MENU_REL" || fail 'desktop menu action was not attached'
grep -Fq '"shortcuts.prompts.t": {"label":"t · Ask for recommendation"' "$home/$MENU_REL" ||
  fail 'desktop shortcut menu was not attached'
attached_shortcuts="$(awk -v begin="$MENU_BEGIN" -v end="$MENU_END" '
  $0 == begin { inside=1; next }
  $0 == end { inside=0 }
  inside && $0 !~ /"style.theme"/
' "$home/$MENU_REL")"
[[ "$attached_shortcuts" == "$(< "$REPO_DIR/packages/omarchy/desktop/$MENU_FRAGMENT_REL")" ]] ||
  fail 'desktop shortcut menu attachment is not the exact generated fragment'
[[ "$(grep -cFx -- "$BEGIN" "$home/$INPUT_REL")" == 1 && "$(grep -cFx -- "$END" "$home/$INPUT_REL")" == 1 ]] ||
  fail 'desktop loader was not attached exactly once'
[[ "$(grep -cFx -- "$XCOMPOSE_BEGIN" "$home/$XCOMPOSE_REL")" == 1 &&
  "$(grep -cFx -- "$XCOMPOSE_END" "$home/$XCOMPOSE_REL")" == 1 ]] ||
  fail 'desktop XCompose loader was not attached exactly once'
[[ "$(grep -cFx -- "$BINDINGS_BEGIN" "$home/$BINDINGS_REL")" == 1 &&
  "$(grep -cFx -- "$BINDINGS_END" "$home/$BINDINGS_REL")" == 1 ]] ||
  fail 'desktop bindings loader was not attached exactly once'
xcompose_block_line="$(grep -nFx -- "$XCOMPOSE_BEGIN" "$home/$XCOMPOSE_REL" | cut -d: -f1)"
sed -n "1,$((xcompose_block_line - 1))p" "$home/$XCOMPOSE_REL" > "$TEST_ROOT/xcompose-prefix"
assert_same "$TEST_ROOT/xcompose-prefix" "$TEST_ROOT/xcompose.original"
jq -e '.idle.screensaver == 600 and .idle.lock == 900 and .bar.layout.left[0].id == "matt.menu" and .bar.layout.right[0].id == "omarchy.tailscale" and .plugins[0].options.nested == true and .unrelated.array == [3,1,2]' \
  "$home/$SHELL_REL" >/dev/null || fail 'desktop JSON update lost managed or unrelated semantics'
[[ ! -e "$home/desktop-command.trace" && "$(sha256sum "$stock")" == "$stock_hash" ]] ||
  fail 'desktop apply invoked a shell/reload command or changed stock input'
state_identity="$(stat -c '%d:%i' "$state")"
input_hash="$(sha256sum "$home/$INPUT_REL")"
xcompose_hash="$(sha256sum "$home/$XCOMPOSE_REL")"
expect_success "$home" "$native" "$DOTFILES" apply desktop
expect_success "$home" "$native" "$DOTFILES" check desktop
[[ "$(stat -c '%d:%i' "$state")" == "$state_identity" && "$(sha256sum "$home/$INPUT_REL")" == "$input_hash" &&
  "$(sha256sum "$home/$XCOMPOSE_REL")" == "$xcompose_hash" ]] ||
  fail 'desktop apply/check is not idempotent'
pass

# Check is semantic for shell JSON and ignores unrelated changes/key ordering.
jq '.unrelated.after_apply = {"preserve": true}' "$home/$SHELL_REL" > "$home/.config/omarchy/reordered.json"
mv -fT "$home/.config/omarchy/reordered.json" "$home/$SHELL_REL"
chmod 0640 "$home/$SHELL_REL"
expect_success "$home" "$native" "$DOTFILES" check desktop
pass

# A native refresh removes the loader. Check detects it and reapply accepts only
# the package-owned refreshed baseline, preserving those bytes and mode.
cp "$stock" "$home/$INPUT_REL"
chmod 0600 "$home/$INPUT_REL"
cat > "$home/$XCOMPOSE_REL" <<'XCOMPOSE'
include "/usr/share/omarchy/default/xcompose"
<Multi_key> <space> <n> : "PRIVATE-NAME-refreshed"
<Multi_key> <space> <e> : "PRIVATE-EMAIL-refreshed"
<Multi_key> <o> <r> : "Refreshed Omarchy"
XCOMPOSE
chmod 0600 "$home/$XCOMPOSE_REL"
cp -a "$home/$XCOMPOSE_REL" "$TEST_ROOT/xcompose.refreshed"
expect_failure 'recorded guarded attachment is absent' "$home" "$native" "$DOTFILES" check desktop
expect_success "$home" "$native" "$DOTFILES" apply desktop
[[ "$(stat -c %a "$home/$INPUT_REL")" == 600 && "$(stat -c %a "$home/$XCOMPOSE_REL")" == 600 ]] ||
  fail 'refresh reapply changed desktop attachment modes'
block_line="$(grep -nFx -- "$BEGIN" "$home/$INPUT_REL" | cut -d: -f1)"
((block_line > 1)) || fail 'refresh loader is not an end attachment'
sed -n "1,$((block_line - 1))p" "$home/$INPUT_REL" > "$TEST_ROOT/refreshed-prefix"
assert_same "$TEST_ROOT/refreshed-prefix" "$stock"
xcompose_block_line="$(grep -nFx -- "$XCOMPOSE_BEGIN" "$home/$XCOMPOSE_REL" | cut -d: -f1)"
sed -n "1,$((xcompose_block_line - 1))p" "$home/$XCOMPOSE_REL" > "$TEST_ROOT/refreshed-xcompose-prefix"
assert_same "$TEST_ROOT/refreshed-xcompose-prefix" "$TEST_ROOT/xcompose.refreshed"
pass

# Menu refresh without markers is drift; deliberate apply re-adopts its bytes.
printf '%s\n' '{' '  // refreshed menu' '  "open.future": {"action":"future"}' '}' > "$home/$MENU_REL"
cp "$home/$MENU_REL" "$TEST_ROOT/menu.refreshed"
expect_failure 'recorded guarded attachment is absent' "$home" "$native" "$DOTFILES" check desktop
expect_success "$home" "$native" "$DOTFILES" apply desktop
grep -Fq '"open.future": {"action":"future"}' "$home/$MENU_REL" || fail 'menu refresh reapply lost unrelated content'
pass

# A refresh to an unaccepted baseline and malformed/duplicate/modified blocks
# are refused without replacing bytes.
cp "$stock" "$home/$INPUT_REL"
printf '%s\n' '-- drift after refresh' >> "$home/$INPUT_REL"
cp "$home/$INPUT_REL" "$TEST_ROOT/refresh-drift"
expect_failure 'omarchy refresh config hypr/input.lua' "$home" "$native" "$DOTFILES" apply desktop
assert_same "$home/$INPUT_REL" "$TEST_ROOT/refresh-drift"
cp "$stock" "$home/$INPUT_REL"
expect_success "$home" "$native" "$DOTFILES" apply desktop
cp "$home/$XCOMPOSE_REL" "$TEST_ROOT/exact-xcompose-loader"
printf '%s\n' "$XCOMPOSE_BEGIN" 'include "%H/duplicate"' "$XCOMPOSE_END" >> "$home/$XCOMPOSE_REL"
expect_failure 'partial, malformed, duplicate, or modified' "$home" "$native" "$DOTFILES" check desktop
cp "$TEST_ROOT/exact-xcompose-loader" "$home/$XCOMPOSE_REL"
sed -i 's#%H/.config/dotfiles/omarchy/XCompose#%H/unsafe#' "$home/$XCOMPOSE_REL"
expect_failure 'partial, malformed, duplicate, or modified' "$home" "$native" "$DOTFILES" remove desktop
cp "$TEST_ROOT/exact-xcompose-loader" "$home/$XCOMPOSE_REL"
pass

# Shell schema, scalar types, symlinks, and field conflicts fail before mutation.
for kind in malformed schema type symlink owner; do
  read -r bad_host bad_home < <(prepare_native_desktop "bad-$kind")
  case "$kind" in
    malformed) printf '{broken\n' > "$bad_home/$SHELL_REL" ;;
    schema) jq '.version = 2' "$bad_home/$SHELL_REL" > "$bad_home/replacement"; mv "$bad_home/replacement" "$bad_home/$SHELL_REL" ;;
    type) jq '.idle.lock = "300"' "$bad_home/$SHELL_REL" > "$bad_home/replacement"; mv "$bad_home/replacement" "$bad_home/$SHELL_REL" ;;
    symlink) mv "$bad_home/$SHELL_REL" "$bad_home/shell-target.json"; ln -s ../../shell-target.json "$bad_home/$SHELL_REL" ;;
    owner) export DOTFILES_TEST_BAD_OWNER_PATH="$bad_home/$SHELL_REL" ;;
  esac
  expect_failure 'JSON resource' "$bad_home" "$bad_host" "$DOTFILES" apply desktop
  unset DOTFILES_TEST_BAD_OWNER_PATH
  [[ ! -e "$bad_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$bad_home/$FRAGMENT_REL" ]] ||
    fail "$kind shell refusal wrote desktop ownership"
done
jq '.idle.lock = 901' "$home/$SHELL_REL" > "$home/.config/omarchy/conflict.json"
mv -fT "$home/.config/omarchy/conflict.json" "$home/$SHELL_REL"
chmod 0640 "$home/$SHELL_REL"
expect_failure 'managed JSON fields conflict' "$home" "$native" "$DOTFILES" apply desktop
expect_failure 'managed JSON fields conflict' "$home" "$native" "$DOTFILES" remove desktop
pass

# A pre-existing local clone or duplicate source/clone entries are never
# silently adopted or normalized.
for kind in unmanaged-clone duplicate-menu; do
  read -r bad_host bad_home < <(prepare_native_desktop "menu-plugin-$kind")
  if [[ "$kind" == unmanaged-clone ]]; then
    jq '.bar.layout.left[0].id = "matt.menu"' "$bad_home/$SHELL_REL" > "$bad_home/shell-replacement.json"
    expected='already uses an unmanaged clone'
  else
    jq '.bar.layout.left += [{"id":"matt.menu"}]' "$bad_home/$SHELL_REL" > "$bad_home/shell-replacement.json"
    expected='JSON resource'
  fi
  mv -fT "$bad_home/shell-replacement.json" "$bad_home/$SHELL_REL"
  expect_failure "$expected" "$bad_home" "$bad_host" "$DOTFILES" apply desktop
  [[ ! -e "$bad_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$bad_home/$MENU_PLUGIN_REL" ]] ||
    fail "$kind conflict wrote desktop ownership"
done
pass

# Removal restores only recorded fields, preserves unrelated semantic changes,
# removes the exact loader/link, and deletes state last.
jq '.idle.lock = 900 | .unrelated.during_ownership = "keep"' "$home/$SHELL_REL" > "$home/.config/omarchy/repaired.json"
mv -fT "$home/.config/omarchy/repaired.json" "$home/$SHELL_REL"
chmod 0640 "$home/$SHELL_REL"
# Removal owns the exact live block and does not depend on a still-installed
# adoption template or its package metadata.
rm "$native/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc"
rm "$native/usr/share/omarchy/default/xcompose"
sed -i '\#^/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc#d' "$native/var/lib/dotfiles-test/pacman-owners.tsv"
expect_success "$home" "$native" "$DOTFILES" remove desktop
[[ ! -e "$state" && ! -e "$home/$FRAGMENT_REL" && ! -e "$home/$ALIASES_REL" &&
  ! -e "$home/$BINDINGS_FRAGMENT_REL" && ! -e "$home/$MENU_FRAGMENT_REL" &&
  ! -e "$home/$COMPOSE_SHORTCUT_REL" && ! -e "$home/$SHORTCUTS_REL" && ! -e "$home/$MENU_ADAPTER_REL" &&
  ! -e "$home/$MENU_PLUGIN_REL/manifest.json" &&
  -f "$home/$MENU_REL" && ! -L "$home/$MENU_REL" && ! -e "$home/$SWITCHER_REL" ]] ||
  fail 'desktop removal retained state or package link'
assert_file "$home/$INPUT_REL"
assert_file "$home/$XCOMPOSE_REL"
assert_file "$home/$BINDINGS_REL"
[[ "$(grep -cF -- "$BEGIN" "$home/$INPUT_REL" || true)" == 0 ]] || fail 'desktop removal retained loader'
assert_same "$home/$XCOMPOSE_REL" "$TEST_ROOT/xcompose.refreshed"
assert_same "$home/$BINDINGS_REL" "$TEST_ROOT/bindings.original"
assert_same "$home/$MENU_REL" "$TEST_ROOT/menu.refreshed"
jq -e '.idle.screensaver == 150 and .idle.lock == 300 and .unrelated.during_ownership == "keep" and .bar.layout.left[0].id == "omarchy.menu" and .bar.layout.right[0].id == "omarchy.tailscale"' \
  "$home/$SHELL_REL" >/dev/null || fail 'desktop removal changed unrelated shell semantics'
[[ ! -e "$home/desktop-command.trace" ]] || fail 'desktop lifecycle invoked restart/reload commands'
expect_success "$home" "$native" "$DOTFILES" remove desktop
assert_contains "$TEST_OUTPUT" 'already absent'
pass

# Missing state is not treated as absent while exact package links or guarded
# markers remain, and removal preflight does not mutate either case.
for retained in links markers; do
  read -r lost_host lost_home < <(prepare_native_desktop "lost-state-$retained")
  cp -a "$lost_home/$INPUT_REL" "$TEST_ROOT/lost-$retained-input.original"
  cp -a "$lost_home/$XCOMPOSE_REL" "$TEST_ROOT/lost-$retained-xcompose.original"
  expect_success "$lost_home" "$lost_host" "$DOTFILES" apply desktop
  lost_state="$lost_home/.local/state/dotfiles/v2/desktop.json"
  rm "$lost_state"
  if [[ "$retained" == links ]]; then
    cp -a "$TEST_ROOT/lost-$retained-input.original" "$lost_home/$INPUT_REL"
    cp -a "$TEST_ROOT/lost-$retained-xcompose.original" "$lost_home/$XCOMPOSE_REL"
  else
    rm "$lost_home/$FRAGMENT_REL" "$lost_home/$ALIASES_REL" "$lost_home/$BINDINGS_FRAGMENT_REL" \
      "$lost_home/$MENU_FRAGMENT_REL" "$lost_home/$COMPOSE_SHORTCUT_REL" "$lost_home/$SWITCHER_REL" \
      "$lost_home/$SHORTCUTS_REL" "$lost_home/$MENU_ADAPTER_REL"
  fi
  input_before="$(sha256sum "$lost_home/$INPUT_REL")"
  xcompose_before="$(sha256sum "$lost_home/$XCOMPOSE_REL")"
  expect_failure 'partial, malformed, duplicate, or modified' "$lost_home" "$lost_host" "$DOTFILES" remove desktop
  [[ "$(sha256sum "$lost_home/$INPUT_REL")" == "$input_before" &&
    "$(sha256sum "$lost_home/$XCOMPOSE_REL")" == "$xcompose_before" ]] ||
    fail "missing-state $retained removal changed guarded files"
  if [[ "$retained" == links ]]; then
    [[ -L "$lost_home/$FRAGMENT_REL" && -L "$lost_home/$SWITCHER_REL" ]] ||
      fail 'missing-state removal deleted retained package links'
  else
    [[ "$(grep -cFx -- "$BEGIN" "$lost_home/$INPUT_REL")" == 1 &&
      "$(grep -cFx -- "$XCOMPOSE_BEGIN" "$lost_home/$XCOMPOSE_REL")" == 1 ]] ||
      fail 'missing-state removal deleted retained guarded markers'
  fi
done
pass

# Unsafe, malformed, wrapped, ambiguous, unmanaged, and marker-drift menus refuse.
for kind in symlink parent owner nul malformed items ambiguous unmanaged unmanaged-shortcuts unmanaged-shortcuts-child partial duplicate modified; do
  read -r bad_host bad_home < <(prepare_native_desktop "bad-menu-$kind")
  case "$kind" in
    symlink) mv "$bad_home/$MENU_REL" "$bad_home/menu-target"; ln -s "$bad_home/menu-target" "$bad_home/$MENU_REL" ;;
    parent) mv "$bad_home/.config/omarchy/extensions" "$bad_home/menu-parent"; ln -s "$bad_home/menu-parent" "$bad_home/.config/omarchy/extensions" ;;
    owner) export DOTFILES_TEST_BAD_OWNER_PATH="$bad_home/$MENU_REL" ;;
    nul) printf '\0' >> "$bad_home/$MENU_REL" ;;
    malformed) printf '{ broken\n' > "$bad_home/$MENU_REL" ;;
    items) printf '%s\n' '{' '  "items": {' '    "wrapped": {"action":"x"}' '  }' '}' > "$bad_home/$MENU_REL" ;;
    ambiguous) printf '%s\n' '{' '{' '}' > "$bad_home/$MENU_REL" ;;
    unmanaged) printf '%s\n' '{' '  "style.theme": {"action":"other"}' '}' > "$bad_home/$MENU_REL" ;;
    unmanaged-shortcuts) printf '%s\n' '{' '  "shortcuts": {"action":"other"}' '}' > "$bad_home/$MENU_REL" ;;
    unmanaged-shortcuts-child) printf '%s\n' '{' '  "shortcuts.other": {"action":"other"}' '}' > "$bad_home/$MENU_REL" ;;
    partial) printf '%s\n' '{' '  // >>> dotfiles desktop menu theme >>>' '}' > "$bad_home/$MENU_REL" ;;
    duplicate|modified)
      expect_success "$bad_home" "$bad_host" "$DOTFILES" apply desktop
      if [[ "$kind" == duplicate ]]; then
        sed -i '/dotfiles desktop menu theme <<</a\  // >>> dotfiles desktop menu theme >>>\n  // <<< dotfiles desktop menu theme <<<' "$bad_home/$MENU_REL"
      else
        sed -i 's/"label":"Theme"/"label":"Changed"/' "$bad_home/$MENU_REL"
      fi ;;
  esac
  cp -a "$bad_home/$MENU_REL" "$TEST_ROOT/bad-menu-$kind.original"
  expect_failure '' "$bad_home" "$bad_host" "$DOTFILES" check desktop
  unset DOTFILES_TEST_BAD_OWNER_PATH
  assert_same "$bad_home/$MENU_REL" "$TEST_ROOT/bad-menu-$kind.original"
  if [[ "$kind" == duplicate || "$kind" == modified ]]; then
    expect_failure '' "$bad_home" "$bad_host" "$DOTFILES" remove desktop
    assert_same "$bad_home/$MENU_REL" "$TEST_ROOT/bad-menu-$kind.original"
  fi
done
pass

# Intent state is durable before the first JSON/package/attachment write, and a
# handled interruption leaves retryable ownership with no temporary files.
read -r interrupt_host interrupt_home < <(prepare_native_desktop interrupt)
hold="$TEST_ROOT/interrupt-hold"
mkdir "$hold"
HOME="$interrupt_home" PATH="$fake_bin:$PATH" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$interrupt_host" \
  DOTFILES_TEST_HOLD_AT=lean-after-state-write DOTFILES_TEST_HOLD_DIR="$hold" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  "$DOTFILES" apply desktop > "$TEST_ROOT/interrupt.log" 2>&1 &
child=$!
wait_for_file "$hold/lean-after-state-write.ready"
interrupt_state="$interrupt_home/.local/state/dotfiles/v2/desktop.json"
assert_file "$interrupt_state"
jq -e '.resources[".config/omarchy/shell.json"].fields["/idle/lock"].original == 300' "$interrupt_state" >/dev/null ||
  fail 'interrupted desktop state lacks JSON origin'
[[ "$(jq -r .idle.lock "$interrupt_home/$SHELL_REL")" == 300 && ! -e "$interrupt_home/$FRAGMENT_REL" && "$(grep -cF -- "$BEGIN" "$interrupt_home/$INPUT_REL" || true)" == 0 ]] ||
  fail 'desktop wrote a managed object before complete state'
kill -TERM "$child"
: > "$hold/lean-after-state-write.release"
if wait "$child"; then fail 'interrupted desktop apply unexpectedly succeeded'; fi
expect_success "$interrupt_home" "$interrupt_host" "$DOTFILES" apply desktop
expect_success "$interrupt_home" "$interrupt_host" "$DOTFILES" remove desktop
if compgen -G "$interrupt_home/.config/omarchy/.shell.json.tmp.*" >/dev/null; then fail 'desktop interruption retained a JSON temp'; fi
pass

# The selector builds an exact locked bundled-theme view and delegates without
# changing user themes or its parent environment.
selector="$REPO_DIR/packages/omarchy/desktop/$SWITCHER_REL"
runtime_home="$(new_home theme-selector-runtime)"
runtime_root="$TEST_ROOT/fake-omarchy"
runtime_native="$TEST_ROOT/usr-bin-omarchy-theme-switcher"
runtime_native_menu="$TEST_ROOT/usr-bin-omarchy-menu-images"
runtime_cache_base="$TEST_ROOT/theme-cache"
runtime_trace="$TEST_ROOT/theme-selector.trace"
mapfile -t DENIED_THEMES < "$REPO_DIR/manifests/hidden-themes.txt"
readonly -a DENIED_THEMES
readonly -a ALLOWED_THEMES=(catppuccin catppuccin-latte everforest gruvbox kanagawa matte-black nord osaka-jade retro-82 ristretto solitude tokyo-night)
mkdir -p "$runtime_root/bin" "$runtime_root/themes" "$runtime_cache_base" \
  "$runtime_home/.config/omarchy/themes/user-only"
for theme in "${DENIED_THEMES[@]}" "${ALLOWED_THEMES[@]}"; do
  mkdir "$runtime_root/themes/$theme"
done
printf '%s\n' bundled-preview > "$runtime_root/themes/ethereal/preview.png"
cat > "$runtime_native" <<'SCRIPT'
#!/usr/bin/env bash
printf 'OMARCHY_PATH=%s\nXDG_CACHE_HOME=%s\n' "$OMARCHY_PATH" "$XDG_CACHE_HOME" >> "$FAKE_SELECTOR_TRACE"
printf '%s\0' "$@" > "$FAKE_SELECTOR_TRACE.args"
omarchy-menu-images --selector-probe >> "$FAKE_SELECTOR_TRACE"
theme="${FAKE_VISIBLE_THEME:-tokyo-night}"
bundled="$OMARCHY_PATH/themes/$theme"
user="$HOME/.config/omarchy/themes/$theme"
[[ -d "$bundled" ]] || exit 97
if [[ -d "$user" ]]; then
  printf 'VISIBLE_THEME_SOURCE=%s\n' "$user" >> "$FAKE_SELECTOR_TRACE"
  if [[ -f "$user/preview.png" ]]; then preview="$user/preview.png"; else preview="$bundled/preview.png"; fi
  [[ -f "$preview" ]] || exit 98
  printf 'VISIBLE_THEME_PREVIEW=%s\n' "$(< "$preview")" >> "$FAKE_SELECTOR_TRACE"
else
  printf 'VISIBLE_THEME_SOURCE=%s\n' "$bundled" >> "$FAKE_SELECTOR_TRACE"
fi
printf '%s\n' 'selected-theme'
printf '%s\n' 'native-selector-stderr' >&2
exit "${FAKE_SELECTOR_STATUS:-0}"
SCRIPT
chmod 0755 "$runtime_native"
ln -s "$runtime_native" "$runtime_root/bin/omarchy-theme-switcher"
cat > "$runtime_native_menu" <<'SCRIPT'
#!/usr/bin/env bash
printf 'MENU_IMAGES_OMARCHY_PATH=%s\nMENU_IMAGES_ARGS=%s\n' "$OMARCHY_PATH" "$*"
SCRIPT
chmod 0755 "$runtime_native_menu"
ln -s "$runtime_native_menu" "$runtime_root/bin/omarchy-menu-images"

run_theme_selector() {
  local status
  set +e
  HOME="$runtime_home" PATH="$fake_bin:$PATH" OMARCHY_PATH=ignored XDG_CACHE_HOME="$runtime_cache_base" DOTFILES_TESTING=1 \
    DOTFILES_TEST_OMARCHY_ROOT="$runtime_root" DOTFILES_TEST_NATIVE_SELECTOR="$runtime_native" DOTFILES_TEST_NATIVE_OWNER="$EUID" \
    DOTFILES_TEST_NATIVE_MENU_IMAGES="$runtime_native_menu" \
    FAKE_SELECTOR_TRACE="$runtime_trace" FAKE_SELECTOR_STATUS="${FAKE_SELECTOR_STATUS:-0}" \
    FAKE_VISIBLE_THEME="${FAKE_VISIBLE_THEME:-}" FAKE_LOCK_SWAP="${FAKE_LOCK_SWAP:-}" FAKE_LOCK_PATH="${FAKE_LOCK_PATH:-}" \
    "$selector" "$@" > "$TEST_ROOT/theme-selector.stdout" 2> "$TEST_ROOT/theme-selector.stderr"
  status=$?
  set -e
  TEST_OUTPUT="$(< "$TEST_ROOT/theme-selector.stdout")"
  return "$status"
}

run_theme_selector --preload 'future argument' || fail 'theme selector delegation failed'
[[ "$TEST_OUTPUT" == selected-theme && "$(< "$TEST_ROOT/theme-selector.stderr")" == native-selector-stderr ]] ||
  fail 'theme selector did not preserve native output'
mapfile -d '' -t forwarded < "$runtime_trace.args"
[[ "${forwarded[*]}" == '--preload future argument' && ${#forwarded[@]} -eq 2 ]] ||
  fail 'theme selector did not forward arguments unchanged'
view_root="$runtime_cache_base/dotfiles/omarchy-theme-switcher/v1/view"
runtime_child_cache="$runtime_cache_base/dotfiles/omarchy-theme-switcher/v1/runtime-cache"
assert_contains "$(< "$runtime_trace")" "OMARCHY_PATH=$view_root"
assert_contains "$(< "$runtime_trace")" "XDG_CACHE_HOME=$runtime_child_cache"
assert_contains "$(< "$runtime_trace")" "MENU_IMAGES_OMARCHY_PATH=$runtime_root"
assert_contains "$(< "$runtime_trace")" 'MENU_IMAGES_ARGS=--selector-probe'
for theme in "${DENIED_THEMES[@]}"; do
  [[ ! -e "$view_root/themes/$theme" && ! -L "$view_root/themes/$theme" ]] || fail "denied theme is visible: $theme"
done
for theme in "${ALLOWED_THEMES[@]}"; do
  [[ -L "$view_root/themes/$theme" && "$(readlink "$view_root/themes/$theme")" == "$runtime_root/themes/$theme" ]] ||
    fail "allowed theme link is not exact: $theme"
done
[[ -d "$runtime_home/.config/omarchy/themes/user-only" && ! -e "$view_root/themes/user-only" ]] ||
  fail 'selector changed or copied the user theme view'
mkdir "$runtime_home/.config/omarchy/themes/ethereal"
FAKE_VISIBLE_THEME=ethereal
run_theme_selector || fail 'denied-slug user override was not visible'
unset FAKE_VISIBLE_THEME
assert_contains "$(< "$runtime_trace")" "VISIBLE_THEME_SOURCE=$runtime_home/.config/omarchy/themes/ethereal"
assert_contains "$(< "$runtime_trace")" 'VISIBLE_THEME_PREVIEW=bundled-preview'
[[ -L "$view_root/themes/ethereal" && "$(readlink "$view_root/themes/ethereal")" == "$runtime_root/themes/ethereal" ]] ||
  fail 'denied bundled theme was not retained as a user-theme preview fallback'

rm "$runtime_root/bin/omarchy-theme-switcher"
ln -s "$runtime_root/themes" "$runtime_root/bin/omarchy-theme-switcher"
if run_theme_selector; then fail 'selector accepted a native symlink resolving outside /usr/bin'; fi
assert_contains "$(< "$TEST_ROOT/theme-selector.stderr")" 'native theme selector is missing or unsafe'
rm "$runtime_root/bin/omarchy-theme-switcher"
ln -s "$runtime_native" "$runtime_root/bin/omarchy-theme-switcher"

retained_inode="$(stat -c %i "$view_root/themes/tokyo-night")"
mkdir "$runtime_root/themes/new-upstream-theme"
ln -s "$runtime_root/themes/hackerman" "$view_root/themes/hackerman"
ln -s "$runtime_root/themes/catppuccin" "$view_root/themes/deleted-upstream-theme"
run_theme_selector || fail 'theme selector reconciliation failed'
[[ "$(stat -c %i "$view_root/themes/tokyo-night")" == "$retained_inode" ]] || fail 'correct theme link was replaced'
[[ -L "$view_root/themes/new-upstream-theme" && ! -L "$view_root/themes/hackerman" &&
  ! -L "$view_root/themes/deleted-upstream-theme" ]] || fail 'theme view did not add unknown or remove stale links'

[[ "$(stat -c %a "$runtime_cache_base")" == 755 ]] || fail 'selector changed ordinary XDG cache root mode'
chmod 0755 "$runtime_cache_base/dotfiles" "$runtime_cache_base/dotfiles/omarchy-theme-switcher"
run_theme_selector || fail 'theme selector did not normalize dedicated cache modes'
for private_dir in "$runtime_cache_base/dotfiles" "$runtime_cache_base/dotfiles/omarchy-theme-switcher" \
  "$runtime_cache_base/dotfiles/omarchy-theme-switcher/v1" "$view_root" "$view_root/themes" "$runtime_child_cache"; do
  [[ "$(stat -c %a "$private_dir")" == 700 ]] || fail "dedicated cache directory is not private: $private_dir"
done

lock_path="$runtime_cache_base/dotfiles/omarchy-theme-switcher/v1/lock"
printf '%s\n' lock-sentinel > "$lock_path"
run_theme_selector || fail 'selector failed with an existing safe lock'
[[ "$(< "$lock_path")" == lock-sentinel ]] || fail 'selector truncated the cache lock while opening it'
cat > "$fake_bin/flock" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${FAKE_LOCK_SWAP:-}" == 1 ]]; then
  mv "$FAKE_LOCK_PATH" "$FAKE_LOCK_PATH.opened"
  ln -s "$FAKE_LOCK_PATH.opened" "$FAKE_LOCK_PATH"
fi
exec /usr/bin/flock "$@"
SCRIPT
chmod 0755 "$fake_bin/flock"
FAKE_LOCK_SWAP=1 FAKE_LOCK_PATH="$lock_path"
if run_theme_selector; then fail 'selector accepted a lock path swapped after opening'; fi
unset FAKE_LOCK_SWAP FAKE_LOCK_PATH
assert_contains "$(< "$TEST_ROOT/theme-selector.stderr")" 'cache lock changed while locking'
rm "$lock_path"
mv "$lock_path.opened" "$lock_path"
rm "$fake_bin/flock"

for symlink_kind in root component; do
  unsafe_cache="$TEST_ROOT/unsafe-cache-$symlink_kind"
  unsafe_target="$TEST_ROOT/unsafe-cache-$symlink_kind-target"
  mkdir "$unsafe_target"
  if [[ "$symlink_kind" == root ]]; then
    ln -s "$unsafe_target" "$unsafe_cache"
  else
    mkdir "$unsafe_cache"
    ln -s "$unsafe_target" "$unsafe_cache/dotfiles"
  fi
  set +e
  HOME="$runtime_home" XDG_CACHE_HOME="$unsafe_cache" DOTFILES_TESTING=1 DOTFILES_TEST_OMARCHY_ROOT="$runtime_root" \
    DOTFILES_TEST_NATIVE_SELECTOR="$runtime_native" DOTFILES_TEST_NATIVE_MENU_IMAGES="$runtime_native_menu" \
    DOTFILES_TEST_NATIVE_OWNER="$EUID" "$selector" \
    > /dev/null 2> "$TEST_ROOT/unsafe-cache-$symlink_kind.stderr"
  unsafe_status=$?
  set -e
  [[ "$unsafe_status" != 0 ]] || fail "selector accepted symlinked cache $symlink_kind"
  assert_contains "$(< "$TEST_ROOT/unsafe-cache-$symlink_kind.stderr")" 'cache directory is unsafe'
done

printf '%s\n' unsafe > "$view_root/themes/unexpected"
expect_runtime_status=0
if run_theme_selector; then expect_runtime_status=1; fi
((expect_runtime_status == 0)) || fail 'theme selector accepted an unexpected cache object'
assert_contains "$(< "$TEST_ROOT/theme-selector.stderr")" 'refusing unexpected cache entry'
[[ "$(< "$view_root/themes/unexpected")" == unsafe ]] || fail 'theme selector deleted an unexpected cache object'
rm "$view_root/themes/unexpected"

FAKE_SELECTOR_STATUS=23
if run_theme_selector status-check; then fail 'theme selector lost native failure status'; else selector_status=$?; fi
[[ "$selector_status" == 23 && "$(< "$TEST_ROOT/theme-selector.stdout")" == selected-theme ]] ||
  fail 'theme selector did not preserve native status/stdout'
unset FAKE_SELECTOR_STATUS

export OMARCHY_PATH=parent-omarchy XDG_CACHE_HOME=parent-cache
run_theme_selector || fail 'scoped selector invocation failed'
[[ "$OMARCHY_PATH" == parent-omarchy && "$XDG_CACHE_HOME" == parent-cache ]] || fail 'selector changed parent environment'
unset OMARCHY_PATH XDG_CACHE_HOME

missing_root="$TEST_ROOT/missing-selector-root"
mkdir -p "$missing_root/themes" "$missing_root/bin"
set +e
HOME="$runtime_home" XDG_CACHE_HOME="$runtime_cache_base" DOTFILES_TESTING=1 DOTFILES_TEST_OMARCHY_ROOT="$missing_root" \
  DOTFILES_TEST_NATIVE_SELECTOR="$runtime_native" DOTFILES_TEST_NATIVE_MENU_IMAGES="$runtime_native_menu" \
  DOTFILES_TEST_NATIVE_OWNER="$EUID" "$selector" \
  > /dev/null 2> "$TEST_ROOT/missing-selector.stderr"
missing_status=$?
set -e
[[ "$missing_status" != 0 ]] || fail 'missing native selector was accepted'
assert_contains "$(< "$TEST_ROOT/missing-selector.stderr")" 'native theme selector is missing or unsafe'
rm -r "$missing_root/themes"
ln -s "$runtime_native" "$missing_root/bin/omarchy-theme-switcher"
set +e
HOME="$runtime_home" XDG_CACHE_HOME="$runtime_cache_base" DOTFILES_TESTING=1 DOTFILES_TEST_OMARCHY_ROOT="$missing_root" \
  DOTFILES_TEST_NATIVE_SELECTOR="$runtime_native" DOTFILES_TEST_NATIVE_MENU_IMAGES="$runtime_native_menu" \
  DOTFILES_TEST_NATIVE_OWNER="$EUID" "$selector" \
  > /dev/null 2> "$TEST_ROOT/missing-themes.stderr"
missing_status=$?
set -e
[[ "$missing_status" != 0 ]] || fail 'missing themes directory was accepted'
assert_contains "$(< "$TEST_ROOT/missing-themes.stderr")" 'bundled themes directory is missing or unsafe'

rm -f "$view_root/themes/"*
children=()
for invocation in 1 2 3 4 5 6; do
    HOME="$runtime_home" XDG_CACHE_HOME="$runtime_cache_base" DOTFILES_TESTING=1 DOTFILES_TEST_OMARCHY_ROOT="$runtime_root" \
      DOTFILES_TEST_NATIVE_SELECTOR="$runtime_native" DOTFILES_TEST_NATIVE_MENU_IMAGES="$runtime_native_menu" \
      DOTFILES_TEST_NATIVE_OWNER="$EUID" \
    FAKE_SELECTOR_TRACE="$runtime_trace.concurrent.$invocation" "$selector" --preload \
    > "$TEST_ROOT/concurrent-selector.$invocation.out" 2> "$TEST_ROOT/concurrent-selector.$invocation.err" &
  children+=("$!")
done
for child in "${children[@]}"; do wait "$child" || fail 'concurrent theme selector invocation failed'; done
for theme in ethereal "${ALLOWED_THEMES[@]}" new-upstream-theme; do
  [[ -L "$view_root/themes/$theme" && "$(readlink "$view_root/themes/$theme")" == "$runtime_root/themes/$theme" ]] ||
    fail "concurrent selector view did not converge: $theme"
done
[[ "$(find "$view_root/themes" -mindepth 1 -maxdepth 1 -type l | wc -l)" == 14 ]] ||
  fail 'concurrent selector view contains unexpected links'
pass

# Installed production selector assumptions are checked read-only when present.
if [[ -d /usr/share/omarchy/themes && -e /usr/share/omarchy/bin/omarchy-theme-switcher ]]; then
  [[ -L /usr/share/omarchy/bin/omarchy-theme-switcher &&
    "$(realpath -e /usr/share/omarchy/bin/omarchy-theme-switcher)" == /usr/bin/omarchy-theme-switcher &&
    -f /usr/bin/omarchy-theme-switcher && ! -L /usr/bin/omarchy-theme-switcher && -x /usr/bin/omarchy-theme-switcher &&
    "$(stat -c %u /usr/bin/omarchy-theme-switcher)" == 0 &&
    -L /usr/share/omarchy/bin/omarchy-menu-images &&
    "$(realpath -e /usr/share/omarchy/bin/omarchy-menu-images)" == /usr/bin/omarchy-menu-images &&
    -f /usr/bin/omarchy-menu-images && ! -L /usr/bin/omarchy-menu-images && -x /usr/bin/omarchy-menu-images &&
    "$(stat -c %u /usr/bin/omarchy-menu-images)" == 0 ]] || fail 'installed production selector layout is incompatible'
else
  printf 'SKIP: installed production selector layout unavailable\n'
fi
pass

# Concurrent shell replacement at the engine hold is never overwritten; state
# remains so the original vector can be restored and retried safely.
read -r concurrent_host concurrent_home < <(prepare_native_desktop concurrent)
hold="$TEST_ROOT/concurrent-hold"
mkdir "$hold"
HOME="$concurrent_home" PATH="$fake_bin:$PATH" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$concurrent_host" \
  DOTFILES_TEST_HOLD_AT=lean-before-json-rename DOTFILES_TEST_HOLD_DIR="$hold" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  "$DOTFILES" apply desktop > "$TEST_ROOT/concurrent.log" 2>&1 &
child=$!
wait_for_file "$hold/lean-before-json-rename.ready"
jq '.unrelated.concurrent = true' "$concurrent_home/$SHELL_REL" > "$concurrent_home/.config/omarchy/concurrent.json"
mv -fT "$concurrent_home/.config/omarchy/concurrent.json" "$concurrent_home/$SHELL_REL"
: > "$hold/lean-before-json-rename.release"
if wait "$child"; then fail 'concurrent desktop JSON update unexpectedly succeeded'; fi
assert_contains "$(< "$TEST_ROOT/concurrent.log")" 'changed concurrently; refusing overwrite'
jq -e '.idle.lock == 300 and .unrelated.concurrent == true' "$concurrent_home/$SHELL_REL" >/dev/null ||
  fail 'concurrent shell update was overwritten'
assert_file "$concurrent_home/.local/state/dotfiles/v2/desktop.json"
if compgen -G "$concurrent_home/.config/omarchy/.shell.json.tmp.*" >/dev/null; then fail 'concurrent refusal retained a JSON temp'; fi
pass

# Ubuntu apply/check/remove are validation-only, including an ownership-free
# default remove, and do not require Stow or invent desktop state.
ubuntu="$(make_host desktop-ubuntu linux ubuntu 24.04)"
ubuntu_home="$(new_home desktop-ubuntu)"
before="$(find "$ubuntu_home" -mindepth 1 -printf '%P\n')"
for verb in apply check remove; do
  expect_success "$ubuntu_home" "$ubuntu" "$DOTFILES" "$verb" desktop
  assert_contains "$TEST_OUTPUT" 'outside the Ubuntu profile'
done
after="$(find "$ubuntu_home" -mindepth 1 -printf '%P\n')"
[[ "$before" == "$after" && ! -e "$ubuntu_home/.local/state/dotfiles/v2/desktop.json" ]] ||
  fail 'Ubuntu desktop lifecycle wrote files or state'
expect_success "$ubuntu_home" "$ubuntu" "$DOTFILES" remove
[[ ! -e "$ubuntu_home/.local/state/dotfiles/v2/desktop.json" ]] || fail 'Ubuntu default remove invented desktop state'
assert_not_contains "$TEST_OUTPUT" 'desktop'
pass

# The real shortcuts CLI repeatedly evolves generated menu content against an
# isolated deployed desktop. Hashless v2 state bootstraps before repository
# mutation; every apply/check converges and removal restores unrelated bytes.
shortcuts_repo="$(copy_repo_fixture desktop-shortcuts-cli)"
read -r shortcuts_host shortcuts_home < <(prepare_native_desktop shortcuts-cli)
printf '%s\n' '{' '  "unrelated.cli": {"action":"preserve"}' '}' > "$shortcuts_home/$MENU_REL"
cp -a "$shortcuts_home/$MENU_REL" "$TEST_ROOT/shortcuts-cli-menu.original"
expect_success "$shortcuts_home" "$shortcuts_host" "$shortcuts_repo/dotfiles.sh" apply desktop
shortcuts_state="$shortcuts_home/.local/state/dotfiles/v2/desktop.json"
jq '.version = 2 | .attachments |= map_values({id,origin,before_sha256})' "$shortcuts_state" > "$shortcuts_home/hashless-state.json"
mv -fT "$shortcuts_home/hashless-state.json" "$shortcuts_state"
shortcuts_bin="$TEST_ROOT/shortcuts-cli-bin"
mkdir "$shortcuts_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$shortcuts_bin/stow"
cat > "$shortcuts_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
cat > "$shortcuts_bin/hyprctl" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod 0755 "$shortcuts_bin/stow" "$shortcuts_bin/omarchy" "$shortcuts_bin/hyprctl"
shortcuts_runtime="$TEST_ROOT/shortcuts-runtime"
mkdir "$shortcuts_runtime"
chmod 0700 "$shortcuts_runtime"
run_shortcuts_cli() {
  local output
  if ! output="$(HOME="$shortcuts_home" PATH="$shortcuts_bin:$PATH" XDG_RUNTIME_DIR="$shortcuts_runtime" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$shortcuts_host" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
    "$shortcuts_repo/scripts/dotfiles-shortcuts" "$@" 2>&1)"; then
    TEST_OUTPUT="$output"
    fail "desktop shortcuts CLI failed: $*"
  fi
}
jq '.groups += [{"id":"manual-sync","name":"Manual sync","prefix":"m"}]' \
  "$shortcuts_repo/manifests/desktop-shortcuts.json" > "$shortcuts_repo/manifests/manual-sync.json"
mv -fT "$shortcuts_repo/manifests/manual-sync.json" "$shortcuts_repo/manifests/desktop-shortcuts.json"
if "$shortcuts_repo/scripts/generate-desktop-shortcuts" >/dev/null 2>&1; then fail 'manual manifest edit did not make generated files stale'; fi
run_shortcuts_cli sync
grep -Fq '"shortcuts.manual-sync": {"label":"Manual sync (m)"}' "$shortcuts_home/$MENU_REL" ||
  fail 'standalone sync did not migrate hashless state before generated changes'
jq '.shortcuts += [{"id":"m-x","group":"manual-sync","key":"x","label":"x · Pending","source":"managed","output":"pending"}]' \
  "$shortcuts_repo/manifests/desktop-shortcuts.json" > "$shortcuts_repo/manifests/pending.json"
mv -fT "$shortcuts_repo/manifests/pending.json" "$shortcuts_repo/manifests/desktop-shortcuts.json"
"$shortcuts_repo/scripts/generate-desktop-shortcuts" --write
pending_hold="$TEST_ROOT/shortcuts-pending-hold"
mkdir "$pending_hold"
HOME="$shortcuts_home" PATH="$shortcuts_bin:$PATH" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$shortcuts_host" \
  DOTFILES_TEST_HOLD_AT=lean-before-final-state-write DOTFILES_TEST_HOLD_DIR="$pending_hold" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  "$shortcuts_repo/dotfiles.sh" apply desktop > "$TEST_ROOT/shortcuts-pending.log" 2>&1 &
child=$!
wait_for_file "$pending_hold/lean-before-final-state-write.ready"
grep -Fq '"shortcuts.manual-sync.x": {"label":"x · Pending"' "$shortcuts_home/$MENU_REL" ||
  fail 'pending desktop apply did not publish generated target'
jq -e '.version == 3 and
  (.attachments[".config/omarchy/extensions/omarchy-menu.jsonc"].pending_sha256 | test("^[0-9a-f]{64}$"))' \
  "$shortcuts_state" >/dev/null || fail 'pending desktop transition was not durable'
kill -TERM "$child"
: > "$pending_hold/lean-before-final-state-write.release"
if wait "$child"; then fail 'pending desktop apply unexpectedly completed'; fi
jq '(.shortcuts[] | select(.id == "m-x")) |= (.label = "x · Recovered" | .output = "recovered")' \
  "$shortcuts_repo/manifests/desktop-shortcuts.json" > "$shortcuts_repo/manifests/recovered.json"
mv -fT "$shortcuts_repo/manifests/recovered.json" "$shortcuts_repo/manifests/desktop-shortcuts.json"
if "$shortcuts_repo/scripts/generate-desktop-shortcuts" >/dev/null 2>&1; then fail 'pending recovery manifest did not leave generated files stale'; fi
run_shortcuts_cli sync
grep -Fq '"shortcuts.manual-sync.x": {"label":"x · Recovered"' "$shortcuts_home/$MENU_REL" ||
  fail 'standalone sync did not advance a pending v3 transition'
jq -e 'all(.attachments[]; .pending_sha256 == null)' "$shortcuts_state" >/dev/null ||
  fail 'standalone sync did not settle pending v3 state'
shortcuts_generated_menu="$shortcuts_repo/packages/omarchy/desktop/$MENU_FRAGMENT_REL"
cp -a "$shortcuts_generated_menu" "$TEST_ROOT/shortcuts-generated-menu.valid"
sed -i 's/Manual sync (m)/Tampered generated menu/' "$shortcuts_generated_menu"
shortcuts_live_hash="$(sha256sum "$shortcuts_home/$MENU_REL")"
DOTFILES_SHORTCUTS_MIGRATE_STATE=1 capture "$shortcuts_home" "$shortcuts_host" "$shortcuts_repo/dotfiles.sh" apply desktop
((TEST_RC != 0)) || fail 'caller-controlled migration flag bypassed v3 generated-file validation'
assert_contains "$TEST_OUTPUT" 'desktop shortcut generated files are stale'
[[ "$(sha256sum "$shortcuts_home/$MENU_REL")" == "$shortcuts_live_hash" ]] ||
  fail 'migration flag misuse changed the live v3 menu'
cp -a "$TEST_ROOT/shortcuts-generated-menu.valid" "$shortcuts_generated_menu"
run_shortcuts_cli group add --name Snippets --prefix s --id snippets
run_shortcuts_cli add --group snippets --key x --label 'x · First' --text first
run_shortcuts_cli group rename snippets --name 'Changed snippets'
run_shortcuts_cli edit s-x --label 'x · Second' --text second
expect_success "$shortcuts_home" "$shortcuts_host" "$shortcuts_repo/dotfiles.sh" check desktop
grep -Fq '"shortcuts.snippets.x": {"label":"x · Second"' "$shortcuts_home/$MENU_REL" ||
  fail 'repeated CLI evolution did not deploy the final generated menu'
grep -Fq '"unrelated.cli"' "$shortcuts_home/$MENU_REL" || fail 'CLI evolution lost unrelated menu content'
jq -e '.version == 3 and all(.attachments[];
  (.managed_sha256 | test("^[0-9a-f]{64}$")) and .pending_sha256 == null)' "$shortcuts_state" >/dev/null ||
  fail 'CLI evolution did not migrate attachment hashes'
expect_success "$shortcuts_home" "$shortcuts_host" "$shortcuts_repo/dotfiles.sh" remove desktop
assert_same "$shortcuts_home/$MENU_REL" "$TEST_ROOT/shortcuts-cli-menu.original"
pass

# Default selection includes Ubuntu validation and native desktop ownership;
# default removal discovers desktop from state rather than inventing ownership.
default_repo="$(copy_repo_fixture desktop-defaults)"
cat >> "$default_repo/lib/areas/desktop.sh" <<'SCRIPT'
for fixture_area in git tools bash tmux nvim agents herdr; do
  eval "preflight_${fixture_area}() { :; }; apply_${fixture_area}() { :; }; remove_${fixture_area}() { :; }"
done
SCRIPT
cat > "$default_repo/manifests/dependencies.tsv" <<'MANIFEST'
schema|2
manager|apt|sudo|apt-get|install|-y
manager|native
require|desktop|apply,check,remove|all|jq|apt-package|jq|bootstrap-critical
require|desktop|apply,check,remove|all|flock|apt-package|util-linux|bootstrap-critical
require|desktop|apply,check,remove|all|realpath|apt-package|coreutils|bootstrap-critical
require|desktop|apply,check,remove|omarchy|stow|omarchy-native|-|area
MANIFEST
default_ubuntu="$(make_host desktop-default-ubuntu linux ubuntu 24.04)"
default_ubuntu_home="$(new_home desktop-default-ubuntu)"
expect_success "$default_ubuntu_home" "$default_ubuntu" "$default_repo/dotfiles.sh" apply
assert_contains "$TEST_OUTPUT" 'outside the Ubuntu profile'
expect_success "$default_ubuntu_home" "$default_ubuntu" "$default_repo/dotfiles.sh" check
assert_contains "$TEST_OUTPUT" "area 'desktop' preflight passed"
[[ ! -e "$default_ubuntu_home/.local/state/dotfiles/v2/desktop.json" ]] || fail 'Ubuntu defaults invented desktop state'

read -r default_native default_home < <(prepare_native_desktop default-native)
expect_success "$default_home" "$default_native" "$default_repo/dotfiles.sh" apply
assert_file "$default_home/.local/state/dotfiles/v2/desktop.json"
expect_success "$default_home" "$default_native" "$default_repo/dotfiles.sh" check
expect_success "$default_home" "$default_native" "$default_repo/dotfiles.sh" remove
[[ ! -e "$default_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$default_home/$FRAGMENT_REL" ]] ||
  fail 'ownership-driven default remove did not remove desktop'
pass

printf 'PASS: %s desktop test groups\n' "$TEST_COUNT"
