# Neovim Config

This Neovim configuration originally came from [dam9000/kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim), which is a modular variant of [nvim-lua/kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim).

This repository is not a fork of either project.

## Requirements

- Neovim stable or nightly
- Git
- `make`, `unzip`, and a C compiler such as `gcc`
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- [fd](https://github.com/sharkdp/fd)
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/tree/master/crates/cli)
- Clipboard provider such as `xclip`, `xsel`, or `win32yank`
- Nerd Font, optional but recommended

## Setup

This is retained legacy migration input and is no longer deployed. The retired
repository-root Stow package must not be run. Deploy the managed generic or WSL
configuration with:

```bash
~/dotfiles/bootstrap.sh --area nvim
```

The first explicit launch restores plugins at the committed lock:

```bash
nvim
```

Use `:Lazy` to inspect plugin status. Later lock changes require an explicit
`~/.local/share/dotfiles/bin/nvim-restore` before ordinary startup.
