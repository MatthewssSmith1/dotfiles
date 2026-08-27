# Agents

## Ownership

The `agents` area deploys one shared personal package on every profile. It owns its Git-versioned files beneath `~/.agents/skills/`, the canonical `~/.agents/AGENTS.md` link, and only these harness bridges:

```text
~/.config/opencode/AGENTS.md -> ../../.agents/AGENTS.md
~/.claude/CLAUDE.md          -> ../.agents/AGENTS.md
```

OpenCode and Claude configuration, plugins, credentials, sessions, generated state, and unrelated skills remain host-owned. Managed skill names are whole-directory boundaries: an unmanaged same-name directory or an extra entry refuses before mutation. Other skill names coexist as external directories or symlinks and survive apply, check, reapply, and removal. In particular, the Omarchy-native `omarchy` and `diagnose-crash` skill symlinks remain native-owned.

## Personal Skills

The globally deployed personal inventory is `grilling`, `handoff`, `writing-for-agents`, and `setup-domain-modeling`. Their complete contents live in [`packages/common/agents`](../../packages/common/agents) and change through normal Git review. The repository-local `applying-dotfiles` and `updating-dependencies` skills remain project-scoped.

[`scripts/agent-skills`](../../scripts/agent-skills) verifies the package inventory, skill frontmatter, regular-file structure, and file modes offline. It does not use a separate lock or schema and does not fetch or update skills.

## Lifecycle

Apply and check are offline:

```bash
dotfiles.sh check agents
dotfiles.sh apply agents
scripts/agent-skills verify
```

The canonical instruction file is regular package content. Stow creates its
home link and all skill-file links with `--no-folding`; the area creates the two
bridges without clobbering existing paths. Exact bridge text and resolution are
derivable ownership, so Agents writes no state. Apply adopts an already exact
bridge, check requires both exact bridges, and removal deletes only exact
bridges before removing the package closure.
