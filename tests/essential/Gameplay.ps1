# SPDX-License-Identifier: MIT
# Existing gameplay load order, shared by the essential checks and subject runs.
function Get-ScGameplayFiles {
    @((Join-Path $Core 'core_fixture.lua'))
    (Join-Path $Shared 'SCNamespace.lua')
    (Join-Path $Shared 'SCForceEntryState.lua')
    (Join-Path $Shared 'SCSpeechColors.lua')
    (Join-Path $Shared 'SCCall.lua')
    (Join-Path $Shared 'SCStableValue.lua')
    (Join-Path $Shared 'SCTransaction.lua')
    (Join-Path $Shared 'SCNativeList.lua')
    (Join-Path $Shared 'SCConfig.lua')
    (Join-Path $Shared 'SCVitals.lua')
    (Join-Path $Client 'SCGameplayUtil.lua')
    (Join-Path $Essential 'gameplay_fixture.lua')
    @(
        'SCBanditsAdapter.lua',
        'SCNames.lua',
        'SCInventoryIndex.lua',
        'SCVitalsTrace.lua',
        'SCBaseObjectRef.lua',
        'SCTopology.lua',
        'SCPathSearch.lua',
        'SCNavTraffic.lua',
        'SCNavTraversal.lua',
        'SCActionSupervisor.lua',
        'SCVehicle.lua',
        'SCLocomotion.lua',
        'SCPerformance.lua',
        'SCDialogue.lua',
        'SCAllegiance.lua',
        'SCLifeEvents.lua',
        'SCCommunity.lua',
        'SCBackground.lua',
        'SCThreatSet.lua',
        'SCCombatThreatModel.lua',
        'SCCombatSquad.lua',
        'SCPerceptionScan.lua',
        'SCZombieFacts.lua',
        'SCSenses.lua',
        'SCWorkRoutes.lua',
        'SCStairTransition.lua',
        'SCNavigation.lua',
        'SCPositioning.lua',
        'SCCombat.lua',
        'SCMedical.lua',
        'SCMedicKit.lua',
        'SCEncounter.lua',
        'SCForceEntry.lua',
        'SCLogistics.lua',
        'SCLighting.lua',
        'SCNeeds.lua',
        'SCHygieneEffects.lua',
        'SCTVWatching.lua',
        'SCComputerUse.lua',
        'SCRadioListening.lua',
        'SCNativeCareActions.lua',
        'SCDowntime.lua',
        'SCPersonality.lua',
        'SCPersonalItems.lua',
        'SCDiaryText.lua',
        'SCDiaryCatalog.lua',
        'SCDiaryItem.lua',
        'SCDiary.lua',
        'SCRelationship.lua',
        'SCTales.lua',
        'SCIntrusiveLines.lua',
        'SCBanter.lua',
        'SCWorkVoiceLines.lua',
        'SCGestures.lua',
        'SCObjectives.lua',
        'SCJournal.lua',
        'SCFarmStorage.lua',
        'SCBaseLife.lua',
        'SCFarmWork.lua',
        'SCManureWork.lua',
        'SCAnimalWork.lua',
        'SCAnimalShearing.lua',
        'SCFishing.lua',
        'SCChefWork.lua',
        'SCQuirks.lua',
        'SCFactions.lua',
        'SCTrade.lua',
        'SCFactionLife.lua',
        'SCFactionContracts.lua',
        'SCFactionWorld.lua',
        'SCFactionBehavior.lua',
        'SCZombieTargeting.lua',
        'SCCombatTrace.lua',
        'SCZombieAttack.lua',
        'SCInfectionCrisis.lua',
        'SCAutonomy.lua',
        'SCCommands.lua',
        'SCInteraction.lua',
        'SCCompanionGifts.lua',
        'SCFactionRecruitment.lua',
        'SCRelationshipHelp.lua',
        'SCBaseAlert.lua',
        'SCDecision.lua'
    ) | ForEach-Object { Join-Path $Client $_ }
    (Join-Path $Gameplay 'base_work_fixture.lua')
    (Join-Path $Client 'SCFloorSort.lua')
    (Join-Path $Client 'SCBaseWork.lua')
}
