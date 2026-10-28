-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
check(type(SC) == "table" and SC.Identity.worldSaveKey == "SC_WorldV1"
        and SC.Identity.saveSchema == 3, "namespace identity")
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
    -- Game code writes some item modData from Java: torn sheets keep their
    -- filterLife as a boxed Float. The test runner provides one, and a plain
    -- Java object, as the real userdata they are in game.
    local foreign = { filterLife = SC_TEST_BOXED_FLOAT, handle = SC_TEST_JAVA_OBJECT, kept = "yes" }
    local strictCopy, strictReason = SC.StableValue.copyStrict(foreign, {
        maxDepth = 2, maxEntries = 8, path = "$.item.modData",
    })
    local lenient, lenientReason = SC.StableValue.copyStrict(foreign, {
        maxDepth = 2, maxEntries = 8, path = "$.item.modData", foreignScalars = true,
    })
    check(type(SC_TEST_BOXED_FLOAT) == "userdata" and type(SC_TEST_JAVA_OBJECT) == "userdata"
            and strictCopy == nil
            and string.find(tostring(strictReason), "unsupported userdata", 1, true) ~= nil
            and lenient ~= nil and lenientReason == nil and lenient.filterLife == 0.75
            and lenient.handle == nil and lenient.kept == "yes",
        "a boxed Java number in item modData copies as a number and other Java objects are left out: "
            .. tostring(lenientReason))
