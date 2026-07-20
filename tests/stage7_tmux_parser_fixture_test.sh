#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly FIXTURES="$REPO_DIR/scripts/tmux-parser-fixtures"
readonly TEST_ROOT="$(mktemp -d)"
TEST_OUTPUT=""

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT
fail() { printf 'FAIL: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2; exit 1; }

[[ -x "$FIXTURES" ]] || fail 'tmux parser fixture operation is not executable'
bash -n "$FIXTURES" || fail 'tmux parser fixture operation has invalid Bash syntax'

mkdir "$TEST_ROOT/cache" "$TEST_ROOT/deny-bin"
chmod 0700 "$TEST_ROOT/cache"
for command_name in curl wget apt apt-get dpkg; do
  printf '#!/usr/bin/env bash\nprintf attempted >> %q\nexit 97\n' "$TEST_ROOT/network-attempted" \
    > "$TEST_ROOT/deny-bin/$command_name"
  chmod 0755 "$TEST_ROOT/deny-bin/$command_name"
done
PATH="$TEST_ROOT/deny-bin:/usr/bin:/bin" "$FIXTURES" validate-lock >/dev/null || \
  fail 'offline tmux parser fixture lock validation failed'
[[ ! -e "$TEST_ROOT/network-attempted" ]] || fail 'fixture lock validation invoked a network or package-install command'

set +e
TEST_OUTPUT="$(PATH="$TEST_ROOT/deny-bin:/usr/bin:/bin" "$FIXTURES" verify --root "$TEST_ROOT/cache" 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'offline fixture verification accepted a missing managed root'
[[ "$TEST_OUTPUT" == *"prepare it with: $FIXTURES sync --root $TEST_ROOT/cache"* ]] || \
  fail 'missing fixture verification did not print the precise preparation command'
[[ ! -e "$TEST_ROOT/network-attempted" ]] || fail 'offline fixture verification invoked a network or package-install command'

# Cache roots and every managed object chain are EUID-owned real paths. Writable
# roots, symlinked path components, and nested generation symlinks refuse.
unsafe="$TEST_ROOT/unsafe-cache"
mkdir "$unsafe"; chmod 0777 "$unsafe"
set +e
TEST_OUTPUT="$("$FIXTURES" verify --root "$unsafe" 2>&1)"; status=$?
set -e
[[ "$status" != 0 && ( "$TEST_OUTPUT" == *'must not be group- or world-writable'* || \
  "$TEST_OUTPUT" == *'unsafe writable path component'* ) ]] || \
  fail 'fixture verification accepted an unsafe writable cache root'
mkdir "$TEST_ROOT/real-parent"; ln -s "$TEST_ROOT/real-parent" "$TEST_ROOT/link-parent"
set +e
TEST_OUTPUT="$("$FIXTURES" verify --root "$TEST_ROOT/link-parent" 2>&1)"; status=$?
set -e
[[ "$status" != 0 && ( "$TEST_OUTPUT" == *'symlinked path component'* || \
  "$TEST_OUTPUT" == *'existing, non-symlink directory'* ) ]] || \
  fail 'fixture verification accepted a symlinked cache-root component'

nested="$TEST_ROOT/nested-cache"; mkdir "$nested"
generation="$nested/.tmux-parser-fixtures-generation.unsafe"; mkdir -p "$generation/ubuntu-jammy-tmux-3-2a-amd64/usr/bin"
ln -s /usr/bin/tmux "$generation/ubuntu-jammy-tmux-3-2a-amd64/usr/bin/tmux"
ln -s "${generation##*/}" "$nested/tmux-parser-fixtures-v1"
set +e
TEST_OUTPUT="$("$FIXTURES" verify --root "$nested" 2>&1)"; status=$?
set -e
[[ "$status" != 0 && "$TEST_OUTPUT" == *'nested symlinks'* ]] || \
  fail 'fixture verification accepted a nested managed symlink'

# Shared verification locks coexist, while an exclusive sync waits for readers.
shared_a="$TEST_ROOT/shared-a"; shared_b="$TEST_ROOT/shared-b"; mkdir "$shared_a" "$shared_b"
set +e
DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-after-shared-lock DOTFILES_TEST_HOLD_DIR="$shared_a" \
  "$FIXTURES" verify --root "$TEST_ROOT/cache" > "$TEST_ROOT/shared-a.out" 2>&1 &
pid_a=$!
DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-after-shared-lock DOTFILES_TEST_HOLD_DIR="$shared_b" \
  "$FIXTURES" verify --root "$TEST_ROOT/cache" > "$TEST_ROOT/shared-b.out" 2>&1 &
pid_b=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ -e "$shared_a/fixture-after-shared-lock.ready" && -e "$shared_b/fixture-after-shared-lock.ready" ]] && break
  sleep 0.01
done
[[ -e "$shared_a/fixture-after-shared-lock.ready" && -e "$shared_b/fixture-after-shared-lock.ready" ]] || \
  fail 'shared fixture verification locks did not coexist'
exclusive="$TEST_ROOT/exclusive"; mkdir "$exclusive"
set +e
DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-after-exclusive-lock DOTFILES_TEST_HOLD_DIR="$exclusive" \
  "$FIXTURES" sync --root "$TEST_ROOT/cache" > "$TEST_ROOT/exclusive.out" 2>&1 &
pid_exclusive=$!
set -e
sleep 0.1
[[ ! -e "$exclusive/fixture-after-exclusive-lock.ready" ]] || fail 'exclusive fixture sync bypassed active shared locks'
: > "$shared_a/fixture-after-shared-lock.release"; : > "$shared_b/fixture-after-shared-lock.release"
wait "$pid_a" || true; wait "$pid_b" || true
for ((attempt=0; attempt<500; attempt++)); do [[ -e "$exclusive/fixture-after-exclusive-lock.ready" ]] && break; sleep 0.01; done
[[ -e "$exclusive/fixture-after-exclusive-lock.ready" ]] || fail 'exclusive fixture sync did not acquire the released cache-root lock'
kill -TERM "$pid_exclusive"
wait "$pid_exclusive" || true

