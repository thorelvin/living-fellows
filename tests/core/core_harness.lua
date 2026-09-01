-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
check(type(SC) == "table" and SC.Identity.saveKey == "SC_SaveV1", "namespace identity")
do
    local values = SC.Call.pack(SC.Call.protected(function()
        return "first", nil, "third", nil
    end))
    check(values.n == 5 and values[1] == true and values[2] == "first"
            and values[3] == nil and values[4] == "third" and values[5] == nil,
        "protected calls preserve sparse and trailing return values exactly")
    local exact = { one = 1, two = 2, three = 3 }
    local copied, copyReason = SC.StableValue.copyStrict(exact, {
        maxDepth = 2, maxEntries = 4, path = "$.exact",
    })
    local rejected, rejectReason = SC.StableValue.copyStrict(exact, {
        maxDepth = 2, maxEntries = 3, path = "$.over",
    })
    check(copied and copied.three == 3 and copyReason == nil and rejected == nil
            and string.find(tostring(rejectReason), "limit exceeded", 1, true),
        "strict stable copies succeed at the exact boundary and reject one over")
end
local immutable = pcall(function() SC.Config.defaults.frameBudgetMs = 99 end)
check(not immutable and SC.Config.get("frameBudgetMs") == 2, "configuration is immutable")
do
    local priorSandbox = SandboxVars
    SandboxVars = { LivingFellows = {
        EncountersEnabled = false, EncounterFrequency = 4, MaxCompanions = 9,
        CompanionNeedsRate = 0.75, HouseholdSpawnsEnabled = false,
        HouseholdDailyChance = 17, MaxHouseholds = 1, UIOpacity = 0.44,
    } }
    local refreshed = SC.Config.refreshSandbox()
    check(refreshed and SC.Config.get("productionEncounterEnabled") == false
        and SC.Config.get("productionSpawnCooldownMs") == 120000
        and SC.Config.get("maxCompanions") == 9
        and SC.Config.get("needsRateMultiplier") == 0.75
        and SC.Config.get("factionEnabled") == false
        and SC.Config.get("factionDailySpawnChancePercent") == 17
        and SC.Config.get("factionMaxHouseholds") == 1
        and SC.Config.get("uiPanelOpacity") == 0.44,
        "sandbox options override the single canonical runtime configuration")
    SandboxVars = priorSandbox
    SC.Config.refreshSandbox()
    check(SC.Config.get("maxCompanions") == 16 and SC.Config.get("factionMaxHouseholds") == 3,
        "sandbox refresh clears stale overrides when no options are available")
end

local scheduled = 0
local schedulerClock = 0
SC.Scheduler._setClock(function() return schedulerClock end)
check(SC.Scheduler.register("core-test", 10, 5, function() scheduled = scheduled + 1 end),
    "scheduler accepts a valid task")
SC.Scheduler.tick()
schedulerClock = 10
SC.Scheduler.tick()
check(scheduled == 1, "scheduler invokes due task once")
check(not SC.Scheduler.dueFor("sc-a", "sense", 100, 0), "stable staggering defers initial lane")

do
    for _ = 1, 3 do
        SC.Diagnostics.guard("breaker-test", "sc-a", function() error("injected failure") end)
    end
    check(SC.Diagnostics.isDisabled("breaker-test", "sc-a"), "circuit breaker opens")
    local breakerClock = SC_TEST_CLOCK
    SC_TEST_CLOCK = SC_TEST_CLOCK + SC.Config.get("runtime", "circuitBreakerResetMs") + 1
    check(not SC.Diagnostics.isDisabled("breaker-test", "sc-a"),
        "circuit breaker becomes half-open after its reset window")
    local recovered, recoveredValue = SC.Diagnostics.guard("breaker-test", "sc-a",
        function() return "recovered" end)
    local recoveredSnapshot = SC.Diagnostics.snapshot()["breaker-test:sc-a"]
    check(recovered and recoveredValue == "recovered" and recoveredSnapshot.state == "closed"
        and recoveredSnapshot.consecutiveFailures == 0 and recoveredSnapshot.recoveries == 1,
        "successful half-open probe closes and resets the circuit")
    for _ = 1, 4 do SC.Diagnostics.report("notice-test", "sc-a", "ordinary warning") end
    check(not SC.Diagnostics.isDisabled("notice-test", "sc-a"),
        "ordinary diagnostics do not disable a runtime subsystem")
    SC_TEST_CLOCK = breakerClock
end

