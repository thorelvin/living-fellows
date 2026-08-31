# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputRoot = '',
    [switch]$AllowExternalOutput
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $scriptDirectory
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\private-playtest'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$Payload = Join-Path $ProjectRoot 'SurvivorCompanion'
$Destination = Join-Path $OutputRoot 'SurvivorCompanion'
$projectPrefix = $ProjectRoot.TrimEnd('\') + '\'
$outputIsProject = $OutputRoot.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$outputIsTemporary = $OutputRoot.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase)
if (-not $AllowExternalOutput -and -not $outputIsProject -and -not $outputIsTemporary) {
    throw "Private payload output must be under the project or temporary directory: $OutputRoot"
}
if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Copy-Item -LiteralPath $Payload -Destination $Destination -Recurse

# Public Workshop builds require ZombieBuddy.  The private native playtest uses
# the separately installed, reversible SCLauncher instead, so leaving the
# Workshop dependency here would make Build 42 disable the mod before the local
# bridge can be exercised.  Only this copied payload drops the dependency.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($metadataPath in @(
        (Join-Path $Destination 'mod.info'),
        (Join-Path $Destination '42\mod.info'))) {
    $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding utf8
    $metadata = [regex]::Replace($metadata,
        '(?m)^require=\\ZombieBuddy\r?\n', '')
    $metadata = [regex]::Replace($metadata,
        '(?m)^ZBVersionMin=2\.3\.3\r?\n', '')
    $metadata = $metadata.Replace(
        'Requires ZombieBuddy 2.3.3 or newer.',
        'Uses the local development bridge launcher.')
    if (($metadata -match '(?m)^require=\\ZombieBuddy$') -or
        ($metadata -match '(?m)^ZBVersionMin=')) {
        throw "Private payload retained its Workshop-only loader dependency: $metadataPath"
    }
    [System.IO.File]::WriteAllText($metadataPath, $metadata, $utf8NoBom)
}

$Config = Join-Path $Destination '42\media\lua\shared\SCConfig.lua'
$text = Get-Content -LiteralPath $Config -Raw -Encoding utf8
$experimentalOff = '    experimentalNpcPlayerActor = false,'
$debugOff = '    debugSpawnEnabled = false,'
$movementRecorderOff = '    movementRecorderEnabled = false,'
$experimentalCount = [regex]::Matches($text, [regex]::Escape($experimentalOff)).Count
$debugCount = [regex]::Matches($text, [regex]::Escape($debugOff)).Count
$movementRecorderCount = [regex]::Matches($text, [regex]::Escape($movementRecorderOff)).Count
if ($experimentalCount -ne 1 -or $debugCount -ne 1 -or $movementRecorderCount -ne 1) {
    throw 'Private-playtest configuration markers were not found exactly once.'
}
$text = $text.Replace($debugOff, '    debugSpawnEnabled = true,')
$text = $text.Replace($movementRecorderOff, '    movementRecorderEnabled = true,')
[System.IO.File]::WriteAllText($Config, $text, $utf8NoBom)

$marker = @'
PRIVATE NATIVE BRIDGE PLAYTEST - NOT FOR PUBLIC RELEASE

This copy enables the in-game Debug tab and its manual spawn controls. Actor
creation requires the version-pinned SurvivorCompanionBridge bootstrap. The
original SCNativeCompanion class extends IsoPlayer but never occupies a local
player slot. Multiplayer and split-screen fail closed.

Any native health or isolation failure freezes and removes the candidate. Test
manual household spawn, faction behavior, animation, combat, inventory,
vehicles, death, Knox and save/load before publishing this build.
'@
$markerPath = Join-Path $Destination 'PRIVATE-NATIVE-BRIDGE.txt'
[System.IO.File]::WriteAllText($markerPath, $marker, $utf8NoBom)
$markerBytes = [System.IO.File]::ReadAllBytes($markerPath)
if (@($markerBytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
    throw 'Private marker must remain plain ASCII.'
}

$classes = Get-ChildItem -LiteralPath $Destination -Recurse -File -Filter '*.class'
if ($classes) { throw 'Private payload contains loose Java classes.' }
$jars = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -Filter '*.jar')
$expectedJar = Join-Path $Destination '42\media\java\SurvivorCompanionBridge.jar'
if ($jars.Count -ne 1 -or $jars[0].FullName -ne $expectedJar) {
    throw 'Private payload must contain exactly the versioned SurvivorCompanion bridge JAR.'
}
Write-Output $Destination
