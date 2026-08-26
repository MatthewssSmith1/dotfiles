#!/usr/bin/env bash
# Focused tests for the final deployment runtime and profile parser.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/lean_engine.sh"
trap - EXIT INT TERM
trap cleanup_test EXIT

SCRIPT_NAME=lean-engine-test
DOTFILES_DIR="$TEST_ROOT/repo"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
export FAKE_STOW_TRACE
mkdir -p "$DOTFILES_DIR/packages/common/one" "$DOTFILES_DIR/packages/common/two/.config/lean" \
  "$DOTFILES_DIR/profiles" "$FAKE_BIN"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$FAKE_BIN/stow"
chmod 0755 "$FAKE_BIN/stow"
export PATH="$FAKE_BIN:$PATH"
printf 'one\n' > "$DOTFILES_DIR/packages/common/one/.one"
printf 'two\n' > "$DOTFILES_DIR/packages/common/two/.config/lean/two"

readonly ATTACH_BEGIN='# >>> dotfiles lean fixture >>>'
readonly ATTACH_END='# <<< dotfiles lean fixture <<<'
readonly ATTACH_TOKEN='dotfiles lean fixture'
readonly ATTACH_BLOCK="$ATTACH_BEGIN
source \"\$HOME/.config/lean/personal.bash\"
$ATTACH_END"

reset_lean_home() {
  local name="$1"
  HOME="$TEST_ROOT/home-$name"
  mkdir "$HOME"
  TARGET_ROOT="$HOME"
  : > "$FAKE_STOW_TRACE"
  unset FAKE_STOW_FAIL_PACKAGE DOTFILES_TESTING DOTFILES_TEST_HOLD_AT DOTFILES_TEST_HOLD_DIR
}

validate_fixture_json() {
  jq -e '
    .schema == 1 and (.idle | type == "object") and
    (.idle.screensaver | type == "number" and floor == .) and
    (.idle.lock | type == "number" and floor == .)
  ' "$1" >/dev/null
}

write_fixture_json() {
  local screensaver="${1:-150}" lock="${2:-300}"
  mkdir -p "$HOME/.config/lean"
  printf '{\n  "schema": 1,\n  "idle": { "screensaver": %s, "lock": %s },\n  "bar": { "widgets": ["clock", "tailscale"] },\n  "unrelated": { "nested": true }\n}\n' \
    "$screensaver" "$lock" > "$HOME/.config/lean/app.json"
}

register_packages() {
  local profile="${1:-omarchy}"
  lean_begin_area fixture "$profile" packages
  lean_add_package common/one
  lean_add_package common/two
}

register_attachment() {
  local profile="${1:-omarchy}"
  lean_begin_area attached "$profile" packages
  lean_add_package common/one
  lean_add_guarded_attachment bash-rc-v1 .bashrc "$ATTACH_BEGIN" "$ATTACH_END" \
    "$ATTACH_TOKEN" "$ATTACH_BLOCK" append 0644
}

register_structured() {
  local profile="${1:-omarchy}"
  lean_begin_area structured "$profile" packages
  lean_add_package common/one
  lean_add_guarded_attachment bash-rc-v1 .bashrc "$ATTACH_BEGIN" "$ATTACH_END" \
    "$ATTACH_TOKEN" "$ATTACH_BLOCK" append 0644
  lean_add_json_scalar_fields fixture-idle-v1 .config/lean/app.json validate_fixture_json \
    /idle/screensaver integer 600 /idle/lock integer 900
}

register_json_only() {
  lean_begin_area json-only omarchy packages
  lean_add_json_scalar_fields fixture-idle-v1 .config/lean/app.json validate_fixture_json \
    /idle/screensaver integer 600 /idle/lock integer 900
}

capture_direct() {
  set +e
  TEST_OUTPUT="$("$@" 2>&1)"
  TEST_RC=$?
  set -e
}