local function actionList()
    local list = { values = {} }
    function list:add(value) self.values[#self.values + 1] = value end
    function list:size() return #self.values end
    function list:contains(value)
        for _, candidate in ipairs(self.values) do if candidate == value then return true end end
        return false
    end
    function list:remove(value)
        for index, candidate in ipairs(self.values) do
            if candidate == value then table.remove(self.values, index) return true end
        end
        return false
    end
    return list
end

local square = { x = 0, y = 0, z = 0 }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end

local actor = {
    __owned = true,
    __class = "IsoPlayer",
    data = {},
    square = square,
    forwardX = 1,
    forwardY = 0,
    characterActions = actionList(),
}
function actor:getModData() return self.data end
function actor:isDead() return self.dead == true end
function actor:isOnDeathDone() return self.deathDone == true end
function actor:getSquare() return self.square end
function actor:getCurrentSquare() return self.square end
function actor:getX() return self.px or (self.square.x + 0.5) end
function actor:getY() return self.py or (self.square.y + 0.5) end
function actor:getZ() return self.square.z end
function actor:getInventory()
    return { getItems = function() return {} end }
end
local actorBody = {}
function actorBody:getHealth() return 100 end
function actorBody:getOverallBodyHealth() return 100 end
function actorBody:isInfected() return false end
function actor:getBodyDamage()
    return not self.bodyUnavailable and actorBody or nil
end
function actor:getMoodles() return {} end
function actor:getXp() return {} end
function actor:getEmitter() return {} end
function actor:getVisual() return {} end
function actor:getForwardDirectionX() return self.forwardX end
function actor:getForwardDirectionY() return self.forwardY end
function actor:faceLocationF(x, y)
    local dx, dy = x - self:getX(), y - self:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    self.forwardX, self.forwardY = dx / length, dy / length
    self.turning = true
    return true
end
function actor:playEmote(emote) self.lastEmote = emote return true end
function actor:isTurning() return self.turning == true end
function actor:getCharacterActions() return self.characterActions end
function actor:reportEvent(event)
    self.lastEvent = event
    if event == "EventSitOnGround" then self.groundSitting = true end
end
function actor:getVehicle() return self.vehicle end
function actor:canStandAt() return true end
function actor:isCompanionMovementClear()
    return self.continuousCollisionBlocked ~= true
end
function actor:setForwardDirection(x, y) self.forwardX, self.forwardY = x, y end
function actor:setRunning(value) self.running = value end
function actor:setSprinting(value) self.sprinting = value end
function actor:setSneaking(value)
    self.sneakSetCalls = (self.sneakSetCalls or 0) + 1
    self.sneaking = value
end
function actor:isRunning() return self.running == true end
function actor:isSprinting() return self.sprinting == true end
function actor:isSneaking() return self.sneaking == true end
function actor:setMoving(value) self.moving = value end
function actor:isMoving() return self.moving == true end
function actor:setIsAiming(value) self.aiming = value == true end
function actor:isAiming() return self.aiming == true end
function actor:setCompanionTacticalMovement(enabled, strafeX, strafeY)
    self.tacticalMovement = enabled == true
    self.strafeX = tonumber(strafeX) or 0
    self.strafeY = tonumber(strafeY) or 0
    self.aiming = enabled == true
    return true
end
function actor:setReading(value) self.reading = value == true end
function actor:faceThisObject(value)
    if value and value.getX and value.getY then return self:faceLocationF(value:getX(), value:getY()) end
    return false
end
function actor:MoveForward(distance, x, y)
    self.px = self:getX() + x * distance
    self.py = self:getY() + y * distance
end
function actor:setPrimaryHandItem(item) self.primaryHand = item end
function actor:getPrimaryHandItem() return self.primaryHand end
function actor:setSecondaryHandItem(item) self.secondaryHand = item end
function actor:getSecondaryHandItem() return self.secondaryHand end
function actor:setAimAtFloor(value) self.aimAtFloor = value end
function actor:setDoShove(value) self.doShove = value == true end
function actor:isDoShove() return self.doShove == true end
function actor:setDoGrapple(value) self.doGrapple = value == true end
function actor:isDoGrapple() return self.doGrapple == true end
function actor:setAuthorizeShoveStomp(value) self.authorizedHandToHand = value == true end
function actor:setAuthorizedHandToHandAction(value)
    self.authorizedHandToHandAction = value == true
end
function actor:isAuthorizedHandToHandAction()
    if self.authorizedHandToHandAction == nil then return true end
    return self.authorizedHandToHandAction == true
end
function actor:setAuthorizedHandToHand(value) self.authorizedHandToHand = value == true end
function actor:isAuthorizedHandToHand()
    if self.authorizedHandToHand == nil then return true end
    return self.authorizedHandToHand == true
end
function actor:setAttackType(value) self.attackType = value end
function actor:CanAttack()
    self.canAttackCalls = (self.canAttackCalls or 0) + 1
    if self.attackStarted == true or self.attackModelReady == false then return false end
    self.useHandWeapon = self.primaryHand
    return true
end
function actor:DoAttack()
    self.doAttackCalls = (self.doAttackCalls or 0) + 1
    if not self:isAuthorizedHandToHandAction() then return false end
    self.attackStarted = true
    return false
end
function actor:isAttackStarted() return self.attackStarted == true end
function actor:setKnockedDown(value) self.knockedDown = value end
function actor:isKnockedDown() return self.knockedDown == true end
function actor:setSitOnFurnitureObject(value) self.seatObject = value end
function actor:setSittingOnFurniture(value) self.sitting = value end
function actor:isSittingOnFurniture() return self.sitting == true end
function actor:isSitOnGround() return self.groundSitting == true end
function actor:setVariable(name, value)
    self.lastVariable, self.lastVariableValue = name, value
    if name == "forceGetUp" and value == true then self.groundSitting = false end
end

local pathBehavior = {}
pathBehavior.pathNextIsSet = true
pathBehavior.pathNextX = 1.5
pathBehavior.pathNextY = 0.5
function pathBehavior:pathToLocationF(x, y, z)
    self.x, self.y, self.z, self.cancelled = x, y, z, false
    self.startCount = (self.startCount or 0) + 1
end
function pathBehavior:isTargetLocation(x, y, z)
    return self.x == x and self.y == y and self.z == z
end
function pathBehavior:cancel() self.cancelled = true end
function pathBehavior:shouldBeMoving() return self.cancelled ~= true and self.x ~= nil end
function pathBehavior:hasStartedMoving() return self.startedMoving == true end
function pathBehavior:isTurningToObstacle() return self.turning == true end
function pathBehavior:isMovingUsingPathFind() return self.usingPath == true end
function pathBehavior:allowTurnAnimation() return true end
function pathBehavior:isStrafing() return false end
function pathBehavior:pathToNearestTable(locations)
    self.nearestLocations, self.cancelled = locations, false
    self.x, self.y, self.z = locations[1], locations[2], locations[3]
end
function actor:getPathFindBehavior2() return pathBehavior end
function actor:pathToLocationF(x, y, z)
    pathBehavior:pathToLocationF(x, y, z)
    self.moving = true
end
function actor:bridgePathToNearest(locations)
    pathBehavior:pathToNearestTable(locations)
    self.moving = true
    return true
end

local provider = {
    testOnly = true,
    kind = "experimental-npc-player",
    directNative = false,
}
function provider:isActor(candidate) return candidate ~= nil and candidate.__owned == true end
function provider:attack(candidate, action, intent)
    self.lastRejectedAction = action
    return false, "injected native rejection"
end
function provider:stop() return true end
function provider:recover(candidate, targetSquare)
    candidate.square = targetSquare
    candidate.px, candidate.py = nil, nil
    return true
end
check(SC.Actor._setProviderForTests(provider), "real Actor adapter accepts explicit test provider")
SC_TEST_EXPERIMENTAL_STATUS = SC.Actor.bridgeStatus(false)
check(SC_TEST_EXPERIMENTAL_STATUS.ready == true
        and SC_TEST_EXPERIMENTAL_STATUS.provider == SC.Identity.providers.experimental
        and SC_TEST_EXPERIMENTAL_STATUS.code == "experimental_provider",
    "canonical experimental provider kind reaches its intended support status")

local neutralActor = setmetatable({
    __owned = true,
    __class = "IsoPlayer",
    data = {},
    square = square,
    characterActions = actionList(),
}, { __index = actor })
local neutralRecord = SC.Registry.register(neutralActor, {
    id = "sc-core-neutral",
    recruited = false,
})
check(neutralRecord ~= nil and neutralRecord.recruited == false
        and neutralRecord.order == "wander" and neutralRecord.scavenge == false,
    "fresh neutral registry actors do not inherit recruited follow defaults")
check(SC.Registry.unregister(neutralActor) == neutralRecord,
    "neutral registry default regression fixture unregisters cleanly")

do
    local source = {
        identity = { forename = "Owned", surname = "Copy" },
        state = {
            order = { current = "invalid", followDistance = 999,
                combatStance = "invalid", weaponPriority = "invalid" },
            personality = { memories = { { text = "original" } },
                background = { occupation = "carpenter" }, care = {}, reveals = {} },
            downtime = { facts = { repaired = 1 } },
        },
    }
    local copyActor = setmetatable({ __owned = true, __class = "IsoPlayer", data = {},
        square = square, characterActions = actionList() }, { __index = actor })
    local copied = SC.Registry.register(copyActor, {
        id = "sc-owned-copy", recruited = true, identity = source.identity, state = source.state,
    })
    source.identity.forename = "Mutated"
    source.state.personality.memories[1].text = "mutated"
    check(copied and copied.identity.forename == "Owned"
            and copied.memories[1].text == "original"
            and copied.order == "follow" and copied.followDistance == 3
            and copied.combatMode == "defensive" and copied.weaponPriority == "best",
        "registry owns nested inputs and normalizes invalid command enums")
    SC.Registry.unregister(copyActor)
end

do
    local storage = { SC_FactionId = "old-faction", SC_FactionRole = "old-role" }
    local failed = false
    local proxy = setmetatable({}, {
        __index = function(_, key) return storage[key] end,
        __newindex = function(_, key, value)
            if key == "SC_FactionRole" and not failed then
                failed = true
                error("injected mod-data assignment failure")
            end
            storage[key] = value
        end,
    })
    local rollbackActor = setmetatable({ __owned = true, __class = "IsoPlayer",
        data = proxy, square = square, characterActions = actionList() }, { __index = actor })
    local committed, reason = SC.Registry.register(rollbackActor, {
        id = "sc-rollback", recruited = true, factionId = "new-faction",
        factionRole = "new-role",
    })
    check(committed == nil and string.find(tostring(reason), "registry commit failed", 1, true)
            and storage.SC_Id == nil and storage.SC_FactionId == "old-faction"
            and storage.SC_FactionRole == "old-role"
            and SC.Registry.byId("sc-rollback") == nil
            and SC.Registry.idOf(rollbackActor) == nil,
        "registry assignment failure restores all actor fields and both ownership maps")
end

local record = SC.Registry.register(actor, { id = "sc-core-actor", recruited = true })
check(record ~= nil and SC.Actor.isCompanion(actor)
        and record.rideWithPlayer == true,
    "registry ownership integrates and old records default Ride with player on")
check(record.state and record.state.order
        and record.state.order.movementMode == "copy"
        and record.state.order.movementModeVersion == 0,
    "recruited records enter command migration with Copy player movement")
record.trust = 7
record.bond = 11
record.morale = 63
record.stress = 21
record.timeTogetherMs = 7200000
record.background = { occupation = "mechanic", home = "rosewood" }
actor.__migratedMovement = SC.Commands.peek(actor)
check(actor.__migratedMovement.moveMode == "copy"
        and actor.__migratedMovement.moveModeVersion == 2,
    "old recruited saves enter the Copy player default in memory")
check(SC.Commands.persist(actor)
        and actor.data.SC_MoveMode == "copy"
        and actor.data.SC_MoveModeVersion == 2,
    "old recruited saves persist the one-time Copy player migration")
actor.__migratedMovement = nil
check(SC.Commands.issue(record.id, "guard", nil, nil), "command adapter accepts persistent order")
check(SC.Commands.issue(record.id, "set_follow_distance", { distance = 8 }, nil),
    "command adapter accepts persistent follow distance")
check(SC.Commands.issue(record.id, "set_scavenge", { enabled = false }, nil),
    "command adapter accepts persistent scavenging preference")
check(SC.Commands.issue(record.id, "set_move_mode", { mode = "jog" }, nil),
    "command adapter accepts persistent movement mode")
check(SC.Commands.issue(record.id, "set_combat_doctrine", { doctrine = "ranged_support" }, nil),
    "command adapter accepts a persistent rules-of-engagement doctrine")
check(SC.Commands.issue(record.id, "set_combat_mode", { mode = "passive" }, nil)
        and SC.Commands.issue(record.id, "set_weapon_priority", { priority = "quiet" }, nil)
        and SC.Commands.issue(record.id, "set_hold_fire", { enabled = true }, nil),
    "stance, weapon priority, and hold-fire remain independent policy controls")
check(SC.Commands.issue(record.id, "set_group", { group = "Bravo" }, nil),
    "command adapter accepts persistent group")
check(SC.Commands.issue(record.id, "set_work_mode", { mode = "craft" }, nil),
    "command adapter accepts persistent work mode")
local commandSnapshot, commandSnapshotReason = SC.Persistence.captureRecord(record)
check(commandSnapshot ~= nil and commandSnapshotReason == nil
    and commandSnapshot.order.current == "guard"
    and commandSnapshot.order.followDistance == 8
    and commandSnapshot.order.scavenge == false
    and commandSnapshot.order.movementMode == "jog"
    and commandSnapshot.order.movementModeVersion == 2
    and commandSnapshot.order.combatStance == "passive"
    and commandSnapshot.order.combatDoctrine == "ranged_support"
    and commandSnapshot.order.holdFire == true
    and commandSnapshot.order.weaponPriority == "quiet"
    and commandSnapshot.order.workMode == "craft"
    and commandSnapshot.group == "Bravo"
    and commandSnapshot.personality.trust == 7
    and commandSnapshot.personality.bond == 11
    and commandSnapshot.personality.morale == 63
    and commandSnapshot.personality.stress == 21
    and commandSnapshot.personality.timeTogetherMs == 7200000
    and commandSnapshot.personality.background.occupation == "mechanics",
    "real Commands -> Registry state -> Persistence schema preserves stable command fields: stance="
        .. tostring(commandSnapshot and commandSnapshot.order.combatStance)
        .. " doctrine=" .. tostring(commandSnapshot and commandSnapshot.order.combatDoctrine)
        .. " hold=" .. tostring(commandSnapshot and commandSnapshot.order.holdFire)
        .. " weapon=" .. tostring(commandSnapshot and commandSnapshot.order.weaponPriority)
        .. " work=" .. tostring(commandSnapshot and commandSnapshot.order.workMode)
        .. " current=" .. tostring(commandSnapshot and commandSnapshot.order.current)
        .. " distance=" .. tostring(commandSnapshot and commandSnapshot.order.followDistance)
        .. " scavenge=" .. tostring(commandSnapshot and commandSnapshot.order.scavenge)
        .. " move=" .. tostring(commandSnapshot and commandSnapshot.order.movementMode)
        .. " group=" .. tostring(commandSnapshot and commandSnapshot.group)
        .. " trust=" .. tostring(commandSnapshot and commandSnapshot.personality.trust)
        .. " bond=" .. tostring(commandSnapshot and commandSnapshot.personality.bond)
        .. " morale=" .. tostring(commandSnapshot and commandSnapshot.personality.morale)
        .. " stress=" .. tostring(commandSnapshot and commandSnapshot.personality.stress)
        .. " time=" .. tostring(commandSnapshot and commandSnapshot.personality.timeTogetherMs)
        .. " occupation=" .. tostring(commandSnapshot and commandSnapshot.personality.background.occupation))
for _, key in ipairs({
    "SC_Order", "SC_FollowDistance", "SC_Scavenge", "SC_MoveMode", "SC_CombatMode",
    "SC_CombatDoctrine", "SC_HoldFire", "SC_WeaponPriority", "SC_Group", "SC_Trust", "SC_Bond",
    "SC_Morale", "SC_Stress", "SC_TimeTogetherMs", "SC_WorkMode",
}) do actor.data[key] = nil end
SC.Commands.reset(actor)
local restoredCommandState = SC.Commands.peek(actor)
check(restoredCommandState.order == "guard" and restoredCommandState.followDistance == 8
    and restoredCommandState.scavenge == false and restoredCommandState.moveMode == "jog"
    and restoredCommandState.combatMode == "passive"
    and restoredCommandState.combatDoctrine == "ranged_support"
    and restoredCommandState.holdFire == true
    and restoredCommandState.weaponPriority == "quiet" and restoredCommandState.group == "Bravo"
    and restoredCommandState.workMode == "craft"
    and restoredCommandState.trust == 7 and restoredCommandState.bond == 11
    and restoredCommandState.morale == 63 and restoredCommandState.stress == 21
    and restoredCommandState.timeTogetherMs == 7200000
    and restoredCommandState.background.occupation == "mechanics",
    "Registry persistence schema rehydrates independent policies without transient actor mod-data")

local barricadeObject = { square = square, objectIndex = 0 }
function barricadeObject:getSquare() return self.square end
function barricadeObject:getObjectIndex() return self.objectIndex end
function barricadeObject:isBarricadeAllowed() return true end
function barricadeObject:getBarricadeForCharacter() return nil end
check(SC.Commands.issue(record.id, "barricade", { object = barricadeObject }, nil),
    "barricade work order accepts a loaded barricadeable target")
local buildingState = SC.Commands.peek(actor)
local buildingSnapshot = SC.Persistence.captureRecord(record)
check(buildingState.order == "work" and buildingState.workMode == "build"
    and buildingState.returnOrder == "guard" and buildingState.returnWorkMode == "craft"
    and buildingState.workTarget.object == barricadeObject
    and buildingState.workTarget.initialPlanks == 0
    and buildingSnapshot.order.workTarget.object == nil
    and buildingSnapshot.order.workTarget.objectIndex == 0
    and buildingSnapshot.order.workTarget.initialPlanks == 0,
    "one-shot building persists only a stable target and remembers the prior role")
check(SC.Commands.issue(record.id, "finish_work", nil, nil),
    "internal work completion command is accepted")
local completedWorkState = SC.Commands.peek(actor)
check(completedWorkState.order == "guard" and completedWorkState.workMode == "craft"
    and completedWorkState.workTarget == nil and completedWorkState.returnOrder == nil,
    "completed building restores the prior permanent role and work mode")

local brokenPart = {}
function brokenPart:getType() return "Hand_L" end
local brokenParts = { brokenPart }
function brokenParts:size() return #self end
function brokenParts:get(index) return self[index + 1] end
local brokenBody = {}
function brokenBody:getBodyParts() return brokenParts end
local brokenActor = {}
function brokenActor:getBodyDamage() return brokenBody end
local vitalsApplied, vitalsReason = SC.Vitals.apply(brokenActor, {
    health = 100, overallHealth = 100, infected = false, parts = {
        { type = "Hand_L", health = 100 },
    },
})
check(not vitalsApplied and string.find(tostring(vitalsReason), "SetHealth", 1, true) ~= nil,
    "native-vitals restore rejects a missing setter instead of reporting success")

local needsParts = {}
function needsParts:size() return 0 end
function needsParts:get() return nil end
local needsBody = { health = 100, infected = false, infectionTime = -1, mortality = -1 }
function needsBody:getHealth() return self.health end
function needsBody:getOverallBodyHealth() return self.health end
function needsBody:isInfected() return self.infected end
function needsBody:getInfectionTime() return self.infectionTime end
function needsBody:getInfectionMortalityDuration() return self.mortality end
function needsBody:getApparentInfectionLevel() return 0 end
function needsBody:getBodyParts() return needsParts end
function needsBody:setInfected(value) self.infected = value end
function needsBody:setInfectionTime(value) self.infectionTime = value end
function needsBody:setInfectionMortalityDuration(value) self.mortality = value end
function needsBody:setOverallBodyHealth(value) self.health = value end
local hungerStat = CharacterStat.HUNGER
local thirstStat = CharacterStat.THIRST
local nativeStats = { hunger = 0.62, thirst = 0.74 }
function nativeStats:get(stat)
    if stat == hungerStat then return self.hunger end
    if stat == thirstStat then return self.thirst end
    return 0
end
function nativeStats:set(stat, value)
    if stat == hungerStat then self.hunger = value return true end
    if stat == thirstStat then self.thirst = value return true end
    return false
end
local needsActor = { health = 100 }
function needsActor:getBodyDamage() return needsBody end
function needsActor:getHealth() return self.health end
function needsActor:setHealth(value) self.health = value end
function needsActor:getStats() return nativeStats end
local savedNeeds = SC.Vitals.capture(needsActor)
check(savedNeeds and math.abs(savedNeeds.hunger - 0.62) < 0.001
    and math.abs(savedNeeds.thirst - 0.74) < 0.001,
    "native hunger and thirst are captured in the persistent vitals record")
savedNeeds.hunger, savedNeeds.thirst = 0.21, 0.32
local restoredNeeds, restoredNeedsReason = SC.Vitals.apply(needsActor, savedNeeds)
check(restoredNeeds and math.abs(nativeStats.hunger - 0.21) < 0.001
    and math.abs(nativeStats.thirst - 0.32) < 0.001,
    "native hunger and thirst restore transactionally: " .. tostring(restoredNeedsReason))

local vehicle = { id = 7, script = "Base.TestCar", x = 1, y = 0, z = 0, speed = 0 }
function vehicle:getId() return self.id end
function vehicle:getScriptName() return self.script end
function vehicle:getX() return self.x end
function vehicle:getY() return self.y end
function vehicle:getZ() return self.z end
function vehicle:getMaxPassengers() return 3 end
function vehicle:isSeatInstalled(seat) return seat == 1 end
function vehicle:isSeatOccupied() return false end
function vehicle:getCurrentSpeedKmHour() return self.speed end
function vehicle:getEnterSeatDistance(seat, x, y)
    if seat ~= 1 then return -1 end
    return (x - 1.5) * (x - 1.5) + (y - 0.5) * (y - 0.5)
end
function vehicle:enter(seat, candidate)
    if seat ~= 1 or self.passenger ~= nil then return false end
    self.passenger, candidate.vehicle = candidate, self
    return true
end
function vehicle:exit(candidate)
    if self.passenger ~= candidate then return false end
    self.passenger, candidate.vehicle = nil, nil
    return true
end
function vehicle:getSeat(candidate) return self.passenger == candidate and 1 or -1 end
function vehicle:getCharacter(seat) return seat == 1 and self.passenger or nil end
local vehicleCell = {}
function vehicleCell:getGridSquare(x, y, z)
    local candidate = { x = x, y = y, z = z }
    function candidate:getX() return self.x end
    function candidate:getY() return self.y end
    function candidate:getZ() return self.z end
    function candidate:isSolid() return false end
    function candidate:isSolidTrans() return false end
    function candidate:TreatAsSolidFloor() return true end
    function candidate:isFree() return true end
    return candidate
end
function vehicle:getCell() return vehicleCell end

local manifestVehicle = {
    id = 8, script = "Base.FourSeatCar", x = 1, y = 0, z = 0, speed = 0,
    occupants = {},
}
function manifestVehicle:getId() return self.id end
function manifestVehicle:getScriptName() return self.script end
function manifestVehicle:getX() return self.x end
function manifestVehicle:getY() return self.y end
function manifestVehicle:getZ() return self.z end
function manifestVehicle:getMaxPassengers() return 4 end
function manifestVehicle:isSeatInstalled(seat) return seat >= 0 and seat <= 3 end
function manifestVehicle:isSeatOccupied(seat) return self.occupants[seat] ~= nil end
function manifestVehicle:getCharacter(seat) return self.occupants[seat] end
function manifestVehicle:getSeat(candidate)
    for seat, occupant in pairs(self.occupants) do if occupant == candidate then return seat end end
    return -1
end
function manifestVehicle:getCurrentSpeedKmHour() return self.speed end

local manifestPlayer = { data = {}, vehicle = manifestVehicle, square = square }
function manifestPlayer:getModData() return self.data end
function manifestPlayer:getVehicle() return self.vehicle end
function manifestPlayer:getX() return 0.5 end
function manifestPlayer:getY() return 0.5 end
function manifestPlayer:getZ() return 0 end

local manifestActors = {}
for index = 1, 10 do
    local candidateSquare = { x = index, y = 0, z = 0 }
    local candidate = setmetatable({
        __owned = true,
        __class = "IsoPlayer",
        data = {},
        square = candidateSquare,
        characterActions = actionList(),
    }, { __index = actor })
    local id = string.format("sc-manifest-%02d", index)
    check(SC.Registry.register(candidate, { id = id, recruited = true }) ~= nil,
        "ten-companion manifest fixture registers companion " .. tostring(index))
    check(SC.Commands.issue(id, "follow", nil, manifestPlayer),
        "manifest fixture companion follows the player")
    check(SC.Commands.issue(id, "set_ride_with_player", { enabled = true }, manifestPlayer),
        "manifest fixture companion opts into automatic vehicle travel")
    manifestActors[#manifestActors + 1] = candidate
end
local doctrineAccepted, doctrineReason = SC.Commands.setTeamCombatDoctrine(
    manifestPlayer, "weapons_free")
check(doctrineAccepted == true and doctrineReason == "weapons_free"
        and manifestPlayer.data.SC_TeamCombatDoctrine == "weapons_free",
    "one universal selector persists the team rules of engagement")
for _, candidate in ipairs(manifestActors) do
    local doctrineState = SC.Commands.peek(candidate)
    check(doctrineState.combatDoctrine == "weapons_free"
            and doctrineState.combatMode == "aggressive"
            and doctrineState.holdFire == false,
        "team doctrine is applied atomically to every recruited companion")
end
SC.Vehicle.invalidateManifests()
local assignedSeats, waitingCount = {}, 0
for _, candidate in ipairs(manifestActors) do
    local assignment, assignmentReason, capacity = SC.Vehicle.assignmentFor(
        candidate, manifestVehicle, manifestPlayer)
    if assignment ~= nil then
        assignedSeats[assignment.seat] = (assignedSeats[assignment.seat] or 0) + 1
        check(assignment.capacity == 3 and assignment.assigned == 3,
            "four-seat vehicle exposes exactly three companion seats")
    else
        check(assignmentReason == "vehicle_capacity_wait"
            and capacity.capacity == 3 and capacity.assigned == 3,
            "overflow companion waits without receiving an invalid seat")
        waitingCount = waitingCount + 1
    end
end
check(assignedSeats[1] == 1 and assignedSeats[2] == 1 and assignedSeats[3] == 1
        and waitingCount == 7,
    "ten companions produce three unique passenger assignments and seven safe waiters")

-- An outside occupant can take a planned seat before the companion reaches
-- the door. The next lookup must rebuild instead of retaining a stale seat.
local firstAssignment = SC.Vehicle.assignmentFor(manifestActors[1], manifestVehicle, manifestPlayer)
if firstAssignment ~= nil then
    manifestVehicle.occupants[firstAssignment.seat] = { outsider = true }
    local reassigned, staleReason, staleCapacity = SC.Vehicle.assignmentFor(
        manifestActors[1], manifestVehicle, manifestPlayer)
    check((reassigned ~= nil and reassigned.seat ~= firstAssignment.seat)
            or (reassigned == nil and staleReason == "vehicle_capacity_wait"
                and staleCapacity.capacity == 2),
        "manifest rebuilds when another passenger takes a planned seat")
    manifestVehicle.occupants[firstAssignment.seat] = nil
end
SC.Vehicle.invalidateManifests(manifestVehicle)
for _, candidate in ipairs(manifestActors) do SC.Registry.unregister(candidate) end
local laterRecruit = setmetatable({
    __owned = true,
    __class = "IsoPlayer",
    data = {},
    square = { x = 2, y = 2, z = 0 },
    characterActions = actionList(),
}, { __index = actor })
local laterRecord = SC.Registry.register(laterRecruit, {
    id = "sc-later-recruit", recruited = false,
})
check(laterRecord ~= nil
        and SC.Commands.issue(laterRecord.id, "recruit", nil, manifestPlayer)
        and SC.Commands.peek(laterRecruit).combatDoctrine == "weapons_free",
    "companions recruited later inherit the persisted team doctrine")
SC.Registry.unregister(laterRecruit)

local preflight, preflightReason = SC.Vehicle.preflightBoard(actor, vehicle, nil)
check(preflight ~= nil and preflightReason == nil and preflight.actorId == "sc-core-actor"
    and preflight.vehicle == vehicle and preflight.seat == 1,
    "vehicle preflight resolves a bounded native seat without mutation")
local reserved, reservedBy = SC.Vehicle.isSeatReserved(vehicle, 1)
check(not reserved and reservedBy == nil and actor:getVehicle() == nil,
    "vehicle preflight does not reserve, enter, or mutate the actor")
local staleOk, staleReason = SC.Vehicle.board(actor, vehicle, nil, {
    preflight = {
        actorId = preflight.actorId,
        vehicle = vehicle,
        vehicleKey = preflight.vehicleKey,
        seat = 2,
        reservation = preflight.reservation,
    },
})
check(not staleOk and string.find(tostring(staleReason), "unavailable", 1, true) ~= nil,
    "stale or invalid vehicle preflight cannot reserve a seat")
reserved = SC.Vehicle.isSeatReserved(vehicle, 1)
check(not reserved, "rejected vehicle preflight leaves reservations unchanged")
actor.px = -10
local distantPreflight, distantReason = SC.Vehicle.preflightBoard(actor, vehicle, nil)
check(distantPreflight == nil and distantReason == "companion is not at the passenger door",
    "vehicle entry refuses long-range engine teleportation")
actor.px = nil
vehicle.speed = 12
local movingPreflight, movingReason = SC.Vehicle.preflightBoard(actor, vehicle, nil)
check(movingPreflight == nil and movingReason == "vehicle is moving",
    "vehicle entry refuses a moving target")
vehicle.speed = 0
function SC.__testVehicleTransaction()
    local boardingTransaction, boardingTransactionReason = SC.Vehicle.beginBoarding(
        actor, vehicle, 1, { followPlayer = true })
    local boardingSnapshot = SC.ActionSupervisor.snapshot(actor)
    local seatReserved, seatReservedBy = SC.Vehicle.isSeatReserved(vehicle, 1)
    check(boardingTransaction ~= nil and boardingTransactionReason == "started"
            and boardingSnapshot.owner == "vehicle" and boardingSnapshot.action == "board_vehicle"
            and boardingSnapshot.phase == "approaching" and boardingSnapshot.reservationCount == 1
            and seatReserved and seatReservedBy == "sc-core-actor",
        "vehicle approach owns the actor and the exact passenger seat")
    check(SC.Vehicle.cancelTransaction(actor, "fixture_cancel")
            and SC.ActionSupervisor.snapshot(actor).phase == "idle"
            and SC.ActionSupervisor.reservationCount(actor) == 0
            and SC.Vehicle.isSeatReserved(vehicle, 1) == false,
        "cancelled vehicle approach releases actor and seat ownership")
end
SC.__testVehicleTransaction()
SC.__testVehicleTransaction = nil
local boarded, boardReason = SC.Vehicle.board(actor, vehicle, nil, { preflight = preflight })
check(boarded and boardReason == "native_seat" and SC.Vehicle.isNativeSeated(actor)
    and SC.Registry.byId("sc-core-actor") ~= nil
    and SC.ActionSupervisor.snapshot(actor).phase == "idle"
    and SC.ActionSupervisor.reservationCount(actor) == 0,
    "verified native passenger entry commits once and releases action ownership")
function SC.__testVehiclePolicyStatus()
    check(SC.Commands.issue(record.id, "set_ride_with_player", { enabled = false }, nil),
        "Ride with player can be disabled while already seated")
    vehicle.speed = 12
    local movingStatus = SC.Vehicle.statusFor(actor, manifestPlayer)
    local movingExit, movingExitReason = SC.Vehicle.exit(actor, vehicle)
    check(movingStatus.status == "waiting_safe_exit" and movingStatus.canExitNow == false
            and not movingExit and movingExitReason == "vehicle is moving"
            and actor:getVehicle() == vehicle,
        "disabled Ride policy waits in the moving car and direct exit is safely rejected")
    vehicle.speed = 0
    local seatedStatus = SC.Vehicle.statusFor(actor, manifestPlayer)
    check(seatedStatus.status == "in_vehicle" and seatedStatus.canExitNow == true,
        "a stopped seated companion exposes the contextual emergency exit")
    local exited, exitReason = SC.Vehicle.exit(actor, vehicle)
    check(exited and exitReason == "native_exit" and actor:getVehicle() == nil
        and actor:getCurrentSquare() ~= nil
        and SC.ActionSupervisor.snapshot(actor).phase == "idle"
        and SC.ActionSupervisor.reservationCount(actor) == 0,
        "native passenger exit restores a valid square and closes its transaction")
    manifestPlayer.vehicle = nil
    local footStatus = SC.Vehicle.statusFor(actor, manifestPlayer)
    check(footStatus.status == "on_foot", "vehicle status reports an unseated companion on foot")
    check(SC.Commands.issue(record.id, "follow", nil, manifestPlayer)
            and SC.Commands.issue(record.id, "set_ride_with_player", { enabled = true }, manifestPlayer),
        "vehicle approach status fixture enables follow and ride policies")
    manifestPlayer.vehicle = vehicle
    SC.Vehicle.invalidateManifests(vehicle)
    local approachStatus = SC.Vehicle.statusFor(actor, manifestPlayer)
    check(approachStatus.status == "approaching_vehicle" and approachStatus.seat == 1,
        "an assigned follower reports that it is approaching the player vehicle")
    SC.Vehicle.invalidateManifests(vehicle)
    manifestPlayer.vehicle = nil
end
SC.__testVehiclePolicyStatus()
SC.__testVehiclePolicyStatus = nil

local fireWindow = { hittable = true }
function fireWindow:isHittable() return self.hittable end
local fireDoor = {}
function fireDoor:findWindow() return fireWindow end
local fireVehicle = {
    id = 9, script = "Base.FireTestCar", x = 1, y = 0, z = 0, speed = 0,
    passenger = actor,
}
function fireVehicle:getId() return self.id end
function fireVehicle:getScriptName() return self.script end
function fireVehicle:getX() return self.x end
function fireVehicle:getY() return self.y end
function fireVehicle:getZ() return self.z end
function fireVehicle:getSeat(candidate) return candidate == self.passenger and 1 or -1 end
function fireVehicle:getCharacter(seat) return seat == 1 and self.passenger or nil end
function fireVehicle:getPassengerDoor(seat) return seat == 1 and fireDoor or nil end
function fireVehicle:getCurrentSpeedKmHour() return self.speed end
actor.vehicle = fireVehicle
local closedFire, closedReason = SC.Vehicle.canPassengerFire(actor, {}, "ranged_support")
check(not closedFire and closedReason == "passenger_window_closed",
    "passenger never fires through intact closed glass")
fireWindow.hittable = false
local rangedFire = SC.Vehicle.canPassengerFire(actor, {}, "ranged_support")
local stealthFire, stealthReason = SC.Vehicle.canPassengerFire(actor, {}, "stealth")
check(rangedFire == true and not stealthFire
        and stealthReason == "vehicle_fire_blocked_by_doctrine",
    "only ranged doctrines allow passenger fire through an open or broken window")
fireVehicle.speed = 16
local rangedFast, rangedFastReason = SC.Vehicle.canPassengerFire(actor, {}, "ranged_support")
local freeAtSpeed = SC.Vehicle.canPassengerFire(actor, {}, "weapons_free")
fireVehicle.speed = 31
local freeTooFast, freeTooFastReason = SC.Vehicle.canPassengerFire(actor, {}, "weapons_free")
check(not rangedFast and rangedFastReason == "vehicle_too_fast_to_fire"
        and freeAtSpeed == true and not freeTooFast
        and freeTooFastReason == "vehicle_too_fast_to_fire",
    "vehicle passenger fire observes doctrine-specific speed ceilings")
fireVehicle.speed = 0
SC_TEST_CLOCK = 2000
local firstShot = SC.Vehicle.claimPassengerShot(actor, {}, "ranged_support")
local secondShot, secondShotReason = SC.Vehicle.claimPassengerShot(actor, {}, "ranged_support")
SC_TEST_CLOCK = 2240
local thirdShot = SC.Vehicle.claimPassengerShot(actor, {}, "ranged_support")
check(firstShot == true and not secondShot and secondShotReason == "vehicle_fire_lane_busy"
        and thirdShot == true,
    "passengers share a bounded firing cadence instead of firing simultaneously")
actor.vehicle = nil
local nativeSeatRecord = {
    id = "sc-native-seat",
    recruited = true,
    identity = { forename = "Avery", surname = "Reed", gender = "female" },
    position = { x = 12, y = 15, z = 0 },
    vehicle = {
        stored = false,
        vehicle = { id = 7, script = "Base.TestCar", x = 12, y = 15, z = 0 },
        seat = 1,
    },
}
local importedNative, importNativeReason = SC.Vehicle.importNativeSeat(nativeSeatRecord)
local exportedNative = SC.Vehicle.exportStored()[nativeSeatRecord.id]
check(importedNative and importNativeReason ~= nil and exportedNative ~= nil
    and exportedNative.vehicle.stored == true and SC.Vehicle.storedCount() == 1,
    "native-seated save is distinguished and converted to a correct-vehicle reservation")
SC.Vehicle.reset()

local targetSquare = { x = 1, y = 0, z = 0 }
function targetSquare:getX() return self.x end
function targetSquare:getY() return self.y end
function targetSquare:getZ() return self.z end
local target = { __class = "IsoZombie", square = targetSquare }
function target:isDead() return false end
function target:getSquare() return self.square end
function target:getCurrentSquare() return self.square end
function target:getX() return self.square.x + 0.5 end
function target:getY() return self.square.y + 0.5 end
function target:getZ() return self.square.z end
function target:isOnFloor() return false end

local combatOk, combatReason = SC.Combat.update(actor, nil, {
    snapshot = {
        threats = {{ actor = target, distanceSq = 1, visible = true, attacking = true }},
        allies = {}, escapeSquares = {}, pressure = 0, immediateCount = 1,
    },
})
check(not combatOk and string.find(tostring(combatReason), "rejected", 1, true) ~= nil
    and provider.lastRejectedAction == "shove",
    "real Combat -> GameplayUtil -> Actor -> NativeActions chain propagates rejection")

local directProvider = {
    testOnly = true,
    kind = "experimental-npc-player",
    directNative = true,
}
function directProvider:isActor(candidate) return candidate ~= nil and candidate.__owned == true end
function directProvider:stop(candidate) return SC.NativeActions.stopDirect(candidate) end
function directProvider:retireDead(candidate)
    if candidate.deathDone ~= true then return false, "death_pending" end
    candidate.__owned = false
    return true
end
function directProvider:barricade(candidate, object)
    self.lastBarricade = object
    return true, "provider_barricade_started"
end
function directProvider:removeBarricade(candidate, object)
    self.lastRemovedBarricade = object
    return true, "provider_remove_barricade_started"
end
function directProvider:dismantle(candidate, object)
    self.lastDismantled = object
    return true, "provider_dismantle_started"
end
check(SC.Actor._setProviderForTests(directProvider),
    "pure-Lua experimental adapter selects explicit direct-native execution")

actor.px, actor.py = 0.5, 0.5
local moved, moveReason = SC.Actor.setMovement(actor, "jog", { action = "move", dx = 1, dy = 0 })
check(moved and moveReason == "moving" and actor.running == true and actor.px > 0.5,
    "direct-native adapter starts and verifies normalized movement")
local utilityRejected, utilityRejectReason = SC.GameplayUtil.move(actor, "walk", {
    action = "unsupported_test_action",
})
check(not utilityRejected and string.find(tostring(utilityRejectReason), "unsupported actor intent", 1, true),
    "gameplay executor preserves a native action rejection reason for player feedback")
local pathOk, pathReason = SC.Actor.setMovement(actor, "walk", {
    action = "path", targetSquare = targetSquare, enginePath = true,
})
check(pathOk and pathReason == "path_started" and pathBehavior.x == 1.5,
    "direct-native adapter starts and verifies engine pathing")
local continuedPath, continuedReason = SC.Actor.setMovement(actor, "walk", {
    action = "path", targetSquare = targetSquare, enginePath = true,
})
check(continuedPath and continuedReason == "path_continues" and pathBehavior.startCount == 1,
    "identical active native path targets are retained without restarting locomotion")
check(actor.moving == true and actor.running == false and actor.sneaking == false,
    "engine pathing enters ordinary player walk locomotion")
check(SC.Actor.stop(actor) and pathBehavior.cancelled == true and actor.moving == false,
    "native stop cancels pathing and clears player locomotion")

local weapon = { getCategory = function() return "Weapon" end }
local equipOk, equipReason = SC.Actor.setMovement(actor, "walk", {
    action = "equip_weapon", item = weapon,
})
check(equipOk and equipReason == "equipped" and actor.primaryHand == weapon,
    "direct-native adapter starts and verifies equipment")
local readyOk, readyReason = SC.Actor.setMovement(actor, "walk", {
    action = "ready_weapon", targetSquare = targetSquare,
})
check(readyOk and readyReason == "weapon_ready" and actor.aiming == true
        and actor.aimAtFloor == false,
    "armed companion enters and verifies the native player weapon-ready state")
actor.px, actor.py = 0.5, 0.5
local backstepOk, backstepReason = SC.Actor.setMovement(actor, "walk", {
    action = "backstep", target = target, keepFacing = true, weaponReady = true,
})
check(backstepOk and backstepReason == "moving" and actor.tacticalMovement == true
        and actor.strafeY < -0.9 and math.abs(actor.strafeX) < 0.1
        and actor.forwardX > 0.9 and actor.px < 0.5,
    "combat backstep uses the stock backward-walk blend while facing the threat")
actor.px, actor.py = 0.5, 0.5
local strafeOk = SC.Actor.setMovement(actor, "walk", {
    action = "lateral_kite", target = target, keepFacing = true, weaponReady = true,
})
check(strafeOk and actor.tacticalMovement == true and math.abs(actor.strafeX) > 0.9
        and math.abs(actor.strafeY) < 0.1 and actor.forwardX > 0.9,
    "combat kite uses a lateral player strafe without turning away from the threat")
local lowerOk, lowerReason = SC.Actor.setMovement(actor, "walk", { action = "lower_weapon" })
check(lowerOk and lowerReason == "weapon_lowered" and actor.aiming == false
        and actor.tacticalMovement == false and actor.strafeX == 0 and actor.strafeY == 0,
    "weapon-ready posture lowers through the native player state")
do
    local twoHandedWeapon = { isTwoHandWeapon = function() return true end }
    local twoHandedOk, twoHandedReason = SC.Actor.setMovement(actor, "walk", {
        action = "equip_weapon", item = twoHandedWeapon,
    })
    check(twoHandedOk and twoHandedReason == "equipped"
        and actor.primaryHand == twoHandedWeapon and actor.secondaryHand == twoHandedWeapon,
        "direct-native adapter equips a two-handed axe in both hands")
    AttackType = { SHOVE = {}, STOMP = {}, SHOT = {}, MELEE_SWING = {} }
    actor.attackModelReady = false
    local warmupOk, warmupReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = target, weapon = twoHandedWeapon,
    })
    check(not warmupOk and warmupReason == "native weapon is not attack-ready"
        and (actor.doAttackCalls or 0) == 0,
        "freshly equipped weapon waits for native CanAttack model readiness")
    actor.attackModelReady = true
    local attackOk, attackReason = SC.Actor.setMovement(actor, "walk", {
        action = "shove", target = target,
    })
    check(attackOk and attackReason == "attack_started" and actor.attackType == AttackType.SHOVE
        and actor.doShove == true and actor.doGrapple == false
        and actor.authorizedHandToHandAction ~= false
        and actor.authorizedHandToHand ~= false,
        "direct-native adapter preflights, authorizes, starts, and restores native attack state")
    actor.attackStarted = false
    local meleeOk, meleeReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = target, weapon = twoHandedWeapon,
    })
    check(meleeOk and meleeReason == "attack_started" and actor.doShove == false,
        "a weapon swing clears stale shove state before the native attack starts")
