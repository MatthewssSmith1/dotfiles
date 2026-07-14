# Dotfiles

Opinionated zsh, Git, Neovim, and tmux configuration managed with
[GNU Stow](https://www.gnu.org/software/stow/).

## Includes

- zsh with vi mode, Zinit, Powerlevel10k, aliases, and tool initialization
- Git defaults with private identity stored outside the repository
- Neovim based on Kickstart
- tmux with persistent layouts and AI assistant session restoration

## Setup

Tested primarily on Ubuntu 22.04+ and Ubuntu under WSL. Install the system
prerequisites first:

```bash
sudo apt-get update
sudo apt-get install -y build-essential ca-certificates curl fd-find fzf gh git jq ripgrep stow tar tmux unzip zsh
```

Clone and bootstrap:

```bash
git clone https://github.com/MatthewssSmith1/dotfiles.git ~/dotfiles
GIT_USER_NAME='Your Name' GIT_USER_EMAIL='you@example.com' ~/dotfiles/bootstrap.sh
```

Run the non-mutating preflight separately with:

```bash
~/dotfiles/bootstrap.sh --check
```

Bootstrap is user-scoped, refuses to run as root, and does not install system
packages or change the login shell. It is safe to rerun and fails rather than
overwrite unmanaged files that conflict with Stow.

The script uses [mise](https://mise.jdx.dev/) to install Node.js LTS, pnpm,
Neovim, Claude Code, OpenCode, zoxide, and Worktrunk. It installs Vite+ with its
official installer and bootstraps Zinit on the first zsh startup. Credentials
and service authentication remain manual.

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

Shared Git defaults live in `.gitconfig`; personal identity lives in the
private `~/.gitconfig.local` file. Bootstrap creates that file with restricted
permissions when it is missing or still contains example placeholders. It does
not overwrite an established identity.

Use `.gitconfig.local.example` as the template, or provide `GIT_USER_NAME` and
`GIT_USER_EMAIL` when running bootstrap.

## Commands

| Command | Description |
|---------|-------------|
| `stow .` | Create symlinks |
| `stow -D .` | Remove symlinks |
| `stow -R .` | Refresh symlinks |
| `tests/bootstrap_test.sh` | Run repository checks |
