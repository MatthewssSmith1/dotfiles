# Git

The Git area is the foundation slice: it is deployed end-to-end first because
it exercises every foundation mechanism at once — explicit packages, profile
detection, deployment state, and the guarded-attachment helper via the
`~/.gitconfig` entrypoint. See
[the implementation plan](../plan.md#2-minimal-source-foundation-and-git-end-to-end).

## Accepted Design

Use Omarchy's complete Git behavior as the untouched baseline, then layer a
small shared personal override and external local identity.

The baseline includes:

- `co`, `br`, `ci`, and `st` aliases.
- Rebase on pull.
- Automatic upstream setup on push.
- Histogram diffs and moved-line highlighting.
- Mnemonic diff prefixes.
- Verbose commit templates.
- Automatic column output.
- Recent-first branch ordering.
- Version-aware tag ordering.
- Enabled `rerere` with automatic reuse.
- Upstream's `master` default branch before personal override.

## Load Order

Expected effective order:

```text
/etc/gitconfig
~/.config/git/config
~/.gitconfig
~/.config/dotfiles/personal/git.conf
~/.gitconfig.local
~/.config/dotfiles/local/git.conf
repository .git/config
```

On Omarchy, preserve the native XDG file as the untouched baseline. On generic
systems, Stow the pinned synchronized XDG baseline.

Keep `~/.gitconfig` as a regular guarded include entrypoint. This allows native
`git config --global` writes without mutating the checkout. Its managed include
sequence loads the shared personal file, external identity file, and optional
central host-local file in the order shown above.

## Personal And Local Layers

- Put `init.defaultBranch = main` in the shared personal layer.
- Store identity only in `~/.gitconfig.local`.
- Keep `~/.gitconfig.local` untracked, regular, and mode `0600`.
- Allow optional host-specific non-identity settings in
  `~/.config/dotfiles/local/git.conf`.
- Let repository-local configuration retain final precedence.

Migration must preserve effective credential helpers as host-local settings in
`~/.config/dotfiles/local/git.conf`. The current hard-coded helper paths should
not enter a shared layer, but they must not disappear silently: migration
reports each effective helper and preserves it until the user explicitly
replaces or removes it. `rebase.autostash` is not retained unless another
host-local or repository layer supplies it.

## Migration

1. Inspect the current global and XDG configurations with origin information.
2. Inspect `~/.gitconfig.local` with `lstat` semantics. Accept a symlink only
   when its lexical and resolved targets match the known legacy checkout path.
3. Copy its complete identity configuration into a temporary external
   mode-`0600` regular file; never write or run `chmod` through the symlink.
4. Preserve effective credential helpers and unrelated host values in the
   central local file.
5. Replace only known legacy links or managed include blocks.
6. Install or preserve the profile baseline.
7. Install the guarded regular global entrypoint.
8. Atomically rename the external identity file over the validated legacy
   symlink. The rename itself replaces the symlink; do not unlink afterward.
9. Validate every required value and source.

Migration must stop rather than overwrite an unrelated regular file or
malformed managed block.

## Non-Goals

- Committing user identity or credentials.
- Preserving checkout-backed local identity.
- Forcing one shared credential helper across platforms.
- Editing the native Omarchy XDG baseline.
- Hiding the `main` deviation inside a copied baseline.

## Acceptance Criteria

- Omarchy and generic profiles expose the same required baseline behavior.
- `init.defaultBranch` resolves to `main` from the personal layer.
- Identity resolves from the mode-`0600` external local file.
- Optional host settings resolve from the central local file.
- Repository settings can override all user-level layers.
- Existing effective credential helpers remain available from the host-local
  layer unless explicitly removed; `rebase.autostash` is absent unless another
  layer supplies it.
- `git config --show-origin --show-scope --get-regexp '.*'` reports expected
  values and provenance.
- Authenticated fetch through a fake host-local helper succeeds with terminal
  prompts disabled, proving migration does not remove helper behavior.
- Repeated bootstrap does not duplicate includes or mutate tracked files.
