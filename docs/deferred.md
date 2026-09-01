# Deferred Work

## Status

These improvements are intentionally outside the initial Omarchy alignment. This document is not a schedule or promise of implementation order.

## Portable Coordinated Themes

### Intent

Extend Omarchy's coordinated visual language to portable development tools so the same named theme produces a recognizably consistent terminal experience on Omarchy and Ubuntu systems.

The selected Omarchy baseline does not dynamically apply every selected palette to tmux or Starship. Coordinating those tools is a personal extension, not a claim about current upstream behavior.

### Targets

- Neovim
- tmux
- Starship
- fzf
- Lazygit

### Potential Source Model

The following is a design sketch, not an accepted implementation:

```text
Pinned Omarchy theme definitions
+ portable application adapters
+ personal theme overlays or definitions
+ generated application configuration
```

Such a system could support synchronized upstream themes, personal themes using the same contract, and personal overlays on an upstream theme. Upstream definitions should remain distinct from generated output and personal changes, and catalog updates should be explicit and reviewable rather than a live runtime dependency.

Generated application configuration would not be edited directly.

### Native Omarchy Behavior

Native Omarchy theme selection remains authoritative. If implemented, portable integration could react to Omarchy's theme-change hook and update additional terminal tools, but would not replace `omarchy-theme-set` or interfere with desktop, terminal, background, or application integrations.

### Generic Behavior

A future portable selector could choose from the synchronized catalog and invoke the same application adapters without requiring Omarchy. A potential portable design would avoid dependencies on Hyprland, Waybar, Wayland clipboard tools, wallpapers, desktop restart commands, Omarchy's package manager, or Omarchy system services.

### Potential Application Adapters

Possible adapter responsibilities are:

- Neovim selects the corresponding LazyVim colorscheme specification.
- tmux derives status, border, message, and mode colors without changing the interaction model.
- Starship derives colors without changing prompt structure or symbols.
- fzf derives foreground, background, selection, border, and highlight colors.
- Lazygit derives its UI palette without changing Git behavior or keybindings.

A future implementation could update running applications where reload behavior is predictable and safe. Failure isolation and reload policy remain design questions.

### Desired Outcome

Selecting the same theme on an Omarchy desktop and an Ubuntu VPS should yield a consistent Neovim, tmux, Starship, fzf, and Lazygit experience while Omarchy continues to control its own system theme integrations.

## Fuller Windows Terminal Integration

The managed-settings mechanism shipped for theming: `windows/terminal/managed-settings.json` plus `windows/terminal/apply.ps1` upsert shared defaults and the Omarchy color scheme (see [windows/README.md](../windows/README.md)). Still deferred:

- Extending the managed surface to the unbind actions currently documented as manual steps (see [Windows Terminal](environments/windows-terminal.md)).

Do not assume terminal or tmux upgrades restore extended keys before testing. Current protocol analysis predicts that the targeted versions will not negotiate them. Record tested versions and observed input, then revisit the affected bindings if either implementation changes.

Dotfiles never patches Windows Terminal `settings.json`; host-side settings remain an explicit user action.
