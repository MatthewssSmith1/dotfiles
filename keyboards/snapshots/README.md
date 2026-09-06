# Original Keyboard Evidence

Immutable reference inputs, not the intended layout and not proof of current
device state. See each target's provenance document for original paths, capture
details, and limitations. Runtime snapshots/backups live in XDG state, not here.

- `toucan/`: getter-only Studio extraction from the original circular-trackpad
  Toucan; raw responses, geometry, advertised behaviors and decoded reference.
  `snapshot.json` records an intermediate extraction; `metadata.json` supplies
  the completed advertised-behavior metadata. No setters were used.
- `air60/`: user-exported VIA layout and device definition. These files are not
  a fresh live read or a firmware backup.
- `keyd/`: byte-preserved five original `/etc/keyd` configuration files. Device
  selectors are historical evidence, not verification of every transport.

The root `SHA256SUMS` verifies exactly the preserved input files:

```sh
sha256sum --check SHA256SUMS
```

Run that command in this directory, or `./keyboards/keyboard check` from the repo
root. Toucan's nested `SHA256SUMS` is itself the original capture manifest: it
also names omitted temporary scripts/research files. Use the root manifest for
this curated set. Do not reformat the raw JSON or overwrite original exports.

Provenance and capture artifacts include local paths, device serials and a
Bluetooth address. They contain no pairing keys/passwords, but device identifiers
may be worth redacting in a separately prepared public sharing copy. Prefer the
standalone intended-layout HTML for showing the configuration to others.
