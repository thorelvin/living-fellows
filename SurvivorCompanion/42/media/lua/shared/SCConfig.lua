-- SPDX-License-Identifier: MIT

require "SCNamespace"

local SC = SurvivorCompanion
SC.Config = SC.Config or {}

local function readonly(source, label)
    local proxy = {}
    setmetatable(proxy, {
        __index = source,
        __newindex = function()
            error("attempt to modify immutable configuration " .. label, 2)
        end,
        __metatable = "immutable",
    })
    return proxy
end

-- The only canonical value table. Section/key calls are translated through
-- aliases below, so a setting is never copied into several defaults tables.
local valueData = {
    frameBudgetMs = 2,
    performanceSampleWindow = 120,
    performancePerceptionUnitsPerFrame = 72,
    performanceNavigationNodesPerFrame = 64,
    performanceScavengeSquaresPerFrame = 28,
    performanceScavengeContainersPerFrame = 2,
    performanceFactionSamplesPerFrame = 12,
    performanceUrgentUnitFloor = 96,
    performanceCacheTtlMs = 75,
    performanceLoadEvaluationFrames = 60,
    performanceLoadChangeCooldownFrames = 120,
    performanceLoadRaiseRatio = 0.22,
    performanceLoadLowerRatio = 0.05,
    circuitBreakerErrors = 3,
    circuitBreakerFailures = 3,
    circuitBreakerResetMs = 30000,
    diagnosticCooldownMs = 10000,
    disabledNoticeCooldownMs = 30000,
    maxIntentLength = 48,

    -- Public reliability telemetry is deliberately bounded. The action
    -- supervisor keeps control state in memory only; saves reconstruct work
    -- from authoritative game state instead of serializing a partial commit.
    actionHistoryLimit = 20,
    actionRetryBaseMs = 1500,
    actionRetrySecondMs = 5000,
    actionRetryThirdMs = 15000,
    actionRetryMaximumMs = 60000,
    actionRetryMaxAttempts = 4,
    actionSelectedTimeoutMs = 2500,
    actionReservedTimeoutMs = 5000,
    actionApproachTimeoutMs = 15000,
    actionSettleTimeoutMs = 2500,
    actionAnimationTimeoutMs = 12000,
    actionCommitTimeoutMs = 1000,
    actionVerifyTimeoutMs = 1000,
    actionWaitingTimeoutMs = 15000,
    actionRecoveryTimeoutMs = 15000,
    actionPoseMaximumDisplacement = 0.25,

    movementIntervalMs = 100,
    combatDecisionIntervalMs = 125,
    followIntervalMs = 167,
    perceptionIntervalMs = 500,
    slowIntervalMs = 1000,
    persistenceIntervalMs = 30000,
    walkDistance = 0.045,
    runDistance = 0.075,
    sneakDistance = 0.032,
    movementSoundDelta = 1.0,

    perceptionRadius = 18,
    perceptionSquareBudget = 240,
    perceptionThreatLimit = 32,
    perceptionExitLimit = 16,
    perceptionAllyLimit = 16,
    immediateThreatRadius = 2.25,
    lastKnownThreatMs = 5000,
    soundMemoryMs = 8000,
    soundLimit = 16,
    escapeScanRadius = 5,

    navigationArrivalDistance = 0.6,
    navigationMicroDistance = 1.45,
    navigationNodeBudget = 220,
    navigationAlternativeRoutes = 3,
    navigationAlternativeNodeBudget = 80,
    navigationAlternativeMinLength = 6,
    navigationRouteDiversityPenalty = 3.5,
    navigationStealthVisibleRadius = 10,
    navigationStealthObstructedRadius = 6,
    navigationStealthCloseRadius = 4,
    navigationStealthThreatPenalty = 36,
    navigationStealthClosePenalty = 90,
    navigationStealthNodeBudget = 320,
    navigationStealthRepathMs = 1800,
    navigationBushPenalty = 5.5,
    navigationTreePenalty = 12,
    navigationTreeClearancePenalty = 4,
    navigationEmergencyVegetationScale = 0.2,
    navigationRepathMs = 900,
    navigationStuckMs = 2200,
    navigationObstacleStuckMs = 900,
    navigationBlockedEdgeMs = 4500,
    navigationDynamicBlockedEdgeMs = 1100,
    navigationNativeLeaseMs = 6500,
    navigationNativeStartGraceMs = 650,
    navigationNativeTurnGraceMs = 3200,
    navigationActorStateGraceMs = 900,
    navigationActorStateTimeoutMs = 12000,
    navigationRouteMemorySuccessMs = 30000,
    navigationRouteMemoryFailureMs = 8000,
    navigationRouteMemorySuccessBonus = 0.25,
    navigationRouteMemoryFailurePenalty = 4.5,
    navigationCrowdPenalty = 9,
    navigationRecoveryAttempts = 3,
    navigationTerminalRetryMs = 8000,
    navigationGoalResetDistance = 3.0,
    navigationReservationMs = 8000,
    navigationBreadcrumbLimit = 64,
    navigationEgressNodeBudget = 160,
    navigationEgressRadius = 18,
    navigationEgressRefreshMs = 2500,
    navigationCornerObserveMs = 350,
    navigationRoomEntryObserveMs = 450,
    navigationWeaponReadyHoldMs = 1200,
    navigationStairObserveMs = 450,
    navigationStairSpacing = 1.75,
    navigationChokeReservationMs = 1400,
    navigationChokeCorridorNodes = 3,
    navigationPersonalSpace = 0.9,
    navigationStepReservationMs = 450,
    navigationYieldMs = 900,
    navigationTrafficDeadlockMs = 2200,
    navigationTrafficWaiterMs = 5000,
    movementRecorderWindowMs = 30000,
    movementRecorderMaxEvents = 180,
    movementRecorderEnabled = false,
    doorCloseDelayMs = 700,
    doorClearanceDistance = 0.38,
    curtainCooldownMs = 45000,
    curtainDecisionIntervalMs = 12000,
    curtainTaskTimeoutMs = 30000,
    curtainSearchRadius = 5,
    curtainSearchSquareBudget = 121,
    curtainSearchObjectBudget = 128,
    windowOpenMs = 1300,
    windowSmashMs = 900,
    windowGlassRemovalMs = 1400,
    windowClimbMs = 1300,

    vehicleBoardRangeSquared = 2.56,
    vehicleBoardMaxSpeedKph = 0.5,
    vehicleApproachRadius = 4,
    -- A manifest is allocated before followers approach the doors.  This keeps
    -- large teams from crowding one entrance or repeatedly requesting seats
    -- which do not exist.  Unseated followers wait for the player to stop and
    -- leave the vehicle; they are never teleported after a moving car.
    vehicleManifestLimit = 32,
    vehicleRangedSupportMaxSpeedKph = 15,
    vehicleWeaponsFreeMaxSpeedKph = 30,
    vehicleFireSpacingMs = 240,

    combatRetreatPressure = 3.5,
    combatFirearmMinDistance = 2.2,
    combatShoveDistance = 1.35,
    combatShoveFollowupDelayMs = 300,
    combatShoveFollowupWindowMs = 1800,
    combatStompDistance = 1.55,
    combatStompMaxImmediate = 1,
    combatMeleeDistance = 1.7,
    friendlyFire = false,
    friendlyFireCorridor = 0.8,
    combatAllySupportRadius = 6,
    combatAllySupportMax = 12,
    combatCloseThreatRadius = 4.5,
    combatStealthEmergencyRadius = 1.5,
    combatCloseDefenseRadius = 5,
    combatWeaponsFreeRadius = 14,
    combatTargetClaimMs = 450,
    combatTargetClaimPenalty = 42,
    combatRearThreatPriority = 30,
    combatFlankThreatPriority = 18,
    combatOverrunRisk = 62,
    combatOverrunRecoveryRisk = 38,
    combatOverrunHoldMs = 2600,
    -- Competent survivors preserve enough stamina to break contact. Heavy
    -- weapons, poor fitness, crowding and weak exits raise this reserve.
    combatMinimumEnduranceReserve = 0.18,
    combatMaximumEnduranceReserve = 0.62,
    combatHeavyWeaponWeight = 2.5,
    -- Build 42 rewards a settled sight picture. Skilled, calm shooters need
    -- less time; panic and relationship stress make the pause longer.
    combatAimBaseMs = 650,
    combatAimMinimumMs = 220,
    combatAimMaximumMs = 1800,
    combatAimSkillReductionMs = 55,
    combatAimPanicPenaltyMs = 170,
    combatAimStressPenaltyMs = 4,
    combatTacticalRetreatMinDistance = 1.45,
    combatTacticalRetreatMaxDistance = 6.5,
    combatTacticalRetreatMaxImmediate = 1,
    combatRetreatCounterCooldownMs = 1100,
    combatRetreatCoverFireMinDistance = 3.0,
    combatRetreatCoverFireMaxRisk = 76,
    -- Combat barks are event-driven. The actor and group gates keep a squad
    -- from becoming a constant wall of speech, while the per-event cooldowns
    -- preserve rare high-value calls such as retreat and confirmed kills.
    combatBarkActorGapMs = 7500,
    combatBarkGroupGapMs = 2500,
    combatBarkCriticalActorGapMs = 2000,
    combatBarkCriticalGroupGapMs = 1200,
    combatBarkEngageCooldownMs = 30000,
    combatBarkRetreatCooldownMs = 20000,
    combatBarkStruggleCooldownMs = 30000,
    combatBarkKillCooldownMs = 14000,
    combatBarkStruggleDelayMs = 6500,
    combatBarkStruggleActionCount = 4,
    combatBarkKillCreditMs = 5000,
    combatBarkSoundRadius = 8,

    downedHealth = 18,
    downedRecoverHealth = 25,
    medicalRange = 1.35,
    medicalCriticalHealth = 35,

    encounterIntervalMs = 1000,
    encounterActiveRadius = 75,
    encounterDespawnRadius = 95,
    scavengeRadius = 14,
    scavengeSquareBudget = 100,
    scavengeItemBudget = 40,
    scavengeReservationMs = 12000,
    scavengeFailureCooldownMs = 15000,
    scavengeSettleMs = 250,
    scavengeNoUsefulCooldownMs = 30000,
    scavengeSuccessCooldownMs = 4000,
    scavengeStatusHoldMs = 8000,
    scavengeMemoryLimit = 96,
    -- Completed visual actions remain claimable until their gameplay owner has
    -- committed the corresponding inventory or medical transaction.
    visualEffectClaimMs = 2000,
    actionPacingShortMinMs = 350,
    actionPacingShortMaxMs = 850,
    actionPacingMinMs = 650,
    actionPacingMaxMs = 1500,
    actionPacingLongMinMs = 1000,
    actionPacingLongMaxMs = 2400,
    actionPacingLookChancePercent = 42,
    actionPacingLookDelayPercent = 45,
    actionPacingFollowSlack = 2.5,
    actionPacingRepeatBoostMs = 350,
    actionPacingRepeatWindowMs = 10000,
    actionVisualMinTicks = 45,
    actionVisualMaxTicks = 420,
    corpseLootRadius = 10,
    corpseLootSquareBudget = 80,
    corpseLootGraceMs = 6000,

    -- Companions treat effective capacity as a safety limit, not a target.
    -- Quartermasters may use more of it because hauling is their job; every
    -- other role preserves enough headroom to run and fight without a heavy
    -- load penalty.
    logisticsSoftLoadRatio = 0.72,
    logisticsHardLoadRatio = 0.90,
    logisticsQuartermasterSoftLoadRatio = 0.82,
    logisticsQuartermasterHardLoadRatio = 0.95,
    -- Explicitly allowing overload remains bounded: the NPC will knowingly
    -- accept movement penalties, but still sheds weight before the engine's
    -- hard encumbrance state becomes effectively unmanageable.
    logisticsOverloadSoftLoadRatio = 1.00,
    logisticsOverloadHardLoadRatio = 1.20,
    logisticsInventoryItemBudget = 256,
    logisticsStorageRange = 32,
    logisticsUpdateIntervalMs = 750,
    logisticsBagUpgradeMinimum = 2.0,
    logisticsClothingUpgradeMinimum = 8.0,

    downtimeWashRadius = 4,
    downtimeWashMinimumWater = 4,

    followDistance = 3,
    followFarDistance = 18,
    followRecoveryDistance = 42,
    guardRadius = 5,
    -- Long enough for a guard to finish a natural idle/read/repair cycle
    -- between short patrol legs instead of pacing continuously.
    guardPatrolIntervalMs = 30000,
    threatWarningCooldownMs = 15000,
    threatWarningGroupCooldownMs = 3500,
    threatWarningSoundRadius = 10,
    sharedAlertMemoryMs = 5000,
    -- SCNativeCompanion deliberately skips IsoPlayer's local visibility pass.
    -- A bounded companion-side scan feeds visible actors into the zombie's own
    -- spotted() logic instead, preserving vanilla target-distance preference.
    zombieTargetScanIntervalMs = 350,
    zombieTargetRadius = 18,
    zombieTargetCloseNoticeRadius = 2.5,
    zombieTargetSwitchAdvantage = 0.75,
    zombieTargetMaxChecks = 128,
    sharedAlertCloseRadius = 8,
    formationSeparation = 1.25,
    formationArrivalDistance = 0.9,
    formationReleaseDistance = 1.55,
    rearScanIntervalMs = 8500,
    rearScanHoldMs = 550,
    positioningReservationMs = 650,
    conversationPreferredDistance = 1.65,
    conversationMinimumDistance = 1.2,
    conversationMaximumDistance = 2.8,
    conversationCompanionSpacing = 1.15,
    conversationHoldMs = 5000,
    downtimeIntervalMs = 1500,
    downtimeSafeMs = 5000,
    downtimeReservationMs = 30000,
    downtimeActivityMs = 6000,
    ambientRepeatCooldownMs = 60000,
    -- Vanilla overhead chat fades too quickly for full companion sentences.
    -- Use real-time, length-aware display targets; the native companion keeps
    -- the actor-owned line alive without routing speech through the player.
    dialogueDisplayMinMs = 8000,
    dialogueDisplayBaseMs = 5000,
    dialogueDisplayPerCharacterMs = 70,
    dialogueDisplayMaxMs = 15000,
    workReservationMs = 45000,
    workApproachTimeoutMs = 90000,
    decisionHysteresis = 8,
    decisionMinStateMs = 900,
    relationshipObservationIntervalMs = 1000,
    -- Living-survivor simulation uses world age for emotional time and the
    -- existing scheduler for CPU cadence. Major incidents are deliberately
    -- rare, causal and interruptible by every survival-critical decision.
    communityPulseIntervalMs = 1000,
    mindSampleGameMinutes = 10,
    mindThoughtLimit = 12,
    mindHistoryLimit = 96,
    mindPairLimit = 64,
    mindPairMemoryLimit = 8,
    mindMinorStress = 55,
    mindMajorStress = 82,
    mindCriticalGameMinutes = 30,
    mindMinorCooldownGameHours = 6,
    mindMajorCooldownGameHours = 96,
    mindGroupCooldownGameHours = 60,
    mindJoyMorale = 82,
    mindJoyMaximumStress = 25,
    mindJoySustainGameHours = 2,
    mindJoyCooldownGameHours = 36,
    mindJoyDurationGameHours = 6,
    mindBoredGameMinutes = 45,
    mindPurposeCooldownGameHours = 2,
    mindSupplyRunAgeGameHours = 48,
    mindSupplyRequestCooldownGameHours = 24,
    mindSupplyPromiseGameHours = 24,
    mindDetailedRadius = 40,
    mindSocialRadius = 10,
    mindRestlessRoutePoints = 4,
    mindRestlessRouteRadius = 6,
    mindEpisodeActionTimeoutMs = 12000,
    mindShutdownGameHours = 4,
    mindShutdownSupportGameMinutes = 15,
    griefMemoryLimit = 8,
    griefDeathHistoryLimit = 32,
    griefAcuteMinHours = 18,
    griefAcuteMaxHours = 72,
    griefRecoveryMinDays = 5,
    griefRecoveryMaxDays = 18,
    griefReactionDelayGameMinutes = 12,
    griefPauseGameMinutes = 25,
    objectiveAuditIntervalMs = 5000,
    objectiveCooldownMs = 21600000,
    maxObjectiveHistory = 8,
    maxJournalMemories = 12,
    personalityDecisionModifierCap = 8,
    personalityOverrunModifierCap = 4,
    personalityDowntimeModifierCap = 6,
    objectiveDecisionModifierCap = 4,
    objectiveActivityModifierCap = 6,
    objectiveItemModifierCap = 12,

    -- Native hunger/thirst still advance so moodles, nutrition and item effects
    -- remain vanilla.  SCNeeds only rebates half of each positive sampled delta.
    needsRateMultiplier = 0.5,
    needsRateSampleMs = 1000,
    needsNaturalDeltaLimit = 1.0,
    needsHungerThreshold = 0.55,
    needsHungerEmergency = 0.82,
    needsThirstThreshold = 0.48,
    needsThirstEmergency = 0.75,
    needsWaterSourceRadius = 12,
    needsWaterSquareBudget = 180,

    -- A container becomes camp storage only after the local player has opened
    -- it.  This prevents autonomous workers from raiding unseen world loot.
    campStorageRadius = 24,
    campStorageSquareBudget = 220,
    campStorageItemBudget = 80,
    campStorageReservationMs = 20000,

    -- Bounded Base Life state keeps per-pulse work and long-world saves predictable.
    baseDefaultAreaRadius = 6,
    baseMaxZones = 24,
    baseMaxStorages = 32,
    baseMaxMaintenanceTargets = 64,
    baseMaxJobs = 64,
    baseHistoryLimit = 96,
    baseJobLeaseMs = 45000,
    baseJobRetryMs = 10000,
    baseAuditIntervalMs = 2000,
    baseGuardPatrolIntervalMs = 30000,
    baseGuardShiftMs = 180000,
    baseOperationsAuditIntervalMs = 5000,
    baseOperationsStorageItemBudget = 160,

    -- Bites start a social incident. Evidence and deliberation advance slowly,
    -- with an additional delay before any irreversible outcome is eligible.
    infectionCrisisIntervalMs = 500,
    infectionCrisisSafeDelayMs = 10000,
    infectionCrisisDeliberationMs = 12000,
    infectionCrisisHistoryLimit = 96,
    infectionCrisisEvidenceLimit = 32,
    infectionCrisisMaxRecords = 32,

    dangerSignalMaxDistance = 10,
    dangerSignalImmediateRadius = 4,

    debugSpawnEnabled = false,
    debugSpawnIntervalMs = 60000,
    -- Private playtest encounters are deliberately close and may use a visible
    -- square when open terrain offers no unseen candidate. Production spawn
    -- distance and visibility rules remain independent below.
    debugSpawnMinDistance = 8,
    debugSpawnMaxDistance = 15,
    debugDiscoveryDistance = 6,
    productionEncounterEnabled = true,
    productionSpawnCheckIntervalMs = 5000,
    productionSpawnInitialDelayMs = 60000,
    productionSpawnCooldownMs = 300000,
    maxNeutralEncounters = 1,
    spawnMinDistance = 25,
    spawnMaxDistance = 55,
    spawnSampleCount = 48,
    spawnLocalSafetyRadius = 3,
    spawnMaxNearbyZombies = 2,
    -- Runtime loops remain bounded, but a player may field ten companions and
    -- still retain headroom for neutral encounters and base residents.
    maxCompanions = 16,

    -- Persistent survivor factions. Production checks are cheap and bounded;
    -- the seven-day gate is measured in world age, not real-time scheduler
    -- ticks. Debug tools call the same validated house/spawn pipeline manually.
    factionEnabled = true,
    factionPulseIntervalMs = 1000,
    factionProductionCheckIntervalMs = 30000,
    factionFirstEligibleDay = 7,
    factionSpawnCooldownDays = 7,
    factionDailySpawnChancePercent = 8,
    factionMaxHouseholds = 3,
    factionMinHouseDistance = 300,
    factionSpawnMinDistance = 35,
    factionSpawnMaxDistance = 90,
    factionHouseSampleBudget = 96,
    factionMemberMin = 1,
    factionMemberMax = 3,
    factionWarningOuterRadius = 18,
    factionWarningInnerRadius = 10,
    factionPursuitLeash = 15,
    factionBarkCooldownMs = 20000,
    factionHibernationDistance = 120,
    factionWakeDistance = 100,
    factionBarricadeFirstPassPlanks = 2,
    factionBarricadeFinalPlanks = 4,
    factionTrespassForgivenessDays = 3,
    factionOffenseForgivenessDays = 7,
    factionTradeDistance = 6,
    -- Large modded player inventories remain bounded but must not hide contract
    -- goods merely because they occur after the ordinary companion scan cap.
    factionTradeInventoryScanLimit = 4096,
    -- 0.17 faction life remains group-bounded: one inventory audit per world
    -- hour, one deterministic crisis roll per six hours, and one actor-facing
    -- life update every few seconds regardless of frame rate.
    factionLifePulseIntervalMs = 2500,
    factionResourceAuditHours = 1,
    factionRepresentativeApproachRadius = 26,
    factionCrisisCheckHours = 6,
    factionCrisisCooldownHours = 72,
    factionCrisisChancePercent = 4,
    factionRumourMinDistance = 45,
    factionRumourMaxDistance = 120,
    -- 0.18 Social Contracts stays deliberately household-bounded: one live
    -- promise, short guest invitations, and infrequent social-state updates.
    factionContractPulseIntervalMs = 2500,
    factionContractDeadlineHours = 48,
    factionContractCooldownHours = 24,
    factionContractThreatRadius = 18,
    factionContractThreatMinLoadedSquares = 64,
    factionContractTargetDistance = 24,
    factionContractMemoryLimit = 64,
    factionContractHistoryLimit = 32,
    factionGuestAccessHours = 12,
    factionPrivateContactRadius = 14,
    -- A household may lend one named resident for a real field trial after
    -- sustained trust. The actor is never cloned; the same persistent record
    -- changes affiliation transactionally and can return home.
    factionRecruitmentEnabled = true,
    factionRecruitmentContractsRequired = 2,
    factionRecruitmentTrialMinHours = 6,
    factionRecruitmentTrialMaxHours = 24,
    factionRecruitmentExtensionHours = 12,
    factionRecruitmentCooldownHours = 72,
    -- The faction-world layer is deliberately slow and bounded. It creates
    -- social consequences and news, never off-screen actor deaths or damage.
    factionWorldEventIntervalHours = 24,
    factionWorldRelationLimit = 64,
    factionWorldNewsLimit = 48,

    restoreIntervalMs = 5000,
    restorePerPulse = 2,
    restoreMaximumBackoffMs = 300000,
    restoreMaximumAttempts = 6,
    persistenceMaxDocumentEntries = 2000000,
    maxInventoryItems = 256,
    -- Persistence has a separate, larger budget than ordinary AI inventory
    -- scans.  Reaching either bound aborts the save transaction instead of
    -- silently dropping possessions.
    persistenceMaxInventoryItems = 2048,
    persistenceMaxInventoryDepth = 12,
    persistenceMaxItemModDataEntries = 256,
    maxMemories = 64,
    maxDowntimeFacts = 32,
    maxVehicleLookup = 128,

    defaultOrder = "follow",
    defaultFollowDistance = 3,
    defaultScavenge = true,
    defaultCombatStance = "defensive",
    defaultCombatDoctrine = "close_defense",
    defaultWeaponPriority = "best",
    defaultRideWithPlayer = true,

    uiPanelOpacity = 0.66,

    -- Private-test escape hatch only. Staging rejects a true value.
    experimentalNpcPlayerActor = false,
}

