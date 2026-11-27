# SPDX-License-Identifier: MIT
<#
Fixture helpers shared by test_installer.ps1 and the per-case worker it runs.

They took their inputs from the enclosing script's variables when there was only
one caller. Now that each fault-injection case runs in its own process, every
helper takes what it needs as a parameter, so a worker cannot silently pick up
a different sandbox or launcher config than the parent intended.
#>

function Get-ScOriginalLauncherConfig {
    return (@{
        mainClass = 'zombie/gameStates/MainScreenState'
        classpath = @('.', 'projectzomboid.jar')
        vmArgs = @('-Xmx1024m')
    } | ConvertTo-Json -Depth 5)
}

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

function New-InstallFixture([string]$Sandbox, [string]$Name, [string]$OriginalConfig) {
    $root = Join-Path $Sandbox $Name
    $mods = Join-Path $root 'mods'
    $game = Join-Path $root 'game'
    $backups = Join-Path $root 'managed-backups'
    $bridge = Join-Path $root 'native-bridge'
    $configBackups = Join-Path $root 'config-backups'
    New-Item -ItemType Directory -Path $mods, $game, $backups, $configBackups -Force | Out-Null
    $configPath = Join-Path $game 'ProjectZomboid64.json'
    Set-Content -LiteralPath $configPath -Value $OriginalConfig -Encoding utf8
    return [ordered]@{
        root = $root; mods = $mods; game = $game; backups = $backups
        bridge = $bridge; configBackups = $configBackups; config = $configPath
        target = (Join-Path $mods 'LivingFellows')
    }
}

function New-StandaloneInstallFixture([string]$Sandbox, [string]$Name, [string]$OriginalConfig) {
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
    Set-Content -LiteralPath $configPath -Value $OriginalConfig -Encoding utf8
    return [ordered]@{
        root = $root; mods = $mods; game = $game; data = $data
        backups = $backups; bridge = $bridge; configBackups = $configBackups
        config = $configPath; target = (Join-Path $mods 'LivingFellows')
    }
}

