#!/usr/bin/env bash

set -Eeuo pipefail

unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly BOOTSTRAP="$REPO_DIR/bootstrap.sh"
TEST_ROOT="$(mktemp -d)"
TEST_BIN="$TEST_ROOT/bin"
mkdir "$TEST_BIN"
for command_name in eza bat fdfind fzf rg zoxide; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_BIN/$command_name"
  chmod +x "$TEST_BIN/$command_name"
done
export PATH="$TEST_BIN:$PATH"
TEST_COUNT=0
TEST_OUTPUT=""
TEST_RC=0

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

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

capture() {
  local home="$1" host="$2" bootstrap="$3"
  shift 3
  if TEST_OUTPUT="$(HOME="$home" PATH="$TEST_BIN:$PATH" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
    GIT_USER_NAME='Stage Three User' GIT_USER_EMAIL='stage3@example.com' "$bootstrap" "$@" 2>&1)"; then
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

# Additional fixture payloads live only in these test-time repo copies. Flipping
# readiness exercises populated upstream snapshots without changing the manifest.
make_stage3_fixture() {
  local name="$1"
  shift
  local fixture="$TEST_ROOT/fixture-$name"
  local area bash_fixture=false tmux_fixture=false zsh_fixture=false
  mkdir "$fixture"
  cp -a "$REPO_DIR/." "$fixture/"
  # Historical Stage 3 fixtures opt into tmux explicitly; production is ready now.
  sed -i 's/^area|tmux|ready$/area|tmux|framework/' "$fixture/manifests/areas.tsv"
  if [[ "$name" != real-baselines && "$name" != default-ready ]]; then
    for area in starship tmux nvim; do
      rm -rf -- "$fixture/packages/upstream/$area"
      mkdir -p -- "$fixture/packages/upstream/$area"
      printf 'Placeholder for isolated Stage 3 fixture.\n' > \
        "$fixture/packages/upstream/$area/.empty-package"
      printf '^/\\.empty-package$\n' > "$fixture/packages/upstream/$area/.stow-local-ignore"
    done
    # Later stages populated every tmux layer. Historical Stage 3 fixtures use
    # only payloads added explicitly below, preserving their generic-engine scope.
    for package in generic/tmux wsl/tmux common/tmux; do
      rm -rf -- "$fixture/packages/$package"
      mkdir -p -- "$fixture/packages/$package"
      printf 'Placeholder for isolated Stage 3 fixture.\n' > "$fixture/packages/$package/.empty-package"
      printf '^/\\.empty-package$\n' > "$fixture/packages/$package/.stow-local-ignore"
    done
  fi
  for area in "$@"; do
    if grep -qxF "area|$area|framework" "$fixture/manifests/areas.tsv"; then
      sed -i "s/^area|$area|framework$/area|$area|ready/" "$fixture/manifests/areas.tsv"
    fi
    grep -qxF "area|$area|ready" "$fixture/manifests/areas.tsv" || \
      fail "fixture $name could not mark area $area ready"
    [[ "$area" != bash ]] || bash_fixture=true
    [[ "$area" != tmux ]] || tmux_fixture=true
    [[ "$area" != zsh ]] || zsh_fixture=true
  done
  if [[ "$bash_fixture" == true ]]; then
    cat >> "$fixture/lib/areas/bash.sh" <<'SCRIPT'

# Stage 3 fixtures exercise the generic engine, not the later Bash lifecycle.
preflight_bash() { preflight_generic bash; }
apply_bash() { apply_generic; }
remove_bash() { remove_generic bash; }
SCRIPT
  fi
  if [[ "$tmux_fixture" == true ]]; then
    cat >> "$fixture/lib/areas/tmux.sh" <<'SCRIPT'

# Stage 3 fixtures exercise the generic engine, not the later tmux lifecycle.
preflight_tmux() { preflight_generic tmux; }
apply_tmux() { apply_generic; }
remove_tmux() { remove_generic tmux; }
SCRIPT
  fi
  if [[ "$zsh_fixture" == true ]]; then
    cat >> "$fixture/lib/areas/zsh.sh" <<'SCRIPT'

# Stage 3 fixtures exercise the generic engine, not the later zsh lifecycle.
preflight_zsh() { preflight_generic zsh; }
apply_zsh() { apply_generic; }
remove_zsh() { remove_generic zsh; }
SCRIPT
  fi
  printf '%s' "$fixture"
}

