-- Execute the real fragments with a recording Lua Hyprland API, without a compositor.
local package_root = assert(arg[1])
local expected = {
  ["SUPER + F"] = { "Full screen", { "fullscreen", { mode = "fullscreen" } } },
  ["SUPER + SHIFT + K"] = { "Personal shortcuts", "omarchy-menu toggle shortcuts" },
  ["SUPER + K"] = { "Keybindings", "omarchy-menu-keybindings" },
  ["SUPER + CTRL + A"] = { "Audio", "omarchy-shell shell toggle omarchy.audio" },
  ["SUPER + CTRL + W"] = { "Network", "omarchy-shell shell toggle omarchy.network" },
  ["SUPER + CTRL + D"] = { "Display", "omarchy-shell shell toggle omarchy.monitor" },
  ["SUPER + CTRL + B"] = { "Bluetooth", "omarchy-shell shell toggle omarchy.bluetooth" },
  ["SUPER + CTRL + P"] = { "Power", "omarchy-shell shell toggle omarchy.power" },
}
-- Explicit physical keycodes: top-row 1 through 0, independent of layout.
for i, code in ipairs({ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }) do
  expected["SUPER + code:" .. code] = {
    "Switch to workspace " .. i, { "focus", { workspace = tostring(i) } },
  }
  expected["SUPER + SHIFT + code:" .. code] = {
    "Move window to workspace " .. i, { "move", { workspace = tostring(i) } },
  }
  if i <= 9 then
    expected["SUPER + CTRL + code:" .. code] = {
      "Bar panel " .. i, "omarchy-shell -q shell togglePanelAt right " .. i,
    }
  end
end
local function equal(actual, wanted)
  assert(type(actual) == type(wanted), "value type differs")
  if type(wanted) ~= "table" then
    assert(actual == wanted, "value differs: " .. tostring(actual) .. " / " .. tostring(wanted))
    return
  end
  for key, value in pairs(wanted) do equal(actual[key], value) end
  for key in pairs(actual) do assert(wanted[key] ~= nil, "unexpected field: " .. key) end
end
local function dispatcher(name)
  return function(options) return { name, options } end
end
local active, unbound, seen = {}, {}, {}
hl = {
  unbind = function(keys)
    assert(expected[keys], "unexpected unbind: " .. keys)
    assert(not unbound[keys], "duplicate unbind: " .. keys)
    active[keys], unbound[keys] = nil, true
  end,
  dsp = {
    focus = dispatcher("focus"),
    window = { fullscreen = dispatcher("fullscreen"), move = dispatcher("move") },
  },
}
o = { bind = function(keys, description, action, flags)
  assert(unbound[keys] and not active[keys], "must unbind before replacing: " .. keys)
  assert(not seen[keys], "duplicate binding: " .. keys)
  equal({ description, action }, assert(expected[keys], "unexpected binding: " .. keys))
  equal(flags, { dont_inhibit = true, allow_input_capture = true })
  active[keys], seen[keys], unbound[keys] = true, true, nil
end }
local getenv = os.getenv
os.getenv = function(name)
  if name == "HOME" then return package_root end
  return getenv(name)
end
for keys in pairs(expected) do active[keys] = "stock binding" end
for _ = 1, 2 do
  seen = {}
  dofile(package_root .. "/.config/dotfiles/omarchy/hypr/bindings.lua")
  local count = 0
  for keys in pairs(expected) do
    assert(seen[keys] and active[keys], "missing binding: " .. keys)
    count = count + 1
  end
  assert(count == 37)
  assert(next(unbound) == nil)
end
print("PASS: 37 exact capture bindings; repeated loading replaces every binding")
