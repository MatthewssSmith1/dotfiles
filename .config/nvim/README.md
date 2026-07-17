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

This is the retained legacy configuration. Existing links remain usable, but
the retired repository-root Stow package must not be run. Fresh deployment is
deferred until the generic and WSL Neovim migration stage.

Start Neovim and let lazy.nvim install plugins:

```bash
nvim
```

Use `:Lazy` to inspect plugin status.
