# Neovim

## Accepted Direction

Retire the current Kickstart configuration in one deliberate reset. The new
workflow is:

```text
LazyVim starter
+ LazyVim
+ Omarchy Neovim overlay and released lock state
+ portability adapter where required
+ minimal shared personal configuration
```

Do not automatically migrate Oil, Floaterm, One Monokai, custom keymaps, or any
other current plugins and preferences. The initial personal layer enables only
relative line numbers through normal LazyVim extension points.

## Source Model

There is no standalone Omarchy Neovim repository. The released configuration
is assembled from pinned Git sources, the LazyVim starter tree, overlay files
in `omarchy-pkgs`, and three PKGBUILD-appended option lines, plus a released
`lazy-lock.json` extracted from a package artifact. Exact pins, appended lines,
and the artifact trust boundary are recorded in [Upstream](../upstream.md) and
[Artifacts](../artifacts/README.md).

Two baseline facts worth knowing while evaluating the stock experience: the
Omarchy baseline sets `relativenumber = false` (the personal layer visibly
inverts this) and `autoformat = false`.

`omarchy-nvim 2026.7.15-1` was evaluated during Stage 8 because it replaces the
remote-clipboard module with an OSC-52 and tmux approach. It was available only
on edge, not in authoritative stable metadata, so the latest-stable policy
retains `2026.6.17-1`. The newer clipboard behavior is recorded for a future
stable refresh but is not incorporated from edge (see [Upstream](../upstream.md)).

## Native Omarchy

- Let the installed `omarchy-nvim` package own the baseline.
- Keep native Omarchy theme selection authoritative.
- Store personal source outside the refresh-managed Neovim directory.
- Use a small regular loader to attach the personal layer.
- Reapply that loader after `omarchy-nvim-refresh`.
- Do not copy personal changes into package-owned baseline files.

An explicit Omarchy refresh may replace user configuration and clear Neovim
data, state, and cache. Recovery must recreate only the managed loader and let
the refreshed native baseline initialize normally.

## Generic And WSL

- Deploy the user configuration and `lazy-lock.json` assembled from the
  pinned sources per [Upstream](../upstream.md).
- Do not commit or deploy any plugin cache.
- Use the pinned default Omarchy Tokyo Night theme input.
- Add only portability changes needed outside Omarchy.
- Load the same relative-number personal layer used by native Omarchy.
- Preserve the released lock state during normal bootstrap.
- Adapt the starter bootstrap so `lazy.nvim` is checked out at the commit in
  `lazy-lock.json` before its code executes, rather than running mutable
  `stable` branch HEAD.
- Disable lazy.nvim's periodic update checker so ordinary startup remains
  offline.
- Disable lazy.nvim's automatic missing-plugin installation during ordinary
  startup. Missing plugins install only through the one-time first-launch
  restore or a later explicit restore after a lock change.
- Both restore paths run headless `Lazy restore` and verify applicable plugin
  checkout commits against the committed lockfile.
- Require every active shared plugin spec to have a lockfile entry. Project
  local specs may remain enabled, but missing project plugins are reported and
  never fetched implicitly.

## Reset And Migration

Migration must recognize the current individually Stowed Kickstart links and
remove only links owned by known old paths in this checkout. It must refuse
unrelated regular-file conflicts and avoid carrying old plugin state into the
new configuration accidentally.

Accepted backup policy: git history is the configuration backup. The live
`~/.config/nvim` consists of Stow links into this repository, so the
Kickstart tree needs no copy — removal of the links is sufficient, and any
revert is a checkout of history. Host-local runtime state is preserved by
renaming `~/.local/share/nvim`, `~/.local/state/nvim`, and `~/.cache/nvim` to
timestamped `.bak` siblings rather than deleting them.

Accepted first-start network policy: on a fresh generic host, network access
is permitted on the first explicit `nvim` launch. A small pre-start loader runs
a one-time locked restore before normal editor startup, verifies applicable
plugin commits, and records the restored lockfile blob identity in Neovim area
state only after success. An interrupted restore leaves the marker absent and
retries on the next explicit launch without changing `lazy-lock.json`. Later
plugin network access occurs only through an explicit restore command after a
lock change. Bootstrap itself never fetches Neovim plugins. First start
therefore requires connectivity; that is accepted. This guarantee covers
plugin restoration. Mason packages, Treesitter
parsers, Lua rocks, generated build outputs, and project-local Lazy specs are
outside the plugin lockfile. Before the Neovim stage closes, inventory every
automatic downloader and assign each asset one policy: pinned provisioning,
explicit user-initiated network access, or disabled automatic installation.
Ordinary startup must remain offline after that policy is implemented.

## Open Questions