expect_direct_failure() {
  local expected="$1"
  shift
  capture_direct "$@"
  ((TEST_RC != 0)) || fail 'lean command unexpectedly succeeded'
  assert_contains "$TEST_OUTPUT" "$expected"
}

apply_packages() { register_packages "${1:-omarchy}"; lean_apply_area; }
check_packages() { register_packages "${1:-omarchy}"; lean_check_area; }
remove_packages() { register_packages "${1:-omarchy}"; lean_remove_area; }
apply_attachment() { register_attachment "${1:-omarchy}"; lean_apply_area; }
remove_attachment() { register_attachment "${1:-omarchy}"; lean_remove_area; }
apply_structured() { register_structured "${1:-omarchy}"; lean_apply_area; }
check_structured() { register_structured "${1:-omarchy}"; lean_check_area; }
remove_structured() { register_structured "${1:-omarchy}"; lean_remove_area; }
apply_json_only() { register_json_only; lean_apply_area; }

# Check performs Stow/package inspection only and package-only apply writes no
# ownership state.
reset_lean_home check
apply_packages
one_link="$(readlink -- "$HOME/.one")"
two_link="$(readlink -- "$HOME/.config/lean/two")"
check_packages
expect_direct_failure 'refusing lean state write without guarded attachments' lean_write_state_atomic
[[ ! -e "$HOME/.local/state/dotfiles/v2" && "$(readlink -- "$HOME/.one")" == "$one_link" &&
  "$(readlink -- "$HOME/.config/lean/two")" == "$two_link" ]] || fail 'lean check mutated managed objects'
pass

# Existing guarded files retain exact host bytes and mode around the managed
# block; apply and remove use atomic regular-file replacement.
reset_lean_home attachment-lifecycle
printf 'native bytes without newline' > "$HOME/.bashrc"
chmod 0640 "$HOME/.bashrc"
cp -a "$HOME/.bashrc" "$TEST_ROOT/attachment.original"
apply_attachment
register_attachment
lean_check_area
remove_attachment
assert_same "$HOME/.bashrc" "$TEST_ROOT/attachment.original"
[[ "$(stat -c %a -- "$HOME/.bashrc")" == 640 ]] || fail 'attachment lifecycle changed the host file mode'
pass

# Every Stow simulation and attachment conflict check completes before state or
# package writes. The pre-existing conflict is retained byte-for-byte.
reset_lean_home full-preflight
printf 'host bytes\n%s\n' "$ATTACH_BEGIN" > "$HOME/.bashrc"
cp "$HOME/.bashrc" "$TEST_ROOT/full-preflight.original"
expect_direct_failure 'partial, malformed' apply_attachment
[[ ! -e "$HOME/.one" && ! -e "$HOME/.local/state/dotfiles/v2/attached.json" ]] ||
  fail 'full preflight failure occurred after the first managed write'
assert_same "$HOME/.bashrc" "$TEST_ROOT/full-preflight.original"
[[ "$(< "$FAKE_STOW_TRACE")" == 'stow|true|one' ]] || fail 'apply did not complete Stow simulation before refusing attachment'
pass

# A failed second package leaves only derivable repository links and no state.
# Re-running after the package failure converges directly.
reset_lean_home retry
FAKE_STOW_FAIL_PACKAGE=two
export FAKE_STOW_FAIL_PACKAGE
capture_direct apply_packages
((TEST_RC != 0)) || fail 'injected fake Stow failure unexpectedly succeeded'
[[ -L "$HOME/.one" && ! -e "$HOME/.config/lean/two" ]] || fail 'partial apply did not stop safely'
[[ ! -e "$HOME/.local/state/dotfiles/v2" ]] || fail 'failed package-only apply wrote intent state'
unset FAKE_STOW_FAIL_PACKAGE
apply_packages
check_packages
pass

