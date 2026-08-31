# SPDX-License-Identifier: MIT
"""Static release-boundary and central-runtime checks."""

from __future__ import annotations

import json
import re
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
PAYLOAD = PROJECT / "SurvivorCompanion"
LUA = PAYLOAD / "42" / "media" / "lua"
CLIENT = LUA / "client"
SHARED = LUA / "shared"


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


lua_files = sorted(LUA.rglob("*.lua"))
all_lua = "\n".join(path.read_text(encoding="utf-8") for path in lua_files)
tick_adds = [
    (path, match.start())
    for path in lua_files
    for match in re.finditer(r"Events\.OnTick\.Add\s*\(", path.read_text(encoding="utf-8"))
]
require(len(tick_adds) == 1 and tick_adds[0][0].name == "SCRuntime.lua",
        f"expected one central OnTick attachment, got {tick_adds}")

runtime = (CLIENT / "SCRuntime.lua").read_text(encoding="utf-8")
for task in ("decision", "vitals", "vehicle", "restore", "spawn-completion",
             "encounter-spawn", "factions",
             "ui-refresh", "community", "persistence"):
    require(f'"{task}"' in runtime, f"central scheduler task missing: {task}")
require('Scheduler.register("debug-spawn"' not in runtime,
        "automatic one-minute debug spawning must remain removed from runtime")
require("SC.Decision.resetAll" in runtime, "lifecycle reset must clear Decision state")
require('SC.Diagnostics.guard("decision", record.id' in runtime
        and 'SC.Diagnostics.guard("vitals", record.id' in runtime,
        "actor-specific runtime work lacks per-companion circuit breakers")
require("SC.UI.scheduledRefresh" in runtime, "UI refresh must be scheduler-owned")
require("onPlayerContainerOpened" in runtime, "container-open signal is not wired")
require("selectContainerWrapper" in runtime and "setNewContainerWrapper" in runtime
        and "ISInventoryPage.selectContainer == selectContainerWrapper" in runtime
        and "ISInventoryPage.setNewContainer == setNewContainerWrapper" in runtime,
        "container hook removal lacks explicit wrapper-ownership checks")
require("SC.Persistence.restore(player())" in runtime,
        "persistence document must import even when provider is unavailable")
require("notifyDisabled(reason)" in runtime and "setHaloNote" in runtime,
        "fail-closed runtime lacks its rate-limited in-game notice")
require("record.runtime.inactive == true" in runtime,
        "runtime tasks do not skip quarantined actors")
require("SC.Actor.validateNative(record.actor)" in runtime,
        "runtime does not remove a native companion that fails its health gate")
require("SC.Community.noteCompanionDeath" in runtime
        and runtime.index("SC.Community.noteCompanionDeath")
        < runtime.index("SC.Actor.retireDead(record.actor)"),
        "grief must be recorded once while the dead actor and nearby witnesses still exist")

bootstrap = (CLIENT / "SCBootstrap.lua").read_text(encoding="utf-8")
for module in ("SCSenses", "SCNavigation", "SCCombat", "SCMedical", "SCEncounter",
               "SCLogistics", "SCNeeds", "SCDowntime", "SCPersonality", "SCPersonalItems",
               "SCDialogue", "SCRelationship", "SCObjectives", "SCJournal", "SCLifeEvents", "SCCommunity",
               "SCAutonomy", "SCCommands", "SCDecision",
               "SCSupport", "SCUI", "SCUIContext", "SCCompanionMap"):
    require(f'require "{module}"' in bootstrap, f"bootstrap requirement missing: {module}")

native = (CLIENT / "SCNativeActions.lua").read_text(encoding="utf-8")
navigation = (CLIENT / "SCNavigation.lua").read_text(encoding="utf-8")
require("setDoShove" not in native, "nonexistent B42 setDoShove call regressed")
require("AttemptAttack" not in native, "AttemptAttack fallback must not receive guessed arguments")
for token in ("setAttackType", "DoAttack", "SHOVE", "STOMP", "SHOT", "MELEE_SWING"):
    require(token in native, f"native attack adapter missing {token}")
require('action == "shove" or action == "stomp"' in native,
        "shove/stomp authorization is not scoped")
require("room_sweep_facing_started" in native and "faceLocationF" in native
        and "isTurning" in native, "verified human room sweep is missing")
for action in ("loot_container", "kneel_treat", "rip_clothing_for_bandage",
               "read", "repair", "replace_bandage", "craft_supply"):
    require(re.search(rf"\b{action}\s*=\s*\{{\s*animation", native),
            f"verified human timed-action mapping missing: {action}")
