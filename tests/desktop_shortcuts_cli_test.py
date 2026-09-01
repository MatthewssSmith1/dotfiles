#!/usr/bin/env python3

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import multiprocessing
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
SPEC = importlib.util.spec_from_loader(
    "dotfiles_shortcuts_cli",
    importlib.machinery.SourceFileLoader("dotfiles_shortcuts_cli", str(REPO / "scripts/dotfiles-shortcuts")),
)
CLI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLI)


def concurrent_add(root, key, started, entered, release, result):
    started.set()

    def change(data):
        entered.set()
        if release is not None:
            release.wait(5)
        CLI.add_alias(data, "general", key, key, key)

    try:
        with mock.patch.object(CLI, "_sync"):
            CLI.mutate(Path(root), change)
        result.put(None)
    except Exception as error:
        result.put(repr(error))


def concurrent_sync(root, entered, release, result):
    def hold_sync(_root):
        entered.set()
        release.wait(5)

    try:
        with mock.patch.object(CLI, "_sync", side_effect=hold_sync):
            CLI.sync(Path(root))
        result.put(None)
    except Exception as error:
        result.put(repr(error))


class DesktopShortcutsCliTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repo"
        (self.root / "scripts").mkdir(parents=True)
        (self.root / "manifests").mkdir()
        shutil.copy2(REPO / "scripts/generate-desktop-shortcuts", self.root / "scripts")
        shutil.copy2(REPO / "scripts/desktop_shortcuts_lib.py", self.root / "scripts")
        shutil.copy2(REPO / "manifests/desktop-shortcuts.json", self.root / "manifests")
        for name, source in CLI.output_paths(REPO).items():
            target = CLI.output_paths(self.root)[name]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        self.sync_patch = mock.patch.object(CLI, "_sync")
        self.sync_mock = self.sync_patch.start()

    def tearDown(self):
        self.sync_patch.stop()
        self.temporary.cleanup()

    def manifest(self):
        return json.loads((self.root / CLI.MANIFEST_REL).read_text())

    def run_cli(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = CLI.main(list(args), self.root)
        return status, stdout.getvalue(), stderr.getvalue()

    def bytes(self):
        paths = [self.root / CLI.MANIFEST_REL, *CLI.output_paths(self.root).values()]
        return {path: path.read_bytes() for path in paths}

    def test_list_includes_all_ownership_sources(self):
        status, output, _ = self.run_cli("list")
        self.assertEqual(status, 0)
        self.assertIn("space-a\tmanaged\tspace a\t", output)
        self.assertIn("space-e\thost\tspace e\t", output)
        self.assertIn("space-space\tomarchy\tspace space\t", output)

    def test_add_edit_and_duplicate_refusal(self):
        text = 'quote " ; $HOME *.md café'
        self.assertEqual(self.run_cli("add", "--group", "general", "--key", "q", "--label", "q · Quoted", "--text", text)[0], 0)
        added = self.manifest()["shortcuts"][-1]
        self.assertEqual((added["id"], added["output"]), ("space-q", text))
        self.assertNotIn("$HOME", self.run_cli("add", "--group", "general", "--key", "q", "--label", "duplicate", "--text", "x")[1])
        self.assertNotEqual(self.run_cli("add", "--group", "general", "--key", "q", "--label", "duplicate", "--text", "x")[0], 0)
        self.assertEqual(self.run_cli("edit", "space-q", "--key", "z", "--label", "z · Changed", "--text", "changed")[0], 0)
        changed = self.manifest()["shortcuts"][-1]
        self.assertEqual((changed["id"], changed["key"], changed["label"], changed["output"]),
                         ("space-q", "z", "z · Changed", "changed"))

    def test_native_changes_and_unconfirmed_deletion_are_refused(self):
        original = self.bytes()
        self.assertNotEqual(self.run_cli("edit", "space-e", "--label", "private")[0], 0)
        self.assertNotEqual(self.run_cli("delete", "space-e", "--yes")[0], 0)
        self.assertNotEqual(self.run_cli("delete", "space-a")[0], 0)
        self.assertEqual(self.bytes(), original)
        self.assertEqual(self.run_cli("delete", "space-a", "--yes")[0], 0)
        self.assertNotIn("space-a", [item["id"] for item in self.manifest()["shortcuts"]])

    def test_group_crud_preserves_stable_fields_and_requires_empty_group(self):
        self.assertEqual(self.run_cli("group", "add", "--name", "Code Snippets", "--prefix", "c")[0], 0)
        self.assertEqual(self.run_cli("group", "add", "--name", "Other", "--prefix", "o", "--id", "stable-other")[0], 0)
        self.assertEqual(self.run_cli("group", "rename", "stable-other", "--name", "Renamed")[0], 0)
        group = next(group for group in self.manifest()["groups"] if group["id"] == "stable-other")
        self.assertEqual(group, {"id": "stable-other", "name": "Renamed", "prefix": "o"})
        self.assertNotEqual(self.run_cli("group", "delete", "general", "--yes")[0], 0)
        self.assertNotEqual(self.run_cli("group", "delete", "stable-other")[0], 0)
        self.assertEqual(self.run_cli("group", "delete", "stable-other", "--yes")[0], 0)

    def test_stale_files_block_crud_but_sync_repairs_generation(self):
        path = CLI.output_paths(self.root)["menu"]
        path.write_text("stale\n")
        before = (self.root / CLI.MANIFEST_REL).read_bytes()
        status, _, error = self.run_cli("add", "--group", "general", "--key", "q", "--label", "q", "--text", "q")
        self.assertNotEqual(status, 0)
        self.assertIn("run 'dotfiles-shortcuts sync'", error)
        self.assertEqual((self.root / CLI.MANIFEST_REL).read_bytes(), before)
        self.sync_patch.stop()
        with mock.patch.object(CLI, "run_checked", return_value=subprocess.CompletedProcess([], 0, "", "")):
            self.assertEqual(self.run_cli("sync")[0], 0)
        self.sync_patch = mock.patch.object(CLI, "_sync")
        self.sync_mock = self.sync_patch.start()
        self.assertNotEqual(path.read_text(), "stale\n")

    def test_repository_write_failure_rolls_back_every_byte(self):
        before = self.bytes()
        real_write = CLI.write_generated
        calls = 0

        def fail_once(root, rendered):
            nonlocal calls
            calls += 1
            if calls == 1:
                first = next(iter(CLI.output_paths(root).values()))
                CLI.atomic_write(first, b"partial\n")
                raise OSError("simulated artifact failure")
            return real_write(root, rendered)

        with mock.patch.object(CLI, "write_generated", side_effect=fail_once):
            self.assertNotEqual(self.run_cli("add", "--group", "general", "--key", "q", "--label", "q", "--text", "q")[0], 0)
        self.assertEqual(self.bytes(), before)

    def test_apply_failure_keeps_valid_repository_state(self):
        self.sync_mock.side_effect = CLI.ShortcutError("fake apply failure")
        status, _, error = self.run_cli("add", "--group", "general", "--key", "q", "--label", "q", "--text", "q")
        self.assertNotEqual(status, 0)
        self.assertIn("repository updated", error)
        self.assertIn("dotfiles-shortcuts sync", error)
        self.assertIn("space-q", [item["id"] for item in self.manifest()["shortcuts"]])
        self.assertEqual(subprocess.run([str(self.root / CLI.GENERATOR_REL)]).returncode, 0)

    def test_apply_failure_stderr_reaches_error(self):
        failed = subprocess.CompletedProcess([], 23, "", "guarded menu conflict\n")
        with mock.patch.object(CLI.subprocess, "run", return_value=failed):
            with self.assertRaisesRegex(CLI.ShortcutError, "guarded menu conflict"):
                CLI.run_checked(["fake-apply"], self.root, capture=True)

    def test_concurrent_crud_is_serialized_without_repository_lock_file(self):
        context = multiprocessing.get_context("fork")
        first_started, first_entered = context.Event(), context.Event()
        second_started, second_entered = context.Event(), context.Event()
        release, results = context.Event(), context.Queue()
        first = context.Process(
            target=concurrent_add,
            args=(self.root, "x", first_started, first_entered, release, results),
        )
        second = context.Process(
            target=concurrent_add,
            args=(self.root, "y", second_started, second_entered, None, results),
        )
        first.start()
        self.assertTrue(first_entered.wait(5))
        second.start()
        self.assertTrue(second_started.wait(5))
        self.assertFalse(second_entered.wait(0.3))
        release.set()
        first.join(5)
        second.join(5)
        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual([results.get(timeout=1), results.get(timeout=1)], [None, None])
        keys = {item["key"] for item in self.manifest()["shortcuts"]}
        self.assertTrue({"x", "y"}.issubset(keys))
        self.assertFalse(CLI.lock_path(self.root).is_relative_to(self.root))

    def test_standalone_sync_serializes_with_crud(self):
        context = multiprocessing.get_context("fork")
        sync_entered, crud_started, crud_entered = context.Event(), context.Event(), context.Event()
        release, results = context.Event(), context.Queue()
        syncing = context.Process(target=concurrent_sync, args=(self.root, sync_entered, release, results))
        crud = context.Process(
            target=concurrent_add,
            args=(self.root, "x", crud_started, crud_entered, None, results),
        )
        syncing.start()
        self.assertTrue(sync_entered.wait(5))
        crud.start()
        self.assertTrue(crud_started.wait(5))
        self.assertFalse(crud_entered.wait(0.3))
        release.set()
        syncing.join(5)
        crud.join(5)
        self.assertFalse(syncing.is_alive())
        self.assertFalse(crud.is_alive())
        self.assertEqual([results.get(timeout=1), results.get(timeout=1)], [None, None])
        self.assertIn("x", {item["key"] for item in self.manifest()["shortcuts"]})

    def test_lock_refuses_repository_runtime_directory_without_creating_files(self):
        runtime = self.root / "runtime"
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}):
            with self.assertRaisesRegex(CLI.ShortcutError, "inside repository"):
                CLI.lock_path(self.root)
        self.assertFalse(runtime.exists())

    def test_manage_cancellation_changes_nothing(self):
        before = self.bytes()
        with mock.patch.object(CLI, "menu_select", return_value=None) as menu_select:
            self.assertEqual(self.run_cli("manage")[0], 0)
        menu_select.assert_called_once_with(
            "Manage shortcuts",
            [
                "\tAdd text alias", "\tEdit text alias", "󰭌\tDelete text alias", "󰉗\tAdd group",
                "\tRename group", "󰭌\tDelete empty group", "\tEdit manifest", "\tSync configuration",
            ],
        )
        self.assertEqual(self.bytes(), before)
        self.sync_mock.assert_not_called()

        group_choice = "general · General"
        with mock.patch.object(CLI, "menu_select", side_effect=["Add text alias", group_choice]), \
             mock.patch.object(CLI, "menu_input", return_value=None):
            self.assertEqual(self.run_cli("manage")[0], 0)
        self.assertEqual(self.bytes(), before)

        with mock.patch.object(CLI, "menu_select", side_effect=["Delete text alias", "space-a · a · AGENTS.md", "Cancel"]):
            self.assertEqual(self.run_cli("manage")[0], 0)
        self.assertEqual(self.bytes(), before)

    def test_menu_commands_distinguish_cancellation_from_failure(self):
        cancelled = subprocess.CompletedProcess([], 1, "", "")
        with mock.patch.object(CLI.subprocess, "run", return_value=cancelled):
            self.assertIsNone(CLI.menu_select("Pick", ["one"]))
            self.assertIsNone(CLI.menu_input("Type"))

        crashed = subprocess.CompletedProcess([], 2, "", "shell IPC failed\n")
        with mock.patch.object(CLI.subprocess, "run", return_value=crashed):
            with self.assertRaisesRegex(CLI.ShortcutError, "shell IPC failed"):
                CLI.menu_select("Pick", ["one"])
        with mock.patch.object(CLI.subprocess, "run", return_value=crashed), \
             mock.patch.object(CLI, "notify") as notify:
            self.assertEqual(self.run_cli("manage")[0], 1)
            self.assertIn("shell IPC failed", notify.call_args.args[0])
            self.assertTrue(notify.call_args.kwargs["failure"])
        failed_with_cancel_status = subprocess.CompletedProcess([], 1, "", "shell IPC failed\n")
        with mock.patch.object(CLI.subprocess, "run", return_value=failed_with_cancel_status):
            with self.assertRaisesRegex(CLI.ShortcutError, "shell IPC failed"):
                CLI.menu_input("Type")
        with mock.patch.object(CLI.subprocess, "run", side_effect=FileNotFoundError("omarchy")):
            with self.assertRaisesRegex(CLI.ShortcutError, "menu command unavailable"):
                CLI.menu_input("Type")

    def test_sync_fakes_host_commands_and_only_reloads_changed_binding(self):
        self.sync_patch.stop()
        calls = []

        def fake_run(args, cwd, capture=False):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, "", "")

        binding = CLI.output_paths(self.root)["binding"]
        binding.write_text("stale\n")
        with mock.patch.object(CLI, "run_checked", side_effect=fake_run):
            CLI.sync(self.root)
        self.assertEqual(calls, [
            [str(self.root / "dotfiles.sh"), "apply", "desktop"],
            ["omarchy", "restart", "xcompose"],
            ["omarchy", "menu", "refresh"],
            ["hyprctl", "reload"],
            ["hyprctl", "configerrors"],
            [str(self.root / "dotfiles.sh"), "check", "desktop"],
        ])
        calls.clear()
        with mock.patch.object(CLI, "run_checked", side_effect=fake_run):
            CLI.sync(self.root)
        self.assertNotIn(["hyprctl", "reload"], calls)
        self.sync_patch = mock.patch.object(CLI, "sync")
        self.sync_mock = self.sync_patch.start()

    def test_launcher_is_relocatable_and_forwards_literal_arguments(self):
        moved = Path(self.temporary.name) / "moved"
        launcher = moved / "packages/omarchy/desktop/.local/bin/dotfiles-shortcuts"
        launcher.parent.mkdir(parents=True)
        shutil.copy2(REPO / "packages/omarchy/desktop/.local/bin/dotfiles-shortcuts", launcher)
        launcher.chmod(launcher.stat().st_mode | stat.S_IXUSR)
        (moved / "scripts").mkdir(parents=True)
        (moved / "manifests").mkdir()
        (moved / "profiles").mkdir()
        (moved / "manifests/areas.tsv").touch()
        (moved / "profiles/omarchy.conf").touch()
        (moved / "profiles/ubuntu.conf").touch()
        canonical = moved / "scripts/dotfiles-shortcuts"
        canonical.write_text("#!/usr/bin/env bash\nprintf '<%s>\\n' \"$@\"\nexit 37\n")
        canonical.chmod(0o755)
        exposed = Path(self.temporary.name) / "bin/dotfiles-shortcuts"
        exposed.parent.mkdir()
        exposed.symlink_to(launcher)
        result = subprocess.run([exposed, "two words", "*.md", ";"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 37)
        self.assertEqual(result.stdout, "<two words>\n<*.md>\n<;>\n")

        for relative in ("scripts/dotfiles-shortcuts", "manifests/areas.tsv", "profiles/omarchy.conf", "profiles/ubuntu.conf"):
            outer = Path(self.temporary.name) / relative
            outer.parent.mkdir(parents=True, exist_ok=True)
            outer.touch()
        (Path(self.temporary.name) / "scripts/dotfiles-shortcuts").chmod(0o755)
        ambiguous = subprocess.run([exposed, "list"], text=True, capture_output=True)
        self.assertNotEqual(ambiguous.returncode, 0)
        self.assertIn("expected exactly one checkout root, found 2", ambiguous.stderr)


if __name__ == "__main__":
    unittest.main()
