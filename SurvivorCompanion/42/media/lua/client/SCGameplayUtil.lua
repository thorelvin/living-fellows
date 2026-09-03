-- SPDX-License-Identifier: MIT

if type(require) == "function" then pcall(require, "SCNativeList") end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.GameplayUtil = SC.GameplayUtil or {}
local U = SC.GameplayUtil

-- Gameplay fallbacks are intentionally centralized here. SC.Config values win
-- whenever the core configuration service is available.
local fallbackValues = {
    performancePerceptionUnitsPerFrame = 72,
    performanceNavigationNodesPerFrame = 64,
    performanceScavengeSquaresPerFrame = 28,
    performanceScavengeContainersPerFrame = 2,
    performanceFactionSamplesPerFrame = 12,
    performanceUrgentUnitFloor = 96,
    performanceCacheTtlMs = 75,
    perceptionRadius = 18,
    perceptionSquareBudget = 240,
    perceptionThreatLimit = 32,
    perceptionExitLimit = 16,
    perceptionAllyLimit = 16,
    perceptionIntervalMs = 500,
    immediateThreatRadius = 2.25,
    lastKnownThreatMs = 5000,
    soundMemoryMs = 8000,
    soundLimit = 16,
    escapeScanRadius = 5,
    navigationArrivalDistance = 0.6,
    navigationMicroDistance = 1.45,
    navigationNodeBudget = 220,
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
    navigationActorStateGraceMs = 900,
    navigationActorStateTimeoutMs = 12000,
    navigationCrowdPenalty = 9,
    navigationRecoveryAttempts = 3,
    navigationGoalResetDistance = 3.0,
    navigationReservationMs = 8000,
    navigationBreadcrumbLimit = 64,
    navigationEgressNodeBudget = 160,
    navigationEgressRadius = 18,
    navigationEgressRefreshMs = 2500,
    navigationCornerObserveMs = 350,
    navigationWeaponReadyHoldMs = 1200,
    navigationStairObserveMs = 450,
    navigationStairSpacing = 1.75,
    navigationChokeReservationMs = 1400,
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
    combatRetreatPressure = 3.5,
    combatFirearmMinDistance = 2.2,
    combatShoveDistance = 1.35,
    combatMeleeDistance = 1.7,
    combatMeleeReachMargin = 0.2,
    combatMeleeHoldFraction = 0.5,
    combatDecisionIntervalMs = 125,
    friendlyFire = false,
    friendlyFireCorridor = 0.8,
    combatAllySupportRadius = 6,
    combatAllySupportMax = 12,
    combatCloseThreatRadius = 4.5,
    combatTargetClaimPenalty = 42,
    combatRearThreatPriority = 30,
    combatFlankThreatPriority = 18,
    combatOverrunRisk = 62,
    combatOverrunRecoveryRisk = 38,
    combatOverrunHoldMs = 2600,
    combatMinimumEnduranceReserve = 0.18,
    combatMaximumEnduranceReserve = 0.62,
    combatHeavyWeaponWeight = 2.5,
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
    scavengeNoUsefulCooldownMs = 30000,
    scavengeSuccessCooldownMs = 4000,
    scavengeStatusHoldMs = 8000,
    scavengeMemoryLimit = 96,
    followIntervalMs = 167,
    followDistance = 3,
    followFarDistance = 18,
    followRecoveryDistance = 42,
    guardRadius = 5,
    guardPatrolIntervalMs = 30000,
    threatWarningCooldownMs = 15000,
    threatWarningGroupCooldownMs = 3500,
    threatWarningSoundRadius = 10,
    sharedAlertMemoryMs = 5000,
    zombieTargetScanIntervalMs = 350,
    zombieTargetRadius = 18,
    zombieTargetCloseNoticeRadius = 2.5,
    zombieTargetSwitchAdvantage = 0.75,
    zombieTargetMaxChecks = 128,
    zombieTargetMemoryFrames = 200,
    zombieAttackReach = 1.3,
    zombieAttackHoldRadius = 3.0,
    zombieAttackCooldownMs = 1600,
    zombieAttackMaxChecks = 64,
    zombieBiteChance = 0.25,
    zombieBiteDamage = 12,
    zombieScratchDamage = 6,
    zombieGrabThreshold = 2,
    zombieGrabReach = 1.6,
    zombieGrabChance = 0.5,
    zombieGrabAttemptCooldownMs = 500,
    zombieGrabEscapeChance = 0.2,
    zombieGrabMinDurationMs = 1500,
    zombieGrabGraceMs = 9000,
    zombieGrabDragIntervalMs = 900,
    zombieGrabBiteChance = 0.5,
    sharedAlertCloseRadius = 8,
    formationSeparation = 1.25,
    downtimeIntervalMs = 1500,
    downtimeSafeMs = 5000,
    downtimeReservationMs = 30000,
    downtimeActivityMs = 6000,
    ambientRepeatCooldownMs = 60000,
    dialogueDisplayMinMs = 8000,
    dialogueDisplayBaseMs = 5000,
    dialogueDisplayPerCharacterMs = 70,
    dialogueDisplayMaxMs = 15000,
    workReservationMs = 45000,
    workApproachTimeoutMs = 90000,
    decisionHysteresis = 8,
    decisionMinStateMs = 900,
    relationshipObservationIntervalMs = 1000,
    needsRateMultiplier = 0.5,
    needsRateSampleMs = 1000,
    needsNaturalDeltaLimit = 1.0,
    needsHungerThreshold = 0.55,
    needsHungerEmergency = 0.82,
    needsThirstThreshold = 0.48,
    needsThirstEmergency = 0.75,
    needsWaterSourceRadius = 12,
    needsWaterSquareBudget = 180,
    campStorageRadius = 24,
    campStorageSquareBudget = 220,
    campStorageItemBudget = 80,
    campStorageReservationMs = 20000,
    dangerSignalMaxDistance = 10,
    dangerSignalImmediateRadius = 4,
    diagnosticCooldownMs = 10000,
    circuitBreakerErrors = 3,
    circuitBreakerResetMs = 30000,
    maxCompanions = 16,
}