require("native visual timed action did not start" in native,
        "visual actions lack truthful start rejection")
for token in ('require "TimedActions/ISBarricadeAction"', "getFirstTagEvalRecurse",
              "getSomeTypeRecurse", "setSecondaryHandItem",
              "barricade_timed_action_started"):
    require(token in native, f"real barricade action contract missing: {token}")
for token in ('require "TimedActions/ISUnbarricadeAction"',
              'require "TimedActions/ISDismantleAction"', "removeBarricade",
              "getCurrentUses", 'workTag("REMOVE_BARRICADE")',
              'workTag("SAW")', 'workTag("SCREWDRIVER")',
              'queueTrackedWork(actor, timedAction, record, "remove_barricade")',
              'queueTrackedWork(actor, timedAction, record, "dismantle")'):
    require(token in native, f"real destructive work action contract missing: {token}")
for token in ('require "TimedActions/ISEatFoodAction"',
              'require "TimedActions/ISDrinkFromBottle"',
              'require "TimedActions/ISTakeWaterAction"',
              "eat_food", "drink_item", "drink_source", "needsStatus", "cancelNeeds"):
    require(token in native, f"real companion needs action contract missing: {token}")
require("playEmote" in native and "hand_signal_started" in native,
        "native silent hand-signal adapter missing")
require("tacticalStrafe" in native and "facingTarget" in native
        and "setForwardDirection\", facingX, facingY" in native,
        "native tactical sidestep does not preserve its observation vector")
require('"EventSitOnGround"' in native and '"forceGetUp"' in native
        and 'action == "sit_ground"' in native and 'action == "stand_ground"' in native,
        "verified ground-sitting and recovery adapters are missing")

gameplay_util = (CLIENT / "SCGameplayUtil.lua").read_text(encoding="utf-8")
require('U.call(item, "getTags")' in gameplay_util
        and 'U.call(itemTag, "getTranslationName")' in gameplay_util
        and 'if type(item) == "table" then' in gameplay_util,
        "Build 42 item-tag lookup can regress to the pool-corrupting hasTag(String) call")

actor = (CLIENT / "SCActor.lua").read_text(encoding="utf-8")
require('kind = "iso-companion"' in actor and 'globalValue("SCBridge")' in actor
        and 'expectedNativeProtocol = "42.20-isocompanion-5"' in actor,
        "version-pinned native IsoCompanion provider boundary is missing")
for token in ("requestSpawn", "pollSpawn", "beginSpawn", "spawn_pending"):
    require(token in actor, f"deferred native spawn contract missing: {token}")
require('kind = "experimental-npc-player"' in actor and "directNative = true" in actor,
        "disabled emergency fallback boundary is missing")
require("isExistInTheWorld" in actor and "native removal postcondition failed" in actor
        and "quarantineRecord" in actor,
        "actor removal lacks verified postconditions/inactive quarantine")

vehicle = (CLIENT / "SCVehicle.lua").read_text(encoding="utf-8")
for token in ("function vehicleService.preflightBoard", "function vehicleService.isSeatReserved",
              "function vehicleService.assignmentFor", "function vehicleService.statusFor",
              "function vehicleService.canPassengerFire", "safeFallback", "rollbackNativeEntry"):
    require(token in vehicle, f"vehicle preflight/rollback contract missing: {token}")
require("if safeFallback ~= true then" in vehicle,
        "virtual seating must be blocked unless native non-entry/rollback was verified")
require('"getBestSeat"' not in vehicle and '"getMaxPassengers"' in vehicle
        and '"getEnterSeatDistance"' in vehicle,
        "vehicle seating must not use Build 42's getBestSeat stub")
require('"getCurrentSpeedKmHour"' in vehicle
        and "companion is not at the passenger door" in vehicle,
        "vehicle entry lacks speed and passenger-door proximity gates")
require("function vehicleService.importNativeSeat" in vehicle,
        "native-seated save records are not distinguished on restore")

persistence = (CLIENT / "SCPersistence.lua").read_text(encoding="utf-8")
require("save transaction aborted; prior snapshot retained" in persistence,
        "active record capture failure does not abort the save transaction")
require("lastStableSnapshot" in persistence and "quarantined companion" in persistence,
        "quarantined record does not preserve its last stable snapshot")
require("record.vehicle.stored == false" in persistence and "importNativeSeat" in persistence,
        "native and virtual vehicle save states are not distinguished")
