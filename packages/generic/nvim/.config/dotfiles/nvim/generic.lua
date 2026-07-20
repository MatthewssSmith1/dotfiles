local M = {}

local config = vim.fn.stdpath("config")
local data = vim.fn.stdpath("data")
local lockfile = config .. "/lazy-lock.json"
local state = vim.fn.expand("~/.local/state/dotfiles/v1/nvim.json")
local restore = vim.fn.expand("~/.local/share/dotfiles/bin/nvim-restore")
local personal = vim.fn.expand("~/.config/dotfiles/nvim/personal.lua")

local function read(path)
  local file, err = io.open(path, "rb")
  if not file then
    error(("dotfiles Neovim policy cannot read %s: %s"):format(path, err))
  end
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function lock_identity()
  return vim.fn.sha256(read(lockfile))
end

local function restored_identity()
  local decoded = vim.json.decode(read(state))
  if decoded.schema_version ~= 1 or decoded.area ~= "nvim" or (decoded.profile ~= "generic" and decoded.profile ~= "wsl") then
    error("dotfiles Neovim deployment state is malformed or profile-incompatible")
  end
  return decoded.restored_lock_sha256
end

local function lazy_commit()
  local decoded = vim.json.decode(read(lockfile))
  local commit = decoded["lazy.nvim"] and decoded["lazy.nvim"].commit
  if type(commit) ~= "string" or not commit:match("^[0-9a-f]+$") or #commit ~= 40 then
    error("dotfiles Neovim lock has no valid lazy.nvim commit")
  end
  return commit
end

local function checkout_commit(path)
  local result = vim.system({ "git", "-C", path, "rev-parse", "HEAD" }, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or nil
end

function M.before_lazy()
  local identity = lock_identity()
  local marker_value = restored_identity()

  if vim.env.DOTFILES_NVIM_RESTORING ~= "1" then
    if not marker_value then
      local result = vim.system({ restore, "--first-launch" }, { text = true }):wait()
      if result.code ~= 0 then
        error("first locked Neovim restore failed:\n" .. (result.stderr or result.stdout or ""))
      end
      marker_value = restored_identity()
    elseif marker_value ~= identity then
      error("Neovim lock changed; run nvim-restore explicitly before starting Neovim")
    end
  end

  if marker_value ~= identity and vim.env.DOTFILES_NVIM_RESTORING ~= "1" then
    error("Neovim restore did not record the active lock identity")
  end

  local lazypath = data .. "/lazy/lazy.nvim"
  local expected = lazy_commit()
  local actual = checkout_commit(lazypath)
  if actual ~= expected then
    error(("lazy.nvim is not at the locked commit (expected %s, found %s); run nvim-restore"):format(
      expected,
      actual or "missing"
    ))
  end
end

function M.after_lazy()
  dofile(personal)
  require("dotfiles_policy").validate()
end

return M
