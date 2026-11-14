# SPDX-License-Identifier: MIT
# These are ordered source lists, consumed by the shared fresh-environment runner.
@{ Name = 'first-meeting-and-safe-arrival'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $Shared 'SCDiagnostics.lua'),
    (Join-Path $Client 'SCSpawnSafety.lua'),
    (Join-Path $Client 'SCFirstMeeting.lua'),
    (Join-Path $Client 'SCSpawn.lua'),
    (Join-Path $Core 'first_meeting_harness.lua')
) }
$lifecycleOwnerFiles = @((Join-Path $Core 'core_fixture.lua'))
$lifecycleOwnerFiles += @('SCNamespace.lua', 'SCSpeechColors.lua', 'SCCall.lua',
    'SCStableValue.lua', 'SCTransaction.lua', 'SCNativeList.lua', 'SCConfig.lua',
    'SCDiagnostics.lua', 'SCForceEntryState.lua', 'SCRegistry.lua') | ForEach-Object { Join-Path $Shared $_ }
$lifecycleOwnerFiles += @('SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua',
    'SCNativeCombatActions.lua', 'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua',
    'SCNativeActions.lua', 'SCActionSupervisor.lua', 'SCActor.lua', 'SCGameplayUtil.lua',
    'SCLocomotion.lua', 'SCVehicle.lua') | ForEach-Object { Join-Path $Client $_ }
@{ Name = 'actor-action-isolation'; Files = @($lifecycleOwnerFiles) + @(
    (Join-Path $Essential 'lifecycle_harness.lua')) }

$lifecycleArrivalFiles = @((Join-Path $Core 'core_fixture.lua'))
$lifecycleArrivalFiles += @('SCNamespace.lua', 'SCSpeechColors.lua', 'SCCall.lua',
    'SCStableValue.lua', 'SCNativeList.lua', 'SCConfig.lua', 'SCDiagnostics.lua', 'SCForceEntryState.lua') |
    ForEach-Object { Join-Path $Shared $_ }
@{ Name = 'arrival-exact-reload'; Files = @($lifecycleArrivalFiles) + @(
    (Join-Path $Client 'SCPersistence.lua'),
    (Join-Path $Gameplay 'home_arrival_persistence_harness.lua')) }
@{ Name = 'resident-wake-restoration'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'faction_restore_harness.lua')) }
