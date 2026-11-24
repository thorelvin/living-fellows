# SPDX-License-Identifier: MIT
# Group boundaries are fresh Lua environments in the shared serial runner.
@{ Name = 'behaviour.power-night'; Files = @(
    (Join-Path $Essential 'power_night_fixture.lua'),
    (Join-Path $Shared 'SCEmmaAccess.lua'),
    (Join-Path $Client 'SCTVWatching.lua'),
    (Join-Path $Client 'SCPowerNightCatalog.lua'),
    (Join-Path $Client 'SCPowerNight.lua'),
    (Join-Path $Client 'SCPowerNightUI.lua'),
    (Join-Path $Client 'SCTerminalServices.lua'),
    (Join-Path $Essential 'power_night_harness.lua')) }
@{ Name = 'behaviour.power-night-seating'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Essential 'power_night_seating_harness.lua')) }
@{ Name = 'behaviour.decision-arbitration-and-shelter-entry'; Files = @(
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Client 'SCActionSupervisor.lua'),
    (Join-Path $Client 'SCDecision.lua'),
    (Join-Path $Gameplay 'decision_arbitration_harness.lua')) }
@{ Name = 'behaviour.farming-storage-compatibility'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'farming_storage_harness.lua')) }

@{
    Name = 'behaviour.runtime-contracts'
    Files = @(
        (Join-Path $Core 'core_fixture.lua'),
        (Join-Path $Shared 'SCNamespace.lua'),
        (Join-Path $Shared 'SCCall.lua'),
        (Join-Path $Shared 'SCStableValue.lua'),
        (Join-Path $Shared 'SCConfig.lua'),
        (Join-Path $Shared 'SCDiagnostics.lua'),
        (Join-Path $Client 'SCScheduler.lua'),
        (Join-Path $Core 'core_harness.lua')
    )
}
@{ Name = 'behaviour.follow-and-access'; Files = @(Get-ScGameplayFiles) + (Join-Path $Gameplay 'gameplay_harness.lua') }
@{ Name = 'behaviour.logistics-stalled-survey'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCSupport.lua'), (Join-Path $Gameplay 'logistics_pending_harness.lua')) }
@{ Name = 'behaviour.logistics-duration-clock'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCSupport.lua'), (Join-Path $Essential 'logistics_clock_case.lua'),
    (Join-Path $Gameplay 'logistics_pending_harness.lua')) }
@{ Name = 'behaviour.stay-with-me-identity'; Files = @(Get-ScGameplayFiles) + (Join-Path $Gameplay 'stay_with_me_identity_harness.lua') }
@{ Name = 'behaviour.stay-with-me-protection'; Files = @(Get-ScGameplayFiles) + @(
    'SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua', 'SCNativeCombatActions.lua',
    'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua', 'SCNativeActions.lua' |
    ForEach-Object { Join-Path $Client $_ }) + (Join-Path $Gameplay 'stay_with_me_combat_harness.lua') }
@{ Name = 'behaviour.shared-history'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $ProjectRoot 'tests\fixtures\voice-soak\community-02718.lua'),
    (Join-Path $Gameplay 'shared_history_harness.lua')) }
@{ Name = 'behaviour.companion-scenes'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'scene_harness.lua')) }
@{ Name = 'behaviour.speech-variety'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'voice_memory_harness.lua')) }
@{ Name = 'behaviour.truthful-recall'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'recall_harness.lua')) }
@{ Name = 'behaviour.sixty-day-voice-gates'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'voice_soak_config.lua'),
    (Join-Path $Gameplay 'voice_soak_gates.lua'),
    (Join-Path $Gameplay 'voice_soak_harness.lua')) }
@{ Name = 'behaviour.combat-coordination'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'combat_coordination_regression_harness.lua')) }
@{ Name = 'behaviour.open-ground-melee'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'open_ground_melee_harness.lua')) }
@{ Name = 'behaviour.melee-weapon-readiness'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'melee_weapon_readiness_harness.lua')) }
@{ Name = 'behaviour.ground-finisher-execution'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'ground_finisher_execution_harness.lua')) }

