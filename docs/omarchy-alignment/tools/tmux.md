# tmux

## Stage Status

Stage 7 now has implemented area lifecycle, migration, native attachment,
isolated parser validation, active-server inspection, exact plugin
provisioning, parser fixtures, and adversarial automated tests. Its payload and
schema-backed locks are committed, and `manifests/areas.tsv` marks tmux `ready`
after those gates passed. It is now default-selected. A fresh host still needs
the explicit `--provision --area tmux` lifecycle described below so the runtime
and plugin closure converge before configuration preflight and apply.
WSL operational acceptance completed on Windows Terminal 1.24.11911.0 after
the live server transition, Resurrect restore, and terminal checks passed.

## Accepted Design

Generic Linux and WSL use the pinned, byte-identical Omarchy configuration as a
private baseline. The XDG entrypoint is a dispatcher owned by the generic
package; it is not the upstream snapshot. Runtime order is explicit and does
not depend on Stow package order:

1. Pinned untouched Omarchy baseline.
2. Generic portability adapter.
3. Optional WSL adapter, which intentionally contains no commands.
4. Common TPM declarations and managed Assistant Resurrect hooks.
5. Guarded TPM initialization, as the final command in common persistence.

There is no tmux host-local layer. tmux startup does not clone, update, clean,
or otherwise mutate plugin checkouts.

## Load Paths

| Owner | Managed source | Home target | Purpose |
|-------|----------------|-------------|---------|
| `generic/tmux` | `packages/generic/tmux/.config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | XDG dispatcher |
| `upstream/tmux` | `packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf` | `~/.config/dotfiles/upstream/tmux/tmux.conf` | Private byte-identical baseline |
| `generic/tmux` | `packages/generic/tmux/.config/dotfiles/tmux/generic.conf` | `~/.config/dotfiles/tmux/generic.conf` | Generic adapter |
| `wsl/tmux` | `packages/wsl/tmux/.config/dotfiles/tmux/wsl.conf` | `~/.config/dotfiles/tmux/wsl.conf` | Command-empty WSL adapter |
| `common/tmux` | `packages/common/tmux/.config/dotfiles/tmux/persistence.conf` | `~/.config/dotfiles/tmux/persistence.conf` | TPM plugins, managed Assistant Resurrect hooks, persistence options, and final TPM guard |

The dispatcher sources the optional WSL path with `source-file -q`. Generic
hosts do not deploy that path; WSL hosts deploy the command-empty file. No
package has a duplicate Stow destination.

Native Omarchy keeps its regular Omarchy-owned
`~/.config/tmux/tmux.conf`. Stage 7 appends one state-recorded, guarded source
attachment after the native baseline:

```tmux
# >>> dotfiles tmux >>>
if-shell 'test -r "$HOME/.config/dotfiles/tmux/persistence.conf"' \
  'source-file "$HOME/.config/dotfiles/tmux/persistence.conf"'
