-- bootstrap lazy.nvim, LazyVim and your plugins
local dotfiles = dofile(vim.fn.expand("~/.config/dotfiles/nvim/generic.lua"))
dotfiles.before_lazy()
require("config.lazy")
dotfiles.after_lazy()
