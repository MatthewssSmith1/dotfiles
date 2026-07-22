#!/usr/bin/env bash
# Shared test harness sourced by every file in tests/. Usage, from tests/<domain>_test.sh:
#
#   set -Eeuo pipefail
#   source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"
#
# Provides TEST_DIR, REPO_DIR, BOOTSTRAP, a self-cleaning TEST_ROOT, assertion and
# capture helpers, host/home fixtures, network sentinels, repo-copy fixtures, and
# JSON Schema validation. A test file may redefine any function after sourcing;
# the later definition wins. Define test_extra_cleanup() for domain-specific
# teardown; it runs before TEST_ROOT is removed.

HARNESS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR="$(cd -- "$HARNESS_LIB_DIR/.." && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly BOOTSTRAP="$REPO_DIR/bootstrap.sh"

TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""
TEST_RC=0

cleanup_test() {
  if declare -F test_extra_cleanup >/dev/null; then
    test_extra_cleanup || true
  fi
  rm -rf -- "$TEST_ROOT"
}
trap cleanup_test EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ -z "$TEST_OUTPUT" ]] || printf '%s\n' "$TEST_OUTPUT" >&2
  exit 1
}

pass() {
  ((TEST_COUNT += 1))
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "expected output not to contain: $2"
}

assert_file() {
  [[ -f "$1" && ! -L "$1" ]] || fail "expected regular file: $1"
}

assert_same() {
  cmp -s -- "$1" "$2" || fail "files differ: $1 $2"
}

assert_empty_home() {
  local entries
  entries="$(find "$1" -mindepth 1 -print -quit)"
  [[ -z "$entries" ]] || fail "expected empty HOME, found $entries"
}

wait_for_file() {
  local path="$1" attempt
  for ((attempt=0; attempt<500; attempt++)); do
    [[ ! -e "$path" ]] || return 0
    sleep 0.01
  done
  fail "timed out waiting for $path"
}

# Host fixtures emulate /etc/os-release and the WSL kernel marker under
# DOTFILES_TEST_HOST_ROOT.
make_host() {
  local name="$1" kind="$2" id="${3:-ubuntu}" version="${4:-24.04}"
  local root="$TEST_ROOT/host-$name"
  mkdir -p "$root/etc" "$root/proc/sys/kernel"
  printf 'ID="%s"\nVERSION_ID="%s"\n' "$id" "$version" > "$root/etc/os-release"
  case "$kind" in
    wsl) printf '6.6.0-MiCrOsOfT-standard-WSL2\n' > "$root/proc/sys/kernel/osrelease" ;;
    linux) printf '6.8.0-generic\n' > "$root/proc/sys/kernel/osrelease" ;;
    *) fail "unknown host fixture kind: $kind" ;;
  esac
  printf '%s' "$root"
}

new_home() {
  local name="$1"
  local home="$TEST_ROOT/home-$name"
  mkdir "$home"
  printf '%s' "$home"
}

# capture runs a bootstrap under test-controlled HOME/host and records
# TEST_OUTPUT/TEST_RC. Knobs, all optional:
#   TEST_GIT_USER_NAME / TEST_GIT_USER_EMAIL  identity exported to the run
#   CAPTURE_PATH_PREFIX  prepended to PATH for the run
#   CAPTURE_DEFAULT_AREA appended as --area <name> unless the caller passes one
capture() {
  local home="$1" host="$2" bootstrap="$3"
  shift 3
  if [[ -n "${CAPTURE_DEFAULT_AREA:-}" ]]; then
    local argument explicit_area=false
    for argument in "$@"; do
      [[ "$argument" != --area && "$argument" != --area=* ]] || explicit_area=true
    done
    [[ "$explicit_area" == true ]] || set -- "$@" --area "$CAPTURE_DEFAULT_AREA"
  fi
  local path_value="$PATH"
  [[ -z "${CAPTURE_PATH_PREFIX:-}" ]] || path_value="$CAPTURE_PATH_PREFIX:$PATH"
  if TEST_OUTPUT="$(HOME="$home" PATH="$path_value" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
    GIT_USER_NAME="${TEST_GIT_USER_NAME:-Harness Test User}" \
    GIT_USER_EMAIL="${TEST_GIT_USER_EMAIL:-harness@example.com}" \
    "$bootstrap" "$@" 2>&1)"; then
    TEST_RC=0
  else
    TEST_RC=$?
  fi
}

expect_success() {
  capture "$@"
  ((TEST_RC == 0)) || fail "command unexpectedly failed with $TEST_RC"
}

