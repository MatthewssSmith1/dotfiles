# Air60 V2 Native VIA Layout

**Applied for testing on 2026-09-06.** All 816 keymap cells matched after the
253-cell update and independent readback. Air60-only host pass-through is active.
Physical typing, switch behavior and power-cycle persistence remain pending.
See [LIVE-TEST.md](LIVE-TEST.md) for backups, identities and results.
No firmware was flashed. Statements below about operations not run refer to the
initial offline implementation, before this live session.

`layout.json` is a native VIA export: eight flat, row-major layers of 102
matrix cells. `prepare_layout.py` records the exact offline migration from the
hash-checked original; it is not a universal layout schema or firmware generator.
Its default prints JSON; `--write` regenerates only this directory's layout.
The backend reads `layout.json` directly and does not run the migration script.

## Layout Choices

| Layer | Role | Activation |
| --- | --- | --- |
| 0 | Enhanced | Physical Mac switch, stock NKRO off |
| 1, 2 | Retired, transparent physical positions | No remaining references |
| 3 | Plain | Physical Windows switch, stock NKRO on |
| 4 | Nav | Enhanced hold Z/X/C/V/B |
| 5 | Symbols | Enhanced hold slash/N/M/comma/period |
| 6 | Functions | Dedicated Fn at matrix `[2,14]`, both modes |
| 7 | Device Utilities | Hold Fn, then slash; retains side-light/media controls |

Layer 7 is deliberately **Utilities, not spare**: it preserves useful controls
without crowding the unified Functions layer. All overlays are above base 3.
Layers 1/2 have no active references and contain only transparent/absent cells.

Position reference uses **emitted Base keys**, not original keycap legends.
Enhanced preserves the previous layer 3 exactly, now on layer 0:

```text
Esc    1 2 3 4 5 - 6 7 8 9 0 = Backspace
'      Q W E R T Tab \ Y U I O P \
Esc    A S D F G Caps ; H J K L Enter
[      Z X C V B F9 / N M , . ] Fn
Ctrl Super Backspace    Space    Delete Left Down Up Right
```

The duplicated backslashes are distinct: `[2,7]` is the moved left-of-Y
backslash; `[2,13]` is the rightmost one. The former is Symbols `^`; the latter
is Functions F12. The alpha-row leftmost apostrophe is `[2,0]`, not the separate
number-row Escape `[0,0]`. Backspace/Delete stay `[5,2]`/`[5,9]`, immediately
left/right of Space `[5,6]`. Existing peripheral Ctrl, Super, Caps, brackets,
arrows, Tab and unusual F9 position remain deliberate carry-forwards.
Center INS `[2,6]` = Tab, CMD `[3,6]` = Caps, END `[4,7]` = F9 for
Omarchy voxtype. Physical Tab/Caps/left Shift emit quote/Esc/left bracket.

Plain (layer 3) retains the moved right-hand layout but restores immediate
dedicated modifiers and physical Tab/Caps/left Shift:

```text
Esc    1 2 3 4 5 - 6 7 8 9 0 = Backspace
Tab    Q W E R T ' \ Y U I O P \
Caps   A S D F G Delete ; H J K L Enter
LShift Z X C V B [ / N M , . ] Fn
Ctrl Super LAlt          Space    RAlt Left Down Up Right
```

Plain center INS `[2,6]` = quote, CMD `[3,6]` = Delete, END `[4,7]` =
left bracket. LAlt `[5,2]` and RAlt `[5,9]` flank Space. Ctrl/Super
`[5,0]`/`[5,1]` remain ordinary in both modes. Plain has no MT/LT or
Nav/Symbols access; it is not stock QWERTY. Both modes retain Fn `MO(6)`.

Plain strips every letter MT/LT: letters type immediately. Enhanced uses
A/S/D/F = left Super/Alt/Shift/Ctrl; H/J/K/L = right Ctrl/Shift/Alt/Super.
Original mixed left/right MT syntax actually encodes a right-side modifier in
QMK's five-bit modifier field; the desired strings spell that out explicitly.

| Base Positions | Nav | Symbols | Functions |
| --- | --- | --- | --- |
| Q W E R T | fall through | ! @ # $ % | BLE1 BLE2 BLE3 RF USB |
| moved backslash Y U I O | fall through, Home PgDn PgUp End | ^ & * ( ) | fall through except O = battery |
| A S D F G | Super Alt Shift Ctrl, G falls through | 1 2 3 4 5 | F1 F2 F3 F4 F5 |
| semicolon H J K L | fall through, Left Down Up Right | 6 7 8 9 0 | F6 F7 F8 F9 F10 |
| N M comma period | disabled, VolumeDown, VolumeUp, disabled | underscore minus plus equals | RGB slower/faster on N/M; others fall through |
| P / rightmost backslash | fall through | fall through | F11 / F12 |

