# Windows Terminal

## Status

This is manual client guidance for the planned tmux workflow. The unbind syntax
follows current Microsoft documentation, but the tmux stage must record the
Windows Terminal and tmux versions used for final key, color, and clipboard
validation.

Client-terminal guidance for any session typed into Windows Terminal: a WSL
shell, or an SSH session into a VPS or other remote Linux host. The host's
profile does not matter; what matters is that Windows Terminal is the
terminal. Connecting to the same host from a Linux terminal instead makes all
of this irrelevant.

Windows Terminal settings are never patched automatically from WSL or by
bootstrap. Everything here is an explicit manual action on the Windows side.

## Required Setting

Windows Terminal binds `alt+enter` to fullscreen toggle by default, which
consumes the Omarchy tmux vertical-split binding (`M-Enter`) before the
terminal ever sees it. Unbind it in `settings.json` (Settings > Open JSON
file):

```json
"actions": [
  { "id": "unbound", "keys": "alt+enter" }
]
```

## Recommended Settings

These bindings fall through to the shell in common cases but are intercepted
when Windows Terminal has its own panes to act on. Unbinding makes the tmux
bindings unconditional:

```json
"actions": [
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

The planned policy is to document these rather than rebind them if validation
confirms the analysis. If protocol support changes or the gap hurts in
practice, revisit the decision or use a host-local tmux override.

## Expected Caveats To Validate

- Ctrl+Space is expected to work with an English keyboard layout. A CJK input
  method may consume it as the IME toggle before the terminal sees it; validate
  the configured input method and retain `C-b` as the fallback prefix.
- Truecolor and OSC 52 clipboard are expected to need no terminal-side setting;
  verify both independently on the recorded Windows Terminal version.

## Verification Checklist

Inside a tmux session in a Windows Terminal tab, after applying the required
unbind:

1. `C-Space c` creates a window; `C-b c` also works.
2. `M-2` switches to window 2.
3. `M-Enter` splits vertically.
4. `C-M-Right` moves pane focus; `C-M-S-Right` resizes.
5. `echo $TERM` inside tmux prints `tmux-256color`.
6. A truecolor test script shows a smooth gradient.
7. If the protocol analysis is confirmed, `prefix + h` and `prefix + x` cover
   the two unavailable Alt bindings.
