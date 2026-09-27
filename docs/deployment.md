# Deployment

Dotfiles deploys explicit qualified Stow packages and never treats the repository root as a package. Profiles define ordered baseline, adapter, and personal closures; `upstream/reference` is evidence, not deployable content.

| Area                | Omarchy                                             | Ubuntu                                                             |
| ------------------- | --------------------------------------------------- | ------------------------------------------------------------------ |
| Git                 | `common/git`                                        | `upstream/git`, `ubuntu/git`, `common/git`                         |
| Tools               | `common/tools`, `omarchy/tools`                     | `common/tools`, `ubuntu/tools`                                     |
| Bash                | `common/bash`                                       | `upstream/bash`, `upstream/starship`, `ubuntu/bash`, `common/bash` |
| tmux                | validation-only                                     | `upstream/tmux`, `ubuntu/tmux`                                     |
| Neovim              | `common/nvim`; native default independent          | `ubuntu/nvim`, `common/nvim`; mise runtime                        |
| Agents              | `common/agents` (skills, bridges, Claude overlay/launcher) | `common/agents` (skills, bridges, Claude overlay/launcher)       |
| Herdr               | validation-only                                     | `ubuntu/herdr`                                                     |
| Desktop             | `omarchy/desktop` plus guarded/structured ownership | validation-only                                                    |
| OpenCode (optional) | `common/opencode`                                   | `common/opencode`                                                  |

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

An operation is mandatory and must come first. `--profile` is assertion-only: the profile is always detected from the host, and the flag merely fails the run when its value does not match the detected host class. Areas are positional; optional areas require explicit selection for apply/check. Legacy operation flags, selector flags, comma lists, and options after an area are rejected. No areas selects ready defaults for apply/check and owned defaults for removal. `list` and help do not require a supported host. The executable `~/.local/bin/dotfiles` payload in `common/tools` locates exactly one checkout root and forwards this interface without a fixed checkout path.

`dotfiles.sh` runs as the user and never changes the login shell. `apply nvim` uses scoped `sudo apt-get install` for missing Ubuntu prerequisites and provisions user-owned mise tools and editor dependencies with network access. On Omarchy, missing native packages require a deliberate `sudo pacman -Syu <missing packages>` outside apply to avoid partial upgrades. Other areas retain their existing boundaries and manual missing-dependency guidance. `check` is read-only and local; `remove` is local and preserves installed tools and application data.

The Omarchy tools closure also deploys `dotfiles-omarchy-prune`, `dotfiles-amdgpu-ips`, and `dotfiles-polkit-fingerprint` onto `PATH` but never executes them. The latter two are explicit administration helpers for narrowly owned privileged system changes; normal apply/check/remove remains user-scoped and inert.

Every selected area completes preflight before its first write. Apply and remove take an exclusive lock on `HOME`; check takes a shared lock, so concurrent checks coexist but never overlap a mutating run. Derivable package links can converge directly after an interrupted Stow run; dotfiles has no deployment transaction, journal, backup, or rollback layer.

## Lean Ownership

Lean package links are derived from the active profile and therefore need no state. Ownership records live under `~/.local/state/dotfiles/v2/`: record formats 1 and 2 are accepted read-only compatibility inputs. Every successful apply writes format 3, which unifies attachments and fixed JSON scalar fields. Each attachment records its last deployed block hash and a nullable pending target hash. Apply atomically publishes `managed=A,pending=B` before replacing A with B, then publishes `managed=B,pending=null`; an interrupted transition is therefore recoverable without treating arbitrary desired bytes as owned. A hashless format-1/2 record migrates only when its live block exactly matches the current desired or known legacy block. Check does not migrate state. The state directory name remains `v2` because that is the active lean-engine namespace; the retired `~/.local/state/dotfiles/v1/` namespace is refused with manual cleanup guidance. Native validation-only and package-only areas write no state. Default removal still derives optional package-only ownership, so an omitted area list removes deployed OpenCode links without selector state.

