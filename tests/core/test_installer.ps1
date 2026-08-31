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

    Write-Output 'INSTALLER_TRANSACTION_PASS ownership=true rollback=external no-duplicate-id=true legacy-preflight=true native-launcher=true'
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
