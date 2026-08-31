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
`shell.json`, and a generated package XCompose fragment with managed aliases. It
also guards the `Style > Theme` entry and a `Shortcuts` submenu in the regular personal menu
extension and owns `dotfiles-omarchy-theme-switcher`. That row still uses
Omarchy's native image carousel and
`omarchy-theme-set`, but hides these bundled theme directories: `ethereal`,
`flexoki-light`, `hackerman`, `last-horizon`, `lumon`, `lupine`, `miasma`,
`rose-pine`, `vantablack`, and `white`. User-installed themes remain visible,
and new bundled themes appear unless added to that exact denylist. Hidden
themes remain installed and directly selectable with `omarchy theme set NAME`.
Background double-right-click remains native and unfiltered; dotfiles does not
intercept or replace its selector.
The selector exposes a filtered themes-only root during preview discovery, then
a scoped `omarchy-menu-images` adapter restores `/usr/share/omarchy` for shell
IPC. The filtered root is never exposed to `omarchy-shell`.

`SUPER+SHIFT+K` opens the generated shortcut submenu. Its actions call
`dotfiles-omarchy-compose-shortcut` with stable IDs and replay the corresponding
`Multi_key` sequence through `wtype`; XCompose remains authoritative. The
clipboard is unchanged and actions do not submit Enter. Name and email are
read-only references to definitions in native `~/.XCompose`; em dash references
Omarchy's packaged default. Their private output is never copied into the
repository, and managed CRUD cannot edit or delete them.

Use these operator workflows:

```bash
dotfiles-shortcuts manage
dotfiles-shortcuts edit-manifest
dotfiles-shortcuts sync
```

The manager offers alias/group CRUD, manifest editing, and synchronization.
After manual edits, run `dotfiles-shortcuts sync`. CRUD updates the canonical
repository manifest and generated XCompose, menu, binding, and helper artifacts,
so changes persist for ordinary review and commits. Sync separately applies the
desktop area, restarts XCompose, refreshes the menu, and reloads Hyprland only
when its generated binding changed; `dotfiles.sh apply/check/remove` never do
those runtime operations.

A guarded include attaches that fragment to the regular Omarchy-owned
`~/.XCompose`, preserving its default include, name, and email content. A second
guarded loader attaches the private shortcut binding fragment to the regular
`~/.config/hypr/bindings.lua`. It
leaves keyboard layout/options and every unrelated shell value, including
Tailscale widgets, to Omarchy. It does not install, configure, authenticate, or
validate Tailscale. Apply does not restart or reload desktop components; the
shell file watchers consume valid shell and menu changes, so no menu refresh is
normally needed.

If an Omarchy refresh replaces `~/.XCompose`, reapplying the desktop area
restores the guarded include without duplication.

First adoption requires separate explicit confirmation before the single-file
native reset `omarchy refresh config hypr/input.lua`, followed by
`dotfiles.sh apply desktop`. Do not substitute the broader Hyprland refresh.
Omarchy creates `~/.config/omarchy/extensions/omarchy-menu.jsonc` as a regular
stock template. Dotfiles keeps it regular, inserts one marked `style.theme`
entry after the opening `{`, and preserves compatible unrelated entries byte
for byte, including multiline objects, partial overrides, submenus, providers,
and target links. If refresh removes the markers, check reports drift;
deliberate apply re-adopts the refreshed compatible baseline. Unmanaged
`style.theme`, malformed or wrapped `items` objects, ambiguous anchors, and
unsafe paths are refused.

For tmux, the native `~/.config/tmux/tmux.conf` remains the regular Omarchy-owned baseline. The validation-only area checks exact package identity, runtime output, stock bytes, safe owner/mode, key prefixes, terminal, and parsing without writing files or state.

## Executable Ownership

Development tools resolve to native Omarchy packages. Dotfiles fails if a
protected command such as Neovim does not resolve to its accepted package-owned
`/usr/bin` runtime.

Herdr resolves exactly to package-owned `/usr/bin/herdr`; dotfiles validates
its accepted version and stock config without changing it. See the
[Herdr contract](../tools/herdr.md).

Claude Code, Codex, and the generic OpenCode executable retain their Omarchy or native host owners. The optional OpenCode area adds only profile/TUI overlays, named launchers, and a helper; interactive Bash routes plain `opencode` through the personal overlay without replacing the native executable. It adds no assistant mise selector, does not require an assistant executable, and leaves assistant application state untouched.

Bash is ready; native attachment and refresh behavior is covered by isolated fixtures.

## Version Drift

Native Omarchy self-updates while other machines deploy the pinned snapshot recorded in [Upstream](../upstream.md). Dotfiles reports separate core and `omarchy-nvim` package warnings when a valid native owner's parseable version differs from its recorded pin. These warnings are non-blocking; missing owners, malformed metadata, and forbidden shadows remain blocking. Drift is expected, and advancing either pin is a separate explicit sync-and-review operation.

## Validation

Native-profile validation was performed live on this machine before the v4 vertical conversions. Current tmux acceptance is the focused validation-only suite plus a real installed parser when tmux 3.5 or newer is available.