Functions also has F1-F12 across the twelve physical number-row positions
`[1,1]` through `[1,12]` (physical order, not the moved Base digit order).
Bluetooth profiles are user-facing 1/2/3, via CUSTOM(3/4/5), not QMK layer IDs.
No number-row Bluetooth duplicates; that row retains twelve function keys.
These device-specific Functions positions are intentional: Air60 puts F11/F12
on P/rightmost backslash (plus number-row duplicates), Toucan proposes R/T to
free Q/W/E for Bluetooth, and generic keyd uses Symbols plus the physical
number row for all F1-F12. They do not require identical activation mechanisms.

Nav and Symbols put grave on `[2,0]`; Symbols and Functions put direct shifted
grave (tilde on a US host layout) on `[0,0]`. Functions also has grave on `[2,0]`.
Symbols also puts direct tilde on physical left Shift `[4,0]`, matching Toucan.
Plain's apostrophe moves to `[2,6]`; number-row Escape remains unchanged.
Overlays 4/5/6/7 retain their exact bytes and physical coordinates: grave
stays at `[2,0]`, RGB brightness down at `[4,0]`, not the relocated punctuation.
Shifted symbols are native `LSFT(KC_*)`, never Unicode injection.

Unassigned physical overlay positions intentionally fall through, including
the slash Symbols trigger and Z/X/C/V/B Nav triggers. Nav N/period explicitly
emit nothing, not accidental legacy letters. Symbols A/S/D/F are digits, not
modifiers. Once Symbols is active, N/M/comma/period emit operators directly;
another held trigger (e.g. slash) must maintain Symbols. Test actual release,
roll and nested LT behavior on installed firmware. This is not keyd's engine.

Functions N/M control main RGB speed, `[4,0]`/`[4,15]` brightness down/up,
Down mode, Up brightness down, Right hue. These are Enhanced's bracket
positions; Plain's relocated left bracket does not move the overlay.
Functions + slash accesses Utilities:

- N/M: side speed down/up; right bracket: side brightness up.
- Down/Up/Right: side mode/brightness down/color (original positions).
- Number row: original brightness, Mac task/search/voice/DND and media/volume.
- Q/W/E/R/T: Mac task/search/voice/console/DND; U/I: screenshot area/whole.
- O/P: sleep toggle/battery display.

RF DFU, device reset and RGB factory-test bindings were intentionally **not**
migrated. Historical originals retain them as evidence. Assigning a keycode
does not execute it, but the desired map avoids accidentally invoking them.
No bond-clear/reset/bootloader commands exist in this backend.

## Pinned Evidence

Vendor repository: <https://github.com/nuphy-src/qmk_firmware/tree/f1856912d603800eaca227ae2e1c5c8548fdf261>

| Pinned Path | Finding |
| --- | --- |
| `keyboards/nuphy/air60_v2/ansi/ansi.h:22-50` | Custom enum begins at QK_KB_0; indices match supplied definition |
| `quantum/keycodes.h:35-44,748` | MT `0x2000`, LT `0x4000`, MO `0x5220`, custom base `0x7E00` |
| `quantum/quantum_keycodes.h:88,117-123` | Layer/modifier masks and basic eight-bit tap encoding |
| `keyboards/nuphy/air60_v2/ansi/keyboard.json:4-28` | USB `19f5:3255`, release 1.1.7, eight layers, 6x17 matrix, mouse/consumer support |
| `quantum/via.h:62-105` | Protocol 12, firmware value defaults to zero, command IDs |
| `quantum/via.c:279-461` | Echo response framing, keycode/buffer getters and setter |
| `quantum/dynamic_keymap.c:122-127` | Setter persists high byte then low byte to EEPROM; not transactional |
| `tmk_core/protocol/usb_descriptor.c:388-407` | Raw HID page `FF60`, usage `61`, unnumbered 32-byte input/output |
| `keyboards/nuphy/air60_v2/ansi/ansi.c:304-329,373-397` | Windows base 3/NKRO enabled; Mac base 0/NKRO disabled |
| `keyboards/nuphy/air60_v2/ansi/ansi.c:409-495,610-650` | Link behavior, reset/sleep/battery/tilde handlers |
| `quantum/process_keycode/process_rgb.c:58-99` | Legacy RGB codes also operate RGB matrix |

Independent VIA application pin:
<https://github.com/the-via/app/tree/65b50efc8e14e6feabff38ce20c191edf1f078f9>
`src/utils/key-to-byte/v12.ts` confirms CUSTOM base `0x7e00`;
`src/utils/advanced-keys.ts` confirms CUSTOM, MT, LT, MO and LSFT syntax.
Protocol 11 instead uses `0x7f00`, and older versions `0x5f80`. **Never infer
wire codes solely from the VIA definition's display names.** Only protocol 12
is enabled here. Upstream clones are research-only, not runtime dependencies.

