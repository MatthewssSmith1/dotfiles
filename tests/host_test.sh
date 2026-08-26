#!/usr/bin/env bash
# Native Omarchy v4 and Ubuntu host detection/profile selection.

set -Eeuo pipefail

unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

# Host tests isolate detection/profile behavior. Seed the selected package-only
# area so lean check does not turn an otherwise valid host probe into an
# undeployed-area assertion.
new_home() {
  local name="$1" home source relative parent lexical
  home="$TEST_ROOT/home-$name"
  mkdir "$home"
  shopt -s dotglob nullglob globstar
  for source in "$REPO_DIR/packages/common/agents"/**/*; do
    [[ -f "$source" && ! -L "$source" ]] || continue
    relative="${source#"$REPO_DIR/packages/common/agents/"}"
    parent="$(dirname -- "$home/$relative")"
    mkdir -p "$parent"
    lexical="$(realpath -m -s --relative-to="$parent" -- "$source")"
    ln -s "$lexical" "$home/$relative"
  done
  shopt -u dotglob nullglob globstar
  mkdir -p "$home/.config/opencode" "$home/.claude"
  ln -s ../../.agents/AGENTS.md "$home/.config/opencode/AGENTS.md"
  ln -s ../.agents/AGENTS.md "$home/.claude/CLAUDE.md"
  printf '%s' "$home"
}

host_bin="$TEST_ROOT/host-bin"
mkdir "$host_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$host_bin/stow"
chmod 0755 "$host_bin/stow"
CAPTURE_PATH_PREFIX="$host_bin"

prepare_omarchy() {
  local root="$1" home="$2" marker="${3-4.0.0.alpha}" owner="${4-omarchy 4.0.1-1}"
  mkdir -p "$root/usr/share/omarchy" "$home/.config/git"
  printf '%s\n' "$marker" > "$root/usr/share/omarchy/version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/usr/bin/omarchy"
  chmod 0755 "$root/usr/bin/omarchy"
  record_pacman_ownership "$root" "$owner" /usr/share/omarchy/version /usr/bin/omarchy
  cp "$REPO_DIR/packages/upstream/git/.config/git/config" "$home/.config/git/config"
}

ubuntu_host="$(make_host ubuntu linux ubuntu 24.04)"
ubuntu_new_host="$(make_host ubuntu-new linux ubuntu 26.10)"
ubuntu_old_host="$(make_host ubuntu-old linux ubuntu 22.04)"
debian_host="$(make_host debian linux debian 13)"
wsl_host="$(make_host wsl wsl ubuntu 24.04)"

