# Upstream Sources

## Source Of Truth

The source of truth is a set of pinned git commits in the relevant upstream
repositories, not mutable configuration installed on one machine. Omarchy core
and the Omarchy Neovim configuration have independent release lifecycles and
require separate recorded revisions.

Git-backed inputs use immutable commits and source blob identities. During
networked synchronization, Git proves that each selected path and blob belongs
to the requested commit. The committed manifest then lets offline verification
prove that the accepted snapshot still matches those recorded identities and
documented transforms. Offline verification does not independently reconstruct
or authenticate upstream history when the upstream Git objects are absent.

The one input that cannot be derived from Git, the released Neovim
`lazy-lock.json`, is preserved as a committed snapshot with its trust boundary
and provenance recorded in [Artifacts](artifacts/README.md).

Use one active tracked baseline. Git history provides rollback; do not retain a
directory for every old release.

## Active Pins

| Source | Repository | Version | Commit |
|--------|------------|---------|--------|
| Omarchy | `https://github.com/basecamp/omarchy` | `v3.8.3` | `6aa2aec1c035d50cfb6871d490cdf9a1169f5ac3` |
| LazyVim starter | `https://github.com/LazyVim/starter` | `803bc181d7c0d6d5eeba9274d9be49b287294d99` | `803bc181d7c0d6d5eeba9274d9be49b287294d99` |
| Omarchy Neovim overlay | `https://github.com/omacom-io/omarchy-pkgs` | `2026.6.17-1` | `78e5cc81953c44c804eb00e5be093e2674e09503` |

The Stage 8 stable-channel reevaluation is recorded in
[`manifests/proposals/2026-07-20-stage8-neovim-stable.json`](../../manifests/proposals/2026-07-20-stage8-neovim-stable.json).
Both Neovim inputs record package identity `omarchy-nvim 2026.6.17-1`.

There is no standalone Omarchy Neovim repository. The released configuration
is assembled from three inputs:

1. The LazyVim starter tree at the pinned commit. The release's PKGBUILD pins
   this input by tarball checksum; the pinned commit above was verified equal
   to that checksum.
2. The overlay files tracked in `omarchy-pkgs` under `pkgbuilds/omarchy-nvim/`
   at the pinned commit (`lua/`, `plugin/`, `lazyvim.json`).
3. Three lines the PKGBUILD appends to `lua/config/options.lua`, recorded here
   because they exist only in the PKGBUILD:

   ```lua
   require('config.remote_clipboard').setup()
   vim.opt.relativenumber = false
   vim.g.autoformat = false
   ```

The `omarchy-pkgs` commit above is the commit associated with
`2026.6.17-1`; the artifact's recorded build date follows it by four minutes.
The built package generated `lazy-lock.json` at build time; the extracted copy
is committed at
[`packages/upstream/nvim/.config/nvim/lazy-lock.json`](../../packages/upstream/nvim/.config/nvim/lazy-lock.json)
with fixed artifact and extracted-file hashes recorded in
[Artifacts](artifacts/README.md). On 2026-07-20 the package and detached
signature were still available from stable. The signature, repository checksum,
PKGBUILD identity, package metadata, and complete packaged configuration were
verified; the packaged configuration was byte-identical to the committed
snapshot.

`omarchy-nvim 2026.7.15-1`, including its newer OSC-52/tmux clipboard module,
was explicitly evaluated. It existed on the edge endpoint but was absent from
authoritative stable metadata, and its stable archive URL returned HTTP 404.
The approved latest-stable policy therefore retains `2026.6.17-1`; edge content
must not be assembled into this baseline.

## Manifest

The active [`manifests/sources.json`](../../manifests/sources.json) records one
entry per snapshot file, rather than one entry per source tree. Source-manifest
schema v1 remains compatible with the Stage 2 records and adds optional
reference destinations, append and overwrite transforms, and artifact records.
Each entry records:

- Schema version.
- Upstream repository URL and immutable commit.
- Human-readable release identity where applicable.
- Source path, Git blob ID, and file mode.
- Destination path and mode.
- Deterministic append or overwrite assembly metadata, including replaced input
  identity or exact appended bytes.
- Output Git blob ID for transformed files.
- The committed `lazy-lock.json` snapshot path, hash, and provenance record.

The manifest is canonical for exact pins and file inventory.

Source blob IDs are practical verification records, not a claim that the
manifest alone proves a blob's path through an unavailable upstream tree. The
networked sync operation verifies that relationship before proposing a
manifest change; review and this repository's history preserve the accepted
mapping afterward.

## Snapshot Scope

The single active snapshot root is `packages/upstream`. It contains:

- `git/.config/git/config` and `starship/.config/starship.toml`, mapped to their
  XDG home destinations.
- `tmux/.config/dotfiles/upstream/tmux/tmux.conf`, the byte-identical Omarchy
  tmux input mapped to private managed
  `~/.config/dotfiles/upstream/tmux/tmux.conf`. The separate generic package
  owns the public `~/.config/tmux/tmux.conf` dispatcher, so the upstream
  snapshot is never modified to become a loader.
