# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ModsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods'),
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge'),
    [switch]$KeepNativeBridge,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
# Must match the stable ownership id written by every managed local build.
$Owner = 'LivingFellows.Companion.cleanroom.0.9.0'
$bridgeRootWasExplicit = $PSBoundParameters.ContainsKey('BridgeRoot')

function Test-SamePath([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\')).Equals(
        [System.IO.Path]::GetFullPath($Right).TrimEnd('\'),
        [System.StringComparison]::OrdinalIgnoreCase)
}

$ModsRoot = [System.IO.Path]::GetFullPath($ModsRoot)
$liveCacheRoot = [System.IO.Path]::GetFullPath(
    (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'))
$liveCachePrefix = $liveCacheRoot.TrimEnd('\') + '\'
if (($ModsRoot.StartsWith($liveCachePrefix, [System.StringComparison]::OrdinalIgnoreCase)) -and
    (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue)) {
    throw 'Close Project Zomboid before uninstalling.'
}
$Target = Join-Path $ModsRoot 'SurvivorCompanion'
$rootPrefix = $ModsRoot.TrimEnd('\') + '\'
if (-not ([System.IO.Path]::GetFullPath($Target)).StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Invalid uninstall target: $Target"
}
$manifestPath = Join-Path $Target '.sc-install-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "No owned Living Fellows install was found at $Target"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($manifest.owner -ne $Owner) { throw "Refusing to remove target owned by $($manifest.owner)" }
$manifestBridgeRoot = [string]$manifest.bridgeRoot
if ([string]::IsNullOrWhiteSpace($manifestBridgeRoot)) {
    throw 'Owned mod manifest has no bridgeRoot; refusing uninstall before mutation.'
}
$manifestBridgeRoot = [System.IO.Path]::GetFullPath($manifestBridgeRoot).TrimEnd('\')
if ($bridgeRootWasExplicit -and -not (Test-SamePath $BridgeRoot $manifestBridgeRoot)) {
    throw "Explicit BridgeRoot does not match the owned mod manifest: $BridgeRoot"
}
$BridgeRoot = $manifestBridgeRoot

$changed = @()
$targetPrefix = [System.IO.Path]::GetFullPath($Target).TrimEnd('\') + '\'
foreach ($property in $manifest.files.PSObject.Properties) {
    $file = Join-Path $Target ($property.Name.Replace('/', '\'))
    $fileMissing = -not (Test-Path -LiteralPath $file -PathType Leaf)
    $hashChanged = $false
    if (-not $fileMissing) {
        $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashChanged = $actualHash -ne $property.Value
    }
    if ($fileMissing -or $hashChanged) {
        $changed += $property.Name
    }
}
$ownedNames = @($manifest.files.PSObject.Properties.Name) + '.sc-install-manifest.json'
Get-ChildItem -LiteralPath $Target -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($targetPrefix.Length).Replace('\', '/')
    if ($relative -notin $ownedNames) { $changed += $relative }
}
if ($changed.Count -gt 0 -and -not $Force) {
    throw "Installed files changed or were added; refusing uninstall without -Force: $($changed -join ', ')"
}

$backup = [string]$manifest.backupPath
if ($backup) {
    $backup = [System.IO.Path]::GetFullPath($backup)
    $backupRoot = [string]$manifest.backupRoot
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        throw 'Manifest has a managed backup but no external backup root.'
    }
    $backupRoot = [System.IO.Path]::GetFullPath($backupRoot)
    $backupPrefix = $backupRoot.TrimEnd('\') + '\'
    $backupInRoot = $backup.StartsWith($backupPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    $backupLeaf = Split-Path -Leaf $backup
    $backupOwnedName = $backupLeaf.StartsWith('SurvivorCompanion-managed-backup-')
    if (-not $backupInRoot -or -not $backupOwnedName) {
        throw "Manifest contains an unsafe backup path: $backup"
    }
    $normalizedBackupRoot = $backupRoot.TrimEnd('\')
    $normalizedModsRoot = $ModsRoot.TrimEnd('\')
    $backupSameAsMods = $normalizedBackupRoot.Equals($normalizedModsRoot,
        [System.StringComparison]::OrdinalIgnoreCase)
    $backupInsideMods = $backupRoot.StartsWith($rootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)
    if ($backupSameAsMods -or $backupInsideMods) {
        throw "Manifest backup root is inside the live mods directory: $backupRoot"
    }
    if (-not (Test-Path -LiteralPath $backup -PathType Container)) {
        throw "Managed backup is missing: $backup"
    }
    $backupManifestPath = Join-Path $backup '.sc-install-manifest.json'
    if (-not (Test-Path -LiteralPath $backupManifestPath -PathType Leaf)) {
        throw "Managed backup has no ownership manifest: $backup"
    }
    $backupManifest = Get-Content -LiteralPath $backupManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($backupManifest.owner -ne $Owner) {
        throw "Managed backup has unexpected owner: $($backupManifest.owner)"
    }
}
$isFinalGeneration = [string]::IsNullOrWhiteSpace($backup)
$nativeUninstaller = Join-Path $PSScriptRoot 'Uninstall-NativeBridge.ps1'
if ($isFinalGeneration) {
    $nativeManifest = Join-Path $BridgeRoot 'install-manifest.json'
    if (-not (Test-Path -LiteralPath $nativeManifest -PathType Leaf)) {
        throw "Final managed generation requires its native rollback manifest: $nativeManifest"
    }
    # Validate launcher ownership, exact installed hashes, original backup and
    # canonical bridge paths before moving even the first mod file.
    & $nativeUninstaller -BridgeRoot $BridgeRoot -PreflightOnly | Out-Null
}
$quarantine = Join-Path $ModsRoot ('.SurvivorCompanion.uninstall.' + [guid]::NewGuid().ToString('N'))
$restoredBackup = $false
try {
    Move-Item -LiteralPath $Target -Destination $quarantine
    if ($backup) {
        Move-Item -LiteralPath $backup -Destination $Target
        $restoredBackup = $true
    }
    if ($isFinalGeneration -and -not $KeepNativeBridge) {
        # The native uninstaller is itself transactional. Keep the mod in
        # quarantine until it commits so a failed launcher rollback can restore
        # the exact live generation.
        & $nativeUninstaller -BridgeRoot $BridgeRoot | Out-Null
    }
}
catch {
    $targetExists = Test-Path -LiteralPath $Target
    $backupMissing = $backup -and -not (Test-Path -LiteralPath $backup)
    if ($restoredBackup -and $targetExists -and $backupMissing) {
        Move-Item -LiteralPath $Target -Destination $backup
    }
    $quarantineExists = Test-Path -LiteralPath $quarantine -PathType Container
    $targetMissing = -not (Test-Path -LiteralPath $Target)
    if ($quarantineExists -and $targetMissing) {
        Move-Item -LiteralPath $quarantine -Destination $Target
    }
    throw
}

# At this point either a prior generation is live, the caller deliberately
# retained a preflighted bridge, or the native rollback committed. Failure to
# delete this no-longer-live quarantine must not roll back a successful native
# transaction into an inconsistent half-install.
try { Remove-Item -LiteralPath $quarantine -Recurse -Force }
catch { Write-Warning "Owned uninstall quarantine was retained at $quarantine`: $($_.Exception.Message)" }

Write-Output "Removed owned Living Fellows install at $Target"
if ($restoredBackup) { Write-Output "Restored prior managed install from $backup" }
if ($isFinalGeneration -and -not $KeepNativeBridge) {
    Write-Output 'Restored the original Project Zomboid launcher configuration.'
}
