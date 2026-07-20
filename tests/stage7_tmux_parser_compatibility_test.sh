#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly FIXTURE_ID='ubuntu-jammy-tmux-3-2a-amd64'
readonly MANAGED_ROOT='tmux-parser-fixtures-v1'
readonly TMUX_32A_SIZE='971320'
readonly TMUX_32A_SHA256='6684c9b0bd4af08461f9e476e0abee9c3f08daa5d55ed6fb7c663c000e09f83d'
readonly TMUX_34_SIZE='1102608'
readonly TMUX_34_SHA256='034b15c64035f783d43862f2775eb4828f61571ca62c8199796000b97d556ecd'
readonly TMUX_34_PACKAGE_VERSION='3.4-1ubuntu0.1'

FIXTURE_ROOT="${TMUX_PARSER_FIXTURE_ROOT:-}"
TMUX_32A_BIN="${TMUX_PARSER_TMUX_32A_BIN:-}"
TMUX_34_BIN="${TMUX_PARSER_TMUX_34_BIN:-/usr/bin/tmux}"
TMUX_37B_ROOT="${TMUX_PARSER_TMUX_37B_ROOT:-$HOME/.local/share/dotfiles/provisioning/tools/tmux/3.7b}"
TMUX_37B_BIN="${TMUX_PARSER_TMUX_37B_BIN:-}"
TEST_OUTPUT=""

