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
        target = (Join-Path $mods 'SurvivorCompanion')
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
        config = $configPath; target = (Join-Path $mods 'SurvivorCompanion')
    }
}

function Install-StandaloneFixture([string]$ProjectRoot, $Fixture,
        [string]$PreparedPayload, [string]$PrebuiltJar) {
    & (Join-Path $ProjectRoot 'scripts\Install-Local.ps1') `
        -ProjectRoot $ProjectRoot -ModsRoot $Fixture.mods -GameRoot $Fixture.game `
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

function Get-StandaloneFixtureSnapshot($Fixture) {
    return Get-TreeSnapshot @{
        config = $Fixture.config
        target = $Fixture.target
        installData = $Fixture.data
    }
}
