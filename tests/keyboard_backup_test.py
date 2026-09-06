#!/usr/bin/env python3
"""Offline Air60 backup destination regressions; no device access."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("air60_backup_backend", ROOT / "keyboards/air60/backend.py")
air = importlib.util.module_from_spec(spec)
spec.loader.exec_module(air)


class Air60BackupTests(unittest.TestCase):
    def test_backup_rejects_repository_and_symlink_alias_before_mkdir(self):
        layout = air.load()
        before = {"layers": air.validate(layout)}
        before["layers"][0][0] = air.encode("KC_F12")
        with tempfile.TemporaryDirectory() as tmp:
            alias = Path(tmp) / "repo"
            alias.symlink_to(ROOT, target_is_directory=True)
            for root in (ROOT, ROOT / ".state", ROOT / "keyboards/snapshots",
                         alias, alias / ".state"):
                for explicit in (True, False):
                    client = Mock()
                    client.snapshot.return_value = before
                    with self.subTest(root=root, explicit=explicit), \
                            patch.dict(os.environ, {"XDG_STATE_HOME": str(root)}), \
                            patch.object(Path, "mkdir") as mkdir:
                        with self.assertRaisesRegex(air.Air60Error, "outside the repository"):
                            air.apply(client, layout, state_dir=root if explicit else None,
                                      firmware_profile=air.PROFILE, ack_layout_review=True,
                                      emit=lambda text: None)
                        mkdir.assert_not_called()
                        client.set_key.assert_not_called()


if __name__ == "__main__":
    unittest.main()
