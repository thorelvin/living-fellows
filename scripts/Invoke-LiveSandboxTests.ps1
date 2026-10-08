# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$UserCache = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'),
    [string]$SeedSave,
    [string]$GameMode,
    [ValidateRange(45, 900)]
    # Large mod lists can spend more than three minutes in script, map and
    # asset loading before Build 42 exposes its click-to-start gate. The
    # in-game harness retains its own bounded deadline once play begins.
    [int]$TimeoutSeconds = 300,
    [switch]$HiddenWindow,
    [switch]$LivingFellowsOnly,
    [switch]$UIMenuProbe,
    [switch]$BaseMaintenanceProbe,
    [switch]$HygieneProbe,
    [string]$HygieneScreenshot = '',
    [string]$HygieneEightDirectionsScreenshotDirectory = '',
    [switch]$BaseSecondFloorProbe,
    [switch]$WaterSourceProbe,
    [switch]$ProjectALifeDamageProbe,
    [string]$ProjectALifeModPath = '',
    [string[]]$ExcludeModId = @(),
    [string]$FactionMapScreenshot = '',
    [switch]$FactionMapOnly,
    [string]$BaseLayoutScreenshot = '',
    [switch]$BaseLayoutOnly,
    [string]$CompanionInventoryScreenshot = '',
    [switch]$CompanionInventoryOnly,
    [switch]$FurniturePoseOnly,
    [switch]$VehiclePassengerOnly,
    [string]$VehiclePassengerScreenshot = '',
    [switch]$WoodcutterOnly,
    [switch]$PostedStreamOnly,
    [switch]$PathingOnly,
    [switch]$PlaceMetadataOnly,
    [switch]$SplitScreenOnly,
    [switch]$SplitBaseLayoutProbe,
    [switch]$ColdCompanionProbe,
    [switch]$FishingMapListProbe,
    [switch]$FishingBankProbe,
    [switch]$FishingCatchProbe,
    [switch]$ChefRecipesProbe,
    [switch]$ColdRestartProbe,
    [switch]$ColdRestartHandoff,
    [switch]$ColdRestartCrashProbe,
    [switch]$ColdRestartLfFirstCrashProbe,
    [switch]$LeaderSlotOnly,
    [switch]$LeaderRemote,
    [ValidateRange(-2048, 2048)][int]$LeaderRemoteOffsetX = 512,
    [ValidateRange(-2048, 2048)][int]$LeaderRemoteOffsetY = 0,
    [switch]$TeamHandoff,
    [switch]$TeamRadioFixture,
    [switch]$TeamRadioPlacedProbe,
    [switch]$TeamRadioTimedPlacementProbe,
    [switch]$TeamRadioPlacedPickupProbe,
    [long]$TeamRadioPlacedExpectedWalkieId = 0,
    [long]$TeamRadioPlacedExpectedHamId = 0,
    [switch]$TeamRadioTextProbe,
    [switch]$TeamRadioCommandProbe,
    [switch]$TeamWaypointProbe,
    [switch]$TeamLocalTravelProbe,
    [switch]$TeamLocalLootRoundTripProbe,
    [switch]$TeamExtendedRouteProbe,
    [switch]$TeamExtendedQuietProbe,
    [switch]$TeamExtendedReturnProbe,
    [switch]$TeamExtendedReturnResumeProbe,
    [int]$TeamExtendedReturnSourceX = 0,
    [int]$TeamExtendedReturnSourceY = 0,
    [switch]$TeamCorpseStreamingProbe,
    [switch]$TeamCorpseStreamingReloadProbe,
    [int]$TeamCorpseStreamVerifyX = 0,
    [int]$TeamCorpseStreamVerifyY = 0,
    [switch]$TeamAutonomousScoutProbe,
    [switch]$TeamZombieVisibilityProbe,
    [switch]$TeamRoadRouteProbe,
    [ValidateRange(20, 200)][int]$TeamRoadDistanceTiles = 180,
    [switch]$TeamRoadMovementProbe,
    [switch]$TeamRoadHordeProbe,
    [switch]$TeamRoadBlockedRadioProbe,
    [switch]$TeamRoadAlternateProbe,
    [switch]$TeamRoadRestartStageOnly,
    [switch]$TeamRoadRestartResumeProbe,
    [switch]$TeamKnownPlaceScoutProbe,
    [switch]$TeamUnvisitedPlaceScoutProbe,
    [switch]$TeamAutonomousSearchProbe,
    [switch]$TeamSharedSearchProbe,
    [switch]$TeamLeaderMotionProbe,
    [switch]$TeamUnvisitedInteriorSearchProbe,
    [switch]$TeamMultifloorSearchProbe,
    [switch]$TeamMultifloorSquadProbe,
    [switch]$TeamAutonomousSearchStageOnly,
    [switch]$TeamAutonomousSearchResumeProbe,
    [switch]$TeamBuildingProbe,
    [switch]$TeamWindowProbe,
    [switch]$TeamInsideDoorProbe,
    [switch]$TeamDoorBashProbe,
    [switch]$TeamDoorBashAutoProbe,
    [switch]$TeamPursuerProbe,
    [switch]$TeamPursuerFixture,
    [switch]$TeamStragglerProbe,
    [switch]$TeamRestartAuditOnly,
    [switch]$TeamRestartStageOnly,
    [switch]$TeamOverlapProbe,
    [switch]$TeamReturnReleaseProbe,
    [switch]$TeamReturnStageOnly,
    [switch]$TeamIdleSlotRestartProbe,
    [switch]$TeamAllDeadIdleRestartProbe,
    [switch]$TeamCorpseReloadProbe,
    [switch]$TeamLootSurvey,
    [switch]$TeamLootProbe,
    [switch]$TeamLootVerifyOnly,
    [string]$TeamLootVerifyToken = '',
    [string]$TeamLootVerifyItemType = '',
    [long]$TeamLootVerifyNativeId = 0,
    [switch]$TeamAllDeadCleanup,
    [switch]$TeamAllDeadStageOnly,
    [switch]$TeamAllDeadMenuCleanupProbe,
    [switch]$TeamMenuCleanupProbe,
    [switch]$PerformanceBaselineOnly,
    [ValidateSet(4, 8, 16)][int]$PerformancePopulation = 4,
    [switch]$TeamPerformanceProbe,
    [switch]$TeamPerformanceRouteProbe,
    [switch]$TeamPerformanceEncounterProbe,
    [switch]$TeamRepeatedHandoff,
    [switch]$TeamRadioKitOnly,
    [switch]$TeamExpeditionUiProbe,
    [switch]$TeamRadioKitVerifyOnly,
    [ValidateRange(8, 180)][int]$LeaderWatchSeconds = 8,
    [string]$SplitScreenScreenshot = '',
    [string]$ZombieVisibilityScreenshot = '',
    [string]$PostHandoffScreenshot = '',
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $scriptDirectory
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$UserCache = [System.IO.Path]::GetFullPath($UserCache)
if ($SplitScreenOnly -and ($PathingOnly -or $FactionMapOnly -or $BaseLayoutOnly)) {
    throw '-SplitScreenOnly cannot be combined with another focused mode.'
}
if ($LeaderSlotOnly -and -not $SplitScreenOnly) {
    throw '-LeaderSlotOnly requires -SplitScreenOnly.'
}
if ($SplitBaseLayoutProbe -and (-not $SplitScreenOnly -or -not $LeaderSlotOnly)) {
    throw '-SplitBaseLayoutProbe requires -SplitScreenOnly and -LeaderSlotOnly.'
}
if ($ColdCompanionProbe -and (-not $SplitScreenOnly -or $LeaderSlotOnly)) {
    throw '-ColdCompanionProbe requires the standalone split-screen probe.'
}
if ($FishingBankProbe -and (-not $SplitScreenOnly -or -not $LeaderSlotOnly -or -not $LeaderRemote)) {
    throw '-FishingBankProbe requires -SplitScreenOnly, -LeaderSlotOnly and -LeaderRemote.'
}
if ($FishingCatchProbe -and -not $FishingBankProbe) {
    throw '-FishingCatchProbe requires -FishingBankProbe.'
}
if ($ColdRestartProbe -and -not $ColdCompanionProbe) {
    throw '-ColdRestartProbe requires -ColdCompanionProbe.'
}
if ($ColdRestartHandoff -and -not $ColdRestartProbe) {
    throw '-ColdRestartHandoff requires -ColdRestartProbe.'
}
if ($ColdRestartCrashProbe -and (-not $ColdRestartProbe -or $ColdRestartHandoff)) {
    throw '-ColdRestartCrashProbe requires -ColdRestartProbe without -ColdRestartHandoff.'
}
if ($ColdRestartLfFirstCrashProbe -and (-not $ColdRestartProbe -or
    $ColdRestartHandoff -or $ColdRestartCrashProbe)) {
    throw '-ColdRestartLfFirstCrashProbe requires a standalone -ColdRestartProbe.'
}
if ($LeaderRemote -and -not $LeaderSlotOnly) {
    throw '-LeaderRemote requires -LeaderSlotOnly.'
}
if ($TeamHandoff -and -not ($LeaderSlotOnly -and ($LeaderRemote -or $TeamLocalTravelProbe -or $TeamAutonomousScoutProbe -or $TeamAutonomousSearchProbe))) {
    throw '-TeamHandoff requires -LeaderSlotOnly and a remote or local travel probe.'
}
if ($TeamRadioFixture -and -not $TeamHandoff) {
    throw '-TeamRadioFixture requires -TeamHandoff.'
}
if ($TeamRadioPlacedProbe -and -not ($TeamRadioFixture -or $TeamRadioKitOnly -or $TeamRadioKitVerifyOnly)) {
    throw '-TeamRadioPlacedProbe requires a radio fixture or radio-kit stage/reload.'
}
if ($TeamRadioPlacedProbe -and $TeamRadioKitVerifyOnly -and
    ($TeamRadioPlacedExpectedWalkieId -le 0 -or $TeamRadioPlacedExpectedHamId -le 0)) {
    throw '-TeamRadioPlacedProbe reload requires both staged native radio item IDs.'
}
if ($TeamRadioPlacedPickupProbe -and (-not $TeamRadioPlacedProbe -or -not $TeamRadioKitVerifyOnly)) {
    throw '-TeamRadioPlacedPickupProbe requires -TeamRadioPlacedProbe and -TeamRadioKitVerifyOnly.'
}
if ($TeamRadioTimedPlacementProbe -and
    (-not $TeamRadioPlacedProbe -or -not $TeamRadioKitOnly)) {
    throw '-TeamRadioTimedPlacementProbe requires -TeamRadioPlacedProbe and -TeamRadioKitOnly.'
}
if ($TeamRadioTextProbe -and -not $TeamRadioFixture) {
    throw '-TeamRadioTextProbe requires -TeamRadioFixture.'
}
if ($TeamRadioCommandProbe -and -not $TeamRadioTextProbe) {
    throw '-TeamRadioCommandProbe requires -TeamRadioTextProbe.'
}
if ($TeamWaypointProbe -and -not $TeamHandoff) {
    throw '-TeamWaypointProbe requires -TeamHandoff.'
}
if ($TeamLocalTravelProbe -and (-not $TeamHandoff -or $LeaderRemote -or $TeamWaypointProbe -or $TeamRadioFixture -or $TeamLootSurvey -or $TeamOverlapProbe -or $TeamAllDeadCleanup -or $TeamRepeatedHandoff)) {
    throw '-TeamLocalTravelProbe requires a focused local team handoff run.'
}
if ($PlaceMetadataOnly -and ($SplitScreenOnly -or $PathingOnly -or
    $FactionMapOnly -or $BaseLayoutOnly -or $LeaderSlotOnly)) {
    throw '-PlaceMetadataOnly requires a standalone read-only run.'
}
if ($TeamAutonomousScoutProbe -and (-not $TeamHandoff -or $LeaderRemote -or
    $TeamLocalTravelProbe -or $TeamExtendedRouteProbe -or
    ($TeamRadioFixture -and -not $TeamRoadBlockedRadioProbe) -or
    $TeamLootSurvey -or $TeamOverlapProbe)) {
    throw '-TeamAutonomousScoutProbe requires a focused local team handoff run.'
}
if ($TeamRoadRouteProbe -and -not $TeamAutonomousScoutProbe) {
    throw '-TeamRoadRouteProbe requires -TeamAutonomousScoutProbe.'
}
if ($TeamRoadMovementProbe -and -not $TeamRoadRouteProbe) {
    throw '-TeamRoadMovementProbe requires -TeamRoadRouteProbe.'
}
if ($TeamRoadHordeProbe -and -not $TeamRoadRouteProbe) {
    throw '-TeamRoadHordeProbe requires -TeamRoadRouteProbe.'
}
if ($TeamRoadBlockedRadioProbe -and
    (-not $TeamRoadHordeProbe -or -not $TeamRadioFixture)) {
    throw '-TeamRoadBlockedRadioProbe requires -TeamRoadHordeProbe and -TeamRadioFixture.'
}
if ($TeamRoadAlternateProbe -and -not $TeamRoadHordeProbe) {
    throw '-TeamRoadAlternateProbe requires -TeamRoadHordeProbe.'
}
if ($TeamRoadRestartStageOnly -and -not $TeamRoadRouteProbe) {
    throw '-TeamRoadRestartStageOnly requires -TeamRoadRouteProbe.'
}
if ($TeamRoadRestartResumeProbe -and (-not $LeaderSlotOnly -or $TeamHandoff -or
    $TeamAutonomousScoutProbe -or $TeamRoadRouteProbe)) {
    throw '-TeamRoadRestartResumeProbe requires a focused -LeaderSlotOnly reload.'
}
if ($TeamKnownPlaceScoutProbe -and -not $TeamAutonomousScoutProbe) {
    throw '-TeamKnownPlaceScoutProbe requires -TeamAutonomousScoutProbe.'
}
if ($TeamUnvisitedPlaceScoutProbe -and (-not $TeamAutonomousScoutProbe -or
    $TeamKnownPlaceScoutProbe)) {
    throw '-TeamUnvisitedPlaceScoutProbe requires a separate -TeamAutonomousScoutProbe run.'
}
if ($TeamAutonomousSearchProbe -and (-not $TeamHandoff -or $LeaderRemote -or
    $TeamLocalTravelProbe -or $TeamAutonomousScoutProbe -or $TeamRadioFixture -or
    $TeamLootSurvey -or $TeamOverlapProbe)) {
    throw '-TeamAutonomousSearchProbe requires a focused local team handoff run.'
}
if ($TeamSharedSearchProbe -and (-not $TeamAutonomousSearchProbe -or
    $TeamAutonomousSearchStageOnly -or $TeamUnvisitedInteriorSearchProbe)) {
    throw '-TeamSharedSearchProbe requires the ordinary -TeamAutonomousSearchProbe run.'
}
if ($TeamLeaderMotionProbe -and -not $TeamUnvisitedInteriorSearchProbe) {
    throw '-TeamLeaderMotionProbe requires -TeamUnvisitedInteriorSearchProbe.'
}
if ($TeamUnvisitedInteriorSearchProbe -and (-not $TeamAutonomousSearchProbe -or
    $TeamAutonomousSearchStageOnly -or $TeamAutonomousSearchResumeProbe)) {
    throw '-TeamUnvisitedInteriorSearchProbe requires a separate -TeamAutonomousSearchProbe run.'
}
if ($TeamMultifloorSearchProbe -and -not $TeamUnvisitedInteriorSearchProbe) {
    throw '-TeamMultifloorSearchProbe requires -TeamUnvisitedInteriorSearchProbe.'
}
if ($TeamMultifloorSquadProbe -and -not $TeamMultifloorSearchProbe) {
    throw '-TeamMultifloorSquadProbe requires -TeamMultifloorSearchProbe.'
}
if ($TeamAutonomousSearchStageOnly -and -not $TeamAutonomousSearchProbe) {
    throw '-TeamAutonomousSearchStageOnly requires -TeamAutonomousSearchProbe.'
}
if ($TeamAutonomousSearchResumeProbe -and (-not $LeaderSlotOnly -or $TeamHandoff -or
    $LeaderRemote -or $TeamAutonomousSearchProbe)) {
    throw '-TeamAutonomousSearchResumeProbe requires a focused -LeaderSlotOnly reload.'
}
if ($TeamLocalLootRoundTripProbe -and (-not $TeamLocalTravelProbe -or
    $TeamExtendedRouteProbe -or $TeamBuildingProbe)) {
    throw '-TeamLocalLootRoundTripProbe requires a focused local trip.'
}
if ($TeamExtendedRouteProbe -and -not ($TeamLocalTravelProbe -or ($TeamWaypointProbe -and $LeaderRemote))) {
    throw '-TeamExtendedRouteProbe requires a local trip or remote waypoint probe.'
}
if ($TeamExtendedQuietProbe -and (-not ($TeamExtendedRouteProbe -or
    $TeamExtendedReturnResumeProbe -or
    $TeamRoadRestartResumeProbe -or
    $TeamAutonomousScoutProbe -or $TeamUnvisitedInteriorSearchProbe) -or
    $TeamPursuerProbe)) {
    throw '-TeamExtendedQuietProbe requires an extended route without the pursuer probe.'
}
if ($TeamExtendedReturnProbe -and (-not $TeamExtendedRouteProbe -or
    -not $TeamHandoff -or $TeamPursuerProbe)) {
    throw '-TeamExtendedReturnProbe requires a focused extended team route.'
}
if ($TeamExtendedReturnResumeProbe -and (-not $LeaderSlotOnly -or
    $TeamHandoff -or $LeaderRemote -or -not $TeamExtendedQuietProbe -or
    $TeamExtendedReturnSourceX -le 0 -or $TeamExtendedReturnSourceY -le 0)) {
    throw '-TeamExtendedReturnResumeProbe requires a saved remote team and recorded route origin.'
}
if ($TeamCorpseStreamingProbe -and (-not $TeamExtendedRouteProbe -or
    -not $LeaderRemote -or -not $TeamWaypointProbe -or -not $TeamExtendedQuietProbe)) {
    throw '-TeamCorpseStreamingProbe requires a controlled quiet remote extended route.'
}
if ($TeamCorpseStreamingReloadProbe -and (-not $LeaderSlotOnly -or
    $TeamHandoff -or $LeaderRemote -or
    $TeamCorpseStreamVerifyX -le 0 -or $TeamCorpseStreamVerifyY -le 0)) {
    throw '-TeamCorpseStreamingReloadProbe requires an idle slot-1 reload and recorded positive corpse coordinates.'
}
if ($TeamBuildingProbe -and (-not $TeamHandoff -or -not $LeaderRemote -or
    $TeamWaypointProbe -or $TeamExtendedRouteProbe -or $TeamLootSurvey)) {
    throw '-TeamBuildingProbe requires a focused remote team run.'
}
if ($TeamWindowProbe -and -not $TeamBuildingProbe) {
    throw '-TeamWindowProbe requires -TeamBuildingProbe.'
}
if ($TeamInsideDoorProbe -and (-not $TeamBuildingProbe -or $TeamWindowProbe)) {
    throw '-TeamInsideDoorProbe requires -TeamBuildingProbe without -TeamWindowProbe.'
}
if ($TeamDoorBashProbe -and (-not $TeamBuildingProbe -or $TeamWindowProbe)) {
    throw '-TeamDoorBashProbe requires -TeamBuildingProbe without -TeamWindowProbe.'
}
if ($TeamDoorBashAutoProbe -and (-not $TeamDoorBashProbe -or $TeamInsideDoorProbe)) {
    throw '-TeamDoorBashAutoProbe requires -TeamDoorBashProbe without -TeamInsideDoorProbe.'
}
if ($TeamPursuerProbe -and (-not $TeamExtendedRouteProbe -or
    -not $LeaderRemote -or -not $TeamHandoff)) {
    throw '-TeamPursuerProbe requires a remote extended team route.'
}
if ($TeamPursuerFixture -and -not $TeamPursuerProbe) {
    throw '-TeamPursuerFixture requires -TeamPursuerProbe.'
}
if ($TeamStragglerProbe -and (-not $TeamHandoff -or -not $LeaderRemote -or
    -not $TeamWaypointProbe -or $TeamExtendedRouteProbe)) {
    throw '-TeamStragglerProbe requires a focused remote team waypoint probe.'
}
if ($TeamRestartAuditOnly -and (-not $LeaderSlotOnly -or $TeamHandoff -or $LeaderRemote)) {
    throw '-TeamRestartAuditOnly requires -LeaderSlotOnly without a new mission.'
}
if ($TeamRestartStageOnly -and (-not $TeamHandoff -or (-not $LeaderRemote -and -not $TeamLocalTravelProbe) -or $TeamWaypointProbe -or $TeamRadioFixture -or $TeamLootSurvey)) {
    throw '-TeamRestartStageOnly requires a focused remote or local team handoff run.'
}
if ($TeamOverlapProbe -and (-not $TeamHandoff -or $TeamWaypointProbe -or $TeamLootSurvey -or $TeamRadioFixture -or $TeamAllDeadCleanup -or $TeamRepeatedHandoff)) {
    throw '-TeamOverlapProbe requires a focused remote team handoff run.'
}
if ($TeamReturnReleaseProbe -and -not $TeamOverlapProbe) {
    throw '-TeamReturnReleaseProbe requires -TeamOverlapProbe.'
}
if ($TeamReturnStageOnly -and -not $TeamReturnReleaseProbe) {
    throw '-TeamReturnStageOnly requires -TeamReturnReleaseProbe.'
}
if ($TeamIdleSlotRestartProbe -and (-not $LeaderSlotOnly -or $TeamHandoff -or
    $LeaderRemote -or $TeamReturnStageOnly)) {
    throw '-TeamIdleSlotRestartProbe requires a focused -LeaderSlotOnly reload.'
}
if ($TeamAllDeadIdleRestartProbe -and -not $TeamIdleSlotRestartProbe) {
    throw '-TeamAllDeadIdleRestartProbe requires -TeamIdleSlotRestartProbe.'
}
if ($TeamCorpseReloadProbe -and -not $TeamAllDeadIdleRestartProbe) {
    throw '-TeamCorpseReloadProbe requires -TeamAllDeadIdleRestartProbe.'
}
if ($TeamAllDeadStageOnly -and -not $TeamAllDeadCleanup) {
    throw '-TeamAllDeadStageOnly requires -TeamAllDeadCleanup.'
}
if ($TeamAllDeadMenuCleanupProbe -and (-not $TeamAllDeadCleanup -or $TeamAllDeadStageOnly)) {
    throw '-TeamAllDeadMenuCleanupProbe requires -TeamAllDeadCleanup without -TeamAllDeadStageOnly.'
}
if ($TeamMenuCleanupProbe -and (-not $TeamHandoff -or -not $LeaderRemote -or
    $TeamAllDeadCleanup -or $TeamRestartStageOnly)) {
    throw '-TeamMenuCleanupProbe requires a focused remote team handoff run.'
}
if ($PerformanceBaselineOnly -and (-not $SplitScreenOnly -or $LeaderSlotOnly -or $TeamHandoff)) {
    throw '-PerformanceBaselineOnly requires a focused split-screen wrapper with no leader slot.'
}
if ($PerformancePopulation -ne 4 -and -not ($PerformanceBaselineOnly -or $TeamPerformanceProbe)) {
    throw '-PerformancePopulation 8 or 16 requires -PerformanceBaselineOnly or -TeamPerformanceProbe.'
}
if ($TeamPerformanceProbe -and (-not $TeamHandoff -or -not $LeaderRemote -or
    $PerformanceBaselineOnly -or $TeamAllDeadCleanup -or $TeamMenuCleanupProbe)) {
    throw '-TeamPerformanceProbe requires a focused remote team handoff run.'
}
if ($TeamPerformanceRouteProbe -and (-not $TeamHandoff -or -not $LeaderRemote -or
    -not $TeamWaypointProbe -or -not $TeamExtendedRouteProbe -or
    -not $TeamExtendedQuietProbe -or
    $TeamPerformanceProbe -or $PerformanceBaselineOnly -or
    $PerformancePopulation -ne 4)) {
    throw '-TeamPerformanceRouteProbe requires a focused quiet four-member extended remote route.'
}
if ($TeamPerformanceEncounterProbe -and -not ($TeamPerformanceProbe -or
    $TeamPerformanceRouteProbe)) {
    throw '-TeamPerformanceEncounterProbe requires a remote performance probe.'
}
if ($TeamLootSurvey -and -not $TeamHandoff) {
    throw '-TeamLootSurvey requires -TeamHandoff.'
}
if ($TeamLootProbe -and -not $TeamLootSurvey) {
    throw '-TeamLootProbe requires -TeamLootSurvey.'
}
if ($TeamLootVerifyOnly -and (-not $LeaderSlotOnly -or $TeamHandoff -or $LeaderRemote)) {
    throw '-TeamLootVerifyOnly requires -LeaderSlotOnly without an expedition.'
}
$validLootToken = $TeamLootVerifyToken -match '^SC-Harness-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'
$validLootType = $TeamLootVerifyItemType -match '^[A-Za-z0-9_.]{1,128}$'
if ($TeamLootVerifyOnly -and -not ($validLootToken -and $validLootType -and $TeamLootVerifyNativeId -gt 0)) {
    throw '-TeamLootVerifyOnly requires a prior run token, item type and native id.'
}
if ($TeamLootSurvey -and ($TeamRadioFixture -or $TeamWaypointProbe)) {
    throw '-TeamLootSurvey is a focused remote-container survey.'
}
if ($TeamAllDeadCleanup -and -not $TeamHandoff) {
    throw '-TeamAllDeadCleanup requires -TeamHandoff.'
}
if ($TeamRepeatedHandoff -and -not $TeamHandoff) {
    throw '-TeamRepeatedHandoff requires -TeamHandoff.'
}
if ($TeamRadioKitOnly -and (-not $LeaderSlotOnly -or $TeamHandoff -or $LeaderRemote)) {
    throw '-TeamRadioKitOnly requires -LeaderSlotOnly without an expedition.'
}
if ($TeamRadioKitVerifyOnly -and (-not $LeaderSlotOnly -or $TeamHandoff -or $LeaderRemote -or $TeamRadioKitOnly)) {
    throw '-TeamRadioKitVerifyOnly requires -LeaderSlotOnly without kit provisioning.'
}
if (-not [string]::IsNullOrWhiteSpace($HygieneEightDirectionsScreenshotDirectory)) {
    if (-not $HygieneProbe) {
        throw '-HygieneEightDirectionsScreenshotDirectory requires -HygieneProbe.'
    }
    $HygieneEightDirectionsScreenshotDirectory = [System.IO.Path]::GetFullPath(
        $HygieneEightDirectionsScreenshotDirectory)
    New-Item -ItemType Directory -Path $HygieneEightDirectionsScreenshotDirectory -Force | Out-Null
}
if ($SplitScreenOnly -ne (-not [string]::IsNullOrWhiteSpace($SplitScreenScreenshot))) {
    throw '-SplitScreenOnly requires -SplitScreenScreenshot, and that screenshot requires -SplitScreenOnly.'
}
if ($ColdRestartHandoff -ne (-not [string]::IsNullOrWhiteSpace($PostHandoffScreenshot))) {
    throw '-ColdRestartHandoff requires -PostHandoffScreenshot, and that screenshot requires -ColdRestartHandoff.'
}
if ($ColdRestartHandoff) {
    $PostHandoffScreenshot = [System.IO.Path]::GetFullPath($PostHandoffScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $PostHandoffScreenshot) -Force | Out-Null
}
if ($SplitScreenOnly) {
    $SplitScreenScreenshot = [System.IO.Path]::GetFullPath($SplitScreenScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $SplitScreenScreenshot) -Force | Out-Null
}
if ($TeamZombieVisibilityProbe -and (-not $TeamAutonomousScoutProbe -or
    -not $TeamRoadRouteProbe -or [string]::IsNullOrWhiteSpace($ZombieVisibilityScreenshot))) {
    throw '-TeamZombieVisibilityProbe requires a road scout and a screenshot path.'
}
if ($TeamZombieVisibilityProbe) {
    $ZombieVisibilityScreenshot = [System.IO.Path]::GetFullPath($ZombieVisibilityScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $ZombieVisibilityScreenshot) -Force | Out-Null
}
$captureFactionMap = -not [string]::IsNullOrWhiteSpace($FactionMapScreenshot)
if ($captureFactionMap) {
    $FactionMapScreenshot = [System.IO.Path]::GetFullPath($FactionMapScreenshot)
    $screenshotDirectory = Split-Path -Parent $FactionMapScreenshot
    if ([string]::IsNullOrWhiteSpace($screenshotDirectory)) {
        throw 'Faction-map screenshot needs an explicit parent directory.'
    }
    New-Item -ItemType Directory -Path $screenshotDirectory -Force | Out-Null
}
if ($FactionMapOnly -and -not $captureFactionMap) {
    throw '-FactionMapOnly requires -FactionMapScreenshot.'
}
if ($PathingOnly -and $FactionMapOnly) {
    throw '-PathingOnly and -FactionMapOnly are mutually exclusive.'
}
$captureBaseLayout = -not [string]::IsNullOrWhiteSpace($BaseLayoutScreenshot)
if ($captureBaseLayout) {
    $BaseLayoutScreenshot = [System.IO.Path]::GetFullPath($BaseLayoutScreenshot)
    $layoutDirectory = Split-Path -Parent $BaseLayoutScreenshot
    if ([string]::IsNullOrWhiteSpace($layoutDirectory)) {
        throw 'Base-layout screenshot needs an explicit parent directory.'
    }
    New-Item -ItemType Directory -Path $layoutDirectory -Force | Out-Null
}
if ($captureBaseLayout -ne $BaseLayoutOnly.IsPresent) {
    throw '-BaseLayoutScreenshot and -BaseLayoutOnly must be used together.'
}
if ($CompanionInventoryOnly -ne (-not [string]::IsNullOrWhiteSpace($CompanionInventoryScreenshot))) {
    throw '-CompanionInventoryOnly requires -CompanionInventoryScreenshot.'
}
if ($CompanionInventoryOnly) {
    $CompanionInventoryScreenshot = [System.IO.Path]::GetFullPath($CompanionInventoryScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $CompanionInventoryScreenshot) -Force | Out-Null
}
if ($VehiclePassengerOnly -ne (-not [string]::IsNullOrWhiteSpace($VehiclePassengerScreenshot))) {
    throw '-VehiclePassengerOnly requires -VehiclePassengerScreenshot.'
}
if ($VehiclePassengerOnly) {
    if ($HiddenWindow) { throw '-VehiclePassengerOnly requires a visible game window for capture.' }
    $VehiclePassengerScreenshot = [System.IO.Path]::GetFullPath($VehiclePassengerScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $VehiclePassengerScreenshot) -Force | Out-Null
}
if ($BaseLayoutOnly -and ($PathingOnly -or $FactionMapOnly -or $captureFactionMap)) {
    throw '-BaseLayoutOnly cannot be combined with pathing or faction-map runs.'
}
$RunsRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build\live-sandbox-runs'))
$runsPrefix = $RunsRoot.TrimEnd('\') + '\'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Test-ProjectZomboidRunning {
    $matches = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like 'ProjectZomboid*' -or
        ($_.Name -match '^java(w)?\.exe$' -and $_.CommandLine -match 'ProjectZomboid')
    })
    return $matches.Count -gt 0
}

