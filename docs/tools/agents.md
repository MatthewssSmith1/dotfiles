# Agents

## Ownership

The `agents` area deploys one shared personal package on every profile. It owns its Git-versioned universal skills beneath `~/.agents/skills/`, Claude-only skills beneath `~/.claude/skills/`, Codex CLI profiles beneath `~/.codex/<name>.config.toml`, the canonical `~/.agents/AGENTS.md` link, and exact harness bridges:

```text
~/.config/opencode/AGENTS.md -> ../../.agents/AGENTS.md
~/.claude/CLAUDE.md          -> ../.agents/AGENTS.md
~/.claude/skills/<universal> -> ../../.agents/skills/<universal>
```

Agents also owns `~/.config/dotfiles/claude/{personal,work}.json`, `~/.local/bin/claude-dotfiles`, and the `claude-personal`/`claude-work` launchers described below.

OpenCode configuration is independently owned only when the optional `opencode` area is applied; see [OpenCode](opencode.md). OpenCode plugins, credentials, sessions, generated state, other Claude configuration (including `~/.claude/settings.json`), synced Claude skills, unrelated skills, and the rest of `~/.codex/` (including `config.toml`) remain host-owned. Managed skill names are whole-directory boundaries: an unmanaged same-name directory or an extra entry refuses before mutation. Universal skill names are also exact Claude aliases and cannot overlap Claude-only skill names. Other skill names coexist as external directories or symlinks and survive apply, check, reapply, and removal. In particular, the Omarchy-native `omarchy` and `diagnose-crash` skill symlinks remain native-owned.

## Claude Code Settings

The minimal, repository-owned personal overlay sets `autoMemoryEnabled` to `false` and empties `attribution.commit` and `attribution.pr`, so Claude adds no co-author trailer to commits and no generated-by footer to pull requests. The work overlay is the personal overlay plus TrueFoundry routing (below). The launcher passes the selected overlay through `--settings`, merging it above normal user/project settings; organization-managed settings retain higher precedence. Plugins, credentials, and writable user preferences stay host-owned.

```text
claude                        -> managed interactive Bash dispatch by agent-profile
cx-personal / cx-work         -> explicit named profile
claude-personal|claude-work   -> claude-dotfiles <profile> -> native claude
command claude                -> native bypass from interactive Bash
```

`agent-profile` selects personal or work for both `claude` and `opencode`; see [OpenCode](opencode.md#profiles-and-launching). Personal falls back to native Claude when the launcher is absent. The Bash function is not exported. `claude-dotfiles` requires `personal` or `work` first, preserves the remaining arguments and exit status, requires a native executable, and rejects caller `--settings` options before `--`; use the native bypass for an alternative settings file. Dotfiles does not install or require Claude during deployment.

### Work: TrueFoundry

Work sends every request through the TrueFoundry gateway using only the TFY key, on the metered `claude-group/` route (the same route OpenCode work uses). It does not use a Claude subscription seat. The overlay sets `ANTHROPIC_BASE_URL`, pins the opus/sonnet/haiku/fable aliases to Opus, Sonnet, and Haiku 5.5 and Fable 5.1, maps those IDs to `claude-group/<id>` through `modelOverrides` so Claude Code still recognizes them, and disables experimental betas for the gateway.

The key is never in a settings file or argument list. The work launcher uses an inherited `TFY_API_KEY`, otherwise re-executes once through `dotfiles-secret exec-env truefoundry` (see [Local Environment Bundles](secrets.md)), otherwise fails closed. It exports the key only as `ANTHROPIC_AUTH_TOKEN`, which takes precedence over the stored claude.ai login without replacing it, and clears `TFY_API_KEY`, `ANTHROPIC_API_KEY`, and `CLAUDE_CODE_OAUTH_TOKEN`. Personal clears `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, and `TFY_API_KEY`, so it keeps the claude.ai login.

Both profiles share `~/.claude`, including the claude.ai login, history, and plugins. **Do not run `/logout` in a work session**: it revokes the shared login used by personal. Features tied to the claude.ai login (claude.ai connectors, Remote Control, cloud sessions, voice) are unavailable in work.

IDE/Desktop launches do not pass through this launcher. To apply the same preferences for clients reading user settings, set `"autoMemoryEnabled": false` and `"attribution": {"commit": "", "pr": ""}` in the host-owned `~/.claude/settings.json`, preserving its other keys. Existing memory files remain intact. Start a fresh shell after deploying Bash changes and restart Claude Code to load changed settings.

Apply and removal retire the exact link left by the earlier single `settings.json` overlay; check reports it. Removing Agents deletes its exact overlay/launcher links along with its other managed payloads and bridges. It preserves the user settings file, so a manually configured user preference remains in effect.

## Personal Skills

The globally deployed universal inventory is `discuss`, `grilling`, `handoff`, `retro`, `writing-for-agents`, and `setup-repo-skills`; Claude sees the same directories through exact aliases. The Claude-only inventory is `codex-subagent`, with its companion reference `parallel-worktrees.md`; `codex-subagent` invokes Codex through the package-owned `subagent` profile (`~/.codex/subagent.config.toml`). Their complete contents live in [`packages/common/agents`](../../packages/common/agents) and change through normal Git review. The repository-local `applying-dotfiles` and `updating-dependencies` skills remain project-scoped.

[`scripts/agent-skills`](../../scripts/agent-skills) verifies the package inventory, skill frontmatter, regular-file structure, and file modes offline. It does not use a separate lock or schema and does not fetch or update skills.

## Lifecycle

Apply and check are offline:

```bash
dotfiles.sh check agents
dotfiles.sh apply agents
scripts/agent-skills verify
```

The canonical instruction file, Claude-only skills, and Codex profiles are regular package content. Stow creates their home links and all universal skill-file links with `--no-folding`; the area creates instruction bridges and per-skill Claude aliases without clobbering existing paths. Exact link text and resolution are derivable ownership, so Agents writes no state. Apply adopts already exact bridges, check requires them, and removal deletes only exact bridges before removing the package closure.