# The installer checks classpath membership, not executable third-party code.
# Keep this a valid ZIP with the recognized entry; never launch its dummy class.
function Set-ScPzoLauncherFixture($Fixture) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $jar = Join-Path $Fixture.game 'pzoptimizer.jar'
    $zip = [System.IO.Compression.ZipFile]::Open($jar, 'Create')
    try {
        foreach ($entry in @('com/pzoptimizer/PZOEntrypoint.class','com/pzoptimizer/JavaModLoader.class')) {
            $stream = $zip.CreateEntry($entry).Open()
            try { $stream.WriteByte(0) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    $config = Get-ScOriginalLauncherConfig | ConvertFrom-Json
    $config.mainClass = 'com/pzoptimizer/PZOEntrypoint'
    $config.classpath += @('pzoptimizer.jar', '.')
    $config.vmArgs += @('-agentlib:zbNative', '-Dforeign.keep=one', '-Dforeign.keep=one')
    $config | Add-Member -NotePropertyName windows -NotePropertyValue ([pscustomobject]@{
        gameArguments = @('-Dforeign.option=keep', '-Dforeign.option=keep')
    })
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Fixture.config -Encoding utf8
    return $jar
}

function Install-StandaloneFixture([string]$ProjectRoot, $Fixture,
        [string]$PreparedPayload, [string]$PrebuiltJar, [string]$Fault = '') {
    & (Join-Path $ProjectRoot 'scripts\Install-Local.ps1') `
        -ProjectRoot $ProjectRoot -ModsRoot $Fixture.mods -GameRoot $Fixture.game `
        -BackupRoot $Fixture.backups -BridgeRoot $Fixture.bridge `
        -ConfigBackupRoot $Fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
        -PrebuiltBridgeJar $PrebuiltJar -Standalone -FailAfter $Fault | Out-Null
}

function Set-LegacyBrandFixture($Fixture) {
    $localManifestPath = Join-Path $Fixture.target '.sc-install-manifest.json'
    $localManifest = Get-Content -LiteralPath $localManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    $localManifest.PSObject.Properties.Remove('modId')
    $localManifest.PSObject.Properties.Remove('backupModId')
    $localManifest.version = '0.27.101-standalone-native'
    foreach ($relative in @('mod.info', '42\mod.info')) {
        $path = Join-Path $Fixture.target $relative
        $info = Get-Content -LiteralPath $path -Raw -Encoding utf8
        $previous = $info.Replace('id=LivingFellows', 'id=SurvivorCompanion').
            Replace('modversion=0.27.102', 'modversion=0.27.101')
        [System.IO.File]::WriteAllText($path, $previous)
    }
    $modJar = Join-Path $Fixture.target '42\media\java\LivingFellowsBridge.jar'
    Move-Item -LiteralPath $modJar -Destination (
        Join-Path (Split-Path -Parent $modJar) 'SurvivorCompanionBridge.jar')
    $modPrefix = $Fixture.target + '\'
    $files = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Fixture.target -Recurse -File |
        Where-Object { $_.FullName -ne $localManifestPath })) {
        $relative = $file.FullName.Substring($modPrefix.Length).Replace('\', '/')
        $files[$relative] = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    }
    $localManifest.files = $files
    $localManifest | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $localManifestPath -Encoding utf8
    Move-Item -LiteralPath $Fixture.target -Destination (Join-Path $Fixture.mods 'SurvivorCompanion')

    $nativeManifestPath = Join-Path $Fixture.bridge 'install-manifest.json'
    $nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    $previousJar = Join-Path $Fixture.bridge 'SurvivorCompanionBridge.jar'
    Move-Item -LiteralPath $nativeManifest.bridgeJar -Destination $previousJar
    $nativeManifest.bridgeJar = $previousJar
    $nativeManifest.owner = 'SurvivorCompanion.NativeBridge'
    $nativeManifest.bridgeProtocol = '42.22-isocompanion-37'
    $nativeManifest.wrapperMainClass = 'survivorcompanion/bridge/SCLauncher'
    if ($nativeManifest.launchMode -eq 'wrapper') {
        $config = Get-Content -LiteralPath $Fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
        $config.mainClass = $nativeManifest.wrapperMainClass
        $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Fixture.config -Encoding utf8
        $nativeManifest.installedMainClass = $config.mainClass
        $nativeManifest.installedConfigSha256 = (Get-FileHash -LiteralPath $Fixture.config).Hash.
            ToLowerInvariant()
    }
    $nativeManifest | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $nativeManifestPath -Encoding utf8
}

function Get-InstallFixtureSnapshot($Fixture) {
    return Get-TreeSnapshot @{
        config = $Fixture.config
        launcherJar = (Join-Path $Fixture.game 'LivingFellowsBridge.jar')
        foreignPzoJar = (Join-Path $Fixture.game 'pzoptimizer.jar')
        bridge = $Fixture.bridge
        target = $Fixture.target
        legacyTarget = (Join-Path $Fixture.mods 'SurvivorCompanion')
        profile = (Join-Path $Fixture.mods 'default.txt')
        managedBackups = $Fixture.backups
        configBackups = $Fixture.configBackups
    }
}

function Get-StandaloneFixtureSnapshot($Fixture) {
    return Get-TreeSnapshot @{
        config = $Fixture.config
        launcherJar = (Join-Path $Fixture.game 'LivingFellowsBridge.jar')
        foreignPzoJar = (Join-Path $Fixture.game 'pzoptimizer.jar')
        target = $Fixture.target
        legacyTarget = (Join-Path $Fixture.mods 'SurvivorCompanion')
        profile = (Join-Path $Fixture.mods 'default.txt')
        installData = $Fixture.data
    }
}
