#!/usr/bin/env python3

import copy
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from desktop_shortcuts_lib import load_manifest, native_references, render, validate_manifest  # noqa: E402


class DesktopShortcutsGeneratorTest(unittest.TestCase):
    def setUp(self):
        self.manifest = load_manifest()

    def assert_invalid(self, mutation, message):
        candidate = copy.deepcopy(self.manifest)
        mutation(candidate)
        with self.assertRaisesRegex(ValueError, message):
            validate_manifest(candidate)

    def test_v2_manifest_and_exact_rendering(self):
        self.assertEqual(self.manifest["version"], 2)
        self.assertEqual(
            self.manifest["_instructions"],
            "After manual edits, run: dotfiles-shortcuts sync",
        )
        rendered = render(self.manifest)
        self.assertEqual(rendered, render(copy.deepcopy(self.manifest)))
        self.assertEqual(
            rendered["xcompose"],
            '<Multi_key> <space> <a> : "AGENTS.md"\n'
            '<Multi_key> <p> <b> : "Continue discussing with me briefly."\n'
            '<Multi_key> <p> <d> : "Continue discussing with me, focussing on points we have yet to agree on."\n'
            '<Multi_key> <p> <p> : "Write an implementation plan for this; put it in a temporary *.md file outside this repo."\n'
            '<Multi_key> <p> <t> : "What do you think/recommend? Discuss with me."\n',
        )
        menu_lines = rendered["menu"].splitlines()
        self.assertIn('"shortcuts.general": {"label":"General (space)"}', menu_lines[1])
        self.assertIn('"shortcuts.prompts": {"label":"Prompts (p)"}', menu_lines[6])
        self.assertIn('"label":"space · Em dash"', rendered["menu"])
        self.assertEqual(
            menu_lines[-1],
            '  "shortcuts.manage": {"label":"Manage shortcuts...","action":"dotfiles-shortcuts manage"},',
        )
        for shortcut_id in ("space-a", "space-e", "space-n", "space-space", "p-b", "p-d", "p-p", "p-t"):
            self.assertIn(f"  {shortcut_id})", rendered["helper"])
        self.assertEqual(
            native_references(self.manifest),
            [
                ("host", "space-e", "Multi_key", "space", "e"),
                ("host", "space-n", "Multi_key", "space", "n"),
                ("omarchy", "space-space", "Multi_key", "space", "space"),
            ],
        )
        for private_output in ("user@example.com", "Example User"):
            self.assertNotIn(private_output, "".join(rendered.values()))

    def test_exact_fields_and_text_shapes(self):
        self.assert_invalid(lambda data: data.update(extra=True), "manifest fields")
        self.assert_invalid(lambda data: data["groups"][0].update(label="General"), "group fields")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(extra=True), "shortcut fields")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(output=""), "shortcut output")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(label="two\nlines"), "shortcut label")
        self.assert_invalid(lambda data: data["shortcuts"][1].update(output="private"), "shortcut fields")
        self.assert_invalid(lambda data: data["shortcuts"][0].pop("output"), "shortcut fields")

    def test_duplicate_ids_routes_sequences_and_prefixes(self):
        self.assert_invalid(
            lambda data: data["shortcuts"][1].update(id="space-a"),
            "duplicate shortcut ID",
        )
        self.assert_invalid(
            lambda data: data["shortcuts"][1].update(key="a"),
            "duplicate shortcut route",
        )
        self.assert_invalid(
            lambda data: (
                data["groups"][1].update(prefix="space"),
                data["shortcuts"][4].update(key="a"),
            ),
            "duplicate Compose sequence",
        )
        self.assert_invalid(
            lambda data: data["groups"][1].update(prefix="space"),
            "duplicate group prefix",
        )
        self.assert_invalid(
            lambda data: data["groups"][1].update(id="general"),
            "duplicate group ID",
        )

    def test_route_and_source_validation(self):
        self.assert_invalid(lambda data: data["groups"][0].update(prefix="bad key"), "group prefix")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(key="bad-key"), "shortcut key")
        self.assert_invalid(lambda data: data["groups"][0].update(prefix="Return"), "group prefix")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(key="underscore"), "shortcut key")
        for supported in ("space", "a", "Z", "0"):
            candidate = copy.deepcopy(self.manifest)
            candidate["shortcuts"][0]["key"] = supported
            if supported == "space":
                candidate["shortcuts"][3]["key"] = "z"
            validate_manifest(candidate)
        self.assert_invalid(lambda data: data["shortcuts"][0].update(group="missing"), "unknown group")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(source="external"), "shortcut source")
        self.assert_invalid(lambda data: data["shortcuts"][0].update(source=[]), "shortcut source")


if __name__ == "__main__":
    unittest.main()
