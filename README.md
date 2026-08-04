# Dotfiles

Opinionated Bash, zsh, Git, Neovim, tmux, and agent configuration. [GNU Stow](https://www.gnu.org/software/stow/) is the deployment mechanism for every area on every profile and is a required dependency of `bootstrap.sh`. On generic and WSL hosts it links pinned baselines, adapters, and shared personal layers; on native Omarchy the installed baselines stay untouched, but the shared personal fragments under `~/.config/dotfiles/` are still Stow links that guarded attachments source.

## Includes

- Bash with Starship, fzf, zoxide, mise activation, and the pinned Omarchy
  shell behavior
- zsh with vi mode, Zinit, Powerlevel10k, aliases, and tool initialization,
  retained as a behaviorally frozen escape hatch
- Git defaults with private identity stored outside the repository
- Neovim based on pinned LazyVim and Omarchy release inputs
- tmux with persistent layouts and AI assistant session restoration
- Pinned personal agent skills and shared OpenCode/Claude instructions
- Windows Terminal theming applied from the Windows host

## Profiles

Bootstrap auto-detects the host profile: `omarchy` (native Omarchy machines attach guarded layers to installed baselines), `generic` (Ubuntu 24.04 and newer, including VPSs, deploys pinned snapshots plus adapters), and `wsl` (generic plus a WSL adapter). A validated `--profile` override exists; a profile change is refused until existing deployment state is removed explicitly. See [Architecture](docs/architecture.md).

## Setup

Ubuntu 24.04 and newer, including WSL2, is the primary generic target. Bootstrap reports missing dependencies and prints the exact manual `apt-get` command; it never invokes `sudo` itself.

Clone and bootstrap:

```bash
git clone https://github.com/MatthewssSmith1/dotfiles.git ~/dotfiles
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' ~/dotfiles/bootstrap.sh --area git
```

Run the non-mutating preflight separately with:

```bash
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' \
  ~/dotfiles/bootstrap.sh --check --area git
```

Bootstrap is user-scoped, refuses to run as root, never installs distro packages, and does not change the login shell. Ordinary apply, check, and removal stay offline. Git, Bash, tmux, Neovim, transitional zsh, agents, and Herdr are ready and selected by default; native Omarchy attaches Git, Bash, tmux, and the Neovim personal loader to installed baselines. Default selection skips the transitional zsh area on hosts where zsh is not installed and has never been deployed; explicit `--area zsh` still requires it. Bootstrap preserves unrelated shell, agent, application, and authentication state.

Bash with Starship is the primary configured workflow; the account's zsh login shell is never changed. Generic and WSL Bash use byte-reversible startup-file blocks; native Omarchy uses a separate additive attachment. On a first WSL deployment, bootstrap enforces the operational order: apply `--area bash`, smoke-test it from a separate process, then apply `--area zsh`. A default or combined apply cannot perform both first-time shell deployments; later default applies converge normally. See the [shell contract](docs/tools/shell.md).

## Provisioning

Runtime tools install only through explicit, ownership-aware, checksum-locked provisioning:

```bash
~/dotfiles/bootstrap.sh --check --provision
~/dotfiles/bootstrap.sh --provision
```

Only the second command may fetch the complete printed, checksum-locked plan. Ordinary apply remains configuration-only and both check forms remain offline. Area-scoped `--provision --area <area>` never selects the core personal tool set. See the [deployment contract](docs/deployment.md#bootstrap-contract) and its canonical [operation and network policy](docs/deployment.md#operation-and-network-policy).

Neovim requires version 0.11 or newer and works best with a Nerd Font and a clipboard provider. See [the Neovim contract](docs/tools/neovim.md) for details.

## tmux

A fresh host must first run the complete `--provision --area tmux` lifecycle, which provisions the runtime and receipted plugin closure before configuration preflight and apply:

```bash
~/dotfiles/bootstrap.sh --provision --area tmux
```

Generic and WSL hosts put the dispatcher at `~/.config/tmux/tmux.conf`, loading a private byte-identical Omarchy baseline, the generic adapter, a command-empty WSL adapter where present, and common persistence, then perform guarded TPM initialization as the final action. Native Omarchy keeps its regular baseline and receives only a guarded common-persistence attachment. tmux has no host-local layer.

The exact TPM, Resurrect, Assistant Resurrect, and Continuum commits are in `manifests/tmux-plugins.lock.json`. Startup and ordinary apply/check are offline and never install or update plugins. Removal retains `~/.tmux/plugins/` and `~/.tmux/resurrect/`. See the full [tmux contract](docs/tools/tmux.md) and manual [Windows Terminal unbinds](docs/environments/windows-terminal.md).

## Windows Host

Windows is a supported environment through [windows/](windows/README.md): repo-managed Windows Terminal theming applied by a merge script run manually from a Windows shell, outside bootstrap and Stow. The manual [Windows Terminal unbinds](docs/environments/windows-terminal.md) still apply.

The repository contains in-repo symlinks (`CLAUDE.md`, `.claude/skills`); a Windows clone needs Developer Mode (or an elevated Git) so `core.symlinks` materializes them as real links.

## Git Identity

The pinned Omarchy baseline is deployed to `~/.config/git/config`, while shared personal settings live under `~/.config/dotfiles/personal/`. The regular `~/.gitconfig` entrypoint loads those settings, private identity from the external mode-`0600` `~/.gitconfig.local`, and optional host settings from `~/.config/dotfiles/local/git.conf`.

Use `.gitconfig.local.example` as the template, or provide `GIT_USER_NAME` and `GIT_USER_EMAIL` when running bootstrap.

## Upstream Pins

The Omarchy core, LazyVim starter, and Omarchy Neovim overlay are pinned as immutable commits in `manifests/sources.json`, with the released `lazy-lock.json` preserved as a hash-verified artifact ([evidence](docs/artifacts/README.md)). `scripts/upstream verify` proves the committed snapshot offline; `scripts/upstream sync --proposal <file>` is the only networked baseline operation. Refreshing pins follows the `updating-dependencies` skill. See [Upstream](docs/upstream.md).

## Commands

| Command | Description |
|---------|-------------|
| `bootstrap.sh --check --area git` | Check Git deployment without mutation |
| `bootstrap.sh --area git` | Apply the Git area |
| `bootstrap.sh --area git,bash,tmux` | Apply several areas with one flag |
| `bootstrap.sh --tool git` | `--tool` is an alias for `--area` |
| `bootstrap.sh --remove --area git` | Remove managed Git links and includes |
| `bootstrap.sh --area agents` | Deploy pinned skills and global instruction bridges |
| `bootstrap.sh --area herdr` | Deploy regular Herdr configuration |
| `scripts/agent-skills verify` | Verify the vendored skill closure offline |
| `scripts/upstream verify` | Verify all pinned upstream snapshots offline |
| `scripts/tmux-parser-fixtures validate-lock` | Validate the test-only tmux parser fixture pin offline |
| `scripts/tmux-parser-fixtures sync --root /tmp/opencode/tmux-parser-cache` | Explicitly prepare the locked real tmux 3.2a parser fixture without package installation |
| `tests/tmux_parser_gate.sh --fixture-root /tmp/opencode/tmux-parser-cache` | Run the opt-in real 3.2a/3.4/3.7b parser gate |
| `tests/run.sh` | Run exhaustive repository checks ([test routing](tests/README.md)) |

## Documentation

- [Architecture](docs/architecture.md) — layers, profiles, areas, ownership
- [Deployment](docs/deployment.md) — packages, bootstrap contract, network
  policy, state, native attachments
- [Upstream](docs/upstream.md) — source pins, snapshots, synchronization
- Tool contracts: [Git](docs/tools/git.md), [Shell](docs/tools/shell.md),
  [tmux](docs/tools/tmux.md), [Neovim](docs/tools/neovim.md),
  [Agents](docs/tools/agents.md)
- Environments: [Omarchy](docs/environments/omarchy.md),
  [generic Linux](docs/environments/generic.md),
  [WSL](docs/environments/wsl.md),
  [Windows Terminal](docs/environments/windows-terminal.md)
- [Deferred work](docs/deferred.md)
