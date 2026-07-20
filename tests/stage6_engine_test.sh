#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""

cleanup_test() {
  rm -rf -- "$TEST_ROOT"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ -z "$TEST_OUTPUT" ]] || printf '%s\n' "$TEST_OUTPUT" >&2
  exit 1
}

pass() {
  ((TEST_COUNT += 1))
}

assert_same() {
  cmp -s -- "$1" "$2" || fail "files differ: $1 $2"
}

expect_failure() {
  local expected="$1"
  shift
  if TEST_OUTPUT="$("$@" 2>&1)"; then
    fail 'command unexpectedly succeeded'
  fi
  [[ "$TEST_OUTPUT" == *"$expected"* ]] || fail "expected output to contain: $expected"
}

SCRIPT_NAME=stage6-engine-test
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/engine.sh"
trap - EXIT INT TERM
trap cleanup_test EXIT

DOTFILES_DIR="$REPO_DIR"
CHECKOUT_ROOT="$REPO_DIR"
AREA_ORDER=(git bash tmux nvim zsh)
readonly ATTACHMENT_BEGIN='# >>> dotfiles managed stage6 fixture >>>'
readonly ATTACHMENT_END='# <<< dotfiles managed stage6 fixture <<<'
readonly ATTACHMENT_TOKEN='dotfiles managed stage6 fixture'
readonly ATTACHMENT_BLOCK="$ATTACHMENT_BEGIN
source \"\$HOME/.config/dotfiles/bash/rc.bash\"
$ATTACHMENT_END"

reset_home() {
  local name="$1"
  HOME="$TEST_ROOT/home-$name"
  mkdir "$HOME"
  TARGET_ROOT="$(cd -- "$HOME" && pwd -P)"
  AREA=test
  AREA_STATE="$HOME/.local/state/dotfiles/v1/test.json"
  AREA_JOURNAL_PATHS=()
  TARGET_PATHS=()
  TARGET_SOURCES=()
  TARGET_LEXICAL=()
  MANAGED_DIRS=()
  OLD_STATE=false
  TX_PATHS=()
  TX_EXISTED=()
  TX_SNAPSHOTS=()
  TX_INITIAL_IDENTITIES=()
  TX_EXPECTED_IDENTITIES=()
  TX_MUTATED=()
  TX_CREATED_DIRS=()
  TX_RECOVERY_PATHS=()
  TX_QUARANTINE_PATHS=()
  TEMP_PATHS=()
  TEMP_OBJECT_IDENTITIES=()
  TEMP_RECURSIVE=()
  QUARANTINE_IDENTITIES=()
  TRANSACTION_ACTIVE=false
  TRANSACTION_ROLLING_BACK=false
  ROLLBACK_FAILED=false
  TRANSACTION_RECOVERY_REQUIRED=false
  JOURNAL_DIR=""
}

# Prepend preserves an existing no-final-newline file, mode, and exact bytes.
reset_home prepend
printf 'legacy without newline' > "$HOME/.bashrc"
chmod 0640 "$HOME/.bashrc"
cp -a "$HOME/.bashrc" "$TEST_ROOT/prepend.original"
guarded_attachment_preflight .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend new
[[ "$GUARDED_ATTACHMENT_ACTION" == insert && "$GUARDED_ATTACHMENT_ORIGIN" == existing-no-final-newline ]] || \
  fail 'prepend preflight did not classify the existing file'
install_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend 0644 new
attached_hash="$(sha256_file "$HOME/.bashrc")"
install_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend 0644 new
[[ "$(sha256_file "$HOME/.bashrc")" == "$attached_hash" ]] || fail 'exact reapply changed attachment bytes'
remove_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend existing-no-final-newline
assert_same "$HOME/.bashrc" "$TEST_ROOT/prepend.original"
[[ "$(stat -c %a -- "$HOME/.bashrc")" == 640 ]] || fail 'prepend did not preserve mode'
pass