function Add-ModEntry([string]$Text, [string]$ModId) {
    if ($Text -match ('(?m)^\s*mod\s*=\s*' + [regex]::Escape($ModId) + '\s*,?\s*$')) {
        return $Text
    }
    $pattern = New-Object regex '(?ms)(mods\s*\{\s*)'
    if (-not $pattern.IsMatch($Text)) { throw 'mods.txt has no mods block.' }
    $newline = [Environment]::NewLine
    return $pattern.Replace($Text, ('$1    mod = ' + $ModId + ',' + $newline), 1)
}

function Remove-ModEntry([string]$Text, [string]$ModId) {
    if ($ModId -notmatch '^[A-Za-z0-9_. -]{1,128}$') {
        throw "Unsafe excluded mod id: $ModId"
    }
    $pattern = New-Object regex (
        '(?m)^\s*mod\s*=\s*' + [regex]::Escape($ModId) + '\s*,?\s*\r?\n?')
    return $pattern.Replace($Text, '')
}

function Initialize-WindowInput {
    if ($null -eq ('SCLiveHarness.WindowInput' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace SCLiveHarness {
    public static class WindowInput {
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr hWnd, out Rect rect);

        [StructLayout(LayoutKind.Sequential)]
        public struct Point {
            public int X;
            public int Y;
        }

        [DllImport("user32.dll")]
        private static extern bool ClientToScreen(IntPtr hWnd, ref Point point);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out Point point);

        [DllImport("user32.dll")]
        private static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int command);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(Point point);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);

        // A background process may take the foreground only right after input;
        // a synthetic ALT tap satisfies Windows' foreground lock. Input is sent
        // only once the client really is the foreground window, so a click or
        // key can never land in another application.
        public static bool Focus(IntPtr hWnd) {
            const byte VK_MENU = 0x12;
            const uint KEYEVENTF_KEYUP = 0x0002;
            if (hWnd == IntPtr.Zero) return false;
            if (IsIconic(hWnd)) ShowWindow(hWnd, 9);
            if (GetForegroundWindow() == hWnd) return true;
            keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            System.Threading.Thread.Sleep(200);
            return GetForegroundWindow() == hWnd;
        }

        private static bool PointOnWindow(IntPtr hWnd, Point point) {
            IntPtr hit = WindowFromPoint(point);
            return hit == hWnd || GetAncestor(hit, 2) == hWnd;
        }

        [DllImport("user32.dll")]
        private static extern void mouse_event(uint flags, uint dx, uint dy,
            uint data, UIntPtr extraInfo);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte virtualKey, byte scanCode,
            uint flags, UIntPtr extraInfo);

        public static bool GetClientScreenRect(IntPtr hWnd, out Rect rect) {
            rect = new Rect();
            if (hWnd == IntPtr.Zero) return false;
            if (!GetClientRect(hWnd, out rect)) return false;
            Point topLeft = new Point { X = rect.Left, Y = rect.Top };
            Point bottomRight = new Point { X = rect.Right, Y = rect.Bottom };
            if (!ClientToScreen(hWnd, ref topLeft) ||
                !ClientToScreen(hWnd, ref bottomRight)) return false;
            rect.Left = topLeft.X;
            rect.Top = topLeft.Y;
            rect.Right = bottomRight.X;
            rect.Bottom = bottomRight.Y;
            return rect.Right > rect.Left && rect.Bottom > rect.Top;
        }

        public static bool PressVirtualKey(IntPtr hWnd, byte virtualKey) {
            const uint KEYEVENTF_KEYUP = 0x0002;
            if (!Focus(hWnd)) return false;
            System.Threading.Thread.Sleep(250);
            keybd_event(virtualKey, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(120);
            keybd_event(virtualKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            return true;
        }

        public static bool ClickClientCentre(IntPtr hWnd) {
            const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
            const uint MOUSEEVENTF_LEFTUP = 0x0004;
            Rect rect;
            if (hWnd == IntPtr.Zero || !GetClientRect(hWnd, out rect)) return false;
            Point original;
            if (!GetCursorPos(out original)) return false;
            Point centre = new Point {
                X = Math.Max(1, (rect.Right - rect.Left) / 2),
                Y = Math.Max(1, (rect.Bottom - rect.Top) / 2)
            };
            if (!ClientToScreen(hWnd, ref centre)) return false;
            if (!Focus(hWnd) || !PointOnWindow(hWnd, centre)) return false;
            System.Threading.Thread.Sleep(250);
            if (!SetCursorPos(centre.X, centre.Y)) return false;
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(180);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
            SetCursorPos(original.X, original.Y);
            return true;
        }
    }
}
'@
    }
}

