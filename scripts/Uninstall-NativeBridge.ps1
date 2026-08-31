# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge')
)

$ErrorActionPreference = 'Stop'
$Owner = 'SurvivorCompanion.NativeBridge'
$BridgeRoot = [System.IO.Path]::GetFullPath($BridgeRoot).TrimEnd('\')
$manifestPath = Join-Path $BridgeRoot 'install-manifest.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-HashOrEmpty([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Same-Path([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\')).Equals(
        [System.IO.Path]::GetFullPath($Right).TrimEnd('\'),
        [System.StringComparison]::OrdinalIgnoreCase)
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "No owned native bridge manifest was found at $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($manifest.owner -ne $Owner) { throw "Refusing to remove bridge owned by $($manifest.owner)" }
if (-not (Same-Path ([string]$manifest.bridgeRoot) $BridgeRoot)) {
    throw 'Native manifest bridge root does not match the requested uninstall root.'
}

$configPath = [System.IO.Path]::GetFullPath([string]$manifest.gameConfig)
$gameRoot = [System.IO.Path]::GetFullPath([string]$manifest.gameRoot).TrimEnd('\')
if (-not (Same-Path (Split-Path -Parent $configPath) $gameRoot)) {
    throw 'Native manifest game root and launcher configuration path disagree.'
}
$gameExecutable = Join-Path $gameRoot 'ProjectZomboid64.exe'
if ((Test-Path -LiteralPath $gameExecutable -PathType Leaf) -and
    (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue)) {
    throw 'Close Project Zomboid before uninstalling the native companion bridge.'
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Project Zomboid launcher configuration is missing: $configPath"
}
$bridgeJar = [System.IO.Path]::GetFullPath([string]$manifest.bridgeJar)
if (-not (Same-Path $bridgeJar (Join-Path $BridgeRoot 'SurvivorCompanionBridge.jar'))) {
    throw 'Native manifest JAR path is outside its owned bridge location.'
}
if (-not (Test-Path -LiteralPath $bridgeJar -PathType Leaf) -or
    (Get-HashOrEmpty $bridgeJar) -ne [string]$manifest.bridgeSha256) {
    throw 'Owned native bridge JAR is missing or changed; refusing automatic launcher rollback.'
}

$configHash = Get-HashOrEmpty $configPath
if ($manifest.installedConfigSha256 -and
    $configHash -ne [string]$manifest.installedConfigSha256) {
    throw 'Launcher configuration changed after installation; refusing automatic rollback.'
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
$wrapper = [string]$manifest.wrapperMainClass
if ($config.mainClass -ne $wrapper) {
    throw "Launcher mainClass changed after installation; refusing automatic rollback: $($config.mainClass)"
}
$originalBackup = [System.IO.Path]::GetFullPath([string]$manifest.originalConfigBackup)
if (-not (Test-Path -LiteralPath $originalBackup -PathType Leaf)) {
    throw "Original launcher backup is missing: $originalBackup"
}
$originalHash = Get-HashOrEmpty $originalBackup
if ($manifest.originalConfigSha256 -and
    $originalHash -ne [string]$manifest.originalConfigSha256) {
    throw 'Original launcher backup hash no longer matches the owned manifest.'
}
$original = Get-Content -LiteralPath $originalBackup -Raw -Encoding utf8 | ConvertFrom-Json
if ([string]$original.mainClass -ne [string]$manifest.originalMainClass -or
    [string]$original.mainClass -eq $wrapper) {
    throw 'Original launcher backup does not preserve the true original main class.'
}

$transactionRoot = Join-Path $BridgeRoot ('.uninstall-transaction.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
$currentConfigBackup = Join-Path $transactionRoot 'ProjectZomboid64.managed.json'
$currentManifestBackup = Join-Path $transactionRoot 'install-manifest.json'
$stagedOriginal = Join-Path $transactionRoot 'ProjectZomboid64.original.json'
Copy-Item -LiteralPath $configPath -Destination $currentConfigBackup
Copy-Item -LiteralPath $manifestPath -Destination $currentManifestBackup
Copy-Item -LiteralPath $originalBackup -Destination $stagedOriginal
$disabledManifest = Join-Path $BridgeRoot `
    ('install-manifest.uninstalled.' + (Get-Date -Format 'yyyyMMdd-HHmmss') `
        + '-' + ([guid]::NewGuid().ToString('N')).Substring(0, 8) + '.json')

try {
    Copy-Item -LiteralPath $stagedOriginal -Destination $configPath -Force
    if ((Get-HashOrEmpty $configPath) -ne $originalHash) {
        throw 'Original launcher configuration restore hash mismatch.'
    }
    Move-Item -LiteralPath $manifestPath -Destination $disabledManifest
}
catch {
    $trigger = $_
    $rollbackFailures = @()
    try { Copy-Item -LiteralPath $currentConfigBackup -Destination $configPath -Force }
    catch { $rollbackFailures += "config restore: $($_.Exception.Message)" }
    try {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Copy-Item -LiteralPath $currentManifestBackup -Destination $manifestPath
        }
    } catch { $rollbackFailures += "manifest restore: $($_.Exception.Message)" }
    if ((Get-HashOrEmpty $configPath) -ne (Get-HashOrEmpty $currentConfigBackup)) {
        $rollbackFailures += 'config rollback hash mismatch'
    }
    if ((Get-HashOrEmpty $manifestPath) -ne (Get-HashOrEmpty $currentManifestBackup)) {
        $rollbackFailures += 'manifest rollback hash mismatch'
    }
    if ($rollbackFailures.Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            $trigger.Exception.Message + ' Rollback failures: ' + ($rollbackFailures -join '; '),
            $trigger.Exception)
    }
    throw $trigger
}
finally {
    if (Test-Path -LiteralPath $transactionRoot) {
        try { Remove-Item -LiteralPath $transactionRoot -Recurse -Force }
        catch { Write-Warning "Could not remove native uninstall staging directory: $($_.Exception.Message)" }
    }
}

Write-Output "NATIVE_BRIDGE_UNINSTALL_PASS config=$configPath retainedJar=$bridgeJar restoredHash=$originalHash"
