# Dotfiles

Opinionated zsh, Git, Neovim, and tmux configuration. Git is deployed through
profile-aware [GNU Stow](https://www.gnu.org/software/stow/) packages; the
remaining areas retain their legacy links until their migration stages land.

## Includes

- zsh with vi mode, Zinit, Powerlevel10k, aliases, and tool initialization
- Git defaults with private identity stored outside the repository
- Neovim based on Kickstart
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

Bootstrap is user-scoped, refuses to run as root, stays offline, and does not
install packages or change the login shell. Stage 2 deploys only Git. It leaves
existing shell, tmux, Neovim, zsh, agent, application, and authentication state
untouched. Do not run Stow against the repository root; that package is
permanently retired and inert.

To make zsh the login shell, run this separately and start a new login session:

```bash
chsh -s "$(command -v zsh)"
```

Neovim requires version 0.11 or newer and works best with a Nerd Font and a
clipboard provider. See [the Neovim README](.config/nvim/README.md) for details.

## Tmux

Tmux uses [TPM](https://github.com/tmux-plugins/tpm) with
[Resurrect](https://github.com/tmux-plugins/tmux-resurrect),
[Continuum](https://github.com/tmux-plugins/tmux-continuum), and
[Assistant Resurrect](https://github.com/timvw/tmux-assistant-resurrect).
Plugins install automatically on first start, which requires network access.

Sessions save every five minutes and restore when the tmux server starts:

| Key | Action |
|-----|--------|
| `prefix` + `Ctrl-s` | Save manually |
| `prefix` + `Ctrl-r` | Restore manually |
| `prefix` + `U` | Update plugins |

Neovim relaunches in its restored pane and working directory, but editor state
is not preserved. Claude Code, OpenCode, and Codex conversations resume from
their saved session IDs; in-flight work is not restored.

Copy mode uses Vim keys, mouse support, extended scrollback, and OSC 52:

| Key | Action |
|-----|--------|
| `prefix` + `[` | Enter copy mode |
| `v` | Begin selection |
| `y` or `Enter` | Copy selection |
| `prefix` + `]` | Paste the tmux buffer |

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
| `scripts/upstream verify` | Verify the pinned Git snapshot offline |
| `tests/bootstrap_test.sh` | Run repository checks |
