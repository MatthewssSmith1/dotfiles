-- Native state is authoritative. Never evaluate a theme's Lua: inspect only
-- the supported declarative plugin/option shape before using its settings.
local M = {}
local uv = vim.uv or vim.loop
-- Omarchy itself uses this HOME path, irrespective of the caller's XDG roots.
local state = vim.env.HOME .. "/.local/state/omarchy/current"
local supported = {
  ["tokyo-night"] = { plugin = "folke/tokyonight.nvim", colorscheme = "tokyonight-night" },
  everforest = { plugin = "neanias/everforest-nvim", colorscheme = "everforest", background = "soft" },
  catppuccin = { plugin = "catppuccin/nvim", colorscheme = "catppuccin-nvim" },
}
local fallback = supported["tokyo-night"]
local last_warning
local function warn(message)
  if message == last_warning then return end
  last_warning = message
  vim.schedule(function() vim.notify("Personal Neovim theme: " .. message, vim.log.levels.WARN) end)
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function is_omarchy()
  local release = read("/etc/os-release") or ""
  return ("\n" .. release):match("\nID=['\"]?omarchy['\"]?%s*\n") ~= nil
end

local function native()
  local name = read(state .. "/theme.name")
  if not name then return nil end
  local slug = name:match("^%s*([%w%-]+)%s*$")
  local spec = read(state .. "/theme/neovim.lua")
  if not spec then return nil end -- staging can briefly replace the directory
  return slug, spec
end

local function ubuntu()
  local config = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")
  local path = config .. "/dotfiles/local/theme"
  local info = uv.fs_lstat(path)
  local text = info and info.type == "file" and info.uid == uv.getuid() and read(path) or nil
  local slug = text and text:match("^([%w%-]+)\n$")
  return supported[slug] or fallback, text or ""
end

local function validated(slug, spec)
  local expected = supported[slug]
  if not expected then
    warn("unsupported native theme " .. tostring(slug) .. "; using Tokyo Night")
    return fallback
  end
  -- Strip whitespace and require the full reviewed native spec shape. This
  -- refuses injected statements, extra plugins and unprovisioned schemes.
  local compact = spec:gsub("%-%-[^\n]*", ""):gsub("%s+", "")
  local plugin = expected.plugin
  local scheme = expected.colorscheme
  local name = slug == "catppuccin" and 'name="catppuccin",' or ""
  local priority = slug == "everforest" and "" or "priority=1000,"
  local background = slug == "everforest" and 'background="soft",' or ""
  local first = '{"' .. plugin .. '",' .. name .. priority .. '}'
  if slug == "everforest" then first = '{"' .. plugin .. '"}' end
  local expected_spec = 'return{' .. first .. ',{"LazyVim/LazyVim",opts={colorscheme="' .. scheme .. '",' .. background .. '},},}'
  if compact == expected_spec then
    return expected
  end
  warn("native " .. slug .. " Neovim spec differs from reviewed settings; using Tokyo Night")
  return fallback
end

function M.resolve()
  if not is_omarchy() then return (ubuntu()) end
  local slug, spec = native()
  if spec then return validated(slug, spec) end
  warn("native theme state unavailable; using Tokyo Night")
  return fallback
end

local timer
local current
local current_identity
function M.apply(selected)
  local previous = current
  local ok, err = pcall(function()
    if selected == supported.everforest then
      require("everforest").setup({ background = selected.background })
    end
    vim.opt.background = "dark"
    vim.cmd.colorscheme(selected.colorscheme)
  end)
  if not ok then
    current = previous
    warn("reload failed: " .. tostring(err) .. "; will retry")
    return false
  end
  current = selected
  return true
end

function M.watch()
  if timer then return end
  current = M.resolve()
  if not is_omarchy() then
    local _, identity = ubuntu()
    current_identity = identity
    timer = uv.new_timer()
    timer:start(1000, 1000, vim.schedule_wrap(function()
      local selected, next_identity = ubuntu()
      if next_identity ~= current_identity and M.apply(selected) then current_identity = next_identity end
    end))
    return
  end
  local initial_slug, initial_spec = native()
  if initial_spec then current_identity = tostring(initial_slug) .. "\0" .. initial_spec end
  timer = uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(function()
    local slug, spec = native()
    if not spec then return end
    local identity = tostring(slug) .. "\0" .. spec
    if identity == current_identity then return end
    local selected = validated(slug, spec)
    if M.apply(selected) then current_identity = identity end
  end))
end

return M
