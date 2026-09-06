# Toucan Runtime Backend

The personal tap-preferred/200 ms left firmware was built and flashed on
2026-09-06; right firmware was untouched. All 168 bindings matched after save
and a left power cycle. Functions 3:0 and 3:41 are None; Nav+X is transparent
again and Nav+Z still unlocks Studio. Initial user-reported checks passed;
longer typing and separate BLE/battery tests remain. Keep both halves USB powered.
See [LIVE-TEST.md](LIVE-TEST.md) for dated results and runtime backups, and
[FIRMWARE-PREP.md](FIRMWARE-PREP.md) for retained images and recovery limits.

## Files And Identity

`keymap.json` is a native ZMK Studio `get_keymap` response-shaped document, not
a universal layout schema. Bindings use firmware-local behavior IDs and ZMK
HID-usage parameters. Physical positions are zero-based, in the captured layout
order: three rows of twelve (left six then right six), then six thumbs.

Target: USB `1d50:615e`, revision `0305`, interface `00`, CDC ACM,
serial `93F54E4E61BA5937`; RPC name `Toucan`, serial bytes `k/VOTmG6WTc=`.
VID/PID alone is insufficient. Every recorded USB identity property and RPC
identity is checked. Exact geometry and behavior metadata are checked before
mutation. This does not prove a PCB revision or firmware commit.
Validation also protects thumbs (except the approved Functions 41 correction),
the ordinary Base bottom row, Nav mouse bindings, and Nav+Z unlock against
accidental edits to the desired document.

`../snapshots/toucan/` contains byte-exact original JSON, wire evidence, decoded
references, and original hash manifest. It is never used as a routine backup
directory. The original `snapshot.json` has an intentional historical blocked
status; `metadata.json` completes the successful advertised-behavior extraction.

## Intended Mapping

- Stable IDs remain Base 0, Symbols 2, Nav 1, Functions 3, in that display order.
  No add/remove/reorder/reset or physical-layout setter is implemented.
- Base A/S/D/F hold left Super/Alt/Shift/Ctrl; H/J/K/L hold right
  Ctrl/Shift/Alt/Super. Their tap letters and every other Base binding remain.
- Bottom-row Base letters remain ordinary key presses. Middle thumbs remain
  momentary Nav (position 37) and Symbols (40). Existing conditional Functions
  activation is preserved, not recreated. The user confirmed both thumbs reach
  ADJ; runtime getters cannot expose or verify its compiled definition.
- Nav preserves mouse-right at G (17), Mouse5 at V (28), Mouse4 at B (29),
  Studio unlock at Z (25), and existing arrows/paging. A/S/D/F become immediate
  Super/Alt/Shift/Ctrl for dragging and navigation chords.
- Nav M/comma (32/33), directly below Down/Up, use consumer VolumeDown/Up
  `0x000c00ea`/`0x000c00e9`, not the original keyboard-page volume usages.
  Nav N (31) deliberately stays transparent; period (34) keeps right Shift.
- Symbols preserves the original digit/symbol rows and N/M/comma/period
  `_ - + =`. The accidental A/S/D/F outputs at physical Z/X/C/V (25..28)
  become explicit None. B stays transparent. Peripheral modifiers remain.
- Base top-left is apostrophe; Symbols top-left is grave; Symbols left bracket
  position 24 provides direct tilde. These are US HID legends, host-layout dependent.
- Functions F1..F10 remain at positions 13..22. Previously approved and applied:
  F11/F12 move from Q/W to R/T (4/5), making room for Bluetooth profiles 1/2/3
  at Q/W/E (1/2/3), parameters 0/1/2. USB/BLE output selection is assigned at
  backslash/Y (6/7). Previous/next Bluetooth profile actions at 32/33 remain.
  Selecting an empty profile allows pairing; no bond-clear bindings are added.
- Functions positions 0 and 41 are explicitly None, replacing invalid momentary
  target `458795` and unknown behavior 0. The backend permits only this exact
  correction, with normal behavior-metadata validation. Historical anomalies
  may be verified unchanged but cannot be restored over corrected live bindings.

