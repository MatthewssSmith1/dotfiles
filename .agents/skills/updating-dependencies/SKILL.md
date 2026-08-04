---
name: updating-dependencies
description: Update pinned upstream baselines (Omarchy core, omarchy-nvim overlay and package artifact, LazyVim starter) — use when refreshing manifests/sources.json pins, syncing packages/upstream snapshots, or re-verifying the lazy-lock.json artifact.
---

Authoritative background: [upstream.md](../../../docs/upstream.md) (source model, sync guarantees) and [artifacts/README.md](../../../docs/artifacts/README.md) (package trust boundary). This file carries the operational walkthrough; keep it consistent with those contracts.

Work in a throwaway directory (e.g. `/tmp/omarchy-update-<date>/`). Everything before `scripts/upstream sync` is read-only research; sync is the only step that touches the checkout, and it only stages then atomically replaces `packages/upstream` + `manifests/sources.json`.

## 1. Discover latest stable versions

- Omarchy core: `git ls-remote --tags https://github.com/basecamp/omarchy 'refs/tags/v*'` — take the highest tag. Tags are lightweight, so the listed hash is the commit ID (an annotated tag would show a separate `^{}` peel line; use that one).
- omarchy-nvim: the authoritative channel is the stable package database, not git. `curl -fsSLO https://pkgs.omarchy.org/stable/x86_64/omarchy.db`, `tar -xf` it, and read `omarchy-nvim-<ver>/desc` for `%VERSION%`, `%SHA256SUM%`, and `%BUILDDATE%`. Git may carry newer pkgvers that never reached stable (2026.7.15, for example); never pin those.
- Map the package version to its `omarchy-pkgs` commit: `git clone --filter=blob:none https://github.com/omacom-io/omarchy-pkgs`, then `git log -- pkgbuilds/omarchy-nvim/` and find the commit whose PKGBUILD sets the matching `pkgver=`. Sanity-check that `%BUILDDATE%` follows that commit's date by minutes, not days.

## 2. Review what actually changed

- Core: `git diff --stat <old-tag> <new-tag> -- <every path in manifests/sources.json with repository basecamp/omarchy>`. An empty diff means a metadata-only pin refresh.
- Overlay: `git diff <old-commit> <new-commit> -- pkgbuilds/omarchy-nvim/` in omarchy-pkgs. Three things matter:
  - the `source=`/`sha256sums=` lines (a changed starter tarball checksum means the LazyVim starter pin moved and must be re-resolved to a commit);
  - the lines the PKGBUILD appends to `lua/config/options.lua` (recorded as an append transform in the manifest — if these change, the transform bytes in the proposal review must match);
  - the overlay file inventory under `lua/`, `plugin/`, `lazyvim.json` (added/removed files change the manifest inventory, not just blobs).
- Read the content diffs of changed overlay files: they deploy into the generic/WSL Neovim profile, so judge portability impact before accepting.

## 3. Preserve the package artifact evidence

`lazy-lock.json` exists only inside the built package. While the package is still on stable, immediately capture the full evidence set modeled on `docs/artifacts/omarchy-nvim-<ver>/`:

