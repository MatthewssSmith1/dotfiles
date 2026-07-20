# Dotfiles

Opinionated Bash, zsh, Git, Neovim, and tmux configuration. Git, Bash, tmux,
Neovim, and transitional zsh deploy through profile-aware
[GNU Stow](https://www.gnu.org/software/stow/) packages.

## Includes

- zsh with vi mode, Zinit, Powerlevel10k, aliases, and tool initialization
- Git defaults with private identity stored outside the repository
- Neovim based on pinned LazyVim and Omarchy release inputs
- tmux with persistent layouts and AI assistant session restoration

## Setup

Ubuntu 24.04 and newer, including WSL2, is the primary generic target.
Bootstrap reports missing Git-area dependencies and prints the exact manual
`apt-get` command; it never invokes `sudo` itself.

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

Bootstrap is user-scoped, refuses to run as root, never installs distro
packages, and does not change the login shell. Ordinary apply, check, and
removal stay offline. Git, Bash, tmux, Neovim, and transitional zsh are ready
and selected by default on generic and WSL hosts. Native Omarchy Neovim
integration remains deferred to Stage 9. Bootstrap preserves
unrelated shell, agent, application, and authentication state. Do not run Stow
against the repository root; that package is permanently retired and inert.

The accepted Stage 6 contract makes Bash with Starship the primary configured
workflow without changing the account's current zsh login shell. Generic and
WSL Bash use byte-reversible startup-file blocks; native Omarchy uses a
separate additive attachment. Shell rollout is Bash-first and remains gated on
isolated tests and live smoke checks. See the
[shell contract](docs/omarchy-alignment/tools/shell.md).

On a first WSL deployment, bootstrap enforces that operational order: apply
`--area bash`, smoke-test it from a separate process, then apply `--area zsh`.
A default or combined apply cannot perform both first-time shell deployments;
later default applies converge normally after both areas have state.

Stage 5 adds explicit, ownership-aware retained-tool provisioning:

```bash
~/dotfiles/bootstrap.sh --check --provision
~/dotfiles/bootstrap.sh --provision
```

Only the second command may fetch the complete printed, checksum-locked plan.
Ordinary apply remains configuration-only and both check forms remain offline.
Area-scoped `--provision --area <area>` never selects the core personal tool
set. See the
[deployment contract](docs/omarchy-alignment/deployment.md#bootstrap-contract).

Neovim requires version 0.11 or newer and works best with a Nerd Font and a
clipboard provider. See [the Neovim README](.config/nvim/README.md) for details.

## Tmux Stage 7 Contract

tmux is ready after its lifecycle, adversarial, denied-network, and real-parser
automated gates passed. WSL operational acceptance passed after the manual
server transition and Windows Terminal checks. A fresh host must first run the complete
`--provision --area tmux` lifecycle, which provisions the runtime and receipted
plugin closure before configuration preflight and apply. The reviewed root
`.tmux.conf` remains migration input until that first apply.

The implemented generic and WSL design puts the dispatcher at
`~/.config/tmux/tmux.conf`, loads a private byte-identical Omarchy baseline,
generic adapter, command-empty WSL adapter where present, and common persistence,
then performs guarded TPM initialization as the final action. Native Omarchy
keeps its regular baseline and receives only a guarded common-persistence
attachment. tmux has no host-local layer.

The exact TPM, Resurrect, Assistant Resurrect, and Continuum commits are in
`manifests/tmux-plugins.lock.json`. Startup and ordinary apply/check are offline
and never install or update plugins. The sole plugin provisioning apply command
is:

```bash
~/dotfiles/bootstrap.sh --provision --area tmux
```

Removal retains `~/.tmux/plugins/` and `~/.tmux/resurrect/`. See the full
[tmux contract](docs/omarchy-alignment/tools/tmux.md) and manual
[Windows Terminal unbinds](docs/environments/windows-terminal.md).

## Git Identity

The pinned Omarchy baseline is deployed to `~/.config/git/config`, while shared
personal settings live under `~/.config/dotfiles/personal/`. The regular
`~/.gitconfig` entrypoint loads those settings, private identity from the
external mode-`0600` `~/.gitconfig.local`, and optional host settings from
`~/.config/dotfiles/local/git.conf`.

Use `.gitconfig.local.example` as the template, or provide `GIT_USER_NAME` and
`GIT_USER_EMAIL` when running bootstrap.

## Commands

| Command | Description |
|---------|-------------|
| `bootstrap.sh --check --area git` | Check Git deployment without mutation |
| `bootstrap.sh --area git` | Apply the Git area |
| `bootstrap.sh --remove --area git` | Remove managed Git links and includes |
| `scripts/upstream verify` | Verify all pinned upstream snapshots offline |
| `scripts/tmux-parser-fixtures validate-lock` | Validate the test-only tmux parser fixture pin offline |
| `scripts/tmux-parser-fixtures sync --root <cache-root>` | Explicitly prepare the locked real tmux 3.2a parser fixture without package installation |
| `tests/stage7_tmux_parser_compatibility_test.sh --fixture-root <cache-root>` | Run the opt-in real 3.2a/3.4/3.7b parser gate |
| `tests/bootstrap_test.sh` | Run repository checks |
