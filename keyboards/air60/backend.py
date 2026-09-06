#!/usr/bin/env python3
"""Air60 V2 VIA keymap-only backend. No third-party runtime dependencies."""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import stat
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PROFILE = "nuphy-f1856912d603800eaca227ae2e1c5c8548fdf261"
VID, PID = 0x19F5, 0x3255
ROWS, COLS, LAYERS = 6, 17, 8
# Exact unnumbered, 32-byte input/output RawReport from pinned usb_descriptor.c.
DESCRIPTOR = bytes.fromhex(
    "0660ff0961a1010962150026ff009520750881020963150026ff00952075089102c0"
)


class Air60Error(RuntimeError):
    pass


def load(path=HERE / "layout.json"):
    return json.loads(Path(path).read_text())


BASIC = {"KC_NO": 0, "KC_TRNS": 1}
BASIC.update({"KC_" + chr(65 + n): 4 + n for n in range(26)})
BASIC.update({"KC_" + str(n): 29 + n for n in range(1, 10)})
BASIC["KC_0"] = 39
BASIC.update(dict(zip(
    ("KC_ENT KC_ESC KC_BSPC KC_TAB KC_SPC KC_MINS KC_EQL KC_LBRC KC_RBRC "
     "KC_BSLS KC_NUHS KC_SCLN KC_QUOT KC_GRV KC_COMM KC_DOT KC_SLSH KC_CAPS").split(),
    range(40, 58))))
BASIC.update({f"KC_F{n}": 57 + n for n in range(1, 13)})
BASIC.update(dict(zip("KC_PSCR KC_SCRL KC_PAUS KC_INS KC_HOME KC_PGUP KC_DEL KC_END KC_PGDN KC_RGHT KC_LEFT KC_DOWN KC_UP".split(), range(70, 83))))
BASIC.update(dict(zip("KC_LCTL KC_LSFT KC_LALT KC_LGUI KC_RCTL KC_RSFT KC_RALT KC_RGUI".split(), range(224, 232))))
BASIC.update({"KC_MUTE": 0xA8, "KC_VOLU": 0xA9, "KC_VOLD": 0xAA,
              "KC_MNXT": 0xAB, "KC_MPRV": 0xAC, "KC_MPLY": 0xAE,
              "KC_BRIU": 0xBD, "KC_BRID": 0xBE})
# Legacy RGB aliases, not the newer RM_* range.
BASIC.update({"RGB_MOD": 0x7821, "RGB_HUI": 0x7823, "RGB_VAI": 0x7827,
              "RGB_VAD": 0x7828, "RGB_SPI": 0x7829, "RGB_SPD": 0x782A})
MODS = {"MOD_LCTL": 1, "MOD_LSFT": 2, "MOD_LALT": 4, "MOD_LGUI": 8,
        "MOD_RCTL": 17, "MOD_RSFT": 18, "MOD_RALT": 20, "MOD_RGUI": 24}


def encode(text):
    """Strict, non-evaluating subset of pinned QMK/VIA keycode syntax."""
    if not isinstance(text, str):
        raise Air60Error("Keycode must be a VIA string")
    if text in BASIC:
        return BASIC[text]
    if m := re.fullmatch(r"CUSTOM\((\d+)\)", text):
        n = int(m[1])
        if n < 24:
            return 0x7E00 + n
    if m := re.fullmatch(r"MO\((\d+)\)", text):
        if int(m[1]) < LAYERS:
            return 0x5220 | int(m[1])
    if m := re.fullmatch(r"LT\((\d+),(KC_[A-Z0-9]+)\)", text):
        if int(m[1]) < LAYERS and m[2] in BASIC and 4 <= BASIC[m[2]] <= 0xFF:
            return 0x4000 | int(m[1]) << 8 | BASIC[m[2]]
    if m := re.fullmatch(r"MT\((MOD_[A-Z]+(?:\s*\|\s*MOD_[A-Z]+)*),(KC_[A-Z0-9]+)\)", text):
        names = re.split(r"\s*\|\s*", m[1])
        if all(n in MODS for n in names) and m[2] in BASIC and 4 <= BASIC[m[2]] <= 0xFF:
            mods = 0
            for n in names:
                mods |= MODS[n]
            return 0x2000 | mods << 8 | BASIC[m[2]]
    if m := re.fullmatch(r"LSFT\((KC_[A-Z0-9]+)\)", text):
        if m[1] in BASIC and 4 <= BASIC[m[1]] <= 0xFF:
            return 0x0200 | BASIC[m[1]]
    raise Air60Error(f"Unverified keycode or layer: {text!r}")


