# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [ValidateSet('playtest', 'public-beta', 'release')]
    [string]$Channel = 'playtest'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$Payload = Join-Path $ProjectRoot 'SurvivorCompanion'
$Workshop = Join-Path $ProjectRoot 'Workshop'
$ModsStageRoot = Join-Path $Workshop 'Contents\mods'
$Stage = Join-Path $ModsStageRoot 'SurvivorCompanion'
$Build = Join-Path $ProjectRoot 'build\release'
$VersionFile = Join-Path $ProjectRoot 'VERSION.txt'
if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    throw "Canonical version file is missing: $VersionFile"
}
$ReleaseVersion = (Get-Content -LiteralPath $VersionFile -Raw -Encoding utf8).Trim()
if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Canonical version must use MAJOR.MINOR.PATCH: $ReleaseVersion"
}
$ChannelLabel = switch ($Channel) {
    'playtest' { 'PLAYTEST' }
    'public-beta' { 'PUBLIC-BETA' }
    'release' { 'RELEASE' }
}
$Zip = Join-Path $Build ("LivingFellowsCompanion-$ReleaseVersion-$ChannelLabel.zip")
$Manifest = Join-Path $Build 'HASH-MANIFEST.sha256'
$Config = Join-Path $Payload '42\media\lua\shared\SCConfig.lua'

function Assert-ChildPath([string]$Parent, [string]$Child) {
    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $childPath = [System.IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing operation outside $Parent`: $Child"
    }
}

function RelativeHashes([string]$Root) {
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $result = [ordered]@{}
    Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($rootPath.Length).Replace('\', '/')
        $result[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $result
}

& (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') `
    -ProjectRoot $ProjectRoot -InstallIntoPayload | Out-Null
if (-not (Test-Path -LiteralPath $Payload -PathType Container)) { throw "Payload not found: $Payload" }
$configText = Get-Content -LiteralPath $Config -Raw -Encoding utf8
if ($configText -notmatch '(?m)^\s*experimentalNpcPlayerActor\s*=\s*false,\s*$') {
    throw 'Workshop staging requires experimentalNpcPlayerActor=false in source.'
}
if ($configText -notmatch '(?m)^\s*debugSpawnEnabled\s*=\s*false,\s*$') {
    throw 'Workshop staging requires debugSpawnEnabled=false in source.'
}
if ($configText -notmatch '(?m)^\s*movementRecorderEnabled\s*=\s*false,\s*$') {
    throw 'Workshop staging requires movementRecorderEnabled=false in source.'
}
$looseClasses = Get-ChildItem -LiteralPath $Payload -Recurse -File -Filter '*.class'
if ($looseClasses) { throw "Loose Java classes are forbidden in release payload: $($looseClasses.FullName -join ', ')" }
$payloadJars = @(Get-ChildItem -LiteralPath $Payload -Recurse -File -Filter '*.jar')
$expectedPayloadJar = Join-Path $Payload '42\media\java\SurvivorCompanionBridge.jar'
if ($payloadJars.Count -ne 1 -or $payloadJars[0].FullName -ne $expectedPayloadJar) {
    throw 'Release payload must contain exactly the owned versioned native bridge JAR.'
}

$rootMetadata = Get-Content -LiteralPath (Join-Path $Payload 'mod.info') -Raw -Encoding utf8
$versionMetadata = Get-Content -LiteralPath (Join-Path $Payload '42\mod.info') -Raw -Encoding utf8
if ($rootMetadata -ne $versionMetadata) { throw 'Root and 42 mod.info files must be identical.' }
$metadataMatch = [regex]::Match($rootMetadata, '(?m)^modversion=([^\r\n]+)$')
if (-not $metadataMatch.Success -or $metadataMatch.Groups[1].Value.Trim() -ne $ReleaseVersion) {
    throw "mod.info version does not match release package version $ReleaseVersion."
}
$namespaceText = Get-Content -LiteralPath (Join-Path $Payload '42\media\lua\shared\SCNamespace.lua') -Raw -Encoding utf8
$namespaceMatch = [regex]::Match($namespaceText, 'release\s*=\s*"([^"]+)"')
if (-not $namespaceMatch.Success -or $namespaceMatch.Groups[1].Value -ne $ReleaseVersion) {
    throw "SC.Identity.release does not match release package version $ReleaseVersion."
}
foreach ($required in @('workshop.txt', 'preview.png')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Workshop $required) -PathType Leaf)) {
        throw "Workshop file is missing: $required"
    }
}