require("community = SC.Community" in persistence
        and "SC.Community.restore(document.community)" in persistence,
        "community state is not persisted and restored")

commands = (CLIENT / "SCCommands.lua").read_text(encoding="utf-8")
require("entry.state =" in commands and "movementMode = state.moveMode" in commands
        and "combatStance = state.combatMode" in commands,
        "command state is not synchronized into the persistence schema")
for token in ("SC_WorkMode", "workTarget = stableWorkTarget", "handleBarricade",
              "handleFinishWork", "set_work_mode", "SC_WorkInitialPlanks"):
    require(token in commands, f"persistent companion work order missing: {token}")

downtime = (CLIENT / "SCDowntime.lua").read_text(encoding="utf-8")
require('itemType == "sheet" or itemType == "base.sheet"' in downtime
        and 'outputType = "Base.SheetRope"' in downtime,
        "downtime craft mode must use the real one-sheet sheet-rope recipe")
require('candidates(actor, commands, state, current, desiredKind)' in downtime,
        "downtime activities are not filtered by the explicit work mode")
require("ambientRepeatCooldownMs" in downtime and "lastFact.activity" in downtime,
        "ambient downtime can repeat the same action indefinitely")

decision = (CLIENT / "SCDecision.lua").read_text(encoding="utf-8")
require("guardPatrolTarget" in decision and 'action = "guard_patrol"' in decision,
        "base guards lack a bounded patrol state")
require("IGUI_SC_Threat_Warning" in decision and '"companion_alert"' in decision,
        "companions do not warn nearby survivors about visible threats")
require("workReservations" in decision and "work_reserved_by_companion" in decision
        and "releaseWorkReservation" in decision,
        "multi-companion work reservation contract is missing")
require("recentSharedAlert" in decision and 'action = "face_alert"' in decision,
        "shared companion danger reaction contract is missing")
require("barricade_already_completed" in decision and "initialPlanks" in decision,
        "save/load-safe one-shot build baseline is missing")
require("workApproachTimeoutMs" in decision and "work_timeout" in decision,
        "targeted work lacks a bounded approach timeout")
require("reportWorkFailure" in decision and "IGUI_SC_Work_NeedHammer" in decision,
        "targeted work failures do not produce bounded player feedback")
require("SC.Logistics.prepareBuild" in decision and 'candidate.kind == "needs"' in decision,
        "build logistics or needs utility is not integrated into arbitration")
require("SC.Personality.adjustDecision(commands.personalityProfile" in decision
        and "SC.Objectives.decisionBonus(commands.objectives" in decision,
        "bounded character-depth preference pass is not command-state based")
require("function actions.cancelWork" in native and "ISTimedActionQueue.clear" in native
        and "restoreWorkInventory" in native,
        "native work cancellation and equipment restoration contract is missing")
require("leaveFurniture" in native and 'setSittingOnFurniture", false' in native,
        "physical actions do not clear native furniture-sitting state")

vitals = (SHARED / "SCVitals.lua").read_text(encoding="utf-8")
require("setRequired" in vitals and "native vitals did not retain" in vitals,
        "native vitals restore does not truthfully verify mutations")
require("setInfectedWound" not in vitals,
        "nonexistent B42 BodyPart.setInfectedWound call regressed")

config = (SHARED / "SCConfig.lua").read_text(encoding="utf-8")
require(re.search(r"(?m)^\s*experimentalNpcPlayerActor\s*=\s*false,\s*$", config) is not None,
        "release experimental actor provider must be OFF")
require(re.search(r"(?m)^\s*debugSpawnEnabled\s*=\s*false,\s*$", config) is not None,
        "release debug spawn must be OFF")
require(re.search(r"(?m)^\s*productionEncounterEnabled\s*=\s*true,\s*$", config) is not None,
        "normal production encounter cadence must remain enabled")
require(re.search(r"(?m)^\s*debugSpawnIntervalMs\s*=\s*60000,\s*$", config) is not None,
        "debug spawn interval must be 60 seconds")
roster_limit = re.search(r"(?m)^\s*maxCompanions\s*=\s*(\d+),\s*$", config)
require(roster_limit is not None and 10 <= int(roster_limit.group(1)) <= 16,
        "release roster must support ten companions while remaining bounded to sixteen")

spawn = (CLIENT / "SCSpawn.lua").read_text(encoding="utf-8")
require("function spawn.generateIdentity" in spawn and "lastGeneratedIdentityKey" in spawn,
        "bounded non-repeating identity generator missing")
