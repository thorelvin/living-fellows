# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [switch]$FishingOnly,
    [switch]$NicknamesOnly,
    [switch]$HomeTripOnly
)

$ErrorActionPreference = 'Stop'
if ($FishingOnly -and $NicknamesOnly) { throw 'Choose one focused test group.' }
if ($HomeTripOnly -and ($FishingOnly -or $NicknamesOnly)) { throw 'Choose one focused test group.' }
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$ClientRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$SharedRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = & (Join-Path $ProjectRoot 'scripts\Resolve-TestJavac.ps1')
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sc-gameplay-tests-" + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $Jar) -or -not (Test-Path -LiteralPath $GameJava)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

$Core = Join-Path $ProjectRoot 'tests/core'
$Gameplay = $TestRoot
$Essential = Join-Path $ProjectRoot 'tests/essential'
$Shared = $SharedRoot
$Client = $ClientRoot
. (Join-Path $Essential 'Gameplay.ps1')
$LuaFiles = @(Get-ScGameplayFiles)
$BaseLuaFiles = @($LuaFiles)
$LuaFiles += Join-Path $TestRoot 'gameplay_harness.lua'
$LuaFiles += Join-Path $Essential 'combat_harness.lua'
$LuaFiles += Join-Path $Essential 'needs_harness.lua'
$LuaFiles += Join-Path $TestRoot 'tv_watching_harness.lua'
$LuaFiles += Join-Path $TestRoot 'computer_use_harness.lua'
$LuaFiles += Join-Path $TestRoot 'radio_listening_harness.lua'
$LuaFiles += Join-Path $TestRoot 'fishing_harness.lua'
$LuaFiles += Join-Path $TestRoot 'chef_harness.lua'
$LuaFiles += Join-Path $TestRoot 'hygiene_effects_harness.lua'
$LuaFiles += Join-Path $TestRoot 'hygiene_audio_harness.lua'
$LuaFiles += Join-Path $TestRoot 'base_alert_harness.lua'
if ($FishingOnly) {
    $LuaFiles = @($BaseLuaFiles)
    $LuaFiles += Join-Path $TestRoot 'fishing_harness.lua'
}

