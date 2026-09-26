# SPDX-License-Identifier: MIT

from pathlib import Path
import re
import sys


PROJECT = Path(__file__).resolve().parents[2]
CLIENT = PROJECT / "SurvivorCompanion" / "42" / "media" / "lua" / "client"
SHARED = CLIENT.parent / "shared"
OWNED = [
    "SCGameplayUtil.lua",
    "SCVitalsTrace.lua",
    "SCBaseObjectRef.lua",
    "SCTopology.lua",
    "SCPathSearch.lua",
    "SCNavTraffic.lua",
    "SCNavTraversal.lua",
    "SCWorkRoutes.lua",
    "SCDialogue.lua",
    "SCAllegiance.lua",
    "SCLifeEvents.lua",
    "SCCommunity.lua",
    "SCDiaryText.lua",
    "SCDiaryCatalog.lua",
    "SCDiaryItem.lua",
    "SCDiary.lua",
    "SCBackground.lua",
    "SCThreatSet.lua",
    "SCPerceptionScan.lua",
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
    "SCTales.lua",
    "SCBanter.lua",
    "SCGestures.lua",
    "SCObjectives.lua",
    "SCJournal.lua",
    "SCBaseLife.lua",
    "SCWorkTransport.lua",
    "SCGatherWork.lua",
    "SCFarmWork.lua",
    "SCQuirks.lua",
    "SCBaseWork.lua",
    "SCProduction.lua",
    "SCFactions.lua",
    "SCTrade.lua",
    "SCFactionLife.lua",
    "SCFactionContracts.lua",
    "SCFactionWorld.lua",
    "SCFactionBehavior.lua",
    "SCZombieTargeting.lua",
    "SCZombieAttack.lua",
    "SCInfectionCrisis.lua",
    "SCAutonomy.lua",
    "SCCommands.lua",
    "SCFactionRecruitment.lua",
    "SCDecision.lua",
]

