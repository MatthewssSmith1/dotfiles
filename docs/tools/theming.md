# Application Themes

The tools area supplies the shared selector and reviewed offline catalog. Omarchy integration is implemented; Ubuntu adapters remain phase two.

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
| `opencode` | Existing named profile/keybinding overlays; native theme inheritance |

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

`list` works without Omarchy. Status reads `${XDG_CONFIG_HOME:-~/.config}/dotfiles/local/theme`, defaulting missing/invalid selections to Tokyo Night without writing anything. It reports Ubuntu integration pending; personal Neovim continues using Tokyo Night in this phase. `set` and `sync` refuse mutation. Tools apply/check/remove preserve the local selection and existing application configuration.

Future adapters must consume the reviewed portable palettes and use explicit application colors, preserving the SSH client's terminal palette.

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Successful list/sync; current supported Omarchy status/set; or synchronized check without hook failure |
| `1` | Stale/absent observation, unsupported native status/set, recorded hook failure, or Ubuntu status/check with pending integration |
| `2` | Invalid arguments/catalog, native read/command failure, or unsupported Ubuntu mutation |

The catalog contract and exact source evidence are documented in [Upstream Sources](../upstream.md#portable-theme-catalog). Selected themes and generated state are host-local and never committed.
