# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    # build\native-bridge is a shared directory that every caller wipes and
    # rebuilds. Test-Project builds it once up front and passes this, so the
    # stages can run side by side without destroying each other's classes.
    [switch]$SkipNativeBridge,
    # How many of this suite's independent JVM harnesses may run at once. Each
    # one is a separate VM reading the payload and writing nothing, so the only
    # real limit is the machine.
    [int]$Jobs = 0,
    # Test-Source already runs the core static tests, the release-sync check
    # and the installer transaction test. The installer test owns a fixed
    # sandbox under build\, so running both copies at once would have
    # them wipe each other's staging. Test-Project passes this and keeps the
    # Test-Source copy.
    [switch]$SkipSharedSourceChecks
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
. (Join-Path $ProjectRoot 'scripts\ScParallel.ps1')
if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Math]::Min(8, [int]$env:NUMBER_OF_PROCESSORS))
}

$jarMissing = -not (Test-Path -LiteralPath $Jar -PathType Leaf)
$runtimeMissing = -not (Test-Path -LiteralPath $GameJava -PathType Leaf)
if ($jarMissing -or $runtimeMissing) {
    throw "Project Zomboid 42.20.4 runtime not found under $GameRoot"
}

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    if (-not $SkipNativeBridge) {
        & (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') `
            -ProjectRoot $ProjectRoot -InstallIntoPayload | Out-Null
    }
    if (-not (Test-Path -LiteralPath $NativeJar -PathType Leaf)) {
        throw 'Native bridge build gate did not produce its JAR.'
    }

    # Another gate stage can rebuild build\native-bridge while this suite runs:
    # the installer test drives a real -NativeBridge development install, and
    # that compiles the bridge into the shared directory, wiping it first. Take
    # a private snapshot and run against that, so a concurrent rebuild cannot
    # pull the classes out from under a JVM that is still starting.
    $NativeSnapshot = Join-Path $BuildRoot 'native-bridge'
    New-Item -ItemType Directory -Path $NativeSnapshot -Force | Out-Null
    Copy-Item -LiteralPath $NativeJar -Destination $NativeSnapshot -Force
    Copy-Item -LiteralPath $NativeClasses `
        -Destination (Join-Path $NativeSnapshot 'classes') -Recurse -Force
    $NativeJar = Join-Path $NativeSnapshot 'SurvivorCompanionBridge.jar'
    $NativeClasses = Join-Path $NativeSnapshot 'classes'

    # Every harness below is a separate JVM that reads the payload and the
    # game JAR and writes nothing, so they are independent by construction.
    # Collect them instead of running them one at a time: this suite is ~37
    # JVM starts and they dominate the gate.
    $steps = New-Object System.Collections.ArrayList
    function Add-ScJvmStep {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string[]]$JvmArgs,
            [string[]]$Files = @(),
            [Parameter(Mandatory)][string]$Failure
        )
        [void]$steps.Add((New-ScStep -Name $Name -FilePath $GameJava `
            -WorkingDirectory $GameRoot -Failure $Failure -Arguments ($JvmArgs + $Files)))
    }
    & $Javac -cp $NativeClasses -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java') `
        (Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java') `
        (Join-Path $TestRoot 'SCNativeApiSignatureTest.java') `
        (Join-Path $TestRoot 'SCBridgeLuaNumberContractTest.java') `
        (Join-Path $TestRoot 'SCAnimationContractTest.java') `
        (Join-Path $TestRoot 'SCItemContainerContractTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCKahluaExposureTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCDeferredMainThreadQueueTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCBootstrapLifecycleTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCIsoPlayerControlTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCIsoCompanionControlTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCNativeCleanupTransactionTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCNativeBridgeExposureTest.java') `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCStreetLookupTest.java')
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
        (Join-Path $Client 'SCNativeTraversalActions.lua'),
        (Join-Path $Client 'SCNativeVisualActions.lua'),
        (Join-Path $Client 'SCNativeCombatActions.lua'),
        (Join-Path $Client 'SCNativeWorkActions.lua'),
        (Join-Path $Client 'SCNativeMovementActions.lua'),
        (Join-Path $Client 'SCNativeActions.lua'),
        (Join-Path $Client 'SCActionSupervisor.lua'),
        (Join-Path $Client 'SCBackground.lua'),
        (Join-Path $Client 'SCActor.lua'),
        (Join-Path $Client 'SCVehicle.lua'),
        (Join-Path $Client 'SCPerformance.lua'),
        (Join-Path $Client 'SCScheduler.lua'),
        (Join-Path $Client 'SCPersistence.lua'),
        (Join-Path $Client 'SCGameplayUtil.lua'),
        (Join-Path $Client 'SCBaseObjectRef.lua'),
        (Join-Path $Client 'SCBaseLife.lua'),
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
        Add-ScJvmStep 'core' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $coreFiles 'Core Kahlua integration harness failed.'

        $combatRecoveryFiles = @($coreFiles | Select-Object -SkipLast 2)
        $combatRecoveryFiles += Join-Path $TestRoot 'combat_recovery_harness.lua'
        Add-ScJvmStep 'combat-recovery' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $combatRecoveryFiles 'Native combat recovery/spacing regression harness failed.'

        $groundFinisherFiles = @($combatRecoveryFiles | Select-Object -SkipLast 1)
        $groundFinisherFiles += Join-Path $TestRoot 'ground_finisher_harness.lua'
        Add-ScJvmStep 'ground-finisher' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $groundFinisherFiles 'Grounded finisher regression harness failed.'

        $navigationTraversalFiles = @($coreFiles | Select-Object -SkipLast 2)
        $navigationTraversalFiles += @(
            (Join-Path $Client 'SCTopology.lua'),
            (Join-Path $Client 'SCPathSearch.lua'),
            (Join-Path $Client 'SCNavTraffic.lua'),
            (Join-Path $Client 'SCNavTraversal.lua'),
            (Join-Path $Client 'SCWorkRoutes.lua'),
            (Join-Path $Client 'SCNavigation.lua'),
            (Join-Path $TestRoot 'navigation_traversal_regression_harness.lua')
        )
        Add-ScJvmStep 'navigation-traversal' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $navigationTraversalFiles 'Door/async traversal regression harness failed.'

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
            (Join-Path $Client 'SCNativeTraversalActions.lua'),
            (Join-Path $Client 'SCNativeVisualActions.lua'),
            (Join-Path $Client 'SCNativeCombatActions.lua'),
            (Join-Path $Client 'SCNativeWorkActions.lua'),
            (Join-Path $Client 'SCNativeMovementActions.lua'),
            (Join-Path $Client 'SCNativeActions.lua'),
            (Join-Path $Client 'SCActionSupervisor.lua'),
            (Join-Path $Client 'SCBackground.lua'),
            (Join-Path $Client 'SCActor.lua'),
            (Join-Path $TestRoot 'actor_ownership_harness.lua')
        )
        Add-ScJvmStep 'actor-ownership' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $actorOwnershipFiles 'Lua/native actor ownership harness failed.'

        $supervisorSoakFiles = @($coreFiles | Select-Object -SkipLast 2)
        $supervisorSoakFiles += Join-Path $TestRoot 'supervisor_fault_soak_harness.lua'
        Add-ScJvmStep 'supervisor-soak' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $supervisorSoakFiles 'Action-supervisor fault/soak harness failed.'

        $performanceFiles = @($coreFiles | Select-Object -SkipLast 1)
        $performanceFiles += Join-Path $TestRoot 'performance_scalability_harness.lua'
        Add-ScJvmStep 'performance' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $performanceFiles 'AI performance scalability harness failed.'

        $characterDepthFiles = @($coreFiles | Select-Object -SkipLast 1)
        $characterDepthFiles += Join-Path $TestRoot 'character_depth_persistence_harness.lua'
        Add-ScJvmStep 'character-depth' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $characterDepthFiles 'Character-depth persistence harness failed.'

        $tradePersistenceFiles = @($coreFiles | Select-Object -SkipLast 2)
        $tradePersistenceFiles += @(
            (Join-Path $Client 'SCTrade.lua'),
            (Join-Path $TestRoot 'trade_persistence_recovery_harness.lua')
        )
        Add-ScJvmStep 'trade-persistence' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $tradePersistenceFiles 'Trade/persistence recovery integration harness failed.'

        $workTransportFiles = @($coreFiles | Select-Object -SkipLast 2)
        $workTransportFiles += @(
            (Join-Path $TestRoot 'work_transport_fixture.lua'),
            (Join-Path $Client 'SCWorkTransport.lua'),
            (Join-Path $Client 'SCGatherWork.lua'),
            (Join-Path $Client 'SCBaseWork.lua'),
            (Join-Path $TestRoot 'work_transport_harness.lua')
        )
        Add-ScJvmStep 'work-transport' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $workTransportFiles 'Gathering/transport ownership integration harness failed.'

        $productionFiles = @($coreFiles | Select-Object -SkipLast 2)
        $productionFiles += @(
            (Join-Path $Client 'SCDialogue.lua'),
            (Join-Path $TestRoot 'work_transport_fixture.lua'),
            (Join-Path $TestRoot 'production_fixture.lua'),
            (Join-Path $Client 'SCWorkTransport.lua'),
            (Join-Path $Client 'SCGatherWork.lua'),
            (Join-Path $Client 'SCBaseWork.lua'),
            (Join-Path $Client 'SCDiaryItem.lua'),
            (Join-Path $Client 'SCProduction.lua'),
            (Join-Path $TestRoot 'production_harness.lua')
        )
        Add-ScJvmStep 'production' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $productionFiles 'Base production (fell/saw/dig/bury) integration harness failed.'

        $farmingFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Client 'SCGameplayUtil.lua'),
            (Join-Path $Client 'SCFarmWork.lua'),
            (Join-Path $TestRoot 'farming_harness.lua')
        )
        Add-ScJvmStep 'farming' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $farmingFiles 'Autonomous farming policy harness failed.'

        $persistenceTransactionFiles = @($coreFiles | Select-Object -SkipLast 2)
        $persistenceTransactionFiles += Join-Path $TestRoot 'persistence_transaction_harness.lua'
        Add-ScJvmStep 'persistence-transaction' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $persistenceTransactionFiles 'Persistence transaction/boundary harness failed.'

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
        Add-ScJvmStep 'runtime-hook' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $runtimeHookFiles 'Runtime container-hook ownership harness failed.'

        $runtimeTransactionFiles = @($runtimeHookFiles | Select-Object -SkipLast 1)
        $runtimeTransactionFiles += Join-Path $TestRoot 'runtime_transaction_harness.lua'
        Add-ScJvmStep 'runtime-transaction' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $runtimeTransactionFiles 'Runtime startup/teardown transaction harness failed.'

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
        Add-ScJvmStep 'decision-scheduler' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $decisionSchedulerFiles 'Decision scheduler multi-actor/critical-lane harness failed.'

        $aiResponseFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Shared 'SCDiagnostics.lua'),
            (Join-Path $TestRoot 'runtime_hook_fixture.lua'),
            (Join-Path $Client 'SCPerformance.lua'),
            (Join-Path $Client 'SCScheduler.lua'),
            (Join-Path $Client 'SCRuntime.lua'),
            (Join-Path $TestRoot 'ai_response_harness.lua')
        )
        Add-ScJvmStep 'ai-response' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $aiResponseFiles 'AI response/load harness failed.'

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
        Add-ScJvmStep 'registry-transaction' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $registryTransactionFiles 'Registry transaction harness failed.'

        $configReloadFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $TestRoot 'config_reload_before.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $TestRoot 'config_reload_harness.lua')
        )
        Add-ScJvmStep 'config-reload' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $configReloadFiles 'Configuration hot-reload harness failed.'

        $sharedPrimitiveFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCTransaction.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $TestRoot 'shared_primitives_harness.lua')
        )
        Add-ScJvmStep 'shared-primitive' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $sharedPrimitiveFiles 'Shared safety primitive harness failed.'

        $bootstrapLifecycleFiles = @(
            (Join-Path $TestRoot 'core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $TestRoot 'bootstrap_lifecycle_fixture.lua'),
            (Join-Path $Client 'SCBootstrap.lua'),
            (Join-Path $TestRoot 'bootstrap_lifecycle_harness.lua')
        )
        Add-ScJvmStep 'bootstrap-lifecycle' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $bootstrapLifecycleFiles 'Bootstrap lifecycle transaction harness failed.'

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
        Add-ScJvmStep 'faction-lifecycle' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $factionLifecycleFiles 'Production faction lifecycle harness failed.'

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
        Add-ScJvmStep 'strict-copy' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $strictCopyFiles 'Strict copy boundary harness failed.'

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
        Add-ScJvmStep 'subsystem-restore' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $subsystemRestoreFiles 'Subsystem restore-integrity harness failed.'

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
        Add-ScJvmStep 'production-spawn' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $productionSpawnFiles 'Production encounter cadence harness failed.'

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
        Add-ScJvmStep 'private' @('-cp', "$BuildRoot;$Jar", 'KahluaTestRunner') $privateFiles 'Private manual-spawn provider harness failed.'
    }
    finally {
        Pop-Location
    }

    Add-ScJvmStep 'sc-native-api-signature-test' @('-cp', "$BuildRoot;$NativeJar;$Jar", 'SCNativeApiSignatureTest') @() 'Native API signature gate failed.'
    Add-ScJvmStep 'sc-bridge-lua-number-contract-test' @('-cp', "$BuildRoot;$NativeJar;$Jar", 'SCBridgeLuaNumberContractTest') @() 'Native Kahlua number contract gate failed.'
    Add-ScJvmStep 'sc-animation-contract-test' @('-cp', "$BuildRoot;$Jar", 'SCAnimationContractTest', $GameRoot) @() 'Installed Build 42 animation contract gate failed.'
    Add-ScJvmStep 'sc-item-container-contract-test' @('-cp', "$BuildRoot;$Jar", 'SCItemContainerContractTest') @() 'Installed Build 42 item-container contract gate failed.'
    Add-ScJvmStep 'sc-deferred-main-thread-queue-test' @('-cp', "$BuildRoot;$NativeClasses", 'survivorcompanion.bridge.SCDeferredMainThreadQueueTest') @() 'Deferred main-thread spawn queue gate failed.'
    Add-ScJvmStep 'sc-bootstrap-lifecycle-test' @('-cp', "$BuildRoot;$NativeClasses", 'survivorcompanion.bridge.SCBootstrapLifecycleTest') @() 'Bootstrap generation lifecycle gate failed.'
    Add-ScJvmStep 'sc-street-lookup-test' @('-cp', "$BuildRoot;$NativeClasses", 'survivorcompanion.bridge.SCStreetLookupTest') @() 'Native nearest-street lookup gate failed.'

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
        Add-ScJvmStep 'sc-kahlua-exposure-test' @('-cp', "$BuildRoot;$Jar", 'survivorcompanion.bridge.SCKahluaExposureTest') @() 'Actual LuaManager exposure gate failed.'
        Add-ScJvmStep 'sc-iso-player-control-test' @('-cp', "$BuildRoot;$Jar", 'survivorcompanion.bridge.SCIsoPlayerControlTest') @() 'Actual IsoPlayer control gate failed.'
        Add-ScJvmStep 'sc-iso-companion-control-test' @('-cp', "$BuildRoot;$NativeJar;$Jar", 'survivorcompanion.bridge.SCIsoCompanionControlTest') @() 'Native IsoCompanion isolation control failed.'
        Add-ScJvmStep 'sc-native-cleanup-transaction-test' @('-cp', "$BuildRoot;$NativeJar;$Jar", 'survivorcompanion.bridge.SCNativeCleanupTransactionTest') @() 'Native cleanup transaction control failed.'
        Add-ScJvmStep 'sc-native-bridge-exposure-test' @('-cp', "$BuildRoot;$NativeJar;$Jar", 'survivorcompanion.bridge.SCNativeBridgeExposureTest') @() 'Production native bridge Kahlua exposure failed.'
        Add-ScJvmStep 'sc-launcher' @('-cp', "$NativeJar;$Jar", 'survivorcompanion.bridge.SCLauncher', '--sc-bridge-smoke-test') @() 'Native bridge launcher smoke test failed.'
    }
    finally {
        Pop-Location
    }

    Invoke-ScParallelSteps -Steps $steps.ToArray() -Throttle $Jobs -Label 'core harnesses'

    if (-not $SkipSharedSourceChecks) {
        & $Python (Join-Path $TestRoot 'test_core_static.py')
        if ($LASTEXITCODE -ne 0) { throw 'Core static tests failed.' }
        & $Python (Join-Path $ProjectRoot 'tests\source\test_release_sync.py')
        if ($LASTEXITCODE -ne 0) { throw 'Release constants/documentation synchronization failed.' }
        & (Join-Path $TestRoot 'test_installer.ps1') -ProjectRoot $ProjectRoot -Jobs $Jobs
    }
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
