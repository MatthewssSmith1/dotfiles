# Omarchy

## Status

This document describes planned post-migration behavior. The repository README
remains authoritative until native integration and validation pass.

Notes for native Omarchy machines. On this profile, installed Omarchy
defaults are authoritative; this repository attaches shared layers without
replacing refresh-managed files. See
[Architecture](../omarchy-alignment/architecture.md) and
[Deployment](../omarchy-alignment/deployment.md#native-omarchy-attachments).

## Refresh-Managed Files

Omarchy refresh or reinstall operations can replace Bash, tmux, Starship, and
Neovim configuration. Those destinations stay regular Omarchy-owned files,
never symlinks into this checkout. Shared behavior attaches through small
guarded regular-file changes (marker blocks, idempotent, drift-reporting),
and `omarchy-nvim-refresh` can additionally clear Neovim data, state, and
cache — recovery recreates only the managed loader.

After a supported refresh, re-run bootstrap to reapply attachments; it
converges without duplicating them.

## Executable Ownership

Development tools resolve to native Omarchy packages. Bootstrap fails if a
prohibited command such as Neovim resolves through a mise shim instead of the
native package. See the ownership table in
[Deployment](../omarchy-alignment/deployment.md#executable-ownership).
Missing native owners and forbidden exported-function, `PATH`, shim, user-local,
or project shadows are blocking. Arbitrary unexported aliases and functions in
the parent shell are outside bootstrap's inherited visibility; the managed
interactive shell closes that boundary in Stage 6.

## Version Drift

Native Omarchy self-updates while other machines deploy the pinned snapshot
recorded in [Upstream](../omarchy-alignment/upstream.md). Bootstrap reports
separate core and `omarchy-nvim` package warnings when a valid native owner's
parseable version differs from its recorded pin. These warnings are
non-blocking; missing owners, malformed metadata, and forbidden shadows remain
blocking. Drift is expected, and advancing either pin is a separate explicit
sync-and-review operation.

## Validation

Native-profile design and validation are batched into one stage run from this
machine: attachment behavior against real refresh-managed files, Neovim loader
design and refresh recovery, forbidden-shim detection, and separate core and
Neovim package drift warnings. Checklist:
[Omarchy native integration and validation](../omarchy-alignment/plan.md#9-omarchy-native-integration-and-validation).
