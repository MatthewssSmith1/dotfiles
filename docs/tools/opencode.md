# OpenCode

## Ownership

`opencode` is an optional, package-only area on both Linux profiles. It owns:

```text
~/.config/opencode/base.jsonc
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
The personal overlay is intentionally empty except for its schema declaration.

OpenCode's executable, `AGENTS.md` bridge, plugins, credentials, sessions,
package metadata, backups, TUI settings, and generated state have separate
owners. The `agents` area continues to own only the `AGENTS.md` bridge.

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
finds the first other `opencode` executable on `PATH`, injects only
`OPENCODE_CONFIG`, and preserves arguments and exit status.

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
