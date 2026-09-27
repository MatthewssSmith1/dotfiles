-- OSC 52 copies reach attached tmux clients and remote terminals. Local
-- Wayland paste remains available when editing inside tmux.
local M = {}

local function proc_lines(pid, file)
  local ok, lines = pcall(vim.fn.readfile, "/proc/" .. pid .. "/" .. file)
  return ok and lines or {}
end

local function proc_ppid(pid)
  for _, line in ipairs(proc_lines(pid, "status")) do
    local ppid = line:match("^PPid:%s+(%d+)")
    if ppid then
      return tonumber(ppid)
    end
  end
end

local function ancestor_process_named(name)
  local pid = vim.fn.getpid()
  for _ = 1, 16 do
    local ppid = proc_ppid(pid)
    if not ppid or ppid <= 1 then
      return false
    end
    if (proc_lines(ppid, "comm")[1] or ""):find(name, 1, true) then
      return true
    end
    pid = ppid
  end
  return false
end

function M.setup()
  if not (vim.env.TMUX or vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.HERDR_PANE_ID or ancestor_process_named("herdr")) then
    return
  end

  local osc52 = require("vim.ui.clipboard.osc52")
  local has_wayland = vim.env.WAYLAND_DISPLAY ~= nil
    and vim.fn.executable("wl-copy") == 1
    and vim.fn.executable("wl-paste") == 1

  local function copy(register)
    local emit = osc52.copy(register)
    return function(lines)
      if has_wayland then
        local cmd = { "wl-copy", "--sensitive", "--type", "text/plain" }
        if register == "*" then
          cmd[#cmd + 1] = "--primary"
        end
        vim.fn.system(cmd, lines)
      end
      emit(lines)
    end
  end

  local function paste(register)
    if not has_wayland then
      return osc52.paste(register)
    end
    return function()
      local cmd = { "wl-paste", "--no-newline" }
      if register == "*" then
        cmd[#cmd + 1] = "--primary"
      end
      local lines = vim.fn.systemlist(cmd, "", 1)
      return vim.v.shell_error == 0 and lines or {}
    end
  end

  vim.g.clipboard = {
    name = "MattRemoteClipboard",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
    cache_enabled = 0,
  }
end

return M