local readOnlyDefaults = {}
setmetatable(readOnlyDefaults, {
    __index = fallbackValues,
    __newindex = function()
        error("SurvivorCompanion gameplay defaults are immutable", 2)
    end,
    __metatable = false,
})
U.Defaults = readOnlyDefaults

local weakActorState = setmetatable({}, { __mode = "k" })
local circuitState = setmetatable({}, { __mode = "k" })
local globalCircuits = {}
local diagnostics = {}

local function packedArguments(...)
    return { n = select("#", ...), ... }
end

local function invoke(obj, methodName, args)
    if obj == nil then return false, nil end
    local okMethod, method = pcall(function() return obj[methodName] end)
    if not okMethod or type(method) ~= "function" then return false, nil end
    args = args or { n = 0 }
    local count = tonumber(args.n) or #args
    local ok, a, b, c, d = pcall(method, obj, unpack(args, 1, count))
    if not ok then return false, nil, tostring(a) end
    return true, a, b, c, d
end

function U.call(obj, methodName, ...)
    local ok, a, b, c, d = invoke(obj, methodName, packedArguments(...))
    return a, ok, b, c, d
end

function U.hasMethod(obj, methodName)
    if obj == nil then return false end
    local ok, value = pcall(function() return obj[methodName] end)
    return ok and type(value) == "function"
end

function U.nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime then
            local age, ageOk = U.call(gameTime, "getWorldAgeHours")
            if ageOk and type(age) == "number" then return math.floor(age * 3600000) end
        end
    end
    return math.floor((os.clock and os.clock() or 0) * 1000)
end

local function configLookup(key)
    local config = SC.Config
    if type(config) ~= "table" then return nil end
    if type(config.get) == "function" then
        local ok, value = pcall(config.get, key)
        if not ok then ok, value = pcall(config.get, config, key) end
        if ok and value ~= nil then return value end
    end
    if config.values and config.values[key] ~= nil then return config.values[key] end
    if config.defaults and config.defaults[key] ~= nil then return config.defaults[key] end
    if config[key] ~= nil and type(config[key]) ~= "function" then return config[key] end
    return nil
end

function U.config(key)
    local value = configLookup(key)
    if value ~= nil then return value end
    return fallbackValues[key]
end

function U.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function U.copyShallow(source)
    local target = {}
    if type(source) == "table" then
        for key, value in pairs(source) do target[key] = value end
    end
    return target
end

function U.actorState(actor, suppliedRuntime)
    if type(suppliedRuntime) == "table" then return suppliedRuntime end
    if actor == nil then return {} end
    local state = weakActorState[actor]
    if not state then
        state = {}
        weakActorState[actor] = state
    end
    return state
end

function U.peekActorState(actor)
    return actor and weakActorState[actor] or nil
end

function U.clearActorState(actor)
    if actor then
        weakActorState[actor] = nil
        circuitState[actor] = nil
    else
        weakActorState = setmetatable({}, { __mode = "k" })
        circuitState = setmetatable({}, { __mode = "k" })
        globalCircuits = {}
        diagnostics = {}
    end
end

function U.idOf(actor)
    if actor == nil then return nil end
    local modData, ok = U.call(actor, "getModData")
    if ok and type(modData) == "table" and type(modData.SC_Id) == "string" then
        return modData.SC_Id
    end
    local id, idOk = U.call(actor, "getOnlineID")
    if idOk and id ~= nil then return "runtime-" .. tostring(id) end
    return tostring(actor)
end

function U.stableHash(value)
    local textValue = tostring(value or "")
    local hash = 216613626
    for index = 1, #textValue do
        hash = (hash * 16777619 + string.byte(textValue, index)) % 2147483647
    end
    return hash
end

function U.isDue(actor, slot, intervalMs, now)
    if not actor or not slot or not intervalMs then return true end
    local runtime = U.actorState(actor)
    runtime.timers = runtime.timers or {}
    runtime.timerIntervals = runtime.timerIntervals or {}
    local current = now or U.nowMs()
    local due = runtime.timers[slot]
    if due == nil then
        local phase = U.stableHash(U.idOf(actor) .. ":" .. slot) % math.max(1, intervalMs)
        due = current - (current % intervalMs) + phase
        if due <= current then due = due + intervalMs end
        runtime.timers[slot] = due
        runtime.timerIntervals[slot] = intervalMs
        return false
    end
    local previousInterval = runtime.timerIntervals[slot]
    if previousInterval and intervalMs < previousInterval and due - current > intervalMs then
        due = current + intervalMs
        runtime.timers[slot] = due
    end
    runtime.timerIntervals[slot] = intervalMs
    if current < due then return false end
    runtime.timers[slot] = due + intervalMs
    if runtime.timers[slot] <= current then runtime.timers[slot] = current + intervalMs end
    return true
