# Windows-side configuration

Configuration applied on the Windows host itself, as opposed to the Stow
packages that target WSL and Linux hosts. Windows is a distinct supported
environment — not a layer in the Linux adapter model of
[architecture.md](../docs/omarchy-alignment/architecture.md) — and this area
brings the Windows host up to the same Omarchy-derived behavior, starting with
Windows Terminal theming.

Nothing here runs from `bootstrap.sh`; apply scripts run manually from a
Windows shell.

## terminal/

Windows Terminal settings are managed by merge, not by owning the file: the
live `settings.json` contains machine-generated profiles (VS Developer
prompts, dynamic GUIDs), so `apply.ps1` upserts only the surface defined in
`managed-settings.json` — shared `profiles.defaults` and the "Omarchy Tokyo
Night" scheme (exact values from Omarchy v3.8.3's Tokyo Night `colors.toml`) —
and strips those keys from individual profiles so the defaults stay
authoritative.

```powershell
powershell -ExecutionPolicy Bypass -File windows\terminal\apply.ps1
```

`-DryRun` prints the merged result without writing; a real apply first backs
up the live file to `settings.json.bak` beside it.

The tmux keybinding unbinds in
[docs/environments/windows-terminal.md](../docs/environments/windows-terminal.md)
remain manual and are the next candidate for the managed surface.