expect_failure() {
  local expected="$1"
  shift
  capture "$@"
  ((TEST_RC != 0)) || fail 'command unexpectedly succeeded'
  assert_contains "$TEST_OUTPUT" "$expected"
}

# Network isolation: prefer a real network namespace when unprivileged
# unshare is available; the probe result is cached after the first call.
network_namespace_available() {
  if [[ -z "${NETWORK_NAMESPACE:-}" ]]; then
    NETWORK_NAMESPACE=false
    if unshare --user --map-current-user --net true >/dev/null 2>&1; then
      NETWORK_NAMESPACE=true
    fi
  fi
  [[ "$NETWORK_NAMESPACE" == true ]]
}

run_network_isolated() {
  if network_namespace_available; then
    unshare --user --map-current-user --net -- "$@"
  else
    "$@"
  fi
}

# Sentinel stubs record any network-capable command into $HOME/network-attempted
# and fail with status 97. Mode "with-git" (default) also wraps git so remote
# subcommands trip the sentinel while local ones pass through; use "no-git"
# for tests that legitimately run git against local paths.
install_network_sentinels() {
  local home="$1" mode="${2:-with-git}" name
  mkdir -p "$home/fake-bin"
  for name in curl wget ssh scp sudo apt apt-get pacman dnf yum apk snap flatpak npm pnpm yarn bun pip pip3; do
    cat > "$home/fake-bin/$name" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s:%s\n' "${0##*/}" "$*" >> "$HOME/network-attempted"
exit 97
SCRIPT
    chmod 0755 "$home/fake-bin/$name"
  done
  [[ "$mode" == with-git ]] || return 0
  cat > "$home/fake-bin/git" <<'SCRIPT'
#!/usr/bin/env bash
case " ${*:-} " in
  *' clone '*|*' fetch '*|*' pull '*|*' push '*|*' ls-remote '*|*' submodule '*)
    printf 'git:%s\n' "$*" >> "$HOME/network-attempted"
    exit 97
    ;;
esac
exec /usr/bin/git "$@"
SCRIPT
  chmod 0755 "$home/fake-bin/git"
}

make_fake_initializer() {
  local path="$1" name="$2" selector="$3"
  cat > "$path" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$*" == "$selector" ]]; then
  printf '%s\n' 'printf "%s\\n" $name-init >> "\$INIT_TRACE"'
fi
SCRIPT
  chmod 0755 "$path"
}

# Repo-copy fixtures give a test its own checkout whose manifests it may edit.
copy_repo_fixture() {
  local name="$1"
  local fixture="$TEST_ROOT/fixture-$name"
  mkdir "$fixture"
  cp -a "$REPO_DIR/." "$fixture/"
  printf '%s' "$fixture"
}

set_area_status() {
  local fixture="$1" area="$2" status="$3"
  sed -i "s/^area|$area|[a-z]*$/area|$area|$status/" "$fixture/manifests/areas.tsv"
  grep -qxF "area|$area|$status" "$fixture/manifests/areas.tsv" || \
    fail "could not mark area $area $status in $fixture"
}

# JSON Schema validation via python3 + jsonschema (Draft 2020-12). Skips with a
# warning when the validator is unavailable so the suite stays dependency-light.
schema_validator_available() {
  if [[ -z "${SCHEMA_VALIDATOR:-}" ]]; then
    SCHEMA_VALIDATOR=false
    if python3 -c 'import jsonschema' >/dev/null 2>&1; then
      SCHEMA_VALIDATOR=true
    fi
  fi
  [[ "$SCHEMA_VALIDATOR" == true ]]
}

validate_json_schema() {
  local schema="$1" instance="$2"
  if ! schema_validator_available; then
    printf 'WARN: python3-jsonschema unavailable; skipped schema validation of %s\n' "$instance" >&2
    return 0
  fi
  python3 - "$schema" "$instance" <<'PYTHON' || fail "schema validation failed: $instance against $schema"
import json, sys
import jsonschema

with open(sys.argv[1]) as handle:
    schema = json.load(handle)
with open(sys.argv[2]) as handle:
    instance = json.load(handle)
validator = jsonschema.Draft202012Validator(schema)
validator.check_schema(schema)
errors = list(validator.iter_errors(instance))
for error in errors[:10]:
    path = '/'.join(str(part) for part in error.absolute_path) or '<root>'
    print(f'{path}: {error.message}', file=sys.stderr)
sys.exit(1 if errors else 0)
PYTHON
}
