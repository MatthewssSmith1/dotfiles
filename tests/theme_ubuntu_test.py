"""Offline Ubuntu adapter regressions, invoked by tools_test.sh."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
BIN = REPO / 'packages/common/tools/.local/share/dotfiles/bin'
sys.dont_write_bytecode = True
sys.path.insert(0, str(BIN))
import theme_ubuntu


class UbuntuThemes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / 'config'
        self.state = self.home / 'state/dotfiles/theme'
        self.current = self.state / 'ubuntu/current'
        self.selection = self.config / 'dotfiles/local/theme'
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_STATE_HOME=str(self.home / 'state'), PYTHONDONTWRITEBYTECODE='1')

    def run_theme(self, *args, code=0):
        result = subprocess.run([sys.executable, str(BIN / 'theme.py'), 'ubuntu', *args],
                                env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout

    def install(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)

    def test_fallback_reads_and_sync_do_not_persist_selection(self):
        self.run_theme('status', code=1)
        self.run_theme('check', code=1)
        self.assertEqual(list(self.home.iterdir()), [])
        self.run_theme('sync')
        self.assertFalse(self.selection.exists())
        self.selection.parent.mkdir(parents=True)
        for invalid in ('../everforest\n', 'everforest\nextra\n', 'catppuccin-latte\n'):
            self.selection.write_text(invalid)
            self.assertIn('fallback; invalid', self.run_theme('status'))
            self.run_theme('sync')
            self.assertEqual(self.selection.read_text(), invalid)
        self.assertEqual((self.current / 'selection').read_text(), 'tokyo-night\n')

    def test_all_palettes_and_unrelated_settings(self):
        base = tomllib.loads((REPO / 'packages/ubuntu/herdr/.config/herdr/config.toml').read_text())
        bindings = json.loads((REPO / 'packages/common/opencode/.config/dotfiles/opencode/tui.jsonc').read_text())
        for slug in ('tokyo-night', 'everforest', 'catppuccin'):
            self.run_theme('set', slug)
            colors = tomllib.loads((BIN.parent / f'themes/{slug}/colors.toml').read_text())
            generated = tomllib.loads((self.current / 'herdr.toml').read_text())
            self.assertEqual(generated['theme']['custom']['accent'], colors['accent'])
            generated['theme'] = base['theme']
            generated['ui']['accent'] = base['ui']['accent']
            self.assertEqual(generated, base)
            tui = json.loads((self.current / 'opencode-tui.json').read_text())
            self.assertEqual(tui.pop('theme'), 'dotfiles-host')
            self.assertEqual(tui, bindings)
            palette = json.loads((self.current / 'opencode-theme.json').read_text())['theme']
            self.assertEqual(palette['background'], colors['background'])
            self.assertEqual(palette['primary'], colors['accent'])
            self.assertTrue(all(value in colors.values() for value in palette.values()))
            prompt = tomllib.loads((self.current / 'starship.toml').read_text())
            self.assertIn(colors['accent'], prompt['directory']['style'])
            self.assertEqual(self.selection.read_text(), slug + '\n')
            before = self.current.lstat().st_mtime_ns
            self.run_theme('sync')
            self.run_theme('check')
            self.assertEqual(self.current.lstat().st_mtime_ns, before)

    def test_corruption_repair_and_concurrent_switches(self):
        self.run_theme('sync')
        (self.current / 'accent').write_text('broken')
        self.run_theme('check', code=1)
        self.run_theme('sync')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda slug: self.run_theme('set', slug),
                          ['everforest', 'catppuccin', 'tokyo-night'] * 3))
        self.run_theme('check')
        self.assertEqual(self.selection.read_text(), (self.current / 'selection').read_text())

    def test_conflicts_and_runtime_failure_preserve_selection(self):
        self.run_theme('set', 'everforest')
        previous = self.current.readlink()
        self.install(self.home / '.local/share/dotfiles/bin/opencode-launch', '#!/bin/sh\nexit 0\n')
        link = self.config / 'opencode/themes/dotfiles-host.json'
        link.parent.mkdir(parents=True)
        link.write_text('user content')
        self.run_theme('set', 'catppuccin', code=2)
        self.assertEqual(link.read_text(), 'user content')
        self.assertEqual(self.current.readlink(), previous)
        link.unlink()
        self.install(self.home / '.config/herdr/config.toml', '')
        self.install(self.home / '.local/share/mise/installs/aqua-ogulcancelik-herdr/0.8.2/herdr',
                     '#!/bin/sh\nexit 7\n')
        self.run_theme('set', 'catppuccin', code=2)
        self.assertEqual(self.current.readlink(), previous)
        self.assertEqual(self.selection.read_text(), 'everforest\n')

    def test_symlink_selection_and_state_refused(self):
        self.selection.parent.mkdir(parents=True)
        target = self.home / 'keep'
        target.write_text('everforest\n')
        self.selection.symlink_to(target)
        self.run_theme('set', 'catppuccin', code=2)
        self.assertEqual(target.read_text(), 'everforest\n')
        self.assertIn('fallback', self.run_theme('status', code=1))
        self.selection.unlink()
        (self.state / 'ubuntu/current').symlink_to(self.home)
        self.run_theme('sync', code=2)

    def test_selection_write_failure_rolls_back_pointer(self):
        self.run_theme('set', 'everforest')
        previous = self.current.readlink()
        catalog = json.loads((BIN.parent / 'themes/catalog.json').read_text())
        original = theme_ubuntu.atomic

        def fail_selection(path, text):
            if path == self.selection:
                raise PermissionError('injected selection failure')
            original(path, text)

        with patch.dict(os.environ, self.env), patch.object(theme_ubuntu, 'atomic', fail_selection):
            with self.assertRaises(PermissionError):
                theme_ubuntu.run('set', ['set', 'catppuccin'], catalog,
                                 BIN.parent / 'themes', self.config, self.state)
        self.assertEqual(self.current.readlink(), previous)
        self.run_theme('check')

    def test_opencode_discovery_link_and_herdr_override(self):
        self.install(self.home / '.local/share/dotfiles/bin/opencode-launch', '#!/bin/sh\nexit 0\n')
        self.install(self.home / '.local/bin/dotfiles-theme', '#!/bin/sh\nexit 0\n')
        self.install(self.home / '.config/herdr/config.toml', '')
        self.install(self.home / '.local/share/mise/installs/aqua-ogulcancelik-herdr/0.8.2/herdr',
                     '#!/bin/sh\nprintf "%s\\n" "$HERDR_CONFIG_PATH" "$@"\n')
        self.run_theme('sync')
        link = self.config / 'opencode/themes/dotfiles-host.json'
        self.assertEqual(link.read_text(), (self.current / 'opencode-theme.json').read_text())
        wrapper = REPO / 'packages/ubuntu/herdr/.local/bin/herdr'
        for override in (None, '/explicit/config.toml'):
            env = self.env.copy()
            env.pop('HERDR_CONFIG_PATH', None)
            if override:
                env['HERDR_CONFIG_PATH'] = override
            result = subprocess.run([str(wrapper), 'argument with spaces'], env=env,
                                    capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout.splitlines(),
                             [override or str(self.current / 'herdr.toml'), 'argument with spaces'])

    def test_shell_accent_preserves_options_status_and_override(self):
        self.run_theme('sync')
        self.install(self.home / '.local/bin/dotfiles-theme', '#!/bin/sh\nexit 0\n')
        init = REPO / 'packages/ubuntu/bash/.config/dotfiles/bash/init.bash'
        script = '''
_dotfiles_bash_trace() { :; }
DOTFILES_BASH_VALIDATE_OWNERSHIP=1 source "$1"
FZF_DEFAULT_OPTS='--height=40%'
STARSHIP_CONFIG=/explicit/starship.toml
_dotfiles_bash_theme_prompt
FZF_DEFAULT_OPTS+=' --reverse'
_dotfiles_bash_theme_prompt
[[ "$FZF_DEFAULT_OPTS" == '--height=40% --reverse --color='* ]] || exit 10
[[ "$STARSHIP_CONFIG" == /explicit/starship.toml ]] || exit 11
false
_dotfiles_bash_theme_prompt
[[ $? == 1 ]] || exit 12
unset STARSHIP_CONFIG
_dotfiles_bash_theme_prompt
[[ "$STARSHIP_CONFIG" == "$XDG_STATE_HOME/dotfiles/theme/ubuntu/current/starship.toml" ]] || exit 13
'''
        subprocess.run(['bash', '-c', script, 'test', str(init)], env=self.env, check=True)

    def test_named_opencode_profiles_use_palette_only_on_ubuntu(self):
        self.run_theme('sync')
        wrapper = REPO / 'packages/common/opencode/.local/share/dotfiles/bin/opencode-launch'
        for profile in ('personal', 'work', 'tui'):
            source = REPO / f'packages/common/opencode/.config/dotfiles/opencode/{profile}.jsonc'
            self.install(self.home / f'.config/dotfiles/opencode/{profile}.jsonc', source.read_text())
        self.install(self.home / '.local/share/dotfiles/bin/opencode-launch', wrapper.read_text())
        self.run_theme('sync')
        self.install(self.home / '.local/bin/opencode',
                     '#!/bin/sh\nprintf "%s\\n" "$OPENCODE_CONFIG" "$OPENCODE_TUI_CONFIG" "$@"\n')
        for host in ('ubuntu', 'omarchy'):
            self.install(self.home / '.local/bin/dotfiles-theme', f'#!/bin/sh\nprintf "{host}\\n"\n')
            for profile in ('personal', 'work'):
                result = subprocess.run([str(wrapper), profile, 'argument with spaces'],
                                        env={**self.env, 'PATH': str(self.home / '.local/bin') + ':/usr/bin:/bin'},
                                        check=True, capture_output=True, text=True)
                self.assertEqual(result.stdout.splitlines(), [
                    str(self.home / f'.config/dotfiles/opencode/{profile}.jsonc'),
                    str(self.current / 'opencode-tui.json') if host == 'ubuntu' else
                    str(self.home / '.config/dotfiles/opencode/tui.jsonc'), 'argument with spaces'])


if __name__ == '__main__':
    unittest.main()