# Publication adversaries use an already prepared real cache and never fetch.
# The aggregate suite remains offline when no explicit cache is supplied.
REAL_CACHE="${TMUX_PARSER_FIXTURE_ROOT:-}"
if [[ -n "$REAL_CACHE" ]]; then
  "$FIXTURES" verify --root "$REAL_CACHE" >/dev/null || fail 'selected publication-test fixture cache is invalid'
  publication="$TEST_ROOT/publication-cache"; mkdir "$publication"; cp -a "$REAL_CACHE/archives" "$publication/"
  "$FIXTURES" sync --root "$publication" >/dev/null || fail 'publication test could not seed its managed generation'
  old_target="$(readlink "$publication/tmux-parser-fixtures-v1")"
  set +e
  TEST_OUTPUT="$(DOTFILES_TESTING=1 DOTFILES_TEST_FAIL_AT=fixture-after-publication \
    "$FIXTURES" sync --root "$publication" 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 ]] || fail 'post-publication interruption seam unexpectedly succeeded'
  "$FIXTURES" verify --root "$publication" >/dev/null || fail 'interruption deleted the newly active generation'
  new_target="$(readlink "$publication/tmux-parser-fixtures-v1")"
  [[ "$new_target" != "$old_target" && -d "$publication/$old_target" ]] || \
    fail 'publication immediately deleted the previous reader generation'

  cas="$TEST_ROOT/cas-cache"; mkdir "$cas"; cp -a "$REAL_CACHE/archives" "$cas/"
  "$FIXTURES" sync --root "$cas" >/dev/null
  active="$(readlink "$cas/tmux-parser-fixtures-v1")"
  cp -a "$cas/$active" "$cas/.tmux-parser-fixtures-generation.concurrent"
  hold="$TEST_ROOT/cas-hold"; mkdir "$hold"
  set +e
  ( DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-before-publish-cas DOTFILES_TEST_HOLD_DIR="$hold" \
      "$FIXTURES" sync --root "$cas" > "$TEST_ROOT/cas.out" 2>&1; printf '%s' "$?" > "$TEST_ROOT/cas.rc" ) &
  cas_pid=$!
  set -e
  for ((attempt=0; attempt<500; attempt++)); do [[ -e "$hold/fixture-before-publish-cas.ready" ]] && break; sleep 0.01; done
  [[ -e "$hold/fixture-before-publish-cas.ready" ]] || fail 'fixture CAS race did not reach publication hold'
  ln -s .tmux-parser-fixtures-generation.concurrent "$cas/concurrent-link"
  mv -fT "$cas/concurrent-link" "$cas/tmux-parser-fixtures-v1"
  : > "$hold/fixture-before-publish-cas.release"
  wait "$cas_pid" || true
  [[ "$(< "$TEST_ROOT/cas.rc")" != 0 && "$(readlink "$cas/tmux-parser-fixtures-v1")" == .tmux-parser-fixtures-generation.concurrent ]] || \
    fail 'fixture publication CAS overwrote a concurrent managed-link update'
  [[ "$(< "$TEST_ROOT/cas.out")" == *'changed since preflight'* ]] || fail 'fixture CAS mismatch was not reported'

  wrapper34="$TEST_ROOT/tmux-3.4-wrapper"
  printf '#!/usr/bin/env bash\nprintf "tmux 3.4\\n"\n' > "$wrapper34"; chmod 0755 "$wrapper34"
  set +e
  TEST_OUTPUT="$("$REPO_DIR/tests/stage7_tmux_parser_compatibility_test.sh" --fixture-root "$REAL_CACHE" \
    --tmux-3.4 "$wrapper34" --tmux-3.7b-root "$HOME/.local/share/dotfiles/provisioning/tools/tmux/3.7b" 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 && "$TEST_OUTPUT" == *'direct /usr/bin/tmux executable'* ]] || \
    fail 'real-parser identity gate accepted a tmux 3.4 version wrapper'
  wrapper37="$TEST_ROOT/tmux-3.7b-wrapper"; mkdir "$wrapper37"
  printf '#!/usr/bin/env bash\nprintf "tmux 3.7b\\n"\n' > "$wrapper37/tmux"; chmod 0755 "$wrapper37/tmux"
  set +e
  TEST_OUTPUT="$("$REPO_DIR/tests/stage7_tmux_parser_compatibility_test.sh" --fixture-root "$REAL_CACHE" \
    --tmux-3.7b-root "$wrapper37" 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 && "$TEST_OUTPUT" == *'mode, size, or SHA-256 differs'* ]] || \
    fail 'real-parser identity gate accepted a tmux 3.7b version wrapper'
fi

jq -e '
  .schema_version == 1 and .managed_root == "tmux-parser-fixtures-v1" and
  .extractor == ["dpkg-deb", "--extract"] and (.fixtures | length == 1)
' "$REPO_DIR/manifests/tmux-parser-fixtures.lock.json" >/dev/null || \
  fail 'tmux parser fixture lock lost its static contract'

if grep -Eq 'tmux-parser-fixtures[[:space:]]+sync' \
  "$REPO_DIR/bootstrap.sh" "$REPO_DIR"/lib/*.sh "$REPO_DIR"/lib/areas/*.sh; then
  fail 'bootstrap or library code can invoke tmux parser fixture sync'
fi

printf 'PASS: offline tmux parser fixture lock and operation checks\n'
