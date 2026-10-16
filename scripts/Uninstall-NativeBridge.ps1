# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge'),
    [switch]$PreflightOnly,
    [string]$ExpectedCurrentConfigSha256 = ''
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
$launcherJar = ''
$launcherJarExisted = $false
if ($manifest.launcherJar) {
    $launcherJar = [System.IO.Path]::GetFullPath([string]$manifest.launcherJar)
    if (-not (Same-Path $launcherJar (Join-Path $gameRoot 'LivingFellowsBridge.jar')) -or
        [string]$manifest.launcherClasspathEntry -ne 'LivingFellowsBridge.jar' -or
        [string]$manifest.launcherJarSha256 -ne [string]$manifest.bridgeSha256) {
        throw 'Owned game-local launcher JAR manifest is inconsistent.'
    }
    $launcherJarExisted = Test-Path -LiteralPath $launcherJar -PathType Leaf
    if ($launcherJarExisted -and
        (Get-HashOrEmpty $launcherJar) -ne [string]$manifest.launcherJarSha256) {
        throw 'Owned game-local launcher JAR changed; refusing automatic rollback.'
    }
}

$configHash = Get-HashOrEmpty $configPath
$installedConfigHash = [string]$manifest.installedConfigSha256
if ([string]::IsNullOrWhiteSpace($installedConfigHash)) {
    throw 'Native bridge manifest has no installedConfigSha256; refusing automatic rollback.'
}
if ($ExpectedCurrentConfigSha256 -and $configHash -ne $ExpectedCurrentConfigSha256.ToLowerInvariant()) {
    throw 'Launcher configuration changed after uninstall preflight; refusing automatic rollback.'
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
$wrapper = [string]$manifest.wrapperMainClass
if ($config.mainClass -ne $wrapper) {
    throw "Launcher mainClass changed after installation; refusing automatic rollback: $($config.mainClass)"
}
$jarArgument = if ($launcherJar) { 'LivingFellowsBridge.jar' }
    else { $bridgeJar.Replace('\', '/') }
$classpathMatches = @($config.classpath | Where-Object {
    ([string]$_).Replace('\', '/').Equals($jarArgument,
        [System.StringComparison]::OrdinalIgnoreCase)
})
if ($classpathMatches.Count -ne 1) {
    throw 'SCLauncher classpath ownership is missing or duplicated; refusing automatic rollback.'
}
$originalBackup = [System.IO.Path]::GetFullPath([string]$manifest.originalConfigBackup)
if (-not (Test-Path -LiteralPath $originalBackup -PathType Leaf)) {
    throw "Original launcher backup is missing: $originalBackup"
}
$originalHash = Get-HashOrEmpty $originalBackup
$recordedOriginalHash = [string]$manifest.originalConfigSha256
if ([string]::IsNullOrWhiteSpace($recordedOriginalHash)) {
    throw 'Native bridge manifest has no originalConfigSha256; refusing automatic rollback.'
}
if ($originalHash -ne $recordedOriginalHash.ToLowerInvariant()) {
    throw 'Original launcher backup hash no longer matches the owned manifest.'
}
$original = Get-Content -LiteralPath $originalBackup -Raw -Encoding utf8 | ConvertFrom-Json
if ([string]$original.mainClass -ne [string]$manifest.originalMainClass -or
    [string]$original.mainClass -eq $wrapper) {
    throw 'Original launcher backup does not preserve the true original main class.'
}

$mode = if (-not [bool]$manifest.preserveLauncherEdits -and
    $configHash -eq $installedConfigHash.ToLowerInvariant()) { 'exact' } else { 'selective' }
$expectedHash = $originalHash
$updatedConfigText = ''
if ($mode -eq 'selective') {
    # Keep later VM and classpath edits from other mods; remove only our entries.
    $config.mainClass = [string]$manifest.originalMainClass
    $config.classpath = @($config.classpath | Where-Object {
        -not ([string]$_).Replace('\', '/').Equals($jarArgument,
            [System.StringComparison]::OrdinalIgnoreCase)
    })
    $updatedConfigText = $config | ConvertTo-Json -Depth 100
    $roundTrip = $updatedConfigText | ConvertFrom-Json
    if ([string]$roundTrip.mainClass -ne [string]$manifest.originalMainClass -or
        @($roundTrip.classpath | Where-Object {
            ([string]$_).Replace('\', '/').Equals($jarArgument,
                [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -ne 0) {
        throw 'Selective launcher rollback failed validation.'
    }
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $expectedHash = [System.BitConverter]::ToString(
            $hasher.ComputeHash($utf8NoBom.GetBytes($updatedConfigText))).Replace('-', '').ToLowerInvariant()
    } finally { $hasher.Dispose() }
}

if ($PreflightOnly) {
    Write-Output "NATIVE_BRIDGE_UNINSTALL_PREFLIGHT_PASS config=$configPath jar=$bridgeJar mode=$mode currentHash=$configHash expectedHash=$expectedHash"
    return
}

$transactionRoot = Join-Path $BridgeRoot ('.uninstall-transaction.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
$currentConfigBackup = Join-Path $transactionRoot 'ProjectZomboid64.managed.json'
$currentLauncherJarBackup = Join-Path $transactionRoot 'LivingFellowsBridge.jar'
$currentManifestBackup = Join-Path $transactionRoot 'install-manifest.json'
$stagedOriginal = Join-Path $transactionRoot 'ProjectZomboid64.restored.json'
Copy-Item -LiteralPath $configPath -Destination $currentConfigBackup
if ($launcherJarExisted) {
    Copy-Item -LiteralPath $launcherJar -Destination $currentLauncherJarBackup
}
Copy-Item -LiteralPath $manifestPath -Destination $currentManifestBackup
if ($mode -eq 'exact') {
    Copy-Item -LiteralPath $originalBackup -Destination $stagedOriginal
} else {
    [System.IO.File]::WriteAllText($stagedOriginal, $updatedConfigText, $utf8NoBom)
}
if ((Get-HashOrEmpty $stagedOriginal) -ne $expectedHash) {
    throw 'Staged launcher rollback hash mismatch.'
}
$disabledManifest = Join-Path $BridgeRoot `
    ('install-manifest.uninstalled.' + (Get-Date -Format 'yyyyMMdd-HHmmss') `
        + '-' + ([guid]::NewGuid().ToString('N')).Substring(0, 8) + '.json')

try {
    if ((Get-HashOrEmpty $configPath) -ne $configHash) {
        throw 'Launcher configuration changed during uninstall; refusing automatic rollback.'
    }
    Copy-Item -LiteralPath $stagedOriginal -Destination $configPath -Force
    if ((Get-HashOrEmpty $configPath) -ne $expectedHash) {
        throw 'Launcher configuration restore hash mismatch.'
    }
    if ($launcherJarExisted) {
        Remove-Item -LiteralPath $launcherJar -Force
    }
    Move-Item -LiteralPath $manifestPath -Destination $disabledManifest
}
catch {
    $trigger = $_
    $rollbackFailures = @()
    try { Copy-Item -LiteralPath $currentConfigBackup -Destination $configPath -Force }
    catch { $rollbackFailures += "config restore: $($_.Exception.Message)" }
    try {
        if ($launcherJarExisted) {
            Copy-Item -LiteralPath $currentLauncherJarBackup -Destination $launcherJar -Force
        }
    } catch { $rollbackFailures += "game-local JAR restore: $($_.Exception.Message)" }
    try {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Copy-Item -LiteralPath $currentManifestBackup -Destination $manifestPath
        }
    } catch { $rollbackFailures += "manifest restore: $($_.Exception.Message)" }
    if ((Get-HashOrEmpty $configPath) -ne (Get-HashOrEmpty $currentConfigBackup)) {
        $rollbackFailures += 'config rollback hash mismatch'
    }
    if ($launcherJarExisted -and
        (Get-HashOrEmpty $launcherJar) -ne (Get-HashOrEmpty $currentLauncherJarBackup)) {
        $rollbackFailures += 'game-local JAR rollback hash mismatch'
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

Write-Output "NATIVE_BRIDGE_UNINSTALL_PASS config=$configPath retainedJar=$bridgeJar mode=$mode restoredHash=$expectedHash"