# Unrelated regular files and unrelated links are never adopted or overwritten.
reset_lean_home conflict
printf 'unrelated\n' > "$HOME/.one"
expect_direct_failure 'unrelated destination conflict' apply_packages
[[ "$(< "$HOME/.one")" == unrelated && ! -e "$HOME/.local/state/dotfiles/v2" ]] ||
  fail 'unrelated destination conflict was changed'
pass

# Removal refuses both a replaced package link and a modified guarded block.
# Only the attachment-owning area retains state for manual repair.
reset_lean_home modified-remove
apply_packages
rm "$HOME/.one"
ln -s "$TEST_ROOT/unrelated" "$HOME/.one"
expect_direct_failure 'unrelated destination conflict' remove_packages
[[ ! -e "$HOME/.local/state/dotfiles/v2" && -L "$HOME/.one" ]] ||
  fail 'refused package-only removal wrote state or removed the conflicting link'

reset_lean_home modified-attachment
printf 'native\n' > "$HOME/.bashrc"
apply_attachment
printf '%s\n' 'changed managed line' >> "$HOME/.bashrc"
# Surrounding host bytes may change, but changing a marker block itself must refuse.
sed -i 's|source "$HOME/.config/lean/personal.bash"|modified managed block|' "$HOME/.bashrc"
expect_direct_failure 'partial, malformed' remove_attachment
assert_file "$HOME/.local/state/dotfiles/v2/attached.json"
pass

# Already-absent owned links and attachment files converge on removal retry.
reset_lean_home absent-remove
apply_packages
rm "$HOME/.one"
remove_packages
[[ ! -e "$HOME/.local/state/dotfiles/v2" && ! -e "$HOME/.config/lean/two" ]] ||
  fail 'absent package target did not converge during removal'
remove_packages
assert_contains "$(< "$FAKE_STOW_TRACE")" 'delete|true|two'
assert_contains "$(< "$FAKE_STOW_TRACE")" 'delete|false|two'
reset_lean_home absent-attachment
apply_attachment
rm "$HOME/.bashrc"
remove_attachment
[[ ! -e "$HOME/.local/state/dotfiles/v2/attached.json" && ! -e "$HOME/.one" ]] ||
  fail 'absent attachment did not converge during removal'
pass

# State replacement keeps the old complete object visible until one
# same-directory rename publishes the new complete object.
reset_lean_home atomic-state
apply_attachment
hold="$TEST_ROOT/state-hold"
mkdir "$hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$DOTFILES_DIR" PATH="$PATH" \
  FAKE_STOW_TRACE="$FAKE_STOW_TRACE" DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=lean-before-state-rename \
  DOTFILES_TEST_HOLD_DIR="$hold" SCRIPT_NAME=lean-state-child bash -c '
    set -Eeuo pipefail
    source "'$REPO_DIR'/lib/common.sh"
    source "'$REPO_DIR'/lib/lean_engine.sh"
    lean_begin_area attached omarchy packages
    LEAN_ATTACHMENT_IDS=(bash-rc-v1)
    LEAN_ATTACHMENT_PATHS=(.bashrc)
    LEAN_ATTACHMENT_ORIGINS=(created)
    LEAN_ATTACHMENT_BEFORE_HASHES=("")
    LEAN_ATTACHMENT_IDS+=(bash-login-v1)
    LEAN_ATTACHMENT_PATHS+=(.profile)
    LEAN_ATTACHMENT_ORIGINS+=(created)
    LEAN_ATTACHMENT_BEFORE_HASHES+=("")
    lean_write_state_atomic
  ' > "$TEST_ROOT/state-child.log" 2>&1 &
child=$!
wait_for_file "$hold/lean-before-state-rename.ready"
jq -e '.version == 1 and (.attachments | length) == 1' "$HOME/.local/state/dotfiles/v2/attached.json" >/dev/null ||
  fail 'state replacement exposed a partial destination before atomic rename'
