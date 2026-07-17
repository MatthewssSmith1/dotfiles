# Deployment

## Accepted Design

Retain GNU Stow, but permanently stop treating the repository root as one Stow
package. Bootstrap deploys explicit packages for the selected profile and
areas.

Conceptual layout:

```text
packages/
  common/
    git/
    bash/
    tmux/
    nvim/
    zsh/
  upstream/
    git/
    bash/
    tmux/
    starship/
    nvim/
  generic/
    git/
    bash/
    tmux/
    nvim/
  wsl/
    bash/
    tmux/

profiles/
  omarchy.conf
  generic.conf
  wsl.conf
```

Every package listed in the profile closure must exist, even when its payload
is temporarily empty during framework tests. Package IDs are stable, qualified
paths such as `common/git`, `upstream/git`, and `generic/git`; state never
records an unqualified name.

Profiles expand areas into this ordered package closure:

| Area | Omarchy | Generic | WSL |
|------|---------|---------|-----|
| Git | `common/git` | `upstream/git`, `generic/git`, `common/git` | Same as Generic |
| Bash | `common/bash` | `upstream/bash`, `upstream/starship`, `generic/bash`, `common/bash` | `upstream/bash`, `upstream/starship`, `generic/bash`, `wsl/bash`, `common/bash` |
| tmux | `common/tmux` | `upstream/tmux`, `generic/tmux`, `common/tmux` | `upstream/tmux`, `generic/tmux`, `wsl/tmux`, `common/tmux` |
| Neovim | `common/nvim` | `upstream/nvim`, `generic/nvim`, `common/nvim` | Same as Generic |
| zsh | `common/zsh` | `common/zsh` | `common/zsh` |

Baseline packages deploy before adapters, which deploy before personal
packages. Packages must use include/source boundaries rather than target the
same path. Manifest expansion rejects duplicate payload destinations before
Stow runs.

## Stow Rules

- Invoke Stow for a qualified `<layer>/<area>` package as:

  ```bash
  stow --dir="$DOTFILES_DIR/packages/<layer>" --target="$HOME" \
    --no-folding --stow <area>
  ```

  Use `--simulate` for preflight. Use `--delete` only when the exact recorded
  package definition still exists; otherwise remove links directly from
  recorded per-target ownership after the same lexical and resolved checks.
- Use `--no-folding` so multiple packages can safely share
  `~/.config/dotfiles/`.
- Keep docs, scripts, tests, metadata, ignored assets, deployment state, and
  host-local files outside every Stow payload.
- Preflight every operation for one selected area before changing that area.
- Support independent installation and removal by area.
- Do not let a conflict in one area block another selected area.
- Never return to a repository-wide `stow .` operation.

The package-foundation change starts a phased per-area root-Stow cutover:

1. Capture a reviewed manifest of every known live link into this checkout on
   the Stage 2 WSL host. Scan relevant dotfiles destinations rather than opaque
   application-owned data. Capture native Omarchy links in Stage 9 before that
   host is migrated.
2. Add package roots and migration logic without deleting or moving legacy
   source paths, so pulling the implementation cannot break existing links.
3. Change bootstrap so it cannot invoke root `stow .` and update permanent
   README commands.
4. Migrate Git; leave legacy links for unfinished areas in place but unmanaged.
5. As each later area migrates, remove only links whose recorded lexical and resolved
   targets both match the live link.
6. Deploy that area's explicit packages.
7. Remove tracked compatibility source paths only after every known host has
   migrated or remains pinned to an older checkout. Ignored agent skills are
   user-managed and permanently outside migration ownership.

Moving an area's payload files before its known old links are removed is
forbidden because it would create broken links. The current root package
ignores `docs/` only as a temporary defense before this cutover.

## Bootstrap Contract

Bootstrap must:

- Resolve the repository from the script's own path rather than assuming
  `~/dotfiles`.
- Auto-detect the profile using the rules in [Architecture](architecture.md).
- Support a validated `--profile` override.
- Treat repeated `--area` options as the complete requested area set.
- Use all default areas when no `--area` is supplied.
- Provide a non-mutating `--check` mode.
- Support `--remove` with optional repeated `--area` arguments. `--profile` is
  invalid with `--remove`; removal uses recorded state. With no areas,
  `--remove` selects every recorded area.
- Check and report missing system dependencies without invoking `sudo`.
  Because bootstrap never installs distro packages, fresh generic and WSL
  hosts have an explicit manual step. Area manifests generate the exact
  package-manager command; documentation examples are illustrative until those
  manifests exist.
- On the Omarchy profile, compare `~/.local/share/omarchy/version` against the
  recorded core pin and `pacman -Q omarchy-nvim` against the recorded Neovim
  package identity in [Upstream](upstream.md). Missing native owners are
  errors; parseable version mismatches produce separate non-blocking warnings.
  Drift is expected, and updating a pin is a separate explicit operation.