New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $TestRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay Kahlua runner compilation failed.' }

    Push-Location -LiteralPath $GameRoot
    try {
        $homeTripFiles = @(
            (Join-Path $ProjectRoot 'tests/core/core_fixture.lua'),
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $ClientRoot 'SCExpeditionIntegration.lua'),
            (Join-Path $ClientRoot 'SCHomeTrip.lua'),
            (Join-Path $ClientRoot 'SCExpeditionPrototype.lua'),
            (Join-Path $TestRoot 'home_trip_fixture.lua'),
            (Join-Path $TestRoot 'home_trip_harness.lua')
        )
        $homeArrivalPersistenceFiles = @(
            (Join-Path $ProjectRoot 'tests/core/core_fixture.lua'),
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $SharedRoot 'SCCall.lua'),
            (Join-Path $SharedRoot 'SCStableValue.lua'),
            (Join-Path $SharedRoot 'SCNativeList.lua'),
            (Join-Path $SharedRoot 'SCConfig.lua'),
            (Join-Path $SharedRoot 'SCDiagnostics.lua'),
            (Join-Path $ClientRoot 'SCPersistence.lua'),
            (Join-Path $TestRoot 'home_arrival_persistence_harness.lua')
        )
        if ($HomeTripOnly) {
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @homeTripFiles
            if ($LASTEXITCODE -ne 0) { throw 'Walking home trip lifecycle harness failed.' }
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @homeArrivalPersistenceFiles
            if ($LASTEXITCODE -ne 0) { throw 'Remote home arrival persistence harness failed.' }
            return
        }
        $needsFiles = @(
            (Join-Path $ClientRoot 'SCNeeds.lua'),
            (Join-Path $TestRoot 'needs_rate_regression_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @needsFiles
        if ($LASTEXITCODE -ne 0) { throw 'Companion needs rate regression harness failed.' }
        if (-not $NicknamesOnly) {
            $scenarioLines = foreach ($scenario in @($LuaFiles | Select-Object -Skip $BaseLuaFiles.Count)) {
                "--group $([IO.Path]::GetFileNameWithoutExtension($scenario))"
                foreach ($source in $BaseLuaFiles) { $source }
                $scenario
            }
            $scenarioList = Join-Path $BuildRoot 'gameplay.groups'
            [IO.File]::WriteAllLines($scenarioList, [string[]]$scenarioLines, (New-Object Text.UTF8Encoding($false)))
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner --groups $scenarioList
            if ($LASTEXITCODE -ne 0) { throw 'Gameplay Kahlua integration harness failed.' }
            if ($FishingOnly) { return }
            # Distinct specialists retained from the removed monolith each get
            # a fresh environment; none depend on previous scenario side effects.
            $subjects = @(
                @{ Name = 'loadout'; Files = @('loadout_harness.lua') },
                @{ Name = 'camp habits'; Files = @('camp_habits_harness.lua') },
                @{ Name = 'decision ownership'; Files = @('decision_ownership_harness.lua') },
                @{ Name = 'target work'; Files = @('target_work_harness.lua') },
                @{ Name = 'character depth'; Files = @('character_depth_harness.lua') },
                @{ Name = 'faction restore'; Files = @('faction_restore_harness.lua') },
                @{ Name = 'vehicle policy'; Files = @('vehicle_policy_harness.lua') },
                @{ Name = 'human combat'; Files = @('human_combat_regressions.lua', 'human_combat_harness.lua') },
                @{ Name = 'weapon selection'; Files = @('weapon_selection_regressions.lua', 'weapon_selection_harness.lua') }
            )
            foreach ($subject in $subjects) {
                $subjectFiles = @($BaseLuaFiles) + @($subject.Files | ForEach-Object { Join-Path $TestRoot $_ })
                & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @subjectFiles
                if ($LASTEXITCODE -ne 0) { throw "Gameplay $($subject.Name) subject failed." }
            }
            $voiceDepthFiles = @((Join-Path $ProjectRoot 'tests/core/core_fixture.lua')) + @($BaseLuaFiles) + @(
                (Join-Path $ClientRoot 'SCProduction.lua'),
                (Join-Path $TestRoot 'voice_depth_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @voiceDepthFiles
            if ($LASTEXITCODE -ne 0) { throw 'Contextual voice depth and pacing harness failed.' }
            # Other integration fixtures replace utility/subsystem tables.
            # Floor regressions need the real inventory scanner and storage
            # helper, so load them into a fresh Kahlua environment.
            $floorSortFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $SharedRoot 'SCCall.lua'),
                (Join-Path $SharedRoot 'SCNativeList.lua'),
                (Join-Path $SharedRoot 'SCStableValue.lua'),
                (Join-Path $ClientRoot 'SCGameplayUtil.lua'),
                (Join-Path $TestRoot 'base_work_fixture.lua'),
                (Join-Path $ClientRoot 'SCWorkTransport.lua'),
                (Join-Path $ClientRoot 'SCFloorSort.lua'),
                (Join-Path $ClientRoot 'SCBaseWork.lua'),
                (Join-Path $TestRoot 'floor_sort_harness.lua'),
                (Join-Path $ClientRoot 'SCFloorSort.lua'),
                (Join-Path $TestRoot 'floor_stack_reload_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @floorSortFiles
            if ($LASTEXITCODE -ne 0) { throw 'Floor sorting regression harness failed.' }
            $guardPatrolFiles = @(
                (Join-Path $ProjectRoot 'tests\core\core_fixture.lua'),
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $SharedRoot 'SCCall.lua'),
                (Join-Path $SharedRoot 'SCNativeList.lua'),
                (Join-Path $TestRoot 'base_guard_patrol_fixture.lua'),
                (Join-Path $ClientRoot 'SCBaseWork.lua'),
                (Join-Path $TestRoot 'base_guard_patrol_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @guardPatrolFiles
            if ($LASTEXITCODE -ne 0) { throw 'Base guard patrol liveness harness failed.' }
            $followHandoffFiles = @(
                (Join-Path $ProjectRoot 'tests\core\core_fixture.lua'),
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $SharedRoot 'SCCall.lua'),
                (Join-Path $SharedRoot 'SCStableValue.lua'),
                (Join-Path $SharedRoot 'SCNativeList.lua'),
                (Join-Path $TestRoot 'base_guard_patrol_fixture.lua'),
                (Join-Path $ClientRoot 'SCBaseWork.lua'),
                (Join-Path $ClientRoot 'SCGuardPost.lua'),
                (Join-Path $ClientRoot 'SCCommands.lua'),
                (Join-Path $TestRoot 'follow_order_handoff_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @followHandoffFiles
            if ($LASTEXITCODE -ne 0) { throw 'Follow order handoff harness failed.' }
            $encounterHandoffFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCScavengeLoot.lua'),
                (Join-Path $ClientRoot 'SCEncounter.lua'),
                (Join-Path $TestRoot 'encounter_handoff_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @encounterHandoffFiles
            if ($LASTEXITCODE -ne 0) { throw 'Encounter work handoff regression harness failed.' }
            $expeditionContainerFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCScavengeLoot.lua'),
                (Join-Path $ClientRoot 'SCEncounter.lua'),
                (Join-Path $TestRoot 'expedition_container_search_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @expeditionContainerFiles
            if ($LASTEXITCODE -ne 0) { throw 'Expedition store container discovery regression harness failed.' }
            $expeditionDeadlineFiles = @(
                (Join-Path $ProjectRoot 'tests/core/core_fixture.lua'),
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCScavengeLoot.lua'),
                (Join-Path $ClientRoot 'SCEncounter.lua'),
                (Join-Path $ClientRoot 'SCExpeditionPrototype.lua'),
                (Join-Path $TestRoot 'expedition_search_deadline_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @expeditionDeadlineFiles
            if ($LASTEXITCODE -ne 0) { throw 'Expedition bounded discovery and real return clock regression harness failed.' }
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @homeTripFiles
            if ($LASTEXITCODE -ne 0) { throw 'Walking home trip lifecycle harness failed.' }
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @homeArrivalPersistenceFiles
            if ($LASTEXITCODE -ne 0) { throw 'Remote home arrival persistence harness failed.' }
            $decisionArbitrationFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $SharedRoot 'SCCall.lua'),
                (Join-Path $ClientRoot 'SCActionSupervisor.lua'),
                (Join-Path $ClientRoot 'SCDecision.lua'),
                (Join-Path $TestRoot 'decision_arbitration_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @decisionArbitrationFiles
            if ($LASTEXITCODE -ne 0) { throw 'Decision arbitration regression harness failed.' }
            $needsTripFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCNeeds.lua'),
                (Join-Path $TestRoot 'needs_trip_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @needsTripFiles
            if ($LASTEXITCODE -ne 0) { throw 'Expedition carried-supply needs regression failed.' }
            $needsPriorityFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCScavengeLoot.lua'),
                (Join-Path $ClientRoot 'SCEncounter.lua'),
                (Join-Path $ClientRoot 'SCNeeds.lua'),
                (Join-Path $TestRoot 'needs_priority_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @needsPriorityFiles
            if ($LASTEXITCODE -ne 0) { throw 'Needs food preference and travel pause regression failed.' }
            $campSupplyBudgetFiles = $needsPriorityFiles + @(
                (Join-Path $SharedRoot 'SCConfig.lua'),
                (Join-Path $ClientRoot 'SCPerformance.lua'),
                (Join-Path $TestRoot 'camp_supply_budget_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @campSupplyBudgetFiles
            if ($LASTEXITCODE -ne 0) { throw 'Shared camp supply budget, cursor and cache regression failed.' }
            $supplyPolicyFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCLogistics.lua'),
                (Join-Path $TestRoot 'supply_policy_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @supplyPolicyFiles
            if ($LASTEXITCODE -ne 0) { throw 'Expedition supply policy regression harness failed.' }
            $readingSessionFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $SharedRoot 'SCCall.lua'),
                (Join-Path $SharedRoot 'SCConfig.lua'),
                (Join-Path $TestRoot 'reading_session_fixture.lua'),
                (Join-Path $ClientRoot 'SCActionSupervisor.lua'),
                (Join-Path $ClientRoot 'SCDowntime.lua'),
                (Join-Path $TestRoot 'reading_session_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @readingSessionFiles
            if ($LASTEXITCODE -ne 0) { throw 'Reading session regression harness failed.' }
            $seatRouteFiles = @($readingSessionFiles | Select-Object -SkipLast 1)
            $seatRouteFiles += Join-Path $TestRoot 'downtime_seat_route_harness.lua'
            $seatRouteFiles += Join-Path $TestRoot 'follower_sitting_harness.lua'
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @seatRouteFiles
            if ($LASTEXITCODE -ne 0) { throw 'Downtime seat route handoff harness failed.' }
            $autonomyGroundFiles = @(
                (Join-Path $SharedRoot 'SCNamespace.lua'),
                (Join-Path $SharedRoot 'SCSpeechColors.lua'),
                (Join-Path $ClientRoot 'SCAutonomy.lua'),
                (Join-Path $TestRoot 'autonomy_ground_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @autonomyGroundFiles
            if ($LASTEXITCODE -ne 0) { throw 'Autonomy ground interaction regression harness failed.' }
            $comfortFiles = @(
                (Join-Path $TestRoot 'user_comfort_fixture.lua'),
                (Join-Path $ClientRoot 'SCTales.lua'),
                (Join-Path $ClientRoot 'SCBanter.lua'),
                (Join-Path $ClientRoot 'SCGestures.lua'),
                (Join-Path $TestRoot 'user_comfort_harness.lua')
            )
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @comfortFiles
            if ($LASTEXITCODE -ne 0) { throw 'User comfort preference harness failed.' }
            $medicalFiles = @((Join-Path $ProjectRoot 'tests\core\core_fixture.lua'))
            $medicalFiles += $BaseLuaFiles
            $medicalFiles += Join-Path $TestRoot 'medical_liveness_regression_harness.lua'
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @medicalFiles
            if ($LASTEXITCODE -ne 0) { throw 'Medical liveness/rescue regression harness failed.' }
            $combatFiles = @((Join-Path $ProjectRoot 'tests\core\core_fixture.lua'))
            $combatFiles += $BaseLuaFiles
            $combatFiles += Join-Path $TestRoot 'combat_coordination_regression_harness.lua'
            & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @combatFiles
            if ($LASTEXITCODE -ne 0) { throw 'Combat coordination regression harness failed.' }
        }
        $diaryFiles = @(
            (Join-Path $TestRoot 'diary_fixture.lua'),
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $SharedRoot 'SCCall.lua'),
            (Join-Path $SharedRoot 'SCStableValue.lua'),
            (Join-Path $SharedRoot 'SCNativeList.lua'),
            (Join-Path $SharedRoot 'SCConfig.lua'),
            (Join-Path $SharedRoot 'SCDiagnostics.lua'),
            (Join-Path $ClientRoot 'SCGameplayUtil.lua'),
            (Join-Path $ClientRoot 'SCNames.lua'),
            (Join-Path $ClientRoot 'SCPersonalItems.lua'),
            (Join-Path $ClientRoot 'SCDiaryText.lua'),
            (Join-Path $ClientRoot 'SCDiaryCatalog.lua'),
            (Join-Path $ClientRoot 'SCDiaryItem.lua'),
            (Join-Path $ClientRoot 'SCDiary.lua'),
            (Join-Path $TestRoot 'diary_harness.lua'),
            (Join-Path $TestRoot 'nickname_diary_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @diaryFiles
        if ($LASTEXITCODE -ne 0) { throw 'Private diary harness failed.' }
        $memorialFiles = @(
            (Join-Path $TestRoot 'nickname_memorial_fixture.lua'),
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $SharedRoot 'SCStableValue.lua'),
            (Join-Path $ClientRoot 'SCNames.lua'),
            (Join-Path $ClientRoot 'SCCommunity.lua'),
            (Join-Path $ClientRoot 'SCProduction.lua'),
            (Join-Path $TestRoot 'nickname_memorial_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @memorialFiles
        if ($LASTEXITCODE -ne 0) { throw 'Nickname memorial harness failed.' }
        $graveMarkerFiles = @(
            (Join-Path $TestRoot 'grave_marker_name_fixture.lua'),
            (Join-Path $ClientRoot 'SCBaseWork.lua'),
            (Join-Path $ClientRoot 'SCInfectionCrisis.lua'),
            (Join-Path $TestRoot 'grave_marker_name_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @graveMarkerFiles
        if ($LASTEXITCODE -ne 0) { throw 'Grave marker name harness failed.' }
        if ($NicknamesOnly) { return }
        $transferFiles = @(
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $ClientRoot 'SCUIBridge.lua'),
            (Join-Path $TestRoot 'companion_inventory_transfer_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @transferFiles
        if ($LASTEXITCODE -ne 0) { throw 'Companion inventory transfer harness failed.' }
        $giftFiles = @(
            (Join-Path $ClientRoot 'SCCompanionGifts.lua'),
            (Join-Path $TestRoot 'companion_gifts_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @giftFiles
        if ($LASTEXITCODE -ne 0) { throw 'Companion gift offer harness failed.' }
        $workVoiceFiles = @(
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $SharedRoot 'SCCall.lua'),
            (Join-Path $SharedRoot 'SCStableValue.lua'),
            (Join-Path $SharedRoot 'SCNativeList.lua'),
            (Join-Path $SharedRoot 'SCConfig.lua'),
            (Join-Path $ClientRoot 'SCGameplayUtil.lua'),
            (Join-Path $ClientRoot 'SCDialogue.lua'),
            (Join-Path $ClientRoot 'SCWorkVoiceLines.lua'),
            (Join-Path $ClientRoot 'SCWorkVoice.lua'),
            (Join-Path $TestRoot 'work_voice_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @workVoiceFiles
        if ($LASTEXITCODE -ne 0) { throw 'Expedition and work voice harness failed.' }
        $terminalFiles = @(
            (Join-Path $SharedRoot 'SCNamespace.lua'),
            (Join-Path $SharedRoot 'SCSpeechColors.lua'),
            (Join-Path $ClientRoot 'SCTerminalLines.lua'),
            (Join-Path $ClientRoot 'SCTerminalKnowledge.lua'),
            (Join-Path $ClientRoot 'SCTerminalConversation.lua'),
            (Join-Path $ClientRoot 'SCTerminalBrain.lua'),
            (Join-Path $ClientRoot 'SCTerminalLore.lua'),
            (Join-Path $ClientRoot 'SCTerminalFiles.lua'),
            (Join-Path $ClientRoot 'SCTerminalPresentation.lua'),
            (Join-Path $ClientRoot 'SCTerminalBusinessData.lua'),
            (Join-Path $ClientRoot 'SCTerminalBrands.lua'),
            (Join-Path $ClientRoot 'SCTerminalArtBounds.lua'),
            (Join-Path $ClientRoot 'SCTerminalSystem.lua'),
            (Join-Path $ClientRoot 'SCTerminalWorld.lua'),
            (Join-Path $TestRoot 'terminal_harness.lua'),
            (Join-Path $TestRoot 'terminal_system_harness.lua'),
            (Join-Path $TestRoot 'terminal_lore_harness.lua'),
            (Join-Path $TestRoot 'terminal_knowledge_harness.lua'),
            (Join-Path $TestRoot 'terminal_conversation_harness.lua')
            (Join-Path $TestRoot 'terminal_grid_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @terminalFiles
        if ($LASTEXITCODE -ne 0) { throw 'Camp computer terminal harness failed.' }
        $personaFiles = @('SCTerminalPersona.lua', 'SCTerminalPersonaSpiffy.lua', 'SCTerminalPersonaEllis.lua', 'SCTerminalPersonaDuty.lua') | ForEach-Object { Join-Path $ClientRoot $_ }
        $personaFiles += Join-Path $TestRoot 'persona_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @personaFiles
        if ($LASTEXITCODE -ne 0) { throw 'Supplied persona conversation harness failed.' }
    }
    finally {
        Pop-Location
    }

    & python (Join-Path $TestRoot 'test_gameplay_static.py')
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay static tests failed.' }
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $ResolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
        $ResolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $ResolvedBuildRoot.StartsWith($ResolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean test build outside the temporary directory: $ResolvedBuildRoot"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
