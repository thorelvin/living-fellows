# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge'),
    [string]$ConfigBackupRoot,
    [string]$PrebuiltBridgeJar = '',
    [ValidateSet('', 'native-config-stage', 'native-config-replace',
        'native-jar-replace', 'native-manifest-write')]
    [string]$FailAfter = ''
)

$ErrorActionPreference = 'Stop'
$Owner = 'SurvivorCompanion.NativeBridge'
$WrapperMain = 'survivorcompanion/bridge/SCLauncher'
$OriginalMain = 'zombie/gameStates/MainScreenState'
$ExpectedProtocol = '42.21-isocompanion-26'
$ExpectedSupportedGame = '42.21'
$ExpectedCompiledGame = '42.21.0'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Normalize-Path([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-SamePath([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    return (Normalize-Path $Left).Equals((Normalize-Path $Right),
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-HashOrEmpty([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-Fault([string]$Boundary) {
    if ($FailAfter -eq $Boundary) {
        throw "Injected native installer failure after $Boundary"
    }
}

function Get-BridgeMetadata([string]$JarPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($required in @(
            'survivorcompanion/bridge/SCNativeCompanion.class',
            'survivorcompanion/bridge/SCBridge.class',
            'survivorcompanion/bridge/SCBootstrap.class',
            'survivorcompanion/bridge/SCLauncher.class',
            'survivorcompanion/bridge/Main.class'
        )) {
            if ($entryNames -notcontains $required) {
                throw "Native bridge JAR is missing $required"
            }
        }
        if ($entryNames | Where-Object { $_ -match '^zombie/' }) {
            throw 'Native bridge JAR contains forbidden Project Zomboid classes.'
        }
        $manifestEntry = $archive.GetEntry('META-INF/MANIFEST.MF')
        if ($null -eq $manifestEntry) { throw 'Native bridge JAR has no manifest.' }
        $stream = $manifestEntry.Open()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        try { $manifestText = $reader.ReadToEnd() }
        finally { $reader.Dispose(); $stream.Dispose() }
        $fields = @{}
        foreach ($line in ($manifestText -split "`r?`n")) {
            if ($line -match '^([^:]+):\s*(.*)$') { $fields[$matches[1]] = $matches[2].Trim() }
        }
        return [ordered]@{
            protocol = [string]$fields['SC-Bridge-Protocol']
            supportedGame = [string]$fields['SC-Supported-Game-Version']
            compiledGame = [string]$fields['SC-Compiled-Game-Version']
        }
    }
    finally { $archive.Dispose() }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = Normalize-Path $ProjectRoot
$GameRoot = Normalize-Path $GameRoot
$BridgeRoot = Normalize-Path $BridgeRoot
$gameExecutable = Join-Path $GameRoot 'ProjectZomboid64.exe'
if ((Test-Path -LiteralPath $gameExecutable -PathType Leaf) -and
    (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue)) {
    throw 'Close Project Zomboid before installing the native companion bridge.'
}
$configPath = Join-Path $GameRoot 'ProjectZomboid64.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "ProjectZomboid64.json was not found at $configPath"
}
if ([string]::IsNullOrWhiteSpace($ConfigBackupRoot)) {
    $ConfigBackupRoot = Join-Path $ProjectRoot 'build\game-config-backups'
}
$ConfigBackupRoot = Normalize-Path $ConfigBackupRoot

$manifestPath = Join-Path $BridgeRoot 'install-manifest.json'
$targetJar = Join-Path $BridgeRoot 'SurvivorCompanionBridge.jar'
$targetJarArgument = $targetJar.Replace('\', '/')
$launcherJarArgument = 'LivingFellowsBridge.jar'
$launcherJar = Join-Path $GameRoot $launcherJarArgument
function Test-BridgeClasspathEntry([string]$Entry) {
    $normalized = $Entry.Replace('\', '/')
    return $normalized.Equals($targetJarArgument,
        [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.Equals($launcherJarArgument,
            [System.StringComparison]::OrdinalIgnoreCase)
}
$configText = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
$configHashAtStart = Get-HashOrEmpty $configPath
$config = $configText | ConvertFrom-Json
if ($null -eq $config.classpath) { throw 'ProjectZomboid64.json has no classpath array.' }

$existingManifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $existingManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($existingManifest.owner -ne $Owner) {
        throw "Refusing to update a native bridge owned by $($existingManifest.owner)"
    }
}

if ($config.mainClass -eq $WrapperMain -and $null -eq $existingManifest) {
    throw "SCLauncher is active but its owned manifest is missing at $manifestPath. Restore ProjectZomboid64.json from a known-good backup before reinstalling; the wrapper must never be inferred as the original launcher."
}
if ($config.mainClass -ne $OriginalMain -and $config.mainClass -ne $WrapperMain) {
    throw "Refusing to replace an unknown Project Zomboid mainClass: $($config.mainClass)"
}
$recoveredGameReinstall = $false
$preserveLauncherEdits = $false
if ($existingManifest) {
    $ownedBridgeRoot = if ([string]::IsNullOrWhiteSpace([string]$existingManifest.bridgeRoot)) {
        Split-Path -Parent ([string]$existingManifest.bridgeJar)
    } else { [string]$existingManifest.bridgeRoot }
    $manifestMismatch = -not (Test-SamePath ([string]$existingManifest.gameRoot) $GameRoot) `
        -or -not (Test-SamePath ([string]$existingManifest.gameConfig) $configPath) `
        -or -not (Test-SamePath $ownedBridgeRoot $BridgeRoot) `
        -or -not (Test-SamePath ([string]$existingManifest.bridgeJar) $targetJar) `
        -or [string]$existingManifest.wrapperMainClass -ne $WrapperMain
    if ($manifestMismatch) {
        throw 'Existing native bridge manifest does not own this normalized game/config/bridge path set.'
    }
    $classpathMatches = @($config.classpath | Where-Object {
        Test-BridgeClasspathEntry ([string]$_)
    })
    if ($config.mainClass -eq $WrapperMain) {
        $recordedInstalledConfigHash = [string]$existingManifest.installedConfigSha256
        if ([string]::IsNullOrWhiteSpace($recordedInstalledConfigHash)) {
            throw 'Owned native bridge manifest has no installedConfigSha256; refusing update before mutation.'
        }
        if ($classpathMatches.Count -ne 1) {
            throw 'SCLauncher classpath ownership is missing or duplicated; refusing update.'
        }
        $preserveLauncherEdits = [bool]$existingManifest.preserveLauncherEdits -or
            -not $recordedInstalledConfigHash.Equals($configHashAtStart,
                [System.StringComparison]::OrdinalIgnoreCase)
    } else {
        # Steam restores ProjectZomboid64.json on reinstall but leaves the
        # user's LocalAppData ownership manifest behind. A vanilla launcher
        # with no bridge classpath entry can be installed afresh, provided the
        # old bridge and backup still match the manifest we own.
        if ($config.mainClass -ne $OriginalMain -or $classpathMatches.Count -ne 0) {
            throw 'Owned native bridge manifest exists but SCLauncher is not active and the launcher is not clean; refusing recovery.'
        }
        if ([string]$existingManifest.originalMainClass -ne $OriginalMain -or
            [string]::IsNullOrWhiteSpace([string]$existingManifest.originalConfigSha256)) {
            throw 'Owned native bridge manifest has no verified original launcher; refusing reinstall recovery.'
        }
        $recoveredGameReinstall = $true
    }
    if (-not (Test-Path -LiteralPath $targetJar -PathType Leaf)) {
        throw "Owned native bridge JAR is missing: $targetJar"
    }
    $currentJarHash = Get-HashOrEmpty $targetJar
    if ([string]$existingManifest.bridgeSha256 -ne $currentJarHash) {
        throw 'Owned native bridge JAR hash no longer matches its manifest; refusing update.'
    }
    if ($existingManifest.launcherJar) {
        if (-not (Test-SamePath ([string]$existingManifest.launcherJar) $launcherJar) -or
            [string]::IsNullOrWhiteSpace([string]$existingManifest.launcherJarSha256)) {
            throw 'Existing launcher JAR ownership does not match this game root.'
        }
        if ((Test-Path -LiteralPath $launcherJar -PathType Leaf) -and
            (Get-HashOrEmpty $launcherJar) -ne [string]$existingManifest.launcherJarSha256) {
            throw 'Owned game-local launcher JAR changed; refusing update.'
        }
    } elseif (Test-Path -LiteralPath $launcherJar) {
        throw "Unmanaged game-local launcher JAR already exists: $launcherJar"
    }
    if ([string]$existingManifest.originalMainClass -eq $WrapperMain -or
        [string]::IsNullOrWhiteSpace([string]$existingManifest.originalMainClass)) {
        throw 'Owned manifest does not preserve the true original launcher main class.'
    }
    $originalBackup = [string]$existingManifest.originalConfigBackup
    if (-not (Test-Path -LiteralPath $originalBackup -PathType Leaf)) {
        throw "Original successful-install launcher backup is missing: $originalBackup"
    }
    if ($existingManifest.originalConfigSha256) {
        if ((Get-HashOrEmpty $originalBackup) -ne [string]$existingManifest.originalConfigSha256) {
            throw 'Original successful-install launcher backup hash changed; refusing update.'
        }
    }
    if ($recoveredGameReinstall) {
        $oldOriginal = Get-Content -LiteralPath $originalBackup -Raw -Encoding utf8 |
            ConvertFrom-Json
        if ([string]$oldOriginal.mainClass -ne $OriginalMain) {
            throw 'Original successful-install launcher backup is not vanilla; refusing reinstall recovery.'
        }
    }
}
elseif (Test-Path -LiteralPath $launcherJar) {
    throw "Unmanaged game-local launcher JAR already exists: $launcherJar"
}

$buildOutput = $null
if ([string]::IsNullOrWhiteSpace($PrebuiltBridgeJar)) {
    $builder = Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1'
    $buildOutput = & $builder -ProjectRoot $ProjectRoot -InstallIntoPayload
    $builtJar = Join-Path $ProjectRoot 'build\native-bridge\SurvivorCompanionBridge.jar'
    if (-not (Test-Path -LiteralPath $builtJar -PathType Leaf)) {
        throw 'Native bridge build did not produce the expected JAR.'
    }
} else {
    $builtJar = Normalize-Path $PrebuiltBridgeJar
    if (-not (Test-Path -LiteralPath $builtJar -PathType Leaf)) {
        throw "Prebuilt native bridge JAR was not found: $builtJar"
    }
    $buildOutput = "NATIVE_BRIDGE_PREBUILT_PASS jar=$builtJar sha256=$(Get-HashOrEmpty $builtJar)"
}
$metadata = Get-BridgeMetadata $builtJar
if ($metadata.protocol -ne $ExpectedProtocol -or
    $metadata.supportedGame -ne $ExpectedSupportedGame -or
    $metadata.compiledGame -ne $ExpectedCompiledGame) {
    throw "Native bridge metadata mismatch. Expected protocol=$ExpectedProtocol supportedGame=$ExpectedSupportedGame compiledGame=$ExpectedCompiledGame; received protocol=$($metadata.protocol) supportedGame=$($metadata.supportedGame) compiledGame=$($metadata.compiledGame)."
}
New-Item -ItemType Directory -Path $BridgeRoot, $ConfigBackupRoot -Force | Out-Null

$backupPath = if ($existingManifest -and -not $recoveredGameReinstall) {
    [string]$existingManifest.originalConfigBackup
} else {
    $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    Join-Path $ConfigBackupRoot ("ProjectZomboid64.before-SurvivorCompanion.$suffix.json")
}
$originalMainClass = if ($existingManifest -and -not $recoveredGameReinstall) {
    [string]$existingManifest.originalMainClass
} else { [string]$config.mainClass }
$originalClasspath = if ($existingManifest -and -not $recoveredGameReinstall) {
    @($existingManifest.originalClasspath)
} else { @($config.classpath) }
$originalConfigHash = if ($existingManifest -and -not $recoveredGameReinstall -and $existingManifest.originalConfigSha256) {
    [string]$existingManifest.originalConfigSha256
} elseif ($existingManifest -and -not $recoveredGameReinstall) {
    Get-HashOrEmpty $backupPath
} else {
    Get-HashOrEmpty $configPath
}

$reuseCurrentConfig = $existingManifest -and -not $recoveredGameReinstall -and
    $classpathMatches.Count -eq 1 -and
    ([string]$classpathMatches[0]).Replace('\', '/').Equals($launcherJarArgument,
        [System.StringComparison]::OrdinalIgnoreCase)
if (-not $reuseCurrentConfig) {
    $newClasspath = @($config.classpath | Where-Object {
        -not (Test-BridgeClasspathEntry ([string]$_))
    })
    $newClasspath += $launcherJarArgument
    $config.mainClass = $WrapperMain
    $config.classpath = @($newClasspath)
}

$transactionRoot = Join-Path $BridgeRoot ('.install-transaction.' + [guid]::NewGuid().ToString('N'))
$priorRoot = Join-Path $transactionRoot 'prior'
$stagedRoot = Join-Path $transactionRoot 'staged'
New-Item -ItemType Directory -Path $priorRoot, $stagedRoot -Force | Out-Null
$priorConfig = Join-Path $priorRoot 'ProjectZomboid64.json'
$priorJar = Join-Path $priorRoot 'SurvivorCompanionBridge.jar'
$priorLauncherJar = Join-Path $priorRoot $launcherJarArgument
$priorManifest = Join-Path $priorRoot 'install-manifest.json'
$stagedConfig = Join-Path $stagedRoot 'ProjectZomboid64.json'
$stagedJar = Join-Path $stagedRoot 'SurvivorCompanionBridge.jar'
$stagedLauncherJar = Join-Path $stagedRoot $launcherJarArgument
$stagedManifest = Join-Path $stagedRoot 'install-manifest.json'
Copy-Item -LiteralPath $configPath -Destination $priorConfig
$priorJarExisted = Test-Path -LiteralPath $targetJar -PathType Leaf
$priorLauncherJarExisted = Test-Path -LiteralPath $launcherJar -PathType Leaf
$priorManifestExisted = Test-Path -LiteralPath $manifestPath -PathType Leaf
$priorBackupExisted = Test-Path -LiteralPath $backupPath -PathType Leaf
if ($priorJarExisted) { Copy-Item -LiteralPath $targetJar -Destination $priorJar }
if ($priorLauncherJarExisted) {
    Copy-Item -LiteralPath $launcherJar -Destination $priorLauncherJar
}
if ($priorManifestExisted) { Copy-Item -LiteralPath $manifestPath -Destination $priorManifest }
$priorConfigHash = Get-HashOrEmpty $priorConfig
$priorJarHash = Get-HashOrEmpty $priorJar
$priorLauncherJarHash = Get-HashOrEmpty $priorLauncherJar
$priorManifestHash = Get-HashOrEmpty $priorManifest

if ($reuseCurrentConfig) {
    Copy-Item -LiteralPath $priorConfig -Destination $stagedConfig
} else {
    [System.IO.File]::WriteAllText($stagedConfig, ($config | ConvertTo-Json -Depth 100), $utf8NoBom)
}
Get-Content -LiteralPath $stagedConfig -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null
Copy-Item -LiteralPath $builtJar -Destination $stagedJar
Copy-Item -LiteralPath $builtJar -Destination $stagedLauncherJar
$stagedJarHash = Get-HashOrEmpty $stagedJar
$installedConfigHash = Get-HashOrEmpty $stagedConfig
$manifest = [ordered]@{
    schemaVersion = 3
    owner = $Owner
    installedAtUtc = if ($existingManifest -and -not $recoveredGameReinstall) { [string]$existingManifest.installedAtUtc } else { [DateTime]::UtcNow.ToString('o') }
    updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    projectRoot = $ProjectRoot
    gameRoot = $GameRoot
    gameConfig = $configPath
    installedConfigSha256 = $installedConfigHash
    preserveLauncherEdits = $preserveLauncherEdits
    bridgeRoot = $BridgeRoot
    bridgeJar = $targetJar
    bridgeSha256 = $stagedJarHash
    launcherJar = $launcherJar
    launcherJarSha256 = $stagedJarHash
    launcherClasspathEntry = $launcherJarArgument
    bridgeProtocol = $ExpectedProtocol
    supportedGameVersion = $ExpectedSupportedGame
    compiledGameVersion = $ExpectedCompiledGame
    wrapperMainClass = $WrapperMain
    originalMainClass = $originalMainClass
    originalClasspath = @($originalClasspath)
    originalConfigBackup = $backupPath
    originalConfigSha256 = $originalConfigHash
}
[System.IO.File]::WriteAllText($stagedManifest,
    ($manifest | ConvertTo-Json -Depth 12), $utf8NoBom)
Get-Content -LiteralPath $stagedManifest -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null

$committed = $false
try {
    Invoke-Fault 'native-config-stage'
    if ((Get-HashOrEmpty $configPath) -ne $configHashAtStart) {
        throw 'Launcher configuration changed during install; refusing to overwrite it.'
    }
    if (-not $priorBackupExisted) {
        Copy-Item -LiteralPath $priorConfig -Destination $backupPath
        if ((Get-HashOrEmpty $backupPath) -ne $originalConfigHash) {
            throw 'Original launcher backup verification failed.'
        }
    }
    if (-not $reuseCurrentConfig) {
        Copy-Item -LiteralPath $stagedConfig -Destination $configPath -Force
    }
    Invoke-Fault 'native-config-replace'
    Copy-Item -LiteralPath $stagedJar -Destination $targetJar -Force
    Copy-Item -LiteralPath $stagedLauncherJar -Destination $launcherJar -Force
    Invoke-Fault 'native-jar-replace'
    Copy-Item -LiteralPath $stagedManifest -Destination $manifestPath -Force
    Invoke-Fault 'native-manifest-write'

    if ((Get-HashOrEmpty $configPath) -ne $installedConfigHash -or
        (Get-HashOrEmpty $targetJar) -ne $stagedJarHash -or
        (Get-HashOrEmpty $launcherJar) -ne $stagedJarHash -or
        (Get-HashOrEmpty $manifestPath) -ne (Get-HashOrEmpty $stagedManifest)) {
        throw 'Native bridge install postcondition hash mismatch.'
    }
    $committed = $true
}
catch {
    $trigger = $_
    $rollbackFailures = @()
    try { Copy-Item -LiteralPath $priorConfig -Destination $configPath -Force }
    catch { $rollbackFailures += "config restore: $($_.Exception.Message)" }
    try {
        if ($priorJarExisted) { Copy-Item -LiteralPath $priorJar -Destination $targetJar -Force }
        elseif (Test-Path -LiteralPath $targetJar) { Remove-Item -LiteralPath $targetJar -Force }
    } catch { $rollbackFailures += "JAR restore: $($_.Exception.Message)" }
    try {
        if ($priorLauncherJarExisted) {
            Copy-Item -LiteralPath $priorLauncherJar -Destination $launcherJar -Force
        } elseif (Test-Path -LiteralPath $launcherJar) {
            Remove-Item -LiteralPath $launcherJar -Force
        }
    } catch { $rollbackFailures += "game-local JAR restore: $($_.Exception.Message)" }
    try {
        if ($priorManifestExisted) { Copy-Item -LiteralPath $priorManifest -Destination $manifestPath -Force }
        elseif (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
    } catch { $rollbackFailures += "manifest restore: $($_.Exception.Message)" }
    try {
        if (-not $priorBackupExisted -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    } catch { $rollbackFailures += "backup restore: $($_.Exception.Message)" }

    if ((Get-HashOrEmpty $configPath) -ne $priorConfigHash) {
        $rollbackFailures += 'config rollback hash mismatch'
    }
    if ($priorJarExisted -ne (Test-Path -LiteralPath $targetJar -PathType Leaf) -or
        ($priorJarExisted -and (Get-HashOrEmpty $targetJar) -ne $priorJarHash)) {
        $rollbackFailures += 'JAR rollback presence/hash mismatch'
    }
    if ($priorLauncherJarExisted -ne (Test-Path -LiteralPath $launcherJar -PathType Leaf) -or
        ($priorLauncherJarExisted -and
            (Get-HashOrEmpty $launcherJar) -ne $priorLauncherJarHash)) {
        $rollbackFailures += 'game-local JAR rollback presence/hash mismatch'
    }
    if ($priorManifestExisted -ne (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        ($priorManifestExisted -and (Get-HashOrEmpty $manifestPath) -ne $priorManifestHash)) {
        $rollbackFailures += 'manifest rollback presence/hash mismatch'
    }
    if ($rollbackFailures.Count -gt 0) {
        $message = $trigger.Exception.Message + ' Rollback failures: ' + ($rollbackFailures -join '; ')
        throw [System.InvalidOperationException]::new($message, $trigger.Exception)
    }
    throw $trigger
}
finally {
    if (Test-Path -LiteralPath $transactionRoot) {
        try { Remove-Item -LiteralPath $transactionRoot -Recurse -Force }
        catch { Write-Warning "Could not remove native installer staging directory: $($_.Exception.Message)" }
    }
}

if (-not $committed) { throw 'Native bridge transaction did not commit.' }
Write-Output "NATIVE_BRIDGE_INSTALL_PASS config=$configPath jar=$targetJar backup=$backupPath"
Write-Output $buildOutput
