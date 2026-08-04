# Linux / WSL host (Stow areas via bootstrap)

1. Preflight without mutation: `~/dotfiles/bootstrap.sh --check --area <area>`.
2. Apply: `~/dotfiles/bootstrap.sh --area <area>`. A first WSL shell
   deployment must apply `bash`, smoke-test from a separate process, then
   apply `zsh` — never both in one run.
3. Provisioning is the only online step and must be explicit:
   `~/dotfiles/bootstrap.sh --provision --area <area>`.
4. Done when `--check` passes cleanly and the focused suites in
   `tests/README.md` pass. Run `tests/run.sh` for its cross-cutting triggers.

Contracts: `docs/deployment.md` and `docs/tools/`.

## Native Omarchy

Omarchy-installed files are authoritative; only common and personal attachments deploy on top. Read `docs/environments/omarchy.md` before touching anything baseline-adjacent.
