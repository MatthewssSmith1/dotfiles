# tmux

## Accepted Design

Use the pinned untouched Omarchy tmux configuration as the baseline. Add only a
minimal portability adapter and a shared persistence layer.

Generic load order:

```text
pinned untouched Omarchy baseline
generic portability adapter
personal persistence declarations
TPM initialization
```

Native Omarchy retains its regular installed config and receives a guarded
source hook to the same shared persistence file.

## Baseline Behavior

The baseline owns the interaction model, including:

- `C-Space` primary prefix and `C-b` fallback.
- Omarchy pane, window, and session controls.
- Vi copy mode.
- Mouse support.
- One-based pane and window indexes.
- Truecolor and extended-key behavior.
- Stock status bar and titles.
- Stock `prefix + q` reload command.

Do not migrate current custom copy-mode overrides, `status-keys vi`, or
`set-clipboard external` during the initial alignment.

## Persistence Layer

Preserve:

- TPM.
- tmux-resurrect.
- Assistant Resurrect.
- tmux-continuum.
- Five-minute automatic saves.
- Automatic restoration.
- Existing data beneath `~/.tmux/resurrect/`.

Keep plugin declarations separate from the upstream baseline. Continuum must
be last among plugin declarations, and guarded TPM initialization must be the
final tmux action.

## Plugin Lifecycle

Record each plugin repository URL, exact commit, and expected directory in
`tmux-plugins.lock`. The Stage 7 explicit plugin-provisioning operation installs
missing locked plugins and verifies existing checkouts. Updating a pin is a
separate reviewable operation; ordinary configuration apply stays offline.

tmux startup must never clone, update, or otherwise access the network.

## Runtime And Terminals

The baseline is written for tmux 3.5. The intended owner is a distro package
at 3.5 or newer, or locked `aqua:tmux/tmux-builds` through mise
(see [Deployment](../deployment.md#executable-ownership)).
Only explicit provisioning apply may fetch the fallback. No-area `--provision`
includes tmux as a platform foundation even while its configuration area is
framework-only; explicit `--area tmux` remains refused until the tmux payload
stage lands.

Interim behavior on hosts that have not converged is tolerate-and-report.
The baseline config loads and works on older tmux, but unknown options print
a startup notice and stay inert:

- `allow-passthrough` requires tmux 3.3 (OSC passthrough is not configured
  below that).
- `extended-keys-format` requires tmux 3.5.

Ubuntu 24.04's distro tmux is 3.4, so an unconverged host shows exactly the
one `extended-keys-format` notice; Ubuntu 22.04's tmux 3.2a shows both.
`bootstrap --check` must report a tmux older than 3.5 and name the inert
options.

Runtime rules:

- Validate that the `tmux-256color` terminfo entry exists and is usable
  (provided by `ncurses-base` on Ubuntu 22.04 and newer).
- Validate the selected client executable and version outside tmux, the version
  and resolved owner of any existing server, and the version on the isolated
  test socket separately. On Linux, resolve the server PID reported by tmux
  through `/proc/<pid>/exe`; if ownership cannot be proven, report a transition
  whenever an active server exists.
- Preserve both documented prefixes.
- Do not automatically reload or restart a running tmux server.
- Report `prefix + q` after deployment when a running server may need reload.
- Validate effective behavior with an isolated tmux socket.

Reloading configuration cannot replace a running server process. After a tmux
executable or owner transition, bootstrap reports the mismatch and leaves the
server untouched even when old and new versions compare equal. The user saves
sessions, exits clients, deliberately runs
`tmux kill-server`, starts the approved binary, and verifies restoration. This
manual restart is part of the tmux stage gate.

## Windows Terminal Clients

Windows Terminal is a client-terminal concern, not a host profile: the
guidance applies whenever the user types into Windows Terminal, whether the
shell is WSL or an SSH session into a generic VPS. Full guidance, including
the required `settings.json` unbinds, lives in
[Windows Terminal](../../environments/windows-terminal.md).

Summary of the policy to validate:

- One required manual unbind: `alt+enter` (Windows Terminal's fullscreen
  toggle otherwise consumes the `M-Enter` split binding). Recommended
  unbinds: `alt+left/right/up/down`, `alt+shift+left/right`, and
  `ctrl+alt+left`.
- Protocol analysis predicts that two bindings will be unavailable on the
  targeted Windows Terminal/tmux versions and should be documented rather than
  rebound if validation confirms it: `M-S-Enter`
  (indistinguishable from `M-Enter` without a mutually supported extended-key
  protocol) and `M-Escape` (reserved by Windows). Use the baseline's prefix
  equivalents instead. Host-local rebinds remain available later if the gap
  hurts in practice.
- Truecolor and OSC 52 clipboard are expected to need no terminal-side change;
  validate them separately before closing the gate.

The manual verification checks are part of the tmux stage gate in
[the implementation plan](../plan.md#7-tmux-migration). The fuller
integration (tracked settings fragment, verification script) is recorded in
[Deferred Work](../deferred.md#fuller-windows-terminal-integration).

## Open Question

Select and record exact commits for TPM, tmux-resurrect, Assistant Resurrect,
and tmux-continuum before plugin provisioning is implemented.

## Non-Goals

- Preserving custom bindings that override the Omarchy interaction model.
- Cloning or updating plugins from tmux startup.
- Editing Windows Terminal settings automatically.
- Reloading or restarting the user's active server during deployment.
- Duplicating the upstream baseline in the personal layer.

## Acceptance Criteria

- Generic and native profiles expose the expected prefixes, indexes, bindings,
  status behavior, and key protocol.
- A fresh server starts with zero configuration errors on tmux 3.5 or newer,
  and with exactly the documented notices on older versions.
- The native baseline remains a regular Omarchy-owned file.
- The generic baseline matches the verified pinned snapshot.
- Plugin order is deterministic, Continuum is last, and TPM initializes last.
- Every plugin checkout matches `tmux-plugins.lock`.
- Startup works offline and performs no plugin mutation.
- Existing Resurrect state remains intact.
- Deployment does not disturb a running tmux server.
- An executable or owner transition reports an active old server and the
  manual restart procedure; restoration is verified after that restart.
- An isolated socket test validates effective options and key tables.
- Real-session restoration receives a final manual check.
