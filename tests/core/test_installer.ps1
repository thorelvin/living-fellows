# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    # Fault-injection cases that may run at once. 0 picks a value from the
    # machine. Set it to 1 to read a failure without interleaving.
    [int]$Jobs = 0
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
. (Join-Path $PSScriptRoot 'InstallerFixtures.ps1')
. (Join-Path $ProjectRoot 'scripts\ScParallel.ps1')
if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Math]::Min(8, [int]$env:NUMBER_OF_PROCESSORS))
}

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
$originalConfig = Get-ScOriginalLauncherConfig
Set-Content -LiteralPath $gameConfig -Value $originalConfig -Encoding utf8
$Install = Join-Path $ProjectRoot 'scripts\Install-Local.ps1'
$Uninstall = Join-Path $ProjectRoot 'scripts\Uninstall-Local.ps1'
$NativeInstall = Join-Path $ProjectRoot 'scripts\Install-NativeBridge.ps1'
$StandaloneUninstall = Join-Path $ProjectRoot 'scripts\Uninstall-Standalone.ps1'

# The standalone .bat wrappers must not hand PowerShell a bare "%~dp0": %~dp0 ends
# with a backslash, so the trailing \" is parsed as an escaped quote and the rest
# of the command line is swallowed into the argument, which then trips
# [System.IO.Path]::GetFullPath with "Illegal characters in the path" -- a hard
# install failure for every standalone unzip-and-run. Wrappers must strip the
# trailing backslash before passing the directory as an argument.
foreach ($bat in @('Install.bat', 'Install-Debug.bat', 'Uninstall.bat')) {
    $batPath = Join-Path $ProjectRoot $bat
    if (-not (Test-Path -LiteralPath $batPath -PathType Leaf)) {
        throw "Standalone wrapper missing: $bat"
    }
    foreach ($line in (Get-Content -LiteralPath $batPath)) {
        if ($line -match '(?i)^\s*powershell' -and $line -match '"%~dp0"') {
            throw "$bat passes a bare `"%~dp0`" as a PowerShell argument; the trailing backslash escapes the closing quote and corrupts the argument. Strip the trailing backslash first."
        }
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
    $defaultProfile = Join-Path $ModsRoot 'default.txt'
    $profileText = Get-Content -LiteralPath $defaultProfile -Raw -Encoding utf8
    if (@([regex]::Matches($profileText,
            '(?m)^\s*mod\s*=\s*SurvivorCompanion\s*,?\s*$')).Count -ne 1) {
        throw 'Installer did not activate Living Fellows exactly once in the default mod profile.'
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
    $profileText = Get-Content -LiteralPath $defaultProfile -Raw -Encoding utf8
    if (@([regex]::Matches($profileText,
            '(?m)^\s*mod\s*=\s*SurvivorCompanion\s*,?\s*$')).Count -ne 1) {
        throw 'Installer duplicated Living Fellows in the default mod profile during update.'
    }
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

    # Every case below owns a self-contained fixture under the sandbox --
    # its own mods, game, managed backups, bridge and config-backup roots --
    # and touches nothing outside it, so they run concurrently. The sequence
    # above deliberately does not: it installs, reinstalls to rotate the
    # backup generations and uninstalls against one set of roots, and that
    # order is the thing under test.
    $caseRunner = Join-Path $PSScriptRoot 'run_installer_case.ps1'
    $cases = New-Object System.Collections.ArrayList
    function Add-InstallerCase([string]$Case, [string]$Variant = '') {
        $arguments = @(
            '-ProjectRoot', $ProjectRoot, '-Sandbox', $Sandbox, '-Case', $Case,
            '-PreparedPayload', $preparedPayload,
            '-StandalonePreparedPayload', $standalonePreparedPayload,
            '-PrebuiltJar', $prebuiltJar)
        if ($Variant) { $arguments += @('-Variant', $Variant) }
        $name = if ($Variant) { "$Case/$Variant" } else { $Case }
        [void]$cases.Add((New-ScPowerShellStep -Name $name -Script $caseRunner `
            -Arguments $arguments -Failure "Installer case failed: $name"))
    }

    $failureBoundaries = @(
        'payload-build', 'payload-validation', 'native-config-stage',
        'native-config-replace', 'native-jar-replace', 'native-manifest-write',
        'local-manifest-write', 'old-mod-backup', 'new-mod-move',
        'target-postcondition'
    )
    # old-mod-backup cannot be reached on a fresh install: there is no
    # previous generation to back up.
    foreach ($boundary in @($failureBoundaries | Where-Object { $_ -ne 'old-mod-backup' })) {
        Add-InstallerCase 'fresh-matrix' $boundary
    }
    foreach ($boundary in $failureBoundaries) {
        Add-InstallerCase 'matrix' $boundary
    }
    Add-InstallerCase 'native-failure-matrix'
    foreach ($mode in @('fresh', 'update')) {
        Add-InstallerCase 'target-corruption' $mode
    }
    foreach ($mode in @('missing', 'mismatch')) {
        Add-InstallerCase 'native-installed-config-hash' $mode
    }
    foreach ($case in @('derived-bridge', 'missing-native-final-generation',
            'missing-native-installed-config-hash', 'manifestless-wrapper',
            'stale-protocol')) {
        Add-InstallerCase $case
    }
    foreach ($boundary in @('standalone-snapshot', 'standalone-generation-remove',
            'standalone-native-rollback', 'standalone-postcondition')) {
        Add-InstallerCase 'standalone-atomic' $boundary
    }
    Add-InstallerCase 'standalone-deep-corrupt'
    Add-InstallerCase 'standalone-success'

    $expectedCases = 35
    if ($cases.Count -ne $expectedCases) {
        # A case list that quietly shrinks is a coverage loss that still
        # reports a pass, so the count is part of the contract.
        throw "Installer case list changed: expected $expectedCases, built $($cases.Count)."
    }
    Invoke-ScParallelSteps -Steps $cases.ToArray() -Throttle $Jobs -Label 'installer cases'

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

    Write-Output 'INSTALLER_TRANSACTION_PASS ownership=true rollback=all-boundaries standalone-atomic=true deep-chain-preflight=true derived-bridge=true exact-target=true no-duplicate-id=true legacy-preflight=true native-launcher=true manifestless-refusal=true stale-protocol=true bat-wrapper-safe=true default-profile=true'
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