end

ISReloadWeaponAction = {}
function ISReloadWeaponAction.BeginAutomaticReload(candidate)
    local queue = ISTimedActionQueue.getTimedActionQueue(candidate)
    local action = {}
    queue.queue[#queue.queue + 1] = action
    queue.current = action
end
local reloadOk, reloadReason = SC.Actor.setMovement(actor, "walk", {
    action = "reload", weapon = weapon,
})
check(reloadOk and reloadReason == "reload_started",
    "direct-native adapter verifies reload queue entry")
ISTimedActionQueue.queues[actor] = nil

local window = { opened = false, smashed = false, glassRemoved = false }
function window:IsOpen() return self.opened end
function window:isSmashed() return self.smashed end
function window:isGlassRemoved() return self.glassRemoved end
function window:removeBrokenGlass() self.glassRemoved = true end
function actor:openWindow(value) value.opened = true end
function actor:smashWindow(value) value.smashed = true end
function actor:climbThroughWindow() self.climbing = true end
function actor:isClimbing() return self.climbing == true end
local windowOk, windowReason = SC.Actor.setMovement(actor, "walk", {
    action = "open_window", object = window,
})
check(windowOk and windowReason == "window_opened" and window.opened,
    "direct-native adapter verifies window interaction")
local downedOk = SC.Actor.setMovement(actor, "walk", { action = "downed" })
check(downedOk and actor.knockedDown == true,
    "direct-native adapter verifies native downed state")
local seat = {}
local sitOk, sitReason = SC.Actor.setMovement(actor, "walk", { action = "sit", object = seat })
check(sitOk and sitReason == "sitting" and actor.seatObject == seat,
    "direct-native adapter verifies native furniture sitting")
local groundSitOk, groundSitReason = SC.Actor.setMovement(actor, "walk", {
    action = "sit_ground", reason = "bounded_shutdown_test",
})
check(groundSitOk and groundSitReason == "ground_sit_requested"
        and actor.groundSitting == true and actor.lastEvent == "EventSitOnGround",
    "shutdown requests the verified vanilla ground-sitting event")
local groundStandOk, groundStandReason = SC.Actor.setMovement(actor, "walk", {
    action = "stand_ground", reason = "bounded_shutdown_recovery_test",
})
check(groundStandOk and groundStandReason == "ground_stand_requested"
        and actor.groundSitting == false and actor.lastVariable == "forceGetUp",
    "shutdown recovery requests the vanilla force-get-up transition")
-- The real state machine clears these flags after the animation completes.
-- The lightweight fixture has no animation update loop, so finish it here.
actor.knockedDown = false
actor.climbing = false

local sweepOk, sweepReason = SC.Actor.setMovement(actor, "walk", { action = "room_sweep" })
check(sweepOk and sweepReason == "room_sweep_facing_started" and actor.forwardY > 0.9
    and actor.sitting == false and actor.seatObject == nil,
    "room sweep stands from furniture and verifies native human facing")
actor.forwardX, actor.forwardY = 1, 0
local rightSweepOk = SC.Actor.setMovement(actor, "walk", {
    action = "room_sweep", sweepSide = "right", sweepForwardX = 1, sweepForwardY = 0,
})
check(rightSweepOk and actor.forwardY < -0.9,
    "room-entry sweep can explicitly inspect the right corner from the approach heading")
local actorX, actorY = actor:getX(), actor:getY()
local rearScanOk, rearScanReason = SC.Actor.setMovement(actor, "walk", {
    action = "rear_scan", targetPosition = { x = actorX - 2, y = actorY, z = 0 },
})
check(rearScanOk and rearScanReason == "rear_scan_started" and actor.forwardX < -0.9,
    "rear awareness uses verified native human facing")
local restoreFacingOk, restoreFacingReason = SC.Actor.setMovement(actor, "walk", {
    action = "face_formation", targetPosition = { x = actorX + 2, y = actorY, z = 0 },
})
check(restoreFacingOk and restoreFacingReason == "formation_facing_restored"
    and actor.forwardX > 0.9,
    "formation facing is restored after the rear check")
actor.forwardX, actor.forwardY = 1, 0
local alertFacingOk, alertFacingReason = SC.Actor.setMovement(actor, "walk", {
    action = "face_alert", targetPosition = { x = 0.5, y = 4.5, z = 0 },
})
check(alertFacingOk and alertFacingReason == "alert_facing_started" and actor.forwardY > 0.9,
    "shared danger alert starts and verifies exact native human facing")
actor.forwardX, actor.forwardY, actor.lastEmote = 1, 0, nil
local conversationPoseOk, conversationPoseReason = SC.Actor.setMovement(actor, "walk", {
    action = "conversation_pose", targetPosition = { x = 0.5, y = 4.5, z = 0 }, emote = "yes",
})
check(conversationPoseOk and conversationPoseReason == "conversation_pose_started"
    and actor.forwardY > 0.9 and actor.lastEmote == "yes",
    "conversation pose atomically faces the partner and starts one validated human gesture")
actor.lastEmote = nil
local saluteOk = SC.Actor.setMovement(actor, "walk", {
    action = "hand_signal", emote = "salute",
})
check(saluteOk and actor.lastEmote == "salutecasual",
    "salute UI alias resolves to an installed Build 42 player emote")
do
    pathBehavior.x, pathBehavior.y, pathBehavior.z, pathBehavior.cancelled = 2.5, 0.5, 0, false
    pathBehavior.startedMoving, pathBehavior.turning, pathBehavior.usingPath = false, true, true
    local telemetry = SC.NativeActions.pathTelemetry(actor)
    check(telemetry.available and telemetry.active and telemetry.pending
            and telemetry.turningToObstacle and telemetry.pathNextIsSet
            and telemetry.pathNextX == 1.5 and telemetry.pathNextY == 0.5,
        "native path telemetry exposes pending, turning, and next-node engine state")
    pathBehavior.turning = false
    local nearestOk, nearestReason = SC.NativeActions.pathToNearest(actor, {
        { x = 4, y = 0, z = 0 }, { x = 4, y = 1, z = 0 },
    }, "sneak")
    check(nearestOk and nearestReason == "nearest_path_started"
            and #pathBehavior.nearestLocations == 6 and actor.sneaking == true,
        "native nearest-of-many adapter submits all interaction approaches once")
    SC.NativeActions.stopDirect(actor)
end
actor:pathToLocationF(4.5, 0.5, 0)
check(pathBehavior:shouldBeMoving() and actor:isMoving(),
    "loot ownership regression begins with retained approach pathing")
local visualOk, visualReason = SC.Actor.setMovement(actor, "walk", { action = "loot_container" })
check(visualOk and string.find(visualReason, "visual_timed_action_started", 1, true) ~= nil
    and actor.lastAnimation == "Loot" and pathBehavior.cancelled == true
    and actor:isMoving() == false,
    "external-effect action atomically cancels approach pathing before its verified human timed action")
local visualStartX = actor:getX()
local movedWhileLooting, visualBlockReason = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 1, dy = 0,
})
check(not movedWhileLooting
        and visualBlockReason == "locomotion_protected_activity:active:visual:loot_container"
        and actor:getX() == visualStartX,
    "active loot animation owns the pose and prevents kneeling movement")