require("local survivorOutfits" in spawn and "Generic01" in spawn
        and "Backpacker" in spawn and "visualSeed" in spawn,
        "generated identity lacks a bounded stock outfit/visual seed")
name_entries = re.findall(r'\{ name = "([^"]+)", gender = "(?:female|male)" \}', spawn)
require(len(name_entries) >= 100 and len(name_entries) == len(set(name_entries)),
        "expanded genre first-name pool must contain at least 100 unique names")
for expected_name in (
    "Rick", "Michonne", "Daryl", "Maggie", "Negan",
    "Joel", "Ellie", "Abby", "Dina", "Tess",
    "Shaun", "Ed", "Liz", "Dianne", "Yvonne",
    "Jim", "Selena", "Ana", "Zoey", "Leon", "Seokwoo",
):
    require(expected_name in name_entries,
            f"requested genre first name missing: {expected_name}")
require("function spawn.productionPulse" in spawn and "productionSpawnCooldownMs" in spawn,
        "bounded non-debug production encounter pulse is unreachable")
require("runtime.active = true" in spawn and "runtime.disabledReason = nil" in spawn,
        "spawn cadence cannot recover from native bridge exposure startup races")

actor_source = (CLIENT / "SCActor.lua").read_text(encoding="utf-8")
require("getSpecificPlayer" in actor_source and "getNumActivePlayers" in actor_source,
        "experimental provider must observe player slots through vanilla accessors")
require(re.search(r"playerClass\.players\s*\[", actor_source) is None,
        "experimental provider must not index the live B42 IsoPlayer Java array")
require('invoke(value, "getPlayerNum")' in actor_source,
        "player-slot invariants must use the exposed player-number method")
require("actor.playerIndex" not in actor_source and "setLocalPlayer" not in actor_source,
        "private provider must not write player indexes or occupy local-player slots")
require("function actorService.bridgeStatus" in actor_source
        and 'code = "bridge_missing"' in actor_source
        and 'status.code = "protocol_mismatch"' in actor_source,
        "public bridge health status does not distinguish actionable failures")
require("cachedProvider = nil" in actor_source and "cachedReady = false" in actor_source
        and "return rejectExperimental(nil, observationReason)" in actor_source,
        "experimental provider failures must latch fail-closed instead of repeating every minute")
debug_pulse = re.search(r"function spawn\.debugPulse\(.*?\nend", spawn, re.S)
require(debug_pulse is not None and "runtime.active == false" in debug_pulse.group(0)
        and "SC.Actor.checkBridge(false)" in debug_pulse.group(0),
        "private debug cadence must fail closed before attempting actor spawn")

diagnostics = (SHARED / "SCDiagnostics.lua").read_text(encoding="utf-8")
require("tonumber(value)" in diagnostics,
        "diagnostics does not normalize Build 42 boxed timestamps")
require('state = "open"' in diagnostics and 'circuit.state = "half_open"' in diagnostics
        and "circuitBreakerResetMs" in diagnostics and "function diagnostics.retry" in diagnostics,
        "recoverable subsystem circuit breaker contract is missing")

namespace_text = (SHARED / "SCNamespace.lua").read_text(encoding="utf-8")
require("saveSchema = 2" in namespace_text
        and "local function captureInventory" in persistence
        and "complete = true" in persistence
        and "weaponParts" in persistence and "applyEquipment" in persistence
        and "inventory snapshot is incomplete" in persistence,
        "schema-2 recursive inventory/equipment transaction is missing")
require('invoke(fluid, "getSpecificFluidAmount", kind)' in persistence
        and 'invoke(sample, "getPercentage", index)' in persistence
        and 'invoke(instance, "getAmount")' not in persistence
        and 'invoke(sample, "release")' in persistence,
        "fluid persistence regressed to the non-Kahlua-exposed FluidInstance amount API")

support_source = (CLIENT / "SCSupport.lua").read_text(encoding="utf-8")
for token in ("function support.snapshot", "function support.summary",
              "function support.copySummary", "function support.retryFailures",
              "Clipboard.setClipboard", "SC.Actor.bridgeStatus"):
    require(token in support_source, f"public support report contract missing: {token}")

sandbox_options = PAYLOAD / "42" / "media" / "sandbox-options.txt"
sandbox_translation = SHARED / "Translate" / "EN" / "Sandbox.json"
require(sandbox_options.is_file() and sandbox_translation.is_file(),
        "Living Fellows sandbox options or English labels are missing")
