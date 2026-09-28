local theme = require("config.dotfiles_theme")

return {
  { "folke/tokyonight.nvim", priority = 1000 },
  { "neanias/everforest-nvim", priority = 1000, config = function()
    require("everforest").setup({ background = theme.resolve().background or "medium" })
  end },
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "LazyVim/LazyVim", opts = function(_, opts)
    if vim.env.DOTFILES_NVIM_PROVISIONING == "1" then
      -- The selected plugin may not have been cloned on a fresh apply yet.
      opts.colorscheme = "habamax"
    else
      opts.colorscheme = theme.resolve().colorscheme
      theme.watch()
    end
  end },
}
