#!/usr/bin/env bash
# Lean Git area: native additive behavior and Ubuntu layered deployment.

set -Eeuo pipefail
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

TEST_GIT_USER_NAME='Git Fixture User'
TEST_GIT_USER_EMAIL='git-fixture@example.com'
fake_bin="$TEST_ROOT/bin"
install_fake_stow "$fake_bin"
CAPTURE_PATH_PREFIX="$fake_bin"

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

# Ubuntu deploys baseline, dormant GitHub capability, personal layer, private
# identity, and one guarded include block. Package links never create v2 state.
home="$(new_home ubuntu)"
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
state="$home/.local/state/dotfiles/v2/git.json"
assert_file "$state"
jq -e '.area == "git" and .profile == "ubuntu" and (.attachments | keys) == [".gitconfig"]' "$state" >/dev/null ||
  fail 'Git v2 state does not contain only attachment ownership'
[[ -L "$home/.config/git/config" && -L "$home/.config/dotfiles/personal/git.conf" &&
  -L "$home/.config/dotfiles/git/github-vps.conf" &&
  -L "$home/.local/bin/gh" &&
  -L "$home/.local/share/dotfiles/bin/dotfiles-github-auth" ]] || fail 'Ubuntu Git links are missing'
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
[[ ! -e "$home/.config/dotfiles/git/github-vps.conf" &&
  ! -e "$home/.local/bin/gh" &&
  ! -e "$home/.local/share/dotfiles/bin/dotfiles-github-auth" ]] || fail 'native Git deployed Ubuntu-only payloads'
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

# A host-owned gh path blocks the Git area before partial deployment.
home="$(new_home gh-collision)"
mkdir -p "$home/.local/bin"
printf 'host-owned\n' > "$home/.local/bin/gh"
expect_failure 'collision' "$home" "$ubuntu" "$DOTFILES" apply git
[[ "$(< "$home/.local/bin/gh")" == host-owned && ! -e "$home/.config/git/config" ]] ||
  fail 'gh collision refusal changed HOME or partially deployed Git'
pass

# The optional host-local layer loads after personal config and before identity.
home="$(new_home local-layer)"
mkdir -p "$home/.config/dotfiles/local"
cat > "$home/.config/dotfiles/local/git.conf" <<'EOF'
[user]
	name = Host Local User
[credential]
	helper = cache
EOF
chmod 0640 "$home/.config/dotfiles/local/git.conf"
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
[[ "$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --get credential.helper)" == cache ]] ||
  fail 'host-local Git layer was not loaded'
[[ "$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --get user.name)" == "$TEST_GIT_USER_NAME" ]] ||
  fail 'identity did not load after the host-local Git layer'
expect_success "$home" "$ubuntu" "$DOTFILES" check git
expect_success "$home" "$ubuntu" "$DOTFILES" remove git
assert_file "$home/.config/dotfiles/local/git.conf"
pass

# Present host-local config must be a safe, valid user-owned file.
home="$(new_home unsafe-local-mode)"
mkdir -p "$home/.config/dotfiles/local"
printf '[credential]\n\thelper = cache\n' > "$home/.config/dotfiles/local/git.conf"
chmod 0664 "$home/.config/dotfiles/local/git.conf"
expect_failure 'group- or other-writable' "$home" "$ubuntu" "$DOTFILES" apply git
home="$(new_home unsafe-local-link)"
mkdir -p "$home/.config/dotfiles/local"
printf '[credential]\n\thelper = cache\n' > "$home/outside"
ln -s "$home/outside" "$home/.config/dotfiles/local/git.conf"
expect_failure 'regular non-symlink' "$home" "$ubuntu" "$DOTFILES" apply git
home="$(new_home invalid-local-syntax)"
mkdir -p "$home/.config/dotfiles/local"
printf '[broken\n' > "$home/.config/dotfiles/local/git.conf"
expect_failure 'not valid Git configuration' "$home" "$ubuntu" "$DOTFILES" apply git
pass

# The retained local identity cannot become a credential or include layer.
for forbidden in credential include includeIf; do
  home="$(new_home "identity-$forbidden")"
  cat > "$home/.gitconfig.local" <<EOF
