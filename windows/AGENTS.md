# Windows Agent Instructions

`windows/` is a distinct environment, not part of the Linux adapter layers.
Apply scripts run manually from a Windows shell, outside bootstrap and Stow.

## Invariants

- Never hand-edit the live Windows Terminal `settings.json`. Change
  `windows/terminal/managed-settings.json` and run
  `windows/terminal/apply.ps1` (see the `applying-dotfiles` skill).
- The keybinding unbinds in `docs/environments/windows-terminal.md` are a
  manual step; the script does not apply them.