end
local immutable = pcall(function() SC.Config.defaults.frameBudgetMs = 99 end)
check(not immutable and SC.Config.get("frameBudgetMs") == 3, "configuration is immutable")
do
    local priorSandbox = SandboxVars
    SandboxVars = { LivingFellows = {
        EncountersEnabled = false, EncounterFrequency = 4, MaxCompanions = 9,
        CompanionNeedsRate = 0.75, HouseholdSpawnsEnabled = false,
        HouseholdDailyChance = 17, MaxHouseholds = 1, UIOpacity = 0.44,
        ShowCompanionNames = false, ExpeditionDestinationScope = 2,
    } }
    local refreshed = SC.Config.refreshSandbox()
    check(refreshed and SC.Config.get("productionEncounterEnabled") == false
        and SC.Config.get("productionSpawnCooldownMs") == 120000
        and SC.Config.get("maxCompanions") == 9
        and SC.Config.get("needsRateMultiplier") == 0.75
        and SC.Config.get("factionEnabled") == false
        and SC.Config.get("factionDailySpawnChancePercent") == 17
        and SC.Config.get("factionMaxHouseholds") == 1
        and SC.Config.get("uiPanelOpacity") == 0.44
        and SC.Config.get("companionNameLabels") == false
        and SC.Config.get("expeditionDestinationScope") == "known_only",
        "sandbox options override the single canonical runtime configuration")
    SandboxVars = priorSandbox
    SC.Config.refreshSandbox()
    check(SC.Config.get("maxCompanions") == 16 and SC.Config.get("factionMaxHouseholds") == 3
        and SC.Config.get("companionNameLabels") == true
        and SC.Config.get("expeditionDestinationScope") == "all_nearby",
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
    function list:get(index) return self.values[index + 1] end
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
    endurance = 0.65,
    perks = { [Perks.Strength] = 5, [Perks.Fitness] = 5 },
    moodleLevels = {},
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
function actor:getStats()
    local owner = self
    return {
        get = function(_, stat)
            if stat == CharacterStat.ENDURANCE then return owner.endurance end
            return 0
        end,
    }
end
function actor:getPerkLevel(perk) return self.perks[perk] or 0 end
function actor:getMoodles()
    local owner = self
    return {
        getMoodleLevel = function(_, moodle) return owner.moodleLevels[moodle] or 0 end,
    }
end
function actor:getXp() return {} end
function actor:getEmitter() return {} end
function actor:getVisual() return {} end
function actor:getForwardDirectionX() return self.forwardX end
function actor:getForwardDirectionY() return self.forwardY end
function actor:CanSee(target)
    return target ~= nil and target.hidden ~= true
end
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
function actor:hasFootInjury() return self.footInjury == true end
function actor:getSneakLimpSpeedScale() return self.limpSpeedScale or 1 end
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
function actor:resetModelNextFrame() self.modelResetCount = (self.modelResetCount or 0) + 1 end
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
function actor:isAimAtFloor() return self.aimAtFloor == true end
function actor:setCompanionFloorAttackInput(enabled, stomp)
    self.floorInput, self.stompInput = enabled == true, stomp == true
    return true
end
function actor:setCompanionAimTarget(value) self.companionAimTarget = value end
function actor:setCompanionFloorTarget(value) self.targetOnGround = value end
function actor:getCompanionAttackCollisionSerial()
    return self.companionAttackCollisionSerial or 0
end
function actor:getCompanionAttackCollisionHitCount()
    return self.companionAttackCollisionHitCount or 0
end
function actor:getCompanionAttackCollisionTarget()
    return self.companionAttackCollisionTarget
end
function actor:didCompanionAttackCollisionHitTarget()
    return self.companionAttackCollisionTargetHit == true
end
-- CB-09: the bridge publishes a terminal receipt on both the completing and
-- the throwing path, on counters kept separate from the completed-hit serial.
function actor:getCompanionAttackAttemptSerial()
    return self.companionAttackAttemptSerial or 0
end
function actor:getCompanionAttackReceiptSerial()
    return self.companionAttackReceiptSerial or 0
end
function actor:getCompanionAttackReceiptOutcome()
    return self.companionAttackReceiptOutcome or "none"
end
function actor:getCompanionAttackReceiptCause()
    return self.companionAttackReceiptCause or ""
end
local bareHandsWeapon = {
    __class = "HandWeapon",
    getType = function() return "BareHands" end,
    getFullType = function() return "Base.BareHands" end,
}
actor.bareHandsWeapon = bareHandsWeapon
function actor:getUseHandWeapon() return self.useHandWeapon end
function actor:getWornItems()
    local owner = self
    local entries = owner.wornShoes and { owner.wornShoes } or {}
    return {
        size = function() return #entries end,
        get = function(_, index)
            local candidate = entries[index + 1]
            if not candidate then return nil end
            return {
                getItem = function() return candidate end,
                getLocation = function() return "Shoes" end,
            }
        end,
    }
end
function actor:getWornItem() return self.wornShoes end
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
    self.useHandWeapon = self.doShove and self.bareHandsWeapon or self.primaryHand
    return true
end
function actor:DoAttack()
    self.doAttackCalls = (self.doAttackCalls or 0) + 1
    if not self:isAuthorizedHandToHandAction() then return false end
    self.attackStarted = true
    return false
end
function actor:isAttackStarted() return self.attackStarted == true end
function actor:getMeleeDelay() return self.meleeDelay or 0 end
function actor:getRecoilDelay() return self.recoilDelay or 0 end
function actor:setCompanionMovementTarget(x, y, z, tolerance, ttlMs)
    self.movementTarget = { x = x, y = y, z = z, tolerance = tolerance, ttlMs = ttlMs }
    return true
end
function actor:setKnockedDown(value) self.knockedDown = value end
function actor:isKnockedDown() return self.knockedDown == true end
function actor:setSitOnFurnitureObject(value) self.seatObject = value end
function actor:getSitOnFurnitureObject() return self.seatObject end
function actor:setSittingOnFurniture(value) self.sitting = value end
function actor:isSittingOnFurniture() return self.sitting == true end
function actor:getCurrentActionContextStateName() return self.actionContextName or "idle" end
function actor:isOnBed() return self.onBed == true end
function actor:setOnBed(value) self.onBed = value == true end
function actor:setbOnBed(value) self.onBed = value == true end
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
                background = { occupation = "carpenter" }, care = {}, reveals = {},
                ritual = { id = "gnome_commander", completions = 2 } },
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
    source.state.personality.ritual.id = "mutated"
    check(copied and copied.identity.forename == "Owned"
            and copied.memories[1].text == "original"
            and copied.state.personality.ritual.id == "gnome_commander"
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
do
check(actor.data.SC_PlayerAttackProtected == true,
    "a recruited, peaceful companion publishes the native player-hit protection marker")
actor.__migratedMovement.care.playerHostile = true
check(SC.Commands.persist(actor) and actor.data.SC_PlayerAttackProtected == false,
    "a companion hostile to the player remains hittable")
actor.__migratedMovement.care.playerHostile = false
check(SC.Commands.persist(actor) and actor.data.SC_PlayerAttackProtected == true,
    "a peaceful relationship restores the native player-hit marker")
actor.__migratedMovement.care.playerCeasefire = true
check(SC.Commands.persist(actor) and actor.data.SC_PlayerAttackProtected == false,
    "a conditional ceasefire leaves the survivor hittable for renewed conflict")
actor.__migratedMovement.care.playerCeasefire = false
check(SC.Commands.persist(actor) and actor.data.SC_PlayerAttackProtected == true,
    "clearing the ceasefire restores the peaceful native marker")
check(SC.BaseLife.setRestriction(record.id, "exiled")
        and actor.data.SC_PlayerAttackProtected == false,
    "exile makes the former ally hittable immediately")
check(SC.BaseLife.setRestriction(record.id, nil)
        and actor.data.SC_PlayerAttackProtected == true,
    "lifting exile refreshes player-hit protection immediately")
local peacefulBaseState = SC.BaseLife.export()
local exiledBaseState = SC.BaseLife.export()
exiledBaseState.restrictions[record.id] = "exiled"
check(SC.BaseLife.restore(exiledBaseState)
        and actor.data.SC_PlayerAttackProtected == false,
    "restored exile clears the native marker even after command state is loaded")
check(SC.BaseLife.restore(peacefulBaseState)
        and actor.data.SC_PlayerAttackProtected == true,
    "restoring a world without exile refreshes the native marker")
end
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
check(SC.Commands.issue(record.id, "set_weapon_priority", { priority = "quiet" }, nil)
        and SC.Commands.issue(record.id, "set_hold_fire", { enabled = true }, nil)
        and SC.Commands.issue(record.id, "set_combat_doctrine", { doctrine = "ranged_support" }, nil),
    "doctrine, weapon priority, and hold-fire remain independent policy controls")
check(SC.Commands.issue(record.id, "set_group", { group = "Bravo" }, nil),
    "command adapter accepts persistent group")
check(SC.Commands.issue(record.id, "set_work_mode", { mode = "craft" }, nil),
    "command adapter accepts persistent work mode")
local ritualState = SC.Commands.peek(actor)
ritualState.ritual = {
    version = 1, id = "rubber_duck_oracle", completions = 3, stage = "routine",
    lastAt = 12345, duck = {
        relicKey = "sc-core-actor:ritual:duck", phase = "recovery_pending",
        baseId = "test-base", x = 4, y = 5, z = 0,
    },
}
ritualState.tales = {
    version = 1,
    list = { { id = "tale:core", day = 11, place = "the church", placeKind = "room",
        timeOfDay = "night", kills = 7, closeCall = "grabbed", weapon = "crowbar",
        witnesses = { "sc-core-witness" }, playerThere = true, tellings = 2,
        lastToldHour = 250 } },
    witnessed = { { id = "tale:other", teller = "sc-core-teller", kills = 4 } },
}
ritualState.flavor = { version = 1, placesSeen = { police = true }, storiesTold = {},
    lastWorkoutDay = 11 }
ritualState.followCarSqlId = 501
check(SC.Commands.persist(actor), "personal ritual state commits through Commands")
local commandSnapshot, commandSnapshotReason = SC.Persistence.captureRecord(record)
check(SC.SpeechColors.valid(record.speechColorKey)
    and commandSnapshot.speechColorKey == record.speechColorKey,
    "speech colour survives the production registry/capture path")
check(commandSnapshot ~= nil and commandSnapshotReason == nil
    and commandSnapshot.order.current == "guard"
    and commandSnapshot.order.followDistance == 8
    and commandSnapshot.order.followCarSqlId == 501
    and commandSnapshot.order.scavenge == false
    and commandSnapshot.order.movementMode == "jog"
    and commandSnapshot.order.movementModeVersion == 2
    and commandSnapshot.order.combatStance == "defensive"
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
    and commandSnapshot.personality.background.occupation == "mechanics"
    and commandSnapshot.personality.ritual.id == "rubber_duck_oracle"
    and commandSnapshot.personality.ritual.duck.phase == "recovery_pending"
    and commandSnapshot.personality.ritual.duck.x == 4
    and commandSnapshot.personality.tales.list[1].kills == 7
    and commandSnapshot.personality.tales.list[1].witnesses[1] == "sc-core-witness"
    and commandSnapshot.personality.tales.witnessed[1].teller == "sc-core-teller"
    and commandSnapshot.personality.flavor.lastWorkoutDay == 11
    and commandSnapshot.personality.flavor.placesSeen.police == true,
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
        .. " occupation=" .. tostring(commandSnapshot and commandSnapshot.personality.background.occupation)
        .. " ritual=" .. tostring(commandSnapshot and commandSnapshot.personality.ritual
            and commandSnapshot.personality.ritual.id))
for _, key in ipairs({
    "SC_Order", "SC_FollowDistance", "SC_Scavenge", "SC_MoveMode", "SC_CombatMode",
    "SC_CombatDoctrine", "SC_HoldFire", "SC_WeaponPriority", "SC_Group", "SC_Trust", "SC_Bond",
    "SC_Morale", "SC_Stress", "SC_TimeTogetherMs", "SC_WorkMode", "SC_FollowCarSqlId",
}) do actor.data[key] = nil end
SC.Commands.reset(actor)
local restoredCommandState = SC.Commands.peek(actor)
check(restoredCommandState.order == "guard" and restoredCommandState.followDistance == 8
    and restoredCommandState.followCarSqlId == 501
    and restoredCommandState.scavenge == false and restoredCommandState.moveMode == "jog"
    and restoredCommandState.combatMode == "defensive"
    and restoredCommandState.combatDoctrine == "ranged_support"
    and restoredCommandState.holdFire == true
    and restoredCommandState.weaponPriority == "quiet" and restoredCommandState.group == "Bravo"
    and restoredCommandState.workMode == "craft"
    and restoredCommandState.trust == 7 and restoredCommandState.bond == 11
    and restoredCommandState.morale == 63 and restoredCommandState.stress == 21
    and restoredCommandState.timeTogetherMs == 7200000
    and restoredCommandState.ritual.id == "rubber_duck_oracle"
    and restoredCommandState.ritual.duck.phase == "recovery_pending"
    and restoredCommandState.tales.list[1].kills == 7
    and restoredCommandState.tales.list[1].place == "the church"
    and restoredCommandState.tales.list[1].tellings == 2
    and restoredCommandState.flavor.lastWorkoutDay == 11
    and restoredCommandState.background.occupation == "mechanics",
    "Registry persistence schema rehydrates independent policies without transient actor mod-data")
restoredCommandState.followCarSqlId = nil
check(SC.Commands.persist(actor), "test follow-car assignment clears after restore")

local barricadeObject = { square = square, objectIndex = 0, data = {} }
function barricadeObject:getSquare() return self.square end
function barricadeObject:getObjectIndex() return self.objectIndex end
function barricadeObject:getModData() return self.data end
function barricadeObject:transmitModData() self.modDataTransmitted = true end
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
    and buildingSnapshot.order.workTarget.objectId == buildingState.workTarget.objectId
    and type(buildingSnapshot.order.workTarget.objectId) == "string"
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

do
    -- CB-08 (extended). BodyPart.setScratched takes
    -- (flag, forceNoInfection); verified in the 42.20.4 bytecode, a FALSE
    -- second argument calls generateZombieInfection(). BodyPart.setCut exposes
    -- only its one-argument no-roll form.
    local recorded = {}
    local woundPart = { woundInfection = 0 }
    function woundPart:getType() return "ForeArm_R" end
    local function note(name, ...)
        recorded[name] = { ... }
        return true
    end
    function woundPart:SetHealth(v) return note("SetHealth", v) end
    function woundPart:SetBitten(v, infected) return note("SetBitten", v, infected) end
    function woundPart:SetInfected(v) return note("SetInfected", v) end
    function woundPart:setScratched(a, b) return note("setScratched", a, b) end
    function woundPart:setCut(a, b) return note("setCut", a, b) end
    function woundPart:setWoundInfectionLevel(v) return note("setWoundInfectionLevel", v) end
    setmetatable(woundPart, { __index = function() return function() return true end end })

    local woundParts = { woundPart }
    function woundParts:size() return #self end
    function woundParts:get(index) return self[index + 1] end
    local woundBody = {}
    function woundBody:getBodyParts() return woundParts end
    local woundActor = {}
    function woundActor:getBodyDamage() return woundBody end

    SC.Vitals.apply(woundActor, {
        health = 100, overallHealth = 100, infected = false, parts = {
            { type = "ForeArm_R", health = 70, scratched = true, cut = true,
              woundInfection = 0.4 },
        },
    })
    check(recorded.setScratched ~= nil and recorded.setScratched[2] == true,
        "restoring a saved scratch suppresses the engine's fresh infection roll")
    check(recorded.setCut ~= nil and recorded.setCut[1] == true
            and recorded.setCut[2] == nil,
        "restoring a saved cut uses the native one-argument no-roll contract")
    check(recorded.setWoundInfectionLevel ~= nil
        and recorded.setWoundInfectionLevel[1] == 0.4,
        "the saved wound infection level is what gets restored, not a new roll")
    check(recorded.SetBitten ~= nil and recorded.SetBitten[1] == false
            and recorded.SetBitten[2] == false
            and recorded.SetInfected ~= nil and recorded.SetInfected[1] == false,
        "healthy saved body parts cannot gain Knox from the native bite setter")
    SC.Vitals.apply(woundActor, {
        health = 100, overallHealth = 100, infected = true, parts = {
            { type = "ForeArm_R", health = 70, bitten = true,
              knoxInfected = true },
        },
    })
    check(recorded.SetBitten[1] == true and recorded.SetBitten[2] == true
            and recorded.SetInfected[1] == true,
        "a genuinely infected bite retains its body-part Knox flag")
end

do
    local function color(r, g, b, a)
        local value = { r = r, g = g, b = b, a = a }
        function value:getRedFloat() return self.r end
        function value:getGreenFloat() return self.g end
        function value:getBlueFloat() return self.b end
        function value:getAlphaFloat() return self.a end
        return value
    end
    local oldImmutableColor = ImmutableColor
    ImmutableColor = { new = function(r, g, b, a) return color(r, g, b, a) end }
    local visual = {
        hairModel = "LongCurly", beardModel = "Goatee", nonAttachedHair = "LongCurly",
        skinTexture = "FemaleBody04", skinTextureIndex = 4, bodyHairIndex = 2,
        hairColor = color(0.12, 0.23, 0.34, 1),
        naturalHairColor = color(0.11, 0.22, 0.33, 1),
        beardColor = color(0.14, 0.25, 0.36, 1),
        naturalBeardColor = color(0.13, 0.24, 0.35, 1),
        skinColor = color(0.41, 0.31, 0.21, 1),
    }
    local function getterFor(field)
        return function(self) return self[field] end
    end
    local function setterFor(field)
        return function(self, value) self[field] = value end
    end
    for field, getter in pairs({
        hairModel = "getHairModel", beardModel = "getBeardModel",
        nonAttachedHair = "getNonAttachedHair", skinTexture = "getSkinTexture",
        skinTextureIndex = "getSkinTextureIndex", bodyHairIndex = "getBodyHairIndex",
        hairColor = "getHairColor", naturalHairColor = "getNaturalHairColor",
        beardColor = "getBeardColor", naturalBeardColor = "getNaturalBeardColor",
        skinColor = "getSkinColor",
    }) do
        visual[getter] = getterFor(field)
    end
    for field, setter in pairs({
        hairModel = "setHairModel", beardModel = "setBeardModel",
        nonAttachedHair = "setNonAttachedHair", skinTexture = "setSkinTextureName",
        skinTextureIndex = "setSkinTextureIndex", bodyHairIndex = "setBodyHairIndex",
        hairColor = "setHairColor", naturalHairColor = "setNaturalHairColor",
        beardColor = "setBeardColor", naturalBeardColor = "setNaturalBeardColor",
        skinColor = "setSkinColor",
    }) do
        visual[setter] = setterFor(field)
    end
    local appearanceActor = { visual = visual, resets = 0 }
    function appearanceActor:getHumanVisual() return self.visual end
    function appearanceActor:resetModelNextFrame() self.resets = self.resets + 1 end
    local savedAppearance = SC.Persistence._captureAppearanceForTests(appearanceActor)
    visual.hairModel, visual.beardModel, visual.skinTexture = "Bald", "", "FemaleBody01"
    visual.skinTextureIndex, visual.bodyHairIndex = 1, 0
    visual.hairColor, visual.skinColor = color(1, 1, 1, 1), color(1, 1, 1, 1)
    local appearanceApplied, appearanceReason =
        SC.Persistence._applyAppearanceForTests(appearanceActor, savedAppearance)
    check(appearanceApplied and appearanceReason == nil
            and visual.hairModel == "LongCurly" and visual.beardModel == "Goatee"
            and visual.skinTexture == "FemaleBody04" and visual.skinTextureIndex == 4
            and visual.bodyHairIndex == 2 and visual.hairColor.r == 0.12
            and visual.skinColor.r == 0.41 and appearanceActor.resets == 1,
        "save/load restores exact hair, beard, skin and body appearance: "
            .. tostring(appearanceReason))

    local itemVisual = {
        baseTexture = 7, textureChoice = 3, hue = 0.27,
        decal = "Kentucky", alternateModelName = "Tucked",
        tint = color(0.22, 0.44, 0.66, 1),
    }
    local clothing = { visual = itemVisual, synced = 0 }
    function itemVisual:getBaseTexture() return self.baseTexture end
    function itemVisual:getTextureChoice() return self.textureChoice end
    function itemVisual:getHue() return self.hue end
    function itemVisual:getDecal(definition)
        if definition ~= clothing then error("expected ClothingItem definition") end
        return self.decal
    end
    function itemVisual:getAlternateModelName() return self.alternateModelName end
    function itemVisual:getTint(definition)
        if definition ~= clothing then error("expected ClothingItem definition") end
        return self.tint
    end
    function itemVisual:setBaseTexture(value) self.baseTexture = value end
    function itemVisual:setTextureChoice(value) self.textureChoice = value end
    function itemVisual:setHue(value) self.hue = value end
    function itemVisual:setDecal(value) self.decal = value end
    function itemVisual:setAlternateModelName(value) self.alternateModelName = value end
    function itemVisual:setTint(value) self.tint = value end
    function clothing:getVisual() return self.visual end
    function clothing:getClothingItem() return self end
    function clothing:synchWithVisual() self.synced = self.synced + 1 end
    local savedItemVisual = SC.Persistence._captureItemVisualForTests(clothing)
    itemVisual.baseTexture, itemVisual.textureChoice, itemVisual.hue = 1, 0, 0
    itemVisual.decal, itemVisual.alternateModelName = "", ""
    itemVisual.tint = color(1, 1, 1, 1)
    local itemVisualApplied, itemVisualReason =
        SC.Persistence._applyItemVisualForTests(clothing, savedItemVisual)
    check(itemVisualApplied and itemVisualReason == nil
            and itemVisual.baseTexture == 7 and itemVisual.textureChoice == 3
            and itemVisual.hue == 0.27 and itemVisual.decal == "Kentucky"
            and itemVisual.alternateModelName == "Tucked"
            and itemVisual.tint.r == 0.22 and clothing.synced == 1,
        "save/load restores clothing texture, model, decal, hue and tint: "
            .. tostring(itemVisualReason))
    ImmutableColor = oldImmutableColor
end

do
    local function impossibleLegacy(name)
        return {
            identity = { forename = name, appearance = nil }, knox = true,
            vitals = {
                infected = true, infectionTime = 0.004,
                infectionMortalityDuration = 10, apparentInfection = 5,
                parts = { { type = "Hand_L", bitten = false, scratched = false,
                    cut = false, deepWound = false, biteTime = 0,
                    scratchTime = 0, cutTime = 0 } },
            },
        }
    end
    local legacy = {
        companions = { a = impossibleLegacy("A"), b = impossibleLegacy("B") },
        factionActors = {},
        infectionCrisis = {
            observations = {
                a = { bites = 0, infected = true, infectionLevel = 5 },
                b = { bites = 0, infected = true, infectionLevel = 6 },
            },
            crises = { c = { subjectId = "a" } },
            history = { { crisisId = "c", subjectId = "a" }, { kind = "unrelated" } },
        },
    }
    local repaired = SC.Persistence._repairLegacyKnoxCohortForTests(legacy)
    check(repaired == 2 and legacy.companions.a.vitals.infected == false
            and legacy.companions.b.vitals.infectionTime == -1
            and legacy.companions.a.knox == false
            and legacy.infectionCrisis.observations.a.infected == false
            and legacy.infectionCrisis.crises.c == nil
            and #legacy.infectionCrisis.history == 1,
        "the impossible all-infected wound-free legacy cohort is repaired once")

    local legitimate = { companions = {
        a = impossibleLegacy("A"), b = impossibleLegacy("B"),
    }, factionActors = {} }
    legitimate.companions.a.vitals.parts[1].bitten = true
    check(SC.Persistence._repairLegacyKnoxCohortForTests(legitimate) == 0
            and legitimate.companions.b.vitals.infected == true,
        "a mixed cohort with real wound evidence is never auto-cleared")
    local current = { companions = {
        a = impossibleLegacy("A"), b = impossibleLegacy("B"),
    }, factionActors = {} }
    current.companions.a.identity.appearance = { hairModel = "Bob" }
    current.companions.b.identity.appearance = { hairModel = "CrewCut" }
    check(SC.Persistence._repairLegacyKnoxCohortForTests(current) == 0,
        "appearance alone cannot trigger a whole-group Knox repair")

    local restoredCohort = { companions = {
        a = impossibleLegacy("A"), b = impossibleLegacy("B"),
        c = impossibleLegacy("C"),
    }, factionActors = {} }
    for _, row in pairs(restoredCohort.companions) do
        row.identity.appearance = { hairModel = "Bob" }
        row.vitals.infectionTime = 2.5
        row.vitals.infectionElapsedHours = 21
        row.vitals.apparentInfection = 42
    end
    restoredCohort.companions.b.vitals.infectionElapsedHours = 0.50456641
    restoredCohort.companions.c.vitals.infectionElapsedHours = 0.50456643
    restoredCohort.companions.a.vitals.overallHealth = 20
    restoredCohort.companions.a.vitals.parts = {
        { type = "Hand_L", health = 20 }, { type = "Hand_R", health = 21 },
        { type = "Foot_L", health = 19 }, { type = "Foot_R", health = 22 },
    }
    check(SC.Persistence._repairLegacyKnoxCohortForTests(restoredCohort) == 3
            and restoredCohort.companions.a.vitals.infected == false
            and restoredCohort.companions.b.vitals.infectionElapsedHours == nil
            and restoredCohort.companions.a.vitals.overallHealth == 100
            and restoredCohort.companions.a.vitals.parts[1].health == 100,
        "synchronized wound-free Knox after load repairs the whole saved cohort")
    restoredCohort.companions.a.vitals.infected = true
    restoredCohort.companions.b.vitals.infected = true
    restoredCohort.companions.c.vitals.infected = true
    restoredCohort.companions.a.vitals.parts[1].knoxInfected = true
    check(SC.Persistence._repairLegacyKnoxCohortForTests(restoredCohort) == 0,
        "a save with explicit part-level Knox evidence is never auto-cleared")
end

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
-- The native method takes a Java int seat; nil fails to unbox and throws.
local nilSeatQueries = 0
function vehicle:getEnterSeatDistance(seat, x, y)
    if seat == nil then
        nilSeatQueries = nilSeatQueries + 1
        error("getEnterSeatDistance: seat cannot be nil")
    end
    if seat ~= 1 then return -1 end
    return (x - 1.5) * (x - 1.5) + (y - 0.5) * (y - 0.5)
end
function vehicle:enter(seat, candidate)
    if seat ~= 1 or self.passenger ~= nil then return false end
    self.passenger, candidate.vehicle = candidate, self
    self.passengerPosition = "outside"
    return true
end
function vehicle:exit(candidate)
    if self.passenger ~= candidate then return false end
    self.passenger, candidate.vehicle = nil, nil
    self.passengerPosition = nil
    return true
end
function vehicle:getSeat(candidate) return self.passenger == candidate and 1 or -1 end
function vehicle:getCharacter(seat) return seat == 1 and self.passenger or nil end
function vehicle:getPassengerPosition(seat, position)
    if seat == 1 and position == "inside" and not self.missingInside then
        return { position = position }
    end
    return nil
end
function vehicle:setCharacterPosition(candidate, seat, position)
    if self.rejectInside then error("injected inside-position failure") end
    if seat == 1 and self.passenger == candidate then self.passengerPosition = position end
end
function vehicle:transmitCharacterPosition(seat, position)
    if seat == 1 then self.transmittedPosition = position end
end
function vehicle:playPassengerAnim(seat, animation)
    if seat == 1 then self.passengerAnimation = animation end
end
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
local originalManifestLiving = SC.Registry.living
SC.Registry.living = function()
    local mixed = {}
    for index = 1, 20 do mixed[#mixed + 1] = { neutral = index } end
    for _, candidate in ipairs(manifestActors) do mixed[#mixed + 1] = candidate end
    return mixed
end
local mixedAssignment = SC.Vehicle.assignmentFor(
    manifestActors[1], manifestVehicle, manifestPlayer)
check(mixedAssignment ~= nil and mixedAssignment.capacity == 3,
    "vehicle boarding finds recruited followers after neutral registry entries")
SC.Registry.living = originalManifestLiving
SC.Vehicle.invalidateManifests()
manifestActors[1].getX = function() return nil end
manifestActors[1].getBodyDamage = function()
    return { getHealth = function() return 10 end }
end
local availablePassenger = SC.Vehicle.assignmentFor(
    manifestActors[2], manifestVehicle, manifestPlayer)
local positionlessPassenger = SC.Vehicle.assignmentFor(
    manifestActors[1], manifestVehicle, manifestPlayer)
check(availablePassenger ~= nil and positionlessPassenger == nil,
    "an unloaded wounded follower cannot reserve a seat ahead of a present follower")
manifestActors[1].getX = nil
manifestActors[1].getBodyDamage = nil
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

-- VanSeats has six installed seats, but its two rear seats have no outside
-- entry area. A follower must take a middle door and switch inside, freeing
-- that door seat for the fourth and fifth companions.
do
local sixSeatVan = {
    id = 88, script = "Base.VanSeats", x = 1, y = 0, z = 0, speed = 0,
    occupants = {}, positions = {},
}
function sixSeatVan:getId() return self.id end
function sixSeatVan:getScriptName() return self.script end
function sixSeatVan:getX() return self.x end
function sixSeatVan:getY() return self.y end
function sixSeatVan:getZ() return self.z end
function sixSeatVan:getCell() return vehicleCell end
function sixSeatVan:getMaxPassengers() return 6 end
function sixSeatVan:isSeatInstalled(seat) return seat >= 0 and seat < 6 end
function sixSeatVan:isSeatOccupied(seat) return self.occupants[seat] ~= nil end
function sixSeatVan:getCharacter(seat) return self.occupants[seat] end
function sixSeatVan:getSeat(candidate)
    for seat, occupant in pairs(self.occupants) do
        if occupant == candidate then return seat end
    end
    return -1
end
function sixSeatVan:getCurrentSpeedKmHour() return self.speed end
function sixSeatVan:getScript()
    return { getPassenger = function(_, seat)
        return { getPositionById = function(_, position)
            if position ~= "outside" then return nil end
            local area = seat < 4 and "Seat" .. tostring(seat)
                or "Seat" .. tostring(seat - 2)
            return { getArea = function() return area end }
        end }
    end }
end
function sixSeatVan:getPassengerPosition(seat, position)
    if seat < 0 or seat >= 6 then return nil end
    if position == "inside" then return { position = position } end
    if position == "outside" then
        local area = seat < 4 and "Seat" .. tostring(seat)
            or "Seat" .. tostring(seat - 2)
        return { getArea = function() return area end }
    end
end
function sixSeatVan:getEnterSeatDistance(seat, x, y)
    if self.singleDoor and seat ~= 1 then return -1 end
    if seat >= 4 then return -1 end
    return (x - 1.5) ^ 2 + (y - 0.5) ^ 2
end
function sixSeatVan:canSwitchSeat(from, to)
    return from == 1 and (to == 2 or to == 3)
        or (from == 2 or from == 3) and to == 1
        or (from == 2 or from == 3) and (to == 4 or to == 5)
        or (from == 4 or from == 5) and (to == 2 or to == 3)
end
function sixSeatVan:switchSeat(candidate, to)
    local from = self:getSeat(candidate)
    if from < 0 or self.occupants[to] ~= nil or not self:canSwitchSeat(from, to) then
        return
    end
    self.occupants[from], self.occupants[to] = nil, candidate
    self.positions[to], self.positions[from] = "inside", nil
end
function sixSeatVan:enter(seat, candidate)
    if self.occupants[seat] ~= nil then return false end
    self.occupants[seat], candidate.vehicle = candidate, self
    self.positions[seat] = "outside"
    return true
end
function sixSeatVan:exit(candidate)
    local seat = self:getSeat(candidate)
    if seat < 0 then return false end
    self.occupants[seat], self.positions[seat], candidate.vehicle = nil, nil, nil
    return true
end
function sixSeatVan:setCharacterPosition(candidate, seat, position)
    if self.occupants[seat] == candidate then self.positions[seat] = position end
end
function sixSeatVan:transmitCharacterPosition() end
function sixSeatVan:playPassengerAnim() end
function sixSeatVan:getPassengerDoor() return nil end
local previousPlayerVehicle = manifestPlayer.vehicle
manifestPlayer.vehicle = sixSeatVan
SC.Vehicle.invalidateManifests()
local rearWait, rearWaitReason = SC.Vehicle.assignmentFor(
    manifestActors[4], sixSeatVan, manifestPlayer)
check(rearWait == nil and rearWaitReason == "vehicle_entry_seat_wait",
    "six-seat rear passengers wait for an occupied middle doorway")
sixSeatVan.occupants[0] = manifestPlayer
for seat = 1, 3 do
    sixSeatVan.occupants[seat] = manifestActors[seat]
    manifestActors[seat].vehicle = sixSeatVan
    sixSeatVan.positions[seat] = "inside"
end
local fourth = SC.Vehicle.assignmentFor(manifestActors[4], sixSeatVan, manifestPlayer)
check(fourth and fourth.seat == 2 and sixSeatVan:getCharacter(4) == manifestActors[2]
        and sixSeatVan:getCharacter(2) == nil,
    "first middle passenger switches to rear and frees the fourth seat")
manifestActors[4].px, manifestActors[4].py = 1.5, 0.5
local fourthBoarded, fourthReason = SC.Vehicle.board(manifestActors[4], sixSeatVan, 2, {})
check(fourthBoarded and fourthReason == "native_seat"
        and sixSeatVan:getCharacter(2) == manifestActors[4]
        and sixSeatVan.positions[2] == "inside",
    "fourth companion boards the freed middle door in a native inside seat")
local fifth = SC.Vehicle.assignmentFor(manifestActors[5], sixSeatVan, manifestPlayer)
local fifthDoor = fifth and fifth.seat or -1
check((fifthDoor == 2 or fifthDoor == 3)
        and sixSeatVan:getCharacter(5) ~= nil
        and sixSeatVan:getCharacter(fifthDoor) == nil,
    "another middle passenger switches to rear and frees the fifth door seat")
manifestActors[5].px, manifestActors[5].py = 1.5, 0.5
local fifthBoarded, fifthReason = SC.Vehicle.board(manifestActors[5], sixSeatVan,
    fifthDoor, {})
check(fifthBoarded and fifthReason == "native_seat"
        and sixSeatVan:getCharacter(fifthDoor) == manifestActors[5]
        and sixSeatVan.positions[fifthDoor] == "inside"
        and sixSeatVan:getCharacter(1) ~= nil
        and sixSeatVan:getCharacter(2) ~= nil
        and sixSeatVan:getCharacter(3) ~= nil
        and sixSeatVan:getCharacter(4) ~= nil
        and sixSeatVan:getCharacter(5) ~= nil,
    "five companions occupy five distinct inside seats of the six-seat van")
local rearBlocked, rearBlockedReason = SC.Vehicle.exit(manifestActors[2], sixSeatVan)
check(not rearBlocked and rearBlockedReason == "vehicle_exit_access_wait"
        and sixSeatVan:getCharacter(4) == manifestActors[2],
    "rear passenger stays seated while both middle door seats are occupied")
local middleExited, middleExitReason = SC.Vehicle.exit(manifestActors[5], sixSeatVan)
check(middleExited and middleExitReason == "native_exit",
    "a middle passenger exits to open the rear passenger's path")
local rearExited, rearExitReason = SC.Vehicle.exit(manifestActors[2], sixSeatVan)
check(rearExited and rearExitReason == "native_exit"
        and manifestActors[2]:getVehicle() == nil,
    "rear passenger switches through the freed middle seat and exits")
for seat = 0, 5 do
    local passenger = sixSeatVan.occupants[seat]
    if passenger then passenger.vehicle = nil end
    sixSeatVan.occupants[seat] = nil
end
sixSeatVan.singleDoor = true
sixSeatVan.occupants[0] = manifestPlayer
for index = 1, 5 do
    manifestActors[index].px, manifestActors[index].py = 1.5, 0.5
end
SC.Vehicle.invalidateManifests(sixSeatVan)
for index = 1, 5 do
    local passenger = manifestActors[index]
    local assignment, assignmentReason = SC.Vehicle.assignmentFor(passenger, sixSeatVan, manifestPlayer)
    local boarded, status
    if assignment then
        boarded, status = SC.Vehicle.board(passenger,
            sixSeatVan, assignment.seat, {})
    end
    check(boarded == true and status == "native_seat"
            and assignment.seat == 1,
        "single-door van routes companion " .. index .. " through the front passenger door"
            .. " (assigned=" .. tostring(assignment and assignment.seat)
            .. ", reason=" .. tostring(assignmentReason)
            .. ", board=" .. tostring(boarded)
            .. ", status=" .. tostring(status) .. ")")
end
local allInside = true
for seat = 1, 5 do
    allInside = allInside and sixSeatVan:getCharacter(seat) ~= nil
end
check(allInside, "single-door van fills all five passenger seats through native switches")
for seat = 1, 5 do
    local passenger = sixSeatVan:getCharacter(seat)
    local exited = passenger and SC.Vehicle.exit(passenger, sixSeatVan)
    check(exited == true and passenger:getVehicle() == nil,
        "single-door van passenger " .. seat .. " exits through free seat links")
end
manifestPlayer.vehicle = previousPlayerVehicle
for index = 1, 5 do
    manifestActors[index].px, manifestActors[index].py = nil, nil
end
SC.Vehicle.invalidateManifests(sixSeatVan)
-- The stock Masterson Horizon (Base.SmallCar02) has four seats but only two
-- side doors. Rear passengers must enter through a front seat and switch.
do
    local horizon = setmetatable({ id = 89, script = "Base.SmallCar02",
        x = 1, y = 0, z = 0, speed = 0, occupants = {}, positions = {} },
        { __index = sixSeatVan })
    function horizon:getMaxPassengers() return 4 end
    function horizon:isSeatInstalled(seat) return seat >= 0 and seat < 4 end
    function horizon:getScript()
        return { getPassenger = function(_, seat)
            return { getPositionById = function(_, position)
                if position ~= "outside" then return nil end
                return { getArea = function()
                    return seat < 2 and "SeatFront" .. tostring(seat) or nil
                end }
            end }
        end }
    end
    function horizon:getPassengerPosition(seat, position)
        if seat < 0 or seat >= 4 then return nil end
        if position == "inside" then return { position = position } end
        return seat < 2 and { getArea = function()
            return "SeatFront" .. tostring(seat)
        end } or nil
    end
    function horizon:getEnterSeatDistance(seat, x, y)
        if seat > 1 then return -1 end
        return (x - 1.5)^2 + (y - 0.5)^2
    end
    function horizon:canSwitchSeat(from, to)
        return from ~= to and from >= 0 and from < 4
            and to >= 0 and to < 4
    end
    local door = { locked = true, opened = false }
    function door:isLocked() return self.locked end
    function door:setLocked(value) self.locked = value end
    function door:isOpen() return self.opened end
    function door:setOpen(value) self.opened = value end
    function horizon:getPassengerDoor(seat)
        return seat == 1 and { getDoor = function() return door end } or nil
    end
    function horizon:toggleLockedDoor() end
    function horizon:transmitPartDoor() end
    local savedSpecificPlayer = getSpecificPlayer
    getSpecificPlayer = function(index)
        return index == 0 and manifestPlayer or nil
    end
    manifestPlayer.vehicle, horizon.occupants[0] = horizon, manifestPlayer
    SC.Vehicle.invalidateManifests()
    for index = 1, 3 do
        local passenger = manifestActors[index]
        passenger.px, passenger.py = 1.5, 0.5
        local assignment, assignmentReason = SC.Vehicle.assignmentFor(
            passenger, horizon, manifestPlayer)
        check(assignment and assignment.seat == 1,
            "Masterson Horizon routes passenger " .. index
                .. " through its front door: " .. tostring(assignmentReason))
        local boarded, reason = SC.Vehicle.board(passenger, horizon, 1, {})
        check(boarded and reason == "native_seat"
                and horizon:getCharacter(1) == passenger
                and not door.locked and not door.opened,
            "Masterson Horizon boards passenger " .. index
                .. " through the player-unlocked door: " .. tostring(reason))
    end
    check(horizon:getCharacter(1) == manifestActors[3]
            and horizon:getCharacter(2) == manifestActors[1]
            and horizon:getCharacter(3) == manifestActors[2],
        "all three companions occupy the three passenger seats")
    for index = 1, 3 do
        local passenger = manifestActors[index]
        horizon.occupants[horizon:getSeat(passenger)] = nil
        passenger.vehicle, passenger.px, passenger.py = nil, nil, nil
    end
    manifestPlayer.vehicle = previousPlayerVehicle
    getSpecificPlayer = savedSpecificPlayer
    SC.Vehicle.invalidateManifests(horizon)
end
end
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
SC.Commands.peek(laterRecruit)
check(laterRecruit.data.SC_PlayerAttackProtected == false,
    "an unrecruited survivor remains hittable")
check(laterRecord ~= nil
        and SC.Commands.issue(laterRecord.id, "recruit", nil, manifestPlayer)
        and SC.Commands.peek(laterRecruit).combatDoctrine == "weapons_free"
        and laterRecruit.data.SC_PlayerAttackProtected == true,
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
local originalVehicleTransition = SC.ActionSupervisor.transition
SC.ActionSupervisor.transition = function(token, phase, detail)
    if phase == "committing" then return false, "commit_owner_refused" end
    return originalVehicleTransition(token, phase, detail)
end
local refusedBoard, refusedBoardReason = SC.Vehicle.board(actor, vehicle, nil,
    { preflight = preflight })
SC.ActionSupervisor.transition = originalVehicleTransition
check(refusedBoard == false and refusedBoardReason == "commit_owner_refused"
        and actor:getVehicle() == nil
        and SC.Vehicle.isSeatReserved(vehicle, 1) == false,
    "boarding refuses native entry when its commit owner is not accepted")
SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "board_vehicle")
SC.ActionSupervisor.transition = function(token, phase, detail)
    if phase == "verifying" then return false, "board_verify_owner_refused" end
    return originalVehicleTransition(token, phase, detail)
end
local unverifiedBoard, unverifiedBoardReason = SC.Vehicle.board(actor, vehicle, nil,
    { preflight = preflight })
SC.ActionSupervisor.transition = originalVehicleTransition
check(unverifiedBoard == false and unverifiedBoardReason == "board_verify_owner_refused"
        and actor:getVehicle() == nil and vehicle.passenger == nil
        and SC.Vehicle.isSeatReserved(vehicle, 1) == false,
    "boarding rolls native entry back if verification ownership is rejected")
SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "board_vehicle")
function SC.__testVehicleInsidePosition()
    vehicle.missingInside = true
    local unpositionableBoard, unpositionableReason = SC.Vehicle.board(actor, vehicle, nil,
        { preflight = preflight })
    vehicle.missingInside = nil
    check(unpositionableBoard == false
            and string.find(tostring(unpositionableReason), "inside passenger position", 1, true)
            and actor:getVehicle() == nil and vehicle.passenger == nil,
        "boarding refuses a vehicle seat without a scripted inside position")
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "board_vehicle")
    vehicle.rejectInside = true
    local misplacedBoard, misplacedReason = SC.Vehicle.board(actor, vehicle, nil,
        { preflight = preflight })
    vehicle.rejectInside = nil
    check(misplacedBoard == false
            and string.find(tostring(misplacedReason), "placement failed", 1, true)
            and actor:getVehicle() == nil and vehicle.passenger == nil
            and vehicle.passengerPosition == nil,
        "a failed inside-seat transition rolls native boarding back")
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "board_vehicle")
end
SC.__testVehicleInsidePosition()
SC.__testVehicleInsidePosition = nil
local boarded, boardReason = SC.Vehicle.board(actor, vehicle, nil, { preflight = preflight })
check(boarded and boardReason == "native_seat" and SC.Vehicle.isNativeSeated(actor)
    and SC.Registry.byId("sc-core-actor") ~= nil
    and vehicle.passengerPosition == "inside"
    and vehicle.transmittedPosition == "inside"
    and vehicle.passengerAnimation == "idle"
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
    local originalTransition = SC.ActionSupervisor.transition
    SC.ActionSupervisor.transition = function(token, phase, detail)
        if phase == "committing" then return false, "exit_commit_owner_refused" end
        return originalTransition(token, phase, detail)
    end
    local refusedExit, refusedExitReason = SC.Vehicle.exit(actor, vehicle)
    SC.ActionSupervisor.transition = originalTransition
    check(refusedExit == false and refusedExitReason == "exit_commit_owner_refused"
            and actor:getVehicle() == vehicle,
        "exiting refuses native seat mutation when its commit owner is not accepted")
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "exit_vehicle")
    SC.ActionSupervisor.transition = function(token, phase, detail)
        if phase == "verifying" then return false, "exit_verify_owner_refused" end
        return originalTransition(token, phase, detail)
    end
    local unverifiedExit, unverifiedExitReason = SC.Vehicle.exit(actor, vehicle)
    SC.ActionSupervisor.transition = originalTransition
    check(unverifiedExit == false and unverifiedExitReason == "exit_verify_owner_refused"
            and actor:getVehicle() == vehicle and vehicle.passenger == actor
            and vehicle.passengerPosition == "inside",
        "exiting restores the occupied inside seat if verification ownership is rejected")
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "exit_vehicle")
    local originalRecover = SC.Actor.recover
    SC.Actor.recover = function() return false, "fixture_recover_rejected" end
    local failedPlacement, failedPlacementReason = SC.Vehicle.exit(actor, vehicle)
    SC.Actor.recover = originalRecover
    check(failedPlacement == false
            and string.find(tostring(failedPlacementReason), "seat rollback verified", 1, true)
            and actor:getVehicle() == vehicle and vehicle.passenger == actor
            and vehicle.passengerPosition == "inside",
        "a failed exit placement restores the passenger to the inside offset")
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "exit_vehicle")
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

