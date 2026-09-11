# Toucan Firmware Build, Flash And Recovery

The personal tap-preferred/200 ms left image was built and flashed on
2026-09-06. Right firmware stayed untouched. All 168 bindings matched after
removing the temporary Nav+X Bootloader binding and again after a left power
cycle. Initial user-reported checks passed; longer typing and separate BLE/
battery tests remain pending. See [LIVE-TEST.md](LIVE-TEST.md) for dated results.

## Retained Artifacts

Local root: `~/.local/share/toucan-build-v03/`. The retention contract is:

- `candidate-evidence.tar.gz`, `personal-evidence.tar.gz`,
  `postflash-evidence.tar.gz`, and each archive's `.sha256` sidecar.
  These are unchanged, complementary historical evidence, not current docs.
- `recovery/trial-left.uf2`, `recovery/recovery-left.uf2`,
  `recovery/recovery-right.uf2`, `recovery/SHA256SUMS`, and `recovery/README.md`.

| Personal UF2 | SHA256 |
| --- | --- |
| Trial left, tap-preferred/200 ms | `d0616395e6505e57a459e54433c750cf564461f426a98f49b90e8d467f6da451` |
| Recovery left, hold-preferred/200 ms | `09f9b6572290a37e3d21e452820d9b0d01b95b0c8a04d8a9f6d922657fa3db9e` |
| Recovery/trial right, identical | `2bc27e893a6c38140c4874890b5e803ac2d3ab5f5f885d13c82c828a3e5dffa7` |

Recovery images contain the personal layout; they are neither original-image
rollback nor settings rollback. Original installed firmware is unknown.
Checked-in original snapshots remain immutable.

The candidate archive retains vendor-baseline/patched UF2, ELF, DTS and config
sets, vendor source, frozen inputs, scripts, logs and package baselines. The
personal archive adds personal builds, generator/inspection tools, live
preflash records, archived backend/protocol and original snapshot. The postflash
archive adds bootloader/readback diagnostics, flash outcome, final verifications
and runtime apply backup. Preserve all three rather than treating one as a
replacement for the others.

Cleanup on 2026-09-06 verified archive checksums and matched 144 retained
inputs/artifacts/records to archive members before removing `ws/`, `vendor/`,
`configs/`, `build/` and archived loose scripts/records. The pinned Podman
image and these seven task-only packages were removed after dependency checks:
`podman`, `passt`, `containers-common`, `conmon`, `catatonit`,
`aardvark-dns`, `netavark`. Pre-existing packages, runtime backups and original
snapshots were preserved; no blanket container pruning was used. The retained
set is not an offline rebuild environment: future rebuilds require dependency
and image downloads.

## Pinned Build Inputs

