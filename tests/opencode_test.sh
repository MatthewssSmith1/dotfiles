#!/usr/bin/env bash
# Optional OpenCode profile overlays, native coexistence, and lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
install_fake_stow "$fake_bin"
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
  cat > "$home/.local/bin/opencode" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '%s\n' "${FAKE_OPENCODE_VERSION:-opencode v2.1.2}"; exit; fi
[[ ! -v OPENCODE_TUI_CONFIG && ! -v OPENCODE_CONFIG_CONTENT && ! -v OPENCODE_SERVER && ! -v OPENCODE_SERVER_URL ]] || exit 99
[[ ! -v EXPECTED_XDG_CONFIG_HOME || "$XDG_CONFIG_HOME" == "$EXPECTED_XDG_CONFIG_HOME" ]] || exit 98
[[ ! -v EXPECTED_TFY_API_KEY || "$TFY_API_KEY" == "$EXPECTED_TFY_API_KEY" ]] || exit 97
printf '%s\n' "$OPENCODE_CONFIG" "$OPENCODE_CLI_CONFIG_CONTENT" "$DOTFILES_OPENCODE_PLUGIN_DIR"
printf '<%s>\n' "$@"
exit "${FAKE_OPENCODE_STATUS:-0}"
EOF
  chmod 0755 "$home/.local/bin/opencode"
  printf '{"$schema":"https://opencode.ai/config.json","autoupdate":false}\n' > "$home/.config/opencode/opencode.json"
  printf '{"theme":"system"}\n' > "$home/.config/opencode/tui.json"
  printf '{"theme":{"name":"system"},"animations":false}\n' > "$home/.config/opencode/cli.json"
  printf '{"plugin":["./herdr-tui-session.js"]}\n' > "$home/.config/opencode/tui.jsonc"
  printf 'export default {}\n' > "$home/.config/opencode/herdr-tui-session.js"
  printf 'instructions\n' > "$home/.config/opencode/AGENTS.md"
}

assert_managed_links() {
  local home="$1" path
  for path in \
    .config/dotfiles/opencode/personal.jsonc \
    .config/dotfiles/opencode/cli.json \
    .config/dotfiles/opencode/runtime/index.js \
    .config/dotfiles/opencode/work.jsonc \
    .local/bin/opencode-personal \
    .local/bin/opencode-work \
    .local/share/dotfiles/bin/opencode-launch; do
    [[ -L "$home/$path" ]] || fail "OpenCode managed link is absent: $path"
  done
}

# Profiles retain reviewed boundaries, native V2 fields, and distinct mode colors.
personal_profile="$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/personal.jsonc"
work_profile="$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/work.jsonc"
cli_profile="$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/cli.json"
jq -e '
  (has("providers") | not) and (has("model") | not) and
  .update == "disable" and
  .plugins == ["-opencode.config.compatibility", "{env:DOTFILES_OPENCODE_PLUGIN_DIR}"] and
  .skills == ["{env:HOME}/.agents/skills"] and
  .agents.build.color == "#7aa2f7" and .agents.plan.color == "#ff9e64" and
  .agents.explore.model == "openai/gpt-6.1-sol-fast#medium" and
  .agents.general.model == "openai/gpt-6.1-sol-fast#medium" and
  .agents.compaction.model == "openai/gpt-6.1-sol-fast#medium" and
  .agents.title.model == "openai/gpt-6-luna#low" and
  .agents.posthog.model == "openai/gpt-6.1-sol#low" and
  .mcp.servers.posthog == {"type":"remote","url":"https://mcp.posthog.com/mcp","disabled":false,"codemode":false} and
  (.agents.posthog.system | type == "string" and length > 0)
