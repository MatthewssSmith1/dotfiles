# tmux

## Ownership

Native Omarchy owns `/usr/bin/tmux` and `~/.config/tmux/tmux.conf`. The tmux
area is validation-only there: apply, check, and remove perform the same
read-only validation, invoke no Stow command, and write no deployment state.
The accepted package is `tmux 3.7_c-1`, reporting `tmux 3.7c`; the stock config
must remain byte-identical to the accepted Omarchy v4 snapshot. On drift, run
`omarchy refresh tmux` or reinstall tmux and rerun validation.

Ubuntu deploys `upstream/tmux` and `ubuntu/tmux` as a package-only, state-free
closure. The upstream file remains byte-identical. The Ubuntu package adds only
an XDG dispatcher, an exact mise selector, static help text, and a small adapter
that replaces the Omarchy-only `?` command with `display-popup` and `less`.

## Runtime

Ubuntu accepts package-owned `/usr/bin/tmux` when it reports version 3.5 or
newer. Otherwise install the exact fallback outside dotfiles:

```bash
mise install aqua:tmux/tmux-builds@3.7c
```

The area validates `C-Space`, `C-b`, `tmux-256color`, the portable help binding,
and real parsing with the selected runtime. Parsing uses a temporary HOME and
explicit temporary socket, does not require a network namespace, and removes
both after validation.

Dotfiles does not install tmux or plugins. It does not inspect or manage
`~/.tmux/plugins`, `~/.tmux/resurrect`, sockets, sessions, or other tmux runtime
state. Removal acts only on exact Ubuntu package links.

Manual Windows Terminal key handling remains documented in
[Windows Terminal](../environments/windows-terminal.md).
