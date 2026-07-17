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

## Version Drift

Native Omarchy self-updates while other machines deploy the pinned snapshot
recorded in [Upstream](../omarchy-alignment/upstream.md). Bootstrap and
`--check` print a non-blocking warning when the installed version differs
from the pin. Drift is expected; advancing the pin is a separate explicit
sync-and-review operation.

## Validation

Native-profile design and validation are batched into one stage run from this
machine: attachment behavior against real refresh-managed files, Neovim loader
design and refresh recovery, forbidden-shim detection, and separate core and
Neovim package drift warnings. Checklist:
[Omarchy native integration and validation](../omarchy-alignment/plan.md#9-omarchy-native-integration-and-validation).