: > "$hold/lean-before-state-rename.release"
wait "$child" || fail 'atomic state child failed'
jq -e '.version == 1 and .area == "attached" and (.attachments | length) == 2' \
  "$HOME/.local/state/dotfiles/v2/attached.json" >/dev/null ||
  fail 'atomically published state is malformed'

rm -rf "$hold"
mkdir "$hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$DOTFILES_DIR" PATH="$PATH" \
  FAKE_STOW_TRACE="$FAKE_STOW_TRACE" DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=lean-before-state-rename \
  DOTFILES_TEST_HOLD_DIR="$hold" SCRIPT_NAME=lean-state-interrupt bash -c '
    set -Eeuo pipefail
    source "'$REPO_DIR'/lib/common.sh"
    source "'$REPO_DIR'/lib/lean_engine.sh"
    lean_begin_area attached omarchy packages
    LEAN_ATTACHMENT_IDS=(bash-rc-v1 bash-login-v1 bash-profile-v1)
    LEAN_ATTACHMENT_PATHS=(.bashrc .profile .bash_profile)
    LEAN_ATTACHMENT_ORIGINS=(created created created)
    LEAN_ATTACHMENT_BEFORE_HASHES=("" "" "")
    lean_write_state_atomic
  ' > "$TEST_ROOT/state-interrupt.log" 2>&1 &
child=$!
wait_for_file "$hold/lean-before-state-rename.ready"
kill -TERM "$child"
if wait "$child"; then fail 'interrupted state publication unexpectedly succeeded'; fi
jq -e '.version == 1 and (.attachments | length) == 2' "$HOME/.local/state/dotfiles/v2/attached.json" >/dev/null ||
  fail 'interrupted state publication changed the destination'
if compgen -G "$HOME/.local/state/dotfiles/v2/.attached.json.tmp.*" >/dev/null; then
  fail 'interrupted state publication retained a temporary file'
fi
pass

# A resource-bearing first apply records complete attachment and JSON origins
# before any object write. Retrying from that intent state converges and never
# replaces the origins.
reset_lean_home structured-ordering
write_fixture_json
printf 'native\n' > "$HOME/.bashrc"
cp "$HOME/.config/lean/app.json" "$TEST_ROOT/structured.original"
register_structured
lean_preflight_area apply
lean_write_state_atomic
structured_state="$HOME/.local/state/dotfiles/v2/structured.json"
jq -e '
  .version == 2 and (.attachments | keys) == [".bashrc"] and
  (.resources | keys) == [".config/lean/app.json"] and
  .resources[".config/lean/app.json"].fields["/idle/screensaver"].original == 150 and
  .resources[".config/lean/app.json"].fields["/idle/lock"].original == 300
' "$structured_state" >/dev/null || fail 'complete version-2 origins were not persisted before writes'
assert_same "$HOME/.config/lean/app.json" "$TEST_ROOT/structured.original"
[[ ! -e "$HOME/.one" && "$(< "$HOME/.bashrc")" == native ]] || fail 'intent-state publication changed a managed object'
state_identity="$(stat -c '%d:%i' "$structured_state")"
apply_structured
[[ "$(jq -r '.idle.screensaver, .idle.lock' "$HOME/.config/lean/app.json" | tr '\n' ' ')" == '600 900 ' ]] ||
  fail 'structured apply did not install managed values'
if compgen -G "$HOME/.config/lean/.app.json.tmp.*" >/dev/null; then fail 'successful JSON apply retained a temporary file'; fi
[[ "$(stat -c '%d:%i' "$structured_state")" == "$state_identity" ]] || fail 'repeated apply replaced recorded origins'
apply_structured
[[ "$(stat -c '%d:%i' "$structured_state")" == "$state_identity" ]] || fail 'idempotent apply rewrote version-2 state'
pass

