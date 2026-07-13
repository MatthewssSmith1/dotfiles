#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly BOOTSTRAP="$REPO_DIR/bootstrap.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$BOOTSTRAP" || fail 'bootstrap.sh has invalid Bash syntax'

grep -q '((EUID != 0))' "$BOOTSTRAP" || fail 'bootstrap does not use the shell EUID for root refusal'
grep -q -- '--target="$HOME"' "$BOOTSTRAP" || fail 'Stow does not explicitly target HOME'

if grep -Eq '(^|[^[:alnum:]_])(sudo|apt-get|usermod|chsh)([^[:alnum:]_]|$)|/etc/shells' "$BOOTSTRAP"; then
  fail 'bootstrap.sh contains a privileged package or login-shell operation'
fi

temp_home="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temp_home"
}
trap cleanup EXIT

check_output="$(HOME="$temp_home" "$BOOTSTRAP" --check 2>&1)" || {
  printf '%s\n' "$check_output" >&2
  fail 'bootstrap preflight failed on this system'
}
[[ "$check_output" == *'no changes made'* ]] || \
  fail 'bootstrap preflight did not confirm its non-mutating behavior'
shopt -s nullglob dotglob
home_entries=("$temp_home"/*)
((${#home_entries[@]} == 0)) || fail 'bootstrap preflight modified HOME'

if HOME="$temp_home" "$BOOTSTRAP" --unknown >/dev/null 2>&1; then
  fail 'bootstrap accepted an unknown argument'
fi

if command -v unshare >/dev/null 2>&1 && unshare --user --map-root-user true 2>/dev/null; then
  if unshare --user --map-root-user env HOME="$temp_home" "$BOOTSTRAP" --check >/dev/null 2>&1; then
    fail 'bootstrap did not refuse effective UID 0'
  fi
fi

conflict_root="$(mktemp -d)"
cp -a "$REPO_DIR/." "$conflict_root/dotfiles"
mkdir "$conflict_root/home"
printf 'unmanaged\n' > "$conflict_root/home/.zshrc"
conflict_output="$(HOME="$conflict_root/home" "$conflict_root/dotfiles/bootstrap.sh" 2>&1)" && \
  fail 'bootstrap accepted an unmanaged Stow conflict'
[[ "$conflict_output" == *'Stow conflict preflight failed'* ]] || \
  fail 'bootstrap did not report the Stow conflict clearly'
[[ "$(cat "$conflict_root/home/.zshrc")" == 'unmanaged' ]] || \
  fail 'bootstrap changed the conflicting unmanaged file'
[[ ! -e "$conflict_root/home/.local" && ! -e "$conflict_root/home/.gitconfig.local" ]] || \
  fail 'bootstrap mutated HOME before detecting the Stow conflict'
rm -rf -- "$conflict_root"

printf 'PASS: bootstrap boundary and preflight checks\n'
