# Portable Theming: Omarchy Implementation Plan

Status: proposed work; no implementation completed by this document.

Scope: phase one of the [Portable Application Theming Proposal](theming-proposal.md). Establish the shared foundation and native integration on Omarchy, then hand off a stable interface for Ubuntu implementation and real-host validation.

## Completion Criteria

- The common selector supports Everforest, Tokyo Night, and dark Catppuccin.
- Both native picker changes and common command changes synchronize personal Neovim with the native selection.
- OpenCode's personal/work profiles follow the native theme without disturbing profile settings or Herdr integration.
- Native Herdr and Bash continue to follow their existing Omarchy appearance; any integration gaps are identified and addressed within native ownership boundaries.
- Supported Neovim theme plugins are provisioned and locked; switching needs no network access.
- Portable source inputs, eligibility rules, and application mappings have reviewed provenance and offline validation.
- Ubuntu-facing contracts are documented and fixture-tested. Ubuntu application integration and real SSH behavior remain the next phase.
- The original native theme is restored after live acceptance testing.

## 1. Establish The Baseline

Read the applicable configuration and upstream-update workflows before implementation. Record:

- Repository status, native Omarchy version, pinned core version, current theme, and relevant application versions.
- Effective native theme paths and any user overlays. The observed installation currently stores state under `~/.local/state/omarchy/current/`; confirm this against the implementation target.
- Native theme staging, `theme-set` hook ordering, and reload commands.
- The actual startup and reload behavior of native Neovim, personal Neovim, both OpenCode profiles, Herdr, and Bash/Starship.

Inspect these integration points:

| Area | Existing files |
| --- | --- |
| Personal Neovim | `packages/common/nvim/.config/nvim-matt/`, `lib/areas/nvim.sh`, `docs/tools/neovim.md` |
| OpenCode profiles | `packages/common/opencode/`, `lib/areas/opencode.sh`, `docs/tools/opencode.md` |
| Native desktop integration | `packages/omarchy/desktop/`, `lib/areas/desktop.sh` |
| Shell and Herdr | Profile-specific Bash/Herdr packages, `lib/areas/bash.sh`, `lib/areas/herdr.sh` |
| Theme filtering | `manifests/hidden-themes.txt`, the managed Omarchy theme switcher |
| Provenance | `manifests/sources.json`, `scripts/upstream`, `lib/upstream/`, `docs/upstream.md` |

Distinguish live observations from pinned behavior. In particular, verify colorscheme names and plugin options rather than assuming that a current native installation matches the historical Neovim snapshot.

## 2. Define The Shared Contract

Finalize the following before building adapters:

- `dotfiles-theme`, `dotfiles-theme list`, and `dotfiles-theme set <slug>`; specify output, exit codes, unsupported-theme reporting, and reload notices.
- A supported-theme manifest with stable slugs, palette provenance, Neovim plugin/settings mappings, and any application-specific overrides.
- Generated eligible-theme inventory derived from the pinned stock inventory minus the existing hidden list.
- Ubuntu host-local state at the proposed `~/.config/dotfiles/local/theme`, including missing/invalid-state behavior. Use Tokyo Night as the documented initial fallback to preserve the existing personal editor default; do not persist a selection merely by reading it.
- Native resolution from Omarchy's actual current state, with no second persisted selection. For unsupported native themes, report the mismatch and use an explicit personal-Neovim fallback rather than changing the desktop selection.
- A small internal synchronization entry point shared by the native hook and command integration.
- Locations and ownership for generated output outside the repository; publish validated output atomically and serialize overlapping synchronization attempts.

Choose deployment ownership explicitly in `manifests/areas.tsv` and the relevant area code. Prefer the existing tools area for the common command/catalog, desktop for the native hook, and each application area for its adapter. Verify this placement handles independently installed or removed areas without introducing undeclared dependencies; document any necessary dependency changes.

Applications may be absent. Status should distinguish absent applications, unsupported mappings, and failures. An adapter failure must be reported without claiming that every application switched successfully. Native changes already applied by Omarchy remain authoritative.

Ubuntu mutation support can remain unfinished in this phase, but must report that clearly. Deploying the shared foundation must preserve the VPS's existing usable application configuration until its adapters are ready.

## 3. Add Reviewed Theme Inputs

Follow the upstream-update workflow for snapshot and manifest changes:

1. Inspect the three themes at the active immutable core pin. Identify required palettes, theme-specific Neovim specs, and any necessary templates.
2. Extend synchronization inventory and provenance records with exact source paths, modes, and blob identities. Reuse existing Tokyo Night inputs where suitable.
3. Record enough pinned stock-theme inventory evidence to regenerate eligibility offline; do not depend on the locally installed theme directory for this list.
4. Generate eligibility deterministically and validate that supported themes are eligible and have all required mappings.
5. Keep exact upstream inputs separate from portable derived output, documenting transformations and testing their reproduction.
6. Extend refresh verification so new upstream themes appear as eligible candidates, while removed, newly excluded, or incomplete supported themes require an explicit resolution.

Do not refresh unrelated pins as a side effect. Verify candidate synchronization failure preserves the previous accepted snapshot and manifest. Theme selection, shell startup, apply/check/remove must never invoke upstream synchronization.

## 4. Implement Native Selection And Synchronization

