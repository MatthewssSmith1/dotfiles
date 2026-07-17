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

## Initial Pins

| Source | Pin | Status |
|--------|-----|--------|
| Omarchy release | `v3.8.3` | Accepted |
| Omarchy commit | `6aa2aec1c035d50cfb6871d490cdf9a1169f5ac3` | Accepted |
| LazyVim starter | `803bc181d7c0d6d5eeba9274d9be49b287294d99` | Accepted |
| Omarchy Neovim overlay | `omarchy-pkgs` commit `78e5cc81953c44c804eb00e5be093e2674e09503`, path `pkgbuilds/omarchy-nvim/` | Accepted |
| Neovim release identity | `omarchy-nvim 2026.6.17-1` | Accepted |

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
[`artifacts/omarchy-nvim-2026.6.17-1-lazy-lock.json`](artifacts/omarchy-nvim-2026.6.17-1-lazy-lock.json)
with artifact and extracted-file hashes recorded for provenance. The original
package and signature were not retained, and the stable channel deletes
superseded artifacts. Package membership therefore cannot now be independently
reverified; this lockfile is an explicitly accepted extracted snapshot.

An update to `omarchy-nvim 2026.7.15` (which replaces the remote-clipboard
module with an OSC-52 and tmux approach, a better fit for SSH, VPS, and tmux
workflows) is expected. Evaluate it when it reaches the stable channel, before
the Neovim stage runs, extracting its lockfile the same way. See
[Neovim](tools/neovim.md).

## Manifest

The machine-readable source manifest records one entry for every synchronized
input or generated output:

- Schema version.
- Upstream repository URL and immutable commit.
- Human-readable release identity where applicable.
- Source path, Git blob ID, and file mode.
- Destination path and mode.
- Deterministic transformation or assembly rule, including input order,
  overwrite behavior, and exact appended bytes.
- Output Git blob ID for transformed files.
- The committed `lazy-lock.json` snapshot path, hash, and provenance record.

The manifest becomes canonical for exact pins after it exists. Until then,
this document is canonical.

Source blob IDs are practical verification records, not a claim that the
manifest alone proves a blob's path through an unavailable upstream tree. The
networked sync operation verifies that relationship before proposing a
manifest change; review and this repository's history preserve the accepted
mapping afterward.

## Snapshot Scope

Commit readable snapshots of:

- The full Omarchy `default/bash/` tree for reference and selected use.
- Omarchy Git configuration.
- Omarchy tmux configuration.
- Omarchy Starship configuration.
- The default Tokyo Night Neovim theme input
  (`themes/tokyo-night/neovim.lua` in the Omarchy tree).
- The assembled Omarchy Neovim user configuration: starter tree, overlay
  files, and appended option lines, per the source model above.
- The released `lazy-lock.json` (already committed under
  [artifacts](artifacts/README.md); it relocates into the snapshot tree when
  the sync stage is built).

Do not commit the complete Omarchy repository or any Neovim plugin cache.

## Synchronization Interface

The intended interface has separate verification and update modes:

```text
scripts/upstream verify
scripts/upstream sync --proposal /path/to/reviewed-source-proposal.json
```

The proposal records every requested human-readable version, immutable commit,
repository, and package identity. Sync refuses version-only inputs and writes a
candidate active manifest from the reviewed proposal plus verified source blob
data.

`verify` is fully offline. It computes Git blob identities from the committed
active baseline, replays deterministic transforms where applicable, verifies
inventory, modes, and artifact hashes, and prints the recorded pins. It proves
that the working snapshot matches the accepted manifest, not that absent
upstream Git history is authentic.

`sync` is the only baseline operation allowed to use the network. Existing pins
are addressed by recorded version and commit. A proposed update must supply an
explicit version-to-commit mapping rather than asking sync to trust a mutable
version name. Sync fetches those commits into temporary storage, verifies each
selected path and blob against Git, assembles a candidate snapshot and
manifest, and runs offline verification against the candidate before replacing
the active snapshot.

Synchronization must never:

- Deploy configuration.
- Invoke Stow.
- Update runtime plugins.
- Touch files under `$HOME` outside the resolved checkout and its
  same-filesystem staging directory.
- Run during bootstrap or shell startup.

This is consistent with the canonical operation matrix in
[Deployment](deployment.md#operation-and-network-policy): bootstrap apply may
fetch locked runtime tools and tmux plugins, but it never fetches Neovim
plugins or synchronizes baselines.

Selected upstream files are committed directly so ordinary Git diffs show
baseline changes during review.

## Update Procedure

1. Select explicit stable core and Neovim versions.
2. Resolve and review each version-to-commit mapping before invoking sync.
3. For a Neovim package update, download the exact package and signature while
   available; preserve package metadata and the extraction procedure.
4. Fetch pinned commits and package inputs into same-filesystem staging beside
   the checkout content that will be replaced.
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
- Offline verification succeeds without network access and proves the snapshot
  matches the accepted manifest.
- Sync rejects source paths or blobs that do not belong to the supplied
  immutable commits.
- A failed sync leaves the active snapshot unchanged.
- Snapshot changes produce readable Git diffs.
- Bootstrap and startup cannot trigger synchronization.
- The committed `lazy-lock.json` snapshot and its provenance record are
  preserved through sync operations.
