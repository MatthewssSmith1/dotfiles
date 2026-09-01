---
name: updating-dependencies
description: Update pinned Omarchy core, omarchy-nvim package, and LazyVim starter inputs, including source snapshots and signed package evidence.
---

Authoritative contracts: [upstream.md](../../../docs/upstream.md) and [artifacts/README.md](../../../docs/artifacts/README.md). Keep this operational workflow consistent with them.

Use a throwaway directory under `/tmp` for research and downloads. Research and artifact capture must not modify the checkout. `scripts/upstream sync` is the checkout-changing source synchronization operation; manual identity/evidence updates required by sync are made immediately before it.

## 1. Resolve independent stable streams

- Omarchy core is selected from immutable upstream tags. Resolve the selected tag to its full commit with `git ls-remote --tags`; use the peeled object for an annotated tag. Omarchy v4 installs its runtime tree under `/usr/share/omarchy`, but Git is authoritative when an installed tree omits a tracked baseline such as Git configuration.
- Resolve `omarchy-nvim` independently from the stable package database at `https://pkgs.omarchy.org/stable/x86_64/omarchy.db`. Read `%VERSION%`, `%SHA256SUM%`, and `%BUILDDATE%` from the package record. Do not describe the package as matching the core release.
- Map that package version to the immutable `omarchy-pkgs` commit whose `pkgbuilds/omarchy-nvim/PKGBUILD` sets its `pkgver`. Confirm the package build date is consistent with the commit date.
- Resolve the LazyVim starter commit from the source archive and checksum in that PKGBUILD. Prove the archive tree/checksum maps to the selected immutable starter commit rather than carrying an earlier starter pin forward by assumption.

## 2. Review source scope and portability

- Diff core and package commits independently. Review every tracked source path, overlay inventory change, PKGBUILD append, and starter change.
- The v4 contract records machine-verifiable provenance for Herdr config, selected Herdr Bash helpers, tmux, Starship, Bash sources, Git baseline, and the Tokyo Night palette/template. Source paths in the manifest must identify immutable Git blobs even when live-host inspection begins under `/usr/share/omarchy`.
- Baseline/reference snapshots remain byte-exact. Ubuntu payload adapters may select or curate reviewed helpers. Do not import an evident upstream defect, a desktop-only command, or an Omarchy-only dependency into the portable Ubuntu payload merely because it appears in the baseline.
- Preserve repository-owned framework markers such as `.stow-local-ignore` and `.empty-package` through generated tree replacement.

## 3. Capture the signed package evidence

While the selected package remains in stable, download its archive, detached signature, and current database into the throwaway directory.

1. Verify the archive SHA-256 equals stable metadata and record SHA-256 for the database, archive, and signature.
2. Import the public key from the pinned `omarchy-pkgs` commit into a temporary `GNUPGHOME`; verify the detached signature and record fingerprint/timestamp.
3. Extract the package. Preserve `.PKGINFO`, `.BUILDINFO`, stable package record, retrieval metadata, signing key, base64 signature, and sorted `config.sha256`. Verify `.BUILDINFO`'s PKGBUILD hash against the pinned commit and verify every accepted packaged config member.
4. Copy the extracted `lazy-lock.json`; it is package-only evidence and cannot be reconstructed from Git.
5. Keep exactly one active `docs/artifacts/omarchy-nvim-<version>/` evidence set. Remove only the superseded active evidence directory; retain historical proposal records and Git history. Do not commit the large package archive.

Never weaken signature, checksum, package-member, or provenance checks to make a refresh pass. Report any unavailable stable artifact or signature failure as a blocker.

## 4. Stage identities and proposal

Before sync, update the accepted artifact identity consistently in `scripts/upstream`, `manifests/sources.json`, the package lockfile, evidence, and focused test constants. Update fixed transform output blobs when source or transform bytes changed.

Create `manifests/proposals/<date>-<purpose>.json` with the exact independent pins `omarchy`, `lazyvim-starter`, and `omarchy-pkgs`. Each pin records its HTTPS repository, human version/package identity, and full 40-hex commit. Leave superseded proposals untouched.

## 5. Synchronize and inspect

Run the only networked baseline operation:

```sh
scripts/upstream sync --proposal manifests/proposals/<file>.json
```

Sync must fetch immutable commits, prove path/blob membership, replay recorded transforms, preserve the accepted package-only artifact, verify the candidate, and atomically replace the active manifest/snapshot. Review generated diffs, the complete source inventory, adapter curation, and framework markers.

Then verify offline:

```sh
scripts/upstream verify
```

## 6. Propagate and test

Update `docs/upstream.md`, `docs/artifacts/README.md`, directly affected tool contracts, script/test constants, and stale active identity references. The active manifest is canonical for pins and source inventory. Do not rewrite area lifecycles as part of an accepted-input refresh, and do not add Neovim restore markers or state-convergence steps; package lock acceptance is verified by manifest/artifact checks.

Run the focused gates while iterating:

```sh
scripts/upstream verify
tests/upstream_test.sh
tests/contract_test.sh
tests/shell_test.sh
tests/git_test.sh
tests/herdr_test.sh
tests/tmux_test.sh
tests/nvim_test.sh
```

Run additional directly affected static suites when inventory or deployment contracts require them. Because an upstream refresh is cross-cutting, run `tests/run.sh` before committing. This workflow does not deploy or apply the accepted inputs to the live host.
