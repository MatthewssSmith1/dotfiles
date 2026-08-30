#!/usr/bin/env bash
# Native desktop ownership and Ubuntu validation-only behavior.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
cat > "$fake_bin/stat" <<'SCRIPT'
#!/usr/bin/env bash
if [[ -n "${DOTFILES_TEST_BAD_OWNER_PATH:-}" && "$1" == -c && "$2" == %u && "${*: -1}" == "$DOTFILES_TEST_BAD_OWNER_PATH" ]]; then
  printf '%s\n' "$((EUID + 1))"
  exit 0
fi
exec /usr/bin/stat "$@"
SCRIPT
chmod 0755 "$fake_bin/stat"
FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
export FAKE_STOW_TRACE
CAPTURE_PATH_PREFIX="$fake_bin"

for command_name in omarchy-shell hyprctl omarchy-theme-switcher omarchy-theme-set; do
  printf '#!/usr/bin/env bash\nprintf "%%s:%%s\\n" "${0##*/}" "$*" >> "$HOME/desktop-command.trace"\nexit 99\n' > "$fake_bin/$command_name"
  chmod 0755 "$fake_bin/$command_name"
done

readonly INPUT_REL='.config/hypr/input.lua'
readonly FRAGMENT_REL='.config/dotfiles/omarchy/hypr/input.lua'
readonly XCOMPOSE_REL='.XCompose'
readonly ALIASES_REL='.config/dotfiles/omarchy/XCompose'
readonly SHELL_REL='.config/omarchy/shell.json'
readonly MENU_REL='.config/omarchy/extensions/omarchy-menu.jsonc'
readonly SWITCHER_REL='.local/bin/dotfiles-omarchy-theme-switcher'
readonly BEGIN='-- >>> dotfiles desktop input >>>'
readonly END='-- <<< dotfiles desktop input <<<'
readonly XCOMPOSE_BEGIN='# >>> dotfiles desktop xcompose >>>'
readonly XCOMPOSE_END='# <<< dotfiles desktop xcompose <<<'

prepare_native_desktop() {
  local name="$1" root home stock
  root="$(make_host "desktop-$name" linux omarchy 4)"
  home="$(new_home "desktop-$name")"
  mkdir -p "$root/usr/share/omarchy/config/hypr" "$root/usr/share/omarchy/config/omarchy/extensions" \
    "$home/.config/hypr" "$home/.config/omarchy"
  printf '4.0.0.alpha\n' > "$root/usr/share/omarchy/version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/usr/bin/omarchy"
  chmod 0755 "$root/usr/bin/omarchy"
  stock="$root/usr/share/omarchy/config/hypr/input.lua"
  printf '%s\n' '-- stock input' 'hl.config({ input = {} })' > "$stock"
  cp "$stock" "$home/$INPUT_REL"
  chmod 0640 "$home/$INPUT_REL"
  cat > "$home/$XCOMPOSE_REL" <<'XCOMPOSE'
# Include fast emoji access
include "/usr/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "Example User"
<Multi_key> <space> <e> : "user@example.com"
XCOMPOSE
  chmod 0640 "$home/$XCOMPOSE_REL"
  cat > "$home/$SHELL_REL" <<'JSON'
{
  "version": 1,
  "idle": { "screensaver": 150, "lock": 300 },
  "bar": { "layout": { "right": [{ "id": "omarchy.tailscale" }] } },
  "plugins": [{ "id": "fixture", "options": { "nested": true } }],
  "unrelated": { "array": [3, 1, 2] }
}
JSON
  chmod 0640 "$home/$SHELL_REL"
  printf '%s\n' '{' '  // Stock personal menu extension.' '}' > "$root/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc"
  record_pacman_ownership "$root" 'omarchy 4.0.1-1' /usr/share/omarchy/version /usr/bin/omarchy
  record_pacman_ownership "$root" 'omarchy-settings 4.0.1-1' /usr/share/omarchy/config/hypr/input.lua
  printf '%s\t%s\n' "$root" "$home"
}

read -r native home < <(prepare_native_desktop lifecycle)
stock="$native/usr/share/omarchy/config/hypr/input.lua"
stock_hash="$(sha256sum "$stock")"
cp -a "$home/$INPUT_REL" "$TEST_ROOT/input.original"
cp -a "$home/$XCOMPOSE_REL" "$TEST_ROOT/xcompose.original"
cp -a "$home/$SHELL_REL" "$TEST_ROOT/shell.original"
: > "$FAKE_STOW_TRACE"

