# Herdr

Herdr `0.7.5` is ready on Omarchy, generic Linux, and WSL. Native Windows and Herdr's agent-control skill remain deferred.

## Configuration

`common/herdr` stores the canonical TOML privately at `~/.config/dotfiles/herdr/config.toml`. Bootstrap copies it to the regular mode-`0600` file `~/.config/herdr/config.toml`; Herdr UI writes therefore create detectable drift instead of changing the checkout. Logs, sockets, sessions, and plugin state beside that file remain unowned.

The sole prefix is `Ctrl+Space`. `h`, `v`, `x`, and `c` provide pane/tab actions; `Ctrl+Alt+Arrow` focuses panes; `Alt+Arrow` and `Alt+1..9` navigate tabs and workspaces. Herdr's detach, reload, resize-mode, rename, and workspace lifecycle defaults remain intact. A nested tmux remains reachable through `Ctrl+B`.

The reviewed predecessor containing only `ui.agent_panel_sort = "spaces"` at mode `0664` is backed up transactionally. Removal restores its exact bytes and mode. Any other pre-existing config refuses without mutation.

## Provisioning

Only explicit `--provision` installs Herdr. The Linux x86-64 release is checksum-locked in `manifests/provisioning.json`, retained under `~/.local/share/dotfiles/provisioning/tools/herdr/0.7.5`, registered as `aqua:herdrdev/herdr@0.7.5`, and exposed through the protected `~/.local/bin/herdr` launcher.

The reviewed direct `0.7.5` binary may be adopted without downloading it only when mode, size, and SHA-256 all match the takeover lock. Other objects refuse. Root, mise link, launcher, and receipt commit together. Omarchy requires its native mise owner.

`herdr update` is outside the contract. Update by reviewing and refreshing the repository lock; managed config disables version checks.
