# Deployment

Dotfiles deploys explicit qualified Stow packages and never treats the
repository root as a package. Profiles define ordered baseline, adapter, and
personal closures; `upstream/reference` is evidence, not deployable content.

| Area | Omarchy | Ubuntu |
|---|---|---|
| Git | `common/git` | `upstream/git`, `ubuntu/git`, `common/git` |
| Tools | `common/tools`, `omarchy/tools` | `common/tools`, `ubuntu/tools` |
| Bash | `common/bash` | `upstream/bash`, `upstream/starship`, `ubuntu/bash`, `common/bash` |
| tmux | validation-only | `upstream/tmux`, `ubuntu/tmux` |
| Neovim | `common/nvim` plus loader | `upstream/nvim`, `ubuntu/nvim`, `common/nvim` |
| Agents | `common/agents` | `common/agents` |
| Herdr | validation-only | `ubuntu/herdr` |
| Desktop | `omarchy/desktop` plus guarded/structured ownership | validation-only |
| OpenCode (optional) | `common/opencode` | `common/opencode` |

## Command Contract

The public grammar is:

```text
dotfiles.sh apply [--profile omarchy|ubuntu] [area ...]
dotfiles.sh check [--profile omarchy|ubuntu] [area ...]
dotfiles.sh remove [area ...]
dotfiles.sh list
dotfiles.sh help [command]
dotfiles.sh --help
```

An operation is mandatory and must come first. Areas are positional; optional
areas require explicit selection for apply/check. Legacy operation flags,
selector flags, comma lists, and options after an area are rejected. No areas
selects ready defaults for apply/check and owned defaults for removal. `list`
and help do not require a supported host. The executable
`~/.local/bin/dotfiles` payload in `common/tools` locates exactly one checkout
root and forwards this interface without a fixed checkout path.

The `dotfiles.sh` deployment lifecycle is non-root and user-scoped. It never
invokes `sudo`, a distro package manager, an installer, or a network-capable
command, and it never changes the login shell. Missing dependencies print exact
manual guidance.

The Omarchy tools closure also deploys `dotfiles-omarchy-prune` onto `PATH` but
never executes it. This separate, manually invoked administration command asks
Omarchy to remove selected packages and web-app launchers; Omarchy's package
command may request sudo authentication.

Every selected area completes preflight before its first write. A
shared/exclusive lock on `HOME` coordinates apply/remove and check respectively.
Derivable package links can converge directly after an interrupted Stow run;
dotfiles has no deployment transaction, journal, backup, or rollback layer.

## Lean Ownership

Lean package links are derived from the active profile and therefore need no
state. Ownership records live under `~/.local/state/dotfiles/v2/`: record
format 1 stores attachments, while format 2 adds fixed JSON scalar fields.
Both formats may coexist for one profile and format-1 records are not rewritten
merely because they were read. The retired `~/.local/state/dotfiles/v1/`
namespace is refused with manual cleanup guidance. Native validation-only and
package-only areas write no state. Default removal still derives optional
package-only ownership, so an omitted area list removes deployed OpenCode links
without selector state.

Native refresh-owned baselines remain regular files. Git, Bash, Neovim, and
desktop use guarded attachments; desktop also owns only the two registered
idle scalars in `shell.json`. Its generated package XCompose fragment provides
managed aliases; a guarded include attaches it to the regular Omarchy-owned
`~/.XCompose` without replacing the default include, name, or email content.
The same manifest generates a `SUPER+SHIFT+K` binding fragment, static shortcut
submenu rows, and a stable-ID helper that replays those Compose sequences with
`wtype` without touching the clipboard or pressing Enter. A guarded loader
attaches the binding fragment to the regular Omarchy-owned `bindings.lua`.
The desktop package links the bundled-theme filter selector and guards only the
managed theme and shortcut rows in the regular Omarchy menu extension. Anchored insertion
preserves unrelated top-level, object-valued JSONC entries, including multiline
partial overrides, submenus, providers, and target links; wrapped `items` form
is deliberately refused. Apply alone may expand older valid area state to
register the menu. Check/remove refuse incomplete state. Menu file watching
normally makes refresh unnecessary. Background double-right-click remains
native and unfiltered; hidden themes stay installed and directly selectable.
The filter's private `omarchy-menu-images` adapter restores the real Omarchy
root only for native image-selector IPC.

The offline `dotfiles.sh` lifecycle deploys and checks repository state but
does not activate shortcut runtime changes. `dotfiles-shortcuts manage` performs
interactive CRUD, `dotfiles-shortcuts edit-manifest` opens the canonical
manifest, and `dotfiles-shortcuts sync` explicitly regenerates, applies, and
reloads XCompose/menu state. CRUD changes the repository manifest and generated
artifacts so normal review and commits preserve it.
tmux and Herdr are validation-only.
Modified links or attachments refuse removal. Removal preserves application
data, caches, sessions, credentials, and all Neovim runtime roots.

## Network Boundaries

| Operation | Network |
|---|---|
| Dotfiles apply/check/remove | Forbidden |
| `dotfiles-omarchy-prune` | No fetch; privileged local package mutation |
| Shell, tmux, ordinary Neovim startup | Forbidden |
| Herdr runtime manifest refresh | Explicitly allowed for agent detection |
| OpenCode personal startup | May fetch its pinned npm plugin when uncached |
| `scripts/upstream verify` | Forbidden |
| `scripts/upstream sync --proposal ...` | Explicitly allowed for pinned source refresh |
| `nvim-restore` | Explicitly allowed for locked plugin restoration |
| Manual distro/mise installation | Outside dotfiles |

Ubuntu selectors are ordinary mise configuration. Install them manually with
the exact command printed by the relevant area; dotfiles writes selectors but
never runs `mise install`.

Application runtime networking is allowed only when documented in this matrix.
The managed exceptions are Herdr's agent-detection manifest refresh, with
version checks disabled, and OpenCode personal-profile installation of its
pinned npm plugin when absent from the host cache. This does not alter the
offline dotfiles apply/check/remove guarantee.
