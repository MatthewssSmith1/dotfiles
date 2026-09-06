# Native behavior tests; all file mutations are confined to a unique temp directory.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-windows-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$settings = Join-Path $root 'settings.json'
$shell = (Get-Process -Id $PID).Path
function Run-Terminal([string[]]$ExtraArgs) {
    $output = & $shell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\terminal\apply.ps1" -SettingsPath $settings @ExtraArgs 2>&1
    Assert ($LASTEXITCODE -eq 0) "Terminal script failed: $output"
    $output
}
try {
    $fixture = @'
{
  "profiles": {
    "defaults": { "historySize": 1234, "font": { "cellWidth": "1.1", "face": "Old" } },
    "list": [ { "guid": "fixture", "name": "Fixture", "commandline": "ssh fixture", "colorScheme": "Old", "font": { "face": "Old", "cellHeight": "1.2" } } ]
  },
  "schemes": [ { "name": "Unmanaged", "background": "#000000" } ],
  "actions": [ { "command": "copy", "id": "keep" } ],
  "keybindings": [ { "id": "keep", "keys": "ctrl+c" } ],
  "unrelated": { "preserve": true }
}
'@
    [IO.File]::WriteAllText($settings, $fixture)
    $before = (Get-FileHash $settings).Hash
    $preview = Run-Terminal @('-DryRun')
    Assert ((($preview -join [Environment]::NewLine) + [Environment]::NewLine) -ceq (Get-TerminalMerge $settings)) 'Dry-run output differs from planned merge'
    Assert ((Get-FileHash $settings).Hash -eq $before) 'Dry-run changed settings'
    Assert (@(Get-ChildItem $root).Count -eq 1) 'Dry-run created a file'
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $null = & $shell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\apply.ps1" -DryRun -SettingsPath $settings
    Assert ($LASTEXITCODE -eq 0) 'Top-level dry-run failed'
    Assert ([Environment]::GetEnvironmentVariable('Path','User') -ceq $userPath) 'Dry-run changed user PATH'
    $null = Run-Terminal @()
    Assert ((Get-FileHash "$settings.bak").Hash -eq $before) 'Original backup differs'
    $first = (Get-FileHash $settings).Hash
    $null = Run-Terminal @()
    Assert ((Get-FileHash $settings).Hash -eq $first) 'Apply is not byte-idempotent'
    Assert (@(Get-ChildItem $root).Count -eq 2) 'No-op apply created another backup'
    $null = Run-Terminal @('-Check')
    $merged = Get-Content $settings -Raw | ConvertFrom-Json
    Assert ($merged.profiles.defaults.historySize -eq 1234) 'Lost unmanaged defaults'
    Assert ($merged.profiles.defaults.font.cellWidth -eq '1.1') 'Lost nested default font setting'
    Assert ($merged.profiles.list[0].font.cellHeight -eq '1.2') 'Lost nested per-profile font setting'
    Assert (-not $merged.profiles.list[0].font.face) 'Managed per-profile font shadow remains'
    Assert ($merged.profiles.list[0].commandline -eq 'ssh fixture') 'Lost profile command'
    Assert ($merged.actions[0].id -eq 'keep' -and $merged.keybindings[0].keys -eq 'ctrl+c') 'Changed manual bindings'
    Assert ($merged.unrelated.preserve -and @($merged.schemes).Count -eq 2) 'Lost unrelated settings/scheme'
    # A later edit must preserve the original .bak, and back up the new input separately.
    [IO.File]::WriteAllText($settings, '{}')
    $null = Run-Terminal @()
    Assert ((Get-FileHash "$settings.bak").Hash -eq $before) 'Overwrote original backup'
    Assert (@(Get-ChildItem $root -Filter '*.bak').Count -eq 2) 'Missing subsequent backup'
    [IO.File]::WriteAllText($settings, '{invalid')
    $count = @(Get-ChildItem $root).Count
    $threw = $false
    try { $null = Get-TerminalMerge $settings } catch { $threw = $true }
    Assert $threw 'Malformed JSON was accepted'
    Assert (@(Get-ChildItem $root).Count -eq $count) 'Parse failure wrote files'
    $entries = @('C:\Owned\Links','C:\Owned\shims')
    $path = Merge-UserPath 'C:\Custom;C:\Owned\Links\;C:\Other;C:\Owned\shims' $entries
    Assert ($path -ceq 'C:\Owned\Links;C:\Owned\shims;C:\Custom;C:\Other') 'PATH merge lost unrelated entries'
    Assert ((Merge-UserPath $path $entries) -ceq $path) 'PATH merge is not idempotent'
    $originalLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $root
        $autoPath = Join-Path $root 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        $null = New-Item -ItemType Directory -Path (Split-Path $autoPath) -Force
        [IO.File]::WriteAllText($autoPath, '{}')
        Assert ((Get-TerminalSettingsPath) -ceq $autoPath) 'Single settings path detection failed'
    } finally { $env:LOCALAPPDATA = $originalLocalAppData }
    Write-Output 'PASS: native dry-run, byte-idempotence, backups, nested preservation, empty/malformed settings, PATH merge'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notlike 'dotfiles-windows-test-*') { throw 'Unsafe test cleanup target' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