REQUIRED_EXPORTS = {
    "SCBaseObjectRef.lua": ["describe", "copy", "normalize", "resolve", "identity", "signature"],
    "SCPathSearch.lua": ["new", "resume", "run", "classifyFailure"],
    "SCNavTraffic.lua": ["observeGroupPassage", "groupPassageActive",
                         "ensureGroupPassage", "markActorPassage", "reserveChoke",
                         "releaseChoke", "reserveStep", "releaseStep", "reset"],
    "SCNavTraversal.lua": ["reserve", "release", "interactDoor", "handleDoor", "handleWindow",
                            "handleWindowFrame", "doorGeometry", "occupiesDoorway",
                            "alignDoorApproach", "alignWindowApproach", "handleFence",
                            "closeOwnedDoors", "reset"],
    "SCAllegiance.lua": ["isHostile", "relationship", "areAllies", "isProtected"],
    "SCThreatSet.lua": ["threatPreferred", "proximityPreferred", "isImmediate",
                        "new", "add", "finish"],
    "SCPerceptionScan.lua": ["nativeCandidates", "nextOffsets", "newJob", "invalid", "reset"],
    "SCDialogue.lua": ["register", "has", "choose", "say", "sayLastWords",
                       "monitorMortality", "reset", "poolSize", "topics"],
    "SCLifeEvents.lua": ["emit", "drain", "reset"],
    "SCCommunity.lua": ["mindFor", "peekMind", "processEvents", "noteCompanionDeath",
                         "activeGrief", "finishGriefReaction", "export", "restore"],
    "SCDiaryText.lua": ["validToken", "prepareCatalog", "validateCatalog", "generate"],
    "SCDiaryItem.lua": ["read", "readPayload", "initialize", "append", "parseEntry",
                        "displayName", "findWritingImplement"],
    "SCDiary.lua": ["clock", "pulse", "noteRecruited", "noteBandage", "noteSharedEscape", "noteInteriorState",
                    "noteAuthorDeath", "noteCompanionDeath", "noteCrisisKnowledge",
                    "noteCrisisOutcome", "writeActivity", "commitWrite", "abandonWrite",
                    "authorAlive", "contentRevision", "export", "restore", "reset"],
    "SCAutonomy.lua": ["observe", "intentFor", "update", "respond", "offerSupport"],
    "SCBackground.lua": ["initialize", "applyNative", "preferredRole"],
    "SCSenses.lua": ["snapshot"],
    "SCNavigation.lua": ["request", "evaluateRoutes", "groupPassageActive"],
    "SCWorkRoutes.lua": ["stationaryFastRouteRequested", "key", "lookup", "record",
                         "invalidate", "snapshot", "reset"],
    "SCPositioning.lua": ["formationTarget", "cqbRole", "beginConversation", "updateConversation", "updateHoldAwareness"],
    "SCCombat.lua": ["update", "assessOverrun"],
    "SCMedical.lua": ["update"],
    "SCEncounter.lua": ["update", "onPlayerContainerOpened"],
    "SCLogistics.lua": ["prepareBuild"],
    "SCNeeds.lua": ["update", "updateRates", "assess", "narrate"],
    "SCDowntime.lua": ["update", "canPerform"],
    "SCPersonality.lua": ["initialize", "adjustDecision", "overrunThresholdDelta"],
    "SCPersonalItems.lua": ["ensure", "isProtected", "restoreMarker"],
    "SCRelationship.lua": ["initialize", "observe", "respond", "score",
                             "overrunThresholdDelta", "pushThresholdDelta"],
    "SCBanter.lua": ["update", "combatPulse", "grabbedPulse", "overrunRefusal",
                      "interiorPulse", "reset"],
    "SCTales.lua": ["noteKill", "noteCloseCall", "update", "normalize", "reset"],
    "SCGestures.lua": ["update", "noteStoodUp", "workoutActivity", "requestIdleWorkout", "reset"],
    "SCObjectives.lua": ["initialize", "update", "respondPlans", "assignableKinds", "assign"],
    "SCVitalsTrace.lua": ["report", "snapshot", "reset"],
    "SCJournal.lua": ["build"],
    "SCBaseLife.lua": ["create", "describeObject", "resolveObject", "removeZone", "removeStorage", "setStorageCategory",
                       "setReserve", "setMaintenanceTargetEnabled", "removeMaintenanceTarget",
                       "enqueueJob", "claimJob", "cancelJob", "retryJob", "setPolicy",
                       "guardStatus", "auditOperations", "createGatherOrder", "pauseGatherOrder",
                       "resumeGatherOrder", "retryGatherOrder", "cancelGatherOrder",
                       "changeGatherDestination", "addGatherWorker", "releaseGatherCargo",
                       "accountGatherDelivery", "extendGatherOrder",
                       "registerProductionOperation", "createProductionOrder",
                       "pauseProductionOrder", "resumeProductionOrder", "retryProductionOrder",
                       "cancelProductionOrder", "addProductionWorker", "blockProductionOrder",
                       "reopenProductionOrder", "recordProductionProgress",
                       "completeProductionOrder", "noteProductionCounter",
                       "noteProductionGrave", "forgetProductionGrave", "linkProductionHaul",
                       "productionOrder", "productionOrders", "productionCounters",
                       "dutyResidentIds",
                       "export", "restore"],
    "SCProduction.lua": ["register", "descriptor", "operations", "update", "workerPhase",
                         "forgetOrder", "retryOrder", "cancelActor", "diagnostics", "reset"],
    "SCWorkTransport.lua": ["reserve", "collect", "deposit", "reconcile",
                            "recoverPending", "transferVerified", "isCargoProtected",
                            "retryOrder", "retryCleanup", "releaseCarriedCargo", "prepareActorRetirement",
                            "diagnostics", "reset"],
    "SCGatherWork.lua": ["validateZone", "nextCandidate", "update", "retryOrder",
                         "diagnostics", "reset"],
    "SCFarmWork.lua": ["audit", "jobModifier", "update", "cancelActor", "reset", "summary"],
    "SCQuirks.lua": ["normalize", "describe", "acceptsLoot", "itemDesireBonus",
                       "onVerifiedLoot", "recognitionCandidate", "speakRecognition",
                       "observeRecognitionResolution", "ritualIntent", "updateRitual",
                       "interrupt", "reset"],
    "SCBaseWork.lua": ["update", "auditMaintenance"],
    "SCFactions.lua": ["productionPulse", "banditProductionPulse", "debugSpawnHousehold",
                        "debugSpawnBanditCamp", "hostileTargetFor", "isHostileBetween",
                        "noteOffense", "fulfillRequest", "describeLocation",
                        "resolveQuestContainer", "export", "restore", "pulse"],
    "SCTrade.lua": ["completeRequest", "catalog", "barter", "payRestitution",
                    "prepareQuestRewards", "completeQuest", "questItemProgress"],
    "SCFactionLife.lua": ["initialize", "auditResources", "pulseGroup", "intentFor",
                          "updateActor", "shareRumour", "resolveCrisis", "summary", "validate"],
    "SCFactionContracts.lua": ["initialize", "talk", "accept", "chooseReward", "fulfill", "declineOffer", "withdraw",
                               "requestAccess", "tradePolicy", "pulseGroup", "summary",
                               "validate"],
    "SCFactionWorld.lua": ["reconcile", "relation", "pulse", "onStandingChanged",
                           "notePlayerAction", "summary", "export", "restore"],
    "SCFactionBehavior.lua": ["intentFor", "humanThreatFor", "updateHumanCombat",
                               "update", "reset"],
    "SCZombieTargeting.lua": ["consider", "scan", "reset"],
    "SCZombieAttack.lua": ["resolve", "isGrabbed", "reset"],
    "SCInfectionCrisis.lua": ["pulse", "updateActor", "export", "restore"],
    "SCCommands.lua": ["issue", "describe"],
    "SCFactionRecruitment.lua": ["initialize", "ask", "startTrial", "decide",
                                  "returnNow", "pulseGroup", "summary", "validate"],
    "SCDecision.lua": ["update"],
}

