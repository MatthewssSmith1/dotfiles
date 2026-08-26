#!/usr/bin/env bash
# Agent skill provenance, package inventory, exact bridges, and lean lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
export PATH="$fake_bin:$PATH" FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
CAPTURE_PATH_PREFIX="$fake_bin"
host="$(make_host agents linux)"

run_agents_area() {
  local home="$1" operation="$2"
  HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=agents-test \
    SELECTED_PROFILE=ubuntu MODE="$operation" DOTFILES_TESTING=1 bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/lean_engine.sh"
      source "$DOTFILES_DIR/lib/areas/agents.sh"
      validate_area_manifest
      case "$MODE" in
        apply) preflight_agents; apply_agents ;;
        check) preflight_agents ;;
        remove) remove_agents ;;
      esac
    '
}

expect_agents_failure() {
  local expected="$1" home="$2" operation="$3"
  set +e
  TEST_OUTPUT="$(run_agents_area "$home" "$operation" 2>&1)"
  TEST_RC=$?
  set -e
  ((TEST_RC != 0)) || fail 'Agents command unexpectedly succeeded'
  assert_contains "$TEST_OUTPUT" "$expected"
}

# The lock proves exact vendored provenance and closes over the complete package.
validate_json_schema "$REPO_DIR/schemas/agent-skills-lock.schema.json" \
  "$REPO_DIR/manifests/agent-skills.lock.json"
"$REPO_DIR/scripts/agent-skills" verify >/dev/null
[[ "$(jq -r .commit "$REPO_DIR/manifests/agent-skills.lock.json")" == 2ab958093e83e0ec752e6c1c5932da465bf23e0c ]] ||
  fail 'agent skill commit pin drifted'
[[ "$(jq '.skills | length' "$REPO_DIR/manifests/agent-skills.lock.json")" == 7 ]] || fail 'skill inventory count drifted'
[[ "$(jq '[.skills[].files[]] | length' "$REPO_DIR/manifests/agent-skills.lock.json")" == 26 ]] || fail 'skill file count drifted'
fixture="$(copy_repo_fixture agents-lock-extra)"
printf 'extra\n' > "$fixture/packages/common/agents/.agents/skills/grilling/EXTRA.md"
if TEST_OUTPUT="$("$fixture/scripts/agent-skills" verify 2>&1)"; then fail 'verification accepted an undeclared file'; fi
assert_contains "$TEST_OUTPUT" 'undeclared package file'
pass

# Apply deploys the exact package closure and bridges without state, and is idempotent.
home="$(new_home agents-lifecycle)"
mkdir -p "$home/.agents/skills/unrelated" "$home/.config/opencode" "$home/.claude"
printf 'keep skill\n' > "$home/.agents/skills/unrelated/KEEP"
printf 'keep opencode\n' > "$home/.config/opencode/settings.json"
printf 'keep claude\n' > "$home/.claude/settings.json"
run_agents_area "$home" apply
[[ -L "$home/.agents/AGENTS.md" && "$(realpath "$home/.agents/AGENTS.md")" == \
  "$REPO_DIR/packages/common/agents/.agents/AGENTS.md" ]] || fail 'canonical instructions are not package-owned'
while IFS= read -r destination; do
  [[ -L "$home/$destination" ]] || fail "missing skill package link: $destination"
done < <(jq -r '.skills[].files[].destination' "$REPO_DIR/manifests/agent-skills.lock.json")
[[ "$(readlink -- "$home/.config/opencode/AGENTS.md")" == '../../.agents/AGENTS.md' ]] || fail 'OpenCode bridge is not exact'
[[ "$(readlink -- "$home/.claude/CLAUDE.md")" == '../.agents/AGENTS.md' ]] || fail 'Claude bridge is not exact'
[[ "$(realpath "$home/.config/opencode/AGENTS.md")" == "$REPO_DIR/packages/common/agents/.agents/AGENTS.md" ]] ||
  fail 'OpenCode bridge has wrong provenance'