1. Download `omarchy-nvim-<ver>-any.pkg.tar.zst` and its `.sig` from `https://pkgs.omarchy.org/stable/x86_64/`; record SHA-256 of database, package, and signature (`SHA256SUMS`).
2. Verify the package hash equals the database `%SHA256SUM%`.
3. Verify the detached signature with the public key committed in the pinned `omarchy-pkgs` revision (`gpg --import` that key into a throwaway `GNUPGHOME`); record fingerprint and signature timestamp.
4. Extract; preserve `.PKGINFO`/`.BUILDINFO` metadata, confirm `.BUILDINFO`'s PKGBUILD SHA-256 matches the PKGBUILD at the pinned overlay commit.
5. Hash every regular member of `usr/share/omarchy-nvim/config` into `config.sha256` — one `<sha256>  <relative path>` line per file, sorted with `LC_ALL=C` (offline verify regenerates the expected list with jq's codepoint sort and `cmp`s it byte-for-byte; a locale-sorted file fails). Keep the base64 signature (`package.sig.b64`), key (`omarchy-signing-key.asc`), database record (`repository.desc`), and response metadata (`retrieval.txt`).
6. Do not commit the ~177 MB archive; the member-hash record is the accepted trust-on-verification boundary. Delete the previous release's evidence directory — one active baseline; git history is the archive.

## 4. Stage the repo-side identity swap (before sync)

Sync does not take the artifact from the proposal — `preserve_artifacts` copies the *active* checkout's lockfile into the candidate and requires the *active* `manifests/sources.json` artifact record to match constants hardcoded in `scripts/upstream`. So before running sync:

1. Update the constants block near the top of `scripts/upstream`: `LAZY_LOCK_RELEASE`, `LAZY_LOCK_SHA256`, `NVIM_EVIDENCE_DIR`, `STABLE_DB_SHA256`, `PACKAGE_SHA256`, `SIGNATURE_SHA256` (`SIGNING_KEY_SHA256` only if the key rotated), plus the version-bearing literals inside `verify_nvim_artifact_evidence` (package filename greps, `pkgver = …`, `pkgbuild_sha256sum = …`). A global sed of old→new hash/version pairs covers all of it.
2. Copy the newly extracted `lazy-lock.json` over `packages/upstream/nvim/.config/nvim/lazy-lock.json` (mode 0644).
3. Hand-edit the `artifacts[0]` record in `manifests/sources.json` (release, sha256, provenance artifact/artifact_sha256/build_date/extracted/record).
4. If the starter pin moved, also recompute the two `nvim-offline-bootstrap-policy` transform output blobs (`NVIM_INIT_POLICY_BLOB`, `NVIM_LAZY_POLICY_BLOB`).

## 5. Propose and sync

- Write `manifests/proposals/<date>-<purpose>.json` (schema v1: `pins` of `{id, repository, version, commit[, package_identity]}`; exactly the three ids `omarchy`, `lazyvim-starter`, `omarchy-pkgs`; commits must be full 40-hex — version-only pins are refused).
- `scripts/upstream sync --proposal manifests/proposals/<file>` — the only networked baseline operation. It fetches the immutable commits, proves path/blob membership, replays transforms, assembles the candidate, runs offline verification, then atomically replaces the snapshot and manifest.
- Review `git diff` of the resulting baseline change; confirm repo-owned framework markers (`packages/upstream/*/.stow-local-ignore`, `.empty-package`) survived the tree swap; then `scripts/upstream verify` must pass offline.

## 6. Propagate and validate

- Grep the repo for the old identities (release tags, package versions, commits, artifact hashes). Expect hits in `tests/upstream_test.sh` (baseline-drift assertions mirror the script constants and expected pin/artifact records — the same sed mapping applies, plus the proposal path in the proposal-drift assertion), `docs/upstream.md` (Active Pins, narrative, references), `artifacts/README.md`, and prior proposal records. `check_omarchy_core_drift` and `check_omarchy_neovim_drift` read `manifests/sources.json`, so they self-update.
- Leave superseded proposal files untouched; they are the decision record.
- Run `tests/upstream_test.sh` while iterating, then `tests/run.sh`; a baseline refresh is cross-cutting under `tests/README.md`.
- Live-validate affected areas separately from sync: per-area `--check`, apply where drift is expected (a changed deployed baseline needs reapply on generic/WSL hosts; native Omarchy areas only attach to native files, so usually just the drift warnings clear). On generic/WSL a changed `lazy-lock.json` makes Neovim `--check` report a stale restore marker until an explicit `nvim-restore` run with connectivity.

## Update log

- 2026-07-28: v3.8.3 → v3.8.4 and omarchy-nvim 2026.6.17-1 → 2026.7.17-1. Core diff was empty for all tracked paths (pin-metadata-only). Overlay changed `remote_clipboard.lua` (OSC-52/tmux rewrite) and `omarchy-theme-hotreload.lua` (reload fix); PKGBUILD appended lines and starter checksum unchanged, so the starter commit pin carried over. Found and fixed a sync bug: `preserve_framework_markers` dropped `packages/upstream/nvim/.stow-local-ignore` because it only preserved markers for package roots absent from the candidate. Also retargeted `check_omarchy_neovim_drift` from the superseded `manifests/proposals/2026-07-20-neovim-stability.json` proposal to the manifest artifact release.
