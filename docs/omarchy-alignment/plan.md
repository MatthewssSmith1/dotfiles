# Implementation Plan

## Working Rule

Implement stages in order. A stage is complete only after its gate and
stage-specific tests pass. Open questions may delay their affected stage but
must not cause guessed behavior to enter implementation.

The primary implementation host is the upgraded Ubuntu 24.04 WSL distro.
Generic behavior is developed there first; Omarchy-specific code paths use
isolated fixtures until the native integration stage.

## 1. Documentation And Contract Closure (Status: Implemented)

- Record accepted network, verification, tmux backend, profile transition,
  credential, zsh, agent-scope, and WSL rollout decisions.
- Define exact profile probes and override compatibility.
- Define qualified package IDs, profile expansion, state, removal, transaction,
  and root-Stow cutover contracts.
- Distinguish planned behavior from the current implementation.
- Preserve the released Neovim lockfile and document its trust boundary.

Gate: an implementation agent can begin the Git foundation without choosing
undocumented profile, package, state, migration, network, or authentication
behavior.

## 2. Minimal Source Foundation And Git End-To-End (Status: Implemented)

Build the smallest complete vertical slice. This stage includes the source data
that Git deployment consumes rather than depending on the later general sync
stage.

- Add the source-manifest schema and the pinned Omarchy Git snapshot.
- Record Git source path, commit, blob identity, mode, and destination.
- Add offline verification for that minimal snapshot.
- Add the minimal Git/Stow/bootstrap dependency manifest and generate its exact
  manual package command in this stage; Stage 5 generalizes the mechanism.
- Capture and review the complete known legacy-link inventory for every current
  area on the Stage 2 WSL host before disabling root Stow. Scope the scan to
  dotfiles destinations and known legacy links; opaque application data beneath
  the home directory is not part of this inventory. Leave non-Git legacy links
  in place and unmanaged until their own migration stages. Capture the native
  Omarchy inventory in Stage 9 before migrating that host.
- Mark all inventoried agent-skill links as permanently excluded from this
  migration's cleanup.
- Introduce package expansion, exact Stow invocation, profile detection with
  validated override, process locking, and per-area state for Git.
- Add the guarded regular-file helper needed by `~/.gitconfig`.
- Convert identity into an external mode-`0600` regular file without following
  the legacy symlink during writes or permission changes.
- Preserve effective credential helpers and unrelated host settings in the
  local layer.
- Deploy the Git baseline, adapter, and personal layer.
- Land package roots and migration logic while retaining every tracked legacy
  source path. Ignored agent skills remain permanently outside migration
  ownership and may be managed or removed by the user. Then atomically disable
  root Stow, update permanent README commands, and migrate only Git. Other
  inventoried legacy links remain in place but unmanaged until their per-area
  migration stages; tracked compatibility source paths remain until every known
  host has migrated or is pinned to an old checkout.

Tests added in this stage cover:

- Profile detection, conflicts, unsupported hosts, and every override.
- Qualified package expansion and duplicate-target refusal.
- `--check`, apply, `--remove`, profile mismatch, locking, state schema, and
  interruption at each state commit point.
- Relative, absolute, broken, moved-checkout, and unrelated legacy links.
- Guarded marker parsing, malformed blocks, permissions, symlink destinations,
  atomic replacement, and concurrent access.
- Git value origins, external identity mode, local setting preservation,
  repository precedence, and prompt-disabled fake credential helpers.

Gate: Git deploys and removes independently on the fresh WSL host; every
required value resolves from the expected layer; identity and credentials
remain functional and external; root-package Stow is no longer reachable.

## 3. Generalize Deployment Mechanics And Migration Safety (Status: Implemented)

- Generalize area manifests, dependency closure, per-area transactions, state,
  and removal to Bash, tmux, Neovim, and transitional zsh.
- Define package closures for those areas without deploying their unfinished
  replacement payloads.
- Consume the reviewed legacy-link inventory when testing generalized cleanup;
  do not rediscover ownership after paths move.
- Add fixture packages that test layer ordering and independent-area failure
  without representing unfinished production configuration.
- Leave agent skills completely untouched.

Tests added in this stage cover:

