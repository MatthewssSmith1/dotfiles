# Omarchy

Notes for native Omarchy machines. On this profile, installed Omarchy defaults are authoritative; this repository attaches shared layers without replacing refresh-managed files. See [Architecture](../architecture.md) and [Deployment](../deployment.md#native-omarchy-attachments).

## Refresh-Managed Files

Omarchy refresh or reinstall operations can replace Bash, tmux, Starship, and Neovim configuration. Those destinations stay regular Omarchy-owned files, never symlinks into this checkout. Shared behavior attaches through the canonical guarded-attachment contract in [Deployment](../deployment.md#native-omarchy-attachments); the Neovim refresh (`omarchy-nvim-setup`) can additionally clear Neovim data, state, and cache — recovery recreates only the managed loader.

For Bash specifically, bootstrap appends an additive block that sources only common personal integrations after the native `.bashrc`; it does not use the generic/WSL bypass strategy and does not replace the native Starship baseline. No native login attachment is planned without fixture-backed evidence that one is needed.

After a supported refresh, re-run bootstrap to reapply attachments; it converges without duplicating them.

For tmux, the native `~/.config/tmux/tmux.conf` remains the regular Omarchy-owned baseline. Bootstrap appends one guarded managed block that sources only `~/.config/dotfiles/tmux/persistence.conf`; that common file ends with guarded TPM initialization. Native Omarchy receives no generic dispatcher, private generic snapshot, generic or WSL adapter, or host-local tmux layer.

## Executable Ownership

Development tools resolve to native Omarchy packages. Bootstrap fails if a prohibited command such as Neovim resolves through a mise shim instead of the native package. See the ownership table in [Deployment](../deployment.md#executable-ownership). Missing native owners and forbidden exported-function, `PATH`, shim, user-local, or project shadows are blocking. Arbitrary unexported aliases and functions in the parent shell are outside bootstrap's inherited visibility; the managed interactive shell closes that boundary without executing rejected aliases, functions, or executable shadows.

Herdr is the sole exception: explicit provisioning installs its checksum-locked release through native mise. Its regular config and predecessor restoration follow the shared [Herdr contract](../tools/herdr.md).

Bash and zsh are ready; native attachment and refresh behavior were validated live on this profile.

## Version Drift

Native Omarchy self-updates while other machines deploy the pinned snapshot recorded in [Upstream](../upstream.md). Bootstrap reports separate core and `omarchy-nvim` package warnings when a valid native owner's parseable version differs from its recorded pin. These warnings are non-blocking; missing owners, malformed metadata, and forbidden shadows remain blocking. Drift is expected, and advancing either pin is a separate explicit sync-and-review operation.

## Validation

Native-profile validation was performed live on this machine: attachment behavior against real refresh-managed files, Neovim loader refresh recovery (`omarchy-nvim-setup`, then failing check, then byte-identical reapply), forbidden-shim detection, and separate core and Neovim package drift warnings. Per-area check, apply, removal, and reapply cycles converge with byte-identical restoration of native files; check, removal, apply, and shell/tmux startup were additionally proven inside a denied-network namespace.