def validate(layout):
    if not isinstance(layout, dict) or set(layout) != {"name", "vendorProductId", "macros", "layers", "encoders"}:
        raise Air60Error("Expected native VIA export fields")
    if layout["name"] != "NuPhy Air60 V2" or layout["vendorProductId"] != (VID << 16 | PID):
        raise Air60Error("Wrong layout identity")
    if layout["macros"] != [""] * 16 or layout["encoders"] != []:
        raise Air60Error("Only keymap management supported; macros/encoders must be empty")
    layers = layout["layers"]
    if not isinstance(layers, list) or len(layers) != LAYERS:
        raise Air60Error("Expected eight layers")
    if any(not isinstance(row, list) or len(row) != ROWS * COLS for row in layers):
        raise Air60Error("Expected 102 row-major matrix cells per layer")
    return [[encode(code) for code in row] for row in layers]


def discover():
    """Sysfs only; no HID requests. Match wired identity AND exact raw descriptor."""
    devices = []
    for entry in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        device = entry / "device"
        fields = dict(line.split("=", 1) for line in (device / "uevent").read_text().splitlines() if "=" in line)
        if fields.get("HID_ID") != "0003:000019F5:00003255":
            continue
        if (device / "report_descriptor").read_bytes() != DESCRIPTOR:
            continue
        usb = next((p for p in device.resolve().parents if (p / "idVendor").exists()), None)
        if usb is None or (usb / "idVendor").read_text().strip() != "19f5" or (usb / "idProduct").read_text().strip() != "3255":
            raise Air60Error("USB ancestry does not match HID identity")
        devices.append({"path": "/dev/" + entry.name, "sysfs": str(device.resolve()),
                        "vid": VID, "pid": PID, "descriptor_sha256": hashlib.sha256(DESCRIPTOR).hexdigest(),
                        "serial": fields.get("HID_UNIQ", ""),
                        "bcdDevice": (usb / "bcdDevice").read_text().strip()})
    return devices


def select_device(devices, path=None):
    matches = [d for d in devices if path is None or d["path"] == path]
    if len(matches) != 1:
        raise Air60Error("Missing/ambiguous Air60 raw interface; select exact --device /dev/hidrawN")
    return matches[0]