# JSON replacement is semantic and preserves unrelated values and mode. Check
# ignores formatting/key order, while apply and removal reject any third value.
[[ "$(stat -c %a -- "$HOME/.config/lean/app.json")" == 644 ]] || fail 'unexpected fixture mode'
chmod 0640 "$HOME/.config/lean/app.json"
jq '.unrelated.added = [3,2,1]' "$HOME/.config/lean/app.json" > "$HOME/.config/lean/reformat.json"
mv -fT "$HOME/.config/lean/reformat.json" "$HOME/.config/lean/app.json"
chmod 0640 "$HOME/.config/lean/app.json"
check_structured
[[ "$(stat -c %a -- "$HOME/.config/lean/app.json")" == 640 ]] || fail 'semantic check changed mode'
[[ "$(jq -c '.bar,.unrelated' "$HOME/.config/lean/app.json")" == '{"widgets":["clock","tailscale"]}'$'\n''{"nested":true,"added":[3,2,1]}' ]] ||
  fail 'unrelated JSON values were not preserved semantically'
jq '.idle.lock = 901' "$HOME/.config/lean/app.json" > "$HOME/.config/lean/conflict.json"
mv -fT "$HOME/.config/lean/conflict.json" "$HOME/.config/lean/app.json"
chmod 0640 "$HOME/.config/lean/app.json"
expect_direct_failure 'managed JSON fields conflict' apply_structured
expect_direct_failure 'managed JSON fields conflict' remove_structured
[[ "$(jq -r .idle.lock "$HOME/.config/lean/app.json")" == 901 ]] || fail 'JSON conflict was overwritten'
pass

# Removal restores only the recorded vector, preserves unrelated changes, and
# accepts an already-restored vector when retrying after a later interruption.
jq '.idle.lock = 900 | .unrelated.during_ownership = "preserve"' "$HOME/.config/lean/app.json" > "$HOME/.config/lean/repaired.json"
mv -fT "$HOME/.config/lean/repaired.json" "$HOME/.config/lean/app.json"
chmod 0640 "$HOME/.config/lean/app.json"
register_structured
lean_preflight_area remove
lean_replace_json_resource 0 original
[[ -f "$structured_state" && -L "$HOME/.one" && "$(jq -r '.idle.screensaver, .idle.lock' "$HOME/.config/lean/app.json" | tr '\n' ' ')" == '150 300 ' ]] ||
  fail 'interrupted removal did not retain state and later owned objects'
remove_structured
[[ ! -e "$structured_state" && ! -e "$HOME/.one" ]] || fail 'completed removal did not delete state last'
[[ "$(jq -r .unrelated.during_ownership "$HOME/.config/lean/app.json")" == preserve && "$(stat -c %a -- "$HOME/.config/lean/app.json")" == 640 ]] ||
  fail 'removal changed unrelated JSON or mode'
assert_contains "$(< "$HOME/.bashrc")" native
pass

# Existing attachment-only version-1 records remain byte/inode stable, and
# valid version-1 and version-2 records coexist only for one profile.
reset_lean_home state-versions
printf 'native\n' > "$HOME/.bashrc"
apply_attachment
v1_state="$HOME/.local/state/dotfiles/v2/attached.json"
v1_identity="$(stat -c '%d:%i' "$v1_state")"
apply_attachment
[[ "$(jq -r .version "$v1_state")" == 1 && "$(stat -c '%d:%i' "$v1_state")" == "$v1_identity" ]] ||
  fail 'version-1 state was migrated or rewritten'
write_fixture_json
printf 'native\n' > "$HOME/.bashrc.structured"
register_json_only
lean_apply_area
lean_begin_area mixed omarchy packages
[[ "$(jq -r .version "$v1_state")" == 1 && "$(jq -r .version "$HOME/.local/state/dotfiles/v2/json-only.json")" == 2 ]] ||
  fail 'mixed valid state versions were not accepted'
