local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  -- Publish only a complete checkout. An interrupted clone must not prevent
  -- the next apply from bootstrapping the manager.
  vim.fn.mkdir(vim.fn.fnamemodify(lazypath, ":h"), "p")
  local staging = assert((vim.uv or vim.loop).fs_mkdtemp(lazypath .. ".bootstrap-XXXXXX"))
  local result = vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", staging })
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(staging, "rf")
    error("lazy.nvim bootstrap failed: " .. result)
  end
  -- A fresh clone must match the declared manager revision before it loads.
  local file = assert(io.open(vim.fn.stdpath("config") .. "/lazy-lock.json", "r"))
  local lock = vim.json.decode(file:read("*a"))
  file:close()
  local commit = assert(lock["lazy.nvim"] and lock["lazy.nvim"].commit)
  result = vim.fn.system({ "git", "-C", staging, "checkout", commit })
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(staging, "rf")
    error("lazy.nvim bootstrap checkout failed: " .. result)
  end
  assert((vim.uv or vim.loop).fs_rename(staging, lazypath))
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  -- The headless apply command restores the declared lock before installing.
  -- Ordinary interactive startup retains Lazy's normal missing-plugin flow.
  install = { missing = vim.env.DOTFILES_NVIM_PROVISIONING ~= "1", colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = false },
  performance = {
    rtp = { disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
  },
})
