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
function Install-AgentFixture($Fixture, [string]$Fault = '') {
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $Fixture.game `
        -BridgeRoot $Fixture.bridge -ConfigBackupRoot $Fixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar -FailAfter $Fault | Out-Null
}
function Assert-AgentFixture($Fixture) {
    $config = Get-Content -LiteralPath $Fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath (Join-Path $Fixture.bridge 'install-manifest.json') `
        -Raw -Encoding utf8 | ConvertFrom-Json
    if ($config.mainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or
        @($config.classpath | Where-Object { $_ -ceq 'LivingFellowsBridge.jar' }).Count -ne 1 -or
        @($config.vmArgs | Where-Object { $_ -match '^-javaagent:.*LivingFellowsBridge.jar' }).Count -ne 0 -or
        $manifest.schemaVersion -ne 4 -or $manifest.launchMode -ne 'pzo-loader' -or
        $manifest.launcherAgentArgument -ne '' -or
        $manifest.installedMainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or
        $manifest.originalMainClass -ne 'com/pzoptimizer/PZOEntrypoint') {
        throw 'Recognized PZO launcher did not retain its main with loader-only bootstrap state.'
    }
}

switch ($Case) {
'legacy-brand' {
    $fixture = New-StandaloneFixture ('legacy-brand-' + $Variant)
    if ($Variant -eq 'pzo') { Set-ScPzoLauncherFixture $fixture | Out-Null }
    $originalConfigHash = (Get-FileHash -LiteralPath $fixture.config).Hash
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    Set-LegacyBrandFixture $fixture
    $legacyTarget = Join-Path $fixture.mods 'SurvivorCompanion'
    $legacyJar = Join-Path $fixture.bridge 'SurvivorCompanionBridge.jar'
    $nativeManifestPath = Join-Path $fixture.bridge 'install-manifest.json'
    $profilePath = Join-Path $fixture.mods 'default.txt'
    $save = Join-Path $fixture.root 'Saves\Sandbox\Test World'
    New-Item -ItemType Directory -Path $save | Out-Null
    $saveMods = Join-Path $save 'mods.txt'
    $profile = "VERSION = 1,`r`nmods`r`n{`r`n    mod = OtherFirst,`r`n" +
        "    mod = \SurvivorCompanion,`r`n    mod = OtherSecond,`r`n    mod = LivingFellows,`r`n" +
        "}`r`nmaps`r`n{`r`n    map = ForeignMap,`r`n}`r`n"
    [IO.File]::WriteAllText($profilePath, $profile)
    [IO.File]::WriteAllText($saveMods, $profile)
    $saveHash = (Get-FileHash -LiteralPath $saveMods).Hash
    $before = Get-StandaloneFixtureSnapshot $fixture
    if ($Variant -eq 'conflict') {
        New-Item -ItemType Directory -Path $fixture.target | Out-Null
        $before = Get-StandaloneFixtureSnapshot $fixture
        foreach ($operation in @(
            { Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar },
            { & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -InstallDataRoot $fixture.data }
        )) {
            $refusal = ''
            try { & $operation | Out-Null } catch { $refusal = $_.Exception.Message }
            if ($refusal -notmatch 'Both the current and previous Living Fellows mod directories' -or
                (Get-StandaloneFixtureSnapshot $fixture) -cne $before) {
                throw "Duplicate legacy/current paths were not refused safely: $refusal"
            }
        }
        Move-Item -LiteralPath $fixture.target -Destination (Join-Path $fixture.root 'inactive-new-dir')
        Move-Item -LiteralPath (Join-Path $legacyTarget '.sc-install-manifest.json') `
            -Destination (Join-Path $fixture.root 'inactive-legacy-manifest.json')
        $before = Get-StandaloneFixtureSnapshot $fixture
        $refusal = ''
        try { Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar }
        catch { $refusal = $_.Exception.Message }
        if ($refusal -notmatch 'Refusing to overwrite unmanaged mod directory' -or
            (Get-StandaloneFixtureSnapshot $fixture) -cne $before) {
            throw "Unmanaged previous path was not refused safely: $refusal"
        }
    } else {
        if ($Variant -eq 'wrapper') {
            foreach ($fault in @('native-jar-replace', 'new-mod-move', 'profile-migration')) {
                $failure = ''
                try { Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar $fault }
                catch { $failure = $_.Exception.Message }
                if ($failure -notmatch "failure after $fault" -or
                    (Get-StandaloneFixtureSnapshot $fixture) -cne $before) {
                    throw "Legacy upgrade rollback failed at $($fault): $failure"
                }
            }
        }
        if ($Variant -ne 'uninstall-old') {
            Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
            $manifest = Get-Content -LiteralPath $nativeManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
            $localManifest = Get-Content -LiteralPath (Join-Path $fixture.target '.sc-install-manifest.json') `
                -Raw -Encoding utf8 | ConvertFrom-Json
            $backupInfo = Get-Content -LiteralPath (Join-Path $localManifest.backupPath 'mod.info') -Raw -Encoding utf8
            $expectedProfile = $profile.Replace('mod = \SurvivorCompanion,','mod = \LivingFellows,').
                Replace("    mod = LivingFellows,`r`n",'')
            if ($manifest.owner -cne 'LivingFellows.NativeBridge' -or
                $manifest.wrapperMainClass -cne 'livingfellows/bridge/SCLauncher' -or
                $manifest.bridgeProtocol -cne '42.22-isocompanion-38' -or
                (Test-Path -LiteralPath $legacyTarget) -or (Test-Path -LiteralPath $legacyJar) -or
                $localManifest.modId -cne 'LivingFellows' -or $localManifest.backupModId -cne 'SurvivorCompanion' -or
                $backupInfo -notmatch '(?m)^id=SurvivorCompanion\r?$' -or
                [IO.File]::ReadAllText($profilePath) -cne $expectedProfile) {
                throw 'Legacy upgrade did not publish exactly one current mod identity and preserve its previous generation.'
            }
            if ($Variant -eq 'pzo') { Assert-AgentFixture $fixture }
            if ($Variant -eq 'wrapper') {
                $before = Get-StandaloneFixtureSnapshot $fixture
                $failure = ''
                try {
                    & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
                        -InstallDataRoot $fixture.data -FailAfter 'standalone-generation-remove' | Out-Null
                } catch { $failure = $_.Exception.Message }
                if ($failure -notmatch 'failure after standalone-generation-remove' -or
                    (Get-StandaloneFixtureSnapshot $fixture) -cne $before) {
                    throw "Cross-generation uninstall rollback failed: $failure"
                }
            }
        }
        & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
            -InstallDataRoot $fixture.data | Out-Null
        if ((Test-Path -LiteralPath $fixture.target) -or (Test-Path -LiteralPath $legacyTarget) -or
            (Test-Path -LiteralPath $nativeManifestPath) -or
            (Get-FileHash -LiteralPath $fixture.config).Hash -cne $originalConfigHash -or
            [IO.File]::ReadAllText($profilePath) -match '(?im)^\s*mod\s*=\s*\\?(LivingFellows|SurvivorCompanion),' -or
            (Get-FileHash -LiteralPath $saveMods).Hash -cne $saveHash) {
            throw 'Uninstall did not fully retire the managed generations and restore the original launcher.'
        }
    }
}

