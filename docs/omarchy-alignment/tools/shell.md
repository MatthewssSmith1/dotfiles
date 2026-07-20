# Shell

## Accepted Design

Bash with Starship is the primary configured Omarchy-oriented shell workflow.
Bootstrap configures it but never changes the login shell. Existing zsh remains
a transitional escape hatch during migration; the account login shell remains
unchanged. Bash and zsh are ready after the Stage 6 implementation and isolated
gates passed; WSL live-host acceptance passed after the ordered rollout and
smoke checks.

## Native Omarchy Bash

- Retain the installed Omarchy Bash baseline.
- Append an exact guarded source block to the native regular `.bashrc`; the
  block sources only the common personal dispatcher after the native baseline.
- Keep the shared personal source outside the refresh-managed file.
- Reapply only when a supported native refresh removed the complete recorded
  block. Partial, duplicate, nested, malformed, or modified markers block
  reapply.
- Do not add a login-file attachment unless fixture-backed research proves the
  native login path requires one.
- Leave native Starship configuration authoritative.

The attachment follows the idempotency and drift rules in
[Deployment](../deployment.md#native-omarchy-attachments).

## Generic And WSL Attachments

Generic and WSL deployment does not Stow over, move, delete, or discard an
unrelated regular `.bashrc`, `.bash_profile`, `.bash_login`, or `.profile`.
Bootstrap prepends a byte-preserving managed block to `.bashrc`. In
non-interactive Bash the block returns immediately. In interactive Bash it
sources the managed dispatcher and then returns from `.bashrc`, deliberately
bypassing the inactive legacy remainder while preserving every original byte.
Removal deletes only the exact recorded block and restores the original bytes
and mode.

For login Bash, bootstrap records and reuses the first existing path in Bash's
normal precedence order: `.bash_profile`, `.bash_login`, then `.profile`. If
none exists, it creates a regular `.bash_profile` containing only the managed
login block and records that it created the file. The prepended block uses
POSIX-compatible syntax, acts only when `BASH_VERSION` is set, sources
`.bashrc`, and returns; another shell reading `.profile` continues through its
unrelated content. Removal restores a pre-existing file byte-for-byte, or
deletes an exact attachment-only `.bash_profile` only when state proves
bootstrap created it. A later higher-precedence file does not change the
recorded selection.

Attachment placement is profile data, not a guess based on startup-file
contents. Symlinks, non-regular files, unsafe ownership, and ambiguous markers
are refused before mutation. Because shell startup files cannot validly contain
NUL bytes and shell variables cannot preserve them, any attachment destination
containing NUL is explicitly refused before mutation rather than rewritten.

## Managed Bash Load Order

Assemble selected portable components rather than sourcing the full upstream
Bash tree. Generic and WSL use this exact observable order:

```text
1. interactive-shell guard
2. unexported per-process exactly-once guard
3. portable environment and deterministic PATH
4. pinned upstream shell behavior
5. pinned upstream aliases
6. pinned upstream tmux helpers required by ic/ix/icx
7. portable mise activation
8. Starship initialization unless TERM=dumb
9. zoxide initialization
10. fzf completion, history search, file selection, and preview integration
11. pinned Readline settings through bind -f
12. WSL adapter when the WSL profile is selected
13. guarded Worktrunk integration
14. shared personal layer
15. readable host-local Bash layer
```

The WSL adapter is an explicit additive boundary after all generic portable
initialization and before common personal integrations. It initially has no
runtime settings and must not invent terminal, `WSLENV`, browser, clipboard, or
Windows executable behavior. Generic omits this layer. Native Omarchy runs only
runtime layers 13 through 15 after the dispatcher guards and its native
baseline. The exactly-once guard is not exported, so re-sourcing in one process
is a no-op while a nested Bash initializes normally.

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
- Set `EDITOR` and `VISUAL` to `nvim` only when each variable is unset; preserve
  explicitly empty as well as nonempty values. Apply the same unset-only rule
  to `SUDO_EDITOR` (defaulting to the resulting `EDITOR`), `BAT_THEME`
  (`ansi`), `MANROFFOPT` (`-c`), and `MANPAGER`
  (`sh -c 'col -bx | bat -l man -p'`).
- Add the managed private `~/.local/share/dotfiles/bin` once at the protected
  PATH precedence point. Its executable `bat` and `fd` wrappers select distro
  `bat` or `batcat`, and `fd` or `fdfind`, without resolving recursively to
  themselves. They are not interactive aliases because FZF previews and
  `MANPAGER` use child processes.
- Preserve the pinned alias file byte-for-byte. Its `ls`, `lsa`, `lt`, and
  `lta` aliases exist only when `eza` is available while it is sourced, and its
  `cd` alias and `zd` function exist only when `zoxide` is then available.
  Other unconditional aliases remain defined even when their eventual target
  command is absent; invocation may fail normally.
- Build duplicate-free PATH precedence from protected provisioned launchers,
  the private wrappers, the existing OpenCode directory when present, and
  standard system paths. Do not add NVM, Deno, Vite+, or legacy `~/.fzf/bin`.
- Keep the personal Bash preference layer otherwise empty initially.

Non-interactive Bash returns before any managed environment mutation or
initializer. Interactive SSH uses the same managed path; non-interactive SSH
commands do not. Every runtime initializer is capability-guarded so an optional
command disappearing after deployment causes no startup failure or diagnostic.

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
Its initializer child runs with `MISE_OFFLINE=1` in a denied-network user
namespace after `setpriv` removes every capability and enables
no-new-privileges. If that isolation cannot be established at runtime, startup
silently skips the optional integration rather than running it unrestricted;
check requires the isolation primitives to be usable.
Vite+ remains project-owned through project mise files; the Bash migration must
not add a global Vite+ environment hook. NVM, Deno, legacy `~/.fzf.bash`, and
the duplicate legacy Worktrunk initializer are also retired from managed Bash.
Stage 5 does not install, update,
configure, or inspect OpenCode or `opencode-openai-codex-auth`, and unrelated
shell deployment preserves the existing executable, configuration, plugins,
and authentication state.

The final layer is the readable real, untracked
`~/.config/dotfiles/local/bash.sh`; bootstrap sources but does not own or delete
it. The initial WSL file sources Cargo's `~/.cargo/env` only when readable, adds
and initializes rbenv only when `~/.rbenv/bin` and the command exist, and adds
`~/.elan/bin` only when that directory exists. It must remain silent when those
tools are absent, must not move protected mise-owned commands behind host-local
paths, and contains no Node, NVM, Deno, Vite+, installer, updater,
authentication, or network behavior.

No new Bash or personal-tool hook may install, update, authenticate, or use the
network during shell startup. The canonical operation policy is documented in
[Deployment](../deployment.md#operation-and-network-policy).

## Interactive Ownership Validation

Check and apply run the protected-command resolver inside a controlled managed
interactive Bash that starts through the dispatcher, does not show a prompt,
and returns machine-readable results. This closes the visibility gap for
aliases and non-exported functions while retaining checks for exported
functions, every PATH candidate, user-local and project-local shadows, and mise
resolution from controlled directories. It inspects rejected objects without
executing them, rejects additional unapproved candidates even when the expected
owner is first, validates the private `bat` and `fd` wrappers through their
ultimate distro-owned commands, and distinguishes required deployment
dependencies from optional commands missing after deployment.

The executable-owner pass never sources host-local code. Host-local aliases and
functions are inspected separately from a copied fixture HOME under a user,
mount, and denied-network namespace: mandatory command sentinels remain active
and the real HOME is bind-mounted read-only. After namespace and mount setup,
`setpriv` drops all capabilities and sets no-new-privileges before copied code
runs, preventing it from remounting the real HOME. Failure to establish or prove
that isolation is blocking with package and namespace remediation. Side effects
using `$HOME` remain inside the disposable fixture, and network-command attempts
fail validation. `unshare`, `mount`, and `setpriv` from `util-linux` are required
for Bash apply and check.

## Transitional zsh

zsh is the current login shell and remains available as a behaviorally frozen
escape hatch while the stock Omarchy Bash experience is evaluated. History, vi
mode, key bindings, Powerlevel10k, Zinit, plugins, completion styles, zoxide,
fzf, mise, Worktrunk, aliases, and OpenCode PATH behavior receive no new
features during the migration. Converging the two setups or retiring zsh is a
deliberate post-migration decision recorded in
[Deferred Work](../deferred.md#shell-convergence).

The retained zsh behavior uses distro-owned fzf completion and key-binding
files directly. It does not source the legacy host installer hook or add
`~/.fzf/bin`; this is an ownership correction rather than a new shell feature.

The only startup network exception is the existing first start when no readable
Zinit entrypoint exists; it may clone the Zinit core. Plugin installation is not
part of that exception. Plugins load only when the complete reviewed local
plugin directory closure already exists, and Zinit receives a local-only Git
protocol policy while loading it. Once the entrypoint exists, ordinary zsh
startup cannot clone, update, synchronize, or install plugins. Mise activation
is explicitly offline, and Worktrunk shell initialization runs in a denied-network
namespace. This exception is transitional behavior, not a model for Bash.

- Do not change the login shell or invoke `chsh`.
- Relocate a recognized legacy `.zsh_aliases.local` link to the real untracked
  `~/.config/dotfiles/local/zsh_aliases.zsh` in the same transaction that makes
  managed `.zshrc` source the new path when readable. An absent destination may
  be created; a byte-identical regular destination may be reused. A divergent,
  symlinked, or non-regular destination, an unrecognized source, or a
  reappeared old source after completed migration is refused without merging.
  With neither source nor completed migration, deploy without fabricating
  local content. Copy source bytes atomically while retaining the old source,
  create a collision-free retained backup and ledger record, and remove the old
  link only after the active source is validated.
- Retire global Vite+ initialization from managed `.zshrc` and remove only the
  reviewed Vite+ comment/source block from host-owned `.zshenv`. Preserve Cargo,
  OpenCode, and every unrelated byte; refuse partial or ambiguous matches;
  journal the original for rollback; and retain a collision-free backup and
  migration-ledger record. The Vite+ installation remains untouched, and
  `--remove` does not restore the retired hook.
- Refuse a NUL-bearing `.zshenv` before mutation. Retained migration backups
  are installed without replacement races at mode `0600`; check/reapply verify
  their EUID owner, mode, and exact ledger fingerprint.
- Do not create, move, source, remove, or record `.zshrc.local`.
- Do not reconcile zsh aliases or keybindings with Bash.

These local-path and Vite+ migrations are the only approved exceptions to the
zsh behavioral freeze.

## Removal And Retention

Bash removal preflights every attachment and link, removes only exact recorded
blocks and package links, restores pre-existing generic/WSL startup files and
modes byte-for-byte, and deletes an attachment-only login file only when state
proves bootstrap created it. It retains provisioning, host-local Bash, and
migration records.

zsh removal deletes only recorded package links and area state. It retains the
central local aliases file, Zinit and plugins, history, migration ledger and
backups, and the durable Vite+ retirement. It never restores the old local
alias link or changes the login shell.

## Non-Goals

- Sourcing Omarchy's Arch, Wayland, UWSM, Kitty, or desktop machinery wholesale
  on generic systems.
- Importing existing zsh customizations into Bash.
- Defining new personal Bash preferences before stock behavior is evaluated.
- Adding new installation or update behavior to shell startup.
- Taking ownership of a host's `.inputrc`.
- Adding `.zshrc.local` behavior.

## Acceptance Criteria

- Interactive Bash loads each component once in the documented order.
- Non-interactive Bash exits without interactive initialization or output.
- Login, SSH, and nested interactive scenarios do not double-source `.bashrc`.
- Native Omarchy retains its baseline and Starship ownership.
- Generic systems expose stock aliases, required helper functions, Starship,
  fzf, zoxide, and mise behavior.
- Missing optional commands do not break startup, and alias presence matches
  the unchanged pinned source's capability checks.
- `EDITOR` and `VISUAL` preserve existing user values.
- WSL-specific behavior is additive to the generic profile.
- Bash startup performs no network access, installation, update, or
  authentication.
- Transitional zsh retains only its documented missing-Zinit first-start fetch,
  applies only the two approved migrations, and remains available without
  changing the login shell.