end

local function outputDiagnostic(textValue)
    if type(print) == "function" then print(textValue) end
end

function U.diagnostic(subsystem, actor, message)
    local key = tostring(subsystem) .. ":" .. tostring(U.idOf(actor) or "global")
    local now = U.nowMs()
    local nextAllowed = diagnostics[key] or 0
    if now < nextAllowed then return end
    diagnostics[key] = now + (U.config("diagnosticCooldownMs") or 10000)
    outputDiagnostic("[SurvivorCompanion/" .. tostring(subsystem) .. "] " .. tostring(message))
end

function U.safeSubsystem(subsystem, actor, callback)
    -- Core scheduler/runtime and gameplay modules share one circuit state when
    -- diagnostics is loaded.  Keep the local implementation only as a narrow
    -- standalone-test fallback for this utility module.
    if SC.Diagnostics and type(SC.Diagnostics.guard) == "function" then
        return SC.Diagnostics.guard(subsystem, U.idOf(actor), callback)
    end
    local now = U.nowMs()
    local bucket
    if actor then
        bucket = circuitState[actor]
        if not bucket then
            bucket = {}
            circuitState[actor] = bucket
        end
    else
        bucket = globalCircuits
    end
    local circuit = bucket[subsystem]
    if not circuit then
        circuit = { failures = 0, disabledUntil = 0 }
        bucket[subsystem] = circuit
    end
    if circuit.disabledUntil > now then return false, "disabled" end
    local ok, a, b, c = pcall(callback)
    if ok then
        circuit.failures = 0
        return true, a, b, c
    end
    circuit.failures = circuit.failures + 1
    U.diagnostic(subsystem, actor, a)
    if circuit.failures >= (U.config("circuitBreakerErrors") or 3) then
        circuit.disabledUntil = now + (U.config("circuitBreakerResetMs") or 30000)
        circuit.failures = 0
    end
    return false, a
end

function U.position(value)
    if value == nil then return nil end
    if type(value) == "table" and type(value.x) == "number" and type(value.y) == "number" then
        return value.x, value.y, value.z or 0
    end
    local x, xOk = U.call(value, "getX")
    local y, yOk = U.call(value, "getY")
    local z, zOk = U.call(value, "getZ")
    if xOk and yOk then return x, y, zOk and z or 0 end
    return nil
end

function U.squareOf(value)
    if value == nil then return nil end
    if type(value) == "table" and value.square ~= nil then return value.square end
    if U.hasMethod(value, "getSquare") then
        local square, ok = U.call(value, "getSquare")
        if ok and square ~= nil then return square end
    end
    if U.hasMethod(value, "getCurrentSquare") then
        local square, ok = U.call(value, "getCurrentSquare")
        if ok and square ~= nil then return square end
    end
    -- Native passengers legitimately have no ordinary current square. Their
    -- vehicle square remains the loaded origin for senses and safety checks.
    if U.hasMethod(value, "getVehicle") then
        local vehicle, vehicleOk = U.call(value, "getVehicle")
        if vehicleOk and vehicle ~= nil then
            local square, squareOk = U.call(vehicle, "getSquare")
            if squareOk and square ~= nil then return square end
        end
    end
    if U.hasMethod(value, "getX") and U.hasMethod(value, "isFree") then return value end
    return nil
end

function U.distanceSq(a, b)
    local ax, ay, az = U.position(a)
    local bx, by, bz = U.position(b)
    if not ax or not bx then return math.huge end
    local dx, dy = ax - bx, ay - by
    local dz = (az or 0) - (bz or 0)
    return dx * dx + dy * dy + dz * dz * 9
end

function U.distance(a, b)
    local value = U.distanceSq(a, b)
    if value == math.huge then return value end
    return math.sqrt(value)
end

function U.cell()
    if type(getCell) == "function" then
        local ok, cell = pcall(getCell)
        if ok then return cell end
    end
    return nil
end

function U.gridSquare(x, y, z)
    local cell = U.cell()
    if not cell then return nil end
    local square, ok = U.call(cell, "getGridSquare", math.floor(x), math.floor(y), math.floor(z or 0))
    if ok then return square end
    return nil
end

function U.loadedSquare(target)
    local square = U.squareOf(target)
    if square then return square end
    local x, y, z = U.position(target)
    if x then return U.gridSquare(x, y, z) end
    return nil
end

function U.listSize(list)
    return SC.NativeList.size(list)
end

function U.listGet(list, index)
    local value = SC.NativeList.get(list, index)
    return value
end

function U.each(list, limit, callback)
    local count = math.min(U.listSize(list), limit or math.huge)
    for index = 0, count - 1 do
        local value = U.listGet(list, index)
        if value ~= nil and callback(value, index) == false then break end
    end
end

function U.instanceOf(value, className)
    if value == nil then return false end
    if type(instanceof) == "function" then
        local ok, result = pcall(instanceof, value, className)
        if ok then return result == true end
    end
    if type(value) == "table" then
        return value.__class == className or value.className == className
    end
    return false
end

function U.isZombie(value)
    if value == nil then return false end
    if U.instanceOf(value, "IsoZombie") then return true end
    local zombie, ok = U.call(value, "isZombie")
    return ok and zombie == true