- Independent selected-area success and aggregate failure.
- Rollback journal success and rollback-failure refusal.
- Omitted deployed areas remaining untouched.
- Full and per-area removal from recorded state.
- Profile changes refusing until all prior state is removed.
- Unknown packages, stale checkout roots, malformed state, and newer schema.
- Fixture package conflicts and shared-path refusal.

Gate: the framework represents every in-scope area and proves its transaction
semantics with fixtures, without claiming unfinished shell, tmux, or Neovim
payloads are ready.

## 4. Full Upstream Synchronization (Status: Implemented)

- Expanded schema v1 compatibly with reference destinations, append/overwrite
  transforms, and artifacts, with one manifest entry per snapshot file.
- Populated `packages/upstream/{starship,tmux,nvim}` and the Omarchy Bash/theme
  reference root from the reviewed proposal and exact immutable pins.
- Added HTTPS-only networked sync with same-filesystem staging, Git path/blob
  verification, offline candidate verification, atomic replacement recovery,
  and complete offline accepted-snapshot verification.
- Relocated the preserved `lazy-lock.json` into the Neovim snapshot without
  changing its bytes, hash, or recorded provenance.
- Recorded one real append and no overwrite: the pinned starter has no
  `lazyvim.json` collision.

Tests added in this stage cover:

- Unreachable commits, missing paths, blob mismatches, mode and symlink inputs,
  transform ordering, and malicious paths.
- Failed fetch, assembly, candidate verification, and atomic replacement.
- Offline verification under denied network access.
- Manifest and snapshot drift.

Gate: all committed baseline files reproduce from explicit pinned inputs during
sync, and the accepted snapshots verify offline against the manifest.

## 5. Ownership-Aware Provisioning (Status: Implemented)

- Added profile-aware and area-aware dependency checks generated from manifests.
- Print exact manual package commands without invoking `sudo`.
- Added pinned generic mise installation and additive configuration fragments.
- Selected exact tool versions, backends, artifacts, hashes, and origins.
- Use locked `aqua:tmux/tmux-builds` when the distro tmux is older than 3.5.
- Added explicit `--provision`; ordinary apply remains configuration-only, while
  `--check --provision` remains offline and non-mutating.
- Provision Node, pnpm, Claude Code, and Worktrunk only through no-area
  `--provision`; area-scoped provisioning selects only area dependencies.
- Keep OpenCode and `opencode-openai-codex-auth` outside Stage 5 and preserve
  their executable, configuration, plugins, and authentication state.
- Keep Vite+ project-owned and locked through project mise files, with no
  global installer, executable, or shell hook.
- Added separate native Omarchy core and Neovim package drift warnings.
- Reject forbidden executable shadows within the observable ownership boundary;
  Stage 6 invokes the reusable resolver inside the managed interactive shell.

Tests added in this stage cover:

- Offline non-mutating `--check`.
- Full and per-area generated package commands on clean Ubuntu 24.04 metadata.
- Pinned apply under controlled network access and denied baseline sync.
- Mise lock state, backend identity, and PATH ownership from multiple working
  directories.
- Exported-function, shim, user-local-bin, and project shadowing through normal
  bootstrap; alias and non-exported-function cases through the reusable
  resolver in a controlled shell.
- Temporary homes, XDG roots, fixture mise/OpenCode installations, and
  controlled paths; automated gates perform no real provisioning apply.

Gate: generic systems converge using approved owners, missing distro packages
are reported exactly, runtime pins do not advance silently, and Omarchy keeps
native ownership.

## 6. Shell Migration (Status: Complete; Ready; WSL Operational Acceptance Passed)

Phase 1 closes and reviews the documentation contract before code, payload,
readiness, or live-home changes. Its accepted design is in
[Shell](tools/shell.md): reversible generic/WSL bypass blocks and stable login
selection, a distinct additive native attachment, exact runtime order and WSL
adapter boundary, private `bat`/`fd` wrappers, actual conditional aliases, and
the retained host-local Bash layer.

No implementation phase may begin until the Phase 1 documentation diff has
been reviewed and the active documents pass the contract gate.

Implementation then proceeds in separate gated phases:

1. Generalize guarded regular-file blocks, migration-ledger handling, and
   narrowly approved legacy-link replacement; prove byte, mode, marker, ledger,
   and rollback behavior without changing shell readiness.
