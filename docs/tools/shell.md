# Bash

Bash is the only repository-managed shell. Dotfiles never changes the login
shell and never installs or updates a tool during apply, check, removal, or
startup.

## Ownership

Native Omarchy keeps its regular package-owned `~/.bashrc`, Bash defaults,
Starship configuration, and refresh lifecycle. The Bash area deploys only the
common personal payload and appends one exact guarded source block. A complete
Omarchy refresh may replace that block; reapply records the refreshed baseline
and restores the attachment without replacing the host file.

Ubuntu deploys the reviewed portable upstream Bash subset, Starship config, an
Ubuntu adapter, the common personal layer, and `dotfiles-secret`. It appends the
same concise source block to the host-owned `~/.bashrc`; no login file is
created or modified. Removal deletes only the exact managed block and links.
When Bash is the account login shell, one of `~/.profile`, `~/.bash_profile`, or
`~/.bash_login` must already exist. If none exists, preflight stops with manual
guidance; restore a host-owned `~/.profile` that sources `~/.bashrc`.

The full Omarchy v4 Bash tree is retained as an exact immutable reference. The
Ubuntu subset uses a replayable transform for aliases and tmux helpers: it omits
the Omarchy-only agent alias, excludes the desktop-only square layout, and
repairs the upstream undefined pane focus target. Shell and Readline inputs are
byte-exact.

Ubuntu owns the exact `aqua:starship/starship@1.26.0` mise selector. Missing
Starship guidance is explicit and manual. Native Bash owns no Starship or Node
selector, and Bash never selects Node on either profile.

## Load Order

The dispatcher is interactive-only and runs once per Bash process. Ubuntu
loads environment defaults, pinned shell behavior, aliases, tmux helpers, mise,
Starship, zoxide, fzf, Readline, Worktrunk, common personal settings, then the
host-local file. Native Omarchy enters at Worktrunk after its native baseline.

Every initializer is capability-guarded and receives `MISE_OFFLINE=1`; startup
does not install, update, fetch, or emit missing-tool diagnostics. Starship is
also skipped for `TERM=dumb`. The readable, user-owned regular
`~/.config/dotfiles/local/bash.sh` is sourced last and remains untracked.

## Validation

`tests/shell_test.sh` covers payload syntax and closure, load order,
interactive/noninteractive guards, missing tools, exact attachments, native
refresh recovery, Ubuntu login startup diagnostics, host-local sourcing, and
apply/check/remove behavior using fake Stow and isolated native/Ubuntu homes.
`tests/secrets_test.sh` is the canonical `dotfiles-secret` contract.