# Append restores no-final-newline bytes and distinguishes empty existing from created.
reset_home append
printf 'native without newline' > "$HOME/.bashrc"
chmod 0600 "$HOME/.bashrc"
cp -a "$HOME/.bashrc" "$TEST_ROOT/append.original"
install_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" append 0644 new
remove_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" append existing-no-final-newline
assert_same "$HOME/.bashrc" "$TEST_ROOT/append.original"
[[ "$(stat -c %a -- "$HOME/.bashrc")" == 600 ]] || fail 'append did not preserve mode'

: > "$HOME/.profile"
install_guarded_attachment .profile "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend 0644 new
remove_guarded_attachment .profile "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend existing-empty
[[ -f "$HOME/.profile" && ! -s "$HOME/.profile" ]] || fail 'empty pre-existing file was deleted'

install_guarded_attachment .bash_profile "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend 0644 new
remove_guarded_attachment .bash_profile "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend created
[[ ! -e "$HOME/.bash_profile" ]] || fail 'bootstrap-created attachment-only file was retained'
pass

# Every ambiguous marker shape and modified block fails closed.
reset_home malformed
malformed_cases=(begin-only end-only duplicate nested reordered modified-block modified-marker)
for case_name in "${malformed_cases[@]}"; do
  case "$case_name" in
    begin-only) printf '%s\n' "$ATTACHMENT_BEGIN" > "$HOME/.bashrc" ;;
    end-only) printf '%s\n' "$ATTACHMENT_END" > "$HOME/.bashrc" ;;
    duplicate) printf '%s\n%s\n%s\n%s\n' "$ATTACHMENT_BLOCK" "$ATTACHMENT_BEGIN" x "$ATTACHMENT_END" > "$HOME/.bashrc" ;;
    nested) printf '%s\n%s\n%s\n%s\n' "$ATTACHMENT_BEGIN" "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_END" > "$HOME/.bashrc" ;;
    reordered) printf '%s\n%s\n' "$ATTACHMENT_END" "$ATTACHMENT_BEGIN" > "$HOME/.bashrc" ;;
    modified-block) printf '%s\nchanged\n%s\n' "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" > "$HOME/.bashrc" ;;
    modified-marker) printf '# >>> %s changed >>>\n' "$ATTACHMENT_TOKEN" > "$HOME/.bashrc" ;;
  esac
  expect_failure 'partial, malformed, nested, duplicate, or modified' guarded_attachment_preflight \
    .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" prepend new
done
pass

# Refresh permits only complete block loss from a safe existing regular file.
reset_home refresh
printf 'native baseline\n' > "$HOME/.bashrc"
install_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" append 0644 refresh
printf 'refreshed native baseline\n' > "$HOME/.bashrc"
install_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" append 0644 refresh
guarded_attachment_preflight .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" append exact
printf 'refreshed native baseline\nsource "$HOME/.config/dotfiles/bash/rc.bash"\n' > "$HOME/.bashrc"
expect_failure 'partial, malformed, nested, duplicate, or modified' guarded_attachment_preflight \
  .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" append refresh
pass

# Symlinks, non-regular files, unsafe parents, and foreign ownership are refused.
reset_home safety
printf 'outside\n' > "$TEST_ROOT/outside"
ln -s "$TEST_ROOT/outside" "$HOME/.bashrc"
expect_failure 'not a regular file' guarded_attachment_preflight .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" \
  "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" prepend new
rm "$HOME/.bashrc"
mkdir "$HOME/.bashrc"
expect_failure 'not a regular file' guarded_attachment_preflight .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" \
  "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" prepend new
rm -rf "$HOME/.bashrc"
mkfifo "$HOME/.bashrc"
expect_failure 'not a regular file' guarded_attachment_preflight .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" \
  "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" prepend new