'pzo-legacy-agent-upgrade' {
    $fixture = New-StandaloneFixture 'pzo-legacy-agent-upgrade'
    $foreignJar = Set-ScPzoLauncherFixture $fixture
    $foreignHash = (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash
    $originalHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    # Recreate the exact owned schema-4 launch mode shipped by .19/.20.
    $legacy = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $legacy.vmArgs += '-javaagent:LivingFellowsBridge.jar'
    $legacy | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixture.config -Encoding utf8
    $manifestPath = Join-Path $fixture.bridge 'install-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.launchMode = 'agent'
    $manifest.launcherAgentArgument = '-javaagent:LivingFellowsBridge.jar'
    $manifest.installedConfigSha256 = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    foreach ($fault in @('native-config-replace','native-manifest-write')) {
        $before = Get-InstallFixtureSnapshot $fixture
        $failed = $false
        try { Install-AgentFixture $fixture $fault }
        catch { $failed = $_.Exception.Message -like '*Injected native installer failure*' }
        if (-not $failed -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
            throw "Legacy PZO agent upgrade did not roll back exactly at $fault."
        }
    }
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    Assert-AgentFixture $fixture
    & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -InstallDataRoot $fixture.data | Out-Null
    if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $originalHash -or
        (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash -ne $foreignHash -or
        (Test-Path -LiteralPath $fixture.target)) {
        throw 'Legacy PZO agent upgrade/uninstall did not restore the original PZO state.'
    }
}

'pzo-agent-lifecycle' {
    $fixture = New-StandaloneFixture ('pzo-agent-' + $Variant)
    $foreignJar = Set-ScPzoLauncherFixture $fixture
    $foreignHash = (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash
    $originalHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    Assert-AgentFixture $fixture
    $installedHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    Assert-AgentFixture $fixture
    if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $installedHash) {
        throw 'Unchanged PZO agent update rewrote the launcher bytes.'
    }
    if ($Variant -eq 'selective') {
        $edited = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
        $edited.mainClass = 'com.pzoptimizer.PZOEntrypoint'
        $edited.classpath += @('foreign/keep', 'foreign/keep')
        $edited.vmArgs += @('-Xmx4096m', '-Xmx4096m', '-Dforeign.keep=two')
        $edited.windows.gameArguments += '-Dforeign.later=keep'
        $edited | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
        $editedHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
        Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
        if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $editedHash) {
            throw 'PZO agent update rewrote foreign ordered/duplicate launcher settings.'
        }
        $edited.classpath = @($edited.classpath | Where-Object { $_ -cne 'LivingFellowsBridge.jar' })
        $edited.vmArgs = @($edited.vmArgs | Where-Object { $_ -cne '-javaagent:LivingFellowsBridge.jar' })
    } elseif ($Variant -ne 'exact') { throw "Unknown PZO lifecycle variant: $Variant" }
    & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
        -InstallDataRoot $fixture.data | Out-Null
    $restored = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    if ($Variant -eq 'exact') {
        if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $originalHash) {
            throw 'PZO agent exact uninstall did not restore original launcher bytes.'
        }
    } elseif (($restored | ConvertTo-Json -Depth 100 -Compress) -cne
            ($edited | ConvertTo-Json -Depth 100 -Compress)) {
        throw 'PZO selective uninstall changed foreign values, order or duplicate counts.'
    }
    if ((Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash -ne $foreignHash -or
        (Test-Path -LiteralPath $fixture.target) -or
        (Test-Path -LiteralPath (Join-Path $fixture.game 'LivingFellowsBridge.jar'))) {
        throw 'PZO lifecycle changed the foreign JAR or left an owned install active.'
    }
}

