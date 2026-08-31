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

## Hardware Workarounds

Applying the tools area also installs `dotfiles-omarchy-amdgpu-ips`. This
manual helper targets the Framework Laptop 13 AMD Ryzen AI 300 Series with
board `FRANMGCP09` and AMD display device `1002:150e`; it refuses every other
hardware tuple. It addresses the AMDGPU IPS/DMUB display-idle hard lock tracked
in [Omarchy issue 6223](https://github.com/omacom/omarchy/issues/6223) by adding
`amdgpu.dcdebugmask=0x800` to Limine's default kernel command line.

Disabling IPS may increase idle power use. Normal dotfiles apply, check, and
remove only deploy or remove the inert helper and never alter `/etc`, rebuild
boot images, or apply the kernel argument.

Inspect, configure, or remove the workaround explicitly:

```bash
dotfiles-omarchy-amdgpu-ips status
dotfiles-omarchy-amdgpu-ips apply
dotfiles-omarchy-amdgpu-ips remove
```

`apply` and `remove` manage only
`/etc/limine-entry-tool.d/90-dotfiles-amdgpu-ips.conf`, refuse unexpected
content or competing assignments, and rebuild Limine entries. They never
reboot. After either mutation, reboot deliberately and run `status` again;
success after apply is an exact managed configuration and exactly one active
`amdgpu.dcdebugmask=0x800` token. Remove the workaround and reboot after an
upstream kernel fix is confirmed.

## Desktop

The desktop area owns natural touchpad scrolling in a private fragment, the
`idle.screensaver=600` and `idle.lock=900` scalar values in the regular Omarchy
`shell.json`, and a package XCompose fragment with four personal aliases. It
also owns the personal menu extension and `dotfiles-omarchy-theme-switcher`.
The Style > Theme row still uses Omarchy's native image carousel and
`omarchy-theme-set`, but hides these bundled theme directories: `ethereal`,
`flexoki-light`, `hackerman`, `last-horizon`, `lumon`, `lupine`, `miasma`,
`rose-pine`, `vantablack`, and `white`. User-installed themes remain visible,
and new bundled themes appear unless added to that exact denylist. Hidden
themes remain installed and directly selectable with `omarchy theme set NAME`.

A guarded include attaches that fragment to the regular Omarchy-owned
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
Omarchy also initially creates
`~/.config/omarchy/extensions/omarchy-menu.jsonc` as a regular stock template.
After reviewing it, remove the unchanged template and rerun
`dotfiles.sh apply desktop`; edited templates are preserved and require a
manual merge. If an explicit Omarchy config reset later replaces the managed
link, check reports drift and apply preserves the replacement until it is
deliberately re-adopted.

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
