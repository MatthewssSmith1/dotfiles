# Herdr

Herdr `0.8.2` is ready on Omarchy and Ubuntu. Native Windows and Herdr's agent-control skill remain deferred.

## Configuration

On native Omarchy, Herdr is validation-only. Dotfiles requires package-owned `/usr/bin/herdr`, valid package metadata, matching executable version output, a safe user-owned config, `ui.status_indicators = "symbols"`, and a successful offline `herdr config check` against an isolated copy of the actual config. Valid unreviewed package versions warn instead of blocking; this is not a compatibility guarantee. Other native settings remain host-owned and may differ from the repository snapshot. Apply, check, and remove write no persistent files and create no deployment state. Set the preference manually under `[ui]` when validation reports a mismatch; inspect ownership, metadata, or runtime-version failures before reinstalling Herdr. Semantic preference validation requires Python 3.11+ with `tomllib`.

The shared symbols preference uses distinct static glyphs for blocked, working, done, idle, and unknown agent states. Herdr's other option and default, `"dots"`, uses compact colored status marks. Ubuntu deploys `"symbols"`; native validation requires it in the host-owned config.

Ubuntu deploys the accepted v4 config with a mechanically verified policy preamble and reviewed UI preference suffix, an exact `aqua:ogulcancelik/herdr@0.8.2` mise selector, and curated `hdl`, `hds`, `hdlm`, and `hsl` helpers from `ubuntu/herdr`. Helpers diagnose missing Herdr, `jq`, `awk`, Hunk, OpenCode, and the selected editor. The Bash dispatcher sources them only when the Herdr package is present.

Ubuntu also deploys `~/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf` so Moshi's generated user service can resolve the mise-managed Herdr shim. Dotfiles does not own Moshi's primary service. Running `systemctl --user daemon-reload` and restarting the service remain manual, outside dotfiles apply/check/remove.

The sole prefix is `Ctrl+Space`. `h`, `v`, `x`, and `c` provide pane/tab actions; `Ctrl+Alt+Arrow` focuses panes; `Alt+Arrow` and `Alt+1..9` navigate tabs and workspaces. Herdr's detach, reload, resize-mode, rename, and workspace lifecycle defaults remain intact. A nested tmux remains reachable through `Ctrl+B`.

The Ubuntu area is package-only and creates no state. Removal accepts only exact Stow links and preserves logs, sessions, sockets, and other runtime siblings.

The policy records onboarding as complete and disables version checks because the Ubuntu runtime is repository- and mise-pinned. Agent-detection manifest checks are intentionally enabled and may use the network during ordinary Herdr runtime. The reviewed UI suffix sets `agent_panel_sort = "priority"`, `host_cursor = "native"`, and `status_indicators = "symbols"` in the snapshot's final `[ui]` table. The native cursor preserves Neovim's mode-dependent cursor shapes on WSL, at the possible cost of ConPTY cursor flicker. Changing Ubuntu settings through Herdr writes through the Stow link into this checkout; incorporate permanent preferences into the repository config, derivation validator, and contract tests.

## Installation

Dotfiles does not fetch or install Herdr. On Ubuntu, install the selected runtime explicitly with `mise install aqua:ogulcancelik/herdr@0.8.2`; ordinary apply, check, and remove remain offline. The registry key retains Herdr's former repository owner; validation requires the exact versioned mise installation so stale launchers cannot satisfy the contract by reporting the selected version.

On native Omarchy, update Herdr through Omarchy's package management. Ubuntu retains its exact mise selector; update it by reviewing and refreshing the repository pin. `herdr update` is outside both runtime ownership contracts.
