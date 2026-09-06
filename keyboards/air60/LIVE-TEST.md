# Air60 Live Test

Session: 2026-09-06, host `mbook`, host restart 00:28 -05:00.
User approved distinct Plain/Enhanced maps, the switch swap, and explicit apply.

## Target And Provenance

- Windows switch: Plain, native base 3, stock NKRO-enabled path.
- Mac switch: Enhanced, native base 0, stock NKRO-disabled path.
- User reports stock firmware; USB release `0117`, VID/PID `19f5:3255`.
- Raw interface `/dev/hidraw9`, USB `3-1`, no serial string.
- Raw descriptor SHA256:
  `b464b2658e8e41b89af847112efa3c3059c330864e10094425c0b92d55e24d89`.
- Live VIA protocol 12, eight layers, firmware value 0. Matrix 6x17 is pinned
  vendor evidence, not discovered by a getter. Exact build cannot be attested
  through VIA; the stock profile acknowledgement used pinned vendor commit
  `f1856912d603800eaca227ae2e1c5c8548fdf261`.
- Live pre-change matrix exactly matched the original VIA export. Backup
  conversion to a supported native restore layout was lossless.

## Applied And Verified

- Updated generator/native map, specification and separate mode diagrams.
- Preserved prior intended Enhanced bindings and overlays 4-7; moved Enhanced
  to base 0, created approved Plain base 3, kept 1/2 retired.
- 94 keyboard tests passed; 17 repository contract groups passed. Optional
  JSON Schema checks skipped: `python3-jsonschema` unavailable.
- Desktop/mobile Chromium checks passed both modes, with no page overflow or
  JS errors. These are reference checks, not physical keyboard tests.
- Initial privilege prompt timed out before stopping keyd; user approved retry.
  Keyd stopped successfully before any Air60 setters.
- Applied 253 changed cells, with durable before/desired/diff/intent records,
  per-cell readback, and a complete matching after snapshot.
- Independent full readback matched, both before and after restarting keyd.
  These immediate-persistence VIA writes require no separate Save command.
- No firmware flashing, macro/lighting-settings writes, reset, bond clearing,
  or Bluetooth commands were performed.
- Incomplete same-user HID access audit warning remains scoped: cooperative
  flock and visible competitor checks passed, not hard system-wide exclusivity.

## Host Pass-Through

Only `/etc/keyd/air60.conf` was replaced. The general keyd installer was not used
because it also targets generic mappings. The one-file deployment checked
expected hashes, backed up the complete directory, validated the full config,
atomically replaced the profile, checked untouched files, and started keyd.

Live `/proc/bus/input/devices` and the keyd journal established these USB IDs;
the 00:28:13 startup log confirms all four match `/etc/keyd/air60.conf`:

| Interface | Keyd Selector | Input Inventory |
| --- | --- | --- |
| Boot keyboard | `k:19f5:3255:e3746a94` | input55, USB input0 |
| NKRO keyboard | `k:19f5:3255:0d7157bb` | input59, USB input2 |
| System Control | `k:19f5:3255:a10585ca` | input57, USB input2 |
| Consumer Control | `k:19f5:3255:921cd195` | input58, USB input2 |

The mouse remains ignored. Both keyboard interfaces need coverage because the
physical mode switch changes rollover behavior. Keyd evidence handling now
accepts multiple verified IDs per transport while retaining existing single-ID
records; duplicate, unknown or ambiguous verified IDs are rejected.

Historical Bluetooth selector `k:19f5:3246:838051e9` remains reserved. Air60 was
not in the connected Bluetooth inventory. Receiver identity is unknown and no
receiver was present in the input inventory. Keep both transports disconnected
until separately reviewed; no wireless behavior has been verified.

Toucan's profile and the laptop/generic files retained their pre-session hashes.
The restart log confirms both Toucan interfaces still use Toucan pass-through.

## Backups And Hashes