[user]
	name = Existing User
	email = existing@example.com
[$forbidden "fixture"]
	helper = cache
EOF
  chmod 0600 "$home/.gitconfig.local"
  case "$forbidden" in
    credential) expect_failure 'identity-only' "$home" "$ubuntu" "$DOTFILES" apply git ;;
    *) expect_failure 'ambiguous identity include' "$home" "$ubuntu" "$DOTFILES" apply git ;;
  esac
done
pass

# Activation requires the managed marker origin, fixed backend, exact helper
# chains, useHttpPath, and fail-closed HTTP routing.
ubuntu_without_gh="$(make_host git-ubuntu-without-gh linux ubuntu 24.04)"
home="$(new_home active-without-gh)"
mkdir -p "$home/.config/dotfiles/local"
cat > "$home/.config/dotfiles/local/git.conf" <<'EOF'
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
EOF
expect_failure 'requires fixed /usr/bin/gh' "$home" "$ubuntu_without_gh" "$DOTFILES" apply git

printf '#!/usr/bin/env bash\nexit 0\n' > "$ubuntu/usr/bin/gh"
chmod 0755 "$ubuntu/usr/bin/gh"
home="$(new_home active)"
mkdir -p "$home/.config/dotfiles/local"
cat > "$home/.config/dotfiles/local/git.conf" <<'EOF'
[credential]
	helper = cache
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
EOF
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
origin="$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --show-origin --get dotfiles.github-vps.enabled)"
[[ "$origin" == file:"$home/.config/dotfiles/git/github-vps.conf"$'\t'true ]] || fail 'active marker origin is not exact'
mapfile -t helpers < <(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --get-all credential.https://github.com.helper)
[[ "${#helpers[@]}" == 2 && -z "${helpers[0]}" && "${helpers[1]}" == '!~/.local/share/dotfiles/bin/dotfiles-github-auth' ]] ||
  fail 'active HTTPS helper chain is not exact'
[[ "$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --get credential.https://github.com.useHttpPath)" == true ]] ||
  fail 'active HTTPS useHttpPath is absent'
if printf 'protocol=http\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' |
  HOME="$home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git credential fill > "$TEST_ROOT/http-output" 2> "$TEST_ROOT/http-errors"; then
  fail 'HTTP GitHub credentials did not fail closed'
fi
! grep -q '^password=' "$TEST_ROOT/http-output" || fail 'HTTP denial returned a credential'
if printf 'protocol=https\nhost=github.com\npath=unknown/private\n\n' |
  HOME="$home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git credential fill > "$TEST_ROOT/unknown-output" 2> "$TEST_ROOT/unknown-errors"; then
  fail 'unknown GitHub route fell through or prompted'
fi
! grep -q '^password=' "$TEST_ROOT/unknown-output" || fail 'unknown GitHub route returned a credential'
expect_success "$home" "$ubuntu" "$DOTFILES" check git
printf '\n[credential]\n\thelper = store\n' >> "$home/.config/dotfiles/local/git.conf"
expect_failure 'helper after the managed reset/router' "$home" "$ubuntu" "$DOTFILES" check git
cat > "$home/.config/dotfiles/local/git.conf" <<'EOF'
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
EOF
local_hash="$(sha256sum "$home/.config/dotfiles/local/git.conf")"
expect_failure 'deactivate GitHub VPS access' "$home" "$ubuntu" "$DOTFILES" remove git
[[ "$(sha256sum "$home/.config/dotfiles/local/git.conf")" == "$local_hash" &&
  -L "$home/.config/dotfiles/git/github-vps.conf" ]] || fail 'active Git removal refusal changed host config or deployment'
: > "$home/.config/dotfiles/local/git.conf"
expect_success "$home" "$ubuntu" "$DOTFILES" remove git
assert_file "$home/.config/dotfiles/local/git.conf"
pass

# Alternate marker origins and post-activation helper additions are rejected.
home="$(new_home wrong-marker)"
mkdir -p "$home/.config/dotfiles/local"
printf '[dotfiles "github-vps"]\n\tenabled = true\n' > "$home/.config/dotfiles/local/git.conf"
expect_failure 'must be true and originate' "$home" "$ubuntu" "$DOTFILES" apply git
home="$(new_home altered-chain)"
mkdir -p "$home/.config/dotfiles/local"
cat > "$home/.config/dotfiles/local/git.conf" <<'EOF'
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
[credential "https://github.com"]
	helper = cache
EOF
expect_failure 'unexpected credential.https://github.com.helper chain' "$home" "$ubuntu" "$DOTFILES" apply git
pass

# Included, later generic, and selected/narrow URL helpers cannot survive the
# managed reset/router. Every selected repository and protocol is modeled.
for section in \
  https://github.com/MatthewssSmith1/dotfiles \
  http://github.com/MatthewssSmith1/dotfiles \
  https://github.com/mimir-db/mimir-db \
  http://github.com/mimir-db/mimir-db \
  https://github.com/mimir-db/mimir-db-v0 \
  http://github.com/mimir-db/mimir-db-v0; do
  fixture_name="${section//[^A-Za-z0-9]/-}"
  home="$(new_home "selected-helper-$fixture_name")"
  mkdir -p "$home/.config/dotfiles/local"
  cat > "$home/.config/dotfiles/local/git.conf" <<EOF
[credential "$section"]
	helper = store
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
EOF
  expect_failure 'additional helper applicable' "$home" "$ubuntu" "$DOTFILES" apply git
done
home="$(new_home included-helper)"
mkdir -p "$home/.config/dotfiles/local"
cat > "$home/.config/dotfiles/local/late.conf" <<'EOF'
[credential]
	helper = store
EOF
cat > "$home/.config/dotfiles/local/git.conf" <<'EOF'
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
[include]
	path = ~/.config/dotfiles/local/late.conf
EOF
expect_failure 'helper after the managed reset/router' "$home" "$ubuntu" "$DOTFILES" apply git
pass

# Active checks reject a helper override in the repository being inventoried.
home="$(new_home repository-override)"
mkdir -p "$home/.config/dotfiles/local" "$home/worktree"
printf '[include]\n\tpath = ~/.config/dotfiles/git/github-vps.conf\n' > "$home/.config/dotfiles/local/git.conf"
git -C "$home/worktree" init -q
git -C "$home/worktree" config credential.helper store
if output="$(cd "$home/worktree" && HOME="$home" PATH="$CAPTURE_PATH_PREFIX:$PATH" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$ubuntu" GIT_USER_NAME="$TEST_GIT_USER_NAME" GIT_USER_EMAIL="$TEST_GIT_USER_EMAIL" \
  "$DOTFILES" apply git 2>&1)"; then
  fail 'repository-local credential helper override was accepted'
