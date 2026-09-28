# Application Themes

The tools area supplies the shared selector and reviewed offline catalog, with native Omarchy integration and explicit-color Ubuntu adapters.

```bash
dotfiles-theme                   # current selection, synchronization, integrations
dotfiles-theme list              # catppuccin, everforest, tokyo-night
dotfiles-theme set everforest
dotfiles-theme set tokyo-night
dotfiles-theme set catppuccin     # dark variant
```

`status` is an explicit alias for the no-argument form. Output is human-readable. `list` prints sorted supported slugs, one per line; eligible candidates do not appear until reviewed. The native picker retains its broader catalog.

## Deployment and Ownership

```bash
./dotfiles.sh check tools nvim desktop
./dotfiles.sh apply tools
./dotfiles.sh apply nvim
./dotfiles.sh apply desktop
./dotfiles.sh check tools nvim desktop
```

Initial checks can report pending deployment/provisioning. Neovim apply installs its locked plugins through the existing provisioning workflow; subsequent switching is offline.

| Area | Ownership |
| --- | --- |
| `tools` | `~/.local/bin/dotfiles-theme`, Python helper and catalog below `~/.local/share/dotfiles/` |
| `desktop` | Only `~/.config/omarchy/hooks/theme-set.d/90-dotfiles-theme` within native theme hooks |
| `nvim` | Personal resolver, watcher, static plugins and lockfile within `nvim-matt` |
| `opencode` | Named profile/keybinding overlays; native theme inheritance or Ubuntu generated TUI overlay |
| `herdr` | Ubuntu launcher and shell dispatcher; native remains validation-only |
| `bash` | Ubuntu prompt-time Starship and FZF accent integration |

These areas remain independently deployable. The hook is inert without the common helper; personal Neovim reads native state even without tools or desktop. Tools/desktop apply reconcile available native state without selecting a theme. Removal preserves installed tools/plugins, native selection, application data and generated observation. The hook is an exact managed symlink rather than a copy installed outside deployment ownership.

## Native Omarchy

Omarchy remains authoritative at `~/.local/state/omarchy/current/theme.name` and `theme/`. `set` accepts a supported slug, calls `omarchy theme set`, then reconciles observation. Native hook events reread actual state rather than trusting the event slug. Synchronization never selects another theme.

Generated state lives under `${XDG_STATE_HOME:-~/.local/state}/dotfiles/theme/`:

- `current.json`: version 1 observation (`host`, `theme`, `supported`, SHA-256 `inputs` for native `colors.toml` and `neovim.lua`). This is not a selection input.
- `sync.lock`: serializes atomic observation publication. Reading existing native staging state also takes Omarchy's shared lock.
- `hook.lock` and optional `hook-error`: serialize hook results and retain the last failure until this hook succeeds.

`dotfiles-theme sync` refreshes observation. `dotfiles-theme check` is read-only/local and detects missing/stale observation or a recorded hook failure. It allows synchronized unsupported native themes so desktop deployment remains usable. To retry a failed hook after fixing its reported error:

```bash
~/.config/omarchy/hooks/theme-set.d/90-dotfiles-theme
dotfiles-theme check
```

A plain `sync` does not clear hook failure evidence. Native theme selection is not rolled back if reconciliation fails. Status describes integration availability and reload requirements; it does not inspect rendered pixels or prove every running application reloaded. Use each area's `dotfiles.sh check` for installation/configuration readiness.

### Application behavior

| Application | Native behavior |
| --- | --- |
| Personal Neovim | Reviewed native slug/spec; one-second watcher, including same-slug spec changes; restart pre-integration instances once |
| OpenCode personal/work | Native `theme: "system"`, terminal palette, native `SIGUSR2` reload; restart if an existing session retains colors |
| Herdr | Native terminal colors; reconnect if an existing session retains colors |
| Bash/Starship | Native shell/prompt settings using terminal ANSI colors |

Unsupported native selections keep the desktop selection and use Tokyo Night in personal Neovim. Changed/unreviewed native Neovim specs also fall back with an editor warning. Palette-only overlays remain native; the personal editor does not synthesize a new colorscheme from arbitrary palette overrides. See [Neovim](neovim.md), [OpenCode](opencode.md), and the [acceptance record](../theming-ubuntu-handoff.md).

## Ubuntu Contract

`list` works without Omarchy. Selection lives at `${XDG_CONFIG_HOME:-~/.config}/dotfiles/local/theme`: a user-owned regular file containing one supported slug followed by a newline. Missing/invalid selections use Tokyo Night without persisting the fallback. `set` validates the slug and writes selection atomically; `sync` regenerates from the current selection without changing it. Status/check remain local and read-only.

```bash
./dotfiles.sh check tools nvim opencode herdr bash
./dotfiles.sh apply tools nvim opencode herdr bash
dotfiles-theme set tokyo-night
./dotfiles.sh check tools nvim opencode herdr bash
dotfiles-theme check
```

Generated output lives in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/theme/ubuntu/`. A `sync.lock` serializes writers and read-only observations. Each complete `generation-*` contains OpenCode palette/TUI JSON, Herdr and Starship TOML, an accent, and the applied slug. An atomic `current` symlink publishes the generation after validation. Prior generations are retained for processes using resolved paths. Failed validation leaves the previous selection and generation active; failed selection publication rolls back the generation pointer. An interrupted process can leave selection/output out of sync: `check` detects this and `sync` repairs it.

Tools apply and Ubuntu OpenCode apply synchronize available integration. Tools check detects stale output. A discovered managed OpenCode launcher enables the generated discovery link `${XDG_CONFIG_HOME:-~/.config}/opencode/themes/dotfiles-host.json`; conflicting user files are refused. App settings are derived from repository baselines, never written through Stow links. Herdr's installed 0.8.2 runtime additionally validates generated config in an isolated temporary home.

| Application | Ubuntu behavior |
| --- | --- |
| Personal Neovim | Reads local selection directly; one-second watcher retries failed reloads; works without tools |
| OpenCode personal/work | Explicit `dotfiles-host` palette, shared keybindings preserved; quit and restart existing sessions |
| Herdr | Managed `~/.local/bin/herdr` selects generated config through `HERDR_CONFIG_PATH`; explicit caller override wins; use reload-config and reconnect, or restart a pre-integration server deliberately |
| Bash/Starship | Next prompt selects generated Starship config and FZF accents; explicit `STARSHIP_CONFIG` wins; open a new shell after first deployment |

Adapters use explicit colors without emitting terminal-palette escape sequences. Local and remote hosts keep independent selections. Tools removal preserves selection/generated data; launchers and prompt integration stop consuming it when the selector is absent. App-area removal removes only its managed links and preserves application data. Retained OpenCode theme files remain discoverable but are no longer forced by removed profile launchers. Herdr settings edited through its themed runtime affect generated data and are replaced by the next synchronization; permanent preferences belong in the reviewed repository baseline.

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Successful list/sync; synchronized supported status/set; synchronized check without hook failure |
| `1` | Stale/absent output or observation, unsupported native status/set, or recorded hook failure |
| `2` | Invalid arguments/catalog, unsafe/conflicting output paths, or read/command/adapter failure |

The catalog contract and exact source evidence are documented in [Upstream Sources](../upstream.md#portable-theme-catalog). Selected themes and generated state are host-local and never committed.
