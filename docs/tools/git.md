# Git

The Git area is the foundation slice: it exercises every foundation mechanism at once — explicit packages, profile detection, deployment state, and the guarded-attachment helper via the `~/.gitconfig` entrypoint.

## Accepted Design

Use Omarchy's complete Git behavior as the untouched baseline, then layer a small shared personal override and external local identity.

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
~/.config/dotfiles/local/git.conf
~/.gitconfig.local
repository .git/config
```

On Omarchy, preserve the native XDG file as the untouched baseline. On Ubuntu, Stow the pinned synchronized XDG baseline.

Keep `~/.gitconfig` as a regular guarded include entrypoint. This allows native
`git config --global` writes without mutating the checkout. Its managed sequence
loads shared personal configuration, whose final optional include loads the
central host-local file, then loads external identity. Repository configuration
retains final precedence.

## Omarchy Baseline Pin

On the `omarchy` profile, apply and check hard-fail during preflight unless the native `~/.config/git/config` matches all sixteen required baseline values exactly. A new Omarchy release that changes its Git configuration therefore blocks deployment until the pin is deliberately reviewed and updated. The contract is a hard refusal, not reconciliation; the separate non-blocking drift warnings layer on top of this same pin.

## Personal And Local Layers

- Put `init.defaultBranch = main` in the shared personal layer.
- Store identity only in `~/.gitconfig.local`.
- Keep `~/.gitconfig.local` untracked, regular, and mode `0600`.
- Allow optional host-specific non-identity settings in
  `~/.config/dotfiles/local/git.conf`.
- Let repository-local configuration retain final precedence.

Credential helpers normally remain host-local settings. Dotfiles does not
migrate or rewrite historical helper paths. On Ubuntu VPS hosts, appending the
managed `github-vps.conf` include to the host-local file activates the exact
GitHub helper reset/router and constrained `gh`; without that include the
capability is dormant. The managed reset deliberately supersedes earlier
generic helpers. Active validation rejects every later generic helper and every
additional URL helper Git would select for a managed repository over HTTP or
HTTPS, including included and repository-local settings.
`rebase.autostash` is not supplied unless a host-local or repository layer sets
it.

Follow [GitHub Access](github-access.md) before activation, GitHub credential
setup, remote writes, protected-branch changes, or PAT rotation.

## Non-Goals

- Committing user identity or credentials.
- Preserving checkout-backed local identity.
- Forcing one shared credential helper across platforms.
- Editing the native Omarchy XDG baseline.
- Hiding the `main` deviation inside a copied baseline.

## Acceptance Criteria

- Omarchy and Ubuntu profiles expose the same required baseline behavior.
- `init.defaultBranch` resolves to `main` from the personal layer.
- Identity resolves from the mode-`0600` external local file.
- Optional host settings resolve from the central local file.
- Repository settings can override all user-level layers.
- Host-local settings load before identity; an activated managed GitHub reset is
  the sole effective helper for exact GitHub HTTP/HTTPS contexts.
- `rebase.autostash` is absent unless another layer supplies it.
- `git config --show-origin --show-scope --get-regexp '.*'` reports expected
  values and provenance.
- Authenticated fetch through a fake host-local helper succeeds with terminal
  prompts disabled.
- Repeated apply does not duplicate includes or mutate tracked files.
