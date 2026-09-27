return {
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight-night" } },
  { "nvim-neo-tree/neo-tree.nvim", opts = { window = { width = 25 } } },
  { "folke/snacks.nvim", opts = { scroll = { enabled = false } } },
  { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "css" } } },
  {
    "iamcco/markdown-preview.nvim",
    build = function()
      -- Upstream's async install() returns before its terminal download exits.
      require("lazy").load({ plugins = { "markdown-preview.nvim" } })
      vim.fn["mkdp#util#install_sync"](true)
      if vim.v.shell_error ~= 0 then
        error("markdown-preview.nvim binary installation failed")
      end
    end,
  },
}