do
    local savedSpecificPlayer = getSpecificPlayer
    local savedDoor = vehicle.getPassengerDoor
    local savedToggle = vehicle.toggleLockedDoor
    local door = { locked = true, opened = false }
    function door:isLocked() return self.locked end
    function door:setLocked(value) self.locked = value end
    function door:isOpen() return self.opened end
    function door:setOpen(value) self.opened = value end
    local part = { getDoor = function() return door end }
    vehicle.getPassengerDoor = function(_, seat)
        return seat == 1 and part or nil
    end
    vehicle.toggleLockedDoor = function()
        -- The companion has no key and the native player toggle can also
        -- decline on some vehicles. The in-car lock control is the fallback.
    end
    getSpecificPlayer = function() return nil end
    local denied, deniedReason = SC.Vehicle.board(actor, vehicle, 1, {})
    check(not denied and deniedReason == "passenger door is locked"
            and door.locked and actor:getVehicle() == nil,
        "a locked two-seat passenger door stays locked without a local player aboard")
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "board_vehicle")
    manifestPlayer.vehicle = vehicle
    getSpecificPlayer = function(index)
        return index == 0 and manifestPlayer or nil
    end
    local boardedLocked, lockedReason = SC.Vehicle.board(actor, vehicle, 1, {})
    check(boardedLocked and lockedReason == "native_seat"
            and not door.locked and not door.opened
            and vehicle.passenger == actor,
        "a follower boards the locked passenger seat when the player is inside")
    local exitedLocked = SC.Vehicle.exit(actor, vehicle)
    check(exitedLocked and actor:getVehicle() == nil,
        "the locked-door fixture leaves its passenger on foot")
    manifestPlayer.vehicle = nil
    getSpecificPlayer = savedSpecificPlayer
    vehicle.getPassengerDoor = savedDoor
    vehicle.toggleLockedDoor = savedToggle
end

-- Companion driving: the driver's seat goes only through boardDriver, never to
-- a follower and never with a stranger aboard; SC.Driving forwards to the bridge.
function SC.__testCompanionDriving()
    local car = { id = 31, script = "Base.DriveTestCar", x = 1, y = 0, z = 0, speed = 0,
        occupants = {}, positions = {} }
    function car:getId() return self.id end
    function car:getScriptName() return self.script end
    function car:getX() return self.x end
    function car:getY() return self.y end
    function car:getZ() return self.z end
    function car:getMaxPassengers() return 4 end
    function car:isSeatInstalled(seat) return seat >= 0 and seat <= 3 end
    function car:isSeatOccupied(seat) return self.occupants[seat] ~= nil end
    function car:getCurrentSpeedKmHour() return self.speed end
    function car:getEnterSeatDistance(seat, x, y)
        if seat < 0 or seat > 3 then return -1 end
        return (x - 1.5) * (x - 1.5) + (y - 0.5) * (y - 0.5)
    end
    function car:enter(seat, candidate)
        if self.occupants[seat] ~= nil then return false end
        self.occupants[seat], candidate.vehicle = candidate, self
        self.positions[seat] = "outside"
        return true
    end
    function car:exit(candidate)
        for seat, occupant in pairs(self.occupants) do
            if occupant == candidate then
                self.occupants[seat], candidate.vehicle = nil, nil
                self.positions[seat] = nil
                return true
            end
        end
        return false
    end
    function car:getSeat(candidate)
        for seat, occupant in pairs(self.occupants) do
            if occupant == candidate then return seat end
        end
        return -1
    end
    function car:getCharacter(seat) return self.occupants[seat] end
    function car:getDriver() return self.occupants[0] end
    function car:getPassengerPosition(seat, position)
        if position == "inside" then return { position = position } end
        return nil
    end
    function car:setCharacterPosition(candidate, seat, position)
        if self.occupants[seat] == candidate then self.positions[seat] = position end
    end
    function car:transmitCharacterPosition() end
    function car:playPassengerAnim() end
    function car:getCell() return vehicleCell end
    function car:getKeyId() return 4242 end
    local driverDoor = { locked = true, opened = false }
    function driverDoor:isLocked() return self.locked end
    function driverDoor:setLocked(value) self.locked = value end
    function driverDoor:isOpen() return self.opened end
    function driverDoor:setOpen(value) self.opened = value end
    local driverWindow = { intact = true }
    function driverWindow:isHittable() return self.intact end
    local windowPart = { getWindow = function() return driverWindow end }
    local doorPart = { getDoor = function() return driverDoor end,
        getChildWindow = function() return windowPart end }
    function car:getPassengerDoor(seat) return seat == 0 and doorPart or nil end
    function car:toggleLockedDoor()
        self.unlockAttempts = (self.unlockAttempts or 0) + 1
        if not driverWindow.intact then driverDoor.locked = false end
    end
    function car:transmitPartDoor() self.doorTransmits = (self.doorTransmits or 0) + 1 end
    local priorSmash = actor.smashCarWindow
    actor.smashCarWindow = function(_, part)
        if part == windowPart then driverWindow.intact = false end
    end
    local nativeEnter = car.enter
    car.enter = function(self, seat, candidate)
        if seat == 0 and not driverDoor.opened then return false end
        return nativeEnter(self, seat, candidate)
    end
    local priorSquare, priorPx, priorPy = actor.square, actor.px, actor.py

    local followerSeat, followerReason = SC.Vehicle.preflightBoard(actor, car, 0)
    check(followerSeat == nil and followerReason == "requested vehicle seat is unavailable",
        "the ride-along path never hands a companion the driver's seat")
    local passengerBoard = SC.Vehicle.board(actor, car, 0, {})
    SC.ActionSupervisor.resetRetry(actor, "next_fault_case", "board_vehicle")
    check(passengerBoard == false and actor:getVehicle() == nil and car:getDriver() == nil,
        "ordinary boarding cannot be talked into seat zero")
    car.occupants[2] = { stranger = true }
    check(SC.Vehicle.hasPlayerAboard(car),
        "a parked driving lease detects a foreign passenger")
    local strangerSeat, strangerReason = SC.Vehicle.preflightDriver(actor, car)
    car.occupants[2] = nil
    check(not SC.Vehicle.hasPlayerAboard(car),
        "a known empty car has no player aboard")
    car.getMaxPassengers = function() return 0 end
    check(SC.Vehicle.hasPlayerAboard(car),
        "unknown passenger capacity cannot retain a driving lease")
    car.getMaxPassengers = function() return 4 end
    check(strangerSeat == nil
            and strangerReason == "someone who is not a companion is in this vehicle",
        "a companion never takes the wheel with the player or a stranger aboard")
    local priorClient = isClient
    isClient = function() return true end
    local remoteSeat, remoteReason = SC.Vehicle.preflightDriver(actor, car)
    isClient = priorClient
    check(remoteSeat == nil and remoteReason == "companion driving is single-player only",
        "companion driving fails closed in multiplayer")
    local driverPreflight = SC.Vehicle.preflightDriver(actor, car)
    check(driverPreflight ~= nil and driverPreflight.seat == 0,
        "an empty, stopped car offers its driver's seat to the driving path")
    local boardedDriver, driverReason = SC.Vehicle.boardDriver(actor, car)
    local driverRecord = SC.Registry.byId("sc-core-actor")
    check(boardedDriver and driverReason == "native_seat" and car:getDriver() == actor
            and car.positions[0] == "inside"
            and driverRecord.runtime.vehicle.seat == 0
            and SC.ActionSupervisor.snapshot(actor).phase == "idle"
            and car.unlockAttempts == 2 and not driverWindow.intact
            and not driverDoor.locked and not driverDoor.opened
            and car.doorTransmits >= 2,
        "the locked driver door first tries its lock, then breaks glass and opens before seating: "
            .. tostring(driverReason))
    actor.smashCarWindow = priorSmash

    local priorBridge = rawget(_G, "SCBridge")
    check(not SC.Vehicle.hasPlayerAboard(car),
        "a verified companion driver is not treated as a player boarding")
    local calls = {}
    local bridge = { refuseSet = false }
    function bridge.driveStart(who, haveKey)
        calls[#calls + 1] = { "driveStart", who, haveKey }
        return true
    end
    function bridge.driveStartWithPassenger(who, passenger, haveKey)
        calls[#calls + 1] = { "driveStartWithPassenger", who, passenger, haveKey }
        return true
    end
    function bridge.driveSet(who, steering, kmh, brakeForObstacles)
        calls[#calls + 1] = { "driveSet", who, steering, kmh, brakeForObstacles }
        return not bridge.refuseSet
    end
    function bridge.driveStop(who)
        calls[#calls + 1] = { "driveStop", who }
        return true
    end
    function bridge.driveStatus(who, out)
        out.state, out.speedKmh, out.active = "cruising", 9, true
        return true
    end
    function bridge.scanLane(who, lookAhead, out)
        out.blocked, out.obstacleKind, out.obstacleDistance = true, "vehicle", 6
        out.lookAhead = lookAhead
        return true
    end
    function bridge.driveFollow(who, route, kmh)
        calls[#calls + 1] = { "driveFollow", who, route, kmh }
        return true
    end
    function bridge.driveFollowTuned(who, route, kmh, scale)
        calls[#calls + 1] = { "driveFollowTuned", who, route, kmh, scale }
        return true
    end
    function bridge.driveFollowVehicle(who, leader, route, kmh)
        calls[#calls + 1] = { "driveFollowVehicle", who, leader, route, kmh }
        return true
    end
    function bridge.driveApproach(who, route, kmh)
        calls[#calls + 1] = { "driveApproach", who, route, kmh }
        return true
    end
    function bridge.driveTurnAround(who, followBack)
        calls[#calls + 1] = { "driveTurnAround", who, followBack }
        return true
    end
    function bridge.getLastFailure() return "stub refusal" end
    rawset(_G, "SCBridge", bridge)
    local Driving = SC.Driving
    local priorInventory = actor.getInventory
    actor.getInventory = function()
        return { haveThisKeyId = function(_, id) return id == 4242 and { key = true } or nil end }
    end
    check(Driving.available() and Driving.isDriver(actor) and Driving.hasKey(actor),
        "a seated driver holding the car's key is ready to drive")
    local started = Driving.start(actor)
    actor.getInventory = priorInventory
    check(started and calls[1][1] == "driveStart" and calls[1][2] == actor
            and calls[1][3] == true,
        "taking the wheel hands the bridge the driver and whether it holds the key")
    check(Driving.cruise(actor, 12, -0.5) and calls[2][1] == "driveSet"
            and calls[2][3] == -0.5 and calls[2][4] == 12 and calls[2][5] == true,
        "cruise passes speed and steering with obstacle braking on by default")
    check(Driving.cruise(actor, 10, 0, false) and calls[3][5] == false,
        "obstacle braking can only be switched off explicitly")
    check(Driving.hold(actor) and calls[4][3] == 0 and calls[4][4] == 0 and calls[4][5] == true,
        "holding is a zero-speed cruise that keeps obstacle braking")
    bridge.refuseSet = true
    local refused, refusedReason = Driving.cruise(actor, 10, 0)
    bridge.refuseSet = false
    check(refused == false and refusedReason == "stub refusal",
        "a native refusal comes back with the bridge's reason")
    local status = Driving.status(actor)
    local lane = Driving.scanLane(actor, 14)
    check(status and status.state == "cruising" and status.speedKmh == 9
            and lane and lane.blocked == true and lane.obstacleKind == "vehicle"
            and lane.lookAhead == 14,
        "status and lane scans come back as plain tables")
    check(Driving.routeText({ { x = 1, y = 2, width = 8 }, { x = 10.5, y = 2 } })
            == "1.00,2.00,8.0;10.50,2.00,0.0"
            and Driving.routeText({ { x = 1, y = 2 } }) == nil
            and Driving.routeText({ { x = 1 }, { x = 2, y = 3 } }) == nil,
        "a planned route becomes the bridge's x,y,width text, and a broken one is refused")
    local route = { points = { { x = 5, y = 6, width = 8 }, { x = 45, y = 6, width = 8 } } }
    check(Driving.followRoute(actor, route, 12) and calls[#calls][1] == "driveFollow"
            and calls[#calls][3] == "5.00,6.00,8.0;45.00,6.00,8.0" and calls[#calls][4] == 12,
        "following a planner route hands the bridge its points and cruise speed")
    local convoyAccepted, convoyReason = Driving.followVehicle(actor, car, route, 50)
    check(convoyAccepted
            and calls[#calls][1] == "driveFollowVehicle"
            and calls[#calls][3] == car and calls[#calls][5] == 50,
        "convoy trail keeps the lead vehicle identity and its 50 km/h ceiling: "
            .. tostring(convoyReason) .. " last=" .. tostring(calls[#calls][1]))
    local priorCalls = #calls
    local refusedRoute, refusedRouteReason = Driving.followRoute(actor, { points = {} }, 12)
    check(refusedRoute == false and refusedRouteReason == "route has fewer than two points"
            and #calls == priorCalls,
        "an empty route never reaches the bridge")
    check(Driving.turnAround(actor, true) and calls[#calls][1] == "driveTurnAround"
            and calls[#calls][3] == true,
        "turning round asks the bridge to drive the route back")
    check(Driving.release(actor) and calls[#calls][1] == "driveStop",
        "letting go of the wheel stops native driving")
    local bookedPlayer = { vehicle = nil }
    function bookedPlayer:getVehicle() return self.vehicle end
    check(car:enter(1, bookedPlayer), "the booked player boards a real passenger seat")
    local ordinary, ordinaryWhy = Driving.start(actor)
    check(ordinary == false and ordinaryWhy == "player_aboard",
        "ordinary companion driving still refuses a real passenger")
    local booked, bookedWhy = Driving.start(actor, bookedPlayer)
    check(booked == true and calls[#calls][1] == "driveStartWithPassenger"
            and calls[#calls][2] == actor and calls[#calls][3] == bookedPlayer,
        "only an exact seated passenger reaches the service bridge entry: "
            .. tostring(bookedWhy))
    car.occupants[2] = { stranger = true }
    check(not Driving.isDriving(actor) and calls[#calls][1] == "driveStop",
        "an unexpected passenger revokes the active service drive")
    car.occupants[2] = nil
    local rebooked = Driving.start(actor, bookedPlayer)
    check(rebooked == true, "the exact player may start again after the stranger leaves")
    car:exit(bookedPlayer)
    check(not Driving.isDriving(actor) and calls[#calls][1] == "driveStop",
        "the service drive stops when its booked player exits")
    rawset(_G, "SCBridge", nil)
    local offline, offlineReason = Driving.cruise(actor, 10, 0)
    check(not Driving.available() and offline == false
            and offlineReason == "driving bridge is unavailable",
        "without the native bridge driving fails closed")
    rawset(_G, "SCBridge", priorBridge)

    local leftWheel, leftReason = SC.Vehicle.exit(actor, car)
    check(leftWheel and leftReason == "native_exit" and car:getDriver() == nil
            and actor:getVehicle() == nil,
        "a companion gets out of the driver's seat through the ordinary exit: "
            .. tostring(leftReason))
    check(not Driving.isDriver(actor), "a companion on foot is not a driver")
    actor.square, actor.px, actor.py = priorSquare, priorPx, priorPy
end
SC.__testCompanionDriving()
SC.__testCompanionDriving = nil

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
do
    local priorTaxiService = SC.TaxiService
    fireVehicle.passengerSeat = 0
    function fireVehicle:getSeat(candidate)
        return candidate == self.passenger and self.passengerSeat or -1
    end
    function fireVehicle:getCharacter(seat)
        return seat == self.passengerSeat and self.passenger or nil
    end
    function fireVehicle:getPassengerDoor(seat)
        return seat == self.passengerSeat and fireDoor or nil
    end
    local ordinaryDriver, ordinaryReason = SC.Vehicle.canPassengerFire(actor,
        {}, "weapons_free")
    SC.TaxiService = { canDefend = function(candidate, vehicle)
        return candidate == actor and vehicle == fireVehicle
    end }
    local stoppedTaxiDriver = SC.Vehicle.canPassengerFire(actor, {}, "weapons_free")
    fireVehicle.speed = 1
    local movingTaxiDriver, movingReason = SC.Vehicle.canPassengerFire(actor,
        {}, "weapons_free")
    check(not ordinaryDriver and ordinaryReason == "vehicle_fire_requires_passenger_seat"
            and stoppedTaxiDriver == true and not movingTaxiDriver
            and movingReason == "vehicle_too_fast_to_fire",
        "only the verified stationary taxi driver may use the driver window")
    SC.TaxiService = priorTaxiService
end
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

do
-- A parked car unloads with its area: the game removes it from the world and
-- later loads it again as a new object with a new runtime id. The companion
-- seated in the removed object is released without vehicle:exit(), which
-- would write the removed car back to the vehicle database, and goes back to
-- the reloaded car's door, found by the database id.
local staleCar = { id = 31, sqlId = 5, script = "Base.TestCar", x = 1, y = 0, z = 0,
    removed = false, exits = 0 }
function staleCar:getId() return self.id end
function staleCar:getSqlId() return self.sqlId end
function staleCar:getScriptName() return self.script end
function staleCar:getX() return self.x end
function staleCar:getY() return self.y end
function staleCar:getZ() return self.z end
function staleCar:getSeat(candidate) return self.passenger == candidate and 1 or -1 end
function staleCar:getCharacter(seat) return seat == 1 and self.passenger or nil end
function staleCar:isRemovedFromWorld() return self.removed end
function staleCar:clearPassenger(seat)
    if seat ~= 1 then return false end
    self.passenger = nil
    return true
end
function staleCar:exit()
    self.exits = self.exits + 1
    return true
end
function actor:setVehicle(value) self.vehicle = value end
function actor:setCollidable(value) self.collidable = value end
function actor:ensureUnscheduled()
    self.unscheduled = true
    return true
end
actor.vehicle, staleCar.passenger = staleCar, actor
local keptSeat, keptReason = SC.Vehicle.releaseUnloadedSeat(actor)
check(keptSeat == false and keptReason == "vehicle_loaded"
        and actor:getVehicle() == staleCar and staleCar.passenger == actor,
    "a companion in a loaded car keeps its seat")
staleCar.removed = true
local released, anchor = SC.Vehicle.releaseUnloadedSeat(actor)
check(released == true and type(anchor) == "table"
        and actor:getVehicle() == nil and staleCar.passenger == nil
        and staleCar.exits == 0 and actor.unscheduled == true
        and actor.collidable == true and not SC.Vehicle.isNativeSeated(actor)
        and anchor.sqlId == 5 and anchor.seat == 1 and anchor.x == 1 and anchor.y == 0,
    "a companion seated in an unloaded car is released without a database write: "
        .. tostring(type(anchor) == "table" and anchor.sqlId or anchor))

local reloaded = setmetatable({ id = 44 }, { __index = vehicle })
function reloaded:getSqlId() return 5 end
function reloaded:isRemovedFromWorld() return false end
local otherCar = setmetatable({ id = 45 }, { __index = vehicle })
function otherCar:getSqlId() return 6 end
function otherCar:isRemovedFromWorld() return false end
local carList = { items = { otherCar, reloaded } }
function carList:size() return #self.items end
function carList:get(index) return self.items[index + 1] end
local priorCarCell = getCell
getCell = function()
    return { getVehicles = function() return carList end }
end
local door, doorReason = SC.Vehicle.reloadedCarSquare(anchor)
local doorGap = door and reloaded:getEnterSeatDistance(1, door:getX() + 0.5,
    door:getY() + 0.5) or nil
function reloaded:getEnterSeatDistance(seat, x, y)
    if seat == 0 then return (x - 0.5) ^ 2 + (y - 0.5) ^ 2 end
    return vehicle.getEnterSeatDistance(self, seat, x, y)
end
local driverDoor, driverDoorReason = SC.Vehicle.reloadedCarSquare({ sqlId = 5, seat = 0 })
local driverGap = driverDoor and reloaded:getEnterSeatDistance(0,
    driverDoor:getX() + 0.5, driverDoor:getY() + 0.5) or nil
reloaded.getEnterSeatDistance = nil
local missing, missingReason = SC.Vehicle.reloadedCarSquare({ sqlId = 7, seat = 1 })
reloaded.speed = 6
local movingDoor = SC.Vehicle.reloadedCarSquare(anchor)
check(movingDoor == nil, "an unloaded passenger cannot recover beside a car still moving")
reloaded.speed = 0
local priorArrayList = ArrayList
local nativeSet = { size = function() return #carList.items end }
local setCopies = 0
ArrayList = { new = function(collection)
    assert(collection == nativeSet, "copy the actual vehicle collection")
    setCopies = setCopies + 1
    return carList
end }
getCell = function() return { getVehicles = function() return nativeSet end } end
local setDoor, setDoorReason = SC.Vehicle.reloadedCarSquare({ sqlId = 5, seat = 0 })
check(setDoor ~= nil and setDoorReason == "car_door" and setCopies == 1,
    "the driver's door is found in Build 42's non-indexed vehicle Set")
ArrayList.new = function() error("collection copy unavailable") end
local failedSetDoor = SC.Vehicle.reloadedCarSquare({ sqlId = 5, seat = 0 })
check(failedSetDoor == nil, "failed native Set conversion cannot invent a loaded car")
ArrayList = priorArrayList
getCell = priorCarCell
check(door ~= nil and doorReason == "car_door" and doorGap ~= nil and doorGap <= 2.56,
    "the released companion goes to the door of the reloaded car with the same database id")
check(driverDoor ~= nil and driverDoorReason == "car_door"
        and driverGap ~= nil and driverGap <= 2.56,
    "seat zero resolves a safe tile beside the reloaded driver's door")
check(missing == nil and missingReason == "car_not_loaded",
    "a car that has not loaded again yet leaves the companion waiting")
actor.setVehicle, actor.setCollidable, actor.ensureUnscheduled = nil, nil, nil
actor.vehicle, actor.unscheduled, actor.collidable = nil, nil, nil
SC.Vehicle.reset()
end

do
-- LF-04: a temporary virtual-seat restore failure must be retried, not consumed
-- after one attempt. restoreForVehicle reports how many stored passengers still
-- await placement so the runtime keeps retrying instead of stranding them.
local passengerRecord = {
    id = "sc-vseat-retry",
    vehicle = { stored = true, vehicle = { id = vehicle.id, script = vehicle.script }, seat = 2 },
}
check(SC.Vehicle.importStored(passengerRecord) == true
        and SC.Vehicle.storedCountFor(vehicle) == 1,
    "a stored virtual passenger is counted for its vehicle key")
local realRestoreAt = SC.Persistence.restoreAt
SC.Persistence.restoreAt = function() return nil, "no loaded spawn square" end
local restored, remaining = SC.Vehicle.restoreForVehicle(vehicle, manifestPlayer)
SC.Persistence.restoreAt = realRestoreAt
check(restored == 0 and remaining == 1,
    "a temporary restore failure leaves the passenger stored and reports it as remaining, so the runtime retries the exit instead of consuming it")
SC.Vehicle.reset()
end

do
-- 0.26.1 sent every car exit through the native door check with a nil seat:
-- one logged engine exception per nearby tile, and no tile ever qualified, so
-- a stored passenger could not be placed at all.
nilSeatQueries = 0
local tileLookups = 0
local realGridSquare = vehicleCell.getGridSquare
vehicleCell.getGridSquare = function(...)
    tileLookups = tileLookups + 1
    return realGridSquare(...)
end
local noneRestored, noneRemaining = SC.Vehicle.restoreForVehicle(vehicle, manifestPlayer)
vehicleCell.getGridSquare = realGridSquare
check(noneRestored == 0 and noneRemaining == 0 and nilSeatQueries == 0 and tileLookups == 0,
    "leaving a car with nobody stored in it searches no tiles and asks the native door check nothing")
check(SC.Vehicle.importStored({
        id = "sc-vseat-place",
        vehicle = { stored = true, vehicle = { id = vehicle.id, script = vehicle.script },
            seat = 2 },
    }) == true, "a stored passenger awaits placement beside its car")
local placedAt
local realRestoreAt = SC.Persistence.restoreAt
SC.Persistence.restoreAt = function(_, square)
    placedAt = square
    return {}, "restored"
end
local restored, remaining = SC.Vehicle.restoreForVehicle(vehicle, manifestPlayer)
SC.Persistence.restoreAt = realRestoreAt
check(restored == 1 and remaining == 0 and placedAt ~= nil and nilSeatQueries == 0,
    "a stored passenger is placed on a loaded tile beside the car without a nil-seat door query")
SC.Vehicle.reset()
end

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

-- The rejection contract needs a shove attempt. A following companion may
-- instead take its stable unarmed withdrawal policy, so use guard for this
-- one integration probe and restore Follow afterward.
check(SC.Commands.issue(record.id, "guard", nil, nil),
    "combat rejection probe selects a shove-capable order")
local combatOk, combatReason = SC.Combat.update(actor, nil, {
    snapshot = {
        threats = {{ actor = target, distanceSq = 1, visible = true, attacking = true }},
        allies = {}, escapeSquares = {}, pressure = 0, immediateCount = 1,
    },
})
check(not combatOk and string.find(tostring(combatReason), "rejected", 1, true) ~= nil
    and provider.lastRejectedAction == "shove",
    "real Combat -> GameplayUtil -> Actor -> NativeActions chain propagates rejection")
check(SC.Commands.issue(record.id, "follow", nil, nil),
    "combat rejection probe restores Follow")

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

do
    local saved = { px = actor.px, py = actor.py, forwardX = actor.forwardX,
        forwardY = actor.forwardY, moving = actor.moving, aiming = actor.aiming,
        tacticalMovement = actor.tacticalMovement,
        strafeX = actor.strafeX, strafeY = actor.strafeY }
    actor.px, actor.py, actor.forwardX, actor.forwardY = 0.5, 0.5, -1, 0
    actor.moving, actor.aiming = false, false
    local hauled, haulReason = SC.NativeMovementActions.dispatch(actor, "walk", {
        action = "drag_body_to_grave", dx = 1, dy = 0, draggingBody = true,
    }, directProvider)
    check(hauled == true and actor.px > 0.5 and actor.forwardX < -0.9
            and actor.tacticalMovement ~= true and actor.aiming ~= true,
        "corpse hauling translates toward the grave while facing the body without aiming: "
            .. tostring(haulReason))
    local priorDragProbe = actor.isDraggingCorpse
    actor.isDraggingCorpse = function() return true end
    local nativeFacing = SC.NativeActions.faceDraggedCorpse(actor,
        { x = actor:getX() + 1, y = actor:getY(), z = 0 })
    check(nativeFacing and actor.forwardX < -0.9,
        "a retained native door path restores the backward corpse-drag bearing")
    actor.isDraggingCorpse = priorDragProbe
    for key, value in pairs(saved) do actor[key] = value end
    if saved.px == nil then actor.px = nil end
    if saved.py == nil then actor.py = nil end
    if saved.aiming == nil then actor.aiming = nil end
    if saved.tacticalMovement == nil then actor.tacticalMovement = nil end
    if saved.strafeX == nil then actor.strafeX = nil end
    if saved.strafeY == nil then actor.strafeY = nil end
end

do
    local blowtorch = { uses = 2 }
    function blowtorch:getCurrentUses() return self.uses end
    local pry = { broken = false }
    function pry:isBroken() return self.broken end
    local inventory = {}
    function inventory:getFirstTypeEvalRecurse(itemType, predicate)
        if itemType == "BlowTorch" and predicate(blowtorch) then return blowtorch end
        return nil
    end
    function inventory:getFirstTagEvalRecurse(tag, predicate)
        if tag ~= nil and predicate(pry) then return pry end
        return nil
    end
    local worker = { inventory = inventory }
    function worker:getInventory() return self.inventory end
    local barricade = { metal = false, bars = false }
    function barricade:isMetal() return self.metal end
    function barricade:isMetalBar() return self.bars end
    local object = { barricade = barricade }
    function object:getBarricadeForCharacter() return self.barricade end
    local priorItemTag = ItemTag
    ItemTag = { REMOVE_BARRICADE = "REMOVE_BARRICADE" }
    local foundBarricade, woodTool = SC.NativeActions._removeBarricadeToolForTests(worker, object)
    barricade.metal = true
    local _, sheetTool = SC.NativeActions._removeBarricadeToolForTests(worker, object)
    barricade.metal, barricade.bars = false, true
    local _, barsTool = SC.NativeActions._removeBarricadeToolForTests(worker, object)
    object.barricade = nil
    local missingBarricade, missingTool, missingReason =
        SC.NativeActions._removeBarricadeToolForTests(worker, object)
    function object:getBarricadeForCharacter() error("lookup exploded") end
    local failedBarricade, failedTool, failedReason =
        SC.NativeActions._removeBarricadeToolForTests(worker, object)
    ItemTag = priorItemTag
    check(foundBarricade == barricade and woodTool == pry
            and sheetTool == blowtorch and barsTool == blowtorch
            and missingBarricade == nil and missingTool == nil
            and missingReason == "companion cannot reach the selected barricade side",
        "unbarricade resolves success/value order and selects pry versus blowtorch by live material")
    check(failedBarricade == nil and failedTool == nil
            and failedReason == "companion cannot reach the selected barricade side",
        "unbarricade treats a throwing barricade lookup as unavailable")
end

do
local oldForwardX, oldForwardY = actor.forwardX, actor.forwardY
local oldMoving = actor.moving
local oldRunning, oldSprinting = actor.running, actor.sprinting
local originalFaceLocation = actor.faceLocationF
local faceCalls = 0
actor.px, actor.py = 0.5, 0.5
actor.forwardX, actor.forwardY, actor.turning = -1, 0, false
function actor:faceLocationF(x, y)
    faceCalls = faceCalls + 1
    return originalFaceLocation(self, x, y)
end
local requested, requestedReason = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), 1, 0, false, {})
local retained, retainedReason = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), 1, 0, false, {})
actor.turning = false
local ready = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), 1, 0, false, {})
local continuousCorner = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), 0, 1, false, { continuousFollow = true })
local continuousReverse, continuousReverseReason = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), -1, 0, false, { continuousFollow = true })
local urgentTurn = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), -1, 0, false, { urgent = true })

-- The 0.23.0 playtest stalled every scavenge approach a hair short of its goal
-- square: 0.036 tiles away, the actor turned instead of stepping for 1500
-- frames and the approach timed out. Within a fraction of a tile the direction
-- vector is mostly noise, so the facing test fails on nearly every tick.
local reversedShortStep = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), -1, 0, false, {}, 0.036)
local reversedFullStep, reversedFullReason = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), -1, 0, false, {}, 1.5)
actor.turning = true
local turningShortStep = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), -1, 0, false, {}, 0.036)
actor.turning = false
actor.faceLocationF = originalFaceLocation
-- The fixture does not advance the native animation graph between checks. The
-- turn requested above is explicitly completed before later movement tests.
actor.forwardX, actor.forwardY, actor.turning = oldForwardX, oldForwardY, false
check(reversedShortStep == nil and turningShortStep == nil,
    "a final fractional step waited for a turn and could never arrive")
-- Walking across a room to a shelf is cruising, not a tactical reposition.
-- Without this a scavenger advances in visible single paces while a follower
-- covers the same ground smoothly.
check(SC.NativeActions._prepareForwardTurnForTests(
        actor, actor:getX(), actor:getY(), 0, 1, false,
        { continuousApproach = true }, 4) == nil,
    "an approach walk stopped for a shallow turn the way a follower does not")
check(SC.NativeActions._prepareForwardTurnForTests(
        actor, actor:getX(), actor:getY(), 0, 1, false, {}, 4) ~= nil,
    "an ordinary walk stopped relaxing its turn rule, so the approach flag proves nothing")
-- That last probe deliberately requests a turn, and the fixture does not
-- advance the animation graph. Complete it, as the block above does, or every
-- later movement check inherits a turning actor.
actor.forwardX, actor.forwardY, actor.turning = oldForwardX, oldForwardY, false
actor.moving, actor.running, actor.sprinting = false, oldRunning, oldSprinting
check(reversedFullStep == true and reversedFullReason == "turning_for_movement",
    "an ordinary reversal no longer turns before moving")
actor.moving, actor.running, actor.sprinting = oldMoving, oldRunning, oldSprinting
check(requested == true and requestedReason == "turning_for_movement"
        and retained == true and retainedReason == "turning_for_movement"
        and ready == nil and faceCalls == 2,
    "sharp player-track corners finish one native turn before translation resumes")
check(continuousCorner == nil and continuousReverse == true
        and continuousReverseReason == "turning_for_movement" and urgentTurn == nil,
    "continuous follow blends a right-angle bend but still stops before reversing")
end

do
local oldForwardX, oldForwardY, oldTurning = actor.forwardX, actor.forwardY, actor.turning
local oldMoving, oldRunning, oldSprinting = actor.moving, actor.running, actor.sprinting
actor.forwardX, actor.forwardY, actor.turning = 1, 0, true
local shallow = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), 0.8, 0.6, false, { continuousFollow = true })
local reverse, reverseReason = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), -1, 0, false, { continuousFollow = true })
actor.forwardX, actor.forwardY, actor.turning = 1, 0, true
local track, trackReason = SC.NativeActions._prepareForwardTurnForTests(
    actor, actor:getX(), actor:getY(), 0.8, 0.6, false, {})
actor.forwardX, actor.forwardY, actor.turning = oldForwardX, oldForwardY, oldTurning
actor.moving, actor.running, actor.sprinting = oldMoving, oldRunning, oldSprinting
check(shallow == nil and reverse == true and reverseReason == "turning_for_movement"
        and track == true and trackReason == "turning_for_movement",
    "a follower keeps walking through a turn underway; a reversal or player-track step still waits")
end

actor.px, actor.py = 0.5, 0.5
local moved, moveReason = SC.Actor.setMovement(actor, "jog", { action = "move", dx = 1, dy = 0 })
actor.healthyJogDistanceForTest = actor.px - 0.5
check(moved and moveReason == "moving" and actor.running == true and actor.px > 0.5,
    "direct-native adapter starts and verifies normalized movement")
do
    -- Dismissal is a player order: the short pause between actions or a routine
    -- job holding the actor must not swallow it, while combat keeps its claim.
    -- The farewell walk is real native movement, so it needs a direction.
    local recruit = setmetatable({
        __owned = true, __class = "IsoPlayer", data = {},
        square = { x = 2, y = 2, z = 0 }, px = 2.5, py = 2.5,
        characterActions = actionList(),
    }, { __index = actor })
    local record = SC.Registry.register(recruit, { id = "sc-dismiss-recruit", recruited = false })
    check(record ~= nil and SC.Commands.issue(record.id, "recruit", nil, manifestPlayer)
            and SC.Commands.issue(record.id, "dismiss", nil, manifestPlayer)
            and SC.Commands.peek(recruit).recruited == false,
        "a dismissed companion is given a direction to walk away in")
    check(SC.Commands.issue(record.id, "recruit", nil, manifestPlayer)
            and SC.NativeActions.beginPacing(recruit, "core_dismiss_pause",
                { minimumMs = 60000, maximumMs = 60000 })
            and SC.NativeActions.pacingStatus(recruit) == true,
        "dismissal fixture pauses the recruit between actions")
    check(SC.Commands.issue(record.id, "dismiss", nil, manifestPlayer)
            and SC.Commands.peek(recruit).recruited == false
            and SC.NativeActions.pacingStatus(recruit) == false,
        "a companion pausing between actions can still be dismissed")
    local jobCancelled = false
    check(SC.Commands.issue(record.id, "recruit", nil, manifestPlayer)
            and SC.ActionSupervisor.begin(recruit, {
                owner = "scavenge", action = "loot_container", targetKey = "container:dismiss",
                priority = SC.ActionSupervisor.Priority.WORK, interruptible = true,
                onCancel = function(_, reason) jobCancelled = true return true, reason end,
            }) ~= nil,
        "dismissal fixture gives the recruit a routine job")
    check(SC.Commands.issue(record.id, "dismiss", nil, manifestPlayer)
            and SC.Commands.peek(recruit).recruited == false
            and jobCancelled and SC.ActionSupervisor.current(recruit) == nil,
        "a companion busy with a routine job is released and dismissed")
    local combat = SC.Commands.issue(record.id, "recruit", nil, manifestPlayer)
        and SC.ActionSupervisor.begin(recruit, {
            owner = "combat", action = "escape", targetKey = "threat:dismiss",
            priority = SC.ActionSupervisor.Priority.SURVIVAL, interruptible = true,
        })
    check(combat ~= nil and combat ~= false
            and not SC.Commands.issue(record.id, "dismiss", nil, manifestPlayer)
            and SC.Commands.peek(recruit).recruited == true
            and SC.ActionSupervisor.current(recruit) == combat,
        "a companion fighting for its life keeps its claim over a dismissal")
    if combat then SC.ActionSupervisor.complete(combat, "test_done") end
    SC.NativeActions.stopDirect(recruit)
    SC.Registry.unregister(recruit)
end
do
actor.px, actor.py, actor.footInjury, actor.limpSpeedScale = 0.5, 0.5, true, 0.55
local limpMoved, limpReason = SC.Actor.setMovement(
    actor, "jog", { action = "move", dx = 1, dy = 0 })
check(limpMoved and limpReason == "moving" and actor.running == false
        and actor.px > 0.5 and actor.px - 0.5 < actor.healthyJogDistanceForTest * 0.7,
    "a Run command caps an injured companion to visibly matching limp speed")
end
actor.footInjury, actor.limpSpeedScale = false, 1
actor.healthyJogDistanceForTest = nil
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
;(function()
    local oldTargetCheck = pathBehavior.isTargetLocation
    function pathBehavior:isTargetLocation() return false end
    pathBehavior.cancelled = true
    actor.moving = false
    local rejected, rejectedReason = SC.Actor.setMovement(actor, "walk", {
        action = "path", targetSquare = targetSquare, enginePath = true,
    })
    pathBehavior.isTargetLocation = oldTargetCheck
    check(not rejected and rejectedReason == "native path request did not retain its target"
            and pathBehavior.cancelled == true and actor.moving == false,
        "a mutated native path that fails verification receives full locomotion cleanup")
end)()

local weapon = { getCategory = function() return "Weapon" end }
local equipOk, equipReason = SC.Actor.setMovement(actor, "walk", {
    action = "equip_weapon", item = weapon,
})
check(equipOk and equipReason == "equipped" and actor.primaryHand == weapon,
    "direct-native adapter starts and verifies equipment")
local readyOk, readyReason = SC.Actor.setMovement(actor, "walk", {
    action = "ready_weapon", target = target,
})
check(readyOk and readyReason == "weapon_ready" and actor.aiming == true
        and actor.aimAtFloor == false and actor.companionAimTarget == target
        and actor.forwardX > 0.9,
    "armed companion retains its live combat target throughout the native weapon-ready state")
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
actor.px, actor.py = 0.5, 0.5
local moonwalkOk, moonwalkReason = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 0, dy = 1, facingTarget = target,
})
check(moonwalkOk and moonwalkReason == "moving" and actor.tacticalMovement == true
        and actor.forwardX > 0.9,
    "traveling off the facing axis uses the directional strafe blend even without a tactical flag (moonwalk fix)")