end

function U.isDead(value)
    if value == nil then return true end
    local dead, ok = U.call(value, "isDead")
    if ok then return dead == true end
    local health, healthOk = U.call(value, "getHealth")
    return healthOk and type(health) == "number" and health <= 0
end

function U.nativeHealth(value)
    if value == nil then return 0 end
    local body, bodyOk = U.call(value, "getBodyDamage")
    if bodyOk and body then
        local health, healthOk = U.call(body, "getHealth")
        if healthOk and type(health) == "number" then return health end
    end
    local health, healthOk = U.call(value, "getHealth")
    if healthOk and type(health) == "number" then return health end
    return 100
end

function U.isValidActor(actor)
    if actor == nil or U.isDead(actor) then return false end
    local square = U.squareOf(actor)
    return square ~= nil
end

function U.isCompanion(actor)
    local actorService = SC.Actor
    if type(actorService) ~= "table" or type(actorService.isCompanion) ~= "function" then return false end
    local ok, result = pcall(actorService.isCompanion, actor)
    if not ok then ok, result = pcall(actorService.isCompanion, actorService, actor) end
    return ok and result == true
end

function U.stop(actor)
    local actorService = SC.Actor
    if type(actorService) ~= "table" or type(actorService.stop) ~= "function" then return false end
    local ok, result = pcall(actorService.stop, actor)
    if not ok then ok, result = pcall(actorService.stop, actorService, actor) end
    return ok and result == true
end

function U.move(actor, mode, intent)
    local actorService = SC.Actor
    if type(actorService) ~= "table" or type(actorService.setMovement) ~= "function" then
        return false, "actor_executor_unavailable"
    end
    local safeIntent = type(intent) == "table" and intent or { action = intent }
    safeIntent.humanAnimationOnly = true
    local ok, result, reason = pcall(actorService.setMovement, actor, mode, safeIntent)
    if not ok then
        ok, result, reason = pcall(actorService.setMovement, actorService, actor, mode, safeIntent)
    end
    if not ok then return false, tostring(result) end
    return result == true, reason
end

function U.modData(value)
    local data, ok = U.call(value, "getModData")
    if ok and type(data) == "table" then return data end
    if type(value) == "table" then
        value.__modData = value.__modData or {}
        return value.__modData
    end
    return nil
end

function U.objectLabel(object)
    if object == nil then return "none" end
    for _, methodName in ipairs({ "getObjectName", "getType", "getName" }) do
        local value, ok = U.call(object, methodName)
        if ok and value ~= nil and tostring(value) ~= "" then
            return tostring(value):gsub("[%c]", " ")
        end
    end
    if type(object) == "table" then
        return tostring(object.__class or object.className or object.type or "table")
    end
    return tostring(object):gsub("[%c]", " ")
end

function U.squareStaticBlocker(square)
    if not square then return nil, "missing_square" end
    local solid, solidOk = U.call(square, "isSolid")
    if solidOk and solid then return square, "solid_square" end
    local found, kind
    U.squareObjects(square, function(object)
        local moved, movedOk = U.call(object, "isMovedThumpable")
        if movedOk and moved == true then
            found, kind = object, "moved_object"
            return false
        end
        local blockAll, blockOk = U.call(object, "isBlockAllTheSquare")
        local thumpable, thumpOk = U.call(object, "isThumpable")
        local stairs, stairsOk = U.call(object, "isStairsObject")
        if blockOk and blockAll == true and (not stairsOk or stairs ~= true)
            and (not thumpOk or thumpable == true or U.instanceOf(object, "IsoThumpable")) then
            found, kind = object, "full_square_thumpable"
            return false
        end
    end, 64)
    if found then return found, kind end
    local floor, floorOk = U.call(square, "TreatAsSolidFloor")
    if floorOk and not floor then return square, "missing_floor" end
    return nil, nil
end

function U.movingBlocker(square, actor)
    local found, kind
    U.squareMovingObjects(square, function(other)
        if other ~= actor and not U.isDead(other) then
            found = other
            if U.isZombie(other) then kind = "zombie_crowd"
            elseif U.isCompanion(other) then kind = "companion_crowd"
            elseif U.instanceOf(other, "IsoPlayer") then kind = "player_crowd"
            elseif U.instanceOf(other, "IsoAnimal") or U.hasMethod(other, "isAnimal") then
                local animal, ok = U.call(other, "isAnimal")
                kind = (not ok or animal == true) and "animal_crowd" or "actor_crowd"
            else kind = "actor_crowd" end
            return false
        end
    end, 24)
    return found, kind
end

function U.movementStateBlocker(actor)
    if not actor then return nil end
    local checks = {
        { "isKnockedDown", "knocked_down" },
        { "isClimbing", "climbing" },
        { "isBlockMovement", "movement_locked" },
    }
    for _, check in ipairs(checks) do
        local value, ok = U.call(actor, check[1])
        if ok and value == true then return check[2] end
    end
    local current, currentOk = U.call(actor, "getCurrentState")
    if currentOk and current ~= nil then
        local name
        if type(getClassSimpleName) == "function" then
            local ok, value = pcall(getClassSimpleName, current)
            if ok then name = tostring(value) end
        end
        name = name or U.objectLabel(current)
        local lower = string.lower(name)
        if string.find(lower, "collidewithwall", 1, true) then return "wall_collision_state", current end
        if string.find(lower, "climb", 1, true) then return "climbing", current end
        if string.find(lower, "knock", 1, true) or string.find(lower, "getup", 1, true) then
            return "knocked_down", current
        end
        if string.find(lower, "playeractions", 1, true) then
            return "action_animation_state", current
        end
    end
    local actions, actionsOk = U.call(actor, "getCharacterActions")
    if actionsOk and actions ~= nil then
        local size, sizeOk = U.call(actions, "size")
        if sizeOk and type(size) == "number" and size > 0 then
            return "unfinished_action", actions
        end
        if type(actions) == "table" and #actions > 0 then
            return "unfinished_action", actions[1]
        end
    end
    return nil
