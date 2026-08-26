# Dotfiles

Opinionated Bash, Git, Neovim, tmux, and agent configuration. [GNU Stow](https://www.gnu.org/software/stow/) deploys explicit area packages. Ubuntu receives pinned baselines and adapters; native Omarchy keeps installed baselines and attaches shared personal fragments.

## Includes

- Bash with Starship, fzf, zoxide, mise activation, and the pinned Omarchy
  shell behavior
- Git defaults with private identity stored outside the repository
- Neovim based on pinned LazyVim and Omarchy release inputs
- tmux with the reviewed Omarchy v4 interaction model and portable Ubuntu help
- Pinned personal agent skills and shared OpenCode/Claude instructions
- Herdr, package-owned on Omarchy and selected exactly through mise on Ubuntu
- Native Omarchy desktop ownership limited to natural touchpad scrolling and
  shell idle thresholds
- Windows Terminal theming applied from the Windows host

## Profiles

`dotfiles.sh` auto-detects `omarchy` or `ubuntu`. Ubuntu 24.04 and newer deploys pinned snapshots plus adapters. WSL is detected and refused. See [Architecture](docs/architecture.md).

## Setup

Ubuntu 24.04 and newer is the portable target. Dotfiles reports missing dependencies and prints the exact manual `apt-get` command; it never invokes `sudo` itself.

Clone and apply:

```bash
git clone https://github.com/MatthewssSmith1/dotfiles.git ~/dotfiles
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' ~/dotfiles/dotfiles.sh apply git
```

Run the non-mutating preflight separately with:

```bash
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' \
  ~/dotfiles/dotfiles.sh check git
```

Dotfiles is user-scoped, refuses to run as root, never fetches or installs packages, and does not change the login shell. Apply, check, and removal stay offline, and dotfiles preserves unrelated shell, agent, application, and authentication state. All eight areas are ready and selected by default; selection and skip rules are in [Architecture](docs/architecture.md#areas).

Applying `tools` deploys the relocatable `~/.local/bin/dotfiles` launcher. It
has the same interface as `dotfiles.sh`, so subsequent commands can use
`dotfiles check`, `dotfiles apply desktop`, or `dotfiles list`.

Bash is the only managed shell. Dotfiles never changes the account login shell; see the [shell contract](docs/tools/shell.md).

Ubuntu version-sensitive tools use exact area-owned mise selectors installed manually outside dotfiles. Neovim uses the exact `aqua:neovim/neovim@0.12.4` selector and an explicit network-capable `nvim-restore`; see [the Neovim contract](docs/tools/neovim.md).

## tmux

Native Omarchy tmux is validation-only. Ubuntu deploys the exact v4 snapshot,
a portable popup-help adapter, and the selector
`aqua:tmux/tmux-builds@3.7c`; install that fallback manually when the distro
runtime is older than 3.5. Dotfiles never installs tmux or manages plugins,
resurrect data, sockets, or sessions. See the [tmux contract](docs/tools/tmux.md).

## Windows Host

Windows is a supported environment through [windows/](windows/README.md): repo-managed Windows Terminal theming applied by a merge script run manually from a Windows shell, outside dotfiles and Stow. The manual [Windows Terminal unbinds](docs/environments/windows-terminal.md) still apply.

The repository contains in-repo symlinks (`CLAUDE.md`, `.claude/skills`); a Windows clone needs Developer Mode (or an elevated Git) so `core.symlinks` materializes them as real links.

## Git Identity

The pinned Omarchy baseline is deployed to `~/.config/git/config`, while shared personal settings live under `~/.config/dotfiles/personal/`. The regular `~/.gitconfig` entrypoint loads those settings, private identity from the external mode-`0600` `~/.gitconfig.local`, and optional host settings from `~/.config/dotfiles/local/git.conf`.

Use `.gitconfig.local.example` as the template, or provide `GIT_USER_NAME` and `GIT_USER_EMAIL` when running dotfiles.

## Upstream Pins

The Omarchy core, LazyVim starter, and Omarchy Neovim overlay are pinned as immutable commits in `manifests/sources.json`, with the released `lazy-lock.json` preserved as a hash-verified artifact ([evidence](docs/artifacts/README.md)). `scripts/upstream verify` proves the committed snapshot offline; `scripts/upstream sync --proposal <file>` is the only networked baseline operation. Refreshing pins follows the `updating-dependencies` skill. See [Upstream](docs/upstream.md).

## Commands

| Command | Description |
|---------|-------------|
| `dotfiles.sh check git` | Check Git deployment without mutation |
| `dotfiles.sh apply git` | Apply the Git area |
| `dotfiles.sh apply git bash tmux` | Apply several areas |
| `dotfiles.sh remove git` | Remove managed Git links and includes |
| `dotfiles.sh apply agents` | Deploy pinned skills and global instruction bridges |
| `dotfiles.sh apply herdr` | Validate native Herdr or deploy the Ubuntu config/helpers/selector |
| `dotfiles.sh apply desktop` | Apply native desktop differences or validate the Ubuntu boundary |
| `dotfiles.sh list` | List profiles and areas without requiring a supported host |
| `scripts/agent-skills verify` | Verify the vendored skill closure offline |
| `scripts/upstream verify` | Verify all pinned upstream snapshots offline |
| `tests/run.sh` | Run exhaustive repository checks ([test routing](tests/README.md)) |

## Documentation

- [Architecture](docs/architecture.md) — layers, profiles, areas, ownership
- [Deployment](docs/deployment.md) — packages, command contract, network
  policy, state, native attachments
- [Upstream](docs/upstream.md) — source pins, snapshots, synchronization
- Tool contracts: [Git](docs/tools/git.md), [Shell](docs/tools/shell.md),
  [Local environment bundles](docs/tools/secrets.md), [tmux](docs/tools/tmux.md), [Neovim](docs/tools/neovim.md),
  [Agents](docs/tools/agents.md)
- Environments: [Omarchy](docs/environments/omarchy.md),
  [Ubuntu Linux](docs/environments/ubuntu.md),
  [Windows Terminal](docs/environments/windows-terminal.md)
- [Deferred work](docs/deferred.md)
