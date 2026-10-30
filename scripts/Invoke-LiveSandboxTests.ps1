# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$UserCache = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'),
    [string]$SeedSave,
    [string]$GameMode,
    [ValidateRange(45, 4500)]
    # Large mod lists can spend more than three minutes in script, map and
    # asset loading before Build 42 exposes its click-to-start gate. The
    # in-game harness retains its own bounded deadline once play begins.
    [int]$TimeoutSeconds = 300,
    # Load the save, leave every companion alone for this long and log what
    # they do. Zero runs the ordinary harness checks instead.
    [ValidateRange(0, 3600)][int]$ObserveSeconds = 0,
    [switch]$ObserveMenusClosed,
    # Natural sleep-cycle control, without seeding companion fatigue.
    [ValidateSet(1, 2, 3)][int]$ObserveSpeed = 1,
    # Safely cancel a blocked recovered cook job in the cloned save before observation.
    [switch]$RestartChefBeforeObserve,
    # Disposable regression: put an inbound upstairs team in the former
    # permanent path-stall hold, then require it to descend and resume travel.
    [switch]$ObserveInboundReturnFault,
    [switch]$HiddenWindow,
    # Launch through the user's Steam client when a direct executable launch
    # cannot initialize SteamAPI. The direct path remains the default.
    [switch]$SteamLaunch,
    # Let a separate UI controller handle the Build 42 start gate. This runner
    # still owns the isolated save, process, logs, and result checks.
    [switch]$ExternalUiControl,
    # Run an isolated clone with the game's supported offline switch when
    # Steam cannot start from this desktop session.
    [switch]$NoSteam,
    # Use this checkout's bridge only in the disposable direct-Java process.
    # The installed game launcher and bridge remain untouched.
    [switch]$IsolatedSourceBridge,
    # Optional exact bridge for old/new native comparisons in isolated clones.
    [string]$IsolatedBridgePath = '',
    [string]$SteamExe = 'C:\Program Files (x86)\Steam\steam.exe',
    [switch]$LivingFellowsOnly,
    [switch]$CompanionFirearmsProbe,
    [switch]$CompanionFacingProbe,
    [ValidateSet('fresh', 'saved', 'both')][string]$CompanionFacingMode = 'fresh',
    [switch]$BanditsAdapterProbe,
    [switch]$BanditsEnabled,
    [ValidateSet('legacy', 'firearms', 'firearms_zombie_control', 'melee', 'unarmed', 'infected', 'lifecycle', 'armor', 'vehicle_window', 'vehicle_bullets', 'solid_wall', 'protected_lane')][string]$BanditsCombatScenario = 'legacy',
    [ValidateSet('random', 'policeofficer', 'veteran', 'unemployed')][string]$BanditsLFProfession = 'random',
    [ValidateSet(2, 4)][int]$BanditsCombatants = 2,
    [ValidateSet('weapons_free', 'close_defense', 'ranged_support', 'stealth')][string]$BanditsCombatDoctrine = 'weapons_free',
    [ValidateSet('before', 'after')][string]$BanditsLoadOrder = 'after',
    [ValidateSet('saved', 'resident', 'household', 'strange_folk', 'strange_folk_save', 'performance', 'reload')][string]$BanditsLFRole = 'saved',
    [ValidatePattern('^(sc-[A-Za-z0-9.+-]+)?$')][string]$BanditsExpectedLFId = '',
    [string]$BanditsModPath = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3268487204\mods\Bandits',
    [switch]$UIMenuProbe,
    [switch]$UserOptionsProbe,
    [switch]$MedicalCheckProbe,
    [switch]$BaseMaintenanceProbe,
    [switch]$FloorSortProbe,
    [switch]$VehicleRefuelProbe,
    [switch]$VehicleUpkeepProbe,
    [switch]$FieldWorkProbe,
    [switch]$FieldCargoProbe,
    [switch]$GuardFollowProbe,
    [switch]$GeneratorRefuelProbe,
    [switch]$PyreBurnProbe,
    [switch]$UpstairsHaulProbe,
    [switch]$OfficeHaulProbe,
    [switch]$OfficeHaulSurveyOnly,
    [switch]$OfficeHaulBaseline,
    [switch]$BaseAlertProbe,
    # Boards the seed save's "Maintain this barricade" target with a real worker.
    [switch]$BarricadeProbe,
    [switch]$BarricadeHardening,
    [switch]$BarricadeMatrixOnly,
    # Exercise real rendered wall cutaways across companion-view releases.
    [switch]$ViewCutawayProbe,
    [switch]$ViewCutawayQuickWatch,
    [ValidateSet('observe', 'B', 'C')]
    [string]$ViewCutawayRestoreMode = 'B',
    [ValidateRange(1, 3)][int]$ViewCutawayCycles = 3,
    # Use a saved crew/car and the ordinary expedition controller, then capture
    # the kitchen after the crew returns naturally.
    [switch]$NormalExpeditionKitchenProbe,
    [ValidateSet(1, 2)][int]$NormalExpeditionKitchenCrewSize = 2,
    # Existing Scarlet/car46, real trees and axes, ordinary production task.
    # Run each mode in a fresh disposable clone: one walking or two driving logs.
    [switch]$WoodExpeditionProbe,
    [ValidateSet('walk', 'drive')][string]$WoodExpeditionTravelMode = 'walk',
    [ValidateSet(1, 3)][int]$WoodExpeditionCrewSize = 1,
    # Observation budget only; never changes the mission's own return timer.
    [ValidateRange(120, 1500)][int]$WoodExpeditionDeadlineSeconds = 780,
    # Explicit disposable fixture: seed one real axe into permitted camp
    # storage only when the saved camp has no usable permitted axe.
    [switch]$WoodExpeditionStockEquipment,
    # Explicit disposable happy-path fixture; removes nearby zombies only
    # at the work site so cargo transport can be checked independently.
    [switch]$WoodExpeditionQuietSite,
    [string]$PyreBurnScreenshot = '',
    [switch]$HygieneProbe,
    [switch]$OddballCoreyProbe,
    [switch]$OddballEarlProbe,
    [switch]$OddballArthurProbe,
    [switch]$OddballArthurBedSurveyOnly,
    [switch]$OddballArthurHeadSideTrial,
    [switch]$OddballArthurPlayerBaseline,
    [switch]$OddballPackProbe,
    [switch]$OddballSmokerProbe,
    [ValidateRange(0, 20000)][int]$OddballSiteX = 0,
    [ValidateRange(0, 20000)][int]$OddballSiteY = 0,
    [ValidateRange(0, 20000)][int]$OddballBedX = 0,
    [ValidateRange(0, 20000)][int]$OddballBedY = 0,
    [switch]$OddballPoseOnly,
    [string]$OddballSceneScreenshot = '',
    [string]$HygieneScreenshot = '',
    [string]$HygieneEightDirectionsScreenshotDirectory = '',
    [string]$StrangeFolkPortraitScreenshotDirectory = '',
    [ValidateSet('all', 'red', 'kevin', 'wendell')]
    [string]$StrangeFolkPortraitTarget = 'all',
    [switch]$WendellApproachProbe,
    [switch]$DeputyRhondaProbe,
    [string]$DeputyRhondaScreenshot = '',
    [switch]$LorettaProbe,
    [string]$LorettaScreenshot = '',
    [ValidateRange(0, 20000)][int]$LorettaSiteX = 0,
    [ValidateRange(0, 20000)][int]$LorettaSiteY = 0,
    [switch]$MilliProbe,
    [string]$MilliScreenshot = '',
    [ValidateRange(0, 20000)][int]$MilliSiteX = 0,
    [ValidateRange(0, 20000)][int]$MilliSiteY = 0,
    [switch]$BaseSecondFloorProbe,
    [switch]$WaterSourceProbe,
    [switch]$FarmCorridorProbe,
    # A companion drives a spawned car on a straight road near the observer.
    [switch]$DrivingProbe,
    # Real player drives one car while an assigned companion follows in another.
    [switch]$ConvoyProbe,
    # Stage A of Markus's taxi: real player remains in a native passenger seat.
    [switch]$TaxiPassengerProbe,
    # Markus radio booking through a hidden physical pickup and free road ride.
    [switch]$TaxiCallProbe,
    # Real parked-driver firing at an inert zombie before the passenger boards.
    [switch]$TaxiDefenseProbe,
    # A repeat booking from a completed fare: 200+ tiles, paid with gold necklace.
    [switch]$TaxiCallLongPaid,
    # Reproduce a repeat pickup across the road and record the native turn.
    [switch]$TaxiTurnDiagnostic,
    # Save the booked player and Markus during the physical taxi ride.
    [switch]$TaxiCallStage,
    # Resume that same taxi, actor, passenger, booking, and fare in a new game.
    [switch]$TaxiCallResume,
    # Resume the paid taxi stage from its retained clone to prove a cold reload.
    [switch]$TaxiRecoveryResume,
    # With -DrivingProbe: drive an expedition-planner route round one wreck,
    # turn round, and drive back round two, instead of the mechanics checks.
    [switch]$DrivingRoute,
    # With -DrivingProbe: drive a planner route round a junction into a side street.
    [switch]$DrivingTurn,
    # Leave normal companion Decision scheduled during the route test.
    [switch]$DrivingWithAi,
    # Disposable-cache negative control: remove Decision's driving gate.
    [switch]$DrivingGateNegativeControl,
    # Exercise the production job's bounded alternate route around a full block.
    [switch]$DrivingBlocked,
    # Save a moving seat-zero driver, then reload its retained clone with Resume.
    [switch]$DrivingSaveStage,
    [switch]$DrivingSaveResume,
    # Step 2 gate: a slot-1 companion drives after player 0 leaves its loaded area.
    [switch]$DrivingRemote,
    # Step 2: mark parking and run a three-companion car expedition end to end.
    [switch]$TeamDriveProbe,
    # Send the same squad to a real building roughly 150 tiles away to search.
    [switch]$TeamDriveScavengeProbe,
    # Optional exact site ID for a repeatable real-building search probe.
    [string]$TeamDriveScavengeSiteId = '',
    # Revisit the roadside stop that previously stranded the team during its turn.
    [switch]$TeamDriveObstacleProbe,
    # Stage a three-person mission while driving, then reload the retained clone.
    [switch]$TeamDriveRestartStage,
    [switch]$TeamDriveRestartResume,
    # With -DrivingProbe: save driving-cruise.png at cruising speed and
    # driving-crash.png after the crash test into this directory.
    [string]$DrivingScreenshotDirectory = '',
    [switch]$ProjectALifeDamageProbe,
    [switch]$ProjectALifeAdapterProbe,
    [switch]$ProjectALifeEnabled,
    [ValidateSet('combat', 'reload_stage', 'reload', 'performance')][string]$ProjectALifeScenario = 'combat',
    [ValidateSet('pistol', 'melee')][string]$ProjectALifeWeapon = 'pistol',
    [switch]$ProjectALifeObserveHousehold,
    [ValidateSet('member', 'resident', 'household', 'strange_folk')][string]$ProjectALifeRole = 'member',
    [ValidateSet('before', 'after')][string]$ProjectALifeLoadOrder = 'after',
    [string]$ProjectALifeModPath = '',
    [string[]]$ExcludeModId = @(),
    [string]$FactionMapScreenshot = '',
    [switch]$FactionMapOnly,
    [string]$BaseLayoutScreenshot = '',
    [switch]$BaseLayoutOnly,
    [string]$CompanionInventoryScreenshot = '',
    [switch]$CompanionInventoryOnly,
    [switch]$CompanionTransferProbe,
    [switch]$GiftedEquipmentProbe,
    # Repeated native squad-versus-zombie survival trials in a cloned save.
    [switch]$SquadCombatProbe,
    [switch]$SquadCombatFrontOnly,
    [switch]$SquadCombatSingleCase,
    [ValidateRange(1, 6)][int]$SquadCombatCaseIndex = 1,
    [ValidateRange(0, 5)][int]$SquadCombatCompanions = 0,
    [ValidateRange(1, 16)][int[]]$SquadCombatZombieCounts = @(),
    [switch]$SquadCombatNaturalAcquisition,
    [switch]$SquadCombatPassiveControl,
    [ValidateSet('Base.Crowbar', 'Base.Pen', 'Base.HuntingKnife', 'Base.Shovel', 'Base.GardenHoe', 'Base.WoodenMallet', 'Base.Wrench')]
    [string]$SquadCombatWeaponType = 'Base.Crowbar',
    [ValidateSet('Base.Crowbar', 'Base.WoodenMallet', 'Base.Wrench')]
    [string[]]$SquadCombatWeaponTypes = @(),
    [ValidateRange(0.0, 1.0)][double]$SquadCombatFatigue = 0.0,
    [ValidateSet('inherit', 'on', 'off')][string]$SquadCombatMultiHit = 'inherit',
    [ValidateSet('stay', 'follow')][string]$SquadCombatOrder = 'stay',
    [string]$SquadCombatBackupWeaponType = '',
    [switch]$SquadCombatPhoto,
    [switch]$SquadCombatNearObserver,
    [switch]$SquadCombatRadioLure,
    [switch]$SquadCombatBaseline,
    [ValidateRange(1, 5)][int]$SquadCombatTrials = 3,
    [ValidateRange(30, 300)][int]$SquadCombatSeconds = 55,
    [switch]$FurniturePoseOnly,
    [switch]$SleepProbe,
    [switch]$FirestationRestProbe,
    [switch]$FirestationRestGroup,
    [ValidateRange(1, 5)][int]$FirestationRestFirstTrial = 1,
    [switch]$VehiclePassengerOnly,
    [switch]$SixSeatProbe,
    [string]$VehiclePassengerScreenshot = '',
    [switch]$WoodcutterOnly,
    [switch]$PostedStreamOnly,
    [switch]$PathingOnly,
    # Cloned-save 50-tile player road run with per-second Follow gap trace.
    [switch]$FollowRoadProbe,
    # Compare the same road run with the team's open formation enabled.
    [switch]$FollowRoadFanOut,
    # Move unrelated recruits to a safe Stay point so their care needs cannot
    # pull the measured trio off the route in a movement-only comparison.
    [switch]$FollowRoadIsolated,
    # Diagnostic A/B: use committed Follow/medical modules in the disposable
    # sandbox while retaining the current live probe and runner.
    [switch]$FollowRoadBaseline,
    # Permit a diagnostic run with the same bridge bytecode when only the
    # packaged release label changed. All other JAR differences still fail.
    [switch]$AllowManifestVersionMismatch,
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
    # An isolated short search that deposits its exact returned item into a
    # real marked camp container before releasing the second view.
    [switch]$TeamExpeditionIntegrationProbe,
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
    [switch]$TeamExpeditionZoomOnly,
    [switch]$TeamRadioKitVerifyOnly,
    [ValidateRange(8, 180)][int]$LeaderWatchSeconds = 8,
    [string]$SplitScreenScreenshot = '',
    [string]$ZombieVisibilityScreenshot = '',
    [string]$PostHandoffScreenshot = '',
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
# The loading-gate agent JAR is built with ZipFile, which Windows
# PowerShell 5.1 does not load by default.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
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
if ($OddballCoreyProbe -and $OddballEarlProbe) {
    throw 'Choose one focused oddball probe per cloned-save run.'
}
if ($WoodExpeditionStockEquipment -and -not $WoodExpeditionProbe) {
    throw '-WoodExpeditionStockEquipment requires -WoodExpeditionProbe.'
}
if ($ViewCutawayQuickWatch -and -not $ViewCutawayProbe) {
    throw '-ViewCutawayQuickWatch requires -ViewCutawayProbe.'
}
if ($WoodExpeditionQuietSite -and -not $WoodExpeditionProbe) {
    throw '-WoodExpeditionQuietSite requires -WoodExpeditionProbe.'
}
if ((@($OddballCoreyProbe, $OddballEarlProbe, $OddballArthurProbe,
    $OddballPackProbe, $OddballSmokerProbe, $MilliProbe) | Where-Object { $_ }).Count -gt 1) {
    throw 'Choose one focused oddball probe per cloned-save run.'
}
if (($OddballSiteX -gt 0) -ne ($OddballSiteY -gt 0) -or
    (($OddballSiteX -gt 0 -or $OddballSiteY -gt 0) -and
        -not ($OddballArthurProbe -or $OddballPackProbe -or $OddballSmokerProbe))) {
    throw '-OddballSiteX and -OddballSiteY must be positive together and require an Arthur, Pack, or Smoker probe.'
}
if (($OddballBedX -gt 0) -ne ($OddballBedY -gt 0) -or
    (($OddballBedX -gt 0 -or $OddballBedY -gt 0) -and -not $OddballArthurProbe)) {
    throw '-OddballBedX and -OddballBedY must be positive together and require -OddballArthurProbe.'
}
if ($OddballPoseOnly -and -not $OddballArthurProbe) {
    throw '-OddballPoseOnly requires -OddballArthurProbe.'
}
if ($OddballArthurPlayerBaseline -and -not $OddballArthurProbe) {
    throw '-OddballArthurPlayerBaseline requires -OddballArthurProbe.'
}
if ($OddballArthurBedSurveyOnly -and -not $OddballArthurProbe) {
    throw '-OddballArthurBedSurveyOnly requires -OddballArthurProbe.'
}
if ($OddballArthurHeadSideTrial -and -not $OddballArthurProbe) {
    throw '-OddballArthurHeadSideTrial requires -OddballArthurProbe.'
}
$captureOddballScene = -not [string]::IsNullOrWhiteSpace($OddballSceneScreenshot)
if ($captureOddballScene) {
    if (-not ($OddballArthurProbe -or $OddballPackProbe -or $OddballSmokerProbe) -or $HiddenWindow) {
        throw '-OddballSceneScreenshot requires an Arthur, Pack, or Smoker probe and a visible game window.'
    }
    $OddballSceneScreenshot = [System.IO.Path]::GetFullPath($OddballSceneScreenshot)
    if (Test-Path -LiteralPath $OddballSceneScreenshot) {
        throw "Oddball scene screenshot already exists: $OddballSceneScreenshot"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $OddballSceneScreenshot) -Force | Out-Null
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
if ($TeamExpeditionIntegrationProbe -and -not $TeamAutonomousSearchProbe) {
    throw '-TeamExpeditionIntegrationProbe requires -TeamAutonomousSearchProbe.'
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
if ($TeamExpeditionZoomOnly -and (-not $TeamRadioKitOnly -or -not $TeamExpeditionUiProbe)) {
    throw '-TeamExpeditionZoomOnly requires -TeamRadioKitOnly and -TeamExpeditionUiProbe.'
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
$captureStrangeFolkPortraits = -not [string]::IsNullOrWhiteSpace(
    $StrangeFolkPortraitScreenshotDirectory)
if (-not $captureStrangeFolkPortraits -and $StrangeFolkPortraitTarget -ne 'all') {
    throw '-StrangeFolkPortraitTarget requires -StrangeFolkPortraitScreenshotDirectory.'
}
if ($WendellApproachProbe -and (-not $captureStrangeFolkPortraits -or
    $StrangeFolkPortraitTarget -ne 'wendell')) {
    throw '-WendellApproachProbe requires one Wendell portrait screenshot.'
}
$strangeFolkPortraitLabels = if ($StrangeFolkPortraitTarget -eq 'all') {
    @('red', 'kevin', 'wendell')
} else { @($StrangeFolkPortraitTarget) }
if ($captureStrangeFolkPortraits) {
    if ($HiddenWindow) {
        throw '-StrangeFolkPortraitScreenshotDirectory requires a visible game window.'
    }
    $StrangeFolkPortraitScreenshotDirectory = [System.IO.Path]::GetFullPath(
        $StrangeFolkPortraitScreenshotDirectory)
    if (Test-Path -LiteralPath $StrangeFolkPortraitScreenshotDirectory -PathType Leaf) {
        throw 'Strange Folk portrait destination is a file, not a directory.'
    }
    New-Item -ItemType Directory -Path $StrangeFolkPortraitScreenshotDirectory -Force | Out-Null
    foreach ($portrait in $strangeFolkPortraitLabels) {
        $destination = Join-Path $StrangeFolkPortraitScreenshotDirectory ($portrait + '.png')
        if (Test-Path -LiteralPath $destination) {
            throw "Strange Folk portrait already exists; choose a fresh directory: $destination"
        }
    }
}
$captureDeputyRhonda = -not [string]::IsNullOrWhiteSpace($DeputyRhondaScreenshot)
if ($captureDeputyRhonda) {
    if (-not $DeputyRhondaProbe -or $HiddenWindow) {
        throw '-DeputyRhondaScreenshot requires -DeputyRhondaProbe and a visible game window.'
    }
    $DeputyRhondaScreenshot = [System.IO.Path]::GetFullPath($DeputyRhondaScreenshot)
    if (Test-Path -LiteralPath $DeputyRhondaScreenshot) {
        throw "Deputy Rhonda screenshot already exists; choose a fresh path: $DeputyRhondaScreenshot"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $DeputyRhondaScreenshot) -Force | Out-Null
}
$captureLoretta = -not [string]::IsNullOrWhiteSpace($LorettaScreenshot)
if (($LorettaSiteX -gt 0) -ne ($LorettaSiteY -gt 0) -or
    (($LorettaSiteX -gt 0 -or $LorettaSiteY -gt 0) -and -not $LorettaProbe)) {
    throw '-LorettaSiteX and -LorettaSiteY must be positive together and require -LorettaProbe.'
}
if ($captureLoretta) {
    if (-not $LorettaProbe -or $HiddenWindow) {
        throw '-LorettaScreenshot requires -LorettaProbe and a visible game window.'
    }
    $LorettaScreenshot = [System.IO.Path]::GetFullPath($LorettaScreenshot)
    if (Test-Path -LiteralPath $LorettaScreenshot) {
        throw "Loretta screenshot already exists; choose a fresh path: $LorettaScreenshot"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $LorettaScreenshot) -Force | Out-Null
}
$captureMilli = -not [string]::IsNullOrWhiteSpace($MilliScreenshot)
if (($MilliSiteX -gt 0) -ne ($MilliSiteY -gt 0) -or
    (($MilliSiteX -gt 0 -or $MilliSiteY -gt 0) -and -not $MilliProbe)) {
    throw '-MilliSiteX and -MilliSiteY must be positive together and require -MilliProbe.'
}
if ($captureMilli) {
    if (-not $MilliProbe -or $HiddenWindow) {
        throw '-MilliScreenshot requires -MilliProbe and a visible game window.'
    }
    $MilliScreenshot = [System.IO.Path]::GetFullPath($MilliScreenshot)
    if (Test-Path -LiteralPath $MilliScreenshot) {
        throw "Milli screenshot already exists; choose a fresh path: $MilliScreenshot"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $MilliScreenshot) -Force | Out-Null
}
if ($PyreBurnProbe -ne (-not [string]::IsNullOrWhiteSpace($PyreBurnScreenshot))) {
    throw '-PyreBurnProbe requires -PyreBurnScreenshot.'
}
if ($PyreBurnProbe -and $status -eq 'PASS') {
    $PyreBurnScreenshot = [System.IO.Path]::GetFullPath($PyreBurnScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $PyreBurnScreenshot) -Force | Out-Null
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
if ($DrivingRoute -and -not $DrivingProbe) { throw '-DrivingRoute requires -DrivingProbe.' }
if ($ConvoyProbe -and -not $DrivingProbe) { throw '-ConvoyProbe requires -DrivingProbe.' }
if ($TaxiPassengerProbe -and -not $DrivingProbe) {
    throw '-TaxiPassengerProbe requires -DrivingProbe.'
}
if ($TaxiCallProbe -and -not $DrivingProbe) {
    throw '-TaxiCallProbe requires -DrivingProbe.'
}
if ($TaxiDefenseProbe -and -not $TaxiCallProbe) {
    throw '-TaxiDefenseProbe requires -TaxiCallProbe.'
}
if ($TaxiCallStage -and -not $TaxiCallProbe) {
    throw '-TaxiCallStage requires -TaxiCallProbe.'
}
if ($TaxiCallLongPaid -and (-not $TaxiCallProbe -or $TaxiCallStage)) {
    throw '-TaxiCallLongPaid requires -TaxiCallProbe without -TaxiCallStage.'
}
if ($TaxiCallLongPaid -and [string]::IsNullOrWhiteSpace($SeedSave)) {
    throw '-TaxiCallLongPaid requires a completed first-fare -SeedSave.'
}
if ($TaxiTurnDiagnostic -and -not $TaxiCallLongPaid) {
    throw '-TaxiTurnDiagnostic requires -TaxiCallLongPaid.'
}
if ($TaxiCallResume -and -not $DrivingProbe) {
    throw '-TaxiCallResume requires -DrivingProbe.'
}
if ($TaxiRecoveryResume -and -not $DrivingProbe) {
    throw '-TaxiRecoveryResume requires -DrivingProbe.'
}
if ($DrivingTurn -and -not $DrivingProbe) { throw '-DrivingTurn requires -DrivingProbe.' }
if ($DrivingTurn -and $DrivingRoute) { throw 'Choose -DrivingRoute or -DrivingTurn, not both.' }
if ($DrivingWithAi -and (-not $DrivingProbe -or -not $DrivingRoute)) {
    throw '-DrivingWithAi requires -DrivingProbe -DrivingRoute.'
}
if ($DrivingGateNegativeControl -and
    (-not $DrivingProbe -or -not $DrivingRoute -or -not $DrivingWithAi)) {
    throw '-DrivingGateNegativeControl requires -DrivingProbe -DrivingRoute -DrivingWithAi.'
}
$drivingExclusiveModes = @($DrivingRoute, $DrivingTurn, $DrivingBlocked,
    $DrivingSaveStage, $DrivingSaveResume, $DrivingRemote, $TeamDriveProbe, $ConvoyProbe,
    $TaxiPassengerProbe, $TaxiCallProbe, $TaxiCallResume,
    $TaxiRecoveryResume) | Where-Object { $_.IsPresent }
# Taxi booking can reuse the turn probe's real junction and roadside observer.
# Its service controller still owns the pickup and ride, not the turn scenario.
$taxiJunctionCombination = $TaxiCallProbe -and $DrivingTurn -and $drivingExclusiveModes.Count -eq 2
if ($drivingExclusiveModes.Count -gt 1 -and -not $taxiJunctionCombination) {
    throw 'Choose one driving route, turn, blocked, save-stage, or save-resume mode.'
}
if (($DrivingBlocked -or $DrivingSaveStage -or $DrivingSaveResume -or $DrivingRemote -or $TeamDriveProbe) -and -not $DrivingProbe) {
    throw 'Driving blocked and save modes require -DrivingProbe.'
}
if ($TeamDriveScavengeProbe -and (-not $TeamDriveProbe -or -not $DrivingProbe)) {
    throw '-TeamDriveScavengeProbe requires -DrivingProbe -TeamDriveProbe.'
}
if ($TeamDriveObstacleProbe -and -not $TeamDriveScavengeProbe) {
    throw '-TeamDriveObstacleProbe requires -TeamDriveScavengeProbe.'
}
if ($DrivingSaveResume -and [string]::IsNullOrWhiteSpace($SeedSave)) {
    throw '-DrivingSaveResume requires -SeedSave pointing at a retained stage clone.'
}
if ($TaxiRecoveryResume -and [string]::IsNullOrWhiteSpace($SeedSave)) {
    throw '-TaxiRecoveryResume requires -SeedSave pointing at a retained taxi stage clone.'
}
if ($TaxiCallResume -and [string]::IsNullOrWhiteSpace($SeedSave)) {
    throw '-TaxiCallResume requires -SeedSave pointing at a retained taxi call stage clone.'
}
if (($TeamDriveRestartStage -or $TeamDriveRestartResume) -and
    (-not $TeamDriveProbe -or -not $DrivingProbe -or
        $TeamDriveRestartStage.IsPresent -eq $TeamDriveRestartResume.IsPresent)) {
    throw 'Choose one team-drive restart stage or resume mode with -DrivingProbe -TeamDriveProbe.'
}
if ($TeamDriveRestartResume -and [string]::IsNullOrWhiteSpace($SeedSave)) {
    throw '-TeamDriveRestartResume requires -SeedSave pointing at a retained stage clone.'
}
if ($ExternalUiControl -and $HiddenWindow) {
    throw '-ExternalUiControl requires a visible game window.'
}
if ($SquadCombatPhoto -and -not $SquadCombatProbe) {
    throw '-SquadCombatPhoto requires -SquadCombatProbe.'
}
if ($SquadCombatNearObserver -and -not $SquadCombatProbe) {
    throw '-SquadCombatNearObserver requires -SquadCombatProbe.'
}
if ($SquadCombatRadioLure -and -not $SquadCombatProbe) {
    throw '-SquadCombatRadioLure requires -SquadCombatProbe.'
}
if ($SquadCombatSingleCase -and -not $SquadCombatProbe) {
    throw '-SquadCombatSingleCase requires -SquadCombatProbe.'
}
if ($SquadCombatCompanions -gt 0 -or $SquadCombatZombieCounts.Count -gt 0 -or $SquadCombatNaturalAcquisition -or $SquadCombatPassiveControl -or $SquadCombatWeaponTypes.Count -gt 0 -or $SquadCombatFatigue -gt 0 -or $SquadCombatMultiHit -ne 'inherit' -or $SquadCombatOrder -ne 'stay') {
    if (-not $SquadCombatProbe) { throw 'Custom combat scenarios require -SquadCombatProbe.' }
    if (($SquadCombatCompanions -gt 0) -ne ($SquadCombatZombieCounts.Count -gt 0)) {
        throw 'Specify custom companion and zombie counts together.'
    }
    if ($SquadCombatZombieCounts.Count -gt 6) { throw 'At most six custom combat cases are supported per run.' }
}
if ($ExternalUiControl -and -not [string]::IsNullOrWhiteSpace($DrivingScreenshotDirectory)) {
    throw 'Use the external UI controller for screenshots with -ExternalUiControl.'
}
if (-not [string]::IsNullOrWhiteSpace($DrivingScreenshotDirectory)) {
    if (-not $DrivingProbe) { throw '-DrivingScreenshotDirectory requires -DrivingProbe.' }
    if ($HiddenWindow) { throw '-DrivingScreenshotDirectory requires a visible game window for capture.' }
    $DrivingScreenshotDirectory = [System.IO.Path]::GetFullPath($DrivingScreenshotDirectory)
    New-Item -ItemType Directory -Path $DrivingScreenshotDirectory -Force | Out-Null
}
if ($VehiclePassengerOnly) {
    if ($HiddenWindow) { throw '-VehiclePassengerOnly requires a visible game window for capture.' }
    $VehiclePassengerScreenshot = [System.IO.Path]::GetFullPath($VehiclePassengerScreenshot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $VehiclePassengerScreenshot) -Force | Out-Null
}
if ($SteamLaunch -and $HiddenWindow -and -not $PrepareOnly) {
    throw '-SteamLaunch needs a visible game window; Steam does not pass Start-Process window style to the game.'
}
if ($SteamLaunch -and $NoSteam) {
    throw '-NoSteam requires the direct Project Zomboid launcher.'
}
if ($IsolatedBridgePath) {
    if (-not $IsolatedSourceBridge) { throw '-IsolatedBridgePath requires -IsolatedSourceBridge.' }
    if (-not (Test-Path -LiteralPath $IsolatedBridgePath -PathType Leaf) -or
        [IO.Path]::GetExtension($IsolatedBridgePath) -ine '.jar') {
        throw '-IsolatedBridgePath requires an existing exact .jar file.'
    }
    $IsolatedBridgePath = (Resolve-Path -LiteralPath $IsolatedBridgePath).Path
}
if ($IsolatedSourceBridge -and $SteamLaunch) {
    throw '-IsolatedSourceBridge requires the direct isolated-Java launch.'
}
if ($RestartChefBeforeObserve -and $ObserveSeconds -le 0) {
    throw '-RestartChefBeforeObserve requires -ObserveSeconds.'
}
if ($ObserveMenusClosed -and $ObserveSeconds -le 0) {
    throw '-ObserveMenusClosed requires -ObserveSeconds.'
}
if ($BaseLayoutOnly -and ($PathingOnly -or $FactionMapOnly -or $captureFactionMap)) {
    throw '-BaseLayoutOnly cannot be combined with pathing or faction-map runs.'
}
$RunsRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build\live-sandbox-runs'))
$runsPrefix = $RunsRoot.TrimEnd('\') + '\'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Test-ProjectZomboidRunning {
    try {
        $matches = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -like 'ProjectZomboid*' -or
            ($_.Name -match '^java(w)?\.exe$' -and $_.CommandLine -match 'ProjectZomboid')
        })
    } catch {
        # Restricted desktop sessions may deny WMI process command lines.
        # The game executable name remains available through Get-Process.
        $matches = @(Get-Process -Name 'ProjectZomboid64', 'ProjectZomboid32' `
            -ErrorAction SilentlyContinue)
    }
    return $matches.Count -gt 0
}

function Test-CachedirLaunchArgument {
    param([string]$CommandLine, [string]$ExpectedCacheRoot)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $cache = [regex]::Escape($ExpectedCacheRoot)
    # Steam may quote the complete argument instead of only the path.
    return $CommandLine -match ('(?i)(?:^|\s)(?:"-cachedir=' + $cache +
        '"|-cachedir=(?:"' + $cache + '"|' + $cache + '))(?=\s|$)')
}

function Get-SteamLaunchedClient {
    param(
        [int[]]$ExistingProcessIds,
        [string]$ExpectedExecutable,
        [string]$ExpectedCacheRoot,
        [string]$ConsolePath,
        [datetime]$LaunchUtc
    )
    # Steam can pass the request to an already-running client. Its process
    # handle is not the game's, so discover only a new Project Zomboid PID.
    $newClients = @{}
    foreach ($client in @(Get-Process -Name 'ProjectZomboid64' -ErrorAction SilentlyContinue)) {
        if ($client.Id -notin $ExistingProcessIds) { $newClients[$client.Id] = $client }
    }
    $details = @{}
    try {
        foreach ($entry in @(Get-CimInstance Win32_Process `
                -Filter "Name = 'ProjectZomboid64.exe'" -ErrorAction Stop)) {
            $id = [int]$entry.ProcessId
            if ($id -in $ExistingProcessIds) { continue }
            $details[$id] = $entry
            if (-not $newClients.ContainsKey($id)) {
                try { $newClients[$id] = [System.Diagnostics.Process]::GetProcessById($id) }
                catch { }
            }
        }
    } catch {
        # WMI command lines may be unavailable in a restricted desktop session.
        # In that case the unique new PID and newly written cloned console are
        # required together before the harness claims ownership.
    }

    $argumentMatches = @()
    $consoleFallback = @()
    foreach ($id in @($newClients.Keys)) {
        $client = $newClients[$id]
        $entry = $details[$id]
        $actualPath = $null
        if ($null -ne $entry) { $actualPath = $entry.ExecutablePath }
        if ([string]::IsNullOrWhiteSpace($actualPath)) {
            try { $actualPath = $client.Path } catch { }
        }
        if (-not [string]::IsNullOrWhiteSpace($actualPath) -and
            -not [string]::Equals([System.IO.Path]::GetFullPath($actualPath),
                $ExpectedExecutable, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $commandLine = if ($null -ne $entry) { $entry.CommandLine } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($commandLine)) {
            if (Test-CachedirLaunchArgument $commandLine $ExpectedCacheRoot) {
                $argumentMatches += $client
            }
        } else {
            $consoleFallback += $client
        }
    }
    if ($argumentMatches.Count -eq 1) { return $argumentMatches[0] }
    if ($argumentMatches.Count -gt 1) {
        throw 'More than one new Project Zomboid client uses the isolated cachedir.'
    }
    if ($consoleFallback.Count -eq 1 -and
        (Test-Path -LiteralPath $ConsolePath -PathType Leaf) -and
        (Get-Item -LiteralPath $ConsolePath).LastWriteTimeUtc -ge $LaunchUtc.AddSeconds(-2)) {
        return $consoleFallback[0]
    }
    return $null
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
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

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

        // The game polls its own mouse state and ignores posted window clicks.
        // Foreground input is retained for Steam-owned visible test clients.
        public static string ClickOwnedClientCentre(IntPtr hWnd, uint processId) {
            if (hWnd == IntPtr.Zero) return "missing_window";
            uint owner;
            if (GetWindowThreadProcessId(hWnd, out owner) == 0 || owner != processId)
                return "window_owner_mismatch";
            if (ClickClientCentre(hWnd)) return "foreground";
            return "window_not_foreground";
        }
    }
}
'@
    }
}

