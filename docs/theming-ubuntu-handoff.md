# Theming: Ubuntu Handoff

Recorded 2026-09-27. Shared foundation and Omarchy code are implemented and deployed on the reference host. Full phase-one visual acceptance is still pending. The implementation accompanies this record; the design documents were committed as `4ea5563`. Commit/push only when requested.

## Stable Inputs and Interfaces

- [Operations](tools/theming.md): CLI, exit codes, state, ownership, recovery, reload limits.
- [Catalog provenance](upstream.md#portable-theme-catalog): version-1 supported mappings, generated eligibility, exact palette copies and Git inventory evidence.
- Core remains v4.0.4, commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`. Historical Neovim package remains `2026.8.13-1`; neither pin was advanced.
- Supported slugs: `everforest`, `tokyo-night`, dark `catppuccin`. Twelve themes are eligible; eligibility does not enable them.
- Ubuntu selection contract: `~/.config/dotfiles/local/theme` (XDG config respected); missing/invalid reads use Tokyo Night without persisting it. Mutation and adapters were implemented on the VPS on 2026-09-28; see validation below.
- Native observation: `~/.local/state/dotfiles/theme/current.json`; personal Neovim reads native Omarchy state directly. No second native selection is stored.

### Personal Neovim mappings

| Slug | Plugin | Scheme/settings | Locked revision |
| --- | --- | --- | --- |
| `everforest` | `neanias/everforest-nvim` | `everforest`, plugin background `soft` | `a0e9edc57379e8feafc6ba207c26dbb12fc1b6d8` |
| `tokyo-night` | `folke/tokyonight.nvim` | `tokyonight-night` | `cdc07ac78467a233fd62c493de29a17e0cf2b2b6` |
| `catppuccin` | `catppuccin/nvim` | `catppuccin-nvim`; reports `catppuccin-mocha` at runtime | `edefef779ab08ce1a4a404713e3012b0d202bd35` |

All three are statically declared. First provisioning uses built-in `habamax`; ordinary startup resolves native state. A one-second watcher notices theme/spec changes and retries failed reloads. Unreviewed specs and unsupported native themes warn and use Tokyo Night.

**Native discrepancy:** installed stock palettes and Neovim spec files match all six pinned inputs byte-for-byte. However, native Everforest reports plugin background `medium`, while personal Neovim reports `soft`: the stock spec places `background = "soft"` in LazyVim options; personal integration explicitly passes it to Everforest's setup. Colorscheme names match, but exact editor backgrounds are not identical. Keep this distinction visible during visual acceptance.

## Validation Completed

Host: Omarchy `4.0.4-1`, Neovim `0.12.5-1`, omarchy-nvim `2026.8.13-1`, OpenCode `1.18.32` in both named launchers, Herdr `0.8.2-1`, Starship `1.26.0`.

- `tests/run.sh --jobs 2` passed during integration and again after the final fixes. Real Stow integration is intentionally separate from the fixture gate; Windows Terminal merge was skipped because PowerShell was unavailable, and missing `python3-jsonschema` prevented schema validation.
- Focused contract, tools, desktop, Neovim and provisioning suites also passed after fixing first-provisioning startup, same-slug watcher retries and persistent hook failure reporting.
- `scripts/upstream verify` passed: 51 pinned snapshot files plus generated catalog/inventory checks. `git diff --check` passed.
- Live tools, desktop, Neovim, OpenCode, Herdr and Bash area checks passed; Neovim apply completed without the initial missing-Everforest error. The final real native-hook invocation and synchronization check passed. Hyprland reported no config errors.
- On-host offline matrix selected Tokyo Night → Catppuccin → Everforest → Tokyo Night → Everforest through **both** `dotfiles-theme set` and `omarchy theme set`. Every selection synchronized; a persistent personal headless Neovim followed each switch, and fresh personal/native starts reported matching colorscheme names.
- Unsupported native Gruvbox remained selected while personal Neovim fell back to Tokyo Night; status reported unsupported and synchronized check succeeded.
- Network access was disabled using `unshare -Urnpf --mount-proc`. PID isolation kept native process-reload signals away from the running agent/application sessions. Background rotation was disabled with `OMARCHY_THEME_SKIP_BACKGROUND=1`. Consequently this matrix proves native state, hook, offline operation and editor behavior, not full desktop/app repaint.
- Initial and restored native theme: **Everforest**. Tools/desktop reconciliation and Neovim reapply retained it.

Fixtures additionally cover concurrent/atomic observation, stale hook event arguments, persistent failure visibility after a later sync, hook recovery/removal, absent independent areas, unsupported selection, same-slug editor spec changes, and Ubuntu without Omarchy. Checks remain local/read-only.

## Acceptance Still Open on Omarchy

For all three themes, use the actual native picker and common command in a normal desktop session. Verify desktop/terminal rendering, both OpenCode profile TUIs, Herdr panes/status, Bash/Starship, and editor appearance. Record which existing sessions require restart/reconnect. The CLI matrix exercised the picker backend, not its interactive UI. Native `SIGUSR2` dispatch was inspected; successful in-session OpenCode retint has not been demonstrated. Restore Everforest afterward.

## Ubuntu Implementation and Validation (2026-09-28)

- Implemented serialized atomic selection/generation publication, failure rollback, read-only status/check, Neovim resolver/watcher, explicit OpenCode/Herdr palettes, and Starship/FZF accents. See [operations](tools/theming.md#ubuntu-contract) for ownership and recovery.
- Reviewed OpenCode 1.18.32 theme shape and symlink discovery, plus Herdr 0.8.2 literal-color fields and `HERDR_CONFIG_PATH` file semantics against tagged sources.
- Targeted contract, tools, Neovim, Herdr, OpenCode, Bash suites passed; nine Ubuntu adapter regressions cover fallback, all palettes, unrelated settings, concurrent switching, corrupt output, conflicting files, injected runtime/selection failures, launchers, and shell options/status preservation.
- Full-suite attempts were interrupted. The user explicitly requested targeted suites instead; no full-gate pass is claimed.
- Applied `tools nvim opencode herdr bash` on the VPS; all five area checks and `dotfiles-theme check` passed. Herdr accepted the generated config. Selected **Tokyo Night** persistently.
- Network-isolated (`unshare -Urn`) real personal Neovim stayed open through Everforest → Catppuccin → Tokyo Night; each live colorscheme reload passed. Final VPS selection: **Tokyo Night**.

### Acceptance Remaining

- Visual SSH/OpenCode/Herdr acceptance with differing local/remote selections; existing Herdr server reload/reconnect behavior. Existing app sessions were not restarted. Restart OpenCode and pre-integration Neovim once; open a new Bash session. A pre-integration Herdr server needs a deliberate restart to adopt the generated config path.
- Return to Omarchy for the native picker/common-command and visual acceptance listed above; restore Everforest there. Its host selection was not changed by VPS deployment.

Generated application output belongs outside Git and shared `nvim-matt` links. The eventual implementation commit transports definitions only; host selections remain independent. Additional themes and Claude Code remain later scope.