local visualQueue = ISTimedActionQueue.getTimedActionQueue(actor)
visualQueue.current:perform()
local completedVisual = SC.NativeActions.visualStatus(actor, "loot_container")
check(completedVisual == "completed", "completed loot animation remains claimable by its effect owner")
local movedBeforeClaim, claimReason = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 1, dy = 0,
})
check(not movedBeforeClaim
        and claimReason == "locomotion_protected_activity:result_pending:visual:loot_container",
    "completed loot animation keeps a bounded transaction claim window")
SC_TEST_CLOCK = SC_TEST_CLOCK + SC.Config.get("visualEffectClaimMs") + 1
local resumedAfterClaim = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 1, dy = 0,
})
check(resumedAfterClaim and actor:getX() > visualStartX,
    "ordinary movement resumes after an unclaimed visual effect expires")
do
    local foreignAction = { source = "ISUnequipAction" }
    actor.characterActions:add(foreignAction)
    local foreignActionX = actor:getX()
    local movedDuringForeignAction, foreignActionReason = SC.Actor.setMovement(actor, "walk", {
        action = "move", dx = 1, dy = 0,
    })
    check(not movedDuringForeignAction
            and string.find(tostring(foreignActionReason), "unfinished_action", 1, true) ~= nil
            and actor:getX() == foreignActionX and actor:isMoving() == false,
        "untracked vanilla timed actions cannot translate a kneeling/action pose: "
            .. tostring(foreignActionReason))
    actor.characterActions:remove(foreignAction)