add_payload() {
  local fixture="$1" package="$2" relative="$3" content="$4"
  local target="$fixture/packages/$package/$relative"
  mkdir -p "$(dirname -- "$target")"
  printf '%s\n' "$content" > "$target"
}

readonly BOOTSTRAP_SOURCES=(
  "$BOOTSTRAP"
  "$REPO_DIR/lib/common.sh"
  "$REPO_DIR/lib/host.sh"
  "$REPO_DIR/lib/engine.sh"
  "$REPO_DIR/lib/areas/git.sh"
  "$REPO_DIR/lib/areas/bash.sh"
  "$REPO_DIR/lib/areas/tmux.sh"
  "$REPO_DIR/lib/areas/zsh.sh"
  "$REPO_DIR/lib/areas/generic.sh"
)
for source_file in "${BOOTSTRAP_SOURCES[@]}"; do
  [[ -f "$source_file" ]] || fail "missing bootstrap source file: $source_file"
done
bash -n "${BOOTSTRAP_SOURCES[@]}" || fail 'a bootstrap source file has invalid Bash syntax'

wsl_host="$(make_host stage3-wsl wsl)"

# Committed statics: the area manifest, the canonical profile closure table,
# populated shell/upstream snapshots, and placeholders for unfinished package layers.
expected_areas='schema|1
area|git|ready
area|bash|ready
area|tmux|ready
area|nvim|framework
area|zsh|ready'
[[ "$(cat "$REPO_DIR/manifests/areas.tsv")" == "$expected_areas" ]] || \
  fail 'manifests/areas.tsv does not record the current readiness table'
declare -A EXPECTED_CLOSURES=(
  [generic:git]='upstream/git,generic/git,common/git'
  [generic:bash]='upstream/bash,upstream/starship,generic/bash,common/bash'
  [generic:tmux]='upstream/tmux,generic/tmux,common/tmux'
  [generic:nvim]='upstream/nvim,generic/nvim,common/nvim'
  [generic:zsh]='common/zsh'
  [wsl:git]='upstream/git,generic/git,common/git'
  [wsl:bash]='upstream/bash,upstream/starship,generic/bash,wsl/bash,common/bash'
  [wsl:tmux]='upstream/tmux,generic/tmux,wsl/tmux,common/tmux'
  [wsl:nvim]='upstream/nvim,generic/nvim,common/nvim'
  [wsl:zsh]='common/zsh'
  [omarchy:git]='common/git'
  [omarchy:bash]='common/bash'
  [omarchy:tmux]='common/tmux'
  [omarchy:nvim]='common/nvim'
  [omarchy:zsh]='common/zsh'
)
for key in "${!EXPECTED_CLOSURES[@]}"; do
  profile="${key%%:*}"
  area="${key#*:}"
  grep -qxF "$area ${EXPECTED_CLOSURES[$key]}" "$REPO_DIR/profiles/$profile.conf" || \
    fail "profile $profile does not list the canonical $area closure"
done
for profile in omarchy generic wsl; do
  [[ "$(grep -cve '^#' -e '^$' "$REPO_DIR/profiles/$profile.conf")" == 5 ]] || \
    fail "profile $profile does not list exactly five area closures"
done
for package in common/nvim generic/git generic/nvim; do
  root="$REPO_DIR/packages/$package"
  [[ -d "$root" && ! -L "$root" ]] || fail "missing committed package root: packages/$package"
  entries="$(cd "$root" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$entries" == './.empty-package ./.stow-local-ignore ' ]] || \
    fail "packages/$package is not an empty placeholder: $entries"
done
zsh_root="$REPO_DIR/packages/common/zsh"
[[ -d "$zsh_root" && ! -L "$zsh_root" ]] || fail 'missing packages/common/zsh'
zsh_entries="$(cd "$zsh_root" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')"
[[ "$zsh_entries" == './.p10k.zsh ./.zsh_aliases ./.zshrc ' ]] || \
  fail "packages/common/zsh does not contain the exact Stage 6 payload: $zsh_entries"
[[ -f "$REPO_DIR/packages/wsl/bash/.config/dotfiles/bash/wsl.bash" ]] || \
  fail 'packages/wsl/bash is missing its Stage 6 adapter payload'
