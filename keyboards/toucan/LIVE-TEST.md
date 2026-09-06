# Toucan Live Test

## 2026-09-06: Personal Left Firmware

Approved personal tap-preferred/200 ms left image built and flashed; right
firmware and host remaps unchanged. Functions 3:0 and 3:41 are None.

- Physical RST was difficult to press. The user assigned and saved a temporary
  Nav+X Bootloader binding through Studio; independent readback confirmed only
  that change. Nav+Z unlock stayed unchanged and backend guards were retained.
- The left UF2 volume was identified by serial and bootloader metadata.
  Preflash `CURRENT.UF2` was captured but is not a vetted restore image.
- All 685568 trial-left bytes were copied; final fsync returned EIO as the UF2
  volume disconnected. Runtime re-enumerated one second later. No automatic
  reflash occurred and no postflash flash-memory hash was obtained.
- The guarded backend restored Nav+X to Transparent (ID 23), saved and verified.
  Backup/result: `~/.local/state/keyboards/toucan/apply-e6wqn56c/`.
- Fresh independent verification and another after the user's left power cycle
  returned `verified: true`, `changes: []`. All 168 bindings, stable order,
  geometry and behavior metadata matched; no settings or bonds were cleared.
- User reported both halves typing, overlapping rolls, intentional D/J Shift
  (>200 ms), modifier chords, thumb layers, trackpad, display/LEDs and no stuck
  keys passed. These are user reports, not instrumented HID traces. Longer
  typing and separate BLE/battery tests remain pending; USB power does not
  establish the selected host output transport.
- Intermittent first-read `invalid protobuf tag` failures recurred; one
  preflash retry timed out at `core.get_device_info`. Complete diagnostic/retry
  captures passed with unchanged decoder, framing, identity and access checks.
  The cause remains unresolved.

The unchanged `postflash-evidence.tar.gz` under
`~/.local/share/toucan-build-v03/` retains the before/temporary-binding snapshots,
raw-frame diagnostic, bootloader records, runtime apply backup and
`records/personal-postflash-verification.json` /
`records/personal-powercycle-verification-retry.json`. It complements the
candidate and personal archives. [FIRMWARE-PREP.md](FIRMWARE-PREP.md) lists exact
UF2 hashes, retention/rebuild requirements and recovery limits. Original
installed firmware remains unknown; recovery images restore personal compiled
defaults, not the original image or saved settings.

## 2026-09-05: Runtime Layout And Host Pass-Through

The entries below preserve the earlier runtime-only session and its hashes;
they do not describe the September 6 firmware image or current keymap hash.

Session: 2026-09-05, host `mbook`, last automated check 23:26 -05:00.
User approved home-row mods, Functions relocation/output controls, Symbols
cleanup and Nav changes.

## Applied And Verified

- USB identity `1d50:615e`, serial `93F54E4E61BA5937`, `/dev/ttyACM0`.
- Both halves USB powered; laptop keyboard available as fallback.
- 25 binding changes and four layer renames applied through Studio RPC.
- RAM readback matched; save acknowledged; post-save and fresh-connection
  verification matched with no pending unsaved changes. No flash/reset/bond clear.
- Initial getter-only snapshot failed with `invalid protobuf tag`. Diagnostic
  retry and subsequent complete snapshots succeeded. It recurred on the first
  verification after physical Studio unlock following the power cycle; diagnostic
  verification and a subsequent saved snapshot again passed. Cause remains undetermined;
  decoder/framing validation was not weakened. No setters preceded the failure.
- Same-user process access audit remains incomplete; flock/TIOCEXCL and visible
  competitor checks passed. This is not a system-wide exclusivity guarantee.

## Host Remapping

Although reported temporarily stopped, keyd was active at preflight. It was
explicitly stopped before applying Toucan. Its stop logged exit status 15;
subsequent start succeeded.

Only `/etc/keyd/toucan.conf` was replaced with the native staged pass-through
profile. All configs passed `keyd check`; service startup logs confirmed:

| Transport | Keyd selector | Identity evidence |
| --- | --- | --- |
| USB | `k:1d50:615e:982e9afd` | input18, USB bus 0003, matching Toucan serial |
| Bluetooth | `k:1d50:615e:b1063934` | input20, bus 0005, MAC `CD:F7:07:F4:F2:0E` |

Bluetooth was already connected despite USB power. Both interfaces now match
`/etc/keyd/toucan.conf` in the 23:15:06 service journal, and again on reconnect
at 23:23:15/17. USB-directed physical checks were reported successful by the user;
Bluetooth-specific typing remains untested. No Bluetooth settings were changed.
This identity finding does not identify which output transport is selected.

`default.conf`, `air60.conf`, `home-row-mods` and `shared-layers` retained their
pre-session SHA256 hashes. The general keyd installer was deliberately not used
because it would also deploy staged generic mappings. Keyd is running again.

## Recovery Evidence

Local runtime records, not checked-in original snapshots:

- Pre-apply snapshot: `~/.local/state/keyboards/toucan/snapshot-yeve7hvn/snapshot.json`
- Runtime keymap backup/result (not firmware image or bonds): `~/.local/state/keyboards/toucan/apply-uyyjdtt8/`
- Post-save snapshot: `~/.local/state/keyboards/toucan/snapshot-025irv4n/snapshot.json`
- Post-power-cycle snapshot: `~/.local/state/keyboards/toucan/snapshot-umf58gi0/snapshot.json`
  (byte-identical to the post-save snapshot, with the same SHA256 below).
- Root-owned complete host backup: `/var/lib/toucan-keyd-backup.CLIoVC9b/before/`
- Desired host profile copy: `/var/lib/toucan-keyd-backup.CLIoVC9b/desired.conf`

SHA256:

| Artifact | Hash |
| --- | --- |
| Native `toucan/keymap.json` | `40fe7ca6a3e8079883d85e1ceef2778c0a36d2f3b7c3e5428526c2812d4033e5` |
| Post-save complete snapshot | `0823e4aa9bc8377cdce2da3bd245f655dede4523b7f8a9091d27a78deb3941a9` |
| Installed `toucan.conf` | `3fced99213715ca2b760ea674030b377f735cbfc34eeb11cfc5e731f63b777fd` |

Do not restore the old host profile over the new firmware without coordinated
review: that reintroduces duplicate home-row processing. Use the laptop fallback
and stop keyd if necessary while diagnosing. Firmware restoration is not automatic.

## Physical And Persistence Results

- User reported the USB-selection, typing, home-row chord and thumb-layer checks
  all worked as expected, then completed the remaining Symbols, Functions,
  volume, mouse-button and normal-typing checklist without reporting problems.
- User completed the instructed unplug-both-halves power cycle and reconnected.
- Studio was locked after restart; user physically unlocked with Nav+Z.
- Read-only verification then passed: `verified: true`, `changes: []`, no pending
  unsaved changes. A separate complete snapshot matched the pre-cycle saved state
  byte-for-byte; offline diff against the intended keymap was also empty.
- Keyd remained active; both reconnected interfaces matched Toucan pass-through.
  All five host config hashes matched the post-apply state.
- Bluetooth typing, battery operation and Air60/generic rollout were deferred
  in this session. See the Air60 live record for its subsequent deployment.

The September 5 USB-directed checks and power-cycle persistence passed.
Physical results are user-reported, not an instrumented capture of emitted events.
The intermittent first-read protobuf error remains an unresolved tooling issue;
successful full readbacks do not explain or eliminate it.
