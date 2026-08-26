#!/usr/bin/env bash
# Lean Git area: native additive behavior and Ubuntu layered deployment.

set -Eeuo pipefail
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

TEST_GIT_USER_NAME='Git Fixture User'
TEST_GIT_USER_EMAIL='git-fixture@example.com'
fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
export FAKE_STOW_TRACE
CAPTURE_PATH_PREFIX="$fake_bin"
: > "$FAKE_STOW_TRACE"

prepare_native() {
  local root="$1" home="$2"
  mkdir -p "$root/usr/share/omarchy" "$home/.config/git"
  printf '4.0.0.alpha\n' > "$root/usr/share/omarchy/version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/usr/bin/omarchy"
  chmod 0755 "$root/usr/bin/omarchy"
  record_pacman_ownership "$root" 'omarchy 4.0.1-1' /usr/share/omarchy/version /usr/bin/omarchy
  cp "$REPO_DIR/packages/upstream/git/.config/git/config" "$home/.config/git/config"
}

ubuntu="$(make_host git-ubuntu linux ubuntu 24.04)"
native="$(make_host git-native linux omarchy 4)"

# Ubuntu deploys baseline, explicit empty adapter, personal layer, private
# identity, and one guarded include block. Package links never create v2 state.
home="$(new_home ubuntu)"
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
state="$home/.local/state/dotfiles/v2/git.json"
assert_file "$state"
jq -e '.area == "git" and .profile == "ubuntu" and (.attachments | keys) == [".gitconfig"]' "$state" >/dev/null ||
  fail 'Git v2 state does not contain only attachment ownership'
[[ -L "$home/.config/git/config" && -L "$home/.config/dotfiles/personal/git.conf" ]] || fail 'Ubuntu Git links are missing'
[[ ! -e "$home/.config/dotfiles/local/git.conf" ]] || fail 'retired migration-local Git file was created'
assert_file "$home/.gitconfig.local"
[[ "$(stat -c %a -- "$home/.gitconfig.local")" == 600 ]] || fail 'identity mode is not 0600'
[[ "$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --get init.defaultBranch)" == main ]] ||
  fail 'personal Git layer did not override the baseline'
expect_success "$home" "$ubuntu" "$DOTFILES" check git
identity_hash="$(sha256sum "$home/.gitconfig.local")"
expect_success "$home" "$ubuntu" "$DOTFILES" remove git
[[ ! -e "$state" && ! -e "$home/.gitconfig" && ! -e "$home/.config/git/config" ]] || fail 'Git removal retained managed ownership'
[[ "$(sha256sum "$home/.gitconfig.local")" == "$identity_hash" ]] || fail 'Git removal changed host identity'
pass

# Native baseline remains a regular package-owned file while only common/git
# and the exact include attachment are managed.
home="$(new_home native)"
prepare_native "$native" "$home"
baseline_hash="$(sha256sum "$home/.config/git/config")"
expect_success "$home" "$native" "$DOTFILES" apply git
[[ -f "$home/.config/git/config" && ! -L "$home/.config/git/config" ]] || fail 'native baseline was replaced'
[[ "$(sha256sum "$home/.config/git/config")" == "$baseline_hash" ]] || fail 'native baseline bytes changed'
[[ "$(< "$FAKE_STOW_TRACE")" == *'stow|false|git'* ]] || fail 'common Git package was not deployed'
expect_success "$home" "$native" "$DOTFILES" remove git
[[ "$(sha256sum "$home/.config/git/config")" == "$baseline_hash" ]] || fail 'native removal changed baseline'
pass

# Existing identity is retained, protected to 0600, and never recorded as owned.
home="$(new_home identity)"
printf '[user]\n\tname = Existing User\n\temail = existing@example.com\n' > "$home/.gitconfig.local"
chmod 0644 "$home/.gitconfig.local"
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
[[ "$(stat -c %a -- "$home/.gitconfig.local")" == 600 ]] || fail 'existing identity was not protected'
[[ "$(git config --file "$home/.gitconfig.local" --get user.name)" == 'Existing User' ]] || fail 'environment replaced existing identity'
! jq -e '.attachments[".gitconfig.local"]' "$home/.local/state/dotfiles/v2/git.json" >/dev/null || fail 'identity was recorded as owned'
expect_success "$home" "$ubuntu" "$DOTFILES" remove git
pass

# Exact guarded removal preserves unrelated bytes and refuses modified blocks.
home="$(new_home guarded)"
printf '# host prefix\n' > "$home/.gitconfig"
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
printf '# host suffix\n' >> "$home/.gitconfig"
expect_success "$home" "$ubuntu" "$DOTFILES" remove git
[[ "$(< "$home/.gitconfig")" == $'# host prefix\n# host suffix' ]] || fail 'guarded removal changed unrelated bytes'
home="$(new_home modified)"
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
sed -i 's|path = ~/.gitconfig.local|path = /tmp/changed|' "$home/.gitconfig"
expect_failure 'partial, malformed' "$home" "$ubuntu" "$DOTFILES" remove git
assert_file "$home/.local/state/dotfiles/v2/git.json"
pass

# Retired v1 Git ownership is never adopted by the lean area.
home="$(new_home v1)"
mkdir -p "$home/.local/state/dotfiles/v1"
printf '{}\n' > "$home/.local/state/dotfiles/v1/git.json"
expect_failure "legacy v1 deployment state exists for lean area 'git'" "$home" "$ubuntu" "$DOTFILES" apply git
[[ ! -e "$home/.local/state/dotfiles/v2" ]] || fail 'v1 refusal wrote lean state'
pass

# Check remains non-mutating and foreign Git environment is rejected.
home="$(new_home check)"
expect_failure "lean ownership state is absent for area 'git'" "$home" "$ubuntu" "$DOTFILES" check git
assert_empty_home "$home"
expect_failure 'GIT_CONFIG_GLOBAL' "$home" "$ubuntu" env GIT_CONFIG_GLOBAL=/dev/null "$DOTFILES" check git
assert_empty_home "$home"
pass

printf 'PASS: %s lean Git test groups\n' "$TEST_COUNT"