[[ ! -e "$home/.local/state/dotfiles/v1/agents.json" && ! -e "$home/.local/state/dotfiles/v2/agents.json" ]] ||
  fail 'package-only Agents wrote deployment state'
run_agents_area "$home" check
run_agents_area "$home" apply
run_agents_area "$home" check
pass

# Exact existing bridges are adopted derivably; any non-exact bridge refuses.
adopt_home="$(new_home agents-adopt-bridge)"
mkdir -p "$adopt_home/.agents" "$adopt_home/.config/opencode" "$adopt_home/.claude"
ln -s "$(realpath -m -s --relative-to="$adopt_home/.agents" -- \
  "$REPO_DIR/packages/common/agents/.agents/AGENTS.md")" "$adopt_home/.agents/AGENTS.md"
ln -s ../../.agents/AGENTS.md "$adopt_home/.config/opencode/AGENTS.md"
ln -s ../.agents/AGENTS.md "$adopt_home/.claude/CLAUDE.md"
run_agents_area "$adopt_home" apply
run_agents_area "$adopt_home" check

conflict_home="$(new_home agents-bridge-conflict)"
mkdir -p "$conflict_home/.config/opencode"
printf 'foreign\n' > "$conflict_home/.config/opencode/AGENTS.md"
expect_agents_failure 'unrelated destination conflict' "$conflict_home" apply
[[ "$(< "$conflict_home/.config/opencode/AGENTS.md")" == foreign ]] || fail 'bridge conflict was modified'
pass

# Managed skill names are directory boundaries; unrelated skill names survive.
conflict_home="$(new_home agents-skill-conflict)"
mkdir -p "$conflict_home/.agents/skills/grilling"
expect_agents_failure 'unmanaged managed-skill directory conflict' "$conflict_home" apply
printf 'extra\n' > "$home/.agents/skills/grilling/EXTRA"
expect_agents_failure 'extra file in managed skill directory' "$home" check
rm "$home/.agents/skills/grilling/EXTRA"
pass

# Removal refuses a changed bridge before touching package links, then removes only exact ownership.
rm "$home/.config/opencode/AGENTS.md"
ln -s ../foreign "$home/.config/opencode/AGENTS.md"
expect_agents_failure 'unrelated destination conflict' "$home" remove
[[ -L "$home/.agents/AGENTS.md" && "$(readlink "$home/.config/opencode/AGENTS.md")" == ../foreign ]] ||
  fail 'refused removal changed Agents ownership'
rm "$home/.config/opencode/AGENTS.md"
ln -s ../../.agents/AGENTS.md "$home/.config/opencode/AGENTS.md"
run_agents_area "$home" remove
[[ ! -e "$home/.agents/AGENTS.md" && ! -L "$home/.agents/AGENTS.md" ]] || fail 'canonical link survived removal'
[[ ! -e "$home/.config/opencode/AGENTS.md" && ! -L "$home/.config/opencode/AGENTS.md" ]] || fail 'OpenCode bridge survived removal'
[[ ! -e "$home/.claude/CLAUDE.md" && ! -L "$home/.claude/CLAUDE.md" ]] || fail 'Claude bridge survived removal'
[[ "$(< "$home/.agents/skills/unrelated/KEEP")" == 'keep skill' && \
  "$(< "$home/.config/opencode/settings.json")" == 'keep opencode' && \
  "$(< "$home/.claude/settings.json")" == 'keep claude' ]] || fail 'removal changed unrelated content'
pass

# Legacy state is refused with cleanup guidance and never adopted or rewritten.
legacy_home="$(new_home agents-v1)"
mkdir -p "$legacy_home/.local/state/dotfiles/v1"
printf '{}\n' > "$legacy_home/.local/state/dotfiles/v1/agents.json"
expect_agents_failure 'use the legacy checkout to remove it, or clean it up manually' "$legacy_home" apply
[[ "$(< "$legacy_home/.local/state/dotfiles/v1/agents.json")" == '{}' && \
  ! -e "$legacy_home/.local/state/dotfiles/v2" ]] || fail 'v1 refusal mutated deployment state'
pass

printf 'PASS: %s Agents test groups\n' "$TEST_COUNT"
