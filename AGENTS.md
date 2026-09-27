# Agent Instructions

This repository deploys Matt's user-scoped dotfiles to native Omarchy v4 and Ubuntu 24.04+ hosts, with separate Windows Terminal configuration.

Treat Omarchy as the reference Linux environment: preserve its reviewed behavior on Ubuntu where practical, and keep shared personal preferences as a separate layer.

## Invariants

- Never run Stow against the repository root.
- `dotfiles.sh` runs as the user and never changes the login shell. `apply nvim` may provision native packages with scoped elevation and install user-owned tools/plugins as the user; other areas retain their existing boundaries.
- `check` is read-only and local. `remove` is local and preserves installed tools and application data.

## Validation

- Use the smallest suites listed in `tests/AGENTS.md`.
- Isolated area changes need `tests/contract_test.sh` and the relevant area suite.
- Run `tests/run.sh` for shared deployment code, schemas, topology, test infrastructure, upstream refreshes, or cross-area changes.

## Workflows

- Follow `.agents/skills/applying-dotfiles/SKILL.md` for configuration changes.
- GitHub: before PAT or credential setup, remote writes, pull-request or protected-branch work, or token rotation/revocation, follow `docs/tools/github-access.md`.
- Follow the `updating-dependencies` skill for upstream pin refreshes.
- Changes under `windows/` also follow `windows/AGENTS.md`.
