# Windows host (Windows Terminal)

Source of truth: `windows/terminal/managed-settings.json`. The live
`settings.json` is merged, never owned — it holds machine-generated profiles.

1. Edit `managed-settings.json`.
2. Dry-run from a Windows shell and inspect the merged output:
   `powershell -ExecutionPolicy Bypass -File windows\terminal\apply.ps1 -DryRun`
3. Apply (same command without `-DryRun`; a `.bak` backup is written beside
   the live file).
4. Done when a second `-DryRun` matches the live file byte-for-byte and open
   terminal tabs show the change (Windows Terminal hot-reloads).

The keybinding unbinds in `docs/environments/windows-terminal.md` are a
manual step, not applied by the script.
