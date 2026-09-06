#!/usr/bin/env python3
"""Wrapper contract tests: no device access or privileged operations."""
import contextlib
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("keyboard_cli", str(ROOT / "keyboards/keyboard"))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)


class KeyboardCLI(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(os, "geteuid", return_value=1000))
        self.stdout = self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.stderr = self.stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.run = self.stack.enter_context(patch.object(subprocess, "run", return_value=
            subprocess.CompletedProcess([], 0, stdout='{"fixture": true}\n')))

    def test_default_help_never_opens_device(self):
        self.assertEqual(cli.main([]), 0)
        self.run.assert_not_called()
        self.assertIn("usage:", self.stdout.getvalue())

    def test_snapshot_hashes(self):
        cli.check_snapshots()

    def test_empty_manifest_prevents_backend_dispatch(self):
        with patch.object(Path, "read_text", return_value=""):
            self.assertEqual(cli.main(["check"]), 1)
        self.run.assert_not_called()

    def test_unknown_option_is_an_error(self):
        with self.assertRaises(SystemExit):
            cli.main(["--bogus"])
        self.run.assert_not_called()

    def test_aggregate_check_is_only_checks(self):
        self.assertEqual(cli.main(["check"]), 0)
        self.assertEqual(self.run.call_count, 3)
        for call in self.run.call_args_list:
            self.assertEqual(call.args[0][-1], "check")

    def test_backend_failure_propagates(self):
        self.run.return_value.returncode = 1
        self.assertEqual(cli.main(["status"]), 1)
        self.assertEqual(self.run.call_count, 3)

    def test_apply_needs_explicit_target(self):
        with self.assertRaises(SystemExit):
            cli.main(["apply"])
        self.run.assert_not_called()

    def test_no_flash_command(self):
        with self.assertRaises(SystemExit):
            cli.main(["flash", "toucan"])
        self.run.assert_not_called()

    def test_apply_refuses_other_hosts(self):
        with patch.object(Path, "is_dir", return_value=False):
            self.assertEqual(cli.main(["apply", "air60"]), 1)
        self.run.assert_not_called()

    def test_help_routes_without_hardware_options(self):
        self.assertEqual(cli.main(["apply", "air60", "--help"]), 0)
        self.assertEqual(self.run.call_args.args[0][-2:], ["apply", "--help"])

    def test_device_snapshot_saved_only_on_success(self):
        with patch.object(cli, "save_snapshot", return_value=Path("/fixture/snapshot.json")) as save:
            self.assertEqual(cli.main(["snapshot", "toucan"]), 0)
            save.assert_called_once_with("toucan", '{"fixture": true}\n')
            self.run.return_value.returncode = 1
            self.assertEqual(cli.main(["snapshot", "toucan"]), 1)
            self.assertEqual(save.call_count, 1)

    def test_private_snapshot_permissions_and_originals_untouched(self):
        uid = os.getuid()
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"XDG_STATE_HOME": tmp}), \
                patch.object(os, "geteuid", return_value=uid):
            path = cli.save_snapshot("toucan", '{"fixture": true}\n')
            self.assertTrue(path.is_relative_to(Path(tmp)))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(path.read_text(), '{"fixture": true}\n')
        cli.check_snapshots()

    def test_snapshot_rejects_repository_and_symlink_alias_before_mkdir(self):
        with tempfile.TemporaryDirectory() as tmp:
            alias = Path(tmp) / "repo"
            alias.symlink_to(ROOT, target_is_directory=True)
            for state in (ROOT, ROOT / ".state", ROOT / "keyboards/snapshots",
                          alias, alias / ".state"):
                with self.subTest(state=state), \
                        patch.dict(os.environ, {"XDG_STATE_HOME": str(state)}), \
                        patch.object(Path, "mkdir") as mkdir:
                    with self.assertRaisesRegex(ValueError, "outside the repository"):
                        cli.save_snapshot("toucan", '{"fixture": true}\n')
                    mkdir.assert_not_called()

    def test_root_cannot_operate_firmware_devices(self):
        with patch.object(os, "geteuid", return_value=0):
            self.assertEqual(cli.main(["apply", "toucan"]), 1)
        self.run.assert_not_called()

    def test_root_cannot_open_reference(self):
        with patch.object(os, "geteuid", return_value=0):
            self.assertEqual(cli.main(["reference"]), 1)
        self.run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