'pzo-loader-reinstall' {
    $fixture = New-Fixture 'pzo-loader-reinstall'
    $foreignJar = Set-ScPzoLauncherFixture $fixture
    $foreignHash = (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash
    Install-AgentFixture $fixture
    $manifest = Get-Content -LiteralPath (Join-Path $fixture.bridge 'install-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Copy-Item -LiteralPath $manifest.originalConfigBackup -Destination $fixture.config -Force
    $restoredHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
    Install-AgentFixture $fixture
    Assert-AgentFixture $fixture
    & (Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1') -BridgeRoot $fixture.bridge | Out-Null
    if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $restoredHash -or
        (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash -ne $foreignHash) {
        throw 'A clean PZO reinstall was not recovered and restored without foreign changes.'
    }
}

'pzo-agent-recovery' {
    if ($Variant -notin @('clean', 'wrapper-migration')) { throw "Unknown PZO recovery variant: $Variant" }
    $fixture = New-Fixture ('pzo-recovery-' + $Variant)
    Install-AgentFixture $fixture
    $manifestPath = Join-Path $fixture.bridge 'install-manifest.json'
    $old = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    # Reproduce a pre-agent manifest; absent mode must still mean wrapper.
    foreach ($field in @('launchMode', 'installedMainClass', 'launcherAgentArgument')) {
        $old.PSObject.Properties.Remove($field)
    }
    $old.schemaVersion = 3
    $old | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $foreignJar = Set-ScPzoLauncherFixture $fixture
    $foreignHash = (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash
    $baseline = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $baselineHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
    if ($Variant -eq 'wrapper-migration') {
        $rewritten = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
        $rewritten.classpath += 'LivingFellowsBridge.jar'
        $rewritten | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
    }
    foreach ($fault in @('native-config-replace', 'native-manifest-write')) {
        $before = Get-InstallFixtureSnapshot $fixture
        $failed = $false
        try { Install-AgentFixture $fixture $fault }
        catch { $failed = $_.Exception.Message -like '*Injected native installer failure*' }
        if (-not $failed -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
            throw "PZO recovery/migration did not restore exact state at $fault ($Variant)."
        }
    }
    Install-AgentFixture $fixture
    Assert-AgentFixture $fixture
    $migrated = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $savedBaseline = Get-Content -LiteralPath $migrated.originalConfigBackup -Raw -Encoding utf8 | ConvertFrom-Json
    if ($migrated.originalConfigBackup -eq $old.originalConfigBackup -or
        ($savedBaseline | ConvertTo-Json -Depth 100 -Compress) -cne
            ($baseline | ConvertTo-Json -Depth 100 -Compress) -or
        (Get-FileHash -LiteralPath $migrated.originalConfigBackup -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            $migrated.originalConfigSha256) {
        throw 'PZO recovery did not preserve the rewritten original baseline minus only owned LF entries.'
    }
    & (Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1') -BridgeRoot $fixture.bridge | Out-Null
    $expectedHash = if ($Variant -eq 'clean') { $baselineHash } else { $migrated.originalConfigSha256 }
    if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $expectedHash -or
        (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash -ne $foreignHash) {
        throw 'PZO recovery/migration uninstall did not restore its verified baseline and foreign JAR.'
    }
}

'pzo-agent-rejected' {
    $unknown = New-Fixture 'pzo-unknown-main'
    Set-ScPzoLauncherFixture $unknown | Out-Null
    $config = Get-Content -LiteralPath $unknown.config -Raw -Encoding utf8 | ConvertFrom-Json
    $config.mainClass = 'other/UnknownLauncher'
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $unknown.config -Encoding utf8
    $before = Get-InstallFixtureSnapshot $unknown
    $refused = $false
    try { Install-AgentFixture $unknown }
    catch { $refused = $_.Exception.Message -match 'unknown.*mainClass' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $unknown) -ne $before) {
        throw 'Unknown launcher was not rejected before all mutation.'
    }
    $missing = New-Fixture 'pzo-missing-entry'
    $missingJar = Set-ScPzoLauncherFixture $missing
    $zip = [System.IO.Compression.ZipFile]::Open($missingJar, 'Update')
    try { $zip.GetEntry('com/pzoptimizer/PZOEntrypoint.class').Delete() }
    finally { $zip.Dispose() }
    $before = Get-InstallFixtureSnapshot $missing
    $refused = $false
    try { Install-AgentFixture $missing }
    catch { $refused = $_.Exception.Message -match 'PZO|entrypoint|main.*class' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $missing) -ne $before) {
        throw 'PZO main without its classpath entry was not rejected before mutation.'
    }
    $fixture = New-Fixture 'pzo-agent-ambiguous'
    Set-ScPzoLauncherFixture $fixture | Out-Null
    Install-AgentFixture $fixture
    Assert-AgentFixture $fixture
    $installed = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8
    foreach ($problem in @('duplicate-agent', 'nonexact-agent', 'duplicate-classpath')) {
        $config = $installed | ConvertFrom-Json
        switch ($problem) {
            'missing-agent' { $config.vmArgs = @($config.vmArgs | Where-Object { $_ -ne '-javaagent:LivingFellowsBridge.jar' }) }
            'duplicate-agent' { $config.vmArgs += '-javaagent:LivingFellowsBridge.jar' }
            'nonexact-agent' { $config.vmArgs += '-javaagent:./LivingFellowsBridge.jar' }
            'missing-classpath' { $config.classpath = @($config.classpath | Where-Object { $_ -ne 'LivingFellowsBridge.jar' }) }
            'duplicate-classpath' { $config.classpath += (Join-Path $fixture.bridge 'LivingFellowsBridge.jar').Replace('\', '/') }
        }
        $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
        $before = Get-InstallFixtureSnapshot $fixture
        foreach ($operation in @('update', 'uninstall')) {
            $refused = $false
            try {
                if ($operation -eq 'update') { Install-AgentFixture $fixture }
                else { & (Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1') -BridgeRoot $fixture.bridge -PreflightOnly | Out-Null }
            } catch { $refused = $_.Exception.Message -match 'agent|classpath' }
            if (-not $refused -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
                throw "Ambiguous PZO $problem was not rejected before mutation by $operation."
            }
        }
    }
}

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
    # Change the launcher immediately before each publish guard, without a
    # product fault hook. Refusal must retain that edit and all owned files.
    $nativeUninstall = Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1'
    foreach ($operation in @(
            @{ script = $NativeInstall; guard = 'if ((Get-HashOrEmpty $configPath) -ne $configHashAtStart)' },
            @{ script = $nativeUninstall; guard = 'if ((Get-HashOrEmpty $configPath) -ne $configHash)' })) {
        $before = Get-InstallFixtureSnapshot $nativeFixture
        $priorBytes = [System.IO.File]::ReadAllBytes($nativeFixture.config)
        $racedBytes = [byte[]]($priorBytes + [byte]32)
        $guard = @(Select-String -LiteralPath $operation.script -SimpleMatch $operation.guard)
        if ($guard.Count -ne 1) { throw 'Native prepublish guard is missing or ambiguous.' }
        $breakpoint = Set-PSBreakpoint -Script $operation.script -Line $guard[0].LineNumber -Action {
            [System.IO.File]::AppendAllText($configPath, ' ')
        }
        $refused = $false
        try {
            if ($operation.script -eq $NativeInstall) {
                & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $nativeFixture.game `
                    -BridgeRoot $nativeFixture.bridge -ConfigBackupRoot $nativeFixture.configBackups `
                    -PrebuiltBridgeJar $PrebuiltJar | Out-Null
            } else { & $nativeUninstall -BridgeRoot $nativeFixture.bridge | Out-Null }
        } catch { $refused = $_.Exception.Message -like '*Launcher configuration changed during*' }
        finally { Remove-PSBreakpoint -Breakpoint $breakpoint }
        if (-not $refused -or
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($nativeFixture.config)) -cne
            [Convert]::ToBase64String($racedBytes)) {
            throw "Native prepublish refusal overwrote a concurrent launcher edit: $($operation.script)"
        }
        [System.IO.File]::WriteAllBytes($nativeFixture.config, $priorBytes)
        if ((Get-InstallFixtureSnapshot $nativeFixture) -ne $before) {
            throw "Native prepublish refusal changed owned files: $($operation.script)"
        }
    }
}

'schema2-migration' {
    $fixture = New-Fixture 'schema2-migration'
    $originalHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant()
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
        -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    $manifestPath = Join-Path $fixture.bridge 'install-manifest.json'
    $gameJar = Join-Path $fixture.game 'LivingFellowsBridge.jar'
    $legacyJar = (Join-Path $fixture.bridge 'LivingFellowsBridge.jar').Replace('\', '/')
    $config = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $config.classpath = @($config.classpath | ForEach-Object {
        if ($_ -eq 'LivingFellowsBridge.jar') { $legacyJar } else { $_ }
    })
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
    Remove-Item -LiteralPath $gameJar -Force
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($field in @('launcherJar', 'launcherJarSha256', 'launcherClasspathEntry',
            'launchMode', 'installedMainClass', 'launcherAgentArgument')) {
        $manifest.PSObject.Properties.Remove($field)
    }
    $manifest.schemaVersion = 2
    $manifest.installedConfigSha256 =
        (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
        -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    $updated = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $updatedManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    if ($updated.classpath -notcontains 'LivingFellowsBridge.jar' -or
        $updated.classpath -contains $legacyJar -or
        $updatedManifest.schemaVersion -ne 4 -or
        $updatedManifest.launchMode -ne 'wrapper' -or
        $updatedManifest.installedMainClass -ne 'livingfellows/bridge/SCLauncher' -or
        [string]$updatedManifest.launcherAgentArgument -ne '' -or
        (Get-FileHash -LiteralPath $gameJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            [string]$updatedManifest.launcherJarSha256) {
        throw 'Schema 2 launcher did not migrate to an owned relative JAR.'
    }
    & (Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1') `
        -BridgeRoot $fixture.bridge | Out-Null
    if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            $originalHash -or (Test-Path -LiteralPath $gameJar)) {
        throw 'Migrated launcher did not uninstall to its original state.'
    }
}

'unmanaged-game-jar' {
    $fixture = New-Fixture 'unmanaged-game-jar'
    Set-Content -LiteralPath (Join-Path $fixture.game 'LivingFellowsBridge.jar') `
        -Value 'unrelated file' -Encoding utf8
    $before = Get-InstallFixtureSnapshot $fixture
    $refused = $false
    try {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
            -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
            -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    } catch { $refused = $_.Exception.Message -like '*Unmanaged game-local launcher JAR*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
        throw 'Installer changed an unmanaged game-local JAR.'
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
    if ($Variant -eq 'missing') {
        $refused = $false
        try {
            & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
                -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
                -PrebuiltBridgeJar $PrebuiltJar | Out-Null
        } catch {
            $refused = $_.Exception.Message -like '*installedConfigSha256*refusing update*'
        }
        if (-not $refused -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
            throw 'Native update accepted or mutated a missing installedConfigSha256 fixture.'
        }
    } else {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
            -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
            -PrebuiltBridgeJar $PrebuiltJar | Out-Null
        $updated = Get-Content -LiteralPath $ownedManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
        $currentHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($updated.installedConfigSha256 -ne $currentHash) {
            throw 'Native update did not refresh a stale launcher hash after verifying ownership.'
        }
    }
}

'shared-launcher' {
    $originalWithAgent = (Get-ScOriginalLauncherConfig | ConvertFrom-Json)
    $originalWithAgent.vmArgs += '-agentlib:zbNative'
    $fixture = New-StandaloneInstallFixture $Sandbox ('shared-launcher-' + $Variant) `
        ($originalWithAgent | ConvertTo-Json -Depth 12)
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    $shared = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $shared.classpath += 'pzopt/aot/pzopt.jar'
    $shared.vmArgs += @('-XX:+UseZGC', '-Xmx4096m')
    $shared | Add-Member -NotePropertyName windows -NotePropertyValue ([pscustomobject]@{
        gameArguments = @('-Dforeign.option=keep')
    })
    $shared | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
    $sharedHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Variant -eq 'update') {
        Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
        if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sharedHash) {
            throw 'Standalone update rewrote a launcher edited by another mod.'
        }
    }
    & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
        -InstallDataRoot $fixture.data | Out-Null
    $restored = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $ownedJar = (Join-Path $fixture.bridge 'LivingFellowsBridge.jar').Replace('\', '/')
    if ($restored.mainClass -ne 'zombie/gameStates/MainScreenState' -or
        @($restored.classpath | Where-Object { ([string]$_).Replace('\', '/') -eq $ownedJar }).Count -ne 0 -or
        $restored.classpath -notcontains 'pzopt/aot/pzopt.jar' -or
        $restored.vmArgs -notcontains '-agentlib:zbNative' -or
        $restored.vmArgs -notcontains '-XX:+UseZGC' -or
        $restored.vmArgs -notcontains '-Xmx4096m' -or
        $restored.windows.gameArguments -notcontains '-Dforeign.option=keep') {
        throw 'Selective standalone uninstall did not preserve other launcher settings.'
    }
}

'shared-launcher-ambiguous' {
    $fixture = New-StandaloneFixture 'shared-launcher-ambiguous'
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    $config = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    $config.classpath += $config.classpath[-1]
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
    $before = Get-StandaloneFixtureSnapshot $fixture
    $refused = $false
    try {
        & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
            -InstallDataRoot $fixture.data | Out-Null
    } catch { $refused = $_.Exception.Message -like '*classpath ownership is missing or duplicated*' }
    if (-not $refused -or (Get-StandaloneFixtureSnapshot $fixture) -ne $before) {
        throw 'Ambiguous launcher ownership was not refused before standalone mutation.'
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
    $brokenConfig.mainClass = 'livingfellows/bridge/SCLauncher'
    $brokenConfig.classpath += (Join-Path $manifestless.bridge 'LivingFellowsBridge.jar').Replace('\', '/')
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

'game-reinstall-recovery' {
    $fixture = New-Fixture 'game-reinstall-recovery'
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
        -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    $manifestPath = Join-Path $fixture.bridge 'install-manifest.json'
    $previous = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    # Steam restores only the game launcher during reinstall; LocalAppData
    # still contains our manifest and bridge JAR.
    Set-Content -LiteralPath $fixture.config -Value $originalConfig -Encoding utf8
    $vanillaHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant()
    $before = Get-InstallFixtureSnapshot $fixture
    $failed = $false
    try {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
            -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
            -PrebuiltBridgeJar $PrebuiltJar -FailAfter 'native-config-replace' | Out-Null
    } catch { $failed = $_.Exception.Message -like '*Injected native installer failure*' }
    if (-not $failed -or (Get-InstallFixtureSnapshot $fixture) -ne $before) {
        throw 'Game-reinstall recovery did not roll back exactly on install failure.'
    }
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $fixture.game `
        -BridgeRoot $fixture.bridge -ConfigBackupRoot $fixture.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    $recovered = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    if ($recovered.originalConfigBackup -eq $previous.originalConfigBackup -or
        $recovered.originalConfigSha256 -ne $vanillaHash -or
        $recovered.originalMainClass -ne 'zombie/gameStates/MainScreenState' -or
        (Get-FileHash -LiteralPath $recovered.originalConfigBackup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $vanillaHash) {
        throw 'Game-reinstall recovery did not preserve the new vanilla launcher.'
    }
    & (Join-Path $ProjectRoot 'scripts\Uninstall-NativeBridge.ps1') `
        -BridgeRoot $fixture.bridge | Out-Null
    if ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash.ToLowerInvariant() -ne $vanillaHash) {
        throw 'Game-reinstall recovery could not restore the new vanilla launcher.'
    }

    $mixed = New-Fixture 'game-reinstall-mixed-launcher'
    & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $mixed.game `
        -BridgeRoot $mixed.bridge -ConfigBackupRoot $mixed.configBackups `
        -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    $mixedConfig = Get-Content -LiteralPath $mixed.config -Raw -Encoding utf8 |
        ConvertFrom-Json
    $mixedConfig.mainClass = 'zombie/gameStates/MainScreenState'
    $mixedConfig.classpath = @($mixedConfig.classpath | ForEach-Object {
        ([string]$_).Replace('/', '\')
    })
    $mixedConfig | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $mixed.config -Encoding utf8
    $mixedBefore = Get-InstallFixtureSnapshot $mixed
    $refused = $false
    try {
        & $NativeInstall -ProjectRoot $ProjectRoot -GameRoot $mixed.game `
            -BridgeRoot $mixed.bridge -ConfigBackupRoot $mixed.configBackups `
            -PrebuiltBridgeJar $PrebuiltJar | Out-Null
    } catch { $refused = $_.Exception.Message -like '*launcher is not clean*' }
    if (-not $refused -or (Get-InstallFixtureSnapshot $mixed) -ne $mixedBefore) {
        throw 'Game-reinstall recovery accepted an ambiguous launcher classpath.'
    }

    $standalone = New-StandaloneFixture 'standalone-game-reinstall'
    Install-StandaloneFixture $ProjectRoot $standalone $StandalonePreparedPayload $PrebuiltJar
    Set-Content -LiteralPath $standalone.config -Value $originalConfig -Encoding utf8
    $standaloneVanillaHash = (Get-FileHash -LiteralPath $standalone.config -Algorithm SHA256).Hash.ToLowerInvariant()
    Install-StandaloneFixture $ProjectRoot $standalone $StandalonePreparedPayload $PrebuiltJar
    & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $standalone.mods `
        -InstallDataRoot $standalone.data | Out-Null
    if ((Get-FileHash -LiteralPath $standalone.config -Algorithm SHA256).Hash.ToLowerInvariant() -ne $standaloneVanillaHash -or
        (Test-Path -LiteralPath $standalone.target)) {
        throw 'Standalone update after game reinstall did not uninstall cleanly.'
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
            $writer.Write("Manifest-Version: 1.0`r`nMain-Class: livingfellows.bridge.SCLauncher`r`nSC-Bridge-Protocol: stale`r`nSC-Supported-Game-Version: 42.20`r`nSC-Compiled-Game-Version: 42.20.4`r`n`r`n")
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

'damaged-mod-info' {
    # Missing or edited metadata is repairable when the payload verifies
    # ownership. Foreign replacements and conflicting Living Fellows IDs refuse.
    $damaged = if ($Variant -eq 'local') { New-Fixture 'damaged-mod-info-local' }
        else { New-StandaloneFixture ('damaged-mod-info-' + $Variant) }
    $installDamaged = {
        if ($Variant -eq 'local') {
            & $Install -ProjectRoot $ProjectRoot -ModsRoot $damaged.mods -GameRoot $damaged.game `
                -BackupRoot $damaged.backups -BridgeRoot $damaged.bridge `
                -ConfigBackupRoot $damaged.configBackups -PreparedPayloadRoot $PreparedPayload `
                -NativeBridge | Out-Null
        } else {
            Install-StandaloneFixture $ProjectRoot $damaged $StandalonePreparedPayload $PrebuiltJar
        }
    }
    $uninstallDamaged = {
        param([switch]$Force)
        if ($Variant -eq 'local') { & $Uninstall -ModsRoot $damaged.mods -Force:$Force | Out-Null }
        else {
            & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $damaged.mods `
                -InstallDataRoot $damaged.data -Force:$Force | Out-Null
        }
    }
    $snapshot = {
        if ($Variant -eq 'local') { Get-InstallFixtureSnapshot $damaged }
        else { Get-StandaloneFixtureSnapshot $damaged }
    }
    $originalConfigHash = (Get-FileHash -LiteralPath $damaged.config).Hash
    & $installDamaged
    $info = Join-Path $damaged.target 'mod.info'
    $versionedInfo = Join-Path $damaged.target '42\mod.info'
    $infoText = [IO.File]::ReadAllText($info)
    $refusalPattern = 'mod\.info names a different mod ID'
    if ($Variant -eq 'conflict') {
        [IO.File]::WriteAllText($info, $infoText.Replace('id=LivingFellows', 'id=SurvivorCompanion'))
    } elseif ($Variant -eq 'duplicate-id-conflict') {
        [IO.File]::AppendAllText($info, "`r`nid=SurvivorCompanion`r`n")
    } elseif ($Variant -eq 'versioned-id-conflict') {
        $versionedText = [IO.File]::ReadAllText($versionedInfo)
        [IO.File]::WriteAllText($versionedInfo, $versionedText.Replace('id=LivingFellows', 'id=SurvivorCompanion'))
    } elseif ($Variant -eq 'repeated-id-prefix-conflict') {
        $versionedText = [IO.File]::ReadAllText($versionedInfo)
        [IO.File]::WriteAllText($versionedInfo, $versionedText.Replace('id=LivingFellows', 'id=Survivorid=Companion'))
    } elseif ($Variant -eq 'version-directory-id-conflict') {
        $specificVersion = Join-Path $damaged.target '42.22'
        New-Item -ItemType Directory -Path $specificVersion | Out-Null
        [IO.File]::WriteAllText((Join-Path $specificVersion 'mod.info'),
            $infoText.Replace('id=LivingFellows', 'id=SurvivorCompanion'))
    } elseif ($Variant -eq 'foreign-replacement') {
        $original = Join-Path $damaged.root 'previous-owned-copy'
        Move-Item -LiteralPath $damaged.target -Destination $original
        $foreignScripts = Join-Path $damaged.target '42\media\lua\client'
        New-Item -ItemType Directory -Path $foreignScripts -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $original '.sc-install-manifest.json') -Destination $damaged.target
        Copy-Item -LiteralPath (Join-Path $original 'LICENSE.txt') -Destination $damaged.target
        [IO.File]::WriteAllText($info, "name=Different Mod`r`nid=DifferentMod`r`n")
        [IO.File]::WriteAllText($versionedInfo, [IO.File]::ReadAllText($info))
        [IO.File]::WriteAllText((Join-Path $foreignScripts 'DifferentMod.lua'), 'DifferentMod = {}')
        $refusalPattern = 'metadata and payload do not verify ownership'
    } elseif ($Variant -eq 'edited') {
        [IO.File]::WriteAllText($info, $infoText.Replace('id=LivingFellows', 'id=MyRenamedCopy'))
        $refusalPattern = ''
    } elseif ($Variant -in @('missing', 'local')) {
        Remove-Item -LiteralPath $info
        $refusalPattern = ''
    } else { throw "Unknown damaged-mod-info variant: $Variant" }
    $before = & $snapshot

    if ($refusalPattern) {
        foreach ($operation in @(
            { & $uninstallDamaged -Force },
            $installDamaged,
            { & $Uninstall -ModsRoot $damaged.mods -Force | Out-Null }
        )) {
            $refusal = ''
            try { & $operation } catch { $refusal = $_.Exception.Message }
            if ($refusal -notmatch $refusalPattern -or (& $snapshot) -cne $before) {
                throw "Damaged metadata case '$Variant' was not refused before mutation: $refusal"
            }
        }
    } else {
        $refusal = ''
        try { & $uninstallDamaged } catch { $refusal = $_.Exception.Message }
        if ($refusal -notmatch 'changed or (were added|is missing)' -or (& $snapshot) -cne $before) {
            throw "A damaged generation was removed without -Force or for the wrong reason: $refusal"
        }
        & $installDamaged
        if ([IO.File]::ReadAllText($info) -notmatch '(?m)^id=LivingFellows\r?$') {
            throw 'Reinstalling did not repair the damaged generation.'
        }
        if ($Variant -eq 'local') {
            # The intact newest generation goes and the damaged one returns as the
            # live mod, so the final -Force below removes a damaged live target.
            & $uninstallDamaged
            if (-not (Test-Path -LiteralPath $damaged.target) -or (Test-Path -LiteralPath $info)) {
                throw 'Local uninstall did not restore the damaged previous generation.'
            }
        } else {
            $before = & $snapshot
            $refusal = ''
            try { & $uninstallDamaged } catch { $refusal = $_.Exception.Message }
            if ($refusal -notmatch 'changed or is missing' -or (& $snapshot) -cne $before) {
                throw "A damaged backup generation was removed without -Force: $refusal"
            }
        }
        & $uninstallDamaged -Force
        if ((Test-Path -LiteralPath $damaged.target) -or
            (Test-Path -LiteralPath (Join-Path $damaged.mods 'SurvivorCompanion')) -or
            (Test-Path -LiteralPath (Join-Path $damaged.bridge 'install-manifest.json')) -or
            @(Get-ChildItem -LiteralPath $damaged.backups -Directory -ErrorAction SilentlyContinue).Count -ne 0 -or
            (Get-FileHash -LiteralPath $damaged.config).Hash -cne $originalConfigHash) {
            throw 'Uninstall -Force did not remove every damaged generation and restore the launcher.'
        }
    }
}

'invalid-staged-mod-id' {
    $fixture = New-StandaloneFixture ('invalid-staged-mod-id-' + $Variant)
    $relative = switch ($Variant) {
        'wrong-root' { 'mod.info' }
        'version-directory-override' { '42.22\mod.info' }
        default { '42\mod.info' }
    }
    # Exercise both fresh installation and update of an intact installation.
    if ($Variant -ne 'wrong-root') {
        Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    }
    $prepared = Join-Path $fixture.root 'invalid-payload'
    Copy-Item -LiteralPath $StandalonePreparedPayload -Destination $prepared -Recurse
    $path = Join-Path $prepared $relative
    $expectedError = 'Install payload mod\.info must declare exactly one id=LivingFellows'
    if ($Variant -eq 'version-directory-override') {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) | Out-Null
        Copy-Item -LiteralPath (Join-Path $prepared '42\mod.info') -Destination $path
        $expectedError = 'Install payload mod\.info uses an unexpected version directory'
    }
    $info = [IO.File]::ReadAllText($path)
    if ($Variant -eq 'duplicate-versioned') {
        [IO.File]::AppendAllText($path, "`r`nid=LivingFellows`r`n")
    } elseif ($Variant -eq 'space-before-equals') {
        [IO.File]::WriteAllText($path, $info.Replace('id=LivingFellows', 'id =LivingFellows'))
    } elseif ($Variant -eq 'indented-key') {
        [IO.File]::WriteAllText($path, $info.Replace('id=LivingFellows', ' id=LivingFellows'))
    } elseif ($Variant -eq 'utf8-bom-id') {
        $firstId = "id=LivingFellows`r`n" + [regex]::Replace($info, '(?m)^id=LivingFellows\r?$', '')
        [IO.File]::WriteAllText($path, $firstId, [Text.UTF8Encoding]::new($true))
    } elseif ($Variant -eq 'utf16-metadata') {
        [IO.File]::WriteAllText($path, $info, [Text.Encoding]::Unicode)
    } else {
        [IO.File]::WriteAllText($path, $info.Replace('id=LivingFellows', 'id=DifferentMod'))
    }

    $before = Get-StandaloneFixtureSnapshot $fixture
    $refusal = ''
    try {
        Install-StandaloneFixture $ProjectRoot $fixture $prepared $PrebuiltJar 'native-config-stage'
    } catch { $refusal = $_.Exception.Message }
    if ($refusal -notmatch $expectedError -or
        -not $refusal.EndsWith("\$relative") -or
        (Get-StandaloneFixtureSnapshot $fixture) -cne $before) {
        throw "Invalid payload ID '$Variant' was not refused before launcher work: $refusal"
    }
}

'uninstall-after-game-repair' {
    # Steam's file check, a game update or another launcher can rewrite the
    # launcher after Living Fellows was installed. Uninstall must still remove
    # everything of ours and leave everything else exactly as it is.
    $fixture = New-StandaloneFixture ('uninstall-after-repair-' + $Variant)
    $profilePath = Join-Path $fixture.mods 'default.txt'
    $profileBefore = "VERSION = 1,`r`n`r`nmods`r`n{`r`n    mod = KeepThisMod,`r`n}`r`n`r`nmaps`r`n{`r`n}`r`n"
    $existingProfile = if ($Variant -eq 'steam-check') {
        $profileBefore.Replace('    mod = KeepThisMod,', "    mod = \LivingFellows,`r`n    mod = KeepThisMod,")
    } else { $profileBefore }
    [System.IO.File]::WriteAllText($profilePath, $existingProfile,
        (New-Object System.Text.UTF8Encoding($false)))
    $foreignJar = ''
    if ($Variant -eq 'pzo-steam-check') { $foreignJar = Set-ScPzoLauncherFixture $fixture }
    $foreignHash = if ($foreignJar) {
        (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash
    } else { '' }
    Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
    $gameJar = Join-Path $fixture.game 'LivingFellowsBridge.jar'
    $bridgeManifest = Join-Path $fixture.bridge 'install-manifest.json'
    $profileAfterInstall = Get-Content -LiteralPath $profilePath -Raw -Encoding utf8
    if (-not (Test-Path -LiteralPath $gameJar -PathType Leaf) -or
        $profileAfterInstall -notmatch '(?m)^\s*mod = \\?LivingFellows,') {
        throw 'Repair fixture install did not place the bridge and enable the mod.'
    }
    if ($Variant -eq 'steam-check' -and $profileAfterInstall -cne $existingProfile) {
        throw 'Install added a duplicate entry beside the existing backslash-prefixed mod id.'
    }
    if ($Variant -in @('steam-check', 'pzo-steam-check')) {
        # Steam restores its own launcher and leaves extra files such as our JAR.
        Set-Content -LiteralPath $fixture.config -Value $originalConfig -Encoding utf8
    } elseif ($Variant -eq 'pzo-takeover') {
        # PZO replaces the main class but keeps the classpath entries it found.
        $taken = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
        $taken.mainClass = 'com/pzoptimizer/PZOEntrypoint'
        $taken.classpath += 'pzoptimizer.jar'
        $taken.vmArgs += '-Dforeign.keep=one'
        $taken | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
    } else { throw "Unknown repair variant: $Variant" }
    $repairedHash = (Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash
    $output = (@(& $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
        -InstallDataRoot $fixture.data 3>&1) | ForEach-Object { [string]$_ }) -join "`n"
    if ((Test-Path -LiteralPath $fixture.target) -or (Test-Path -LiteralPath $gameJar) -or
        (Test-Path -LiteralPath $bridgeManifest)) {
        throw "Uninstall after a launcher repair ($Variant) left Living Fellows files behind."
    }
    if ((Get-Content -LiteralPath $profilePath -Raw -Encoding utf8) -cne $profileBefore) {
        throw "Uninstall after a launcher repair ($Variant) did not restore the default mod list exactly."
    }
    if ($foreignJar -and (Get-FileHash -LiteralPath $foreignJar -Algorithm SHA256).Hash -ne $foreignHash) {
        throw 'Uninstall after a launcher repair changed the PZO JAR.'
    }
    $after = Get-Content -LiteralPath $fixture.config -Raw -Encoding utf8 | ConvertFrom-Json
    if ($Variant -eq 'pzo-takeover') {
        if ($after.mainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or
            $after.classpath -contains 'LivingFellowsBridge.jar' -or
            $after.classpath -notcontains 'pzoptimizer.jar' -or
            $after.vmArgs -notcontains '-Dforeign.keep=one') {
            throw 'Uninstall after a PZO takeover did not remove only the Living Fellows classpath entry.'
        }
    } elseif ((Get-FileHash -LiteralPath $fixture.config -Algorithm SHA256).Hash -ne $repairedHash -or
        $output -notmatch 'left unchanged') {
        throw "Uninstall rewrote a launcher that no longer used Living Fellows ($Variant)."
    }
}

'uninstall-after-repair-ambiguous' {
    # A launcher still holding some Living Fellows entry next to a host main
    # class is not one the uninstaller can read safely; it must refuse untouched.
    foreach ($shape in @('duplicate-classpath', 'stray-agent')) {
        $fixture = New-StandaloneFixture ('uninstall-repair-ambiguous-' + $shape)
        Install-StandaloneFixture $ProjectRoot $fixture $StandalonePreparedPayload $PrebuiltJar
        $config = $originalConfig | ConvertFrom-Json
        if ($shape -eq 'duplicate-classpath') {
            $config.classpath += @('LivingFellowsBridge.jar', 'LivingFellowsBridge.jar')
        } else {
            $config.vmArgs += '-javaagent:LivingFellowsBridge.jar'
        }
        $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.config -Encoding utf8
        $before = Get-StandaloneFixtureSnapshot $fixture
        $refused = $false
        try {
            & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
                -InstallDataRoot $fixture.data | Out-Null
        } catch { $refused = $_.Exception.Message -like '*refusing automatic rollback*' }
        if (-not $refused -or (Get-StandaloneFixtureSnapshot $fixture) -ne $before) {
            throw "Ambiguous repaired launcher ($shape) was not refused before any change."
        }
    }
}

'other-copies' {
    # The Steam Workshop edition and an upload staging folder share the mod id.
    # Install and uninstall name them so a player knows what still loads; they
    # never touch them.
    $root = Join-Path $Sandbox 'other-copies'
    $steamapps = Join-Path $root 'library\steamapps'
    $zomboid = Join-Path $root 'Zomboid'
    $data = Join-Path $root 'install-data'
    $fixture = [ordered]@{
        root = $root; mods = (Join-Path $zomboid 'mods')
        game = (Join-Path $steamapps 'common\ProjectZomboid'); data = $data
        backups = (Join-Path $data 'mod-backups'); bridge = (Join-Path $data 'bridge')
        configBackups = (Join-Path $data 'config-backups')
    }
    $fixture.config = Join-Path $fixture.game 'ProjectZomboid64.json'
    $fixture.target = Join-Path $fixture.mods 'LivingFellows'
    New-Item -ItemType Directory -Path $fixture.mods, $fixture.game, $fixture.backups,
        $fixture.configBackups -Force | Out-Null
    Set-Content -LiteralPath $fixture.config -Value $originalConfig -Encoding utf8
    function Get-CaseText([scriptblock]$Action) {
        return (@(& $Action 3>&1) | ForEach-Object {
            if ($_ -is [System.Management.Automation.WarningRecord]) { $_.Message } else { [string]$_ }
        }) -join "`n"
    }
    function Test-Mentions([string]$Text, [string]$Path) {
        return $Text.IndexOf($Path, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }
    $runInstall = {
        & $Install -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods -GameRoot $fixture.game `
            -BackupRoot $fixture.backups -BridgeRoot $fixture.bridge `
            -ConfigBackupRoot $fixture.configBackups -PreparedPayloadRoot $StandalonePreparedPayload `
            -PrebuiltBridgeJar $PrebuiltJar -Standalone
    }
    $runUninstall = {
        & $StandaloneUninstall -ProjectRoot $ProjectRoot -ModsRoot $fixture.mods `
            -InstallDataRoot $fixture.data
    }
    $quiet = Get-CaseText $runInstall
    if ($quiet -match 'Another copy of Living Fellows') {
        throw 'Installer warned about another copy when there was none.'
    }
    $workshopItem = Join-Path $steamapps 'workshop\content\108600\3805760339'
    $stagingCopy = Join-Path $zomboid 'Workshop\LivingFellowsCompanion\Contents\mods\LivingFellows'
    New-Item -ItemType Directory -Path (Join-Path $workshopItem 'mods\LivingFellows'),
        $stagingCopy -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $workshopItem 'mods\LivingFellows\mod.info') `
        -Value 'id=LivingFellows' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $stagingCopy 'mod.info') -Value 'id=LivingFellows' -Encoding utf8
    # Steam's record no longer lists the item: a leftover folder the game does
    # not load. The upload staging copy does load first, so it is named.
    $record = Join-Path $steamapps 'workshop\appworkshop_108600.acf'
    Set-Content -LiteralPath $record -Encoding utf8 -Value `
        "`"AppWorkshop`"`n{`n`t`"WorkshopItemsInstalled`"`n`t{`n`t`t`"515555911`"`n`t`t{`n`t`t}`n`t}`n}"
    $copiesBefore = Get-TreeSnapshot @{ workshop = $workshopItem; staging = $stagingCopy }
    $installText = Get-CaseText $runInstall
    if ($installText -match 'subscribed' -or (Test-Mentions $installText $workshopItem) -or
        -not (Test-Mentions $installText $stagingCopy)) {
        throw 'Installer misjudged a leftover Workshop folder or missed the upload staging copy.'
    }
    $profilePath = Join-Path $fixture.mods 'default.txt'
    function Assert-WorkshopRefusal([string]$Location) {
        $before = (Get-StandaloneFixtureSnapshot $fixture) + (Get-FileHash -LiteralPath $profilePath).Hash
        $refusal = ''
        try { Get-CaseText $runInstall | Out-Null } catch { $refusal = $_.Exception.Message }
        if ($refusal -notlike '*Steam still lists or has a Living Fellows Workshop copy*' -or
            -not (Test-Mentions $refusal $Location) -or
            -not (Test-Mentions $refusal 'filedetails/?id=3805760339') -or
            -not (Test-Mentions $refusal 'Nothing was changed') -or
            ((Get-StandaloneFixtureSnapshot $fixture) + (Get-FileHash -LiteralPath $profilePath).Hash) -ne $before) {
            throw "Workshop copy at $Location was not refused before any change: $refusal"
        }
    }
    $unlisted = Get-Content -LiteralPath $record -Raw -Encoding utf8
    $listed = $unlisted.Replace('515555911', '3805760339')
    [IO.File]::WriteAllText($record, $listed)
    Assert-WorkshopRefusal $workshopItem
    [IO.File]::WriteAllText($record, $unlisted)

    $otherLibrary = Join-Path $root 'secondary library'
    $otherWorkshop = Join-Path $otherLibrary 'steamapps\workshop'
    $otherRecord = Join-Path $otherWorkshop 'appworkshop_108600.acf'
    $otherItem = Join-Path $otherWorkshop 'content\108600\3805760339'
    New-Item -ItemType Directory -Path $otherWorkshop -Force | Out-Null
    $libraries = Join-Path $steamapps 'libraryfolders.vdf'
    [IO.File]::WriteAllLines($libraries, [string[]]@('"libraryfolders"', '{', '"1"', '{',
        ('"path" "' + $otherLibrary.Replace('\', '\\') + '"'), '}', '}'))
    $pending = $listed.Replace('WorkshopItemsInstalled', 'WorkshopItemDetails')
    [IO.File]::WriteAllText($otherRecord, $pending)
    Assert-WorkshopRefusal $otherItem
    New-Item -ItemType Directory -Path (Join-Path $otherItem 'mods\LivingFellows') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $otherItem 'mods\LivingFellows\mod.info') `
        -Value 'id=LivingFellows' -Encoding utf8
    [IO.File]::WriteAllText($otherRecord, $listed)
    Assert-WorkshopRefusal $otherItem
    $otherBefore = Get-TreeSnapshot @{ workshop = $otherItem; record = $otherRecord }

    # Subscribing after installing standalone: uninstall still finishes and
    # names everything that keeps loading.
    $uninstallText = Get-CaseText $runUninstall
    if (-not (Test-Mentions $uninstallText $otherItem) -or (Test-Mentions $uninstallText $workshopItem) -or
        -not (Test-Mentions $uninstallText $stagingCopy) -or
        (Test-Path -LiteralPath $fixture.target)) {
        throw 'Uninstall did not finish or did not name the copies that still load.'
    }
    $again = Get-CaseText $runUninstall
    if ($again -notmatch 'nothing was removed' -or -not (Test-Mentions $again $stagingCopy)) {
        throw 'A second uninstall run did not report a clean state and the remaining copy.'
    }
    if ((Get-TreeSnapshot @{ workshop = $workshopItem; staging = $stagingCopy }) -ne $copiesBefore -or
        (Get-TreeSnapshot @{ workshop = $otherItem; record = $otherRecord }) -ne $otherBefore) {
        throw 'Install or uninstall changed another copy of Living Fellows.'
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
