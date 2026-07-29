# omarchy-nvim 2026.7.17-1 Evidence

This directory preserves compact evidence captured from the authoritative Omarchy stable repository on 2026-07-29 UTC. The stable channel had advanced from `2026.6.17-1` to `2026.7.17-1`; newer pkgvers (`2026.7.23`, `2026.7.27`) existed in `omarchy-pkgs` git history but were absent from stable metadata and were not selected.

## Verification

The following stable endpoints returned HTTP 200:

- `https://pkgs.omarchy.org/stable/x86_64/omarchy.db`
- `https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.7.17-1-any.pkg.tar.zst`
- `https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.7.17-1-any.pkg.tar.zst.sig`

The repository record is preserved as `repository.desc`; normalized response metadata is in `retrieval.txt`. `SHA256SUMS` records the downloaded database, package, and detached signature hashes. The 119-byte signature is preserved losslessly as base64 in `package.sig.b64`, and the exact public key from `omarchy-pkgs` commit `2eb15bc7265c5293985f7e5f483e39df7be9c548` (`pkgbuilds/omarchy-keyring/omarchy.gpg`, byte-identical to the key preserved for `2026.6.17-1`) is preserved in `omarchy-signing-key.asc`.

GnuPG reported a valid Ed25519 signature made at `2026-07-20T04:02:26Z` by fingerprint `40DFB630FF42BCFFB047046CF0134EE680CAC571`, identity `Omarchy <pkgs@omarchy.org>`. The key was authenticated by its membership in the selected `omarchy-pkgs` commit; no external Web-of-Trust certification was claimed. The package SHA-256 matched `%SHA256SUM%` in the stable database.

The archive's `.PKGINFO` and `.BUILDINFO` are preserved verbatim. The latter's PKGBUILD SHA-256 (`290ef38620d729cd2a72c0f20f77daf8271d8a489b1ef0336a1fb3878605b83b`) matches the PKGBUILD at the selected overlay commit. The package build date `1784519868` (`2026-07-20T03:57:48Z`) follows that commit by five minutes. `config.sha256` records every regular member of `usr/share/omarchy-nvim/config`. Extracting that complete directory and running `diff -qr` against the pre-sync committed snapshot differed only in the five expected members: the two policy-transformed files (`init.lua`, `lua/config/lazy.lua`), the two overlay files changed between the pinned commits (`lua/config/remote_clipboard.lua`, `lua/plugins/omarchy-theme-hotreload.lua`), and the rebuilt `lazy-lock.json`. The packaged and committed `lazy-lock.json` both hash to `1a4bb48e02a0b26c87413e3f3c732d833dd8b41ddebe942c825d590222c3f601` (51 plugins, 16 at newer commits than the previous release).

## Retention Boundary

The package archive is 177,781,788 bytes and expands to 242,839,808 bytes. It is not committed: this repository has no large-artifact convention or LFS, contains no archive payloads, and committing this package would be disproportionate. The stable database archive is also omitted because its package record is retained as text and its exact download hash is recorded.

Offline verification can prove that the committed snapshot still matches the accepted per-member extraction record, reconstruct the exact detached signature and key, and verify any future copy of the archive with the recorded package hash. Without the 177 MB archive, it still cannot independently prove that the accepted member-hash record was inside the signed package. That final package-membership link remains a documented trust-on-verification boundary.