rm "$HOME/.bashrc"
mkdir "$TEST_ROOT/unsafe-parent"
ln -s "$TEST_ROOT/unsafe-parent" "$HOME/.config"
expect_failure 'symlinked, non-directory, or escaping parent' guarded_attachment_preflight \
  .config/bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" prepend new
rm "$HOME/.config"
printf 'owned\n' > "$HOME/.bashrc"
foreign_owner_preflight() {
  stat() {
    if [[ "$1" == -c && "$2" == %u ]]; then printf '%s\n' "$((EUID + 1))"; else command stat "$@"; fi
  }
  guarded_attachment_preflight .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
    "$ATTACHMENT_BLOCK" prepend new
}
expect_failure 'unsafe owner' foreign_owner_preflight
pass

# NUL-bearing startup files fail closed before attachment mutation.
reset_home nul
printf 'before\0after' > "$HOME/.bashrc"
cp "$HOME/.bashrc" "$TEST_ROOT/nul.original"
expect_failure 'contains NUL bytes and cannot be edited safely' guarded_attachment_preflight \
  .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" "$ATTACHMENT_BLOCK" prepend new
assert_same "$HOME/.bashrc" "$TEST_ROOT/nul.original"
pass

# State v1 rejects duplicate or unsafe attachment identity and path records.
reset_home state
state="$HOME/bash.json"
jq -cn --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" --arg hash "$(sha256_string "$ATTACHMENT_BLOCK")" '
  {schema_version:1,profile:"generic",area:"bash",checkout_root:$checkout,target_root:$target,
   packages:[],targets:[],managed_directories:[],
   attachments:[{id:"bash-rc-existing-v1",path:".bashrc",content_hash:$hash},
                {id:"bash-rc-existing-v1",path:".profile",content_hash:$hash}],backups:[]}' > "$state"
expect_failure 'malformed or unknown deployment state' validate_state_file "$state"
jq '.attachments[1].id = "bash-login-existing-v1" | .attachments[1].path = ".bashrc"' "$state" > "$state.tmp"
mv "$state.tmp" "$state"
expect_failure 'malformed or unknown deployment state' validate_state_file "$state"
jq '.attachments[1].path = "../escape"' "$state" > "$state.tmp"
mv "$state.tmp" "$state"
expect_failure 'unsafe target path in state' validate_state_file "$state"
foreign_state_owner() {
  stat() {
    if [[ "${*: -1}" == "$state" ]]; then printf '%s\n' "$((EUID + 1))"; else command stat "$@"; fi
  }
  validate_state_file "$state"
}
expect_failure 'state has an unsafe owner' foreign_state_owner
pass

# Ledger IDs and retained backup paths are unique, relative, and parent-safe.
reset_home ledger
AREA=migration-fixture
AREA_STATE="$HOME/.local/state/dotfiles/v1/migration-fixture.json"
begin_transaction
append_migration_ledger zsh-local-alias-v1 "$(sha256_string aliases)" '.local/state/dotfiles/v1/backups/zsh/aliases'
TRANSACTION_ACTIVE=false
ledger="$HOME/.local/state/dotfiles/v1/migrations.json"
validate_migrations_ledger
preflight_migration zsh-local-alias-v1 false 'zsh local alias migration'
[[ "$MIGRATION_STATUS" == completed ]] || fail 'completed migration was not detected'
expect_failure 'retired source reappeared' preflight_migration zsh-local-alias-v1 true 'zsh local alias migration'
cp "$ledger" "$TEST_ROOT/ledger.good"
jq '.migrations += [.migrations[0]]' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
expect_failure 'malformed or unknown migration ledger' validate_migrations_ledger
cp "$TEST_ROOT/ledger.good" "$ledger"
jq '.migrations[0].backups = ["../escape"]' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
expect_failure 'unsafe retained migration backup path' validate_migrations_ledger
cp "$TEST_ROOT/ledger.good" "$ledger"
mkdir -p "$TEST_ROOT/ledger-external"
ln -s "$TEST_ROOT/ledger-external" "$HOME/.local/state/dotfiles/v1/backups"
expect_failure 'symlinked, non-directory, or escaping parent' validate_migrations_ledger
pass