Exact custom-code mapping (wire value = `0x7E00 + index`):

| Index | Vendor Enum | Meaning |
| --- | --- | --- |
| 0 | RF_DFU | RF firmware update, omitted |
| 1 | LNK_USB | USB output |
| 2 | LNK_RF | 2.4 GHz selection/pairing |
| 3/4/5 | LNK_BLE1/2/3 | Bluetooth selection/pairing |
| 6/7/8/9/10 | MAC_TASK/SEARCH/VOICE/CONSOLE/DND | Mac actions |
| 11/12 | MAC_PRT/PRTA | Screenshot whole/area |
| 13/14 | SIDE_VAI/VAD | Side brightness up/down |
| 15/16 | SIDE_MOD/HUI | Side mode/color |
| 17/18 | SIDE_SPI/SPD | Side speed up/down |
| 19 | DEV_RESET | Device reset, omitted |
| 20 | SLEEP_MODE | Toggle automatic sleep, persistent when pressed |
| 21 | BAT_SHOW | Toggle battery indication |
| 22 | RGB_TEST | Factory RGB test, omitted |
| 23 | SHIFT_GRV | Shift+grave; desired layout uses standard LSFT instead |

The vendor adds BAT_NUM at index 24, but the supplied definition does not
advertise it. It is intentionally rejected, not guessed into the desired map.
Short RF/BLE presses select; long holds pair in vendor firmware. RF/BLE actions
are ignored while its link mode is USB. Their behavior is not a ZMK-style
explicit bond-clear action; do not long-hold merely to test a binding.

## Backend Safety

Python 3.9+ stdlib on Linux, offline runtime; no hidapi or global pip packages.
Raw HID opens O_RDWR because even a getter requires an output report, but
snapshot/diff/verify only send getter commands. Every input/output uses 32-byte
VIA payloads, with a leading zero report ID only on Linux writes. Responses
must echo the command and relevant coordinates/offsets; timeouts, short reads,
unhandled commands and stale packets fail rather than retrying a setter.

Identity requires wired USB VID/PID, USB ancestry, exact pinned raw report
descriptor and a unique interface. `--device` explicitly disambiguates multiple
matching units; no Bluetooth/receiver guesses. A held FD is checked against
rediscovery and the device node before every request. `bcdDevice`, serial and
sysfs location are recorded. VIA protocol 12, eight layers and firmware value
zero are required. Matrix dimensions are pinned evidence, not falsely claimed
as discoverable by a VIA getter.

**VIA cannot attest the installed vendor build/custom enum.** Apply requires
the exact `--firmware-profile` acknowledgement below after checking installed
firmware provenance against these sources. USB release and VIA firmware value
are not cryptographic firmware identities. Do not acknowledge an unknown build.
Unknown protocol versions/custom codes are hard errors, not numeric passthrough.
Apply additionally requires `--ack-layout-review` after reviewing the selected
native layout and diff. Both acknowledgements are required even for a no-op;
the CLI refuses missing acknowledgements before opening HID.

Hidraw has no kernel-enforced exclusive-open operation. This implementation
holds cooperative `flock` and audits `/proc/*/fd` for processes with the **same
effective UID** before every request. Effective UID comes from `/proc/*/status`,
not real UID or directory ownership. Detected same-user competitors and malformed
UID records are fatal; other-user/root FD directories are not opened. Inaccessible
process status (even for unrelated processes), same-user FD tables or FD links
produce one scoped warning per transport on stderr, not refusal or a mid-write
abort. Visible FDs remain checked before every request; snapshot stdout stays JSON.
Do not elevate privileges or stop unrelated credential/system services to remove
a warning. Close browsers, Studio, VIA and other HID clients before connecting.
Existing hidden same-user or other-user handles, privileged processes, hidden
processes, UID changes and new non-cooperating opens racing the audit remain
possible. This is practical same-user conflict
detection, **not hard exclusivity**; that would require a broker/kernel mechanism.
No device requests were attempted during implementation.

Apply validates all 816 desired cells first, then obtains a full current
keymap/capability snapshot and computes the complete diff. Before setters it:

1. Prints the diff and creates a private run directory under XDG state.
2. Writes/fsyncs `before.json`, `desired.json`, `diff.json` with mode 0600.
3. Re-reads the entire keymap/identity and refuses a concurrent change.
4. Writes/fsyncs one intent record **before** each changed-cell setter.
5. Reads each cell back immediately, then verifies all 816 cells at the end.

