# SPDX-License-Identifier: MIT

from pathlib import Path
import re
import sys


CLIENT = Path(__file__).resolve().parents[2] / "SurvivorCompanion" / "42" / "media" / "lua" / "client"
OWNED = [
    "SCGameplayUtil.lua",
    "SCDialogue.lua",
    "SCLifeEvents.lua",
    "SCCommunity.lua",
    "SCBackground.lua",
    "SCSenses.lua",
    "SCNavigation.lua",
    "SCPositioning.lua",
    "SCCombat.lua",
    "SCMedical.lua",
    "SCEncounter.lua",
    "SCLogistics.lua",
    "SCNeeds.lua",
    "SCDowntime.lua",
    "SCPersonality.lua",
    "SCPersonalItems.lua",
    "SCRelationship.lua",
    "SCObjectives.lua",
    "SCJournal.lua",
    "SCBaseLife.lua",
    "SCBaseWork.lua",
    "SCFactions.lua",
    "SCTrade.lua",
    "SCFactionLife.lua",
    "SCFactionContracts.lua",
    "SCFactionWorld.lua",
    "SCFactionBehavior.lua",
    "SCZombieTargeting.lua",
    "SCInfectionCrisis.lua",
    "SCAutonomy.lua",
    "SCCommands.lua",
    "SCFactionRecruitment.lua",
    "SCDecision.lua",
]

REQUIRED_EXPORTS = {
    "SCDialogue.lua": ["register", "has", "choose", "say", "reset", "poolSize", "topics"],
    "SCLifeEvents.lua": ["emit", "drain", "reset"],
    "SCCommunity.lua": ["mindFor", "peekMind", "processEvents", "noteCompanionDeath",
                         "activeGrief", "finishGriefReaction", "export", "restore"],
    "SCAutonomy.lua": ["observe", "intentFor", "update", "respond", "offerSupport"],
    "SCBackground.lua": ["initialize", "applyNative", "preferredRole"],
    "SCSenses.lua": ["snapshot"],
    "SCNavigation.lua": ["request", "evaluateRoutes"],
    "SCPositioning.lua": ["formationTarget", "beginConversation", "updateConversation", "updateHoldAwareness"],
    "SCCombat.lua": ["update"],
    "SCMedical.lua": ["update"],
    "SCEncounter.lua": ["update", "onPlayerContainerOpened"],
    "SCLogistics.lua": ["prepareBuild"],
    "SCNeeds.lua": ["update", "updateRates", "assess"],
    "SCDowntime.lua": ["update", "canPerform"],
    "SCPersonality.lua": ["initialize", "adjustDecision", "overrunThresholdDelta"],
    "SCPersonalItems.lua": ["ensure", "isProtected", "restoreMarker"],
    "SCRelationship.lua": ["initialize", "observe", "respond"],
    "SCObjectives.lua": ["initialize", "update", "respondPlans"],
    "SCJournal.lua": ["build"],
    "SCBaseLife.lua": ["create", "enqueueJob", "claimJob", "setPolicy", "guardStatus",
                       "auditOperations", "export", "restore"],
    "SCBaseWork.lua": ["update", "auditMaintenance"],
    "SCFactions.lua": ["productionPulse", "debugSpawnHousehold", "noteOffense", "fulfillRequest",
                        "export", "restore", "pulse"],
    "SCTrade.lua": ["completeRequest", "catalog", "barter", "payRestitution"],
    "SCFactionLife.lua": ["initialize", "auditResources", "pulseGroup", "intentFor",
                          "updateActor", "shareRumour", "resolveCrisis", "summary", "validate"],
    "SCFactionContracts.lua": ["initialize", "talk", "accept", "fulfill", "withdraw",
                               "requestAccess", "tradePolicy", "pulseGroup", "summary",
                               "validate"],
    "SCFactionWorld.lua": ["reconcile", "relation", "pulse", "onStandingChanged",
                           "notePlayerAction", "summary", "export", "restore"],
    "SCFactionBehavior.lua": ["intentFor", "update", "reset"],
    "SCZombieTargeting.lua": ["consider", "scan", "reset"],
    "SCInfectionCrisis.lua": ["pulse", "updateActor", "export", "restore"],
    "SCCommands.lua": ["issue", "describe"],
    "SCFactionRecruitment.lua": ["initialize", "ask", "startTrial", "decide",
                                  "returnNow", "pulseGroup", "summary", "validate"],
    "SCDecision.lua": ["update"],
}

