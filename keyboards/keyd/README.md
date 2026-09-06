# keyd Backend

Nothing here is deployed by Stow or `dotfiles.sh`. Toucan and Air60 pass-through
were installed separately; see the [Toucan](../toucan/LIVE-TEST.md) and
[Air60](../air60/LIVE-TEST.md) live records. Generic staging has not been deployed.
Python standard library; no downloads. Installed `keyd v2.6.0` advertises
`check`, and the staged configuration passed that real parser. Other builds
without advertised `check` fail closed. `keyd -c` is not treated as validation.

## CLI/API

The main CLI can invoke `python3 -B keyboards/keyd/backend.py COMMAND [OPTIONS]`.
Commands: `status` (default), `check`, `diff`, `snapshot`, `apply`, `verify`.
Exit 0 means the requested operation completed; 1 means blocked/failure.
`status` and `apply` print JSON; `diff` prints unified diff; snapshot prints its
directory. `check` and `verify` print a scoped statement, never a hardware claim.
All diagnostics go to stderr. Importable `main(argv)` returns the same exit code.

`--target DIR` defaults to `/etc/keyd`; read-only commands and snapshot can inspect
temporary fixtures. `--state DIR` defaults to `$XDG_STATE_HOME/keyboards/keyd`
(or `~/.local/state/keyboards/keyd`). Snapshots are new 0700 directories containing
0600 files and metadata/hashes. They never overwrite tracked original evidence.

`check` validates the selected staged payload and detects live conflicts. It does
not require files already installed. `verify` additionally requires exact managed
file bytes. Neither proves daemon-loaded mappings, transport selection, hold-tap
feel, or emitted keys. `status` is observational, not a preflight approval.
`diff --migrate DEVICE` can preview pass-through without granting migration.

## Staging

Top-level `.conf` files describe the intended endpoint. By default the backend
installs only the new generic layout, retaining original device profiles with
private `legacy-home-row-mods` and `legacy-shared-layers` includes. This prevents
generic changes from silently altering firmware devices. Seven files are managed;
the two legacy includes are rendered from immutable snapshots, not separate copies.

The general backend is still a **whole-tree installer**, even with `--migrate
air60`; it is unsuitable for the current Air60-only live change, which must preserve
Toucan and generic files byte-for-byte. That change uses a separately guarded
one-file install, not this backend's `apply`. No scoped installer is provided here.