# Supported Ubuntu releases select only the ubuntu profile; retired names are
# rejected by the CLI rather than being interpreted as overrides.
for host in "$ubuntu_host" "$ubuntu_new_host"; do
  home="$(new_home "ubuntu-${host##*/}")"
  expect_success "$home" "$host" "$DOTFILES" check agents
  assert_contains "$TEST_OUTPUT" "selected profile 'ubuntu'"
  expect_success "$home" "$host" "$DOTFILES" check --profile ubuntu agents
  expect_failure "not allowed" "$home" "$host" "$DOTFILES" check --profile omarchy agents
done
home="$(new_home retired-overrides)"
expect_failure "invalid profile 'generic'" "$home" "$ubuntu_host" "$DOTFILES" check --profile generic agents
expect_failure "invalid profile 'wsl'" "$home" "$ubuntu_host" "$DOTFILES" check --profile wsl agents
expect_failure 'usage:' "$home" "$ubuntu_host" "$DOTFILES" --provision
expect_failure 'usage:' "$home" "$ubuntu_host" "$DOTFILES" --retire-provisioned claude-code
pass

# WSL refusal precedes every other host signal, including a complete Omarchy
# installation, and no override can make it deployable.
home="$(new_home wsl)"
expect_failure 'WSL hosts are not supported' "$home" "$wsl_host" "$DOTFILES" check agents
prepare_omarchy "$wsl_host" "$home"
printf 'ID="omarchy"\nVERSION_ID="4"\n' > "$wsl_host/etc/os-release"
expect_failure 'WSL hosts are not supported' "$home" "$wsl_host" "$DOTFILES" check --profile omarchy agents
pass

# A native v4 host requires regular system signals, ID=omarchy, and identical
# fixture pacman identities. The alpha family marker may accompany 4.0.1-1.
omarchy_host="$(make_host omarchy linux omarchy 4)"
home="$(new_home omarchy)"
prepare_omarchy "$omarchy_host" "$home"
expect_success "$home" "$omarchy_host" "$DOTFILES" check agents
assert_contains "$TEST_OUTPUT" "selected profile 'omarchy'"
assert_not_contains "$TEST_OUTPUT" 'Omarchy core package drift'
expect_success "$home" "$omarchy_host" "$DOTFILES" check --profile omarchy agents
expect_failure 'not allowed' "$home" "$omarchy_host" "$DOTFILES" check --profile ubuntu agents
[[ "$(fixture_pacman_owner "$omarchy_host" /usr/bin/omarchy)" == 'omarchy 4.0.1-1' ]] || \
  fail 'fixture package authority changed'
pass

# Family mismatch and malformed marker forms fail closed.
for record in old-family:3.8.4 malformed:four empty:'' multiline:4.0.0; do
  name="${record%%:*}"
  marker="${record#*:}"
  root="$(make_host "marker-$name" linux omarchy 4)"
  home="$(new_home "marker-$name")"
  prepare_omarchy "$root" "$home" "$marker"
  [[ "$name" != multiline ]] || printf '4.0.0\nextra\n' > "$root/usr/share/omarchy/version"
  expect_failure 'Omarchy v4 family marker' "$home" "$root" "$DOTFILES" check agents
done
pass

# A v4 marker cannot be authorized by a package from another major family.
root="$(make_host package-family linux omarchy 4)"
home="$(new_home package-family)"
prepare_omarchy "$root" "$home" 4.0.0.alpha 'omarchy 5.0.0-1'
expect_failure 'exact v4 package authority' "$home" "$root" "$DOTFILES" check agents
pass

# Missing, unsafe, and contradictory native signals are distinguished from a
# valid Ubuntu fallback.
root="$(make_host partial-version linux omarchy 4)"
home="$(new_home partial-version)"
mkdir -p "$root/usr/share/omarchy"
printf '4.0.0.alpha\n' > "$root/usr/share/omarchy/version"
expect_failure 'partial Omarchy installation' "$home" "$root" "$DOTFILES" check agents

root="$(make_host partial-command linux omarchy 4)"
home="$(new_home partial-command)"
printf '#!/usr/bin/env bash\n' > "$root/usr/bin/omarchy"
chmod 0755 "$root/usr/bin/omarchy"
expect_failure 'partial Omarchy installation' "$home" "$root" "$DOTFILES" check agents

root="$(make_host id-only linux omarchy 4)"
home="$(new_home id-only)"
expect_failure 'ID=omarchy requires native version and command signals' "$home" "$root" "$DOTFILES" check agents

root="$(make_host contradictory linux ubuntu 24.04)"
home="$(new_home contradictory)"
prepare_omarchy "$root" "$home"
expect_failure 'contradictory host signals' "$home" "$root" "$DOTFILES" check agents
pass

# Both native paths must be executable/regular non-symlinks.
for signal in version command; do
  root="$(make_host "symlink-$signal" linux omarchy 4)"
  home="$(new_home "symlink-$signal")"
  prepare_omarchy "$root" "$home"
  if [[ "$signal" == version ]]; then
    mv "$root/usr/share/omarchy/version" "$root/version.real"
    ln -s "$root/version.real" "$root/usr/share/omarchy/version"
  else
    mv "$root/usr/bin/omarchy" "$root/omarchy.real"
    ln -s "$root/omarchy.real" "$root/usr/bin/omarchy"
  fi
  expect_failure 'regular non-symlink file' "$home" "$root" "$DOTFILES" check agents
done
root="$(make_host non-executable linux omarchy 4)"
home="$(new_home non-executable)"
prepare_omarchy "$root" "$home"
chmod 0644 "$root/usr/bin/omarchy"
expect_failure 'executable regular non-symlink file' "$home" "$root" "$DOTFILES" check agents
pass

# Ownership metadata is isolated under each fixture root; missing, wrong, or
# split package identities never fall back to the developer host's /usr.
root="$(make_host owner-missing linux omarchy 4)"
home="$(new_home owner-missing)"
prepare_omarchy "$root" "$home"
rm "$root/var/lib/dotfiles-test/pacman-owners.tsv"
expect_failure 'package authority' "$home" "$root" "$DOTFILES" check agents

root="$(make_host owner-wrong linux omarchy 4)"
home="$(new_home owner-wrong)"
prepare_omarchy "$root" "$home" 4.0.0.alpha 'mise-bin 4.0.1-1'
expect_failure 'exact v4 package authority' "$home" "$root" "$DOTFILES" check agents

root="$(make_host owner-split linux omarchy 4)"
home="$(new_home owner-split)"
prepare_omarchy "$root" "$home"
printf '/usr/bin/omarchy\tomarchy 4.0.2-1\n' >> "$root/var/lib/dotfiles-test/pacman-owners.tsv"
expect_failure 'package authority' "$home" "$root" "$DOTFILES" check agents
pass

# Every selected area must pass preflight before an earlier area may write.
# Tools sorts before Agents, whose conflicting bridge supplies the late failure.
home="$(new_home aggregate-preflight)"
rm "$home/.config/opencode/AGENTS.md"
printf 'host-owned conflict\n' > "$home/.config/opencode/AGENTS.md"
expect_failure 'unrelated destination conflict' "$home" "$ubuntu_host" \
  "$DOTFILES" apply tools agents
[[ ! -e "$home/.config/mise/conf.d/20-dotfiles-tools.toml" && \
  ! -e "$home/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml" ]] || \
  fail 'an earlier area wrote before every selected area passed preflight'
pass

# Unsupported distro/version and non-Linux diagnostics remain deterministic.
home="$(new_home old-ubuntu)"
expect_failure 'unsupported Ubuntu release: 22.04' "$home" "$ubuntu_old_host" "$DOTFILES" check agents
home="$(new_home non-ubuntu)"
expect_failure 'unsupported Linux distribution: ID=debian' "$home" "$debian_host" "$DOTFILES" check agents
root="$(make_host missing-os linux ubuntu 24.04)"
rm "$root/etc/os-release"
home="$(new_home missing-os)"
expect_failure 'ID=missing VERSION_ID=missing' "$home" "$root" "$DOTFILES" check agents
root="$(make_host malformed-os linux ubuntu 24.04)"
printf 'ID="ubuntu\nVERSION_ID="24.04"\n' > "$root/etc/os-release"
home="$(new_home malformed-os)"
expect_failure 'malformed ID' "$home" "$root" "$DOTFILES" check agents
home="$(new_home non-linux)"
DOTFILES_TEST_UNAME=Darwin expect_failure 'unsupported host operating system: Darwin' \
  "$home" "$ubuntu_host" "$DOTFILES" check agents
pass

printf 'PASS: %s host/profile test groups\n' "$TEST_COUNT"