# Attachment and ledger mutations both participate in one transaction rollback.
reset_home rollback
printf 'rollback bytes without newline' > "$HOME/.bashrc"
chmod 0640 "$HOME/.bashrc"
cp -a "$HOME/.bashrc" "$TEST_ROOT/rollback.original"
AREA=rollback-fixture
AREA_STATE="$HOME/.local/state/dotfiles/v1/rollback-fixture.json"
AREA_JOURNAL_PATHS=("$HOME/.bashrc")
begin_transaction
install_guarded_attachment .bashrc "$ATTACHMENT_BEGIN" "$ATTACHMENT_END" "$ATTACHMENT_TOKEN" \
  "$ATTACHMENT_BLOCK" prepend 0644 new
append_migration_ledger zsh-vite-retirement-v1 "$(sha256_string vite)"
rollback_transaction
assert_same "$HOME/.bashrc" "$TEST_ROOT/rollback.original"
[[ "$(stat -c %a -- "$HOME/.bashrc")" == 640 ]] || fail 'rollback changed attachment mode'
[[ ! -e "$HOME/.local/state/dotfiles/v1/migrations.json" ]] || fail 'rollback retained an uncommitted ledger'
pass

# Reviewed legacy replacements are manifest-exact, simulated absent, and removed only in a transaction.
reset_home reviewed
review_repo="$TEST_ROOT/review-repo"
old_repo="$TEST_ROOT/review-old"
mkdir -p "$review_repo/manifests" "$review_repo/packages/common/zsh" "$review_repo/lib/stow-preflight-target" "$old_repo"
: > "$review_repo/lib/stow-preflight-target/.keep"
printf 'new zshrc\n' > "$review_repo/packages/common/zsh/.zshrc"
printf 'old zshrc\n' > "$old_repo/.zshrc"
jq -cn --arg home "$TARGET_ROOT" --arg root "$old_repo" \
  '{schema_version:1,hosts:[{id:"fixture",status:"reviewed",home:$home,checkout_root:$root,platform:"fixture",
    scan_scope:"fixture",records:[[".zshrc",".zshrc","zsh","tracked","replace-stage-6"]],blockers:[]}]}' \
  > "$review_repo/manifests/legacy-links.json"