Assert-ChildPath $ProjectRoot $ModsStageRoot
Assert-ChildPath $ProjectRoot $Build
if (Test-Path -LiteralPath $ModsStageRoot) { Remove-Item -LiteralPath $ModsStageRoot -Recurse -Force }
New-Item -ItemType Directory -Path $ModsStageRoot -Force | Out-Null
Copy-Item -LiteralPath $Payload -Destination $Stage -Recurse
$stagedMods = @(Get-ChildItem -LiteralPath $ModsStageRoot -Directory)
if ($stagedMods.Count -ne 1 -or $stagedMods[0].Name -ne 'SurvivorCompanion') {
    throw 'Workshop staging must contain exactly one SurvivorCompanion mod payload.'
}

$sourceHashes = RelativeHashes $Payload
$stageHashes = RelativeHashes $Stage
if (($sourceHashes.Keys -join "`n") -ne ($stageHashes.Keys -join "`n")) {
    throw 'Workshop staging file set differs from source payload.'
}
foreach ($relative in $sourceHashes.Keys) {
    if ($sourceHashes[$relative] -ne $stageHashes[$relative]) {
        throw "Workshop staging hash mismatch: $relative"
    }
}

New-Item -ItemType Directory -Path $Build -Force | Out-Null
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
Compress-Archive -LiteralPath (Join-Path $Workshop 'workshop.txt'), (Join-Path $Workshop 'preview.png'), (Join-Path $Workshop 'Contents') -DestinationPath $Zip -CompressionLevel Optimal

$ArchiveCheck = Join-Path $Build 'archive-content-check'
Assert-ChildPath $Build $ArchiveCheck
if (Test-Path -LiteralPath $ArchiveCheck) { Remove-Item -LiteralPath $ArchiveCheck -Recurse -Force }
try {
    Expand-Archive -LiteralPath $Zip -DestinationPath $ArchiveCheck
    foreach ($required in @('workshop.txt', 'preview.png', 'Contents\mods\SurvivorCompanion\mod.info',
            'Contents\mods\SurvivorCompanion\42\mod.info',
            'Contents\mods\SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar',
            'Contents\mods\SurvivorCompanion\LICENSE.txt',
            'Contents\mods\SurvivorCompanion\README.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ArchiveCheck $required) -PathType Leaf)) {
            throw "Archive is missing required content: $required"
        }
    }
    $archiveModsRoot = Join-Path $ArchiveCheck 'Contents\mods'
    $archiveMods = @(Get-ChildItem -LiteralPath $archiveModsRoot -Directory)
    if ($archiveMods.Count -ne 1 -or $archiveMods[0].Name -ne 'SurvivorCompanion') {
        throw 'Archive contains an unexpected mod payload.'
    }
    $forbidden = Get-ChildItem -LiteralPath $ArchiveCheck -Recurse -File | Where-Object {
        $_.Extension -eq '.class' -or $_.Name -like 'PRIVATE-*.txt'
    }
    if ($forbidden) { throw "Archive contains private or loose-class content: $($forbidden.FullName -join ', ')" }
    $archiveJars = @(Get-ChildItem -LiteralPath $ArchiveCheck -Recurse -File -Filter '*.jar')
    if ($archiveJars.Count -ne 1 -or $archiveJars[0].Name -ne 'SurvivorCompanionBridge.jar') {
        throw 'Archive native bridge JAR ownership check failed.'
    }
    $archiveConfig = Get-Content -LiteralPath (Join-Path $ArchiveCheck 'Contents\mods\SurvivorCompanion\42\media\lua\shared\SCConfig.lua') -Raw -Encoding utf8
    foreach ($setting in @('experimentalNpcPlayerActor', 'debugSpawnEnabled',
            'movementRecorderEnabled')) {
        if ($archiveConfig -notmatch "(?m)^\s*$setting\s*=\s*false,\s*$") {
            throw "Archive does not preserve the public false gate: $setting"
        }
    }
}
finally {
    if (Test-Path -LiteralPath $ArchiveCheck) { Remove-Item -LiteralPath $ArchiveCheck -Recurse -Force }
}

$lines = @('# SPDX-License-Identifier: MIT', '# source and Workshop staging hashes')
foreach ($relative in $sourceHashes.Keys) {
    $lines += "$($sourceHashes[$relative])  SurvivorCompanion/$relative"
}
$lines += "$( (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant() )  $(Split-Path -Leaf $Zip)"
Set-Content -LiteralPath $Manifest -Value $lines -Encoding utf8

Write-Output "Workshop review staging: $Stage"
Write-Output "$ChannelLabel archive: $Zip"
Write-Output "Hash manifest: $Manifest"