end

function U.safehouseBlocker(square, actor)
    local multiplayer = false
    if type(isClient) == "function" then
        local ok, value = pcall(isClient)
        multiplayer = ok and value == true
    end
    if not multiplayer and type(isServer) == "function" then
        local ok, value = pcall(isServer)
        multiplayer = ok and value == true
    end
    if not multiplayer or SafeHouse == nil then return false end
    local okMethod, method = pcall(function() return SafeHouse.isSafehouseAllowTrepass end)
    if not okMethod or type(method) ~= "function" then return false end
    local ok, allowed = pcall(method, square, actor)
    if not ok then ok, allowed = pcall(method, SafeHouse, square, actor) end
    return ok and allowed ~= true
end

function U.isSquareFree(square)
    if not square then return false end
    return U.squareStaticBlocker(square) == nil
end

-- Keep faction, encounter and restore placement in lockstep with the native
-- bridge's SCBridge.validSpawnSquare contract.  isSquareFree() is a movement
-- convenience check; it deliberately does not prove that a native actor may
-- be constructed on the square.
function U.isSafeSpawnSquare(square)
    if not square then return false, "square_unavailable" end
    local cell, cellOk = U.call(square, "getCell")
    if not cellOk or cell == nil then return false, "cell_unloaded" end
    local chunk, chunkOk = U.call(square, "getChunk")
    if not chunkOk or chunk == nil then return false, "chunk_unloaded" end
    local solid, solidOk = U.call(square, "isSolid")
    if not solidOk or solid == true then return false, "solid" end
    local transparentSolid, transparentOk = U.call(square, "isSolidTrans")
    if not transparentOk or transparentSolid == true then return false, "solid_transparent" end
    local floor, floorOk = U.call(square, "TreatAsSolidFloor")
    if not floorOk or floor ~= true then return false, "missing_floor" end
    local free, freeOk = U.call(square, "isFree", true)
    if not freeOk or free ~= true then return false, "occupied" end
    local safe, safeOk = U.call(square, "isSafeToSpawn")
    if not safeOk or safe ~= true then return false, "unsafe_to_spawn" end
    return true, "safe"
end

function U.edgeBlocked(fromSquare, toSquare)
    if not fromSquare or not toSquare then return true end
    local blocked, ok = U.call(fromSquare, "isBlockedTo", toSquare)
    if ok then return blocked == true end
    return false
end

function U.canSee(observer, target)
    if not observer or not target then return false end
    local observerSquare = U.squareOf(observer)
    local targetSquare = U.squareOf(target)
    if not observerSquare or not targetSquare then return false end
    local _, _, observerZ = U.position(observerSquare)
    local _, _, targetZ = U.position(targetSquare)
    if math.floor(observerZ or 0) ~= math.floor(targetZ or 0) then return false end

    local targetIsSquare = U.hasMethod(target, "isFree") and not U.hasMethod(target, "getSquare")
    if not targetIsSquare then
        local visible, ok = U.call(observer, "CanSee", target)
        return ok and visible == true
    end

    local los = LosUtil
    if los == nil then return false end
    local lineClear
    local okMethod, method = pcall(function() return los.lineClear end)
    if okMethod and type(method) == "function" then lineClear = method end
    if not lineClear then return false end
    local ox, oy, oz = U.position(observerSquare)
    local tx, ty, tz = U.position(targetSquare)
    local cell = U.cell()
    if not ox or not tx or not cell then return false end
    local ok, result = pcall(
        lineClear,
        cell,
        math.floor(ox), math.floor(oy), math.floor(oz or 0),
        math.floor(tx), math.floor(ty), math.floor(tz or 0),
        false
    )
    if not ok or result == nil then return false end
    local resultName = string.lower(tostring(result))
    if resultName == "clear" or string.match(resultName, "%.clear$") then return true end
    if string.find(resultName, "clearthroughopendoor", 1, true)
        or string.find(resultName, "clearthroughwindow", 1, true) then return true end
    return false
end

function U.characterStatValue(actor, statName, fallback)
    local stats, statsOk = U.call(actor, "getStats")
    if not statsOk or not stats then return fallback end
    local enumTable = CharacterStat
    if enumTable == nil then return fallback end
    local enumOk, enumValue = pcall(function() return enumTable[statName] end)
    if not enumOk or enumValue == nil then return fallback end
    local value, valueOk = U.call(stats, "get", enumValue)
    if valueOk and type(value) == "number" then return value end
    return fallback
end

