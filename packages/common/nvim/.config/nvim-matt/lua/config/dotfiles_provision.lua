-- Headless entry point (DOTFILES_NVIM_PROVISIONING=1):
-- nvim --headless '+lua require("config.dotfiles_provision").run()'
local M = {}
local timeout = 600000

local function await(phase, done)
  if not vim.wait(timeout, done, 100) then
    error(phase .. " timed out after " .. timeout .. "ms")
  end
end

local function plugins()
  if vim.env.DOTFILES_NVIM_PROVISIONING ~= "1" then
    error("set DOTFILES_NVIM_PROVISIONING=1 before launching Neovim to preserve the declared lock")
  end
  local lazy = require("lazy")
  local manage = require("lazy.manage")
  local lock = require("lazy.manage.lock")
  lock.load()
  local declared = vim.deepcopy(lock.lock)
  -- An empty data root first knows only the LazyVim parent spec. Reload
  -- specs after each install so its imported extras become visible.
  local function phase_run(phase)
    -- Lazy rewrites its lock after each operation. Retain the declared
    -- revisions across the intermediate install before running restore.
    lock.lock = vim.tbl_deep_extend("force", lock.lock, declared)
    local runner = manage[phase]({ show = false, lockfile = true })
    await("lazy " .. phase, function()
      return not runner:is_running()
    end)
    for name, plugin in pairs(require("lazy.core.config").plugins) do
      for _, task in ipairs(plugin._.tasks or {}) do
        if task:has_errors() then
          error("lazy " .. phase .. " failed for " .. name .. ": " .. task:output(vim.log.levels.ERROR))
        end
      end
    end
  end
  for _ = 1, 6 do
    local config = require("lazy.core.config")
    local missing = false
    for _, plugin in pairs(config.plugins) do
      if plugin.url and not plugin._.installed then
        missing = true
        break
      end
    end
    if not missing then
      break
    end
    phase_run("install")
    -- LazyVim's own plugin specs live in its checkout. A fresh headless
    -- instance has not loaded the new checkout into runtimepath yet.
    local parent = require("lazy.core.config").plugins["LazyVim"]
    if parent and parent._.installed then
      vim.opt.rtp:prepend(parent.dir)
    end
    require("lazy.core.util").unloaded_cache = {}
    require("lazy.core.cache").reset()
    require("lazy.core.plugin").load()
  end
  for name, plugin in pairs(require("lazy.core.config").plugins) do
    if plugin.url and not plugin._.installed then
      error("lazy install incomplete: " .. name)
    end
  end
  local drift = false
  local restart = false
  for name, plugin in pairs(require("lazy.core.config").plugins) do
    local target = declared[name]
    if plugin.url and target then
      local result = vim.system({ "git", "-C", plugin.dir, "rev-parse", "HEAD" }, { text = true }):wait()
      if result.code ~= 0 or vim.trim(result.stdout) ~= target.commit then
        drift = true
        if name == "LazyVim" or name == "lazy.nvim" then
          restart = true
        end
      end
    end
  end
  if drift then
    phase_run("restore")
  end
  if restart then
    return true
  end
  local preview = require("lazy.core.config").plugins["markdown-preview.nvim"]
  local preview_binary = preview and preview.dir .. "/app/bin/markdown-preview-linux"
  if preview and vim.fn.executable(preview_binary) ~= 1 then
    -- An interrupted build leaves the Git checkout installed. Lazy only
    -- rebuilds installed plugins when this state is explicitly requested.
    preview._.build = true
    phase_run("install")
    if vim.fn.executable(preview_binary) ~= 1 then
      error("markdown-preview.nvim build did not create app/bin/markdown-preview-linux")
    end
  end
end