bash_upstream_root="$REPO_DIR/packages/upstream/bash"
[[ ! -e "$bash_upstream_root/.empty-package" && \
  ! -e "$bash_upstream_root/.stow-local-ignore" ]] || \
  fail 'packages/upstream/bash retains framework markers'
for payload in shell aliases fns/tmux inputrc; do
  [[ -f "$bash_upstream_root/.config/dotfiles/upstream/bash/$payload" && \
    ! -L "$bash_upstream_root/.config/dotfiles/upstream/bash/$payload" ]] || \
    fail "packages/upstream/bash is missing selected payload: $payload"
done
for fragment in \
  common/bash/.config/mise/conf.d/20-dotfiles-common.toml \
  generic/bash/.config/mise/conf.d/30-dotfiles-profile.toml; do
  [[ -f "$REPO_DIR/packages/$fragment" && ! -L "$REPO_DIR/packages/$fragment" ]] || \
    fail "missing staged mise fragment: packages/$fragment"
done
for package in upstream/starship upstream/tmux upstream/nvim; do
  root="$REPO_DIR/packages/$package"
  [[ -d "$root" && ! -L "$root" ]] || fail "missing populated package root: packages/$package"
  [[ -z "$(find "$root" -name .empty-package -o -name .stow-local-ignore)" ]] || \
    fail "packages/$package retains framework markers"
  [[ -n "$(find "$root" -type f -print -quit)" ]] || fail "packages/$package has no snapshot payload"
done
reference_root="$REPO_DIR/packages/upstream/reference"
[[ -d "$reference_root/omarchy/default/bash" && -d "$reference_root/omarchy/themes/tokyo-night" ]] || \
  fail 'packages/upstream/reference does not contain the Stage 4 reference snapshot roots'
pass

# Ready-flipped fixtures deploy the real Stage 4 XDG baselines and retain exact
# state ownership; readiness remains a production-stage decision.
fixture="$(make_stage3_fixture real-baselines bash tmux)"
home="$(new_home real-baselines)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash --area tmux
[[ "$(realpath "$home/.config/starship.toml")" == \
  "$fixture/packages/upstream/starship/.config/starship.toml" ]] || fail 'real Starship baseline did not deploy'
[[ "$(realpath "$home/.config/tmux/tmux.conf")" == \
  "$fixture/packages/generic/tmux/.config/tmux/tmux.conf" ]] || fail 'real tmux dispatcher did not deploy'
[[ "$(realpath "$home/.config/dotfiles/upstream/tmux/tmux.conf")" == \
  "$fixture/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf" ]] || fail 'private tmux baseline did not deploy'
for record in bash:.config/starship.toml tmux:.config/tmux/tmux.conf; do
  area="${record%%:*}"
  target="${record#*:}"
  state="$home/.local/state/dotfiles/v1/$area.json"
  assert_file "$state"
  jq -e --arg target "$target" 'any(.targets[]; .path == $target)' "$state" >/dev/null || \
    fail "$area state does not record $target"
done
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
assert_empty_home "$home"
[[ "$(cat "$REPO_DIR/manifests/areas.tsv")" == "$expected_areas" ]] || \
  fail 'ready-flipped fixture changed committed area readiness'
pass

# Framework areas refuse apply and check symmetrically; a focused fixture proves
# the Git/Bash/zsh default-ready selection without invoking later area behavior.
home="$(new_home framework-refusal)"
expect_failure "area 'nvim' is framework-only" "$home" "$wsl_host" "$BOOTSTRAP" --check --area nvim
assert_empty_home "$home"
expect_failure "unknown area 'python'" "$home" "$wsl_host" "$BOOTSTRAP" --area python

default_fixture="$(make_stage3_fixture default-ready bash zsh)"
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh" --check
assert_contains "$TEST_OUTPUT" "area 'git' preflight passed"
assert_contains "$TEST_OUTPUT" "area 'bash' preflight passed"
assert_contains "$TEST_OUTPUT" "area 'zsh' preflight passed"
assert_not_contains "$TEST_OUTPUT" "area 'tmux'"
assert_empty_home "$home"
expect_failure 'first WSL Bash deployment must explicitly select --area bash without zsh' \
  "$home" "$wsl_host" "$default_fixture/bootstrap.sh"