fi
assert_contains "$output" 'repository-local credential helper override requires explicit review'
home="$(new_home repository-url-override)"
mkdir -p "$home/.config/dotfiles/local" "$home/worktree"
printf '[include]\n\tpath = ~/.config/dotfiles/git/github-vps.conf\n' > "$home/.config/dotfiles/local/git.conf"
git -C "$home/worktree" init -q
expect_success "$home" "$ubuntu" "$DOTFILES" apply git
git -C "$home/worktree" config credential.https://github.com/mimir-db/mimir-db.helper store
if output="$(cd "$home/worktree" && HOME="$home" PATH="$CAPTURE_PATH_PREFIX:$PATH" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$ubuntu" GIT_USER_NAME="$TEST_GIT_USER_NAME" GIT_USER_EMAIL="$TEST_GIT_USER_EMAIL" \
  "$DOTFILES" check git 2>&1)"; then
  fail 'repository-local URL credential helper override was accepted'
fi
assert_contains "$output" 'repository-local credential helper override requires explicit review'
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
expect_failure 'GIT_CONFIG_PARAMETERS' "$home" "$ubuntu" env GIT_CONFIG_PARAMETERS="'x.y=z'" "$DOTFILES" check git
expect_failure 'GIT_CONFIG_KEY_0' "$home" "$ubuntu" env GIT_CONFIG_KEY_0=x.y "$DOTFILES" check git
assert_empty_home "$home"
pass

printf 'PASS: %s lean Git test groups\n' "$TEST_COUNT"
