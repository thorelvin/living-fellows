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
        -BackupRoot $BackupRoot -BridgeRoot $BridgeRoot -NativeBridge | Out-Null
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
    $patchedConfig = Get-Content -LiteralPath $gameConfig -Raw -Encoding utf8 | ConvertFrom-Json
    $bridgeJar = (Join-Path $BridgeRoot 'SurvivorCompanionBridge.jar').Replace('\', '/')
    $launcherInvalid = $patchedConfig.mainClass -ne 'survivorcompanion/bridge/SCLauncher'
    $launcherInvalid = $launcherInvalid -or $patchedConfig.classpath -notcontains $bridgeJar
    $launcherInvalid = $launcherInvalid -or -not (Test-Path -LiteralPath (Join-Path $BridgeRoot 'install-manifest.json'))
    if ($launcherInvalid) {
        throw 'Native bridge launcher configuration was not installed transactionally.'
    }

    & $Install -ProjectRoot $ProjectRoot -ModsRoot $ModsRoot -GameRoot $GameRoot `
        -BackupRoot $BackupRoot -BridgeRoot $BridgeRoot -NativeBridge | Out-Null
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

    $failureBoundaries = @(
        'payload-build', 'payload-validation', 'native-config-stage',
        'native-config-replace', 'native-jar-replace', 'native-manifest-write',
        'local-manifest-write', 'old-mod-backup', 'new-mod-move'
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

    $legacy = Join-Path $GameRoot 'zombie\characters\IsoSurvivor.class'
    New-Item -ItemType Directory -Path (Split-Path -Parent $legacy) -Force | Out-Null
    Set-Content -LiteralPath $legacy -Value 'legacy fixture' -Encoding ascii
    $legacyRefused = $false
    try {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $ModsRoot -GameRoot $GameRoot `
            -BackupRoot $BackupRoot -BridgeRoot $BridgeRoot -NativeBridge | Out-Null
    } catch {
        $legacyRefused = $_.Exception.Message -like '*Legacy loose actor bridge detected*'
    }
    if (-not $legacyRefused) { throw 'Installer did not reject the legacy loose actor class.' }

    Write-Output 'INSTALLER_TRANSACTION_PASS ownership=true rollback=all-boundaries no-duplicate-id=true legacy-preflight=true native-launcher=true manifestless-refusal=true stale-protocol=true'
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