Generic right-hand physical positions are shifted: physical `Y U I O P` emit
`backslash Y U I O`, physical `H J K L semicolon` emit `semicolon H J K L`, and
physical `N M comma dot slash` emit `slash N M comma dot`. Physical left/right
bracket emit P/backslash (matching Air60 moved keys); physical backslash remains
backslash. Layer bindings use physical positions, not remapped output names.
Z/X/C/V/**B** hold Nav; the five right bottom-row positions hold Symbols.
Symbols + physical `1..0 minus equal` gives F1..F12. Physical grave stays grave;
Symbols+Tab also gives grave and Symbols+left Shift gives tilde. Alt keys remain
Backspace/Delete, Caps/Escape remain swapped, physical Shifts emit brackets.
Home-row timing preserves current 200ms (Shift 180ms), not engine equivalence.
Nav N/period outputs are explicitly inert. These are reviewable intended choices;
apply requires layout-review acknowledgment. Symbols operators require another
trigger held; physical rollover/release testing remains outstanding.

## Migration Gate

For each device, select `--migrate DEVICE --ack-migration DEVICE --evidence FILE`.
This starts target-specific **test pass-through**, not a claim of completed
firmware behavior testing. Prerequisites are a persisted keymap readback matching
the intended firmware layout, its hash/date/record, and identity evidence for each
used transport. Physical tests happen **after** pass-through removes duplicate
host processing. No `firmware_verified` boolean or pre-migration physical test
record is required. Evidence is an attestation, not an automatic hardware detector.
Never manufacture it from this example. Required shape:

```json
{
  "toucan": {
    "profile_sha256": "sha256 of intended toucan.conf",
    "firmware_sha256": "sha256 of persisted firmware keymap readback",
    "readback_at": "ISO date/time of persisted readback",
    "readback_record": "path/reference proving intended keymap readback after persistence",
    "transports": {
      "usb": {
        "status": "verified",
        "keyd_id": "k:1d50:615e:982e9afd",
        "identity_record": "path/reference to live keyd identity inspection"
      },
      "bluetooth": {
        "status": "not-used",
        "reason": "Explicit operator decision; do not connect this transport",
        "disconnected": true,
        "keyd_ids": ["k:1d50:615e:b1063934"]
      }
    }
  }
}
```

Toucan requires USB/Bluetooth entries; Air60 requires USB/Bluetooth/receiver.
At least one used transport must have `status: verified` and an `identity_record`;
verified here means identity, not key behavior. A verified entry accepts either
one matching `keyd_id` (the existing form) or a nonempty `keyd_ids` list of unique,
valid intended selectors, never both fields. Unknown IDs and duplicates are rejected.
The existing `identity_record` must cover all listed interfaces, for example a journal
record showing all of them. Per-transport records and migration acknowledgments
remain required.
Every intended selector must be accounted for: either verified on a used transport
or explicitly listed in a not-used transport's `keyd_ids` array. Not-used entries
require a nonempty `reason` and `disconnected: true`; they must stay disconnected.
An empty/omitted array accounts for no selectors. Reserving an existing selector
does not claim its transport correspondence has been verified.

Air60 live sysfs/proc/journal evidence identifies four USB keyboard-class interfaces:

| Selector | Interface |
| --- | --- |
| `k:19f5:3255:e3746a94` | NuPhy NuPhy Air60 V2, boot keyboard input0 |
| `k:19f5:3255:0d7157bb` | NKRO named Keyboard input2 |
| `k:19f5:3255:a10585ca` | System Control input2 |
| `k:19f5:3255:921cd195` | Consumer Control input2 |

All four are in the intended pass-through profile. The currently ignored Mouse
interface stays ignored; no mouse selector is added. Air60's `transports` example
(inside its own hash/readback-bound device record):

```json
{
  "usb": {
    "status": "verified",
    "keyd_ids": [
      "k:19f5:3255:e3746a94",
      "k:19f5:3255:0d7157bb",
      "k:19f5:3255:a10585ca",
      "k:19f5:3255:921cd195"
    ],
    "identity_record": "path/reference to sysfs/proc/journal evidence covering all four USB interfaces"
  },
  "bluetooth": {
    "status": "not-used",
    "reason": "Historical selector reserved pending identity inspection; keep Bluetooth disconnected",
    "disconnected": true,
    "keyd_ids": ["k:19f5:3246:838051e9"]
  },
  "receiver": {
    "status": "not-used",
    "reason": "Receiver identity unknown; keep receiver disconnected during USB migration",
    "disconnected": true
  }
}
```

The historical Bluetooth selector is preserved, not newly verified. Bluetooth and
the unknown receiver must stay disconnected during USB migration.
Unknown transports are not covered by generic fallback. Verify keyd IDs live before adding new selectors
to the intended profile. Original known selectors remain preserved. Air60 Plain
and Enhanced both bypass keyd during test pass-through.

After the explicit apply, complete physical tests with a fallback keyboard available:
Base typing/rolls, home-row chords, release/stuck modifiers, Nav/Symbols/Functions,
operators while another trigger is held, and reconnect/persistence. Test Air60
Plain and Enhanced. Record results, date, tested transports, firmware readback hash,
and profile hash in a separate human completion record. A failed test is not a
completed migration: stop rollout, keep untested transports disconnected, and
review coordinated firmware/host recovery. Merely restoring old host mappings
over new firmware can reintroduce double processing. No extra state framework or
completion command is added: `verify` stays file-level, and `runtime_verified`
stays false even after a human records completion.
Implicit reversal of a migrated profile is refused, even if `--migrate` is omitted.

## Privilege Boundary

No command elevates itself. `apply` requires explicit `--execute`,
`--ack-layout-review`, and root, with fixed target `/etc/keyd` and
`--state /var/lib/keyboard-keyd`. First review source, diff, evidence, and run
unprivileged check. A later separately authorized operator can use `sudo` from an
interactive terminal (or `pkexec` without a terminal) to invoke the reviewed
Python backend with those flags. Do not run the general dotfiles CLI as root.
Do not grant passwordless elevation to this user-writable checkout.
No privileged invocation was performed during implementation.

Apply locks the directory against other backend instances, rejects symlinks,
unknown overlapping `.conf` profiles, unexpected managed contents, and unmanaged
include consumers. It validates the entire desired payload with flattened local
includes, backs up the complete current directory and metadata, validates recovery
configs, rechecks for concurrent edits, installs only changed files atomically as
root:root 0644, verifies bytes, reloads keyd, and checks service activity. Matching
files cause no writes or reload. Other administrators must not edit/reload keyd
concurrently; keyd has no atomic multi-file/daemon transaction or loaded-map getter.

On write/readback/reload failure, changed files are restored (including original
owner/mode and absence), followed by a recovery reload. Concurrent edits are not
overwritten. `recovery.json` records failure and unresolved restoration errors;
failure always exits nonzero, even if restoration succeeds. Reload success is
not proof of correct physical outputs. Backups and `intended.diff` survive failure.

For manual recovery, use the printed backup directory's `manifest.json`: verify
hashes before copying only affected managed files back with recorded owner/mode;
remove only newly installed managed files absent from that manifest. Never copy
the backup's JSON/diff records into `/etc/keyd`, never replace unrelated files.
Validate the restored complete config using supported `keyd check`, then explicitly
reload and test a fallback keyboard. If recovery reports concurrent changes or a
reload failure, stop automation and review rather than blindly retrying.

## Tests

`python3 -B tests/keyboard_keyd_test.py` uses temporary directories and mocked
validation/reload commands. No real privilege command or live mutation occurs.
`python3 -B keyboards/keyd/backend.py check` is a real read-only parser check.
