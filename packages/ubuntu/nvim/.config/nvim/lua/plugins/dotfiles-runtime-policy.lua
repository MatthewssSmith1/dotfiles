return {
  {
    "mason-org/mason.nvim",
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
    config = function(_, opts)
      -- Registry refreshes and package installation are explicit :Mason actions.
      require("mason").setup(opts)
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = { ensure_installed = {}, automatic_enable = false },
  },
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { lua_ls = { mason = false } } },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
  {
    "saghen/blink.cmp",
    opts = {
      fuzzy = {
        implementation = "lua",
        prebuilt_binaries = { download = false },
      },
    },
  },
}
