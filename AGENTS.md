# Agent Instructions

Code and manifests are the source of truth; docs explain intent and stay terse. Do not restate in docs what the code already carries.

## Invariants

- Never run Stow against the repository root; that package is retired.
- `dotfiles.sh` is user-scoped: it never invokes sudo, never installs distro
  packages, and never changes the login shell.
- Dotfiles apply, check, and remove are always offline and fetch nothing.

## Testing

- Prefer the smallest relevant suites during development and for isolated area
  changes; use the routing table in `tests/README.md`.
- Run `tests/run.sh` before committing cross-cutting changes: `dotfiles.sh`,
  shared deployment code, test infrastructure, shared schemas or
  topology, upstream refreshes, or changes spanning several areas.
- An isolated area change needs `tests/contract_test.sh` and its area suite;
  the full suite is not required unless the change widens beyond that area.

## Layout

- `packages/`, `profiles/`, `lib/`, `dotfiles.sh` - Stow deployment for
  Ubuntu and Omarchy hosts.
- `windows/` — Windows-host configuration; see `windows/AGENTS.md`.
- `docs/` — architecture, deployment, and upstream contracts;
  `docs/tools/` per-tool contracts; `docs/artifacts/` preserved package
  evidence; `docs/environments/` per-environment notes (omarchy, ubuntu,
  windows-terminal); `docs/deferred.md` future work.

Configuration changes deploy through the apply procedures in the `applying-dotfiles` skill (`.agents/skills/applying-dotfiles/SKILL.md`). Upstream pin refreshes follow the `updating-dependencies` skill.