The F11/F12 relocation, freed Symbols keys, output controls, and Nav N/period
decision passed the prior layout review. The two None corrections are now
deployed and verified; no other layout changes were made permanent.

## API For Coordinator

Load `backend.py` with `importlib.util.spec_from_file_location`; no package
installation or import-path changes needed. All public values are JSON-compatible.

```python
desired = backend.load(backend.HERE / 'keymap.json')
presence = backend.status()               # sysfs only; no serial open or RPC
backend.validate(desired)                 # offline against original capabilities
changes = backend.diff(backend.original(), desired)  # offline original-state diff
with backend.SerialRPC(port, writable=False) as rpc:
    state = backend.snapshot(rpc)          # getters only, checks identity/unlocked
    changes = backend.diff(state, desired) # pure, complete live prevalidation
    result = backend.verify(rpc, desired)  # raises on mismatch or unsaved state
```

For explicit apply, open `SerialRPC(port, writable=True)` and call
`backend.apply(rpc, desired, backup_root=optional_path)`. The coordinator must
obtain explicit layout-review acknowledgment before opening a writable session;
the low-level `apply` API remains unchanged. No API opens a connection
implicitly except the standalone CLI. Mock clients need only
`call(subsystem, method, value=True)` returning decoded protobuf field values.
Lock enums and setter response enums are numeric (unlocked 1, setter success 0);
save success is exactly `{"ok": true}`.

`diff` returns a list of `{method, request, before}` objects. Requests are native
`set_layer_props` or `set_layer_binding` arguments, always using **stable IDs**.
`apply` returns `{changed, changes, backup}`; a no-op has no backup and no writes.
`verify` returns `{"verified": true, "changes": []}`. Failures raise `Error`,
`OSError`, `ValueError`, or `TimeoutError`; coordinator must return nonzero.
On apply failures after backup, `Error` includes the recovery directory.

`status(*, sysfs_root='/sys')` returns `{present, devices, source, studio_state}`.
Each device has `{sysfs_path, usb_identity, ports}`. It inventories matching USB
VID/PID/serial through sysfs, without udev subprocesses, serial opens, or RPCs.
An absent target returns `present: false`, an empty device list, and success;
permission/I/O errors are not reported as absence. Presence is not proof of
Studio access, exclusivity, unlocked state, or applied layout. Status inventories
all matches, independently of `--port`, and does not load the desired keymap.

Standalone (repository root):

```sh
python3 keyboards/toucan/backend.py status
python3 keyboards/toucan/backend.py check
python3 tests/keyboard_toucan_test.py
python3 keyboards/toucan/backend.py snapshot
python3 keyboards/toucan/backend.py diff
python3 keyboards/toucan/backend.py verify
```

The final three commands are read-only device operations.
`snapshot` prints JSON to stdout; callers choose a private output file.
`diff --from-snapshot PATH` uses a complete backend snapshot offline, not the
incomplete historical first-session snapshot. `--keymap`, `--port`, and
`--backup-root` are explicit overrides. No-argument usage cannot mutate hardware.
The standalone `apply` command requires `--ack-layout-review` for an explicit
user-authorized run. Without it, main returns nonzero before loading the keymap
or opening any connection. The flag acknowledges review; it does not weaken
identity, access, backup, pending-state, or readback checks.

## Safety And Recovery

Linux only; Python 3.9+ standard library plus existing `udevadm`. No network,
global packages, protobuf runtime, serial library, sudo, firmware flashing,
behavior execution, bond clearing, settings reset, discard, or software unlock.

The transport takes a cooperative nonblocking `flock` and `TIOCEXCL`, then
audits visible processes with the **same effective UID** for pre-existing device
handles, including this process's other handles. Effective UID comes from the
second UID value in `/proc/PID/status`, not the real UID or proc-directory owner.
It refuses before sending RPCs on detected same-user competitors or malformed
effective-UID records. Inaccessible process status (even for unrelated processes),
same-user FD tables or FD links produce one scoped warning per open session on
stderr, not refusal; snapshot JSON on stdout remains valid. Visible FDs are still
checked. Other-effective-UID FD tables are never inspected. Close browser,
Studio, VIA and other device clients before connecting.