REQUIRED_COMMANDS = {
    "status", "needs", "memory", "background", "opinion", "relationship", "encourage", "praise", "plans",
    "recruit", "dismiss", "follow", "cautious_follow", "stay", "guard", "regroup", "retreat", "emote",
    "set_follow_distance", "set_scavenge", "set_work_mode", "set_move_mode", "set_combat_doctrine", "set_weapon_priority",
    "set_hold_fire",
    "hold_fire", "fire_at_will", "move_to", "open_door", "close_door", "finish_interaction", "check_room", "finish_room_check", "board_vehicle",
    "designate_target", "avoid_target", "assign_objective",
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
        if name == "SCPerceptionScan.lua":
            # The only permitted global zombie-list read is the explicit rolling
            # candidate discovery. Keep the old ban everywhere else, and make
            # its cursor, unit cap and elapsed deadline part of the source gate.
            require(text.count('"getZombieList"') == 1
                    and "function Scan.nativeCandidates" in text
                    and "sharedNative" in text
                    and "state.nativeScanCursor" in text
                    and "processed < limit and shared.cursor < shared.cycleCount" in text
                    and "math.min(math.max(1, shared.cycleCount), 128" in text
                    and "shared.liveCount = count" in text
                    and "processed >= 4 and clock() >= deadline" in text
                    and "SC.NativeList.get(list, index)" in text
                    and "perceptionNativeRosterQueryPerSlice" in text
                    and "state.nativeRosterCursor" in text
                    and "math.floor(zz or 0) == math.floor(z or 0)" in text
                    and "distanceSq <= radiusSq" in text
                    and "math.min(32" in text,
                    "native zombie query is not cursor/deadline bounded")
        else:
            require("getZombieList" not in text, f"unbounded global zombie query: {name}")
        require(not re.search(r"\b(isClient|isServer|sendClientCommand|sendServerCommand)\s*\(", text),
                f"multiplayer API bypass: {name}")
        require("ZombieWalk" not in text and "ZombieRun" not in text and "ZombieHitReaction" not in text,
                f"zombie animation requested: {name}")

    gameplay_util = sources["SCGameplayUtil.lua"]
    config_source = (SHARED / "SCConfig.lua").read_text(encoding="utf-8")
    gameplay_runner = (PROJECT / "tests" / "gameplay" / "run_gameplay_tests.ps1").read_text(
        encoding="utf-8")
    require('pcall(require, "SCConfig")' in gameplay_util
            and "local fallbackValues" not in gameplay_util,
            "gameplay utility does not exclusively use the canonical SCConfig service")
    require(gameplay_runner.index("SCConfig.lua") < gameplay_runner.index("SCGameplayUtil.lua"),
            "gameplay harness must load canonical SCConfig before SCGameplayUtil")
    require("perceptionScanRebaseDistance = 2.0" in config_source
            and "combatTargetActionHardCap = 8" in config_source
            and "workGatherObjectsPerSlice = 32" in config_source
            and "workGatherCandidateMaxAttempts = 3" in config_source
            and "workRecoveryMaxAttempts = 8" in config_source,
            "responsiveness controls are missing from canonical SCConfig")

    transport_source = sources["SCWorkTransport.lua"]
    gather_source = sources["SCGatherWork.lua"]
    base_life_source = sources["SCBaseLife.lua"]
    base_work_source = sources["SCBaseWork.lua"]
    require('logs = "Base.Log"' in base_life_source
            and 'planks = "Base.Plank"' in base_life_source,
            "gathering must use exact installed Build 42 item types")
    require('job.type == "gather_materials"' in base_work_source
            and "SC.GatherWork.update(actor, state, job)" in base_work_source,
            "base dispatcher does not route gathering through the production worker")
    production_source = sources["SCProduction.lua"]
    require('job.type == "production"' in base_work_source
            and "SC.Production.update(actor, state, job, runtime)" in base_work_source,
            "base dispatcher does not route production orders")
    for kind in ("chop_tree", "saw_logs", "dig_grave", "bury_body", "fill_grave",
                 "grab_body", "drop_body", "burn_body"):
        require(f'action = "{kind}"' in production_source,
                f"production does not dispatch the verified native {kind} action")
    require("productionScanSquaresPerSlice" in production_source
            and "productionChopMaxMs" in production_source
            and "productionActionMaxMs" in production_source
            and "productionCandidateMaxAttempts" in production_source,
            "production scans, actions and retries must stay bounded")
    require("emulateWorkEvent" in production_source and "chopSession.native" in production_source,
            "chop fallback must only emulate vanilla's event after native events are disproved")
    require("transientRejection(reason)" in production_source
            and '"production_pacing"' in production_source,
            "pacing and busy rejections must wait instead of exhausting work targets")
    require("workSquareAdmitted(square, requestIntent)" in sources["SCNavigation.lua"]
            and "admitsWork" in sources["SCNavigation.lua"]
            and "SC.BaseLife.admitsWork" in sources["SCWorkRoutes.lua"]
            and "workReach = lumberOrder(order)" in gather_source
            and "SC.BaseLife.jobAllowsWorkReach(job)" in base_work_source
            and "productionLumberReach" in base_life_source
            and "lumberNight()" in production_source,
            "lumber work may cross only the bounded reach band around the camp")
    require(re.search(r"[^\x00-\x7f]", production_source) is None,
            "production dialogue and source must stay ASCII")
    require("verifiedContainerOwner" in transport_source
            and 'invoke(container, "hasRoomFor", actor, item)' in transport_source
            and "captureDetachedItem" in transport_source
            and "restoreDetachedItem" in transport_source,
            "work transport lacks exact ownership, capacity, or recovery boundaries")
    require("workGatherSquaresPerSlice" in gather_source
            and "workGatherObjectsPerSlice" in gather_source
            and "workCampOnly = true" in gather_source
            and 'return nil, "gather_area_scan_incomplete", false' in gather_source,
            "gathering scan must be resumable and preserve incomplete evidence")
    require("requestIntent.workCampOnly ~= true" in sources["SCNavigation.lua"]
            and "outside_admitted_area" in sources["SCNavigation.lua"],
            "ordinary camp work must not fall back to an unrestricted native route")

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
                  "SCNavTraffic.lua": "Traffic",
                  "SCNavTraversal.lua": "Traversal",
                  "SCWorkRoutes.lua": "Routes",
                  "SCPerceptionScan.lua": "Scan",
                  "SCWorkTransport.lua": "Transport", "SCGatherWork.lua": "Gather",
                  "SCFactionLife.lua": "Life", "SCFactionContracts.lua": "Contracts",
                  "SCFactionWorld.lua": "World", "SCFactionRecruitment.lua": "Recruitment",
                  "SCDiaryText.lua": "Text", "SCDiaryItem.lua": "Item",
                  "SCVitalsTrace.lua": "Trace"}.get(
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
    require("navigationPathSearchHardMs" in sources["SCNavigation.lua"]
            and "progressAt" in sources["SCNavigation.lua"]
            and "path_search_stalled:" in sources["SCNavigation.lua"],
            "incremental path search lacks progress-leased stall recovery and a hard bound")
    require("recoveryWaypoint" in sources["SCNavigation.lua"]
            and 'actorState == "bumped_state"' in sources["SCNavigation.lua"]
            and "cancelled_stale_bump" in sources["SCNavigation.lua"],
            "BumpedState does not own a stable local clearance waypoint")
    require("string.match(rawLabel" in gameplay_util
            and gameplay_util.index("string.match(rawLabel")
                < gameplay_util.index('for _, methodName in ipairs({ "getObjectName"')
            and gameplay_util.index('return "bumped_state", current')
                < gameplay_util.index('U.call(actor, "isBlockMovement")'),
            "opaque B42 state labels are probed unsafely or BumpedState is hidden by movement_locked")
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
    require('differentFloor(sourceSquare, goalSquare)' in sources["SCNavigation.lua"]
            and 'requestIntent.multiLevelPath = true' in sources["SCNavigation.lua"]
            and '"navigationMultiLevelLeaseMs"' in sources["SCNavigation.lua"],
            "cross-floor destinations do not use a native progress-leased 3D path")
    require("checking_room_entry_" in sources["SCNavigation.lua"]
            and 'phase == 0 and "left" or "right"' in sources["SCNavigation.lua"]
            and "navigationRoomEntryObserveMs" in sources["SCNavigation.lua"],
            "two-sided room-entry corner checking missing")
    require("navigationOwnershipPermission" in sources["SCNavigation.lua"]
            and "movementPermission" in sources["SCNavigation.lua"]
            and sources["SCNavigation.lua"].index(
                "local permitted, permissionReason = navigationOwnershipPermission(actor, intent)",
                sources["SCNavigation.lua"].index("function Navigation.request("))
                < sources["SCNavigation.lua"].index(
                    "local now = utility.nowMs()",
                    sources["SCNavigation.lua"].index("function Navigation.request(")),
            "navigation must reject a competing owner before route state mutates")
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
    locomotion_source = (CLIENT / "SCLocomotion.lua").read_text(encoding="utf-8")
    require("formationOffsets" in positioning_source and "followerSlot" in positioning_source
            and "leaderHeading" in positioning_source,
            "stable direction-relative formation contract missing")
    require("formationArrivalDistance" in positioning_source
            and "formationReleaseDistance" in positioning_source
            and "holdingFormation" in positioning_source,
            "formation arrival hysteresis contract missing")
    require("positioningReservationMs" in positioning_source
            and "navigationStepReservationMs" in sources["SCNavTraffic.lua"]
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
    require('action = "rear_guard_watch"' in positioning_source
            and 'action == "rear_guard_watch"' in native_actions_source
            and "rear_guard_watch = true" in locomotion_source,
            "rear guard watch is not wired through positioning, native facing, and locomotion")
    bootstrap_source = (CLIENT / "SCBootstrap.lua").read_text(encoding="utf-8")
    require('require "SCPositioning"' in bootstrap_source
            and '"Positioning"' in bootstrap_source,
            "positioning module is not load-ordered and fail-fast validated")
    traversal_source = sources["SCNavTraversal.lua"]
    require('not invoke(context, "objectOpen", entry.object)' in traversal_source
            and 'action .. "_verification_timeout"' in traversal_source
            and 'invoke(context, "windowSmashed", window)' in traversal_source
            and 'invoke(context, "windowGlassRemoved", window)' in traversal_source
            and 'utility.call(actor, "openWindow", window)' not in traversal_source
            and '"ToggleWindow"' not in traversal_source,
            "native-authoritative door/window postconditions missing")
    require("scavengeSquareBudget" in sources["SCEncounter.lua"], "scavenge budget not enforced")
    # Blind container choice. The harness reaches the three helpers directly but
    # not the three places selection has to call them, so the wiring is pinned
    # here: sticky first, the outside-only score folded into the ranking, and
    # the container marked open at the moment the companion reaches into it.
    encounter_source = sources["SCEncounter.lua"]
    require("local openContainer, openItem, openCategory, openOwner, openScore ="
            in encounter_source
            and "return beginTask(actor, state, openContainer, openItem, openCategory,"
            in encounter_source
            and "score = score + Encounter.blindContainerScore(" in encounter_source
            and "Encounter._noteContainerOpened(state, task.container, time)"
            in encounter_source,
            "container choice is not blind-scored, sticky and marked on opening")
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
    require('NEED_ORDER = { "thirst", "hunger", "fatigue" }' in sources["SCNeeds.lua"]
            and "speech.pending" in sources["SCNeeds.lua"]
            and all(f'["need.{need}.{severity}"]' in sources["SCDialogue.lua"]
                    for need in ("hunger", "thirst", "fatigue")
                    for severity in ("noted", "serious", "urgent")),
            "transition-only hunger, thirst, and fatigue narration is incomplete")
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
    require("function Decision._safetyLeashCandidate" in sources["SCDecision.lua"]
            and "Decision._safetyLeashCandidate(actor, player, snapshot" in sources["SCDecision.lua"]
            and "decisionSafetyHoldLeashMs" in sources["SCDecision.lua"]
            and 'diagnostic("safety-hold"' in sources["SCDecision.lua"],
            "an unresolvable tactical hold must be bounded, leashed to the leader and diagnosed")
    require("observeRelationship" in sources["SCDecision.lua"]
            and 'safeSubsystem("relationship"' in sources["SCDecision.lua"],
            "relationship observation is not integrated into the decision cadence")
    relationship_source = sources["SCRelationship.lua"]
    require("shared_escape" in relationship_source and "rescued_player" in relationship_source
            and "timeTogetherMs" in relationship_source and "lastEncouragedAt" in relationship_source,
            "relationship history, shared-event, or anti-spam contract missing")
    require("validEmotes" in relationship_source and "function Relationship.isEmote" in relationship_source,
            "validated Build 42 human emote contract missing")
    dialogue_source = sources["SCDialogue.lua"]
    require("local partyRecent = {}" in dialogue_source
            and "sharesPartyRecent" in dialogue_source
            and "commonLookup" in dialogue_source
            and "A party list may never starve" in dialogue_source,
            "bounded earshot-level recent memory for shared danger and combat barks is missing")
    require(dialogue_source.count('"combat.kill"') >= 1
            and "combatBarkRecentLimit" in sources["SCCombat.lua"]
            and "combatBarkRecentLimit = 7" in (SHARED / "SCConfig.lua").read_text(encoding="utf-8"),
            "hot combat bark depth or its per-topic recent window is missing")
    farm_source = sources["SCFarmWork.lua"]
    require("local FARM_SPEECH" in farm_source
            and "local function speak(actor, topic" in farm_source
            and all(f'["{topic}"]' in farm_source for topic in (
                "farm.plot.start", "farm.sow.start", "farm.water.start",
                "farm.harvest.start", "farm.harvest.done", "farm.crop.ruined",
                "farm.crop.diseased", "farm.tool.trouble"))
            and 'speak(actor, "farm.tool.trouble"' in farm_source,
            "bounded farming start, outcome, crop-loss, and tool speech is incomplete")
    signal_start = dialogue_source.index('["signal.one"]')
    signal_end = dialogue_source.index('["combat.engage"]', signal_start)
    require("tap" not in dialogue_source[signal_start:signal_end].lower(),
            "visible-zombie hand signals still describe body tapping")
    require(all(f'["scavenge.loot.{tone}"]' in dialogue_source
                for tone in ("excited", "disappointed", "gross"))
            and "maybeReactToLoot(actor, state, task, commands, time)" in sources["SCEncounter.lua"]
            and "scavengeLootReactionChancePercent" in sources["SCEncounter.lua"],
            "post-transfer personality-aware scavenging reactions are missing")
    traversal_source = (CLIENT / "SCNativeTraversalActions.lua").read_text(encoding="utf-8")
    require(all(f'["traversal.wall.{outcome}"]' in dialogue_source
                for outcome in ("success", "struggle", "fail"))
            and 'invoke(actor, "isClimbOverWallSuccess")' in traversal_source
            and 'invoke(actor, "isClimbOverWallStruggle")' in traversal_source
            and "wallClimbReactionChancePercent" in traversal_source
            and "wallClimbReactionGroupCooldownMs" in traversal_source,
            "random outcome-matched high-wall companion reactions are missing")
    quirks_source = sources["SCQuirks.lua"]
    gameplay_util_source = sources["SCGameplayUtil.lua"]
    require("canonical = ok and identityInList" not in gameplay_util_source
            and "pendingWorldRecoveryByItem" in gameplay_util_source
            and "world_item_presence_unknown_destination_preserved" in gameplay_util_source,
            "floor-item tri-state ownership or managed recovery contract is missing")
    require('== "Base.Rubberducky"' in quirks_source
            and "Base.KeyRing_RubberDuck" not in quirks_source
            and 'phase = "recovery_pending"' in quirks_source
            and "takeWorldItemVerified" in quirks_source
            and "dropItem" in quirks_source,
            "exact rubber-duck relic identity and transactional recovery contract missing")
    require(all(f'"{ritual}"' in quirks_source for ritual in (
                "spiffo_salute", "bourbon_blessing", "mannequin_apology",
                "gnome_commander", "sports_pep_talk", "rubber_duck_oracle"))
            and 'candidate.kind == "ritual"' in sources["SCDecision.lua"]
            and "SC.Quirks.ritualIntent" in sources["SCAutonomy.lua"],
            "persistent personality ritual catalogue is not integrated into autonomy")
    require("duckSearches" in quirks_source
            and "sameIdentitySet" in quirks_source
            and 'status == "pending"' in quirks_source
            and 'return "absent"' in quirks_source,
            "bounded rubber-duck recovery does not distinguish pending from proven absence")
    require('SC.Dialogue.register("recognition.local"' in quirks_source
            and 'SC.Dialogue.register("recognition.grief"' in quirks_source
            and "subjectGender" in sources["SCCommunity.lua"]
            and "SC.Quirks.recognitionCandidate" in sources["SCDecision.lua"],
            "gendered Kentucky zombie-recognition dialogue is not wired to grief and threat warnings")
    persistence_source = (CLIENT / "SCPersistence.lua").read_text(encoding="utf-8")
    registry_source = (SHARED / "SCRegistry.lua").read_text(encoding="utf-8")
    ui_source = (CLIENT / "SCUI.lua").read_text(encoding="utf-8")
    require("personality.ritual" in persistence_source
            and "personality.ritual" in registry_source
            and '"ritual", copyLimits.ritual' in command_source
            and "ritual = detached.ritual" in command_source
            and "ritual = ritual" in sources["SCJournal.lua"]
            and "UI_SC_Journal_Ritual" in ui_source,
            "ritual persistence/export/journal projection is incomplete")
    zombie_attack_source = sources["SCZombieAttack.lua"]
    runtime_source = (CLIENT / "SCRuntime.lua").read_text(encoding="utf-8")
    require(all(f'"lastwords.{circumstance}"' in dialogue_source
                for circumstance in ("pinned", "zombies", "health", "turning"))
            and all(f"bond_{tier}" in dialogue_source
                    for tier in ("cautious", "ally", "trusted", "close", "family")),
            "cause- and relationship-specific last-word pools missing")
    require("function Dialogue.monitorMortality" in dialogue_source
            and "SC.Dialogue.monitorMortality" in runtime_source
            and "SC.Dialogue.monitorMortality" in zombie_attack_source
            and "SC.Dialogue.sayLastWords" in sources["SCInfectionCrisis.lua"],
            "last-word mortality probes are not wired to health, zombie wounds, and Knox conversion")
    require('return "grab_farewell"' in zombie_attack_source
            and "lastWordsDeathDelayMs" in zombie_attack_source
            and zombie_attack_source.index("grabbed.finalWordsAt ~= nil")
                < zombie_attack_source.index("if attackers < threshold"),
            "fatal zombie drag-down does not preserve a living farewell beat")
    require("function U.playUISound" in sources["SCGameplayUtil.lua"]
            and "fallbackSound" in sources["SCGameplayUtil.lua"]
            and "numeric ~= 0" in sources["SCGameplayUtil.lua"]
            and command_source.count('U().playUISound("UIAchievement")') == 2,
            "successful neutral and faction recruitment do not share one vanilla UI cue")
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
    require("bandit_camp" in faction_source
            and "banditFactionDailySpawnChancePercent" in faction_source
            and "banditFactionMaxCamps" in faction_source
            and "banditTierForDay" in faction_source,
            "bounded, day-scaled bandit faction production contract missing")
    require("member.spawnQueued = false" in faction_source
            and "SC.Persistence.isPending(member.actorId)" in faction_source
            and "Only hibernated snapshots live" in faction_source,
            "faction streaming/persistence duplicate-prevention contract missing")
    require("rewardReserved" in faction_source
            and 'reserved[row.item] = "request_reward"' in trade_source
            and "factionReserveItems" in trade_source,
            "request rewards are not excluded from ordinary barter stock")
    require("transaction_rollback_failed" in trade_source
            and "containerBelongsTo" in trade_source
            and "protected_trade_item" in trade_source,
            "atomic ownership-validated faction transaction contract missing")
    contract_source = sources["SCFactionContracts.lua"]
    quest_script = CLIENT.parents[1] / "scripts" / "LivingFellows_QuestItems.txt"
    require(quest_script.is_file()
            and "LivingFellows.SealedMedicalCase" in contract_source
            and "retrieve_item = true" in contract_source
            and "clear_horde = true" in contract_source,
            "generated retrieval items or horde quest kinds missing")
    require("LF_QuestInstanceId" in contract_source
            and "resolveQuestContainer" in faction_source
            and "factionQuestHouseSampleBudget" in contract_source
            and "LF_QuestReward" in trade_source,
            "persistent quest target, identity, or reserved reward contract missing")
    require("addZombiesInOutfit" in contract_source
            and "LF_QuestDeathCounted" in contract_source
            and "factionQuestHordeActivationRadius" in contract_source,
            "deferred, de-duplicated horde materialization contract missing")
    require("allowHostile = true" in trade_source
            and "restitutionRequired" in faction_source
            and 'kind == "theft" or kind == "damage"' in faction_source,
            "cooldown and double-value restitution path missing")
    require("factionPursuitLeash" in faction_behavior
            and "friendlyInLine" in faction_behavior
            and "emergency_seal" in faction_behavior,
            "territorial combat leash, friendly-fire, or emergency seal policy missing")
    require("rememberHumanThreat" in faction_behavior
            and "banditFactionLastSeenMs" in faction_behavior
            and "hostileSound" in faction_behavior
            and "banditPatrol" in faction_behavior,
            "bandit LOS memory, sound investigation, or patrol policy missing")
    require("MAX_RELATIONS" in faction_world and "MAX_NEWS" in faction_world
            and "nextEventHour" in faction_world and "word_travels:" in faction_world,
            "bounded persistent faction-world relations or consequence propagation missing")
    persistence_source = (CLIENT / "SCPersistence.lua").read_text(encoding="utf-8")
    require('{ field = "factionWorld", owner = SC.FactionWorld' in persistence_source
            and re.search(r"SC\.Call\.protected\(\s*definition\.owner\.restore",
                          persistence_source) is not None,
            "faction-world state is not part of the transactional save document")
    require("function Combat.assessOverrun" in sources["SCCombat.lua"]
            and "combatOverrunHoldMs" in sources["SCCombat.lua"]
            and "occupiedThreatSectors" in sources["SCSenses.lua"],
            "directional overrun assessment and retreat hysteresis missing")
    require("retreatTether" in sources["SCCombat.lua"]
            and "combatFollowRetreatHardLeash" in sources["SCCombat.lua"]
            and "corridorDanger" in sources["SCSenses.lua"]
            and "combatRetreatCorridorThreatRadius" in sources["SCSenses.lua"]
            and "outsideCohesion" in sources["SCSenses.lua"],
            "combat retreat lacks a group tether or route-corridor threat scoring")
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
            and "faceTargetBeforeEmote" in decision_source
            and "interruptForFollow = false" in decision_source
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
    # 0.25.5 review CR-10: proximity must never stand in for reach at a water
    # source, at the start of a wash or at its commit.
    require("local function washSourceInReach" in downtime_source
            and downtime_source.count("washSourceInReach(actor") >= 4
            and "1.45" not in downtime_source,
            "wash start or commit still gates on plain distance instead of reach")
    # 0.25.5 review CR-09: the storage policy is re-read at the transfer, not
    # only while the book was chosen from across the room.
    require("local function borrowedCheckoutAuthorized" in downtime_source
            and "borrowedCheckoutAuthorized(actor, activity)" in downtime_source
            and "availableCountExact" in downtime_source,
            "camp book checkout does not re-read the storage policy at transfer time")
    for module in ("SCPersonality.lua", "SCPersonalItems.lua", "SCObjectives.lua", "SCJournal.lua"):
        require("Events." not in sources[module], f"character-depth module owns a global event hook: {module}")
    require('config("objectiveAuditIntervalMs") or 5000' in sources["SCPersonalItems.lua"]
            and "observations[actor] = current + interval" in sources["SCPersonalItems.lua"],
            "keepsake observation is not bounded to the objective audit cadence")
    # A companion died with two zombies on him and the log could not say
    # whether he swung. The harness can reach the reporter but not the refusal
    # that should call it, so the call site is pinned here.
    _refusal = sources["SCCombat.lua"].index('return false, "no_credible_target"')
    require('Combat.reportEngagement(actor, "no_credible_target", #scored,'
            in sources["SCCombat.lua"][max(0, _refusal - 500):_refusal],
            "combat refuses a target without recording what it had to decide with")
    require('Combat.reportEngagement(actor, "attacking"' in sources["SCCombat.lua"],
            "combat attacks without leaving any record that it did")
    relationship_source = sources["SCRelationship.lua"]
    # Vanilla gives a dressing the First Aid of whoever applied it, so the
    # applying actor has to reach the calculation. The harness can call the
    # calculation but not the commit that feeds it, so that is pinned here.
    require("bandageLifeFor(helper or patient, bandage)" in sources["SCMedical.lua"]
            and "state.emergencyTransaction, helper)" in sources["SCMedical.lua"]
            and "context.inventory, nil, player)" in sources["SCMedical.lua"],
            "a bandage is dated without the First Aid of whoever applied it")
    # Steering cannot climb, so an approach barred by a fence or a window has
    # to be handed to the router that owns traversal. The harness can reach the
    # vector but not the approach that consumes it, so this is pinned here.
    require('string.sub(vectorReason, 1, 8) == "barrier:"' in sources["SCCombat.lua"]
            and 'action = "combat_approach", target = targetActor,' in sources["SCCombat.lua"],
            "a combat approach barred by a climbable barrier never routes across it")

    # `x and nil or y` and `x and false or y` always evaluate y, because the
    # middle operand is itself falsy -- so the expression cannot express the
    # branch it looks like it expresses. This has now shipped three times: the
    # route that recorded a failure beside a success, the group-passage stop
    # that reported a rejection as accepted, and thirteen more found by
    # grepping for it. A comment may name the pattern; code may not use it.
    falsy_middle = []
    for name, text in sorted(sources.items()):
        for number, line in enumerate(text.splitlines(), start=1):
            code = line.split("--", 1)[0]
            if "and nil or" in code or "and false or" in code:
                falsy_middle.append(f"{name}:{number} {line.strip()}")
    require(not falsy_middle,
            "`and nil/false or` always evaluates its fallback: "
            + "; ".join(falsy_middle[:5]))

    # A door already recorded as locked must not be handed back to the engine
    # pathfinder, which does not consult the blacklist the Lua planner uses.
    require('if SC.Navigation.behindLockedDoor(actor, goalSquare, now)'
            in sources["SCNavigation.lua"]
            and 'return false, "path_blocked:door_locked"' in sources["SCNavigation.lua"],
            "the native fallback no longer routes into a known locked room")

    # A zombie chewing on somebody is not "already handled" because the person
    # it is chewing on has claimed it. Ownership must never block urgent defence.
    require('and not ownSupport and record.rescue ~= true then'
            in sources["SCCombat.lua"],
            "the claim penalty is still charged to a rescue")

    # A casualty another helper holds must be filtered out before ranking, or
    # the most urgent one is chosen, refused, and chosen again while a second
    # wounded companion is never considered at all.
    require("if not Medical.treatmentAvailable(actor, candidate) then return end"
            in sources["SCMedical.lua"],
            "the rescue selector still ranks casualties somebody else is treating")

    # Two companions must never be sent to one retreat tile. The unaligned
    # fallback pass has to respect ownership like the aligned one, and the
    # assignment has to recheck it -- a reservation is only true at the moment
    # it is taken. Pinned rather than exercised: the harness fixture refuses the
    # second companion for an unrelated reason and so cannot isolate this.
    require("local owner = ownerKey and plan.reserved[ownerKey] or nil"
            in sources["SCCombat.lua"]
            and 'return nil, plan, "retreat_square_reserved"' in sources["SCCombat.lua"],
            "the shared-retreat fallback can still steal a reserved tile")

    # Coordination must run whether or not scoring precomputed a vector. It sat
    # inside `if moveX == nil`, so the ordinary successful-steering path skipped
    # it and a second attacker walked into the first's place anyway. Pinned:
    # isolating this needs scoring and execution driven together, which the
    # harness does not do.
    approach_guard = sources["SCCombat.lua"]
    require("if moveX == nil and target.rescue ~= true" not in approach_guard,
            "approach coordination is gated on a missing movement vector again")
    require("if target.rescue ~= true" in approach_guard
            and "Combat.shouldYieldEngagement(actor, targetActor, desired, now)"
            in approach_guard,
            "approach coordination no longer runs before the movement vector")
    # A climbable barrier keeps the approach alive so execution can route it.
    require("action.requiresRoute = true" in approach_guard
            and "action.barrierKind = string.sub(vectorReason, 9)" in approach_guard,
            "a routable barrier is dropped before execution can route it")

    combat_source = sources["SCCombat.lua"]
    banter_source = sources["SCBanter.lua"]
    objectives_source = sources["SCObjectives.lua"]
    require("combatRelationshipOverrunModifierCap" in relationship_source
            and "combatPushOverrunModifierCap" in relationship_source
            and "context.playerRequested" in relationship_source
            and "context.escapeCount" in relationship_source
            and "context.support" in relationship_source
            and "relationshipDelta" in combat_source and "pushDelta" in combat_source,
            "earned combat control is not relationship-gated or escape/support bounded")
    require('"combat_push"' in command_source and '"target_pushed"' in command_source
            and "combatPushMoraleCost" in command_source
            and "combatPushStressCost" in command_source
            and '"combat_push_succeeded"' in combat_source
            and '"combat_push_injury"' in combat_source,
            "double-Focus push cost and outcome memories are incomplete")
    require("assignedByPlayer" in objectives_source and "objectives.personal" in objectives_source
            and "function Objectives.assign(" in objectives_source
            and 'assign_objective = handleAssignObjective' in command_source,
            "player-assigned objective overlay/restore contract is missing")
    require("function Banter.interiorPulse" in banter_source
            and 'trait(actor, "DEAF")' in banter_source
            and 'trait(actor, "SMOKER")' in banter_source
            and "SC.Vitals.effectiveNicotineStress" in banter_source
            and "interior_refusal_priority" in banter_source
            and "commands.stress" not in banter_source.split("function Banter.interiorPulse", 1)[1].split("end\n\nlocal function interiorPartyPulse", 1)[0],
            "interior narration lacks native transition gates, refusal priority, or stress separation")
    diary_source = sources["SCDiary.lua"]
    require('scene = "interior"' in diary_source and '"interior.dread"' in diary_source
            and '"interior.panic"' in diary_source and '"interior.nicotine"' in diary_source,
            "interior-state diary evidence is not wired")
    require("SC.Actor.setMovement" not in "\n".join(sources.values()),
            "gameplay must resolve the movement bridge dynamically through the helper")

    diary = sources["SCDiary.lua"]
    diary_item = sources["SCDiaryItem.lua"]
    diary_text = sources["SCDiaryText.lua"]
    runtime_source = (CLIENT / "SCRuntime.lua").read_text(encoding="utf-8")
    persistence_source = (CLIENT / "SCPersistence.lua").read_text(encoding="utf-8")
    native_source = (CLIENT / "SCNativeActions.lua").read_text(encoding="utf-8")
    require("knoxInfected" not in diary and "IsInfected" not in diary
            and "getApparentInfectionLevel" not in diary,
            "diaries must never read hidden Knox infection, only Medical's felt fever level")
    for source in (diary, diary_text, diary_item):
        require("ZombRand" not in source and "math.random" not in source,
                "diary selection must be deterministic and never consume gameplay RNG")
        require("Events." not in source, "diary gameplay modules own no global event hook")
    require("SC.Diary.commitWrite(actor, activity.diary)" in downtime_source
            and "SC.Diary.abandonWrite" in downtime_source
            and "write_diary = true" in downtime_source,
            "a diary page must commit only from a completed supervised downtime action")
    require(re.search(r"\bwrite_diary\s*=\s*\{\s*animation", native_source) is not None,
            "diary writing lacks its verified human visual action")
    require(runtime_source.index("SC.Diary.noteAuthorDeath")
            > runtime_source.index("SC.Community.noteCompanionDeath")
            and runtime_source.index("SC.Diary.noteAuthorDeath")
            < runtime_source.index("SC.Actor.retireDead(record.actor)"),
            "author death must freeze the diary after grief and before actor retirement")
    require('field = "diaries", owner = SC.Diary' in persistence_source
            and "job.diaryContentRevision" in persistence_source
            and "diary content changed during scheduled capture" in persistence_source,
            "diary page content is not bound to the scheduled save barrier")
    require("putShort" in diary_item and "MAX_ENTRY_BYTES = 1600" in diary_item
            and "Item.MAX_TOTAL_BYTES" in diary_item,
            "diary entries must stay individually bounded under the 16-bit ModData string save")
    require("diary_harness.lua" in gameplay_runner,
            "the private diary Kahlua harness is not part of the gameplay gate")

    # Incomplete observation is never proof of absence, and an action
    # stopping is never proof of completion.
    production_source = sources["SCProduction.lua"]
    personal_source = sources["SCPersonalItems.lua"]
    base_work_source = sources["SCBaseWork.lua"]
    require("bodyContentsStatus" in production_source
            and "belongings_scan_incomplete" in production_source
            and production_source.count("disposalStillPermitted(") >= 3,
            "corpse disposal must scan nested belongings and re-check before the irreversible act")
    require("function PersonalItems.walkContainer" in personal_source
            and "function PersonalItems.searchResumable" in personal_source
            and "function PersonalItems.ownedBy" in personal_source
            and "remaining.exhausted" in personal_source,
            "bounded inventory traversal must be resumable and report incompleteness")
    require("book_search_incomplete" in sources["SCDiary.lua"],
            "an unfinished book search must never authorise a second diary")
    require("local function destinationsFor" in base_work_source
            and "local function returnCargo" in base_work_source
            and "state.cargo" in base_work_source,
            "hauling must pick a destination with room and keep an exact cargo receipt")
    require("local function buildOutcome" in base_work_source
            and "scCompleted" in base_work_source
            and "build_result_missing" in base_work_source,
            "a build completes only with a receipt and the requested object present")
    require("local function carriedSupplies" in base_work_source
            and "local function stageCarriedSupply" in base_work_source,
            "carried supplies must be found inside bags and staged for the build action")
    require(re.search(r"return SC\.Navigation\.request(Any)?\(actor, (targets|approaches)",
                      base_work_source) is None,
            "an approach result must not leak a third value into the terminal flag")
    life_events = sources["SCLifeEvents.lua"]
    require("SC.Diary.observeLifeEvent" in life_events
            and "table.remove(queue, 1)" in life_events.split("SC.Diary.observeLifeEvent")[0],
            "diaries must observe life events without draining SCCommunity's queue")
    require('SC.Diary.noteDowntime' in downtime_source
            and downtime_source.index("SC.Diary.noteDowntime")
            > downtime_source.index('failureReasons[activity.kind] or "downtime_commit_failed"'),
            "only a completed, verified downtime activity may reach a diary")

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