fail() { printf 'FAIL: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2; exit 1; }
usage() {
  fail "usage: ${0##*/} --fixture-root <cache-root> [--tmux-3.2a <bin>] [--tmux-3.4 <bin>] [--tmux-3.7b-root <root>] [--tmux-3.7b <bin>]"
}

while (($# > 0)); do
  case "$1" in
    --fixture-root) (($# >= 2)) || usage; FIXTURE_ROOT="$2"; shift 2 ;;
    --tmux-3.2a) (($# >= 2)) || usage; TMUX_32A_BIN="$2"; shift 2 ;;
    --tmux-3.4) (($# >= 2)) || usage; TMUX_34_BIN="$2"; shift 2 ;;
    --tmux-3.7b-root) (($# >= 2)) || usage; TMUX_37B_ROOT="$2"; shift 2 ;;
    --tmux-3.7b) (($# >= 2)) || usage; TMUX_37B_BIN="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -z "$TMUX_32A_BIN" ]]; then
  [[ -n "$FIXTURE_ROOT" ]] || fail \
    "tmux 3.2a parser fixture root was not selected; prepare one with: $REPO_DIR/scripts/tmux-parser-fixtures sync --root <cache-root>"
  TMUX_32A_BIN="$FIXTURE_ROOT/$MANAGED_ROOT/$FIXTURE_ID/usr/bin/tmux"
fi
[[ -n "$TMUX_37B_BIN" ]] || TMUX_37B_BIN="$TMUX_37B_ROOT/tmux"

[[ -n "$FIXTURE_ROOT" ]] || fail 'tmux 3.2a requires its verified managed fixture root'
"$REPO_DIR/scripts/tmux-parser-fixtures" verify --root "$FIXTURE_ROOT" >/dev/null || \
  fail 'tmux 3.2a managed fixture root verification failed'
expected_32a="$FIXTURE_ROOT/$MANAGED_ROOT/$FIXTURE_ID/usr/bin/tmux"
[[ "$(realpath -e -- "$TMUX_32A_BIN" 2>/dev/null || true)" == "$(realpath -e -- "$expected_32a")" ]] || \
  fail 'tmux 3.2a must be the executable in the verified managed fixture generation'

if [[ ! -f "$TMUX_32A_BIN" || -L "$TMUX_32A_BIN" || ! -x "$TMUX_32A_BIN" ]]; then
  fail "tmux 3.2a parser fixture is unavailable; prepare it with: $REPO_DIR/scripts/tmux-parser-fixtures sync --root $FIXTURE_ROOT"
fi
[[ "$(stat -c '0%a:%s' -- "$TMUX_32A_BIN")" == "0755:$TMUX_32A_SIZE" && \
  "$(sha256sum -- "$TMUX_32A_BIN" | while read -r hash _; do printf '%s' "$hash"; done)" == "$TMUX_32A_SHA256" ]] || \
  fail "tmux 3.2a parser fixture identity drift; prepare it with: $REPO_DIR/scripts/tmux-parser-fixtures sync --root $FIXTURE_ROOT"

verify_tmux_34_identity() {
  local owner package
  [[ "$TMUX_34_BIN" == /usr/bin/tmux && -f "$TMUX_34_BIN" && ! -L "$TMUX_34_BIN" && -x "$TMUX_34_BIN" ]] || \
    fail 'tmux 3.4 parser must be the direct /usr/bin/tmux executable'
  [[ "$(stat -c '0%a:%s' -- "$TMUX_34_BIN")" == "0755:$TMUX_34_SIZE" && \
    "$(sha256sum -- "$TMUX_34_BIN" | while read -r hash _; do printf '%s' "$hash"; done)" == "$TMUX_34_SHA256" ]] || \
    fail 'distro /usr/bin/tmux 3.4 executable identity drift'
  owner="$(/usr/bin/dpkg-query -S /usr/bin/tmux 2>/dev/null || true)"
  [[ "$owner" == 'tmux: /usr/bin/tmux' ]] || fail 'distro /usr/bin/tmux is not owned exactly by the tmux package'
  package="$(/usr/bin/dpkg-query -W -f='${db:Status-Abbrev}|${binary:Package}|${Version}|${Architecture}' tmux 2>/dev/null || true)"
  [[ "$package" == "ii |tmux|$TMUX_34_PACKAGE_VERSION|amd64" ]] || fail "distro tmux package identity drift: $package"
}

verify_tmux_37b_identity() {
  local manifest="$REPO_DIR/manifests/provisioning.json" receipt="$HOME/.local/state/dotfiles/provisioning/v1/receipt.json"
  local expected_root expected_executable expected_mode expected_size expected_sha manifest_sha receipt_sha receipt_row
  expected_root="$(jq -r '.tools[] | select(.id == "tmux") | .install_root' "$manifest")"
  expected_executable="$(jq -r '.tools[] | select(.id == "tmux") | .artifact.executable' "$manifest")"
  IFS=$'\t' read -r expected_mode expected_size expected_sha < <(jq -r '
    .tools[] | select(.id == "tmux") |
    [.executable_identity.mode, (.executable_identity.size | tostring), .executable_identity.sha256] | @tsv
  ' "$manifest")
  [[ "$(realpath -e -- "$TMUX_37B_ROOT" 2>/dev/null || true)" == "$TMUX_37B_ROOT" &&
    -d "$TMUX_37B_ROOT" && ! -L "$TMUX_37B_ROOT" && "$(stat -c %u -- "$TMUX_37B_ROOT")" == "$EUID" ]] || \
    fail 'tmux 3.7b root is not an EUID-owned canonical directory'
  [[ "$TMUX_37B_BIN" == "$TMUX_37B_ROOT/$expected_executable" && -f "$TMUX_37B_BIN" && \
    ! -L "$TMUX_37B_BIN" && -x "$TMUX_37B_BIN" && "$(stat -c %u -- "$TMUX_37B_BIN")" == "$EUID" ]] || \
    fail 'tmux 3.7b executable is not at the EUID-owned manifest artifact path'
  [[ "$(stat -c '0%a:%s' -- "$TMUX_37B_BIN")" == "$expected_mode:$expected_size" && \
    "$(sha256sum -- "$TMUX_37B_BIN" | while read -r hash _; do printf '%s' "$hash"; done)" == "$expected_sha" ]] || \
    fail 'tmux 3.7b executable mode, size, or SHA-256 differs from the provisioning manifest'
  if [[ "$TMUX_37B_ROOT" == "$HOME/$expected_root" ]]; then
    [[ -f "$receipt" && ! -L "$receipt" && "$(stat -c '%u:%a' -- "$receipt")" == "$EUID:600" ]] || \
      fail 'tmux 3.7b retained root has no safe provisioning receipt'
    manifest_sha="$(sha256sum -- "$manifest" | while read -r hash _; do printf '%s' "$hash"; done)"
    receipt_sha="$(jq -er .manifest_sha256 "$receipt" 2>/dev/null || true)"
    if [[ "$receipt_sha" != "$manifest_sha" ]]; then
      jq -e --arg hash "$receipt_sha" '.previous_manifest_sha256s | index($hash) != null' \
        "$REPO_DIR/manifests/proposals/2026-07-17-stage5-tool-pins.json" >/dev/null || \
        fail 'tmux 3.7b receipt is not tied to the active or accepted provisioning manifest'
    fi
    receipt_row="$(jq -er '.tools[] | select(.id == "tmux") |
      [.backend,.version,.platform,.install_root,.executable,.executable_sha256] | @tsv' "$receipt" 2>/dev/null || true)"
    [[ "$receipt_row" == $'aqua:tmux/tmux-builds\t3.7b\tlinux-x86_64\t'"$expected_root"$'\t'"$expected_executable"$'\t'"$expected_sha" ]] || \
      fail 'tmux 3.7b provisioning receipt executable identity is not exact'
  fi
}

verify_tmux_34_identity
verify_tmux_37b_identity

run_parser_case() {
  local label="$1" executable="$2" expected_version="$3" expected_diagnostics="$4" output version
  executable="$(realpath -e -- "$executable" 2>/dev/null)" || fail "$label executable is unavailable: $executable"
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || fail "$label executable is unsafe: $executable"
  version="$(env -u TMUX HOME=/nonexistent "$executable" -V 2>/dev/null)" || fail "$label version probe failed"
  [[ "$version" == "tmux $expected_version" ]] || fail "$label must be real tmux $expected_version, found: $version"

  output="$(HOME=/nonexistent TARGET_ROOT=/nonexistent DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage7-real-tmux-parser \
    SELECTED_PROFILE=generic MODE=check TMUX_CASE_BIN="$executable" TMUX_CASE_VERSION="$expected_version" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/tmux.sh"
      TMUX_CLIENT_BIN="$TMUX_CASE_BIN"
      TMUX_CLIENT_VERSION="$TMUX_CASE_VERSION"
       validate_tmux_isolated_config checkout
    ' 2>&1)" || { TEST_OUTPUT="$output"; fail "$label rejected the committed dispatcher/baseline/persistence configuration"; }
  [[ "$output" == *"validated isolated tmux $expected_version parser: config diagnostics=$expected_diagnostics"* ]] || {
    TEST_OUTPUT="$output"
    fail "$label did not report the exact expected compatibility diagnostics"
  }
  printf 'PASS: %s diagnostics=%s\n' "$label" "$expected_diagnostics"
}

run_parser_case 'official Ubuntu Jammy tmux 3.2a fixture' "$TMUX_32A_BIN" 3.2a \
  'allow-passthrough extended-keys-format'
run_parser_case 'distro /usr/bin/tmux 3.4' "$TMUX_34_BIN" 3.4 'extended-keys-format'
run_parser_case 'retained static tmux 3.7b' "$TMUX_37B_BIN" 3.7b 'none'

printf 'PASS: real tmux parser compatibility gate (denied network, unique isolated sockets and homes)\n'
