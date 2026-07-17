# Preserved Artifacts

## omarchy-nvim-2026.6.17-1-lazy-lock.json

The `lazy-lock.json` shipped inside the built package
`omarchy-nvim 2026.6.17-1`, extracted from
`/usr/share/omarchy-nvim/config/lazy-lock.json` in the artifact.

This file cannot be re-derived from any git source. The package build runs
`nvim --headless "+Lazy! sync"`, which resolves every plugin to its branch
HEAD at build time and generates the lockfile inside the artifact only.

Provenance:

- Artifact: `omarchy-nvim-2026.6.17-1-any.pkg.tar.zst` from the Omarchy
  stable package channel.
- Artifact SHA-256:
  `b4a6704df33709e4265cab31d2b8e725fa0dc49cd0872ce22b208a13b0f4e67a`.
- Extracted `lazy-lock.json` SHA-256:
  `0bf36c5e91f71bc3659391761b3856ab7dfcaeda8aca6a3de954d9a06e7e28de`.
- Build date recorded in the artifact: 2026-06-20T19:46:26Z, four minutes
  after omarchy-pkgs commit `78e5cc81953c44c804eb00e5be093e2674e09503` set
  `pkgver=2026.6.17`.
- Extracted 2026-07-16. The stable channel removes old artifact versions
  when new ones promote, so the original download URL is expected to stop
  resolving.

## Trust Boundary

The package archive, detached signature, `.PKGINFO`, and `.BUILDINFO` were not
retained. The recorded archive hash and timing corroborate the extraction but
cannot now prove offline that this JSON was a member of the vanished package.
The committed file is therefore an accepted trust-on-extraction snapshot; Git
history and the extracted-file hash detect later drift.

For every future package revision, preserve the exact package and signature in
durable storage before promotion removes it. Record the download URL, retrieval
time, signature status and signer, package metadata, extraction command and
tool version, archive hash, and extracted lockfile hash. Only then describe
package membership as independently verifiable.

The lockfile contains 51 pinned plugins. It relocates into the upstream
snapshot tree when the synchronization stage of the
[implementation plan](../plan.md) is built; until then this directory is its
canonical location. See [Upstream](../upstream.md) for the full source model.