# <<< dotfiles tmux <<<
```

The common file's own final command performs guarded TPM initialization. The
attachment uses the deployment engine's regular-file marker, identity,
rollback, drift, and exact-removal rules. A supported refresh may reattach a
completely absent exact block; malformed, duplicate, partial, modified, or
nested markers refuse. Native Omarchy never receives the private generic
baseline, generic adapter, WSL adapter, dispatcher, or a host-local source.

## Baseline Behavior

The baseline owns the interaction model, including:

- `C-Space` primary prefix and `C-b` fallback.
- Omarchy pane, window, and session controls.
- Vi copy mode.
- Mouse support.
- One-based pane and window indexes.
- Truecolor and extended-key behavior.
- Stock status bar and titles.
- Stock `prefix + q` reload command, which reloads the XDG dispatcher on
  generic and WSL and the native file on Omarchy.

Do not migrate the legacy custom copy-mode overrides, `status-keys vi`, or
`set-clipboard external`. Do not duplicate or edit the upstream baseline to add
personal behavior.

## Persistence Layer

Common persistence preserves:

- TPM.
- tmux-resurrect.
- Assistant Resurrect save/restore scripts through managed Resurrect hooks.
- tmux-continuum.
- Five-minute automatic saves.
- Automatic restoration.
- Existing data beneath `~/.tmux/resurrect/`.

TPM is first, Resurrect follows it, and Continuum is the final TPM plugin so no
later plugin replaces its status hook. The Assistant Resurrect checkout is
explicitly `managed-hooks`, not TPM-loaded. Common persistence sets only
`@resurrect-hook-post-save-all` and `@resurrect-hook-post-restore-all` to
HOME-resolved, quoted invocations of the locked checkout's
`scripts/save-assistant-sessions.sh` and
`scripts/restore-assistant-sessions.sh`. Its `tmux-assistant-resurrect.tmux`
entrypoint is never executed because it installs Claude hooks in
`~/.claude/settings.json` and an OpenCode plugin under
`~/.config/opencode/plugins/`. This deployment does not install either. The
guarded TPM invocation is the final non-comment command in
`persistence.conf`. A missing or non-executable TPM entrypoint is skipped at
startup; deployment checks diagnose the incomplete closure before startup is
considered converged.

## Plugin Lock

[`manifests/tmux-plugins.lock.json`](../../../manifests/tmux-plugins.lock.json)
is the machine-readable source of truth and conforms to
[`schemas/tmux-plugin-lock-v1.schema.json`](../../../schemas/tmux-plugin-lock-v1.schema.json).
Array order is checkout/persistence order. Filtering it to `loading: "tpm"`
is the exact TPM declaration/load order; the `managed-hooks` row is not passed
to TPM.

| Checkout | Loading | Repository | Commit | Expected directory |
|----------|---------|------------|--------|--------------------|
| TPM | TPM | `https://github.com/tmux-plugins/tpm` | `e261deb1b47614eed3400089ce7197dc68acc4eb` | `~/.tmux/plugins/tpm` |
| tmux-resurrect | TPM | `https://github.com/tmux-plugins/tmux-resurrect` | `cff343cf9e81983d3da0c8562b01616f12e8d548` | `~/.tmux/plugins/tmux-resurrect` |
| tmux-assistant-resurrect | managed hooks only | `https://github.com/timvw/tmux-assistant-resurrect` | `9ea274cc91b64ad0360f1a827950381e637f39a7` | `~/.tmux/plugins/tmux-assistant-resurrect` |
| tmux-continuum | TPM, last | `https://github.com/tmux-plugins/tmux-continuum` | `0698e8f4b17d6454c71bf5212895ec055c578da0` | `~/.tmux/plugins/tmux-continuum` |

An exact local closure has all and only the declared checkout directories,
each at its locked commit with the exact `origin`, a clean worktree and index,
and an EUID-owned, non-symlinked checkout path. The plugin root and every path
component bootstrap manages must also be EUID-owned real directories rather
than symlinks. A missing checkout, unexpected entry, dirty checkout, repository
mismatch, non-Git object, linked worktree, unsafe owner, symlinked path, or
unreadable metadata is not an exact closure.
All read-only Git inspection runs with `GIT_OPTIONAL_LOCKS=0`; exact validation
must leave every checkout's `.git/index` identity, bytes, mode, size, and mtime
unchanged.

Exactness is also receipted at
`~/.local/state/dotfiles/provisioning/v1/tmux-plugins.json`. The retained,
EUID-owned regular mode-`0600` file conforms to
[`schemas/tmux-plugin-receipt-v1.schema.json`](../../../schemas/tmux-plugin-receipt-v1.schema.json)
and records schema version 1, the SHA-256 identity of the complete lock, and
the lock-ordered `id`, canonical repository, commit, tree, and directory for
every plugin. Ordinary apply and check require both the active receipt and its
exact filesystem closure; an unreceipted checkout is not implicitly trusted.
Receipt lock hashes are accepted only when they equal the active lock. There is
no reviewed historical lock catalog, so every non-active hash refuses rather
than treating the checkouts as unreceipted adoption candidates. Plugin
directories `.` and `..` are invalid in both lock and receipt contracts.

