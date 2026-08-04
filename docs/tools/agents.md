# Agents

## Ownership

The `agents` area deploys one shared personal package on every profile. It owns the pinned files beneath `~/.agents/skills/`, the canonical `~/.agents/AGENTS.md` link, and only these harness bridges:

```text
~/.config/opencode/AGENTS.md -> ../../.agents/AGENTS.md
~/.claude/CLAUDE.md          -> ../.agents/AGENTS.md
```

OpenCode and Claude configuration, plugins, credentials, sessions, generated state, and unrelated skills remain host-owned. Managed skill names are whole-directory boundaries: an unrecorded same-name directory or an extra entry refuses before mutation. Other skill names coexist as real external directories and survive removal.

## Provenance

[`manifests/agent-skills.lock.json`](../../manifests/agent-skills.lock.json) records the reviewed Matt Pocock repository commit and the source tree, file blob, mode, size, and destination of every vendored skill. [`scripts/agent-skills`](../../scripts/agent-skills) proves the local package matches those recorded object identities and exact closure offline; review of a lock update establishes their upstream commit reachability. Bootstrap never fetches or updates skills.

The globally deployed inventory contains `grilling`, `handoff`, `teach`, `writing-great-skills`, `domain-modeling`, `research`, and `setup-matt-pocock-skills`. The repository-local `applying-dotfiles` and `updating-dependencies` skills remain project-scoped shared personal files. Tool-generated `~/.agents/.skill-lock.json` is not deployed; managed skills are updated through a reviewed lock and package change rather than a live installer.

## Lifecycle

Apply and check are offline:

```bash
bootstrap.sh --check --area agents
bootstrap.sh --area agents
scripts/agent-skills verify
```

The canonical instruction file is regular package content. Stow creates its home link and all skill-file links with `--no-folding`; the area then creates both relative harness bridges transactionally. State records bridges before package targets so removal cannot strand a bridge through a removed canonical link. A moved checkout rewrites package links while preserving the stable bridge text.
