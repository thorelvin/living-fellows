-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
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
    local store = SC_TEST_SET_WORLD_STORE({ document = { schema = SC.Identity.saveSchema,
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
    SC.Actor._setProviderForTests(nil)
end)()

print("VEHICLE_KEY_RECOVERY_PASS checks=" .. tostring(checks))