- Never change the login shell.
- Avoid authentication prompts and preserve existing OpenCode authentication.
- Be convergent and safe to run repeatedly.

A full bootstrap installs core personal applications. An area-scoped run
installs only dependencies relevant to its selected areas.

## Operation And Network Policy

This table is canonical. Other documents link here rather than broadening its
claims.

| Operation | Mutation | Network policy |
|-----------|----------|----------------|
| `bootstrap.sh --check` | None | Forbidden |
| Bootstrap apply | Selected home and state files | Allowed for pinned runtime tools and locked tmux plugins; never for Neovim plugins/assets or baseline synchronization |
| Bootstrap `--remove` | Selected home and state files | Forbidden |
| `scripts/upstream verify` | None | Forbidden |
| `scripts/upstream sync` | Resolved checkout manifest and snapshots plus same-filesystem staging | Allowed for pinned baseline inputs |
| Bash and tmux startup | Runtime process state only | Forbidden |
| Transitional zsh first start | Zinit runtime state | Existing first-start fetch behavior allowed |
| First explicit generic Neovim launch | Neovim plugin state | Locked plugin restoration allowed |
| Explicit Neovim restore after a lock change | Neovim plugin state | Locked plugin restoration allowed |
| Explicit Neovim runtime-asset provisioning | Declared Mason, Treesitter, rock, or build state | Allowed only under the asset policy accepted in Stage 8 |

Apply must print planned networked actions before executing them. Startup must
never install or update tools implicitly except for the documented transitional
zsh first-start behavior. Neovim plugin installation occurs only during the
first explicit launch or a later explicit restore after a lock change. Upstream
sync never deploys configuration. Within `$HOME`, it may touch only the
resolved checkout and a same-filesystem staging directory beside the content it
will atomically replace; all unrelated home paths are forbidden.

## Deployment State

Record the applied profile, areas, and packages beneath:

```text
~/.local/state/dotfiles/
```

Use one versioned JSON state file per area plus a process lock:

```text
~/.local/state/dotfiles/
  v1/
    migrations.json
    git.json
    bash.json
    tmux.json
    nvim.json
    zsh.json
```

Each area state records schema version, profile, area, resolved checkout root,
target root, ordered qualified package IDs, every deployed target path and its
expected lexical source, every managed directory created by deployment,
managed attachment IDs, destinations, and expected content hashes, and any
backup paths created by that area. State exists only for exact cleanup and
mismatch refusal; it never reconciles profiles or overrides detection.

`migrations.json` is a retained host ledger for destructive one-time migrations.
It records migration ID, source fingerprint, completion time, and backup paths.
Removal never deletes this ledger, so reapply cannot repeat Neovim runtime
renames or another completed one-time migration.

All modes open the already-existing `$HOME` directory read-only and take an
advisory `flock` on that file descriptor before reading state. `--check` uses a
shared lock; apply and removal use an exclusive lock. This coordinates runs
without creating a lock file, so `--check` remains non-mutating.

For each selected area it:

1. Expands and validates the package closure.
2. Preflights the complete old and desired state, packages, legacy migration,
   attachments, and rollback path without mutation.
3. Starts a temporary operation journal.
4. Removes obsolete or old-checkout links only when their current lexical and
   resolved targets match recorded ownership.
5. Applies desired packages and attachments.
6. Atomically writes replacement state only after the area succeeds.
7. Rolls back journaled changes if the area fails.

Independent selected areas continue after an area failure; bootstrap returns a
nonzero aggregate status. If rollback itself fails, bootstrap stops further
mutation and reports the journal for manual recovery. Malformed, unknown, or
newer-schema state causes refusal rather than speculative cleanup.

Apply refuses before any mutation when any existing area state names a
different profile from the detected or requested profile. The user must run
`bootstrap.sh --remove` first. Omitting a deployed area during apply leaves its
state and files untouched.

Checkout moves and removed package definitions are handled from recorded link
ownership, not by reconstructing an old package tree. Apply may replace an old
checkout source with the current checkout only after every existing target
matches state. Removal deletes each recorded link or attachment only after the
same check, prunes only empty managed directories, and deletes the area state
atomically after cleanup succeeds. A mismatch leaves state intact and refuses
cleanup.

`--remove` removes only deployed links, exact managed attachment content, empty
managed directories, and successful area state. It deliberately retains
installed applications and mise tools, tmux plugin checkouts, Neovim runtime
data and backups, migration backups, credentials, and every host-local file.
It also retains `migrations.json`. Those resources may be reported but are
never deleted by configuration removal.

## Native Omarchy Attachments

Omarchy refresh or reinstall operations can replace Bash, tmux, Starship, and
Neovim configuration. Do not symlink those refresh-managed destinations into
the checkout.

Attach shared behavior using small regular-file changes:

- Bash: append a guarded source block to native `.bashrc`.
- tmux: append a guarded source line to native tmux configuration.
- Neovim: recreate a small regular loader after refresh.
- Git: preserve the native XDG baseline and use a regular `~/.gitconfig`
  include entrypoint.
- Starship: leave the native configuration unchanged initially.

Attachment operations must:

- Use clear begin and end markers where the file format permits.
- Be idempotent.
- Refuse malformed, nested, or duplicate marker blocks.
- Remove only exact managed content.
- Preserve unrelated user modifications.
- Report drift instead of guessing how to repair it.
- Reapply safely after supported native refresh operations.

## Legacy Migration Safety

The current repository has root-package links and repo-backed local files.
Migration must:

- Convert `~/.gitconfig.local` to an external regular file with mode `0600`
  without following the legacy symlink during writes or permission changes.
- Move current zsh-local content under `~/.config/dotfiles/local/`.
- Remove a legacy symlink only when both its recorded lexical target and its
  normalized resolved destination match the known old path in this checkout.
  Broken links use a non-dereferencing normalized destination for the second
  comparison.
- Handle individually Stowed links in the current Neovim tree.
- Prune only empty directories created by old deployment.
- Refuse unrelated regular-file conflicts.
- Preserve unrelated host settings and credentials.

Neovim's accepted backup policy — git history for the configuration,
timestamped renames for runtime state — is recorded in
[Neovim](tools/neovim.md#reset-and-migration).

## Executable Ownership

| Tool category | Omarchy | Generic and WSL |
|---------------|---------|-----------------|
| Git, fzf, zoxide, fd, eza, bat, rg, jq, GitHub CLI | Native packages | Distro packages |
| tmux | Native package | Distro package when 3.5 or newer, else locked `aqua:tmux/tmux-builds` via mise |
| Neovim, Starship | Native packages | Suitable package or locked mise fallback |
| mise | Native package | Pinned user-scoped install when absent |
| Node and pnpm | mise | mise |
| Claude Code | Native package | mise |
| OpenCode and Worktrunk | mise when needed | mise |
| Vite+ | Official user-scoped installer | Official user-scoped installer |

On Omarchy, bootstrap must fail if a prohibited command such as Neovim
resolves through a mise shim instead of the native package. Alignment does not
require identical installation mechanisms, but it does require unambiguous
owners and compatible behavior.

The Omarchy tmux baseline is written for tmux 3.5. Ubuntu's distro packages
lag (22.04 ships 3.2a, 24.04 ships 3.4), so the mise fallback is the expected
owner on generic systems. Pin the fully qualified Aqua backend and lock its
verified prebuilt artifact; do not rely on mise's shorthand registry order.
This removes tmux source-build dependencies from the manual package step.
Interim behavior on hosts that have not converged is defined in
[tmux](tools/tmux.md#runtime-and-terminals).

## Mise

The general principle: lean into mise wherever it can absorb tool-management
complexity, instead of writing bespoke install, pin, or update logic.

On generic systems, networked bootstrap apply may install a known,
checksum-verified mise version when mise is absent. It must accept a newer
compatible existing version and never downgrade it. `--check` only reports the
missing tool and the planned installation.

Use additive fragments:

```text
~/.config/mise/conf.d/
  20-dotfiles-common.toml
  30-dotfiles-profile.toml
```

Loose selectors express maintenance intent. Committed adjacent lockfiles hold
the exact versions, backends, and artifacts installed by ordinary bootstrap.
Project mise files retain higher precedence for project runtimes, but may not
silently shadow profile-owned commands such as tmux or native Omarchy Neovim.
Bootstrap must not silently advance locked versions.

## Open Questions

Before ownership-aware bootstrap is implemented:

1. Select the exact mise-managed tool versions and generate lockfiles.
2. Define how Vite+ is checked and updated outside mise.
3. Define how the OpenCode Codex plugin is checked and updated outside mise.

These are unresolved decisions, not implementation recommendations.

## Acceptance Criteria

- `--check` reports intended changes and missing dependencies without
  mutation, including the exact manual package command when dependencies are
  missing and a non-blocking Omarchy version-drift warning where applicable.
- Apply and removal obey the canonical network policy.
- Every package for an area passes preflight before that area is changed.
- Repeated bootstrap converges without adding duplicate attachments.
- Root metadata, tests, scripts, and docs are never linked into `$HOME`.
- A failed area does not block or alter another selected area.
- Legacy links are removed only after exact ownership checks.
- Local files, authentication, and unrelated regular files remain intact.
- Omarchy commands resolve to approved native owners.
- Generic managed tools resolve to their locked approved owners.
- Profile mismatch is refused until explicit state-driven removal succeeds.
- State updates are atomic, and concurrent bootstrap runs are refused.
- Bootstrap does not use `sudo`, change the login shell, or update baselines.
