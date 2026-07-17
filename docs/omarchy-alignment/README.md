# Omarchy Alignment

## Status

This is the temporary planning packet for the Omarchy alignment migration. It
records accepted decisions, unresolved gates, implementation order, and
acceptance criteria. The repository README remains authoritative for the
currently implemented configuration until a migration stage is complete.

The packet is tracked in git so the work does not depend on conversation
history or a single working copy. Decisions should be updated here as
implementation proceeds.

## Objective

Provide one Omarchy-oriented development workflow across native Omarchy,
Ubuntu 24.04 and newer generic Linux systems, Ubuntu under WSL, and VPS or
other remote Linux environments.

Consistent behavior and muscle memory are the primary targets. Native Omarchy
uses its installed defaults where possible. Other systems use pinned, reviewed
copies of relevant defaults with portability and personal changes kept visibly
separate.

## Documents

| Document | Responsibility |
|----------|----------------|
| [Architecture](architecture.md) | Goals, layers, profiles, locations, and ownership boundaries |
| [Deployment](deployment.md) | Stow packages, bootstrap, local state, migration safety, executable ownership, and mise |
| [Upstream](upstream.md) | Source pins, snapshots, synchronization, and updates |
| [Implementation Plan](plan.md) | Stage order, gates, verification, rollout, and cleanup |
| [Deferred Work](deferred.md) | Explicitly unscheduled improvements |
| [Git](tools/git.md) | Git layers, includes, identity migration, and tests |
| [Shell](tools/shell.md) | Bash, Starship, fzf, zoxide, mise activation, personal tools, and transitional zsh |
| [tmux](tools/tmux.md) | Baseline, adapters, persistence, plugins, terminals, and tests |
| [Neovim](tools/neovim.md) | Baseline reset, source model, personal override, refresh recovery, and open decisions |
| [Artifacts](artifacts/README.md) | Preserved files that cannot be re-derived from git sources |

Durable per-environment operational guidance lives outside the packet in
[`docs/environments/`](../environments/): [Windows
Terminal](../environments/windows-terminal.md) (client-terminal guidance),
[WSL](../environments/wsl.md), [Omarchy](../environments/omarchy.md), and
[generic Linux and VPS](../environments/generic.md). Those documents outlive
the packet.

## Accepted Direction

- Use four conceptual layers: Omarchy baseline, portability adapter, shared
  personal configuration, and host-local configuration.
- Support auto-detected Omarchy, generic Linux, and WSL profiles with an
  explicit validated override.
- Keep GNU Stow, but deploy explicit per-area packages with `--no-folding`.
- Use guarded attachments instead of symlinks for native Omarchy files that
  refresh operations may replace.
- Keep upstream synchronization explicit, pinned, reviewable, and separate
  from bootstrap and startup.
- Pin upstream inputs as Git commits, record source blob identities and
  transforms in a practical manifest, and reserve artifact hashes for inputs
  that Git cannot reproduce.
- Make Git, Bash, tmux, Neovim, and transitional zsh independently selectable
  areas. Agent-skills migration is deferred.
- Check and report system dependencies without invoking `sudo` or changing the
  login shell. Fresh generic and WSL hosts have an explicit manual package
  installation step; bootstrap prints the exact command.
- Prefer platform packages for stable generic CLI dependencies and mise for
  runtimes and approved user-scoped tools. Lean into mise wherever it can
  absorb tool-management complexity; tmux uses locked
  `aqua:tmux/tmux-builds` when the distro package is older than 3.5.
- Keep `--check`, removal, Bash startup, and tmux startup offline. Apply may
  fetch pinned runtime tools and locked tmux plugins but never Neovim plugins,
  runtime assets, or baselines; transitional zsh retains its documented
  first-start exception.
- Refuse profile changes until all existing deployment state is removed
  explicitly.
- Preserve existing Git credential helpers in the host-local layer.
- Retire the current Kickstart Neovim configuration instead of carrying its
  customizations into the Omarchy baseline. Git history is the configuration
  backup.
- Preserve tmux persistence while adopting the stock Omarchy interaction
  model.
- Treat Bash with Starship as the evaluated primary shell; keep the existing
  zsh configuration as a transitional default and behaviorally frozen escape
  hatch, with convergence or retirement deferred until after the migration.
- Include minimal Windows Terminal client handling in scope: documented
  manual host-side unbinds and key checks, applying to WSL shells and to SSH
  sessions into remote hosts alike.
- Implement and validate first on the upgraded Ubuntu 24.04 WSL distro.
- Batch native Omarchy integration and validation into one consolidated stage
  run from the native machine.
- Keep native Omarchy theme selection authoritative and defer portable,
  coordinated themes.
- Report version drift between installed native Omarchy and the recorded pin
  as a non-blocking warning.

The linked documents are canonical for the details behind these summaries.

## Remaining Planning Gates

These questions do not block this documentation packet. They must be resolved
before implementation reaches the affected stage:

1. Specify the native Neovim personal loader and refresh-recovery behavior
   during the Omarchy native integration stage.
2. Select exact mise-managed tool versions and generate their lockfiles.
3. Select exact TPM and persistence plugin commits.
4. Define update policy for Vite+ and the OpenCode Codex plugin outside mise.
5. Record the tested Windows Terminal version before closing the tmux gate.

Tool-specific implications are recorded in [Deployment](deployment.md),
[tmux](tools/tmux.md), and [Neovim](tools/neovim.md).

## Documentation Rules

- Give each decision one canonical location.
- Link to details instead of duplicating designs.
- Separate accepted decisions, open questions, non-goals, and acceptance
  criteria.
- Label recommendations that have not been accepted.
- Keep exact upstream revisions in [Upstream](upstream.md) until a
  machine-readable manifest replaces them.
- Keep deferred work outside the initial implementation scope.
- Do not create ADRs during active migration planning.

## Temporary Lifecycle

This packet must not become permanent documentation by inertia. At the end of
the migration:

- Move user setup and commands into the repository README.
- Distill stable architecture into concise permanent docs or ADRs.
- Move upstream refresh operations into a dedicated skill or runbook.
- Preserve `docs/environments/` as durable operational context, promoting it
  to a repository skill only if that earns its keep.
- Move exact source pins and ownership rules into machine-readable manifests.
- Retain tool rationale near the implementation only where it remains useful.
- Preserve deferred themes in a durable future-work document if still wanted.

Remove this packet only after those replacements exist and have been reviewed.