- `nvim/.config/nvim/`, the assembled Neovim configuration and released
  `lazy-lock.json`.
- `reference/omarchy/default/bash/` and
  `reference/omarchy/themes/tokyo-night/neovim.lua`, which are verified
  reference inputs and are not home payloads.

Do not commit the complete Omarchy repository or any Neovim plugin cache.

## Synchronization Interface

The implemented interface has separate verification and update modes:

```text
scripts/upstream verify
scripts/upstream sync --proposal manifests/proposals/2026-07-20-stage8-neovim-stable.json
```

The proposal records every requested human-readable version, immutable commit,
repository, and package identity. Sync refuses version-only inputs and writes a
candidate active manifest from the reviewed proposal plus verified source blob
data.

`verify` is fully offline and invokes no network-capable operation. It computes
Git blob identities directly from committed files, replays append transforms,
and verifies complete inventory, modes, destinations, artifact hashes, and
recorded pins. Overwrite records verify the accepted output blob and preserve
the replaced source identity for review; offline verification does not fetch or
authenticate absent upstream history.

`sync` is the only baseline operation allowed to use the network. It accepts
only the three exact HTTPS repositories above and fetches proposal commits by
immutable 40-character ID with tags disabled, prompts disabled, object checking
enabled, and HTTPS as the only production Git protocol. It creates
`.upstream-staging.*` beside the active snapshot, verifies each selected Git
path, blob, and mode, assembles a candidate snapshot and manifest, preserves the
fixed-hash lockfile artifact, and runs offline candidate verification before
replacement. Failures before or during candidate verification remove staging
and leave the active baseline unchanged. If replacement is interrupted, cleanup
restores the old snapshot and manifest together; failed restoration preserves
staging and reports its path for manual recovery.

The current real baseline has exactly one append transform, for
`lua/config/options.lua`, and no overwrite transforms. The pinned LazyVim
starter has no `lazyvim.json`, so the overlay adds that file without a
collision. Sync supports overwrite records for future real collisions.

Synchronization must never:

- Deploy configuration.
- Invoke Stow.
- Update runtime plugins.
- Touch files under `$HOME` outside the resolved checkout and its
  same-filesystem staging directory.
- Run during bootstrap or shell startup.

This is consistent with the canonical operation matrix in
[Deployment](deployment.md#operation-and-network-policy): ordinary bootstrap
apply is offline and configuration-only. Explicit provisioning apply may fetch
only its printed, locked runtime-tool plan and never synchronizes baselines.

Selected upstream files are committed directly so ordinary Git diffs show
baseline changes during review.

## Update Procedure

1. Select explicit stable core and Neovim versions.
2. Resolve and review each version-to-commit mapping before invoking sync.
3. For a Neovim package update, download the exact package and signature while
   available; preserve package metadata and the extraction procedure.
4. Fetch immutable commits over HTTPS into same-filesystem staging beside the
   checkout content that will be replaced.
5. Verify Git path/blob relationships and package evidence.
6. Assemble only the documented inventory with deterministic transforms.
7. Generate the candidate manifest, including source and output blob IDs.
8. Run offline verification against the candidate.
9. Atomically replace the single active snapshot.
10. Review ordinary Git diffs before accepting the update.
11. Test affected profiles and areas separately from synchronization.

## References

- [Omarchy repository](https://github.com/basecamp/omarchy)
- [Omarchy v3.8.3](https://github.com/basecamp/omarchy/tree/v3.8.3)
- [Omarchy tmux configuration](https://github.com/basecamp/omarchy/blob/v3.8.3/config/tmux/tmux.conf)
- [Omarchy Git configuration](https://github.com/basecamp/omarchy/blob/v3.8.3/config/git/config)
- [Omarchy Bash defaults](https://github.com/basecamp/omarchy/tree/v3.8.3/default/bash)
- [Tokyo Night Neovim theme input](https://github.com/basecamp/omarchy/blob/v3.8.3/themes/tokyo-night/neovim.lua)
- [LazyVim starter](https://github.com/LazyVim/starter)
- [Omarchy Neovim PKGBUILD and overlay](https://github.com/omacom-io/omarchy-pkgs/tree/master/pkgbuilds/omarchy-nvim)
- [LazyVim configuration](https://www.lazyvim.org/configuration)
- [Omarchy manual: Dotfiles](https://learn.omacom.io/2/the-omarchy-manual/65/dotfiles)

## Acceptance Criteria

- Every active snapshot file is listed with source path, commit, blob identity,
  destination, mode, and any transform.
- The tmux snapshot retains source blob
  `470040a3bcc3f22e7b4c3ff32ff641198b487f8e` byte-for-byte at its private
  managed path.
- Offline verification succeeds without network access and proves the snapshot
  matches the accepted manifest.
- Sync rejects source paths or blobs that do not belong to the supplied
  immutable commits.
- A failed sync leaves the active snapshot unchanged.
- Snapshot changes produce readable Git diffs.
- Bootstrap and startup cannot trigger synchronization.
- The committed `lazy-lock.json` snapshot and its provenance record are
  preserved through sync operations.
