#!/usr/bin/env bash
# Deployment engine behavior: the generic engine driven through bootstrap over
# synthetic areas, then the startup-file attachment and transaction primitives
# exercised directly against lib/.

set -Eeuo pipefail

unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

# ===========================================================================
# Generic deployment engine over synthetic areas, driven through bootstrap.
# ===========================================================================

# Fake optional shell tools so area preflights see them; exported for direct
# bootstrap invocations and mirrored into capture runs via CAPTURE_PATH_PREFIX.
TEST_BIN="$TEST_ROOT/bin"
mkdir "$TEST_BIN"
for command_name in eza bat fdfind fzf rg zoxide; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_BIN/$command_name"
  chmod +x "$TEST_BIN/$command_name"
done
export PATH="$TEST_BIN:$PATH"
CAPTURE_PATH_PREFIX="$TEST_BIN"

# Additional fixture payloads live only in these test-time repo copies.
# Production areas.tsv now marks every area ready; flipping tmux/nvim back to
# framework deliberately reconstructs a mixed-readiness world so these tests
# exercise the readiness gating mechanism. The fixture is intentional, not
# stale.
make_engine_fixture() {
  local name="$1"
  shift
  local fixture area bash_fixture=false tmux_fixture=false zsh_fixture=false
  fixture="$(copy_repo_fixture "$name")"
  set_area_status "$fixture" tmux framework
  set_area_status "$fixture" nvim framework
  if [[ "$name" != real-baselines && "$name" != default-ready ]]; then
    for area in starship tmux nvim; do
      rm -rf -- "$fixture/packages/upstream/$area"
      mkdir -p -- "$fixture/packages/upstream/$area"
      printf 'Placeholder for isolated Stage 3 fixture.\n' > \
        "$fixture/packages/upstream/$area/.empty-package"
      printf '^/\\.empty-package$\n' > "$fixture/packages/upstream/$area/.stow-local-ignore"
    done
    # Production populated every tmux layer. Engine fixtures use only payloads
    # added explicitly below, preserving their generic-engine scope.
    for package in generic/tmux wsl/tmux common/tmux; do
      rm -rf -- "$fixture/packages/$package"
      mkdir -p -- "$fixture/packages/$package"
      printf 'Placeholder for isolated Stage 3 fixture.\n' > "$fixture/packages/$package/.empty-package"
      printf '^/\\.empty-package$\n' > "$fixture/packages/$package/.stow-local-ignore"
    done
  fi
  for area in "$@"; do
    set_area_status "$fixture" "$area" ready
    [[ "$area" != bash ]] || bash_fixture=true
    [[ "$area" != tmux ]] || tmux_fixture=true
    [[ "$area" != zsh ]] || zsh_fixture=true
  done
  if [[ "$bash_fixture" == true ]]; then
    cat >> "$fixture/lib/areas/bash.sh" <<'SCRIPT'

# Engine fixtures exercise the generic engine, not the later Bash lifecycle.
preflight_bash() { preflight_generic bash; }
apply_bash() { apply_generic; }
remove_bash() { remove_generic bash; }
SCRIPT
  fi
  if [[ "$tmux_fixture" == true ]]; then
    cat >> "$fixture/lib/areas/tmux.sh" <<'SCRIPT'

# Engine fixtures exercise the generic engine, not the later tmux lifecycle.
preflight_tmux() { preflight_generic tmux; }
apply_tmux() { apply_generic; }
remove_tmux() { remove_generic tmux; }
SCRIPT
  fi
  if [[ "$zsh_fixture" == true ]]; then
    cat >> "$fixture/lib/areas/zsh.sh" <<'SCRIPT'

# Engine fixtures exercise the generic engine, not the later zsh lifecycle.
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

wsl_host="$(make_host stage3-wsl wsl)"

# Committed statics: the area manifest, the canonical profile closure table,
# populated snapshots and package layers.
expected_areas='schema|1
area|git|ready
area|bash|ready
area|tmux|ready
area|nvim|ready
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
for package in generic/git; do
  root="$REPO_DIR/packages/$package"
  [[ -d "$root" && ! -L "$root" ]] || fail "missing committed package root: packages/$package"
  entries="$(cd "$root" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$entries" == './.empty-package ./.stow-local-ignore ' ]] || \
    fail "packages/$package is not an empty placeholder: $entries"
done
[[ -f "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" ]] || \
  fail 'packages/common/nvim is missing the shared personal source'