ln -s "$old_repo/.zshrc" "$HOME/.zshrc"
DOTFILES_DIR="$review_repo"
CHECKOUT_ROOT="$review_repo"
AREA=zsh
PACKAGES=(common/zsh)
scan_packages
OLD_STATE=false
expect_failure 'exact reviewed manifest record' approve_legacy_replacement .zshrc .zshrc zsh unreviewed-action
approve_legacy_replacement .zshrc .zshrc zsh replace-stage-6
preflight_desired_targets
run_stow_preflight
AREA_STATE="$HOME/.local/state/dotfiles/v1/zsh.json"
AREA_JOURNAL_PATHS=()
begin_transaction
remove_approved_legacy_replacements
[[ ! -e "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]] || fail 'approved legacy link was not removed'
rollback_transaction
[[ -L "$HOME/.zshrc" ]] || fail 'approved legacy removal did not roll back'

printf 'redirected\n' > "$TEST_ROOT/redirected-zshrc"
rm "$old_repo/.zshrc"
ln -s "$TEST_ROOT/redirected-zshrc" "$old_repo/.zshrc"
scan_packages
OLD_STATE=false
expect_failure 'exact reviewed manifest record' approve_legacy_replacement .zshrc .zshrc zsh replace-stage-6

rm -f "$HOME/.zshrc"
printf 'current checkout source\n' > "$review_repo/.zshrc"
ln -s "$review_repo/.zshrc" "$HOME/.zshrc"
foreign_current_link_owner() {
  stat() {
    if [[ "${*: -1}" == "$HOME/.zshrc" ]]; then printf '%s\n' "$((EUID + 1))"; else command stat "$@"; fi
  }
  owned_legacy_link "$HOME/.zshrc" .zshrc .zshrc zsh replace-stage-6
}
if foreign_current_link_owner; then fail 'current-checkout legacy link with a foreign owner was accepted'; fi
foreign_current_source_owner() {
  stat() {
    if [[ "${*: -1}" == "$review_repo/.zshrc" ]]; then printf '%s\n' "$((EUID + 1))"; else command stat "$@"; fi
  }
  owned_legacy_link "$HOME/.zshrc" .zshrc .zshrc zsh replace-stage-6
}
if foreign_current_source_owner; then fail 'foreign-owned current-checkout legacy source was accepted'; fi
jq --arg root "$review_repo" '.hosts[0].checkout_root = $root' \
  "$review_repo/manifests/legacy-links.json" > "$review_repo/manifests/legacy-links.json.tmp"
mv "$review_repo/manifests/legacy-links.json.tmp" "$review_repo/manifests/legacy-links.json"
foreign_reviewed_source_owner() {
  stat() {
    if [[ "${*: -1}" == "$review_repo/.zshrc" ]]; then printf '%s\n' "$((EUID + 1))"; else command stat "$@"; fi
  }
  reviewed_legacy_link "$HOME/.zshrc" .zshrc .zshrc zsh replace-stage-6
}
if foreign_reviewed_source_owner; then fail 'foreign-owned reviewed legacy source was accepted'; fi
pass

# A regular file swapped in after guarded preflight is preserved and never overwritten.
reset_home guarded-race
printf 'preflight original\n' > "$HOME/.bashrc"
mkdir "$TEST_ROOT/guarded-race-hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-engine-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=before-guarded-replacement-quarantine \
  DOTFILES_TEST_HOLD_DIR="$TEST_ROOT/guarded-race-hold" FIX_BEGIN="$ATTACHMENT_BEGIN" \
  FIX_END="$ATTACHMENT_END" FIX_TOKEN="$ATTACHMENT_TOKEN" FIX_BLOCK="$ATTACHMENT_BLOCK" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    AREA=guarded-race
    AREA_STATE="$HOME/.local/state/dotfiles/v1/guarded-race.json"
    AREA_JOURNAL_PATHS=("$HOME/.bashrc")
    TARGET_PATHS=()
    MANAGED_DIRS=()
    OLD_STATE=false
    begin_transaction
    install_guarded_attachment .bashrc "$FIX_BEGIN" "$FIX_END" "$FIX_TOKEN" "$FIX_BLOCK" prepend 0644 new
  ' > "$TEST_ROOT/guarded-race.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$TEST_ROOT/guarded-race-hold/before-guarded-replacement-quarantine.ready" ]] && break
  sleep 0.01
done
[[ -e "$TEST_ROOT/guarded-race-hold/before-guarded-replacement-quarantine.ready" ]] || fail 'guarded race did not reach its hold'
mv "$HOME/.bashrc" "$HOME/.bashrc.preflight-object"
printf 'concurrent regular data\n' > "$HOME/.bashrc"
: > "$TEST_ROOT/guarded-race-hold/before-guarded-replacement-quarantine.release"
if wait "$race_pid"; then fail 'guarded replacement race unexpectedly succeeded'; fi
[[ "$(< "$HOME/.bashrc")" == 'concurrent regular data' && \
  "$(< "$HOME/.bashrc.preflight-object")" == 'preflight original' ]] || \
  fail 'guarded replacement race lost a regular file'
pass

# An approved legacy link swapped for another symlink is restored and never discarded.
reset_home legacy-race
legacy_repo="$TEST_ROOT/legacy-race-repo"
legacy_old="$TEST_ROOT/legacy-race-old"
mkdir -p "$legacy_repo/manifests" "$legacy_repo/packages/common/zsh" "$legacy_old"
printf 'new\n' > "$legacy_repo/packages/common/zsh/.zshrc"
printf 'old\n' > "$legacy_old/.zshrc"
printf 'concurrent\n' > "$TEST_ROOT/legacy-race-concurrent"
jq -cn --arg home "$TARGET_ROOT" --arg root "$legacy_old" \
  '{schema_version:1,hosts:[{id:"fixture",status:"reviewed",home:$home,checkout_root:$root,platform:"fixture",
    scan_scope:"fixture",records:[[".zshrc",".zshrc","zsh","tracked","replace-stage-6"]],blockers:[]}]}' \
  > "$legacy_repo/manifests/legacy-links.json"