## Plugin Lifecycle

The only plugin provisioning apply interface is:

```bash
bootstrap.sh --provision --area tmux
```

TPM's own install, update, and clean operations are outside the supported
provisioning contract. No-area provisioning installs the tmux executable
foundation but does not provision plugins. The area-scoped check form may
report the same plan but remains offline and non-mutating.

Ordinary apply and both check forms stay offline and refuse unless the exact
plugin closure already exists. They never repair, fetch, checkout, reset, or
clean a plugin. Startup is also offline and performs no closure mutation.

Explicit plugin provisioning preflights the complete closure and prints every
repository, commit, and destination before its first network-capable command.
It may create a missing checkout or replace clean drift only. A clean drifted
checkout must still prove the expected repository, ordinary checkout topology,
safe ownership, no symlinked managed path, and an empty worktree and index.
An exact unreceipted checkout can be adopted only by this explicit operation;
adoption performs no clone but writes the complete receipt after revalidation.

One narrowly reviewed origin migration is available only through that explicit
command. A clean ordinary checkout whose sole origin is exactly
`https://git::@github.com/<locked-owner>/<locked-repo>` is classified
`normalize-origin` for the same lock row. Provisioning fetches and verifies the
locked commit in canonical staging, quarantines the old checkout, and installs
the staged `https://github.com/<locked-owner>/<locked-repo>` replacement; it
never edits origin metadata in place. Ordinary checks continue to refuse the
legacy origin. Any different owner, repository, syntax, extra remote, URL, or
fetch/push ambiguity refuses without mutation.

Provisioning assembles and verifies replacements in private same-filesystem
staging, then replaces eligible checkout directories transactionally. It does
not change an existing checkout in place. All refusal conditions are detected
before mutation; a replacement failure restores the pre-operation directories.
Unexpected entries, dirty or ambiguous repositories, linked worktrees,
non-owned objects, and symlinked managed paths refuse rather than being moved,
deleted, reset, or repaired. Updating a lock pin is a separate reviewed manifest
change.

A refusal concerning plugin-root ownership, topology, or unexpected closure
entries refuses every plugin action. Such a plan has no pending network fetch;
it is not partially reclassified from paths beneath an untrusted root. The
ordered `@plugin` declarations are parsed from actual persistence assignments
and compared exactly with lock order and identity; comments or surrounding
text containing a locked declaration are not evidence of that declaration.

All required exact fetches finish and verify before checkout mutation. Each
stage starts as an empty repository with the canonical HTTPS `origin`, disables
interactive prompting, credential helpers, askpass, and non-HTTPS Git
protocols, and performs one depth-1 fetch of only the locked commit. Eligible old
directories are identity-rechecked and quarantined, staged directories install
without clobber, and the complete new closure is reverified. An atomic
compare-and-swap receipt write is the transaction commit point. Before that
point, failure removes only unchanged transaction-installed directories,
restores unchanged quarantines without clobber, and leaves the old receipt in
place. Concurrently changed objects are retained; inability to complete that
rollback exits with status 70. After the receipt commit, old quarantines are
discarded only after another identity check. Fetch and checkout never recurse
into or fetch submodules, so TPM's test gitlinks remain represented solely by
the clean parent worktree.

`bootstrap.sh --remove --area tmux` removes only managed configuration,
attachment content, and area state. It retains `~/.tmux/plugins/` and
`~/.tmux/resurrect/` exactly as declared by the lock.

## Runtime And Terminals

The baseline targets tmux 3.5 or newer. Generic and WSL use a distro package
when suitable or the locked `aqua:tmux/tmux-builds` fallback through mise. Only
explicit runtime-tool provisioning may fetch that fallback; plugin provisioning
uses the separate area-scoped interface above.

