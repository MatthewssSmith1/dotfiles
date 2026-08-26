#!/usr/bin/env bash

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly HELPER="$REPO_DIR/packages/ubuntu/bash/.local/share/dotfiles/bin/dotfiles-secret"
readonly PLACEHOLDER='fixture-placeholder-value'

make_fixture() {
  local name="$1"
  FIXTURE="$TEST_ROOT/$name"
  FIXTURE_HOME="$FIXTURE/home"
  FIXTURE_BIN="$FIXTURE/bin"
  BUNDLE_DIRECTORY="$FIXTURE_HOME/.config/dotfiles/local/secrets"
  BUNDLE="$BUNDLE_DIRECTORY/app.env"
  CHILD_MARKER="$FIXTURE/child-ran"
  mkdir -p "$BUNDLE_DIRECTORY" "$FIXTURE_BIN"
  chmod 0700 "$FIXTURE_HOME" "$BUNDLE_DIRECTORY"
  chmod 0755 "$FIXTURE_HOME/.config" "$FIXTURE_HOME/.config/dotfiles" "$FIXTURE_HOME/.config/dotfiles/local"
  cat > "$FIXTURE_BIN/child" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
: > "$CHILD_MARKER"
printf '%s\0' "$@" > "$FIXTURE/args"
env > "$FIXTURE/environment"
exit "${CHILD_STATUS:-0}"
SCRIPT
  chmod 0755 "$FIXTURE_BIN/child"
}

write_bundle() {
  printf '%s' "$1" > "$BUNDLE"
  chmod 0600 "$BUNDLE"
}

run_helper() {
  env -i HOME="$FIXTURE_HOME" PATH="$FIXTURE_BIN:/usr/bin:/bin" FIXTURE="$FIXTURE" \
    CHILD_MARKER="$CHILD_MARKER" CHILD_STATUS="${CHILD_STATUS:-0}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" OVERRIDE="${OVERRIDE:-}" "$HELPER" "$@"
}

expect_failure() {
  local description="$1"
  shift
  rm -f "$CHILD_MARKER"
  if run_helper "$@" > "$FIXTURE/output" 2> "$FIXTURE/errors"; then fail "$description was accepted"; fi
  [[ ! -e "$CHILD_MARKER" ]] || fail "$description ran the child"
  if grep -Fq "$PLACEHOLDER" "$FIXTURE/output" "$FIXTURE/errors"; then fail "$description exposed a bundle value"; fi
}

# Complete bundles are injected only into the child and override only its inherited environment.
make_fixture basic
write_bundle $'ONE=fixture-placeholder-value\nTWO=second-placeholder\nOVERRIDE=bundle-value\n'
OVERRIDE=parent-value run_helper exec-env app -- child 'space value' '*.literal'
[[ "${ONE-unset}" == unset && "${TWO-unset}" == unset && "${OVERRIDE-unset}" == unset ]] || fail 'bundle changed the parent environment'
grep -qxF 'ONE=fixture-placeholder-value' "$FIXTURE/environment" || fail 'first assignment did not reach child'
grep -qxF 'TWO=second-placeholder' "$FIXTURE/environment" || fail 'second assignment did not reach child'
grep -qxF 'OVERRIDE=bundle-value' "$FIXTURE/environment" || fail 'bundle did not override inherited child value'
mapfile -d '' -t arguments < "$FIXTURE/args"
[[ "${arguments[*]}" == 'space value *.literal' ]] || fail 'child arguments changed'
pass

# Assignment names cannot replace launcher metadata or the already-resolved command.
make_fixture collisions
cat > "$FIXTURE_BIN/hijack" <<'SCRIPT'
#!/usr/bin/env bash
printf attempted > "$FIXTURE/hijacked"
SCRIPT
chmod 0755 "$FIXTURE_BIN/hijack"
write_bundle $'command_path=hijack\nASSIGNMENT_NAMES=corrupt\nPUBLICATIONS=corrupt\n'
run_helper exec-env app -- child safe
[[ -e "$CHILD_MARKER" && ! -e "$FIXTURE/hijacked" ]] || fail 'bundle assignment replaced launcher state or command'
grep -qxF 'command_path=hijack' "$FIXTURE/environment" || fail 'colliding assignment did not reach child'
grep -qxF 'ASSIGNMENT_NAMES=corrupt' "$FIXTURE/environment" || fail 'array-name assignment did not reach child'
grep -qxF 'PUBLICATIONS=corrupt' "$FIXTURE/environment" || fail 'publication-name assignment did not reach child'
pass

