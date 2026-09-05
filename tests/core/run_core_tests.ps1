# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Payload = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua'
$Client = Join-Path $Payload 'client'
$Shared = Join-Path $Payload 'shared'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sc-core-tests-' + [guid]::NewGuid().ToString('N'))
$NativeJar = Join-Path $ProjectRoot 'build\native-bridge\SurvivorCompanionBridge.jar'
$NativeClasses = Join-Path $ProjectRoot 'build\native-bridge\classes'

$jarMissing = -not (Test-Path -LiteralPath $Jar -PathType Leaf)
$runtimeMissing = -not (Test-Path -LiteralPath $GameJava -PathType Leaf)
if ($jarMissing -or $runtimeMissing) {
    throw "Project Zomboid 42.20.4 runtime not found under $GameRoot"
}

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') `
        -ProjectRoot $ProjectRoot -InstallIntoPayload | Out-Null
    if (-not (Test-Path -LiteralPath $NativeJar -PathType Leaf)) {
        throw 'Native bridge build gate did not produce its JAR.'
    }
    & $Javac -cp $NativeClasses -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java') `
        (Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java') `
        (Join-Path $TestRoot 'SCNativeApiSignatureTest.java') `
        (Join-Path $TestRoot 'SCAnimationContractTest.java') `
        (Join-Path $TestRoot 'SCItemContainerContractTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCKahluaExposureTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCDeferredMainThreadQueueTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCIsoPlayerControlTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCIsoCompanionControlTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCNativeCleanupTransactionTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCNativeBridgeExposureTest.java')
    if ($LASTEXITCODE -ne 0) { throw 'Core Java test harness compilation failed.' }

    $allLua = @(Get-ChildItem -LiteralPath $Payload -Recurse -Filter '*.lua' -File | Sort-Object FullName | ForEach-Object FullName)
    & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler @allLua
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua compilation gate failed.' }

    $coreFiles = @(
        (Join-Path $TestRoot 'core_fixture.lua'),
        (Join-Path $Shared 'SCNamespace.lua'),
        (Join-Path $Shared 'SCCall.lua'),
        (Join-Path $Shared 'SCStableValue.lua'),
        (Join-Path $Shared 'SCTransaction.lua'),
        (Join-Path $Shared 'SCNativeList.lua'),
        (Join-Path $Shared 'SCConfig.lua'),
        (Join-Path $Shared 'SCDiagnostics.lua'),
        (Join-Path $Shared 'SCNet.lua'),
        (Join-Path $Shared 'SCRegistry.lua'),
        (Join-Path $Shared 'SCVitals.lua'),
        (Join-Path $Client 'SCNativeActions.lua'),
        (Join-Path $Client 'SCActionSupervisor.lua'),
        (Join-Path $Client 'SCBackground.lua'),
        (Join-Path $Client 'SCActor.lua'),
        (Join-Path $Client 'SCVehicle.lua'),
        (Join-Path $Client 'SCPerformance.lua'),
        (Join-Path $Client 'SCScheduler.lua'),
        (Join-Path $Client 'SCPersistence.lua'),
        (Join-Path $Client 'SCGameplayUtil.lua'),
        (Join-Path $Client 'SCLocomotion.lua'),
        (Join-Path $Client 'SCPersonality.lua'),
        (Join-Path $Client 'SCPersonalItems.lua'),
        (Join-Path $Client 'SCRelationship.lua'),
        (Join-Path $Client 'SCObjectives.lua'),
        (Join-Path $Client 'SCJournal.lua'),
        (Join-Path $Client 'SCCommands.lua'),
        (Join-Path $Client 'SCCombat.lua'),
        (Join-Path $Client 'SCSupport.lua'),
        (Join-Path $TestRoot 'action_supervisor_harness.lua'),
        (Join-Path $TestRoot 'core_harness.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @coreFiles
        if ($LASTEXITCODE -ne 0) { throw 'Core Kahlua integration harness failed.' }

        $actorOwnershipFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $Shared 'SCTransaction.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Shared 'SCDiagnostics.lua'),
            (Join-Path $Shared 'SCRegistry.lua'),
            (Join-Path $Client 'SCNativeActions.lua'),
            (Join-Path $Client 'SCActionSupervisor.lua'),
            (Join-Path $Client 'SCBackground.lua'),
            (Join-Path $Client 'SCActor.lua'),
            (Join-Path $TestRoot 'actor_ownership_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @actorOwnershipFiles
        if ($LASTEXITCODE -ne 0) { throw 'Lua/native actor ownership harness failed.' }

        $supervisorSoakFiles = @($coreFiles | Select-Object -SkipLast 2)
        $supervisorSoakFiles += Join-Path $TestRoot 'supervisor_fault_soak_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @supervisorSoakFiles
        if ($LASTEXITCODE -ne 0) { throw 'Action-supervisor fault/soak harness failed.' }

        $performanceFiles = @($coreFiles | Select-Object -SkipLast 1)
        $performanceFiles += Join-Path $TestRoot 'performance_scalability_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @performanceFiles
        if ($LASTEXITCODE -ne 0) { throw 'AI performance scalability harness failed.' }

        $characterDepthFiles = @($coreFiles | Select-Object -SkipLast 1)
        $characterDepthFiles += Join-Path $TestRoot 'character_depth_persistence_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @characterDepthFiles
        if ($LASTEXITCODE -ne 0) { throw 'Character-depth persistence harness failed.' }

        $persistenceTransactionFiles = @($coreFiles | Select-Object -SkipLast 2)
        $persistenceTransactionFiles += Join-Path $TestRoot 'persistence_transaction_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @persistenceTransactionFiles
        if ($LASTEXITCODE -ne 0) { throw 'Persistence transaction/boundary harness failed.' }

        $runtimeHookFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Shared 'SCDiagnostics.lua'),
            (Join-Path $TestRoot 'runtime_hook_fixture.lua'),
            (Join-Path $Client 'SCRuntime.lua'),
            (Join-Path $TestRoot 'runtime_hook_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @runtimeHookFiles
        if ($LASTEXITCODE -ne 0) { throw 'Runtime container-hook ownership harness failed.' }

        $runtimeTransactionFiles = @($runtimeHookFiles | Select-Object -SkipLast 1)
        $runtimeTransactionFiles += Join-Path $TestRoot 'runtime_transaction_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @runtimeTransactionFiles
        if ($LASTEXITCODE -ne 0) { throw 'Runtime startup/teardown transaction harness failed.' }

        $decisionSchedulerFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Shared 'SCDiagnostics.lua'),
            (Join-Path $TestRoot 'runtime_hook_fixture.lua'),
            (Join-Path $Client 'SCScheduler.lua'),
            (Join-Path $Client 'SCRuntime.lua'),
            (Join-Path $TestRoot 'decision_scheduler_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @decisionSchedulerFiles
        if ($LASTEXITCODE -ne 0) { throw 'Decision scheduler multi-actor/critical-lane harness failed.' }

        $registryTransactionFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $Shared 'SCTransaction.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Shared 'SCRegistry.lua'),
            (Join-Path $TestRoot 'registry_transaction_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @registryTransactionFiles
        if ($LASTEXITCODE -ne 0) { throw 'Registry transaction harness failed.' }

        $configReloadFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $TestRoot 'config_reload_before.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $TestRoot 'config_reload_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @configReloadFiles
        if ($LASTEXITCODE -ne 0) { throw 'Configuration hot-reload harness failed.' }

        $sharedPrimitiveFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCTransaction.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $TestRoot 'shared_primitives_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @sharedPrimitiveFiles
        if ($LASTEXITCODE -ne 0) { throw 'Shared safety primitive harness failed.' }

        $bootstrapLifecycleFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $TestRoot 'bootstrap_lifecycle_fixture.lua'),
            (Join-Path $Client 'SCBootstrap.lua'),
            (Join-Path $TestRoot 'bootstrap_lifecycle_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @bootstrapLifecycleFiles
        if ($LASTEXITCODE -ne 0) { throw 'Bootstrap lifecycle transaction harness failed.' }

        $factionLifecycleFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $TestRoot 'faction_lifecycle_fixture.lua'),
            (Join-Path $Client 'SCFactions.lua'),
            (Join-Path $Client 'SCFactionContracts.lua'),
            (Join-Path $Client 'SCRuntime.lua'),
            (Join-Path $Client 'SCBootstrap.lua'),
            (Join-Path $TestRoot 'faction_lifecycle_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @factionLifecycleFiles
        if ($LASTEXITCODE -ne 0) { throw 'Production faction lifecycle harness failed.' }

        $strictCopyFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $TestRoot 'strict_copy_boundary_fixture.lua'),
            (Join-Path $Client 'SCCommands.lua'),
            (Join-Path $Client 'SCFactionContracts.lua'),
            (Join-Path $Client 'SCFactionRecruitment.lua'),
            (Join-Path $TestRoot 'strict_copy_boundary_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @strictCopyFiles
        if ($LASTEXITCODE -ne 0) { throw 'Strict copy boundary harness failed.' }

        $subsystemRestoreFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $TestRoot 'subsystem_restore_integrity_fixture.lua'),
            (Join-Path $Client 'SCBaseLife.lua'),
            (Join-Path $Client 'SCInfectionCrisis.lua'),
            (Join-Path $Client 'SCCommunity.lua'),
            (Join-Path $Client 'SCFactions.lua'),
            (Join-Path $Client 'SCFactionWorld.lua'),
            (Join-Path $TestRoot 'subsystem_restore_integrity_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @subsystemRestoreFiles
        if ($LASTEXITCODE -ne 0) { throw 'Subsystem restore-integrity harness failed.' }

        $productionSpawnFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $Shared 'SCTransaction.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Shared 'SCDiagnostics.lua'),
            (Join-Path $Shared 'SCRegistry.lua'),
            (Join-Path $Client 'SCSpawn.lua'),
            (Join-Path $TestRoot 'production_spawn_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @productionSpawnFiles
        if ($LASTEXITCODE -ne 0) { throw 'Production encounter cadence harness failed.' }

        & (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') -ProjectRoot $ProjectRoot | Out-Null
        $PrivateLua = Join-Path $ProjectRoot 'build\private-playtest\SurvivorCompanion\42\media\lua'
        $privateFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $PrivateLua 'shared\SCNamespace.lua'),
            (Join-Path $PrivateLua 'shared\SCCall.lua'),
            (Join-Path $PrivateLua 'shared\SCStableValue.lua'),
            (Join-Path $PrivateLua 'shared\SCTransaction.lua'),
            (Join-Path $PrivateLua 'shared\SCConfig.lua'),
            (Join-Path $PrivateLua 'shared\SCDiagnostics.lua'),
            (Join-Path $PrivateLua 'shared\SCRegistry.lua'),
            (Join-Path $PrivateLua 'client\SCSpawn.lua'),
            (Join-Path $TestRoot 'private_spawn_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @privateFiles
        if ($LASTEXITCODE -ne 0) { throw 'Private manual-spawn provider harness failed.' }
    }
    finally {
        Pop-Location
    }

    & $GameJava -cp "$BuildRoot;$NativeJar;$Jar" SCNativeApiSignatureTest
    if ($LASTEXITCODE -ne 0) { throw 'Native API signature gate failed.' }
    & $GameJava -cp "$BuildRoot;$Jar" SCAnimationContractTest $GameRoot
    if ($LASTEXITCODE -ne 0) { throw 'Installed Build 42 animation contract gate failed.' }
    & $GameJava -cp "$BuildRoot;$Jar" SCItemContainerContractTest
    if ($LASTEXITCODE -ne 0) { throw 'Installed Build 42 item-container contract gate failed.' }
    & $GameJava -cp "$BuildRoot;$NativeClasses" survivorcompanion.bridge.SCDeferredMainThreadQueueTest
    if ($LASTEXITCODE -ne 0) { throw 'Deferred main-thread spawn queue gate failed.' }

    $clothingCatalog = Join-Path $GameRoot 'media\clothing\clothing.xml'
    [xml]$clothing = Get-Content -LiteralPath $clothingCatalog -Raw -Encoding utf8
    $femaleOutfits = @($clothing.outfitManager.m_FemaleOutfits | ForEach-Object { [string]$_.m_Name })
    $maleOutfits = @($clothing.outfitManager.m_MaleOutfits | ForEach-Object { [string]$_.m_Name })
    foreach ($outfit in @('Generic01', 'Generic02', 'Generic03', 'Generic04', 'Generic05',
            'Grunge', 'Hobbyist', 'Backpacker', 'Camper', 'Evacuee')) {
        if ($femaleOutfits -notcontains $outfit -or $maleOutfits -notcontains $outfit) {
            throw "Required stock companion outfit is not available for both sexes: $outfit"
        }
    }
    Write-Output 'VANILLA_OUTFIT_CONTRACT_PASS count=10 female=true male=true'

    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" survivorcompanion.bridge.SCKahluaExposureTest
        if ($LASTEXITCODE -ne 0) { throw 'Actual LuaManager exposure gate failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" survivorcompanion.bridge.SCIsoPlayerControlTest
        if ($LASTEXITCODE -ne 0) { throw 'Actual IsoPlayer control gate failed.' }
        & $GameJava -cp "$BuildRoot;$NativeJar;$Jar" survivorcompanion.bridge.SCIsoCompanionControlTest
        if ($LASTEXITCODE -ne 0) { throw 'Native IsoCompanion isolation control failed.' }
        & $GameJava -cp "$BuildRoot;$NativeJar;$Jar" survivorcompanion.bridge.SCNativeCleanupTransactionTest
        if ($LASTEXITCODE -ne 0) { throw 'Native cleanup transaction control failed.' }
        & $GameJava -cp "$BuildRoot;$NativeJar;$Jar" survivorcompanion.bridge.SCNativeBridgeExposureTest
        if ($LASTEXITCODE -ne 0) { throw 'Production native bridge Kahlua exposure failed.' }
        & $GameJava -cp "$NativeJar;$Jar" survivorcompanion.bridge.SCLauncher --sc-bridge-smoke-test
        if ($LASTEXITCODE -ne 0) { throw 'Native bridge launcher smoke test failed.' }
    }
    finally {
        Pop-Location
    }

    & $Python (Join-Path $TestRoot 'test_core_static.py')
    if ($LASTEXITCODE -ne 0) { throw 'Core static tests failed.' }
    & $Python (Join-Path $ProjectRoot 'tests\source\test_release_sync.py')
    if ($LASTEXITCODE -ne 0) { throw 'Release constants/documentation synchronization failed.' }
    & (Join-Path $TestRoot 'test_installer.ps1') -ProjectRoot $ProjectRoot
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $resolved = [System.IO.Path]::GetFullPath($BuildRoot)
        $temporary = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporary, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe core-test cleanup: $resolved"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
