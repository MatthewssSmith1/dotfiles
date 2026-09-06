# Official Nerd Fonts asset; deliberately separate from WinGet application ownership.
#Requires -Version 5.1
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$version = '3.5.1'
$sha256 = '239395baf60c89b2eaf4862b6b09db0ef95605cd3e8eef51c00345822a81a665'
$url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v$version/FiraCode.zip"
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$styles = @('Bold','Light','Medium','Regular','Retina','SemiBold')
$complete = $true
foreach ($style in $styles) {
    $name = "FiraCodeNerdFontMono-$style.ttf"
    $properties = Get-ItemProperty -LiteralPath $fontKey -ErrorAction SilentlyContinue
    $registered = $properties."FiraCode Nerd Font Mono $style (TrueType)"
    if (-not (Test-Path -LiteralPath "$fontDir\$name") -or $registered -ne "$fontDir\$name") { $complete = $false }
}
if ($complete) { Write-Output 'Present: FiraCode Nerd Font Mono (all six registered styles)'; return }
if ($DryRun) { Write-Output "Would download checksum-verified Nerd Fonts v$version and register six Mono styles for the current user."; return }
$cache = "$env:LOCALAPPDATA\dotfiles\cache\nerd-fonts-$version"
$null = New-Item -ItemType Directory -Path $cache -Force
$archive = "$cache\FiraCode.zip"
if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) { throw 'Nerd Fonts checksum mismatch; nothing installed.' }
Expand-Archive -LiteralPath $archive -DestinationPath "$cache\expanded" -Force
$null = New-Item -ItemType Directory -Path $fontDir -Force
if (-not (Test-Path -LiteralPath $fontKey)) { $null = New-Item -Path $fontKey }
if (-not ('DotfilesFontApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DotfilesFontApi {
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)]
    public static extern int AddFontResourceEx(string name, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr result);
}
'@
}
foreach ($style in $styles) {
    $name = "FiraCodeNerdFontMono-$style.ttf"
    $source = @(Get-ChildItem -LiteralPath "$cache\expanded" -Filter $name -Recurse)
    if ($source.Count -ne 1) { throw "Expected exactly one $name in verified font release." }
    $target = Join-Path $fontDir $name
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash $target).Hash -ne (Get-FileHash $source[0].FullName).Hash) {
            throw "Existing font differs: $target. Uninstall that font manually before replacing it."
        }
    } else { Copy-Item -LiteralPath $source[0].FullName -Destination $target }
    $null = New-ItemProperty -LiteralPath $fontKey -Name "FiraCode Nerd Font Mono $style (TrueType)" -Value $target -PropertyType String -Force
    if ([DotfilesFontApi]::AddFontResourceEx($target, 0, [IntPtr]::Zero) -eq 0) { throw "Windows could not load font: $target" }
}
$result = [IntPtr]::Zero
$null = [DotfilesFontApi]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, $null, 2, 1000, [ref]$result)
Write-Output "Installed FiraCode Nerd Font Mono v$version for this user. Reopen Terminal if necessary."