# The package contains the two desktop fragments and two theme-filter payloads.
fragment="$REPO_DIR/packages/omarchy/desktop/$FRAGMENT_REL"
aliases="$REPO_DIR/packages/omarchy/desktop/$ALIASES_REL"
expected_fragment=$'hl.config({\n  input = {\n    touchpad = {\n      natural_scroll = true,\n    },\n  },\n})'
expected_aliases=$'<Multi_key> <space> <a> : "AGENTS.md"\n<Multi_key> <p> <b> : "Continue discussing with me briefly."\n<Multi_key> <p> <d> : "Continue discussing with me, focussing on points we have yet to agree on."\n<Multi_key> <p> <t> : "What do you think/recommend? Discuss with me."'
[[ "$(< "$fragment")" == "$expected_fragment" ]] || fail 'desktop fragment is not exact'
[[ "$(< "$aliases")" == "$expected_aliases" ]] || fail 'desktop Compose aliases are not exact'
[[ "$(find "$REPO_DIR/packages/omarchy/desktop" -type f | wc -l)" == 4 ]] || fail 'desktop package payload inventory is not exact'
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

# Existing stock and edited menu-extension templates are preserved with distinct
# one-time adoption guidance.
for kind in stock edited; do
  read -r menu_host menu_home < <(prepare_native_desktop "menu-$kind")
  mkdir -p "$menu_home/.config/omarchy/extensions"
  cp "$menu_host/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc" "$menu_home/$MENU_REL"
  if [[ "$kind" == edited ]]; then
    printf '%s\n' '// personal row' >> "$menu_home/$MENU_REL"
    expected='manually merge'
  else
    expected='one-time adoption'
  fi
  cp "$menu_home/$MENU_REL" "$TEST_ROOT/menu-$kind.original"
  for verb in apply check; do
    expect_failure "$expected" "$menu_home" "$menu_host" "$DOTFILES" "$verb" desktop
    assert_same "$menu_home/$MENU_REL" "$TEST_ROOT/menu-$kind.original"
    [[ ! -e "$menu_home/.local/state/dotfiles/v2/desktop.json" && ! -e "$menu_home/$SWITCHER_REL" ]] ||
      fail "$verb changed files during $kind menu adoption refusal"
  done
done
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
  .version == 2 and .area == "desktop" and .profile == "omarchy" and
  (.attachments | keys) == [".XCompose", ".config/hypr/input.lua"] and
  .resources[".config/omarchy/shell.json"].fields["/idle/screensaver"].original == 150 and
  .resources[".config/omarchy/shell.json"].fields["/idle/lock"].original == 300
' "$state" >/dev/null || fail 'desktop state does not contain complete origins'
assert_file "$home/$INPUT_REL"
assert_file "$home/$SHELL_REL"
[[ -L "$home/$FRAGMENT_REL" && -L "$home/$ALIASES_REL" && -L "$home/$MENU_REL" && -L "$home/$SWITCHER_REL" &&
  "$(stat -c %a "$home/$INPUT_REL")" == 640 &&
  "$(stat -c %a "$home/$XCOMPOSE_REL")" == 640 && "$(stat -c %a "$home/$SHELL_REL")" == 640 ]] ||
  fail 'desktop apply changed regular-file or mode contracts'
[[ "$(grep -cFx -- "$BEGIN" "$home/$INPUT_REL")" == 1 && "$(grep -cFx -- "$END" "$home/$INPUT_REL")" == 1 ]] ||
  fail 'desktop loader was not attached exactly once'
[[ "$(grep -cFx -- "$XCOMPOSE_BEGIN" "$home/$XCOMPOSE_REL")" == 1 &&
  "$(grep -cFx -- "$XCOMPOSE_END" "$home/$XCOMPOSE_REL")" == 1 ]] ||
  fail 'desktop XCompose loader was not attached exactly once'
xcompose_block_line="$(grep -nFx -- "$XCOMPOSE_BEGIN" "$home/$XCOMPOSE_REL" | cut -d: -f1)"
sed -n "1,$((xcompose_block_line - 1))p" "$home/$XCOMPOSE_REL" > "$TEST_ROOT/xcompose-prefix"
assert_same "$TEST_ROOT/xcompose-prefix" "$TEST_ROOT/xcompose.original"
jq -e '.idle.screensaver == 600 and .idle.lock == 900 and .bar.layout.right[0].id == "omarchy.tailscale" and .plugins[0].options.nested == true and .unrelated.array == [3,1,2]' \
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
printf '%s\n' '<Multi_key> <o> <r> : "Refreshed Omarchy"' > "$home/$XCOMPOSE_REL"
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