- Pre-apply snapshot: `~/.local/state/keyboards/air60/snapshot-nlmu2o4u/snapshot.json`
- Apply records: `~/.local/state/keyboards/air60/apply-b_52rrdo/`
- Full persisted readback: `after.json` inside that apply directory.
- Bound transport evidence: `keyd-evidence.json` inside that apply directory;
  validated against the intended Air60-only payload before host installation.
- Root-owned host backup: `/var/lib/air60-keyd-backup.cL1NeN8c/before/`
- Root-owned installed profile copy: `/var/lib/air60-keyd-backup.cL1NeN8c/desired.conf`

| Artifact | SHA256 |
| --- | --- |
| Native `air60/layout.json` | `db74739b4407a2dfa31dfeef38862bec1af8767e423c792c1eaa3335fb6a58b2` |
| Full `after.json` readback | `eb78ff0681a22a9ab46b9b042128d2506dee05023cfe2231be83b2d4258c7afe` |
| Installed `air60.conf` | `8cf339e7f3b901e2f8351135246b24a1be6fee73f78b37bf660a1ecd9c52d659` |
| Unchanged `toucan.conf` | `3fced99213715ca2b760ea674030b377f735cbfc34eeb11cfc5e731f63b777fd` |
| Unchanged `default.conf` | `b72a8088064bd83d4afb9fdf3dbc39c8bede5ed684c0c80035e3b84a90892e5d` |
| Unchanged `home-row-mods` | `f2694907eb1a36cd133cd11f79e12c729880443def7ecc0d5e43cd575db30f51` |
| Unchanged `shared-layers` | `20b08cba808e5ed4ca2d04a77206799deb6ec2bcff0d6c5950655d4c46709670` |

Recovery must coordinate device and host mappings. Do not blindly restore the
old Air60 host profile over the new native layers. Use a fallback keyboard,
inspect the recorded state, and choose an explicit firmware/host recovery.

## Pending Human Checks

- Plain/Windows: Tab, Caps, Shift, both Alt keys, Ctrl/Super, center quote/Delete/
  bracket, immediate letters and representative gaming chords.
- Enhanced/Mac: quote/Escape, near-Space editing keys, center Tab/Caps/F9
  voice-to-text, home-row mods, Nav/Symbols, Fn/Utilities and fast typing rolls.
- Modifier release and simultaneous-key behavior in both modes. NKRO statements
  above describe pinned stock policy, not instrumented runtime measurements.
- Power off/on (not merely unplug USB), reconnect, and verify persisted map.
- Bluetooth/receiver testing and generic rollout remain deferred.

This is a test deployment, not a completed physical acceptance record.

## Symbols Tilde Correction

On 2026-09-06 the user reported Symbols + physical left Shift emitted `[`;
they approved changing it to `~` to match Toucan muscle memory.

- Layer 5 `[4,0]`: `KC_TRNS` -> `LSFT(KC_GRV)` (`0x0001` -> `0x0235`).
- Generator, native layout, specification, reference and regression assertions
  updated. Enhanced Base remains `[`; Plain Base remains ordinary left Shift.
- Live diff and apply both reported exactly one changed cell. Full readback
  matched during apply and through a fresh connection afterward.
- Backup and result: `~/.local/state/keyboards/air60/apply-ixf9baae/`.
- Current native layout SHA256:
  `e2a02ac30e274219a9e6ddfa90492c3008d6a98dd12cc1b7057fc02c20c560be`.
- This apply's `after.json` SHA256:
  `6b1db8133754dc5cbae1c561c3c1c0a4e20cdb392ed3bee26f2745a4f4ac4091`.
- Keyd pass-through stayed running and unchanged; no host migration was needed.
- All 99 keyboard tests passed, including new repository-wide private backup
  path guards. The full test runner passed keyboard suites but failed five
  existing suites: CLI/tools/desktop/OpenCode reject the Worktrunk version;
  host fixtures omit a required Claude skill alias. All five reproduced from
  an isolated archive of unchanged HEAD `00b505b`.
- Human confirmation of tilde output and power-cycle persistence remains pending.
