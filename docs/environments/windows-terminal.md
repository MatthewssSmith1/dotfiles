# Windows Terminal

## Status

Client-terminal guidance for SSH sessions into a remote Linux host. The host's
profile does not matter; what matters is that Windows Terminal is the terminal.
The accepted tmux fallback is 3.7c.

Dotfiles never patches Windows Terminal settings. Theming is repo-managed from
the Windows side via [windows/terminal/apply.ps1](../../windows/README.md); the
keybinding unbinds below are still a manual step.

## Required Settings

Windows Terminal shortcuts can consume the Herdr map before the terminal sends
it to the remote host. Manually unbind every combination below; `apply.ps1`
intentionally does not manage actions or keybindings. Windows Terminal 1.24
stores assignments separately from actions, so add these entries to the
`keybindings` array in `settings.json` (Settings > Open JSON file):

```json
"keybindings": [
  { "id": "unbound", "keys": "alt+enter" },
  { "id": "unbound", "keys": "alt+left" },
  { "id": "unbound", "keys": "alt+right" },
  { "id": "unbound", "keys": "alt+up" },
  { "id": "unbound", "keys": "alt+down" },
  { "id": "unbound", "keys": "alt+shift+left" },
  { "id": "unbound", "keys": "alt+shift+right" },
  { "id": "unbound", "keys": "alt+shift+up" },
  { "id": "unbound", "keys": "alt+shift+down" },
  { "id": "unbound", "keys": "alt+shift+enter" },
  { "id": "unbound", "keys": "alt+escape" },
  { "id": "unbound", "keys": "ctrl+alt+left" },
  { "id": "unbound", "keys": "ctrl+alt+right" },
  { "id": "unbound", "keys": "ctrl+alt+up" },
  { "id": "unbound", "keys": "ctrl+alt+down" },
  { "id": "unbound", "keys": "ctrl+alt+shift+left" },
  { "id": "unbound", "keys": "ctrl+alt+shift+right" },
  { "id": "unbound", "keys": "ctrl+alt+shift+up" },
  { "id": "unbound", "keys": "ctrl+alt+shift+down" }
]
```

Manual checklist: Alt+Left/Right/Up/Down, Alt+Shift+Left/Right/Up/Down,
Alt+Enter, Alt+Shift+Enter, Alt+Escape, Ctrl+Alt+Left/Right/Up/Down, and
Ctrl+Alt+Shift+Left/Right/Up/Down.

## Known Limitations

Unbinding removes Windows Terminal assignments, but it cannot overcome two
Windows input/protocol limitations:

- `M-S-Enter` (horizontal split): without extended keys, Alt+Shift+Enter
  transmits identically to Alt+Enter, so tmux runs the vertical-split binding
  instead. tmux requests extended keys via `modifyOtherKeys`; Windows
  Terminal and tmux do not negotiate a mutually supported extended-key mode.
  Use `prefix + h` instead.
- `M-Escape` (kill pane): Alt+Escape is a reserved Windows shortcut (window
  z-order cycling) and never reaches the terminal. Use `prefix + x` instead.

The accepted policy is to document these rather than add host-local rebinds.
When Herdr key delivery is unavailable or ambiguous, use tmux as the fallback
path and its `prefix + h` and `prefix + x` bindings. Revisit the shared design
only if tested protocol support changes.

## Color Scheme

The Omarchy tmux status uses ANSI `black` on ANSI `blue` for its session badge,
and Windows Terminal's built-in schemes have insufficient contrast for that
pair. The "Omarchy Tokyo Night" scheme in
[windows/terminal/managed-settings.json](../../windows/terminal/managed-settings.json)
uses the accepted v4 Tokyo Night source and is applied as the
`profiles.defaults` color scheme.

## Validated Client Behavior

- Ctrl+Space works with the tested English keyboard layout. A CJK input
  method may consume it as the IME toggle before the terminal sees it; validate
  the configured input method and retain `C-b` as the fallback prefix.
- Truecolor, mouse behavior, and OSC 52 clipboard export work without an
  additional terminal-side setting on Windows Terminal 1.24.11911.0.
- The Omarchy Tokyo Night palette gives the tmux session badge sufficient
  contrast while preserving the upstream ANSI color assignments.

## Verification Checklist

Use tmux to verify terminal key delivery when Herdr cannot provide a reliable
result. Inside a tmux session in a Windows Terminal tab, after applying all
required unbinds:

1. `C-Space c` creates a window; `C-b c` also works.
2. `M-2` switches to window 2.
3. `M-Enter` splits vertically.
4. `C-M-Right` moves pane focus; `C-M-S-Right` resizes.
5. `echo $TERM` inside tmux prints `tmux-256color`.
6. A truecolor test script shows a smooth gradient.
7. Mouse focus, selection, and scrolling work.
8. `printf %s osc52-check | tmux load-buffer -w -` places `osc52-check` on
   the Windows clipboard.
9. If the protocol analysis is confirmed, `prefix + h` and `prefix + x` cover
   the two unavailable Alt bindings.