[[ -x "$REPO_DIR/packages/generic/nvim/.local/share/dotfiles/bin/nvim-restore" ]] || \
  fail 'packages/generic/nvim is missing the restore helper'
[[ ! -e "$REPO_DIR/packages/common/nvim/.empty-package" && \
  ! -e "$REPO_DIR/packages/generic/nvim/.empty-package" ]] || \
  fail 'materialized Neovim packages retain placeholders'
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
for package in upstream/starship upstream/tmux; do
  root="$REPO_DIR/packages/$package"
  [[ -d "$root" && ! -L "$root" ]] || fail "missing populated package root: packages/$package"
  [[ -z "$(find "$root" -name .empty-package -o -name .stow-local-ignore)" ]] || \
    fail "packages/$package retains framework markers"
  [[ -n "$(find "$root" -type f -print -quit)" ]] || fail "packages/$package has no snapshot payload"
done
[[ "$(< "$REPO_DIR/packages/upstream/nvim/.stow-local-ignore")" == '^/\.stow-local-ignore$' ]] || \
  fail 'packages/upstream/nvim does not have the exact materialized hidden-file Stow policy'
[[ ! -e "$REPO_DIR/packages/upstream/nvim/.empty-package" ]] || \
  fail 'packages/upstream/nvim retains its framework placeholder'
reference_root="$REPO_DIR/packages/upstream/reference"
[[ -d "$reference_root/omarchy/default/bash" && -d "$reference_root/omarchy/themes/tokyo-night" ]] || \
  fail 'packages/upstream/reference does not contain the Stage 4 reference snapshot roots'
pass

# Ready-flipped fixtures deploy the real Stage 4 XDG baselines and retain exact
# state ownership; readiness remains a production-stage decision.
fixture="$(make_engine_fixture real-baselines bash tmux)"
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

# A focused historical fixture proves the Git/Bash/zsh default-ready selection
# without invoking later area behavior.
home="$(new_home framework-refusal)"
expect_failure "unknown area 'python'" "$home" "$wsl_host" "$BOOTSTRAP" --area python

default_fixture="$(make_engine_fixture default-ready bash zsh)"
expect_success "$home" "$wsl_host" "$default_fixture/bootstrap.sh" --check
assert_contains "$TEST_OUTPUT" "area 'git' preflight passed"
assert_contains "$TEST_OUTPUT" "area 'bash' preflight passed"
assert_contains "$TEST_OUTPUT" "area 'zsh' preflight passed"
assert_not_contains "$TEST_OUTPUT" "area 'tmux'"
assert_not_contains "$TEST_OUTPUT" "area 'nvim'"
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
fixture="$(make_engine_fixture independent bash tmux)"
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
fixture="$(make_engine_fixture ordering bash)"
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
fixture="$(make_engine_fixture rollback-failure bash tmux)"
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
fixture="$(make_engine_fixture omitted bash tmux)"
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
fixture="$(make_engine_fixture profile-change bash tmux)"
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
fixture="$(make_engine_fixture bad-closure bash)"
sed -i 's|^bash .*$|bash missing/bash|' "$fixture/profiles/wsl.conf"
home="$(new_home bad-closure)"
expect_failure 'missing package root' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area bash
assert_empty_home "$home"
expect_failure 'missing package root' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area git
assert_empty_home "$home"
pass

# A moved checkout is reconciled for a generic area from recorded ownership.
fixture="$(make_engine_fixture moved-one bash)"
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
fixture="$(make_engine_fixture states bash)"
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
fixture="$(make_engine_fixture duplicate-targets bash)"
add_payload "$fixture" generic/bash '.config/dotfiles/fixture/shared' 'generic'
add_payload "$fixture" common/bash '.config/dotfiles/fixture/shared' 'common'
home="$(new_home duplicate-targets)"
expect_failure 'duplicate payload target' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check --area bash
assert_empty_home "$home"
fixture="$(make_engine_fixture shared-target bash tmux)"
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
fixture="$(make_engine_fixture legacy bash tmux)"
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
fixture="$(make_engine_fixture legacy-resolved tmux)"
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

# ===========================================================================
# Startup-file attachment engine primitives, exercised directly against lib/.
# ===========================================================================

# These groups run engine functions in-process, so expect_failure takes a
# direct command instead of the harness bootstrap-capture signature.
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

printf 'PASS: %s engine test groups\n' "$TEST_COUNT"