ln -s "$legacy_old/.zshrc" "$HOME/.zshrc"
mkdir "$TEST_ROOT/legacy-race-hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$legacy_repo" SCRIPT_NAME=stage6-engine-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=before-approved-legacy-quarantine \
  DOTFILES_TEST_HOLD_DIR="$TEST_ROOT/legacy-race-hold" bash -c '
    set -Eeuo pipefail
    source "'$REPO_DIR'/lib/common.sh"
    source "'$REPO_DIR'/lib/engine.sh"
    AREA=zsh
    AREA_STATE="$HOME/.local/state/dotfiles/v1/zsh.json"
    AREA_JOURNAL_PATHS=()
    PACKAGES=(common/zsh)
    scan_packages
    OLD_STATE=false
    approve_legacy_replacement .zshrc .zshrc zsh replace-stage-6
    begin_transaction
    remove_approved_legacy_replacements
  ' > "$TEST_ROOT/legacy-race.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$TEST_ROOT/legacy-race-hold/before-approved-legacy-quarantine.ready" ]] && break
  sleep 0.01
done
[[ -e "$TEST_ROOT/legacy-race-hold/before-approved-legacy-quarantine.ready" ]] || fail 'legacy race did not reach its hold'
mv "$HOME/.zshrc" "$HOME/.zshrc.approved-object"
ln -s "$TEST_ROOT/legacy-race-concurrent" "$HOME/.zshrc"
: > "$TEST_ROOT/legacy-race-hold/before-approved-legacy-quarantine.release"
if wait "$race_pid"; then fail 'legacy symlink race unexpectedly succeeded'; fi
[[ -L "$HOME/.zshrc" && "$(readlink "$HOME/.zshrc")" == "$TEST_ROOT/legacy-race-concurrent" && \
  -L "$HOME/.zshrc.approved-object" ]] || fail 'legacy removal race lost a symlink'
pass

# Rollback never removes an unexpected directory and reserves status 70 for recovery.
reset_home rollback-race
printf 'rollback original\n' > "$HOME/state"
mkdir "$TEST_ROOT/rollback-race-hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-engine-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=before-rollback-path \
  DOTFILES_TEST_HOLD_DIR="$TEST_ROOT/rollback-race-hold" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    AREA=rollback-race
    AREA_STATE="$HOME/state"
    AREA_JOURNAL_PATHS=()
    TARGET_PATHS=()
    MANAGED_DIRS=()
    OLD_STATE=false
    begin_transaction
    write_transaction_string_atomic "managed post-state" "$HOME/state" 0600
    die "injected rollback race"
  ' > "$TEST_ROOT/rollback-race.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$TEST_ROOT/rollback-race-hold/before-rollback-path.ready" ]] && break
  sleep 0.01
