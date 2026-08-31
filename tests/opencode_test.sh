#!/usr/bin/env bash
# Optional OpenCode profile overlays, native coexistence, and lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
export FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
: > "$FAKE_STOW_TRACE"
CAPTURE_PATH_PREFIX="$fake_bin"
ubuntu="$(make_host opencode-ubuntu linux ubuntu 24.04)"
native="$(make_host opencode-native linux omarchy 4)"
mkdir -p "$native/usr/share/omarchy"
printf '4.0.0\n' > "$native/usr/share/omarchy/version"
printf '#!/usr/bin/env bash\nexit 0\n' > "$native/usr/bin/omarchy"
chmod 0755 "$native/usr/bin/omarchy"
record_pacman_ownership "$native" 'omarchy 4.0.0-1' /usr/share/omarchy/version /usr/bin/omarchy

seed_native_home() {
  local home="$1"
  mkdir -p "$home/.local/bin" "$home/.config/opencode"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$OPENCODE_CONFIG" "$OPENCODE_TUI_CONFIG"\nprintf "<%%s>\\n" "$@"\nexit "${FAKE_OPENCODE_STATUS:-0}"\n' > "$home/.local/bin/opencode"
  chmod 0755 "$home/.local/bin/opencode"
  printf '{"$schema":"https://opencode.ai/config.json","autoupdate":false}\n' > "$home/.config/opencode/opencode.json"
  printf '{"theme":"system"}\n' > "$home/.config/opencode/tui.json"
  printf '{"plugin":["./herdr-tui-session.js"]}\n' > "$home/.config/opencode/tui.jsonc"
  printf 'export default {}\n' > "$home/.config/opencode/herdr-tui-session.js"
  printf 'instructions\n' > "$home/.config/opencode/AGENTS.md"
}

assert_managed_links() {
  local home="$1" path
  for path in \
    .config/dotfiles/opencode/personal.jsonc \
    .config/dotfiles/opencode/tui.jsonc \
    .config/dotfiles/opencode/work.jsonc \
    .local/bin/opencode-personal \
    .local/bin/opencode-work \
    .local/share/dotfiles/bin/opencode-launch; do
    [[ -L "$home/$path" ]] || fail "OpenCode managed link is absent: $path"
  done
}

# Profiles retain reviewed boundaries and shared TUI bindings.
personal_profile="$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/personal.jsonc"
work_profile="$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/work.jsonc"
tui_profile="$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/tui.jsonc"
personal_provider_hash='e986bec224382f24e2334b152cdf23ffaf13ccefde895e3fe4c94d2702d3bce8'
jq -e '
  .plugin == ["opencode-openai-codex-auth@4.4.0"] and
  .agent.compaction == {"model":"openai/gpt-5.6-terra","variant":"low"} and
  (.provider.openai.models | keys) == [
    "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-max",
    "gpt-5.1-codex-mini", "gpt-5.2", "gpt-5.2-codex"
  ]
' "$personal_profile" >/dev/null || fail 'personal OpenCode Codex OAuth profile drifted'
[[ "$(jq -cS '.provider.openai' "$personal_profile" | sha256sum | cut -d ' ' -f1)" == "$personal_provider_hash" ]] ||
  fail 'personal OpenCode provider catalog drifted'
jq -e '
  (has("plugin") | not) and
  (.provider | keys) == ["truefoundry-gateway", "truefoundry-gateway-openai"] and
  .enabled_providers == ["truefoundry-gateway", "truefoundry-gateway-openai"] and
  .agent.compaction == {
    "model":"truefoundry-gateway-openai/codex-group/gpt-5.6-terra",
    "variant":"low"
  }
' "$work_profile" >/dev/null || fail 'work OpenCode profile boundary drifted'
jq -e '.keybinds == {
  "app_exit":"<leader>q",
  "input_clear":"<leader>k",
  "prompt_stash":"ctrl+s",
  "prompt_stash_pop":"ctrl+y",
  "input_newline":"ctrl+return,shift+return,alt+return,ctrl+j"
}' "$tui_profile" >/dev/null || fail 'shared OpenCode TUI bindings drifted'
pass

