# SPDX-License-Identifier: MIT
# Group boundaries are fresh Lua environments in the shared serial runner.
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
@{ Name = 'behaviour.combat-ownership'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCPZOptimizerAdapter.lua'),
    (Join-Path $Essential 'combat_harness.lua')) }
@{ Name = 'behaviour.needs-and-sleep'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'needs_harness.lua') }
@{ Name = 'behaviour.native-personal-care'; Files = @(Get-ScGameplayFiles) + @(
    'SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua', 'SCNativeCombatActions.lua',
    'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua', 'SCNativeActions.lua'
    | ForEach-Object { Join-Path $Client $_ }) + @(
    'TimedActions\ISFixAction.lua', 'TimedActions\ISCleanBandage.lua',
    'TimedActions\ISWashYourself.lua', 'TimedActions\ISWashClothing.lua',
    'Entity\TimedActions\ISHandcraftAction.lua'
    | ForEach-Object { Join-Path (Join-Path $GameRoot 'media\lua\shared') $_ }) + @(
    (Join-Path $Essential 'native_care_harness.lua')) }
@{ Name = 'behaviour.autonomy-ground-and-needs'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCAutonomy.lua'),
    (Join-Path $Gameplay 'autonomy_ground_harness.lua')) }
@{ Name = 'behaviour.crisis-recovery'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCActionFeedback.lua'),
    (Join-Path $Essential 'crisis_feedback_harness.lua')) }
@{ Name = 'behaviour.radio-operator'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCRadioWork.lua'),
    (Join-Path $Essential 'radio_work_harness.lua')) }
@{ Name = 'behaviour.chicken-care'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Essential 'animal_night_admission_harness.lua'),
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'animal_work_harness.lua')) }
@{ Name = 'behaviour.cattle-care'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Essential 'cattle_receipt_harness.lua'),
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'cattle_work_harness.lua')) }
@{ Name = 'behaviour.sheep-care'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Core 'farming_lifecycle_fixture.lua'),
    (Join-Path $Essential 'sheep_work_harness.lua')) }
@{ Name = 'behaviour.first-meeting-visitor'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'first_meeting_visitor_harness.lua') }
@{ Name = 'behaviour.relationship-help'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'relationship_help_harness.lua') }
@{ Name = 'behaviour.family-pyre'; Files = @(
    (Join-Path $Essential 'caleb_fixture.lua'),
    (Join-Path $Client 'SCOddballCaleb.lua'),
    (Join-Path $Essential 'caleb_harness.lua')) }