sandbox_text = sandbox_options.read_text(encoding="utf-8")
for option in ("EncountersEnabled", "EncounterFrequency", "MaxCompanions",
               "CompanionNeedsRate", "HouseholdSpawnsEnabled", "HouseholdDailyChance",
               "MaxHouseholds", "UIOpacity"):
    require(f"option LivingFellows.{option}" in sandbox_text,
            f"sandbox option missing: {option}")
require("debugSpawnEnabled" not in sandbox_text and "Debug" not in sandbox_text,
        "release sandbox UI must not expose private debug spawning")
require("function SC.Config.refreshSandbox" in config and "runtimeOverrides" in config
        and "function SC.Config.sandboxSnapshot" in config,
        "sandbox values are not applied through a bounded runtime overlay")

ui_source = (CLIENT / "SCUI.lua").read_text(encoding="utf-8")
require('"support"' in ui_source and "function SCUIDetail:buildSupport" in ui_source
        and "configuredOpacity" in ui_source,
        "always-visible support health tab or sandbox opacity is missing")

factions_source = (CLIENT / "SCFactions.lua").read_text(encoding="utf-8")
faction_restore = re.search(r"function Factions\.restore\(document\)(.*?)\nend", factions_source, re.S)
require(faction_restore is not None
        and "factionMaxHouseholds" not in faction_restore.group(1)
        and "must never prune already-persistent households" in faction_restore.group(1),
        "lower sandbox household limits can still prune an existing save")

require((PAYLOAD / "mod.info").read_bytes() == (PAYLOAD / "42" / "mod.info").read_bytes(),
        "root and 42 metadata differ")
metadata_text = (PAYLOAD / "mod.info").read_text(encoding="utf-8")
require("require=\\ZombieBuddy" in metadata_text and "ZBVersionMin=2.3.3" in metadata_text,
        "public metadata does not declare its ZombieBuddy dependency/version floor")
build_text = (PROJECT / "scripts" / "Build-Workshop.ps1").read_text(encoding="utf-8")
metadata_version = re.search(r"(?m)^modversion=([^\r\n]+)$", metadata_text)
namespace_version = re.search(r'release\s*=\s*"([^"]+)"', namespace_text)
version_file = PROJECT / "VERSION.txt"
canonical_version = version_file.read_text(encoding="utf-8").strip() if version_file.is_file() else ""
require(re.fullmatch(r"\d+\.\d+\.\d+", canonical_version) is not None,
        "canonical VERSION.txt is missing or invalid")
require(metadata_version is not None and namespace_version is not None
        and metadata_version.group(1).strip() == namespace_version.group(1) == canonical_version,
        "VERSION.txt, mod.info, and SC.Identity.release differ")
require("$VersionFile = Join-Path $ProjectRoot 'VERSION.txt'" in build_text
        and "ValidateSet('playtest', 'public-beta', 'release')" in build_text
        and "$ReleaseVersion = (Get-Content" in build_text,
        "Workshop packaging does not use the canonical version and explicit channels")
private_builder = (PROJECT / "scripts" / "New-PrivatePlaytestPayload.ps1").read_text(
    encoding="utf-8")
require("Workshop-only loader dependency" in private_builder
        and "require=\\\\ZombieBuddy" in private_builder
        and "ZBVersionMin=2\\.3\\.3" in private_builder,
        "local-launcher playtest payload does not remove its Workshop-only loader dependency")
require((PAYLOAD / "poster.png").is_file() and (PAYLOAD / "42" / "poster.png").is_file(),
        "poster is not present in both metadata locations")
require((PAYLOAD / "LICENSE.txt").is_file() and (PAYLOAD / "README.txt").is_file(),
        "distributed payload lacks its license or concise readme")
expected_jar = PAYLOAD / "42" / "media" / "java" / "SurvivorCompanionBridge.jar"
payload_jars = list(PAYLOAD.rglob("*.jar"))
require(payload_jars == [expected_jar] and not any(PAYLOAD.rglob("*.class")),
        "payload must contain exactly the owned versioned bridge JAR and no loose classes")
native_sources = PROJECT / "bridge" / "src" / "main" / "java" / "survivorcompanion" / "bridge"
for source in ("SCNativeCompanion.java", "SCBridge.java", "SCBootstrap.java", "SCLauncher.java"):
    require((native_sources / source).is_file(), f"native bridge source missing: {source}")
