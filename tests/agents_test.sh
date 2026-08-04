#!/usr/bin/env bash
# Agent skill provenance and dedicated deployment lifecycle.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

CAPTURE_DEFAULT_AREA=agents
host="$(make_host agents linux)"

run_agents_area() {
  local home="$1" checkout="$2" operation="$3" fail_at="${4:-}" mode=apply
  [[ "$operation" != check ]] || mode=check
  [[ "$operation" != remove ]] || mode=remove
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$checkout" DOTFILES_DIR="$checkout" \
    SCRIPT_NAME=agents-test SELECTED_PROFILE=generic MODE="$mode" DOTFILES_TESTING=1 \
    DOTFILES_TEST_FAIL_AT="$fail_at" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/areas/agents.sh"
      AREA_ORDER=(git bash tmux nvim zsh agents herdr)
      AREA_STATUS=([git]=ready [bash]=ready [tmux]=ready [nvim]=ready [zsh]=ready [agents]=ready [herdr]=ready)
      if [[ "$MODE" == remove ]]; then
        remove_agents
      elif [[ "$MODE" == check ]]; then
        preflight_agents
      else
        preflight_agents
        apply_agents
      fi
    '
}

expect_agents_failure() {
  local expected="$1"
  shift
  set +e
  TEST_OUTPUT="$(run_agents_area "$@" 2>&1)"
  TEST_RC=$?
  set -e
  ((TEST_RC != 0)) || fail 'agents command unexpectedly succeeded'
  assert_contains "$TEST_OUTPUT" "$expected"
}

# The committed lock is schema-valid and closes over every regular package file.
validate_json_schema "$REPO_DIR/schemas/agent-skills-lock.schema.json" \
  "$REPO_DIR/manifests/agent-skills.lock.json"
"$REPO_DIR/scripts/agent-skills" verify >/dev/null
[[ "$(jq -r .commit "$REPO_DIR/manifests/agent-skills.lock.json")" == \
  2ab958093e83e0ec752e6c1c5932da465bf23e0c ]] || fail 'agent skill commit pin drifted'
[[ "$(jq '.skills | length' "$REPO_DIR/manifests/agent-skills.lock.json")" == 7 ]] || \
  fail 'agent skill inventory does not contain seven skills'
[[ "$(jq '[.skills[].files[]] | length' "$REPO_DIR/manifests/agent-skills.lock.json")" == 26 ]] || \
  fail 'agent skill file inventory does not contain 26 upstream files'
[[ "$(< "$REPO_DIR/packages/common/agents/.agents/AGENTS.md")" == $'# Instructions\n\nBe extremely concise. Sacrifice grammar for the sake of concision.' ]] || \
  fail 'canonical agent instructions drifted'
pass

# Verification rejects undeclared closure additions without touching the source checkout.
fixture="$(copy_repo_fixture agents-lock-extra)"
printf 'extra\n' > "$fixture/packages/common/agents/.agents/skills/grilling/EXTRA.md"
if TEST_OUTPUT="$("$fixture/scripts/agent-skills" verify 2>&1)"; then
  fail 'agent skill verification accepted an undeclared package file'
fi
assert_contains "$TEST_OUTPUT" 'undeclared package file'
pass

# Apply creates exact canonical links and bridges while preserving unrelated names and parent content.
home="$(new_home agents-apply)"
mkdir -p "$home/.agents/skills/unrelated" "$home/.config/opencode" "$home/.claude"
printf 'keep skill\n' > "$home/.agents/skills/unrelated/KEEP"
printf 'keep opencode\n' > "$home/.config/opencode/settings.json"
printf 'keep claude\n' > "$home/.claude/settings.json"
expect_success "$home" "$host" "$BOOTSTRAP"
[[ -L "$home/.agents/AGENTS.md" && "$(realpath "$home/.agents/AGENTS.md")" == \
  "$REPO_DIR/packages/common/agents/.agents/AGENTS.md" ]] || fail 'canonical AGENTS.md link is not package-owned'
while IFS= read -r destination; do
  [[ -L "$home/$destination" ]] || fail "missing deployed skill file: $destination"
done < <(jq -r '.skills[].files[].destination' "$REPO_DIR/manifests/agent-skills.lock.json")
[[ "$(readlink -- "$home/.config/opencode/AGENTS.md")" == '../../.agents/AGENTS.md' ]] || \
  fail 'OpenCode bridge is not exact'
[[ "$(readlink -- "$home/.claude/CLAUDE.md")" == '../.agents/AGENTS.md' ]] || \
  fail 'Claude bridge is not exact'
[[ "$(realpath "$home/.config/opencode/AGENTS.md")" == \
  "$REPO_DIR/packages/common/agents/.agents/AGENTS.md" ]] || fail 'OpenCode bridge does not resolve to package source'
state="$home/.local/state/dotfiles/v1/agents.json"
assert_file "$state"
[[ "$(jq -r '[.targets[0].path,.targets[1].path] | join(" ")' "$state")" == \
  '.config/opencode/AGENTS.md .claude/CLAUDE.md' ]] || fail 'state does not order bridges before canonical targets'
