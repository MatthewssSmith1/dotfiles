# Windows Terminal

## Status

Client-terminal guidance for anything typed into Windows Terminal: a WSL
shell, or an SSH session into a remote Linux host. The host's profile does not
matter; what matters is that Windows Terminal is the terminal. Key, color,
mouse, and clipboard behavior passed on Windows Terminal 1.24.11911.0 with
tmux 3.7b.

Windows Terminal settings are never patched from WSL or by bootstrap. Theming
is repo-managed from the Windows side via
[windows/terminal/apply.ps1](../../windows/README.md); the keybinding unbinds
below are still a manual step.

## Required Settings

Windows Terminal binds `alt+enter` to fullscreen toggle by default, which
consumes the Omarchy tmux vertical-split binding (`M-Enter`) before the
terminal ever sees it. The arrow combinations may fall through in some states
but are intercepted when Windows Terminal has panes to act on. Stage 7 requires
all eight unbinds so tmux behavior does not depend on client pane state.
Windows Terminal 1.24 stores assignments separately from actions; add them to
the `keybindings` array in `settings.json` (Settings > Open JSON file):

```json
"keybindings": [
  { "id": "unbound", "keys": "alt+enter" },
  { "id": "unbound", "keys": "alt+left" },
  { "id": "unbound", "keys": "alt+right" },
  { "id": "unbound", "keys": "alt+up" },
  { "id": "unbound", "keys": "alt+down" },
  { "id": "unbound", "keys": "alt+shift+left" },
  { "id": "unbound", "keys": "alt+shift+right" },
  { "id": "unbound", "keys": "ctrl+alt+left" }
]
```

## Expected Limitations To Validate

Protocol analysis predicts that two Omarchy tmux bindings will not work with
the targeted Windows Terminal and tmux versions. Treat these as planned
expectations until the tmux gate records exact versions and observed input:

- `M-S-Enter` (horizontal split): without extended keys, Alt+Shift+Enter
  transmits identically to Alt+Enter, so tmux runs the vertical-split binding
  instead. tmux requests extended keys via `modifyOtherKeys`; Windows
  Terminal and tmux do not negotiate a mutually supported extended-key mode.
  Use `prefix + h` instead.
- `M-Escape` (kill pane): Alt+Escape is a reserved Windows shortcut (window
  z-order cycling) and never reaches the terminal. Use `prefix + x` instead.

The accepted policy is to document these rather than add WSL or host-local tmux
rebinds. Revisit the shared design only if tested protocol support changes.

## Color Scheme

The Omarchy tmux status uses ANSI `black` on ANSI `blue` for its session
badge, and Windows Terminal's built-in schemes have insufficient contrast for
that pair. The "Omarchy Tokyo Night" scheme in
[windows/terminal/managed-settings.json](../../windows/terminal/managed-settings.json)
(exact values from Omarchy v3.8.3's Tokyo Night `colors.toml`) is applied by
`apply.ps1` as the `profiles.defaults` color scheme, so every profile (cmd,
PowerShell, WSL, SSH) inherits it.

## Validated Client Behavior

- Ctrl+Space works with the tested English keyboard layout. A CJK input
  method may consume it as the IME toggle before the terminal sees it; validate
  the configured input method and retain `C-b` as the fallback prefix.
- Truecolor, mouse behavior, and OSC 52 clipboard export work without an
  additional terminal-side setting on Windows Terminal 1.24.11911.0.
- The Omarchy Tokyo Night palette gives the tmux session badge sufficient
  contrast while preserving the upstream ANSI color assignments.

## Verification Checklist

Inside a tmux session in a Windows Terminal tab, after applying all required
unbinds:

1. `C-Space c` creates a window; `C-b c` also works.
2. `M-2` switches to window 2.
3. `M-Enter` splits vertically.
4. `C-M-Right` moves pane focus; `C-M-S-Right` resizes.
5. `echo $TERM` inside tmux prints `tmux-256color`.
6. A truecolor test script shows a smooth gradient.
7. Mouse focus, selection, and scrolling work.
8. `printf %s stage7-osc52 | tmux load-buffer -w -` places `stage7-osc52` on
   the Windows clipboard.
9. If the protocol analysis is confirmed, `prefix + h` and `prefix + x` cover
   the two unavailable Alt bindings.