-- Build 42 exposes perks and moodles as enum-indexed APIs. Keep the enum
-- lookup and Java-call failure contained here so gameplay systems can use
-- genuine character capability without becoming brittle in headless tests or
-- during a game update where an enum is temporarily unavailable.
function U.perkLevel(actor, perkName, fallback)
    local perkTable = type(_G) == "table" and rawget(_G, "Perks") or nil
    if perkTable == nil then return fallback or 0 end
    local ok, perk = pcall(function() return perkTable[perkName] end)
    if not ok or perk == nil then return fallback or 0 end
    local value, valueOk = U.call(actor, "getPerkLevel", perk)
    if valueOk and type(value) == "number" then return value end
    return fallback or 0
end

function U.moodleLevel(actor, moodleName, fallback)
    local moodleTable = type(_G) == "table" and rawget(_G, "MoodleType") or nil
    if moodleTable == nil then return fallback or 0 end
    local ok, moodle = pcall(function() return moodleTable[moodleName] end)
    if not ok or moodle == nil then return fallback or 0 end
    local moodles, moodlesOk = U.call(actor, "getMoodles")
    if not moodlesOk or moodles == nil then return fallback or 0 end
    local value, valueOk = U.call(moodles, "getMoodleLevel", moodle)
    if valueOk and type(value) == "number" then return value end
    return fallback or 0
end

function U.sameFloor(a, b)
    local _, _, az = U.position(a)
    local _, _, bz = U.position(b)
    if az == nil or bz == nil then return false end
    return math.floor(az) == math.floor(bz)
end

function U.squareObjects(square, callback, limit)
    if not square then return end
    local objects, ok = U.call(square, "getObjects")
    if ok then U.each(objects, limit or 48, callback) end
end

function U.squareSpecialObjects(square, callback, limit)
    if not square then return end
    local objects, ok = U.call(square, "getSpecialObjects")
    if ok then U.each(objects, limit or 48, callback) end
end

function U.squareMovingObjects(square, callback, limit)
    if not square then return end
    local objects, ok = U.call(square, "getMovingObjects")
    if ok then U.each(objects, limit or 16, callback) end
end

function U.squareStaticMovingObjects(square, callback, limit)
    if not square then return end
    local objects, ok = U.call(square, "getStaticMovingObjects")
    if ok then U.each(objects, limit or 16, callback) end
end

function U.inventory(actor)
    local inventory, ok = U.call(actor, "getInventory")
    if ok then return inventory end
    return nil
end

