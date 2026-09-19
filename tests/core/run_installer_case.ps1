# SPDX-License-Identifier: MIT
<#
One installer fault-injection case, in its own process.

Each case builds a self-contained fixture under the sandbox -- its own mods,
game, managed backups, bridge and config-backup roots -- snapshots it, drives an
install or uninstall that is expected to fail at a named boundary, and asserts
both that it failed for the stated reason and that the tree came back
byte-identical. Nothing here touches anything outside its own fixture, which is
what lets test_installer.ps1 run these concurrently.

Two things this file must keep getting right, because both would make a broken
installer look green:

  * Every path through a case has to reach an assertion. A case that returns
    early, or whose expected-failure check is never evaluated, exits 0 and is
    reported as a pass.
  * A case fails by throwing. $ErrorActionPreference is Stop and PowerShell
    exits non-zero on an uncaught exception, which is the only signal the parent
    reads. Swallowing an exception here turns a real regression into a pass.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$Sandbox,
    [Parameter(Mandatory)][string]$Case,
    [string]$Variant = '',
    [string]$PreparedPayload = '',
    [string]$StandalonePreparedPayload = '',
    [string]$PrebuiltJar = ''
)

$ErrorActionPreference = 'Stop'

# A case runs in its own host, so it inherits whatever PSModulePath the parent
# had. When those do not match -- a 5.1 child launched from pwsh -- the stock
# Utility module never loads and every case fails deep inside the installer on a
# missing Get-FileHash. Say so here instead, in one line, rather than 35 times.
foreach ($required in @('Get-FileHash', 'ConvertFrom-Json', 'ConvertTo-Json', 'Get-ChildItem')) {
    if (-not (Get-Command $required -ErrorAction SilentlyContinue)) {
        throw ("Required cmdlet '$required' is unavailable in this PowerShell host " +
            "($([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)). " +
            "PSModulePath=$env:PSModulePath")
    }
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
. (Join-Path $PSScriptRoot 'InstallerFixtures.ps1')

$Install = Join-Path $ProjectRoot 'scripts\Install-Local.ps1'
$Uninstall = Join-Path $ProjectRoot 'scripts\Uninstall-Local.ps1'
$NativeInstall = Join-Path $ProjectRoot 'scripts\Install-NativeBridge.ps1'
$StandaloneUninstall = Join-Path $ProjectRoot 'scripts\Uninstall-Standalone.ps1'
$originalConfig = Get-ScOriginalLauncherConfig

function New-Fixture([string]$Name) {
    return (New-InstallFixture $Sandbox $Name $originalConfig)
}
function New-StandaloneFixture([string]$Name) {
    return (New-StandaloneInstallFixture $Sandbox $Name $originalConfig)
}

switch ($Case) {

'fresh-matrix' {
    $fixture = New-Fixture ('fresh-matrix-' + $Variant)
    $before = Get-InstallFixtureSnapshot $fixture
    $failed = $false
    try {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
            -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
            -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
            -NativeBridge -FailAfter $Variant | Out-Null
    } catch { $failed = $_.Exception.Message -like '*Injected*installer failure*' }
    if (-not $failed) { throw "Fresh installer fault boundary did not fail: $Variant" }
    if ((Get-InstallFixtureSnapshot $fixture) -ne $before) {
        throw "Fresh installer fault boundary did not restore exact state: $Variant"
    }
}

'matrix' {
    $fixture = New-Fixture ('matrix-' + $Variant)
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
        -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
        -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
        -NativeBridge | Out-Null
    $before = Get-InstallFixtureSnapshot $fixture
    $failed = $false
    try {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
            -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
            -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
            -NativeBridge -FailAfter $Variant | Out-Null
    } catch {
        $failed = $_.Exception.Message -like '*Injected*installer failure*'
    }
    if (-not $failed) { throw "Installer fault boundary did not fail: $Variant" }
    if ((Get-InstallFixtureSnapshot $fixture) -ne $before) {
        throw "Installer fault boundary did not restore exact state: $Variant"
    }
}

'native-failure-matrix' {
    # These three boundaries deliberately run against one installed bridge, one
    # after another, so each failure also proves the previous rollback left a
    # fixture the next install could still use.
    $nativeFixture = New-Fixture 'native-failure-matrix'
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $nativeFixture.game `
        -BridgeRoot $nativeFixture.bridge -ConfigBackupRoot $nativeFixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    foreach ($boundary in @('native-config-replace', 'native-jar-replace', 'native-manifest-write')) {
        $before = Get-InstallFixtureSnapshot $nativeFixture
        $failed = $false
        try {
            & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $nativeFixture.game `
                -BridgeRoot $nativeFixture.bridge -ConfigBackupRoot $nativeFixture.configBackups `
                -PrebuiltBridgeJar $PrebuiltJar -FailAfter $boundary | Out-Null
        } catch { $failed = $_.Exception.Message -like '*Injected native installer failure*' }
        if (-not $failed) { throw "Native installer fault boundary did not fail: $boundary" }
        if ((Get-InstallFixtureSnapshot $nativeFixture) -ne $before) {
            throw "Native installer fault boundary did not restore exact state: $boundary"
        }
    }
}

'target-corruption' {
    $fixture = New-Fixture ('target-corruption-' + $Variant)
    if ($Variant -eq 'update') {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
            -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
            -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
            -NativeBridge | Out-Null
    }
    $before = Get-InstallFixtureSnapshot $fixture
    $failed = $false
    try {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
            -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
            -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $PreparedPayload `
            -NativeBridge -FailAfter 'target-file-corrupt' | Out-Null
    } catch { $failed = $_.Exception.Message -like '*Installed file hash postcondition failed*' }
    if (-not $failed -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
        throw "Post-move target corruption did not fail with exact rollback: $Variant"
    }
}

'native-installed-config-hash' {
    $fixture = New-Fixture ('native-installed-config-hash-' + $Variant)
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
        -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    $ownedManifestPath = Join-Path $fixture.bridge 'install-manifest.json'
    $ownedManifest = Get-Content -LiteralPath $ownedManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    if ($Variant -eq 'missing') {
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
            -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    } catch {
        $refused = $_.Exception.Message -like '*installedConfigSha256*refusing update*'
    }
    if (-not $refused -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
        throw "Native update accepted or mutated an installedConfigSha256 $Variant fixture."
    }
}

'derived-bridge' {
    $derivedBridge = New-Fixture 'manifest-derived-bridge-root'
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $derivedBridge.mods -GameRoot $derivedBridge.game `
        -BackupRoot $derivedBridge.backups -BridgeRoot $derivedBridge.bridge `
        -ConfigBackupRoot $derivedBridge.configBackups -PreparedPayloadRoot $PreparedPayload `
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
}

'missing-native-final-generation' {
    $missingNative = New-Fixture 'missing-native-final-generation'
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $missingNative.mods -GameRoot $missingNative.game `
        -BackupRoot $missingNative.backups -BridgeRoot $missingNative.bridge `
        -ConfigBackupRoot $missingNative.configBackups -PreparedPayloadRoot $PreparedPayload `
        -NativeBridge | Out-Null
    Remove-Item -LiteralPath (Join-Path $missingNative.bridge 'install-manifest.json') -Force
    $before = Get-InstallFixtureSnapshot $missingNative
    $refused = $false
    try { & $Uninstall -ModsRoot $missingNative.mods | Out-Null }
    catch { $refused = $_.Exception.Message -like '*requires its native rollback manifest*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $missingNative) -ne $before) {
        throw 'Final local generation was removed or changed without its native rollback manifest.'
    }
}

'missing-native-installed-config-hash' {
    $missingNativeHash = New-Fixture 'missing-native-installed-config-hash'
    & $Install -ProjectRoot $ProjectRoot -ModsRoot $missingNativeHash.mods `
        -GameRoot $missingNativeHash.game -BackupRoot $missingNativeHash.backups `
        -BridgeRoot $missingNativeHash.bridge `
        -ConfigBackupRoot $missingNativeHash.configBackups `
        -PreparedPayloadRoot $PreparedPayload -NativeBridge | Out-Null
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
}

'manifestless-wrapper' {
    $manifestless = New-Fixture 'manifestless-wrapper'
    $brokenConfig = Get-Content -LiteralPath $manifestless.config -Raw -Encoding utf8 | ConvertFrom-Json
    $brokenConfig.mainClass = 'survivorcompanion/bridge/SCLauncher'
    $brokenConfig.classpath += (Join-Path $manifestless.bridge 'SurvivorCompanionBridge.jar').Replace('\', '/')
    $brokenConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestless.config -Encoding utf8
    $before = Get-InstallFixtureSnapshot $manifestless
    $refused = $false
    try {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $manifestless.game `
            -BridgeRoot $manifestless.bridge -ConfigBackupRoot $manifestless.configBackups `
            -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    } catch { $refused = $_.Exception.Message -like '*SCLauncher is active*manifest is missing*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $manifestless) -ne $before) {
        throw 'Manifestless active wrapper was not refused without mutation.'
    }
}

'stale-protocol' {
    $staleFixture = New-Fixture 'stale-protocol'
    $staleJar = Join-Path $staleFixture.root 'stale-protocol.jar'
    Copy-Item -LiteralPath $PrebuiltJar -Destination $staleJar
    # ZipFile lives in System.IO.Compression.FileSystem but ZipArchiveMode lives
    # in System.IO.Compression. In one long-running process the second assembly
    # was already loaded by something else; a case in its own process has to ask
    # for both.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
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
}

'standalone-atomic' {
    $fixture = New-StandaloneFixture ('standalone-atomic-' + $Variant)
    1..3 | ForEach-Object {
        Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    }
    $before = Get-StandaloneFixtureSnapshot $fixture
    $failed = $false
    try {
        & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
            -InstallDataRoot $fixture.data -FailAfter $Variant | Out-Null
    } catch { $failed = $_.Exception.Message -like '*Injected standalone uninstaller failure*' }
    $after = Get-StandaloneFixtureSnapshot $fixture
    if (-not $failed -or $after -ne $before) {
        throw "Standalone uninstall boundary did not restore its full snapshot: $Variant"
    }
}

'standalone-deep-corrupt' {
    $deepCorrupt = New-StandaloneFixture 'standalone-deep-corrupt'
    1..3 | ForEach-Object {
        Install-StandaloneFixture $ProjectRoot $deepCorrupt $StandalonePreparedPayload $PrebuiltJar
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
    $before = Get-StandaloneFixtureSnapshot $deepCorrupt
    $refused = $false
    try {
        & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $deepCorrupt.mods `
            -InstallDataRoot $deepCorrupt.data | Out-Null
    } catch { $refused = $_.Exception.Message -like '*generation file changed or is missing*' }
    $after = Get-StandaloneFixtureSnapshot $deepCorrupt
    if (-not $refused -or $after -ne $before) {
        throw 'Deep corrupt standalone generation was not rejected before all mutation.'
    }
}

'standalone-success' {
    $standaloneSuccess = New-StandaloneFixture 'standalone-success'
    1..3 | ForEach-Object {
        Install-StandaloneFixture $ProjectRoot $standaloneSuccess $StandalonePreparedPayload $PrebuiltJar
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
}

default {
    # An unknown case must be loud. Falling through would exit 0 and the parent
    # would report a case that never ran as a pass.
    throw "Unknown installer case: $Case"
}

}

Write-Output ("INSTALLER_CASE_PASS case=$Case" +
    $(if ($Variant) { " variant=$Variant" } else { '' }))