actor.companionAimTarget = target
actor.targetOnGround = target
actor.aimAtFloor = true
local lowerOk, lowerReason = SC.Actor.setMovement(actor, "walk", { action = "lower_weapon" })
check(lowerOk and lowerReason == "weapon_lowered" and actor.aiming == false
        and actor.tacticalMovement == false and actor.strafeX == 0 and actor.strafeY == 0
        and actor.companionAimTarget == nil and actor.targetOnGround == nil
        and actor.aimAtFloor == false,
    "weapon-ready posture lowers and clears stale combat-facing state")
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
    actor.companionAimTarget = nil
    actor.targetOnGround = "stale"
    local warmupOk, warmupReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = target, weapon = twoHandedWeapon,
    })
    check(not warmupOk and warmupReason == "native weapon is not attack-ready"
        and (actor.doAttackCalls or 0) == 0,
        "freshly equipped weapon waits for native CanAttack model readiness")
    check(actor.companionAimTarget == nil and actor.aimAtFloor ~= true
        and actor.targetOnGround == nil,
        "a rejected attack clears the aim target, floor aim, and downed-target residue")
    actor.attackModelReady = true
    -- A retreating actor may still face its old run direction. Model the
    -- game's coarse faceLocationF turn without changing that precise vector;
    -- the hit arc must be corrected before DoAttack starts the shove.
    local originalFaceLocation = actor.faceLocationF
    local originalDoAttack = actor.DoAttack
    actor.forwardX, actor.forwardY = -1, 0
    actor.faceLocationF = function(self)
        self.turning = true
        return true
    end
    actor.DoAttack = function(self, ...)
        self.facingAtAttack = { self.forwardX, self.forwardY }
        return originalDoAttack(self, ...)
    end
    local facingDx, facingDy = target:getX() - actor:getX(), target:getY() - actor:getY()
    local facingLength = math.sqrt(facingDx * facingDx + facingDy * facingDy)
    local expectedX, expectedY = facingDx / facingLength, facingDy / facingLength
    local attackOk, attackReason = SC.Actor.setMovement(actor, "walk", {
        action = "shove", target = target,
    })
    actor.faceLocationF = originalFaceLocation
    actor.DoAttack = originalDoAttack
    check(attackOk and attackReason == "attack_started" and actor.attackType == AttackType.SHOVE
        and actor.doShove == true and actor.doGrapple == false
        and actor.companionAimTarget == target
        and actor.authorizedHandToHandAction ~= false
        and actor.authorizedHandToHand ~= false,
        "direct-native adapter preflights, authorizes, starts, and keeps aim on the started swing")
    check(actor.facingAtAttack and actor.facingAtAttack[1] * expectedX
            + actor.facingAtAttack[2] * expectedY > 0.98,
        "a backward-running companion faces the zombie before shove animation starts"
            .. " (target=" .. tostring(expectedX) .. "," .. tostring(expectedY)
            .. " at attack=" .. tostring(actor.facingAtAttack and actor.facingAtAttack[1])
            .. "," .. tostring(actor.facingAtAttack and actor.facingAtAttack[2]) .. ")")
    actor.attackStarted = false
    local meleeOk, meleeReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = target, weapon = twoHandedWeapon,
    })
    check(meleeOk and meleeReason == "attack_started" and actor.doShove == false,
        "a weapon swing clears stale shove state before the native attack starts")
    actor.attackStarted = false
    actor.companionAttackCollisionSerial = 20
    local evidenceTarget = {
        health = 4,
        getX = function() return 1.5 end,
        getY = function() return 0.5 end,
        getZ = function() return 0 end,
        getHealth = function(self) return self.health end,
        isDead = function(self) return self.health <= 0 end,
        isOnFloor = function() return false end,
        isProne = function() return false end,
    }
    local evidenceAttack = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = evidenceTarget, weapon = twoHandedWeapon,
    })
    evidenceTarget.health = 3.5
    actor.companionAttackCollisionTarget = evidenceTarget
    actor.companionAttackCollisionHitCount = 1
    actor.companionAttackCollisionTargetHit = true
    actor.companionAttackCollisionSerial = 21
    local evidenceHandled, evidenceReason, evidence = SC.NativeActions.pollCombatEvents(actor)
    check(evidenceAttack and evidenceHandled
            and evidenceReason == "attack_melee_collision_landed"
            and evidence and evidence.result == "landed"
            and evidence.healthBefore == 4 and evidence.healthAfter == 3.5,
        "melee collision evidence reports native damage without applying fallback damage")
    actor.attackStarted = false
    local missedAttack = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = evidenceTarget, weapon = twoHandedWeapon,
    })
    actor.companionAttackCollisionTarget = evidenceTarget
    actor.companionAttackCollisionHitCount = 0
    actor.companionAttackCollisionTargetHit = false
    actor.companionAttackCollisionSerial = 22
    local missedHandled, missedReason, missedEvidence = SC.NativeActions.pollCombatEvents(actor)
    check(missedAttack and missedHandled
            and missedReason == "attack_melee_collision_no_effect"
            and missedEvidence and missedEvidence.result == "no_effect",
        "a collision frame without damage is exposed as no-effect evidence for recovery logic")
    actor.attackStarted = false

    -- CB-09. A reflective throw inside the native collision used to leave no
    -- trace: the completed-hit serial never advanced, so Lua saw a timeout --
    -- and a timeout invites a retry, on a call that may already have applied
    -- part of a hit. Both paths now publish a terminal receipt.
    do
        local faultTarget = {
            health = 4,
            getX = function() return 1.5 end,
            getY = function() return 0.5 end,
            getZ = function() return 0 end,
            getHealth = function(self) return self.health end,
            isDead = function(self) return self.health <= 0 end,
            isOnFloor = function() return false end,
            isProne = function() return false end,
        }
        actor.companionAttackReceiptSerial = 5
        actor.companionAttackReceiptOutcome = "completed"
        local faultAttack = SC.Actor.setMovement(actor, "walk", {
            action = "attack_melee", target = faultTarget, weapon = twoHandedWeapon,
        })
        -- The native call threw after it had begun: one claimed attempt, one
        -- failure receipt, and the completed-hit serial deliberately unmoved.
        faultTarget.health = 3.5
        actor.companionAttackReceiptSerial = 6
        actor.companionAttackReceiptOutcome = "failed_maybe_partial"
        actor.companionAttackReceiptCause = "InvocationTargetException: boom"
        local faultHandled, faultReason, faultEvidence =
            SC.NativeActions.pollCombatEvents(actor)
        check(faultAttack and faultHandled == false
                and faultReason == "attack_melee_collision_failed_maybe_partial"
                and faultEvidence and faultEvidence.result == "failed_maybe_partial"
                and faultEvidence.maybePartial == true
                and string.find(tostring(faultEvidence.cause), "boom", 1, true) ~= nil,
            "a collision that threw after impact was not reported as a terminal failure")
        local drained = SC.NativeActions.pollCombatEvents(actor)
        check(drained == false,
            "a failed collision left its pending record behind to be replayed")
        actor.attackStarted = false
        actor.companionAttackReceiptOutcome = "completed"
        actor.companionAttackReceiptCause = ""
    end

    -- CB-11. A shove does no health damage, so its result used to be inferred
    -- from the target being newly grounded or having moved a little. Another
    -- actor's knockdown, or the target simply walking, supplies both.
    do
        local shoveTarget = {
            health = 4, x = 1.5, grounded = false,
            getX = function(self) return self.x end,
            getY = function() return 0.5 end,
            getZ = function() return 0 end,
            getHealth = function(self) return self.health end,
            isDead = function(self) return self.health <= 0 end,
            isOnFloor = function(self) return self.grounded end,
            isProne = function(self) return self.grounded end,
        }
        actor.companionAttackCollisionSerial = 40
        local shoveStarted = SC.Actor.setMovement(actor, "walk", {
            action = "shove", target = shoveTarget,
        })
        -- Somebody else knocks the target down and it drifts, while our own
        -- collision reported a different target entirely.
        shoveTarget.grounded = true
        shoveTarget.x = 2.6
        actor.companionAttackCollisionTarget = { other = true }
        actor.companionAttackCollisionHitCount = 1
        actor.companionAttackCollisionTargetHit = false
        actor.companionAttackCollisionSerial = 41
        local stolenOk, stolenReason, stolenEvidence =
            SC.NativeActions.pollCombatEvents(actor)
        check(shoveStarted and stolenOk
                and stolenReason == "shove_collision_no_effect"
                and stolenEvidence.result == "no_effect"
                and stolenEvidence.collisionTargetMatched == false,
            "a third party's knockdown was credited to this companion's shove")
        actor.attackStarted = false

        -- The same shove, attributed at the real collision boundary, lands.
        shoveTarget.grounded = false
        shoveTarget.x = 1.5
        local ownStarted = SC.Actor.setMovement(actor, "walk", {
            action = "shove", target = shoveTarget,
        })
        actor.companionAttackCollisionTarget = shoveTarget
        actor.companionAttackCollisionHitCount = 1
        actor.companionAttackCollisionTargetHit = false
        actor.companionAttackCollisionSerial = 42
        local ownOk, ownReason, ownEvidence = SC.NativeActions.pollCombatEvents(actor)
        check(ownStarted and ownOk and ownReason == "shove_collision_landed"
                and ownEvidence.result == "landed"
                and ownEvidence.collisionTargetMatched == true,
            "a shove attributed at its own collision boundary was not reported as landed")
        actor.attackStarted = false

        -- Several completed collisions between two polls cannot be told apart,
        -- so that has to be said rather than silently collapsed.
        local overflowStarted = SC.Actor.setMovement(actor, "walk", {
            action = "attack_melee", target = shoveTarget, weapon = twoHandedWeapon,
        })
        actor.companionAttackCollisionTarget = shoveTarget
        actor.companionAttackCollisionHitCount = 1
        actor.companionAttackCollisionTargetHit = true
        actor.companionAttackCollisionSerial = 45
        actor.companionAttackReceiptSerial =
            (actor.companionAttackReceiptSerial or 0) + 3
        local _, _, overflowEvidence = SC.NativeActions.pollCombatEvents(actor)
        check(overflowStarted and overflowEvidence ~= nil
                and overflowEvidence.overflow == true
                and overflowEvidence.eventsSincePoll == 3,
            "several collisions between polls collapsed into one without reporting overflow")
        actor.attackStarted = false
    end

    actor.attackStarted = false
    function twoHandedWeapon:getCategory() return "Weapon" end
    function twoHandedWeapon:getMaxDamage() return 2 end
    function twoHandedWeapon:getMaxRange() return 1.5 end
    function twoHandedWeapon:getMinRange() return 1.2 end
    local groundedWeaponTarget = {
        health = 4,
        getX = function() return 1.5 end,
        getY = function() return 0.5 end,
        getZ = function() return 0 end,
        getHealth = function(self) return self.health end,
        isDead = function(self) return self.health <= 0 end,
        isOnFloor = function() return true end,
        isProne = function() return true end,
        isCrawling = function() return false end,
    }
    actor.companionAttackCollisionSerial = 30
    local groundedWeaponAttack, groundedWeaponReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = groundedWeaponTarget,
        weapon = twoHandedWeapon, floorAttack = true,
    })
    check(groundedWeaponAttack and groundedWeaponReason == "attack_started"
            and actor.aimAtFloor == true and actor.targetOnGround == groundedWeaponTarget
            and actor.useHandWeapon == twoHandedWeapon and actor.doShove == false
            and actor.attackType == AttackType.MELEE_SWING,
        "grounded melee uses the equipped weapon and native player floor-swing state even inside standing minimum range")
    groundedWeaponTarget.health = 3.2
    actor.companionAttackCollisionTarget = groundedWeaponTarget
    actor.companionAttackCollisionHitCount = 1
    actor.companionAttackCollisionTargetHit = true
    actor.companionAttackCollisionSerial = 31
    local groundedWeaponLanded, groundedWeaponLandedReason, groundedWeaponEvidence =
        SC.NativeActions.pollCombatEvents(actor)
    check(groundedWeaponLanded
            and groundedWeaponLandedReason == "attack_melee_collision_landed"
            and groundedWeaponEvidence and groundedWeaponEvidence.source == "native"
            and groundedWeaponEvidence.floorAttack == true
            and groundedWeaponEvidence.healthBefore == 4
            and groundedWeaponEvidence.healthAfter == 3.2,
        "weapon floor attacks wait for native collision damage and expose grounded evidence without a fallback hit")
    actor.attackStarted = false
    local farAttackTarget = {
        getX = function() return 4.5 end,
        getY = function() return 0.5 end,
        getZ = function() return 0 end,
    }
    local attackCallsBeforeRangeGate = actor.doAttackCalls or 0
    local farMeleeOk, farMeleeReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = farAttackTarget, weapon = twoHandedWeapon,
    })
    check(not farMeleeOk and farMeleeReason == "attack target is outside melee range"
            and (actor.doAttackCalls or 0) == attackCallsBeforeRangeGate,
        "the final native attack gate rejects a melee swing before DoAttack when the target is metres away")
    local savedStrikeBarrier = SC.Topology.strikeBarrier
    local checkedStrikeActions = {}
    local checkedWindowPolicies = {}
    SC.Topology.strikeBarrier = function(_, _, action, _, options)
        checkedStrikeActions[#checkedStrikeActions + 1] = action
        checkedWindowPolicies[#checkedWindowPolicies + 1] =
            options and options.allowClosedWindow == true
        return true, "high_fence"
    end
    local callsBeforeBarrier = actor.doAttackCalls or 0
    local blockedMelee, blockedMeleeReason = SC.Actor.setMovement(actor, "walk", {
        action = "attack_melee", target = groundedWeaponTarget,
        weapon = twoHandedWeapon, floorAttack = true,
        combatDoctrine = "weapons_free",
    })
    local blockedShove, blockedShoveReason = SC.Actor.setMovement(actor, "walk", {
        action = "shove", target = groundedWeaponTarget,
    })
    SC.Topology.strikeBarrier = savedStrikeBarrier
    check(not blockedMelee and blockedMeleeReason == "attack_path_blocked:high_fence"
            and not blockedShove and blockedShoveReason == "attack_path_blocked:high_fence"
            and checkedStrikeActions[1] == "attack_melee"
            and checkedStrikeActions[2] == "shove"
            and checkedWindowPolicies[1] == true
            and checkedWindowPolicies[2] == false
            and (actor.doAttackCalls or 0) == callsBeforeBarrier,
        "physical attacks stop at the shared blocker gate before DoAttack while free-fire window permission is melee-only")
    local function stompTarget(health)
        local value = { health = health, hitCalls = 0, setHealthCalls = 0 }
        function value:getX() return 1.0 end
        function value:getY() return 0.5 end
        function value:getZ() return 0 end
        function value:isProne() return true end
        function value:isOnFloor() return true end
        function value:isCrawling() return false end
        function value:isDead() return self.health <= 0 end
        function value:getHealth() return self.health end
        function value:setHealth(nextHealth)
            self.setHealthCalls = self.setHealthCalls + 1
            self.health = nextHealth
        end
        function value:Hit()
            self.hitCalls = self.hitCalls + 1
        end
        return value
    end
    local function collision(targetValue, hit, count)
        actor.companionAttackCollisionTarget = targetValue
        actor.companionAttackCollisionTargetHit = hit == true
        actor.companionAttackCollisionHitCount = count or (hit and 1 or 0)
        actor.companionAttackCollisionSerial =
            (actor.companionAttackCollisionSerial or 0) + 1
    end

    actor.companionAttackCollisionSerial = 40
    actor.wornShoes = nil
    local stomped = stompTarget(2)
    local stompOk, stompReason = SC.Actor.setMovement(actor, "walk", {
        action = "stomp", target = stomped, floorAttack = true,
    })
    check(stompOk and stompReason == "attack_started" and stomped.health == 2,
        "a started stomp never applies damage before its native collision frame")
    stomped.health = 1.25
    collision(stomped, true, 1)
    local landed, landedReason, impact = SC.NativeActions.pollCombatEvents(actor)
    check(landed and landedReason == "stomp_collision_landed"
            and impact and impact.result == "landed" and impact.source == "native"
            and impact.collisionTargetMatched == true and impact.hitCount == 1
            and impact.healthBefore == 2 and impact.healthAfter == 1.25
            and stomped.hitCalls == 0 and stomped.setHealthCalls == 0,
        "stomp accepts one exact native target hit without any Lua damage fallback")

    actor.attackStarted = false
    local missed = stompTarget(2)
    local missStarted = SC.Actor.setMovement(actor, "walk", {
        action = "stomp", target = missed, floorAttack = true,
    })
    collision(missed, false, 0)
    local missHandled, missReason, missEvidence = SC.NativeActions.pollCombatEvents(actor)
    check(missStarted and missHandled and missReason == "stomp_collision_no_effect"
            and missEvidence.result == "no_effect" and missed.health == 2
            and missed.hitCalls == 0 and missed.setHealthCalls == 0,
        "a native stomp miss remains a miss and never becomes a guaranteed fallback hit")

    actor.attackStarted = false
    local intended, other = stompTarget(2), stompTarget(2)
    local exactStarted = SC.Actor.setMovement(actor, "walk", {
        action = "stomp", target = intended, floorAttack = true,
    })
    other.health = 1
    collision(other, true, 1)
    local exactHandled, _, exactEvidence = SC.NativeActions.pollCombatEvents(actor)
    check(exactStarted and exactHandled and exactEvidence.result == "no_effect"
            and exactEvidence.collisionTargetMatched == false
            and intended.health == 2 and intended.hitCalls == 0,
        "a hit on another prone zombie cannot be credited to or damage the intended target")

    actor.attackStarted = false
    local killed = stompTarget(0.4)
    local killStarted = SC.Actor.setMovement(actor, "walk", {
        action = "stomp", target = killed, floorAttack = true,
    })
    killed.health = 0
    collision(killed, true, 1)
    local killHandled, _, killEvidence = SC.NativeActions.pollCombatEvents(actor)
    check(killStarted and killHandled and killEvidence.result == "landed"
            and actor.targetOnGround == nil,
        "a native lethal stomp clears the retained floor target after collision")
    actor.wornShoes = nil
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
function actor:openWindow(value)
    value.opened = true
    self.openingWindow = true
end
function actor:getVariableBoolean(name)
    if name == "SitOnFurnitureStarted" then return self.furniturePoseStarted == true end
    if name == "OnBedStarted" then return self.bedPoseStarted == true end
    return name == "bOpenWindow" and self.openingWindow == true
end
function actor:smashWindow(value) value.smashed = true end
function actor:climbThroughWindow() self.climbing = true end
function actor:isClimbing() return self.climbing == true end
function actor:climbOverFence(direction)
    self.climbing = true
    self.climbDirection = direction
    self.climbKind = "fence"
end
function actor:hopFence(direction, testOnly)
    if testOnly == true then return direction ~= nil end
    if direction == nil then return false end
    self.climbing = true
    self.climbDirection = direction
    self.climbKind = "fence"
    self.usedHopFence = true
    return true
end
function actor:canClimbOverWall(direction) return direction ~= nil end
function actor:climbOverWall(direction)
    if direction == nil then return false end
    self.climbing = true
    self.climbDirection = direction
    self.climbKind = "wall"
    return true
end
function actor:cancelCompanionStuckClimb()
    self.climbing = false
    return true
end
do
    actor.climbing = true
    local climbCancelled, climbCancelReason = SC.NativeActions.cancelStuckClimb(actor)
    check(climbCancelled and climbCancelReason == "stuck_climb_cancelled"
            and actor.climbing == false,
        "stale-climb adapter verifies that the native climb state actually ended")
    local stubbornClimber = {
        isClimbing = function() return true end,
        cancelCompanionStuckClimb = function() return true end,
    }
    local stubbornCancelled, stubbornReason = SC.NativeActions.cancelStuckClimb(stubbornClimber)
    check(not stubbornCancelled and stubbornReason == "native_climb_state_remains",
        "stale-climb adapter rejects an unverified native state transition")
end
do
IsoDirections = IsoDirections or { N = "N", S = "S", E = "E", W = "W" }
actor.climbing, actor.climbDirection, actor.climbKind = false, nil, nil
local fenceOk, fenceReason = SC.Actor.setMovement(actor, "walk", {
    action = "climb_fence", direction = "east", nativeAffordance = "fence",
})
check(fenceOk and fenceReason == "fence_climb_started"
        and actor.climbing and actor.climbDirection == IsoDirections.E
        and actor.climbKind == "fence",
    "direct-native adapter enters the stock low-fence climb state")
actor.climbing, actor.climbDirection, actor.climbKind = false, nil, nil
local wallOk, wallReason = SC.Actor.setMovement(actor, "walk", {
    action = "climb_wall", direction = "north", nativeAffordance = "fence",
})
check(wallOk and wallReason == "wall_climb_started"
        and actor.climbing and actor.climbDirection == IsoDirections.N
        and actor.climbKind == "wall",
    "direct-native adapter validates and enters the stock tall-wall climb state")
actor.climbing, actor.climbDirection, actor.climbKind = false, nil, nil
end
do
local windowOk, windowReason = SC.Actor.setMovement(actor, "walk", {
    action = "open_window", object = window,
})
local windowPhase, windowOwner = SC.NativeActions.activityStatus(actor)
check(windowOk and window.opened and windowPhase == "active" and windowOwner == "traversal",
    "an opened window retains traversal ownership until its native animation finishes")
local tailMovement = SC.Actor.setMovement(actor, "walk", { action = "ready_weapon" })
check(not tailMovement, "another pose cannot interrupt the open-window animation tail")
actor.openingWindow = false -- the native state exits on a later simulation frame
SC_TEST_CLOCK = SC_TEST_CLOCK + 16
check(SC.NativeActions.activityStatus(actor) == "none",
    "window effect completion plus native state exit releases traversal ownership")
end
local downedOk = SC.Actor.setMovement(actor, "walk", { action = "downed" })
check(downedOk and actor.knockedDown == true,
    "direct-native adapter verifies native downed state")
-- The engine exits this state on a later frame; the fixture has no state-machine
-- update loop, so complete that transition before testing voluntary rest.
actor.knockedDown = false

do
local oldPathFindAction, oldRestAction, oldGetOnBedAction, oldSeatingManager =
    ISPathFindAction, ISRestAction, ISGetOnBedAction, SeatingManager
local lastFurniturePath, lastNearestLocations
local function testPathAction(character, object)
    local value = ISBaseTimedAction.new(ISBaseTimedAction, character)
    value.goalFurnitureObject = object
    function value:start() end
    function value:setOnComplete(callback, ...)
        self.completeCallback, self.completeArgs = callback, { ... }
    end
    function value:setOnFail(callback, ...)
        self.failCallback, self.failArgs = callback, { ... }
    end
    function value:completePath()
        if self.completeCallback then
            self.completeCallback(self.completeArgs[1], self.completeArgs[2], self.completeArgs[3])
        end
        ISBaseTimedAction.perform(self)
        local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
        if queue.current and queue.current.action == nil then queue.current:begin() end
    end
    function value:failPath()
        if self.failCallback then
            self.failCallback(self.failArgs[1], self.failArgs[2], self.failArgs[3])
        end
        ISBaseTimedAction.stop(self)
    end
    return value
end
ISPathFindAction = {}
function ISPathFindAction:pathToSitOnFurniture(character, object, anySpriteGridObject)
    lastFurniturePath = testPathAction(character, object)
    lastFurniturePath.anySpriteGridObject = anySpriteGridObject
    return lastFurniturePath
end
function ISPathFindAction:pathToNearest(character, locations)
    lastNearestLocations = locations
    return testPathAction(character, nil)
end
ISRestAction = {}
function ISRestAction:new(character, object, useAnimations)
    local value = ISBaseTimedAction.new(ISBaseTimedAction, character)
    value.bed, value.useAnimations = object, useAnimations
    function value:start()
        if self.bed and self.bed.setSatChair then self.bed:setSatChair(true) end
        self.character:setSitOnFurnitureObject(self.bed)
        self.character:setSittingOnFurniture(true)
        self.character.furniturePoseStarted = false
        self.character:reportEvent("EventSitOnFurniture")
    end
    return value
end
ISGetOnBedAction = {}
function ISGetOnBedAction:new(character, object)
    local value = ISBaseTimedAction.new(ISBaseTimedAction, character)
    value.bed = object
    function value:start()
        self.character:setSitOnFurnitureObject(self.bed)
        self.character:setOnBed(true)
        self.character.bedPoseStarted = false
        self.character:reportEvent("EventGetOnBed")
    end
    return value
end
SeatingManager = {
    getInstance = function()
        return {
            getFacingDirection = function() return "N" end,
        }
    end,
}
IsoFlagType = IsoFlagType or {}
IsoFlagType.bed = IsoFlagType.bed or "bed"

local seat = { occupied = false }
function seat:setSatChair(value) self.occupied = value == true end
local boundedTurn = { waitToStart = function() return true end }
SC.NativeActions._boundSeatingTurnForTests(boundedTurn)
local turnStartedAt = SC_TEST_CLOCK
check(boundedTurn:waitToStart() == true,
    "furniture entry initially gives the native facing turn time to settle")
SC_TEST_CLOCK = turnStartedAt + SC.Config.get("furnitureTurnTimeoutMs") + 1
check(boundedTurn:waitToStart() == false and boundedTurn.scSeatingTurnBounded == true,
    "a companion turn state cannot hold furniture entry forever")
local sitOk, sitReason = SC.Actor.setMovement(actor, "walk", { action = "sit", object = seat })
check(sitOk and sitReason == "taking_seat" and lastFurniturePath ~= nil
        and lastFurniturePath.anySpriteGridObject == true and actor.sitting ~= true,
    "furniture rest first paths to an exact SeatingManager position")
lastFurniturePath:completePath()
check(actor.sitting == true and actor.seatObject == seat and seat.occupied == true
        and actor.lastEvent == "EventSitOnFurniture"
        and SC.NativeActions.furnitureStatus(actor) == "entering",
    "the sit-down animation is not treated as a settled protected pose")
local poseWaitAt = SC_TEST_CLOCK
SC_TEST_CLOCK = poseWaitAt + 1000
actor.px = actor:getX() + 0.1
check(SC.NativeActions.furnitureStatus(actor) == "entering",
    "root movement resets the furniture pose's stillness timer")
SC_TEST_CLOCK = poseWaitAt + 2499
check(SC.NativeActions.furnitureStatus(actor) == "entering",
    "a missing sit-end event does not protect a moving pose early")
SC_TEST_CLOCK = poseWaitAt + 2501
check(SC.NativeActions.furnitureStatus(actor) == "entered",
    "a settled furniture pose recovers when the animation event is missed")
actor.px = nil
actor.furniturePoseStarted = true -- the stock animation emits this at clip end
check(SC.NativeActions.furnitureStatus(actor) == "entered",
    "completed stock furniture animation verifies the seated pose")
local passiveSeatAction = ISTimedActionQueue.getTimedActionQueue(actor).current
if passiveSeatAction then ISBaseTimedAction.perform(passiveSeatAction) end
check(SC.NativeActions.activityStatus(actor) == "none"
        and SC.NativeActions.seatingStatus(actor) == "furniture",
    "a completed sit becomes a passive posture that does not block reading or diary actions")
local leftSeat, leavingReason = SC.NativeActions.leaveSeating(actor)
check(leftSeat == false and leavingReason == "standing_from_furniture"
        and actor.sitting == true and actor.seatObject == seat
        and seat.occupied == true and actor.lastVariable == "forceGetUp",
    "leaving furniture requests native getup while retaining the seat geometry")
actor.sitting = false
actor.actionContextName = "idle" -- one-frame gap between seated and getup states
local handoffGetup, handoffReason = SC.NativeActions.leaveSeating(actor)
check(handoffGetup == false and handoffReason == "standing_from_furniture"
        and actor.seatObject == seat and seat.occupied == true,
    "furniture exit retains chair height during the native getup handoff")
actor.actionContextName = "getup"
local midGetup, midReason = SC.NativeActions.leaveSeating(actor)
check(midGetup == false and midReason == "standing_from_furniture"
        and actor.seatObject == seat and seat.occupied == true
        and SC.NativeActions.seatingStatus(actor) == "furniture",
    "getup keeps furniture placement until the exit clip completes")
actor.actionContextName = "idle"
local finishedGetup = SC.NativeActions.leaveSeating(actor)
check(finishedGetup and actor.seatObject == nil and seat.occupied == false,
    "completed furniture getup releases the seat and occupancy")

-- Every gameplay action waits on the furniture getup, attacks and escapes
-- included, so a stock clip that never starts cannot keep a companion seated.
local function takeSeat(object, action)
    lastFurniturePath = nil
    local ok, reason = SC.Actor.setMovement(actor, "walk", { action = action, object = object })
    check(ok and lastFurniturePath ~= nil,
        "a furniture rest starts for the getup checks: " .. tostring(reason))
    lastFurniturePath:completePath()
    local passive = ISTimedActionQueue.getTimedActionQueue(actor).current
    if passive then ISBaseTimedAction.perform(passive) end
    actor.actionContextName = "sitonfurniture"
end
takeSeat(seat, "sit")
local stuckStart = SC_TEST_CLOCK
local stuckWait, stuckWaitReason = SC.NativeActions.leaveSeating(actor)
SC_TEST_CLOCK = stuckStart + 2000
local stillWaiting, stillWaitingReason = SC.NativeActions.leaveSeating(actor)
check(stuckWait == false and stuckWaitReason == "standing_from_furniture"
        and stillWaiting == false and stillWaitingReason == "standing_from_furniture"
        and actor.sitting == true and seat.occupied == true,
    "a getup that has not started yet is given time before anything is forced")
SC_TEST_CLOCK = stuckStart + 2500
local forcedUp, forcedReason = SC.NativeActions.leaveSeating(actor)
check(forcedUp == true and forcedReason == "forced_stand_from_furniture"
        and actor.sitting == false and actor.seatObject == nil
        and seat.occupied == false
        and SC.NativeActions.seatingStatus(actor) == "furniture",
    "a getup that never starts is replaced by a direct stand: "
        .. tostring(forcedUp) .. " " .. tostring(forcedReason))
-- The engine leaves the seated state on its next update; the fixture has no
-- state machine, so complete that transition here.
actor.actionContextName = "idle"
check(SC.NativeActions.seatingStatus(actor) == "standing",
    "direct stand becomes navigable after the engine leaves the chair state")
takeSeat(seat, "sit")
local hungStart = SC_TEST_CLOCK
SC.NativeActions.leaveSeating(actor)
actor.sitting = false
actor.actionContextName = "getup"
SC_TEST_CLOCK = hungStart + 5000
local hungWait = SC.NativeActions.leaveSeating(actor)
SC_TEST_CLOCK = hungStart + 6000
local hungUp, hungReason = SC.NativeActions.leaveSeating(actor)
check(hungWait == false and hungUp == true
        and hungReason == "forced_stand_from_furniture"
        and actor.seatObject == nil and seat.occupied == false,
    "a getup clip that never finishes is bounded as well")
actor.actionContextName = "idle"

-- A cot without a two-tile bed grid rests in the furniture pose, and stands
-- through the same getup as a chair: its seat stays held until that ends.
local cot = { x = 30, y = 30, z = 0, occupied = false }
function cot:setSatChair(value) self.occupied = value == true end
local cotOk, cotReason = SC.Actor.setMovement(actor, "walk", {
    action = "rest_bed", object = cot,
})
check(cotOk and cotReason == "getting_on_bed" and lastFurniturePath ~= nil,
    "a cot uses the stock furniture-rest path: " .. tostring(cotReason))
lastFurniturePath:completePath()
check(actor.sitting == true and actor.seatObject == cot and cot.occupied == true
        and SC.NativeActions.bedStatus(actor) == "entering",
    "a cot's furniture pose waits for the sit-down animation")
actor.furniturePoseStarted = true
check(SC.NativeActions.bedStatus(actor) == "entered",
    "the cot is entered after its furniture animation completes")
actor.actionContextName = "sitonfurniture"
local cotLeave, cotLeaveReason = SC.NativeActions.leaveSeating(actor)
check(cotLeave == false and cotLeaveReason == "standing_from_furniture"
        and actor.seatObject == cot and cot.occupied == true
        and actor.lastVariable == "forceGetUp",
    "leaving a cot keeps its seat and furniture object while the getup starts: seat="
        .. tostring(actor.seatObject == cot) .. " occupied=" .. tostring(cot.occupied))
actor.sitting = false
actor.actionContextName = "getup"
local cotMid = SC.NativeActions.leaveSeating(actor)
check(cotMid == false and actor.seatObject == cot and cot.occupied == true,
    "the cot keeps its seat through the getup clip")
actor.actionContextName = "idle"
local cotDone = SC.NativeActions.leaveSeating(actor)
check(cotDone == true and actor.seatObject == nil and cot.occupied == false,
    "the cot is released once the companion is standing")

local fallbackOk = SC.Actor.setMovement(actor, "walk", { action = "sit", object = seat })
check(fallbackOk and lastFurniturePath ~= nil,
    "a second furniture attempt starts before testing the blocked-seat fallback")
lastFurniturePath:failPath()
check(actor.groundSitting == true and actor.lastEvent == "EventSitOnGround"
        and SC.NativeActions.furnitureStatus(actor) == "entered",
    "a blocked furniture path uses the vanilla floor-sit fallback instead of timing out")
local fallbackLeft, fallbackLeaveReason = SC.NativeActions.leaveSeating(actor)
check(fallbackLeft == false and fallbackLeaveReason == "standing_from_ground"
        and actor.groundSitting == false,
    "leaving a furniture floor fallback requests and verifies the asynchronous ground stand")

local bedGrid = {}
function bedGrid:getSpriteGridPosY() return 1 end
function bedGrid:getSpriteGridPosX() return 1 end
local bedSprite = {}
function bedSprite:getSpriteGrid() return bedGrid end
local bed = { x = 20, y = 20, z = 0, occupied = false }
function bed:getX() return self.x end
function bed:getY() return self.y end
function bed:getZ() return self.z end
function bed:getSprite() return bedSprite end
function bed:setSatChair(value) self.occupied = value == true end
local bedOk, bedReason = SC.Actor.setMovement(actor, "walk", {
    action = "rest_bed", object = bed,
})
check(bedOk and bedReason == "getting_on_bed"
        and lastFurniturePath ~= nil
        and lastFurniturePath.anySpriteGridObject == true
        and actor.onBed ~= true and actor.sitting ~= true,
    "two-tile bed rest uses the player's native Rest furniture path")
check(actor.lastVariable == "OnBedAnim" and actor.lastVariableValue == "Awake",
    "bed entry selects the stock awake pose before its get-on-bed animation")
lastFurniturePath:completePath()
check(actor.onBed == true and actor.sitting ~= true
        and actor.seatObject == bed and bed.occupied == false
        and actor.lastEvent == "EventGetOnBed"
        and SC.NativeActions.bedStatus(actor) == "entering",
    "sprite-grid bed rest enters the native bed pose")
actor.bedPoseStarted = true
check(SC.NativeActions.bedStatus(actor) == "entered",
    "the stock bed end event settles the bed rest pose")
actor.actionContextName = "onbed"
local bedLeave, bedLeaveReason = SC.NativeActions.leaveSeating(actor)
check(bedLeave == false and bedLeaveReason == "standing_from_bed" and actor.onBed == true
        and actor.seatObject == bed and actor.lastVariable == "forceGetUp",
    "leaving the bed retains the native pose and object for its get-up and ejection: "
        .. tostring(bedLeaveReason))
actor.actionContextName = "getup"
check(SC.NativeActions.leaveSeating(actor) == false and actor.onBed == true
        and actor.seatObject == bed and SC.NativeActions.seatingStatus(actor) == "bed",
    "movement stays gated throughout the native bed get-up clip")
-- Model the stock PlayerGetUpState.exit, including its physical ejection.
actor.onBed, actor.seatObject = false, nil
actor.actionContextName = "idle"
check(SC.NativeActions.leaveSeating(actor) == true
        and actor.seatObject == nil and bed.occupied == false,
    "bed exit permits movement only after the native get-up finishes")

do
    local priorGeometry, priorPath = SC.BedGeometry, ISPathFindAction.pathToLocationF
    local priorBridge = SCBridge
    SCBridge = SCBridge or {}
    local priorShift, priorLift = SCBridge.shiftOnBedPoseTowardPillow, SCBridge.setOnBedRenderLift
    local priorX, priorY = actor.px, actor.py
    local entry = { x=20.2, y=22.5, z=0, pillow={x=20,y=20,z=0} }
    SC.BedGeometry = { entry=function(object, candidate)
        check(object==bed and candidate==actor, "bed geometry resolves the selected actor and mattress")
        return bed, entry
    end }
    ISPathFindAction.pathToLocationF = function(_, candidate, x, y, z)
        check(candidate==actor and x==entry.x and y==entry.y and z==entry.z,
            "aligned bed entry uses the resolved fractional approach")
        lastFurniturePath = testPathAction(candidate, nil)
        return lastFurniturePath
    end
    local shifts, lifts = 0, 0
    SCBridge.shiftOnBedPoseTowardPillow = function(candidate, x, y, z)
        check(candidate==actor and x==20 and y==20 and z==0,
            "bed alignment retains the same mattress pillow")
        shifts=shifts+1 actor.px,actor.py=20.5,20.5 return true
    end
    SCBridge.setOnBedRenderLift = function(candidate, amount)
        check(candidate==actor and amount==180, "bed alignment selects only the verified model lift")
        lifts=lifts+1 return true
    end
    check(SC.Actor.setMovement(actor,"walk",{action="rest_bed",object=bed})==true,
        "a shared mattress entry starts the native action")
    local pendingBed = ISTimedActionQueue.getTimedActionQueue(actor).queue[2]
    check(pendingBed:waitToStart()==true, "bed entry cannot start from a different floor position")
    actor.px,actor.py=entry.x,entry.y
    check(pendingBed:waitToStart()==false, "the exact entry permits the stock bed turn and animation")
    actor.moving=true
    lastFurniturePath:completePath()
    check(actor.moving==false, "bed entry clears the previous path's movement input")
    actor.px,actor.py,actor.bedPoseStarted=20.2,21.3,true
    check(SC.NativeActions.bedStatus(actor)=="entered"
            and SC.NativeActions.bedStatus(actor)=="entered" and shifts==1 and lifts==1,
        "settled bed alignment and model lift commit once before sleep")
    actor.actionContextName="onbed"
    SC.NativeActions.leaveSeating(actor)
    actor.actionContextName="getup"
    SC.NativeActions.leaveSeating(actor)
    actor.onBed,actor.seatObject,actor.actionContextName=false,nil,"idle"
    check(SC.NativeActions.leaveSeating(actor)==true,
        "an aligned mattress pose retains the native get-up exit")
    SC.BedGeometry.entry = function() return nil,nil,"bed_entry_blocked" end
    local blocked,why=SC.Actor.setMovement(actor,"walk",{action="rest_bed",object=bed})
    check(blocked==false and why=="bed_entry_blocked",
        "blocked mattress geometry does not queue an unrelated furniture pose")
    actor.px,actor.py=priorX,priorY
    SC.BedGeometry,ISPathFindAction.pathToLocationF=priorGeometry,priorPath
    SCBridge.shiftOnBedPoseTowardPillow,SCBridge.setOnBedRenderLift=priorShift,priorLift
    SCBridge = priorBridge
end

-- A blocked bed path uses the stock Rest fallback and releases its native
-- queue action before the companion starts another activity.
local failedBedStarted = SC.Actor.setMovement(actor, "walk", {
    action = "rest_bed", object = bed,
})
local failedBedPath = ISTimedActionQueue.getTimedActionQueue(actor).current
if failedBedPath then failedBedPath:failPath() end
check(failedBedStarted and actor.groundSitting == true
        and SC.NativeActions.bedStatus(actor) == "entered",
    "blocked bed Rest path falls back to a grounded pose")
local floorLeave, floorLeaveReason = SC.NativeActions.leaveSeating(actor)
check(floorLeave == false and floorLeaveReason == "standing_from_ground"
        and actor.groundSitting == false,
    "failed bed path releases the floor rest pose without stranding native work")
actor.turning = false
local movedAfterBedFailure = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 1, dy = 0,
})
if not movedAfterBedFailure and actor.turning == true then
    actor.turning = false
    movedAfterBedFailure = SC.Actor.setMovement(actor, "walk", {
        action = "move", dx = 1, dy = 0,
    })