function Invoke-LoadingScreenClick([System.Diagnostics.Process]$Process) {
    Initialize-WindowInput
    $Process.Refresh()
    if ($Process.HasExited -or $Process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
    return [SCLiveHarness.WindowInput]::ClickClientCentre($Process.MainWindowHandle)
}

function Invoke-WindowKey([System.Diagnostics.Process]$Process, [byte]$VirtualKey) {
    Initialize-WindowInput
    $Process.Refresh()
    if ($Process.HasExited -or $Process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
    return [SCLiveHarness.WindowInput]::PressVirtualKey(
        $Process.MainWindowHandle, $VirtualKey)
}

function Save-ClientScreenshot(
    [System.Diagnostics.Process]$Process,
    [string]$Destination
) {
    Initialize-WindowInput
    Add-Type -AssemblyName System.Drawing
    $Process.Refresh()
    if ($Process.HasExited -or $Process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
    $rect = New-Object 'SCLiveHarness.WindowInput+Rect'
    if (-not [SCLiveHarness.WindowInput]::GetClientScreenRect(
        $Process.MainWindowHandle, [ref]$rect)) { return $false }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0,
            (New-Object System.Drawing.Size($width, $height)))
        $bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    return Test-Path -LiteralPath $Destination -PathType Leaf
}

if (Test-ProjectZomboidRunning) {
    throw 'Close Project Zomboid before preparing a real sandbox harness run.'
}

$gameExe = Join-Path $GameRoot 'ProjectZomboid64.exe'
$gameConfig = Join-Path $GameRoot 'ProjectZomboid64.json'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $gameConfig -PathType Leaf)) {
    throw "Project Zomboid client was not found under $GameRoot"
}
$launcher = Get-Content -LiteralPath $gameConfig -Raw -Encoding utf8 | ConvertFrom-Json
if ($launcher.mainClass -ne 'survivorcompanion/bridge/SCLauncher') {
    throw 'The native SCLauncher is not installed; run Install-Local.ps1 -NativeBridge first.'
}
$bridgeClassPath = @($launcher.classpath | Where-Object { $_ -match 'SurvivorCompanion.*Bridge.*\.jar' })
if ($bridgeClassPath.Count -ne 1) {
    throw 'ProjectZomboid64.json does not contain exactly one SurvivorCompanion bridge classpath entry.'
}
$bridgePath = $bridgeClassPath[0].Replace('/', '\')
if (-not [System.IO.Path]::IsPathRooted($bridgePath)) { $bridgePath = Join-Path $GameRoot $bridgePath }
if (-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)) {
    throw "Native companion bridge is missing: $bridgePath"
}

