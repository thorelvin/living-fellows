# SPDX-License-Identifier: MIT
# Disposable local co-op streaming probe. Restores the installed launcher JSON.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SeedSave,
    [string]$GameMode = 'Rising',
    [string]$Screenshot = '',
    [string]$PostHandoffScreenshot = '',
    [switch]$ColdCompanionProbe,
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
    [switch]$TeamRoadRouteProbe,
    [switch]$TeamRoadHordeProbe,
    [switch]$TeamRoadRestartStageOnly,
    [switch]$TeamRoadRestartResumeProbe,
    [switch]$TeamKnownPlaceScoutProbe,
    [switch]$TeamUnvisitedPlaceScoutProbe,
    [switch]$TeamAutonomousSearchProbe,
    [switch]$TeamLeaderMotionProbe,
    [switch]$TeamUnvisitedInteriorSearchProbe,
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
    [switch]$PlaceMetadataOnly,
    [switch]$UseSavedMods,
    [ValidateRange(8, 180)][int]$WatchSeconds = 8,
    [ValidateRange(90, 900)][int]$TimeoutSeconds = 300,
    [switch]$HiddenWindow,
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$gameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$launcherPath = Join-Path $gameRoot 'ProjectZomboid64.json'
$candidate = Join-Path $projectRoot 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw 'Game launcher JSON missing.' }
if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    throw 'Build the experimental native bridge with Build-NativeBridge.ps1 -InstallIntoPayload first.'
}
if (Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like 'ProjectZomboid*' -or
        ($_.Name -match '^java(w)?\.exe$' -and $_.CommandLine -match 'ProjectZomboid')
    }) {
    throw 'Close Project Zomboid before temporarily switching the local launcher.'
}
if ([string]::IsNullOrWhiteSpace($Screenshot)) {
    $Screenshot = Join-Path $projectRoot 'build\split-screen-probe.png'
}
$Screenshot = [System.IO.Path]::GetFullPath($Screenshot)
$effectiveScreenshot = if ($PlaceMetadataOnly) { '' } else { $Screenshot }
if ($ColdRestartHandoff -and [string]::IsNullOrWhiteSpace($PostHandoffScreenshot)) {
    $PostHandoffScreenshot = Join-Path $projectRoot 'build\split-screen-restored-leader.png'
}
$backupRoot = Join-Path $projectRoot ('build\launcher-backup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$backupPath = Join-Path $backupRoot 'ProjectZomboid64.json'
Copy-Item -LiteralPath $launcherPath -Destination $backupPath
$originalHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
$launcher = Get-Content -LiteralPath $launcherPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($launcher.mainClass -ne 'survivorcompanion/bridge/SCLauncher') {
    throw 'The installed game launcher is not the expected Living Fellows launcher.'
}
$bridgeEntries = @($launcher.classpath | Where-Object { $_ -match 'SurvivorCompanion.*Bridge.*\.jar' })
if ($bridgeEntries.Count -ne 1) { throw 'Expected exactly one native bridge classpath entry.' }
$launcher.classpath = @($launcher.classpath | ForEach-Object {
        if ($_ -eq $bridgeEntries[0]) { $candidate.Replace('\', '/') } else { $_ }
    })
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [System.IO.File]::WriteAllText($launcherPath,
        ($launcher | ConvertTo-Json -Depth 10), $utf8NoBom)
    & (Join-Path $projectRoot 'scripts\Invoke-LiveSandboxTests.ps1') `
        -ProjectRoot $projectRoot -GameRoot $gameRoot -SeedSave $SeedSave `
        -GameMode $GameMode -LivingFellowsOnly:(-not $UseSavedMods) `
        -SplitScreenOnly:(-not $PlaceMetadataOnly) `
        -PlaceMetadataOnly:$PlaceMetadataOnly `
        -ColdCompanionProbe:$ColdCompanionProbe `
        -ColdRestartProbe:$ColdRestartProbe `
        -ColdRestartHandoff:$ColdRestartHandoff `
        -ColdRestartCrashProbe:$ColdRestartCrashProbe `
        -ColdRestartLfFirstCrashProbe:$ColdRestartLfFirstCrashProbe `
        -LeaderSlotOnly:$LeaderSlotOnly `
        -LeaderRemote:$LeaderRemote `
        -LeaderRemoteOffsetX $LeaderRemoteOffsetX `
        -LeaderRemoteOffsetY $LeaderRemoteOffsetY `
        -TeamHandoff:$TeamHandoff `
        -TeamRadioFixture:$TeamRadioFixture `
        -TeamRadioPlacedProbe:$TeamRadioPlacedProbe `
        -TeamRadioTimedPlacementProbe:$TeamRadioTimedPlacementProbe `
        -TeamRadioPlacedPickupProbe:$TeamRadioPlacedPickupProbe `
        -TeamRadioPlacedExpectedWalkieId $TeamRadioPlacedExpectedWalkieId `
        -TeamRadioPlacedExpectedHamId $TeamRadioPlacedExpectedHamId `
        -TeamRadioTextProbe:$TeamRadioTextProbe `
        -TeamRadioCommandProbe:$TeamRadioCommandProbe `
        -TeamWaypointProbe:$TeamWaypointProbe `
        -TeamLocalTravelProbe:$TeamLocalTravelProbe `
        -TeamLocalLootRoundTripProbe:$TeamLocalLootRoundTripProbe `
        -TeamExtendedRouteProbe:$TeamExtendedRouteProbe `
        -TeamExtendedQuietProbe:$TeamExtendedQuietProbe `
        -TeamExtendedReturnProbe:$TeamExtendedReturnProbe `
        -TeamExtendedReturnResumeProbe:$TeamExtendedReturnResumeProbe `
        -TeamExtendedReturnSourceX $TeamExtendedReturnSourceX `
        -TeamExtendedReturnSourceY $TeamExtendedReturnSourceY `
        -TeamCorpseStreamingProbe:$TeamCorpseStreamingProbe `
        -TeamCorpseStreamingReloadProbe:$TeamCorpseStreamingReloadProbe `
        -TeamCorpseStreamVerifyX $TeamCorpseStreamVerifyX `
        -TeamCorpseStreamVerifyY $TeamCorpseStreamVerifyY `
        -TeamAutonomousScoutProbe:$TeamAutonomousScoutProbe `
        -TeamRoadRouteProbe:$TeamRoadRouteProbe `
        -TeamRoadHordeProbe:$TeamRoadHordeProbe `
        -TeamRoadRestartStageOnly:$TeamRoadRestartStageOnly `
        -TeamRoadRestartResumeProbe:$TeamRoadRestartResumeProbe `
        -TeamKnownPlaceScoutProbe:$TeamKnownPlaceScoutProbe `
        -TeamUnvisitedPlaceScoutProbe:$TeamUnvisitedPlaceScoutProbe `
        -TeamAutonomousSearchProbe:$TeamAutonomousSearchProbe `
        -TeamLeaderMotionProbe:$TeamLeaderMotionProbe `
        -TeamUnvisitedInteriorSearchProbe:$TeamUnvisitedInteriorSearchProbe `
        -TeamAutonomousSearchStageOnly:$TeamAutonomousSearchStageOnly `
        -TeamAutonomousSearchResumeProbe:$TeamAutonomousSearchResumeProbe `
        -TeamBuildingProbe:$TeamBuildingProbe `
        -TeamWindowProbe:$TeamWindowProbe `
        -TeamInsideDoorProbe:$TeamInsideDoorProbe `
        -TeamDoorBashProbe:$TeamDoorBashProbe `
        -TeamDoorBashAutoProbe:$TeamDoorBashAutoProbe `
        -TeamPursuerProbe:$TeamPursuerProbe `
        -TeamPursuerFixture:$TeamPursuerFixture `
        -TeamStragglerProbe:$TeamStragglerProbe `
        -TeamRestartAuditOnly:$TeamRestartAuditOnly `
        -TeamRestartStageOnly:$TeamRestartStageOnly `
        -TeamOverlapProbe:$TeamOverlapProbe `
        -TeamReturnReleaseProbe:$TeamReturnReleaseProbe `
        -TeamReturnStageOnly:$TeamReturnStageOnly `
        -TeamIdleSlotRestartProbe:$TeamIdleSlotRestartProbe `
        -TeamAllDeadIdleRestartProbe:$TeamAllDeadIdleRestartProbe `
        -TeamCorpseReloadProbe:$TeamCorpseReloadProbe `
        -TeamLootSurvey:$TeamLootSurvey `
        -TeamLootProbe:$TeamLootProbe `
        -TeamLootVerifyOnly:$TeamLootVerifyOnly `
        -TeamLootVerifyToken $TeamLootVerifyToken `
        -TeamLootVerifyItemType $TeamLootVerifyItemType `
        -TeamLootVerifyNativeId $TeamLootVerifyNativeId `
        -TeamAllDeadCleanup:$TeamAllDeadCleanup `
        -TeamAllDeadStageOnly:$TeamAllDeadStageOnly `
        -TeamAllDeadMenuCleanupProbe:$TeamAllDeadMenuCleanupProbe `
        -TeamMenuCleanupProbe:$TeamMenuCleanupProbe `
        -PerformanceBaselineOnly:$PerformanceBaselineOnly `
        -PerformancePopulation $PerformancePopulation `
        -TeamPerformanceProbe:$TeamPerformanceProbe `
        -TeamPerformanceRouteProbe:$TeamPerformanceRouteProbe `
        -TeamPerformanceEncounterProbe:$TeamPerformanceEncounterProbe `
        -TeamRepeatedHandoff:$TeamRepeatedHandoff `
        -TeamRadioKitOnly:$TeamRadioKitOnly `
        -TeamExpeditionUiProbe:$TeamExpeditionUiProbe `
        -TeamRadioKitVerifyOnly:$TeamRadioKitVerifyOnly `
        -LeaderWatchSeconds $WatchSeconds `
        -SplitScreenScreenshot $effectiveScreenshot `
        -PostHandoffScreenshot $PostHandoffScreenshot `
        -TimeoutSeconds $TimeoutSeconds `
        -HiddenWindow:$HiddenWindow
} finally {
    Copy-Item -LiteralPath $backupPath -Destination $launcherPath -Force
    $restoredHash = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
    if ($restoredHash -ne $originalHash) {
        throw 'Launcher JSON restore hash mismatch; inspect the saved backup.'
    }
    Write-Output "Restored original Project Zomboid launcher JSON sha256=$restoredHash"
}
