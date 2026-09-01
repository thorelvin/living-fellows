# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$ModsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods'),
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$BackupRoot,
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge'),
    [string]$ConfigBackupRoot,
    [string]$PreparedPayloadRoot = '',
    [string]$PrebuiltBridgeJar = '',
    [ValidateSet('', 'payload-build', 'payload-validation', 'native-config-stage',
        'native-config-replace', 'native-jar-replace', 'native-manifest-write',
        'old-mod-backup', 'new-mod-move', 'local-manifest-write',
        'target-file-corrupt', 'target-postcondition')]
    [string]$FailAfter = '',
    [switch]$NativeBridge,
    [switch]$Standalone
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$VersionFile = Join-Path $ProjectRoot 'VERSION.txt'
if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    throw "Canonical version file is missing: $VersionFile"
}
$ReleaseVersion = (Get-Content -LiteralPath $VersionFile -Raw -Encoding utf8).Trim()
if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Canonical version must use MAJOR.MINOR.PATCH: $ReleaseVersion"
}
# Stable ownership id lets this installer transactionally replace its managed 0.9.x builds.
$Owner = 'LivingFellows.Companion.cleanroom.0.9.0'
if (-not $NativeBridge -and -not $Standalone) {
    throw 'Choose -NativeBridge for a private debug install or -Standalone for the public manual install.'
}
if ($NativeBridge -and $Standalone) {
    throw 'Choose either -NativeBridge or -Standalone, not both.'
}
# A running game blocks a real installation. Isolated installer tests use a
# synthetic game root with no executable and must not be coupled to an
# unrelated live process outside that sandbox.
$gameExecutable = Join-Path $GameRoot 'ProjectZomboid64.exe'
if ((Test-Path -LiteralPath $gameExecutable -PathType Leaf) -and
    (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue)) {
    throw 'Close Project Zomboid before installing.'
}
$legacyClass = Join-Path $GameRoot 'zombie\characters\IsoSurvivor.class'
if (Test-Path -LiteralPath $legacyClass -PathType Leaf) {
    throw "Legacy loose actor bridge detected at $legacyClass. This installer will not use, overwrite, move, or remove it. Close the game and resolve it manually before continuing."
}

$nativeInstaller = Join-Path $PSScriptRoot 'Install-NativeBridge.ps1'
$nativeArguments = @{
    ProjectRoot = $ProjectRoot
    GameRoot = $GameRoot
    BridgeRoot = $BridgeRoot
}
if (-not [string]::IsNullOrWhiteSpace($ConfigBackupRoot)) {
    $nativeArguments.ConfigBackupRoot = $ConfigBackupRoot
}
if (-not [string]::IsNullOrWhiteSpace($PrebuiltBridgeJar)) {
    $nativeArguments.PrebuiltBridgeJar = $PrebuiltBridgeJar
}
if ($FailAfter -like 'native-*') { $nativeArguments.FailAfter = $FailAfter }

function Invoke-InstallFault([string]$Boundary) {
    if ($FailAfter -eq $Boundary) { throw "Injected local installer failure after $Boundary" }
}

