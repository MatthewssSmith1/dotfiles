# Merges dotfiles-managed Windows Terminal settings into the live settings.json.
#
# Managed surface (see managed-settings.json):
#   - profiles.defaults keys listed under "profileDefaults" (other defaults keys untouched)
#   - the same keys are removed from individual profiles so defaults stay authoritative
#   - color schemes listed under "schemes", upserted by name (other schemes untouched)
#
# Everything else in settings.json (profiles, keybindings, actions) is left alone.
# Idempotent: re-running after a successful apply is a no-op apart from JSON reformatting.
#
# Usage: powershell -ExecutionPolicy Bypass -File apply.ps1 [-DryRun]

param([switch]$DryRun)

$ErrorActionPreference = 'Stop'

$settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not (Test-Path $settingsPath)) {
    throw "Windows Terminal settings not found at $settingsPath"
}

$managed = Get-Content "$PSScriptRoot\managed-settings.json" -Raw | ConvertFrom-Json
$live = Get-Content $settingsPath -Raw | ConvertFrom-Json

foreach ($prop in $managed.profileDefaults.PSObject.Properties) {
    $existing = $live.profiles.defaults.PSObject.Properties[$prop.Name]
    if ($existing) {
        $live.profiles.defaults.($prop.Name) = $prop.Value
    } else {
        $live.profiles.defaults | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
}

$managedKeys = $managed.profileDefaults.PSObject.Properties.Name
foreach ($profile in $live.profiles.list) {
    foreach ($key in $managedKeys) {
        if ($profile.PSObject.Properties[$key]) {
            $profile.PSObject.Properties.Remove($key)
        }
    }
}

foreach ($scheme in $managed.schemes) {
    $others = @($live.schemes | Where-Object { $_.name -ne $scheme.name })
    $live.schemes = $others + $scheme
}

$json = $live | ConvertTo-Json -Depth 100

if ($DryRun) {
    Write-Output $json
    Write-Output "`n[dry-run] No changes written."
    exit 0
}

$backupPath = "$settingsPath.bak"
Copy-Item $settingsPath $backupPath -Force
$json | Set-Content -Path $settingsPath -Encoding utf8
Write-Output "Applied managed settings to $settingsPath (backup at $backupPath)"