assert_empty_home "$home"
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh" --area bash
expect_failure 'first WSL zsh deployment must explicitly select --area zsh without bash' \
  "$home" "$wsl_host" "$default_fixture/bootstrap.sh"
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh" --area zsh
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh"
state_names="$(printf '%s\n' "$home/.local/state/dotfiles/v1/"*.json | xargs -n1 basename | sort | tr '\n' ' ')"
[[ "$state_names" == 'bash.json git.json zsh.json ' ]] || \
  fail 'bare apply did not record exactly the default-ready areas'
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh" --remove
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh" --remove --area bash
assert_contains "$TEST_OUTPUT" "area 'bash' is not deployed; no changes made"
pass

# Independent selected-area success and aggregate failure, for apply and check.
fixture="$(make_stage3_fixture independent bash tmux)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-generic' 'bash generic payload'
add_payload "$fixture" generic/tmux '.fixture-tmux' 'tmux payload'
home="$(new_home independent)"
printf 'existing\n' > "$home/.fixture-tmux"
capture "$home" "$wsl_host" "$fixture/bootstrap.sh" --area tmux --area bash
((TEST_RC == 1)) || fail "aggregate failure expected exit 1, got $TEST_RC"
assert_contains "$TEST_OUTPUT" 'unrelated destination conflict'
assert_contains "$TEST_OUTPUT" "applied bash area for profile 'wsl'"
[[ -L "$home/.config/dotfiles/fixture/bash-generic" ]] || fail 'independent bash area did not deploy'
assert_file "$home/.local/state/dotfiles/v1/bash.json"
[[ "$(jq -r .area "$home/.local/state/dotfiles/v1/bash.json")" == bash ]] || fail 'bash state area is wrong'
[[ "$(cat "$home/.fixture-tmux")" == existing ]] || fail 'failed tmux area modified the conflicting file'
[[ ! -e "$home/.local/state/dotfiles/v1/tmux.json" ]] || fail 'failed tmux area wrote state'
home="$(new_home independent-check)"
printf 'existing\n' > "$home/.fixture-tmux"
capture "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area tmux --area bash
((TEST_RC == 1)) || fail "aggregate check failure expected exit 1, got $TEST_RC"
assert_contains "$TEST_OUTPUT" 'unrelated destination conflict'
assert_contains "$TEST_OUTPUT" "area 'bash' preflight passed"
[[ "$(find "$home" -mindepth 1)" == "$home/.fixture-tmux" ]] || fail 'aggregate check mutated the home'
pass

# Layer ordering across the full five-package WSL bash closure.
fixture="$(make_stage3_fixture ordering bash)"
add_payload "$fixture" upstream/bash '.config/dotfiles/fixture/upstream-bash' 'upstream'
add_payload "$fixture" upstream/starship '.config/dotfiles/fixture/upstream-starship' 'starship'
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/generic-bash' 'generic'
add_payload "$fixture" wsl/bash '.config/dotfiles/fixture/wsl-bash' 'wsl'
add_payload "$fixture" common/bash '.config/dotfiles/fixture/common-bash' 'common'
home="$(new_home ordering)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
state="$home/.local/state/dotfiles/v1/bash.json"
[[ "$(jq -c .packages "$state")" == '["upstream/bash","upstream/starship","generic/bash","wsl/bash","common/bash"]' ]] || \
  fail 'bash state does not record the ordered five-layer closure'
for entry in upstream-bash:upstream/bash upstream-starship:upstream/starship \
  generic-bash:generic/bash wsl-bash:wsl/bash common-bash:common/bash; do
  name="${entry%%:*}"
  package="${entry#*:}"
  [[ "$(realpath "$home/.config/dotfiles/fixture/$name")" == \
    "$fixture/packages/$package/.config/dotfiles/fixture/$name" ]] || \
    fail "layer link $name does not resolve into packages/$package"
done
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove --area bash
[[ ! -e "$state" ]] || fail 'bash removal left state'
assert_empty_home "$home"
pass

# Rollback journal success for a generic area at every exposed mutation fault.
for point in after-stow before-state; do
  home="$(new_home "rollback-$point")"
  if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
    DOTFILES_TEST_FAIL_AT="$point" "$fixture/bootstrap.sh" --area bash 2>&1)"; then
    fail "bash fault injection unexpectedly succeeded at $point"
  fi
  assert_contains "$TEST_OUTPUT" "injected test failure at $point"
  assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'bash'"
  assert_empty_home "$home"
