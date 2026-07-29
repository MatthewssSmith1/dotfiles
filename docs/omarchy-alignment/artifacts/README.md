# Preserved Artifacts

## omarchy-nvim 2026.7.17-1 lazy-lock.json

The `lazy-lock.json` shipped inside the built package `omarchy-nvim 2026.7.17-1`, extracted from `/usr/share/omarchy-nvim/config/lazy-lock.json` in the artifact.

This file cannot be re-derived from any git source. The package build runs `nvim --headless "+Lazy! sync"`, which resolves every plugin to its branch HEAD at build time and generates the lockfile inside the artifact only.

Provenance:

- Artifact: `omarchy-nvim-2026.7.17-1-any.pkg.tar.zst` from the Omarchy
  stable package channel.
- Artifact SHA-256:
  `97d54bd8a44e8f16672c100688e2e418a0efc0aa1e073eb54a7cc14efd93d519`.
- Extracted `lazy-lock.json` SHA-256:
  `1a4bb48e02a0b26c87413e3f3c732d833dd8b41ddebe942c825d590222c3f601`.
- Build date recorded in the artifact: 2026-07-20T03:57:48Z, five minutes
  after omarchy-pkgs commit `2eb15bc7265c5293985f7e5f483e39df7be9c548` set
  `pkgver=2026.7.17`.
- Retrieved and extracted from stable on 2026-07-29.
- Detached signature SHA-256:
  `25aa5948f3377752876936debb8a6d2c1bd44a7b393ebe446b78a70be21e1ce7`.
- Valid signature by Omarchy key fingerprint
  `40DFB630FF42BCFFB047046CF0134EE680CAC571` at 2026-07-20T04:02:26Z.
- Stable repository database SHA-256:
  `6a957256fc29395488276516c4fa977f34bd5746cb927bf9214ef613eb5d5e5a`.
- The stable database package record, package metadata, build identity,
  signature, public key, retrieval metadata, and extracted member hashes are
  retained in
  [`omarchy-nvim-2026.7.17-1/`](omarchy-nvim-2026.7.17-1/).

The evidence set for the previously accepted `2026.6.17-1` release lives in git history; only the active release's evidence directory is retained.

## Trust Boundary

The signature was verified using the key committed in the selected `omarchy-pkgs` revision (byte-identical to the key used for `2026.6.17-1`), the package hash matched current stable repository metadata, and the complete packaged configuration was verified against the assembled snapshot: only the two Stage 8 policy-transformed files, the two overlay files changed between the pinned commits, and the rebuilt lockfile differed from the previous baseline.

The 177,781,788-byte package is not committed because it is disproportionate to this small source repository and there is no existing large-artifact or LFS convention. The detached signature and key, exact package and database hashes, package metadata, PKGBUILD identity, and per-member hashes are retained. Future offline verification can check snapshot drift and authenticate any copy of the exact archive, but without the archive cannot independently replay package membership. The accepted member-hash record therefore remains the final trust-on-verification boundary.

For every future package revision, retain this evidence set immediately. Use durable external artifact storage when available if committing the complete package would remain disproportionate.

The lockfile contains 51 pinned plugins, 16 at newer commits than the `2026.6.17-1` release. Its canonical committed location is [`packages/upstream/nvim/.config/nvim/lazy-lock.json`](../../../packages/upstream/nvim/.config/nvim/lazy-lock.json). Its fixed SHA-256 and provenance are carried in [`manifests/sources.json`](../../../manifests/sources.json). Sync copies only this hash-verified artifact into candidates; offline verify checks it without network access. See [Upstream](../upstream.md) for the full source model.
