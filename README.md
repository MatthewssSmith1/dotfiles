# Dotfiles

Personal dotfiles for Omarchy v4 and Ubuntu 24.04+ hosts, deployed through an offline, user-scoped CLI using explicit GNU Stow packages.

Omarchy is the reference Linux environment; Ubuntu reproduces its pinned, reviewed defaults where practical, with shared personal preferences layered on top.

## Environments

- `omarchy` — native Omarchy v4, keeps package-owned baselines and guarded attachments
- `ubuntu` — Ubuntu 24.04+ (non-WSL), pinned snapshots plus portability adapters
- `windows` — Windows Terminal theming from the Windows host (`windows/`)
- WSL is detected and refused

`dotfiles.sh` auto-detects `omarchy` or `ubuntu`; `--profile` can only select within the detected host class.

## Areas

Eight areas are ready by default: `git`, `tools`, `bash`, `tmux`, `nvim`, `agents`, `herdr`, `desktop`. `opencode` is optional and explicitly deploys parallel work/personal configuration. `desktop` is native ownership (natural touchpad scrolling, shell idle thresholds, generated Compose aliases, and a shortcut manager/menu) and validation-only on Ubuntu.

## Quick start

```bash
git clone https://github.com/MatthewssSmith1/dotfiles.git ~/dotfiles
~/dotfiles/dotfiles.sh list
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' ~/dotfiles/dotfiles.sh check git
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' ~/dotfiles/dotfiles.sh apply git
```

Provide identity via `GIT_USER_NAME`/`GIT_USER_EMAIL` or `~/.gitconfig.local` (see [Git](docs/tools/git.md)). Applying `tools` installs the relocatable `~/.local/bin/dotfiles` launcher with the same interface. On Omarchy it also installs separately invoked host-administration helpers for [default pruning and a hardware-gated AMDGPU workaround](docs/environments/omarchy.md).

## Commands

```text
dotfiles.sh apply [--profile omarchy|ubuntu] [area ...]
dotfiles.sh check [--profile omarchy|ubuntu] [area ...]
dotfiles.sh remove [area ...]
dotfiles.sh list
dotfiles.sh help [command]
dotfiles.sh --help
```

An operation is mandatory and must come first; areas are positional. No areas means ready defaults for apply/check and owned defaults for removal; optional areas require an explicit apply/check. `list` and `help` need no supported host.

## Safety

The `dotfiles.sh` deployment lifecycle never runs as root, invokes `sudo` or a distro package manager, installs mise/distro packages, changes the login shell, or uses the network during apply/check/remove. Missing dependencies print exact manual install commands. Separate Omarchy administration helpers are explicit; pruning delegates package removal to Omarchy, while the hardware-gated AMDGPU helper narrowly manages its documented Limine drop-in.

## Documentation

- [Architecture](docs/architecture.md) — profiles, areas, ownership
- [Deployment](docs/deployment.md) — packages, command contract, network/state
- [Upstream](docs/upstream.md) — pinned sources and synchronization
- Environments: [Omarchy](docs/environments/omarchy.md), [Ubuntu](docs/environments/ubuntu.md), [Windows Terminal](docs/environments/windows-terminal.md)
- Tool contracts: [Git](docs/tools/git.md), [GitHub Access](docs/tools/github-access.md), [Shell](docs/tools/shell.md), [tmux](docs/tools/tmux.md), [Neovim](docs/tools/neovim.md), [Agents](docs/tools/agents.md), [Herdr](docs/tools/herdr.md), [OpenCode](docs/tools/opencode.md)
- Testing: [tests/AGENTS.md](tests/AGENTS.md)
- [Deferred work](docs/deferred.md)
