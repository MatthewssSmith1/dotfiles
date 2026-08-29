#!/usr/bin/env bash
# Optional OpenCode config variants, adoption, selection, and lifecycle.

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

# Personal pins the complete Codex OAuth profile; work stays gateway-only.
personal_profile="$REPO_DIR/packages/common/opencode/.config/opencode/profiles/personal.jsonc"
work_profile="$REPO_DIR/packages/common/opencode/.config/opencode/profiles/work.jsonc"
personal_provider_hash='e986bec224382f24e2334b152cdf23ffaf13ccefde895e3fe4c94d2702d3bce8'
jq -e '
  .plugin == ["opencode-openai-codex-auth@4.4.0"] and
  .agent.compaction == {
    "model": "openai/gpt-5.6-terra",
    "variant": "low"
  } and
  (.provider.openai.models | keys) == [
    "gpt-5.1",
    "gpt-5.1-codex",
    "gpt-5.1-codex-max",
    "gpt-5.1-codex-mini",
    "gpt-5.2",
    "gpt-5.2-codex"
  ]
' "$personal_profile" >/dev/null || fail 'personal OpenCode Codex OAuth profile drifted'
[[ "$(jq -cS '.provider.openai' "$personal_profile" | sha256sum | cut -d ' ' -f1)" == "$personal_provider_hash" ]] ||
  fail 'personal OpenCode 4.4.0 provider catalog drifted'
