# Ubuntu Linux And VPS

## Status

This document describes current Ubuntu-profile behavior. `manifests/areas.tsv` remains authoritative for area readiness.

Ubuntu 24.04 and newer, including remote VPSs, uses the `ubuntu` profile: pinned Omarchy baseline snapshots plus portability adapters. See [Architecture](../architecture.md).

Dotfiles keeps `.bashrc` host-owned and appends one exact managed source block. It does not modify login files. When the account login shell is Bash, the host must provide `~/.profile`, `~/.bash_profile`, or `~/.bash_login`; the recommended host-owned `~/.profile` sources `~/.bashrc`. Preflight reports a missing login file but never creates one. Removal deletes only the managed block and links. The desktop area is validation-only and never reproduces or writes Omarchy desktop configuration. See [Shell](../tools/shell.md).

The tmux area uses `~/.config/tmux/tmux.conf` as an XDG dispatcher and keeps the byte-identical Omarchy baseline private at `~/.config/dotfiles/upstream/tmux/tmux.conf`. The Ubuntu adapter replaces only the Omarchy-specific help command with a portable static popup. The package-only area writes no ownership state.

## Profile Mapping

- A VPS or other standalone Ubuntu host: `ubuntu` profile.
- WSL: refused before any write.
- When connecting to any of these from Windows Terminal (including SSH into
  a VPS), the client-side guidance in
  [Windows Terminal](windows-terminal.md) applies — tmux runs on the host,
  but the keys are intercepted or encoded by the client terminal.

## Manual Package Step

Dotfiles checks and reports dependencies but never invokes `sudo`; review and
run its exact manual package or mise guidance separately, then repeat check.

```bash
./dotfiles.sh check
```

Ubuntu accepts package-owned `/usr/bin/tmux` at version 3.5 or newer. Otherwise install `aqua:tmux/tmux-builds@3.7c` manually; dotfiles does not fetch it. See [tmux](../tools/tmux.md).

## Network Expectations

Network behavior is defined by the canonical [operation matrix](../deployment.md#network-boundaries). Dotfiles and shell, tmux, and ordinary Neovim startup are offline. Exact mise fallbacks are installed manually, Neovim plugin restoration is one explicit helper invocation, and Herdr may refresh its agent-detection manifest during application runtime while keeping version checks disabled.

Managed Bash startup is always offline. Dotfiles never changes the login shell.

Claude Code, Codex, and OpenCode use vendor-native user installations on this profile. They may update through their own lifecycle, but dotfiles does not install, require, inspect, or update them. The optional OpenCode area supplies a wrapper and configuration without owning the underlying executable.

Codex installation is an explicit host-administration step. Review [OpenAI's current Codex CLI instructions](https://developers.openai.com/codex/cli/) before invoking the vendor installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

The installer and later `codex login` remain outside dotfiles. Codex absence is not drift, and `~/.codex` configuration, credentials, sessions, and logs remain host-owned.

Optional child-only injection from persistent, host-owned environment bundles
is documented in [Local environment bundles](../tools/secrets.md). The launcher
is offline and read-only; dotfiles does not create, inspect, or remove real
bundles or application wrappers.

## Validated Environments

### Amazon EC2 Ubuntu 24.04

Validated on 2026-07-20 with Ubuntu 24.04.4 LTS, x86_64, and the `6.17.0-1019-aws` kernel. This predates the profile rename from `generic` to `ubuntu`.

Acceptance covered:

- Migration of legacy repository-root Stow links into independent areas.
- Exact distro ownership for `zoxide`, `eza`, `bat`/`batcat`, and `fd`/`fdfind`.
- Pre-cutover Node 24.18.0, pnpm 11.13.1, Claude Code 2.1.212,
  Worktrunk 0.68.0, tmux, Neovim 0.12.4, and Starship 1.26.0.
- Offline area checks and two ordinary configuration-only applies.
- Bash interactive startup, Git identity and
  credential layering, an isolated and default tmux server, pinned Neovim
  plugin restore, and headless `:checkhealth`.

Ubuntu's AppArmor 4 policy had `kernel.apparmor_restrict_unprivileged_userns=1`, so the denied-network validation sandboxes required a persistent executable-scoped profile for `/usr/bin/unshare` with `flags=(unconfined) { userns, }`. This is narrower than disabling the kernel restriction globally, but applies to every caller of that executable rather than only this repository or account.

This native VPS acceptance is distinct from native Omarchy validation. It does not cover graphical applications, Wayland clipboard integration, local font rendering, terminal-client key translation, or native Omarchy package and refresh behavior. Native Omarchy acceptance is recorded separately in [Omarchy](omarchy.md).