# Removal restores only recorded fields, preserves unrelated semantic changes,
# removes the exact loader/link, and deletes state last.
jq '.idle.lock = 900 | .unrelated.during_ownership = "keep"' "$home/$SHELL_REL" > "$home/.config/omarchy/repaired.json"
mv -fT "$home/.config/omarchy/repaired.json" "$home/$SHELL_REL"
chmod 0640 "$home/$SHELL_REL"
expect_success "$home" "$native" "$DOTFILES" remove desktop
[[ ! -e "$state" && ! -e "$home/$FRAGMENT_REL" && ! -e "$home/$ALIASES_REL" &&
  ! -e "$home/$MENU_REL" && ! -e "$home/$SWITCHER_REL" ]] ||
  fail 'desktop removal retained state or package link'
assert_file "$home/$INPUT_REL"
assert_file "$home/$XCOMPOSE_REL"
[[ "$(grep -cF -- "$BEGIN" "$home/$INPUT_REL" || true)" == 0 ]] || fail 'desktop removal retained loader'
assert_same "$home/$XCOMPOSE_REL" "$TEST_ROOT/xcompose.refreshed"
jq -e '.idle.screensaver == 150 and .idle.lock == 300 and .unrelated.during_ownership == "keep" and .bar.layout.right[0].id == "omarchy.tailscale"' \
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
    rm "$lost_home/$FRAGMENT_REL" "$lost_home/$ALIASES_REL" "$lost_home/$MENU_REL" "$lost_home/$SWITCHER_REL"
  fi
  input_before="$(sha256sum "$lost_home/$INPUT_REL")"
  xcompose_before="$(sha256sum "$lost_home/$XCOMPOSE_REL")"
  expect_failure 'lean ownership state is absent' "$lost_home" "$lost_host" "$DOTFILES" remove desktop
  [[ "$(sha256sum "$lost_home/$INPUT_REL")" == "$input_before" &&
    "$(sha256sum "$lost_home/$XCOMPOSE_REL")" == "$xcompose_before" ]] ||
    fail "missing-state $retained removal changed guarded files"
  if [[ "$retained" == links ]]; then
    [[ -L "$lost_home/$FRAGMENT_REL" && -L "$lost_home/$MENU_REL" ]] ||
      fail 'missing-state removal deleted retained package links'
  else
    [[ "$(grep -cFx -- "$BEGIN" "$lost_home/$INPUT_REL")" == 1 &&
      "$(grep -cFx -- "$XCOMPOSE_BEGIN" "$lost_home/$XCOMPOSE_REL")" == 1 ]] ||
      fail 'missing-state removal deleted retained guarded markers'
  fi
done
pass

# Replaced managed menu destinations are drift and are never overwritten or removed.
read -r replaced_host replaced_home < <(prepare_native_desktop replaced-menu)
expect_success "$replaced_home" "$replaced_host" "$DOTFILES" apply desktop
rm "$replaced_home/$MENU_REL"
printf '%s\n' '{"personal":true}' > "$replaced_home/$MENU_REL"
cp "$replaced_home/$MENU_REL" "$TEST_ROOT/replaced-menu.original"
expect_failure 'manually merge' "$replaced_home" "$replaced_host" "$DOTFILES" apply desktop
assert_same "$replaced_home/$MENU_REL" "$TEST_ROOT/replaced-menu.original"
expect_failure 'unrelated destination conflict' "$replaced_home" "$replaced_host" "$DOTFILES" remove desktop
assert_same "$replaced_home/$MENU_REL" "$TEST_ROOT/replaced-menu.original"
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
runtime_cache_base="$TEST_ROOT/theme-cache"
runtime_trace="$TEST_ROOT/theme-selector.trace"
mkdir -p "$runtime_root/bin" "$runtime_root/themes" "$runtime_cache_base" \
  "$runtime_home/.config/omarchy/themes/user-only" "$runtime_home/.config/omarchy/themes/ethereal"
for theme in ethereal flexoki-light hackerman last-horizon lumon lupine miasma rose-pine vantablack white \
  tokyo-night catppuccin; do
  mkdir "$runtime_root/themes/$theme"
