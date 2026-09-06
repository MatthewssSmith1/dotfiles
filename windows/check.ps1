# Offline/read-only. Exit 1 for missing base setup or drift; runtimes are pending unless required.
#Requires -Version 5.1
param([switch]$RequireRuntimes, [string]$SettingsPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$failed = $false
foreach ($app in (Get-WindowsApps)) {
    if ($app.Installed) { Write-Output "OK: $($app.Name) $($app.Version)" }
    else { Write-Output "MISSING: $($app.Name); run windows\install.ps1"; $failed = $true }
}
foreach ($entry in (Get-ManagedPathEntries)) {
    $saved = @([Environment]::GetEnvironmentVariable('Path','User') -split ';' | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
    if ($entry -notin $saved) { Write-Output "DRIFT: user PATH lacks $entry"; $failed = $true }
}
foreach ($name in @('git.exe','mise.exe','gh.exe','node.exe','npm','pnpm')) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $runtime = $name -in @('node.exe','npm','pnpm')
    if (-not $command) {
        Write-Output "MISSING: $name in this process PATH"
        if (-not $runtime -or $RequireRuntimes) { $failed = $true }
        continue
    }
    $path = $command.Source
    $expected = switch ($name) {
        'git.exe' { "$env:ProgramFiles\Git\*" }
        'mise.exe' { "$env:LOCALAPPDATA\Microsoft\WinGet\*" }
        'gh.exe' { "$env:ProgramFiles\GitHub CLI\*" }
        default { "$env:LOCALAPPDATA\mise\*" }
    }
    if ($path -notlike $expected) {
        Write-Output "RESOLUTION: $name -> $path (expected $expected); use a fresh shell or apply.ps1 -SessionOnly"
        if (-not $runtime -or $RequireRuntimes) { $failed = $true }
    } else { Write-Output "OK: $name -> $path" }
}
foreach ($style in @('Bold','Light','Medium','Regular','Retina','SemiBold')) {
    $properties = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
    $path = $properties."FiraCode Nerd Font Mono $style (TrueType)"
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { Write-Output "MISSING: registered font style $style"; $failed = $true }
}
try {
    if (-not $SettingsPath) { $SettingsPath = Get-TerminalSettingsPath }
    $canonical = ((Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json) | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    if ($canonical -cne (Get-TerminalMerge $SettingsPath)) { Write-Output 'DRIFT: Terminal managed settings'; $failed = $true }
    else { Write-Output 'OK: Terminal managed settings' }
} catch { Write-Output "CHECK FAILED: $($_.Exception.Message)"; $failed = $true }
Write-Output 'NOTE: Runtime resolution does not verify SST operational compatibility; compare versions with the project requirements. npm comes with Node.'
Write-Output 'MANUAL: GitHub, Codex, Tailscale, AWS and SSH sign-ins; Terminal font rendering and keybindings.'
if ($failed) { exit 1 }
exit 0
