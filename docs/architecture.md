# Architecture

Configuration separates pinned upstream baselines, Ubuntu portability adapters,
shared personal settings, and untracked host-local data. Native Omarchy keeps
its package-owned baselines; Ubuntu 24.04 and newer deploys reviewed snapshots.

## Profiles

`omarchy` requires exact native Omarchy v4 signals and package authority.
`ubuntu` requires non-WSL Ubuntu 24.04 or newer. A Microsoft kernel marker is
detected first and refused; WSL has no profile or payload. Explicit profile
overrides cannot cross the detected host class.

## Areas

The manifest defines eight default-ready areas: Git, tools, Bash, tmux, Neovim,
agents, Herdr, and desktop. Every area uses the lean engine. Desktop is native
Omarchy ownership and validation-only on Ubuntu. Default removal combines
package-only derivation with recorded ownership; the retired state namespace is
never interpreted as ownership.

## Ownership

Tracked payloads deploy as explicit qualified packages beneath `packages/`.
Host-local files remain regular files beneath `~/.config/dotfiles/local/`.
Native refresh-managed files remain regular Omarchy-owned files and receive
only exact guarded attachments. Ubuntu Bash likewise keeps `.bashrc` host-owned
and attaches one exact source block.

`dotfiles.sh` is user-scoped, never changes the login shell, and keeps
apply/check/remove offline. Networked installation and Neovim restoration are
explicit commands outside dotfiles. Windows Terminal remains a separate
Windows-host concern.
