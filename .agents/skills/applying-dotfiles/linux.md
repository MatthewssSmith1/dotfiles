# Ubuntu / Omarchy host (Stow areas via dotfiles)

1. Preflight without mutation: `~/dotfiles/dotfiles.sh check <area>`.
2. Apply: `~/dotfiles/dotfiles.sh apply <area>`.
3. For `nvim`, Ubuntu apply can install missing packages through scoped `sudo apt-get install` and provision user-owned tools. On Omarchy, if packages are missing, run the reported `sudo pacman -Syu <missing packages>` deliberately before retrying apply; apply does not upgrade the system. For other areas, follow manual dependency guidance.
4. Done when `check` passes cleanly and the focused suites in `tests/AGENTS.md` pass. Run `tests/run.sh` for its cross-cutting triggers. `check` stays read-only and local.

Contracts: `docs/deployment.md` and `docs/tools/`.

## Native Omarchy

Omarchy-installed files are authoritative; only common and personal attachments deploy on top. Read `docs/environments/omarchy.md` before touching anything baseline-adjacent.

Desktop first adoption is not an ordinary apply: obtain explicit confirmation before `omarchy refresh config hypr/input.lua`, then apply `desktop`. Never use the broader Hyprland refresh as a substitute, and do not restart the shell.
