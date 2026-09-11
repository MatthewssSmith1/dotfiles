-- Handwritten capture overrides; personal shortcuts are generated in bindings.lua.
-- Keep desktop navigation local even when a remote client captures input.
local local_navigation = {
  dont_inhibit = true,
  allow_input_capture = true,
}

hl.unbind("SUPER + F")
o.bind("SUPER + F", "Full screen",
  hl.dsp.window.fullscreen({ mode = "fullscreen" }),
  local_navigation)

for workspace = 1, 10 do
  local keys = "SUPER + code:" .. tostring(workspace + 9)
  hl.unbind(keys)
  o.bind(keys, "Switch to workspace " .. workspace,
    hl.dsp.focus({ workspace = tostring(workspace) }),
    local_navigation)

  local move_keys = "SUPER + SHIFT + code:" .. tostring(workspace + 9)
  hl.unbind(move_keys)
  o.bind(move_keys, "Move window to workspace " .. workspace,
    hl.dsp.window.move({ workspace = tostring(workspace) }),
    local_navigation)
end

for panel = 1, 9 do
  local keys = "SUPER + CTRL + code:" .. tostring(panel + 9)
  hl.unbind(keys)
  o.bind(keys, "Bar panel " .. panel,
    "omarchy-shell -q shell togglePanelAt right " .. panel,
    local_navigation)
end

for _, binding in ipairs({
  { "SUPER + CTRL + A", "Audio", "omarchy-shell shell toggle omarchy.audio" },
  { "SUPER + CTRL + W", "Network", "omarchy-shell shell toggle omarchy.network" },
  { "SUPER + CTRL + D", "Display", "omarchy-shell shell toggle omarchy.monitor" },
  { "SUPER + CTRL + B", "Bluetooth", "omarchy-shell shell toggle omarchy.bluetooth" },
  { "SUPER + CTRL + P", "Power", "omarchy-shell shell toggle omarchy.power" },
  { "SUPER + K", "Keybindings", "omarchy-menu-keybindings" },
}) do
  hl.unbind(binding[1])
  o.bind(binding[1], binding[2], binding[3], local_navigation)
end
