#!/usr/bin/env bash
# Agent skill package inventory, exact bridges, and lean lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
export PATH="$fake_bin:$PATH" FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
CAPTURE_PATH_PREFIX="$fake_bin"
host="$(make_host agents linux)"

readonly MANAGED_SKILLS=(
  grilling
  handoff
  setup-domain-modeling
  writing-for-agents
)
readonly MANAGED_SKILL_FILES=(
  grilling/SKILL.md
  grilling/agents/openai.yaml
  handoff/SKILL.md
  handoff/agents/openai.yaml
  setup-domain-modeling/SKILL.md
  setup-domain-modeling/agents/openai.yaml
  setup-domain-modeling/monorepos.md
  setup-domain-modeling/template/.agents/skills/domain-modeling/DR-FORMAT.md
  setup-domain-modeling/template/.agents/skills/domain-modeling/GLOSSARY-FORMAT.md
  setup-domain-modeling/template/.agents/skills/domain-modeling/SKILL.template.md
  setup-domain-modeling/template/.agents/skills/domain-modeling/agents/openai.yaml
  setup-domain-modeling/template/AGENTS.md
  setup-domain-modeling/template/GLOSSARY.md
  setup-domain-modeling/template/docs/adr/AGENTS.md
  setup-domain-modeling/template/docs/bdr/AGENTS.md
  writing-for-agents/SKILL-MECHANICS.md
  writing-for-agents/SKILL.md
  writing-for-agents/agents/openai.yaml
)

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

# Verification derives the exact managed inventory and valid structure from the
# Git-versioned package.
"$REPO_DIR/scripts/agent-skills" verify >/dev/null
skill_root="$REPO_DIR/packages/common/agents/.agents/skills"
actual_skills="$(find "$skill_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)"
expected_skills="$(printf '%s\n' "${MANAGED_SKILLS[@]}" | LC_ALL=C sort)"
[[ "$actual_skills" == "$expected_skills" ]] || fail 'managed skill inventory is not exact'
actual_skill_files="$(find "$skill_root" -type f -printf '%P\n' | LC_ALL=C sort)"
expected_skill_files="$(printf '%s\n' "${MANAGED_SKILL_FILES[@]}" | LC_ALL=C sort)"
[[ "$actual_skill_files" == "$expected_skill_files" ]] || fail 'managed skill file inventory is not exact'
fixture="$(copy_repo_fixture agents-invalid-package)"
printf 'invalid direct entry\n' > "$fixture/packages/common/agents/.agents/skills/UNDECLARED"
if TEST_OUTPUT="$("$fixture/scripts/agent-skills" verify 2>&1)"; then
  fail 'verification accepted an undeclared direct skill entry'
fi
assert_contains "$TEST_OUTPUT" 'direct skill entry is not a directory'
pass

# Apply deploys the exact package closure and bridges without state, preserves
# native Omarchy skills, and is idempotent.
home="$(new_home agents-lifecycle)"
mkdir -p "$home/.agents/skills/unrelated" "$home/.config/opencode" "$home/.claude"
native_root="$host/usr/share/omarchy/default/agents/skills"
mkdir -p "$native_root/omarchy" "$native_root/diagnose-crash"
printf 'native omarchy\n' > "$native_root/omarchy/SKILL.md"
printf 'native diagnose-crash\n' > "$native_root/diagnose-crash/SKILL.md"
ln -s "$native_root/omarchy" "$home/.agents/skills/omarchy"
ln -s "$native_root/diagnose-crash" "$home/.agents/skills/diagnose-crash"
printf 'keep skill\n' > "$home/.agents/skills/unrelated/KEEP"
printf 'keep opencode\n' > "$home/.config/opencode/settings.json"
printf 'keep claude\n' > "$home/.claude/settings.json"

assert_native_skills() {
  [[ -L "$home/.agents/skills/omarchy" &&
    "$(readlink -- "$home/.agents/skills/omarchy")" == "$native_root/omarchy" &&
    "$(< "$home/.agents/skills/omarchy/SKILL.md")" == 'native omarchy' ]] ||
    fail 'native omarchy skill was changed'
  [[ -L "$home/.agents/skills/diagnose-crash" &&
    "$(readlink -- "$home/.agents/skills/diagnose-crash")" == "$native_root/diagnose-crash" &&
    "$(< "$home/.agents/skills/diagnose-crash/SKILL.md")" == 'native diagnose-crash' ]] ||
    fail 'native diagnose-crash skill was changed'
}

run_agents_area "$home" apply
assert_native_skills
[[ -L "$home/.agents/AGENTS.md" && "$(realpath "$home/.agents/AGENTS.md")" == \
  "$REPO_DIR/packages/common/agents/.agents/AGENTS.md" ]] || fail 'canonical instructions are not package-owned'
for skill_file in "${MANAGED_SKILL_FILES[@]}"; do
  [[ -L "$home/.agents/skills/$skill_file" ]] || fail "missing skill package link: $skill_file"
done
[[ "$(readlink -- "$home/.config/opencode/AGENTS.md")" == '../../.agents/AGENTS.md' ]] || fail 'OpenCode bridge is not exact'
[[ "$(readlink -- "$home/.claude/CLAUDE.md")" == '../.agents/AGENTS.md' ]] || fail 'Claude bridge is not exact'
[[ "$(realpath "$home/.config/opencode/AGENTS.md")" == "$REPO_DIR/packages/common/agents/.agents/AGENTS.md" ]] ||
  fail 'OpenCode bridge has wrong provenance'
[[ ! -e "$home/.local/state/dotfiles/v1/agents.json" && ! -e "$home/.local/state/dotfiles/v2/agents.json" ]] ||
  fail 'package-only Agents wrote deployment state'
run_agents_area "$home" check
assert_native_skills
run_agents_area "$home" apply
assert_native_skills
run_agents_area "$home" check
assert_native_skills
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
expect_agents_failure 'personal directory conflicts with managed skill' "$conflict_home" apply
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
assert_native_skills
for skill in "${MANAGED_SKILLS[@]}"; do
  [[ ! -e "$home/.agents/skills/$skill" && ! -L "$home/.agents/skills/$skill" ]] ||
    fail "managed skill survived removal: $skill"
done
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