end
check(movedAfterBedFailure == true,
    "ordinary movement resumes after a blocked bed rest path")

-- A restarted save may already have lost every bed flag while its physical
-- coordinates remain inside the solid mattress. Repair only that footprint,
-- using a clear cardinal exit with the same wall guard as native get-up.
do
    local oldUtility, oldRecover = SC.GameplayUtil, SC.Actor.recover
    local room, otherRoom, cargo = {}, {}, {}
    local origin = { x=10,y=10,z=1,solid=true }
    local west = { x=9,y=10,z=1,clear=true,room=room }
    local east = { x=11,y=10,z=1,clear=true,room=otherRoom }
    local north = { x=10,y=9,z=1,clear=false,room=room }
    local south = { x=10,y=11,z=1,clear=false,room=room }
    local piece = { present=true }
    function piece:getSquare() return self.present and origin or nil end
    function piece:getSprite() return {
        getSpriteGrid=function() return {} end,
        getName=function() return "furniture_bedding_01_1" end,
        getProperties=function() return {get=function() return "Hospital Bed" end} end,
    } end
    function piece:setSatChair() end
    function origin:isSolid() return self.solid end
    function origin:isSolidTrans() return false end
    function origin:getRoom() return room end
    function origin:getObjects() return {
        size=function() return piece.present and 1 or 0 end,
        get=function() return piece end,
    } end
    function origin:testCollideAdjacent(_,dx) return dx == -1 end
    for _,square in ipairs({west,east,north,south}) do
        function square:getRoom() return self.room end
    end
    local trapped={square=origin,collidable=false,inventory=cargo,context="idle"}
    function trapped:getCurrentSquare() return self.square end
    function trapped:getX() return self.px or self.square.x+0.5 end
    function trapped:getY() return self.py or self.square.y+0.5 end
    function trapped:getZ() return self.square.z end
    function trapped:isOnBed() return false end
    function trapped:isDead() return false end
    function trapped:isSittingOnFurniture() return false end
    function trapped:isSitOnGround() return false end
    function trapped:getCurrentActionContextStateName() return self.context end
    function trapped:getCompanionMovementOwner() return self.owner or "none" end
    function trapped:setSitOnFurnitureObject() end
    function trapped:setCollidable(value) self.collidable=value end
    function trapped:isCollidable() return self.collidable end
    local points={ ["10:10"]=origin,["9:10"]=west,["11:10"]=east,["10:9"]=north,["10:11"]=south }
    SC.GameplayUtil={
        position=function(v) return v.x,v.y,v.z end,
        gridSquare=function(x,y,z) return z==1 and points[x..":"..y] or nil end,
        isClearActorSpawnSquare=function(v) return v.clear==true end,
        distance=function(_,v) return math.abs(v.x-10)+math.abs(v.y-10) end,
        sameSquare=function(a,v) return a.square==v end,
    }
    local recovered=0
    SC.Actor.recover=function(a,target) recovered=recovered+1 a.square=target return true end
    check(SC.NativeActions.seatingStatus(trapped)=="bed",
        "a restarted standing actor overlapping a bed is detected before navigation")
    local blocked, blockedReason=SC.NativeActions.leaveSeating(trapped)
    check(not blocked and blockedReason=="standing_from_bed_exit_blocked" and recovered==0
            and trapped.collidable and trapped.inventory==cargo,
        "bed recovery refuses walls, a different room, blocked floor and occupied floor")
    SC_TEST_CLOCK=SC_TEST_CLOCK+1001
    east.room=room
    check(SC.NativeActions.leaveSeating(trapped)==true and trapped.square==east and recovered==1
            and trapped.inventory==cargo and SC.NativeActions.seatingStatus(trapped)=="standing",
        "the same actor and cargo recover to one clear adjacent tile on the original floor")
    trapped.square=origin trapped.px=east.x+0.5 trapped.py=east.y+0.5
    check(SC.NativeActions.seatingStatus(trapped)=="standing"
            and SC.NativeActions.leaveSeating(trapped)==true and recovered==1,
        "a stale current-square pointer cannot move an actor already clear of the bed")
    trapped.px,trapped.py=nil,nil
    trapped.square=origin trapped.collidable=false
    SC_TEST_CLOCK=SC_TEST_CLOCK+1001
    for _,owner in ipairs({"grapple","traversal","attack","corpse_drag"}) do
        trapped.owner=owner
        check(SC.NativeActions.leaveSeating(trapped)==false and recovered==1 and not trapped.collidable,
            "bed cleanup cannot relocate an actor owned by native "..owner)
    end
    trapped.owner=nil piece.present=false origin.solid=false
    SC_TEST_CLOCK=SC_TEST_CLOCK+1001
    check(SC.NativeActions.leaveSeating(trapped)==true and recovered==1,
        "removing the bed releases the pending exit without inventing a displacement")
    SC.NativeActions.releaseActor(trapped)
    SC.GameplayUtil,SC.Actor.recover=oldUtility,oldRecover