Only changed cells are written; a matching layout performs zero setters and
creates no backup. No macro, lighting-setting, encoder, layout-option or reset
setter is available. Native empty macro fields are placeholders, not requests
to erase live macros. The backend applies keymaps only, not entire VIA exports.

**EEPROM updates are immediate and non-atomic, including the two bytes of one
cell.** There is no save command/transaction to roll back. Failure stops all
further setters and attempts a getter-only recovery readback. `failure.json`
records attempted/completed cells and either readback or its error. Durable
intent records remain useful even if the process dies or the disk later fails.
No automatic rollback hides a partial failure or issues unexpected writes.

Recovery: keep a fallback keyboard; retain the printed run directory. Reconnect
only after resolving access/failure causes, snapshot again, compare against
`before.json` and `desired.json`, and explicitly choose forward repair or the
pre-change map. `snapshot_to_layout(before)` produces reviewable native VIA
strings for supported raw codes, rejecting unknown values. Feed the reviewed
result through the same apply preflight; never blindly replay raw EEPROM.
The historical Documents export is not necessarily the pre-change map.

## Callable API

`backend.py` is importable by file path or a directory-local module import.
No device discovery or I/O occurs on import. Public integration surface:

```python
load(path)                             # native VIA dict; default layout.json
validate(layout)                       # eight lists of encoded uint16 values
discover()                            # sysfs-only list of identity dictionaries
Hidraw(path=None)                      # guarded exchange transport; close() required
Client(transport)                      # transport.identity + exchange(bytes32)
client.snapshot()                      # raw layers + identity/capabilities/scope
diff(snapshot, layout)                 # structured changed-cell list
format_diff(changes)                   # human-readable matrix-coordinate diff
apply(client, layout, state_dir=None,  # keyword-only options; explicit mutation
      firmware_profile=PROFILE, ack_layout_review=True, emit=print)
verify(client, layout)                 # raises Air60Error if mismatch
snapshot_to_layout(snapshot)           # offline recovery conversion, no setters
main(argv)                            # CLI adapter; returns 0/1
```

`apply` returns `{"changed": count, "backup": path_or_null}`. All protocol and
validation failures raise `Air60Error`; filesystem failures may raise `OSError`.
The caller must explicitly pass `ack_layout_review=True` (default is false)
alongside `firmware_profile=PROFILE`; neither acknowledgement is implicit.
`Client.set_key`/`request` are low-level internals: the main CLI must use `apply`,
not bypass its backup/preflight. Snapshot raw cells retain unknown codes as
evidence; desired layouts and recovery conversion reject unknown encodings.

Commands from repository root:

```sh
python3 keyboards/air60/backend.py check
python3 keyboards/air60/backend.py status
python3 keyboards/air60/backend.py snapshot --device /dev/hidrawN
python3 keyboards/air60/backend.py diff --device /dev/hidrawN
python3 keyboards/air60/backend.py verify --device /dev/hidrawN
python3 tests/keyboard_air60_test.py
```

Future, separately authorized apply after layout/firmware review, **not run**:

```sh
python3 keyboards/air60/backend.py apply --device /dev/hidrawN \
  --firmware-profile nuphy-f1856912d603800eaca227ae2e1c5c8548fdf261 \
  --ack-layout-review
```

`--layout PATH` selects a reviewed native export for diff/apply/verify.
`--state-dir PATH` changes the runtime backup root, never tracked snapshots.
Snapshot JSON is printed to stdout; the main CLI may store it privately.
Offline original-versus-desired review:

```sh
PYTHONPATH=keyboards/air60 python3 -c 'import backend as b; old=b.load("keyboards/snapshots/air60/original.layout.json"); print(b.format_diff(b.diff({"layers": b.validate(old)}, b.load())))'
```

## Verification Limits

- Mac/Enhanced disables NKRO; Windows/Plain enables it in stock compiled vendor
  switch logic. VIA cannot change that policy. Test installed-firmware rollover.
- Vendor Air60 config has no exposed runtime hold-tap tuning. QMK's usual
  200 ms default is a source baseline, not a measured installed behavior.
- Live setter acceptance, EEPROM persistence across reconnect, typing, rolls,
  modifier release, layer-tap release, RF/BLE pairing and side controls remain
  untested because no Air60 was connected. Readback is not a behavioral test.
- Symbol characters assume US host layout. Mac-specific controls may do
  nothing or different actions on Linux; they are retained device utilities.
- Firmware must own Air60 remaps after migration. Existing keyd Air60 remaps
  must be transitioned separately to pass-through at the reviewed stage, for
  both Plain and Enhanced. This backend never installs/reloads keyd.
- USB is the only management transport implemented. Bluetooth/receiver
  identities and behavior need separate observation. No flashing is required.