REQUIRED_COMMANDS = {
    "status", "needs", "memory", "background", "opinion", "relationship", "encourage", "praise", "plans",
    "recruit", "dismiss", "follow", "cautious_follow", "stay", "guard", "regroup", "retreat", "emote",
    "set_follow_distance", "set_scavenge", "set_work_mode", "set_move_mode", "set_combat_mode", "set_weapon_priority",
    "set_hold_fire",
    "hold_fire", "fire_at_will", "move_to", "open_door", "close_door", "check_room", "board_vehicle",
    "barricade", "remove_barricade", "dismantle", "finish_work", "exit_vehicle",
    "open_inventory", "open_health", "set_group",
    "base_duty", "set_base_role",
}


CHECKS = 0


def require(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(message)


def main() -> int:
    sources: dict[str, str] = {}
    for name in OWNED:
        path = CLIENT / name
        require(path.is_file(), f"missing gameplay source: {name}")
        text = path.read_text(encoding="utf-8")
        sources[name] = text
        require(text.startswith("-- SPDX-License-Identifier: MIT"), f"missing SPDX header: {name}")
        require("Events.OnTick" not in text and "OnTick.Add" not in text, f"independent tick loop: {name}")
        require("getZombieList" not in text, f"unbounded global zombie query: {name}")
        require(not re.search(r"\b(isClient|isServer|sendClientCommand|sendServerCommand)\s*\(", text),
                f"multiplayer API bypass: {name}")
        require("ZombieWalk" not in text and "ZombieRun" not in text and "ZombieHitReaction" not in text,
                f"zombie animation requested: {name}")

    for name in ("SCGameplayUtil.lua", "SCNativeActions.lua", "SCSpawn.lua",
                 "SCRuntime.lua", "SCScheduler.lua"):
        text = (CLIENT / name).read_text(encoding="utf-8")
        require("tonumber(value)" in text,
                f"{name} does not normalize Build 42 boxed timestamps")
    require("tonumber(getTimestampMs())" in (CLIENT / "SCPersistence.lua").read_text(encoding="utf-8"),
            "persistence timestamps are not normalized")
    require("tonumber(getTimestampMs())" in (CLIENT / "SCVehicle.lua").read_text(encoding="utf-8"),
            "vehicle timestamps are not normalized")

    for name, exports in REQUIRED_EXPORTS.items():
        text = sources[name]
        module = {"SCInfectionCrisis.lua": "Crisis", "SCFactionBehavior.lua": "Behavior",
                  "SCZombieTargeting.lua": "Targeting",
                  "SCFactionLife.lua": "Life", "SCFactionContracts.lua": "Contracts",
                  "SCFactionWorld.lua": "World", "SCFactionRecruitment.lua": "Recruitment"}.get(
            name, name.removeprefix("SC").removesuffix(".lua"))
        for export in exports:
            require(re.search(rf"function\s+{re.escape(module)}\.{re.escape(export)}\s*\(", text) is not None,
                    f"missing SC.{module}.{export}")

    command_source = sources["SCCommands.lua"]
    missing_commands = sorted(
        command
        for command in REQUIRED_COMMANDS
        if f'"{command}"' not in command_source
        and re.search(rf"^\s*{re.escape(command)}\s*=", command_source, re.MULTILINE) is None
    )
    require(not missing_commands, "missing command validation names: " + ", ".join(missing_commands))
    require("payload.scope == \"group\"" in command_source and "issueGroupAtomic" in command_source,
            "group-scoped atomic dispatch contract missing")
    require('return false, "non_groupable"' in command_source and "groupableCommands" in command_source,
            "group dispatch must reject immediate non-rollback commands")
    require("issueGroupVehicle" in command_source and "group_partial_nonrollback" in command_source
            and "issued_nonrollback" in command_source,
            "prevalidated group vehicle partial-result contract missing")

    describe_match = re.search(
        r"function\s+Commands\.describe\s*\(.*?\n(.*?)\nend\n\nlocal conversationActions",
        command_source,
        re.DOTALL,
    )
    require(describe_match is not None, "could not inspect Commands.describe")
    describe_body = describe_match.group(1)
    require("stateFor(" not in describe_body and "writeStable(" not in describe_body and "move(" not in describe_body,
            "Commands.describe must remain mutation-free")
    for field in [
        "id", "name", "actor", "health", "hunger", "thirst", "distance", "order", "activity", "intent", "combatMode",
        "holdFire", "followDistance", "scavenge", "workMode", "group", "knox", "status", "alive", "available",
        "wounds", "supplies", "ammunition", "personality", "trust", "bond", "morale", "stress",
        "relationshipTier", "mood", "currentNeed", "recentMemory", "timeTogetherHours",
        "personalityProfile", "objectives", "possessions", "journal",
        "stressResponse", "joyResponse", "boredom", "topThoughts", "currentExpectation",
        "activeEpisode", "inspiration", "pendingRequest",
    ]:
        require(re.search(rf"\b{re.escape(field)}\s*=", describe_body) is not None,
                f"Commands.describe missing field: {field}")

    require("perceptionSquareBudget" in sources["SCSenses.lua"], "perception budget not enforced")
    require("outerSampled" in sources["SCSenses.lua"], "rotating outer perception coverage missing")
    require("navigationNodeBudget" in sources["SCNavigation.lua"], "navigation node budget not enforced")
    require("recovery_exhausted:" in sources["SCNavigation.lua"]
            and "navigationTerminalRetryMs" in sources["SCNavigation.lua"],
            "bounded retryable terminal navigation episode missing")
    require("navigationBreadcrumbLimit" in sources["SCNavigation.lua"]
            and "boundedOutdoorPath" in sources["SCNavigation.lua"]
            and "function Navigation.retreatTarget" in sources["SCNavigation.lua"],
            "bounded entry-route and exterior-egress memory missing")
    require("tacticalStrafe" in sources["SCNavigation.lua"]
            and "checking_blind_corner" in sources["SCNavigation.lua"]
            and "holding_stair_spacing" in sources["SCNavigation.lua"],
            "tactical blind-corner or stair-spacing navigation missing")
    require("checking_room_entry_" in sources["SCNavigation.lua"]
            and 'phase == 0 and "left" or "right"' in sources["SCNavigation.lua"]
            and "navigationRoomEntryObserveMs" in sources["SCNavigation.lua"],
            "two-sided room-entry corner checking missing")
    require("chooseFollowRoute" in sources["SCNavigation.lua"]
            and "navigationAlternativeRoutes" in sources["SCNavigation.lua"]
            and "routeDanger" in sources["SCNavigation.lua"]
            and "routeCrowding" in sources["SCNavigation.lua"]
            and "routeTraversalCost" in sources["SCNavigation.lua"],
            "bounded multi-route follow evaluation missing")
    require("stealthAvoidanceRequested" in sources["SCNavigation.lua"]
            and "stealthThreatPenalty" in sources["SCNavigation.lua"]
            and "navigationStealthVisibleRadius" in sources["SCNavigation.lua"]
            and "snapshot.stealthThreats" in sources["SCNavigation.lua"]
            and 'commands.weaponPriority == "quiet"' in sources["SCNavigation.lua"]
            and 'commands.combatDoctrine == "stealth"' in sources["SCNavigation.lua"],
            "quiet/stealth zombie-buffered routing policy missing")
    positioning_source = sources["SCPositioning.lua"]
    native_actions_source = (CLIENT / "SCNativeActions.lua").read_text(encoding="utf-8")
    require("formationOffsets" in positioning_source and "followerSlot" in positioning_source
            and "leaderHeading" in positioning_source,
            "stable direction-relative formation contract missing")
    require("formationArrivalDistance" in positioning_source
            and "formationReleaseDistance" in positioning_source
            and "holdingFormation" in positioning_source,
            "formation arrival hysteresis contract missing")
    require("positioningReservationMs" in positioning_source
            and "navigationStepReservationMs" in sources["SCNavigation.lua"]
            and "yielding_right_of_way" in sources["SCNavigation.lua"]
            and "right_of_way_yield" in sources["SCNavigation.lua"],
            "personal-space reservation and right-of-way contract missing")
    require("conversationMinimumDistance" in positioning_source
            and "conversationMaximumDistance" in positioning_source
            and "conversation_interrupted_by_danger" in positioning_source,
            "bounded interruptible conversation zone missing")
    require('"conversation_pose"' in positioning_source
            and '"face_conversation"' in positioning_source
            and 'candidate.kind == "conversation"' in sources["SCDecision.lua"],
            "conversation movement arbitration or partner-facing contract missing")
    require("stressPosture" in positioning_source and 'return "sneak", "guarded"' in positioning_source
            and "conversationPose" in native_actions_source,
            "human stress locomotion or atomic conversation pose missing")
    require("formation_rear_scan" in positioning_source and 'action = "rear_scan"' in positioning_source
            and 'action = "face_formation"' in positioning_source
            and 'action == "rear_scan"' in native_actions_source,
            "periodic rear awareness and formation-facing restoration missing")
    bootstrap_source = (CLIENT / "SCBootstrap.lua").read_text(encoding="utf-8")
    require('require "SCPositioning"' in bootstrap_source
            and '"Positioning"' in bootstrap_source,
            "positioning module is not load-ordered and fail-fast validated")
    require("not objectOpen(entry.object)" in sources["SCNavigation.lua"]
            and "window_open_failed" in sources["SCNavigation.lua"]
            and "window_smash_failed" in sources["SCNavigation.lua"]
            and "glass_removal_failed" in sources["SCNavigation.lua"],
            "native-authoritative door/window postconditions missing")
    require("scavengeSquareBudget" in sources["SCEncounter.lua"], "scavenge budget not enforced")
    require("wasPlayerOpened" in sources["SCEncounter.lua"]
            and "campStorageSquareBudget" in sources["SCEncounter.lua"]
            and "takePlayerSupply" in sources["SCEncounter.lua"],
            "visited camp-storage reservation contract missing")
    require("needsRateMultiplier" in sources["SCNeeds.lua"]
            and '"HUNGER"' in sources["SCNeeds.lua"]
            and '"THIRST"' in sources["SCNeeds.lua"]
            and "delta * multiplier" in sources["SCNeeds.lua"],
            "half-rate native hunger/thirst delta compensation missing")
    require("isSafeFood" in sources["SCNeeds.lua"]
            and "isSafeWaterItem" in sources["SCNeeds.lua"]
            and "needsWaterSquareBudget" in sources["SCNeeds.lua"],
            "bounded safe autonomous food/water selection missing")
    require("prepareBuild" in sources["SCLogistics.lua"]
            and "build_hammer" in sources["SCLogistics.lua"]
            and "build_plank" in sources["SCLogistics.lua"]
            and "build_nails" in sources["SCLogistics.lua"],
            "camp build-supply logistics missing")
    require(all(role in sources["SCLogistics.lua"] for role in
                ("generalist", "guard", "builder", "quartermaster", "medic"))
            and "function Logistics.itemNeedScore" in sources["SCLogistics.lua"]
            and "function Logistics.selectSurplus" in sources["SCLogistics.lua"],
            "role-aware loadout targets or surplus selection missing")
    require('getCapacityWeight' in sources["SCGameplayUtil.lua"]
            and 'getEffectiveCapacity' in sources["SCGameplayUtil.lua"]
            and "function U.dropItem" in sources["SCGameplayUtil.lua"]
            and 'U.addItem(source, item)' in sources["SCGameplayUtil.lua"],
            "vanilla-aligned load measurement or transactional ground-drop rollback missing")
    require("function U.transferItemVerified" in sources["SCGameplayUtil.lua"]
            and all(phase in sources["SCEncounter.lua"] for phase in
                    ('\"select\"', '\"approach\"', '\"settle\"', '\"animate\"',
                     '\"commit\"', '\"verify\"', '\"complete\"'))
            and "scavengeMemoryLimit" in sources["SCEncounter.lua"]
            and "preferredLootDestination" in sources["SCLogistics.lua"]
            and "executeTransaction" in sources["SCLogistics.lua"],
            "verified phased scavenging and post-loot execution contract missing")
    require('"food"' in sources["SCLogistics.lua"] and '"water"' in sources["SCLogistics.lua"]
            and '"clothing"' in sources["SCLogistics.lua"] and '"weapon"' in sources["SCLogistics.lua"]
            and '"construction"' in sources["SCLogistics.lua"] and '"crafting"' in sources["SCLogistics.lua"],
            "scavenging categories do not cover survival gear and materials")
    require("squareStaticMovingObjects" in sources["SCEncounter.lua"]
            and "isZombieCorpse" in sources["SCEncounter.lua"]
            and "safeForCorpseLoot" in sources["SCEncounter.lua"]
            and 'sourceKind = corpseContainers[container] and "zombie_corpse"' in sources["SCEncounter.lua"],
            "bounded combat-gated zombie-corpse looting missing")
    require('candidate.kind == "logistics"' in sources["SCDecision.lua"]
            and 'SC.Logistics.update(actor, player, rootRuntime)' in sources["SCDecision.lua"],
            "load management is not integrated into decision arbitration")
    require("SC.Autonomy.intentFor" in sources["SCDecision.lua"]
            and 'callSubsystem("autonomy"' in sources["SCDecision.lua"]
            and 'safeSubsystem("autonomy-observe"' in sources["SCDecision.lua"],
            "bounded living-survivor autonomy is not integrated into decision arbitration")
    require('response == "shutdown"' in sources["SCAutonomy.lua"]
            and 'action = "sit_ground"' in sources["SCAutonomy.lua"]
            and "mindShutdownGameHours" in sources["SCAutonomy.lua"]
            and "survival_interrupt" in sources["SCAutonomy.lua"],
            "depressive shutdown lacks a bounded ground-sitting survival contract")
    require("safeSubsystem" in sources["SCDecision.lua"], "decision subsystem circuit breakers not used")
    require("observeRelationship" in sources["SCDecision.lua"]
            and 'safeSubsystem("relationship"' in sources["SCDecision.lua"],
            "relationship observation is not integrated into the decision cadence")
    relationship_source = sources["SCRelationship.lua"]
    require("shared_escape" in relationship_source and "rescued_player" in relationship_source
            and "timeTogetherMs" in relationship_source and "lastEncouragedAt" in relationship_source,
            "relationship history, shared-event, or anti-spam contract missing")
    require("validEmotes" in relationship_source and "function Relationship.isEmote" in relationship_source,
            "validated Build 42 human emote contract missing")
    require("publicBackground" in relationship_source and "revealedBackground" in relationship_source,
            "Commands.describe relationship projection may leak unrevealed background")
    require("result.objectives = stableSummaryCopy(result.journal.objective" in command_source
            and "result.journal.keepsake" in command_source,
            "command summary does not replace private objective/keepsake state with Journal projections")
    combined = "\n".join(sources.values())
    for removed_api in ["isCanSee", "getInfectionLevel", "getHunger", "getThirst", "getEndurance", "isWearing"]:
        require(re.search(rf"\b{re.escape(removed_api)}\s*\(", combined) is None,
                f"removed or invalid B42 API used: {removed_api}")
    require("LosUtil" in sources["SCGameplayUtil.lua"] and "lineClear" in sources["SCGameplayUtil.lua"],
            "B42 square LOS raycast missing")
    require("getApparentInfectionLevel" in sources["SCMedical.lua"], "B42 apparent infection API missing")
    require("CharacterStat" in sources["SCGameplayUtil.lua"] and '"HUNGER"' in sources["SCEncounter.lua"]
            and '"THIRST"' in sources["SCEncounter.lua"] and '"ENDURANCE"' in sources["SCCombat.lua"],
            "B42 CharacterStat getters missing")
    require("isEquippedClothing" in sources["SCMedical.lua"] and "getWornItems" in sources["SCMedical.lua"],
            "validated B42 worn-clothing checks missing")
    require("removeWornItem" in sources["SCMedical.lua"] and "setWornItem" in sources["SCMedical.lua"]
            and "expendableWornTerms" in sources["SCMedical.lua"]
            and "isRecruitedTeam" in sources["SCMedical.lua"],
            "transactional conservative worn-clothing tear contract missing")
    require("sameFloor" in sources["SCCombat.lua"], "same-floor combat safety gates missing")
    faction_source = sources["SCFactions.lua"]
    trade_source = sources["SCTrade.lua"]
    faction_behavior = sources["SCFactionBehavior.lua"]
    faction_world = sources["SCFactionWorld.lua"]
    require("function U.isSafeSpawnSquare" in sources["SCGameplayUtil.lua"]
            and 'U().isSafeSpawnSquare(square)' in faction_source
            and "reservedSpawnPositions" in faction_source
            and "rollbackGroupCreation" in faction_source,
            "faction residents do not share the native strict spawn-square and reservation contract")
    require("barricaded_household" in faction_source
            and "factionMaxHouseholds" in faction_source
            and "factionMinHouseDistance" in faction_source,
            "bounded generic household faction production contract missing")
    require("member.spawnQueued = false" in faction_source
            and "SC.Persistence.isPending(member.actorId)" in faction_source
            and "Only hibernated snapshots live" in faction_source,
            "faction streaming/persistence duplicate-prevention contract missing")
    require("rewardReserved" in faction_source and "reservedRewards" in trade_source,
            "request rewards are not excluded from ordinary barter stock")
    require("transaction_rollback_failed" in trade_source
            and "containerBelongsTo" in trade_source
            and "protected_trade_item" in trade_source,
            "atomic ownership-validated faction transaction contract missing")
    require("allowHostile = true" in trade_source
            and "restitutionRequired" in faction_source
            and 'kind == "theft" or kind == "damage"' in faction_source,
            "cooldown and double-value restitution path missing")
    require("factionPursuitLeash" in faction_behavior
            and "friendlyInLine" in faction_behavior
            and "emergency_seal" in faction_behavior,
            "territorial combat leash, friendly-fire, or emergency seal policy missing")
    require("MAX_RELATIONS" in faction_world and "MAX_NEWS" in faction_world
            and "nextEventHour" in faction_world and "word_travels:" in faction_world,
            "bounded persistent faction-world relations or consequence propagation missing")
    persistence_source = (CLIENT / "SCPersistence.lua").read_text(encoding="utf-8")
    require('{ field = "factionWorld", owner = SC.FactionWorld' in persistence_source
            and "pcall(definition.owner.restore" in persistence_source,
            "faction-world state is not part of the transactional save document")
    require("function Combat.assessOverrun" in sources["SCCombat.lua"]
            and "combatOverrunHoldMs" in sources["SCCombat.lua"]
            and "occupiedThreatSectors" in sources["SCSenses.lua"],
            "directional overrun assessment and retreat hysteresis missing")
    require("combatAllySupportRadius" in sources["SCCombat.lua"]
            and "combatAllySupportMax" in sources["SCCombat.lua"]
            and "not downed" in sources["SCCombat.lua"],
            "fight-or-flight does not account for nearby healthy teammate support")
    require('function Encounter.onPlayerContainerOpened' in sources["SCEncounter.lua"],
            "player-container-opened production adapter missing")
    require('callUI("openInventory"' in command_source and 'callUI("openHealth"' in command_source,
            "dedicated inventory/health UI adapters missing")
    decision_source = sources["SCDecision.lua"]
    require("switchToStay" in decision_source and "stay_transition_rejected" in decision_source,
            "automatic stay transition result propagation missing")
    require(decision_source.count("utility.stop(actor)")
            == decision_source.count("if not utility.stop(actor)"),
            "SCDecision contains an unchecked utility.stop result")
    require("dead_stop_rejected" in decision_source and "idle_stop_rejected" in decision_source,
            "SCDecision stop rejection reasons missing")
    require("selectedFailure" in decision_source, "selected Decision failure reason may be masked by fallbacks")
    require('candidate.kind == "needs"' in decision_source
            and 'action = "hand_signal"' in decision_source
            and "dangerSignalImmediateRadius" in decision_source,
            "needs arbitration or context-aware silent danger signal missing")
    downtime_source = sources["SCDowntime.lua"]
    require("function Downtime.considerCurtain" in downtime_source
            and 'config("curtainSearchRadius") or 5' in downtime_source
            and "squaresInspected > squareBudget" in downtime_source
            and "inspected > objectBudget" in downtime_source
            and 'environmentalTask = "curtain"' in downtime_source
            and 'commands.combatDoctrine == "stealth"' in downtime_source,
            "bounded pathing stealth-aware curtain decision missing")
    require('snapshot.indoors == true' in decision_source
            and 'SC.Downtime.cancel(actor, "decision_preempted")' in decision_source
            and 'orderAllowsIdle(commands, actor, player, snapshot)' in downtime_source
            and 'SC.NativeActions.cancelVisual' in downtime_source,
            "follow downtime lacks indoor gating or atomic animation preemption")
    for module in ("SCPersonality.lua", "SCPersonalItems.lua", "SCObjectives.lua", "SCJournal.lua"):
        require("Events." not in sources[module], f"character-depth module owns a global event hook: {module}")
    require('config("objectiveAuditIntervalMs") or 5000' in sources["SCPersonalItems.lua"]
            and "observations[actor] = current + interval" in sources["SCPersonalItems.lua"],
            "keepsake observation is not bounded to the objective audit cadence")
    require("SC.Actor.setMovement" not in "\n".join(sources.values()),
            "gameplay must resolve the movement bridge dynamically through the helper")

    print(
        f"Static gameplay contracts PASS: {CHECKS} assertions, "
        f"{len(OWNED)} sources, {len(REQUIRED_COMMANDS)} commands"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