function Invoke-LoadingScreenClick([System.Diagnostics.Process]$Process) {
    if ($ExternalUiControl) { return 'external_control' }
    Initialize-WindowInput
    $Process.Refresh()
    if ($Process.HasExited) { return 'process_exited' }
    return [SCLiveHarness.WindowInput]::ClickOwnedClientCentre(
        $Process.MainWindowHandle, [uint32]$Process.Id)
}

function Invoke-WindowKey([System.Diagnostics.Process]$Process, [byte]$VirtualKey) {
    if ($ExternalUiControl) { return $false }
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
    if ($ExternalUiControl) { return $false }
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

if ($BarricadeHardening -and -not $BarricadeProbe) {
    throw '-BarricadeHardening requires -BarricadeProbe.'
}
if ($FirestationRestGroup -and -not $FirestationRestProbe) {
    throw '-FirestationRestGroup requires -FirestationRestProbe.'
}
if ($BarricadeMatrixOnly -and -not $BarricadeHardening) {
    throw '-BarricadeMatrixOnly requires -BarricadeHardening.'
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
$bridgeClassPath = @($launcher.classpath | Where-Object {
    $_ -match '^(?:SurvivorCompanion|LivingFellows).*Bridge.*\.jar$'
})
if ($bridgeClassPath.Count -ne 1) {
    throw 'ProjectZomboid64.json does not contain exactly one Living Fellows bridge classpath entry.'
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
if ($ObserveSeconds -gt 0 -and $TimeoutSeconds -lt ($ObserveSeconds + 240)) {
    $TimeoutSeconds = $ObserveSeconds + 240
}
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
$drivingStageProof = $null
$drivingExpected = @{}
$taxiExpected = @{}
$taxiCallExpected = @{}
if ($TaxiCallResume) {
    $taxiCallProof = Join-Path $SeedSave 'SC-taxi-call-stage-proof.txt'
    if (-not (Test-Path -LiteralPath $taxiCallProof -PathType Leaf)) {
        throw '-TaxiCallResume needs the proof file from a passing taxi call stage.'
    }
    foreach ($line in Get-Content -LiteralPath $taxiCallProof) {
        if ($line -match '^([a-z_]+)=([A-Za-z0-9:._-]+)$') {
            $taxiCallExpected[$matches[1]] = $matches[2]
        }
    }
    if ($taxiCallExpected.sql_id -notmatch '^[0-9]{1,16}$' -or
        $taxiCallExpected.driver_id -notmatch '^[A-Za-z0-9:._-]{1,96}$' -or
        $taxiCallExpected.booking_generation -notmatch '^[0-9]{1,10}$' -or
        $taxiCallExpected.receipt_id -notmatch '^markus-fare:[0-9]{1,10}$') {
        throw 'The retained taxi call stage proof is incomplete or malformed.'
    }
}
if ($TaxiRecoveryResume) {
    $taxiProof = Join-Path $SeedSave 'SC-taxi-stage-proof.txt'
    if (-not (Test-Path -LiteralPath $taxiProof -PathType Leaf)) {
        throw '-TaxiRecoveryResume needs the proof file from a passing taxi passenger clone.'
    }
    foreach ($line in Get-Content -LiteralPath $taxiProof) {
        if ($line -match '^([a-z_]+)=([A-Za-z0-9:._-]+)$') {
            $taxiExpected[$matches[1]] = $matches[2]
        }
    }
    if ($taxiExpected.sql_id -notmatch '^[0-9]{1,16}$' -or
        $taxiExpected.ring_id -notmatch '^[0-9]{1,16}$' -or
        $taxiExpected.receipt_id -notmatch '^markus-fare:[0-9]{1,10}$') {
        throw 'The retained taxi stage proof is incomplete or malformed.'
    }
}
if ($DrivingSaveResume) {
    $drivingStageProof = Join-Path $SeedSave 'SC-driving-stage-proof.txt'
    if (-not (Test-Path -LiteralPath $drivingStageProof -PathType Leaf)) {
        throw '-DrivingSaveResume needs the proof file written after a passing -DrivingSaveStage clone.'
    }
    foreach ($line in Get-Content -LiteralPath $drivingStageProof) {
        if ($line -match '^([a-z_]+)=([A-Za-z0-9:._-]+)$') {
            $drivingExpected[$matches[1]] = $matches[2]
        }
    }
    if ($drivingExpected.actor_id -notmatch '^[A-Za-z0-9:._-]{1,96}$' -or
        $drivingExpected.sql_id -notmatch '^[0-9]{1,16}$' -or
        $drivingExpected.key_id -notmatch '^[0-9]{1,16}$' -or
        $drivingExpected.key_location -cnotmatch '^(inventory|ignition)$' -or
        $drivingExpected.car_x -notmatch '^[0-9]+(\.[0-9]+)?$' -or
        $drivingExpected.car_y -notmatch '^[0-9]+(\.[0-9]+)?$') {
        throw 'The retained driving stage proof is incomplete or malformed.'
    }
}
$teamDriveExpected = @{}
if ($TeamDriveRestartResume) {
    $teamProof = Join-Path $SeedSave 'SC-team-drive-stage-proof.txt'
    if (-not (Test-Path -LiteralPath $teamProof -PathType Leaf)) {
        throw '-TeamDriveRestartResume needs the proof file from a passing stage clone.'
    }
    foreach ($line in Get-Content -LiteralPath $teamProof) {
        if ($line -match '^([a-z_]+)=([A-Za-z0-9:._-]+)$') {
            $teamDriveExpected[$matches[1]] = $matches[2]
        }
    }
    if ($teamDriveExpected.sql_id -notmatch '^[0-9]{1,16}$' -or
        $teamDriveExpected.leader_id -notmatch '^[A-Za-z0-9:._-]{1,96}$' -or
        $teamDriveExpected.parking_id -notmatch '^[A-Za-z0-9:._-]{1,128}$') {
        throw 'The retained team-drive stage proof is incomplete or malformed.'
    }
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
if ($IsolatedBridgePath) { $sourceBridge = $IsolatedBridgePath }
if (-not (Test-Path -LiteralPath $sourceBridge -PathType Leaf)) {
    throw "Source payload native bridge is missing: $sourceBridge"
}
$installedBridgeHash = (Get-FileHash -LiteralPath $bridgePath -Algorithm SHA256).Hash
$sourceBridgeHash = (Get-FileHash -LiteralPath $sourceBridge -Algorithm SHA256).Hash
if ($installedBridgeHash -ne $sourceBridgeHash -and -not $PrepareOnly -and
    -not $IsolatedSourceBridge) {
    $versionOnly = $false
    if ($AllowManifestVersionMismatch) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $installedArchive = [IO.Compression.ZipFile]::OpenRead($bridgePath)
        $sourceArchive = [IO.Compression.ZipFile]::OpenRead($sourceBridge)
        try {
            $installedEntries = @{}
            foreach ($entry in $installedArchive.Entries) {
                $installedEntries[$entry.FullName] = $entry
            }
            $versionOnly = $installedEntries.Count -eq $sourceArchive.Entries.Count
            foreach ($entry in $sourceArchive.Entries) {
                if (-not $versionOnly) { break }
                $other = $installedEntries[$entry.FullName]
                if ($null -eq $other) { $versionOnly = $false; break }
                $sourceStream = $entry.Open()
                $installedStream = $other.Open()
                try {
                    $sourceMemory = [IO.MemoryStream]::new()
                    $installedMemory = [IO.MemoryStream]::new()
                    $sourceStream.CopyTo($sourceMemory)
                    $installedStream.CopyTo($installedMemory)
                    if ($entry.FullName -eq 'META-INF/MANIFEST.MF') {
                        $sourceText = [Text.Encoding]::UTF8.GetString($sourceMemory.ToArray())
                        $installedText = [Text.Encoding]::UTF8.GetString($installedMemory.ToArray())
                        $pattern = '(?m)^Implementation-Version:[^\r\n]*'
                        $sourceText = [regex]::Replace($sourceText, $pattern,
                            'Implementation-Version: RELEASE')
                        $installedText = [regex]::Replace($installedText, $pattern,
                            'Implementation-Version: RELEASE')
                        $versionOnly = $sourceText -ceq $installedText
                    } else {
                        $versionOnly = [System.Collections.StructuralComparisons]::
                            StructuralEqualityComparer.Equals(
                                $sourceMemory.ToArray(), $installedMemory.ToArray())
                    }
                } finally {
                    $sourceStream.Dispose()
                    $installedStream.Dispose()
                }
            }
        } finally {
            $installedArchive.Dispose()
            $sourceArchive.Dispose()
        }
    }
    if (-not $versionOnly) {
        throw 'The installed native bridge does not match the source candidate. ' +
            'Run Install-Local.ps1 -NativeBridge before the real sandbox harness.'
    }
    Write-Output 'Installed bridge class bytes match source; only the manifest release label differs.'
}
if ($IsolatedSourceBridge) {
    Write-Output "Using source bridge in isolated Java process: $sourceBridge"
}
Copy-Item -LiteralPath $sourceMod -Destination (Join-Path $SandboxMods 'SurvivorCompanion') -Recurse
Copy-Item -LiteralPath $harnessMod -Destination (Join-Path $SandboxMods 'SCRealSandboxHarness') -Recurse
if ($ViewCutawayProbe -or $NormalExpeditionKitchenProbe -or $WoodExpeditionProbe -or $SplitScreenOnly) {
    # Keep view diagnostics focused. Unrelated large probes can exceed
    # Kahlua's debug-local limit when native stock-player diagnostics are enabled.
    $wallHarnessClient = [IO.Path]::GetFullPath((Join-Path $SandboxMods `
        'SCRealSandboxHarness\42\media\lua\client'))
    if (-not $wallHarnessClient.StartsWith($runsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Wall probe fixture is outside the owned run: $wallHarnessClient"
    }
    foreach ($fixtureFile in Get-ChildItem -LiteralPath $wallHarnessClient -File -Filter '*.lua') {
        if ($fixtureFile.Name -notin @('SCRealSandboxHarness.lua', 'SCViewCutawayProbe.lua',
                'SCNormalExpeditionKitchenProbe.lua', 'SCWoodExpeditionProbe.lua', 'SCALifeAdapterProbe.lua')) {
            Remove-Item -LiteralPath $fixtureFile.FullName -Force
        }
    }
}
if ($OfficeHaulBaseline) {
    if (-not $OfficeHaulProbe) { throw 'OfficeHaulBaseline requires OfficeHaulProbe.' }
    foreach ($name in @('SCProduction.lua', 'SCNavigation.lua', 'SCNavTraversal.lua')) {
        $relative = 'SurvivorCompanion/42/media/lua/client/' + $name
        $baselineText = & git -C $ProjectRoot show "HEAD:$relative"
        if ($LASTEXITCODE -ne 0) { throw "Could not load office-haul baseline: $relative" }
        $targetPath = Join-Path $SandboxMods ($relative -replace '/', '\')
        [System.IO.File]::WriteAllText($targetPath,
            (($baselineText -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    }
    Write-Output 'Restored committed corpse-hauling and navigation modules in the disposable sandbox.'
}
if ($FollowRoadBaseline) {
    if (-not $FollowRoadProbe) { throw 'FollowRoadBaseline requires FollowRoadProbe.' }
    foreach ($relative in @(
        'SurvivorCompanion/42/media/lua/client/SCDecision.lua',
        'SurvivorCompanion/42/media/lua/client/SCMedical.lua',
        'SurvivorCompanion/42/media/lua/client/SCPositioning.lua')) {
        $baselineText = & git -C $ProjectRoot show "HEAD:$relative"
        if ($LASTEXITCODE -ne 0) { throw "Could not load Follow baseline: $relative" }
        $targetPath = Join-Path $SandboxMods ($relative -replace '/', '\')
        [System.IO.File]::WriteAllText($targetPath,
            (($baselineText -join "`n") + "`n"),
            [System.Text.UTF8Encoding]::new($false))
    }
    Write-Output 'Restored committed Follow and medical modules in the disposable sandbox.'
}
if ($SquadCombatBaseline) {
    if (-not $SquadCombatProbe) { throw 'SquadCombatBaseline requires SquadCombatProbe.' }
    foreach ($relative in @(
        'SurvivorCompanion/42/media/lua/client/SCCombat.lua',
        'SurvivorCompanion/42/media/lua/client/SCNativeActions.lua')) {
        $baselineText = & git -C $ProjectRoot show "HEAD:$relative"
        if ($LASTEXITCODE -ne 0) { throw "Could not load combat baseline: $relative" }
        $targetPath = Join-Path $SandboxMods ($relative -replace '/', '\')
        [System.IO.File]::WriteAllText($targetPath,
            (($baselineText -join "`n") + "`n"),
            [System.Text.UTF8Encoding]::new($false))
    }
}
if ($DrivingGateNegativeControl) {
    $cachedDecision = Join-Path $SandboxMods `
        'SurvivorCompanion\42\media\lua\client\SCDecision.lua'
    if (-not (Test-Path -LiteralPath $cachedDecision -PathType Leaf)) {
        throw "Isolated driving decision module is missing: $cachedDecision"
    }
    $decisionText = [System.IO.File]::ReadAllText($cachedDecision)
    $driveGate = '        and SC.Driving.isDriving(actor) then'
    $disabledGate = '        and false and SC.Driving.isDriving(actor) then'
    $matchCount = [regex]::Matches($decisionText,
        [regex]::Escape($driveGate)).Count
    if ($matchCount -ne 1) {
        throw "Expected one isolated driving gate, found $matchCount in $cachedDecision"
    }
    [System.IO.File]::WriteAllText($cachedDecision,
        $decisionText.Replace($driveGate, $disabledGate), $utf8NoBom)
    Write-Output 'Disabled the driving gate only in the disposable sandbox mod copy.'
}
if ($BanditsAdapterProbe -or $BanditsEnabled) {
    if (-not (Test-Path -LiteralPath (Join-Path $BanditsModPath '42.21\mod.info') -PathType Leaf)) {
        throw 'BanditsAdapterProbe requires the official Bandits 42.21 payload.'
    }
    Copy-Item -LiteralPath $BanditsModPath -Destination (Join-Path $SandboxMods 'Bandits') -Recurse
}
if ($ProjectALifeDamageProbe -or $ProjectALifeAdapterProbe -or $ProjectALifeEnabled) {
    if ([string]::IsNullOrWhiteSpace($ProjectALifeModPath) -or
        -not (Test-Path -LiteralPath (Join-Path $ProjectALifeModPath '42.20\mod.info') -PathType Leaf)) {
        throw '-ProjectALifeDamageProbe requires -ProjectALifeModPath pointing at the ProjectALifeNPCs mod directory.'
    }
    Copy-Item -LiteralPath $ProjectALifeModPath -Destination (Join-Path $SandboxMods 'ProjectALifeNPCs') -Recurse
}
if ($FieldCargoProbe) {
    # Exact installed test dependencies, copied only into the disposable cache.
    $cargoWorkshopRoot = Join-Path (Split-Path (Split-Path $GameRoot -Parent) -Parent) 'workshop\content\108600'
    foreach ($cargoDependency in @(
        @{ Id = '3171167894'; Name = 'damnlib' },
        @{ Id = '3073430075'; Name = '93fordF350' }
    )) {
        $cargoSource = Join-Path $cargoWorkshopRoot ($cargoDependency.Id + '\mods\' + $cargoDependency.Name)
        if (-not (Test-Path -LiteralPath $cargoSource -PathType Container)) {
            throw "Field cargo probe dependency is not installed: $cargoSource"
        }
        $cargoDestination = Join-Path $SandboxMods $cargoDependency.Name
        if (-not (Test-Path -LiteralPath $cargoDestination)) {
            Copy-Item -LiteralPath $cargoSource -Destination $cargoDestination -Recurse
        }
    }
}

$modText = if ($LivingFellowsOnly) {
    "VERSION = 1,`r`n`r`nmods`r`n{`r`n}`r`n`r`nmaps`r`n{`r`n}`r`n"
} else {
    Get-Content -LiteralPath $seedMods -Raw -Encoding utf8
}
foreach ($excludedId in $ExcludeModId) {
    $modText = Remove-ModEntry $modText $excludedId
}
if ($BanditsAdapterProbe -or $BanditsEnabled) {
    $modText = Remove-ModEntry $modText 'SurvivorCompanion'
    $modText = Remove-ModEntry $modText 'Bandits2'
    if ($BanditsLoadOrder -eq 'before') { $modText = Add-ModEntry $modText 'Bandits2' }
    $modText = Add-ModEntry $modText 'SurvivorCompanion'
    if ($BanditsLoadOrder -eq 'after') { $modText = Add-ModEntry $modText 'Bandits2' }
} else { $modText = Add-ModEntry $modText 'SurvivorCompanion' }
if ($FieldCargoProbe) {
    $modText = Add-ModEntry $modText 'damnlib'
    $modText = Add-ModEntry $modText '93fordF350'
}
if ($ProjectALifeDamageProbe -or $ProjectALifeAdapterProbe -or $ProjectALifeEnabled) {
    $modText = Remove-ModEntry $modText 'SurvivorCompanion'
    $modText = Remove-ModEntry $modText 'ProjectALifeNPCs'
    if ($ProjectALifeLoadOrder -eq 'before') { $modText = Add-ModEntry $modText 'ProjectALifeNPCs' }
    $modText = Add-ModEntry $modText 'SurvivorCompanion'
    if ($ProjectALifeLoadOrder -eq 'after') { $modText = Add-ModEntry $modText 'ProjectALifeNPCs' }
}
$modText = Add-ModEntry $modText 'SCRealSandboxHarness'
[System.IO.File]::WriteAllText((Join-Path $SandboxMods 'default.txt'), $modText, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $TargetSave 'mods.txt'), $modText, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $CacheRoot 'latestSave.ini'),
    ($runId + [Environment]::NewLine + $GameMode + [Environment]::NewLine), $utf8NoBom)

$config = @(
    ('companion_firearms_probe=' + $CompanionFirearmsProbe.IsPresent.ToString().ToLowerInvariant()),
    ('companion_facing_probe=' + $CompanionFacingProbe.IsPresent.ToString().ToLowerInvariant()),
    ('companion_facing_mode=' + $CompanionFacingMode),
    ('bandits_adapter_probe=' + $BanditsAdapterProbe.IsPresent.ToString().ToLowerInvariant()),
    ('bandits_enabled=' + ($BanditsAdapterProbe.IsPresent -or $BanditsEnabled.IsPresent).ToString().ToLowerInvariant()),
    ('bandits_combat_scenario=' + $(if ($CompanionFirearmsProbe) { 'firearms_zombie_control' } else { $BanditsCombatScenario })),
    ('bandits_lf_profession=' + $BanditsLFProfession),
    ('bandits_combatants=' + $BanditsCombatants),
    ('bandits_combat_doctrine=' + $BanditsCombatDoctrine),
    ('bandits_load_order=' + $BanditsLoadOrder),
    ('bandits_lf_role=' + $BanditsLFRole),
    ('bandits_expected_lf_id=' + $BanditsExpectedLFId),
    'enabled=true',
    'autoload=true',
    ('run_id=' + $runId),
    ('world=' + $runId),
    ('mode=' + $GameMode),
    ('project_alife_damage_probe=' + $ProjectALifeDamageProbe.IsPresent.ToString().ToLowerInvariant()),
    ('project_alife_adapter_probe=' + $ProjectALifeAdapterProbe.IsPresent.ToString().ToLowerInvariant()),
    ('project_alife_enabled=' + ($ProjectALifeAdapterProbe.IsPresent -or $ProjectALifeEnabled.IsPresent -or $ProjectALifeDamageProbe.IsPresent).ToString().ToLowerInvariant()),
    ('project_alife_role=' + $ProjectALifeRole),
    ('project_alife_scenario=' + $ProjectALifeScenario),
    ('project_alife_weapon=' + $ProjectALifeWeapon),
    ('project_alife_observe_household=' + $ProjectALifeObserveHousehold.IsPresent.ToString().ToLowerInvariant()),
    ('ui_menu_probe=' + $UIMenuProbe.IsPresent.ToString().ToLowerInvariant()),
    ('user_options_probe=' + $UserOptionsProbe.IsPresent.ToString().ToLowerInvariant()),
    ('medical_check_probe=' + $MedicalCheckProbe.IsPresent.ToString().ToLowerInvariant()),
    ('base_maintenance_probe=' + $BaseMaintenanceProbe.IsPresent.ToString().ToLowerInvariant()),
    ('floor_sort_probe=' + $FloorSortProbe.IsPresent.ToString().ToLowerInvariant()),
    ('vehicle_refuel_probe=' + $VehicleRefuelProbe.IsPresent.ToString().ToLowerInvariant()),
    ('vehicle_upkeep_probe=' + $VehicleUpkeepProbe.IsPresent.ToString().ToLowerInvariant()),
    ('field_work_probe=' + $FieldWorkProbe.IsPresent.ToString().ToLowerInvariant()),
    ('field_cargo_probe=' + $FieldCargoProbe.IsPresent.ToString().ToLowerInvariant()),
    ('guard_follow_probe=' + $GuardFollowProbe.IsPresent.ToString().ToLowerInvariant()),
    ('generator_refuel_probe=' + $GeneratorRefuelProbe.IsPresent.ToString().ToLowerInvariant()),
    ('pyre_burn_probe=' + $PyreBurnProbe.IsPresent.ToString().ToLowerInvariant()),
    ('upstairs_haul_probe=' + $UpstairsHaulProbe.IsPresent.ToString().ToLowerInvariant()),
    ('office_haul_probe=' + $OfficeHaulProbe.IsPresent.ToString().ToLowerInvariant()),
    ('office_haul_survey_only=' + $OfficeHaulSurveyOnly.IsPresent.ToString().ToLowerInvariant()),
    ('base_alert_probe=' + $BaseAlertProbe.IsPresent.ToString().ToLowerInvariant()),
    ('barricade_probe=' + $BarricadeProbe.IsPresent.ToString().ToLowerInvariant()),
    ('barricade_hardening=' + $BarricadeHardening.IsPresent.ToString().ToLowerInvariant()),
    ('barricade_matrix_only=' + $BarricadeMatrixOnly.IsPresent.ToString().ToLowerInvariant()),
    ('view_cutaway_probe=' + $ViewCutawayProbe.IsPresent.ToString().ToLowerInvariant()),
    ('view_cutaway_quick_watch=' + $ViewCutawayQuickWatch.IsPresent.ToString().ToLowerInvariant()),
    ('view_cutaway_restore_mode=' + $ViewCutawayRestoreMode),
    ('view_cutaway_cycles=' + $ViewCutawayCycles),
    ('normal_expedition_kitchen_probe=' + $NormalExpeditionKitchenProbe.IsPresent.ToString().ToLowerInvariant()),
    ('normal_expedition_kitchen_crew_size=' + $NormalExpeditionKitchenCrewSize),
    ('wood_expedition_probe=' + $WoodExpeditionProbe.IsPresent.ToString().ToLowerInvariant()),
    ('wood_expedition_travel_mode=' + $WoodExpeditionTravelMode),
    ('wood_expedition_crew_size=' + $WoodExpeditionCrewSize),
    ('wood_expedition_deadline_seconds=' + $WoodExpeditionDeadlineSeconds),
    ('wood_expedition_stock_equipment=' + $WoodExpeditionStockEquipment.IsPresent.ToString().ToLowerInvariant()),
    ('wood_expedition_quiet_site=' + $WoodExpeditionQuietSite.IsPresent.ToString().ToLowerInvariant()),
    ('hygiene_probe=' + $HygieneProbe.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_corey_probe=' + $OddballCoreyProbe.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_earl_probe=' + $OddballEarlProbe.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_arthur_probe=' + $OddballArthurProbe.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_arthur_bed_survey_only=' + $OddballArthurBedSurveyOnly.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_arthur_head_side_trial=' + $OddballArthurHeadSideTrial.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_arthur_player_baseline=' + $OddballArthurPlayerBaseline.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_pack_probe=' + $OddballPackProbe.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_smoker_probe=' + $OddballSmokerProbe.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_site_x=' + $OddballSiteX),
    ('oddball_site_y=' + $OddballSiteY),
    ('oddball_bed_x=' + $OddballBedX),
    ('oddball_bed_y=' + $OddballBedY),
    ('oddball_pose_only=' + $OddballPoseOnly.IsPresent.ToString().ToLowerInvariant()),
    ('oddball_scene_screenshot=' + $captureOddballScene.ToString().ToLowerInvariant()),
    ('hygiene_eight_directions=' +
        (-not [string]::IsNullOrWhiteSpace($HygieneEightDirectionsScreenshotDirectory)).ToString().ToLowerInvariant()),
    ('strange_folk_portrait_probe=' + $captureStrangeFolkPortraits.ToString().ToLowerInvariant()),
    ('strange_folk_portrait_target=' + $StrangeFolkPortraitTarget),
    ('wendell_approach_probe=' + $WendellApproachProbe.IsPresent.ToString().ToLowerInvariant()),
    ('deputy_rhonda_probe=' + $DeputyRhondaProbe.IsPresent.ToString().ToLowerInvariant()),
    ('deputy_rhonda_screenshot=' + $captureDeputyRhonda.ToString().ToLowerInvariant()),
    ('loretta_probe=' + $LorettaProbe.IsPresent.ToString().ToLowerInvariant()),
    ('loretta_screenshot=' + $captureLoretta.ToString().ToLowerInvariant()),
    ('loretta_site_x=' + $LorettaSiteX),
    ('loretta_site_y=' + $LorettaSiteY),
    ('milli_probe=' + $MilliProbe.IsPresent.ToString().ToLowerInvariant()),
    ('milli_screenshot=' + $captureMilli.ToString().ToLowerInvariant()),
    ('milli_site_x=' + $MilliSiteX),
    ('milli_site_y=' + $MilliSiteY),
    ('base_second_floor_probe=' + $BaseSecondFloorProbe.IsPresent.ToString().ToLowerInvariant()),
    ('water_source_probe=' + $WaterSourceProbe.IsPresent.ToString().ToLowerInvariant()),
    ('farm_corridor_probe=' + $FarmCorridorProbe.IsPresent.ToString().ToLowerInvariant()),
    ('driving_probe=' + $DrivingProbe.IsPresent.ToString().ToLowerInvariant()),
    ('convoy_probe=' + $ConvoyProbe.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_passenger_probe=' + $TaxiPassengerProbe.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_call_probe=' + $TaxiCallProbe.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_defense_probe=' + $TaxiDefenseProbe.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_call_long_paid=' + $TaxiCallLongPaid.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_turn_diagnostic=' + $TaxiTurnDiagnostic.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_call_stage=' + $TaxiCallStage.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_call_resume=' + $TaxiCallResume.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_call_expected_sql_id=' + [string]$taxiCallExpected.sql_id),
    ('taxi_call_expected_driver_id=' + [string]$taxiCallExpected.driver_id),
    ('taxi_call_expected_booking_generation=' + [string]$taxiCallExpected.booking_generation),
    ('taxi_call_expected_receipt_id=' + [string]$taxiCallExpected.receipt_id),
    ('taxi_recovery_resume=' + $TaxiRecoveryResume.IsPresent.ToString().ToLowerInvariant()),
    ('taxi_expected_sql_id=' + [string]$taxiExpected.sql_id),
    ('taxi_expected_ring_id=' + [string]$taxiExpected.ring_id),
    ('taxi_expected_receipt_id=' + [string]$taxiExpected.receipt_id),
    ('driving_route=' + $DrivingRoute.IsPresent.ToString().ToLowerInvariant()),
    ('driving_turn=' + $DrivingTurn.IsPresent.ToString().ToLowerInvariant()),
    ('driving_with_ai=' + $DrivingWithAi.IsPresent.ToString().ToLowerInvariant()),
    ('driving_blocked=' + $DrivingBlocked.IsPresent.ToString().ToLowerInvariant()),
    ('driving_save_stage=' + $DrivingSaveStage.IsPresent.ToString().ToLowerInvariant()),
    ('driving_save_resume=' + $DrivingSaveResume.IsPresent.ToString().ToLowerInvariant()),
    ('driving_remote=' + $DrivingRemote.IsPresent.ToString().ToLowerInvariant()),
    ('team_drive_probe=' + $TeamDriveProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_drive_scavenge_probe=' + $TeamDriveScavengeProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_drive_scavenge_site_id=' + $TeamDriveScavengeSiteId),
    ('team_drive_obstacle_probe=' + $TeamDriveObstacleProbe.IsPresent.ToString().ToLowerInvariant()),
    ('team_drive_restart_stage=' + $TeamDriveRestartStage.IsPresent.ToString().ToLowerInvariant()),
    ('team_drive_restart_resume=' + $TeamDriveRestartResume.IsPresent.ToString().ToLowerInvariant()),
    ('team_drive_expected_sql_id=' + [string]$teamDriveExpected.sql_id),
    ('team_drive_expected_leader_id=' + [string]$teamDriveExpected.leader_id),
    ('team_drive_expected_parking_id=' + [string]$teamDriveExpected.parking_id),
    ('driving_expected_actor_id=' + [string]$drivingExpected.actor_id),
    ('driving_expected_sql_id=' + [string]$drivingExpected.sql_id),
    ('driving_expected_key_id=' + [string]$drivingExpected.key_id),
    ('driving_expected_key_location=' + [string]$drivingExpected.key_location),
    ('driving_expected_car_x=' + [string]$drivingExpected.car_x),
    ('driving_expected_car_y=' + [string]$drivingExpected.car_y),
    ('driving_screenshots=' + (-not [string]::IsNullOrWhiteSpace($DrivingScreenshotDirectory)).ToString().ToLowerInvariant()),
    ('capture_faction_map=' + $captureFactionMap.ToString().ToLowerInvariant()),
    ('faction_map_only=' + $FactionMapOnly.IsPresent.ToString().ToLowerInvariant()),
    ('pathing_only=' + $PathingOnly.IsPresent.ToString().ToLowerInvariant()),
    ('follow_road_probe=' + $FollowRoadProbe.IsPresent.ToString().ToLowerInvariant()),
    ('follow_road_fan_out=' + $FollowRoadFanOut.IsPresent.ToString().ToLowerInvariant()),
    ('follow_road_isolated=' + $FollowRoadIsolated.IsPresent.ToString().ToLowerInvariant()),
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
    ('team_expedition_integration_probe=' + $TeamExpeditionIntegrationProbe.IsPresent.ToString().ToLowerInvariant()),
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
    ('team_expedition_zoom_only=' + $TeamExpeditionZoomOnly.IsPresent.ToString().ToLowerInvariant()),
    ('team_radio_kit_verify_only=' + $TeamRadioKitVerifyOnly.IsPresent.ToString().ToLowerInvariant()),
    ('leader_watch_ms=' + ($LeaderWatchSeconds * 1000)),
    ('capture_base_layout=' + $captureBaseLayout.ToString().ToLowerInvariant()),
    ('base_layout_only=' + $BaseLayoutOnly.IsPresent.ToString().ToLowerInvariant()),
    ('companion_inventory_only=' + $CompanionInventoryOnly.IsPresent.ToString().ToLowerInvariant()),
    ('companion_transfer_probe=' + $CompanionTransferProbe.IsPresent.ToString().ToLowerInvariant()),
    ('gifted_equipment_probe=' + $GiftedEquipmentProbe.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_probe=' + $SquadCombatProbe.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_front_only=' + $SquadCombatFrontOnly.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_single_case=' + $SquadCombatSingleCase.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_case_index=' + $SquadCombatCaseIndex),
    ('squad_combat_custom_companions=' + $SquadCombatCompanions),
    ('squad_combat_custom_zombies=' + ($SquadCombatZombieCounts -join ',')),
    ('squad_combat_natural_acquisition=' + $SquadCombatNaturalAcquisition.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_passive_control=' + $SquadCombatPassiveControl.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_weapon_type=' + $SquadCombatWeaponType),
    ('squad_combat_weapon_types=' + ($SquadCombatWeaponTypes -join ',')),
    ('squad_combat_fatigue=' + $SquadCombatFatigue.ToString([System.Globalization.CultureInfo]::InvariantCulture)),
    ('squad_combat_multihit=' + $SquadCombatMultiHit),
    ('squad_combat_order=' + $SquadCombatOrder),
    ('squad_combat_backup_weapon_type=' + $SquadCombatBackupWeaponType),
    ('squad_combat_photo=' + $SquadCombatPhoto.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_near_observer=' + $SquadCombatNearObserver.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_radio_lure=' + $SquadCombatRadioLure.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_baseline=' + $SquadCombatBaseline.IsPresent.ToString().ToLowerInvariant()),
    ('squad_combat_trials=' + $SquadCombatTrials),
    ('squad_combat_seconds=' + $SquadCombatSeconds),
    ('furniture_pose_only=' + $FurniturePoseOnly.IsPresent.ToString().ToLowerInvariant()),
    ('sleep_probe=' + $SleepProbe.IsPresent.ToString().ToLowerInvariant()),
    ('firestation_rest_probe=' + $FirestationRestProbe.IsPresent.ToString().ToLowerInvariant()),
    ('firestation_rest_group=' + $FirestationRestGroup.IsPresent.ToString().ToLowerInvariant()),
    ('firestation_rest_first_trial=' + $FirestationRestFirstTrial),
    ('vehicle_passenger_only=' + $VehiclePassengerOnly.IsPresent.ToString().ToLowerInvariant()),
    ('six_seat_probe=' + $SixSeatProbe.IsPresent.ToString().ToLowerInvariant()),
    ('woodcutter_only=' + $WoodcutterOnly.IsPresent.ToString().ToLowerInvariant()),
    ('posted_stream_only=' + $PostedStreamOnly.IsPresent.ToString().ToLowerInvariant()),
    ('observe_only=' + ($ObserveSeconds -gt 0).ToString().ToLowerInvariant()),
    ('observe_menus_closed=' + $ObserveMenusClosed.IsPresent.ToString().ToLowerInvariant()),
    ('observe_ms=' + ($ObserveSeconds * 1000)),
    ('observe_speed=' + $ObserveSpeed),
    ('restart_chef_before_observe=' + $RestartChefBeforeObserve.IsPresent.ToString().ToLowerInvariant()),
    ('observe_inbound_return_fault=' + $ObserveInboundReturnFault.IsPresent.ToString().ToLowerInvariant()),
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
    launchMode = if ($SteamLaunch) { 'steam' } else { 'direct' }
    targetSave = $TargetSave
    sourceRelease = ((Get-Content -LiteralPath (Join-Path $sourceMod 'mod.info') |
        Where-Object { $_ -match '^modversion=' }) -replace '^modversion=', '')
    sourceSaveIsReadOnlyInput = $true
    oddballArthurProbe = $OddballArthurProbe.IsPresent
    oddballPackProbe = $OddballPackProbe.IsPresent
    oddballSite = if ($OddballSiteX -gt 0) {
        @{ x = $OddballSiteX; y = $OddballSiteY }
    } else { $null }
    oddballSceneScreenshot = if ($captureOddballScene) { $OddballSceneScreenshot } else { $null }
    sourceBridge = $sourceBridge
    isolatedBridgePath = $IsolatedBridgePath
    sourceBridgeSha256 = $sourceBridgeHash
    installedBridgeMatches = $installedBridgeHash -eq $sourceBridgeHash
    livingFellowsOnly = $LivingFellowsOnly.IsPresent
    barricadeHardening = $BarricadeHardening.IsPresent
    barricadeMatrixOnly = $BarricadeMatrixOnly.IsPresent
    companionFirearmsProbe = $CompanionFirearmsProbe.IsPresent
    companionFacingProbe = $CompanionFacingProbe.IsPresent
    companionFacingMode = $CompanionFacingMode
    banditsAdapterProbe = $BanditsAdapterProbe.IsPresent
    projectALifeAdapterProbe = $ProjectALifeAdapterProbe.IsPresent
    projectALifeEnabled = ($ProjectALifeAdapterProbe.IsPresent -or $ProjectALifeEnabled.IsPresent -or $ProjectALifeDamageProbe.IsPresent)
    projectALifeRole = $ProjectALifeRole
    projectALifeScenario = $ProjectALifeScenario
    projectALifeWeapon = $ProjectALifeWeapon
    projectALifeObserveHousehold = $ProjectALifeObserveHousehold.IsPresent
    projectALifeLoadOrder = $ProjectALifeLoadOrder
    banditsEnabled = ($BanditsAdapterProbe.IsPresent -or $BanditsEnabled.IsPresent)
    banditsCombatScenario = $BanditsCombatScenario
    banditsLFProfession = $BanditsLFProfession
    banditsCombatants = $BanditsCombatants
    banditsCombatDoctrine = $BanditsCombatDoctrine
    banditsLoadOrder = $BanditsLoadOrder
    banditsLFRole = $BanditsLFRole
    banditsExpectedLFId = $BanditsExpectedLFId
    viewCutawayProbe = $ViewCutawayProbe.IsPresent
    viewCutawayQuickWatch = $ViewCutawayQuickWatch.IsPresent
    viewCutawayRestoreMode = $ViewCutawayRestoreMode
    viewCutawayCycles = $ViewCutawayCycles
    normalExpeditionKitchenProbe = $NormalExpeditionKitchenProbe.IsPresent
    normalExpeditionKitchenCrewSize = $NormalExpeditionKitchenCrewSize
    woodExpeditionProbe = $WoodExpeditionProbe.IsPresent
    woodExpeditionTravelMode = $WoodExpeditionTravelMode
    woodExpeditionCrewSize = $WoodExpeditionCrewSize
    woodExpeditionDeadlineSeconds = $WoodExpeditionDeadlineSeconds
    woodExpeditionStockEquipment = $WoodExpeditionStockEquipment.IsPresent
    woodExpeditionQuietSite = $WoodExpeditionQuietSite.IsPresent
    squadCombatProbe = $SquadCombatProbe.IsPresent
    squadCombatFrontOnly = $SquadCombatFrontOnly.IsPresent
    squadCombatSingleCase = $SquadCombatSingleCase.IsPresent
    squadCombatCaseIndex = $SquadCombatCaseIndex
    squadCombatCompanions = $SquadCombatCompanions
    squadCombatZombieCounts = @($SquadCombatZombieCounts)
    squadCombatNaturalAcquisition = $SquadCombatNaturalAcquisition.IsPresent
    squadCombatPassiveControl = $SquadCombatPassiveControl.IsPresent
    squadCombatWeaponType = $SquadCombatWeaponType
    squadCombatWeaponTypes = $SquadCombatWeaponTypes
    squadCombatFatigue = $SquadCombatFatigue
    squadCombatMultiHit = $SquadCombatMultiHit
    squadCombatOrder = $SquadCombatOrder
    squadCombatBackupWeaponType = $SquadCombatBackupWeaponType
    squadCombatPhoto = $SquadCombatPhoto.IsPresent
    squadCombatNearObserver = $SquadCombatNearObserver.IsPresent
    squadCombatRadioLure = $SquadCombatRadioLure.IsPresent
    squadCombatBaseline = $SquadCombatBaseline.IsPresent
    squadCombatTrials = $SquadCombatTrials
    squadCombatSeconds = $SquadCombatSeconds
    externalUiControl = $ExternalUiControl.IsPresent
    excludedModIds = @($ExcludeModId)
    factionMapScreenshot = if ($captureFactionMap) { $FactionMapScreenshot } else { $null }
    factionMapOnly = $FactionMapOnly.IsPresent
    baseLayoutScreenshot = if ($captureBaseLayout) { $BaseLayoutScreenshot } else { $null }
    baseLayoutOnly = $BaseLayoutOnly.IsPresent
    companionInventoryScreenshot = if ($CompanionInventoryOnly) { $CompanionInventoryScreenshot } else { $null }
    vehiclePassengerScreenshot = if ($VehiclePassengerOnly) { $VehiclePassengerScreenshot } else { $null }
    drivingScreenshotDirectory = if ([string]::IsNullOrWhiteSpace($DrivingScreenshotDirectory)) { $null } else { $DrivingScreenshotDirectory }
    drivingWithAi = $DrivingWithAi.IsPresent
    drivingGateNegativeControl = $DrivingGateNegativeControl.IsPresent
    drivingBlocked = $DrivingBlocked.IsPresent
    drivingSaveStage = $DrivingSaveStage.IsPresent
    drivingSaveResume = $DrivingSaveResume.IsPresent
    drivingStageProof = $drivingStageProof
    pathingOnly = $PathingOnly.IsPresent
    splitScreenOnly = $SplitScreenOnly.IsPresent
    splitBaseLayoutProbe = $SplitBaseLayoutProbe.IsPresent
    leaderSlotOnly = $LeaderSlotOnly.IsPresent
    leaderRemote = $LeaderRemote.IsPresent
    leaderWatchSeconds = $LeaderWatchSeconds
    splitScreenScreenshot = if ($SplitScreenOnly) { $SplitScreenScreenshot } else { $null }
    strangeFolkPortraitScreenshotDirectory = if ($captureStrangeFolkPortraits) {
        $StrangeFolkPortraitScreenshotDirectory
    } else { $null }
    deputyRhondaScreenshot = if ($captureDeputyRhonda) { $DeputyRhondaScreenshot } else { $null }
    lorettaScreenshot = if ($captureLoretta) { $LorettaScreenshot } else { $null }
    lorettaSite = if ($LorettaSiteX -gt 0) {
        @{ x = $LorettaSiteX; y = $LorettaSiteY }
    } else { $null }
    milliScreenshot = if ($captureMilli) { $MilliScreenshot } else { $null }
    milliSite = if ($MilliSiteX -gt 0) {
        @{ x = $MilliSiteX; y = $MilliSiteY }
    } else { $null }
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
if ($ViewCutawayProbe -or $SplitScreenOnly -or
    ($WoodExpeditionProbe -and $WoodExpeditionCrewSize -eq 3)) { $argumentLine += ' -debug' }
if ($NoSteam) { $argumentLine += ' -nosteam' }
$autoGateAgent = -not $SteamLaunch -and -not $ExternalUiControl
if ($ConvoyProbe -and -not $autoGateAgent) {
    # The lead-car input helper ships only in the disposable launch agent.
    throw 'The convoy probe needs the isolated Java launch; drop -SteamLaunch and -ExternalUiControl.'
}
$gateAgentMarker = Join-Path $RunRoot 'loading-gate-agent.txt'
$gateAgentJar = Join-Path $RunRoot 'loading-gate-agent.jar'
if ($autoGateAgent) {
    # Build a disposable helper rather than changing the installed launcher or
    # shipping a loading-screen bypass with Living Fellows. PZ reads its own
    # mouse state, so background WM_LBUTTONDOWN posts cannot pass this gate.
    $javaTools = 'C:\Program Files\Java\jdk-24\bin'
    $javac = Join-Path $javaTools 'javac.exe'
    if (-not (Test-Path -LiteralPath $javac -PathType Leaf)) {
        throw 'The isolated loading gate requires JDK 24 javac.exe.'
    }
    $agentClasses = Join-Path $RunRoot 'loading-gate-classes'
    New-Item -ItemType Directory -Path $agentClasses -Force | Out-Null
    $agentSource = Join-Path $ProjectRoot 'tests\live\auto_start\SCLoadingGateAgent.java'
    & $javac -encoding UTF-8 -d $agentClasses $agentSource
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the isolated loading-gate agent.' }
    $agentEntries = @('survivorcompanion/harness/SCLoadingGateAgent.class')
    if ($ConvoyProbe) {
        # Test-only lead-car input; the shipped bridge finds it by name.
        $convoySource = Join-Path $ProjectRoot 'tests\live\auto_start\SCConvoyHarness.java'
        & $javac -encoding UTF-8 -cp (Join-Path $GameRoot 'projectzomboid.jar') `
            -d $agentClasses $convoySource
        if ($LASTEXITCODE -ne 0) { throw 'Could not compile the convoy live-run helper.' }
        $agentEntries += 'survivorcompanion/harness/SCConvoyHarness.class'
    }
    # Write the JAR in place. jar.exe stages a temp file and its cross-directory
    # move is denied in a restricted desktop session.
    $zip = [System.IO.Compression.ZipFile]::Open($gateAgentJar,
        [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $manifestEntry = $zip.CreateEntry('META-INF/MANIFEST.MF')
        $stream = $manifestEntry.Open()
        try {
            $manifestBytes = [System.Text.Encoding]::ASCII.GetBytes(
                "Manifest-Version: 1.0`r`nPremain-Class: survivorcompanion.harness.SCLoadingGateAgent`r`n`r`n")
            $stream.Write($manifestBytes, 0, $manifestBytes.Length)
        } finally { $stream.Dispose() }
        foreach ($entry in $agentEntries) {
            $agentClass = Join-Path $agentClasses ($entry.Replace('/', '\'))
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $agentClass,
                $entry) | Out-Null
        }
    } finally { $zip.Dispose() }
}
if ($SteamLaunch) {
    $SteamExe = [System.IO.Path]::GetFullPath($SteamExe)
    if (-not (Test-Path -LiteralPath $SteamExe -PathType Leaf)) {
        throw "Steam client was not found: $SteamExe"
    }
    if (Test-Path -LiteralPath $consolePath -PathType Leaf) {
        throw "The isolated console already exists before Steam launch: $consolePath"
    }
    $existingGameIds = @(Get-Process -Name 'ProjectZomboid64' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Id)
    try {
        $existingGameIds += @(Get-CimInstance Win32_Process `
            -Filter "Name = 'ProjectZomboid64.exe'" -ErrorAction Stop |
            Select-Object -ExpandProperty ProcessId)
    } catch { }
    $existingGameIds = @($existingGameIds | Sort-Object -Unique)
    $launchUtc = [DateTime]::UtcNow
    # -applaunch passes these game arguments through the desktop Steam client.
    # Steam's PID may be a short-lived forwarding process, not the game PID.
    Start-Process -FilePath $SteamExe -WorkingDirectory (Split-Path -Parent $SteamExe) `
        -ArgumentList ('-applaunch 108600 ' + $argumentLine)
    $process = $null
    $launchDeadline = $launchUtc.AddSeconds([Math]::Min($TimeoutSeconds, 120))
    while ([DateTime]::UtcNow -lt $launchDeadline -and $null -eq $process) {
        $process = Get-SteamLaunchedClient -ExistingProcessIds $existingGameIds `
            -ExpectedExecutable $gameExe -ExpectedCacheRoot $CacheRoot `
            -ConsolePath $consolePath -LaunchUtc $launchUtc
        if ($null -eq $process) { Start-Sleep -Milliseconds 500 }
    }
    if ($null -eq $process) {
        throw "Steam did not start a Project Zomboid client with the isolated cachedir. Run retained at $RunRoot"
    }
    Write-Output "Started Steam-owned Project Zomboid client test pid=$($process.Id)"
} else {
    $directExecutable = $gameExe
    $directArguments = $argumentLine
    if ($autoGateAgent -or $IsolatedSourceBridge) {
        $directExecutable = Join-Path $GameRoot 'jre64\bin\javaw.exe'
        if (-not (Test-Path -LiteralPath $directExecutable -PathType Leaf)) {
            throw "Bundled game Java runtime is missing: $directExecutable"
        }
        $classPathEntries = @($launcher.classpath | ForEach-Object {
            if ($_ -eq $bridgeClassPath[0] -and $IsolatedSourceBridge) {
                $sourceBridge
            } else { $_ }
        })
        $gameClassPath = ($classPathEntries -join ';')
        $gateAgentArgument = ''
        if ($autoGateAgent) {
            $gateAgentArgument = ' -javaagent:"' + $gateAgentJar + '"=' + $gateAgentMarker
        }
        $directArguments = (($launcher.vmArgs -join ' ') +
            ' -XX:+UseZGC' + $gateAgentArgument + ' -cp "' + $gameClassPath +
            '" survivorcompanion.bridge.SCLauncher ' + $argumentLine)
    }
    $startOptions = @{
        FilePath = $directExecutable
        WorkingDirectory = $GameRoot
        ArgumentList = $directArguments
        PassThru = $true
    }
    if ($HiddenWindow) { $startOptions.WindowStyle = 'Hidden' }
    $priorConvoyHarness = $env:SC_LIVE_CONVOY_HARNESS
    try {
        if ($ConvoyProbe) { $env:SC_LIVE_CONVOY_HARNESS = '1' }
        $process = Start-Process @startOptions
    } finally {
        $env:SC_LIVE_CONVOY_HARNESS = $priorConvoyHarness
    }
    Write-Output "Started real Project Zomboid client test pid=$($process.Id) mode=$(if ($autoGateAgent -or $IsolatedSourceBridge) { 'isolated-java' } else { 'game-exe' })"
}
if ($ExternalUiControl) {
    Write-Output 'External UI control is active: click the Build 42 start gate after world load.'
}

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
    $drivingCaptures = @{}
    $splitScreenCaptureCompleted = $false
    $zombieVisibilityCaptureCompleted = $false
    $postHandoffCaptureCompleted = $false
    $crashProbeCompleted = $false
    $hygieneCaptureCompleted = $false
    $strangeFolkPortraitsCaptured = @{}
    $deputyRhondaCaptured = $false
    $lorettaCaptured = $false
    $milliCaptured = $false
    $oddballSceneCaptured = $false
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
                if ($autoGateAgent) {
                    Write-Output 'World load completed; isolated loading-gate agent owns start.'
                } else {
                    Write-Output 'World load completed; waiting for the Build 42 click-to-start gate.'
                }
            }
        }
        if ($autoGateAgent -and (Test-Path -LiteralPath $gateAgentMarker -PathType Leaf) -and
            (Select-String -LiteralPath $gateAgentMarker -Pattern '^agent_failed:' -Quiet)) {
            throw "Isolated loading-gate agent failed; inspect $gateAgentMarker"
        }
        if (-not $ExternalUiControl -and -not $autoGateAgent -and $loadingReadyObserved -and
            [DateTime]::UtcNow -ge $nextLoadingClick -and
            -not (Test-Path -LiteralPath $eventsPath -PathType Leaf)) {
            $clickAttempts++
            $clickResult = Invoke-LoadingScreenClick $process
            if ($clickResult -eq 'foreground') {
                Write-Output "Sent isolated click-to-start attempt $clickAttempts mode=$clickResult pid=$($process.Id)"
            } elseif ($clickAttempts -in @(1, 5, 10, 20)) {
                $process.Refresh()
                Write-Output "Click-to-start unavailable attempt=$clickAttempts reason=$clickResult pid=$($process.Id) exited=$($process.HasExited) window=$($process.MainWindowHandle) title=$($process.MainWindowTitle)"
            }
            if ($clickAttempts -ge 20) {
                throw "Click-to-start did not begin the isolated game after $clickAttempts attempts (last=$clickResult)."
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
        if ($captureStrangeFolkPortraits) {
            foreach ($portrait in $strangeFolkPortraitLabels) {
                if ($strangeFolkPortraitsCaptured[$portrait]) { continue }
                $readyPath = Join-Path $SandboxLua ('strange-folk-' + $portrait + '-ready.txt')
                if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) { continue }
                $destination = Join-Path $StrangeFolkPortraitScreenshotDirectory `
                    ($portrait + '.png')
                Start-Sleep -Milliseconds 750
                if (-not (Save-ClientScreenshot $process $destination)) {
                    throw "Could not capture Strange Folk portrait to $destination"
                }
                $capturedPath = Join-Path $SandboxLua `
                    ('strange-folk-' + $portrait + '-captured.txt')
                [System.IO.File]::WriteAllText($capturedPath,
                    ('captured=true' + [Environment]::NewLine), $utf8NoBom)
                Write-Output "Captured Strange Folk portrait: $destination"
                $strangeFolkPortraitsCaptured[$portrait] = $true
            }
        }
        if ($captureDeputyRhonda -and -not $deputyRhondaCaptured) {
            $readyPath = Join-Path $SandboxLua 'deputy-rhonda-ready.txt'
            if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
                Start-Sleep -Milliseconds 750
                if (-not (Save-ClientScreenshot $process $DeputyRhondaScreenshot)) {
                    throw "Could not capture Deputy Rhonda to $DeputyRhondaScreenshot"
                }
                [System.IO.File]::WriteAllText(
                    (Join-Path $SandboxLua 'deputy-rhonda-captured.txt'),
                    ('captured=true' + [Environment]::NewLine), $utf8NoBom)
                Write-Output "Captured Deputy Rhonda encounter: $DeputyRhondaScreenshot"
                $deputyRhondaCaptured = $true
            }
        }
        if ($captureLoretta -and -not $lorettaCaptured) {
            $readyPath = Join-Path $SandboxLua 'loretta-ready.txt'
            if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
                $nativeShot = Join-Path $CacheRoot 'Screenshots\loretta-harness.png'
                if (Test-Path -LiteralPath $nativeShot -PathType Leaf) {
                    Copy-Item -LiteralPath $nativeShot -Destination $LorettaScreenshot
                    [System.IO.File]::WriteAllText(
                        (Join-Path $SandboxLua 'loretta-captured.txt'),
                        ('captured=true' + [Environment]::NewLine), $utf8NoBom)
                    Write-Output "Captured Loretta encounter: $LorettaScreenshot"
                    $lorettaCaptured = $true
                }
            }
        }
        if ($captureMilli -and -not $milliCaptured) {
            $readyPath = Join-Path $SandboxLua 'milli-ready.txt'
            if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
                Start-Sleep -Milliseconds 750
                if (-not (Save-ClientScreenshot $process $MilliScreenshot)) {
                    throw "Could not capture Milli encounter to $MilliScreenshot"
                }
                [System.IO.File]::WriteAllText(
                    (Join-Path $SandboxLua 'milli-captured.txt'),
                    ('captured=true' + [Environment]::NewLine), $utf8NoBom)
                Write-Output "Captured Milli encounter: $MilliScreenshot"
                $milliCaptured = $true
            }
        }
        if ($captureOddballScene -and -not $oddballSceneCaptured) {
            $readyPath = Join-Path $SandboxLua 'oddball-scene-ready.txt'
            if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
                Start-Sleep -Milliseconds 750
                if (-not (Save-ClientScreenshot $process $OddballSceneScreenshot)) {
                    throw "Could not capture oddball scene to $OddballSceneScreenshot"
                }
                [System.IO.File]::WriteAllText(
                    (Join-Path $SandboxLua 'oddball-scene-captured.txt'),
                    ('captured=true' + [Environment]::NewLine), $utf8NoBom)
                Write-Output "Captured oddball scene: $OddballSceneScreenshot"
                $oddballSceneCaptured = $true
            }
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
            # 0x2D is the physical Insert key, the base layout hotkey's default.
            if (-not (Invoke-WindowKey $process 0x2D)) {
                throw 'Could not focus the client and send the Insert key.'
            }
            Write-Output 'Sent Insert to show the base layout overlay.'
            $layoutVisiblePath = Join-Path $SandboxLua 'base-layout-visible.txt'
            $visibleDeadline = [DateTime]::UtcNow.AddSeconds(10)
            while ([DateTime]::UtcNow -lt $visibleDeadline -and
                -not (Test-Path -LiteralPath $layoutVisiblePath -PathType Leaf)) {
                $process.Refresh()
                if ($process.HasExited) { break }
                Start-Sleep -Milliseconds 200
            }
            if (-not (Test-Path -LiteralPath $layoutVisiblePath -PathType Leaf)) {
                throw 'The game did not confirm the base layout overlay after Insert was pressed.'
            }
            Start-Sleep -Milliseconds 1200
            if (-not (Save-ClientScreenshot $process $BaseLayoutScreenshot)) {
                throw "Could not capture the Project Zomboid client to $BaseLayoutScreenshot"
            }
            Write-Output "Captured base layout screenshot: $BaseLayoutScreenshot"
            if (-not (Invoke-WindowKey $process 0x2D)) {
                throw 'Could not send Insert to hide the base layout after capture.'
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
        if (-not $ExternalUiControl -and
            -not [string]::IsNullOrWhiteSpace($DrivingScreenshotDirectory)) {
            # The car is moving: capture as soon as the probe signals, no settle delay.
            $readyFiles = @(Get-ChildItem -LiteralPath $SandboxLua -Filter 'driving-*-ready.txt' `
                -File -ErrorAction SilentlyContinue)
            foreach ($readyFile in $readyFiles) {
                $shot = $readyFile.Name -replace '^driving-(.+)-ready\.txt$', '$1'
                if ($shot -notmatch '^[a-z]+$' -or $drivingCaptures.ContainsKey($shot)) { continue }
                Initialize-WindowInput
                [void][SCLiveHarness.WindowInput]::Focus($process.MainWindowHandle)
                $destination = Join-Path $DrivingScreenshotDirectory "driving-$shot.png"
                if (-not (Save-ClientScreenshot $process $destination)) {
                    throw "Could not capture the driving $shot screenshot to $destination"
                }
                [System.IO.File]::WriteAllText((Join-Path $SandboxLua "driving-$shot-captured.txt"),
                    ('captured=true' + [Environment]::NewLine), $utf8NoBom)
                Write-Output "Captured driving $shot screenshot: $destination"
                $drivingCaptures[$shot] = $destination
            }
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
$postSummaryForcedStop = $false
$postSummaryExitSeconds = if ($DrivingSaveStage -or $TeamDriveRestartStage -or
    $TaxiPassengerProbe -or $TaxiCallStage) { 90 } else { 15 }
$exitDeadline = [DateTime]::UtcNow.AddSeconds($postSummaryExitSeconds)
while ([DateTime]::UtcNow -lt $exitDeadline) {
    $process.Refresh()
    if ($process.HasExited) { break }
    Start-Sleep -Milliseconds 250
}
$process.Refresh()
if (-not $process.HasExited) {
    $postSummaryForcedStop = $true
    Stop-OwnedSandboxProcess $process 'post_summary_deadline'
}

Get-Content -LiteralPath $eventsPath -ErrorAction SilentlyContinue
if ($TaxiPassengerProbe -and $status -eq 'PASS') {
    foreach ($proof in @(
        'taxi_real_car_claim_and_stock',
        'taxi_native_containers_and_recovery',
        'taxi_first_ride_free_reserved',
        'taxi_player_ride_physical',
        'taxi_real_free_fare_settled_once',
        'taxi_real_car_rebound_after_ledger_reload',
        'taxi_second_visit_keeps_same_native_car',
        'taxi_paid_exact_native_item_reserved',
        'taxi_paid_item_settles_once',
        'taxi_native_save_contains_exact_cab_and_fare',
        'taxi_cold_recovery_stage_written'
    )) {
        $found = Select-String -LiteralPath $eventsPath -SimpleMatch `
            ('PASS|' + $proof + '|') -Quiet
        if (-not $found) {
            throw "Taxi live proof did not complete $proof; run retained at $RunRoot."
        }
    }
}
if ($TaxiCallProbe -and -not $TaxiCallStage -and -not $TaxiTurnDiagnostic -and $status -eq 'PASS') {
    $callProofs = @('taxi_call_accepted_once',
        'taxi_call_native_cab_and_driver',
        'taxi_call_service_driver_not_recruited',
        'taxi_call_physical_pickup',
        'taxi_call_booked_passenger_boarded',
        'taxi_call_real_ride')
    if ($TaxiDefenseProbe) { $callProofs += 'taxi_driver_defended_pickup' }
    if ($TaxiCallLongPaid) {
        $callProofs += @('taxi_call_gold_necklace_reserved',
            'taxi_call_straight_cruise_50',
            'taxi_call_long_paid_ride_settled',
            'taxi_call_departed_and_despawned')
    } else {
        $callProofs += @('taxi_call_free_fare_settled',
            'taxi_call_departed_and_despawned')
    }
    foreach ($proof in $callProofs) {
        if (-not (Select-String -LiteralPath $eventsPath -SimpleMatch `
                ('PASS|' + $proof + '|') -Quiet)) {
            throw "Taxi call proof did not complete $proof; run retained at $RunRoot."
        }
    }
}
if ($TaxiTurnDiagnostic -and $status -eq 'PASS' -and
    -not (Select-String -LiteralPath $eventsPath -SimpleMatch `
        'PASS|taxi_turn_bad_pickup_route_skipped|' -Quiet)) {
    throw "Taxi turn diagnostic did not skip the degenerate pickup route; run retained at $RunRoot."
}
if ($TaxiCallStage -and $status -eq 'PASS') {
    foreach ($proof in @('taxi_call_booked_passenger_boarded',
        'taxi_call_stage_saved')) {
        if (-not (Select-String -LiteralPath $eventsPath -SimpleMatch `
                ('PASS|' + $proof + '|') -Quiet)) {
            throw "Taxi call stage proof did not complete $proof; run retained at $RunRoot."
        }
    }
}
if ($TaxiCallResume -and $status -eq 'PASS') {
    foreach ($proof in @('taxi_call_resume_exact_native_party',
        'taxi_call_resume_arrived_and_settled')) {
        if (-not (Select-String -LiteralPath $eventsPath -SimpleMatch `
                ('PASS|' + $proof + '|') -Quiet)) {
            throw "Taxi call resume proof did not complete $proof; run retained at $RunRoot."
        }
    }
}
if ($TaxiRecoveryResume -and $status -eq 'PASS') {
    foreach ($proof in @('taxi_cold_recovery_same_native_car',
        'taxi_cold_recovery_exact_paid_ring')) {
        $found = Select-String -LiteralPath $eventsPath -SimpleMatch `
            ('PASS|' + $proof + '|') -Quiet
        if (-not $found) {
            throw "Taxi cold recovery did not complete $proof; run retained at $RunRoot."
        }
    }
}
if ($DrivingBlocked -and
    (Select-String -LiteralPath $eventsPath -SimpleMatch 'SKIP|drive_blocked_no_loaded_alternate|' -Quiet)) {
    if ($status -ne 'PASS') {
        throw "LIVE_SANDBOX_FAIL run=$runId results=$eventsPath"
    }
    Write-Output "Live sandbox run retained for audit: $RunRoot"
    Write-Output "Live console: $consolePath"
    Write-Output "LIVE_SANDBOX_SKIP run=$runId reason=no_loaded_alternate results=$eventsPath"
    return
}
if ($DrivingSaveStage -and $status -eq 'PASS') {
    if ($postSummaryForcedStop) {
        throw 'The cloned client did not finish its own world save and exit; driving stage is invalid.'
    }
    $stageSignal = Join-Path $SandboxLua 'driving-save-stage.txt'
    if (-not (Test-Path -LiteralPath $stageSignal -PathType Leaf) -or
        -not (Select-String -LiteralPath $eventsPath -SimpleMatch 'PASS|drive_save_stage_persisted_seat_zero|' -Quiet)) {
        throw "Driving stage did not write verified seat-zero proof: $stageSignal"
    }
    $stageProofDestination = Join-Path $TargetSave 'SC-driving-stage-proof.txt'
    Copy-Item -LiteralPath $stageSignal -Destination $stageProofDestination
    Write-Output "Driving resume seed: $TargetSave"
    Write-Output "Driving stage proof: $stageProofDestination"
}
if ($TaxiPassengerProbe -and $status -eq 'PASS') {
    if ($postSummaryForcedStop) {
        throw 'The cloned client did not finish its own world save and exit; taxi stage is invalid.'
    }
    $taxiStageSignal = Join-Path $SandboxLua 'taxi-save-stage.txt'
    if (-not (Test-Path -LiteralPath $taxiStageSignal -PathType Leaf)) {
        throw "Taxi stage did not write exact cab and fare proof: $taxiStageSignal"
    }
    $taxiProofDestination = Join-Path $TargetSave 'SC-taxi-stage-proof.txt'
    Copy-Item -LiteralPath $taxiStageSignal -Destination $taxiProofDestination
    Write-Output "Taxi recovery seed: $TargetSave"
    Write-Output "Taxi stage proof: $taxiProofDestination"
}
if ($TaxiCallStage -and $status -eq 'PASS') {
    if ($postSummaryForcedStop) {
        throw 'The cloned client did not finish its world save and exit; taxi call stage is invalid.'
    }
    $signal = Join-Path $SandboxLua 'taxi-call-stage.txt'
    if (-not (Test-Path -LiteralPath $signal -PathType Leaf)) {
        throw "Taxi call stage did not write its exact native party proof: $signal"
    }
    $destination = Join-Path $TargetSave 'SC-taxi-call-stage-proof.txt'
    Copy-Item -LiteralPath $signal -Destination $destination
    Write-Output "Taxi call resume seed: $TargetSave"
    Write-Output "Taxi call stage proof: $destination"
}
if ($TeamDriveRestartStage -and $status -eq 'PASS') {
    if ($postSummaryForcedStop) {
        throw 'The cloned client did not finish its own world save and exit; team-drive stage is invalid.'
    }
    $teamStageSignal = Join-Path $SandboxLua 'team-drive-stage.txt'
    if (-not (Test-Path -LiteralPath $teamStageSignal -PathType Leaf) -or
        -not (Select-String -LiteralPath $eventsPath -SimpleMatch 'PASS|team_drive_restart_stage_saved|' -Quiet)) {
        throw "Team-drive stage did not write verified schema-6 proof: $teamStageSignal"
    }
    $teamProofDestination = Join-Path $TargetSave 'SC-team-drive-stage-proof.txt'
    Copy-Item -LiteralPath $teamStageSignal -Destination $teamProofDestination
    Write-Output "Team-drive resume seed: $TargetSave"
    Write-Output "Team-drive stage proof: $teamProofDestination"
}
if ($PyreBurnProbe) {
    # TakeFullScreenshot writes a PNG without appending an extension to the name.
    $pyreSource = Join-Path (Join-Path $CacheRoot 'Screenshots') ($runId + '-pyre-lit')
    if (-not (Test-Path -LiteralPath $pyreSource -PathType Leaf)) {
        throw "The lit pyre screenshot was not created: $pyreSource"
    }
    Copy-Item -LiteralPath $pyreSource -Destination $PyreBurnScreenshot -Force
    Write-Output "Lit pyre screenshot: $PyreBurnScreenshot"
}
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
if ($captureStrangeFolkPortraits) {
    foreach ($portrait in $strangeFolkPortraitLabels) {
        if (-not $strangeFolkPortraitsCaptured[$portrait]) {
            throw "Missing Strange Folk portrait capture: $portrait"
        }
    }
    Write-Output "Strange Folk portraits: $StrangeFolkPortraitScreenshotDirectory"
}
if ($captureDeputyRhonda) {
    if (-not $deputyRhondaCaptured) { throw 'Missing Deputy Rhonda screenshot capture.' }
    Write-Output "Deputy Rhonda screenshot: $DeputyRhondaScreenshot"
}
if ($captureLoretta) {
    if (-not $lorettaCaptured) { throw 'Missing Loretta screenshot capture.' }
    Write-Output "Loretta screenshot: $LorettaScreenshot"
}
if ($captureMilli) {
    if (-not $milliCaptured) { throw 'Missing Milli screenshot capture.' }
    Write-Output "Milli screenshot: $MilliScreenshot"
}
if ($captureOddballScene -and $status -eq 'PASS') {
    if (-not $oddballSceneCaptured) { throw 'Missing oddball scene screenshot capture.' }
    Write-Output "Oddball scene screenshot: $OddballSceneScreenshot"
}
if ($status -ne 'PASS') {
    throw "LIVE_SANDBOX_FAIL run=$runId results=$eventsPath"
}
Write-Output "LIVE_SANDBOX_PASS run=$runId results=$eventsPath"
