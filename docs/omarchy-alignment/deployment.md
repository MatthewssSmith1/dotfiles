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
    reference/
      omarchy/
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
is empty during framework tests. Stage 4 populated the real `upstream/starship`,
`upstream/tmux`, and `upstream/nvim` snapshots, and Stage 6 materialized the
selected deployable Bash snapshots and managed common, generic, and WSL Bash
layers plus the transitional common zsh package. Stage 7 implements the complete
tmux package layout without changing tmux readiness. Payload presence does not
change area readiness in
`manifests/areas.tsv`. Package IDs are stable, qualified
paths such as `common/git`, `upstream/git`, and `generic/git`; state never
records an unqualified name.

`upstream/reference` is verified source material, not a Stow package. No
profile closure names it, so deployment never scans or installs its Bash and
theme inputs.

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

The generic and WSL mappings are XDG-native. Starship links
`~/.config/starship.toml` from `upstream/starship`. For tmux,
`generic/tmux` owns the XDG dispatcher at `~/.config/tmux/tmux.conf`, while
`upstream/tmux` owns the private byte-identical baseline at
`~/.config/dotfiles/upstream/tmux/tmux.conf`. The generic, command-empty WSL,
and common persistence fragments have distinct targets under
`~/.config/dotfiles/tmux/`; runtime source order is defined by the dispatcher,
not package order. tmux is ready after its automated Stage 7 gates passed.

