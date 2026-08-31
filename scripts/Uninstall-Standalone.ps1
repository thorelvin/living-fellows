# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$ModsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods'),
    [string]$InstallDataRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellows'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$BridgeRoot = Join-Path ([System.IO.Path]::GetFullPath($InstallDataRoot)) 'bridge'
$Target = Join-Path ([System.IO.Path]::GetFullPath($ModsRoot)) 'SurvivorCompanion'
$modManifest = Join-Path $Target '.sc-install-manifest.json'
$bridgeManifest = Join-Path $BridgeRoot 'install-manifest.json'

if (Test-Path -LiteralPath $modManifest -PathType Leaf) {
    & (Join-Path $ProjectRoot 'scripts\Uninstall-Local.ps1') `
        -ModsRoot $ModsRoot -BridgeRoot $BridgeRoot -Force:$Force
} elseif (Test-Path -LiteralPath $bridgeManifest -PathType Leaf) {
    & (Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1') -BridgeRoot $BridgeRoot
} else {
    throw 'No owned Living Fellows standalone installation was found.'
}

Write-Output ''
Write-Output 'UNINSTALL COMPLETE'
Write-Output 'The original Project Zomboid launcher configuration has been restored.'
