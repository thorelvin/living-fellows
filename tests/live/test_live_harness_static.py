# SPDX-License-Identifier: MIT

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / "tests/live/mod/SCRealSandboxHarness/42/media/lua/client/SCRealSandboxHarness.lua"
RUNNER = ROOT / "scripts/Invoke-LiveSandboxTests.ps1"
ROOT_INFO = ROOT / "tests/live/mod/SCRealSandboxHarness/mod.info"
VERSION_INFO = ROOT / "tests/live/mod/SCRealSandboxHarness/42/mod.info"

lua = LUA.read_text(encoding="utf-8")
runner = RUNNER.read_text(encoding="utf-8")
root_info = ROOT_INFO.read_text(encoding="utf-8")
version_info = VERSION_INFO.read_text(encoding="utf-8")

checks = 0


def require(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if not condition:
        raise AssertionError(message)


for info in (root_info, version_info):
    require("id=SCRealSandboxHarness" in info, "harness mod id must be isolated")
    require("require=SurvivorCompanion" in info, "harness must load after the production mod")
    require("versionMin=42.20.4" in info and "versionMax=42.20.4" in info,
            "harness must use the same exact game-family gate")

require("-cachedir=" in runner, "runner must redirect the complete user cache")
require("build\\live-sandbox-runs" in runner, "runs must stay under the project build tree")
require("Copy-Item -LiteralPath $SeedSave -Destination $TargetSave -Recurse" in runner,
        "runner must clone, never open, the source save")
require("sourceSaveIsReadOnlyInput = $true" in runner, "run manifest must state source-save ownership")
require("[switch]$LivingFellowsOnly" in runner
        and "livingFellowsOnly = $LivingFellowsOnly.IsPresent" in runner,
        "runner must expose and record a Living-Fellows-only release-isolation mode")
require("-not $LivingFellowsOnly" in runner
        and '"VERSION = 1,`r`n`r`nmods' in runner,
        "isolation mode must omit local mod junctions and rebuild a minimal mod list")
require("autoCleanup = $false" in runner, "audit runs must not recursively clean junction-bearing trees")
require("Test-ProjectZomboidRunning" in runner, "runner must refuse a second game process")
require("installedBridgeHash" in runner and "sourceBridgeHash" in runner
        and "Get-FileHash" in runner,
        "runner must prove the installed bridge matches the source candidate")
require("Stop-OwnedSandboxProcess" in runner
        and "Stop-Process -Id $OwnedProcess.Id -Force" in runner
        and "runner_failure" in runner and "post_summary_deadline" in runner,
        "runner must terminate only its owned client on timeout, failure, or failed self-exit")
require("survivorcompanion/bridge/SCLauncher" in runner, "runner must require the native launcher")
require("SCRealSandboxHarness" in runner and "Add-ModEntry" in runner,
        "runner must add the harness to default and cloned-save mod lists")
require("New-PrivatePlaytestPayload.ps1" in runner,
        "live faction tests must stage the debug-only manual-spawn payload")
require("reset-mods-42_00.txt" in runner and "Copy-Item -LiteralPath $resetMarker" in runner,
        "new cachedirs must preserve Build 42's mod-reset marker before boot")
require("('run_id=' + $runId)" in runner and "('world=' + $runId)" in runner,
        "dynamic config values must remain one key=value line in Windows PowerShell")
require("Start-Process" in runner and "-PassThru" in runner,
        "runner must retain ownership of the launched client process")
require("LIVE_SANDBOX_PASS" in runner and "LIVE_SANDBOX_FAIL" in runner,
        "runner must expose machine-readable terminal markers")
require("Invoke-LoadingScreenClick" in runner,
        "runner must handle Build 42's mouse-only click-to-start gate")
require("mouse_event" in runner and "GetCursorPos" in runner and
        "SetCursorPos(original.X, original.Y)" in runner,
        "the GLFW loading click must restore the user's desktop cursor")
require("game loading took" in runner,
        "runner must wait for the real world load before clicking")
require("-not (Test-Path -LiteralPath $eventsPath" in runner,
        "loading clicks must stop when the live assertions begin")

for token in (
    "Events.OnMainMenuEnter",
    "MainScreen.continueLatestSave",
    "SC_REAL_SANDBOX|AUTOLOAD_CONFIRM",
    "Events.OnGameStart",
    "Events.OnRenderTick",
    "getFileWriter",
    "SC_REAL_SANDBOX_SUMMARY_V1",
    "getCore():quitToDesktop()",
):
    require(token in lua, f"live harness lifecycle contract missing: {token}")

for test_name in (
    "single_player_client",
    "native_bridge_ready",
    "local_player_slot_zero",
    "gameplay_clock_running",
    "deferred_native_spawn",
    "native_actor_validation",
    "registry_ownership",
    "production_scheduler_active",
    "real_route_evaluation",
    "alternative_follow_routes",
    "real_follow_progress",
    "real_room_entry_sweep",
    "native_rear_awareness",
    "formation_facing_restore",
    "local_player_unchanged",
    "native_zombie_targets_companion",
    "direct_native_melee_attack",
    "debug_faction_tools_enabled",
    "manual_faction_household_spawn",
    "persistent_faction_registration",
    "faction_member_command_isolation",
    "faction_fortification_plan",
    "persistent_faction_life_profile",
    "persistent_social_contract_profile",
    "real_representative_conversation",
    "social_contract_single_active_and_reward_scope",
    "all_social_contract_kinds",
    "all_social_contract_complications",
    "social_contract_broken_promise",
    "social_contract_guest_access",
    "faction_debug_personality_controls",
    "faction_debug_routine_control",
    "faction_debug_resource_audit",
    "faction_debug_crisis_controls",
    "real_world_map_rumour",
    "faction_representative_policy",
    "native_faction_barricade_work",
    "territorial_warning_state",
    "faction_save_document",
    "native_human_targeting",
):
    require(f'"{test_name}"' in lua, f"live assertion missing: {test_name}")

require("internal_timeout_ms" in lua and "harness_timeout" in lua,
        "in-game harness needs its own fail-safe timeout")
require("MainScreen.instance.checkSavefileModal" in lua and "modal:onClick(modal.yes)" in lua
        and "autoloadConfirmations" in lua and "modal ~= Harness.autoloadModal" in lua
        and "autoloadPromptSignatures" in lua and '"autoload_prompt_loop"' in lua,
        "isolated cloned saves must auto-confirm sequential load/conversion prompts")
require("pcall(tick)" in lua and "unhandled_harness_error" in lua,
        "event errors must become durable failed results")
require("pcall(MainScreen.continueLatestSave" in lua,
        "main-menu autoload failures must become durable failed results")
require("Actor.beginSpawn" in lua and "Actor.pollSpawn" in lua,
        "spawn test must exercise the deferred production API")
require("Harness.factionProgressAt" in lua
        and "stalledFor > 20000" in lua and "elapsed > 45000" in lua
        and '"queued=" .. tostring(member.spawnQueued == true)' in lua
        and 'if task.name == "factions"' in lua,
        "faction registration must tolerate healthy deferred spawning and diagnose a real stall")
require("beginHarnessControl" in lua
        and "supervisorToken = Harness.roomSupervisorToken" in lua
        and "supervisorToken = Harness.combatSupervisorToken" in lua
        and "record.runtime.inactive = true" not in lua,
        "deterministic probes must use action ownership without deactivating the actor")
require('inventory:AddItem("Base.Katana")' in lua
        and 'action = "attack_melee"' in lua and '"isAttackStarted"' in lua
        and '"isPerformingAttackAnimation"' in lua
        and '"getSecondaryHandItem"' in lua and '"getUseHandWeapon"' in lua
        and 'Harness.phase == "combat_animation"' in lua,
        "live harness must prove that a two-handed native sword attack animates and completes")
for diagnostic in (
    '"getCompanionActionGroupName"', '"getCompanionActionStateName"',
    '"isInitiateAttack"',
    '"getVariableString", "Weapon"', '"getVariableBoolean", "rangedWeapon"',
    '"getVariableBoolean", "bDoShove"', '"isAnimationUpdatingThisFrame"',
    '"getCurrentState"', '"isDoShove"', '"isAimAtFloor"',
    '"isCollidedWithVehicle"', '"isCollidedWithDoor"', '"getCollidedObject"',
    '"target_health="', '"target_dead="',
):
    require(diagnostic in lua,
            f"native combat failure diagnostics missing: {diagnostic}")
require('utility.call(actor, "getActionContext")' not in lua,
        "live diagnostics must not index Build 42's unexposed ActionContext from Kahlua")
require('SC.GameplayUtil.call(Harness.actor, "checkActionGroup")' in lua
        and '"group_control="' in lua,
        "native combat probe must isolate stale player action-group state")
require("SC.Navigation.evaluateRoutes" in lua,
        "route test must exercise real loaded grid squares")
require("checking_room_entry_left" in lua and "checking_room_entry_right" in lua,
        "room test must observe both production sweep phases")
require(re.search(r"expanded\s*<=\s*380", lua) is not None,
        "route test must enforce the bounded search budget")

release_files = [
    ROOT / "SurvivorCompanion/mod.info",
    ROOT / "SurvivorCompanion/42/mod.info",
    ROOT / "scripts/Build-Workshop.ps1",
]
for path in release_files:
    require("SCRealSandboxHarness" not in path.read_text(encoding="utf-8"),
            f"private harness leaked into release surface: {path.name}")

print(f"LIVE_HARNESS_STATIC_PASS assertions={checks}")
