# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = '',
    [string]$ModsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods'),
    [string]$InstallDataRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellows')
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

function Find-ProjectZomboidRoot {
    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\Software\WOW6432Node\Valve\Steam',
        'HKLM:\Software\Valve\Steam')) {
        try {
            $steam = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($property in @('SteamPath', 'InstallPath')) {
                if ($steam.$property) { $steamRoots.Add([string]$steam.$property) }
            }
        } catch { }
    }
    $steamRoots.Add('C:\Program Files (x86)\Steam')
    $steamRoots.Add('C:\Program Files\Steam')

    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in @($steamRoots | Select-Object -Unique)) {
        $libraries.Add($steamRoot)
        $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            $text = Get-Content -LiteralPath $vdf -Raw -Encoding utf8
            foreach ($match in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
            }
        }
    }
    $candidates = @($libraries | Select-Object -Unique | ForEach-Object {
        Join-Path $_ 'steamapps\common\ProjectZomboid'
    })
    $found = @($candidates | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ 'ProjectZomboid64.json') -PathType Leaf
    })
    if ($found.Count -eq 0) {
        throw 'Project Zomboid was not found. Re-run Install.bat from a terminal with -GameRoot "D:\SteamLibrary\steamapps\common\ProjectZomboid".'
    }
    return $found[0]
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) { $GameRoot = Find-ProjectZomboidRoot }
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$ModsRoot = [System.IO.Path]::GetFullPath($ModsRoot)
$InstallDataRoot = [System.IO.Path]::GetFullPath($InstallDataRoot)
$bridgeJar = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar'
if (-not (Test-Path -LiteralPath $bridgeJar -PathType Leaf)) {
    throw 'The bundled native bridge is missing. Download a complete release or source archive again.'
}

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('LivingFellowsStandalone-' + [guid]::NewGuid().ToString('N'))
$tempPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
try {
    & (Join-Path $ProjectRoot 'scripts\New-StandalonePayload.ps1') `
        -ProjectRoot $ProjectRoot -OutputRoot $stageRoot -AllowExternalOutput | Out-Null
    & (Join-Path $ProjectRoot 'scripts\Install-Local.ps1') `
        -ProjectRoot $ProjectRoot -ModsRoot $ModsRoot -GameRoot $GameRoot `
        -BackupRoot (Join-Path $InstallDataRoot 'mod-backups') `
        -BridgeRoot (Join-Path $InstallDataRoot 'bridge') `
        -ConfigBackupRoot (Join-Path $InstallDataRoot 'config-backups') `
        -PreparedPayloadRoot (Join-Path $stageRoot 'SurvivorCompanion') `
        -PrebuiltBridgeJar $bridgeJar -Standalone
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        $resolved = [System.IO.Path]::GetFullPath($stageRoot)
        if (-not $resolved.StartsWith($tempPrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean unexpected standalone stage: $resolved"
        }
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}

Write-Output ''
Write-Output 'INSTALL COMPLETE'
Write-Output 'Start Project Zomboid and enable Living Fellows: Companion for the save.'
Write-Output 'Do not enable a second Workshop copy at the same time.'
