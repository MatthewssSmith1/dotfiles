#!/usr/bin/env python3
"""Offline Air60 contracts. No device access, external packages or setters."""
import copy
import contextlib
import hashlib
import importlib.util
import io
import json
import re
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


air = module("air60_backend", ROOT / "keyboards/air60/backend.py")
prepare = module("air60_prepare", ROOT / "keyboards/air60/prepare_layout.py")


class MockHID:
    """Emulates actual VIA echo framing and immediately persisted keymap memory."""
    def __init__(self, layout):
        self.identity = {"vid": air.VID, "pid": air.PID,
                         "descriptor_sha256": hashlib.sha256(air.DESCRIPTOR).hexdigest(),
                         "path": "/dev/mock-air60"}
        self.memory = bytearray(b"".join(v.to_bytes(2, "big") for row in air.validate(layout) for v in row))
        self.calls = []
        self.version = 12
        self.layers = 8
        self.firmware = 0
        self.fail_set = None
        self.ignore_set = False
        self.corrupt_echo = False
        self.short = False
        self.on_set = lambda: None

    @property
    def setters(self):
        return [call for call in self.calls if call[0] == 5]

    def exchange(self, packet):
        assert len(packet) == 32
        self.calls.append(packet)
        out = bytearray(packet)
        command = packet[0]
        if command == 1:
            out[1:3] = self.version.to_bytes(2, "big")
        elif command == 0x11:
            out[1] = self.layers
        elif command == 2:
            assert packet[1] == 4
            out[2:6] = self.firmware.to_bytes(4, "big")
        elif command == 0x12:
            offset, size = int.from_bytes(packet[1:3], "big"), packet[3]
            assert 0 < size <= 28 and offset + size <= len(self.memory)
            out[4:4 + size] = self.memory[offset:offset + size]
        elif command in (4, 5):
            layer, row, col = packet[1:4]
            assert layer < 8 and row < 6 and col < 17
            offset = ((layer * 6 + row) * 17 + col) * 2
            if command == 4:
                out[4:6] = self.memory[offset:offset + 2]
            else:
                self.on_set()
                if not self.ignore_set:
                    self.memory[offset:offset + 2] = packet[4:6]
                if self.fail_set == len(self.setters):
                    raise air.Air60Error("disconnect after EEPROM mutation")
        else:
            raise AssertionError(f"Unexpected command: {command}")
        if self.corrupt_echo:
            out[0] = 0xFF
        return bytes(out[:-1] if self.short else out)