end
do
    local pacingStarted, pacingReason, pacing = SC.NativeActions.noteResult(
        actor, "core_verified_action", "completed", {
            minimumMs = 1000, maximumMs = 1000, lookChancePercent = 0,
        })
    local pacedX = actor:getX()
    local movedDuringPace, paceBlockReason = SC.Actor.setMovement(actor, "walk", {
        action = "move", dx = 1, dy = 0,
    })
    check(pacingStarted and pacingReason == "pacing_started"
            and pacing.durationMs == 1000 and not movedDuringPace
            and string.find(tostring(paceBlockReason), "action_pacing", 1, true) ~= nil
            and actor:getX() == pacedX,
        "verified results create a bounded human pause that owns ordinary movement")
    actor.running = false
    local urgentMove, urgentReason = SC.Actor.setMovement(actor, "walk", {
        action = "combat_retreat", dx = 1, dy = 0, urgent = true,
    })
    check(urgentMove and urgentReason == "moving"
            and SC.NativeActions.peekPacing(actor) == nil and actor.running == true
            and SC.Locomotion.peek(actor).requestedMode == "walk"
            and SC.Locomotion.peek(actor).effectiveMode == "run"
            and SC.Locomotion.peek(actor).speedOverride == "escape_speed_override",
        "survival-critical escape cancels pacing and overrides a walking policy with running")
    actor.running = true
    local constrainedEscape, constrainedReason = SC.Actor.setMovement(actor, "sneak", {
        action = "ordered_retreat", dx = 1, dy = 0, urgent = true,
        nativeAffordance = "stairs",
    })
    check(constrainedEscape and constrainedReason == "moving" and actor.running == false
            and SC.Locomotion.peek(actor).requestedMode == "sneak"
            and SC.Locomotion.peek(actor).effectiveMode == "walk"
            and SC.Locomotion.peek(actor).speedOverride == "escape_constrained:stairs",
        "escape speed safely walks a native stair transition before resuming the run override")
    local copiedPosture, postureReason = SC.Actor.setMovement(actor, "walk", {
        action = "copy_player_posture", sneaking = true,
    })
    actor.__copiedSetCalls = actor.sneakSetCalls
    actor.__copiedAgain = SC.Actor.setMovement(actor, "walk", {
        action = "copy_player_posture", sneaking = true,
    })
    check(copiedPosture and postureReason == "copy_posture_crouched"
            and actor.__copiedAgain and actor:isSneaking()
            and actor.sneakSetCalls == actor.__copiedSetCalls,
        "Copy player retains verified crouch without resetting the posture every decision")
    actor.__copiedSetCalls, actor.__copiedAgain = nil, nil
