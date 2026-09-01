# omarchy-nvim 2026.8.13-1 Evidence

This directory preserves compact evidence captured from the authoritative Omarchy stable repository on 2026-08-26 UTC. The package stream was selected independently from Omarchy core.

## Verification

The stable database, `omarchy-nvim-2026.8.13-1-any.pkg.tar.zst`, and its detached signature returned HTTP 200. `repository.desc` is the stable database record; `retrieval.txt` records normalized response metadata; `SHA256SUMS` records the downloaded bytes.

The package SHA-256 matched stable `%SHA256SUM%`. GnuPG verified the detached Ed25519 signature made at `2026-08-13T12:58:49Z` by fingerprint `40DFB630FF42BCFFB047046CF0134EE680CAC571`, identity `Omarchy <pkgs@omarchy.org>`. The public key is unchanged from the key blob at `pkgbuilds/omarchy-keyring/omarchy.gpg` in selected `omarchy-pkgs` commit `f20649b0a41ccc700e41d8a1d402b337a0f75cd4`; no external Web-of-Trust claim is made.

The preserved `.BUILDINFO` PKGBUILD SHA-256, `c91107a63b402fd58c1a614fe67e2d9c8f9fe5da2638233b3eccbbd126c4b106`, matches that commit. The package build date is `2026-08-13T12:50:48Z`, 19 minutes after the package commit. The PKGBUILD starter checksum `d865d50211358358d3c3c1e356773c1e3de1e8964215d85eb1b4c77521e17488` matches the archive for immutable LazyVim starter commit `803bc181d7c0d6d5eeba9274d9be49b287294d99`.

`config.sha256` records every regular member below `usr/share/omarchy-nvim/config`. The packaged and committed `lazy-lock.json` hash to `f8693f2607088055adef508221e288b378a8df97411e0d726cbdb672d963a8ca` and contain 51 plugin pins.

## Retention Boundary

The 36,517,625-byte package archive is not committed. The detached signature, signing key, stable record, package/build metadata, response metadata, and all configuration member hashes are retained. Offline verification proves snapshot and evidence drift and can authenticate a future copy of the exact archive; without the archive, package membership remains the documented trust-on-verification boundary.