done
home="$(new_home rollback-after-state-commit)"
if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  DOTFILES_TEST_FAIL_AT=after-state-commit "$fixture/bootstrap.sh" --area bash 2>&1)"; then
  fail 'post-state bash fault injection unexpectedly succeeded'
fi
assert_file "$home/.local/state/dotfiles/v1/bash.json"
[[ -L "$home/.config/dotfiles/fixture/common-bash" ]] || fail 'committed bash state fault lost deployed links'
pass

# Rollback failure stops all further area mutation with reserved status 70 and
# preserves the journal for manual recovery.
fixture="$(make_stage3_fixture rollback-failure bash tmux)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-payload' 'payload'
add_payload "$fixture" generic/tmux '.fixture-tmux' 'tmux payload'
home="$(new_home rollback-failure)"
hold_dir="$TEST_ROOT/rollback-failure-hold"
sabotage_target="$TEST_ROOT/rollback-failure-external"
mkdir "$hold_dir" "$sabotage_target"
HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  DOTFILES_TEST_FAIL_AT=after-stow DOTFILES_TEST_HOLD_AT=before-rollback DOTFILES_TEST_HOLD_DIR="$hold_dir" \
  "$fixture/bootstrap.sh" --area bash --area tmux > "$TEST_ROOT/rollback-failure.log" 2>&1 &
rollback_pid=$!
wait_for_file "$hold_dir/before-rollback.ready"
rm -rf -- "$home/.config"
ln -s "$sabotage_target" "$home/.config"
: > "$hold_dir/before-rollback.release"
status=0
wait "$rollback_pid" || status=$?
TEST_OUTPUT="$(cat "$TEST_ROOT/rollback-failure.log")"
((status == 70)) || fail "rollback failure expected reserved exit 70, got $status"
assert_contains "$TEST_OUTPUT" 'rollback failed; inspect journal'
assert_contains "$TEST_OUTPUT" "rollback failed for area 'bash'; stopping before further areas"
assert_not_contains "$TEST_OUTPUT" 'applied tmux area'
journal="$(sed -n 's/.*inspect journal //p' <<< "$TEST_OUTPUT" | head -n 1)"
[[ -n "$journal" && -d "$journal" ]] || fail 'failed rollback did not preserve its journal'
[[ ! -e "$home/.local/state/dotfiles/v1/tmux.json" && ! -e "$home/.fixture-tmux" ]] || \
  fail 'second area was mutated after rollback failure'
[[ -z "$(find "$sabotage_target" -mindepth 1 -print -quit)" ]] || \
  fail 'failed rollback escaped into the symlinked directory'
rm -rf -- "$journal"
TEST_OUTPUT=""
pass

# Omitted deployed areas remain untouched, and removal is per-area or full.
fixture="$(make_stage3_fixture omitted bash tmux)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-payload' 'payload'
add_payload "$fixture" generic/tmux '.fixture-tmux' 'tmux payload'
home="$(new_home omitted)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash --area tmux
tmux_state="$home/.local/state/dotfiles/v1/tmux.json"
tmux_state_hash="$(sha256sum "$tmux_state")"
tmux_link="$(readlink -- "$home/.fixture-tmux")"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
[[ "$(sha256sum "$tmux_state")" == "$tmux_state_hash" ]] || fail 'omitted tmux state changed on bash apply'
[[ "$(readlink -- "$home/.fixture-tmux")" == "$tmux_link" ]] || fail 'omitted tmux link changed on bash apply'
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove --area bash
[[ ! -e "$home/.local/state/dotfiles/v1/bash.json" ]] || fail 'per-area removal left bash state'
[[ ! -e "$home/.config/dotfiles/fixture/bash-payload" ]] || fail 'per-area removal left bash links'
[[ "$(sha256sum "$tmux_state")" == "$tmux_state_hash" ]] || fail 'per-area removal changed tmux state'
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
[[ ! -e "$home/.local/state/dotfiles/v1/bash.json" && ! -e "$tmux_state" ]] || \
  fail 'full removal left recorded area state'