cp "$HOME/.local/state/dotfiles/v2/json-only.json" "$TEST_ROOT/v2.valid"
jq '.profile = "ubuntu"' "$TEST_ROOT/v2.valid" > "$HOME/.local/state/dotfiles/v2/json-only.json"
expect_direct_failure "existing v2 state uses profile 'ubuntu'" lean_begin_area mixed omarchy packages
cp "$TEST_ROOT/v2.valid" "$HOME/.local/state/dotfiles/v2/json-only.json"
pass

# Version-2 state is strict about its version, keys, field scalar types, pointer
# syntax, and required resource set.
for mutation in \
  '.version = 3' \
  '.extra = true' \
  'del(.resources)' \
  '.resources[".config/lean/app.json"].fields["/idle/lock"].original = "300"' \
  '.resources[".config/lean/app.json"].fields["idle/lock"] = .resources[".config/lean/app.json"].fields["/idle/lock"] | del(.resources[".config/lean/app.json"].fields["/idle/lock"])'; do
  jq "$mutation" "$TEST_ROOT/v2.valid" > "$HOME/.local/state/dotfiles/v2/json-only.json"
  expect_direct_failure 'malformed or unknown lean deployment state' lean_validate_state_file "$HOME/.local/state/dotfiles/v2/json-only.json"
done
cp "$TEST_ROOT/v2.valid" "$HOME/.local/state/dotfiles/v2/json-only.json"
pass

# Malformed JSON, caller-rejected schema, wrong registered scalar type, and a
# symlink are all refused before state publication.
for fixture in malformed schema type; do
  reset_lean_home "invalid-json-$fixture"
  mkdir -p "$HOME/.config/lean"
  case "$fixture" in
    malformed) printf '{broken\n' > "$HOME/.config/lean/app.json" ;;
    schema) printf '{"schema":2,"idle":{"screensaver":150,"lock":300}}\n' > "$HOME/.config/lean/app.json" ;;
    type) printf '{"schema":1,"idle":{"screensaver":"150","lock":300}}\n' > "$HOME/.config/lean/app.json" ;;
  esac
  expect_direct_failure 'JSON resource' apply_json_only
  [[ ! -e "$HOME/.local/state/dotfiles/v2/json-only.json" ]] || fail 'invalid JSON published ownership state'
done
reset_lean_home invalid-json-symlink
mkdir -p "$HOME/.config/lean"
printf '{"schema":1,"idle":{"screensaver":150,"lock":300}}\n' > "$HOME/target.json"
ln -s "$HOME/target.json" "$HOME/.config/lean/app.json"
expect_direct_failure 'not an EUID-owned regular file' apply_json_only
[[ ! -e "$HOME/.local/state/dotfiles/v2/json-only.json" ]] || fail 'symlink JSON published ownership state'
reset_lean_home invalid-json-parent
mkdir -p "$HOME/real-lean" "$HOME/.config"
printf '{"schema":1,"idle":{"screensaver":150,"lock":300}}\n' > "$HOME/real-lean/app.json"
ln -s "$HOME/real-lean" "$HOME/.config/lean"
expect_direct_failure 'symlinked, non-directory, or escaping parent' apply_json_only
reset_lean_home invalid-json-owner
write_fixture_json
apply_with_unsafe_owner() {
  stat() {
    if [[ "$1" == -c && "$2" == %u && "${*: -1}" == "$HOME/.config/lean/app.json" ]]; then
      printf '%s\n' "$((EUID + 1))"
    else
      command stat "$@"
    fi
  }
  apply_json_only
}
expect_direct_failure 'not an EUID-owned regular file' apply_with_unsafe_owner
[[ ! -e "$HOME/.local/state/dotfiles/v2/json-only.json" ]] || fail 'unsafe-owner JSON published ownership state'
pass