local aliases = {
    runtime = {
        frameBudgetMs = "frameBudgetMs",
        circuitBreakerErrors = "circuitBreakerErrors",
        circuitBreakerFailures = "circuitBreakerFailures",
        circuitBreakerResetMs = "circuitBreakerResetMs",
        diagnosticCooldownMs = "diagnosticCooldownMs",
        disabledNoticeCooldownMs = "disabledNoticeCooldownMs",
        maxIntentLength = "maxIntentLength",
        actionHistoryLimit = "actionHistoryLimit",
        actionRetryBaseMs = "actionRetryBaseMs",
        actionRetrySecondMs = "actionRetrySecondMs",
        actionRetryThirdMs = "actionRetryThirdMs",
        actionRetryMaximumMs = "actionRetryMaximumMs",
        actionRetryMaxAttempts = "actionRetryMaxAttempts",
    },
    rates = {
        movementMs = "movementIntervalMs",
        combatMs = "combatDecisionIntervalMs",
        navigationMs = "followIntervalMs",
        perceptionMs = "perceptionIntervalMs",
        slowMs = "slowIntervalMs",
        persistenceMs = "persistenceIntervalMs",
    },
    movement = {
        walkDistance = "walkDistance",
        runDistance = "runDistance",
        sneakDistance = "sneakDistance",
        soundDelta = "movementSoundDelta",
    },
    vehicle = {
        boardRangeSquared = "vehicleBoardRangeSquared",
        boardMaxSpeedKph = "vehicleBoardMaxSpeedKph",
        approachRadius = "vehicleApproachRadius",
    },
    spawn = {
        debugEnabled = "debugSpawnEnabled",
        debugIntervalMs = "debugSpawnIntervalMs",
        debugMinDistance = "debugSpawnMinDistance",
        debugMaxDistance = "debugSpawnMaxDistance",
        debugDiscoveryDistance = "debugDiscoveryDistance",
        productionEnabled = "productionEncounterEnabled",
        productionCheckMs = "productionSpawnCheckIntervalMs",
        productionInitialDelayMs = "productionSpawnInitialDelayMs",
        productionCooldownMs = "productionSpawnCooldownMs",
        maxNeutralEncounters = "maxNeutralEncounters",
        minDistance = "spawnMinDistance",
        maxDistance = "spawnMaxDistance",
        sampleCount = "spawnSampleCount",
        localSafetyRadius = "spawnLocalSafetyRadius",
        maxNearbyZombies = "spawnMaxNearbyZombies",
        maxCompanions = "maxCompanions",
    },
    factions = {
        enabled = "factionEnabled",
        pulseMs = "factionPulseIntervalMs",
        productionCheckMs = "factionProductionCheckIntervalMs",
        firstEligibleDay = "factionFirstEligibleDay",
        cooldownDays = "factionSpawnCooldownDays",
        dailyChancePercent = "factionDailySpawnChancePercent",
        maxHouseholds = "factionMaxHouseholds",
        minHouseDistance = "factionMinHouseDistance",
        spawnMinDistance = "factionSpawnMinDistance",
        spawnMaxDistance = "factionSpawnMaxDistance",
        sampleBudget = "factionHouseSampleBudget",
        memberMin = "factionMemberMin",
        memberMax = "factionMemberMax",
        warningOuterRadius = "factionWarningOuterRadius",
        warningInnerRadius = "factionWarningInnerRadius",
        pursuitLeash = "factionPursuitLeash",
        barkCooldownMs = "factionBarkCooldownMs",
        hibernationDistance = "factionHibernationDistance",
        wakeDistance = "factionWakeDistance",
        firstPassPlanks = "factionBarricadeFirstPassPlanks",
        finalPlanks = "factionBarricadeFinalPlanks",
        trespassForgivenessDays = "factionTrespassForgivenessDays",
        offenseForgivenessDays = "factionOffenseForgivenessDays",
        tradeDistance = "factionTradeDistance",
        tradeInventoryScanLimit = "factionTradeInventoryScanLimit",
        lifePulseMs = "factionLifePulseIntervalMs",
        resourceAuditHours = "factionResourceAuditHours",
        representativeRadius = "factionRepresentativeApproachRadius",
        crisisCheckHours = "factionCrisisCheckHours",
        crisisCooldownHours = "factionCrisisCooldownHours",
        crisisChancePercent = "factionCrisisChancePercent",
        rumourMinDistance = "factionRumourMinDistance",
        rumourMaxDistance = "factionRumourMaxDistance",
        contractPulseMs = "factionContractPulseIntervalMs",
        contractDeadlineHours = "factionContractDeadlineHours",
        contractCooldownHours = "factionContractCooldownHours",
        contractThreatRadius = "factionContractThreatRadius",
        contractThreatMinLoadedSquares = "factionContractThreatMinLoadedSquares",
        contractTargetDistance = "factionContractTargetDistance",
        contractMemoryLimit = "factionContractMemoryLimit",
        contractHistoryLimit = "factionContractHistoryLimit",
        guestAccessHours = "factionGuestAccessHours",
        privateContactRadius = "factionPrivateContactRadius",
        recruitmentEnabled = "factionRecruitmentEnabled",
        recruitmentContractsRequired = "factionRecruitmentContractsRequired",
        recruitmentTrialMinHours = "factionRecruitmentTrialMinHours",
        recruitmentTrialMaxHours = "factionRecruitmentTrialMaxHours",
        recruitmentExtensionHours = "factionRecruitmentExtensionHours",
        recruitmentCooldownHours = "factionRecruitmentCooldownHours",
        worldEventIntervalHours = "factionWorldEventIntervalHours",
        worldRelationLimit = "factionWorldRelationLimit",
        worldNewsLimit = "factionWorldNewsLimit",
    },
    persistence = {
        restoreIntervalMs = "restoreIntervalMs",
        restorePerPulse = "restorePerPulse",
        restoreMaximumBackoffMs = "restoreMaximumBackoffMs",
        restoreMaximumAttempts = "restoreMaximumAttempts",
        maxDocumentEntries = "persistenceMaxDocumentEntries",
        maxInventoryItems = "maxInventoryItems",
        maxSavedInventoryItems = "persistenceMaxInventoryItems",
        maxSavedInventoryDepth = "persistenceMaxInventoryDepth",
        maxItemModDataEntries = "persistenceMaxItemModDataEntries",
        maxMemories = "maxMemories",
        maxDowntimeFacts = "maxDowntimeFacts",
        maxVehicleLookup = "maxVehicleLookup",
    },
    orders = {
        defaultOrder = "defaultOrder",
        defaultFollowDistance = "defaultFollowDistance",
        defaultScavenge = "defaultScavenge",
        defaultCombatStance = "defaultCombatStance",
        defaultWeaponPriority = "defaultWeaponPriority",
    },
    safety = {
        friendlyFire = "friendlyFire",
    },
    experimental = {
        npcPlayerActor = "experimentalNpcPlayerActor",
    },
}

