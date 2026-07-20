local M = {}

local function lock_names()
  local file = assert(io.open(vim.fn.stdpath("config") .. "/lazy-lock.json", "rb"))
  local lock = vim.json.decode(file:read("*a"))
  file:close()
  return lock
end

function M.validate()
  local lock = lock_names()
  local config = require("lazy.core.config")
  for name, plugin in pairs(config.plugins) do
    if plugin.url and not lock[name] then
      if not (vim.uv or vim.loop).fs_stat(plugin.dir) then
        vim.notify("unlocked project-local plugin is missing and was not fetched: " .. name, vim.log.levels.WARN)
      end
    end
  end
end

return M