For Bash, package order is deployment order, not startup order. The stable
common dispatcher owns runtime ordering: generic portable initialization,
then the WSL adapter when selected, then common personal integrations and the
host-local layer. Native Omarchy has no generic or WSL payload and reaches only
the common layers after its native `.bashrc`. The exact runtime order and
profile-specific attachment strategies are defined in
[Shell](tools/shell.md#managed-bash-load-order).

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
- Use all default areas when no `--area` is supplied. During the staged
  migration, `manifests/areas.tsv` records each area as `ready` or
  `framework`; default apply and check select only `ready` areas, and
  explicitly selecting a `framework` area is refused until its payload stage
  lands. Removal ignores readiness because it is state-driven.
- Provide a non-mutating `--check` mode.
- Support explicit `--provision` intent. Provisioning never follows merely from
  omitting `--area`; ordinary apply remains configuration-only.
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
- Do not install, remove, upgrade, reconfigure, or inspect OpenCode or
  `opencode-openai-codex-auth`. Unrelated operations preserve the active
  executable; `~/.config/opencode/opencode.json` or `opencode.jsonc`;
  `package.json`, lockfiles, plugins, and `node_modules` under that directory;
  the unpinned auth-plugin declaration; credentials; sessions; and provider
  state.
- Be convergent and safe to run repeatedly.

Accepted forms are:

```text
bootstrap.sh
bootstrap.sh --check
bootstrap.sh --provision
bootstrap.sh --check --provision
bootstrap.sh --area <area> [--area <area> ...]
bootstrap.sh --check --area <area> [--area <area> ...]
bootstrap.sh --provision --area <area> [--area <area> ...]
bootstrap.sh --check --provision --area <area> [--area <area> ...]
bootstrap.sh --remove [--area <area> ...]
```

Every non-remove form also accepts the existing validated `--profile` override
in any parser-supported order. `--provision` without `--check` means
configuration apply plus approved provisioning. `--check --provision` reports
configuration and provisioning convergence but remains offline and
non-mutating. `--provision` is invalid with `--remove`.

No-area `--provision` is the only full runtime-tool provisioning operation. It selects the
core personal application set (Node, pnpm, Claude Code, and Worktrunk) plus
platform foundations for every eventual default area, including tmux, Neovim,
and Starship, even while some configuration areas are framework-only. An
area-scoped provisioning run selects only dependencies assigned to the
explicit areas and never the core set. Framework-only areas remain
unselectable until their payload stages land except for the exact tmux lifecycle
below, so full provisioning does not imply that unfinished configuration is
ready. Without `--provision`, a no-area run still selects only the currently
`ready` configuration areas.

tmux plugins are a separate Stage 7 lifecycle. No-area provisioning may
provision the tmux executable foundation but never plugins. The only plugin
provisioning apply interface is exactly
`bootstrap.sh --provision --area tmux`; the corresponding check remains offline
and non-mutating. See [tmux](tools/tmux.md#plugin-lifecycle).

## Operation And Network Policy

This table is canonical. Other documents link here rather than broadening its
claims.

| Operation | Mutation | Network policy |
|-----------|----------|----------------|
| `bootstrap.sh --check` | None | Forbidden |
| `bootstrap.sh --check --provision` | None | Forbidden; reports the same locked provisioning set the corresponding provisioning apply would select |
| Ordinary bootstrap apply | Selected configuration and deployment state files | Forbidden; configuration-only |
| `bootstrap.sh --provision` apply | Selected configuration, deployment state, and retained provisioning roots | Allowed only for the printed, locked runtime-tool plan; no baseline, Neovim asset/plugin, OpenCode, Codex auth, or Vite+ operation |
| Bootstrap `--remove` | Selected home and state files | Forbidden |
| `scripts/upstream verify` | None | Forbidden |
| `scripts/upstream sync` | Resolved checkout manifest and snapshots plus same-filesystem staging | Allowed for pinned baseline inputs |
| `scripts/tmux-parser-fixtures validate-lock` or `verify --root <cache-root>` | None | Forbidden |
| `scripts/tmux-parser-fixtures sync --root <cache-root>` | Test-only archive cache, same-parent extraction staging, and the managed parser-fixture root under the caller-selected cache | Allowed only for the complete HTTPS package plan printed before download; never installs the package or changes deployment state |
| Bash and tmux startup | Runtime process state only | Forbidden |
| Transitional zsh first start with no readable Zinit entrypoint | Zinit runtime state | The only startup network exception: the existing Zinit clone is allowed |
| Transitional zsh startup with an existing readable Zinit entrypoint | Runtime process state only | Forbidden; plugins load only from a complete local closure under local-only Git policy |
| `bootstrap.sh --provision --area tmux` plugin provisioning | Locked plugin checkouts | Allowed only for the complete printed lock plan |
| First explicit generic Neovim launch | Neovim plugin state | Locked plugin restoration allowed |
| Explicit Neovim restore after a lock change | Neovim plugin state | Locked plugin restoration allowed |
| Explicit Neovim runtime-asset provisioning | Declared Mason, Treesitter, rock, or build state | Allowed only under the asset policy accepted in Stage 8 |

Provisioning apply must print every planned networked action before the first
network-capable command executes. Startup must never install or update tools
implicitly except for the documented missing-Zinit first-start behavior.
Neovim plugin installation occurs only during the
first explicit launch or a later explicit restore after a lock change. Upstream
sync never deploys configuration. Within `$HOME`, it may touch only the
resolved checkout and a same-filesystem staging directory beside the content it
will atomically replace; all unrelated home paths are forbidden.

Ordinary tmux apply and both check forms verify the exact plugin closure
offline and refuse incomplete or drifted state. Only the explicit area-scoped
plugin provisioning apply may stage missing or clean-drift replacements.
Dirty, ambiguous, non-owned, linked-worktree, and symlinked managed objects
refuse without mutation. Eligible replacements are assembled and verified in
same-filesystem staging and swapped transactionally rather than modified in
place. The machine contract and exact pins are in
`manifests/tmux-plugins.lock.json`.

The plugin receipt is retained separately at
`~/.local/state/dotfiles/provisioning/v1/tmux-plugins.json`. Its v1 schema
records the active lock hash and the ordered repository, commit, tree, and
directory identity of every checkout. The atomically compare-and-swapped full
receipt is the plugin transaction's commit point; it is not incrementally
updated and is not area-removal ownership.
Runtime provisioning, plugin provisioning, tmux configuration preflight, and
tmux configuration apply are ordered gates. A failure or terminal signal in
either provisioning layer prevents both tmux configuration stages; statuses
`70`, `130`, and `143` remain distinct rather than being collapsed into an
aggregate failure. This ordering also applies if tmux later becomes a default
ready area; the readiness manifest is not changed by provisioning.

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
Neovim state may additionally contain `restored_lock_sha256`, exactly 64
lowercase hexadecimal characters. The field is absent after initial deployment
and is written only after complete restore verification. Existing v1 state
without it remains schema-valid, but Neovim `--check` reports a pending restore
and fails convergence. A value different from the deployed lock reports stale
restore and also fails convergence; no other area may record the field.
State and migration-ledger files must be regular, non-symlink, EUID-owned
files. Recorded, desired, and legacy package links are accepted or removed only
while their symlink ownership is also EUID-safe, including a recheck at the
mutation point.

Concurrency protection covers normal cooperative edits by the same user. Every
journaled mutation compares the current object with the transaction-start
identity, or with this transaction's latest recorded post-state, and
read-modify-write files require the identity of the exact version read.
Temporary cleanup and quarantine discard likewise require the tracked object
identity. Bootstrap does not claim to defend against a malicious same-UID
process deliberately guessing and replacing private random quarantine names or
swapping parent directories between individual system calls; that stronger
boundary would require privileged or descriptor-relative filesystem mediation.

Bash state also records the selected login path, whether bootstrap created its
attachment-only file, and exact attachment identities and hashes. Generic and
WSL select the first already-existing `.bash_profile`, `.bash_login`, or
`.profile` once, in that order, and retain that choice across reapply. A newly
created `.bash_profile` is removable only while state and exact content prove
bootstrap created it. Existing startup files remain host-owned bytes around
the reversible managed blocks.

`migrations.json` is a retained host ledger for destructive one-time migrations.
It records migration ID, source fingerprint, completion time, and backup paths.
Removal never deletes this ledger, so reapply cannot repeat Neovim runtime
renames or another completed one-time migration. Stage 6 uses separate stable
records for zsh local-alias relocation and global Vite+ hook retirement.
Stage 8 records XDG-resolved Neovim data, state, and cache roots separately,
including absent roots. Existing roots are no-clobber renamed to collision-free
timestamped `.bak` siblings beneath `HOME`; each record keeps a source
fingerprint and any backup path. A directory-move journal, rather than the file
snapshot journal, reverses uncommitted renames on failure.
Retained zsh backups are no-clobber mode-`0600` files; every check/reapply
verifies owner, mode, and content hash against the recorded source fingerprint.
Initial migration performs the same verification immediately after creation and
again before the original source is destructively rewritten or removed.

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
managed directories, and successful area state. After every selected area is
removed, it re-prunes the selected areas' recorded managed directories (a
directory one area could not prune may only empty once a later area is
removed), and once no recorded state or retained ledger remains it prunes the
empty deployment state directory chain. It deliberately retains
installed applications and mise tools, tmux plugin checkouts, Neovim runtime
data and backups, migration backups, credentials, and every host-local file.
It also retains `migrations.json`. Those resources may be reported but are
never deleted by configuration removal.

For tmux this retention is also declarative: removal keeps both
`~/.tmux/plugins/` and `~/.tmux/resurrect/`. Plugin provisioning state is not
area deployment state and is never inferred as removable ownership.

For generic and WSL Bash, removal restores the bytes and mode of every
pre-existing startup file and deletes a login file only when state proves it was
created as an exact attachment-only file. Native removal deletes only its exact
appended block. Shell removal retains `~/.config/dotfiles/local/bash.sh`,
`~/.config/dotfiles/local/zsh_aliases.zsh`, Zinit data and plugins, shell
history, migration backups and ledger entries, and the completed Vite+
retirement; it never recreates `.zsh_aliases.local` or changes the login shell.

Retained provisioning is not recorded as removable area deployment state.
Installed tools and their manifest-owned launchers survive `--remove`; checks
derive expected resources from the active provisioning manifest and compare
that contract with retained provisioning metadata and the actual installation.

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

The native Bash block is additive and sources only the common dispatcher after
the authoritative native baseline. It is not the generic/WSL bypass block.
Generic and WSL prepend a block that returns immediately for non-interactive
Bash and otherwise runs the managed dispatcher before returning past the
preserved legacy remainder. Their separately selected login block is also
prepended. See [Shell](tools/shell.md#generic-and-wsl-attachments).

The native tmux block is also additive, but sources only the guarded common
persistence path after the native baseline. It never sources or deploys the
private generic baseline, generic adapter, command-empty WSL adapter, or a
host-local file. The final command inside common persistence is guarded TPM
initialization.

## Legacy Migration Safety

The current repository has root-package links and repo-backed local files.
Migration must:

- Convert `~/.gitconfig.local` to an external regular file with mode `0600`
  without following the legacy symlink during writes or permission changes.
- Relocate a recognized `.zsh_aliases.local` link transactionally to the real,
  retained `~/.config/dotfiles/local/zsh_aliases.zsh`; reuse only a
  byte-identical regular destination, never merge divergent content, and remove
  the old link only after active `.zshrc` reads the new path.
- Remove only the exact reviewed Vite+ block from host-owned `.zshenv`, preserve
  Cargo, OpenCode, and unrelated bytes, and retain its rollback backup and
  completed ledger record. Configuration removal does not reverse this
  retirement, and the Vite+ installation remains untouched.
- Leave `.zshrc.local` entirely unowned and untouched.
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
| Git, fzf, zoxide, eza, rg, jq | Native packages | Distro packages |
| `bat` and `fd` command names | Native packages | Managed private wrappers selecting the distro-owned `bat`/`batcat` and `fd`/`fdfind` commands |
| tmux | Native package | Distro package when 3.5 or newer, else locked `aqua:tmux/tmux-builds` via mise |
| Neovim, Starship | Native packages | Suitable package or locked mise fallback |
| mise | Native package | Pinned user-scoped install when absent |
| Node and pnpm | Host-owned and retained; Stage 5 does not replace them | Locked mise artifacts |
| Claude Code | Host-owned and retained; Stage 5 does not replace it | Locked mise artifact |
| Worktrunk | Host-owned and retained; Stage 5 does not replace it | Locked mise artifact |
| OpenCode and `opencode-openai-codex-auth` | Deferred; preserve existing installation and auth state | Deferred; preserve existing installation and auth state |
| Vite+ | Project-local mise files | Project-local mise files |

On Omarchy, bootstrap must fail if a prohibited command such as Neovim
resolves through a mise shim instead of the native package. Alignment does not
require identical installation mechanisms, but it does require unambiguous
owners and compatible behavior.

Vite+ is intentionally project-owned. Projects declare and lock it in their
own mise files; bootstrap never invokes the official installer, creates or
updates a global executable, treats Vite+ as a protected profile command, or
initializes it globally from managed Bash or zsh. Stage 6 durably retires the
reviewed existing global zsh hook.
Project precedence is expected for it. OpenCode and its Codex auth plugin are
outside Stage 5 until a separately reviewed change defines a locked plugin
lifecycle and proves preservation of configuration and authentication.

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

On generic and WSL systems, only explicit provisioning apply may install a
known, checksum-verified mise version when mise is absent. It must accept a
newer compatible existing version and never downgrade it.
`--check --provision` reports the missing tool and planned installation without
network access or mutation; ordinary check and apply do not select optional
core applications.

Use additive fragments:

```text
~/.config/mise/conf.d/
  20-dotfiles-common.toml
  30-dotfiles-profile.toml
```

Loose selectors express maintenance intent. The committed
`manifests/provisioning.json` lock holds the exact versions, backends,
artifacts, inventory identities, hashes, and origins used by explicit provisioning.
Project mise files retain higher precedence for project runtimes, but may not
silently shadow profile-owned commands such as tmux or native Omarchy Neovim.
Bootstrap must not silently advance locked versions.

The retained provisioning receipt is a regular non-symlinked EUID-owned
mode-`0600` file. Validation captures the exact identity whose contents were
checked. Every later read-modify-write parses one stable version and compares
and swaps against that same version, then verifies exact bytes, owner, mode,
and post-write identity. A retained tool root, its mise link, protected
launcher, tool receipt row, and launcher receipt row are one transaction. The
launcher installs before one combined receipt update; commit is not declared
until every filesystem post-state and both exact receipt rows reverify.
Initial mise installation uses the same combined receipt transaction: verified
binary installation and a quarantined compare-and-swap receipt update either
commit together or roll back together on failure or signal, so no stale mise
receipt can survive without its binary.
Launcher-only repair uses the same combined receipt boundary. Rollback removes
only the exact transaction-installed launcher and restores an exact prior
receipted launcher without clobbering a concurrent replacement. Mise files and retained tool directories likewise
capture destination absence before network or staging begins. Files install by
same-directory no-clobber linking; directories install with no-clobber,
no-nesting rename semantics and explicit source/destination postconditions.
Failure removes only unchanged transaction-created destinations and links;
detected changed or appeared same-UID objects are retained at the path named in
the recovery diagnostic. This remains subject to the malicious same-UID
between-syscall boundary documented below.

Verified installation of the new combined receipt is the commit point. The
transaction marks itself committed before best-effort deletion of old receipt
or launcher quarantines and never deletes rollback state first. A cleanup
failure does not revert the committed root, link, launcher, or receipt; it
retains and reports each exact old-object recovery path.

### Observable Ownership Boundary

Bootstrap checks its inherited environment, including exported shell
functions, and every executable candidate found through its effective `PATH`.
It also checks mise resolution from a neutral directory and controlled project
directories so intentional project runtime precedence can be distinguished
from forbidden shadows of protected profile commands. Once Stage 6 deploys the
managed shell, the same resolver runs in that interactive-shell context and can
also inspect aliases and non-exported functions. The controlled shell uses the
managed dispatcher, suppresses the prompt, returns machine-readable status,
inspects every candidate without executing rejected shadows, and validates
private `bat` and `fd` wrappers through their ultimate distro-owned commands.
It disables host-local sourcing for executable ownership. A separate copied
HOME inspection sources host-local Bash inside a denied-network mount namespace
with command sentinels and the real HOME bind-mounted read-only. Bootstrap first
proves the required `util-linux` `unshare`, `mount`, and `setpriv` contract, then
drops all capabilities and enables no-new-privileges before copied host-local
code executes. Bash Worktrunk initialization uses the same capability-free
denied-network child boundary and is skipped silently at startup if that child
cannot be created; apply and check fail closed when the required isolation probe
is unavailable.

An arbitrary unexported alias or function in an already-running parent shell is
not inherited and cannot be inspected reliably. Bootstrap does not parse
unrelated startup files to guess at those objects. Missing native owners and
forbidden observable shadows are blocking; an otherwise valid native Omarchy
owner whose parseable version differs from the recorded core or Neovim pin
produces a separate non-blocking warning.

## Accepted Pin Record

The reviewed proposal is
`manifests/proposals/2026-07-17-stage5-tool-pins.json`; the active lock is
`manifests/provisioning.json`. Bootstrap verifies each artifact itself before
installing it into a retained root and registering that exact root with its
fully qualified backend through offline `mise link`. Mise/Aqua is never allowed
to substitute an unchecked download. Vite+ ownership and the OpenCode/Codex
deferral remain accepted decisions.

## Test Isolation

Stage 5 automated tests use a temporary `HOME`, temporary XDG roots, fixture
host and mise roots, controlled `PATH`, and fixture checkouts when manifests or
area readiness differ. They must not inspect or mutate the developer's real
home, user executable directories, mise data, or active OpenCode installation.
Provisioning applies use fake, local artifacts in fixtures; no real
provisioning apply is part of the automated gate.

## Acceptance Criteria

- `--check` reports intended changes and missing dependencies without
  mutation, including the exact manual package command when dependencies are
  missing and a non-blocking Omarchy version-drift warning where applicable.
- Apply and removal obey the canonical network policy.
- Ordinary apply is configuration-only, and both check forms are offline and
  non-mutating.
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