native_companion = (native_sources / "SCNativeCompanion.java").read_text(encoding="utf-8")
native_bridge = (native_sources / "SCBridge.java").read_text(encoding="utf-8")
require("extends IsoPlayer" in native_companion
        and "RESERVED_NON_LOCAL_PLAYER_INDEX = 3" in native_companion
        and "public boolean isLocalPlayer()" in native_companion,
        "IsoCompanion inheritance or non-local isolation contract is missing")
require("bridgeDeathStarted" in native_companion
        and "addOnDiedListener" in native_companion
        and 'triggerEvent("OnCharacterDeath", this)' in native_companion
        and "super.OnDeath()" not in native_companion,
        "idempotent non-local corpse/death contract is missing")
require("MainThread.queueInvokeOnMainThread" in native_bridge
        and "SPAWN_HANDOFF" in native_bridge
        and "public static long requestSpawn" in native_bridge
        and "synchronous native spawn is disabled" in native_bridge,
        "IsoPlayer construction is not deferred beyond the LuaJavaInvoker frame")
require("MutedLivingCharacterEvent" in native_bridge
        and 'byName.get("OnCreateLivingCharacter")' in native_bridge
        and "callbacks.addAll(saved)" in native_bridge
        and "constructCompanion(descriptor, cell" in native_bridge,
        "native construction does not isolate OnCreateLivingCharacter callbacks")
require("public static boolean recover(SCNativeCompanion actor, IsoGridSquare square)" in native_bridge
        and "actor.getPathFindBehavior2().cancel()" in native_bridge
        and "function actorService.recover(actor, square)" in actor
        and "nativeSquareMissingAt" in runtime,
        "unloaded persistent companion recovery contract is missing")
require("setSceneCulled(false)" in native_bridge
        and "ModelManager.instance.Add(actor)" in native_bridge
        and "ModelManager.instance.Remove(actor)" in native_bridge
        and "actor.setAddedToModelManager(ModelManager.instance, true)" in native_bridge
        and "isAddedToModelManager" in native_bridge
        and "hasActiveModel" in native_bridge,
        "native actor spawn must explicitly join Build 42's model renderer")
require("ModelManager.instance.Remove(actor)" in native_bridge
        and "world, model, or square membership remains" in native_bridge,
        "native actor teardown must release Build 42 model-renderer ownership")
require("getDeclaredMethod(\"updateInternal\")" in native_companion
        and "GENERIC_CHARACTER_UPDATE.invoke(this)" in native_companion
        and "super.update()" not in native_companion
        and "ownersMatch()" in native_companion
        and "slotsMatch" in native_companion,
        "native update is not isolated from the local IsoPlayer controller")
require("public boolean isPlayerMoving()" in native_companion
        and "synchronizePlayerLocomotion()" in native_companion
        and "updateMovementRates()" in native_companion
        and "bridgePathActive" in native_companion
        and "return behavior.shouldBeMoving()" not in native_companion,
        "native companion does not drive the complete player locomotion animation state")
require('"actor_state_busy:" .. tostring(blocker)' in native
        and 'movementStateBlocker(actor)' in native
        and '"action_animation_state"' in gameplay_util,
        "movement can translate an untracked native timed-action pose")
require("setCompanionSpeechDisplayMillis" in native_companion
        and "refreshCompanionSpeech()" in native_companion
        and 'U.call(actor, "setCompanionSpeechDisplayMillis", duration)' in gameplay_util,
        "length-aware actor-owned overhead speech duration is missing")
require('invoke(actor, "pathToLocationF", x, y, z)' in native
        and 'invoke(behavior, "cancel")' in native,
        "native pathing bypasses or retains vanilla player locomotion state")
require('CharacterActionAnims[self.animation]' in native
        and 'animationEnum = true' in native
        and 'setIsAiming' in native
        and 'action == "ready_weapon"' in native
        and 'salute = "salutecasual"' in native,
        "validated player action-animation and weapon-ready contracts are missing")
require('IsoFlagType.canBeCut' in navigation
        and 'navigationBushPenalty' in navigation
        and 'navigationTreePenalty' in navigation
        and 'navigationWeaponReadyHoldMs' in navigation,
        "vegetation-aware tactical navigation contracts are missing")

for translation in (SHARED / "Translate").rglob("*.json"):
    json.loads(translation.read_text(encoding="utf-8"))
for source in lua_files:
    require(source.read_text(encoding="utf-8").startswith("-- SPDX-License-Identifier: MIT"),
            f"missing SPDX header: {source}")

print(f"CORE_STATIC_PASS lua_files={len(lua_files)} one_tick=true native_bridge=true")
