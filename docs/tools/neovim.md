# Neovim

The accepted baseline combines the pinned LazyVim starter, the independently accepted `omarchy-nvim 2026.8.13-1` overlay/artifact, the Tokyo Night adapter, and one personal option: `relativenumber=true`.

## Native Omarchy

The installed `omarchy-nvim` package owns `~/.config/nvim`; dotfiles never rewrites that baseline or manages native plugins and runtime data. The area validates package-owned `/usr/bin/nvim`, accepted `neovim` package/runtime identities, and the exact accepted `omarchy-nvim` package.

`common/nvim` deploys the personal source outside the refresh-owned tree. One regular guarded loader at `~/.config/nvim/plugin/dotfiles-personal.lua` sources it. Lean v2 state records only the loader pre-state needed for exact removal. After a native refresh removes the loader, rerun `dotfiles.sh apply nvim` to reattach it.

## Ubuntu

Ubuntu deploys `upstream/nvim`, `ubuntu/nvim`, and `common/nvim`. The adapter contains the exact `aqua:neovim/neovim@0.12.4` selector and the explicit `nvim-restore` helper. The area is package-only and writes no deployment state.

Ordinary startup requires an existing lazy.nvim checkout at the commit in the committed `lazy-lock.json`. Missing-plugin installation, the periodic checker, lock updates, Lua rocks, inherited automatic Mason/Treesitter work, and Blink binary downloads are disabled during ordinary startup.

Run `~/.local/share/dotfiles/bin/nvim-restore` explicitly with connectivity to restore plugins. It validates `lazy-lock.json`, fetches and checks out `lazy.nvim` at that exact lock entry, sets `DOTFILES_NVIM_RESTORING=1`, and runs headless `Lazy! restore`. It verifies that the lock bytes remain unchanged. The helper does not write deployment state, invoke callbacks, preserve or rename checkouts, or migrate any runtime root.

Apply, check, and remove never inspect or mutate Neovim data, state, or cache roots. Removal deletes only exact managed package links and, on native Omarchy, the exact personal loader.
