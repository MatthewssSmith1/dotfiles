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
hosts have one explicit manual step, and bootstrap prints the exact command.
That command will be generated from the selected profile and area manifests.
Until those manifests exist, this full-profile command is illustrative rather
than authoritative:

```bash
sudo apt install ca-certificates curl git stow zsh tar unzip \
  fzf zoxide fd-find eza bat ripgrep jq gh
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
apply may fetch pinned runtime tools, and the first explicit `nvim` launch may
restore locked plugins.
