#!/usr/bin/env python3
"""Isolated keyd tests; never elevate, install live files, or reload keyd."""
import importlib.util
import copy
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("keyboard_keyd", ROOT / "keyboards/keyd/backend.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class KeydTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="keyd-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.target = self.root / "etc-keyd"
        self.target.mkdir()
        self.state = self.root / "state"
        for name in backend.NAMES:
            (self.target / name).write_bytes((backend.ORIGINAL / name).read_bytes())
        self.before = backend.tree(self.target)
        self.wanted = backend.desired()
        self.calls = []
        self.writes = []

    def runner(self, args):
        self.calls.append(args)
        output = ""
        if args[-1] == "--help":
            output = "Commands:\n    check [<config file>...] Check config\n"
        elif "is-active" in args:
            output = "active\n"
        elif "check" in args:
            for name in args[2:]:
                self.assertNotIn("include ", Path(name).read_text())
        return subprocess.CompletedProcess(args, 0, output, "")

    def writer(self, path, data, mode=0o644, uid=0, gid=0):
        backups = list(self.state.glob("keyd-*/manifest.json"))
        self.assertEqual(len(backups), 1, "backup must precede every install write")
        manifest = json.loads(backups[0].read_text())
        for name, original in self.before.items():
            self.assertEqual((backups[0].parent / name).read_bytes(), original)
            self.assertEqual(manifest[name]["sha256"], backend.digest(original))
        self.writes.append(path.name)
        backend.replace(path, data, mode, os.getuid(), os.getgid())

    def apply(self, **kwargs):
        options = dict(execute=True, layout_ack=True, privileged=True,
                       runner=self.runner, writer=self.writer)
        options.update(kwargs)
        return backend.apply(self.target, self.state, self.wanted, **options)

    def test_original_hashes(self):
        for line in (backend.ORIGINAL / "SHA256SUMS").read_text().splitlines():
            expected, name = line.split()
            self.assertEqual(backend.digest((backend.ORIGINAL / name).read_bytes()), expected)

    def test_staging_preserves_device_includes(self):
        for device, include in (("toucan", "home-row-mods"), ("air60", "shared-layers")):
            self.assertIn(f"include legacy-{include}".encode(), self.wanted[device + ".conf"])
            self.assertEqual(self.wanted["legacy-" + include], self.before[include])

    def test_generic_physical_positions(self):
        layers = self.wanted["shared-layers"].decode()
        base = self.wanted["default.conf"].decode()
        self.assertIn("b = overloadt(nav, b, 200)", layers)
        self.assertNotIn("overloadt(symbols, b", layers)
        self.assertIn("j = overloadt(control, h, 200)", base)
        self.assertIn("semicolon = overloadt(meta, l, 200)", base)
        self.assertIn("leftbrace = p", base)
        self.assertIn("rightbrace = backslash", base)
        self.assertIn("comma = volumedown", layers)
        self.assertIn("dot = volumeup", layers)
        self.assertIn("minus = f11", layers)
        self.assertIn("equal = f12", layers)

    def test_success_and_noop(self):
        result = self.apply()
        self.assertEqual(result["result"], "installed")
        self.assertFalse(result["runtime_verified"])
        self.assertEqual(backend.tree(self.target), self.wanted)
        self.calls.clear()
        self.writes.clear()
        self.assertEqual(self.apply()["result"], "unchanged")
        self.assertEqual(self.writes, [])
        self.assertFalse(any("reload" in call for call in self.calls))
        self.assertEqual(len(list(self.state.iterdir())), 1)

    def test_explicit_boundary(self):
        for flags in ({"execute": False}, {"layout_ack": False}, {"privileged": False}):
            with self.assertRaises(backend.Blocked):
                self.apply(**flags)
        self.assertFalse(self.state.exists())
        self.assertEqual(self.calls, [])

    def test_conflicts_precede_backup_and_commands(self):
        for name in ("default.conf", "unknown.conf"):
            p = self.target / name
            previous = p.read_bytes() if p.exists() else None
            p.write_text("[ids]\n*\n[main]\na = b\n")
            with self.assertRaises(backend.Blocked):
                self.apply()
            if previous is None:
                p.unlink()
            else:
                p.write_bytes(previous)
        self.assertEqual(self.calls, [])
        self.assertFalse(self.state.exists())

    def test_symlink_refused(self):
        (self.target / "default.conf").unlink()
        (self.target / "default.conf").symlink_to(backend.ORIGINAL / "default.conf")
        with self.assertRaises(backend.Blocked):
            self.apply()
        self.assertFalse(self.state.exists())

    def test_missing_validation_capability(self):
        def unsupported(args):
            return subprocess.CompletedProcess(args, 0, "usage: keyd reload", "")
        with self.assertRaisesRegex(backend.Blocked, "no supported offline validator"):
            self.apply(runner=unsupported)
        self.assertFalse(self.state.exists())

    def test_parser_warning_blocks(self):
        def warning(args):
            result = self.runner(args)
            if "check" in args:
                result.stderr = "WARNING invalid binding"
            return result
        with self.assertRaises(backend.Blocked):
            self.apply(runner=warning)
        self.assertFalse(self.state.exists())

    def test_include_escape_and_cycle(self):
        for data in (b"include /etc/keyd/shared-layers\n", b"include default.conf\n"):
            with self.assertRaises(backend.Blocked):
                backend.validate({"default.conf": data}, self.runner)

    def test_reload_failure_restores_bytes_modes_and_absence(self):
        (self.target / "default.conf").chmod(0o640)
        reloads = 0
        def failing(args):
            nonlocal reloads
            result = self.runner(args)
            if "reload" in args:
                reloads += 1
                if reloads == 1:
                    result.returncode = 1
            return result
        with self.assertRaisesRegex(backend.Blocked, "backup/recovery record"):
            self.apply(runner=failing)
        self.assertEqual(backend.tree(self.target), self.before)
        self.assertEqual(stat.S_IMODE((self.target / "default.conf").stat().st_mode), 0o640)
        self.assertEqual(reloads, 2)
        report = json.loads(next(self.state.glob("*/recovery.json")).read_text())
        self.assertTrue(report["files_restored"])

    def test_partial_write_failure_restores(self):
        failed = False
        def failing(path, data, *metadata):
            nonlocal failed
            self.writer(path, data, *metadata)
            if not failed:
                failed = True
                raise OSError("disconnect after atomic replacement")
        with self.assertRaises(backend.Blocked):
            self.apply(writer=failing)
        self.assertEqual(backend.tree(self.target), self.before)

    def test_backup_failure_prevents_writes(self):
        self.state.mkdir(mode=0o755)
        with self.assertRaisesRegex(backend.Blocked, "0700"):
            self.apply()
        self.assertEqual(self.writes, [])
        self.assertEqual(backend.tree(self.target), self.before)

    def test_inactive_service_prevents_backup(self):
        def inactive(args):
            result = self.runner(args)
            if "is-active" in args:
                result.returncode = 3
                result.stdout = "inactive"
            return result
        with self.assertRaisesRegex(backend.Blocked, "active before apply"):
            self.apply(runner=inactive)
        self.assertFalse(self.state.exists())
        self.assertEqual(self.writes, [])

    def test_readback_mismatch_is_failure(self):
        def corrupt(path, data, *metadata):
            self.writer(path, data, *metadata)
            if path.name == "default.conf":
                path.write_bytes(b"corrupt data\n")
        with self.assertRaisesRegex(backend.Blocked, "readback mismatch"):
            self.apply(writer=corrupt)
        report = json.loads(next(self.state.glob("*/recovery.json")).read_text())
        self.assertFalse(report["files_restored"])
        self.assertTrue(report["recovery_errors"])

    def test_reload_timeout_and_failed_recovery_reported(self):
        def timeout(args):
            if "reload" in args:
                raise backend.Blocked("mock timeout")
            return self.runner(args)
        with self.assertRaises(backend.Blocked):
            self.apply(runner=timeout)
        self.assertEqual(backend.tree(self.target), self.before)
        report = json.loads(next(self.state.glob("*/recovery.json")).read_text())
        self.assertTrue(report["files_restored"])
        self.assertTrue(report["recovery_errors"])

    def test_concurrent_change_after_backup_blocks_install(self):
        validations = 0
        def concurrent(args):
            nonlocal validations
            result = self.runner(args)
            if "check" in args:
                validations += 1
                if validations == 2:
                    (self.target / "default.conf").write_text("external edit\n")
            return result
        with self.assertRaisesRegex(backend.Blocked, "Concurrent change before install"):
            self.apply(runner=concurrent)
        self.assertEqual(self.writes, [])

    def test_concurrent_edit_is_not_overwritten_by_recovery(self):
        def failing(args):
            result = self.runner(args)
            if "reload" in args:
                (self.target / "default.conf").write_text("external edit\n")
                result.returncode = 1
            return result
        with self.assertRaises(backend.Blocked):
            self.apply(runner=failing)
        self.assertEqual((self.target / "default.conf").read_text(), "external edit\n")
        report = json.loads(next(self.state.glob("*/recovery.json")).read_text())
        self.assertTrue(report["recovery_errors"])

    def test_migration_requires_bound_transport_evidence(self):
        self.wanted = backend.desired(["toucan"])
        with self.assertRaises(backend.Blocked):
            self.apply()
        with self.assertRaises(backend.Blocked):
            self.apply(migrate=["toucan"], acknowledged=["toucan"])
        record = {"profile_sha256": backend.digest(self.wanted["toucan.conf"]),
                  "firmware_sha256": "a" * 64,
                  "readback_at": "2026-09-05", "readback_record": "fixture-only persisted readback",
                  "transports": {"usb": {"status": "verified", "keyd_id": "k:1d50:615e:982e9afd",
                                          "identity_record": "fixture-only"}}}
        with self.assertRaisesRegex(backend.Blocked, "bluetooth"):
            self.apply(migrate=["toucan"], acknowledged=["toucan"], evidence={"toucan": record})
        self.assertFalse(self.state.exists())
        record["transports"]["bluetooth"] = {"status": "not-used", "reason": "fixture", "disconnected": True,
                                              "keyd_ids": ["k:1d50:615e:b1063934"]}
        result = self.apply(migrate=["toucan"], acknowledged=["toucan"], evidence={"toucan": record})
        self.assertFalse(result["runtime_verified"])
        self.assertIn(b"include legacy-shared-layers", (self.target / "air60.conf").read_bytes())
        self.wanted = backend.desired()
        with self.assertRaisesRegex(backend.Blocked, "reversal"):
            self.apply()

    def test_air60_test_pass_through_accounts_for_unused_selector(self):
        self.wanted = backend.desired(["air60"])
        usb_ids = ["k:19f5:3255:e3746a94", "k:19f5:3255:0d7157bb",
                   "k:19f5:3255:a10585ca", "k:19f5:3255:921cd195"]
        bluetooth_ids = ["k:19f5:3246:838051e9", "k:19f5:3246:7b6b2fa7"]
        self.assertEqual(self.wanted["air60.conf"].decode().split("[ids]\n")[1],
                         "\n".join([*usb_ids, *bluetooth_ids, "", "[main]", ""]))
        self.assertEqual({n: v for n, v in self.wanted.items() if n != "air60.conf"},
                         {n: v for n, v in backend.desired().items() if n != "air60.conf"})
        record = {
            "profile_sha256": backend.digest(self.wanted["air60.conf"]),
            "firmware_sha256": "a" * 64,
            "readback_at": "2026-09-05",
            "readback_record": "fixture-only intended keymap after persistence",
            "transports": {
                "usb": {"status": "verified", "keyd_ids": usb_ids,
                        "identity_record": "fixture-only journal covering all four USB keyboard-class interfaces"},
                "bluetooth": {"status": "not-used", "reason": "identity unverified; disabled for testing",
                              "disconnected": True, "keyd_ids": bluetooth_ids},
                "receiver": {"status": "not-used", "reason": "receiver unplugged", "disconnected": True}
            }
        }
        mutations = [
            (("profile_sha256",), "b" * 64),
            (("firmware_sha256",), "invalid"),
            (("readback_at",), ""),
            (("readback_record",), None),
            (("transports", "usb", "identity_record"), ""),
            (("transports", "usb", "status"), "unknown"),
            (("transports", "usb", "keyd_id"), usb_ids[0]),
            (("transports", "usb", "keyd_id"), None),
            (("transports", "usb", "keyd_ids"), []),
            (("transports", "usb", "keyd_ids"), None),
            (("transports", "usb", "keyd_ids"), usb_ids[0]),
            (("transports", "usb", "keyd_ids"), [*usb_ids, usb_ids[0]]),
            (("transports", "usb", "keyd_ids"), [*usb_ids, "k:ffff:ffff:ffffffff"]),
            (("transports", "usb", "keyd_ids"), [*usb_ids, "invalid"]),
            (("transports", "usb", "keyd_ids"), [*usb_ids, {}]),
            (("transports", "usb", "keyd_ids"), usb_ids[1:]),
            (("transports", "usb"), {"status": "verified", "identity_record": "fixture-only"}),
            (("transports", "usb"), {"status": "verified", "keyd_id": usb_ids[1],
                                      "identity_record": "fixture-only incomplete USB coverage"}),
            (("transports", "bluetooth", "disconnected"), False),
            (("transports", "bluetooth", "disconnected"), "true"),
            (("transports", "bluetooth", "reason"), " "),
            (("transports", "bluetooth", "keyd_ids"), []),
            (("transports", "bluetooth", "keyd_ids"), bluetooth_ids[:1]),
            (("transports", "bluetooth", "keyd_ids"), ["k:ffff:ffff:ffffffff"]),
            (("transports", "bluetooth", "keyd_ids"), "k:19f5:3246:838051e9"),
            (("transports", "bluetooth", "keyd_ids"), [{}]),
            (("transports", "receiver"), {}),
            (("transports", "usb"), {"status": "not-used", "reason": "unplugged", "disconnected": True,
                                      "keyd_ids": ["k:19f5:3255:0d7157bb"]}),
        ]
        for path, value in mutations:
            with self.subTest(path=path, value=value):
                bad = copy.deepcopy(record)
                parent = bad
                for key in path[:-1]:
                    parent = parent[key]
                parent[path[-1]] = value
                with self.assertRaises(backend.Blocked):
                    self.apply(migrate=["air60"], acknowledged=["air60"], evidence={"air60": bad})
                self.assertEqual(self.calls, [])
                self.assertEqual(self.writes, [])
                self.assertFalse(self.state.exists())
        with self.assertRaises(backend.Blocked):
            self.apply(migrate=["air60"], acknowledged=["toucan"], evidence={"air60": record})
        # No physical-behavior claim is necessary to start testing without keyd overlap.
        result = self.apply(migrate=["air60"], acknowledged=["air60"], evidence={"air60": record})
        self.assertEqual(result["result"], "installed")
        self.assertFalse(result["runtime_verified"])
        self.assertEqual((self.target / "air60.conf").read_bytes(), (backend.SOURCE / "air60.conf").read_bytes())
        self.assertIn(b"include legacy-home-row-mods", (self.target / "toucan.conf").read_bytes())

    def test_readonly_operations_never_reload(self):
        backend.conflicts(self.before, self.wanted)
        backend.validate(self.wanted, self.runner)
        self.assertIn("legacy-shared-layers", backend.diff(self.before, self.wanted))
        self.assertFalse(any("reload" in call for call in self.calls))
        self.assertEqual(backend.tree(self.target), self.before)
        self.assertFalse(self.state.exists())

    def test_backup_rejects_repository_and_symlink_alias_before_mkdir(self):
        alias = self.root / "repo"
        alias.symlink_to(ROOT, target_is_directory=True)
        for state in (ROOT, ROOT / ".state", ROOT / "keyboards/snapshots",
                      alias, alias / ".state"):
            for apply in (False, True):
                with self.subTest(state=state, apply=apply), \
                        patch.object(Path, "mkdir") as mkdir:
                    self.state = state
                    with self.assertRaisesRegex(backend.Blocked, "outside the repository"):
                        if apply:
                            self.apply()
                        else:
                            backend.snapshot(self.target, state)
                    mkdir.assert_not_called()
                    self.assertEqual(self.writes, [])
                    self.assertEqual(backend.tree(self.target), self.before)
                    self.assertFalse(any("reload" in call for call in self.calls))

    def test_snapshot_private_and_immutable(self):
        first, _, _ = backend.snapshot(self.target, self.state)
        second, _, _ = backend.snapshot(self.target, self.state)
        self.assertNotEqual(first, second)
        self.assertEqual(stat.S_IMODE(first.stat().st_mode), 0o700)
        for path in first.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(backend.tree(self.target), self.before)


if __name__ == "__main__":
    unittest.main()
