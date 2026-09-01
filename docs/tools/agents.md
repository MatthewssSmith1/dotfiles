# Agents

## Ownership

The `agents` area deploys one shared personal package on every profile. It owns its Git-versioned universal skills beneath `~/.agents/skills/`, Claude-only skills beneath `~/.claude/skills/`, the canonical `~/.agents/AGENTS.md` link, and exact harness bridges:

```text
~/.config/opencode/AGENTS.md -> ../../.agents/AGENTS.md
~/.claude/CLAUDE.md          -> ../.agents/AGENTS.md
~/.claude/skills/<universal> -> ../../.agents/skills/<universal>
```

OpenCode configuration is independently owned only when the optional `opencode` area is applied; see [OpenCode](opencode.md). OpenCode plugins, credentials, sessions, generated state, other Claude configuration, synced Claude skills, and unrelated skills remain host-owned. Managed skill names are whole-directory boundaries: an unmanaged same-name directory or an extra entry refuses before mutation. Universal skill names are also exact Claude aliases and cannot overlap Claude-only skill names. Other skill names coexist as external directories or symlinks and survive apply, check, reapply, and removal. In particular, the Omarchy-native `omarchy` and `diagnose-crash` skill symlinks remain native-owned.

## Personal Skills

The globally deployed universal inventory is `grilling`, `handoff`, `writing-for-agents`, and `setup-domain-modeling`; Claude sees the same directories through exact aliases. The Claude-only inventory is `codex-subagent`. Their complete contents live in [`packages/common/agents`](../../packages/common/agents) and change through normal Git review. The repository-local `applying-dotfiles` and `updating-dependencies` skills remain project-scoped.

[`scripts/agent-skills`](../../scripts/agent-skills) verifies the package inventory, skill frontmatter, regular-file structure, and file modes offline. It does not use a separate lock or schema and does not fetch or update skills.

## Lifecycle

Apply and check are offline:

```bash
dotfiles.sh check agents
dotfiles.sh apply agents
scripts/agent-skills verify
```

The canonical instruction file and Claude-only skills are regular package content. Stow creates their home links and all universal skill-file links with `--no-folding`; the area creates instruction bridges and per-skill Claude aliases without clobbering existing paths. Exact link text and resolution are derivable ownership, so Agents writes no state. Apply adopts already exact bridges, check requires them, and removal deletes only exact bridges before removing the package closure.