done
printf '%s\n' bundled-preview > "$runtime_root/themes/ethereal/preview.png"
cat > "$runtime_root/bin/omarchy-theme-switcher" <<'SCRIPT'
#!/usr/bin/env bash
printf 'OMARCHY_PATH=%s\nXDG_CACHE_HOME=%s\n' "$OMARCHY_PATH" "$XDG_CACHE_HOME" >> "$FAKE_SELECTOR_TRACE"
printf '%s\0' "$@" > "$FAKE_SELECTOR_TRACE.args"
theme=ethereal
bundled="$OMARCHY_PATH/themes/$theme"
user="$HOME/.config/omarchy/themes/$theme"
[[ -d "$bundled" && -d "$user" ]] || exit 97
printf 'VISIBLE_THEME_SOURCE=%s\n' "$user" >> "$FAKE_SELECTOR_TRACE"
if [[ -f "$user/preview.png" ]]; then preview="$user/preview.png"; else preview="$bundled/preview.png"; fi
[[ -f "$preview" ]] || exit 98
printf 'VISIBLE_THEME_PREVIEW=%s\n' "$(< "$preview")" >> "$FAKE_SELECTOR_TRACE"
printf '%s\n' 'selected-theme'
printf '%s\n' 'native-selector-stderr' >&2
exit "${FAKE_SELECTOR_STATUS:-0}"
SCRIPT
chmod 0755 "$runtime_root/bin/omarchy-theme-switcher"

run_theme_selector() {
  local status
  set +e
  HOME="$runtime_home" OMARCHY_PATH="$runtime_root" XDG_CACHE_HOME="$runtime_cache_base" \
    FAKE_SELECTOR_TRACE="$runtime_trace" FAKE_SELECTOR_STATUS="${FAKE_SELECTOR_STATUS:-0}" \
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
assert_contains "$(< "$runtime_trace")" "VISIBLE_THEME_SOURCE=$runtime_home/.config/omarchy/themes/ethereal"
assert_contains "$(< "$runtime_trace")" 'VISIBLE_THEME_PREVIEW=bundled-preview'
[[ -L "$view_root/themes/ethereal" && "$(readlink "$view_root/themes/ethereal")" == "$runtime_root/themes/ethereal" ]] ||
  fail 'denied bundled theme was not retained as a user-theme preview fallback'
for theme in flexoki-light hackerman last-horizon lumon lupine miasma rose-pine vantablack white; do
  [[ ! -e "$view_root/themes/$theme" && ! -L "$view_root/themes/$theme" ]] || fail "denied theme is visible: $theme"
done
for theme in tokyo-night catppuccin; do
  [[ -L "$view_root/themes/$theme" && "$(readlink "$view_root/themes/$theme")" == "$runtime_root/themes/$theme" ]] ||
    fail "allowed theme link is not exact: $theme"
done
[[ -d "$runtime_home/.config/omarchy/themes/user-only" && ! -e "$view_root/themes/user-only" ]] ||
  fail 'selector changed or copied the user theme view'

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
  HOME="$runtime_home" OMARCHY_PATH="$runtime_root" XDG_CACHE_HOME="$unsafe_cache" "$selector" \
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
HOME="$runtime_home" OMARCHY_PATH="$missing_root" XDG_CACHE_HOME="$runtime_cache_base" "$selector" \
  > /dev/null 2> "$TEST_ROOT/missing-selector.stderr"
missing_status=$?
set -e
[[ "$missing_status" != 0 ]] || fail 'missing native selector was accepted'
assert_contains "$(< "$TEST_ROOT/missing-selector.stderr")" 'native theme selector is missing or unsafe'
rm -r "$missing_root/themes"
cp "$runtime_root/bin/omarchy-theme-switcher" "$missing_root/bin/omarchy-theme-switcher"
set +e
HOME="$runtime_home" OMARCHY_PATH="$missing_root" XDG_CACHE_HOME="$runtime_cache_base" "$selector" \
  > /dev/null 2> "$TEST_ROOT/missing-themes.stderr"
missing_status=$?
set -e
[[ "$missing_status" != 0 ]] || fail 'missing themes directory was accepted'
assert_contains "$(< "$TEST_ROOT/missing-themes.stderr")" 'bundled themes directory is missing or unsafe'

rm -f "$view_root/themes/"*
children=()
for invocation in 1 2 3 4 5 6; do
  HOME="$runtime_home" OMARCHY_PATH="$runtime_root" XDG_CACHE_HOME="$runtime_cache_base" \
    FAKE_SELECTOR_TRACE="$runtime_trace.concurrent.$invocation" "$selector" --preload \
    > "$TEST_ROOT/concurrent-selector.$invocation.out" 2> "$TEST_ROOT/concurrent-selector.$invocation.err" &
  children+=("$!")
done
for child in "${children[@]}"; do wait "$child" || fail 'concurrent theme selector invocation failed'; done
for theme in ethereal tokyo-night catppuccin new-upstream-theme; do
  [[ -L "$view_root/themes/$theme" && "$(readlink "$view_root/themes/$theme")" == "$runtime_root/themes/$theme" ]] ||
    fail "concurrent selector view did not converge: $theme"
done
[[ "$(find "$view_root/themes" -mindepth 1 -maxdepth 1 -type l | wc -l)" == 4 ]] ||
  fail 'concurrent selector view contains unexpected links'
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
