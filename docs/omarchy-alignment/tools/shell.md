# Shell

## Accepted Design

Bash with Starship is the primary configured Omarchy-oriented shell workflow.
Bootstrap configures it but never changes the login shell. Existing zsh remains
a transitional default area and escape hatch during migration.

## Native Omarchy Bash

- Retain the installed Omarchy Bash baseline.
- Add a guarded source block to the native regular `.bashrc`.
- Keep the shared personal source outside the refresh-managed file.
- Reapply the block after a supported native config reinstall.
- Leave native Starship configuration authoritative.

The attachment follows the idempotency and drift rules in
[Deployment](../deployment.md#native-omarchy-attachments).

## Generic Bash Load Order

Assemble selected portable components rather than sourcing the full upstream
Bash tree:

```text
interactive guard
portable environment prelude
upstream shell behavior
upstream aliases
upstream tmux helpers required by ic/ix/icx
portable mise, Starship, zoxide, and fzf initialization
upstream Readline settings
personal-tools integration
shared personal layer
host-local layer
```

Specific behavior:

- Source upstream `shell` and `aliases` unchanged.
- Source the upstream tmux function file because stock aliases depend on
  `tdl`.
- Do not initially activate drive-formatting or transcoding functions.
- Reproduce portable portions of upstream `envs` without UWSM or desktop-only
  paths.
- Reimplement upstream `init` path detection for generic distributions.
- Initialize mise before zoxide and other mise-provided commands.
- Load upstream input settings with `bind -f` instead of owning `.inputrc`.
- Use the stock synchronized Starship TOML.
- Set `EDITOR` and `VISUAL` to Neovim only when each variable is unset.
- Provide compatibility commands such as mapping Ubuntu `batcat` behavior to
  `bat`.
- Keep stock aliases defined even when optional target commands are absent.
- Add a guarded login hook so SSH and login Bash reach `.bashrc` exactly once.
- Keep the personal Bash preference layer otherwise empty initially.

## fzf And zoxide

fzf should provide Omarchy-equivalent completion, history search, file
selection, and preview behavior using portable path detection. zoxide should
provide Omarchy's `cd` and `zd` behavior.

Initialization must be capability-guarded. Missing optional commands may reduce
available behavior but must not make an interactive shell fail.

## Mise And Personal Tools

Shell startup activates the shared mise fragments after environment setup and
before mise-provided tools are initialized. Executable ownership and locking
are defined in [Deployment](../deployment.md#mise).

Worktrunk has a separate capability-guarded initialization hook when available.
Vite+ remains project-owned through project mise files; the Bash migration must
not add a global Vite+ environment hook. Stage 5 does not install, update,
configure, or inspect OpenCode or `opencode-openai-codex-auth`, and unrelated
shell deployment preserves the existing executable, configuration, plugins,
and authentication state.

No new Bash or personal-tool hook may install, update, authenticate, or use the
network during shell startup. The canonical exceptions are documented in
[Deployment](../deployment.md#operation-and-network-policy).

## Transitional zsh

zsh is the current daily shell and remains available as a behaviorally frozen
escape hatch while the stock Omarchy Bash experience is evaluated. It
receives no new features during the migration; converging the two setups or
retiring zsh is a deliberate post-migration decision recorded in
[Deferred Work](../deferred.md#shell-convergence).

Its existing first-start Zinit bootstrap remains allowed and may use the
network. Once initialized, ordinary zsh startup must not update plugins or use
the network implicitly. This exception is transitional behavior, not a model
for the new Bash stack.

- Include the existing zsh configuration in the default profile.
- Preserve Zinit, Powerlevel10k, aliases, keybindings, and functions
  behaviorally.
- Do not make zsh the login shell automatically.
- Move host-local content and change its source path to
  `~/.config/dotfiles/local/zsh_aliases.zsh` in one preflighted transaction.
  The shared zsh config sources that exact file only when it is readable;
  removal never deletes this host-local file.
- Allow shared mise fragments to provide managed tools.
- Do not reconcile zsh aliases or keybindings with Bash during this migration.

Installing zsh configuration and changing a login shell remain separate,
explicit actions.

## Non-Goals

- Sourcing Omarchy's Arch, Wayland, UWSM, Kitty, or desktop machinery wholesale
  on generic systems.
- Importing existing zsh customizations into Bash.
- Defining new personal Bash preferences before stock behavior is evaluated.
- Adding new installation or update behavior to shell startup.
- Taking ownership of a host's `.inputrc`.

## Acceptance Criteria

- Interactive Bash loads each component once in the documented order.
- Non-interactive Bash exits without interactive initialization or output.
- Login, SSH, and nested interactive scenarios do not double-source `.bashrc`.
- Native Omarchy retains its baseline and Starship ownership.
- Generic systems expose stock aliases, required helper functions, Starship,
  fzf, zoxide, and mise behavior.
- Missing optional commands do not break startup, and aliases remain defined.
- `EDITOR` and `VISUAL` preserve existing user values.
- WSL-specific behavior is additive to the generic profile.
- Bash startup performs no network access, installation, update, or
  authentication.
- Transitional zsh retains only its documented first-start fetch and remains
  available without changing the login shell.
