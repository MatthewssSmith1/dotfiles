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
idle scalars in `shell.json`. Its package XCompose fragment provides four
personal aliases; a guarded include attaches it to the regular Omarchy-owned
`~/.XCompose` without replacing the default include, name, or email content.
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
| `scripts/upstream verify` | Forbidden |
| `scripts/upstream sync --proposal ...` | Explicitly allowed for pinned source refresh |
| `nvim-restore` | Explicitly allowed for locked plugin restoration |
| Manual distro/mise installation | Outside dotfiles |

Ubuntu selectors are ordinary mise configuration. Install them manually with
the exact command printed by the relevant area; dotfiles writes selectors but
never runs `mise install`.

Application runtime networking is allowed only when documented in this matrix.
Herdr's agent-detection manifest refresh is the current managed exception; its
version checks remain disabled. This does not alter the offline dotfiles
apply/check/remove guarantee.