class Hidraw:
    """Cooperative lock + same-effective-UID FD audit; no hard exclusivity."""
    def __init__(self, path=None):
        self.audit_warned = False
        self.identity = select_device(discover(), path)
        self.fd = os.open(self.identity["path"], os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.guard()
        except BaseException:
            os.close(self.fd)
            raise

    def close(self):
        os.close(self.fd)

    def guard(self):
        if select_device(discover(), self.identity["path"]) != self.identity:
            raise Air60Error("Device identity changed")
        own = os.fstat(self.fd)
        target = os.stat(self.identity["path"])
        if not stat.S_ISCHR(own.st_mode) or own.st_rdev != target.st_rdev or own.st_ino != target.st_ino:
            raise Air60Error("Device node changed")
        # Proc directory ownership can become root for non-dumpable processes;
        # use status's effective UID, not its real UID or directory owner.
        euid = os.geteuid()
        incomplete = False
        for process in Path("/proc").iterdir():
            if not process.name.isdigit():
                continue
            try:
                status = (process / "status").read_text()
                uid = re.search(r"^Uid:\s+\d+\s+(\d+)\s+\d+\s+\d+\s*$", status, re.MULTILINE)
                if uid is None:
                    raise Air60Error(f"Cannot determine effective UID: {process}/status")
                if int(uid[1]) != euid:
                    continue
                for fd in (process / "fd").iterdir():
                    if int(process.name) == os.getpid() and fd.name == str(self.fd):
                        continue
                    try:
                        other = fd.stat()
                    except FileNotFoundError:
                        continue
                    except PermissionError:
                        incomplete = True
                        continue
                    if stat.S_ISCHR(other.st_mode) and other.st_rdev == own.st_rdev:
                        raise Air60Error(f"Competing HID connection: pid {process.name}")
            except FileNotFoundError:
                continue
            except PermissionError:
                incomplete = True
        if incomplete and not self.audit_warned:
            print("air60: warning: same-effective-UID HID audit incomplete: "
                  "inaccessible process status or FDs; continuing with flock and visible-FD "
                  "checks, not system-wide exclusivity. Close browser/Studio/VIA clients; "
                  "do not use sudo or stop unrelated services.", file=sys.stderr)
            self.audit_warned = True

    def exchange(self, packet):
        self.guard()
        if select.select([self.fd], [], [], 0)[0]:
            raise Air60Error("Unsolicited/stale HID response; refusing request")
        if os.write(self.fd, b"\0" + packet) != 33:
            raise Air60Error("Short HID write")
        if not select.select([self.fd], [], [], 2)[0]:
            raise Air60Error("HID timeout; request outcome unknown")
        return os.read(self.fd, 33)


class Client:
    def __init__(self, transport):
        self.transport = transport
        self.identity = transport.identity

    def request(self, command, data=b"", echo=1):
        packet = (bytes([command]) + data).ljust(32, b"\0")
        if len(packet) != 32 or command not in {1, 2, 4, 5, 0x11, 0x12}:
            raise Air60Error("Disallowed VIA command or length")
        result = self.transport.exchange(packet)
        if len(result) != 32 or result[:echo] != packet[:echo]:
            raise Air60Error(f"Unexpected VIA response to {command:#x}")
        return result

    def capabilities(self):
        if self.identity.get("vid") != VID or self.identity.get("pid") != PID or self.identity.get("descriptor_sha256") != hashlib.sha256(DESCRIPTOR).hexdigest():
            raise Air60Error("Unverified transport identity")
        version = int.from_bytes(self.request(1)[1:3], "big")
        count = self.request(0x11)[1]
        firmware = int.from_bytes(self.request(2, b"\x04", echo=2)[2:6], "big")
        if version != 12 or count != LAYERS or firmware != 0:
            raise Air60Error(f"Unsupported profile: VIA={version}, layers={count}, firmware={firmware}")
        return {"protocol": version, "layers": count, "firmware": firmware,
                "matrix": [ROWS, COLS], "matrix_source": "pinned definition, not runtime discovery"}

    def snapshot(self):
        caps = self.capabilities()
        raw = bytearray()
        for offset in range(0, LAYERS * ROWS * COLS * 2, 28):
            size = min(28, LAYERS * ROWS * COLS * 2 - offset)
            raw.extend(self.request(0x12, offset.to_bytes(2, "big") + bytes([size]), echo=4)[4:4 + size])
        values = [int.from_bytes(raw[i:i + 2], "big") for i in range(0, len(raw), 2)]
        return {"identity": dict(self.identity), "capabilities": caps,
                "layers": [values[i:i + 102] for i in range(0, len(values), 102)],
                "scope": "keymap only; macros, lighting, bonds and other settings untouched"}

    def set_key(self, layer, index, value):
        if not (0 <= layer < LAYERS and 0 <= index < ROWS * COLS and 0 <= value <= 0xFFFF):
            raise Air60Error("Setter bounds")
        data = bytes([layer, index // COLS, index % COLS]) + value.to_bytes(2, "big")
        self.request(5, data, echo=6)
        actual = self.request(4, data[:3], echo=4)
        if actual[4:6] != data[3:5]:
            raise Air60Error(f"Readback mismatch at {layer}:{index // COLS},{index % COLS}")


def diff(snapshot, layout):
    desired = validate(layout)
    current = snapshot["layers"]
    if len(current) != LAYERS or any(len(row) != ROWS * COLS for row in current):
        raise Air60Error("Invalid snapshot dimensions")
    if any(type(v) is not int or not 0 <= v <= 0xFFFF for row in current for v in row):
        raise Air60Error("Invalid raw snapshot keycode")
    return [{"layer": layer, "row": i // COLS, "col": i % COLS,
             "before": before, "after": after, "keycode": layout["layers"][layer][i]}
            for layer in range(LAYERS) for i, (before, after) in enumerate(zip(current[layer], desired[layer]))
            if before != after]


def format_diff(changes):
    return "\n".join(f"L{c['layer']} [{c['row']},{c['col']}] {c['before']:#06x} -> {c['after']:#06x} {c['keycode']}" for c in changes) or "No keymap changes"


def snapshot_to_layout(snapshot):
    """Convert a raw keymap backup to reviewable VIA; reject unknown encodings.

    Empty macro fields are placeholders, never written by this backend.
    """
    reverse = {value: name for name, value in BASIC.items()}
    reverse.update({0x7E00 + n: f"CUSTOM({n})" for n in range(24)})
    reverse.update({0x5220 + n: f"MO({n})" for n in range(LAYERS)})
    for name, value in BASIC.items():
        if not 4 <= value <= 255:
            continue
        reverse[0x0200 | value] = f"LSFT({name})"
        for layer in range(LAYERS):
            reverse[0x4000 | layer << 8 | value] = f"LT({layer},{name})"
        for mods in range(1, 32):
            if mods == 16:
                continue
            side = "R" if mods & 16 else "L"
            names = ["MOD_" + side + suffix for bit, suffix in ((1, "CTL"), (2, "SFT"), (4, "ALT"), (8, "GUI")) if mods & bit]
            reverse[0x2000 | mods << 8 | value] = f"MT({' | '.join(names)},{name})"
    result = load()
    diff(snapshot, result)  # Validate the entire raw shape before conversion.
    try:
        result["layers"] = [[reverse[value] for value in row] for row in snapshot["layers"]]
    except KeyError as exc:
        raise Air60Error(f"Backup contains unverified raw keycode {exc.args[0]:#06x}; preserve it, do not guess") from exc
    validate(result)
    return result


def write_record(path, value):
    """Exclusive, private, fsynced evidence. Never overwrite tracked originals."""
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    fd = os.open(Path(path).parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def apply(client, layout, *, state_dir=None, firmware_profile=None, ack_layout_review=False, emit=print):
    """Explicit mutation API. Full preflight/backup before first immediate setter."""
    validate(layout)
    if firmware_profile != PROFILE:
        raise Air60Error(f"Installed build cannot be attested by VIA; acknowledge reviewed profile {PROFILE}")
    if ack_layout_review is not True:
        raise Air60Error("Apply requires explicit layout review acknowledgement (--ack-layout-review)")
    before = client.snapshot()
    changes = diff(before, layout)
    emit(format_diff(changes))
    if not changes:
        return {"changed": 0, "backup": None}
    root = Path(state_dir) if state_dir else Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "keyboards/air60"
    if root.resolve().is_relative_to(HERE.parent.parent):
        raise Air60Error("Runtime backups must be outside the repository")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="apply-", dir=root))
    parent_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(parent_fd)
    finally:
        os.close(parent_fd)
    write_record(run / "before.json", before)
    write_record(run / "desired.json", layout)
    write_record(run / "diff.json", changes)
    emit(f"Recovery record: {run}")
    # Re-read after durable backup. Never overwrite a concurrent edit.
    if client.snapshot() != before:
        raise Air60Error(f"Device changed during preflight; no setters sent. Backup: {run}")
    attempted, completed = [], []
    try:
        for change in changes:
            attempted.append(change)
            # Persist intent BEFORE sending: even a timeout may have changed EEPROM.
            write_record(run / f"intent-{len(attempted):04d}.json", change)
            client.set_key(change["layer"], change["row"] * COLS + change["col"], change["after"])
            completed.append(change)
        after = client.snapshot()
        write_record(run / "after.json", after)
        if diff(after, layout):
            raise Air60Error("Final full-keymap readback mismatch")
        write_record(run / "result.json", {"status": "verified", "completed": completed})
    except BaseException as exc:
        recovery = {"status": "partial-or-unknown", "error": str(exc),
                    "attempted": attempted, "completed": completed}
        try:
            recovery["readback"] = client.snapshot()
        except Exception as read_error:
            recovery["readback_error"] = str(read_error)
        try:
            write_record(run / "failure.json", recovery)
        except Exception:
            pass  # Durable before/diff/intent records still identify possible changes.
        raise Air60Error(f"Apply failed; EEPROM may be partially changed. No automatic rollback. Recovery: {run}: {exc}") from exc
    return {"changed": len(completed), "backup": str(run)}


def verify(client, layout):
    changes = diff(client.snapshot(), layout)
    if changes:
        raise Air60Error("Keymap mismatch:\n" + format_diff(changes))
    return {"matches": True, "scope": "current keymap readback, not reconnect persistence or typing behavior"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["status", "check", "snapshot", "diff", "apply", "verify"])
    parser.add_argument("--device")
    parser.add_argument("--layout", type=Path, default=HERE / "layout.json")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--firmware-profile", choices=[PROFILE])
    parser.add_argument("--ack-layout-review", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "status":
            print(json.dumps(discover(), indent=2))
            return 0
        layout = None
        if args.command != "snapshot":
            layout = load(args.layout)
            validate(layout)
        if args.command == "check":
            print("Air60 native layout valid (offline); no installed-firmware claim")
            return 0
        if args.command == "apply" and (args.firmware_profile != PROFILE or not args.ack_layout_review):
            raise Air60Error("Apply requires both --firmware-profile and --ack-layout-review")
        with contextlib.closing(Hidraw(args.device)) as transport:
            client = Client(transport)
            if args.command == "snapshot":
                print(json.dumps(client.snapshot(), indent=2))
            elif args.command == "diff":
                print(format_diff(diff(client.snapshot(), layout)))
            elif args.command == "verify":
                print(json.dumps(verify(client, layout)))
            else:
                print(json.dumps(apply(client, layout, state_dir=args.state_dir,
                                       firmware_profile=args.firmware_profile, ack_layout_review=args.ack_layout_review)))
        return 0
    except (Air60Error, OSError, ValueError, KeyError, TypeError) as exc:
        print(f"air60: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