# Both hosts deploy six links while preserving native and integration files.
for profile_host in "$ubuntu" "$native"; do
  home="$(new_home "apply-${profile_host##*/}")"
  seed_native_home "$home"
  mkdir "$TEST_ROOT/reference-${profile_host##*/}"
  cp -a "$home/.local/bin/opencode" "$TEST_ROOT/reference-${profile_host##*/}/opencode"
  cp -a "$home/.config/opencode/." "$TEST_ROOT/reference-${profile_host##*/}/config"
  install_network_sentinels "$home"
  CAPTURE_PATH_PREFIX="$home/fake-bin:$fake_bin"
  expect_success "$home" "$profile_host" "$DOTFILES" apply opencode
  assert_managed_links "$home"
  [[ -f "$home/.local/bin/opencode" && ! -L "$home/.local/bin/opencode" ]] ||
    fail 'OpenCode replaced the native executable'
  assert_same "$home/.local/bin/opencode" "$TEST_ROOT/reference-${profile_host##*/}/opencode"
  for path in opencode.json tui.json tui.jsonc herdr-tui-session.js AGENTS.md; do
    assert_same "$home/.config/opencode/$path" "$TEST_ROOT/reference-${profile_host##*/}/config/$path"
  done
  [[ ! -e "$home/.local/state/dotfiles/v2" && ! -e "$home/network-attempted" ]] ||
    fail 'package-only OpenCode wrote state or used the network'
  expect_success "$home" "$profile_host" "$DOTFILES" check opencode
done
CAPTURE_PATH_PREFIX="$fake_bin"
pass

# Exact links from the previous layout migrate without touching unrelated data.
legacy="$(new_home legacy-apply)"
mkdir -p "$legacy/.config/opencode/profiles" "$legacy/.local/bin"
ln -s "$REPO_DIR/packages/common/opencode/.config/opencode/base.jsonc" "$legacy/.config/opencode/base.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.config/opencode/dotfiles-tui.jsonc" "$legacy/.config/opencode/dotfiles-tui.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.config/opencode/profiles/personal.jsonc" "$legacy/.config/opencode/profiles/personal.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.config/opencode/profiles/work.jsonc" "$legacy/.config/opencode/profiles/work.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.local/bin/dotfiles-opencode-profile" "$legacy/.local/bin/dotfiles-opencode-profile"
ln -s "$REPO_DIR/packages/common/opencode/.local/bin/opencode" "$legacy/.local/bin/opencode"
ln -s base.jsonc "$legacy/.config/opencode/opencode.jsonc"
printf 'preserve\n' > "$legacy/.config/opencode/unrelated"
expect_success "$legacy" "$ubuntu" "$DOTFILES" apply opencode
assert_managed_links "$legacy"
[[ ! -e "$legacy/.config/opencode/base.jsonc" && ! -L "$legacy/.config/opencode/base.jsonc" &&
  ! -e "$legacy/.config/opencode/opencode.jsonc" && ! -L "$legacy/.config/opencode/opencode.jsonc" &&
  ! -e "$legacy/.local/bin/opencode" && ! -L "$legacy/.local/bin/opencode" &&
  "$(< "$legacy/.config/opencode/unrelated")" == preserve ]] ||
  fail 'OpenCode apply did not migrate exact legacy links safely'
legacy_remove="$(new_home legacy-remove)"
mkdir -p "$legacy_remove/.config/opencode" "$legacy_remove/.local/bin"
ln -s "$REPO_DIR/packages/common/opencode/.config/opencode/base.jsonc" "$legacy_remove/.config/opencode/base.jsonc"
ln -s base.jsonc "$legacy_remove/.config/opencode/opencode.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.local/bin/opencode" "$legacy_remove/.local/bin/opencode"
expect_success "$legacy_remove" "$ubuntu" "$DOTFILES" remove opencode
[[ ! -e "$legacy_remove/.config/opencode/base.jsonc" && ! -L "$legacy_remove/.config/opencode/base.jsonc" &&
  ! -e "$legacy_remove/.local/bin/opencode" && ! -L "$legacy_remove/.local/bin/opencode" ]] ||
  fail 'OpenCode removal retained exact legacy links'
pass

# Named launchers select exact overlays and preserve arguments and status.
home="$(new_home launcher)"
seed_native_home "$home"
expect_success "$home" "$ubuntu" "$DOTFILES" apply opencode
launcher_path="$home/.local/bin:/usr/bin:/bin"
set +e
output="$(HOME="$home" PATH="$launcher_path" FAKE_OPENCODE_STATUS=37 \
  "$home/.local/bin/opencode-personal" 'two words' '' -- '*' 2>&1)"
status=$?
set -e
((status == 37)) || fail "OpenCode launcher changed status: $status"
expected="$home/.config/dotfiles/opencode/personal.jsonc"$'\n'"$home/.config/dotfiles/opencode/tui.jsonc"$'\n<two words>\n<>\n<-->\n<*>'
[[ "$output" == "$expected" ]] || fail 'personal launcher changed overlays or arguments'
output="$(HOME="$home" PATH="$launcher_path" "$home/.local/bin/opencode-work" literal)"
[[ "$output" == "$home/.config/dotfiles/opencode/work.jsonc"$'\n'"$home/.config/dotfiles/opencode/tui.jsonc"$'\n<literal>' ]] ||
  fail 'work launcher selected the wrong overlays'
set +e
output="$(HOME="$home" PATH=/usr/bin:/bin "$home/.local/share/dotfiles/bin/opencode-launch" personal 2>&1)"
status=$?
set -e
((status == 127)) || fail 'missing OpenCode executable did not return 127'
assert_contains "$output" 'no opencode executable found on PATH'
set +e
HOME="$home" PATH="$launcher_path" "$home/.local/share/dotfiles/bin/opencode-launch" invalid >/dev/null 2>&1
status=$?
set -e
((status == 2)) || fail 'invalid OpenCode profile did not return 2'
pass

# Every loaded global filename rejects top-level plugin/provider declarations.
for name in config.json opencode.json opencode.jsonc; do
  for key in plugin provider; do
    conflict="$(new_home "global-${name//./-}-$key")"
    mkdir -p "$conflict/.config/opencode"
    printf '{"%s":null}\n' "$key" > "$conflict/.config/opencode/$name"
    expect_failure 'declares plugin or provider settings' "$conflict" "$ubuntu" "$DOTFILES" apply opencode
    [[ ! -e "$conflict/.config/dotfiles/opencode/personal.jsonc" ]] ||
      fail 'global OpenCode conflict mutated the home'
  done
done
jsonc_home="$(new_home global-jsonc)"
mkdir -p "$jsonc_home/.config/opencode"
printf '// accepted subset\n{\n  "autoupdate": false,\n}\n' > "$jsonc_home/.config/opencode/opencode.jsonc"
expect_success "$jsonc_home" "$ubuntu" "$DOTFILES" apply opencode
malformed="$(new_home global-malformed)"
mkdir -p "$malformed/.config/opencode"
printf '{broken\n' > "$malformed/.config/opencode/opencode.json"
expect_failure 'invalid JSON/JSONC' "$malformed" "$ubuntu" "$DOTFILES" apply opencode
directory="$(new_home global-directory)"
mkdir -p "$directory/.config/opencode/opencode.json"
expect_failure 'not a readable EUID-owned regular file' "$directory" "$ubuntu" "$DOTFILES" apply opencode
symlink="$(new_home global-symlink)"
mkdir -p "$symlink/.config/opencode"
printf '{}\n' > "$symlink/elsewhere"
ln -s "$symlink/elsewhere" "$symlink/.config/opencode/opencode.json"
expect_failure 'not a readable EUID-owned regular file' "$symlink" "$ubuntu" "$DOTFILES" apply opencode
pass

# Removal ignores malformed host config, removes only managed links, and converges.
printf '{broken\n' > "$home/.config/opencode/opencode.json"
cp -a "$home/.local/bin/opencode" "$TEST_ROOT/removal-opencode"
mkdir "$TEST_ROOT/removal-config"
cp -a "$home/.config/opencode/." "$TEST_ROOT/removal-config"
expect_success "$home" "$ubuntu" "$DOTFILES" remove opencode
for path in \
  .config/dotfiles/opencode/personal.jsonc \
  .config/dotfiles/opencode/tui.jsonc \
  .config/dotfiles/opencode/work.jsonc \
  .local/bin/opencode-personal \
  .local/bin/opencode-work \
  .local/share/dotfiles/bin/opencode-launch; do
  [[ ! -e "$home/$path" && ! -L "$home/$path" ]] || fail "OpenCode removal retained managed link: $path"
done
[[ -f "$home/.local/bin/opencode" ]] ||
  fail 'OpenCode removal retained managed links or removed native executable'
assert_same "$home/.local/bin/opencode" "$TEST_ROOT/removal-opencode"
for path in opencode.json tui.json tui.jsonc herdr-tui-session.js AGENTS.md; do
  assert_same "$home/.config/opencode/$path" "$TEST_ROOT/removal-config/$path"
done
expect_success "$home" "$ubuntu" "$DOTFILES" remove opencode
pass

# Managed namespace conflicts refuse before mutation.
overlay_conflict="$(new_home overlay-conflict)"
mkdir -p "$overlay_conflict/.config/dotfiles/opencode"
printf '{"host_owned":true}\n' > "$overlay_conflict/.config/dotfiles/opencode/tui.jsonc"
expect_failure 'conflict' "$overlay_conflict" "$ubuntu" "$DOTFILES" apply opencode
[[ ! -e "$overlay_conflict/.config/dotfiles/opencode/personal.jsonc" &&
  "$(< "$overlay_conflict/.config/dotfiles/opencode/tui.jsonc")" == '{"host_owned":true}' ]] ||
  fail 'OpenCode overlay conflict mutated the home'
pass

# Argumentless removal includes deployed optional package-only ownership.
default_home="$(new_home default-remove)"
seed_native_home "$default_home"
rm "$default_home/.config/opencode/AGENTS.md"
expect_success "$default_home" "$ubuntu" "$DOTFILES" apply opencode
expect_success "$default_home" "$ubuntu" "$DOTFILES" remove
[[ ! -e "$default_home/.config/dotfiles/opencode/personal.jsonc" &&
  -f "$default_home/.local/bin/opencode" && ! -L "$default_home/.local/bin/opencode" ]] ||
  fail 'default removal retained optional links or removed native executable'
pass

printf 'PASS: %s OpenCode test groups\n' "$TEST_COUNT"
