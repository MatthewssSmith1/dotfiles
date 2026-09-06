# Merge managed settings only. Actions/keybindings remain manual.
#Requires -Version 5.1
param([switch]$DryRun, [switch]$Check, [string]$SettingsPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common.ps1"
if (-not $SettingsPath) { $SettingsPath = Get-TerminalSettingsPath }
$original = [IO.File]::ReadAllText($SettingsPath)
$json = Get-TerminalMerge $SettingsPath
if ($DryRun) { Write-Output $json.TrimEnd([char[]]"`r`n"); return }
if ($Check) {
    # Ignore formatting when checking semantic drift.
    $canonical = ((ConvertFrom-Json $original) | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    if ($canonical -cne $json) { Write-Output 'DRIFT: Windows Terminal managed settings'; exit 1 }
    Write-Output 'OK: Windows Terminal managed settings'; exit 0
}
if ($original -ceq $json) { Write-Output 'Unchanged: Windows Terminal settings'; return }
$backup = Get-BackupPath $SettingsPath
Copy-Item -LiteralPath $SettingsPath -Destination $backup -ErrorAction Stop
# Refuse to overwrite edits made while the merge was being prepared.
if ([IO.File]::ReadAllText($SettingsPath) -cne $original) { throw 'Terminal settings changed concurrently; retry.' }
[IO.File]::WriteAllText($SettingsPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Output "Applied Terminal settings. Backup: $backup"
