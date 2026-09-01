# SPDX-License-Identifier: MIT

[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$BuildRoot = Join-Path $ProjectRoot 'build'
$Sandbox = Join-Path $BuildRoot 'test-installer-sandbox'
$buildPrefix = $BuildRoot.TrimEnd('\') + '\'
$resolvedSandbox = [System.IO.Path]::GetFullPath($Sandbox)
if (-not $resolvedSandbox.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe installer-test sandbox: $resolvedSandbox"
}
if (Test-Path -LiteralPath $Sandbox) { Remove-Item -LiteralPath $Sandbox -Recurse -Force }
$ModsRoot = Join-Path $Sandbox 'mods'
$GameRoot = Join-Path $Sandbox 'game'
$BackupRoot = Join-Path $Sandbox 'managed-backups'
$BridgeRoot = Join-Path $Sandbox 'native-bridge'
$ConfigBackupRoot = Join-Path $Sandbox 'config-backups'
New-Item -ItemType Directory -Path $ModsRoot, $GameRoot, $BackupRoot, $ConfigBackupRoot -Force | Out-Null
$gameConfig = Join-Path $GameRoot 'ProjectZomboid64.json'
$originalConfig = @{
    mainClass = 'zombie/gameStates/MainScreenState'
    classpath = @('.', 'projectzomboid.jar')
    vmArgs = @('-Xmx1024m')
} | ConvertTo-Json -Depth 5
Set-Content -LiteralPath $gameConfig -Value $originalConfig -Encoding utf8
$Install = Join-Path $ProjectRoot 'scripts\Install-Local.ps1'
$Uninstall = Join-Path $ProjectRoot 'scripts\Uninstall-Local.ps1'
$NativeInstall = Join-Path $ProjectRoot 'scripts\Install-NativeBridge.ps1'
$StandaloneUninstall = Join-Path $ProjectRoot 'scripts\Uninstall-Standalone.ps1'

function Get-TreeSnapshot([hashtable]$Paths) {
    $snapshot = [ordered]@{}
    foreach ($label in @($Paths.Keys | Sort-Object)) {
        $path = [System.IO.Path]::GetFullPath([string]$Paths[$label])
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $snapshot[$label] = [ordered]@{
                kind = 'file'
                hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } elseif (Test-Path -LiteralPath $path -PathType Container) {
            $prefix = $path.TrimEnd('\') + '\'
            $entries = [ordered]@{ '<root>' = 'directory' }
            Get-ChildItem -LiteralPath $path -Force -Recurse | Sort-Object FullName | ForEach-Object {
                $relative = $_.FullName.Substring($prefix.Length).Replace('\', '/')
                if ($_.PSIsContainer) { $entries[$relative] = 'directory' }
                else {
                    $entries[$relative] = (Get-FileHash -LiteralPath $_.FullName `
                        -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
            $snapshot[$label] = [ordered]@{ kind = 'directory'; entries = $entries }
        } else {
            $snapshot[$label] = [ordered]@{ kind = 'absent' }
        }
    }
    return ($snapshot | ConvertTo-Json -Depth 20 -Compress)
}

function New-InstallFixture([string]$Name) {
    $root = Join-Path $Sandbox $Name
    $mods = Join-Path $root 'mods'
    $game = Join-Path $root 'game'
    $backups = Join-Path $root 'managed-backups'
    $bridge = Join-Path $root 'native-bridge'
    $configBackups = Join-Path $root 'config-backups'
    New-Item -ItemType Directory -Path $mods, $game, $backups, $configBackups -Force | Out-Null
    $configPath = Join-Path $game 'ProjectZomboid64.json'
    Set-Content -LiteralPath $configPath -Value $originalConfig -Encoding utf8
    return [ordered]@{
        root = $root; mods = $mods; game = $game; backups = $backups
        bridge = $bridge; configBackups = $configBackups; config = $configPath
        target = (Join-Path $mods 'SurvivorCompanion')
    }
}

function New-StandaloneInstallFixture([string]$Name) {
    $root = Join-Path $Sandbox $Name
    $mods = Join-Path $root 'mods'
    $game = Join-Path $root 'game'
    $data = Join-Path $root 'install-data'
    $backups = Join-Path $data 'mod-backups'
    $bridge = Join-Path $data 'bridge'
    $configBackups = Join-Path $data 'config-backups'
    New-Item -ItemType Directory -Path $mods, $game, $backups, $configBackups -Force |
        Out-Null
    $configPath = Join-Path $game 'ProjectZomboid64.json'
    Set-Content -LiteralPath $configPath -Value $originalConfig -Encoding utf8
    return [ordered]@{
        root = $root; mods = $mods; game = $game; data = $data
        backups = $backups; bridge = $bridge; configBackups = $configBackups
        config = $configPath; target = (Join-Path $mods 'SurvivorCompanion')
    }
}

function Install-StandaloneFixture($Fixture, [string]$PreparedPayload, [string]$PrebuiltJar) {
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $Fixture.mods -GameRoot $Fixture.game `
        -BackupRoot $Fixture.backups -BridgeRoot $Fixture.bridge `
        -ConfigBackupRoot $Fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
        -PrebuiltBridgeJar $PrebuiltJar -Standalone | Out-Null
}

function Get-InstallFixtureSnapshot($Fixture) {
    return Get-TreeSnapshot @{
        config = $Fixture.config
        bridge = $Fixture.bridge
        target = $Fixture.target
        managedBackups = $Fixture.backups
        configBackups = $Fixture.configBackups
    }
}

try {
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $ModsRoot -GameRoot $GameRoot `
        -BackupRoot $BackupRoot -BridgeRoot $BridgeRoot `
        -ConfigBackupRoot $ConfigBackupRoot -NativeBridge | Out-Null
    $Target = Join-Path $ModsRoot 'SurvivorCompanion'
    $Config = Join-Path $Target '42\media\lua\shared\SCConfig.lua'
    $configText = Get-Content -LiteralPath $Config -Raw -Encoding utf8
    $experimentalDisabled = $configText -match 'experimentalNpcPlayerActor\s*=\s*false'
    $debugEnabled = $configText -match 'debugSpawnEnabled\s*=\s*true'
    $markerPresent = Test-Path -LiteralPath (Join-Path $Target 'PRIVATE-NATIVE-BRIDGE.txt')
    if (-not $experimentalDisabled -or -not $debugEnabled -or -not $markerPresent) {
        throw 'Private install did not carry its explicit configuration and marker.'
    }
    $installedJars = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Filter '*.jar')
    $jarOwnershipFailed = $installedJars.Count -ne 1
    if (-not $jarOwnershipFailed) {
        $jarOwnershipFailed = $installedJars[0].Name -ne 'SurvivorCompanionBridge.jar'
    }
    $looseClasses = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Filter '*.class')
    $jarOwnershipFailed = $jarOwnershipFailed -or $looseClasses.Count -gt 0
    if ($jarOwnershipFailed) {
        throw 'Private install native bytecode ownership check failed.'
    }
    $compiledBridge = Join-Path $ProjectRoot 'build\native-bridge\SurvivorCompanionBridge.jar'
    $payloadBridge = Join-Path $Target '42\media\java\SurvivorCompanionBridge.jar'
    $launcherBridge = Join-Path $BridgeRoot 'SurvivorCompanionBridge.jar'
    $compiledHash = (Get-FileHash -LiteralPath $compiledBridge -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-FileHash -LiteralPath $payloadBridge -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            $compiledHash -or
        (Get-FileHash -LiteralPath $launcherBridge -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            $compiledHash) {
        throw 'Direct native development install did not use the current compiled bridge in both targets.'
    }
    $patchedConfig = Get-Content -LiteralPath $gameConfig -Raw -Encoding utf8 | ConvertFrom-Json
    $bridgeJar = (Join-Path $BridgeRoot 'SurvivorCompanionBridge.jar').Replace('\', '/')
    $launcherInvalid = $patchedConfig.mainClass -ne 'survivorcompanion/bridge/SCLauncher'
    $launcherInvalid = $launcherInvalid -or $patchedConfig.classpath -notcontains $bridgeJar
    $launcherInvalid = $launcherInvalid -or -not (Test-Path -LiteralPath (Join-Path $BridgeRoot 'install-manifest.json'))
    if ($launcherInvalid) {
        throw 'Native bridge launcher configuration was not installed transactionally.'
    }

    & $Install -ProjectRoot $ProjectRoot -ModsRoot $ModsRoot -GameRoot $GameRoot `
        -BackupRoot $BackupRoot -BridgeRoot $BridgeRoot `
        -ConfigBackupRoot $ConfigBackupRoot -NativeBridge | Out-Null
    $duplicateIds = @(Get-ChildItem -LiteralPath $ModsRoot -Force -Directory | Where-Object {
        $info = Join-Path $_.FullName 'mod.info'
        (Test-Path -LiteralPath $info) -and (Get-Content -LiteralPath $info -Raw) -match '(?m)^id=SurvivorCompanion\s*$'
    })
    if ($duplicateIds.Count -ne 1) {
        throw 'Installer left a duplicate same-ID mod inside the live mods directory.'
    }
    $externalBackups = @(Get-ChildItem -LiteralPath $BackupRoot -Directory)
    if ($externalBackups.Count -ne 1) { throw 'Installer did not create exactly one external rollback.' }
    & $Uninstall -ModsRoot $ModsRoot -BridgeRoot $BridgeRoot | Out-Null
    if (-not (Test-Path -LiteralPath $Target)) { throw 'Managed backup was not restored.' }
    if (@(Get-ChildItem -LiteralPath $BackupRoot -Directory).Count -ne 0) {
        throw 'Restored external rollback remained duplicated after uninstall.'
    }

    $extra = Join-Path $Target 'user-change.txt'
    Set-Content -LiteralPath $extra -Value 'ownership check' -Encoding utf8
    $refused = $false
    try { & $Uninstall -ModsRoot $ModsRoot -BridgeRoot $BridgeRoot | Out-Null } catch { $refused = $true }
    if (-not $refused -or -not (Test-Path -LiteralPath $Target)) {
        throw 'Uninstaller did not refuse an ownership/hash mismatch.'
    }
    Remove-Item -LiteralPath $extra -Force
    & $Uninstall -ModsRoot $ModsRoot -BridgeRoot $BridgeRoot | Out-Null
    if (Test-Path -LiteralPath $Target) { throw 'Owned install remained after uninstall.' }
    $restoredConfig = Get-Content -LiteralPath $gameConfig -Raw -Encoding utf8 | ConvertFrom-Json
    $launcherNotRestored = $restoredConfig.mainClass -ne 'zombie/gameStates/MainScreenState'
    $launcherNotRestored = $launcherNotRestored -or $restoredConfig.classpath -contains $bridgeJar
    if ($launcherNotRestored) {
        throw 'Final uninstall did not restore the launcher configuration.'
    }

    $preparedRoot = Join-Path $Sandbox 'prepared-payload'
    & (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') `
        -ProjectRoot $ProjectRoot -OutputRoot $preparedRoot -AllowExternalOutput | Out-Null
    $preparedPayload = Join-Path $preparedRoot 'SurvivorCompanion'
    $prebuiltJar = Join-Path $preparedPayload '42\media\java\SurvivorCompanionBridge.jar'
    $standalonePreparedRoot = Join-Path $Sandbox 'prepared-standalone-payload'
    & (Join-Path $ProjectRoot 'scripts\New-StandalonePayload.ps1') `
        -ProjectRoot $ProjectRoot -OutputRoot $standalonePreparedRoot `
        -AllowExternalOutput | Out-Null
    $standalonePreparedPayload = Join-Path $standalonePreparedRoot 'SurvivorCompanion'

    $failureBoundaries = @(
        'payload-build', 'payload-validation', 'native-config-stage',
        'native-config-replace', 'native-jar-replace', 'native-manifest-write',
        'local-manifest-write', 'old-mod-backup', 'new-mod-move',
        'target-postcondition'
    )
    foreach ($boundary in @($failureBoundaries | Where-Object { $_ -ne 'old-mod-backup' })) {
        $fixture = New-InstallFixture ('fresh-matrix-' + $boundary)
        $before = Get-InstallFixtureSnapshot $fixture
        $failed = $false
        try {
            & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
                -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
                -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $preparedPayload `
                -NativeBridge -FailAfter $boundary | Out-Null
        } catch { $failed = $_.Exception.Message -like '*Injected*installer failure*' }
        if (-not $failed) { throw "Fresh installer fault boundary did not fail: $boundary" }
        if ((Get-InstallFixtureSnapshot $fixture) -ne $before) {
            throw "Fresh installer fault boundary did not restore exact state: $boundary"
        }
    }
    foreach ($boundary in $failureBoundaries) {
        $fixture = New-InstallFixture ('matrix-' + $boundary)
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
            -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
            -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $preparedPayload `
            -NativeBridge | Out-Null
        $before = Get-InstallFixtureSnapshot $fixture
        $failed = $false
        try {
            & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
                -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
                -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $preparedPayload `
                -NativeBridge -FailAfter $boundary | Out-Null
        } catch {
            $failed = $_.Exception.Message -like '*Injected*installer failure*'
        }
        if (-not $failed) { throw "Installer fault boundary did not fail: $boundary" }
        $after = Get-InstallFixtureSnapshot $fixture
        if ($after -ne $before) {
            throw "Installer fault boundary did not restore exact state: $boundary"
        }
    }

    $nativeFixture = New-InstallFixture 'native-failure-matrix'
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $nativeFixture.game `
        -BridgeRoot $nativeFixture.bridge -ConfigBackupRoot $nativeFixture.configBackups `
        -PrebuiltBridgeJar $prebuiltJar | Out-Null
    foreach ($boundary in @('native-config-replace', 'native-jar-replace', 'native-manifest-write')) {
        $before = Get-InstallFixtureSnapshot $nativeFixture
        $failed = $false
        try {
            & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $nativeFixture.game `
                -BridgeRoot $nativeFixture.bridge -ConfigBackupRoot $nativeFixture.configBackups `
                -PrebuiltBridgeJar $prebuiltJar -FailAfter $boundary | Out-Null
        } catch { $failed = $_.Exception.Message -like '*Injected native installer failure*' }
        if (-not $failed) { throw "Native installer fault boundary did not fail: $boundary" }
        if ((Get-InstallFixtureSnapshot $nativeFixture) -ne $before) {
            throw "Native installer fault boundary did not restore exact state: $boundary"
        }
    }

    foreach ($mode in @('fresh', 'update')) {
        $fixture = New-InstallFixture ('target-corruption-' + $mode)
        if ($mode -eq 'update') {
            & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
                -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
                -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $preparedPayload `
                -NativeBridge | Out-Null
        }
        $before = Get-InstallFixtureSnapshot $fixture
        $failed = $false
        try {
            & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
                -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
                -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $preparedPayload `
                -NativeBridge -FailAfter 'target-file-corrupt' | Out-Null
        } catch { $failed = $_.Exception.Message -like '*Installed file hash postcondition failed*' }
        if (-not $failed -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
            throw "Post-move target corruption did not fail with exact rollback: $mode"
        }
    }

    foreach ($hashMode in @('missing', 'mismatch')) {
        $fixture = New-InstallFixture ('native-installed-config-hash-' + $hashMode)
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
            -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
            -PrebuiltBridgeJar $prebuiltJar | Out-Null
        $ownedManifestPath = Join-Path $fixture.bridge 'install-manifest.json'
        $ownedManifest = Get-Content -LiteralPath $ownedManifestPath -Raw -Encoding utf8 |
            ConvertFrom-Json
        if ($hashMode -eq 'missing') {
            $ownedManifest.PSObject.Properties.Remove('installedConfigSha256')
        } else {
            $ownedManifest.installedConfigSha256 = ('0' * 64)
        }
        $ownedManifest | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath $ownedManifestPath -Encoding utf8
        $before = Get-InstallFixtureSnapshot $fixture
        $refused = $false
        try {
            & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
                -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
                -PrebuiltBridgeJar $prebuiltJar | Out-Null
        } catch {
            $refused = $_.Exception.Message -like '*installedConfigSha256*refusing update*'
        }
        if (-not $refused -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
            throw "Native update accepted or mutated an installedConfigSha256 $hashMode fixture."
        }
    }

    $derivedBridge = New-InstallFixture 'manifest-derived-bridge-root'
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $derivedBridge.mods -GameRoot $derivedBridge.game `
        -BackupRoot $derivedBridge.backups -BridgeRoot $derivedBridge.bridge `
        -ConfigBackupRoot $derivedBridge.configBackups -PreparedPayloadRoot $preparedPayload `
        -NativeBridge | Out-Null
    $before = Get-InstallFixtureSnapshot $derivedBridge
    $refused = $false
    try {
        & $Uninstall -ModsRoot $derivedBridge.mods `
            -BridgeRoot (Join-Path $derivedBridge.root 'wrong-bridge') | Out-Null
    } catch { $refused = $_.Exception.Message -like '*Explicit BridgeRoot does not match*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $derivedBridge) -ne $before) {
        throw 'Local uninstaller did not reject an explicit bridge-root mismatch before mutation.'
    }
    & $Uninstall -ModsRoot $derivedBridge.mods | Out-Null
    if ((Test-Path -LiteralPath $derivedBridge.target) -or
        (Test-Path -LiteralPath (Join-Path $derivedBridge.bridge 'install-manifest.json'))) {
        throw 'Local uninstaller did not derive and remove the owned bridge from its mod manifest.'
    }

    $missingNative = New-InstallFixture 'missing-native-final-generation'
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $missingNative.mods -GameRoot $missingNative.game `
        -BackupRoot $missingNative.backups -BridgeRoot $missingNative.bridge `
        -ConfigBackupRoot $missingNative.configBackups -PreparedPayloadRoot $preparedPayload `
        -NativeBridge | Out-Null
    Remove-Item -LiteralPath (Join-Path $missingNative.bridge 'install-manifest.json') -Force
    $before = Get-InstallFixtureSnapshot $missingNative
    $refused = $false
    try { & $Uninstall -ModsRoot $missingNative.mods | Out-Null }
    catch { $refused = $_.Exception.Message -like '*requires its native rollback manifest*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $missingNative) -ne $before) {
        throw 'Final local generation was removed or changed without its native rollback manifest.'
    }

    $missingNativeHash = New-InstallFixture 'missing-native-installed-config-hash'
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $missingNativeHash.mods `
        -GameRoot $missingNativeHash.game -BackupRoot $missingNativeHash.backups `
        -BridgeRoot $missingNativeHash.bridge `
        -ConfigBackupRoot $missingNativeHash.configBackups `
        -PreparedPayloadRoot $preparedPayload -NativeBridge | Out-Null
    $nativeManifestPath = Join-Path $missingNativeHash.bridge 'install-manifest.json'
    $nativeManifestObject = Get-Content -LiteralPath $nativeManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    $nativeManifestObject.PSObject.Properties.Remove('installedConfigSha256')
    $nativeManifestObject | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $nativeManifestPath -Encoding utf8
    $before = Get-InstallFixtureSnapshot $missingNativeHash
    $refused = $false
    try { & $Uninstall -ModsRoot $missingNativeHash.mods | Out-Null }
    catch { $refused = $_.Exception.Message -like '*has no installedConfigSha256*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $missingNativeHash) -ne $before) {
        throw 'Final local generation bypassed an incomplete native manifest preflight.'
    }

    $manifestless = New-InstallFixture 'manifestless-wrapper'
    $brokenConfig = Get-Content -LiteralPath $manifestless.config -Raw -Encoding utf8 | ConvertFrom-Json
    $brokenConfig.mainClass = 'survivorcompanion/bridge/SCLauncher'
    $brokenConfig.classpath += (Join-Path $manifestless.bridge 'SurvivorCompanionBridge.jar').Replace('\', '/')
    $brokenConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestless.config -Encoding utf8
    $before = Get-InstallFixtureSnapshot $manifestless
    $refused = $false
    try {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $manifestless.game `
            -BridgeRoot $manifestless.bridge -ConfigBackupRoot $manifestless.configBackups `
            -PrebuiltBridgeJar $prebuiltJar | Out-Null
    } catch { $refused = $_.Exception.Message -like '*SCLauncher is active*manifest is missing*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $manifestless) -ne $before) {
        throw 'Manifestless active wrapper was not refused without mutation.'
    }

    $staleFixture = New-InstallFixture 'stale-protocol'
    $staleJar = Join-Path $staleFixture.root 'stale-protocol.jar'
    Copy-Item -LiteralPath $prebuiltJar -Destination $staleJar
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($staleJar,
        [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.GetEntry('META-INF/MANIFEST.MF')
        $entry.Delete()
        $replacement = $archive.CreateEntry('META-INF/MANIFEST.MF')
        $stream = $replacement.Open()
        $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)))
        try {
            $writer.Write("Manifest-Version: 1.0`r`nMain-Class: survivorcompanion.bridge.SCLauncher`r`nSC-Bridge-Protocol: stale`r`nSC-Supported-Game-Version: 42.20`r`nSC-Compiled-Game-Version: 42.20.4`r`n`r`n")
        } finally { $writer.Dispose(); $stream.Dispose() }
    } finally { $archive.Dispose() }
    $before = Get-InstallFixtureSnapshot $staleFixture
    $refused = $false
    try {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $staleFixture.game `
            -BridgeRoot $staleFixture.bridge -ConfigBackupRoot $staleFixture.configBackups `
            -PrebuiltBridgeJar $staleJar | Out-Null
    } catch { $refused = $_.Exception.Message -like '*metadata mismatch*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $staleFixture) -ne $before) {
        throw 'Stale-protocol prebuilt bridge was not rejected before live mutation.'
    }

    foreach ($boundary in @(
            'standalone-snapshot', 'standalone-generation-remove',
            'standalone-native-rollback', 'standalone-postcondition')) {
        $fixture = New-StandaloneInstallFixture ('standalone-atomic-' + $boundary)
        1..3 | ForEach-Object {
            Install-StandaloneFixture $fixture $standalonePreparedPayload $prebuiltJar
        }
        $before = Get-TreeSnapshot @{
            config = $fixture.config
            target = $fixture.target
            installData = $fixture.data
        }
        $failed = $false
        try {
            & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
                -InstallDataRoot $fixture.data -FailAfter $boundary | Out-Null
        } catch { $failed = $_.Exception.Message -like '*Injected standalone uninstaller failure*' }
        $after = Get-TreeSnapshot @{
            config = $fixture.config
            target = $fixture.target
            installData = $fixture.data
        }
        if (-not $failed -or $after -ne $before) {
            throw "Standalone uninstall boundary did not restore its full snapshot: $boundary"
        }
    }

    $deepCorrupt = New-StandaloneInstallFixture 'standalone-deep-corrupt'
    1..3 | ForEach-Object {
        Install-StandaloneFixture $deepCorrupt $standalonePreparedPayload $prebuiltJar
    }
    $newest = Get-Content -LiteralPath `
        (Join-Path $deepCorrupt.target '.sc-install-manifest.json') -Raw -Encoding utf8 |
        ConvertFrom-Json
    $middlePath = [string]$newest.backupPath
    $middle = Get-Content -LiteralPath (Join-Path $middlePath '.sc-install-manifest.json') `
        -Raw -Encoding utf8 | ConvertFrom-Json
    $deepPath = [string]$middle.backupPath
    if ([string]::IsNullOrWhiteSpace($deepPath)) {
        throw 'Three-generation standalone fixture did not create a deep backup.'
    }
    [System.IO.File]::AppendAllText((Join-Path $deepPath '42\mod.info'),
        "`n# injected deep-generation corruption")
    $before = Get-TreeSnapshot @{
        config = $deepCorrupt.config
        target = $deepCorrupt.target
        installData = $deepCorrupt.data
    }
    $refused = $false
    try {
        & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $deepCorrupt.mods `
            -InstallDataRoot $deepCorrupt.data | Out-Null
    } catch { $refused = $_.Exception.Message -like '*generation file changed or is missing*' }
    $after = Get-TreeSnapshot @{
        config = $deepCorrupt.config
        target = $deepCorrupt.target
        installData = $deepCorrupt.data
    }
    if (-not $refused -or $after -ne $before) {
        throw 'Deep corrupt standalone generation was not rejected before all mutation.'
    }

    $standaloneSuccess = New-StandaloneInstallFixture 'standalone-success'
    1..3 | ForEach-Object {
        Install-StandaloneFixture $standaloneSuccess $standalonePreparedPayload $prebuiltJar
    }
    & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $standaloneSuccess.mods `
        -InstallDataRoot $standaloneSuccess.data | Out-Null
    $restoredStandalone = Get-Content -LiteralPath $standaloneSuccess.config -Raw -Encoding utf8 |
        ConvertFrom-Json
    if ((Test-Path -LiteralPath $standaloneSuccess.target) -or
        (Test-Path -LiteralPath (Join-Path $standaloneSuccess.bridge 'install-manifest.json')) -or
        @(Get-ChildItem -LiteralPath $standaloneSuccess.backups -Directory `
            -ErrorAction SilentlyContinue).Count -ne 0 -or
        $restoredStandalone.mainClass -ne 'zombie/gameStates/MainScreenState') {
        throw 'Successful standalone uninstall did not consume all generations and restore launcher.'
    }

    $legacy = Join-Path $GameRoot 'zombie\characters\IsoSurvivor.class'
    New-Item -ItemType Directory -Path (Split-Path -Parent $legacy) -Force | Out-Null
    Set-Content -LiteralPath $legacy -Value 'legacy fixture' -Encoding ascii
    $legacyRefused = $false
    try {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $ModsRoot -GameRoot $GameRoot `
            -BackupRoot $BackupRoot -BridgeRoot $BridgeRoot `
            -ConfigBackupRoot $ConfigBackupRoot -NativeBridge | Out-Null
    } catch {
        $legacyRefused = $_.Exception.Message -like '*Legacy loose actor bridge detected*'
    }
    if (-not $legacyRefused) { throw 'Installer did not reject the legacy loose actor class.' }

    Write-Output 'INSTALLER_TRANSACTION_PASS ownership=true rollback=all-boundaries standalone-atomic=true deep-chain-preflight=true derived-bridge=true exact-target=true no-duplicate-id=true legacy-preflight=true native-launcher=true manifestless-refusal=true stale-protocol=true'
}
finally {
    if (Test-Path -LiteralPath $Sandbox) {
        $finalPath = [System.IO.Path]::GetFullPath($Sandbox)
        if (-not $finalPath.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe test cleanup: $finalPath"
        }
        Remove-Item -LiteralPath $Sandbox -Recurse -Force
    }
}