' "$personal_profile" >/dev/null || fail 'personal OpenCode native ChatGPT OAuth profile drifted'
jq -e -s '
  .[0] as $personal | .[1] as $work |
  ($work | has("model") | not) and
  $work.permissions == $personal.permissions and
  $work.agents == $personal.agents and
  $work.plugins == $personal.plugins and
  $work.skills == $personal.skills and
  $work.mcp == $personal.mcp and
  ($work.providers | keys) == ["truefoundry-gateway"] and
  $work.policies == [
    {"action":"provider.use","resource":"*","effect":"deny"},
    {"action":"provider.use","resource":"openai","effect":"allow"},
    {"action":"provider.use","resource":"truefoundry-gateway","effect":"allow"}
  ] and
  $work.providers["truefoundry-gateway"].package == "aisdk:@ai-sdk/openai-compatible" and
  $work.providers["truefoundry-gateway"].settings == {
    "baseURL":"https://tfy.promptlens.trilogy.com","apiKey":"{env:TFY_API_KEY}"
  } and
  ($work.providers["truefoundry-gateway"].models | keys) == [
    "claude-group/claude-fable-5",
    "claude-group/claude-opus-5",
    "claude-group/claude-sonnet-5",
    "glm-5p3"
  ] and
  ($work.providers | tojson | test("gpt"; "i") | not) and
  ([$work.providers["truefoundry-gateway"].models[] | select(has("variants")) |
    .settings == {"reasoningEffort":"medium"} and
    .variants == [
      {"id":"none","settings":{"reasoningEffort":"none"}},
      {"id":"low","settings":{"reasoningEffort":"low"}},
      {"id":"medium","settings":{"reasoningEffort":"medium"}},
      {"id":"high","settings":{"reasoningEffort":"high"}}
    ]] | length == 3 and all)
' "$personal_profile" "$work_profile" >/dev/null || fail 'work OpenCode personal-plus-TrueFoundry profile drifted'
for profile in "$personal_profile" "$work_profile"; do
  jq -e '
    (has("permission") or has("agent") or has("provider") or has("plugin") | not) and
    .permissions == [
      {"action":"posthog_*","resource":"*","effect":"deny"}
    ] and
    ([.agents | to_entries[] | select(.value | has("permissions")) | .key] == ["posthog"]) and
    .agents.posthog.permissions == [
      {"action":"posthog_*","resource":"*","effect":"allow"},
      {"action":"edit","resource":"*","effect":"deny"}
    ]
  ' "$profile" >/dev/null || fail "OpenCode PostHog restrictions drifted: $profile"
done
jq -e '.keybinds == {
  "app.exit":"<leader>q",
  "session.queued_prompts":"none",
  "prompt.clear":"<leader>k",
  "prompt.stash":"ctrl+s",
  "prompt.stash.pop":"ctrl+y",
  "prompt.queue":"none",
  "input.newline":"ctrl+return,shift+return,alt+return,ctrl+j"
}' "$cli_profile" >/dev/null || fail 'shared OpenCode CLI bindings drifted'
jq -e 'has("theme") | not' "$cli_profile" >/dev/null || fail 'managed CLI overlay must not override native Omarchy theme'
for profile in "$personal_profile" "$work_profile"; do
  jq -e 'has("theme") | not' "$profile" >/dev/null || fail "profile overrides native theme: $profile"
done
pass

# Both hosts deploy managed links while preserving native and integration files.
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
  for path in opencode.json cli.json tui.json tui.jsonc herdr-tui-session.js AGENTS.md; do
    assert_same "$home/.config/opencode/$path" "$TEST_ROOT/reference-${profile_host##*/}/config/$path"
  done
  [[ ! -e "$home/.local/state/dotfiles/v2" && ! -e "$home/network-attempted" ]] ||
    fail 'package-only OpenCode wrote state or used the network'
  expect_success "$home" "$profile_host" "$DOTFILES" check opencode
done
CAPTURE_PATH_PREFIX="$fake_bin"
pass

# Native theme staging can replace its directory; both profiles continue to use
# the host's system theme without snapshotting theme.name or writing generated state.
themed="$(new_home native-themed)"
seed_native_home "$themed"
mkdir -p "$themed/.local/state/omarchy/current/theme"
printf 'everforest\n' > "$themed/.local/state/omarchy/current/theme.name"
expect_success "$themed" "$native" "$DOTFILES" apply opencode
for selection in everforest tokyo-night catppuccin unknown; do
  printf '%s\n' "$selection" > "$themed/.local/state/omarchy/current/theme.name"
  for profile in personal work; do
    output="$(HOME="$themed" PATH="$themed/.local/bin:/usr/bin:/bin" "$themed/.local/bin/opencode-$profile")"
    [[ "$output" == "$themed/.config/dotfiles/opencode/$profile.jsonc"$'\n'"$(< "$cli_profile")"$'\n'"$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/runtime"$'\n<--standalone>' ]] ||
      fail "native theme change altered $profile launch overlay"
  done
  jq -e '.theme.name == "system"' "$themed/.config/opencode/cli.json" >/dev/null || fail 'native CLI theme was changed'
