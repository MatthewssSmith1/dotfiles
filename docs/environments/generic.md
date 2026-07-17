# Generic Linux And VPS

## Status

This document describes planned post-migration behavior. The repository README
remains authoritative until the corresponding implementation stages pass.

Notes for generic Linux hosts — Ubuntu 24.04 and newer is the primary target
platform — including remote VPSs. These hosts will use the generic profile:
pinned Omarchy baseline snapshots plus portability adapters. See
[Architecture](../omarchy-alignment/architecture.md).

## Profile Mapping

- A VPS or other standalone Linux host: generic profile.
- Ubuntu under WSL: WSL profile (generic plus WSL additions); see
  [WSL](wsl.md).
- When connecting to any of these from Windows Terminal (including SSH into
  a VPS), the client-side guidance in
  [Windows Terminal](windows-terminal.md) applies — tmux runs on the host,
  but the keys are intercepted or encoded by the client terminal.

## Manual Package Step

Bootstrap checks and reports dependencies but never invokes `sudo`; fresh
hosts have one explicit manual step, and bootstrap prints one exact command
generated from `manifests/dependencies.tsv` for the selected profile, areas,
operation, and provisioning intent. Review and run that printed command
separately, then repeat the check. For example:

```bash
./bootstrap.sh --check --provision
```

Ubuntu 24.04's tmux is older than the baseline target, so bootstrap uses the
locked prebuilt `aqua:tmux/tmux-builds` mise backend rather than adding source
build dependencies. See
[Deployment](../omarchy-alignment/deployment.md#executable-ownership) for
ownership and [tmux](../omarchy-alignment/tools/tmux.md#runtime-and-terminals)
for interim behavior on unconverged hosts.

## Network Expectations

Network behavior is defined by the canonical
[operation matrix](../omarchy-alignment/deployment.md#operation-and-network-policy).
In particular, `--check`, removal, Bash startup, and tmux startup are offline;
`--check --provision` is also offline and non-mutating, and ordinary apply is
configuration-only. Only explicit `--provision` apply may fetch its printed,
locked runtime-tool plan. No-area provisioning selects Node, pnpm, Claude Code,
Worktrunk, and platform foundations; area-scoped provisioning selects only
dependencies for ready selected areas. The first explicit `nvim` launch may
restore locked plugins under its separate lifecycle.
