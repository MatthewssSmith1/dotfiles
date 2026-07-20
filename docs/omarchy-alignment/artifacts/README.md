# Preserved Artifacts

## omarchy-nvim 2026.6.17-1 lazy-lock.json

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
- Initially extracted 2026-07-16 and independently retrieved again from stable
  on 2026-07-20.
- Detached signature SHA-256:
  `a88bda5a1dadab3617655a122cc697d50a5601cd5f010e5f33bf0420c8ef43d0`.
- Valid signature by Omarchy key fingerprint
  `40DFB630FF42BCFFB047046CF0134EE680CAC571` at 2026-06-20T19:52:41Z.
- Stable repository database SHA-256:
  `3ea5428b2ec4109cbd634026c3f88d1103a135e93bcffa658a99e21aedff5289`.
- The stable database package record, package metadata, build identity,
  signature, public key, retrieval metadata, and extracted member hashes are
  retained in
  [`omarchy-nvim-2026.6.17-1/`](omarchy-nvim-2026.6.17-1/).

## Trust Boundary

The package remained available during the Stage 8 reevaluation. Its signature
was verified using the key committed in the selected `omarchy-pkgs` revision,
its hash matched current stable repository metadata, and its complete packaged
configuration was byte-identical to the committed snapshot. This closes the
former uncertainty about the original extraction.

The 177,497,908-byte package is not committed because it is disproportionate
to this small source repository and there is no existing large-artifact or LFS
convention. The detached signature and key, exact package and database hashes,
package metadata, PKGBUILD identity, and per-member hashes are retained. Future
offline verification can check snapshot drift and authenticate any copy of the
exact archive, but without the archive cannot independently replay package
membership. The accepted member-hash record therefore remains the final
trust-on-verification boundary.

For every future package revision, retain this evidence set immediately. Use
durable external artifact storage when available if committing the complete
package would remain disproportionate.

The lockfile contains 51 pinned plugins. Stage 4 relocated it without changing
its bytes, and Stage 8 confirmed those bytes against the signed stable package.
Its canonical committed location is
[`packages/upstream/nvim/.config/nvim/lazy-lock.json`](../../../packages/upstream/nvim/.config/nvim/lazy-lock.json).
Its fixed SHA-256 and provenance are carried in
[`manifests/sources.json`](../../../manifests/sources.json). Sync copies only
this hash-verified artifact into candidates; offline verify checks it without
network access. See [Upstream](../upstream.md) for the full source model.
