#!/usr/bin/env bash
# Lean tools/mise package policy, diagnostics, and lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
export FAKE_STOW_TRACE
CAPTURE_PATH_PREFIX="$fake_bin"
: > "$FAKE_STOW_TRACE"
ubuntu="$(make_host tools-ubuntu linux ubuntu 24.04)"
native="$(make_host tools-native linux omarchy 4)"
mkdir -p "$native/usr/share/omarchy"
printf '4.0.0.alpha\n' > "$native/usr/share/omarchy/version"
printf '#!/usr/bin/env bash\nexit 0\n' > "$native/usr/bin/omarchy"
chmod 0755 "$native/usr/bin/omarchy"
record_pacman_ownership "$native" 'omarchy 4.0.1-1' /usr/share/omarchy/version /usr/bin/omarchy

make_tool() {
  local name="$1" output="$2"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$output" > "$fake_bin/$name"
  chmod 0755 "$fake_bin/$name"
}

# Apply is configuration-only even when mise and selected tools are absent.
home="$(new_home apply)"
expect_success "$home" "$ubuntu" "$DOTFILES" apply tools
[[ -L "$home/.config/mise/conf.d/20-dotfiles-tools.toml" && -L "$home/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml" ]] ||
  fail 'Ubuntu mise fragments were not deployed'
[[ ! -e "$home/.local/bin/dotfiles-omarchy-prune" ]] || fail 'Ubuntu deployed the Omarchy prune command'
[[ ! -e "$home/.local/state/dotfiles/v2" ]] || fail 'package-only tools wrote ownership state'
[[ ! -e "$home/network-attempted" ]] || fail 'tools apply attempted installation'
pass

# Missing checks are offline and print every explicit selector/manual action.
export DOTFILES_TEST_HIDE_COMMANDS='mise node pnpm wt'
expect_failure 'mise is absent' "$home" "$ubuntu" "$DOTFILES" check tools
assert_contains "$TEST_OUTPUT" 'mise install node@lts'
assert_contains "$TEST_OUTPUT" 'mise install aqua:pnpm/pnpm@11.13.1'
assert_contains "$TEST_OUTPUT" 'mise install aqua:max-sixty/worktrunk@0.68.0'
unset DOTFILES_TEST_HIDE_COMMANDS
pass

# Selected fake tools satisfy the exact accepted checks.
make_tool mise 'mise 2026.7.7'
make_tool node 'v24.0.0'
make_tool pnpm '11.13.1'
make_tool wt 'worktrunk 0.68.0'
expect_success "$home" "$ubuntu" "$DOTFILES" check tools
pass

# Native tools deploy the shared launcher and native prune command without
# executing either payload. Removal converges from the detected profile.
cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/prune-unexpected.trace"
exit 99
SCRIPT
chmod 0755 "$fake_bin/omarchy"
native_home="$(new_home native)"
expect_success "$native_home" "$native" "$DOTFILES" apply tools
[[ -L "$native_home/.local/bin/dotfiles" && -L "$native_home/.local/bin/dotfiles-omarchy-prune" ]] ||
  fail 'native tools launchers were not deployed'
expect_success "$native_home" "$native" "$DOTFILES" check tools
expect_success "$native_home" "$native" "$DOTFILES" remove tools
[[ ! -e "$native_home/.local/bin/dotfiles" && ! -e "$native_home/.local/bin/dotfiles-omarchy-prune" ]] ||
  fail 'native tools removal retained launchers'
expect_success "$native_home" "$native" "$DOTFILES" remove tools
[[ ! -e "$native_home/prune-unexpected.trace" ]] || fail 'tools lifecycle executed the prune command'
pass

# The prune command validates invocation and Omarchy version before mutation.
prune="$REPO_DIR/packages/omarchy/tools/.local/bin/dotfiles-omarchy-prune"
prune_home="$(new_home prune)"
if TEST_OUTPUT="$(HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" unexpected 2>&1)"; then
  fail 'prune command accepted arguments'
else
  assert_contains "$TEST_OUTPUT" 'usage: dotfiles-omarchy-prune'
fi
[[ ! -e "$prune_home/prune-unexpected.trace" ]] || fail 'argument rejection invoked Omarchy'

missing_bin="$TEST_ROOT/missing-omarchy-bin"
mkdir "$missing_bin"
if TEST_OUTPUT="$(HOME="$prune_home" PATH="$missing_bin" /usr/bin/bash "$prune" 2>&1)"; then
  fail 'prune command accepted a host without Omarchy'
else
  assert_contains "$TEST_OUTPUT" 'requires native Omarchy v4'
fi

cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$*" == version ]] && { printf '5.0.0-1\n'; exit 0; }
printf '%s\n' "$*" >> "$HOME/prune-unexpected.trace"
exit 99
SCRIPT
chmod 0755 "$fake_bin/omarchy"
if TEST_OUTPUT="$(HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" 2>&1)"; then
  fail 'prune command accepted unsupported Omarchy'