@{ Name = 'behaviour.combat-squad'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'combat_squad_harness.lua')) }
@{ Name = 'behaviour.guard-post'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'guard_post_harness.lua')) }

@{ Name = 'behaviour.combat-ownership'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCPZOptimizerAdapter.lua'),
    (Join-Path $Essential 'combat_harness.lua')) }
@{ Name = 'behaviour.needs-and-sleep'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'needs_harness.lua') }
@{ Name = 'behaviour.medical-summary'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'medical_summary_harness.lua') }
@{ Name = 'behaviour.medical-maintenance'; Files = @(Get-ScGameplayFiles) + (Join-Path $Gameplay 'medical_procedures_fixture.lua') + (Join-Path $Gameplay 'medical_maintenance_harness.lua') }
@{ Name = 'behaviour.medical-procedures'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_procedures_harness.lua')) }
@{ Name = 'behaviour.medical-stitching'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_stitching_fixture.lua'),
    (Join-Path $Gameplay 'medical_stitching_harness.lua')) }
@{ Name = 'behaviour.medical-medicines'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_medicines_fixture.lua'),
    (Join-Path $Gameplay 'medical_medicines_harness.lua')) }
@{ Name = 'behaviour.medical-supplies'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_medicines_fixture.lua'),
    (Join-Path $Gameplay 'medical_supplies_harness.lua')) }
@{ Name = 'behaviour.medical-kit-phase3'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_medicines_fixture.lua'),
    (Join-Path $Gameplay 'medical_kit_phase3_harness.lua')) }
@{ Name = 'behaviour.medical-procedure-resources'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_procedure_resources_harness.lua')) }
@{ Name = 'behaviour.medical-recovery-persistence'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Client 'SCPersistence.lua'),
    (Join-Path $Essential 'medical_recovery_persistence_harness.lua')) }
@{ Name = 'behaviour.medical-visits'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCBaseFuel.lua'), (Join-Path $Essential 'medical_visits_harness.lua')) }
@{ Name = 'behaviour.medical-voice'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'medical_procedures_fixture.lua'),
    (Join-Path $Gameplay 'medical_medicines_fixture.lua'),
    (Join-Path $Gameplay 'medical_voice_harness.lua')) }
@{ Name = 'behaviour.medical-liveness'; Files = @(Get-ScGameplayFiles) + (Join-Path $Gameplay 'medical_liveness_regression_harness.lua') }
@{ Name = 'behaviour.camp-dressing-wash'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'dressing_job_harness.lua') }
@{ Name = 'behaviour.camp-resident-consumers'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCBaseFuel.lua'), (Join-Path $Essential 'camp_resident_consumers_harness.lua'),
    (Join-Path $UI 'SCUIBasePolicyFixture.lua'), (Join-Path $Client 'SCUIFormat.lua'),
    (Join-Path $Client 'SCUIBounds.lua'), (Join-Path $Client 'SCUIAttention.lua'),
    (Join-Path $Client 'SCUI.lua'), (Join-Path $Essential 'camp_roster_staffing_ui_harness.lua')) }
@{ Name = 'behaviour.passenger-reading'; Files = @(
    (Join-Path $Shared 'SCNamespace.lua'), (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $Gameplay 'reading_session_fixture.lua'),
    (Join-Path $Client 'SCActionSupervisor.lua'), (Join-Path $Client 'SCDowntime.lua'),
    (Join-Path $Gameplay 'reading_session_harness.lua'),
    (Join-Path $Gameplay 'passenger_reading_harness.lua')) }
@{ Name = 'behaviour.crowbar-entry'; Files = @(Get-ScGameplayFiles) + @(
    'SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua', 'SCNativeCombatActions.lua',
    'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua', 'SCNativeActions.lua' |
    ForEach-Object { Join-Path $Client $_ }) + @(
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISForceOpen.lua'),
    (Join-Path $Client 'SCBaseFuel.lua'),
    (Join-Path $Essential 'force_entry_harness.lua')) }
