# Dotfiles

Personal dotfiles for zsh, Git, and Neovim, managed with [GNU Stow](https://www.gnu.org/software/stow/).

This is my working setup. It is public for reference and reuse, but intentionally opinionated.

## Includes

- zsh config with vi mode, history, Zinit, Powerlevel10k, aliases, and tool initialization
- Git config with private identity loaded from `~/.gitconfig.local`
- Neovim config based on Kickstart

## Requirements

- zsh
- Git
- GNU Stow
- GitHub CLI (`gh`) for GitHub HTTPS authentication

Zinit is bootstrapped automatically on first zsh startup.

Recommended tools:

- Neovim
- zoxide
- fzf
- mise
- Bun / pnpm

Optional personal integrations include `opencode`, `claude`, `wt`, `flyctl`, `go`, `zed`, and Vite+.

## Setup (Debian/Ubuntu/WSL)

These setup commands assume Debian, Ubuntu, or WSL. Other platforms may need different package-manager commands.

```bash
sudo apt update
sudo apt install git stow zsh

git clone https://github.com/MatthewssSmith1/dotfiles.git ~/dotfiles
cd ~/dotfiles

cp .gitconfig.local.example .gitconfig.local
$EDITOR .gitconfig.local

stow .
chsh -s "$(command -v zsh)"
```

Restart the shell after changing the default shell.

Back up or remove existing files such as `~/.zshrc`, `~/.gitconfig`, and `~/.config/nvim` before running `stow .`; Stow will fail rather than overwrite conflicting files.

The Neovim config works best with common Kickstart dependencies: `ripgrep`, `fd`, `unzip`, `make`/`gcc`, a clipboard provider, and a Nerd Font. See `.config/nvim/README.md` for details.

## Git Identity

The committed `.gitconfig` contains shared Git defaults only.

Personal identity is loaded from:

```text
~/.gitconfig.local
```

The repo includes `.gitconfig.local.example`; the real `.gitconfig.local` is ignored.

## Commands

| Command | Description |
|---------|-------------|
| `stow .` | Create symlinks |
| `stow -D .` | Remove symlinks |
| `stow -R .` | Restow / refresh symlinks |