$latestFile = Join-Path $UserCache 'latestSave.ini'
if ([string]::IsNullOrWhiteSpace($SeedSave)) {
    if (-not (Test-Path -LiteralPath $latestFile -PathType Leaf)) {
        throw 'No SeedSave was supplied and latestSave.ini does not exist.'
    }
    $latest = @(Get-Content -LiteralPath $latestFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($latest.Count -lt 2) { throw 'latestSave.ini must contain world and game mode.' }
    $seedName = $latest[0].Trim()
    if ([string]::IsNullOrWhiteSpace($GameMode)) { $GameMode = $latest[1].Trim() }
    $SeedSave = Join-Path (Join-Path (Join-Path $UserCache 'Saves') $GameMode) $seedName
}
$SeedSave = [System.IO.Path]::GetFullPath($SeedSave)
if ([string]::IsNullOrWhiteSpace($GameMode)) {
    $GameMode = Split-Path -Leaf (Split-Path -Parent $SeedSave)
}
if ($GameMode -notmatch '^[A-Za-z0-9 _-]{1,64}$') { throw "Unsafe game mode: $GameMode" }
if (-not (Test-Path -LiteralPath $SeedSave -PathType Container)) {
    throw "Seed save does not exist: $SeedSave"
}
$seedMods = Join-Path $SeedSave 'mods.txt'
$seedMap = Join-Path $SeedSave 'map_ver.bin'
if (-not (Test-Path -LiteralPath $seedMods -PathType Leaf) -or
    -not (Test-Path -LiteralPath $seedMap -PathType Leaf)) {
    throw 'Seed save must contain mods.txt and map_ver.bin.'
}

$runId = 'SC-Harness-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),
    ([guid]::NewGuid().ToString('N')).Substring(0, 8)
$RunRoot = [System.IO.Path]::GetFullPath((Join-Path $RunsRoot $runId))
if (-not $RunRoot.StartsWith($runsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe live harness run root: $RunRoot"
}
$CacheRoot = Join-Path $RunRoot 'cache'
$SandboxMods = Join-Path $CacheRoot 'mods'
$SandboxLua = Join-Path $CacheRoot 'Lua\SurvivorCompanionHarness'
$SandboxSaves = Join-Path (Join-Path $CacheRoot 'Saves') $GameMode
$TargetSave = Join-Path $SandboxSaves $runId

New-Item -ItemType Directory -Path $SandboxMods,$SandboxLua,$SandboxSaves -Force | Out-Null

# Copy only user preferences needed to bypass first-run UI. Saves, logs, databases,
# and the real mod list remain outside the disposable cachedir.
foreach ($name in @('options.ini', 'options2.bin', 'debuglog.ini', 'keysB42.ini', 'version.txt')) {
    $source = Join-Path $UserCache $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $CacheRoot $name)
    }
}
$bindings = Join-Path $UserCache 'InputBindings'
if (Test-Path -LiteralPath $bindings -PathType Container) {
    Copy-Item -LiteralPath $bindings -Destination (Join-Path $CacheRoot 'InputBindings') -Recurse
}

