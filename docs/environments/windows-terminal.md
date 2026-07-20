# Windows Terminal

## Status

This is manual client guidance for the accepted tmux workflow. Key, color,
mouse, and clipboard behavior passed on Windows Terminal 1.24.11911.0 with tmux
3.7b.

Client-terminal guidance for any session typed into Windows Terminal: a WSL
shell, or an SSH session into a VPS or other remote Linux host. The host's
profile does not matter; what matters is that Windows Terminal is the
terminal. Connecting to the same host from a Linux terminal instead makes all
of this irrelevant.

Windows Terminal settings are never patched automatically from WSL or by
bootstrap. Everything here is an explicit manual action on the Windows side.

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

## Recommended Palette

The Omarchy tmux status uses ANSI `black` on ANSI `blue` for its session badge.
Windows Terminal's built-in Tango Dark colors have insufficient contrast for
that pair. Use this custom scheme for the Ubuntu profile instead of overriding
the pinned tmux baseline:

```json
{
  "background": "#1A1B26",
  "black": "#32344A",
  "blue": "#7AA2F7",
  "brightBlack": "#444B6A",
  "brightBlue": "#7DA6FF",
  "brightCyan": "#0DB9D7",
  "brightGreen": "#B9F27C",
  "brightPurple": "#BB9AF7",
  "brightRed": "#FF7A93",
  "brightWhite": "#ACB0D0",
  "brightYellow": "#FF9E64",
  "cursorColor": "#C0CAF5",
  "cyan": "#449DAB",
  "foreground": "#A9B1D6",
  "green": "#9ECE6A",
  "name": "Omarchy Tokyo Night",
  "purple": "#AD8EE6",
  "red": "#F7768E",
  "selectionBackground": "#7AA2F7",
  "white": "#787C99",
  "yellow": "#E0AF68"
}
```

Set the Ubuntu profile's `colorScheme` to `Omarchy Tokyo Night`. These are the
exact color values from Omarchy v3.8.3's Tokyo Night `colors.toml`.

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
