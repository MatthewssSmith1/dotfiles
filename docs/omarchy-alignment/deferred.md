# Deferred Work

## Status

These improvements are intentionally outside the initial Omarchy alignment.
This document is not a schedule or promise of implementation order.

## Portable Coordinated Themes

### Intent

Extend Omarchy's coordinated visual language to portable development tools so
the same named theme produces a recognizably consistent terminal experience on
Omarchy and generic systems.

The selected Omarchy baseline does not dynamically apply every selected
palette to tmux or Starship. Coordinating those tools is a personal extension,
not a claim about current upstream behavior.

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

Such a system could support synchronized upstream themes, personal themes
using the same contract, and personal overlays on an upstream theme. Upstream
definitions should remain distinct from generated output and personal changes,
and catalog updates should be explicit and reviewable rather than a live
runtime dependency.

Generated application configuration would not be edited directly.

### Native Omarchy Behavior

Native Omarchy theme selection remains authoritative. If implemented, portable
integration could react to Omarchy's theme-change hook and update additional
terminal tools, but would not replace `omarchy-theme-set` or interfere with
desktop, terminal, background, or application integrations.

### Generic Behavior

A future portable selector could choose from the synchronized catalog and
invoke the same application adapters without requiring Omarchy. A potential
portable design would avoid dependencies on Hyprland, Waybar, Wayland
clipboard tools, wallpapers, desktop restart commands, Omarchy's package
manager, or Omarchy system services.

### Potential Application Adapters

Possible adapter responsibilities are:

- Neovim selects the corresponding LazyVim colorscheme specification.
- tmux derives status, border, message, and mode colors without changing the
  interaction model.
- Starship derives colors without changing prompt structure or symbols.
- fzf derives foreground, background, selection, border, and highlight colors.
- Lazygit derives its UI palette without changing Git behavior or keybindings.

A future implementation could update running applications where reload
behavior is predictable and safe. Failure isolation and reload policy remain
design questions.

### Desired Outcome

Selecting the same theme on an Omarchy desktop and an Ubuntu VPS should yield a
consistent Neovim, tmux, Starship, fzf, and Lazygit experience while Omarchy
continues to control its own system theme integrations.

## Shell Convergence

Bash with Starship is the evaluated primary shell during the migration, while
the existing zsh configuration remains behaviorally frozen as an escape hatch
(see [Shell](tools/shell.md)). After the migration, decide deliberately
whether to converge the two setups or retire zsh. Until that decision, zsh
receives no new features and no reconciliation with Bash.

## Agent Skills

Migrating `~/.agents/skills` is deferred from the initial Omarchy alignment.
The historical repository copy was ignored, its contents are currently absent,
and the existing skill lock was not a complete physical inventory. Stage 2
records those paths for review but does not restore, relocate, or manage them.
Broken bridges to absent skills may be removed as explicit user-approved host
cleanup; bootstrap never performs that cleanup.

A later agent-skills project must first produce a reviewed inventory that
classifies every physical skill as shared personal, vendored third-party, or
host-local. It must record immutable third-party provenance, preserve
host-local skills as real external files, define same-name conflict behavior,
and decide whether tool-generated lock metadata is deployed. Only then should
it introduce a separate Stow package with `--no-folding`.

## Fuller Windows Terminal Integration

The minimal client-terminal handling — documented manual unbinds and key
checks — is in scope for the migration (see
[Windows Terminal](../environments/windows-terminal.md)). The fuller
integration remains deferred:

- A tracked settings-fragment JSONC file containing the unbind actions and
  optional profile settings, with a documented manual merge step. It is never
  Stowed or symlinked, because `settings.json` lives on the Windows side and
  Windows Terminal rewrites it.
- A checked-in WSL-side read-only verification script that asserts terminfo,
  tmux version, and `$WT_SESSION`, then prints the manual checklist.

Do not assume terminal or tmux upgrades restore extended keys before testing.
Current protocol analysis predicts that the targeted versions will not
negotiate them. Record tested versions and observed input, then revisit the
affected bindings if either implementation changes.

The bootstrap must never patch Windows Terminal `settings.json` automatically
from WSL. Host-side settings remain an explicit user action.

## tmux Baseline Guarding For Old Hosts

The generic tmux owner is a distro package at 3.5 or newer, or the locked
mise fallback (see [Deployment](deployment.md#executable-ownership)). Hosts
that cannot take either see a documented, harmless startup notice for
baseline options their tmux does not know (see
[tmux](tools/tmux.md#runtime-and-terminals)). If that notice ever matters,
a deferred option is version-guarding those lines in the deployed baseline
copy as an explicit, manifest-recorded adapter transform. Not scheduled.
