# Agent Instructions

Code and manifests are the source of truth; docs explain intent and stay terse. Do not restate in docs what the code already carries.

## Invariants

- Never run Stow against the repository root; that package is retired.
- `bootstrap.sh` is user-scoped: it never invokes sudo, never installs distro
  packages, and never changes the login shell.
- Ordinary apply and check stay offline; only an explicit `--provision` may
  fetch, and only from its checksum-locked plan.
- Run `tests/bootstrap_test.sh` before committing changes to `bootstrap.sh`,
  `lib/`, or `packages/`.

## Layout

- `packages/`, `profiles/`, `lib/`, `bootstrap.sh` — Stow deployment for
  Linux and WSL hosts.
- `windows/` — Windows-host configuration; see `windows/AGENTS.md`.
- `docs/` — architecture, deployment, and upstream contracts;
  `docs/tools/` per-tool contracts; `docs/artifacts/` preserved package
  evidence; `docs/environments/` per-environment notes (omarchy, generic,
  wsl, windows-terminal); `docs/deferred.md` future work.

Configuration changes deploy through the apply procedures in the `applying-dotfiles` skill (`.agents/skills/applying-dotfiles/SKILL.md`). Upstream pin refreshes follow the `updating-dependencies` skill.