function Get-InstallHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-InstallSamePath([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\')).Equals(
        [System.IO.Path]::GetFullPath($Right).TrimEnd('\'),
        [System.StringComparison]::OrdinalIgnoreCase)
}

$ModsRoot = [System.IO.Path]::GetFullPath($ModsRoot)
New-Item -ItemType Directory -Path $ModsRoot -Force | Out-Null
$Target = Join-Path $ModsRoot 'SurvivorCompanion'
$rootPrefix = $ModsRoot.TrimEnd('\') + '\'
if (-not ([System.IO.Path]::GetFullPath($Target)).StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Invalid install target: $Target"
}
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $BackupRoot = Join-Path ([System.IO.Path]::GetFullPath($ProjectRoot)) 'build\local-install-backups'
}
$BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
$backupPrefix = $BackupRoot.TrimEnd('\') + '\'
$normalizedBackupRoot = $BackupRoot.TrimEnd('\')
$normalizedModsRoot = $ModsRoot.TrimEnd('\')
$backupSameAsMods = $normalizedBackupRoot.Equals($normalizedModsRoot,
    [System.StringComparison]::OrdinalIgnoreCase)
$backupInsideMods = $BackupRoot.StartsWith($rootPrefix,
    [System.StringComparison]::OrdinalIgnoreCase)
if ($backupSameAsMods -or $backupInsideMods) {
    throw "BackupRoot must be outside the Project Zomboid mods directory: $BackupRoot"
}

$backup = $null
$targetManifest = Join-Path $Target '.sc-install-manifest.json'
if (Test-Path -LiteralPath $Target) {
    if (-not (Test-Path -LiteralPath $targetManifest -PathType Leaf)) {
        throw "Refusing to overwrite unmanaged mod directory: $Target"
    }
    $existing = Get-Content -LiteralPath $targetManifest -Raw -Encoding utf8 | ConvertFrom-Json
    if ($existing.owner -ne $Owner) { throw "Refusing to overwrite a target owned by $($existing.owner)" }
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $backupSuffix = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    $backupName = 'SurvivorCompanion-managed-backup-' `
        + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $backupSuffix
    $backup = Join-Path $BackupRoot $backupName
    $resolvedBackup = [System.IO.Path]::GetFullPath($backup)
    if (-not $resolvedBackup.StartsWith($backupPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid managed backup target: $resolvedBackup"
    }
    if (Test-Path -LiteralPath $backup) { throw "Backup target already exists: $backup" }
}

$stageRoot = Join-Path $ModsRoot ('.SurvivorCompanion.stage.' + [guid]::NewGuid().ToString('N'))
$installed = $false
$targetExisted = Test-Path -LiteralPath $Target -PathType Container
$nativeSnapshotReady = $false
$nativeConfigPath = Join-Path $GameRoot 'ProjectZomboid64.json'
$nativeManifestPath = Join-Path ([System.IO.Path]::GetFullPath($BridgeRoot)) 'install-manifest.json'
$nativeJarPath = Join-Path ([System.IO.Path]::GetFullPath($BridgeRoot)) 'SurvivorCompanionBridge.jar'
$nativeBridgeRootExisted = Test-Path -LiteralPath $BridgeRoot -PathType Container
$effectiveConfigBackupRoot = if ([string]::IsNullOrWhiteSpace($ConfigBackupRoot)) {
    Join-Path $ProjectRoot 'build\game-config-backups'
} else { [System.IO.Path]::GetFullPath($ConfigBackupRoot) }
$nativeBackupNamesBefore = @()
try {
    $stagedMod = Join-Path $stageRoot 'SurvivorCompanion'
    $compiledBridgeJar = ''
    if ($NativeBridge -and
        [string]::IsNullOrWhiteSpace($PreparedPayloadRoot) -and
        [string]::IsNullOrWhiteSpace($PrebuiltBridgeJar)) {
        # A direct development install must compile the current Java sources.
        # Do not trust the possibly older JAR checked into the canonical payload
        # and do not mutate that payload as a side effect of installation.
        & (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') `
            -ProjectRoot $ProjectRoot | Out-Null
        $compiledBridgeJar = Join-Path $ProjectRoot `
            'build\native-bridge\SurvivorCompanionBridge.jar'
        if (-not (Test-Path -LiteralPath $compiledBridgeJar -PathType Leaf)) {
            throw 'Direct native bridge compilation did not produce its expected JAR.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($PreparedPayloadRoot)) {
        $payloadBuilder = if ($Standalone) {
            Join-Path ([System.IO.Path]::GetFullPath($ProjectRoot)) 'scripts\New-StandalonePayload.ps1'
        } else {
            Join-Path ([System.IO.Path]::GetFullPath($ProjectRoot)) 'scripts\New-PrivatePlaytestPayload.ps1'
        }
        & $payloadBuilder -ProjectRoot $ProjectRoot -OutputRoot $stageRoot -AllowExternalOutput | Out-Null
    } else {
        $prepared = [System.IO.Path]::GetFullPath($PreparedPayloadRoot)
        if (-not (Test-Path -LiteralPath $prepared -PathType Container)) {
            throw "Prepared private payload was not found: $prepared"
        }
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        Copy-Item -LiteralPath $prepared -Destination $stagedMod -Recurse
        foreach ($metadataPath in @(
            (Join-Path $stagedMod 'mod.info'),
            (Join-Path $stagedMod '42\mod.info'))) {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding utf8
            if (($metadata -match '(?m)^require=\\ZombieBuddy$') -or
                ($metadata -match '(?m)^ZBVersionMin=')) {
                throw "Prepared private payload retained a Workshop-only dependency: $metadataPath"
            }
        }
        $markerName = if ($Standalone) {
            'STANDALONE-NATIVE-BRIDGE.txt'
        } else {
            'PRIVATE-NATIVE-BRIDGE.txt'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $stagedMod $markerName) -PathType Leaf)) {
            throw "Prepared payload is missing its owned marker: $markerName"
        }
    }
    Invoke-InstallFault 'payload-build'
    if (-not (Test-Path -LiteralPath $stagedMod -PathType Container)) { throw 'Private payload staging failed.' }
    $expectedNativeJar = Join-Path $stagedMod '42\media\java\SurvivorCompanionBridge.jar'
    $selectedBridgeJar = if (-not [string]::IsNullOrWhiteSpace($compiledBridgeJar)) {
        [System.IO.Path]::GetFullPath($compiledBridgeJar)
    } elseif (-not [string]::IsNullOrWhiteSpace($PrebuiltBridgeJar)) {
        [System.IO.Path]::GetFullPath($PrebuiltBridgeJar)
    } else { $expectedNativeJar }
    if (-not (Test-Path -LiteralPath $selectedBridgeJar -PathType Leaf)) {
        throw "Selected native bridge JAR was not found: $selectedBridgeJar"
    }
    if (-not (Test-InstallSamePath $selectedBridgeJar $expectedNativeJar)) {
        Copy-Item -LiteralPath $selectedBridgeJar -Destination $expectedNativeJar -Force
    }
    $selectedBridgeHash = Get-InstallHash $expectedNativeJar
    if (Get-ChildItem -LiteralPath $stagedMod -Recurse -File -Filter '*.class') {
        throw 'Loose Java classes are forbidden in local installs.'
    }
    $nativeJars = @(Get-ChildItem -LiteralPath $stagedMod -Recurse -File -Filter '*.jar')
    if ($nativeJars.Count -ne 1 -or $nativeJars[0].FullName -ne $expectedNativeJar) {
        throw 'The staged install does not contain exactly one owned native bridge JAR.'
    }
    Invoke-InstallFault 'payload-validation'

    $stagePrefix = [System.IO.Path]::GetFullPath($stagedMod).TrimEnd('\') + '\'
    $hashes = [ordered]@{}
    Get-ChildItem -LiteralPath $stagedMod -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($stagePrefix.Length).Replace('\', '/')
        $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $installedVersion = if ($Standalone) {
        "$ReleaseVersion-standalone-native"
    } else {
        "$ReleaseVersion-private-native"
    }
    $manifest = [ordered]@{
        owner = $Owner
        version = $installedVersion
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        nativeBridge = $true
        bridgeRoot = [System.IO.Path]::GetFullPath($BridgeRoot)
        bridgeSha256 = $selectedBridgeHash
        backupPath = $backup
        backupRoot = $BackupRoot
        files = $hashes
    }
    $stagedLocalManifest = Join-Path $stagedMod '.sc-install-manifest.json'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stagedLocalManifest -Encoding utf8
    $stagedLocalManifestHash = Get-InstallHash $stagedLocalManifest
    Invoke-InstallFault 'local-manifest-write'

    # Snapshot every native live artifact before the sub-transaction commits.
    # This outer snapshot also rolls the bridge back if a later mod-directory
    # commit fails.
    if (-not (Test-Path -LiteralPath $nativeConfigPath -PathType Leaf)) {
        throw "ProjectZomboid64.json was not found at $nativeConfigPath"
    }
    $outerPrior = Join-Path $stageRoot '.outer-native-prior'
    New-Item -ItemType Directory -Path $outerPrior -Force | Out-Null
    $priorNativeConfig = Join-Path $outerPrior 'ProjectZomboid64.json'
    $priorNativeJar = Join-Path $outerPrior 'SurvivorCompanionBridge.jar'
    $priorNativeManifest = Join-Path $outerPrior 'install-manifest.json'
    Copy-Item -LiteralPath $nativeConfigPath -Destination $priorNativeConfig
    $priorNativeJarExisted = Test-Path -LiteralPath $nativeJarPath -PathType Leaf
    $priorNativeManifestExisted = Test-Path -LiteralPath $nativeManifestPath -PathType Leaf
    if ($priorNativeJarExisted) { Copy-Item -LiteralPath $nativeJarPath -Destination $priorNativeJar }
    if ($priorNativeManifestExisted) {
        Copy-Item -LiteralPath $nativeManifestPath -Destination $priorNativeManifest
    }
    $priorNativeConfigHash = Get-InstallHash $priorNativeConfig
    $priorNativeJarHash = Get-InstallHash $priorNativeJar
    $priorNativeManifestHash = Get-InstallHash $priorNativeManifest
    if (Test-Path -LiteralPath $effectiveConfigBackupRoot -PathType Container) {
        $nativeBackupNamesBefore = @(Get-ChildItem -LiteralPath $effectiveConfigBackupRoot -File |
            ForEach-Object Name)
    }
    $nativeSnapshotReady = $true
    $nativeArguments.PrebuiltBridgeJar = $expectedNativeJar
    & $nativeInstaller @nativeArguments | Out-Null

    if ($backup) {
        Move-Item -LiteralPath $Target -Destination $backup
        Invoke-InstallFault 'old-mod-backup'
    }
    Move-Item -LiteralPath $stagedMod -Destination $Target
    Invoke-InstallFault 'new-mod-move'

    if ($FailAfter -eq 'target-file-corrupt') {
        $corruptTarget = Join-Path $Target '42\mod.info'
        [System.IO.File]::AppendAllText($corruptTarget, "`n# injected post-move corruption")
    }

    # Verify the exact committed generation rather than assuming Move-Item
    # preserved staging. This catches disk/filter-driver corruption, a stale
    # prepared payload and manifest/file divergence before the old generation
    # is released from the rollback transaction.
    $committedManifestPath = Join-Path $Target '.sc-install-manifest.json'
    if ((Get-InstallHash $committedManifestPath) -ne $stagedLocalManifestHash) {
        throw 'Installed mod manifest hash differs from the staged manifest.'
    }
    $committedManifest = Get-Content -LiteralPath $committedManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    if ([string]$committedManifest.owner -ne $Owner -or
        [string]$committedManifest.version -ne $installedVersion -or
        -not (Test-InstallSamePath ([string]$committedManifest.bridgeRoot) $BridgeRoot) -or
        [string]$committedManifest.bridgeSha256 -ne $selectedBridgeHash) {
        throw 'Installed mod manifest ownership/version/native bridge postcondition failed.'
    }
    $committedPrefix = [System.IO.Path]::GetFullPath($Target).TrimEnd('\') + '\'
    $expectedNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    [void]$expectedNames.Add('.sc-install-manifest.json')
    foreach ($property in $committedManifest.files.PSObject.Properties) {
        $relative = [string]$property.Name
        if ([System.IO.Path]::IsPathRooted($relative)) {
            throw "Installed manifest contains an absolute file path: $relative"
        }
        $candidate = [System.IO.Path]::GetFullPath(
            (Join-Path $Target $relative.Replace('/', '\')))
        if (-not $candidate.StartsWith($committedPrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Installed manifest file escapes the mod root: $relative"
        }
        if (-not $expectedNames.Add($relative)) {
            throw "Installed manifest contains a duplicate file path: $relative"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
            (Get-InstallHash $candidate) -ne [string]$property.Value) {
            throw "Installed file hash postcondition failed: $relative"
        }
    }
    $actualNames = @(Get-ChildItem -LiteralPath $Target -Recurse -File | ForEach-Object {
        $_.FullName.Substring($committedPrefix.Length).Replace('\', '/')
    })
    if ($actualNames.Count -ne $expectedNames.Count -or
        @($actualNames | Where-Object { -not $expectedNames.Contains($_) }).Count -ne 0) {
        throw 'Installed file set differs from its ownership manifest.'
    }
    $committedBridgeJar = Join-Path $Target '42\media\java\SurvivorCompanionBridge.jar'
    if ((Get-InstallHash $committedBridgeJar) -ne $selectedBridgeHash -or
        (Get-InstallHash $nativeJarPath) -ne $selectedBridgeHash) {
        throw 'Installed payload and launcher bridge JAR hashes are not identical.'
    }
    $committedNativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    if ([string]$committedNativeManifest.owner -ne 'SurvivorCompanion.NativeBridge' -or
        -not (Test-InstallSamePath ([string]$committedNativeManifest.bridgeRoot) $BridgeRoot) -or
        -not (Test-InstallSamePath ([string]$committedNativeManifest.bridgeJar) $nativeJarPath) -or
        [string]$committedNativeManifest.bridgeSha256 -ne $selectedBridgeHash -or
        [string]$committedNativeManifest.installedConfigSha256 -ne
            (Get-InstallHash $nativeConfigPath)) {
        throw 'Native bridge manifest/hash postcondition failed after local install.'
    }
    Invoke-InstallFault 'target-postcondition'
    $installed = $true
}
catch {
    $trigger = $_
    $rollbackFailures = @()

    try {
        if ($targetExisted) {
            if ($backup -and (Test-Path -LiteralPath $backup -PathType Container)) {
                if (Test-Path -LiteralPath $Target) {
                    Remove-Item -LiteralPath $Target -Recurse -Force
                }
                Move-Item -LiteralPath $backup -Destination $Target
            } elseif (-not (Test-Path -LiteralPath $Target -PathType Container)) {
                throw 'original managed mod and its transaction backup are both missing'
            }
        } elseif (Test-Path -LiteralPath $Target) {
            Remove-Item -LiteralPath $Target -Recurse -Force
        }
    } catch { $rollbackFailures += "mod restore: $($_.Exception.Message)" }

    if ($nativeSnapshotReady) {
        try { Copy-Item -LiteralPath $priorNativeConfig -Destination $nativeConfigPath -Force }
        catch { $rollbackFailures += "launcher restore: $($_.Exception.Message)" }
        try {
            if ($priorNativeJarExisted) {
                Copy-Item -LiteralPath $priorNativeJar -Destination $nativeJarPath -Force
            } elseif (Test-Path -LiteralPath $nativeJarPath) {
                Remove-Item -LiteralPath $nativeJarPath -Force
            }
        } catch { $rollbackFailures += "bridge JAR restore: $($_.Exception.Message)" }
        try {
            if ($priorNativeManifestExisted) {
                Copy-Item -LiteralPath $priorNativeManifest -Destination $nativeManifestPath -Force
            } elseif (Test-Path -LiteralPath $nativeManifestPath) {
                Remove-Item -LiteralPath $nativeManifestPath -Force
            }
        } catch { $rollbackFailures += "bridge manifest restore: $($_.Exception.Message)" }
        try {
            if (Test-Path -LiteralPath $effectiveConfigBackupRoot -PathType Container) {
                Get-ChildItem -LiteralPath $effectiveConfigBackupRoot -File | Where-Object {
                    $_.Name -notin $nativeBackupNamesBefore
                } | Remove-Item -Force
            }
        } catch { $rollbackFailures += "native backup restore: $($_.Exception.Message)" }

        if ((Get-InstallHash $nativeConfigPath) -ne $priorNativeConfigHash) {
            $rollbackFailures += 'launcher rollback hash mismatch'
        }
        if ($priorNativeJarExisted -ne (Test-Path -LiteralPath $nativeJarPath -PathType Leaf) -or
            ($priorNativeJarExisted -and (Get-InstallHash $nativeJarPath) -ne $priorNativeJarHash)) {
            $rollbackFailures += 'bridge JAR rollback presence/hash mismatch'
        }
        if ($priorNativeManifestExisted -ne
            (Test-Path -LiteralPath $nativeManifestPath -PathType Leaf) -or
            ($priorNativeManifestExisted -and
                (Get-InstallHash $nativeManifestPath) -ne $priorNativeManifestHash)) {
            $rollbackFailures += 'bridge manifest rollback presence/hash mismatch'
        }
        if (-not $nativeBridgeRootExisted -and (Test-Path -LiteralPath $BridgeRoot -PathType Container)) {
            try {
                if (@(Get-ChildItem -LiteralPath $BridgeRoot -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $BridgeRoot -Force
                }
            } catch { $rollbackFailures += "empty bridge-root cleanup: $($_.Exception.Message)" }
        }
    }
    if ($rollbackFailures.Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            $trigger.Exception.Message + ' Rollback failures: ' + ($rollbackFailures -join '; '),
            $trigger.Exception)
    }
    throw $trigger
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        $resolvedStage = [System.IO.Path]::GetFullPath($stageRoot)
        if (-not $resolvedStage.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Refusing to clean unexpected stage: $resolvedStage"
        } else {
            try { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
            catch { Write-Warning "Could not remove local installer staging directory: $($_.Exception.Message)" }
        }
    }
}

if ($Standalone) {
    Write-Output "Installed Living Fellows standalone build at $Target"
    Write-Output 'Public gameplay settings are active; the private Debug tab remains disabled.'
} else {
    Write-Output "Installed PRIVATE NATIVE BRIDGE build at $Target"
    Write-Output 'The debug-only in-game tab and manual spawn controls are enabled in the copied configuration.'
}