- Implement the common read/list/set interface with host detection consistent with the repository.
- On Omarchy, validate supported input and delegate to the native theme command. Do not independently reproduce desktop theme staging.
- Install an individually owned script through the supported `theme-set` hook mechanism, retaining unrelated hooks and the flat legacy hook if present.
- Define how deployment tracks the installed hook and removes only its own attachment. Inspect whether the native hook installer copies files before selecting the ownership strategy.
- Have the hook read effective current native state. Treat its event argument as notification context rather than unquestioned current truth: overlapping native changes can make older hook events arrive late.
- Avoid recursion: synchronization must not call native theme selection again. Reapplying the same selection should be safe.
- Surface hook errors through common status/check output as well as diagnostics; the native command may suppress hook output.
- Reconcile initial application state explicitly during deployment, without changing the desktop theme. Keep `check` read-only.

Use existing native application reload behavior where sufficient. Add only the personal integrations it does not cover. Confirm new launches recover the current selection after a missed hook; document any running-session restart requirement.

## 5. Connect Personal Applications

### Neovim

1. Replace the fixed colorscheme in `lua/plugins/editor.lua` with a dedicated theme resolver/spec layer.
2. Declare all three supported themes' required plugins statically, independent of the currently selected theme. Review their settings against Omarchy's theme specs.
3. Lock and provision plugin revisions through the existing personal Neovim workflow. Keep the historical upstream Neovim evidence unchanged.
4. Resolve native effective theme data on Omarchy. Define the portable selection input for Ubuntu without requiring an Omarchy installation.
5. Support theme updates in running personal instances through a tested reload or watcher mechanism, accounting for directory replacement during native staging. Test switching away from and back to the same plugin as well as between different plugins.
6. Keep native `~/.config/nvim` separate. Generated theme files must not be written through the shared `nvim-matt` directory link into the checkout.

### OpenCode

1. Verify native theme behavior in both named launchers and its interaction with `OPENCODE_TUI_CONFIG`.
2. Retain native handling if it already works; otherwise add a narrowly scoped theme adapter at the managed overlay boundary.
3. Preserve keybindings, provider/profile configuration, and Herdr-owned TUI integration. Confirm actual precedence and reload behavior against the installed OpenCode version.
4. Record the portable adapter contract for Ubuntu. Do not assume that identically named built-in themes exactly match Omarchy's palette.

### Herdr And Bash

Verify their native terminal inheritance and prompt colors follow all three desktop themes. Keep the native configuration ownership model. Record any required explicit-color mappings for Ubuntu, including which Herdr fields accept literal colors and which behavior still needs real-host verification.

Do not implement SSH terminal-palette mutation as a shortcut. The future Ubuntu adapters must operate on application colors, preserving the connecting terminal's palette.

## 6. Validate

### Focused automated checks

Use the smallest suites from `tests/AGENTS.md` while iterating, including contract, upstream, tools, desktop, Neovim/provisioning, and OpenCode suites as their files change. Include Bash or Herdr suites if those areas change. Add meaningful coverage for:

- Catalog generation, exclusions, incomplete mappings, and a newly added upstream theme remaining unsupported.
- Missing/invalid local selection, unsupported native themes, absent optional applications, and clear partial-failure status.
- Command-to-native delegation and native hook synchronization without recursion or stale-event overwrite.
- Atomic generated output, independently deployed areas, and owned-hook removal without disturbing other hooks.
- New Neovim starts and repeated theme changes with all required plugins already provisioned.
- Read-only/local checks, offline switching, preserved host-local state, and no generated writes into tracked configuration.
- An Ubuntu fixture with no Omarchy installation, proving portable palette/resolver behavior and explicit reporting of unfinished Ubuntu integration.

This phase changes upstream inputs and multiple areas. Run `tests/run.sh` before committing the implementation; constrain concurrency for this machine and record results. Fixture coverage does not replace Ubuntu host acceptance.

### Native acceptance matrix

For each supported theme:

1. Select it through the common command; verify native theme state and desktop appearance.
2. Verify personal Neovim at startup and in an existing session; compare with native Neovim.
3. Verify both OpenCode profiles, native Herdr, and Bash/Starship. Record whether each updates live or needs a supported reload/restart.
4. Repeat selection through the native picker and verify the personal integrations follow.
5. Switch again with network access unavailable after provisioning.

Also exercise an unsupported native selection without breaking the desktop, reapply without resetting selection, and removal/reattachment in isolated fixtures. Restore the original live theme and verify final status. Do not use broad Omarchy refresh commands to repair integration errors.

## 7. Document And Hand Off To Ubuntu

Update operational documentation only for implemented behavior. Prepare a machine-transition record containing:

- Reviewed implementation commit(s), with commit/push performed only when requested.
- Final command/state/catalog contracts and deployment ownership.
- Exact automated and native checks completed, failures, and remaining gaps.
- Theme/plugin mappings, source versions, and any native-versus-pinned differences.
- Initial and restored host theme, generated-file locations, and reload limitations.
- Ubuntu work remaining: local selection mutation, explicit application adapters, actual Herdr capabilities, both OpenCode profiles, and real SSH validation without terminal-palette changes.
- Return-to-Omarchy checks required after Ubuntu integration.

Phase one ends when the shared contract and native behavior meet the completion criteria. Additional themes and Claude Code remain follow-up scope after both primary hosts pass acceptance.