assert_empty_home "$home"
home="$(new_home remove-empty)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
assert_contains "$TEST_OUTPUT" 'no deployed areas are recorded; no changes made'
assert_empty_home "$home"
pass

# Profile changes refuse before any mutation until prior state is removed.
fixture="$(make_stage3_fixture profile-change bash tmux)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-payload' 'payload'
add_payload "$fixture" generic/tmux '.fixture-tmux' 'tmux payload'
home="$(new_home profile-change)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
expect_failure 'run --remove before changing profiles' "$home" "$wsl_host" \
  "$fixture/bootstrap.sh" --profile generic --area tmux
[[ ! -e "$home/.local/state/dotfiles/v1/tmux.json" && ! -e "$home/.fixture-tmux" ]] || \
  fail 'profile mismatch mutated a newly selected area'
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --profile generic --area tmux
[[ "$(jq -r .profile "$home/.local/state/dotfiles/v1/tmux.json")" == generic ]] || \
  fail 'tmux state does not record the new profile'
pass

# Unknown packages refuse every run because all listed closures must exist.
fixture="$(make_stage3_fixture bad-closure bash)"
sed -i 's|^bash .*$|bash missing/bash|' "$fixture/profiles/wsl.conf"
home="$(new_home bad-closure)"
expect_failure 'missing package root' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area bash
assert_empty_home "$home"
expect_failure 'missing package root' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area git
assert_empty_home "$home"
pass

# A moved checkout is reconciled for a generic area from recorded ownership.
fixture="$(make_stage3_fixture moved-one bash)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-payload' 'payload'
home="$(new_home stage3-moved)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
moved="$TEST_ROOT/fixture-moved-two"
cp -a "$fixture" "$moved"
rm -rf -- "$fixture"
expect_success "$home" "$wsl_host" "$moved/bootstrap.sh" --area bash
[[ "$(jq -r .checkout_root "$home/.local/state/dotfiles/v1/bash.json")" == "$moved" ]] || \
  fail 'bash state did not move to the new checkout'
[[ "$(realpath "$home/.config/dotfiles/fixture/bash-payload")" == \
  "$moved/packages/generic/bash/.config/dotfiles/fixture/bash-payload" ]] || \
  fail 'bash link did not move to the new checkout'
pass

# Malformed and newer-schema generic-area state refuses even git-only runs.
fixture="$(make_stage3_fixture states bash)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-payload' 'payload'
home="$(new_home stage3-states)"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash
state="$home/.local/state/dotfiles/v1/bash.json"
cp "$state" "$TEST_ROOT/bash-state-good.json"
printf '{bad json\n' > "$state"
expect_failure 'malformed or unknown deployment state' "$home" "$wsl_host" "$fixture/bootstrap.sh" --area git
cp "$TEST_ROOT/bash-state-good.json" "$state"
jq '.schema_version = 2' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
expect_failure 'newer deployment state schema 2' "$home" "$wsl_host" "$fixture/bootstrap.sh" --area git
cp "$TEST_ROOT/bash-state-good.json" "$state"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
pass

# Fixture package conflicts: duplicate targets inside one closure and a shared
# path across two areas in one apply.
fixture="$(make_stage3_fixture duplicate-targets bash)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/shared' 'generic'
add_payload "$fixture" common/bash '.config/dotfiles/fixture/shared' 'common'
home="$(new_home duplicate-targets)"
expect_failure 'duplicate payload target' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area bash
assert_empty_home "$home"
fixture="$(make_stage3_fixture shared-target bash tmux)"
add_payload "$fixture" generic/bash '.fixture-shared' 'bash payload'
add_payload "$fixture" generic/tmux '.fixture-shared' 'tmux payload'
home="$(new_home shared-target)"
capture "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash --area tmux
((TEST_RC == 1)) || fail "shared-target apply expected exit 1, got $TEST_RC"
assert_contains "$TEST_OUTPUT" "applied bash area for profile 'wsl'"
assert_contains "$TEST_OUTPUT" 'unrelated destination conflict'
[[ "$(realpath "$home/.fixture-shared")" == "$fixture/packages/generic/bash/.fixture-shared" ]] || \
  fail 'first area did not retain the shared target'
[[ ! -e "$home/.local/state/dotfiles/v1/tmux.json" ]] || fail 'refused second area wrote state'
pass

