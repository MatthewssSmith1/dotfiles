# Agent Instructions

This repository deploys Matt's user-scoped dotfiles to native Omarchy v4 and Ubuntu 24.04+ hosts, with separate Windows Terminal configuration.

Treat Omarchy as the reference Linux environment: preserve its reviewed behavior on Ubuntu where practical, and keep shared personal preferences as a separate layer.

## Invariants

- Never run Stow against the repository root.
- `dotfiles.sh` never runs as root, invokes `sudo`, installs distro packages, changes the login shell, or uses the network.
- Apply, check, and remove are always offline.

## Validation

- Use the smallest suites listed in `tests/AGENTS.md`.
- Isolated area changes need `tests/contract_test.sh` and the relevant area suite.
- Run `tests/run.sh` for shared deployment code, schemas, topology, test infrastructure, upstream refreshes, or cross-area changes.

## Workflows

- Follow `.agents/skills/applying-dotfiles/SKILL.md` for configuration changes.
- GitHub: before PAT or credential setup, remote writes, pull-request or protected-branch work, or token rotation/revocation, follow `docs/tools/github-access.md`.
- Follow the `updating-dependencies` skill for upstream pin refreshes.
- Changes under `windows/` also follow `windows/AGENTS.md`.
