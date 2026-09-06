# Keyboards

The intended unified layout for Toucan, Air60 V2, and generic keyboards on
Omarchy. **Toucan and Air60 applied; generic changes remain staged.** See the
[Toucan session record](toucan/LIVE-TEST.md) and
[Air60 test deployment](air60/LIVE-TEST.md). This is a separate module, not a
Stow package or a `dotfiles.sh` area.

- [SPEC.md](SPEC.md): authoritative design, exact positions, proposed choices.
- [reference.html](reference.html): standalone offline visual reference; open
  directly or use `./keyboards/keyboard reference` from the repository root.
- Native implementations: [Toucan](toucan/README.md), [Air60](air60/README.md),
  [keyd](keyd/README.md).
- [Original snapshots](snapshots/README.md): immutable evidence, not live state.

## Commands

Python 3.10+ standard library on Linux. No downloads, global packages, browser
configuration UI, build toolchain, or firmware flashing required. Toucan also
uses installed `udevadm`; keyd validation uses installed `keyd check`.

```sh
./keyboards/keyboard                     # help, no device access
./keyboards/keyboard status              # sysfs presence + host file state only
./keyboards/keyboard check               # original hashes + native validation
./keyboards/keyboard reference           # open the local HTML
./keyboards/keyboard snapshot toucan     # getter-only private snapshot
./keyboards/keyboard diff toucan         # full read-only preflight + proposed edits
./keyboards/keyboard verify toucan       # persisted current readback comparison
./keyboards/keyboard snapshot air60
./keyboards/keyboard diff air60
./keyboards/keyboard verify air60
./keyboards/keyboard diff keyd            # staged payload, original device remaps
./keyboards/keyboard apply air60 --help   # backend-specific flags
```

Use `--port` for Toucan or `--device /dev/hidrawN` for Air60. Snapshot/diff/verify
need a connected, accessible device and no competing Studio/VIA/browser client.
Getter-only means no configuration setters; it still sends protocol requests.
Status does not open either device. Permission changes are never automatic.

`snapshot` stores successful device reads under
`$XDG_STATE_HOME/keyboards/<target>/snapshot-*/snapshot.json` (default
`~/.local/state`), with private permissions. keyd snapshots retain all current
files plus metadata in the same target's state tree. Apply creates its own durable
pre-change backup and diff. Runtime backups never replace checked-in originals.

`check` is offline, not proof of connected firmware capability. It also invokes
the keyd parser and detects host file conflicts. `verify` compares configuration;
it cannot establish typing behavior or Air60 power-cycle persistence.

## Apply Lifecycle

1. Review the spec, diagrams, native diffs, and the open choices below.
2. Keep a fallback keyboard available; USB-power both Toucan halves. Close
   Studio/VIA clients and obtain fresh snapshots. Check installed firmware
   provenance, especially Air60's vendor-specific custom codes.
3. Explicitly apply one device, using its backend's documented flags. Toucan
   requires `--ack-layout-review`; Air60 additionally requires its pinned
   `--firmware-profile` acknowledgment. This acknowledges reviewed evidence,
   not a firmware identity discovered by VIA.
4. Verify readback and, where appropriate, controlled reconnect persistence.
   Do not mistake duplicate keyd processing for firmware behavior.
5. Start target-specific keyd **test pass-through** using reviewed readback and
   transport identity evidence, as described in [keyd](keyd/README.md).
   An unused transport must be explicitly recorded and remain disconnected.
6. Test physical output: typing/rolls, all modifiers, layer release, mouse buttons,
   volume, symbols, Fn, and both Air60 switch positions. Record results and
   configuration hashes separately from historical snapshots.

No implicit apply-all, flashing, resets, bond clearing, firmware updates,
automatic elevation, or keyd changes during device apply. Failed device updates
stop with recovery records, not automatic retries or rollback writes.

Keyd installation is deliberately privileged and separate. It requires
`--execute --ack-layout-review --state /var/lib/keyboard-keyd`; migration adds
target-specific acknowledgment and evidence. Review and check unprivileged
first. From an interactive terminal, invoke the reviewed command using `sudo`;
use `pkexec` only when no terminal is available. Do not grant passwordless
privileges to this user-writable checkout. All other commands run unprivileged.

## Capability Status

| Target | Implemented and offline-tested | Still requires hardware verification |
| --- | --- | --- |
| Toucan | Captured protobuf fixtures, stable IDs, Mod-Tap assignment, save/readback, backup/failure handling | Setter acceptance, persistence, hold-tap feel, mouse/consumer output, conditional Functions |
| Air60 | Pinned VIA v12 wire/custom codes, native matrix layout, immediate-write/readback handling | Installed firmware provenance, live protocol, setters, reconnect persistence, Plain/Enhanced typing |
| keyd | Installed v2.6 parser, staged layouts, conflict checks, test-migration gate, backup/recovery | Device/transport selection, physical output, migration completion |

Toucan hold-tap timing and conditional-layer definitions are not runtime getters.
Air60's exact build cannot be attested by VIA; its compiled Mac-mode NKRO policy
cannot be changed with this tool. No arbitrary firmware compatibility is claimed.
See device READMEs for pinned evidence and concurrency limits.

## Review Before Applying

- Air60's approved distinct modes: **Mac = Enhanced layer 0, stock NKRO off;
  Windows = Plain layer 3, stock NKRO on.** Enhanced preserves the previous
  layer 3 exactly, including center END = F9 for Omarchy voxtype. Plain has
  immediate letters, physical Tab/Caps/left Shift and LAlt/RAlt around Space;
  center INS/CMD/END = quote/Delete/left bracket. Ordinary Ctrl/Super and the
  moved right-hand layout remain. Fn and overlays are unchanged. Hardware
  behavior still requires separate verification.
- Toucan F11/F12 move to R/T on Functions to free Q/W/E for Bluetooth profiles.
  Air60 F11/F12 remain at P/rightmost backslash, plus its number-row F keys.
- Toucan Symbols' former bottom-row A/S/D/F outputs become None. Nav mouse
  bindings remain. Toucan Nav N stays transparent and period stays right Shift;
  Air60/generic Nav N/period are inert.
- Two anomalous Toucan Functions bindings are retained untouched, not endorsed
  as working controls. Preflight refuses to restore them through unsupported
  setters. Toucan Functions retains its existing layer-specific thumb behavior.
- Air60 Utilities layer 7 retains useful device/media controls. Destructive
  reset/DFU/factory-test bindings are omitted. Generic Nav's existing A/S/D/F
  dual-role modifiers and G=Enter remain explicit device differences.

## Maintenance And Tests

Update native files, `SPEC.md`, and HTML together. The HTML deliberately duplicates
presentation data rather than imposing a universal generation schema. Preserve
snapshot bytes and hashes; capture new evidence separately.

```sh
python3 -B -m unittest discover -s tests -p 'keyboard*_test.py'
bash tests/contract_test.sh
bash tests/cli_test.sh
```

These tests do not touch device settings or `/etc/keyd`. Behavioral testing and
recovery instructions remain target-specific. Future build/flash support, if
needed, belongs here, never in normal dotfiles deployment.
