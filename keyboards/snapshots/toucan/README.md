# Toucan Getter-Only Snapshot

Captured 2026-09-05 20:15:57-20:16:36 UTC over USB CDC ACM. No keymap mutation, save, discard, reset, lock/unlock RPC, behavior execution, flashing, or Bluetooth interaction. Reading Bluetooth behavior metadata does not execute that behavior or inspect Bluetooth connections/bonds.

## Results

- Identity: Toucan; USB vendor ZMK Project; VID:PID `1d50:615e`; serial `93F54E4E61BA5937`; USB bcdDevice `0305`; interface 00, driver cdc_acm.
- RPC serial bytes match USB serial exactly. JSON protobuf representation is base64 `k/VOTmG6WTc=`.
- Studio was unlocked on all three lock-state checks, including the final check. Serial handles closed afterward; subsequent lock state is not asserted.
- Unsaved changes: false before and after. This is the current runtime keymap, not a firmware image or full settings backup.
- Four layers in returned order: BASE (stable ID 0), SYM (ID 2), NAV (ID 1), ADJ (ID 3). Layer parameters use stable IDs, not returned list positions.
- 42 bindings per layer, 168 total; one active physical layout, index 0, named Default Layout.
- Geometry: three rows of six keys per half and three thumbs per half. Logical widths/heights 100 = 1u; coordinates in hundredths of a key unit; rotations in hundredths of a degree. Thumb rotations: 0, +12, +24, -24, -12, 0 degrees. These are firmware presentation coordinates, not measured hardware dimensions.
- `available_layers: 3` means three spare layer slots under upstream protocol semantics, not three existing layers. Maximum layer-name length reported: 20.
- All 24 advertised behaviors have metadata responses. Referenced IDs: 0, 1, 8, 12, 22, 23, 24. ID 0 is not advertised; its detail getter returned meta GENERIC.

## Files

- `snapshot.json`: preserved first-session identity, state, keymap, geometry, behavior IDs, and the ID-0 metadata error. Its status remains blocked to preserve the original result; metadata recovery is in the next file.
- `metadata.json`: second-session details for all advertised behaviors, final unsaved/lock state, complete status.
- `rpc.jsonl`: all 34 request/response pairs across both sessions, decoded protobuf plus exact response payload hex.
- `layers.md`: every layer as human-readable rows and thumbs.
- `bindings.csv`: all 168 bindings with stable layer ID, display order, position, decoded meaning, raw parameters, and geometry.
- `decoded.json`: same per-binding information in JSON.
- `behaviors.md`: complete advertised behavior table with parameter schemas and whether referenced.
- `audit.json`: offline verification of getter allowlist, matched responses, counts, serial match, and observed states.
- `extract.py`: first-session getter-only extractor; refuses to overwrite its snapshot.
- `metadata.py`: advertised-metadata recovery; refuses to overwrite its result.
- `decode.py`: offline-only decoder/audit; does not connect to a device.
- `reference-keymap_subsystem.c`, `reference-keymap.c`: upstream ZMK main source downloaded for interpretation, not source extracted from this device and never compiled/executed.
- `installation.txt`: installed package versions and CLI help, generated locally without opening the serial device.
- `SHA256SUMS`: integrity hashes of the top-level snapshot/report/source files, excluding itself.

## Critical Controls

Positions below are zero-based. Rows are read left-to-right on each half, including thumbs.

- BASE position 37, middle left thumb: Momentary Layer NAV, stable ID 1. BASE position 40, middle right thumb: Momentary Layer SYM, stable ID 2. Both are ordinary momentary keys, not hold-taps.
- NAV position 25, left bottom row column 2 (BASE Z position): Studio Unlock. Only its binding/metadata was read; it was not invoked.
- NAV position 17, left home row column 6: MouseRight. Positions 28/29, left bottom columns 5/6: Mouse5/Mouse4.
- NAV positions 32/33, right bottom columns 3/4: keyboard-page Volume Down/Up, not consumer-page volume usages. Host support can differ.
- ADJ positions 32/33, right bottom columns 3/4: Bluetooth Previous Profile/Next Profile. No profile selection, scanning, pairing, disconnection, or other Bluetooth action was performed.
- ADJ position 0, top-left: behavior 12 Momentary Layer with param1 458795 (`0x0007002b`, Tab HID keycode). This is not a valid exposed layer ID. It is not decoded as a working Tab key; runtime effect is unverified.
- ADJ position 41, rightmost thumb: behavior 0 with both parameters zero. Metadata lookup failed. Upstream encodes missing bindings as zeros, but exact on-device cause/behavior is unknown; do not assume explicit None (ID 4) or Transparent (ID 23).
- No binding directly targets ADJ ID 3. A conditional/tri-layer rule, combo, or other firmware mechanism could activate it, but these getters do not expose that configuration. Holding NAV+SYM to reach ADJ is therefore not confirmed.
- Bootloader (5), External Power (7), Output Selection (15), Reset (18), and `z_so_off` (21, likely soft-off by upstream naming) are advertised but not referenced by these layer bindings. Exact `z_so_off` semantics are not in metadata.
- Bluetooth metadata advertises next (1), previous (2), clear-all (4), clear-selected (0), select (3), and disconnect (5). Select/disconnect advertise profile range 0..5. This does not establish active profile, connected peers, or bond state.
- Output Selection advertises toggle (0), USB (1), BLE (2). It is unbound here and was not executed.

