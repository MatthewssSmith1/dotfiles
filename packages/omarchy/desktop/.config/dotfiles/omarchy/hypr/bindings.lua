hl.unbind("SUPER + SHIFT + K")
o.bind("SUPER + SHIFT + K", "Personal shortcuts", "omarchy-menu toggle shortcuts", { dont_inhibit = true, allow_input_capture = true })
dofile(os.getenv("HOME") .. "/.config/dotfiles/omarchy/hypr/capture-bypass.lua")