done
[[ -e "$TEST_ROOT/rollback-race-hold/before-rollback-path.ready" ]] || fail 'rollback race did not reach its hold'
mv "$HOME/state" "$HOME/state.managed-object"
mkdir "$HOME/state"
printf 'concurrent directory data\n' > "$HOME/state/preserved"
: > "$TEST_ROOT/rollback-race-hold/before-rollback-path.release"
set +e
wait "$race_pid"
status=$?
set -e
[[ "$status" == 70 ]] || fail "rollback collision did not reserve status 70: $status"
[[ -d "$HOME/state" && "$(< "$HOME/state/preserved")" == 'concurrent directory data' && \
  "$(< "$HOME/state.managed-object")" == 'managed post-state' ]] || \
  fail 'rollback race removed an unexpected directory or managed recovery object'
[[ "$(< "$TEST_ROOT/rollback-race.log")" == *'rollback failed; inspect journal'* ]] || \
  fail 'rollback collision did not retain recovery diagnostics'
pass

# A state replacement after transaction start is refused without rollback clobbering it.
reset_home state-cas
printf 'transaction-start state\n' > "$HOME/state"
mkdir "$TEST_ROOT/state-cas-hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-engine-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=before-atomic-rename \
  DOTFILES_TEST_HOLD_DIR="$TEST_ROOT/state-cas-hold" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    AREA=state-cas
    AREA_STATE="$HOME/state"
    AREA_JOURNAL_PATHS=()
    TARGET_PATHS=()
    MANAGED_DIRS=()
    OLD_STATE=false
    begin_transaction
    write_transaction_string_atomic "managed state" "$AREA_STATE" 0600
  ' > "$TEST_ROOT/state-cas.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$TEST_ROOT/state-cas-hold/before-atomic-rename.ready" ]] && break
  sleep 0.01
done
[[ -e "$TEST_ROOT/state-cas-hold/before-atomic-rename.ready" ]] || fail 'state CAS race did not reach its hold'
mv "$HOME/state" "$HOME/state.transaction-start"
printf 'concurrent state replacement\n' > "$HOME/state"
: > "$TEST_ROOT/state-cas-hold/before-atomic-rename.release"
if wait "$race_pid"; then fail 'state CAS race unexpectedly overwrote a concurrent replacement'; fi
[[ "$(< "$HOME/state")" == 'concurrent state replacement' && \
  "$(< "$HOME/state.transaction-start")" == 'transaction-start state' ]] || \
  fail 'state CAS race lost the concurrent or transaction-start object'
[[ "$(< "$TEST_ROOT/state-cas.log")" == *'changed before mutation'* ]] || \
  fail 'state CAS race did not report its pre-state mismatch'
pass

# A valid concurrent ledger append after the exact read is retained and refuses the stale update.
reset_home ledger-cas
ledger="$HOME/.local/state/dotfiles/v1/migrations.json"
mkdir -p "$(dirname -- "$ledger")" "$TEST_ROOT/ledger-cas-hold"
printf '%s\n' '{"schema_version":1,"migrations":[]}' > "$ledger"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-engine-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=after-migration-ledger-read \
  DOTFILES_TEST_HOLD_DIR="$TEST_ROOT/ledger-cas-hold" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    AREA=ledger-cas
    AREA_STATE="$HOME/.local/state/dotfiles/v1/ledger-cas.json"
    AREA_JOURNAL_PATHS=("$HOME/.local/state/dotfiles/v1/migrations.json")
    TARGET_PATHS=()
    MANAGED_DIRS=()
    OLD_STATE=false
    begin_transaction
    append_migration_ledger attempted-v1 "$(sha256_string attempted)"
  ' > "$TEST_ROOT/ledger-cas.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$TEST_ROOT/ledger-cas-hold/after-migration-ledger-read.ready" ]] && break
  sleep 0.01
done
[[ -e "$TEST_ROOT/ledger-cas-hold/after-migration-ledger-read.ready" ]] || fail 'ledger CAS race did not reach its read hold'
concurrent_hash="$(sha256_string concurrent)"
jq --arg hash "$concurrent_hash" \
  '.migrations += [{id:"concurrent-v1",source_fingerprint:$hash,completed_at:"2026-07-18T00:00:00Z",backups:[]}]' \
  "$ledger" > "$ledger.tmp"