end
local collisionStartX = actor:getX()
actor.continuousCollisionBlocked = true
local blockedByPolygon, polygonReason = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 1, dy = 0,
})
check(not blockedByPolygon and polygonReason == "continuous_collision_blocked"
        and actor:getX() == collisionStartX,
    "direct movement obeys the native door-aware continuous polygon collision probe")
actor.continuousCollisionBlocked = false
ISTimedActionQueue.queues[actor] = nil
local testWearLocation = {}
WearClothingAnimations = { [testWearLocation] = "Jacket" }
local wearOk, wearReason = SC.Actor.setMovement(actor, "walk", {
    action = "wear_clothing", wearLocation = testWearLocation,
})
check(wearOk and string.find(wearReason, "visual_timed_action_started", 1, true) ~= nil
    and actor.lastAnimation == "WearClothing"
    and actor.lastAnimVariable.key == "WearClothingLocation"
    and actor.lastAnimVariable.value == "Jacket",
    "clothing visuals use the exact Build 42 body-location animation mapping")
check(SC.NativeActions.cancelVisual(actor, "test_visual_complete"),
    "clothing visual fixture cancels cleanly")
ISTimedActionQueue.queues[actor] = nil
local book = { getReadType = function() return "book" end }
local readOk, readReason = SC.Actor.setMovement(actor, "walk", {
    action = "read", item = book,
})
check(readOk and string.find(readReason, "visual_timed_action_started", 1, true) ~= nil
        and actor.lastAnimation == CharacterActionAnims.Read and actor.reading == true
        and actor.lastAnimVariable.key == "ReadType" and actor.lastAnimVariable.value == "book",
    "reading uses the exact CharacterActionAnims enum and vanilla ReadType state")
check(SC.NativeActions.cancelVisual(actor, "test_visual_complete"),
    "reading visual fixture cancels cleanly")
local barricadeOk, barricadeReason = SC.Actor.setMovement(actor, "walk", {
    action = "barricade", object = barricadeObject,
})
check(barricadeOk and barricadeReason == "provider_barricade_started"
    and directProvider.lastBarricade == barricadeObject,
    "barricade intent reaches the native provider as a real work action")
local removeOk, removeReason = SC.Actor.setMovement(actor, "walk", {
    action = "remove_barricade", object = barricadeObject,
})
check(removeOk and removeReason == "provider_remove_barricade_started"
    and directProvider.lastRemovedBarricade == barricadeObject,
    "remove-barricade intent reaches the native provider as a real work action")
local dismantleOk, dismantleReason = SC.Actor.setMovement(actor, "walk", {
    action = "dismantle", object = barricadeObject,
})
check(dismantleOk and dismantleReason == "provider_dismantle_started"
    and directProvider.lastDismantled == barricadeObject,
    "dismantle intent reaches the native provider as a real work action")

-- Combat fixtures above intentionally use method-minimal pseudo weapons which
-- are not inventory items.  Clear those hands before exercising persistence;
-- the persistence contract correctly rejects an equipped object with no
-- stable full item type.
actor.primaryHand, actor.secondaryHand = nil, nil
local priorPlayerData = {
    SC_SaveV1 = { schema = 1, companions = { sentinel = true } },
}
local transactionalPlayer = {}
function transactionalPlayer:getModData() return priorPlayerData end
local priorDocument = priorPlayerData.SC_SaveV1
actor.bodyUnavailable = true
local failedSave = SC.Persistence.save(transactionalPlayer)
check(failedSave == false and priorPlayerData.SC_SaveV1 == priorDocument,
    "active capture failure aborts the entire save and retains the prior snapshot")
actor.bodyUnavailable = false
local successfulSave, successfulDocument = SC.Persistence.save(transactionalPlayer)
check(successfulSave and successfulDocument.companions[record.id] ~= nil,
    "healthy active record commits transactionally after a prior failure: "
        .. tostring(successfulDocument))

local corpseActor = setmetatable({
    __owned = true, __class = "IsoPlayer", data = {}, square = square,
    dead = true, deathDone = false,
}, { __index = actor })
local corpseRecord = SC.Registry.register(corpseActor, {
    id = "sc-death-contract", recruited = true,
})
check(corpseRecord ~= nil, "death-contract actor registers")
local deathSaveOk, deathDocument = SC.Persistence.save(transactionalPlayer)
check(deathSaveOk and deathDocument.companions[corpseRecord.id] == nil
    and deathDocument.companions[record.id] ~= nil,
    "native death is omitted immediately from persistence without aborting healthy companions")
