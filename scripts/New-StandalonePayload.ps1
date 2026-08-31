# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputRoot = '',
    [switch]$AllowExternalOutput
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\standalone-payload'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$payload = Join-Path $ProjectRoot 'SurvivorCompanion'
$destination = Join-Path $OutputRoot 'SurvivorCompanion'
$projectPrefix = $ProjectRoot.TrimEnd('\') + '\'
$outputIsProject = $OutputRoot.StartsWith($projectPrefix,
    [System.StringComparison]::OrdinalIgnoreCase)
$outputIsTemporary = $OutputRoot.StartsWith([System.IO.Path]::GetTempPath(),
    [System.StringComparison]::OrdinalIgnoreCase)
if (-not $AllowExternalOutput -and -not $outputIsProject -and -not $outputIsTemporary) {
    throw "Standalone payload output must be under the project or temporary directory: $OutputRoot"
}
if (-not (Test-Path -LiteralPath $payload -PathType Container)) {
    throw "Canonical mod payload was not found: $payload"
}
if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Copy-Item -LiteralPath $payload -Destination $destination -Recurse

# The Workshop build delegates JAR loading to ZombieBuddy. The standalone
# installer activates the exact same owned bridge before the game starts, so
# this staged copy must not retain the Workshop dependency declaration.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($metadataPath in @(
        (Join-Path $destination 'mod.info'),
        (Join-Path $destination '42\mod.info'))) {
    $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding utf8
    $metadata = [regex]::Replace($metadata, '(?m)^require=\\ZombieBuddy\r?\n', '')
    $metadata = [regex]::Replace($metadata, '(?m)^ZBVersionMin=2\.3\.3\r?\n', '')
    $metadata = $metadata.Replace(
        'Requires ZombieBuddy 2.3.3 or newer.',
        'Uses the bundled standalone bridge installer.')
    if (($metadata -match '(?m)^require=\\ZombieBuddy$') -or
        ($metadata -match '(?m)^ZBVersionMin=')) {
        throw "Standalone payload retained its Workshop dependency: $metadataPath"
    }
    [System.IO.File]::WriteAllText($metadataPath, $metadata, $utf8NoBom)
}

$configPath = Join-Path $destination '42\media\lua\shared\SCConfig.lua'
$config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
foreach ($required in @(
        'experimentalNpcPlayerActor = false,',
        'debugSpawnEnabled = false,',
        'movementRecorderEnabled = false,')) {
    if ([regex]::Matches($config, [regex]::Escape($required)).Count -ne 1) {
        throw "Standalone public configuration marker was not found exactly once: $required"
    }
}

$marker = @'
LIVING FELLOWS STANDALONE INSTALL

This public copy uses the bundled, version-pinned SurvivorCompanionBridge.
Install.bat activates it through a reversible launcher entry and stores the
original ProjectZomboid64.json configuration for Uninstall.bat to restore.

The bridge is owned by Living Fellows, contains no Project Zomboid classes,
does not modify projectzomboid.jar, and fails closed in multiplayer or split
screen. Public settings are retained; private debug controls stay disabled.
'@
$markerPath = Join-Path $destination 'STANDALONE-NATIVE-BRIDGE.txt'
[System.IO.File]::WriteAllText($markerPath, $marker, $utf8NoBom)

if (Get-ChildItem -LiteralPath $destination -Recurse -File -Filter '*.class') {
    throw 'Standalone payload contains forbidden loose Java classes.'
}
$jars = @(Get-ChildItem -LiteralPath $destination -Recurse -File -Filter '*.jar')
$expectedJar = Join-Path $destination '42\media\java\SurvivorCompanionBridge.jar'
if ($jars.Count -ne 1 -or $jars[0].FullName -ne $expectedJar) {
    throw 'Standalone payload must contain exactly one owned native bridge JAR.'
}

Write-Output $destination