# Values are literal, including empty values and shell-looking bytes; comments and a missing final LF work.
make_fixture literals
side_effect="$FIXTURE/side-effect"
{
cat <<EOF
# fixture data

EMPTY=
EQUALS=abc=def==
EOF
printf 'SPACES=  leading and trailing  \n'
cat <<EOF
HASH=abc#literal
DOLLAR=\$(touch $side_effect)
BACKTICK=\`touch $side_effect\`
QUOTES='"literal"'
BACKSLASH=C:\fixture\path
EOF
} > "$BUNDLE"
truncate -s -1 "$BUNDLE"
chmod 0600 "$BUNDLE"
run_helper exec-env app -- child
[[ ! -e "$side_effect" ]] || fail 'shell-looking bundle data was executed'
grep -qxF 'EMPTY=' "$FIXTURE/environment" || fail 'empty value changed'
grep -qxF 'EQUALS=abc=def==' "$FIXTURE/environment" || fail 'additional equals changed'
grep -qxF 'SPACES=  leading and trailing  ' "$FIXTURE/environment" || fail 'spaces changed'
grep -qxF 'HASH=abc#literal' "$FIXTURE/environment" || fail 'hash changed'
grep -qxF "DOLLAR=\$(touch $side_effect)" "$FIXTURE/environment" || fail 'dollar expression changed'
grep -qxF "BACKTICK=\`touch $side_effect\`" "$FIXTURE/environment" || fail 'backticks changed'
grep -qxF 'QUOTES='\''"literal"'\''' "$FIXTURE/environment" || fail 'quotes changed'
grep -qxF 'BACKSLASH=C:\fixture\path' "$FIXTURE/environment" || fail 'backslashes changed'
pass

# Validation output and child status are fixed and preserved.
make_fixture interface
write_bundle $'VALUE=fixture-placeholder-value\n'
[[ "$(run_helper check-env app)" == valid ]] || fail 'check-env output changed'
CHILD_STATUS=42 run_helper exec-env app -- child status >/dev/null 2> "$FIXTURE/errors" && fail 'child failure was hidden'
[[ "$?" == 42 ]] || fail 'child status changed'
if grep -Fq "$PLACEHOLDER" "$FIXTURE/errors"; then fail 'diagnostics exposed a bundle value'; fi
HOME="$FIXTURE_HOME" PATH="$FIXTURE_BIN:/usr/bin:/bin" FIXTURE="$FIXTURE" CHILD_MARKER="$CHILD_MARKER" \
  bash -x "$HELPER" check-env app > "$FIXTURE/trace-output" 2> "$FIXTURE/trace-errors"
if grep -Fq "$PLACEHOLDER" "$FIXTURE/trace-output" "$FIXTURE/trace-errors"; then fail 'caller xtrace exposed a bundle value'; fi
pass

# Grammar failures are detected before execution.
for content in \
  'malformed-row' \
  '=missing-name' \
  'BAD-NAME=value' \
  'NAME =value' \
  $'DUP=one\nDUP=two\n' \
  $'# comment only\n\n'; do
  make_fixture malformed
  write_bundle "$content"
  expect_failure 'malformed bundle' exec-env app -- child
done
make_fixture controls
printf 'VALUE=good\rbad\n' > "$BUNDLE"; chmod 0600 "$BUNDLE"
expect_failure 'carriage return' exec-env app -- child
printf 'VALUE=good\tbad\n' > "$BUNDLE"; chmod 0600 "$BUNDLE"
expect_failure 'control byte' exec-env app -- child
printf 'VALUE=good\0bad\n' > "$BUNDLE"; chmod 0600 "$BUNDLE"
expect_failure 'NUL byte' exec-env app -- child
pass

# Assignment count and byte-size limits fail closed.
make_fixture limits
: > "$BUNDLE"
for ((index=0; index<=256; index++)); do printf 'VALUE_%d=x\n' "$index" >> "$BUNDLE"; done
chmod 0600 "$BUNDLE"
expect_failure 'excessive assignment count' exec-env app -- child
python3 -c 'import sys; sys.stdout.write("VALUE=" + "x" * 65531)' > "$BUNDLE"; chmod 0600 "$BUNDLE"
[[ "$(stat -c %s "$BUNDLE")" == 65537 ]] || fail 'oversize fixture is wrong'
expect_failure 'excessive bundle size' exec-env app -- child
: > "$BUNDLE"; chmod 0600 "$BUNDLE"
expect_failure 'empty bundle file' exec-env app -- child
pass

# Logical names cannot become paths.
make_fixture names
write_bundle 'VALUE=fixture-placeholder-value'
for name in '' . .. .hidden '../app' 'app/name' '/absolute' 'two words' "$(printf 'a%.0s' {1..129})"; do
  expect_failure 'invalid bundle name' exec-env "$name" -- child
done
pass

# Missing, broad, linked, and wrong-type bundle objects fail closed.
make_fixture objects
write_bundle 'VALUE=fixture-placeholder-value'
rm "$BUNDLE"
expect_failure 'missing bundle' exec-env app -- child
mkdir "$BUNDLE"
expect_failure 'directory bundle' exec-env app -- child
rmdir "$BUNDLE"
write_bundle 'VALUE=fixture-placeholder-value'; chmod 0644 "$BUNDLE"
expect_failure 'broad bundle mode' exec-env app -- child
mv "$BUNDLE" "$FIXTURE/outside"; ln -s "$FIXTURE/outside" "$BUNDLE"
expect_failure 'symlinked bundle' exec-env app -- child
pass

# Every fixed parent must be real, owned by the user, and non-writable; secrets is exactly 0700.
make_fixture parents
write_bundle 'VALUE=fixture-placeholder-value'
chmod 0775 "$FIXTURE_HOME/.config/dotfiles/local"
expect_failure 'writable parent' exec-env app -- child
chmod 0755 "$FIXTURE_HOME/.config/dotfiles/local"; chmod 0750 "$BUNDLE_DIRECTORY"
expect_failure 'inexact secrets mode' exec-env app -- child
chmod 0700 "$BUNDLE_DIRECTORY"
mv "$BUNDLE_DIRECTORY" "$FIXTURE/real-secrets"; ln -s "$FIXTURE/real-secrets" "$BUNDLE_DIRECTORY"
expect_failure 'symlinked secrets directory' exec-env app -- child
make_fixture linked-home
write_bundle 'VALUE=fixture-placeholder-value'
mv "$FIXTURE_HOME" "$FIXTURE/real-home"; ln -s "$FIXTURE/real-home" "$FIXTURE_HOME"
expect_failure 'symlinked HOME' exec-env app -- child
pass

# Usage, removed operations, and unavailable commands fail without reading or running anything.
make_fixture usage
write_bundle 'VALUE=fixture-placeholder-value'
for arguments in 'exec app VALUE -- child' 'status app' 'forget app' 'exec-env app child' 'exec-env app --' 'check-env app extra'; do
  read -r -a words <<< "$arguments"
  expect_failure 'removed or invalid interface' "${words[@]}"
done
expect_failure 'missing command' exec-env app -- unavailable-command
pass

# The helper has no provider, runtime-cache, lock, or network dependency.
make_fixture offline
write_bundle 'VALUE=fixture-placeholder-value'
for name in op loginctl flock curl wget; do
  cat > "$FIXTURE_BIN/$name" <<SCRIPT
#!/usr/bin/env bash
printf '%s' attempted > '$FIXTURE/$name-attempted'
exit 97
SCRIPT
  chmod 0755 "$FIXTURE_BIN/$name"
done
XDG_RUNTIME_DIR="$FIXTURE/runtime-does-not-exist" run_helper exec-env app -- child
for name in op loginctl flock curl wget; do [[ ! -e "$FIXTURE/$name-attempted" ]] || fail "$name was invoked"; done
[[ ! -e "$FIXTURE/runtime-does-not-exist" ]] || fail 'runtime storage was created'
pass

printf 'PASS: %d secret helper tests\n' "$TEST_COUNT"