2. Materialize only the pinned upstream shell, aliases, tmux helper, and
   Readline payloads and verify their byte identity offline.
3. Implement managed Bash payloads and lifecycle, including controlled
   interactive ownership validation, while Bash remains `framework`.
4. Package behaviorally frozen transitional zsh and transactionally relocate
   `.zsh_aliases.local`; retire global Vite+ from managed `.zshrc` and the exact
   reviewed host `.zshenv` block. `.zshrc.local` remains untouched. The only
   startup network exception is a missing-Zinit first start.
5. Complete isolated startup, attachment, ownership, denied-network, migration,
   removal, retention, rollback, and earlier-stage regression tests.

The reusable engine primitives, selected upstream Bash payloads, managed Bash
payload/lifecycle, and transitional zsh packaging/migrations are implemented.
The complete combined Stage 6 matrix passed before both shell areas changed to
`ready`; WSL operational rollout acceptance passed after the ordered live
deployment and smoke checks.

The implementation enforces the WSL operational sequence: first Bash apply is
explicit and excludes zsh; first zsh apply is a later explicit command after
Bash state exists and excludes Bash. Full checks remain available before
rollout, and default apply is restored after both shell states exist.

Shell removal is state-driven and reversible for managed attachments. It
retains host-local files, tools, Zinit, history, migration backups and ledger
records, and the durable Vite+ retirement, and never changes the login shell.

Tests added in this stage cover:

- Interactive, non-interactive, login, SSH, nested, and WSL Bash behavior.
- Alias meanings, capability guards, initialization order, and existing
  `EDITOR`/`VISUAL` values.
- Denied-network Bash startup.
- Transitional zsh before and after Zinit exists.
- Native Bash attachments against isolated fixtures.
- Byte-exact generic/WSL startup-file restoration and native refresh recovery.
- Alias and non-exported-function shadows observed without execution.
- zsh local-file collisions, exact `.zshenv` retirement, retained migrations,
  and `.zshrc.local` non-ownership.

Gate: Bash behavior is predictable across generic, WSL, SSH, and missing-tool
scenarios; Bash startup remains offline; transitional zsh behavior remains
available without a login-shell change. Only after the full isolated gate passes
may Bash and zsh change from `framework` to `ready`; that flip occurs immediately
before live rollout. On WSL, apply and smoke-test Bash first while current zsh
remains the login-shell recovery path, then apply zsh separately. Operational
acceptance completes only after both explicit checks and smoke tests pass. A
rollout failure is fixed and regated rather than bypassing readiness checks.

## 7. tmux Migration (Status: Complete; Ready; WSL Operational Acceptance Passed)

The documentation, package layout, relocated byte-identical baseline,
schema-backed locks, area lifecycle, migration, native attachment, isolated
validation, active-server inspection, parser fixtures, and transactional plugin
provisioning are implemented. tmux is `ready` after the automated Stage 7 gates
passed. WSL operational acceptance passed after the explicit live rollout,
server transition, restore, and Windows Terminal 1.24.11911.0 checks. The
accepted design is in [tmux](tools/tmux.md).

Implemented lifecycle coverage includes:

1. Add tmux area lifecycle code and the native guarded source attachment
   without changing readiness.
2. Implement offline exact-closure checks and the sole networked plugin apply
   interface, `bootstrap.sh --provision --area tmux`.
3. Permit only missing or clean-drift plugin staging/replacement, transactionally;
   refuse dirty, ambiguous, non-owned, linked-worktree, or symlinked state.
4. Prove removal retains both plugin checkouts and Resurrect data.
5. Validate selected client identity, socket-reported active-server versions,
   `/proc` owner/path identity, and denied-network isolated servers independently.

The final manual gates completed with save/restart/restore after the executable
transition and the documented Windows Terminal unbind/version acceptance.

Tests added in this stage cover:

- Effective options and key tables on isolated homes and sockets.
- tmux 3.2a, 3.4, and 3.5-or-newer parsing against the committed baseline.
- Terminfo, truecolor, clipboard, plugin order, exact lock closure, every
  provisioning refusal/rollback path, and denied-network apply, check, and
  startup.
