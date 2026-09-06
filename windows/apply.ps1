# Offline apply. Dot-source with -SessionOnly to prepare an existing agent/shell.
#Requires -Version 5.1
param([switch]$DryRun, [switch]$SessionOnly, [string]$SettingsPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$entries = @(Get-ManagedPathEntries)
$oldPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$newPath = Merge-UserPath $oldPath $entries
if ($SessionOnly) {
    if ($DryRun) { Write-Output 'Would refresh this process PATH from persistent user/machine PATH, with mise shims first.'; return }
    $savedPath = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + $newPath + ';' + $env:Path
    $env:Path = Merge-UserPath $savedPath $entries
    Write-Output 'Prepared this process PATH. No persistent settings changed.'
    return
}
# Validate Terminal input before changing the persistent PATH.
if (-not $SettingsPath) { $SettingsPath = Get-TerminalSettingsPath }
$null = Get-TerminalMerge $SettingsPath
if ($DryRun) {
    if ($oldPath -cne $newPath) { Write-Output 'Would prepend WinGet Links and mise shims to user PATH; preserve other entries.' }
    & "$PSScriptRoot\terminal\apply.ps1" -SettingsPath $SettingsPath -DryRun
    return
}
if ($oldPath -cne $newPath) {
    $stateDir = "$env:LOCALAPPDATA\dotfiles\backups"
    $null = New-Item -ItemType Directory -Path $stateDir -Force
    $backup = Join-Path $stateDir ("user-path-{0}.json" -f [guid]::NewGuid().ToString('N'))
    @{ Path=$oldPath } | ConvertTo-Json | Set-Content -LiteralPath $backup -Encoding UTF8
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Output "Updated user PATH. Backup: $backup"
}
& "$PSScriptRoot\terminal\apply.ps1" -SettingsPath $SettingsPath
Write-Output 'Restart Terminal and Codex to refresh PATH, or dot-source apply.ps1 -SessionOnly in the current shell.'