Hardware basis: user-confirmed original Toucan with circular Cirque trackpad,
using [the original-Toucan vendor sources](https://github.com/beekeeb/zmk-keyboard-toucan).
PCB/component revisions are not fully established. Photos or disassembly are
not a gate; investigate inherited assumptions only if symptoms warrant it.

| Input | Revision |
| --- | --- |
| Original-Toucan repository | `7154e0187128e493cd15785a18af1546419d5bb1` |
| ZMK, peeled v0.3 | `edf5c0814fd3ea202e43aad2d68fd32e882a518c` |
| Cirque, resolved toucan branch | `effec100f0cd3a38e7fba3adfea394586cc84cab` |
| RGB LED widget v0.3 | `8756cb7b8114069fa3c25c6f6c990f24988fceff` |
| Zephyr | `dacab4875df72109b96cc8977547a0dc04875bcd` |

The archived `records/west-frozen.yml` freezes all 41 active West projects.
Container: official Linux/amd64 `zmkfirmware/zmk-dev-arm:3.5`, pinned as:

```text
docker.io/zmkfirmware/zmk-dev-arm@sha256:96c17bcfcce8481c0872b12e5ce7ae890ede09ac280c23c1e72970e72e21a522
```

Recorded tools: West 1.2.0, CMake 3.30.0, Python 3.12.3, Zephyr SDK 0.16.3,
ARM GCC 12.2.0. Compilation used rootless containers without network, devices,
privileged mode, Docker socket or a home-directory mount.

To rebuild, verify archive sidecars and extract each to a separate evidence
directory, preserving historical versions. Assemble a clean build workspace
separately; existing UF2 outputs block the archived build scripts.
Restore the archived original snapshots beside the archived backend in its
expected repository-relative layout. Recreate `ws/config/west.yml` from
`records/west-frozen.yml`; variant-directory manifests are not the dependency
input. Fetch the pinned projects and container again. Archived tools include
`fetch.sh`, `freeze.py`, `build.sh`, `prepare-personal.py`,
`build-personal.sh`, `inspect-uf2.py` and `inspect-personal.py`.
Review their paths before running: scripts expect the workspace mounted at
`/work`, Python tools hard-code `/home/matt/dotfiles`, and
`build-personal.sh` must launch from `/work/ws`.
Fresh containers need `west zephyr-export`. Archive extraction alone does not
materialize the full dependency tree.

Build matrix: board `seeeduino_xiao_ble`; left shields
`toucan_left rgbled_adapter nice_view_gem`, snippet `studio-rpc-usb-uart`,
Studio enabled; right shields `toucan_right rgbled_adapter`.
Personal variants use symbolic behavior/keycode references for all 168 bindings.
The trial overrides the existing Mod-Tap node:

```dts
&mt {
    flavor = "tap-preferred";
};
```

Compiled tapping term is 200 ms for all eight home-row mods. Quick-tap and
prior-idle remain disabled; Layer-Tap is unchanged. Intentional modifiers must
reach the hold timeout. This is not a promise of identical keyd event handling.

The 2026-09-07 Bluetooth placement update is runtime-only. These unchanged
archives retain the September 6 defaults: Functions slash (30) Pass, M (32)
previous, comma (33) next, period (34) RShift. They do not contain the newer
Clear/None/previous/next placements in `keymap.json`. Saved settings overlay
compiled defaults; after recovery, inspect the live diff before applying.

## Inspection Findings

- All 168 September 6 personal bindings matched both resolved DTS and compiled ELF.
  Geometry matched all 42 ordered keys, including signed thumb rotations.
  Four named layers, three reserved slots, tri-layer and protected controls
  remain. Functions 3:0 and 3:41 are None; Nav+Z unlock is unchanged.
- Recovery/trial left configurations match; allocated ELF and UF2 payload
  differ only at `0x705cc`, flavor enum 0 to 2. Right UF2 is byte-identical
  to the vendor baseline; unused behavior code is discarded.
- UF2 framing, nRF52840 family and application-only addresses passed:
  `[0x27000, 0xec000)`. No blocks target internal settings
  `[0xec000, 0xf4000)` or bootloader. UF2 data matches every allocated
  file-backed ELF section at its flash load address, including RAM initializers.
  These checks do not establish the original image's partition scheme.
- The 24 behavior device names remain, but personal compiled registry ordering
  differs. Existing settings map IDs to names. After settings loss, recheck
  metadata; never infer fresh IDs from the original snapshot or bypass guards.
- Stable DTS IDs are Base 0, Nav 1, Symbols 2, Functions 3. Saved Studio display
  order is 0,2,1,3; fresh defaults use 0,1,2,3. Restore display order explicitly
  if needed, without resetting settings/bonds to force compatibility.
- Left Studio, 144x168 display, RGB and split input channel 0 were present;
  right Cirque SPI and BLE peripheral roles matched vendor sources. USB power
  does not bypass the BLE split link or establish selected host transport.
- Both DTS files enable GD25Q16/P25Q16H at one QSPI address; compiled driver
  selects GD25Q16, JEDEC `c8 40 15`. A different chip could fail its runtime
  check. Settings use internal flash. NFC-capable P0.09/P0.10 are matrix pins
  while `CONFIG_NFCT_PINS_AS_GPIOS` is unset; bootloader/UICR state matters and
  was not inspected. Deprecated/shared-address warnings remain inherited;
  right-side `ZMK_USB=y` resolving to `n` is expected for the peripheral.

Detailed evidence is in archived `records/uf2-inspection.json`,
`records/personal-inspection.json`, `records/personal-artifact-sha256.txt`
and build logs. Vendor-baseline/patched artifacts are evidence only.

## Flash And Recovery Procedure

Keep the laptop keyboard available and identify the correct half and mounted
UF2 volume before writing. The [vendor guide](https://docs.beekeeb.com/toucan-keyboard/quick-start-keymap-and-firmware)
uses double-tap RST near USB-C. Physical RST proved difficult in this session;
do not assume bootloader access will remain available if firmware stops working.
No force, hardware shorting, photos or disassembly gate is required.

The approved temporary Studio Nav+X Bootloader binding exposed the left volume
at `/run/media/matt/XIAO-BOOT`, USB path `5-1`, serial
`93F54E4E61BA5937`, USB `2886:0064`, Model `Seeed XIAO nRF52840 Plus`,
Board-ID `nRF52840-SeeedXiao-v1`. Bootloader reported
`0.9.2-29-g6a9a6a3` (2025-10-15), SoftDevice S140 7.3.0.
Re-identify these on every attempt; a mount path alone is insufficient.
Nav+X is now transparent and cannot currently enter the bootloader.
The backend still rejects Bootloader assignments.

Before the flash, `CURRENT.UF2` and `INFO_UF2.TXT` were captured.
The matching source/copy CURRENT SHA256 is
`e84e3a204d7135878b2a3f2caea9ee6e0e763a8d7bf2e8fc77835859ca0d763b`.
This is not a vetted restore image or settings/bond backup. Do not replay it
blindly. No exact original-image recovery is established.

Verify `recovery/SHA256SUMS` and correct-half assignment before copying a
personal UF2. On September 6, all 685568 trial-left bytes were copied with
`dd ... conv=fsync`; final fsync returned EIO as the device disconnected.
Kernel logs showed metadata-write failures after disconnect and runtime
re-enumeration one second later. No automatic reflash occurred. Full live
verification subsequently passed, but no postflash flash-memory hash was read.

After reboot, unlock with Nav+Z and take a complete snapshot before setters.
Saved bindings overlay compiled defaults: apply only the validated diff.
The final guarded apply restored Nav+X to Transparent (ID 23), saved and
verified; fresh and post-power-cycle checks matched all 168 bindings.

Runtime recovery records remain at
`~/.local/state/keyboards/toucan/apply-uyyjdtt8/` (September 5 map) and
`~/.local/state/keyboards/toucan/apply-e6wqn56c/` (temporary binding removal).
These are keymap backups, not firmware or bonds. Additional snapshot and host
backup paths are in [LIVE-TEST.md](LIVE-TEST.md). Reflashing recovery-left changes
firmware/defaults, not persisted overrides. Right recovery is available but
was not flashed; expanding flash scope requires explicit authorization.
Never clear bonds, use settings-reset firmware or Restore Stock Settings to
work around unexplained mismatches.

If typing/connectivity fails, use the laptop fallback and inspect current
state before recovery. Avoid restoring overlapping keyd remaps over firmware
home-row mods. Initial typing/chord/trackpad/display checks were user-reported,
not instrumented. Intermittent first-read `invalid protobuf tag` errors remain
unresolved; successful complete retries did not weaken framing, decoder,
identity or access checks.
