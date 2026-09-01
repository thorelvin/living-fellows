# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$ModsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods'),
    [string]$InstallDataRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellows'),
    [ValidateSet('', 'standalone-snapshot', 'standalone-generation-remove',
        'standalone-native-rollback', 'standalone-postcondition')]
    [string]$FailAfter = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Owner = 'LivingFellows.Companion.cleanroom.0.9.0'

function Normalize-StandalonePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'A required path was empty.' }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-StandaloneSamePath([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    return (Normalize-StandalonePath $Left).Equals((Normalize-StandalonePath $Right),
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-StandalonePathWithin([string]$Path, [string]$Root) {
    $normalizedPath = Normalize-StandalonePath $Path
    $normalizedRoot = Normalize-StandalonePath $Root
    return $normalizedPath.StartsWith($normalizedRoot + '\',
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-StandaloneHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StandaloneTreeDigest([string]$Path) {
    $Path = Normalize-StandalonePath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return 'absent' }
    $prefix = $Path + '\'
    $entries = [ordered]@{ '<root>' = 'directory' }
    Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($prefix.Length).Replace('\', '/')
        if ($_.PSIsContainer) { $entries[$relative] = 'directory' }
        else { $entries[$relative] = 'file:' + (Get-StandaloneHash $_.FullName) }
    }
    return ($entries | ConvertTo-Json -Depth 20 -Compress)
}

function Copy-StandaloneDirectory([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function New-StandaloneDirectorySnapshot(
    [string]$Label, [string]$Source, [string]$SnapshotRoot) {
    $Source = Normalize-StandalonePath $Source
    $snapshotPath = Join-Path $SnapshotRoot $Label
    $existed = Test-Path -LiteralPath $Source -PathType Container
    $digest = Get-StandaloneTreeDigest $Source
    if ($existed) {
        Copy-StandaloneDirectory $Source $snapshotPath
        if ((Get-StandaloneTreeDigest $snapshotPath) -ne $digest) {
            throw "Standalone snapshot verification failed for $Label."
        }
    }
    return [ordered]@{
        label = $Label
        source = $Source
        snapshot = $snapshotPath
        existed = $existed
        digest = $digest
    }
}

function Restore-StandaloneDirectorySnapshot($Snapshot) {
    $source = Normalize-StandalonePath ([string]$Snapshot.source)
    if (Test-Path -LiteralPath $source) {
        Remove-Item -LiteralPath $source -Recurse -Force
    }
    if ([bool]$Snapshot.existed) {
        Copy-StandaloneDirectory ([string]$Snapshot.snapshot) $source
    }
    if ((Get-StandaloneTreeDigest $source) -ne [string]$Snapshot.digest) {
        throw "Standalone rollback verification failed for $($Snapshot.label)."
    }
}

function Invoke-StandaloneFault([string]$Boundary) {
    if ($FailAfter -eq $Boundary) {
        throw "Injected standalone uninstaller failure after $Boundary"
    }
}

function Read-OwnedStandaloneManifest([string]$GenerationPath) {
    $manifestPath = Join-Path $GenerationPath '.sc-install-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Managed standalone generation has no ownership manifest: $GenerationPath"
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
            ConvertFrom-Json
    } catch {
        throw "Managed standalone generation has invalid manifest JSON: $GenerationPath"
    }
    if ([string]$manifest.owner -ne $Owner) {
        throw "Refusing standalone generation owned by $($manifest.owner): $GenerationPath"
    }
    if (-not [bool]$manifest.nativeBridge) {
        throw "Managed standalone generation does not declare native bridge ownership: $GenerationPath"
    }
    return $manifest
}

function Assert-StandaloneGeneration(
    [string]$GenerationPath, $Manifest, [string]$BridgeRoot, [switch]$AllowChanges) {
    if (-not (Test-StandaloneSamePath ([string]$Manifest.bridgeRoot) $BridgeRoot)) {
        throw "Managed standalone generation points to a different bridge root: $GenerationPath"
    }
    if ($null -eq $Manifest.files) {
        throw "Managed standalone generation has no owned file table: $GenerationPath"
    }
    $generation = Normalize-StandalonePath $GenerationPath
    $prefix = $generation + '\'
    $owned = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    [void]$owned.Add('.sc-install-manifest.json')
    foreach ($property in $Manifest.files.PSObject.Properties) {
        $relative = [string]$property.Name
        $expectedHash = [string]$property.Value
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [System.IO.Path]::IsPathRooted($relative) -or
            $relative.Equals('.sc-install-manifest.json',
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Managed standalone manifest has an unsafe file key: $relative"
        }
        if ($expectedHash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Managed standalone manifest has an invalid SHA-256 for $relative"
        }
        $file = [System.IO.Path]::GetFullPath(
            (Join-Path $generation $relative.Replace('/', '\')))
        if (-not $file.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Managed standalone manifest file escapes its generation: $relative"
        }
        if (-not $owned.Add($relative)) {
            throw "Managed standalone manifest contains a duplicate file key: $relative"
        }
        if (-not $AllowChanges -and
            (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
                (Get-StandaloneHash $file) -ne $expectedHash.ToLowerInvariant())) {
            throw "Managed standalone generation file changed or is missing: $GenerationPath :: $relative"
        }
    }
    if (-not $AllowChanges) {
        $actual = @(Get-ChildItem -LiteralPath $generation -Recurse -File | ForEach-Object {
            $_.FullName.Substring($prefix.Length).Replace('\', '/')
        })
        if ($actual.Count -ne $owned.Count -or
            @($actual | Where-Object { -not $owned.Contains($_) }).Count -ne 0) {
            throw "Managed standalone generation contains files outside its manifest: $GenerationPath"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = Normalize-StandalonePath $ProjectRoot
$ModsRoot = Normalize-StandalonePath $ModsRoot
$InstallDataRoot = Normalize-StandalonePath $InstallDataRoot
$BridgeRoot = Normalize-StandalonePath (Join-Path $InstallDataRoot 'bridge')
$BackupRoot = Normalize-StandalonePath (Join-Path $InstallDataRoot 'mod-backups')
$Target = Normalize-StandalonePath (Join-Path $ModsRoot 'SurvivorCompanion')
$modManifest = Join-Path $Target '.sc-install-manifest.json'
$bridgeManifest = Join-Path $BridgeRoot 'install-manifest.json'
$modsPrefix = $ModsRoot + '\'
$dataPrefix = $InstallDataRoot + '\'
if (-not $Target.StartsWith($modsPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not $BridgeRoot.StartsWith($dataPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not $BackupRoot.StartsWith($dataPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    (Test-StandaloneSamePath $BridgeRoot $BackupRoot)) {
    throw 'Standalone uninstall roots are not canonical, disjoint owned children.'
}

if (-not (Test-Path -LiteralPath $modManifest -PathType Leaf) -and
    -not (Test-Path -LiteralPath $bridgeManifest -PathType Leaf)) {
    throw 'No owned Living Fellows standalone installation was found.'
}
if ((Test-Path -LiteralPath $Target -PathType Container) -and
    -not (Test-Path -LiteralPath $modManifest -PathType Leaf)) {
    throw "Standalone target is present without an ownership manifest: $Target"
}

# Walk and validate the complete newest-to-oldest chain before moving a single
# directory. A corrupt deep generation therefore cannot strand the user.
$chain = New-Object System.Collections.Generic.List[object]
$seen = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
$generationPath = if (Test-Path -LiteralPath $modManifest -PathType Leaf) { $Target } else { '' }
while (-not [string]::IsNullOrWhiteSpace($generationPath)) {
    $generationPath = Normalize-StandalonePath $generationPath
    if (-not $seen.Add($generationPath)) {
        throw "Managed standalone backup chain contains a cycle: $generationPath"
    }
    if ($chain.Count -ge 256) {
        throw 'Managed standalone backup chain exceeds 256 versions.'
    }
    if (-not (Test-Path -LiteralPath $generationPath -PathType Container)) {
        throw "Managed standalone generation is missing: $generationPath"
    }
    $generationManifestPath = Join-Path $generationPath '.sc-install-manifest.json'
    $manifest = Read-OwnedStandaloneManifest $generationPath
    Assert-StandaloneGeneration $generationPath $manifest $BridgeRoot -AllowChanges:$Force
    $chain.Add([ordered]@{
        path = $generationPath
        manifest = $manifest
        manifestHash = Get-StandaloneHash $generationManifestPath
    })
    $next = [string]$manifest.backupPath
    if ([string]::IsNullOrWhiteSpace($next)) { break }
    if (-not (Test-StandaloneSamePath ([string]$manifest.backupRoot) $BackupRoot)) {
        throw "Managed standalone generation has an unexpected backup root: $generationPath"
    }
    $next = Normalize-StandalonePath $next
    $nextLeaf = Split-Path -Leaf $next
    if (-not (Test-StandalonePathWithin $next $BackupRoot) -or
        -not (Test-StandaloneSamePath (Split-Path -Parent $next) $BackupRoot) -or
        -not $nextLeaf.StartsWith('SurvivorCompanion-managed-backup-',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed standalone generation has an unsafe backup path: $next"
    }
    $generationPath = $next
}

$nativeState = $null
$nativeUninstaller = Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1'
if ($chain.Count -gt 0 -and -not (Test-Path -LiteralPath $bridgeManifest -PathType Leaf)) {
    throw 'The standalone mod chain exists but its native rollback manifest is missing; no files were changed.'
}
if (Test-Path -LiteralPath $bridgeManifest -PathType Leaf) {
    & $nativeUninstaller -BridgeRoot $BridgeRoot -PreflightOnly | Out-Null
    $nativeState = Get-Content -LiteralPath $bridgeManifest -Raw -Encoding utf8 |
        ConvertFrom-Json
}

$transactionRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('LivingFellowsStandaloneUninstall-' + [guid]::NewGuid().ToString('N'))
$tempPrefix = Normalize-StandalonePath ([System.IO.Path]::GetTempPath())
$transactionPath = Normalize-StandalonePath $transactionRoot
if (-not $transactionPath.StartsWith($tempPrefix + '\',
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe standalone transaction path: $transactionPath"
}
$snapshotRoot = Join-Path $transactionPath 'snapshot'
$snapshotReady = $false
$mutationStarted = $false
$safeToCleanSnapshot = $false
$committed = $false
$removedVersions = 0
try {
    New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
    $targetSnapshot = New-StandaloneDirectorySnapshot 'target' $Target $snapshotRoot
    $backupSnapshot = New-StandaloneDirectorySnapshot 'mod-backups' $BackupRoot $snapshotRoot
    $bridgeSnapshot = New-StandaloneDirectorySnapshot 'bridge' $BridgeRoot $snapshotRoot
    $configPath = Normalize-StandalonePath ([string]$nativeState.gameConfig)
    if ((Test-StandalonePathWithin $configPath $Target) -or
        (Test-StandalonePathWithin $configPath $BackupRoot) -or
        (Test-StandalonePathWithin $configPath $BridgeRoot)) {
        throw "Native launcher configuration overlaps an owned directory: $configPath"
    }
    $configSnapshot = Join-Path $snapshotRoot 'ProjectZomboid64.json'
    Copy-Item -LiteralPath $configPath -Destination $configSnapshot
    $configSnapshotHash = Get-StandaloneHash $configSnapshot
    if ([string]::IsNullOrWhiteSpace($configSnapshotHash) -or
        (Get-StandaloneHash $configPath) -ne $configSnapshotHash) {
        throw 'Standalone launcher snapshot verification failed.'
    }
    $snapshotReady = $true
    Invoke-StandaloneFault 'standalone-snapshot'
    $mutationStarted = $true

    for ($index = 0; $index -lt $chain.Count; $index++) {
        & (Join-Path $ProjectRoot 'scripts\Uninstall-Local.ps1') `
            -ModsRoot $ModsRoot -BridgeRoot $BridgeRoot -KeepNativeBridge -Force:$Force |
            Out-Null
        $removedVersions++
        if ($index + 1 -lt $chain.Count) {
            $currentManifest = Join-Path $Target '.sc-install-manifest.json'
            if ((Get-StandaloneHash $currentManifest) -ne
                [string]$chain[$index + 1].manifestHash) {
                throw "Standalone generation transition verification failed after index $index."
            }
        } elseif (Test-Path -LiteralPath $Target) {
            throw 'Final standalone generation remained after its owned removal.'
        }
        Invoke-StandaloneFault 'standalone-generation-remove'
    }

    if (Test-Path -LiteralPath $bridgeManifest -PathType Leaf) {
        & $nativeUninstaller -BridgeRoot $BridgeRoot | Out-Null
    }
    Invoke-StandaloneFault 'standalone-native-rollback'

    if (Test-Path -LiteralPath $Target) {
        throw "Standalone uninstall stopped at a live target: $Target"
    }
    foreach ($generation in $chain) {
        $path = Normalize-StandalonePath ([string]$generation.path)
        if (-not (Test-StandaloneSamePath $path $Target) -and
            (Test-Path -LiteralPath $path)) {
            throw "Standalone backup generation remained after uninstall: $path"
        }
    }
    if (Test-Path -LiteralPath $bridgeManifest -PathType Leaf) {
        throw 'Native bridge manifest remains after standalone uninstall.'
    }
    if ($null -ne $nativeState) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            throw "Launcher configuration is missing after uninstall: $configPath"
        }
        $originalHash = [string]$nativeState.originalConfigSha256
        if ([string]::IsNullOrWhiteSpace($originalHash) -or
            (Get-StandaloneHash $configPath) -ne $originalHash.ToLowerInvariant()) {
            throw 'Standalone uninstall did not restore the exact original launcher hash.'
        }
    }
    Invoke-StandaloneFault 'standalone-postcondition'
    $committed = $true
    $safeToCleanSnapshot = $true
}
catch {
    $trigger = $_
    $rollbackFailures = @()
    if ($mutationStarted -and $snapshotReady) {
        try { Restore-StandaloneDirectorySnapshot $targetSnapshot }
        catch { $rollbackFailures += "mod target restore: $($_.Exception.Message)" }
        try { Restore-StandaloneDirectorySnapshot $backupSnapshot }
        catch { $rollbackFailures += "backup chain restore: $($_.Exception.Message)" }
        try { Restore-StandaloneDirectorySnapshot $bridgeSnapshot }
        catch { $rollbackFailures += "bridge restore: $($_.Exception.Message)" }
        try { Copy-Item -LiteralPath $configSnapshot -Destination $configPath -Force }
        catch { $rollbackFailures += "launcher restore: $($_.Exception.Message)" }
        if ((Get-StandaloneHash $configPath) -ne $configSnapshotHash) {
            $rollbackFailures += 'launcher rollback hash mismatch'
        }
        try {
            Get-ChildItem -LiteralPath $ModsRoot -Force -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '.SurvivorCompanion.uninstall.*' } |
                ForEach-Object {
                    if (-not $_.FullName.StartsWith($modsPrefix,
                            [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Unsafe uninstall quarantine path: $($_.FullName)"
                    }
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force
                }
        } catch { $rollbackFailures += "quarantine cleanup: $($_.Exception.Message)" }
    }
    if ($rollbackFailures.Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            $trigger.Exception.Message + ' Rollback failures: ' +
                ($rollbackFailures -join '; ') +
                ". Verified recovery snapshot retained at $transactionPath",
            $trigger.Exception)
    }
    $safeToCleanSnapshot = $true
    throw $trigger
}
finally {
    if ($safeToCleanSnapshot -and (Test-Path -LiteralPath $transactionPath)) {
        try { Remove-Item -LiteralPath $transactionPath -Recurse -Force }
        catch { Write-Warning "Could not remove verified standalone transaction snapshot: $($_.Exception.Message)" }
    }
}

if (-not $committed) { throw 'Standalone uninstall transaction did not commit.' }
Write-Output ''
Write-Output 'UNINSTALL COMPLETE'
Write-Output "Removed $removedVersions managed Living Fellows version(s)."
Write-Output 'The original Project Zomboid launcher configuration was hash-verified.'