# Clone the save before any game process starts. The source save is never opened by
# the test client because -cachedir redirects every save lookup into CacheRoot.
Copy-Item -LiteralPath $SeedSave -Destination $TargetSave -Recurse

# Expose existing local/Vortex mod payloads through read-only-use junctions. The
# sandbox owns only the junction objects; the runner never cleans or writes targets.
$realMods = Join-Path $UserCache 'mods'
if (-not $LivingFellowsOnly -and (Test-Path -LiteralPath $realMods -PathType Container)) {
    foreach ($directory in Get-ChildItem -LiteralPath $realMods -Directory) {
        if ($directory.Name -eq 'SurvivorCompanion' -or
            $directory.Name -eq 'SCRealSandboxHarness') { continue }
        $link = Join-Path $SandboxMods $directory.Name
        if (-not (Test-Path -LiteralPath $link)) {
            New-Item -ItemType Junction -Path $link -Target $directory.FullName | Out-Null
        }
    }
}
$resetMarker = Join-Path $realMods 'reset-mods-42_00.txt'
if (-not (Test-Path -LiteralPath $resetMarker -PathType Leaf)) {
    throw 'Build 42 mod-reset marker is missing from the user mod directory.'
}
Copy-Item -LiteralPath $resetMarker -Destination (Join-Path $SandboxMods 'reset-mods-42_00.txt')

$privatePayloadRoot = Join-Path $RunRoot 'private-playtest-payload'
& (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') `
    -ProjectRoot $ProjectRoot -OutputRoot $privatePayloadRoot | Out-Null
$sourceMod = Join-Path $privatePayloadRoot 'SurvivorCompanion'
$harnessMod = Join-Path $ProjectRoot 'tests\live\mod\SCRealSandboxHarness'
if (-not (Test-Path -LiteralPath $sourceMod -PathType Container) -or
    -not (Test-Path -LiteralPath $harnessMod -PathType Container)) {
    throw 'Source mod or live harness mod is missing.'
}
$sourceBridge = Join-Path $sourceMod '42\media\java\SurvivorCompanionBridge.jar'
if (-not (Test-Path -LiteralPath $sourceBridge -PathType Leaf)) {
    throw "Source payload native bridge is missing: $sourceBridge"
}
$installedBridgeHash = (Get-FileHash -LiteralPath $bridgePath -Algorithm SHA256).Hash
$sourceBridgeHash = (Get-FileHash -LiteralPath $sourceBridge -Algorithm SHA256).Hash
if ($installedBridgeHash -ne $sourceBridgeHash -and -not $PrepareOnly) {
    throw 'The installed native bridge does not match the source candidate. ' +
        'Run Install-Local.ps1 -NativeBridge before the real sandbox harness.'
}
Copy-Item -LiteralPath $sourceMod -Destination (Join-Path $SandboxMods 'SurvivorCompanion') -Recurse
Copy-Item -LiteralPath $harnessMod -Destination (Join-Path $SandboxMods 'SCRealSandboxHarness') -Recurse
if ($ProjectALifeDamageProbe) {
    if ([string]::IsNullOrWhiteSpace($ProjectALifeModPath) -or
        -not (Test-Path -LiteralPath (Join-Path $ProjectALifeModPath '42.20\mod.info') -PathType Leaf)) {
        throw '-ProjectALifeDamageProbe requires -ProjectALifeModPath pointing at the ProjectALifeNPCs mod directory.'
    }
    Copy-Item -LiteralPath $ProjectALifeModPath -Destination (Join-Path $SandboxMods 'ProjectALifeNPCs') -Recurse
}

$modText = if ($LivingFellowsOnly) {
    "VERSION = 1,`r`n`r`nmods`r`n{`r`n}`r`n`r`nmaps`r`n{`r`n}`r`n"
} else {
    Get-Content -LiteralPath $seedMods -Raw -Encoding utf8
}
foreach ($excludedId in $ExcludeModId) {
    $modText = Remove-ModEntry $modText $excludedId
}
$modText = Add-ModEntry $modText 'SurvivorCompanion'
$modText = if ($ProjectALifeDamageProbe) { Add-ModEntry $modText 'ProjectALifeNPCs' } else { $modText }
$modText = Add-ModEntry $modText 'SCRealSandboxHarness'
[System.IO.File]::WriteAllText((Join-Path $SandboxMods 'default.txt'), $modText, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $TargetSave 'mods.txt'), $modText, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $CacheRoot 'latestSave.ini'),
    ($runId + [Environment]::NewLine + $GameMode + [Environment]::NewLine), $utf8NoBom)