- Existing-server mismatch reporting without automatic reload or restart.
- Native attachment refresh, drift, exact removal, and absence of generic, WSL,
  or host-local sources.
- Duplicate Stow target refusal and removal retention for plugins and Resurrect.
- Manual Windows Terminal key checks on a recorded client version.

Gate: prefixes, bindings, indexes, status, key protocol, plugin order, and
persistence validate on generic and WSL; an upgraded active server is restarted
and restored deliberately; terminal limitations are recorded against tested
versions. Stage 7 marked tmux ready only after the automated gate passed;
package and manifest presence alone never changes readiness.

## 8. Generic And WSL Neovim Migration

- Use the completed 2026-07-20 stable-channel reevaluation: authoritative
  stable remains `omarchy-nvim 2026.6.17-1`; do not substitute edge releases.
- Remove only recognized Kickstart links; use Git history as configuration
  backup.
- Rename runtime data, state, and cache to collision-free timestamped siblings
  once, using XDG-resolved locations and the retained host migration ledger.
- Deploy the assembled generic baseline and relative-number personal layer.
- Bootstrap lazy.nvim at the commit recorded in `lazy-lock.json` before loading
  it.
- Disable periodic update checking.
- On the first explicit launch, run a one-time locked restore before normal
  editor startup. Record the restored lockfile blob identity in Neovim area
  state only after success; interruption leaves it absent and retries safely.
- After later lock changes, require an explicit restore command and update the
  marker only after every applicable plugin checkout verifies.
- Disable automatic missing-plugin installation during ordinary startup and
  require lock coverage for every active shared plugin spec.
- Inventory Mason, Treesitter, rocks, build outputs, and project-local specs;
  assign each a pinned, explicit-network, or disabled-auto-install policy.
- Document rollback from a failed first launch.

Tests added in this stage cover:

- Clean data directories and deliberately divergent plugin caches.
- Locked lazy.nvim bootstrap and explicit restore after lock changes.
- Dirty, folded, individually Stowed, broken, and unrelated config paths.
- Backup collisions, interruption, rerun, rollback, and custom XDG roots.
- First-launch and later explicit-restore network access, followed by
  denied-network ordinary startup after all runtime-asset policies are active.
- Lockfile non-mutation and plugin commit convergence.

Gate: generic and WSL provide the intended LazyVim/Omarchy workflow from pinned
sources without activating old configuration; runtime state remains recoverable;
plugin source commits converge to the committed lock.

## 9. Omarchy Native Integration And Validation

Run this stage from the native Omarchy machine. It includes the remaining
native Neovim design, not only validation.

- Validate Bash, tmux, and Git attachments against real refresh-managed files.
- Design and implement the native Neovim personal loader, drift detection,
  removal, and refresh recovery.
- Run `omarchy-nvim-refresh`, reattach the loader, and verify recovery.
- Verify native executable ownership and separate core/Neovim drift warnings.
- Re-run apply and removal to prove convergence and cleanup.

Gate: Omarchy uses native aligned tools; native refreshes can replace baselines
without overwriting shared personal source; attachments and the Neovim loader
reapply and remove safely.

## 10. Stabilization And Distillation

- Run every area independently and as the full default set.
- Repeat apply, check, removal, and reapply on all supported profiles.
- Test profile mismatch refusal and explicit transition cleanup.
- Deny network during check, removal, Bash startup, tmux startup, and upstream
  verification.
- Exercise approved network paths independently.
- Update permanent README and durable environment guidance from planned to
  implemented behavior.
- Distill source operations into a runbook or skill and exact pins into the
  manifest.

Gate: all target profiles satisfy their acceptance criteria and temporary
planning content has a reviewed durable destination.

## Accepted Rollout

1. Validate the upgraded Ubuntu 24.04 distro's identity and package baseline
   before applying dotfiles.
2. Implement and test each generic/WSL stage there using isolated homes and
   tool-specific test roots before the real home.
3. Run native integration from the Omarchy machine only after generic and WSL
   stages pass.

## Documentation Cleanup

After stabilization, distill this packet into permanent documentation,
machine-readable manifests, operational skills, and nearby implementation
comments as described in the [packet lifecycle](README.md#temporary-lifecycle).
Delete the packet only after those replacements have been reviewed.
