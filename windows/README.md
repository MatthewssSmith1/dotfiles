# Windows-side configuration

Configuration applied on the Windows host itself, as opposed to the Stow packages that target Ubuntu and Omarchy hosts. Windows is a distinct supported environment — not a layer in the Linux adapter model of [architecture.md](../docs/architecture.md) — and this area brings the Windows host up to the same Omarchy-derived behavior, starting with Windows Terminal theming.

Nothing here runs from `dotfiles.sh`; apply scripts run manually from a Windows shell.

## terminal/

Windows Terminal settings are managed by merge, not by owning the file: the live `settings.json` contains machine-generated profiles (VS Developer prompts, dynamic GUIDs), so `apply.ps1` upserts only the surface defined in `managed-settings.json` — shared `profiles.defaults` and the "Omarchy Tokyo Night" scheme (exact values from the accepted Omarchy v4 Tokyo Night `colors.toml`) — and strips those keys from individual profiles so the defaults stay authoritative. Unrelated profiles, GUIDs, schemes, actions, and keybindings remain untouched.

```powershell
powershell -ExecutionPolicy Bypass -File windows\terminal\apply.ps1
```

`-DryRun` prints the merged result without writing; a real apply first backs up the live file to `settings.json.bak` beside it.

The Herdr keybinding unbinds in [docs/environments/windows-terminal.md](../docs/environments/windows-terminal.md) remain manual; `apply.ps1` does not manage actions or keybindings.