# A deterministic pause before rename permits a concurrent source replacement;
# both identity/hash protection and identity-safe temp cleanup must refuse it.
reset_lean_home concurrent-json
write_fixture_json
hold="$TEST_ROOT/json-hold"
mkdir "$hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$DOTFILES_DIR" PATH="$PATH" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=lean-before-json-rename DOTFILES_TEST_HOLD_DIR="$hold" SCRIPT_NAME=lean-json-child \
  bash -c '
    set -Eeuo pipefail
    source "'$REPO_DIR'/lib/common.sh"
    source "'$REPO_DIR'/lib/lean_engine.sh"
    validate_fixture_json() { jq -e '\''.schema == 1 and (.idle.screensaver|type=="number") and (.idle.lock|type=="number")'\'' "$1" >/dev/null; }
    lean_begin_area json-only omarchy packages
    lean_add_json_scalar_fields fixture-idle-v1 .config/lean/app.json validate_fixture_json /idle/screensaver integer 600 /idle/lock integer 900
    lean_apply_area
  ' > "$TEST_ROOT/json-child.log" 2>&1 &
json_child=$!
wait_for_file "$hold/lean-before-json-rename.ready"
json_temps=("$HOME"/.config/lean/.app.json.tmp.*)
[[ ${#json_temps[@]} -eq 1 && -f "${json_temps[0]}" && ! -L "${json_temps[0]}" &&
  "$(stat -c %u -- "${json_temps[0]}")" == "$EUID" && "$(stat -c %a -- "${json_temps[0]}")" == "$(stat -c %a -- "$HOME/.config/lean/app.json")" ]] ||
  fail 'JSON replacement temp was not a same-directory EUID-owned regular file with preserved mode'
jq '.unrelated.concurrent = true' "$HOME/.config/lean/app.json" > "$HOME/.config/lean/concurrent.json"
mv -fT "$HOME/.config/lean/concurrent.json" "$HOME/.config/lean/app.json"
: > "$hold/lean-before-json-rename.release"
if wait "$json_child"; then fail 'concurrent JSON replacement unexpectedly succeeded'; fi
assert_contains "$(< "$TEST_ROOT/json-child.log")" 'changed concurrently; refusing overwrite'
[[ "$(jq -r .unrelated.concurrent "$HOME/.config/lean/app.json")" == true && "$(jq -r .idle.lock "$HOME/.config/lean/app.json")" == 300 ]] ||
  fail 'concurrent JSON source was overwritten'
if compgen -G "$HOME/.config/lean/.app.json.tmp.*" >/dev/null; then fail 'JSON temporary file remained after concurrent refusal'; fi
pass

# A replaced JSON temporary object is never published or deleted by cleanup.
reset_lean_home replaced-json-temp
write_fixture_json
hold="$TEST_ROOT/replaced-json-hold"
mkdir "$hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$DOTFILES_DIR" PATH="$PATH" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=lean-before-json-rename DOTFILES_TEST_HOLD_DIR="$hold" SCRIPT_NAME=lean-json-temp-child \
  bash -c '
    set -Eeuo pipefail
    source "'$REPO_DIR'/lib/common.sh"
    source "'$REPO_DIR'/lib/lean_engine.sh"
    validate_fixture_json() { jq -e '\''.schema == 1 and (.idle.screensaver|type=="number") and (.idle.lock|type=="number")'\'' "$1" >/dev/null; }
    lean_begin_area json-only omarchy packages
    lean_add_json_scalar_fields fixture-idle-v1 .config/lean/app.json validate_fixture_json /idle/screensaver integer 600 /idle/lock integer 900
    lean_apply_area
  ' > "$TEST_ROOT/replaced-json-child.log" 2>&1 &
json_child=$!
wait_for_file "$hold/lean-before-json-rename.ready"
json_temps=("$HOME"/.config/lean/.app.json.tmp.*)
[[ ${#json_temps[@]} -eq 1 ]] || fail 'expected one held JSON temporary file'
rm "${json_temps[0]}"
printf '{"replacement":true}\n' > "${json_temps[0]}"
: > "$hold/lean-before-json-rename.release"
if wait "$json_child"; then fail 'replaced JSON temporary file was published'; fi
assert_contains "$(< "$TEST_ROOT/replaced-json-child.log")" 'temporary file changed before publication'
[[ "$(jq -r .idle.lock "$HOME/.config/lean/app.json")" == 300 && "$(jq -r .replacement "${json_temps[0]}")" == true ]] ||
  fail 'temporary replacement was published or deleted'
rm "${json_temps[0]}"
pass

# Shared/exclusive HOME descriptor locks cooperate without creating lock files.
reset_lean_home lock
lock_ready="$TEST_ROOT/lock.ready"
HOME="$HOME" SCRIPT_NAME=lean-lock-child bash -c '
  set -Eeuo pipefail
  source "'$REPO_DIR'/lib/common.sh"
  source "'$REPO_DIR'/lib/lean_engine.sh"
  lean_acquire_lock apply
  : > "'$lock_ready'"
  sleep 2
  ' &
lock_pid=$!
wait_for_file "$lock_ready"
expect_direct_failure 'another deployment holds the HOME lock' lean_acquire_lock apply
expect_direct_failure 'another mutating deployment holds the HOME lock' lean_acquire_lock check
wait "$lock_pid"
lean_acquire_lock check
exec {LEAN_HOME_LOCK_FD}>&-
pass

# A persisted attachment owner refuses another profile before package mutation.
reset_lean_home profile
apply_attachment omarchy
expect_direct_failure "existing v2 state uses profile 'omarchy'" apply_attachment ubuntu
[[ -L "$HOME/.one" && -f "$HOME/.bashrc" ]] || fail 'profile mismatch changed the existing deployment'
pass

# Any old namespace refuses with actionable manual cleanup guidance.
reset_lean_home old-state
mkdir -p "$HOME/.local/state/dotfiles/v1"
printf '{}\n' > "$HOME/.local/state/dotfiles/v1/fixture.json"
expect_direct_failure 'use the legacy checkout to remove it, or clean it up manually' apply_packages
[[ ! -e "$HOME/.one" && ! -e "$HOME/.local/state/dotfiles/v2" ]] || fail 'old-state refusal mutated HOME'
pass

# Profile parsing preserves ordered qualified closures, validation-only entries,
# and strict malformed/missing-package refusal.
SELECTED_PROFILE=ubuntu
AREA_STATUS=([fixture]=ready [native-check]=ready)
printf 'fixture common/one,common/two\nnative-check validation-only\n' > "$DOTFILES_DIR/profiles/ubuntu.conf"
load_profile_closure fixture
[[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'common/one common/two' ]] ||
  fail 'ordered package closure was not parsed'
load_profile_closure native-check
[[ "$PROFILE_ENTRY_KIND" == validation-only && ${#PACKAGES[@]} -eq 0 ]] ||
  fail 'validation-only closure was not parsed'
for record in \
  'malformed profile entry|native-check validation-only common/one' \
  'malformed profile entry|native-check common/one,' \
  'missing package root|native-check common/missing' \
  'profile has no native-check closure|fixture common/one'; do
  expected="${record%%|*}"; content="${record#*|}"
  printf '%s\n' "$content" > "$DOTFILES_DIR/profiles/ubuntu.conf"
  expect_direct_failure "$expected" load_profile_closure native-check
done
pass

# Validation-only entries validate lifecycle wiring without package or state
# ownership. All verbs remain state-free.
reset_lean_home validation-only
lean_begin_area native-check omarchy validation-only
lean_apply_area
lean_check_area
lean_remove_area
[[ ! -e "$HOME/.local/state/dotfiles" ]] || fail 'validation-only entry wrote deployment state'
pass

if command -v /usr/bin/stow >/dev/null 2>&1; then
  printf 'SKIP: real GNU Stow integration is intentionally separate from fake-Stow unit coverage\n'
else
  printf 'SKIP: real GNU Stow unavailable; fake-Stow unit coverage verified the command contract\n'
fi
printf 'PASS: %s focused lean engine groups\n' "$TEST_COUNT"