else
  assert_contains "$TEST_OUTPUT" 'requires native Omarchy v4, found 5.0.0-1'
fi
[[ ! -e "$prune_home/prune-unexpected.trace" ]] || fail 'version rejection mutated Omarchy'
pass

# Successful runs preserve argument boundaries, disable notifications, avoid
# stdin, and converge without touching representative user data.
cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" == version ]]; then
  printf '4.0.1-1\n'
  exit 0
fi
printf '%s|%s' "${OMARCHY_REMOVE_NOTIFY:-unset}" "$#" >> "$HOME/prune.trace"
printf '|%s' "$@" >> "$HOME/prune.trace"
printf '\n' >> "$HOME/prune.trace"
SCRIPT
chmod 0755 "$fake_bin/omarchy"
mkdir -p "$prune_home/.config/moonlight" "$prune_home/.config/localsend" \
  "$prune_home/.cache/localsend" "$prune_home/.local/share/applications"
printf 'moonlight-data\n' > "$prune_home/.config/moonlight/config.ini"
printf 'localsend-data\n' > "$prune_home/.config/localsend/settings.json"
printf 'cache-data\n' > "$prune_home/.cache/localsend/session"
printf 'unrelated-launcher\n' > "$prune_home/.local/share/applications/Keep.desktop"
data_hash="$(sha256sum "$prune_home/.config/moonlight/config.ini" \
  "$prune_home/.config/localsend/settings.json" "$prune_home/.cache/localsend/session" \
  "$prune_home/.local/share/applications/Keep.desktop")"
HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" </dev/null >/dev/null
HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" </dev/null >/dev/null
expected_trace=$'unset|4|pkg|drop|moonlight-qt|localsend\nfalse|3|webapp|remove|HEY\nfalse|3|webapp|remove|Basecamp\nfalse|3|webapp|remove|Zoom\nfalse|3|webapp|remove|Google Messages'
[[ "$(< "$prune_home/prune.trace")" == "$expected_trace"$'\n'"$expected_trace" ]] ||
  fail 'prune command trace is not exact or convergent'
[[ "$(sha256sum "$prune_home/.config/moonlight/config.ini" \
  "$prune_home/.config/localsend/settings.json" "$prune_home/.cache/localsend/session" \
  "$prune_home/.local/share/applications/Keep.desktop")" == "$data_hash" ]] ||
  fail 'prune command changed representative user data'
pass

# Default remove derives package-only tools from the detected profile without
# state and converges again when links are already absent.
expect_success "$home" "$ubuntu" "$DOTFILES" remove
[[ ! -e "$home/.config/mise/conf.d/20-dotfiles-tools.toml" && ! -e "$home/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml" ]] ||
  fail 'default package-only tools removal retained links'
expect_success "$home" "$ubuntu" "$DOTFILES" remove
pass

# Native common fragment has no Node/foundation selectors; Ubuntu alone owns
# the LTS fallback. Managed settings disable implicit installation and locking.
common="$REPO_DIR/packages/common/tools/.config/mise/conf.d/20-dotfiles-tools.toml"
ubuntu_fragment="$REPO_DIR/packages/ubuntu/tools/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml"
! grep -Eq '^(node|git|tmux|neovim|starship|fzf|zoxide|bat|fd|ripgrep)[[:space:]]*=' "$common" || fail 'common tools select a native foundation tool'
! grep -Rqs 'locked = true' "$REPO_DIR/packages/common/tools" "$REPO_DIR/packages/ubuntu/tools" || fail 'tools retained locked mise mode'
grep -qxF 'not_found_auto_install = false' "$common" || fail 'automatic install setting is missing'
grep -qxF 'idiomatic_version_file_enable_tools = []' "$common" || fail 'idiomatic version files are enabled'
grep -qxF 'node = "lts"' "$ubuntu_fragment" || fail 'Ubuntu Node fallback is missing'
pass

# Narrow precedence fixture models accepted mise ordering: a project-local Node
# selector overrides conf.d while the global fallback applies outside projects.
project="$TEST_ROOT/project"
mkdir "$project"
printf '[tools]\nnode = "22.14.0"\n' > "$project/mise.toml"
global_node="$(sed -n 's/^node = "\([^"]*\)"$/\1/p' "$ubuntu_fragment")"
project_node="$(sed -n 's/^node = "\([^"]*\)"$/\1/p' "$project/mise.toml")"
[[ "$global_node" == lts && "$project_node" == 22.14.0 ]] || fail 'project/global selector precedence fixture is invalid'
pass

# Area-specific v1 state refuses conversion without affecting unrelated v1 areas.
home="$(new_home v1)"
mkdir -p "$home/.local/state/dotfiles/v1"
printf '{}\n' > "$home/.local/state/dotfiles/v1/tools.json"
expect_failure "legacy v1 deployment state exists for lean area 'tools'" "$home" "$ubuntu" "$DOTFILES" apply tools
pass

printf 'PASS: %s tools/mise test groups\n' "$TEST_COUNT"
