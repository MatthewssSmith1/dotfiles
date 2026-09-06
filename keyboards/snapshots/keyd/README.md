# Original Host Configuration

Read-only capture of the five regular files in `/etc/keyd` on 2026-09-05.
These are original host configuration bytes, not desired files or firmware
readbacks. `SHA256SUMS` records hashes computed against the live originals.
Never replace these with routine snapshots; backend snapshots go to private
state directories. No `/etc` writes or service reloads occurred during capture.

Original selectors:

| Device | keyd selector | Evidence |
| --- | --- | --- |
| Toucan | `k:1d50:615e:982e9afd` | Existing host profile; transport coverage not established |
| Air60 | `k:19f5:3255:0d7157bb` | Existing profile labels USB/Bluetooth collectively |
| Air60 | `k:19f5:3246:838051e9` | Exact per-transport correspondence unverified |

Read-only `/proc/bus/input/devices` inspection also found Toucan USB
(`Bus=0003`, name `ZMK Project Toucan Keyboard`) and Bluetooth (`Bus=0005`,
name `Toucan Keyboard`), both vendor/product `1d50:615e`. This does not prove
the keyd capability hash, matching profile, or tested output on either transport.
Do not substitute a vendor/product-only selector or assume the USB hash covers
Bluetooth. Air60 was absent in that inspection; receiver identity remains unknown.