$config = @(
    'enabled=true',
    'autoload=true',
    ('run_id=' + $runId),
    ('world=' + $runId),
    ('mode=' + $GameMode),
    ('project_alife_damage_probe=' + $ProjectALifeDamageProbe.IsPresent.ToString().ToLowerInvariant()),
    ('ui_menu_probe=' + $UIMenuProbe.IsPresent.ToString().ToLowerInvariant()),
    ('base_maintenance_probe=' + $BaseMaintenanceProbe.IsPresent.ToString().ToLowerInvariant()),
    ('hygiene_probe=' + $HygieneProbe.IsPresent.ToString().ToLowerInvariant()),
    ('hygiene_eight_directions=' +
        (-not [string]::IsNullOrWhiteSpace($HygieneEightDirectionsScreenshotDirectory)).ToString().ToLowerInvariant()),
    ('base_second_floor_probe=' + $BaseSecondFloorProbe.IsPresent.ToString().ToLowerInvariant()),
    ('water_source_probe=' + $WaterSourceProbe.IsPresent.ToString().ToLowerInvariant()),
    ('capture_faction_map=' + $captureFactionMap.ToString().ToLowerInvariant()),
    ('faction_map_only=' + $FactionMapOnly.IsPresent.ToString().ToLowerInvariant()),
    ('pathing_only=' + $PathingOnly.IsPresent.ToString().ToLowerInvariant()),
    ('place_metadata_only=' + $PlaceMetadataOnly.IsPresent.ToString().ToLowerInvariant()),
    ('split_screen_only=' + $SplitScreenOnly.IsPresent.ToString().ToLowerInvariant()),
    ('split_base_layout_probe=' + $SplitBaseLayoutProbe.IsPresent.ToString().ToLowerInvariant()),
    ('cold_companion_probe=' + $ColdCompanionProbe.IsPresent.ToString().ToLowerInvariant()),
    ('fishing_bank_probe=' + $FishingBankProbe.IsPresent.ToString().ToLowerInvariant()),
    ('fishing_map_list_probe=' + $FishingMapListProbe.IsPresent.ToString().ToLowerInvariant()),
    ('fishing_catch_probe=' + $FishingCatchProbe.IsPresent.ToString().ToLowerInvariant()),
    ('chef_recipes_probe=' + $ChefRecipesProbe.IsPresent.ToString().ToLowerInvariant()),
    ('cold_restart_probe=' + $ColdRestartProbe.IsPresent.ToString().ToLowerInvariant()),
    ('cold_restart_handoff=' + $ColdRestartHandoff.IsPresent.ToString().ToLowerInvariant()),
    ('cold_restart_crash_probe=' + $ColdRestartCrashProbe.IsPresent.ToString().ToLowerInvariant()),
    ('cold_restart_lf_first_crash_probe=' + $ColdRestartLfFirstCrashProbe.IsPresent.ToString().ToLowerInvariant()),
    ('leader_slot_only=' + $LeaderSlotOnly.IsPresent.ToString().ToLowerInvariant()),
    ('leader_remote=' + $LeaderRemote.IsPresent.ToString().ToLowerInvariant()),
    ('leader_remote_offset_x=' + $LeaderRemoteOffsetX),
    ('leader_remote_offset_y=' + $LeaderRemoteOffsetY),
    ('team_handoff=' + $TeamHandoff.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_fixture=' + $TeamRadioFixture.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_placed_probe=' + $TeamRadioPlacedProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_timed_placement_probe=' + $TeamRadioTimedPlacementProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_placed_pickup_probe=' + $TeamRadioPlacedPickupProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_placed_expected_walkie_id=' + $TeamRadioPlacedExpectedWalkieId),
    ('team_radio_placed_expected_ham_id=' + $TeamRadioPlacedExpectedHamId),
    ('team_radio_text_probe=' + $TeamRadioTextProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_command_probe=' + $TeamRadioCommandProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_waypoint_probe=' + $TeamWaypointProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_local_travel_probe=' + $TeamLocalTravelProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_local_loot_round_trip_probe=' + $TeamLocalLootRoundTripProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_extended_route_probe=' + $TeamExtendedRouteProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_extended_quiet_probe=' + $TeamExtendedQuietProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_extended_return_probe=' + $TeamExtendedReturnProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_extended_return_resume_probe=' + $TeamExtendedReturnResumeProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_extended_return_source_x=' + $TeamExtendedReturnSourceX),
    ('team_extended_return_source_y=' + $TeamExtendedReturnSourceY),
    ('team_corpse_streaming_probe=' + $TeamCorpseStreamingProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_corpse_streaming_reload_probe=' + $TeamCorpseStreamingReloadProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_corpse_stream_verify_x=' + $TeamCorpseStreamVerifyX),
    ('team_corpse_stream_verify_y=' + $TeamCorpseStreamVerifyY),
    ('team_autonomous_scout_probe=' + $TeamAutonomousScoutProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_zombie_visibility_probe=' + $TeamZombieVisibilityProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_route_probe=' + $TeamRoadRouteProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_distance_tiles=' + $TeamRoadDistanceTiles),
    ('team_road_movement_probe=' + $TeamRoadMovementProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_horde_probe=' + $TeamRoadHordeProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_blocked_radio_probe=' + $TeamRoadBlockedRadioProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_alternate_probe=' + $TeamRoadAlternateProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_restart_stage_only=' + $TeamRoadRestartStageOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_road_restart_resume_probe=' + $TeamRoadRestartResumeProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_known_place_scout_probe=' + $TeamKnownPlaceScoutProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_unvisited_place_scout_probe=' + $TeamUnvisitedPlaceScoutProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_autonomous_search_probe=' + $TeamAutonomousSearchProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_shared_search_probe=' + $TeamSharedSearchProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_leader_motion_probe=' + $TeamLeaderMotionProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_unvisited_interior_search_probe=' + $TeamUnvisitedInteriorSearchProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_multifloor_search_probe=' + $TeamMultifloorSearchProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_multifloor_squad_probe=' + $TeamMultifloorSquadProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_autonomous_search_stage_only=' + $TeamAutonomousSearchStageOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_autonomous_search_resume_probe=' + $TeamAutonomousSearchResumeProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_building_probe=' + $TeamBuildingProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_window_probe=' + $TeamWindowProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_inside_door_probe=' + $TeamInsideDoorProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_door_bash_probe=' + $TeamDoorBashProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_door_bash_auto_probe=' + $TeamDoorBashAutoProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_pursuer_probe=' + $TeamPursuerProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_pursuer_fixture=' + $TeamPursuerFixture.IsPresent.ToString().ToLowerInvariant()),
    ('team_straggler_probe=' + $TeamStragglerProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_restart_audit_only=' + $TeamRestartAuditOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_restart_stage_only=' + $TeamRestartStageOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_overlap_probe=' + $TeamOverlapProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_return_release_probe=' + $TeamReturnReleaseProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_return_stage_only=' + $TeamReturnStageOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_idle_slot_restart_probe=' + $TeamIdleSlotRestartProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_all_dead_idle_restart_probe=' + $TeamAllDeadIdleRestartProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_corpse_reload_probe=' + $TeamCorpseReloadProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_loot_survey=' + $TeamLootSurvey.IsPresent.ToString().ToLowerInvariant()),
    ('team_loot_probe=' + $TeamLootProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_loot_verify_only=' + $TeamLootVerifyOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_loot_verify_token=' + $TeamLootVerifyToken),
    ('team_loot_verify_item_type=' + $TeamLootVerifyItemType),
    ('team_loot_verify_native_id=' + $TeamLootVerifyNativeId),
    ('team_all_dead_cleanup=' + $TeamAllDeadCleanup.IsPresent.ToString().ToLowerInvariant()),
    ('team_all_dead_stage_only=' + $TeamAllDeadStageOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_all_dead_menu_cleanup_probe=' + $TeamAllDeadMenuCleanupProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_menu_cleanup_probe=' + $TeamMenuCleanupProbe.IsPresent.ToString().ToLowerInvariant()),
    ('performance_baseline_only=' + $PerformanceBaselineOnly.IsPresent.ToString().ToLowerInvariant()),
    ('performance_population_target=' + $PerformancePopulation),
    ('team_performance_probe=' + $TeamPerformanceProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_performance_route_probe=' + $TeamPerformanceRouteProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_performance_encounter_probe=' + $TeamPerformanceEncounterProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_repeated_handoff=' + $TeamRepeatedHandoff.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_kit_only=' + $TeamRadioKitOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_expedition_ui_probe=' + $TeamExpeditionUiProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_kit_verify_only=' + $TeamRadioKitVerifyOnly.IsPresent.ToString().ToLowerInvariant()),
    ('leader_watch_ms=' + ($LeaderWatchSeconds * 1000)),
    ('capture_base_layout=' + $captureBaseLayout.ToString().ToLowerInvariant()),
    ('base_layout_only=' + $BaseLayoutOnly.IsPresent.ToString().ToLowerInvariant()),
    ('companion_inventory_only=' + $CompanionInventoryOnly.IsPresent.ToString().ToLowerInvariant()),
    ('furniture_pose_only=' + $FurniturePoseOnly.IsPresent.ToString().ToLowerInvariant()),
    ('vehicle_passenger_only=' + $VehiclePassengerOnly.IsPresent.ToString().ToLowerInvariant()),
    ('woodcutter_only=' + $WoodcutterOnly.IsPresent.ToString().ToLowerInvariant()),
    ('posted_stream_only=' + $PostedStreamOnly.IsPresent.ToString().ToLowerInvariant()),
    ('internal_timeout_ms=' + (($TimeoutSeconds - 15) * 1000))
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText((Join-Path $SandboxLua 'config.ini'),
    ($config + [Environment]::NewLine), $utf8NoBom)

$manifest = [ordered]@{
    schema = 1
    runId = $runId
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    seedSave = $SeedSave
    gameMode = $GameMode
    cacheRoot = $CacheRoot
    targetSave = $TargetSave
    sourceRelease = ((Get-Content -LiteralPath (Join-Path $sourceMod 'mod.info') |
        Where-Object { $_ -match '^modversion=' }) -replace '^modversion=', '')
    sourceSaveIsReadOnlyInput = $true
    sourceBridge = $sourceBridge
    sourceBridgeSha256 = $sourceBridgeHash
    installedBridgeMatches = $installedBridgeHash -eq $sourceBridgeHash
    livingFellowsOnly = $LivingFellowsOnly.IsPresent
    excludedModIds = @($ExcludeModId)
    factionMapScreenshot = if ($captureFactionMap) { $FactionMapScreenshot } else { $null }
    factionMapOnly = $FactionMapOnly.IsPresent
    baseLayoutScreenshot = if ($captureBaseLayout) { $BaseLayoutScreenshot } else { $null }
    baseLayoutOnly = $BaseLayoutOnly.IsPresent
    companionInventoryScreenshot = if ($CompanionInventoryOnly) { $CompanionInventoryScreenshot } else { $null }
    vehiclePassengerScreenshot = if ($VehiclePassengerOnly) { $VehiclePassengerScreenshot } else { $null }
    pathingOnly = $PathingOnly.IsPresent
    splitScreenOnly = $SplitScreenOnly.IsPresent
    splitBaseLayoutProbe = $SplitBaseLayoutProbe.IsPresent
    leaderSlotOnly = $LeaderSlotOnly.IsPresent
    leaderRemote = $LeaderRemote.IsPresent
    leaderWatchSeconds = $LeaderWatchSeconds
    splitScreenScreenshot = if ($SplitScreenOnly) { $SplitScreenScreenshot } else { $null }
    autoCleanup = $false
}
[System.IO.File]::WriteAllText((Join-Path $RunRoot 'run-manifest.json'),
    ($manifest | ConvertTo-Json -Depth 4), $utf8NoBom)

$summaryPath = Join-Path $SandboxLua 'summary.txt'
$eventsPath = Join-Path $SandboxLua 'events.log'
$consolePath = Join-Path $CacheRoot 'console.txt'
$performanceActivePath = Join-Path $SandboxLua 'performance-sampling-active.txt'
$processSamplePath = Join-Path $SandboxLua 'performance-process.csv'
$factionMapReadyPath = Join-Path $SandboxLua 'faction-map-ready.txt'
$factionMapVisiblePath = Join-Path $SandboxLua 'faction-map-visible.txt'
$factionMapCapturedPath = Join-Path $SandboxLua 'faction-map-captured.txt'
$zombieVisibilityReadyPath = Join-Path $SandboxLua 'zombie-visibility-ready.txt'
$zombieVisibilityCapturedPath = Join-Path $SandboxLua 'zombie-visibility-captured.txt'
Write-Output "Prepared isolated live sandbox: $RunRoot"
Write-Output "Source save remains untouched: $SeedSave"
if ($PrepareOnly) {
    Write-Output "LIVE_SANDBOX_PREPARED run=$runId cache=$CacheRoot"
    Write-Output "Source bridge for isolated Java launch: $sourceBridge"
    Write-Output 'Prepare-only does not change the installed launcher or start its bridge.'
    return
}

$argumentLine = '-cachedir="' + $CacheRoot + '" -nosound -novoip -debuglog=+General,+Lua'
$startOptions = @{
    FilePath = $gameExe
    WorkingDirectory = $GameRoot
    ArgumentList = $argumentLine
    PassThru = $true
}
if ($HiddenWindow) { $startOptions.WindowStyle = 'Hidden' }
$process = Start-Process @startOptions
Write-Output "Started real Project Zomboid client test pid=$($process.Id)"

function Stop-OwnedSandboxProcess {
    param([System.Diagnostics.Process]$OwnedProcess, [string]$Reason)
    if ($null -eq $OwnedProcess) { return }
    try { $OwnedProcess.Refresh() } catch { return }
    if ($OwnedProcess.HasExited) { return }
    Stop-Process -Id $OwnedProcess.Id -Force -ErrorAction Stop
    [void]$OwnedProcess.WaitForExit(10000)
    Write-Output "Stopped owned live sandbox client pid=$($OwnedProcess.Id) reason=$Reason"
}

try {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextLoadingClick = [DateTime]::MaxValue
    $loadingReadyObserved = $false
    $clickAttempts = 0
    $factionMapCaptureCompleted = $false
    $splitScreenCaptureCompleted = $false
    $zombieVisibilityCaptureCompleted = $false
    $postHandoffCaptureCompleted = $false
    $crashProbeCompleted = $false
    $hygieneCaptureCompleted = $false
    $nextProcessSample = [DateTime]::MinValue
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Live sandbox client exited before writing a summary (exit=$($process.ExitCode)). Run retained at $RunRoot"
        }
        if (($PerformanceBaselineOnly -or $TeamPerformanceProbe -or
            $TeamPerformanceRouteProbe) -and
            (Test-Path -LiteralPath $performanceActivePath -PathType Leaf) -and
            (Select-String -LiteralPath $performanceActivePath -Pattern '^active=' -Quiet) -and
            [DateTime]::UtcNow -ge $nextProcessSample) {
            if (-not (Test-Path -LiteralPath $processSamplePath -PathType Leaf)) {
                [System.IO.File]::WriteAllText($processSamplePath,
                    "utc,private_bytes,working_set_bytes,cpu_total_s`n", $utf8NoBom)
            }
            $process.Refresh()
            $cpuText = $process.TotalProcessorTime.TotalSeconds.ToString(
                'F3', [Globalization.CultureInfo]::InvariantCulture)
            $sampleLine = '{0},{1},{2},{3}' -f [DateTime]::UtcNow.ToString('o'),
                $process.PrivateMemorySize64, $process.WorkingSet64, $cpuText
            [System.IO.File]::AppendAllText($processSamplePath,
                ($sampleLine + "`n"), $utf8NoBom)
            $nextProcessSample = [DateTime]::UtcNow.AddSeconds(1)
        }
        if (-not $loadingReadyObserved -and (Test-Path -LiteralPath $consolePath -PathType Leaf)) {
            $loadingReadyObserved = Select-String -LiteralPath $consolePath `
                -SimpleMatch 'game loading took' -Quiet
            if ($loadingReadyObserved) {
                $nextLoadingClick = [DateTime]::UtcNow.AddMilliseconds(750)
                Write-Output 'World load completed; waiting for the Build 42 click-to-start gate.'
            }
        }
        if ($loadingReadyObserved -and [DateTime]::UtcNow -ge $nextLoadingClick -and
            -not (Test-Path -LiteralPath $eventsPath -PathType Leaf)) {
            $clickAttempts++
            if (Invoke-LoadingScreenClick $process) {
                Write-Output "Sent isolated click-to-start attempt $clickAttempts to pid=$($process.Id)"
            }
            $nextLoadingClick = [DateTime]::UtcNow.AddSeconds(3)
        }
        if ($HygieneProbe -and -not $hygieneCaptureCompleted -and
            -not [string]::IsNullOrWhiteSpace($HygieneScreenshot) -and
            (Test-Path -LiteralPath $eventsPath -PathType Leaf) -and
            (Select-String -LiteralPath $eventsPath -SimpleMatch 'PASS|hygiene_screenshot|' -Quiet)) {
            if (-not (Save-ClientScreenshot $process $HygieneScreenshot)) {
                throw "Could not capture hygiene pose to $HygieneScreenshot"
            }
            Write-Output "Captured hygiene pose: $HygieneScreenshot"
            $hygieneCaptureCompleted = $true
        }
        if ($captureFactionMap -and -not $factionMapCaptureCompleted -and
            (Test-Path -LiteralPath $factionMapReadyPath -PathType Leaf)) {
            # 0x4D is the physical M key. Keep the map open until the in-game
            # harness has observed ISWorldMap and at least one faction-house draw.
            if (-not (Invoke-WindowKey $process 0x4D)) {
                throw 'Could not focus the client and send the M key.'
            }
            Write-Output 'Sent M to open the player map for faction-marker verification.'
            $visibleDeadline = [DateTime]::UtcNow.AddSeconds(10)
            while ([DateTime]::UtcNow -lt $visibleDeadline -and
                -not (Test-Path -LiteralPath $factionMapVisiblePath -PathType Leaf)) {
                $process.Refresh()
                if ($process.HasExited) { break }
                Start-Sleep -Milliseconds 200
            }
            if (-not (Test-Path -LiteralPath $factionMapVisiblePath -PathType Leaf)) {
                throw 'The game did not confirm a rendered faction house after M was pressed.'
            }
            Start-Sleep -Milliseconds 750
            if (-not (Save-ClientScreenshot $process $FactionMapScreenshot)) {
                throw "Could not capture the Project Zomboid client to $FactionMapScreenshot"
            }
            Write-Output "Captured faction player-map screenshot: $FactionMapScreenshot"
            if (-not (Invoke-WindowKey $process 0x4D)) {
                throw 'Could not send M to close the player map after capture.'
            }
            [System.IO.File]::WriteAllText($factionMapCapturedPath,
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            $factionMapCaptureCompleted = $true
        }
        if ($SplitScreenOnly -and -not $splitScreenCaptureCompleted -and
            (Test-Path -LiteralPath (Join-Path $SandboxLua 'split-screen-ready.txt') -PathType Leaf)) {
            Start-Sleep -Milliseconds 1200
            if (-not (Save-ClientScreenshot $process $SplitScreenScreenshot)) {
                throw "Could not capture the split-screen client to $SplitScreenScreenshot"
            }
            [System.IO.File]::WriteAllText((Join-Path $SandboxLua 'split-screen-captured.txt'),
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            Write-Output "Captured split-screen screenshot: $SplitScreenScreenshot"
            $splitScreenCaptureCompleted = $true
        }
        if ($TeamZombieVisibilityProbe -and -not $zombieVisibilityCaptureCompleted -and
            (Test-Path -LiteralPath $zombieVisibilityReadyPath -PathType Leaf)) {
            Start-Sleep -Milliseconds 500
            if (-not (Save-ClientScreenshot $process $ZombieVisibilityScreenshot)) {
                throw "Could not capture the zombie encounter to $ZombieVisibilityScreenshot"
            }
            [System.IO.File]::WriteAllText($zombieVisibilityCapturedPath,
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            Write-Output "Captured companion zombie encounter: $ZombieVisibilityScreenshot"
            $zombieVisibilityCaptureCompleted = $true
        }
        if ($ColdRestartHandoff -and -not $postHandoffCaptureCompleted -and
            (Test-Path -LiteralPath (Join-Path $SandboxLua 'split-restored-ready.txt') -PathType Leaf)) {
            Start-Sleep -Milliseconds 1200
            if (-not (Save-ClientScreenshot $process $PostHandoffScreenshot)) {
                throw "Could not capture the restored companion client to $PostHandoffScreenshot"
            }
            [System.IO.File]::WriteAllText((Join-Path $SandboxLua 'split-restored-captured.txt'),
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            Write-Output "Captured restored companion screenshot: $PostHandoffScreenshot"
            $postHandoffCaptureCompleted = $true
        }
        if (($ColdRestartCrashProbe -or $ColdRestartLfFirstCrashProbe) -and
            (Test-Path -LiteralPath (Join-Path $SandboxLua 'split-crash-ready.txt') -PathType Leaf)) {
            Stop-OwnedSandboxProcess $process 'forced_cold_handoff_save_boundary'
            $crashProbeCompleted = $true
            break
        }
        if ($captureBaseLayout -and -not $baseLayoutCaptureCompleted -and
            (Test-Path -LiteralPath (Join-Path $SandboxLua 'base-layout-ready.txt') -PathType Leaf)) {
            # 0x23 is the physical End key, the base layout hotkey's default.
            if (-not (Invoke-WindowKey $process 0x23)) {
                throw 'Could not focus the client and send the End key.'
            }
            Write-Output 'Sent End to show the base layout overlay.'
            $layoutVisiblePath = Join-Path $SandboxLua 'base-layout-visible.txt'
            $visibleDeadline = [DateTime]::UtcNow.AddSeconds(10)
            while ([DateTime]::UtcNow -lt $visibleDeadline -and
                -not (Test-Path -LiteralPath $layoutVisiblePath -PathType Leaf)) {
                $process.Refresh()
                if ($process.HasExited) { break }
                Start-Sleep -Milliseconds 200
            }
            if (-not (Test-Path -LiteralPath $layoutVisiblePath -PathType Leaf)) {
                throw 'The game did not confirm the base layout overlay after End was pressed.'
            }
            Start-Sleep -Milliseconds 1200
            if (-not (Save-ClientScreenshot $process $BaseLayoutScreenshot)) {
                throw "Could not capture the Project Zomboid client to $BaseLayoutScreenshot"
            }
            Write-Output "Captured base layout screenshot: $BaseLayoutScreenshot"
            if (-not (Invoke-WindowKey $process 0x23)) {
                throw 'Could not send End to hide the base layout after capture.'
            }
            [System.IO.File]::WriteAllText((Join-Path $SandboxLua 'base-layout-captured.txt'),
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            $baseLayoutCaptureCompleted = $true
        }
        if ($CompanionInventoryOnly -and -not $companionInventoryCaptureCompleted -and
            (Test-Path -LiteralPath (Join-Path $SandboxLua 'companion-inventory-ready.txt') -PathType Leaf)) {
            Start-Sleep -Milliseconds 1000
            if (-not (Save-ClientScreenshot $process $CompanionInventoryScreenshot)) {
                throw "Could not capture the companion inventory to $CompanionInventoryScreenshot"
            }
            [System.IO.File]::WriteAllText((Join-Path $SandboxLua 'companion-inventory-captured.txt'),
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            Write-Output "Captured companion inventory screenshot: $CompanionInventoryScreenshot"
            $companionInventoryCaptureCompleted = $true
        }
        if ($VehiclePassengerOnly -and -not $vehiclePassengerCaptureCompleted -and
            (Test-Path -LiteralPath (Join-Path $SandboxLua 'vehicle-passenger-ready.txt') -PathType Leaf)) {
            Start-Sleep -Milliseconds 1000
            if (-not (Save-ClientScreenshot $process $VehiclePassengerScreenshot)) {
                throw "Could not capture the vehicle passenger to $VehiclePassengerScreenshot"
            }
            [System.IO.File]::WriteAllText((Join-Path $SandboxLua 'vehicle-passenger-captured.txt'),
                ('captured=true' + [Environment]::NewLine), $utf8NoBom)
            Write-Output "Captured vehicle passenger: $VehiclePassengerScreenshot"
            $vehiclePassengerCaptureCompleted = $true
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $crashProbeCompleted -and -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "Live sandbox test timed out. Run retained at $RunRoot; inspect $consolePath."
    }
} catch {
    Stop-OwnedSandboxProcess $process 'runner_failure'
    throw
}

if ($crashProbeCompleted) {
    Get-Content -LiteralPath $eventsPath -ErrorAction SilentlyContinue
    Write-Output "LIVE_SANDBOX_FORCED_CRASH run=$runId save=$TargetSave results=$eventsPath"
    return
}

$summary = Get-Content -LiteralPath $summaryPath
$statusLine = $summary | Where-Object { $_ -match '^status=' } | Select-Object -First 1
$status = $statusLine -replace '^status=', ''
$exitDeadline = [DateTime]::UtcNow.AddSeconds(15)
while ([DateTime]::UtcNow -lt $exitDeadline) {
    $process.Refresh()
    if ($process.HasExited) { break }
    Start-Sleep -Milliseconds 250
}
$process.Refresh()
if (-not $process.HasExited) {
    Stop-OwnedSandboxProcess $process 'post_summary_deadline'
}

Get-Content -LiteralPath $eventsPath -ErrorAction SilentlyContinue
if (-not [string]::IsNullOrWhiteSpace($HygieneEightDirectionsScreenshotDirectory)) {
    $directionNames = @('N','NE','E','SE','S','SW','W','NW')
    $sourceDirectory = Join-Path $CacheRoot 'Screenshots'
    foreach ($directionName in $directionNames) {
        $source = Join-Path $sourceDirectory ($runId + '-pee-' + $directionName)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Missing hygiene direction screenshot: $source"
        }
        $destination = Join-Path $HygieneEightDirectionsScreenshotDirectory `
            ('pee-' + $directionName + '.png')
        Copy-Item -LiteralPath $source -Destination $destination -Force
        Write-Output "Hygiene direction $directionName screenshot: $destination"
    }
}
Write-Output "Live sandbox run retained for audit: $RunRoot"
Write-Output "Live console: $consolePath"
if ($captureFactionMap) {
    Write-Output "Faction map screenshot: $FactionMapScreenshot"
}
if ($SplitScreenOnly) { Write-Output "Split-screen screenshot: $SplitScreenScreenshot" }
if ($CompanionInventoryOnly) { Write-Output "Companion inventory screenshot: $CompanionInventoryScreenshot" }
if ($VehiclePassengerOnly) { Write-Output "Vehicle passenger screenshot: $VehiclePassengerScreenshot" }
if ($TeamZombieVisibilityProbe) { Write-Output "Zombie visibility screenshot: $ZombieVisibilityScreenshot" }
if ($PerformanceBaselineOnly -or $TeamPerformanceProbe -or $TeamPerformanceRouteProbe) {
    Write-Output "Performance samples: $SandboxLua"
}
if ($ColdRestartHandoff) { Write-Output "Restored companion screenshot: $PostHandoffScreenshot" }
if ($status -ne 'PASS') {
    throw "LIVE_SANDBOX_FAIL run=$runId results=$eventsPath"
}
Write-Output "LIVE_SANDBOX_PASS run=$runId results=$eventsPath"
