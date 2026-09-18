# Agents

## Ownership

The `agents` area deploys one shared personal package on every profile. It owns its Git-versioned universal skills beneath `~/.agents/skills/`, Claude-only skills beneath `~/.claude/skills/`, Codex CLI profiles beneath `~/.codex/<name>.config.toml`, the canonical `~/.agents/AGENTS.md` link, and exact harness bridges:

```text
~/.config/opencode/AGENTS.md -> ../../.agents/AGENTS.md
~/.claude/CLAUDE.md          -> ../.agents/AGENTS.md
~/.claude/skills/<universal> -> ../../.agents/skills/<universal>
```

Agents also owns `~/.config/dotfiles/claude/settings.json` and `~/.local/bin/claude-dotfiles`, the Claude Code settings overlay and launcher described below.

OpenCode configuration is independently owned only when the optional `opencode` area is applied; see [OpenCode](opencode.md). OpenCode plugins, credentials, sessions, generated state, other Claude configuration (including `~/.claude/settings.json`), synced Claude skills, unrelated skills, and the rest of `~/.codex/` (including `config.toml`) remain host-owned. Managed skill names are whole-directory boundaries: an unmanaged same-name directory or an extra entry refuses before mutation. Universal skill names are also exact Claude aliases and cannot overlap Claude-only skill names. Other skill names coexist as external directories or symlinks and survive apply, check, reapply, and removal. In particular, the Omarchy-native `omarchy` and `diagnose-crash` skill symlinks remain native-owned.

## Claude Code Settings

The minimal, repository-owned overlay sets `autoMemoryEnabled` to `false`. The launcher passes it through `--settings`, merging it above normal user/project settings; organization-managed settings retain higher precedence. Model choices, plugins, credentials, and writable user preferences stay host-owned.

```text
claude           -> managed interactive Bash dispatch -> claude-dotfiles -> native claude
claude-dotfiles  -> explicit managed launch, including scripts/noninteractive shells
command claude  -> native bypass from interactive Bash
```

The Bash function falls back to native Claude when the launcher is absent. It is not exported. The launcher preserves arguments and exit status, requires a native executable, and rejects caller `--settings` options before `--`; use the native bypass for an alternative settings file. Dotfiles does not install or require Claude during deployment.

IDE/Desktop launches do not pass through this launcher. To disable automatic memory for clients reading user settings, set `"autoMemoryEnabled": false` in the host-owned `~/.claude/settings.json`, preserving its other keys. Existing memory files remain intact. Start a fresh shell after deploying Bash changes and restart Claude Code to load changed settings.

Removing Agents deletes its exact overlay/launcher links along with its other managed payloads and bridges. It preserves the user settings file, so a manually configured user preference remains in effect.

## Personal Skills

The globally deployed universal inventory is `grilling`, `handoff`, `writing-for-agents`, and `setup-domain-modeling`; Claude sees the same directories through exact aliases. The Claude-only inventory is `codex-subagent`, with its companion reference `parallel-worktrees.md`; it invokes Codex through the package-owned `subagent` profile (`~/.codex/subagent.config.toml`). Their complete contents live in [`packages/common/agents`](../../packages/common/agents) and change through normal Git review. The repository-local `applying-dotfiles` and `updating-dependencies` skills remain project-scoped.

[`scripts/agent-skills`](../../scripts/agent-skills) verifies the package inventory, skill frontmatter, regular-file structure, and file modes offline. It does not use a separate lock or schema and does not fetch or update skills.

## Lifecycle

Apply and check are offline:

```bash
dotfiles.sh check agents
dotfiles.sh apply agents
scripts/agent-skills verify
```

The canonical instruction file, Claude-only skills, and Codex profiles are regular package content. Stow creates their home links and all universal skill-file links with `--no-folding`; the area creates instruction bridges and per-skill Claude aliases without clobbering existing paths. Exact link text and resolution are derivable ownership, so Agents writes no state. Apply adopts already exact bridges, check requires them, and removal deletes only exact bridges before removing the package closure.
