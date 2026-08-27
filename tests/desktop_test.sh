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

for command_name in omarchy-shell hyprctl; do
  printf '#!/usr/bin/env bash\nprintf "%%s:%%s\\n" "${0##*/}" "$*" >> "$HOME/desktop-command.trace"\nexit 99\n' > "$fake_bin/$command_name"
  chmod 0755 "$fake_bin/$command_name"
done

readonly INPUT_REL='.config/hypr/input.lua'
readonly FRAGMENT_REL='.config/dotfiles/omarchy/hypr/input.lua'
readonly XCOMPOSE_REL='.XCompose'
readonly ALIASES_REL='.config/dotfiles/omarchy/XCompose'
readonly SHELL_REL='.config/omarchy/shell.json'
readonly BEGIN='-- >>> dotfiles desktop input >>>'
readonly END='-- <<< dotfiles desktop input <<<'
readonly XCOMPOSE_BEGIN='# >>> dotfiles desktop xcompose >>>'
readonly XCOMPOSE_END='# <<< dotfiles desktop xcompose <<<'

prepare_native_desktop() {
  local name="$1" root home stock
  root="$(make_host "desktop-$name" linux omarchy 4)"
  home="$(new_home "desktop-$name")"
  mkdir -p "$root/usr/share/omarchy/config/hypr" "$home/.config/hypr" "$home/.config/omarchy"
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

# The package is exactly the natural-scroll fragment and four Compose aliases.
fragment="$REPO_DIR/packages/omarchy/desktop/$FRAGMENT_REL"
aliases="$REPO_DIR/packages/omarchy/desktop/$ALIASES_REL"
expected_fragment=$'hl.config({\n  input = {\n    touchpad = {\n      natural_scroll = true,\n    },\n  },\n})'
expected_aliases=$'<Multi_key> <space> <a> : "AGENTS.md"\n<Multi_key> <p> <b> : "Continue discussing with me briefly."\n<Multi_key> <p> <d> : "Continue discussing with me, focussing on points we have yet to agree on."\n<Multi_key> <p> <t> : "What do you think/recommend? Discuss with me."'
[[ "$(< "$fragment")" == "$expected_fragment" ]] || fail 'desktop fragment is not exact'
[[ "$(< "$aliases")" == "$expected_aliases" ]] || fail 'desktop Compose aliases are not exact'
[[ "$(find "$REPO_DIR/packages/omarchy/desktop" -type f | wc -l)" == 2 ]] || fail 'desktop package payload inventory is not exact'
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
[[ -L "$home/$FRAGMENT_REL" && -L "$home/$ALIASES_REL" && "$(stat -c %a "$home/$INPUT_REL")" == 640 &&
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
[[ ! -e "$state" && ! -e "$home/$FRAGMENT_REL" && ! -e "$home/$ALIASES_REL" ]] ||
  fail 'desktop removal retained state or package link'
assert_file "$home/$INPUT_REL"
assert_file "$home/$XCOMPOSE_REL"
[[ "$(grep -cF -- "$BEGIN" "$home/$INPUT_REL" || true)" == 0 ]] || fail 'desktop removal retained loader'
assert_same "$home/$XCOMPOSE_REL" "$TEST_ROOT/xcompose.refreshed"
jq -e '.idle.screensaver == 150 and .idle.lock == 300 and .unrelated.during_ownership == "keep" and .bar.layout.right[0].id == "omarchy.tailscale"' \
  "$home/$SHELL_REL" >/dev/null || fail 'desktop removal changed unrelated shell semantics'
[[ ! -e "$home/desktop-command.trace" ]] || fail 'desktop lifecycle invoked restart/reload commands'
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