done
[[ ! -e "$themed/.local/state/dotfiles/theme/current.json" ]] || fail 'OpenCode persisted a second native theme selection'
expect_success "$themed" "$native" "$DOTFILES" check opencode
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
output="$(HOME="$home" PATH="$launcher_path" OPENCODE_DISABLE_CLAUDE_CODE=0 FAKE_OPENCODE_STATUS=37 \
  "$home/.local/bin/opencode-personal" 'two words' '' -- '*' 2>&1)"
status=$?
set -e
((status == 37)) || fail "OpenCode launcher changed status: $status"
expected="$home/.config/dotfiles/opencode/personal.jsonc"$'\n'"$(< "$cli_profile")"$'\n'"$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/runtime"$'\n<--standalone>\n<two words>\n<>\n<-->\n<*>'
[[ "$output" == "$expected" ]] || fail 'personal launcher changed overlays or arguments'
output="$(HOME="$home" PATH="$launcher_path" OPENCODE_DISABLE_CLAUDE_CODE=0 "$home/.local/bin/opencode-work" literal)"
[[ "$output" == "$home/.config/dotfiles/opencode/work.jsonc"$'\n'"$(< "$cli_profile")"$'\n'"$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/runtime"$'\n<--standalone>\n<literal>' ]] ||
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
  for key in plugin provider plugins providers; do
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
   .config/dotfiles/opencode/cli.json \
   .config/dotfiles/opencode/runtime/index.js \
  .config/dotfiles/opencode/work.jsonc \
  .local/bin/opencode-personal \
  .local/bin/opencode-work \
  .local/share/dotfiles/bin/opencode-launch; do
  [[ ! -e "$home/$path" && ! -L "$home/$path" ]] || fail "OpenCode removal retained managed link: $path"
done
[[ -f "$home/.local/bin/opencode" ]] ||
  fail 'OpenCode removal retained managed links or removed native executable'
assert_same "$home/.local/bin/opencode" "$TEST_ROOT/removal-opencode"
for path in opencode.json cli.json tui.json tui.jsonc herdr-tui-session.js AGENTS.md; do
  assert_same "$home/.config/opencode/$path" "$TEST_ROOT/removal-config/$path"
done
expect_success "$home" "$ubuntu" "$DOTFILES" remove opencode
pass

# Managed namespace conflicts refuse before mutation.
overlay_conflict="$(new_home overlay-conflict)"
mkdir -p "$overlay_conflict/.config/dotfiles/opencode"
printf '{"host_owned":true}\n' > "$overlay_conflict/.config/dotfiles/opencode/cli.json"
expect_failure 'conflict' "$overlay_conflict" "$ubuntu" "$DOTFILES" apply opencode
[[ ! -e "$overlay_conflict/.config/dotfiles/opencode/personal.jsonc" &&
  "$(< "$overlay_conflict/.config/dotfiles/opencode/cli.json")" == '{"host_owned":true}' ]] ||
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

# Retire only exact trial links, retaining runtime/history and unrelated files.
trial="$(new_home trial-retirement)"
seed_native_home "$trial"
mkdir -p "$trial/.config/dotfiles/opencode/v2-shell" "$trial/.local/share/opencode-v2/personal" "$trial/.local/share/opencode-v2-runtime"
for path in .config/dotfiles/opencode/tui.jsonc .config/dotfiles/opencode/v2-cli.json \
  .config/dotfiles/opencode/v2-personal.jsonc .config/dotfiles/opencode/v2-shell/index.js .local/bin/opencode-v2; do
  ln -s "$REPO_DIR/packages/common/opencode/$path" "$trial/$path"