Interim behavior on hosts that have not converged is tolerate-and-report. The
baseline loads on older tmux, but explicitly sourcing or reloading it reports
unknown-option notices and leaves those options inert:

- `allow-passthrough` requires tmux 3.3.
- `extended-keys-format` requires tmux 3.5.

Ubuntu 24.04's tmux 3.4 shows the `extended-keys-format` notice; Ubuntu 22.04's
tmux 3.2a shows both. Checks report a tmux older than 3.5 and name the inert
options.

### Real Parser Fixtures

Parser compatibility uses the real distro executables, not a version-printing
wrapper and not an assumed-equivalent static build. The test-only 3.2a input is
the official Ubuntu Jammy package locked in
[`manifests/tmux-parser-fixtures.lock.json`](../../../manifests/tmux-parser-fixtures.lock.json),
which conforms to
[`schemas/tmux-parser-fixture-lock-v1.schema.json`](../../../schemas/tmux-parser-fixture-lock-v1.schema.json).
The accepted package is `tmux 3.2a-4ubuntu0.2` for `amd64`, archive size
`428388`, SHA-256
`b51865a24b78d68459421ee68e1e35d53112d9c08c4e823b241141342efb21dd`.
Its extracted `usr/bin/tmux` is mode `0755`, size `971320`, SHA-256
`6684c9b0bd4af08461f9e476e0abee9c3f08daa5d55ed6fb7c663c000e09f83d`,
and reports `tmux 3.2a`.

Noble's `libtinfo` package relationship prevents safely installing this old
Jammy package. It is always extracted with `dpkg-deb --extract` and must never
be passed to `dpkg`, `apt`, or `apt-get` for installation. Prepare an external
fixture cache explicitly:

```bash
mkdir -p /tmp/opencode/stage7-tmux-parser-cache
scripts/tmux-parser-fixtures sync --root /tmp/opencode/stage7-tmux-parser-cache
scripts/tmux-parser-fixtures verify --root /tmp/opencode/stage7-tmux-parser-cache
```

Sync prints the complete HTTPS URL, destination, package identity, extractor,
archive identity, executable identity, and managed root before its first
download. Downloads stay under the caller-selected cache. Extraction occurs in
same-parent staging; only the cache's `tmux-parser-fixtures-v1` managed-root
link is atomically switched after all checks pass. The EUID-owned cache root is
locked through an already-open directory descriptor: sync takes an exclusive
lock and verify takes a shared lock. Managed chains reject nested symlinks and
foreign ownership, publication compares the managed-link identity captured at
preflight, and interrupted publication never removes the active generation.
Old generations are intentionally retained because a concurrent reader may
still hold a path through one. `verify` and `validate-lock` are offline.
Bootstrap, startup, and normal tests never invoke sync.

The opt-in real-version gate uses the extracted 3.2a fixture, distro
`/usr/bin/tmux` 3.4, and the retained static 3.7b executable. Fixture and binary
locations can be selected by arguments or the `TMUX_PARSER_*` environment
overrides: `TMUX_PARSER_FIXTURE_ROOT`, `TMUX_PARSER_TMUX_32A_BIN`,
`TMUX_PARSER_TMUX_34_BIN`, `TMUX_PARSER_TMUX_37B_ROOT`, and
`TMUX_PARSER_TMUX_37B_BIN`.

```bash
tests/stage7_tmux_parser_compatibility_test.sh \
  --fixture-root /tmp/opencode/stage7-tmux-parser-cache \
  --tmux-3.7b-root /tmp/opencode/stage7-tmux-parser-cache/static-3.7b
```

This gate requires the direct package-owned `/usr/bin/tmux` for 3.4 and the
manifest-identity 3.7b executable, never a version wrapper. It requires a
denied-network namespace and creates a unique socket and
temporary home for every parser. It explicitly sources the committed
dispatcher because tmux suppresses configuration diagnostics while creating a
server with `-f`. The source operation must report only
`allow-passthrough` and `extended-keys-format` on 3.2a, only
`extended-keys-format` on 3.4, and no diagnostics on 3.7b; all three then prove
the core effective options and bindings. The aggregate suite validates the
lock/schema and offline operation but intentionally does not require an
external fixture. Requesting the real gate without one fails with the exact
sync command needed to prepare it.

