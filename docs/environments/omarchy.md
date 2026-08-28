# Omarchy

Notes for native Omarchy machines. On this profile, installed Omarchy defaults are authoritative; this repository attaches shared layers without replacing refresh-managed files. See [Architecture](../architecture.md) and [Deployment](../deployment.md#lean-ownership).

## Refresh-Managed Files

Omarchy refresh or reinstall operations can replace Bash, desktop input,
XCompose, and Neovim configuration. Those destinations remain regular
Omarchy-owned files, never symlinks into this checkout. Shared behavior uses
the guarded ownership contract in
[Deployment](../deployment.md#lean-ownership); the Neovim refresh
(`omarchy-nvim-setup`) can additionally clear Neovim data, state, and cache, and
recovery recreates only the managed loader.

For Bash specifically, dotfiles appends one additive source block after the native `.bashrc`; it does not replace the native Bash or Starship baseline and does not modify a login file.

After a supported refresh, re-run the relevant apply command; attachments converge without duplication.

## Default-App Pruning

Applying the tools area installs `dotfiles-omarchy-prune` on `PATH`. Run it
manually as the desktop user to immediately remove the HEY, Basecamp, Zoom, and
Google Messages web-app launchers plus the `moonlight-qt` and `localsend`
packages. It does not prompt for removal confirmation, although Omarchy may ask
for sudo authentication while removing installed packages.

The command uses supported Omarchy package and web-app operations. It preserves
application configuration, data, caches, sessions, and credentials, and is safe
to rerun when targets are already absent. It installs no hook or trigger and is
never executed by dotfiles apply, check, or remove.

Fresh installs, migrations, or `omarchy refresh applications` may restore these
defaults. Rerun `dotfiles-omarchy-prune` explicitly when needed.

## Desktop

The desktop area owns natural touchpad scrolling in a private fragment, the
`idle.screensaver=600` and `idle.lock=900` scalar values in the regular Omarchy
`shell.json`, and a package XCompose fragment with four personal aliases. A
guarded include attaches that fragment to the regular Omarchy-owned
`~/.XCompose`, preserving its default include, name, and email content. It
leaves keyboard layout/options and every unrelated shell value, including
Tailscale widgets, to Omarchy. It does not install, configure, authenticate, or
validate Tailscale. Apply does not restart or reload desktop components; the
shell file watcher consumes valid shell changes.

If an Omarchy refresh replaces `~/.XCompose`, reapplying the desktop area
restores the guarded include without duplication.

First adoption requires separate explicit confirmation before the single-file
native reset `omarchy refresh config hypr/input.lua`, followed by
`dotfiles.sh apply desktop`. Do not substitute the broader Hyprland refresh.

For tmux, the native `~/.config/tmux/tmux.conf` remains the regular Omarchy-owned baseline. The validation-only area checks exact package identity, runtime output, stock bytes, safe owner/mode, key prefixes, terminal, and parsing without writing files or state.

## Executable Ownership

Development tools resolve to native Omarchy packages. Dotfiles fails if a
protected command such as Neovim does not resolve to its accepted package-owned
`/usr/bin` runtime.

Herdr resolves exactly to package-owned `/usr/bin/herdr`; dotfiles validates
its accepted version and stock config without changing it. See the
[Herdr contract](../tools/herdr.md).

Claude Code, Codex, and the OpenCode executable retain their Omarchy or native host owners. The optional OpenCode area manages configuration only; it adds no assistant mise selector, does not require an assistant executable, and leaves assistant application state untouched.

Bash is ready; native attachment and refresh behavior is covered by isolated fixtures.

## Version Drift

Native Omarchy self-updates while other machines deploy the pinned snapshot recorded in [Upstream](../upstream.md). Dotfiles reports separate core and `omarchy-nvim` package warnings when a valid native owner's parseable version differs from its recorded pin. These warnings are non-blocking; missing owners, malformed metadata, and forbidden shadows remain blocking. Drift is expected, and advancing either pin is a separate explicit sync-and-review operation.

## Validation

Native-profile validation was performed live on this machine before the v4 vertical conversions. Current tmux acceptance is the focused validation-only suite plus a real installed parser when tmux 3.5 or newer is available.