done
printf 'history\n' > "$trial/.local/share/opencode-v2/personal/history"
printf 'runtime\n' > "$trial/.local/share/opencode-v2-runtime/preserve"
printf 'unrelated\n' > "$trial/.config/dotfiles/opencode/v2-shell/unrelated"
expect_failure 'legacy managed OpenCode links remain' "$trial" "$ubuntu" "$DOTFILES" check opencode
expect_success "$trial" "$ubuntu" "$DOTFILES" apply opencode
for path in .config/dotfiles/opencode/tui.jsonc .config/dotfiles/opencode/v2-cli.json \
  .config/dotfiles/opencode/v2-personal.jsonc .config/dotfiles/opencode/v2-shell/index.js .local/bin/opencode-v2; do
  [[ ! -e "$trial/$path" && ! -L "$trial/$path" ]] || fail "retained trial link: $path"
done
expect_success "$trial" "$ubuntu" "$DOTFILES" check opencode
expect_success "$trial" "$ubuntu" "$DOTFILES" remove opencode
[[ "$(< "$trial/.local/share/opencode-v2/personal/history")" == history &&
  "$(< "$trial/.local/share/opencode-v2-runtime/preserve")" == runtime &&
  "$(< "$trial/.config/dotfiles/opencode/v2-shell/unrelated")" == unrelated ]] || fail 'trial retirement deleted application data'
printf 'foreign\n' > "$trial/.local/bin/opencode-v2"
expect_success "$trial" "$ubuntu" "$DOTFILES" apply opencode
[[ "$(< "$trial/.local/bin/opencode-v2")" == foreign ]] || fail 'retirement overwrote unrelated launcher'
ln -s "$trial/.local/bin/opencode-v2" "$trial/.config/dotfiles/opencode/v2-personal.jsonc"
expect_success "$trial" "$ubuntu" "$DOTFILES" apply opencode
[[ -L "$trial/.config/dotfiles/opencode/v2-personal.jsonc" &&
  "$(readlink "$trial/.config/dotfiles/opencode/v2-personal.jsonc")" == "$trial/.local/bin/opencode-v2" ]] ||
  fail 'retirement removed an unrelated symlink'
pass

# Profile server commands are private; inherited server/overlay overrides cleared.
for profile in personal work; do
  for command in run mini api models; do
    output="$(HOME="$themed" PATH="$themed/.local/bin:/usr/bin:/bin" OPENCODE_TUI_CONFIG=/old \
      XDG_CONFIG_HOME=/original/config EXPECTED_XDG_CONFIG_HOME=/original/config \
      TFY_API_KEY=fixture-work-key EXPECTED_TFY_API_KEY=fixture-work-key \
      OPENCODE_CONFIG_CONTENT='{}' OPENCODE_SERVER=http://wrong OPENCODE_SERVER_URL=http://wrong \
      "$themed/.local/bin/opencode-$profile" "$command" 'two words' '')"
    assert_contains "$output" $'<'"$command"$'>\n<--standalone>\n<two words>\n<>'
  done
  output="$(HOME="$themed" PATH="$themed/.local/bin:/usr/bin:/bin" "$themed/.local/bin/opencode-$profile" auth login openai)"
  assert_contains "$output" $'<auth>\n<login>\n<--standalone>\n<openai>'
  for command in mcp service reload pair; do
    if HOME="$themed" "$themed/.local/bin/opencode-$profile" "$command" >/dev/null 2>&1; then
      fail "profile command could accidentally reuse shared service: $command"
    fi
  done
  if HOME="$themed" "$themed/.local/bin/opencode-$profile" --server=http://wrong >/dev/null 2>&1; then
    fail 'profile accepted an external server'
  fi
done
pass

if HOME="$themed" PATH="$themed/.local/bin:/usr/bin:/bin" FAKE_OPENCODE_VERSION=1.19.0 \
  "$themed/.local/bin/opencode-personal" >/dev/null 2>&1; then
  fail 'native V2 profile launched against V1'
fi

printf 'PASS: %s OpenCode test groups\n' "$TEST_COUNT"