Runtime validation must:

- Prove that `tmux-256color` terminfo exists and is usable.
- Validate the selected client executable, active server-reported version and
  process owner/path, and isolated test-socket version independently.
- Query only PID and `#{version}` read-only over each supported default/current
  socket. Then read `/proc/<pid>/exe` only for owner/path identity; never execute
  that path. Existing EUID-owned sockets that cannot answer are still reported.
- Preserve both documented prefixes.
- Never automatically reload, restart, or kill a running server.
- After apply, report whether active ownership differs or is unqueryable. For
  that case, instruct the user to save, exit clients, run `tmux kill-server`,
  start the selected owner, and restore, without executing those actions.
- If the active server has the selected owner but may have legacy config,
  advise `tmux source-file ~/.config/tmux/tmux.conf` once, not `prefix + q`.
- Validate effective options and key tables on an isolated socket.
- Require a denied-network user/network namespace for production check and
  apply validation; inability to create it fails closed.

The observable active-server scope is deliberately bounded: the default socket
derived from `TMUX_TMPDIR` (or `/tmp`) and the absolute current-client socket in
`TMUX` when distinct. Stage 7 does not enumerate arbitrary socket directories.
Inspection sends only `display-message -p` to those sockets and never reloads,
restarts, or kills them. Isolated validation uses a unique explicit test socket;
cleanup must prove that server is gone before deleting its socket and home. A
failed cleanup retains and reports the recovery root.

Reloading configuration cannot replace a server process. After an executable
or owner transition, bootstrap reports the mismatch and leaves the server
untouched even when versions compare equal. The user saves sessions, exits
clients, deliberately runs `tmux kill-server`, starts the approved binary, and
restores. A same-owner server instead receives the one-time explicit
`source-file` instruction. These manual transitions are part of the later tmux
gate; bootstrap never performs them.

## Windows Terminal Clients

Windows Terminal is a client concern for WSL and SSH sessions alike. All eight
documented Windows Terminal keybindings are required manual unbinds:
`alt+enter`, all four Alt arrow keys, both Alt+Shift horizontal arrow keys, and
`ctrl+alt+left`. The complete `settings.json` fragment and checks live in
[Windows Terminal](../../environments/windows-terminal.md).

Protocol analysis predicts that `M-S-Enter` and `M-Escape` remain unavailable
on the targeted versions. Use `prefix + h` and `prefix + x`; do not add a WSL
or host-local rebind. Truecolor, mouse behavior, and OSC 52 clipboard export
were validated separately on Windows Terminal 1.24.11911.0.

## Non-Goals

- Preserving bindings that override the Omarchy interaction model.
- Cloning or updating plugins from tmux startup or ordinary apply.
- Editing Windows Terminal settings automatically.
- Reloading or restarting an active server during deployment.
- Adding WSL-specific or host-local tmux behavior.
- Duplicating or modifying the upstream baseline in another layer.

## Readiness Gate

Readiness changed only after automated gates covered package closure and
duplicate targets; baseline byte identity and offline
upstream verification; config parsing on tmux 3.2a, 3.4, and 3.5 or newer;
isolated options and key tables; exact plugin lock/order; denied-network apply,
check, and startup; every provisioning refusal and rollback path; native
attachment refresh/removal; active-server mismatch reporting; and retained
plugins and Resurrect data. Manual Windows Terminal and real-session restore
checks remained separate rollout gates and are now complete for WSL.

Acceptance requires generic, WSL, and native profiles to expose the baseline
behavior and common persistence without startup mutation, duplicate Stow
targets, native baseline replacement, WSL behavior, or a host-local layer.