end

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
actor.climbing = false
actor.sitting = true
actor.seatObject = seat

local sweepWait, sweepWaitReason = SC.Actor.setMovement(actor, "walk", { action = "room_sweep" })
check(sweepWait == false and sweepWaitReason == "standing_from_furniture"
        and actor.sitting == true and actor.seatObject == seat,
    "room sweep waits for furniture getup before moving")
actor.sitting = false
actor.actionContextName = "getup"
local sweepGetup = SC.Actor.setMovement(actor, "walk", { action = "room_sweep" })
check(sweepGetup == false and actor.seatObject == seat,
    "room sweep waits through the furniture getup animation")
actor.actionContextName = "idle"
local sweepOk, sweepReason = SC.Actor.setMovement(actor, "walk", { action = "room_sweep" })
check(sweepOk and sweepReason == "room_sweep_facing_started" and actor.forwardY > 0.9
    and actor.seatObject == nil,
    "room sweep resumes after the native furniture getup")
ISPathFindAction, ISRestAction, ISGetOnBedAction, SeatingManager =
    oldPathFindAction, oldRestAction, oldGetOnBedAction, oldSeatingManager
end
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
actor.forwardX, actor.forwardY = 1, 0
local rearGuardOk, rearGuardReason = SC.Actor.setMovement(actor, "walk", {
    action = "rear_guard_watch", targetPosition = { x = actorX - 2, y = actorY, z = 0 },
    stableFacing = true, awarenessMovement = true, cqbRole = "rear_guard",
})
check(rearGuardOk and rearGuardReason == "rear_guard_watch_started" and actor.forwardX < -0.9,
    "rear guard watch reaches verified native human facing instead of an unsupported intent")
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
do
actor.forwardX, actor.forwardY, actor.lastEmote = 1, 0, nil
actor.moving = true
pathBehavior.startedMoving, pathBehavior.cancelled = true, false
local warningTarget = { x = actor:getX(), y = actor:getY() + 4, z = 0 }
local warningSignalOk, warningSignalReason = SC.Actor.setMovement(actor, "walk", {
    action = "hand_signal", emote = "freeze", target = warningTarget,
    facingTarget = warningTarget, faceTargetBeforeEmote = true, stableFacing = true,
})
check(warningSignalOk and warningSignalReason == "hand_signal_started"
    and actor.forwardY > 0.9 and actor.lastEmote == "freeze"
    and actor:isMoving() == false and pathBehavior.cancelled == true,
    "visible-danger hand signal stops its active route and faces the exact target before its emote")
actor.lastEmote = nil
actor.moving = true
pathBehavior.cancelled = false
local targetlessSignalOk, targetlessSignalReason = SC.Actor.setMovement(actor, "walk", {
    action = "hand_signal", emote = "freeze", faceTargetBeforeEmote = true,
})
check(not targetlessSignalOk and targetlessSignalReason == "hand signal facing target is unavailable"
    and actor.lastEmote == nil and actor:isMoving() == true and pathBehavior.cancelled == false,
    "a directional danger emote fails closed instead of inventing a facing target")
end
actor.lastEmote = nil
local saluteOk = SC.Actor.setMovement(actor, "walk", {
    action = "hand_signal", emote = "salute",
})
check(saluteOk and actor.lastEmote == "salutecasual"
        and actor:isMoving() == true and pathBehavior.cancelled == false,
    "ordinary targetless emotes remain non-directional and do not cancel navigation")
do
    local originalPlay, originalSet = actor.playEmote, actor.setVariable
    local originalGetString, originalGetBoolean = actor.getVariableString,
        actor.getVariableBoolean
    local originalClear = actor.clearVariable
    actor.variables = {}
    function actor:playEmote(emote)
        self.variables.emote, self.variables.EmotePlaying = emote, true
        return true
    end
    function actor:setVariable(name, value) self.variables[name] = value end
    function actor:getVariableString(name) return self.variables[name] end
    function actor:getVariableBoolean(name) return self.variables[name] == true end
    function actor:clearVariable(name) self.variables[name] = nil end
    local clapOk = SC.Actor.setMovement(actor, "walk", {
        action = "hand_signal", emote = "clap",
    })
    local visual = SC.NativeVisualActions
    local _, observed = visual.releaseLoopedEmote(actor, 0)
    local _, active = visual.releaseLoopedEmote(actor, 1000)
    local released, reason = visual.releaseLoopedEmote(actor, 1900)
    check(clapOk and observed == "looped_emote_observed"
            and active == "looped_emote_active"
            and released and reason == "looped_emote_released"
            and actor.variables.EmotePlaying == false and actor.variables.emote == nil,
        "looped clap finishes after a bounded pose instead of playing forever")
    actor.variables.emote, actor.variables.EmotePlaying = "clap", true
    local _, restored = visual.releaseLoopedEmote(actor, 4000)
    local recovered, recoveryReason = visual.releaseLoopedEmote(actor, 5900)
    check(restored == "looped_emote_observed" and recovered
            and recoveryReason == "looped_emote_released",
        "a companion already clapping when loaded is released on the decision lane")
    local surrenderOk = SC.Actor.setMovement(actor, "walk", {
        action = "hand_signal", emote = "surrender",
    })
    local _, surrenderObserved = visual.releaseLoopedEmote(actor, 6000)
    local surrenderHeld, surrenderReason = visual.releaseLoopedEmote(actor, 8000)
    local surrenderReleased, surrenderEnd = visual.releaseLoopedEmote(actor, 8501)
    check(surrenderOk and surrenderObserved == "looped_emote_observed"
            and not surrenderHeld and surrenderReason == "looped_emote_active"
            and surrenderReleased and surrenderEnd == "looped_emote_released"
            and actor.variables.EmotePlaying == false and actor.variables.emote == nil,
        "the other vanilla looping emote, surrender, also ends after a bounded pose")
    actor.variables.emote, actor.variables.EmotePlaying = "clap", true
    visual.releaseLoopedEmote(actor, 9000)
    actor.variables.emote = "thumbsup"
    local replaced, replacementReason = visual.releaseLoopedEmote(actor, 12000)
    check(not replaced and replacementReason == "no_looped_emote"
            and actor.variables.EmotePlaying == true
            and actor.variables.emote == "thumbsup",
        "clap recovery leaves a newer emote alone")
    actor.playEmote, actor.setVariable = originalPlay, originalSet
    actor.getVariableString, actor.getVariableBoolean = originalGetString,
        originalGetBoolean
    actor.clearVariable, actor.variables = originalClear, nil
end
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
-- Kahlua's fixture does not tick the animation graph; complete any facing
-- animation started by the preceding native action before testing locomotion.
actor.turning = false
local resumedAfterClaim, resumedAfterClaimReason = SC.Actor.setMovement(actor, "walk", {
    action = "move", dx = 1, dy = 0,
})
if resumedAfterClaimReason == "turning_for_movement" then
    actor.turning = false
    resumedAfterClaim = SC.Actor.setMovement(actor, "walk", {
        action = "move", dx = 1, dy = 0,
    })
end
check(resumedAfterClaim and actor:getX() > visualStartX,
    "ordinary movement resumes after an unclaimed visual effect expires")
do
    local foreignAction = { source = "ISUnequipAction" }
    actor.characterActions:add(foreignAction)
    local foreignActionX = actor:getX()
    foreignAction.wasMoving = actor:isMoving()
    local movedDuringForeignAction, foreignActionReason = SC.Actor.setMovement(actor, "walk", {
        action = "move", dx = 1, dy = 0,
    })
    check(not movedDuringForeignAction
            and string.find(tostring(foreignActionReason), "unfinished_action", 1, true) ~= nil
            and actor:getX() == foreignActionX
            and actor:isMoving() == foreignAction.wasMoving,
        "untracked vanilla timed actions reject translation without mutating their locomotion owner: "
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
-- Exercise the real native timed action with the same container posture rules
-- used by vanilla ISInventoryTransferAction, including corpses and floor loot.
for _, fixture in ipairs({
    { name = "shelf", position = "High", expected = "High" },
    { name = "cabinet", position = "Mid", expected = "Mid" },
    { name = "box", position = "Low", expected = "Low" },
    { name = "corpse", position = "High", corpse = true, expected = "Low" },
    { name = "freezer", position = "Mid", freezer = "Low", expected = "Low" },
    { name = "floor", position = "High", expected = "Low" },
    { name = "world item", position = "High", worldItem = true, expected = "Low" },
}) do
    local container = {
        getType = function() return fixture.name end,
        getContainerPosition = function() return fixture.position end,
        getFreezerPosition = function() return fixture.freezer end,
        getParent = function() return fixture.corpse and { __class = "IsoDeadBody" } or nil end,
        getContainingItem = function()
            return fixture.worldItem and { getWorldItem = function() return {} end } or nil
        end,
    }
    local started = SC.Actor.setMovement(actor, "walk", {
        action = "loot_container", container = container,
    })
    check(started and actor.lastAnimation == "Loot"
            and actor.lastAnimVariable.key == "LootPosition"
            and actor.lastAnimVariable.value == fixture.expected
            and SC.NativeActions.visualStatus(actor, "loot_container") == "active",
        "native " .. fixture.name .. " looting starts a tracked Loot pose at the correct height")
    SC.NativeActions.cancelVisual(actor, "test_container_pose")
    ISTimedActionQueue.queues[actor] = nil
end
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
        and ISTimedActionQueue.getTimedActionQueue(actor).current.maxTime == 3600
        and actor.lastAnimVariable.key == "ReadType" and actor.lastAnimVariable.value == "book",
    "reading uses the exact CharacterActionAnims enum and vanilla ReadType state")