expect_success "$home" "$host" "$BOOTSTRAP" --check
[[ "$(< "$home/.agents/skills/unrelated/KEEP")" == 'keep skill' ]] || fail 'check changed unrelated skill content'
pass

# A reviewed lock update can remove a managed skill without invalidating old state.
fixture="$(copy_repo_fixture agents-inventory-update)"
update_home="$(new_home agents-inventory-update)"
run_agents_area "$update_home" "$fixture" apply
rm -rf -- "$fixture/packages/common/agents/.agents/skills/research"
jq 'del(.skills[] | select(.name == "research"))' "$fixture/manifests/agent-skills.lock.json" \
  > "$fixture/manifests/agent-skills.lock.json.tmp"
mv "$fixture/manifests/agent-skills.lock.json.tmp" "$fixture/manifests/agent-skills.lock.json"
"$fixture/scripts/agent-skills" verify >/dev/null
run_agents_area "$update_home" "$fixture" apply
[[ ! -e "$update_home/.agents/skills/research/SKILL.md" && \
  ! -L "$update_home/.agents/skills/research/SKILL.md" ]] || fail 'inventory update retained removed skill files'
run_agents_area "$update_home" "$fixture" check
run_agents_area "$update_home" "$fixture" remove
assert_empty_home "$update_home"
pass

# Whole-directory ownership and bridge leaves fail closed before mutation.
conflict_home="$(new_home agents-skill-conflict)"
mkdir -p "$conflict_home/.agents/skills/grilling"
printf 'foreign\n' > "$conflict_home/.agents/skills/grilling/EXTRA"
expect_agents_failure 'unmanaged managed-skill directory conflict' "$conflict_home" "$REPO_DIR" check
[[ "$(< "$conflict_home/.agents/skills/grilling/EXTRA")" == foreign ]] || fail 'skill conflict was modified'

conflict_home="$(new_home agents-bridge-conflict)"
mkdir -p "$conflict_home/.config/opencode"
printf 'foreign\n' > "$conflict_home/.config/opencode/AGENTS.md"
expect_agents_failure 'unrelated destination conflict' "$conflict_home" "$REPO_DIR" check
[[ "$(< "$conflict_home/.config/opencode/AGENTS.md")" == foreign ]] || fail 'bridge conflict was modified'

printf 'extra\n' > "$home/.agents/skills/grilling/EXTRA"
expect_agents_failure 'extra file in managed skill directory' "$home" "$REPO_DIR" check
rm "$home/.agents/skills/grilling/EXTRA"
pass

# A post-bridge failure rolls back canonical targets, bridges, state, and scaffolding.
rollback_home="$(new_home agents-rollback)"
if TEST_OUTPUT="$(run_agents_area "$rollback_home" "$REPO_DIR" apply after-agents-bridges 2>&1)"; then
  fail 'agents fault injection unexpectedly succeeded'
fi
assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'agents'"
assert_empty_home "$rollback_home"
pass

# Reapply from a moved checkout rewrites package links and bridge state.
fixture="$(copy_repo_fixture agents-moved-one)"
moved_home="$(new_home agents-moved)"
run_agents_area "$moved_home" "$fixture" apply
moved="$TEST_ROOT/fixture-agents-moved-two"
cp -a "$fixture" "$moved"
rm -rf -- "$fixture"
run_agents_area "$moved_home" "$moved" apply
[[ "$(realpath "$moved_home/.agents/AGENTS.md")" == \
  "$moved/packages/common/agents/.agents/AGENTS.md" ]] || fail 'moved checkout did not rewrite canonical link'
[[ "$(realpath "$moved_home/.claude/CLAUDE.md")" == \
  "$moved/packages/common/agents/.agents/AGENTS.md" ]] || fail 'moved checkout did not reconcile bridge ownership'
pass

# Removal consumes bridges before canonical links and preserves unrelated content.
run_agents_area "$home" "$REPO_DIR" remove
[[ ! -e "$home/.config/opencode/AGENTS.md" && ! -L "$home/.config/opencode/AGENTS.md" ]] || \
  fail 'removal retained OpenCode bridge'
[[ ! -e "$home/.claude/CLAUDE.md" && ! -L "$home/.claude/CLAUDE.md" ]] || fail 'removal retained Claude bridge'
[[ ! -e "$home/.agents/AGENTS.md" && ! -L "$home/.agents/AGENTS.md" ]] || fail 'removal retained canonical AGENTS.md'
[[ "$(< "$home/.agents/skills/unrelated/KEEP")" == 'keep skill' && \
  "$(< "$home/.config/opencode/settings.json")" == 'keep opencode' && \
  "$(< "$home/.claude/settings.json")" == 'keep claude' ]] || fail 'removal changed unrelated parent content'
[[ ! -e "$state" ]] || fail 'removal retained agents state'
pass

printf 'PASS: %d agents tests\n' "$TEST_COUNT"
