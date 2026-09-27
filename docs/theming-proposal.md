# Portable Application Theming Proposal

Status: agreed direction; not implemented. Commands and paths below describe the proposed interface.

## Purpose

Select one theme per machine and have the relevant applications follow it. Native Omarchy remains the reference environment and continues to theme the whole desktop. Ubuntu receives the same theme vocabulary and reviewed palettes for Neovim, OpenCode, Herdr, and Bash/Starship.

The immediate motivation is personal Neovim: `packages/common/nvim/.config/nvim-matt/lua/plugins/editor.lua` currently hard-codes Tokyo Night, even when this machine's native Omarchy theme is Everforest. Shared preferences should define how applications follow a theme; the selected theme belongs to the host.

## User Experience

The proposed common interface is:

```text
dotfiles-theme                    show the current theme and integration status
dotfiles-theme list               list supported themes
dotfiles-theme set everforest
dotfiles-theme set tokyo-night
dotfiles-theme set catppuccin
```

On Omarchy, selection delegates to `omarchy theme set`. An integration hook synchronizes personal applications when the native desktop picker or another native command changes the theme. The desktop and personal application selections cannot drift into two independent sources of truth.

On Ubuntu, selection is a host-owned, untracked value, following the existing OpenCode profile-selection pattern. A proposed location is `~/.config/dotfiles/local/theme`. Both OpenCode profiles use that same theme; switching between work and personal profiles does not change it.

Two machines may select different themes to make local and remote work immediately distinguishable. Selecting the same theme on both provides a matching appearance without synchronizing host-local state through Git.

## Ownership And Sources Of Truth

| Concern | Authority |
| --- | --- |
| Native Omarchy selection and desktop appearance | Omarchy's current theme and native commands |
| Ubuntu selection | Host-local dotfiles theme selection |
| Portable palettes and application mappings | Reviewed definitions committed in this repository |
| Upstream provenance | Immutable Omarchy source pins and snapshot manifest |
| Generated application theme files | Disposable local output derived from the selected theme |

On native Omarchy, integrations should consume the effective current theme, including supported user overlays where practical. Ubuntu uses the committed, reviewed definitions from the pinned release. A newer native installation or a local overlay can therefore differ from Ubuntu's snapshot; matching names do not promise identical bytes across different upstream versions.

Generated output lives outside the checkout and upstream snapshots. Reapplying dotfiles preserves the chosen theme. Checking remains read-only and local; removal preserves host-local selection, installed tools, and application data. Removing integrations must leave applications with a usable startup path rather than references to removed managed files.

## Initial Theme Catalog

Start with three themes:

- `everforest`
- `tokyo-night`
- `catppuccin` — Omarchy's dark variant; `catppuccin-latte` is separate.

Separate eligibility from support:

```text
eligible = pinned Omarchy stock theme inventory − manifests/hidden-themes.txt
supported = explicitly reviewed themes within eligible
```

The eligible catalog is generated during upstream synchronization and updated with the Omarchy pin. The supported catalog records application mappings and required Neovim plugins. A newly eligible theme is a candidate for review, not an automatic addition to the selector.

The existing hidden-theme list governs native picker filtering, with existing allowances for user themes. Portable eligibility uses that list without changing native custom-theme behavior. The common selector initially offers the three supported themes; the native selector retains its broader functionality.

If a native command selects an unsupported theme, Omarchy still applies it. Integration status must identify the unsupported selection. Personal applications remain usable using a documented fallback; the integration must not change the native theme back or report that all applications match.

## Reusing Omarchy

Omarchy supplies most of the source material:

- `themes/<name>/colors.toml` defines semantic colors and terminal palette entries.
- Theme-specific `neovim.lua` files identify native colorscheme plugins and settings.
- `default/themed/` supplies generated application templates, including generic Neovim and Claude Code themes.

The installed tree is useful for inspecting actual native behavior. Portable inputs come from immutable upstream Git commits through the existing [upstream workflow](upstream.md), so Ubuntu never needs an Omarchy installation. Snapshot only the required inputs, retaining exact source identity and documenting derived mappings.

Application-specific integration still belongs here: a palette alone does not describe OpenCode configuration precedence, Herdr color support, or a shell prompt. Native theme-specific Neovim plugins should be retained where appropriate, with revisions locked and installed during provisioning. Theme switching itself is local and offline.

## Application Behavior

| Application | Intended integration |
| --- | --- |
| Personal Neovim | Resolve the host theme instead of a shared fixed colorscheme; provision supported theme plugins and apply the matching settings. Native Omarchy Neovim remains independent. |
| OpenCode | Apply the host theme across both named profiles while preserving profile settings, managed keybindings, and Herdr integration. Reuse native theme handling on Omarchy where sufficient. |
| Herdr | Keep native terminal inheritance on Omarchy where it already follows the desktop. On Ubuntu, use explicit application colors for an independent VPS appearance; confirm supported custom colors and reload behavior on the real host. |
| Bash/Starship | Keep native Omarchy behavior; derive Ubuntu prompt and managed shell accents from the selected palette. Bash does not own the terminal emulator's background or every command's output colors. |
| Claude Code | Optional follow-up using Omarchy's existing custom-theme template and synchronization behavior, subject to installed-version support. |

Existing configuration ownership remains important: native OpenCode files and Herdr integration files are host-owned; Ubuntu Herdr currently has an exactly validated configuration derivation. Theme integration must extend those contracts deliberately rather than overwrite unrelated settings.

New application launches must use the current selection. Running applications should update through supported reload mechanisms; where restart is required, status should say so. Immediate coordinated repaint across every application is not a prerequisite for the initial release.

## SSH And Terminal Boundaries

Ubuntu application theming must not emit terminal-palette control sequences or rewrite the connecting machine's terminal configuration. The VPS can use Everforest while the local terminal and desktop use Tokyo Night.

Explicit application colors provide independent accents, panels, and editor backgrounds where supported. Unthemed terminal space and programs using ANSI palette inheritance may retain the client's colors. This is intentional: the feature themes selected applications, not the entire remote terminal session.

## Delivery Across Machines

1. **Omarchy:** establish the shared catalog, source provenance, command contract, native integration, and personal Neovim behavior. Validate portable logic with fixtures.
2. **Ubuntu:** finish application adapters and exercise host-local selection, actual application versions, and real SSH/Herdr sessions.
3. **Omarchy return check:** verify Ubuntu changes preserve native picker behavior and personal application synchronization.

Each machine transition carries a reviewed commit and a concise record of completed checks, remaining work, local state, and reload limitations. Shared definitions move between machines; selected themes do not. Commits and pushes remain explicit operations requested by the user.

The first phase is detailed in [Omarchy Implementation Plan](theming-omarchy-plan.md). Claude Code and additional supported themes follow after the four primary applications work on both hosts.