check(SC.NativeActions.cancelVisual(actor, "test_long_read"),
    "the initial reading visual cancels before testing a full-length session")
ISTimedActionQueue.queues[actor] = nil
readOk = SC.Actor.setMovement(actor, "walk", {
    action = "read", item = book, durationMs = 180000,
})
check(readOk and ISTimedActionQueue.getTimedActionQueue(actor).current.maxTime == 10800,
    "a three-minute reading session reaches the native action without being shortened")
do
    local originalStop = SC.NativeActions.stopDirect
    local foreignStops = 0
    SC.NativeActions.stopDirect = function(...)
        foreignStops = foreignStops + 1
        return originalStop(...)
    end
    local accepted, reason = SC.NativeActions.dispatch(actor, "walk", {
        action = "follow_formation", targetSquare = square,
    }, directProvider)
    SC.NativeActions.stopDirect = originalStop
    check(not accepted and reason == "visual_action_active:read"
            and foreignStops == 0,
        "a rejected competing decision cannot cancel another activity owner's path")
end
check(SC.NativeActions.cancelVisual(actor, "test_visual_complete"),
    "reading visual fixture cancels cleanly")
do
    -- A visual timed action that is INTERRUPTED (dropped from the queue without a
    -- completed/stopped flag) must not linger as a phantom native owner. Before,
    -- activityStatus kept returning "interrupted", which made the urgent-decision
    -- path re-queue forever ("Urgent already queued") and blocked urgent dispatch,
    -- freezing companions in the kneel/rip pose they never left. activityStatus now
    -- self-heals the dead visual and reports the true state, resetting the pose.
    ISTimedActionQueue.queues[actor] = nil
    actor.modelResetCount = 0
    local startedInterrupt = SC.Actor.setMovement(actor, "walk", {
        action = "read", item = { getReadType = function() return "book" end },
    })
    check(startedInterrupt and SC.NativeActions.visualStatus(actor) == "active",
        "interrupted-visual fixture starts an active reading animation")
    local interruptQueue = ISTimedActionQueue.getTimedActionQueue(actor)
    if interruptQueue.current and interruptQueue.current.forceStop then
        interruptQueue.current:forceStop()
    end
    interruptQueue.queue = {}
    interruptQueue.current = nil
    check(SC.NativeActions.visualStatus(actor) == "interrupted",
        "a visual dropped from the queue with no completion flag reads as interrupted")
    local healedPhase = SC.NativeActions.activityStatus(actor)
    check(healedPhase == "none"
            and SC.NativeActions.visualStatus(actor) == "none"
            and actor.modelResetCount >= 1,
        "activityStatus self-heals a dead interrupted visual and resets the kneel/read pose")