mv "$ledger.tmp" "$ledger"
: > "$TEST_ROOT/ledger-cas-hold/after-migration-ledger-read.release"
if wait "$race_pid"; then fail 'ledger CAS race unexpectedly overwrote a concurrent append'; fi
jq -e '(.migrations | length) == 1 and .migrations[0].id == "concurrent-v1"' "$ledger" >/dev/null || \
  fail 'ledger CAS race lost or combined the concurrent append'
[[ "$(< "$TEST_ROOT/ledger-cas.log")" == *'changed before mutation'* ]] || \
  fail 'ledger CAS race did not report its exact-read mismatch'
pass

# Replaced temporary and quarantine pathnames are warned about and never deleted.
reset_home temp-identity
temporary="$(mktemp "$HOME/.tracked-temp.XXXXXX")"
track_temp_path "$temporary"
mv "$temporary" "$temporary.created"
printf 'foreign temporary data\n' > "$temporary"
if discard_tracked_temp_path "$temporary" test-replacement 2> "$TEST_ROOT/temp-replacement.log"; then
  fail 'replaced temporary pathname was deleted'
fi
[[ "$(< "$temporary")" == 'foreign temporary data' && -f "$temporary.created" && \
  "$(< "$TEST_ROOT/temp-replacement.log")" == *'path was replaced; leaving it in place'* ]] || \
  fail 'temporary pathname replacement was not preserved with a warning'

printf 'quarantine original\n' > "$HOME/quarantine-source"
mkdir "$TEST_ROOT/quarantine-identity-hold"
HOME="$HOME" TARGET_ROOT="$TARGET_ROOT" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-engine-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=before-quarantine-discard \
  DOTFILES_TEST_HOLD_DIR="$TEST_ROOT/quarantine-identity-hold" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    AREA=quarantine-identity
    AREA_STATE="$HOME/quarantine-source"
    AREA_JOURNAL_PATHS=()
    TARGET_PATHS=()
    MANAGED_DIRS=()
    OLD_STATE=false
    begin_transaction
    remove_current_regular_path "$AREA_STATE" "quarantine fixture"
  ' > "$TEST_ROOT/quarantine-identity.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$TEST_ROOT/quarantine-identity-hold/before-quarantine-discard.ready" ]] && break
  sleep 0.01
done
[[ -e "$TEST_ROOT/quarantine-identity-hold/before-quarantine-discard.ready" ]] || \
  fail 'quarantine identity race did not reach its discard hold'
quarantine_paths=("$HOME"/.quarantine-source.dotfiles-quarantine.*)
((${#quarantine_paths[@]} == 1)) || fail 'quarantine identity race did not expose exactly one quarantine'
quarantine="${quarantine_paths[0]}"
mv "$quarantine" "$quarantine.created"
printf 'foreign quarantine data\n' > "$quarantine"
: > "$TEST_ROOT/quarantine-identity-hold/before-quarantine-discard.release"
set +e
wait "$race_pid"
status=$?
set -e
[[ "$status" == 70 ]] || fail "quarantine replacement did not reserve recovery status 70: $status"
[[ "$(< "$quarantine")" == 'foreign quarantine data' && \
  "$(< "$quarantine.created")" == 'quarantine original' && \
  "$(< "$HOME/quarantine-source")" == 'quarantine original' ]] || \
  fail 'quarantine pathname replacement lost foreign or original data'
[[ "$(< "$TEST_ROOT/quarantine-identity.log")" == *'quarantine was replaced; leaving it in place'* ]] || \
  fail 'quarantine pathname replacement was not diagnosed'
pass

printf 'PASS: %s Stage 6 engine primitive test groups\n' "$TEST_COUNT"