local runtimeOverrides = {}

local function clamp(value, minimum, maximum)
    value = tonumber(value)
    if value == nil then return nil end
    return math.max(minimum, math.min(maximum, value))
end

local function sandboxRoot(source)
    source = source ~= nil and source
        or (type(_G) == "table" and rawget(_G, "SandboxVars") or nil)
    return type(source) == "table" and type(source.LivingFellows) == "table"
        and source.LivingFellows or nil
end

function SC.Config.refreshSandbox(source)
    local sandbox = sandboxRoot(source)
    runtimeOverrides = {}
    if sandbox == nil then return false, "sandbox options unavailable" end

    if type(sandbox.EncountersEnabled) == "boolean" then
        runtimeOverrides.productionEncounterEnabled = sandbox.EncountersEnabled
    end
    local encounterCadence = {
        [1] = 900000, -- very rare
        [2] = 600000, -- rare
        [3] = 300000, -- normal
        [4] = 120000, -- frequent
    }
    local cadence = encounterCadence[math.floor(tonumber(sandbox.EncounterFrequency) or -1)]
    if cadence then runtimeOverrides.productionSpawnCooldownMs = cadence end

    local companions = clamp(sandbox.MaxCompanions, 1, 16)
    if companions then runtimeOverrides.maxCompanions = math.floor(companions) end
    local needsRate = clamp(sandbox.CompanionNeedsRate, 0, 2)
    if needsRate then runtimeOverrides.needsRateMultiplier = needsRate end

    if type(sandbox.HouseholdSpawnsEnabled) == "boolean" then
        runtimeOverrides.factionEnabled = sandbox.HouseholdSpawnsEnabled
    end
    local householdChance = clamp(sandbox.HouseholdDailyChance, 0, 100)
    if householdChance then
        runtimeOverrides.factionDailySpawnChancePercent = math.floor(householdChance)
    end
    local households = clamp(sandbox.MaxHouseholds, 0, 12)
    if households then runtimeOverrides.factionMaxHouseholds = math.floor(households) end
    local opacity = clamp(sandbox.UIOpacity, 0.25, 0.85)
    if opacity then runtimeOverrides.uiPanelOpacity = opacity end
    return true
end

function SC.Config.sandboxSnapshot()
    local result = {}
    for key, value in pairs(runtimeOverrides) do result[key] = value end
    return result
end

local function effectiveValue(key)
    if runtimeOverrides[key] ~= nil then return runtimeOverrides[key] end
    return valueData[key]
end

local sectionViews = {}
for section, mapping in pairs(aliases) do
    local data = setmetatable({}, {
        __index = function(_, key)
            local flatKey = mapping[key]
            return flatKey and effectiveValue(flatKey) or nil
        end,
    })
    sectionViews[section] = readonly(data, "SC.Config.sections." .. section)
end

SC.Config.defaults = SC.Config.defaults or readonly(valueData, "SC.Config.defaults")
SC.Config.sections = SC.Config.sections or readonly(sectionViews, "SC.Config.sections")

function SC.Config.get(section, key)
    if key == nil then
        if valueData[section] ~= nil then
            return effectiveValue(section)
        end
        return sectionViews[section]
    end
    local mapping = aliases[section]
    local flatKey = mapping and mapping[key] or nil
    return flatKey and effectiveValue(flatKey) or nil
end

SC.Config.refreshSandbox()

return SC.Config
