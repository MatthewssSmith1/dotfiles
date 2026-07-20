local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  error("locked lazy.nvim checkout is missing; run nvim-restore")
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  lockfile = vim.env.DOTFILES_NVIM_RESTORE_LOCKFILE or (vim.fn.stdpath("config") .. "/lazy-lock.json"),
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  local_spec = true,
  install = { missing = false, colorscheme = { "tokyonight", "habamax" } },
  pkg = { sources = { "lazy", "packspec" } },
  rocks = { enabled = false },
  checker = {
    enabled = false, -- updates are checked only by explicit user commands
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
