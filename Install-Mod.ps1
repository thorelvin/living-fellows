<#
.SYNOPSIS
    Installs the PZ Radio Link Lua mod into the local Zomboid mods folder.

.DESCRIPTION
    Copies mod\PZRadioLink to <userdir>\Zomboid\mods\PZRadioLink. Nothing in the
    game folder is touched, no game file is patched, and no launch command is
    changed. You still enable the mod from the game's own Mods screen.

.PARAMETER UserDir
    Zomboid user directory. Defaults to $env:USERPROFILE\Zomboid.

.PARAMETER Uninstall
    Removes the installed mod folder instead of installing it.
#>
[CmdletBinding()]
param(
    [string] $UserDir = (Join-Path $env:USERPROFILE 'Zomboid'),
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'mod\PZRadioLink'
$modsDir = Join-Path $UserDir 'mods'
$target = Join-Path $modsDir 'PZRadioLink'

if ($Uninstall) {
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
        Write-Host "Removed $target"
    } else {
        Write-Host "Nothing installed at $target"
    }
    Write-Host 'Your saves, settings and other mods were not touched.'
    return
}

if (-not (Test-Path $source)) {
    throw "Mod source not found: $source"
}
if (-not (Test-Path $UserDir)) {
    throw "Zomboid user directory not found: $UserDir`nRun the game once, or pass -UserDir."
}

if (-not (Test-Path $modsDir)) {
    New-Item -ItemType Directory -Path $modsDir | Out-Null
}
if (Test-Path $target) {
    Remove-Item -Recurse -Force $target
}

Copy-Item -Recurse -Path $source -Destination $target
$count = (Get-ChildItem -Recurse -File $target | Measure-Object).Count

Write-Host "Installed $count files to $target"
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Start-Host.bat            (leave it running)'
Write-Host '  2. Launch Project Zomboid, enable "PZ Radio Link" in Mods'
Write-Host '  3. Open http://127.0.0.1:8777/ in a browser'
Write-Host '  4. In game, right-click a radio you are carrying -> Link to phone'