This is an explicitly scoped access guard, **not system-wide exclusivity**.
`TIOCEXCL` blocks new nonprivileged opens, not pre-existing handles; `flock` only
coordinates cooperating clients. Pre-existing hidden same-user or other-user handles, privileged
processes that bypass kernel exclusivity, processes hidden by proc namespaces or
mount policy, and UID/FD-transfer races are outside the audit's guarantee.
Noncooperating races remain possible. Do not run sudo, elevate privileges, or
stop unrelated credential/system services to remove a warning.

Serial termios is restored on close; DTR/RTS are not explicitly toggled. A CDC
open/close may have firmware-dependent effects; no reset behavior is assumed.
Frames have bounded time/size, byte escaping, request-ID checks, notification
handling, and explicit RPC error checks. Unknown protobuf fields are skipped;
unsupported wire types and malformed/ambiguous responses fail closed.

Apply validates the **entire** desired layout and live capabilities first,
refuses pending-unsaved state, writes mode-0600 `before.json`, `desired.json`,
and `diff.json` under a new mode-0700 private run directory, fsyncs them and
directory entries, rechecks lock/keymap/unsaved state, then sends only differences.
Default root: `$XDG_STATE_HOME/keyboards/toucan` or
`~/.local/state/keyboards/toucan`. Custom roots must already be private if they
exist. RAM readback must match before save. Save acknowledgment, full post-save
snapshot/readback, and no-unsaved status must all pass before reporting success.

Setters are not transactional. Failure stops without automatic save, discard,
rollback, or retry. `failure.json` lists attempted and acknowledged operations;
the last attempt may have reached the board even if its acknowledgment was lost.
A save error can mean partial persistence. A process kill/power loss may prevent
the failure record; the prewritten backup and complete planned diff remain.
Keep a fallback keyboard. Inspect the saved `before.json`, current read-only
snapshot, and failure record before choosing recovery. The backup's `keymap`
can be reviewed as a restore target, but pending changes must first be resolved
deliberately outside this tool. It never saves or discards another session for you.
Original anomalous bindings cannot be promised restorable through setters.

## Provenance And Limits

`protocol.py` is an independently written, minimal wire-schema/codec implementation
of the inspected ZMK Studio definitions and framing from
<https://github.com/electronicmaterialsoffice/zmk-studio-cli> at
`3b3bce06230e497905ab22b343ca866081aa2b07` (MIT, ZMK Contributors).
Inspected sources: `zmk_studio_cli/proto/{studio,core,keymap,behaviors,meta}_pb2.py`,
`rpc/send_request_raw.py`, and `rpc/special_characters.py`. No upstream executable
code or external dependencies are vendored. BehaviorBinding.behavior_id and
physical geometry are **sint32** (zigzag); layer IDs and parameters are uint32.
The tests decode all 34 captured protobuf responses and compare the original
JSON, not merely this codec's own round-trip output.

Setter/save interpretation also consulted the temporary snapshot's captured
`reference-keymap_subsystem.c` and `reference-keymap.c`. Those were retrieved
from upstream main, not pinned device firmware, and are not treated as proof of
original installed behavior. The original firmware commit remains unknown.
Live setters, save/readback and power-cycle persistence passed; dated evidence
is in the live record. No postflash flash-memory hash was obtained.

Runtime metadata advertises Mod-Tap/Layer-Tap but does not expose hold-tap term,
flavor, quick-tap, idle/positional settings, or underlying compiled bindings.
The personal left build was inspected as tap-preferred/200 ms; getters cannot
attest that compiled setting. RGB and battery-display actions are not advertised.
Initial typing, modifiers, layers, trackpad and display checks passed by user
report. Longer typing and separate BLE/battery acceptance remain pending.
Intermittent first-read `invalid protobuf tag` failures remain unresolved;
successful complete retries used unchanged framing, decoder and access checks.
USB management does not prove which host output transport is selected.

Toucan USB/BLE host pass-through is active. Coordinate any host recovery with
the firmware map; duplicate home-row processing can mask firmware results.
The backend never deploys keyd or participates in normal dotfiles deployment.