class Air60Tests(unittest.TestCase):
    def setUp(self):
        self.layout = air.load()
        self.hid = MockHID(self.layout)
        self.client = air.Client(self.hid)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def changed(self):
        result = copy.deepcopy(self.layout)
        result["layers"][0][0] = "KC_F12"
        result["layers"][0][18] = "KC_F11"
        return result

    def apply(self, layout=None, **kwargs):
        return air.apply(self.client, layout or self.changed(), state_dir=self.tmp.name,
                         firmware_profile=air.PROFILE, ack_layout_review=True,
                         emit=lambda text: None, **kwargs)

    def test_original_hashes_and_native_regeneration(self):
        root = ROOT / "keyboards/snapshots/air60"
        for line in (root / "SHA256SUMS").read_text().splitlines():
            digest, name = line.split()
            self.assertEqual(hashlib.sha256((root / name).read_bytes()).hexdigest(), digest)
        self.assertEqual(self.layout, prepare.desired_layout())
        definition = air.load(root / "via-definition.json")
        self.assertEqual(definition["matrix"], {"rows": 6, "cols": 17})
        self.assertEqual(len(definition["customKeycodes"]), 24)
        self.assertEqual(definition["customKeycodes"][19]["title"], "Device Reset")

    def test_plain_and_enhanced_physical_mapping(self):
        enhanced, plain = self.layout["layers"][0], self.layout["layers"][3]
        self.assertEqual(hashlib.sha256(json.dumps(enhanced, separators=(",", ":")).encode()).hexdigest(),
                         "631385c672f3a7bd35dad6649fc94a5fbd71aa83ab854a1f3de8df9dcb2b11f0")
        expected_plain = [re.sub(r"(?:MT\(MOD_\w+|LT\(\d+),(KC_\w+)\)", r"\1", key)
                          for key in enhanced]
        for (row, col), key in {
            (2, 0): "TAB", (3, 0): "CAPS", (4, 0): "LSFT",
            (5, 2): "LALT", (5, 9): "RALT", (2, 6): "QUOT",
            (3, 6): "DEL", (4, 7): "LBRC",
        }.items():
            expected_plain[row * 17 + col] = "KC_" + key
        self.assertEqual(plain, expected_plain)
        self.assertFalse(any(k.startswith(("MT(", "LT(")) for k in plain))
        self.assertEqual(sum(k.startswith("MT(") for k in enhanced), 8)
        self.assertEqual(sum(k.startswith("LT(4,") for k in enhanced), 5)
        self.assertEqual(sum(k.startswith("LT(5,") for k in enhanced), 5)
        self.assertEqual(enhanced[plain.index("KC_B")], "LT(4,KC_B)")
        for layer in (plain, enhanced):
            self.assertEqual(layer[5 * 17:5 * 17 + 2], ["KC_LCTL", "KC_LGUI"])
            self.assertEqual(layer[2 * 17 + 14], "MO(6)")
        self.assertEqual(plain[2 * 17 + 7:2 * 17 + 12], ["KC_BSLS", "KC_Y", "KC_U", "KC_I", "KC_O"])

    def test_nav_symbols_functions_choices(self):
        plain = self.layout["layers"][3]
        self.assertEqual(self.layout["layers"][5][4 * 17], "LSFT(KC_GRV)")
        self.assertEqual(self.layout["layers"][0][4 * 17], "KC_LBRC")
        self.assertEqual(plain[4 * 17], "KC_LSFT")
        for key, expected in {"N": "KC_NO", "M": "KC_VOLD", "COMM": "KC_VOLU", "DOT": "KC_NO"}.items():
            self.assertEqual(self.layout["layers"][4][plain.index("KC_" + key)], expected)
        for key, expected in {"N": "LSFT(KC_MINS)", "M": "KC_MINS", "COMM": "LSFT(KC_EQL)", "DOT": "KC_EQL"}.items():
            self.assertEqual(self.layout["layers"][5][plain.index("KC_" + key)], expected)
        for key, custom in zip("QWE", (3, 4, 5)):
            self.assertEqual(self.layout["layers"][6][plain.index("KC_" + key)], f"CUSTOM({custom})")
        flat = sum(self.layout["layers"], [])
        for unwanted in ("CUSTOM(0)", "CUSTOM(19)", "CUSTOM(22)", "MO(1)", "MO(2)"):
            self.assertNotIn(unwanted, flat)
        self.assertEqual(self.layout["layers"][6][plain.index("KC_P")], "KC_F11")
        self.assertEqual(self.layout["layers"][6][2 * 17 + 13], "KC_F12")

    def test_overlays_unchanged_and_retired_unreachable(self):
        prior = copy.deepcopy(self.layout)
        # The approved tilde correction is the sole change to the prior overlays.
        prior["layers"][5][4 * 17] = "KC_TRNS"
        blocks = re.findall(r"    \[\n[\s\S]*?    \]", json.dumps(prior, indent=2))
        self.assertEqual(hashlib.sha256("\n".join(blocks[4:]).encode()).hexdigest(),
                         "aaa8ab5ae5f2025965e04d7325955567a914223067cf86c15d5a4200eecfabcd")
        definition = air.load(ROOT / "keyboards/snapshots/air60/via-definition.json")
        physical = {int(r) * 17 + int(c) for row in definition["layouts"]["keymap"]
                    for entry in row if isinstance(entry, str) for r, c in [entry.split(",")]}
        retired = ["KC_TRNS" if i in physical else "KC_NO" for i in range(102)]
        for layer in (1, 2):
            self.assertEqual(self.layout["layers"][layer], retired)
        for base, reachable in ((0, {4, 5, 6, 7}), (3, {6, 7})):
            found, pending = set(), [base]
            while pending:
                for key in self.layout["layers"][pending.pop()]:
                    match = re.match(r"(?:MO|LT)\((\d+)", key)
                    if match and (target := int(match[1])) not in found:
                        found.add(target)
                        pending.append(target)
            self.assertEqual(found, reachable)

    def test_pinned_encodings(self):
        expected = {"MT(MOD_LGUI,KC_A)": 0x2804, "MT(MOD_RCTL,KC_H)": 0x310B,
                    "MT(MOD_LCTL | MOD_RCTL,KC_H)": 0x310B,
                    "LT(4,KC_B)": 0x4405, "LT(5,KC_SLSH)": 0x4538,
                    "MO(6)": 0x5226, "LSFT(KC_7)": 0x0224,
                    "CUSTOM(3)": 0x7E03, "CUSTOM(23)": 0x7E17,
                    "RGB_MOD": 0x7821, "KC_VOLD": 0xAA, "KC_VOLU": 0xA9}
        for key, code in expected.items():
            self.assertEqual(air.encode(key), code)
        for bad in ("CUSTOM(24)", "MO(8)", "LT(16,KC_A)", "MT(MOD_BAD,KC_A)",
                    "LT(4,RGB_MOD)", "0x7e00", "QK_BOOT", "__import__('os')", 1):
            with self.assertRaises(air.Air60Error):
                air.encode(bad)

    def test_readonly_snapshot_diff_verify(self):
        snapshot = self.client.snapshot()
        self.assertEqual(snapshot["layers"], air.validate(self.layout))
        self.assertEqual(air.diff(snapshot, self.layout), [])
        self.assertTrue(air.verify(self.client, self.layout)["matches"])
        self.assertFalse(self.hid.setters)
        self.assertEqual({p[0] for p in self.hid.calls}, {1, 2, 0x11, 0x12})

    def test_noop_has_no_writes_or_backup(self):
        self.assertEqual(self.apply(self.layout), {"changed": 0, "backup": None})
        self.assertFalse(self.hid.setters)
        self.assertEqual(list(Path(self.tmp.name).iterdir()), [])

    def test_backup_conversion_roundtrip_and_unknown_refusal(self):
        snapshot = self.client.snapshot()
        self.assertEqual(air.validate(air.snapshot_to_layout(snapshot)), snapshot["layers"])
        original = air.load(ROOT / "keyboards/snapshots/air60/original.layout.json")
        original_snapshot = {"layers": air.validate(original)}
        self.assertEqual(air.validate(air.snapshot_to_layout(original_snapshot)), original_snapshot["layers"])
        snapshot["layers"][0][0] = 0xFFFF
        with self.assertRaisesRegex(air.Air60Error, "unverified raw keycode"):
            air.snapshot_to_layout(snapshot)

    def test_entire_layout_validated_before_transport(self):
        bad = self.changed()
        bad["layers"][7][-1] = "CUSTOM(100)"
        with self.assertRaises(air.Air60Error):
            self.apply(bad)
        self.assertFalse(self.hid.calls)

    def test_schema_identity_dimensions_macros(self):
        for key, value in (("vendorProductId", 0), ("macros", ["text"] * 16),
                           ("encoders", [1]), ("layers", [["KC_A"]] * 8)):
            bad = self.changed()
            bad[key] = value
            with self.assertRaises(air.Air60Error):
                self.apply(bad)
        self.assertFalse(self.hid.calls)

    def test_profile_required_before_transport(self):
        with self.assertRaises(air.Air60Error):
            air.apply(self.client, self.changed(), ack_layout_review=True)
        self.assertFalse(self.hid.calls)

    def test_layout_review_required_before_transport_even_for_noop(self):
        for ack in (False, None, "yes", 1):
            with self.assertRaisesRegex(air.Air60Error, "layout review"):
                air.apply(self.client, self.layout, firmware_profile=air.PROFILE, ack_layout_review=ack)
        self.assertFalse(self.hid.calls)

    def test_cli_requires_both_acknowledgements_before_open(self):
        for flags in ([], ["--firmware-profile", air.PROFILE], ["--ack-layout-review"]):
            with patch.object(air, "Hidraw") as hidraw, patch.object(air.sys, "stderr"):
                self.assertEqual(air.main(["apply", *flags]), 1)
                hidraw.assert_not_called()

    def test_cli_passes_layout_acknowledgement(self):
        with patch.object(air, "Hidraw", return_value=self.hid), \
                patch.object(self.hid, "close", create=True), patch.object(air, "apply", return_value={}) as apply, \
                patch.object(air.sys, "stdout"):
            self.assertEqual(air.main(["apply", "--firmware-profile", air.PROFILE, "--ack-layout-review"]), 0)
            self.assertIs(apply.call_args.kwargs["ack_layout_review"], True)
            self.assertEqual(apply.call_args.kwargs["firmware_profile"], air.PROFILE)

    def test_capability_and_transport_identity_fail_closed(self):
        for field, value in (("version", 11), ("layers", 4), ("firmware", 1)):
            with self.subTest(field=field):
                old = getattr(self.hid, field)
                setattr(self.hid, field, value)
                with self.assertRaises(air.Air60Error):
                    self.apply()
                setattr(self.hid, field, old)
        self.hid.identity["pid"] = 0
        with self.assertRaises(air.Air60Error):
            self.apply()
        self.assertFalse(self.hid.setters)

    def test_backup_diff_and_intent_durable_before_setters(self):
        def check():
            run, = Path(self.tmp.name).iterdir()
            for name in ("before.json", "desired.json", "diff.json", "intent-0001.json"):
                self.assertTrue((run / name).exists())
                self.assertEqual((run / name).stat().st_mode & 0o777, 0o600)
            self.assertEqual(run.stat().st_mode & 0o777, 0o700)
        self.hid.on_set = check
        result = self.apply()
        self.assertEqual(result["changed"], 2)
        self.assertEqual(len(self.hid.setters), 2)
        self.assertTrue((Path(result["backup"]) / "after.json").exists())
        self.assertFalse(air.diff(self.client.snapshot(), self.changed()))

    def test_backup_failure_prevents_all_setters(self):
        with patch.object(air, "write_record", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.apply()
        self.assertFalse(self.hid.setters)

    def test_concurrent_change_prevents_setters(self):
        original = self.client.snapshot
        count = 0
        def snapshot():
            nonlocal count
            count += 1
            if count == 2:
                self.hid.memory[0:2] = b"\0\x04"
            return original()
        with patch.object(self.client, "snapshot", side_effect=snapshot):
            with self.assertRaisesRegex(air.Air60Error, "changed during preflight"):
                self.apply()
        self.assertFalse(self.hid.setters)

    def test_partial_timeout_does_not_rollback_and_records_readback(self):
        self.hid.fail_set = 1
        with self.assertRaisesRegex(air.Air60Error, "partially changed"):
            self.apply()
        self.assertEqual(len(self.hid.setters), 1)
        run, = Path(self.tmp.name).iterdir()
        failure = air.load(run / "failure.json")
        self.assertEqual(len(failure["attempted"]), 1)
        self.assertEqual(failure["completed"], [])
        self.assertEqual(failure["readback"]["layers"][0][0], air.encode("KC_F12"))

    def test_mismatched_set_readback_stops(self):
        self.hid.ignore_set = True
        with self.assertRaisesRegex(air.Air60Error, "Readback mismatch"):
            self.apply()
        self.assertEqual(len(self.hid.setters), 1)

    def test_final_full_readback_detects_other_cell_corruption(self):
        def corrupt():
            self.hid.memory[-2:] = b"\0\x04"
        self.hid.on_set = corrupt
        with self.assertRaisesRegex(air.Air60Error, "Final full-keymap readback mismatch"):
            self.apply()
        run, = Path(self.tmp.name).iterdir()
        self.assertTrue((run / "after.json").exists())
        self.assertTrue((run / "failure.json").exists())

    def test_hidraw_framing_and_timeout(self):
        transport = object.__new__(air.Hidraw)
        transport.fd = 99
        packet = bytes([1]).ljust(32, b"\0")
        with patch.object(transport, "guard"), patch.object(air.os, "write", return_value=33) as write, \
                patch.object(air.select, "select", side_effect=[([], [], []), ([99], [], [])]), \
                patch.object(air.os, "read", return_value=packet):
            self.assertEqual(transport.exchange(packet), packet)
            write.assert_called_once_with(99, b"\0" + packet)
        with patch.object(transport, "guard"), patch.object(air.os, "write", return_value=33), \
                patch.object(air.select, "select", return_value=([], [], [])):
            with self.assertRaisesRegex(air.Air60Error, "timeout"):
                transport.exchange(packet)

    def test_hidraw_ambiguity_or_pending_response_prevents_request(self):
        transport = object.__new__(air.Hidraw)
        transport.fd = 99
        with patch.object(transport, "guard", side_effect=air.Air60Error("exclusive ambiguity")), \
                patch.object(air.os, "write") as write:
            with self.assertRaises(air.Air60Error):
                transport.exchange(bytes(32))
            write.assert_not_called()
        with patch.object(transport, "guard"), patch.object(air.select, "select", return_value=([99], [], [])), \
                patch.object(air.os, "write") as write:
            with self.assertRaisesRegex(air.Air60Error, "stale"):
                transport.exchange(bytes(32))
            write.assert_not_called()

    def test_hidraw_incomplete_audit_warns_once_and_competitor_still_fails(self):
        transport = object.__new__(air.Hidraw)
        transport.fd = 99
        transport.identity = {"path": "/dev/hidraw99"}
        own = SimpleNamespace(st_mode=0o020600, st_rdev=1234, st_ino=5678)
        def entries(path):
            if str(path) == '/proc':
                return iter([Path('/proc/234567'), Path('/proc/123456')])
            if path.parent.name == '234567' and inaccessible == 'fd':
                raise PermissionError('hidden unrelated FD table')
            return iter([path/'1'])
        def read_text(path):
            if path.parent.name == '234567' and inaccessible == 'status':
                raise PermissionError('hidden unrelated process status')
            return 'Uid:\t0\t1000\t0\t0\n'
        def fd_stat(path):
            if path.parent.parent.name == '234567' and inaccessible == 'link':
                raise PermissionError('hidden FD link')
            return own if competing else SimpleNamespace(st_mode=0o100600)
        for inaccessible in ('status', 'fd', 'link'):
            transport.audit_warned = False
            competing = False
            with patch.object(air, "discover", return_value=[transport.identity]), \
                    patch.object(air.os, "fstat", return_value=own), \
                    patch.object(air.os, "stat", return_value=own), \
                    patch.object(air.os, "geteuid", return_value=1000), \
                    patch.object(Path, "read_text", read_text), \
                    patch.object(Path, "stat", fd_stat), patch.object(Path, "iterdir", entries), \
                    contextlib.redirect_stderr(io.StringIO()) as errors, \
                    contextlib.redirect_stdout(io.StringIO()) as output, \
                    patch.object(air.os, 'write', return_value=33) as write, \
                    patch.object(air.os, 'read', return_value=bytes(32)), \
                    patch.object(air.select, 'select', side_effect=lambda r,w,x,t: (r if t else [],w,x)):
                with self.subTest(inaccessible=inaccessible):
                    transport.guard()
                    transport.exchange(bytes(32))
                    transport.exchange(bytes(32))
                    self.assertEqual(errors.getvalue().count('warning:'),1)
                    self.assertIn('same-effective-UID HID audit incomplete',errors.getvalue())
                    self.assertIn('not system-wide exclusivity',errors.getvalue())
                    self.assertEqual(output.getvalue(),'')
                    self.assertEqual(write.call_count,2)
                    competing = True
                    with self.assertRaisesRegex(air.Air60Error, 'Competing'):
                        transport.exchange(bytes(32))
                    self.assertEqual(write.call_count,2)

    def test_hidraw_skips_other_effective_uid_fds(self):
        transport = object.__new__(air.Hidraw)
        transport.fd = 99
        transport.identity = {"path": "/dev/hidraw99"}
        own = SimpleNamespace(st_mode=0o020600, st_rdev=1234, st_ino=5678)
        # Same real UID but different effective UID must be outside the FD audit.
        for uid in (0, 1001):
            with patch.object(air, "discover", return_value=[transport.identity]), \
                    patch.object(air.os, "fstat", return_value=own), \
                    patch.object(air.os, "stat", return_value=own), \
                    patch.object(air.os, "geteuid", return_value=1000), \
                    patch.object(Path, "read_text", return_value=f"Uid:\t1000\t{uid}\t1000\t1000\n"), \
                    patch.object(Path, "iterdir", side_effect=[iter([Path("/proc/123456")]), PermissionError("hidden")]) as listing:
                transport.guard()
                self.assertEqual(listing.call_count, 1)

    def test_failed_recovery_read_keeps_original_backup(self):
        self.hid.fail_set = 1
        original = self.client.snapshot
        count = 0
        def snapshot():
            nonlocal count
            count += 1
            if count > 2:
                raise air.Air60Error("unplugged")
            return original()
        with patch.object(self.client, "snapshot", side_effect=snapshot):
            with self.assertRaises(air.Air60Error):
                self.apply()
        run, = Path(self.tmp.name).iterdir()
        self.assertEqual(air.load(run / "failure.json")["readback_error"], "unplugged")
        self.assertTrue((run / "before.json").exists())

    def test_response_echo_and_length_fail_closed(self):
        for field in ("short", "corrupt_echo"):
            setattr(self.hid, field, True)
            with self.assertRaises(air.Air60Error):
                self.apply()
            setattr(self.hid, field, False)
        self.assertFalse(self.hid.setters)

    def test_device_selection_never_guesses(self):
        with self.assertRaises(air.Air60Error):
            air.select_device([])
        devices = [{"path": "/dev/hidraw1"}, {"path": "/dev/hidraw2"}]
        with self.assertRaises(air.Air60Error):
            air.select_device(devices)
        self.assertEqual(air.select_device(devices, "/dev/hidraw2"), devices[1])

    def test_destructive_protocol_commands_not_available(self):
        for command in (3, 6, 7, 9, 10, 11, 15, 16, 19):
            with self.assertRaises(air.Air60Error):
                self.client.request(command)
        self.assertFalse(self.hid.calls)


if __name__ == "__main__":
    unittest.main()
