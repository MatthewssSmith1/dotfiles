# Dotfiles

Personal dotfiles for zsh, Git, and Neovim, managed with [GNU Stow](https://www.gnu.org/software/stow/).

This is my working setup. It is public for reference and reuse, but intentionally opinionated.

## Includes

- zsh config with vi mode, history, Zinit, Powerlevel10k, aliases, and tool initialization
- Git config with private identity loaded from `~/.gitconfig.local`
- Neovim config based on Kickstart

## Bootstrap

The bootstrap script configures an existing checkout and is tested primarily on
Ubuntu 22.04+ and Ubuntu under WSL. It is strictly user-scoped: it refuses to
run as root and never invokes a privilege escalator, installs system packages,
or changes the login shell.

```bash
git clone https://github.com/MatthewssSmith1/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

To check the checkout and system prerequisites without making changes or using
the network:

```bash
~/dotfiles/bootstrap.sh --check
```

The repository must already be cloned; bootstrap does not clone, pull, reset, or
clean it. It can be run from any current directory and safely rerun after
updates. Reruns converge without duplicating symlinks, shell configuration, or
PATH entries. Tools configured as `latest` or `lts` may advance when rerun.

Before running bootstrap, install its system prerequisites yourself. For Ubuntu
and Debian, one possible manual setup is:

```bash
sudo apt-get update
sudo apt-get install -y build-essential ca-certificates curl fd-find fzf git jq ripgrep stow tar tmux unzip zsh
```

Bootstrap preflights `curl`, `git`, GNU Stow, Zsh, `unzip`, `make`, `gcc`,
`ripgrep`, `fd`/`fdfind`, `fzf`, `jq`, tmux, and `tar`, then reports all missing
commands before making changes. On Debian-family systems it creates a
user-local `fd` symlink to `fdfind` when needed.

It uses [mise](https://mise.jdx.dev/) for Node.js LTS, pnpm, Neovim, Claude
Code, OpenCode, and Worktrunk. Neovim is validated as version 0.11 or newer.
Vite+ is installed with its official installer because it is not in the mise
registry; its Node manager is disabled so mise remains responsible for the
global Node and pnpm versions.

The script does not install Bun, Go, Fly CLI, GitHub CLI, credentials, or
service authentication. Authenticate Claude Code, OpenCode, and GitHub
separately after bootstrap. Zinit is bootstrapped automatically on first Zsh
startup.

Bootstrap does not change the default shell. If desired, do that separately
after setup (for example, with `chsh -s "$(command -v zsh)"`) and start a new
login session.

GNU Stow fails rather than overwrite conflicting unmanaged files. Back up or
remove existing paths such as `~/.zshrc`, `~/.gitconfig`, and
`~/.config/nvim` before rerunning when Stow reports a conflict.
Bootstrap normally restows with `stow -R .`; on older Stow versions affected by
WSL absolute-link scanning bugs, it safely retries with `stow .`.

The Neovim config works best with common Kickstart dependencies: `ripgrep`, `fd`, `unzip`, `make`/`gcc`, a clipboard provider, and a Nerd Font. See `.config/nvim/README.md` for details.

## Git Identity

The committed `.gitconfig` contains shared Git defaults only.

Personal identity is loaded from:

```text
~/.gitconfig.local
```

The repo includes `.gitconfig.local.example`. When `~/.gitconfig.local` is
missing, bootstrap copies the template there with private permissions. Existing
files and valid symlinks are preserved exactly; broken symlinks cause bootstrap
to stop. Replace the generated placeholder name and email before committing.

## Commands

| Command | Description |
|---------|-------------|
| `stow .` | Create symlinks |
| `stow -D .` | Remove symlinks |
| `stow -R .` | Restow / refresh symlinks |
| `tests/bootstrap_test.sh` | Run non-destructive bootstrap checks |
