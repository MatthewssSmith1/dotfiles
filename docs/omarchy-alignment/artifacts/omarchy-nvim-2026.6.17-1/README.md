# omarchy-nvim 2026.6.17-1 Evidence

This directory preserves compact evidence captured from the authoritative
Omarchy stable repository on 2026-07-20 UTC. The selected package remained
`omarchy-nvim 2026.6.17-1`; `2026.7.15-1` was available on edge but absent
from stable metadata and returned HTTP 404 at the stable package URL.

## Verification

The following stable endpoints returned HTTP 200:

- `https://pkgs.omarchy.org/stable/x86_64/omarchy.db`
- `https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.6.17-1-any.pkg.tar.zst`
- `https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.6.17-1-any.pkg.tar.zst.sig`

The repository record is preserved as `repository.desc`; normalized response
metadata is in `retrieval.txt`. `SHA256SUMS` records the downloaded database,
package, and detached signature hashes. The 119-byte signature is preserved
losslessly as base64 in `package.sig.b64`, and the exact public key from
`omarchy-pkgs` commit `78e5cc81953c44c804eb00e5be093e2674e09503`
is preserved in `omarchy-signing-key.asc`.

GnuPG reported a valid Ed25519 signature made at `2026-06-20T19:52:41Z` by
fingerprint `40DFB630FF42BCFFB047046CF0134EE680CAC571`, identity
`Omarchy <pkgs@omarchy.org>`. The key was authenticated by its membership in
the selected `omarchy-pkgs` commit; no external Web-of-Trust certification was
claimed. The package SHA-256 matched `%SHA256SUM%` in the stable database.

The archive's `.PKGINFO` and `.BUILDINFO` are preserved verbatim. The latter's
PKGBUILD SHA-256 matches the PKGBUILD at
the selected overlay commit. `config.sha256` records every regular member of
`usr/share/omarchy-nvim/config`. Extracting that complete directory and running
`diff -qr` against `packages/upstream/nvim/.config/nvim` produced no output.
The packaged and committed `lazy-lock.json` both hash to
`0bf36c5e91f71bc3659391761b3856ab7dfcaeda8aca6a3de954d9a06e7e28de`.

## Retention Boundary

The package archive is 177,497,908 bytes and expands to 242,319,393 bytes.
It is not committed: this repository has no large-artifact convention or LFS,
contains no archive payloads, and its packed object store was about 52 KiB at
reevaluation time. Committing this package would be disproportionate. The
stable database archive is also omitted because its package record is retained
as text and its exact download hash is recorded.

Offline verification can now prove that the committed snapshot still matches
the accepted per-member extraction record, reconstruct the exact detached
signature and key, and verify any future copy of the archive with the recorded
package hash. Without the 177 MB archive, it still cannot independently prove
that the accepted member-hash record was inside the signed package. That final
package-membership link remains a documented trust-on-verification boundary.