function U.inventoryItems(inventory, limit)
    if inventory == nil then return {} end
    local items, ok = U.call(inventory, "getItems")
    if not ok then items = inventory.items or inventory end
    local result = {}
    U.each(items, limit or 80, function(item)
        result[#result + 1] = item
    end)
    return result
end

function U.inventoryContains(inventory, item)
    if not inventory or not item then return false end
    local contains, containsOk = U.call(inventory, "contains", item)
    if containsOk then return contains == true end
    for _, value in ipairs(U.inventoryItems(inventory, 160)) do
        if value == item then return true end
    end
    return false
end

function U.itemType(item)
    local fullType, ok = U.call(item, "getFullType")
    if ok and fullType then return tostring(fullType) end
    local itemType, typeOk = U.call(item, "getType")
    if typeOk and itemType then return tostring(itemType) end
    return type(item) == "table" and (item.fullType or item.type) or ""
end

function U.itemName(item)
    local name, ok = U.call(item, "getDisplayName")
    if ok and name then return tostring(name) end
    return U.itemType(item)
end

function U.itemWeight(item)
    if item == nil then return 0 end
    local value, ok = U.call(item, "getActualWeight")
    if not ok or type(value) ~= "number" then value, ok = U.call(item, "getWeight") end
    if not ok or type(value) ~= "number" then value, ok = U.call(item, "getUnequippedWeight") end
    value = ok and tonumber(value) or nil
    if value == nil or value ~= value or value < 0 then return 0 end
    return value
end

-- Build 42's encumbrance checks compare ItemContainer:getCapacityWeight()
-- against getEffectiveCapacity(character). Keep that exact contract here so
-- AI decisions agree with vanilla movement and transfer rules.
function U.inventoryLoad(actor)
    local inventory = U.inventory(actor)
    if not inventory then return 0, 0, 0, nil end
    local weight, weightOk = U.call(inventory, "getCapacityWeight")
    local capacity, capacityOk = U.call(inventory, "getEffectiveCapacity", actor)
    if not capacityOk or type(capacity) ~= "number" or capacity <= 0 then
        capacity, capacityOk = U.call(actor, "getMaxWeight")
    end
    if not capacityOk or type(capacity) ~= "number" or capacity <= 0 then
        capacity, capacityOk = U.call(inventory, "getMaxWeight")
    end
    if not weightOk or type(weight) ~= "number" then
        weight = 0
        for _, item in ipairs(U.inventoryItems(inventory, U.config("logisticsInventoryItemBudget") or 256)) do
            weight = weight + U.itemWeight(item)
        end
    end
    capacity = capacityOk and tonumber(capacity) or 0
    if capacity <= 0 then return weight, 0, 0, inventory end
    return weight, capacity, weight / capacity, inventory
end

local function normalizedTagName(value)
    if value == nil then return nil end
    local text = string.lower(tostring(value))
    local tail = string.match(text, "[^:%.]+$") or text
    return string.gsub(tail, "[^%w]", "")
end

function U.itemHasTag(item, tag)
    if item == nil or tag == nil then return false end

    -- Build 42.20.4 exposes InventoryItem.hasTag overloads that accept ItemTag,
    -- not a Lua string. A failed string overload can poison Kahlua's pooled
    -- MethodArguments and make later, unrelated calls fail in ReturnValues.put.
    -- Iterate the stable Set<ItemTag> API instead.
    local wanted = normalizedTagName(tag)
    local tags, tagsOk = U.call(item, "getTags")
    if tagsOk and tags ~= nil then
        local iterator, iteratorOk = U.call(tags, "iterator")
        if iteratorOk and iterator ~= nil then
            for _ = 1, 256 do
                local hasNext, hasNextOk = U.call(iterator, "hasNext")
                if not hasNextOk or hasNext ~= true then break end
                local itemTag, nextOk = U.call(iterator, "next")
                if not nextOk or itemTag == nil then break end
                local name, nameOk = U.call(itemTag, "getTranslationName")
                if (nameOk and normalizedTagName(name) == wanted)
                    or normalizedTagName(itemTag) == wanted then
                    return true
                end
            end
        end
        return false
    end

    -- Test fixtures and intentionally Lua-backed adapters may retain the old
    -- string helper. Never take this path for live Java userdata.
    if type(item) == "table" then
        local value, ok = U.call(item, "hasTag", tag)
        if ok then return value == true end
    end
    local lowered = string.lower(U.itemType(item))
    return string.find(lowered, string.lower(tostring(tag)), 1, true) ~= nil
end

function U.consumeItem(inventory, item)
    if not item then return false end
    local usesBefore, usesOk = U.call(item, "getUses")
    local used, useOk = U.call(item, "Use")
    if useOk then
        if used == false then return false end
        if inventory and not U.inventoryContains(inventory, item) then return true end
        local usesAfter, afterOk = U.call(item, "getUses")
        if usesOk and afterOk and type(usesBefore) == "number" and type(usesAfter) == "number" then
            return usesAfter < usesBefore
        end
        return true
    end
    if inventory then
        local removed, removeOk = U.call(inventory, "Remove", item)
        if removeOk then return removed ~= false and not U.inventoryContains(inventory, item) end
    end
    if type(inventory) == "table" and type(inventory.items) == "table" then
        for index, value in ipairs(inventory.items) do
            if value == item then table.remove(inventory.items, index) return true end
        end
    end
    return false
end

function U.addItem(inventory, itemOrType)
    if inventory == nil then return nil, "inventory_unavailable" end
    local item, ok, failure = U.call(inventory, "AddItem", itemOrType)
    if ok and item ~= nil then return item end
    if ok then return nil, "add_item_returned_nil" end
    if type(inventory) == "table" then
        inventory.items = inventory.items or {}
        local value = type(itemOrType) == "table" and itemOrType or { type = itemOrType, fullType = itemOrType }
        inventory.items[#inventory.items + 1] = value
        return value
    end
    return nil, tostring(failure or "add_item_call_failed")
end

-- Build 42 ItemContainer:Remove(InventoryItem) returns void.  The only safe
-- transaction receipt is therefore the exact item's membership before and
-- after each operation.  Keep this synchronous so no decision can observe the
-- item between removal and either destination verification or rollback.
function U.transferItemVerified(source, destination, item)
    if not source or not destination or not item then
        return false, "invalid_transfer"
    end
    if source == destination then return false, "same_container" end
    if not U.inventoryContains(source, item) then
        if U.inventoryContains(destination, item) then
            return true, "already_transferred", {
                item = item, itemType = U.itemType(item), itemName = U.itemName(item),
                source = source, destination = destination, idempotent = true,
            }
        end
        return false, "source_missing"
    end
    if U.inventoryContains(destination, item) then
        return false, "destination_already_contains_item"
    end

    local _, removeCalled = U.call(source, "Remove", item)
    local removed = removeCalled and not U.inventoryContains(source, item)
    if not removeCalled and type(source) == "table" and type(source.items) == "table" then
        for index, value in ipairs(source.items) do
            if value == item then
                table.remove(source.items, index)
                removed = not U.inventoryContains(source, item)
                break
            end
        end
    end
    if not removed then return false, "source_remove_failed" end

    U.addItem(destination, item)
    if U.inventoryContains(destination, item) and not U.inventoryContains(source, item) then
        return true, "transferred", {
            item = item, itemType = U.itemType(item), itemName = U.itemName(item),
            source = source, destination = destination, idempotent = false,
        }
    end

    -- A hostile or capacity-constrained destination may reject AddItem. Remove
    -- any partial destination reference before restoring the exact object.
    if U.inventoryContains(destination, item) then U.call(destination, "Remove", item) end
    U.addItem(source, item)
    if U.inventoryContains(source, item) and not U.inventoryContains(destination, item) then
        return false, "destination_add_failed_rolled_back"
    end
    return false, "transfer_rollback_failed"
end

function U.transferItem(source, destination, item)
    return U.transferItemVerified(source, destination, item)
end

-- Transactional ground drop. The item is restored to its source if the world
-- object cannot be created, so load shedding can never silently delete gear.
function U.dropItem(source, square, item, xOffset, yOffset, zOffset)
    if not source or not square or not item or not U.inventoryContains(source, item) then
        return false, "invalid_drop"
    end
    local removeResult, removeCalled = U.call(source, "Remove", item)
    local removed = removeCalled and removeResult ~= false and not U.inventoryContains(source, item)
    if not removed then return false, "drop_remove_failed" end
    local worldItem, added = U.call(square, "AddWorldInventoryItem", item,
        tonumber(xOffset) or 0.5, tonumber(yOffset) or 0.5,
        tonumber(zOffset) or 0, false)
    if added and worldItem ~= nil then return true, worldItem end
    U.addItem(source, item)
    return false, "drop_world_add_failed"
end

function U.nameOf(actor)
    -- IsoPlayer's display name is an account/local-player label. Non-local
    -- companions can all inherit the same default (commonly "Bob"), even
    -- though their SurvivorDesc identities are distinct. Prefer that identity.
    local descriptor, descOk = U.call(actor, "getDescriptor")
    if descOk and descriptor then
        local first, firstOk = U.call(descriptor, "getForename")
        local last, lastOk = U.call(descriptor, "getSurname")
        local textName = ((firstOk and first) and tostring(first) or "") .. " " .. ((lastOk and last) and tostring(last) or "")
        textName = string.gsub(textName, "^%s+", "")
        textName = string.gsub(textName, "%s+$", "")
        if textName ~= "" then return textName end
    end
    local displayName, displayOk = U.call(actor, "getDisplayName")
    if displayOk and displayName and tostring(displayName) ~= "" then return tostring(displayName) end
    return "Survivor"
end

function U.say(actor, textValue)
    if actor == nil or textValue == nil then return false end
    if not U.isCompanion(actor) then return false end
    local line = tostring(textValue)
    local minimum = tonumber(U.config("dialogueDisplayMinMs")) or 8000
    local maximum = math.max(minimum, tonumber(U.config("dialogueDisplayMaxMs")) or 15000)
    local base = tonumber(U.config("dialogueDisplayBaseMs")) or 5000
    local perCharacter = tonumber(U.config("dialogueDisplayPerCharacterMs")) or 70
    local duration = math.floor(math.max(minimum,
        math.min(maximum, base + #line * perCharacter)))
    -- Owned native companions extend the newest actor-local line using a
    -- real-time clock. Older/test providers simply ignore this optional hook.
    U.call(actor, "setCompanionSpeechDisplayMillis", duration)
    -- IsoPlayer:Say routes through ChatManager's player branch. A non-local
    -- IsoPlayer can therefore inherit the local player's overhead bubble.
    -- Write to this character's own ChatElement first so both the text and its
    -- screen anchor stay on the companion actor.
    local _, actorChatOk = U.call(actor, "addLineChatElement", line)
    if actorChatOk then return true end
    local _, ok = U.call(actor, "Say", line)
    if ok then return true end
    local _, lowerOk = U.call(actor, "say", line)
    return lowerOk
end

function U.text(key, fallback, ...)
    if type(getText) == "function" then
        local args = { ... }
        local ok, value = pcall(getText, key, unpack(args))
        if ok and value and value ~= key then return tostring(value) end
    end
    return fallback or key
end

function U.registryLiving(limit)
    local registry = SC.Registry
    if type(registry) ~= "table" or type(registry.living) ~= "function" then return {} end
    local ok, living = pcall(registry.living)
    if not ok then ok, living = pcall(registry.living, registry) end
    if not ok or living == nil then return {} end
    local result = {}
    local maximum = limit or U.config("maxCompanions") or 16
    if type(living) == "table" and #living == 0 then
        for _, entry in pairs(living) do
            local actor = type(entry) == "table" and entry.actor or entry
            if actor then result[#result + 1] = actor end
            if #result >= maximum then break end
        end
    else
        U.each(living, maximum, function(entry)
            result[#result + 1] = type(entry) == "table" and entry.actor or entry
        end)
    end
    return result
end

function U.resolveActor(id)
    local registry = SC.Registry
    if type(registry) ~= "table" or type(registry.byId) ~= "function" then return nil, nil end
    local ok, entry = pcall(registry.byId, id)
    if not ok then ok, entry = pcall(registry.byId, registry, id) end
    if not ok or entry == nil then return nil, nil end
    if type(entry) == "table" and entry.actor ~= nil then return entry.actor, entry end
    return entry, nil
end

function U.squareKey(square)
    local x, y, z = U.position(square)
    if not x then return nil end
    return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y)) .. ":" .. tostring(math.floor(z or 0))
end

function U.pointSegmentDistanceSq(point, startPoint, endPoint)
    local px, py, pz = U.position(point)
    local ax, ay, az = U.position(startPoint)
    local bx, by, bz = U.position(endPoint)
    if not px or not ax or not bx then return math.huge end
    if math.floor(az or 0) ~= math.floor(bz or 0)
        or math.floor(pz or 0) ~= math.floor(az or 0) then return math.huge end
    local dx, dy = bx - ax, by - ay
    local lengthSq = dx * dx + dy * dy
    if lengthSq <= 0.0001 then
        local qx, qy = px - ax, py - ay
        return qx * qx + qy * qy
    end
    local t = ((px - ax) * dx + (py - ay) * dy) / lengthSq
    t = U.clamp(t, 0, 1)
    local qx, qy = px - (ax + t * dx), py - (ay + t * dy)
    return qx * qx + qy * qy
end

function U.sortByScoreDescending(values)
    table.sort(values, function(a, b)
        if a.score == b.score then return tostring(a.kind or "") < tostring(b.kind or "") end
        return a.score > b.score
    end)
    return values
end

return U