end
ISTimedActionQueue.queues[actor] = nil
do
    -- Body language: an Ext gesture sets the stock "Ext" variable and fires
    -- EventDoExt; a workout enters the stock fitness state through its own
    -- variables and leaves it again when cancelled.
    local variables, events = {}, {}
    local savedSetVariable, savedReportEvent = actor.setVariable, actor.reportEvent
    function actor:setVariable(name, value)
        variables[name] = value
        return savedSetVariable(self, name, value)
    end
    function actor:reportEvent(event)
        events[#events + 1] = event
        return savedReportEvent(self, event)
    end
    function actor:clearVariable(name) variables[name] = nil end
    function actor:SetVariable(name, value) variables[name] = value end
    local function indexOf(list, value)
        for index, candidate in ipairs(list) do
            if candidate == value then return index end
        end
        return nil
    end
    local yawnOk, yawnReason = SC.Actor.setMovement(actor, "walk", {
        action = "ext_gesture", ext = "Yawn",
    })
    local yawnEvent = events[#events]
    local badOk, badReason = SC.Actor.setMovement(actor, "walk", {
        action = "ext_gesture", ext = "Moonwalk",
    })
    check(yawnOk and yawnReason == "ext_gesture_started" and variables.Ext == "Yawn"
            and yawnEvent == "EventDoExt" and not badOk
            and string.find(tostring(badReason), "unsupported ext gesture", 1, true) ~= nil,
        "an Ext gesture plays the stock yawn and refuses anything outside the list: "
            .. tostring(yawnReason) .. "/" .. tostring(badReason))
    events = {}
    ISTimedActionQueue.queues[actor] = nil
    local workoutOk, workoutReason = SC.Actor.setMovement(actor, "walk", {
        action = "workout", exercise = "situp", struggle = true, durationMs = 30000,
    })
    local timed = ISTimedActionQueue.getTimedActionQueue(actor).current
    local fitnessAt, updateAt = indexOf(events, "EventFitness"), indexOf(events, "EventUpdateFitness")
    check(workoutOk and string.find(tostring(workoutReason), "visual_timed_action_started", 1, true) ~= nil
            and variables.ExerciseType == "situp" and variables.FitnessStruggle == true
            and fitnessAt ~= nil and updateAt ~= nil and fitnessAt < updateAt
            and timed ~= nil and timed.maxTime == 1800
            and SC.NativeActions.visualStatus(actor) == "active",
        "a workout enters the stock fitness state for its full length, past the usual visual cap: "
            .. tostring(workoutReason))
    check(SC.NativeActions.cancelVisual(actor, "test_workout_cancel")
            and variables.ExerciseEnded == true and variables.ExerciseStarted == false
            and variables.FitnessFinished == "true",
        "cancelling a workout ends the exercise, so no pose is left behind")
    actor.setVariable, actor.reportEvent = savedSetVariable, savedReportEvent
    actor.clearVariable, actor.SetVariable = nil, nil
    ISTimedActionQueue.queues[actor] = nil
end
do
    -- Stand-in actions carry the sounds of the vanilla action they mirror:
    -- washing at a sink runs WashYourself until done or cancelled, reading
    -- opens, turns and closes the book, and a sneeze gets its voice.
    local played, stopped, voiced = {}, {}, {}
    local lastHandle = 100
    function actor:playSound(name)
        lastHandle = lastHandle + 1
        played[#played + 1] = name
        return lastHandle
    end
    function actor:stopOrTriggerSound(handle) stopped[#stopped + 1] = handle end
    function actor:playerVoiceSound(name) voiced[#voiced + 1] = name return 1 end
    ISTimedActionQueue.queues[actor] = nil
    local washOk = SC.Actor.setMovement(actor, "walk", { action = "wash_self", durationMs = 3000 })
    local washSound, washHandle = played[#played], lastHandle
    local washCancelled = SC.NativeActions.cancelVisual(actor, "test_wash_cancel")
    check(washOk and washSound == "WashYourself" and washCancelled
            and stopped[#stopped] == washHandle,
        "washing at a sink plays the stock washing sound and a cancel stops it: "
            .. tostring(washSound))
    ISTimedActionQueue.queues[actor] = nil
    played = {}
    local book = { getReadType = function() return "book" end,
        getType = function() return "BookCarpentry1" end }
    local readOk = SC.Actor.setMovement(actor, "walk", { action = "read", item = book })
    local reading = ISTimedActionQueue.getTimedActionQueue(actor).current
    if reading then
        reading:animEvent("PageFlip")
        reading:perform()
    end
    check(readOk and played[1] == "OpenBook" and played[2] == "PageFlipBook"
            and played[3] == "CloseBook",
        "reading opens the book, turns its pages and closes it: " .. table.concat(played, ","))
    SC.NativeActions.clearVisual(actor)
    ISTimedActionQueue.queues[actor] = nil
    local sneezed = SC.Actor.setMovement(actor, "walk", { action = "ext_gesture", ext = "Sneeze1" })
    check(sneezed and voiced[#voiced] == "SneezeLight",
        "a companion's sneeze uses the stock sneeze voice: " .. tostring(voiced[#voiced]))
    actor.playSound, actor.stopOrTriggerSound, actor.playerVoiceSound = nil, nil, nil
    ISTimedActionQueue.queues[actor] = nil
end
do
    -- A companion dressing its own wound faces nobody; facing itself is a
    -- zero vector that turned it on the spot every tick.
    ISTimedActionQueue.queues[actor] = nil
    local selfOk = SC.Actor.setMovement(actor, "walk", { action = "kneel_treat", patient = actor })
    local selfAction = ISTimedActionQueue.getTimedActionQueue(actor).current
    local selfFacing = selfAction and selfAction.faceTarget
    local selfAnimation, selfEvent = actor.lastAnimation, actor.lastEvent
    SC.NativeActions.cancelVisual(actor, "test_self_treatment")
    ISTimedActionQueue.queues[actor] = nil
    local other = { x = 1, y = 1, z = 0 }
    local otherOk = SC.Actor.setMovement(actor, "walk", { action = "kneel_treat", patient = other })
    local otherAction = ISTimedActionQueue.getTimedActionQueue(actor).current
    local otherFacing = otherAction and otherAction.faceTarget
    local otherAnimation, otherEvent = actor.lastAnimation, actor.lastEvent
    local otherPosition = actor.lastAnimVariable
    SC.NativeActions.cancelVisual(actor, "test_rescue_treatment")
    ISTimedActionQueue.queues[actor] = nil
    check(selfOk and selfAction ~= nil and selfFacing == nil and otherOk and otherFacing == other,
        "a companion dressing its own wound faces nobody, and tending another faces the patient")
    check(selfAnimation == CharacterActionAnims.Bandage and selfEvent == "EventBandage"
            and otherAnimation == "Loot" and otherEvent == "EventLootItem"
            and otherPosition.key == "LootPosition" and otherPosition.value == "Mid",
        "companion rescue uses vanilla's other-patient reach, not a self-bandage pose")
    local splintOk = SC.Actor.setMovement(actor, "walk", {
        action = "apply_splint", patient = other,
    })
    local splintAction = ISTimedActionQueue.getTimedActionQueue(actor).current
    check(splintOk and splintAction and splintAction.faceTarget == other
            and actor.lastAnimation == "Loot" and actor.lastEvent == "EventLootItem",
        "applying a splint also faces the patient with the vanilla reach pose")
    SC.NativeActions.cancelVisual(actor, "test_remote_splint")
    ISTimedActionQueue.queues[actor] = nil
end
do
    -- Player-initiated bandaging must use the game's other-patient reach.
    -- An unqualified self-Bandage action selects its hands-up fallback pose.
    local player = { variables = {} }
    function player:SetVariable(name, value) self.variables[name] = value end
    function player:reportEvent(event) self.lastEvent = event end
    function player:playSound(sound) self.lastSound = sound return 1 end
    local action = SCApplyCompanionBandage:new(player, actor, 220)
    action:start()
    check(player.lastAnimation == "Loot"
            and player.variables.LootPosition == "Mid"
            and player.lastEvent == "EventLootItem"
            and player.lastSound == "FirstAidApplyBandage",
        "player bandaging a companion uses the other-patient reach, not the surrender fallback")
end
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
do
local priorPlayerData = { untouched = true }
local transactionalPlayer = {}
function transactionalPlayer:getModData() return priorPlayerData end
local priorStore = SC_TEST_SET_WORLD_STORE({
    document = { schema = SC.Identity.saveSchema, companions = { sentinel = true } },
})
local priorDocument = priorStore.document
actor.bodyUnavailable = true
local failedSave = SC.Persistence.save(transactionalPlayer)
check(failedSave == false and priorStore.document == priorDocument,
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
local invalidData = SC_TEST_SET_WORLD_STORE({ document = invalidDocument })
local invalidPlayer = {}
function invalidPlayer:getModData() return invalidData end
local invalidRestored = SC.Persistence.restore(invalidPlayer)
local invalidSaved = SC.Persistence.save(invalidPlayer)
check(not invalidRestored and not invalidSaved and invalidData.document == invalidDocument,
    "unsupported save schema is retained without destructive overwrite")
SC.Persistence.reset()

local playerData = {
    OtherMod = { untouched = true },
}
SC_TEST_SET_WORLD_STORE({ document = {
        schema = SC.Identity.saveSchema,
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
})
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

do
    local restoreCell = { squares = {} }
    local building = {}
    local room = {}
    function room:getBuilding() return building end
    local function restoreSquare(x, y, available, assignedRoom)
        local value = { x = x, y = y, z = 0, available = available,
            room = assignedRoom, cell = restoreCell }
        function value:getX() return self.x end
        function value:getY() return self.y end
        function value:getZ() return self.z end
        function value:getCell() return self.cell end
        function value:getChunk() return {} end
        function value:isSolid() return false end
        function value:isSolidTrans() return false end
        function value:TreatAsSolidFloor() return true end
        function value:isFree() return self.available == true end
        function value:isSafeToSpawn() return self.available == true end
        function value:getRoom() return self.room end
        restoreCell.squares[tostring(x) .. ":" .. tostring(y)] = value
        return value
    end
    function restoreCell:getGridSquare(x, y)
        return self.squares[tostring(x) .. ":" .. tostring(y)]
    end
    local occupied = restoreSquare(100, 100, false, room)
    local outside = restoreSquare(99, 100, true, nil)
    local indoor = restoreSquare(102, 100, true, room)
    local relocated = SC.Persistence._nearbyRestoreSquareForTests(occupied)
    check(relocated == indoor,
        "restore relocates an obstructed saved tile to nearby floor in the same building")
    indoor.available = false
    relocated = SC.Persistence._nearbyRestoreSquareForTests(occupied)
    check(relocated == outside,
        "restore uses the nearest safe same-floor fallback before quarantining a companion")
end

local saved, document = SC.Persistence.save(player)
check(saved and document.companions["sc-pending-record"] ~= nil,
    "provider/square failure cannot erase a pending save record")
check(playerData.OtherMod.untouched == true, "unrelated mod data is preserved")
check(SC.Persistence.reset() == true, "character-death fixture resets runtime state")
local replacementPlayerData = {}
local replacementPlayer = { getModData = function() return replacementPlayerData end }
local replacementRestored = SC.Persistence.restore(replacementPlayer)
check(replacementRestored == true
        and SC.Persistence.isPending("sc-pending-record")
        and replacementPlayerData.SC_SaveV1 == nil,
    "a fresh player character restores companions from unchanged world ModData")
end

local function useWorldData(data)
    if data.document == nil and data.SC_SaveV1 ~= nil then
        data.document, data.SC_SaveV1 = data.SC_SaveV1, nil
    end
    return SC_TEST_SET_WORLD_STORE(data)
end

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
local mixedData = useWorldData({ SC_SaveV1 = {
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
} })
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

-- A companion saved in a native seat comes back on foot by its car. As a
-- stored passenger it was keyed by the car's runtime id, which the game
-- reassigns on every load, and waited for a car exit that never matched.
SC.Persistence.reset()
SC.Vehicle.reset()
local seatData = useWorldData({ SC_SaveV1 = {
    schema = SC.Identity.saveSchema, companions = {
        ["sc-seat-on-foot"] = {
            id = "sc-seat-on-foot", recruited = true,
            identity = { forename = "Seat", surname = "Rider" },
            position = { x = 40, y = 40, z = 0 }, inventory = {},
            skills = {}, vitals = {}, order = {},
            vehicle = { stored = false, seat = 1,
                vehicle = { id = 77, sqlId = 5, script = "Base.CarNormal",
                    x = 40, y = 41, z = 0 } },
        },
        ["sc-virtual-rider"] = {
            id = "sc-virtual-rider", recruited = true,
            identity = { forename = "Virtual", surname = "Rider" },
            position = { x = 40, y = 40, z = 0 }, inventory = {},
            skills = {}, vitals = {}, order = {},
            vehicle = { stored = true, seat = 2,
                vehicle = { id = 77, sqlId = 5, script = "Base.CarNormal",
                    x = 40, y = 41, z = 0 } },
        },
    },
} })
check(SC.Persistence.restore({ getModData = function() return seatData end }),
    "a document with seated companions restores")
check(SC.Persistence.isPending("sc-seat-on-foot")
        and not SC.Vehicle.contains("sc-seat-on-foot"),
    "a companion saved in a native seat is restored on foot, not as a stored passenger")
check(SC.Vehicle.contains("sc-virtual-rider")
        and not SC.Persistence.isPending("sc-virtual-rider"),
    "a stored virtual passenger is still imported into its car")
SC.Persistence.reset()
SC.Vehicle.reset()

do
-- Seat-zero saves restore through the same door lookup as passengers. A car
-- outside the loaded area falls back to the saved position and never resumes
-- native seating or driving.
local priorDoor, priorRestore, priorCell = SC.Vehicle.reloadedCarSquare,
    SC.Persistence.restoreAt, getCell
local carLoaded, seenSquare, seenSeat = true, nil, nil
local doorSquare = vehicleCell:getGridSquare(43, 40, 0)
local savedSquare = vehicleCell:getGridSquare(40, 40, 0)
SC.Vehicle.reloadedCarSquare = function(anchor)
    check(anchor.sqlId == 5 and anchor.seat == 0,
        "driver save lookup retains database identity and seat zero")
    seenSeat = anchor.seat
    return carLoaded and doorSquare or nil, carLoaded and "car_door" or "car_not_loaded"
end
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        if x == 40 and y == 40 and z == 0 then return savedSquare end
        return nil
    end }
end
SC.Persistence.restoreAt = function(saved, destination)
    seenSquare = destination
    check(saved.vehicle.stored == false and saved.vehicle.seat == 0,
        "native driver ownership remains explicit until restored on foot")
    return {}, "restored"
end
for _, loaded in ipairs({ true, false }) do
    SC.Persistence.reset()
    carLoaded, seenSquare, seenSeat = loaded, nil, nil
    local data = useWorldData({ SC_SaveV1 = {
        schema = SC.Identity.saveSchema, companions = {
            ["sc-driver-on-foot"] = {
                id = "sc-driver-on-foot", recruited = true,
                identity = { forename = "Driver", surname = "Test" },
                position = { x = 40, y = 40, z = 0 }, inventory = {},
                skills = {}, vitals = {}, order = {},
                vehicle = { stored = false, seat = 0,
                    vehicle = { id = 77, sqlId = 5, script = "Base.CarNormal",
                        x = 40, y = 41, z = 0 } },
            },
        },
    } })
    check(SC.Persistence.restore({ getModData = function() return data end }),
        "driver save restores through the normal persistence path")
    check(seenSeat == 0 and seenSquare == (loaded and doorSquare or savedSquare)
            and not SC.Persistence.isPending("sc-driver-on-foot")
            and not SC.Vehicle.contains("sc-driver-on-foot"),
        loaded and "saved driver restores on foot at the loaded car door"
            or "unloaded car restores the driver on foot at the saved position")
end
SC.Vehicle.reloadedCarSquare, SC.Persistence.restoreAt, getCell =
    priorDoor, priorRestore, priorCell
SC.Persistence.reset()
end

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
local cyclicData = useWorldData({ document = cyclicDocument })
local cyclicPlayer = { getModData = function() return cyclicData end }
local cyclicRestored, cyclicRestoreReason = SC.Persistence.restore(cyclicPlayer)
check(not cyclicRestored
        and cyclicData.document == cyclicDocument
        and string.find(tostring(cyclicRestoreReason), "cannot be preserved", 1, true),
    "cyclic full-envelope input is rejected before restore and retained exactly")
local cyclicSaved, cyclicReason = SC.Persistence.save(cyclicPlayer)
check(not cyclicSaved and cyclicData.document == cyclicDocument
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
local terminalData = useWorldData({ SC_SaveV1 = { schema = SC.Identity.saveSchema, companions = {
    ["sc-terminal-restore"] = {
        id = "sc-terminal-restore", recruited = true,
        identity = { forename = "Terminal", surname = "Retry" },
        position = { x = 40, y = 40, z = 0 }, inventory = {},
        skills = { { id = "MissingPerk", level = 1 } }, vitals = {}, order = {},
    },
} } })
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
local startingData = useWorldData({ SC_SaveV1 = { schema = SC.Identity.saveSchema, companions = {
    ["sc-provider-starting"] = {
        id = "sc-provider-starting", recruited = true,
        identity = { forename = "Waiting", surname = "Bridge" },
        position = { x = 41, y = 41, z = 0 }, inventory = {},
        skills = {}, vitals = {}, order = {},
    },
} } })
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
local retryData = useWorldData({ SC_SaveV1 = { schema = SC.Identity.saveSchema, companions = {
    ["sc-retry-backoff"] = {
        id = "sc-retry-backoff", recruited = true,
        identity = { forename = "Retry", surname = "Bounded" },
        position = { x = 42, y = 42, z = 0 }, inventory = {},
        skills = {}, vitals = {}, order = {},
    },
} } })
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
function deferredProvider:requestSpawn(square, identity, bare)
    self.requested = true
    self.bare = bare
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
function deferredProvider:reveal(candidate)
    self.reveals = (self.reveals or 0) + 1
    -- Order matters: a companion is shown only once everything that decides
    -- what it looks like has run, which is after registration and the
    -- character-depth restore.
    self.revealedAfterRegister = SC.Registry.byId("sc-deferred-spawn") ~= nil
    return candidate == deferredActor
end
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
check(deferredProvider.reveals == 1 and deferredProvider.revealedAfterRegister == true,
    "a companion hidden for construction is shown exactly once, after it is fully built")
-- A new companion keeps the clothes the survivor factory gave it; there is
-- nothing else to dress it in.
check(deferredProvider.bare == false,
    "a newly created companion is spawned wearing the factory outfit")
check(SC.Actor.remove(deferredActor), "deferred-spawn fixture removes transactionally")

-- A companion that cannot be revealed is still a companion. The bridge
-- un-hides it on its own a few seconds later, so a failure here must not
-- destroy an actor that is otherwise built and registered.
local stubbornProvider = {
    testOnly = true, kind = "iso-companion", polls = 0, reveals = 0,
}
local stubbornActor = setmetatable({
    __class = "IsoPlayer", data = {}, square = square, characterActions = actionList(),
}, { __index = actor })
function stubbornProvider:isActor(candidate)
    return candidate == stubbornActor and candidate.__owned == true
end
function stubbornProvider:requestSpawn(square, identity, bare)
    self.bare = bare
    return 78
end
function stubbornProvider:pollSpawn()
    stubbornActor.__owned = true
    return stubbornActor
end
function stubbornProvider:cancelSpawn() return true end
function stubbornProvider:reveal()
    self.reveals = self.reveals + 1
    return false, "injected reveal failure"
end
function stubbornProvider:remove(candidate)
    candidate.__owned = false
    return true
end
check(SC.Actor._setProviderForTests(stubbornProvider), "reveal-failure provider installed")
local stubbornTicket = SC.Actor.beginSpawn(square, {
    id = "sc-reveal-failure",
    recruited = false,
    identity = { forename = "Shy", surname = "Fellow", gender = "male" },
})
local stubbornReady, stubbornRecord = SC.Actor.pollSpawn(stubbornTicket)
check(stubbornReady == stubbornActor and stubbornRecord and stubbornRecord.id == "sc-reveal-failure"
        and SC.Registry.byId("sc-reveal-failure") ~= nil and stubbornProvider.reveals == 1,
    "a companion that could not be revealed is still spawned and registered")
check(SC.Actor.remove(stubbornActor), "reveal-failure fixture removes transactionally")

-- A restored companion brings its own clothes, so the factory outfit is a
-- costume the player would watch it change out of. Ask for it undressed.
local restoredProvider = { testOnly = true, kind = "iso-companion" }
local restoredActor = setmetatable({
    __class = "IsoPlayer", data = {}, square = square, characterActions = actionList(),
}, { __index = actor })
function restoredProvider:isActor(candidate)
    return candidate == restoredActor and candidate.__owned == true
end
function restoredProvider:requestSpawn(spawnSquare, identity, bare)
    self.bare = bare
    return 79
end
function restoredProvider:pollSpawn()
    restoredActor.__owned = true
    return restoredActor
end
function restoredProvider:cancelSpawn() return true end
function restoredProvider:reveal() return true end
function restoredProvider:remove(candidate)
    candidate.__owned = false
    return true
end
check(SC.Actor._setProviderForTests(restoredProvider), "restored-spawn provider installed")
local restoredTicket = SC.Actor.beginSpawn(square, {
    id = "sc-restored-bare",
    recruited = true,
    restored = true,
    identity = { forename = "Dressed", surname = "Already", gender = "female" },
})
local restoredReady = SC.Actor.pollSpawn(restoredTicket)
check(restoredReady == restoredActor and restoredProvider.bare == true,
    "a restored companion is spawned undressed so its own clothes are the only ones seen")
check(SC.Actor.remove(restoredActor), "restored-spawn fixture removes transactionally")
SC.Actor._setProviderForTests(deferredProvider)
SC.Actor._setProviderForTests(deferredProvider)

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
    local oldStopDirect = SC.NativeActions.stopDirect
    local deniedStopCalls = 0
    SC.NativeActions.stopDirect = function(...)
        deniedStopCalls = deniedStopCalls + 1
        return oldStopDirect(...)
    end
    SC.NativeActions.activityStatus = function()
        return "active", "visual", "loot", SC_TEST_CLOCK
    end
    local rejected, reason = SC.Locomotion.authorize(movementActor, "walk", {
        action = "follow_formation", targetSquare = square,
    })
    SC.NativeActions.activityStatus = oldActivityStatus
    SC.NativeActions.stopDirect = oldStopDirect
    check(not rejected and reason == "locomotion_protected_activity:active:visual:loot"
            and SC.Locomotion.peek(movementActor).phase == "interact"
            and deniedStopCalls == 0,
        "ordinary path rejection is side-effect free and cannot stop a visual owner")

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
    local previousExpedition = SC.ExpeditionPrototype
    SC.ExpeditionPrototype = { current = function()
        return { scout = { vehicle = { state = "held", leg = "home",
            blocker = "road_access_blocked" } } }
    end }
    local supportStatus = SC.Support.snapshot(false)
    check(supportStatus.bridge.ready == true
            and supportStatus.bridge.code == "ready"
            and supportStatus.bridge.provider == "iso-companion"
            and type(supportStatus.actionSupervisor) == "table"
            and type(supportStatus.companionActions) == "table"
            and supportStatus.expedition.vehicleState == "held"
            and supportStatus.expedition.vehicleBlocker == "road_access_blocked",
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
            and string.find(copiedText,
                "Expedition car: held/home, blocker road_access_blocked",
                1, true) ~= nil
            and string.find(copiedText, "C:\\Users\\Tester", 1, true) == nil,
        "bounded support report includes action health and redacts private paths")
    local oldLiving, oldId = SC.Registry.living, SC.Registry.idOf
    local oldResident, oldDecision = SC.BaseLife.resident, SC.Decision
    local oldSeating, oldPeek = SC.NativeActions.seatingStatus, SC.Commands.peek
    local oldSupportDowntime = SC.Downtime
    SC.Downtime = {status=function()
        return {kind="sit",phase="waiting",elapsedMs=3000,durationMs=15000,
            fatigue=0.1,endurance=0.9,followPause="leader_settled",sitCooldownMs=177000}
    end}
    local saved = { SC_Order = "follow", SC_CommandSerial = 17 }
    local guard = { getModData = function() return saved end,
        getDisplayName = function() return "Guard" end,
        getX = function() return 1 end, getY = function() return 2 end,
        getZ = function() return 0 end,
        getCurrentActionContextStateName = function() return "GetUp" end }
    SC.Registry.living = function() return { guard } end
    SC.Registry.idOf = function(value)
        if value == guard then return "sc-support-handoff" end
        return oldId(value)
    end
    SC.BaseLife.resident = function(id)
        if id == "sc-support-handoff" then return { duty = false, role = "guard" } end
        return oldResident(id)
    end
    SC.Decision = { peek = function(value)
        if value == guard then return { current = "follow", intent = "standing_from_furniture" } end
        return oldDecision and oldDecision.peek and oldDecision.peek(value)
    end }
    SC.NativeActions.seatingStatus = function(value)
        if value == guard then return "furniture" end
        return oldSeating(value)
    end
    local commandReads = 0
    SC.Commands.peek = function(value)
        if value == guard then commandReads = commandReads + 1 error("diagnostic initialized controls") end
        return oldPeek(value)
    end
    local handoffReport, handoffSnapshot = SC.Support.summary(false)
    local control = handoffSnapshot.companionActions[1].control
    check(control.order == "follow" and control.commandSerial == 17 and control.duty == false
            and control.decision == "follow" and control.seating == "furniture"
            and control.context == "GetUp" and commandReads == 0
            and saved.SC_Order == "follow" and saved.SC_CommandSerial == 17,
        "support records the accepted order and ownership handoff without initializing controls")
    check(string.find(handoffReport, "order follow, serial 17, base duty false/guard", 1, true)
            and string.find(handoffReport,
                "decision follow/standing_from_furniture, seating furniture, native context GetUp", 1, true),
        "support report distinguishes an accepted Follow from a remaining seated native handoff")
    check(handoffSnapshot.companionActions[1].downtime.kind=="sit"
        and string.find(handoffReport,"sit/waiting, elapsed 3s, planned 15s",1,true)
        and string.find(handoffReport,"fatigue 0.1, endurance 0.9",1,true)
        and string.find(handoffReport,"sit cooldown 177s",1,true) and commandReads==0,
        "support identifies the rest timer, actual needs and repeat cooldown without mutating controls")
    SC.Downtime = oldSupportDowntime
    SC.Registry.living, SC.Registry.idOf = oldLiving, oldId
    SC.BaseLife.resident, SC.Decision = oldResident, oldDecision
    SC.NativeActions.seatingStatus, SC.Commands.peek = oldSeating, oldPeek
    SC.ExpeditionPrototype = previousExpedition
    SC.Diagnostics.disable("support-retry-test", nil, "injected manual latch")
    local retryOk, retryCount = SC.Support.retryFailures()
    check(retryOk and retryCount >= 1
            and not SC.Diagnostics.isDisabled("support-retry-test", nil),
        "support action clears failed subsystem circuits and rechecks the provider")
end
runSupportReportChecks()
runSupportReportChecks = nil

;(function()
-- review 3.4: the native target-coord contract. An explicit targetKind is
-- authoritative; otherwise the caller's inference decides, so a tile centers on
-- +0.5 while an exact world position is never shifted.
local centerTargetOnTile = SC.NativeActions._centerTargetOnTileForTests
check(type(centerTargetOnTile) == "function", "target-centring contract seam is exposed")
check(centerTargetOnTile({ targetKind = "square" }, false) == true,
    "an explicit square target kind forces tile centring regardless of inference")
check(centerTargetOnTile({ targetKind = "world" }, true) == false,
    "an explicit world target kind suppresses tile centring regardless of inference")
check(centerTargetOnTile({}, true) == true and centerTargetOnTile({}, false) == false,
    "with no explicit kind the caller's inference is used unchanged")
check(centerTargetOnTile(nil, true) == true,
    "a missing intent falls back to the caller's inference")
local centreActor = { x = 10.5, y = 20.5, z = 0 }
local tileCorner = { x = 10, y = 20, z = 0 }
local atSquare = SC.GameplayUtil.arrived(centreActor, tileCorner, {
    targetKind = "square", distance = 0.1,
})
local atWorld = SC.GameplayUtil.arrived(centreActor, tileCorner, {
    targetKind = "world", distance = 0.1,
})
check(atSquare == true and atWorld == false,
    "shared arrival centres square targets without shifting exact world coordinates")
end)()

;(function()
    -- Review F02: cancelling a tracked needs action cleared the actor's whole
    -- timed-action queue, which also removes whatever a vanilla or third-party
    -- action had queued behind ours -- and restoring our own borrowed item does
    -- not give them their place back. Cancel exactly what this record owns, as
    -- cancelWork already does.
    local NA = SC.NativeActions
    check(type(NA) == "table" and type(NA.cancelNeeds) == "function",
        "native actions exposes needs cancellation")
    local needsActor = { __class = "IsoPlayer" }
    function needsActor:getModData() self.data = self.data or {} return self.data end
    local ourAction = { character = needsActor, action = "drink" }
    local theirAction = { character = needsActor, action = "someone_elses" }
    local queue = { current = ourAction, list = { ourAction, theirAction } }
    function queue:removeFromQueue(timedAction)
        for index, value in ipairs(self.list) do
            if value == timedAction then table.remove(self.list, index) return end
        end
    end
    local previousQueueApi = ISTimedActionQueue
    local cleared = 0
    ISTimedActionQueue = {
        getTimedActionQueue = function() return queue end,
        clear = function() cleared = cleared + 1 queue.list = {} queue.current = nil end,
    }
    NA.resetNeeds(needsActor)
    check(NA._trackNeedsForTests(needsActor, { timedAction = ourAction, kind = "drink" }),
        "a needs record can be installed for cancellation")
    local ok = NA.cancelNeeds(needsActor, "danger")
    ISTimedActionQueue = previousQueueApi
    check(ok == true, "cancelling a tracked needs action succeeds")
    check(cleared == 0, "cancelling a needs action never clears the whole queue")
    check(#queue.list == 1 and queue.list[1] == theirAction,
        "an unrelated queued action survives a needs cancellation: " .. tostring(#queue.list))
end)()


;(function()
    -- The car key belongs to the committed on-foot restore, never a spawn
    -- initializer that can still fail and dispose its actor.
    local oldCell, oldRestore = getCell, SC.Commands.restore
    local oldBegin, oldIndexRelease = SC.Actor.beginSpawn, SC.InventoryIndex.release
    local cars, serial, selected = actionList(), 0, nil
    local provider = { testOnly = true, kind = "iso-companion" }
    function provider:isActor(value) return value and value.__keyActor and value.__owned == true end
    function provider:spawn() selected.actor.__owned = true return selected.actor end
    function provider:remove(value) value.__owned = false return true end
    function provider:cancelSpawn() return true end
    getCell = function()
        return { getVehicles = function() return cars end, getGridSquare = function() return square end }
    end
    SC.Commands.restore = function(value, record)
        if value.failCommit then return false, "injected post-initialize failure" end
        local ok, why = oldRestore(value, record)
        if ok then value.committed = true end
        return ok, why
    end
    check(SC.Actor._setProviderForTests(provider), "key recovery provider installed")
    local function container()
        local value = { items = actionList(), adds = 0 }
        function value:getItems()
            if self.readFailure then error("injected item-list read failure") end
            return self.items
        end
        function value:Remove(item)
            self.items:remove(item)
            if item.container == self then item.container = nil end
        end
        function value:haveThisKeyId(id)
            for _, item in ipairs(self.items.values) do
                if item.keyId == id then return item end
            end
            return nil
        end
        function value:AddItem(item)
            if item ~= self.trackedKey then error("fixture accepts only its existing ignition key") end
            if item == self.trackedKey then
                self.adds = self.adds + 1
                if self.beforeAdd then self.beforeAdd() end
            end
            if self.reject then error("injected source rejection") end
            if self.mode == "duplicate" then return self.duplicate end
            if item.container then item.container:Remove(item) end
            if self.mode == "detach_throw" then
                if self.afterDetach then self.afterDetach() end
                error("injected detached transfer failure")
            end
            item.container = self
            self.items:add(item)
            if self.mode == "readback_throw" then self.readFailure = true end
            if self.mode == "move_wrong" then return self.duplicate end
            return item
        end
        return value
    end
    local function fixture(label, mode)
        serial = serial + 1
        local source, target = container(), container()
        local key = { id = 70000 + serial, keyId = 80000 + serial }
        function key:getID() return self.id end
        function key:getKeyId() return self.keyId end
        function key:getContainer() return self.container end
        key.container = source source.items:add(key)
        source.trackedKey, target.trackedKey = key, key
        target.mode, target.duplicate = mode, { id = key.id, keyId = -1 }
        local car = { sqlId = 90000 + serial, hotSaves = 0, occupants = {} }
        function car:getSqlId() return self.sqlId end
        function car:getDriver() return self.occupants[0] end
        function car:getMaxPassengers() return 4 end
        function car:getCharacter(seat) return self.occupants[seat] end
        function car:getKeyId() return key.keyId end
        function car:getCurrentKey() return source.items:get(0) end
        function car:isKeysInIgnition() return source.items:size() > 0 end
        function car:flagForHotSave() self.hotSaves = self.hotSaves + 1 end
        cars:add(car)
        local value = setmetatable({ __keyActor = true, __owned = false, __class = "IsoPlayer",
            data = {}, square = square, characterActions = actionList(), endurance = 1,
            perks = {}, moodleLevels = {}, dead = false, bodyUnavailable = false,
        }, { __index = actor })
        function value:getInventory() return target end
        function value:getVehicle() return nil end
        local body = setmetatable({ health = 100, infected = false, infectionTime = -1, mortality = -1 },
            { __index = needsBody })
        function value:getBodyDamage() return body end
        function value:getHealth() return self.health or 100 end
        function value:setHealth(amount) self.health = amount end
        function value:getWornItems() return actionList() end
        function value:getPrimaryHandItem() return rawget(self, "primaryHand") end
        function value:getSecondaryHandItem() return rawget(self, "secondaryHand") end
        local saved = { id = "sc-key-" .. label .. "-" .. tostring(serial), recruited = true,
            identity = { forename = "Key", surname = "Recovery" },
            position = { x = 0, y = 0, z = 0 }, inventory = {}, skills = {}, vitals = {}, order = {},
            vehicle = { stored = false, seat = 0, vehicle = { sqlId = car.sqlId } },
        }
        local result = { actor = value, saved = saved, source = source, target = target,
            key = key, car = car }
        target.beforeAdd = function()
            result.postCommit = value.committed and SC.Registry.byId(saved.id).actor == value
            local ready = SC.Vehicle.validateDriverKeyRecovery()
            local savedDuringMove, reason = SC.Persistence.save({})
            result.saveGuard = not ready and not savedDuringMove
                and string.find(tostring(reason), "driver key recovery is unresolved", 1, true)
            result.saveReason = reason
        end
        selected = result
        return result
    end
    local function restore(value, direct)
        selected = value
        if direct then SC.Actor.beginSpawn = nil end
        local restored, why = SC.Persistence.restoreAt(value.saved, square)
        SC.Actor.beginSpawn = oldBegin
        check(restored == value.actor, "actual restore commits key fixture: " .. tostring(why))
        return restored
    end
    local function destination(value)
        return value.key.container == value.target and value.target.items:contains(value.key)
            and not value.source.items:contains(value.key) and value.car:getCurrentKey() == nil
            and value.car:isKeysInIgnition() == false
    end
    local function source(value)
        return value.key.container == value.source and value.source.items:contains(value.key)
            and not value.target.items:contains(value.key) and value.car:getCurrentKey() == value.key
    end
    local function retire(value)
        value.target.mode, value.target.readFailure, value.source.reject = nil, false, false
        value.car.occupants = {}
        local settled, why = SC.Vehicle.prepareDriverKeyReset(value.actor)
        check(settled, "key recovery settles before retirement: " .. tostring(value.saved.id)
            .. ":" .. tostring(why) .. " source=" .. tostring(value.source.items:size())
            .. " target=" .. tostring(value.target.items:size()) .. " adds=" .. tostring(value.source.adds))
        check(SC.Actor.remove(value.actor), "key restore fixture retires safely")
        cars:remove(value.car)
    end
    local sync = fixture("sync") restore(sync, true)
    check(destination(sync) and sync.target.adds == 1 and sync.car.hotSaves == 1,
        "synchronous spawn transfers the exact ignition item once and hot-saves its empty source: "
            .. tostring(sync.target.adds) .. "/" .. tostring(sync.car.hotSaves)
            .. " source=" .. tostring(source(sync)))
    check(sync.postCommit and sync.saveGuard,
        "key transfer follows full commit and blocks reentrant saves: " .. tostring(sync.saveReason))
    retire(sync)
    local ready = fixture("ready") restore(ready)
    check(destination(ready) and ready.target.adds == 1,
        "ready-ticket restore recovers the same existing ignition key")
    retire(ready)
    local failed = fixture("commit-failure") failed.actor.failCommit = true
    local failedActor = SC.Persistence.restoreAt(failed.saved, square)
    check(failedActor == nil and source(failed) and failed.target.adds == 0,
        "failure after native inventory initialization leaves the car key untouched")
    cars:remove(failed.car)

    local async = fixture("async")
    provider.requestSpawn = function() provider.polls = 0 return 700 end
    provider.pollSpawn = function()
        provider.polls = provider.polls + 1
        if provider.polls == 1 then return nil, "spawn_pending" end
        selected.actor.__owned = true return selected.actor
    end
    SC.Persistence.reset()
    local store = useWorldData({ document = { schema = SC.Identity.saveSchema,
        companions = { [async.saved.id] = async.saved } } })
    local keyPlayer = { getModData = function() return store end }
    check(SC.Persistence.restore(keyPlayer) and source(async) and async.target.adds == 0,
        "deferred restore keeps the real ignition key until its spawn commits")
    SC.Persistence.restorePulse(keyPlayer)
    check(destination(async) and async.actor.committed and async.target.adds == 1
            and not SC.Persistence.isPending(async.saved.id),
        "actual deferred restore-pulse completion recovers its exact ignition key")
    provider.requestSpawn, provider.pollSpawn = nil, nil
    retire(async)
    SC.Persistence.reset()

    local duplicate = fixture("duplicate", "duplicate") restore(duplicate)
    check(source(duplicate) and duplicate.car.hotSaves == 0,
        "duplicate-ID AddItem returning another item never consumes the original ignition key")
    for _ = 1, 8 do SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse() end
    check(duplicate.target.adds == 6 and source(duplicate) and SC.Vehicle.validateDriverKeyRecovery(),
        "safe duplicate-ID retries stop after the initial attempt plus five retries")
    retire(duplicate)
    local wrong = fixture("wrong-result", "move_wrong") restore(wrong)
    check(source(wrong) and wrong.source.adds == 1 and wrong.car.hotSaves == 0,
        "a transfer returning the wrong item compensates the exact moved key to ignition")
    retire(wrong)
    local partial = fixture("partial", "detach_throw") partial.source.reject = true restore(partial)
    check(partial.key.container == nil and not SC.Vehicle.validateDriverKeyRecovery()
            and not SC.Vehicle.releaseActor(partial.actor) and not SC.Vehicle.reset()
            and not SC.Persistence.prepareReset(),
        "a detached key with failed rollback blocks save/reset/retirement and retains recovery authority")
    partial.source.reject, partial.target.mode = false, nil
    SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse()
    SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse()
    check(destination(partial) and partial.car.hotSaves == 1 and SC.Vehicle.validateDriverKeyRecovery(),
        "a retained partial transfer rolls back then recovers without respawning its committed actor")
    retire(partial)
    local unreadable = fixture("readback", "readback_throw") unreadable.source.reject = true restore(unreadable)
    local adds = unreadable.target.adds
    unreadable.target.readFailure, unreadable.target.mode, unreadable.source.reject = false, nil, false
    SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse()
    check(destination(unreadable) and unreadable.target.adds == adds and unreadable.car.hotSaves == 1,
        "readback recovery verifies a completed destination without moving the exact key again")
    retire(unreadable)
    local indexFailure = fixture("index")
    SC.InventoryIndex.release = function() error("injected index-release failure") end
    restore(indexFailure)
    check(destination(indexFailure) and SC.Vehicle.validateDriverKeyRecovery(),
        "post-hot-save index failure retains a safe destination without blocking unrelated saves")
    SC.InventoryIndex.release = oldIndexRelease
    SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse()
    check(indexFailure.target.adds == 1 and indexFailure.car.hotSaves == 1,
        "index cleanup retry repeats neither the key move nor its completed hot-save")
    retire(indexFailure)
    local passenger = fixture("passenger") passenger.car.occupants[1] = { __class = "IsoPlayer" }
    restore(passenger)
    check(source(passenger) and passenger.target.adds == 0,
        "a player passenger prevents taking the car's ignition key")
    retire(passenger)
    local laterPassenger = fixture("later-passenger", "duplicate") restore(laterPassenger)
    laterPassenger.car.occupants[1] = { __class = "IsoPlayer" }
    SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse()
    check(source(laterPassenger) and laterPassenger.target.adds == 1,
        "a passenger boarding before retry prevents another ignition-key mutation")
    retire(laterPassenger)
    local replacement = fixture("replacement", "detach_throw")
    local otherKey = { keyId = -1, container = replacement.source }
    replacement.target.afterDetach = function() replacement.source.items:add(otherKey) end
    restore(replacement)
    check(replacement.key.container == nil and replacement.car:getCurrentKey() == otherKey
            and replacement.source.adds == 0 and not SC.Vehicle.prepareDriverKeyReset(replacement.actor),
        "rollback never inserts the old key into an ignition that acquired another key")
    replacement.source:Remove(otherKey)
    replacement.target.afterDetach = nil
    retire(replacement)
    local held = fixture("already-held")
    held.target.haveThisKeyId = function() return { keyId = held.key.keyId } end
    restore(held)
    check(source(held) and held.target.adds == 0,
        "a restored actor already holding a working car key leaves the ignition item untouched")
    retire(held)
    local invalidKeyId = fixture("key-id")
    invalidKeyId.car.getKeyId = function() error("injected key ID read failure") end
    local queried = 0
    invalidKeyId.target.haveThisKeyId = function() queried = queried + 1 return nil end
    restore(invalidKeyId)
    check(queried == 0 and source(invalidKeyId) and invalidKeyId.target.adds == 0,
        "an unreadable car key ID cannot reach the native haveThisKeyId query")
    retire(invalidKeyId)
    local unloaded = fixture("unloaded") cars:remove(unloaded.car) restore(unloaded)
    check(source(unloaded) and unloaded.target.adds == 0,
        "saved-position fallback for an unloaded car never fabricates or takes a key")
    retire(unloaded)
    local pulseFixtures = {}
    for index = 1, 5 do
        local value = fixture("pulse-" .. tostring(index), "duplicate")
        restore(value) pulseFixtures[#pulseFixtures + 1] = value
    end
    SC_TEST_CLOCK = SC_TEST_CLOCK + 31000 SC.Vehicle.restorePulse()
    local attempted = 0
    for _, value in ipairs(pulseFixtures) do attempted = attempted + value.target.adds - 1 end
    check(attempted == 4, "driver key recovery performs at most four actor retries per pulse")
    for _, value in ipairs(pulseFixtures) do retire(value) end
    SC.Commands.restore, SC.Actor.beginSpawn, SC.InventoryIndex.release = oldRestore, oldBegin, oldIndexRelease
    getCell = oldCell
    SC.Actor._setProviderForTests(deferredProvider)
end)()

print("CORE_KAHLUA_PASS checks=" .. tostring(checks))
