# SPDX-License-Identifier: MIT
# These are ordered source lists, consumed by the shared fresh-environment runner.
@{ Name = 'camp-roster-migration'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCBaseFuel.lua'), (Join-Path $Essential 'roster_migration_harness.lua')
) }
@{ Name = 'runtime-final-death'; Files = @(
    (Join-Path $Core 'core_fixture.lua'), (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'), (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCConfig.lua'), (Join-Path $Shared 'SCDiagnostics.lua'),
    (Join-Path $Core 'runtime_hook_fixture.lua'), (Join-Path $Client 'SCScheduler.lua'),
    (Join-Path $Client 'SCRuntime.lua'), (Join-Path $Core 'decision_scheduler_harness.lua')
) }
@{ Name = 'shelter-candidate-exclusions'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCNativeList.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $Core 'expedition_places_fixture.lua'),
    (Join-Path $Client 'SCExpeditionPlaces.lua'),
    (Join-Path $Core 'expedition_places_harness.lua')
) }

@{ Name = 'handover-recovery'; Files = @(
    (Join-Path $Core 'handover_fixture.lua'),
    (Join-Path $Client 'SCHandover.lua'),
    (Join-Path $Core 'handover_harness.lua')
) }
@{ Name = 'handover-cold-loader-recovery'; Files = @(
    (Join-Path $Core 'handover_fixture.lua'),
    (Join-Path $Client 'SCHandover.lua'),
    (Join-Path $Client 'SCHandoverRescue.lua'),
    (Join-Path $Core 'handover_loader_recovery_harness.lua')
) }
@{ Name = 'handover-shelter-radio'; Files = @(
    (Join-Path $Core 'pickup_radio_fixture.lua'),
    (Join-Path $Client 'SCControlUtil.lua'),
    (Join-Path $Client 'SCTaxiBooking.lua'),
    (Join-Path $Client 'SCRadioEndpoints.lua'),
    (Join-Path $Client 'SCPickupRadio.lua'),
    (Join-Path $Client 'SCHandoverRescue.lua'),
    (Join-Path $Core 'handover_rescue_harness.lua')
) }
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
@{ Name = 'bridge-editions'; Files = @($lifecycleOwnerFiles) + @(
    (Join-Path $Client 'SCScheduler.lua'),
    (Join-Path $Client 'SCPerformance.lua'),
    (Join-Path $Client 'SCSupport.lua'),
    (Join-Path $Core 'bridge_editions_harness.lua')) }
@{ Name = 'camp-pickup-booked-reboarding'; Files = @($lifecycleOwnerFiles) + @(
    (Join-Path $Client 'SCExpeditionCar.lua'),
    (Join-Path $Core 'pickup_boarding_contract_harness.lua')) }

$lifecycleArrivalFiles = @((Join-Path $Core 'core_fixture.lua'))
$lifecycleArrivalFiles += @('SCNamespace.lua', 'SCSpeechColors.lua', 'SCCall.lua',
    'SCStableValue.lua', 'SCNativeList.lua', 'SCConfig.lua', 'SCDiagnostics.lua', 'SCForceEntryState.lua') |
    ForEach-Object { Join-Path $Shared $_ }
@{ Name = 'arrival-exact-reload'; Files = @($lifecycleArrivalFiles) + @(
    (Join-Path $Client 'SCBaseFuel.lua'),
    (Join-Path $Client 'SCPersistence.lua'),
    (Join-Path $Gameplay 'home_arrival_persistence_harness.lua')) }
@{ Name = 'camp-resident-absence'; Files = @($lifecycleArrivalFiles) + @(
    (Join-Path $Shared 'SCRegistry.lua'), (Join-Path $Client 'SCGameplayUtil.lua'),
    (Join-Path $Client 'SCBaseLife.lua'), (Join-Path $Gameplay 'base_work_fixture.lua'),
    (Join-Path $Client 'SCBaseWork.lua'),
    (Join-Path $Client 'SCBaseFuel.lua'), (Join-Path $Client 'SCVehicle.lua'),
    (Join-Path $Client 'SCPersistence.lua'), (Join-Path $Client 'SCHandoverRescue.lua'),
    (Join-Path $Essential 'resident_absence_harness.lua')) }
@{ Name = 'bootstrap-waiting-restoration'; Files = @($lifecycleArrivalFiles) + @(
    (Join-Path $Shared 'SCRegistry.lua'),
    (Join-Path $Client 'SCPersistence.lua'),
    (Join-Path $Core 'persistence_bootstrap_harness.lua')) }
@{ Name = 'restore-square-context'; Files = @($lifecycleArrivalFiles) + @(
    (Join-Path $Shared 'SCRegistry.lua'),
    (Join-Path $Client 'SCPersistence.lua'),
    (Join-Path $Core 'persistence_restore_square_harness.lua')) }
@{ Name = 'medical-xp-persistence'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_medicines_fixture.lua'),
    (Join-Path $Client 'SCPersistence.lua'),
    (Join-Path $Core 'persistence_medical_xp_harness.lua')) }
@{ Name = 'resident-wake-restoration'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'faction_restore_harness.lua')) }
@{ Name = 'taxi-driver-restore'; Files = @(
    (Join-Path $Shared 'SCNamespace.lua'), (Join-Path $Client 'SCTaxiService.lua'),
    (Join-Path $Core 'taxi_service_harness.lua')) }
@{ Name = 'camp-pickup-lifecycle'; Files = @(
    (Join-Path $Core 'pickup_service_fixture.lua'),
    (Join-Path $Client 'SCPickupDispatch.lua'),
    (Join-Path $Client 'SCPickupService.lua'),
    (Join-Path $Client 'SCPickupJournal.lua'),
    (Join-Path $Core 'pickup_service_harness.lua')) }
@{ Name = 'camp-pickup-radio'; Files = @(
    (Join-Path $Core 'pickup_radio_fixture.lua'),
    (Join-Path $Client 'SCControlUtil.lua'),
    (Join-Path $Client 'SCTaxiBooking.lua'),
    (Join-Path $Client 'SCRadioEndpoints.lua'),
    (Join-Path $Client 'SCPickupRadio.lua'),
    (Join-Path $Core 'pickup_radio_harness.lua')) }
@{ Name = 'camp-pickup-restart'; Files = @(
    (Join-Path $Core 'pickup_service_fixture.lua'),
    (Join-Path $Client 'SCPickupDispatch.lua'),
    (Join-Path $Client 'SCPickupService.lua'),
    (Join-Path $Client 'SCPickupJournal.lua'),
    (Join-Path $Core 'pickup_restart_harness.lua')) }
@{ Name = 'camp-pickup-approach-handoff'; Files = @(
    (Join-Path $Core 'pickup_service_fixture.lua'),
    (Join-Path $Client 'SCPickupJourney.lua'),
    (Join-Path $Core 'pickup_journey_harness.lua')) }
@{ Name = 'camp-pickup-watch-handoff'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Client 'SCViewSession.lua'),
    (Join-Path $Client 'SCBaseWatch.lua'),
    (Join-Path $Core 'base_watch_harness.lua')) }
@{ Name = 'bootstrap-lifecycle-and-world-report-reset'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Core 'bootstrap_lifecycle_fixture.lua'),
    (Join-Path $Shared 'SCEmmaAccess.lua'),
    (Join-Path $Client 'SCTerminalLockPhone.lua'),
    (Join-Path $Client 'SCTerminalLockRadio.lua'),
    (Join-Path $Client 'SCTerminalLamp.lua'),
    (Join-Path $Client 'SCBootstrap.lua'),
    (Join-Path $Core 'bootstrap_lifecycle_harness.lua')
) }