local function mason()
  -- On a fresh install Snacks was absent during startup. LSP keymaps need its
  -- global even when provisioning loads plugins after startup has completed.
  require("lazy.core.loader").load({ "snacks.nvim" }, { require = "dotfiles provisioning" })
  require("lazy.core.loader").load({ "mason.nvim", "nvim-lspconfig" }, { require = "dotfiles provisioning" })
  local registry = require("mason-registry")
  local refreshed, refresh_error = false, nil
  registry.refresh(function(ok, err)
    refresh_error = not ok and (err or "registry refresh failed") or nil
    refreshed = true
  end)
  await("mason registry", function()
    return refreshed
  end)
  if refresh_error then
    error(refresh_error)
  end

  local names = {}
  local function add(list)
    for _, name in ipairs(list or {}) do
      names[name] = true
    end
  end
  add(require("lazyvim.util").opts("mason.nvim").ensure_installed)
  -- The pinned nvim-treesitter main branch compiles parsers with this CLI.
  names["tree-sitter-cli"] = true
  local lsp = require("lazyvim.util").opts("nvim-lspconfig").servers or {}
  local mappings = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  for server, opts in pairs(lsp) do
    if type(opts) ~= "table" or (opts.enabled ~= false and opts.mason ~= false) then
      if mappings[server] then
        names[mappings[server]] = true
      end
    end
  end
  local pending, failures = {}, {}
  registry:on("package:install:success", function(pkg)
    pending[pkg.name] = nil
  end)
  registry:on("package:install:failed", function(pkg, err)
    if pending[pkg.name] then
      failures[#failures + 1] = pkg.name .. ": " .. tostring(err)
      pending[pkg.name] = nil
    end
  end)
  for name in pairs(names) do
    local ok, pkg = pcall(registry.get_package, name)
    if not ok then
      failures[#failures + 1] = name .. ": " .. tostring(pkg)
    elseif not pkg:is_installed() then
      pending[name] = true
      if not pkg:is_installing() then
        local started, err = pcall(function()
          pkg:install()
        end)
        if not started then
          failures[#failures + 1] = name .. ": " .. tostring(err)
          pending[name] = nil
        end
      end
    end
  end
  await("mason installs", function()
    return next(pending) == nil
  end)
  if #failures > 0 then
    error(table.concat(failures, ", "))
  end
  return names
end

local function parsers()
  require("lazy.core.loader").load({ "nvim-treesitter" }, { require = "dotfiles provisioning" })
  local TS = require("nvim-treesitter")
  local installed = TS.get_installed()
  local missing = {}
  for _, lang in ipairs(require("lazyvim.util").opts("nvim-treesitter").ensure_installed or {}) do
    if not vim.list_contains(installed, lang) then
      missing[#missing + 1] = lang
    end
  end
  if #missing == 0 then
    return
  end
  local done, success, failure = false, false, nil
  TS.install(missing):await(function(err, result)
    success, failure, done = result == true and not err, err, true
  end)
  await("treesitter parsers", function()
    return done
  end)
  if not success then
    error("failed to install one or more parsers: " .. table.concat(missing, ", ") .. ": " .. tostring(failure))
  end
end

local function receipt(required_mason)
  local files = {}
  local function include(path)
    if vim.fn.filereadable(path) ~= 1 then
      error("readiness artifact missing: " .. path)
    end
    files[#files + 1] = path
  end
  local data = vim.fn.stdpath("data")
  local config = vim.fn.stdpath("config")
  local function digest(path)
    -- readfile(..., 'b') retains a trailing empty entry for a final newline.
    return vim.fn.sha256(table.concat(vim.fn.readfile(path, "b"), "\n"))
  end
  local lock = vim.json.decode(table.concat(vim.fn.readfile(config .. "/lazy-lock.json"), "\n"))
  for name, plugin in pairs(require("lazy.core.config").plugins) do
    if plugin.url then
      local desired = lock[name]
      if not desired then
        error("plugin missing from lock: " .. name)
      end
      local result = vim.system({ "git", "-C", plugin.dir, "rev-parse", "HEAD" }, { text = true }):wait()
      if result.code ~= 0 or vim.trim(result.stdout) ~= desired.commit then
        error("plugin does not match lock: " .. name)
      end
      include(plugin.dir .. "/.git/HEAD")
    end
  end
  for name in pairs(required_mason) do
    include(data .. "/mason/packages/" .. name .. "/mason-receipt.json")
  end
  for _, lang in ipairs(require("lazyvim.util").opts("nvim-treesitter").ensure_installed or {}) do
    include(data .. "/site/parser/" .. lang .. ".so")
  end
  if require("lazy.core.config").plugins["markdown-preview.nvim"] then
    local binary = data .. "/lazy/markdown-preview.nvim/app/bin/markdown-preview-linux"
    if vim.fn.executable(binary) ~= 1 then
      error("markdown-preview.nvim executable missing: " .. binary)
    end
    include(binary)
  end
  table.sort(files)
  local path = vim.fn.stdpath("state") .. "/dotfiles-ready.json"
  local out = assert(io.open(path, "wb"))
  out:write(vim.json.encode({
    version = 1,
    files = files,
    lock_sha256 = digest(config .. "/lazy-lock.json"),
    extras_sha256 = digest(config .. "/lazyvim.json"),
  }))
  out:close()
end

function M.run()
  os.remove(vim.fn.stdpath("state") .. "/dotfiles-ready.json")
  local lockpath = vim.fn.stdpath("config") .. "/lazy-lock.json"
  local file = io.open(lockpath, "rb")
  local original = file and file:read("*a") or nil
  if file then
    file:close()
  end
  local ok, err = xpcall(function()
    if plugins() then
      if vim.env.DOTFILES_NVIM_PROVISIONING_RESTARTED == "1" then
        error("LazyVim or lazy.nvim still changed after restarting; rerun apply nvim")
      end
      -- The current process has loaded the former manager/spec code. Finish
      -- under the restored versions in a fresh instance before claiming ready.
      local child = vim.system({
        vim.v.progpath,
        "--headless",
        '+lua require("config.dotfiles_provision").run()',
      }, {
        text = true,
        env = { DOTFILES_NVIM_PROVISIONING_RESTARTED = "1" },
      }):wait(timeout)
      if child.code ~= 0 then
        error("restored LazyVim restart failed: " .. (child.stderr or "") .. " " .. (child.stdout or ""))
      end
      return
    end
    local required_mason = mason()
    parsers()
    receipt(required_mason)
  end, debug.traceback)
  if not ok then
    -- Never promote partially installed revisions to the desired lock.
    if original then
      local restore = assert(io.open(lockpath, "wb"))
      restore:write(original)
      restore:close()
    end
    io.stderr:write("nvim provisioning failed: " .. err .. "\n")
  end
  vim.cmd(ok and "qa!" or "cquit 1")
end

return M