# Generalized cleanup consumes the reviewed legacy inventory: deferred records
# are refused rather than migrated, and agent-skill exclusions stay untouched.
legacy_root="$TEST_ROOT/stage3-legacy-old"
cp -a "$REPO_DIR" "$legacy_root"
fixture="$(make_stage3_fixture legacy bash tmux)"
add_payload "$fixture" generic/tmux '.tmux.conf' 'replacement tmux payload'
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/bash-payload' 'payload'
home="$(new_home stage3-legacy)"
jq --arg home "$home" --arg root "$legacy_root" \
  '.hosts[0].home = $home | .hosts[0].checkout_root = $root' \
  "$fixture/manifests/legacy-links.json" > "$fixture/manifests/legacy-links.json.tmp"
mv "$fixture/manifests/legacy-links.json.tmp" "$fixture/manifests/legacy-links.json"
ln -s "$legacy_root/.tmux.conf" "$home/.tmux.conf"
mkdir "$home/.agents" "$home/.claude"
ln -s "$legacy_root/.agents/.gitignore" "$home/.agents/.gitignore"
ln -s "$legacy_root/.claude/skills" "$home/.claude/skills"
legacy_tmux_hash="$(sha256sum "$legacy_root/.tmux.conf")"
agent_link="$(readlink -- "$home/.agents/.gitignore")"
bridge_link="$(readlink -- "$home/.claude/skills")"
capture "$home" "$wsl_host" "$fixture/bootstrap.sh" --area bash --area tmux
((TEST_RC == 1)) || fail "deferred-inventory apply expected exit 1, got $TEST_RC"
assert_contains "$TEST_OUTPUT" 'unrelated destination conflict'
assert_contains "$TEST_OUTPUT" "applied bash area for profile 'wsl'"
[[ -L "$home/.tmux.conf" && "$(readlink -- "$home/.tmux.conf")" == "$legacy_root/.tmux.conf" ]] || \
  fail 'deferred tmux legacy link was consumed'
[[ "$(sha256sum "$legacy_root/.tmux.conf")" == "$legacy_tmux_hash" ]] || \
  fail 'deferred tmux legacy source changed'
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
[[ -L "$home/.agents/.gitignore" && "$(readlink -- "$home/.agents/.gitignore")" == "$agent_link" ]] || \
  fail 'excluded agent-skill link was touched'
[[ -L "$home/.claude/skills" && "$(readlink -- "$home/.claude/skills")" == "$bridge_link" ]] || \
  fail 'excluded broken agent bridge was touched'
[[ -L "$home/.tmux.conf" ]] || fail 'removal touched the deferred tmux legacy link'
real_elsewhere="$TEST_ROOT/stage3-real-elsewhere"
mkdir "$real_elsewhere"
printf 'unrelated tmux\n' > "$real_elsewhere/.tmux.conf"
fake_root="$TEST_ROOT/stage3-fake-root"
ln -s "$real_elsewhere" "$fake_root"
fixture="$(make_stage3_fixture legacy-resolved tmux)"
add_payload "$fixture" generic/tmux '.tmux.conf' 'replacement tmux payload'
home="$(new_home stage3-legacy-resolved)"
jq --arg home "$home" --arg root "$fake_root" \
  '.hosts[0].home = $home | .hosts[0].checkout_root = $root' \
  "$fixture/manifests/legacy-links.json" > "$fixture/manifests/legacy-links.json.tmp"
mv "$fixture/manifests/legacy-links.json.tmp" "$fixture/manifests/legacy-links.json"
ln -s "$fake_root/.tmux.conf" "$home/.tmux.conf"
capture "$home" "$wsl_host" "$fixture/bootstrap.sh" --area tmux
((TEST_RC != 0)) || fail 'lexical-match resolved-elsewhere legacy link was consumed'
assert_contains "$TEST_OUTPUT" 'unrelated destination conflict'
[[ "$(readlink -- "$home/.tmux.conf")" == "$fake_root/.tmux.conf" ]] || \
  fail 'resolved-elsewhere legacy link changed'
[[ "$(cat "$real_elsewhere/.tmux.conf")" == 'unrelated tmux' ]] || \
  fail 'resolved-elsewhere legacy target changed'
pass

printf 'PASS: %s Stage 3 generalized deployment test groups\n' "$TEST_COUNT"
