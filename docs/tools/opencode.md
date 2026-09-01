# OpenCode

## Ownership

`opencode` is optional and package-only on both Linux profiles. Dotfiles owns:

```text
~/.config/dotfiles/opencode/personal.jsonc
~/.config/dotfiles/opencode/work.jsonc
~/.config/dotfiles/opencode/tui.jsonc
~/.local/bin/opencode-personal
~/.local/bin/opencode-work
~/.local/share/dotfiles/bin/opencode-launch
```

Omarchy retains its regular `~/.local/bin/opencode` mise wrapper, `~/.config/opencode/opencode.json`, and `~/.config/opencode/tui.json`. Herdr retains `~/.config/opencode/tui.jsonc` and its integration scripts. The `agents` area separately owns only the `AGENTS.md` bridge. OpenCode owns its plugins, credentials, sessions, package metadata, caches, backups, and other generated state.

The personal overlay pins `opencode-openai-codex-auth@4.4.0`, its reviewed OpenAI provider catalog, and GPT 5.6 Terra compaction. The work overlay declares only the reviewed TrueFoundry providers and reads its credential from `TFY_API_KEY`. OAuth credentials remain in OpenCode application state. A fresh personal startup may fetch the pinned plugin when absent from cache; dotfiles apply, check, and remove never fetch.

OpenCode loads all existing global config names before the explicit overlay:

```text
~/.config/opencode/config.json
~/.config/opencode/opencode.json
~/.config/opencode/opencode.jsonc
$OPENCODE_CONFIG
```

Apply and check accept missing global files but reject top-level `plugin` or `provider` declarations in any existing one. This prevents global personal configuration leaking into work. Project, `.opencode`, injected-content, and managed-service configuration may load later and remain outside this area. Global `.jsonc` validation accepts the repository's reviewed subset: full-line `//` comments and trailing commas.

## Launching

Managed interactive Bash defines plain `opencode` as personal-by-default:

```text
opencode          -> opencode-launch personal -> native opencode
opencode-personal -> opencode-launch personal -> native opencode
opencode-work     -> opencode-launch work     -> native opencode
```

The Bash function falls back to `command opencode` when the optional launcher is absent. Noninteractive callers resolve native `opencode`; use a named launcher when a profile is required. The launcher finds the first executable `opencode` on `PATH`, injects `OPENCODE_CONFIG` and `OPENCODE_TUI_CONFIG`, and preserves arguments and exit status.

The TUI order begins with native `tui.json`, Herdr's `tui.jsonc`, then the explicit dotfiles overlay. Project TUI configuration may load later. The overlay maps `Ctrl+Enter`, `Shift+Enter`, `Alt+Enter`, and `Ctrl+J` to newline; `Ctrl+S` stashes a prompt; `Ctrl+Y` restores the latest stash; `Ctrl+X K` clears; and `Ctrl+X Q` quits.

## Lifecycle

```bash
dotfiles.sh check opencode
dotfiles.sh apply opencode
dotfiles.sh remove opencode
```

Applying is explicit. No global config is adopted or replaced. Removal deletes only the six exact links and preserves the native executable/configuration, Herdr integration, credentials, and application state. The loaded Bash function immediately falls back to native behavior when the launcher is gone. Apply and remove also delete exact links from the previous dotfiles OpenCode layout, including its obsolete generic wrapper; similarly named unrelated objects are preserved.

OpenCode reads configuration at startup. Quit and restart it after changes.