Native refresh-owned baselines remain regular files. Git, Bash, and desktop use guarded attachments; personal Neovim lives in `~/.config/nvim-matt`, separate from the native Omarchy editor. Desktop owns only the two idle scalars in `shell.json`. Shortcuts and the theme selector extend the native Omarchy menu through JSONC, with stock layout and sizing. Existing clone deployments migrate back to `omarchy.menu` on apply or remove, releasing the old widget ownership and exact clone links; see [desktop migration](environments/omarchy.md#desktop).

Its generated package XCompose fragment provides managed aliases; a guarded include attaches it to the regular Omarchy-owned `~/.XCompose` without replacing the default include, name, or email content. The same manifest generates a `SUPER+SHIFT+K` binding fragment, static shortcut submenu rows, and a stable-ID helper that replays those Compose sequences with `wtype` without touching the clipboard or pressing Enter. A guarded loader attaches the binding fragment to the regular Omarchy-owned `bindings.lua`. The generated binding unbinds its manifest key, enables both capture bypass flags, then loads the stowed handwritten `capture-bypass.lua` with 36 navigation and shell overrides for all capturing apps. See the [desktop migration and live verification](environments/omarchy.md#desktop) before reloading an existing host.

The desktop package links the bundled-theme filter selector and guards the managed theme, shortcut, and Windows-removal rows in the regular Omarchy menu extension. Anchored insertion preserves unrelated top-level, object-valued JSONC entries, including multiline partial overrides, submenus, providers, and target links; wrapped `items` form is deliberately refused. Apply alone may expand older valid area state to register missing attachments. Check/remove refuse incomplete attachment state. Menu file watching normally makes refresh unnecessary. Background double-right-click remains native and unfiltered; hidden themes stay installed and directly selectable. The filter's private `omarchy-menu-images` adapter restores the real Omarchy root only for native image-selector IPC.

The desktop lifecycle deploys and checks repository state but does not activate shortcut runtime changes. `dotfiles-shortcuts manage` performs interactive CRUD, `dotfiles-shortcuts edit-manifest` opens the canonical manifest, and `dotfiles-shortcuts sync` explicitly regenerates, applies, and reloads XCompose/menu state. CRUD changes the repository manifest and generated artifacts so normal review and commits preserve it. tmux and Herdr are validation-only. Modified links or attachments refuse removal. Removal preserves application data, caches, sessions, credentials, and all Neovim runtime roots.

## Network Boundaries

Desktop also owns the Windows VM wrapper and `windows-vm.desktop` package links
on Omarchy only. No VM command or privilege elevation runs during apply/check/
remove, and no VM data or credentials are owned. An existing regular desktop
entry must be inspected, backed up, and explicitly moved aside before adoption;
remove does not restore it. Before upstream install/reinstall, detach the managed
desktop symlink because upstream `tee` follows it. Re-adopt the newly generated
regular entry deliberately afterwards. See the [launcher safeguards and setup
exception](environments/omarchy.md#windows-vm-launcher).

| Operation                              | Network                                          |
| -------------------------------------- | ------------------------------------------------ |
| `apply nvim`                           | Ubuntu native package installation and user-owned editor dependencies; Omarchy reports missing native packages |
| Other area apply; all check/remove     | Local; check is read-only                        |
| Explicit Windows VM wrapper launch     | Upstream VM runtime; fresh setup may download images |
| `dotfiles-omarchy-prune`               | No fetch; privileged local package mutation      |
| `dotfiles-amdgpu-ips`                   | No fetch; explicit privileged boot configuration |
| `dotfiles-polkit-fingerprint`           | No fetch; explicit privileged PAM configuration  |
| Shell, tmux startup                    | Offline                                          |
| Personal Neovim startup                | Normal LazyVim dependency management may fetch  |
| Herdr runtime manifest refresh         | Explicitly allowed for agent detection           |
| OpenCode personal startup              | May fetch its pinned npm plugin when uncached    |
| `scripts/upstream verify`              | Forbidden                                        |
| `scripts/upstream sync --proposal ...` | Explicitly allowed for pinned source refresh     |
| Manual distro/mise installation for other areas | Outside dotfiles                      |

Ubuntu selectors outside Neovim are ordinary mise configuration; install them manually with the exact command printed by the relevant area. Neovim apply may install its mise-managed runtime.

Herdr's agent-detection manifest refresh, OpenCode personal-profile installation of its pinned npm plugin when uncached, and explicitly invoked upstream Windows VM runtime networking retain their documented behavior. Baseline synchronization remains a separate explicit operation.