@{ Name = 'behaviour.farm-storage-and-medic-kits'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCWorkTransport.lua'), (Join-Path $Essential 'farm_storage_medic_harness.lua')) }
@{ Name = 'behaviour.native-personal-care'; Files = @(Get-ScGameplayFiles) + @(
    'SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua', 'SCNativeCombatActions.lua',
    'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua', 'SCNativeActions.lua' |
    ForEach-Object { Join-Path $Client $_ }) + @(
    'TimedActions\ISFixAction.lua', 'TimedActions\ISCleanBandage.lua',
    'TimedActions\ISWashYourself.lua', 'TimedActions\ISWashClothing.lua', 'TimedActions\ISDryMyself.lua',
    'TimedActions\ISTakeWaterAction.lua', 'TimedActions\Animals\ISPetAnimal.lua',
    'Entity\TimedActions\ISHandcraftAction.lua' |
    ForEach-Object { Join-Path (Join-Path $GameRoot 'media\lua\shared') $_ }) + @(
    (Join-Path $Essential 'native_care_harness.lua'),
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISWearClothing.lua'),
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISUnequipAction.lua'),
    (Join-Path $Essential 'native_clothing_harness.lua')) }
@{ Name = 'behaviour.bandage-washing'; Files = @(Get-ScGameplayFiles) + @(
    'SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua', 'SCNativeCombatActions.lua',
    'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua', 'SCNativeActions.lua' |
    ForEach-Object { Join-Path $Client $_ }) + @(
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISWashClothing.lua'),
    (Join-Path $GameRoot 'media\lua\shared\Entity\TimedActions\ISHandcraftAction.lua'),
    (Join-Path $Essential 'bandage_washing_harness.lua')) }
@{ Name = 'behaviour.autonomy-ground-and-needs'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCAutonomy.lua'),
    (Join-Path $Gameplay 'autonomy_ground_harness.lua')) }
@{ Name = 'behaviour.crisis-recovery'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCActionFeedback.lua'),
    (Join-Path $Essential 'crisis_feedback_harness.lua')) }
@{ Name = 'behaviour.crisis-subject'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCBaseFuel.lua'),
    (Join-Path $Essential 'crisis_subject_harness.lua')) }
@{ Name = 'behaviour.radio-operator'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCRadioWork.lua'),
    (Join-Path $Essential 'radio_work_harness.lua')) }
@{ Name = 'behaviour.chicken-care'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Essential 'animal_night_admission_harness.lua'),
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'animal_work_harness.lua')) }
@{ Name = 'behaviour.cattle-care'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCBaseFuel.lua'), (Join-Path $Essential 'cattle_receipt_harness.lua'),
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'cattle_work_harness.lua')) }
@{ Name = 'behaviour.sheep-care'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'sheep_work_harness.lua')) }
@{ Name = 'behaviour.first-meeting-visitor'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'first_meeting_visitor_harness.lua') }
@{ Name = 'behaviour.loretta-car'; Files = @(
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Core 'oddball_loretta_fixture.lua'),
    (Join-Path $Client 'SCOddballLoretta.lua'),
    (Join-Path $Core 'oddball_loretta_harness.lua')) }
@{ Name = 'behaviour.preacher-van'; Files = @(
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCOddballExchange.lua'),
    (Join-Path $Client 'SCOddballPreacher.lua'),
    (Join-Path $Core 'oddball_preacher_harness.lua')) }
@{ Name = 'behaviour.relationship-help'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'relationship_help_harness.lua') }
@{ Name = 'behaviour.family-pyre'; Files = @(
    (Join-Path $Essential 'caleb_fixture.lua'),
    (Join-Path $Client 'SCOddballCaleb.lua'),
    (Join-Path $Essential 'caleb_harness.lua')) }