jq -e '
  ((.plugin // []) | index("opencode-openai-codex-auth@4.4.0") == null) and
  .agent.compaction == {
    "model": "truefoundry-gateway-openai/codex-group/gpt-5.6-terra",
    "variant": "low"
  }
' \
  "$work_profile" >/dev/null || fail 'work OpenCode profile boundary drifted'
pass

# Shared TUI bindings preserve prompt text and avoid default quit aliases.
tui_profile="$REPO_DIR/packages/common/opencode/.config/opencode/dotfiles-tui.jsonc"
jq -e '
  .keybinds == {
    "app_exit": "<leader>q",
    "input_clear": "<leader>k",
    "prompt_stash": "ctrl+s",
    "prompt_stash_pop": "ctrl+y",
    "input_newline": "ctrl+return,shift+return,alt+return,ctrl+j"
  }
' "$tui_profile" >/dev/null || fail 'shared OpenCode TUI bindings drifted'
pass

# Both host profiles deploy the same optional package without state.
for profile_host in "$ubuntu" "$native"; do
  home="$(new_home "apply-${profile_host##*/}")"
  expect_success "$home" "$profile_host" "$DOTFILES" apply opencode
  [[ -L "$home/.config/opencode/base.jsonc" && -L "$home/.config/opencode/dotfiles-tui.jsonc" &&
    -L "$home/.config/opencode/profiles/work.jsonc" &&
    -L "$home/.config/opencode/profiles/personal.jsonc" &&
    -L "$home/.local/bin/opencode" && -L "$home/.config/opencode/opencode.jsonc" ]] ||
    fail 'OpenCode managed links were not deployed'
  [[ "$(readlink -- "$home/.config/opencode/opencode.jsonc")" == base.jsonc ]] ||
    fail 'OpenCode canonical base bridge is not lexical'
  [[ ! -e "$home/.local/state/dotfiles/v2" ]] || fail 'package-only OpenCode wrote ownership state'
  expect_success "$home" "$profile_host" "$DOTFILES" check opencode
done
pass

# The exact current work config is safely adopted and selects work locally.
home="$(new_home adoption)"
mkdir -p "$home/.config/opencode"
cp "$REPO_DIR/packages/common/opencode/.config/opencode/profiles/work.jsonc" "$home/.config/opencode/opencode.jsonc"
printf 'instructions\n' > "$home/.config/opencode/AGENTS.md"
expect_success "$home" "$ubuntu" "$DOTFILES" apply opencode
[[ -L "$home/.config/opencode/opencode.jsonc" &&
  "$(< "$home/.config/dotfiles/local/opencode-profile")" == work ]] ||
  fail 'exact work config adoption did not initialize work selection'
[[ "$(< "$home/.config/opencode/AGENTS.md")" == instructions ]] || fail 'OpenCode changed the Agents bridge namespace'
pass

# Unrelated canonical config refuses before mutation.
conflict="$(new_home conflict)"
mkdir -p "$conflict/.config/opencode"
printf '{"unrelated":true}\n' > "$conflict/.config/opencode/opencode.jsonc"
expect_failure 'unrelated OpenCode config conflicts' "$conflict" "$ubuntu" "$DOTFILES" apply opencode
[[ ! -e "$conflict/.config/opencode/base.jsonc" ]] || fail 'OpenCode conflict mutated the home'
expect_success "$conflict" "$ubuntu" "$DOTFILES" remove
[[ "$(< "$conflict/.config/opencode/opencode.jsonc")" == '{"unrelated":true}' ]] ||
  fail 'default removal changed unowned OpenCode config'
pass

# Selector and named launchers inject the exact overlay and preserve arguments/status.
real_bin="$TEST_ROOT/real-bin"
mkdir "$real_bin"
cat > "$real_bin/opencode" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$OPENCODE_CONFIG"
printf '%s\n' "$OPENCODE_TUI_CONFIG"
printf '<%s>\n' "$@"
exit 37
SCRIPT
chmod 0755 "$real_bin/opencode"
launcher_path="$home/.local/bin:$real_bin:/usr/bin"
set +e
output="$(HOME="$home" PATH="$launcher_path" "$home/.local/bin/opencode" 'two words' 2>&1)"
status=$?
set -e
((status == 37)) || fail "OpenCode launcher changed status: $status"
[[ "$output" == "$home/.config/opencode/profiles/work.jsonc"$'\n'"$home/.config/opencode/dotfiles-tui.jsonc"$'\n<two words>' ]] ||
  fail 'default OpenCode launcher changed work overlay or arguments'
HOME="$home" PATH="$launcher_path" "$home/.local/bin/dotfiles-opencode-profile" personal
[[ "$(HOME="$home" PATH="$launcher_path" "$home/.local/bin/dotfiles-opencode-profile" show)" == personal ]] ||
  fail 'OpenCode selector did not persist personal'
set +e
output="$(HOME="$home" PATH="$launcher_path" "$home/.local/bin/opencode-personal" literal 2>&1)"
status=$?
set -e
((status == 37)) || fail 'named OpenCode launcher changed status'
[[ "$output" == "$home/.config/opencode/profiles/personal.jsonc"$'\n'"$home/.config/opencode/dotfiles-tui.jsonc"$'\n<literal>' ]] ||
  fail 'personal OpenCode launcher selected the wrong overlay'
pass

# Removal is exact, preserves host-owned content and selector, and converges.
printf '{"plugin":["./herdr-tui-session.js"]}\n' > "$home/.config/opencode/tui.jsonc"
expect_success "$home" "$ubuntu" "$DOTFILES" remove opencode
[[ ! -e "$home/.config/opencode/base.jsonc" && ! -e "$home/.config/opencode/dotfiles-tui.jsonc" &&
  ! -e "$home/.local/bin/opencode" ]] ||
  fail 'OpenCode removal retained managed links'
[[ "$(< "$home/.config/dotfiles/local/opencode-profile")" == personal &&
  "$(< "$home/.config/opencode/AGENTS.md")" == instructions &&
  "$(< "$home/.config/opencode/tui.jsonc")" == '{"plugin":["./herdr-tui-session.js"]}' ]] ||
  fail 'OpenCode removal changed host-owned files'
expect_success "$home" "$ubuntu" "$DOTFILES" remove opencode
pass

# A host-owned managed-overlay destination refuses before mutation.
overlay_conflict="$(new_home overlay-conflict)"
mkdir -p "$overlay_conflict/.config/opencode"
printf '{"host_owned":true}\n' > "$overlay_conflict/.config/opencode/dotfiles-tui.jsonc"
expect_failure 'conflict' "$overlay_conflict" "$ubuntu" "$DOTFILES" apply opencode
[[ ! -e "$overlay_conflict/.config/opencode/base.jsonc" &&
  "$(< "$overlay_conflict/.config/opencode/dotfiles-tui.jsonc")" == '{"host_owned":true}' ]] ||
  fail 'OpenCode TUI conflict mutated the home'
pass

# Argumentless removal includes deployed optional package-only ownership.
default_home="$(new_home default-remove)"
expect_success "$default_home" "$ubuntu" "$DOTFILES" apply opencode
expect_success "$default_home" "$ubuntu" "$DOTFILES" remove
[[ ! -e "$default_home/.config/opencode/base.jsonc" && ! -e "$default_home/.local/bin/opencode" ]] ||
  fail 'default removal retained optional OpenCode links'
pass

printf 'PASS: %s OpenCode test groups\n' "$TEST_COUNT"
