# Generic Linux And VPS

## Status

This document describes the current shell and Git behavior plus later migration
stages. The repository README remains authoritative for area readiness.

Notes for generic Linux hosts — Ubuntu 24.04 and newer is the primary target
platform — including remote VPSs. These hosts will use the generic profile:
pinned Omarchy baseline snapshots plus portability adapters. See
[Architecture](../omarchy-alignment/architecture.md).

Stage 6 preserves existing regular Bash startup files rather than replacing
them: a prepended managed `.bashrc` block runs the dispatcher and bypasses the
preserved legacy remainder, while a state-stable login block uses the first
existing `.bash_profile`, `.bash_login`, or `.profile`. Removal restores
pre-existing bytes and modes exactly. The detailed attachment and load-order
contract is in [Shell](../omarchy-alignment/tools/shell.md). Git, Bash, tmux,
Neovim, and transitional zsh are ready and default-selected.

The ready Stage 7 tmux package uses
`~/.config/tmux/tmux.conf` as an XDG
dispatcher and keeps the byte-identical Omarchy baseline private at
`~/.config/dotfiles/upstream/tmux/tmux.conf`. It then loads the generic adapter
and common persistence, with no host-local layer. A fresh host provisions the
locked runtime and plugin closure explicitly before configuration apply.

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
dependencies for selected areas. Only
`bootstrap.sh --provision --area tmux` may provision the exact locked tmux
plugin closure; no-area provisioning selects the executable foundation but not
plugins. The first explicit `nvim` launch may
restore locked plugins under its separate lifecycle.

Managed Bash startup is always offline. The only shell-startup network exception
is transitional zsh's first start when its Zinit entrypoint is absent; an
initialized zsh startup is offline. Bootstrap never changes the login shell.

## Validated Environments

### Amazon EC2 Ubuntu 24.04

Validated on 2026-07-20 with Ubuntu 24.04.4 LTS, x86_64, and the
`6.17.0-1019-aws` kernel. Automatic host detection selected `generic`.

Acceptance covered:

- Migration of legacy repository-root Stow links into independent Git, Bash,
  tmux, Neovim, and transitional zsh areas.
- Exact distro ownership for `zoxide`, `eza`, `bat`/`batcat`, and `fd`/`fdfind`.
- Locked, receipted Node 24.18.0, pnpm 11.13.1, Claude Code 2.1.212,
  Worktrunk 0.68.0, tmux 3.7b, Neovim 0.12.4, and Starship 1.26.0.
- Offline area checks, two ordinary configuration-only applies, and the full
  no-area provisioning check.
- Bash interactive and login startup, initialized zsh startup, Git identity and
  credential layering, an isolated and default tmux 3.7b server, pinned Neovim
  plugin restore, and headless `:checkhealth`.

Ubuntu's AppArmor 4 policy had
`kernel.apparmor_restrict_unprivileged_userns=1`, so the denied-network
validation sandboxes required a persistent executable-scoped profile for
`/usr/bin/unshare` with `flags=(unconfined) { userns, }`. This is narrower than
disabling the kernel restriction globally, but applies to every caller of that
executable rather than only this repository or account.

This native VPS acceptance is distinct from the Ubuntu 24 WSL validation. It
does not cover graphical applications, Wayland clipboard integration, local
font rendering, terminal-client key translation, or native Omarchy package and
refresh behavior. Native Omarchy acceptance remains deferred.
