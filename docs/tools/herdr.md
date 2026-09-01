# Herdr

Herdr `0.8.2` is ready on Omarchy and Ubuntu. Native Windows and Herdr's agent-control skill remain deferred.

## Configuration

On native Omarchy, Herdr is validation-only. Dotfiles requires package-owned `/usr/bin/herdr`, pacman identity `herdr 0.8.2-1`, executable behavior `herdr 0.8.2`, the accepted stock config bytes at `~/.config/herdr/config.toml`, a safe user-owned mode, and a successful offline `herdr config check`. Apply, check, and remove write nothing and create no deployment state. `omarchy refresh herdr` or reinstalling Herdr restores package/config drift.

Ubuntu deploys the accepted v4 config with one mechanically verified policy preamble, an exact `aqua:ogulcancelik/herdr@0.8.2` mise selector, and curated `hdl`, `hds`, `hdlm`, and `hsl` helpers from `ubuntu/herdr`. Helpers diagnose missing Herdr, `jq`, `awk`, Hunk, OpenCode, and the selected editor. The Bash dispatcher sources them only when the Herdr package is present.

Ubuntu also deploys `~/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf` so Moshi's generated user service can resolve the mise-managed Herdr shim. Dotfiles does not own Moshi's primary service. Running `systemctl --user daemon-reload` and restarting the service remain manual, outside dotfiles apply/check/remove.

The sole prefix is `Ctrl+Space`. `h`, `v`, `x`, and `c` provide pane/tab actions; `Ctrl+Alt+Arrow` focuses panes; `Alt+Arrow` and `Alt+1..9` navigate tabs and workspaces. Herdr's detach, reload, resize-mode, rename, and workspace lifecycle defaults remain intact. A nested tmux remains reachable through `Ctrl+B`.

The Ubuntu area is package-only and creates no state. Removal accepts only exact Stow links and preserves logs, sessions, sockets, and other runtime siblings.

The policy records onboarding as complete and disables version checks because the runtime is repository- and mise-pinned. Agent-detection manifest checks are intentionally enabled and may use the network during ordinary Herdr runtime. Changing settings through Herdr writes through the Stow link into this checkout; edit reviewed preferences in the repository and keep the exact policy derivation.

## Installation

Dotfiles does not fetch or install Herdr. On Ubuntu, install the selected runtime explicitly with `mise install aqua:ogulcancelik/herdr@0.8.2`; ordinary apply, check, and remove remain offline. The registry key retains Herdr's former repository owner; validation requires the exact versioned mise installation so stale launchers cannot satisfy the contract by reporting the selected version.

`herdr update` is outside the contract. Update by reviewing and refreshing the repository lock.
