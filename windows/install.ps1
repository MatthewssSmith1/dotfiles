# Explicit networked install; existing applications are left at their current version.
#Requires -Version 5.1
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$apps = @(Get-WindowsApps)
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) { throw 'WinGet is missing. Install/update Microsoft App Installer, then reopen the shell.' }
foreach ($app in $apps) {
    if ($app.Installed) { Write-Output "Present: $($app.Name) $($app.Version)"; continue }
    if ($DryRun) { Write-Output "Would install $($app.Id) from $($app.Source)"; continue }
    Write-Output "Installing $($app.Id) from $($app.Source). A package may require UAC approval."
    & $winget.Source install --id $app.Id --exact --source $app.Source --no-upgrade --silent --disable-interactivity --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "WinGet failed for $($app.Id) (exit $LASTEXITCODE). Review its diagnostic above; resolve installer/UAC/reboot requirements and rerun. No blanket upgrade or automatic reboot is performed." }
}
& "$PSScriptRoot\install-font.ps1" -DryRun:$DryRun
Write-Output 'Node/npm/pnpm: install separately with mise; see windows/README.md for runtime setup.'
