# SPDX-License-Identifier: MIT

[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $ProjectRoot 'tests\core\pz-runtime.json'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Pinned Project Zomboid runtime manifest is missing: $ManifestPath"
}

$Runtime = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$ExpectedVersion = [string]$Runtime.gameVersion
$ExpectedHash = ([string]$Runtime.projectZomboidJarSha256).ToUpperInvariant()
$ExpectedBytes = [long]$Runtime.projectZomboidJarBytes
$JavaRelativePath = [string]$Runtime.javaRelativePath
if ([string]::IsNullOrWhiteSpace($ExpectedVersion) -or
    $ExpectedHash -notmatch '^[0-9A-F]{64}$' -or
    $ExpectedBytes -le 0 -or
    [string]::IsNullOrWhiteSpace($JavaRelativePath)) {
    throw "Pinned Project Zomboid runtime manifest is invalid: $ManifestPath"
}

$ResolvedGameRoot = (Resolve-Path -LiteralPath $GameRoot -ErrorAction Stop).Path
$Jar = Join-Path $ResolvedGameRoot 'projectzomboid.jar'
$GameJava = Join-Path $ResolvedGameRoot $JavaRelativePath
if (-not (Test-Path -LiteralPath $Jar -PathType Leaf)) {
    throw "Pinned Project Zomboid JAR not found: $Jar"
}
if (-not (Test-Path -LiteralPath $GameJava -PathType Leaf)) {
    throw "Pinned Project Zomboid Java runtime not found: $GameJava"
}

$ActualBytes = (Get-Item -LiteralPath $Jar).Length
if ($ActualBytes -ne $ExpectedBytes) {
    throw "Project Zomboid JAR size mismatch for $ExpectedVersion. Expected $ExpectedBytes bytes; received $ActualBytes. Review and repin tests/core/pz-runtime.json before releasing against a new game build."
}
$ActualHash = (Get-FileHash -LiteralPath $Jar -Algorithm SHA256).Hash.ToUpperInvariant()
if ($ActualHash -ne $ExpectedHash) {
    throw "Project Zomboid JAR SHA-256 mismatch for $ExpectedVersion. Expected $ExpectedHash; received $ActualHash. Review and repin tests/core/pz-runtime.json before releasing against a new game build."
}

$Namespace = Get-Content -LiteralPath (Join-Path $ProjectRoot `
    'SurvivorCompanion\42\media\lua\shared\SCNamespace.lua') -Raw
$Installer = Get-Content -LiteralPath (Join-Path $ProjectRoot `
    'scripts\Install-NativeBridge.ps1') -Raw
$NamespaceMatch = [regex]::Match($Namespace, 'gameVersion\s*=\s*"([^"]+)"')
$InstallerMatch = [regex]::Match($Installer, "\`$ExpectedCompiledGame\s*=\s*'([^']+)'")
if (-not $NamespaceMatch.Success -or $NamespaceMatch.Groups[1].Value -ne $ExpectedVersion) {
    throw "SC.Identity.gameVersion does not match pinned runtime $ExpectedVersion."
}
if (-not $InstallerMatch.Success -or $InstallerMatch.Groups[1].Value -ne $ExpectedVersion) {
    throw "Install-NativeBridge ExpectedCompiledGame does not match pinned runtime $ExpectedVersion."
}

Write-Output "PZ_RUNTIME_PASS version=$ExpectedVersion jar-sha256=$ActualHash bytes=$ActualBytes"
