# Shared read-only helpers. Windows PowerShell 5.1 and PowerShell 7.
function Get-WindowsApps {
    $records = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)
    $packages = @(Get-AppxPackage -ErrorAction Stop)
    foreach ($app in (Get-Content "$PSScriptRoot\apps.json" -Raw | ConvertFrom-Json)) {
        $versions = @()
        if ($app.appx) { $versions = @($packages | Where-Object Name -eq $app.appx | ForEach-Object { $_.Version }) }
        if ($app.uninstallName) { $versions = @($records | Where-Object DisplayName -match $app.uninstallName | ForEach-Object { $_.DisplayVersion }) }
        [pscustomobject]@{ Name=$app.name; Id=$app.id; Source=$app.source; Installed=($versions.Count -gt 0); Version=($versions -join ', ') }
    }
}

function Get-ManagedPathEntries {
    @("$env:LOCALAPPDATA\Microsoft\WinGet\Links", "$env:LOCALAPPDATA\mise\shims")
}

function Merge-UserPath([string]$Current, [string[]]$Entries) {
    # Preserve all unrelated entries verbatim; normalize only the entries we own.
    $remaining = @($Current -split ';' | Where-Object {
        $candidate = [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\')
        $_ -and $candidate -notin $Entries
    })
    (@($Entries) + $remaining) -join ';'
}

function Get-TerminalSettingsPath {
    $candidates = @(@(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    ) | Where-Object { Test-Path -LiteralPath $_ })
    if (@($candidates).Count -ne 1) {
        throw 'Open stable Windows Terminal once, or pass -SettingsPath explicitly (missing or ambiguous settings).'
    }
    $candidates[0]
}

function Merge-ManagedObject($Target, $Managed) {
    foreach ($prop in $Managed.PSObject.Properties) {
        $existing = $Target.PSObject.Properties[$prop.Name]
        if ($prop.Value -is [pscustomobject] -and $existing -and $existing.Value -is [pscustomobject]) {
            Merge-ManagedObject $existing.Value $prop.Value
        } elseif ($existing) { $existing.Value = $prop.Value }
        else { $Target | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
    }
}

function Remove-ManagedObject($Target, $Managed) {
    foreach ($prop in $Managed.PSObject.Properties) {
        $existing = $Target.PSObject.Properties[$prop.Name]
        if (-not $existing) { continue }
        if ($prop.Value -is [pscustomobject] -and $existing.Value -is [pscustomobject]) {
            Remove-ManagedObject $existing.Value $prop.Value
            if (@($existing.Value.PSObject.Properties).Count -eq 0) { $Target.PSObject.Properties.Remove($prop.Name) }
        } else { $Target.PSObject.Properties.Remove($prop.Name) }
    }
}

function Get-TerminalMerge([string]$SettingsPath) {
    try { $live = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Cannot parse Terminal settings. PowerShell 5.1 requires strict JSON (no comments/trailing commas). File unchanged. $($_.Exception.Message)" }
    $managed = Get-Content "$PSScriptRoot\terminal\managed-settings.json" -Raw | ConvertFrom-Json
    if (-not $live.profiles) { $live | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $live.profiles.defaults) { $live.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force }
    # $managed.profileDefaults.PSObject.Properties defines the only owned defaults.
    Merge-ManagedObject $live.profiles.defaults $managed.profileDefaults
    foreach ($profile in $live.profiles.list) { Remove-ManagedObject $profile $managed.profileDefaults }
    $schemes = @($live.schemes | Where-Object { $_ -and $_.name -notin @($managed.schemes.name) }) + @($managed.schemes)
    $live | Add-Member -NotePropertyName schemes -NotePropertyValue $schemes -Force
    ($live | ConvertTo-Json -Depth 100) + [Environment]::NewLine
}

function Get-BackupPath([string]$Path) {
    if (-not (Test-Path -LiteralPath "$Path.bak")) { return "$Path.bak" }
    "$Path.$([guid]::NewGuid().ToString('N')).bak"
}
