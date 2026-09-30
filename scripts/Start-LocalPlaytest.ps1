# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$ModsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$expectedVersion = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION.txt') -Raw).Trim()
$modInfo = Join-Path $ModsRoot 'SurvivorCompanion\42\mod.info'
if (-not (Test-Path -LiteralPath $modInfo -PathType Leaf)) {
    throw "Local Living Fellows install is missing: $modInfo"
}
$installedVersion = Select-String -LiteralPath $modInfo -Pattern '^modversion=(.+)$' |
    Select-Object -First 1 -ExpandProperty Matches | ForEach-Object { $_.Groups[1].Value }
if ($installedVersion -ne $expectedVersion) {
    throw "Local Living Fellows is $installedVersion; expected $expectedVersion. Install the latest private playtest first."
}
$gameExe = Join-Path $GameRoot 'ProjectZomboid64.exe'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) {
    throw "Project Zomboid client was not found: $gameExe"
}
if (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue) {
    throw 'Close Project Zomboid before starting the local playtest.'
}

# Build 42 defaults to workshop,steam,mods. A staged Workshop copy with the
# same SurvivorCompanion ID can therefore mask this newer private install.
# Put local mods first for this launch only; no Workshop staging is changed.
$game = Start-Process -FilePath $gameExe -WorkingDirectory $GameRoot `
    -ArgumentList @('-modfolders', 'mods,workshop,steam') -PassThru
Write-Output "Started Living Fellows $installedVersion local playtest pid=$($game.Id)"