## Hold-Tap Limits

- ID 13 Layer-Tap: param1 is layer ID; param2 is key HID usage. Standard ZMK interpretation is hold layer / tap key. Advertised but unused in all four layers.
- ID 14 Mod-Tap: both parameters advertise key HID usage. Standard ZMK interpretation is hold first key / tap second key; commonly the held key is a modifier. Advertised but unused.
- Key metadata permits keyboard usage up to 255 and consumer usage up to 4095. This describes metadata bounds, not a test of all values.
- No other named custom hold-tap behavior is advertised. No home-row hold-taps appear in this extracted keymap.
- Tapping term, flavor (hold-preferred/tap-preferred/balanced), quick-tap, require-prior-idle, positional hold triggers, underlying binding configuration, combos, macros, conditional layers, and firmware build configuration are not returned by these getters. Do not assume upstream default timings match this device.
- Studio binding editing can generally select already-compiled behaviors/parameters; these getters do not provide a way to create arbitrary hold-tap definitions or inspect/tune those build-time properties. No editing was attempted.

## Identification Limits

The USB descriptors and Studio identity establish the firmware-presented name and serial, not the exact PCB revision, MCU/controller model, shield/board target, physical manufacturer, split-half identity, firmware commit, or bootloader version. The shared VID's USB database label OpenMoko is not proof of keyboard manufacturer. USB revision 0305 is not independently verified as a firmware release. The physical layout suggests a 42-key split arrangement, not proof of a specific commercial board.

Symbols in layers.md use US HID legends; the host keyboard layout can produce different characters. Transparent keys fall through active lower-priority layers; the file intentionally does not assume a particular active-layer combination.

## Installation And Commands

CLI source: https://github.com/electronicmaterialsoffice/zmk-studio-cli

Inspected commit: `3b3bce06230e497905ab22b343ca866081aa2b07`.

Editable installation: `/tmp/opencode/zmk-studio-cli-source`.

Isolated environment: `/tmp/opencode/zmk-studio-cli-venv`.

Executable: `/tmp/opencode/zmk-studio-cli-venv/bin/zmk-studio-cli`.

No global pip installation. The source checkout was not manually modified. Editable installation avoids the upstream explicit package-list limitation for subpackages.

Commands actually used, after directory verification:

```sh
git clone https://github.com/electronicmaterialsoffice/zmk-studio-cli.git /tmp/opencode/zmk-studio-cli-source
python -m venv /tmp/opencode/zmk-studio-cli-venv
/tmp/opencode/zmk-studio-cli-venv/bin/python -m pip install -e /tmp/opencode/zmk-studio-cli-source
/tmp/opencode/zmk-studio-cli-venv/bin/zmk-studio-cli --help
/tmp/opencode/zmk-studio-cli-venv/bin/python /tmp/opencode/toucan-snapshot/extract.py
/tmp/opencode/zmk-studio-cli-venv/bin/python /tmp/opencode/toucan-snapshot/metadata.py
/tmp/opencode/zmk-studio-cli-venv/bin/python /tmp/opencode/toucan-snapshot/decode.py
```

The extractor imports the installed CLI protobuf definitions and inspected request sender. It allowlists seven getter methods, logs requests, uses a bounded frame receiver with notification/request-ID handling, and stops on locked state without trying to unlock. The stock CLI opens serial in its main callback, and its receiver can wait indefinitely on a truncated frame. Only top-level CLI help was run; all board extraction used the guarded scripts. Serial open uses pyserial's default DTR/RTS behavior and does not intentionally reset the board.

The first session stopped on the unadvertised ID-0 getter error after obtaining the keymap. A second session rechecked unlocked state, queried only IDs 1..24, then rechecked unsaved and lock states. All 34 outgoing RPCs were getters; all received matching responses. The one error remains in the audit trail. No secrets/bond keys/credentials were requested or stored.

Reference interpretation sources (upstream main as retrieved, not proof of the installed firmware version):

- https://raw.githubusercontent.com/zmkfirmware/zmk/main/app/src/studio/keymap_subsystem.c
- https://raw.githubusercontent.com/zmkfirmware/zmk/main/app/src/keymap.c
- https://raw.githubusercontent.com/zmkfirmware/zmk/main/app/src/behaviors/behavior_momentary_layer.c
- https://raw.githubusercontent.com/zmkfirmware/zmk/main/app/include/dt-bindings/zmk/keys.h
- https://raw.githubusercontent.com/zmkfirmware/zmk/main/app/include/dt-bindings/zmk/modifiers.h