Resolve these during the
[Omarchy native integration and validation stage](../plan.md#9-omarchy-native-integration-and-validation):

1. What exact file and content load the personal layer on native Omarchy?
2. How does bootstrap detect loader drift and remove the loader safely?
3. What clean-install and post-refresh commands prove the workflow?

These questions are stage gates, not recommendations.

Generic and WSL runtime-asset policy is also a Stage 8 gate: identify Mason,
Treesitter, rocks, build outputs, and project-local behavior before asserting
ordinary startup is offline.

## Non-Goals

- Preserving the old Kickstart configuration outside git history.
- Migrating old plugins, colorschemes, options, or keymaps automatically.
- Committing or deploying any Neovim plugin cache.
- Replacing native Omarchy theme selection.
- Adding personal preferences beyond relative line numbers initially.
- Making generic installation byte-identical to Omarchy.

## Acceptance Criteria

- Native Omarchy uses its installed released baseline without repo-owned
  replacements of refresh-managed files.
- Generic and WSL installs derive from the pinned sources and preserve the
  committed `lazy-lock.json`.
- The first generic launch executes the locked lazy.nvim commit, and explicit
  restore converges every applicable plugin checkout to its locked commit.
- Both environments expose the intended LazyVim and Omarchy workflow.
- Relative line numbers come from a visibly separate shared personal layer.
- The old Kickstart configuration and its customizations are not active, and
  old runtime state survives as timestamped `.bak` directories.
- A native refresh can be followed by safe, idempotent loader reattachment.
- Loader drift or unrelated files cause a refusal rather than speculative
  repair.
- A clean generic startup reaches the committed lock state; plugin network
  access occurs only on the first explicit launch or a later explicit restore.
- Ordinary generic startup performs no periodic plugin update check.
- Ordinary startup does not install missing plugins or other runtime assets
  implicitly; explicit restore and provisioning operations follow the
  canonical network policy.
- Native and generic theme behavior matches the initial stock direction.

## Generic/WSL Lifecycle And Restore

The dedicated Neovim area is ready for generic and WSL in
`manifests/areas.tsv`; native Omarchy remains refused until Stage 9 defines its
refresh-safe attachment. Generic/WSL apply validates the exact
upstream/generic/common package and target closure before mutation.
It retires only exact reviewed individual or folded Kickstart links, including
reviewed broken links whose lexical non-dereferencing normalization and resolved
normalization both match the reviewed source. Only exact reviewed container
ancestors are accepted, and links and containers must be user-owned. Unrelated
or modified topology refuses before mutation; the tracked legacy source tree is
never changed.

The first apply resolves data, state, and cache roots from XDG variables,
requires canonical, non-symlink, user-owned ancestor paths beneath `HOME`, and
records completion even when a root is absent. Existing roots are renamed
without clobber to timestamped `.bak`
siblings. Source fingerprints and backup paths are retained in
`migrations.json`; collisions gain a numeric suffix. A directory-move journal
restores every rename and reviewed legacy link if deployment, state, or ledger
commit fails. Removal retains current runtime roots, backups, preserved plugin
checkouts, credentials, and the migration ledger.

The generic adapter invokes `~/.local/share/dotfiles/bin/nvim-restore
--first-launch` only when `nvim.json` has no `restored_lock_sha256`. A stale
value means the deployed lock changed and startup refuses with guidance to run
`nvim-restore` explicitly. During that explicit restore process only, lazy.nvim
may install missing plugins incrementally from its isolated copy of the
committed lock; lock regeneration is disabled. The helper then runs headless
`Lazy! restore`, verifies every applicable checkout, and verifies both lockfile
copies byte-for-byte before invoking:

```text
${DOTFILES_NVIM_RESTORE_CALLBACK:-~/.local/share/dotfiles/bin/nvim-record-restore} <64-lowercase-hex-lock-sha256>
```

The callback opens `HOME` read-only and acquires the deployment advisory lock,
fully validates `nvim.json`, requires generic/WSL and exact managed lockfile
ownership, compares deployed bytes with the supplied hash, and performs an
atomic compare-and-swap state update. There is no sidecar marker. First deploy
omits the field. Reapply preserves it only when it identifies the current
deployed lock; a changed lock omits the value and requires a successful explicit
restore. `--check` fails with a pending message when the field is absent and a
stale message when it differs from the deployed lock, and cannot claim full
convergence in either case. An interrupted restore leaves the field absent or
stale.
An exact Phase 2 sidecar is retired transactionally on first apply and is not
trusted or imported; malformed or unsafe sidecars cause preflight refusal.

### Failed First Launch Recovery

1. Leave `migrations.json` and every timestamped runtime backup in place. Do
   not rename a backup over the new runtime root; the ledger intentionally
   prevents repeating the destructive migration.
2. Inspect the reported checkout error. Repair only the named current checkout
   under the active XDG data root. Clean divergent checkouts preserved by the
   helper remain under the active XDG state root's
   `dotfiles/nvim-preserved/` directory.
3. Run `~/.local/share/dotfiles/bin/nvim-restore` explicitly with connectivity.
   It verifies all applicable checkouts and unchanged lock bytes before the
   state marker can be committed.
4. Run `./bootstrap.sh --check --area nvim`, then launch Neovim normally. Never
   delete `migrations.json` to force another
   runtime rename.

The downloader policy in the generic Lua layer is explicit: lazy periodic
checks, ordinary-startup installation, and Lua rocks are disabled; Mason registry and
package work is limited to explicit `:Mason` actions; Treesitter's automatic
ensure list is empty and parser work is limited to explicit `:TSInstall` or
`:TSUpdate`; project-local specs remain discoverable but missing checkouts are
reported rather than installed. The inherited Mason and Treesitter build hooks
are disabled, and Blink uses its Lua matcher with prebuilt-binary download
disabled. Any remaining plugin build hook can run only as part of the first or
later explicit restore operation.