local earlyRetired, earlyReason = SC.Actor.retireDead(corpseActor)
check(not earlyRetired and earlyReason == "death_pending"
    and SC.Registry.byId(corpseRecord.id) ~= nil,
    "roster ownership remains until native corpse creation finishes")
corpseActor.deathDone = true
local finalRetired, finalRecord = SC.Actor.retireDead(corpseActor)
check(finalRetired and finalRecord.permadead == true
    and SC.Registry.byId(corpseRecord.id) == nil and corpseActor.__owned == false,
    "finalized corpse retires permanently without provider world removal")

local partialRemovalProvider = {
    testOnly = true,
    kind = "experimental-npc-player",
    directNative = true,
    removeCalls = 0,
}
function partialRemovalProvider:isActor(candidate) return candidate ~= nil and candidate.__owned == true end
function partialRemovalProvider:remove(candidate)
    self.removeCalls = self.removeCalls + 1
    if self.removeCalls == 1 then
        candidate.partialWorldRemoval = true
        return false, "injected partial world removal"
    end
    candidate.__owned = false
    return true
end
check(SC.Actor._setProviderForTests(partialRemovalProvider),
    "partial-removal regression selects explicit provider")
local removed, removalReason = SC.Actor.remove(actor)
local quarantined = SC.Registry.byId(record.id)
check(not removed and string.find(tostring(removalReason), "inactive", 1, true) ~= nil
    and quarantined ~= nil and quarantined.runtime.inactive == true
    and not SC.Actor.isCompanion(actor) and #SC.Registry.living() == 0,
    "unverified removal quarantines the registry record and blocks further actor work")
local quarantineSaved, quarantineDocument = SC.Persistence.save(transactionalPlayer)
check(quarantineSaved and quarantineDocument.companions[record.id] ~= nil,
    "quarantined actor re-emits its bounded last stable snapshot")
check(SC.Actor.remove(actor) == true and partialRemovalProvider.removeCalls == 2
        and SC.Registry.byId(record.id) == nil,
    "quarantined removal retains a callable cleanup retry")

SC.Persistence.reset()
local invalidDocument = { schema = 99, companions = { untouched = true } }
local invalidData = { SC_SaveV1 = invalidDocument }
local invalidPlayer = {}
function invalidPlayer:getModData() return invalidData end
local invalidRestored = SC.Persistence.restore(invalidPlayer)
local invalidSaved = SC.Persistence.save(invalidPlayer)
check(not invalidRestored and not invalidSaved and invalidData.SC_SaveV1 == invalidDocument,
    "unsupported save schema is retained without destructive overwrite")
SC.Persistence.reset()

local playerData = {
    OtherMod = { untouched = true },
    SC_SaveV1 = {
        schema = 1,
        companions = {
            ["sc-pending-record"] = {
                id = "sc-pending-record",
                recruited = true,
                identity = { forename = "Avery", surname = "Reed", gender = "female", outfit = "" },
                position = { x = 100, y = 100, z = 0 },
                inventory = {}, skills = {}, vitals = {}, order = {},
            },
        },
    },
}
local player = {}
function player:getModData() return playerData end
local restored = SC.Persistence.restore(player)
check(restored and SC.Persistence.pendingCount() == 1, "unavailable square remains pending")
SC_TEST_CLOCK = SC_TEST_CLOCK + 60000
SC.Persistence.restorePulse(player)
player.__unloadedSnapshot = SC.Persistence.pendingSnapshot()["sc-pending-record"]
check(player.__unloadedSnapshot and player.__unloadedSnapshot.attempts == 0
        and player.__unloadedSnapshot.status == "waiting_environment",
    "an unloaded square waits without consuming destructive restore attempts")
local saved, document = SC.Persistence.save(player)
check(saved and document.companions["sc-pending-record"] ~= nil,
    "provider/square failure cannot erase a pending save record")
check(playerData.OtherMod.untouched == true, "unrelated mod data is preserved")

function runPersistenceIntegrityChecks()
SC.Persistence.reset()
local rawInvalid = {
    id = "sc-invalid-raw", recruited = true,
    identity = { forename = "Raw", surname = "Record" },
    position = { x = 10, y = 10, z = 0 },
    inventory = { schema = 2, complete = true, count = 0, roots = {},
        equipment = { primary = "missing", worn = {}, attached = {} } },
    skills = {}, vitals = {}, order = {},
}
local mixedData = { SC_SaveV1 = {
    schema = SC.Identity.saveSchema, companions = {
        ["sc-valid-pending"] = {
            id = "sc-valid-pending", recruited = true,
            identity = { forename = "Valid", surname = "Record" },
            position = { x = 20, y = 20, z = 0 }, inventory = {},
            skills = {}, vitals = {}, order = {},
        },
        ["sc-invalid-raw"] = rawInvalid,
    },
    community = { version = 2, minds = "malformed", pairs = {}, history = {}, deaths = {} },
} }
local mixedPlayer = { getModData = function() return mixedData end }
local priorCommunity = SC.Community
SC.Community = {
    restore = function() return false, "injected malformed community" end,
    export = function() return { version = 2, minds = {}, pairs = {}, history = {}, deaths = {} } end,
}
check(SC.Persistence.restore(mixedPlayer),
    "a malformed record is isolated without disabling valid pending records")
local quarantineState = SC.Persistence.quarantineSnapshot()
check(SC.Persistence.isPending("sc-valid-pending")
        and quarantineState.companions["sc-invalid-raw"] ~= nil
        and quarantineState.subsystems.community ~= nil,
    "invalid companion and subsystem state are observable in raw quarantine")
local mixedSaved, mixedDocument = SC.Persistence.save(mixedPlayer)
local preservedInvalid = mixedDocument and mixedDocument.companions["sc-invalid-raw"]
check(mixedSaved and preservedInvalid.inventory.equipment.primary == "missing"
        and mixedDocument.community.minds == "malformed",
    "load-save preserves rejected companion and subsystem values verbatim")
SC.Community = priorCommunity

SC.Persistence.reset()
local cyclicRaw = {
    id = "sc-cyclic-raw", recruited = true,
    identity = { forename = "Cycle", surname = "Guard" },
    position = { x = 30, y = 30, z = 0 }, inventory = {},
    skills = {}, vitals = {}, order = {},
}
cyclicRaw.identity.loop = cyclicRaw.identity
local cyclicDocument = { schema = SC.Identity.saveSchema,
    companions = { ["sc-cyclic-raw"] = cyclicRaw } }
local cyclicData = { SC_SaveV1 = cyclicDocument }
local cyclicPlayer = { getModData = function() return cyclicData end }
local cyclicRestored, cyclicRestoreReason = SC.Persistence.restore(cyclicPlayer)
check(not cyclicRestored
        and cyclicData.SC_SaveV1 == cyclicDocument
        and string.find(tostring(cyclicRestoreReason), "cannot be preserved", 1, true),
    "cyclic full-envelope input is rejected before restore and retained exactly")
local cyclicSaved, cyclicReason = SC.Persistence.save(cyclicPlayer)
check(not cyclicSaved and cyclicData.SC_SaveV1 == cyclicDocument
        and string.find(tostring(cyclicReason), "preserved without overwrite", 1, true),
    "blocked cyclic restore keeps OnSave fail-closed and the prior document untouched")

SC.Persistence.reset()
local deterministicProvider = { testOnly = true, kind = "iso-companion", polls = 0 }
function deterministicProvider:isActor() return false end
function deterministicProvider:requestSpawn() return 501 end
function deterministicProvider:pollSpawn()
    self.polls = self.polls + 1
    return nil, "unknown perk in save record: MissingPerk"
end
function deterministicProvider:cancelSpawn() return true end
check(SC.Actor._setProviderForTests(deterministicProvider),
    "deterministic restore-failure provider installed")
local priorGetCell = getCell
getCell = function()
    return { getGridSquare = function() return square end }
end
local terminalData = { SC_SaveV1 = { schema = SC.Identity.saveSchema, companions = {
    ["sc-terminal-restore"] = {
        id = "sc-terminal-restore", recruited = true,
        identity = { forename = "Terminal", surname = "Retry" },
        position = { x = 40, y = 40, z = 0 }, inventory = {},
        skills = { { id = "MissingPerk", level = 1 } }, vitals = {}, order = {},
    },
} } }
local terminalPlayer = { getModData = function() return terminalData end }
check(SC.Persistence.restore(terminalPlayer), "terminal restore document imports")
local terminalSnapshot = SC.Persistence.pendingSnapshot()["sc-terminal-restore"]
check(terminalSnapshot and terminalSnapshot.status == "quarantined"
        and terminalSnapshot.failureClass == "permanent" and terminalSnapshot.attempts == 1,
    "deterministic incompatibility enters terminal quarantine after one attempt")
SC_TEST_CLOCK = SC_TEST_CLOCK + 600000
SC.Persistence.restorePulse(terminalPlayer)
check(deterministicProvider.polls == 1,
    "terminal quarantine stops repeated native spawn work")
check(SC.Persistence.retry("sc-terminal-restore"), "manual retry resets terminal bound")
SC.Persistence.restorePulse(terminalPlayer)
check(deterministicProvider.polls == 2,
    "manual retry performs exactly one new deterministic attempt")
getCell = priorGetCell
SC.Persistence.reset()

local restoreValues = SC.Config._values
local savedRestoreInterval = restoreValues.restoreIntervalMs
local savedRestoreBackoff = restoreValues.restoreMaximumBackoffMs
local savedRestoreAttempts = restoreValues.restoreMaximumAttempts
restoreValues.restoreIntervalMs = 100
restoreValues.restoreMaximumBackoffMs = 1000
restoreValues.restoreMaximumAttempts = 3
getCell = function()
    return { getGridSquare = function() return square end }
end

local startingProvider = {
    testOnly = true, kind = "iso-companion", ready = false, requests = 0, polls = 0,
}
function startingProvider:isActor() return false end
function startingProvider:requestSpawn()
    self.requests = self.requests + 1
    if not self.ready then return nil, "provider is still starting" end
    return 601
end
function startingProvider:pollSpawn()
    self.polls = self.polls + 1
    return nil, "unknown perk in save record: StartupPerk"
end
function startingProvider:cancelSpawn() return true end
check(SC.Actor._setProviderForTests(startingProvider),
    "starting restore provider installed")
