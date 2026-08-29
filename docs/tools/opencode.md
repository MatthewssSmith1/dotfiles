# OpenCode

## Ownership

`opencode` is an optional, package-only area on both Linux profiles. It owns:

```text
~/.config/opencode/base.jsonc
~/.config/opencode/dotfiles-tui.jsonc
~/.config/opencode/profiles/work.jsonc
~/.config/opencode/profiles/personal.jsonc
~/.config/opencode/opencode.jsonc -> base.jsonc
~/.local/bin/opencode
~/.local/bin/opencode-work
~/.local/bin/opencode-personal
~/.local/bin/dotfiles-opencode-profile
~/.local/share/dotfiles/bin/opencode-launch
```

The base remains small. Named profiles are explicit `OPENCODE_CONFIG` overlays;
OpenCode merges the selected overlay over the global base. The work overlay
contains gateway/model metadata but reads its credential from `TFY_API_KEY`.
The personal overlay pins `opencode-openai-codex-auth@4.4.0` and carries that
version's complete modern OpenAI provider/model configuration. The plugin and
model configuration must be updated together; the work overlay does not load
the Codex OAuth plugin. Personal compaction uses GPT 5.6 Terra with the `low`
variant as a repository-owned addition to the plugin template; work keeps its
separately defined gateway-backed compaction agent. Tests lock the normalized
provider catalog hash so field-level template drift requires explicit review.

OpenCode's executable, `AGENTS.md` bridge, plugins, credentials, sessions,
package metadata, backups, other TUI settings, and generated state have
separate owners. The `agents` area continues to own only the `AGENTS.md` bridge.
The repository selects the personal plugin version but does not own its npm
artifact or cache. On a fresh host, personal-profile startup may fetch the
pinned package when OpenCode has not cached it; dotfiles lifecycle operations
remain offline. OAuth credentials stay in OpenCode's host-owned application
state and are never copied into the profile.
The launchers also set `OPENCODE_TUI_CONFIG` to the managed TUI overlay. OpenCode
merges it after the separately owned `~/.config/opencode/tui.jsonc`, preserving
host integrations such as Herdr's plugin. The overlay maps `Ctrl+Enter`,
`Shift+Enter`, `Alt+Enter`, and `Ctrl+J` to newline input; plain `Enter` submits.
It also maps `Ctrl+S` to stash the prompt, `Ctrl+Y` to restore the latest stash,
`Ctrl+X K` to clear the prompt, and `Ctrl+X Q` as the sole quit binding. This
leaves `Ctrl+C` unbound for both prompt clearing and quitting, while preserving
the default `Ctrl+X C` session-compaction binding.

## Selection

The default launcher reads the untracked regular file:

```text
~/.config/dotfiles/local/opencode-profile
```

Select a default or bypass it per invocation:

```bash
dotfiles-opencode-profile work
dotfiles-opencode-profile personal
dotfiles-opencode-profile show
opencode-work
opencode-personal
```

Selection is independent of the `omarchy`/`ubuntu` host profile. The launcher
finds the first other `opencode` executable on `PATH`, injects
`OPENCODE_CONFIG` and the shared `OPENCODE_TUI_CONFIG`, and preserves arguments
and exit status.

## Lifecycle

```bash
dotfiles.sh check opencode
dotfiles.sh apply opencode
dotfiles.sh remove opencode
```

Applying is explicit because the area is optional. On first application, an
existing regular canonical config is adopted only when it exactly matches the
tracked work profile; that migration also selects `work`. Any other canonical
config refuses before mutation. Removal deletes exact managed links and keeps
the host-local selector and all application data.

OpenCode reads configuration at startup. Quit and restart it after applying or
switching profiles.