local startingData = { SC_SaveV1 = { schema = SC.Identity.saveSchema, companions = {
    ["sc-provider-starting"] = {
        id = "sc-provider-starting", recruited = true,
        identity = { forename = "Waiting", surname = "Bridge" },
        position = { x = 41, y = 41, z = 0 }, inventory = {},
        skills = {}, vitals = {}, order = {},
    },
} } }
local startingPlayer = { getModData = function() return startingData end }
check(SC.Persistence.restore(startingPlayer), "provider-starting record imports")
local startingSnapshot = SC.Persistence.pendingSnapshot()["sc-provider-starting"]
check(startingSnapshot and startingSnapshot.status == "waiting_environment"
        and startingSnapshot.failureClass == "transient"
        and startingSnapshot.attempts == 0 and startingProvider.requests == 1,
    "provider startup waits without consuming the destructive retry budget")
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
startingProvider.ready = true
SC.Persistence.restorePulse(startingPlayer)
startingSnapshot = SC.Persistence.pendingSnapshot()["sc-provider-starting"]
check(startingProvider.requests == 2 and startingProvider.polls == 1
        and startingSnapshot.status == "quarantined"
        and startingSnapshot.attempts == 1,
    "a provider becoming ready resumes the preserved record immediately")
SC.Persistence.reset()

local retryProvider = {
    testOnly = true, kind = "iso-companion", requests = 0,
}
function retryProvider:isActor() return false end
function retryProvider:requestSpawn()
    self.requests = self.requests + 1
    return nil, "temporary native queue failure"
end
check(SC.Actor._setProviderForTests(retryProvider),
    "retryable restore provider installed")
local retryData = { SC_SaveV1 = { schema = SC.Identity.saveSchema, companions = {
    ["sc-retry-backoff"] = {
        id = "sc-retry-backoff", recruited = true,
        identity = { forename = "Retry", surname = "Bounded" },
        position = { x = 42, y = 42, z = 0 }, inventory = {},
        skills = {}, vitals = {}, order = {},
    },
} } }
local retryPlayer = { getModData = function() return retryData end }
local retryStart = SC_TEST_CLOCK
check(SC.Persistence.restore(retryPlayer), "retryable restore record imports")
local retrySnapshot = SC.Persistence.pendingSnapshot()["sc-retry-backoff"]
check(retryProvider.requests == 1 and retrySnapshot.attempts == 1
        and retrySnapshot.nextAt == retryStart + 100,
    "first retryable failure schedules the configured base delay")
SC_TEST_CLOCK = retryStart + 99
SC.Persistence.restorePulse(retryPlayer)
check(retryProvider.requests == 1,
    "retryable restore does not run before its deterministic deadline")
SC_TEST_CLOCK = retryStart + 100
SC.Persistence.restorePulse(retryPlayer)
retrySnapshot = SC.Persistence.pendingSnapshot()["sc-retry-backoff"]
check(retryProvider.requests == 2 and retrySnapshot.attempts == 2
        and retrySnapshot.nextAt == retryStart + 300,
    "retryable restore doubles its deterministic delay")
SC_TEST_CLOCK = retryStart + 300
SC.Persistence.restorePulse(retryPlayer)
retrySnapshot = SC.Persistence.pendingSnapshot()["sc-retry-backoff"]
check(retryProvider.requests == 3 and retrySnapshot.attempts == 3
        and retrySnapshot.status == "quarantined" and retrySnapshot.nextAt == nil,
    "retryable restore stops at the configured attempt bound")
SC.Persistence.reset()
getCell = priorGetCell
restoreValues.restoreIntervalMs = savedRestoreInterval
restoreValues.restoreMaximumBackoffMs = savedRestoreBackoff
restoreValues.restoreMaximumAttempts = savedRestoreAttempts
end
runPersistenceIntegrityChecks()
runPersistenceIntegrityChecks = nil

function runFailedPollOwnershipChecks()
local failedPollProvider = {
    testOnly = true, kind = "iso-companion", directNative = true,
    cancelCalls = 0,
}
function failedPollProvider:isActor() return false end
function failedPollProvider:requestSpawn() return 76 end
function failedPollProvider:pollSpawn() error("injected provider poll failure") end
function failedPollProvider:cancelSpawn()
    self.cancelCalls = self.cancelCalls + 1
    if self.cancelCalls == 1 then return false, "injected cancellation failure" end
    return true
end
check(SC.Actor._setProviderForTests(failedPollProvider),
    "failed-poll ownership fixture selects explicit provider")
local failedPollTicket = SC.Actor.beginSpawn(square, {
    id = "sc-failed-poll-ticket", recruited = false,
})
local failedPollActor, failedPollStatus, failedPollReason = SC.Actor.pollSpawn(failedPollTicket)
check(failedPollActor == nil
        and failedPollStatus == "spawn_pending"
        and string.find(tostring(failedPollReason), "cleanup is pending", 1, true) ~= nil
        and failedPollProvider.cancelCalls == 1,
    "provider exception plus failed cancellation retains the Lua spawn ticket")
check(SC.Actor.cancelSpawn(failedPollTicket)
        and failedPollProvider.cancelCalls == 2,
    "retained spawn ticket releases only after a verified cancellation retry")
local consumedPollActor, consumedPollReason = SC.Actor.pollSpawn(failedPollTicket)
check(consumedPollActor == nil and consumedPollReason == "invalid spawn ticket",
    "verified cancellation is the only point that releases Lua ticket ownership")
end
runFailedPollOwnershipChecks()
runFailedPollOwnershipChecks = nil

local deferredActor = setmetatable({
    __owned = false, __class = "IsoPlayer", data = {}, square = square,
}, { __index = actor })
local deferredProvider = {
    testOnly = true,
    kind = "iso-companion",
    directNative = true,
    polls = 0,
}
function deferredProvider:isActor(candidate)
    return candidate == deferredActor and candidate.__owned == true
end
function deferredProvider:requestSpawn()
    self.requested = true
    return 77
end
function deferredProvider:pollSpawn(request)
    check(request == 77, "deferred provider receives its opaque request id")
    self.polls = self.polls + 1
    if self.polls == 1 then return nil, "spawn_pending" end
    deferredActor.__owned = true
    return deferredActor
end
function deferredProvider:cancelSpawn() return true end
function deferredProvider:remove(candidate)
    candidate.__owned = false
    return true
end
check(SC.Actor._setProviderForTests(deferredProvider),
    "deferred-spawn regression selects explicit provider")
local ticket, beginReason = SC.Actor.beginSpawn(square, {
    id = "sc-deferred-spawn",
    recruited = false,
    identity = { forename = "Queue", surname = "Safe", gender = "female" },
})
check(ticket ~= nil and beginReason == "spawn_pending" and deferredProvider.requested,
    "native spawn begins as an opaque deferred request")
local notReady, pendingReason = SC.Actor.pollSpawn(ticket)
check(notReady == nil and pendingReason == "spawn_pending"
    and SC.Registry.byId("sc-deferred-spawn") == nil,
    "pending native creation cannot register a half-built actor")
local deferredReady, deferredRecord = SC.Actor.pollSpawn(ticket)
check(deferredReady == deferredActor and deferredRecord.id == "sc-deferred-spawn"
    and SC.Registry.byId("sc-deferred-spawn").actor == deferredActor,
    "completed deferred creation passes the normal transactional finalizer exactly once")
check(SC.Actor.remove(deferredActor), "deferred-spawn fixture removes transactionally")

function runLocomotionRecorderChecks()
    local originalConfigGet = SC.Config.get
    SC.Config.get = function(section, key)
        if key == nil and section == "movementRecorderEnabled" then return true end
        return originalConfigGet(section, key)
    end
    local movementActor = setmetatable({
        __owned = true, __class = "IsoPlayer", data = {}, square = square,
        characterActions = actionList(),
    }, { __index = actor })
    local authorized, phase = SC.Locomotion.authorize(movementActor, "run", {
        action = "follow_formation", targetSquare = square, nextSquare = square,
    })
    SC.Locomotion.noteResult(movementActor, authorized, "moving", "run", {
        action = "follow_formation", targetSquare = square, nextSquare = square,
    })
    local snapshot = SC.Locomotion.snapshot(movementActor)
    check(authorized and phase == "run" and snapshot.phase == "run"
            and snapshot.owner == "locomotion" and #snapshot.events >= 2,
        "the locomotion state machine records one authoritative movement transition and result")

    local oldActivityStatus = SC.NativeActions.activityStatus
    SC.NativeActions.activityStatus = function()
        return "active", "visual", "loot", SC_TEST_CLOCK
    end
    local rejected, reason = SC.Locomotion.authorize(movementActor, "walk", {
        action = "follow_formation", targetSquare = square,
    })
    SC.NativeActions.activityStatus = oldActivityStatus
    check(not rejected and reason == "locomotion_protected_activity:active:visual:loot"
            and SC.Locomotion.peek(movementActor).phase == "interact",
        "ordinary path movement cannot override a visual animation owner")

    SC.Locomotion.recordNavigation(movementActor, "blocker", {
        blocker = "door", recovery = "lateral_clearance", targetSquare = square,
    })
    Clipboard = { setClipboard = function(value) Clipboard.copied = value end }
    local copied, copiedReason, copiedText = SC.Support.copyMovement(movementActor)
    check(copied and copiedReason == "Movement report copied to the clipboard."
            and Clipboard.copied == copiedText
            and string.find(copiedText, "Living Fellows movement recorder", 1, true)
            and string.find(copiedText, "nav_blocker", 1, true),
        "the bounded movement recorder produces a copyable selected-companion report")
    SC.Locomotion.reset(movementActor)
    SC.Config.get = originalConfigGet
end
runLocomotionRecorderChecks()
runLocomotionRecorderChecks = nil

function runSupportReportChecks()
    local supportStatus = SC.Support.snapshot(false)
    check(supportStatus.bridge.ready == true
            and supportStatus.bridge.code == "ready"
            and supportStatus.bridge.provider == "iso-companion"
            and type(supportStatus.actionSupervisor) == "table"
            and type(supportStatus.companionActions) == "table",
        "support snapshot exposes the selected native provider without mutating it")
    SC.Diagnostics.report("support-path", nil,
        "C:\\Users\\Tester\\Zomboid\\console.txt")
    Clipboard = {
        setClipboard = function(value) Clipboard.copied = value end,
    }
    local copied, copiedReason, copiedText = SC.Support.copySummary(false)
    check(copied and copiedReason == "Support report copied to the clipboard."
            and Clipboard.copied == copiedText
            and string.find(copiedText, "Living Fellows support report", 1, true) ~= nil
            and string.find(copiedText, "Bridge: ready", 1, true) ~= nil
            and string.find(copiedText, "Action supervisor:", 1, true) ~= nil
            and string.find(copiedText, "C:\\Users\\Tester", 1, true) == nil,
        "bounded support report includes action health and redacts private paths")
    SC.Diagnostics.disable("support-retry-test", nil, "injected manual latch")
    local retryOk, retryCount = SC.Support.retryFailures()
    check(retryOk and retryCount >= 1
            and not SC.Diagnostics.isDisabled("support-retry-test", nil),
        "support action clears failed subsystem circuits and rechecks the provider")
end
runSupportReportChecks()
runSupportReportChecks = nil

print("CORE_KAHLUA_PASS checks=" .. tostring(checks))
