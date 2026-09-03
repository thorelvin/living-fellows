-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCConfig"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBarricadeAction"
require "TimedActions/ISUnbarricadeAction"
require "TimedActions/ISDismantleAction"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFromBottle"
require "TimedActions/ISTakeWaterAction"
require "TimedActions/ISWearClothing"

local SC = SurvivorCompanion
SC.NativeActions = SC.NativeActions or {}

local actions = SC.NativeActions
local activeWork = setmetatable({}, { __mode = "k" })
local activeNeeds = setmetatable({}, { __mode = "k" })
local activeFinal = setmetatable({}, { __mode = "k" })
local activeVisual = setmetatable({}, { __mode = "k" })
local pacingStates = setmetatable({}, { __mode = "k" })
local resultHistory = setmetatable({}, { __mode = "k" })
local pacingSequence = 0
local humanEmotes = {
    wavehi = true, wavebye = true, clap = true, thumbsup = true, thankyou = true,
    insult = true, stop = true, surrender = true, thumbsdown = true,
    followme = true, comehere = true, yes = true, no = true, shrug = true,
    undecided = true, ceasefire = true, signalok = true, moveout = true,
    freeze = true, followbehind = true, signalfire = true, comefront = true,
    salute = true,
}
local emoteAliases = {
    -- The stock radial menu expands this UI alias before calling playEmote().
    salute = "salutecasual",
}

local movementActions = {
    move = true,
    path = true,
    ordered_move = true,
    approach_interaction = true,
    approach_player_cautiously = true,
    check_room = true,
    collision_recovery = true,
    combat_retreat = true,
    corner_escape = true,
    hide_indoors = true,
    investigate_sound = true,
    leave_group = true,
    move_to_scavenge = true,
    move_to_camp_storage = true,
    move_to_base_storage = true,
    move_to_base_build = true,
    base_guard_patrol = true,
    return_to_base = true,
    move_to_quarantine = true,
    leave_base = true,
    crisis_approach = true,
    move_to_memorial = true,
    move_to_water_source = true,
    move_to_seat = true,
    move_to_treat = true,
    offscreen_safe_recovery = true,
    ordered_retreat = true,
}

local combatActions = {
    attack_firearm = true,
    attack_melee = true,
    shove = true,
    stomp = true,
}

local windowActions = {
    open_window = true,
    smash_window = true,
    remove_glass = true,
    climb_window = true,
    climb_window_emergency = true,
}

-- These are effect-free, human animation adapters.  The gameplay subsystem owns
-- the associated inventory/body mutation and performs it only after this native
-- timed action has demonstrably entered the actor's native action queue.  Using
-- the real transfer/medical/craft actions here would apply each effect twice.
local visualActionSpecs = {
    loot_container = { animation = "Loot", event = "EventLootItem", lootPosition = "", ticks = 90 },
    kneel_treat = { animation = "Bandage", animationEnum = true,
        event = "EventBandage", ticks = 100 },
    rip_clothing_for_bandage = { animation = "Craft", animationEnum = true, ticks = 120 },
    read = { animation = "Read", animationEnum = true, event = "EventRead",
        secondaryItem = true, ticks = 360 },
    repair = { animation = "Craft", animationEnum = true, primaryItem = true, ticks = 180 },
    replace_bandage = { animation = "Bandage", animationEnum = true,
        event = "EventBandage", ticks = 100 },
    craft_supply = { animation = "Craft", animationEnum = true, ticks = 180 },
    wear_clothing = { animation = "WearClothing", event = "EventWearClothing", ticks = 90 },
    wash_self = { animation = "WashFace", event = "EventWashClothing", ticks = 240 },
    wash_equipment = { animation = "ScrubClothWithSoap", event = "EventWashClothing",
        primaryItem = true, ticks = 240 },
    -- No verified non-local projectile throw exists in Build 42.20.4. These
    -- stay effect-free; the autonomy layer applies sound/item consequences
    -- only after this human timed action reports successful completion.
    stress_bottle_smash = { animation = "Craft", animationEnum = true,
        primaryItem = true, ticks = 150 },
    stress_furniture_hit = { animation = "Craft", animationEnum = true, ticks = 150 },
    -- Effect-free household routine poses. Resource accounting remains owned
    -- by SCFactionLife; these only make meals and drinks visible to the player.
    ambient_eat = { animation = "Eat", animationEnum = true, ticks = 100 },
    ambient_drink = { animation = "Drink", animationEnum = true, ticks = 100 },
}

local VisualTimedAction

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor((os.clock and os.clock() or 0) * 1000)
end

local function stableHash(text)
    local hash = 2166136261
    text = tostring(text or "")
    for index = 1, #text do
        hash = (hash * 16777619 + string.byte(text, index)) % 2147483647
    end
    return hash
end

local function actorKey(actor)
    local utility = SC.GameplayUtil
    if type(utility) == "table" and type(utility.idOf) == "function" then
        local ok, value = pcall(utility.idOf, actor)
        if ok and value ~= nil then return tostring(value) end
    end
    return tostring(actor)
end

local function commandSerial(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return tonumber(state.commandSerial) or 0 end
    end
    return 0
end

local function isUrgentAction(action, intent)
    intent = type(intent) == "table" and intent or {}
    return intent.urgent == true or intent.emergency == true
        or intent.survivalCritical == true or combatActions[action] == true
        or action == "combat_retreat" or action == "ordered_retreat"
        or action == "corner_escape" or action == "climb_window_emergency"
        or action == "downed" or action == "recover_from_downed"
        or action == "exit_vehicle"
end

local function method(object, name)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    if not ok or type(value) ~= "function" then
        return nil
    end
    return value
end

local function invoke(object, name, ...)
    return SC.Call.method(object, name, ...)
end

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function position(value)
    if value == nil then
        return nil
    end
    if type(value) == "table" and finite(value.x) and finite(value.y) then
        return tonumber(value.x), tonumber(value.y), tonumber(value.z) or 0
    end
    local xOk, x = invoke(value, "getX")
    local yOk, y = invoke(value, "getY")
    local zOk, z = invoke(value, "getZ")
    if xOk and yOk and finite(x) and finite(y) then
        return tonumber(x), tonumber(y), zOk and tonumber(z) or 0
    end
    return nil
end

local function normalizeMode(mode)
    if mode == "jog" then
        return "run"
    end
    if mode == "walk" or mode == "run" or mode == "sneak" then
        return mode
    end
    return nil
end

local function heldWeapon(actor)
    local ok, item = invoke(actor, "getPrimaryHandItem")
    if not ok or item == nil then return nil end
    if type(instanceof) == "function" then
        local classOk, isWeapon = pcall(instanceof, item, "HandWeapon")
        if classOk and isWeapon == true then return item end
    end
    local categoryOk, category = invoke(item, "getCategory")
    if categoryOk and tostring(category) == "Weapon" then return item end
    if method(item, "isRanged") ~= nil or method(item, "getMaxDamage") ~= nil then return item end
    return nil
end

local function setTacticalMovement(actor, enabled, strafeX, strafeY)
    if method(actor, "setCompanionTacticalMovement") == nil then
        return nil, "native tactical movement is unavailable"
    end
    local changed, retained = invoke(actor, "setCompanionTacticalMovement",
        enabled == true, tonumber(strafeX) or 0, tonumber(strafeY) or 0)
    if not changed then return false, retained end
    if retained ~= true then return false, "native tactical movement was not retained" end
    return true, enabled and "tactical_movement" or "tactical_movement_cleared"
end

local function setWeaponReady(actor, enabled, target)
    enabled = enabled == true and heldWeapon(actor) ~= nil
    if not enabled then setTacticalMovement(actor, false, 0, 0) end
    if enabled and target ~= nil then
        local x, y = position(target)
        if x ~= nil then
            if type(target) ~= "table" or target.x == nil then x, y = x + 0.5, y + 0.5 end
            invoke(actor, "faceLocationF", x, y)
        end
    end
    if enabled then invoke(actor, "setAimAtFloor", false) end
    local changed, reason = invoke(actor, "setIsAiming", enabled)
    if not changed then return false, reason end
    local checked, aiming = invoke(actor, "isAiming")
    if checked and aiming ~= enabled then
        return false, enabled and "native weapon-ready state was not retained"
            or "native weapon-ready state did not clear"
    end
    if enabled then return true, "weapon_ready" end
    return true, heldWeapon(actor) and "weapon_lowered" or "unarmed_ready_skipped"
end

local function leaveFurniture(actor)
    local sittingOk, sitting = invoke(actor, "isSittingOnFurniture")
    if not sittingOk or sitting ~= true then return true, "already_standing" end
    local stateOk = invoke(actor, "setSittingOnFurniture", false)
    local objectOk = invoke(actor, "setSitOnFurnitureObject", nil)
    local verifyOk, after = invoke(actor, "isSittingOnFurniture")
    if not stateOk or not objectOk or not verifyOk or after == true then
        return false, "native furniture-sitting state could not be cleared"
    end
    return true, "stood_from_furniture"
end

local function groundSeatState(actor)
    local ok, seated = invoke(actor, "isSitOnGround")
    return ok and seated == true
end

local function requestGroundSeat(actor, seated)
    if seated then
        if groundSeatState(actor) then return true, "already_sitting_on_ground" end
        actions.stopDirect(actor)
        local requested, reason = invoke(actor, "reportEvent", "EventSitOnGround")
        return requested, requested and "ground_sit_requested" or reason
    end
    if not groundSeatState(actor) then return true, "already_standing" end
    local requested, reason = invoke(actor, "setVariable", "forceGetUp", true)
    return requested, requested and "ground_stand_requested" or reason
end

local function leaveSeating(actor)
    local standing, reason = leaveFurniture(actor)
    if not standing then return false, reason end
    if groundSeatState(actor) then
        local requested, standReason = requestGroundSeat(actor, false)
        if not requested then return false, standReason end
        -- The animation graph clears isSitOnGround asynchronously. Refuse the
        -- requested gameplay action this tick so it is retried only after the
        -- native character is actually standing.
        return false, "standing_from_ground"
    end
    return true, reason
end

local function targetOf(intent)
    return intent.nextSquare or intent.targetSquare or intent.targetPosition
end

local function vectorFor(actor, intent)
    local dx = tonumber(intent.dx)
    local dy = tonumber(intent.dy)
    if finite(dx) and finite(dy) then
        return dx, dy
    end

    local ax, ay = position(actor)
    if ax == nil then
        return nil, nil, "actor position is unavailable"
    end

    local destination = targetOf(intent)
    if destination ~= nil then
        local tx, ty = position(destination)
        if tx == nil then
            return nil, nil, "target square position is unavailable"
        end
        return tx + 0.5 - ax, ty + 0.5 - ay
    end

    local away = intent.awayFrom
    if away ~= nil then
        local tx, ty = position(away)
        if tx == nil then
            return nil, nil, "avoidance target position is unavailable"
        end
        dx = ax - tx
        dy = ay - ty
        if intent.lateral == true then
            dx, dy = -dy, dx
        end
        return dx, dy
    end

    if finite(intent.x) and finite(intent.y) then
        return tonumber(intent.x) - ax, tonumber(intent.y) - ay
    end
    return nil, nil, "movement intent has no direction or target"
end

function actions.inspectMovementBlocker(actor)
    local utility = SC.GameplayUtil
    if type(utility) == "table" and type(utility.movementStateBlocker) == "function" then
        return utility.movementStateBlocker(actor)
    end
    local knockedOk, knocked = invoke(actor, "isKnockedDown")
    if knockedOk and knocked == true then return "knocked_down" end
    local climbingOk, climbing = invoke(actor, "isClimbing")
    if climbingOk and climbing == true then return "climbing" end
    local blockedOk, blocked = invoke(actor, "isBlockMovement")
    if blockedOk and blocked == true then return "movement_locked" end
    return nil
end

local function movementReady(actor)
    local blocker = actions.inspectMovementBlocker(actor)
    if blocker then
        actions.stopDirect(actor)
        return false, "actor_state_blocked:" .. tostring(blocker)
    end
    return true
end

local function publicField(object, name)
    if object == nil then return false, nil end
    local ok, value = pcall(function() return object[name] end)
    if not ok then return false, nil end
    return true, value
end

-- Read-only engine path state used by the Lua planner.  PathFindBehavior2 can
-- legitimately spend several updates waiting for PolygonalMap2, turning to an
-- obstacle, or handing movement to a climb/open animation.  Those states are
-- progress even when the actor's world position has not changed yet.
function actions.pathTelemetry(actor)
    local behaviorOk, behavior = invoke(actor, "getPathFindBehavior2")
    if not behaviorOk or behavior == nil then return { available = false } end
    local telemetry = { available = true, behavior = behavior }
    local methods = {
        shouldBeMoving = "shouldBeMoving",
        hasStartedMoving = "hasStartedMoving",
        turningToObstacle = "isTurningToObstacle",
        movingUsingPathFind = "isMovingUsingPathFind",
        allowTurnAnimation = "allowTurnAnimation",
        strafing = "isStrafing",
    }
    for key, name in pairs(methods) do
        local ok, value = invoke(behavior, name)
        if ok then telemetry[key] = value == true end
    end
    local fieldOk, field = publicField(behavior, "pathNextIsSet")
    if fieldOk then telemetry.pathNextIsSet = field == true end
    fieldOk, field = publicField(behavior, "pathNextX")
    if fieldOk and finite(field) then telemetry.pathNextX = tonumber(field) end
    fieldOk, field = publicField(behavior, "pathNextY")
    if fieldOk and finite(field) then telemetry.pathNextY = tonumber(field) end
    telemetry.active = telemetry.movingUsingPathFind == true
        or telemetry.turningToObstacle == true
        or (telemetry.movingUsingPathFind == nil and telemetry.shouldBeMoving == true)
    telemetry.pending = telemetry.active == true
        and telemetry.hasStartedMoving == false
    return telemetry
end

local function flattenTargets(targets)
    local locations, firstX, firstY, firstZ = {}, nil, nil, nil
    local seen = {}
    for _, target in ipairs(type(targets) == "table" and targets or {}) do
        local x, y, z = position(target)
        if x ~= nil then
            x, y, z = math.floor(x) + 0.5, math.floor(y) + 0.5, math.floor(z or 0)
            local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
            if not seen[key] then
                seen[key] = true
                locations[#locations + 1] = x
                locations[#locations + 1] = y
                locations[#locations + 1] = z
                if firstX == nil then firstX, firstY, firstZ = x, y, z end
            end
        end
    end
    return locations, firstX, firstY, firstZ
end

-- The owned native actor exposes a narrow wrapper that pairs
-- PathFindBehavior2.pathToNearestTable() with the same player path-state setup
-- used by pathToLocationF().  External Workshop providers may not expose it;
-- callers must retain a normal single-target fallback.
function actions.pathToNearest(actor, targets, mode)
    local ready, readyReason = movementReady(actor)
    if not ready then return false, readyReason end
    local locations, firstX, firstY, firstZ = flattenTargets(targets)
    if #locations < 3 then return false, "nearest path has no valid targets" end
    local behaviorOk, behavior = invoke(actor, "getPathFindBehavior2")
    if not behaviorOk or behavior == nil then
        return false, "native path behavior is unavailable"
    end
    setTacticalMovement(actor, false, 0, 0)
    local weaponReady, weaponReason = setWeaponReady(actor, false)
    if not weaponReady then return false, weaponReason end
    invoke(actor, "setRunning", mode == "run" or mode == "jog")
    invoke(actor, "setSprinting", false)
    invoke(actor, "setSneaking", mode == "sneak")
    local started, reason = invoke(actor, "bridgePathToNearest",
        locations, firstX, firstY, firstZ)
    if not started or reason ~= true then
        return false, started and "native nearest path request was rejected" or reason
    end
    local telemetry = actions.pathTelemetry(actor)
    if telemetry.available and telemetry.active == false then
        invoke(behavior, "cancel")
        return false, "native nearest path request did not become active"
    end
    return true, "nearest_path_started"
end

local function directPath(actor, target, mode, intent)
    local stateReady, stateReason = movementReady(actor)
    if not stateReady then return false, stateReason end
    local x, y, z = position(target)
    if x == nil then
        return false, "path target position is unavailable"
    end
    x = x + 0.5
    y = y + 0.5
    local behaviorOk, behavior = invoke(actor, "getPathFindBehavior2")
    if not behaviorOk or behavior == nil then
        return false, "native path behavior is unavailable"
    end
    -- Engine paths may turn at doors, vegetation and stairs. Do not hold a
    -- stale strafe vector while PathFindBehavior2 owns those turns.
    setTacticalMovement(actor, false, 0, 0)
    local ready, readyReason = setWeaponReady(actor, false)
    if not ready then return false, readyReason end
    invoke(actor, "setRunning", mode == "run")
    invoke(actor, "setSprinting", false)
    invoke(actor, "setSneaking", mode == "sneak")
    local retainedOk, retained = invoke(behavior, "isTargetLocation", x, y, z)
    local activeOk, active = invoke(behavior, "shouldBeMoving")
    if retainedOk and retained == true and activeOk and active == true then
        return true, "path_continues"
    end
    -- Use the character entry point, not PathFindBehavior2 directly. Vanilla
    -- pathToLocationF also selects bPathfind/direct movement and updates the
    -- same locomotion state that the player animation graph consumes.
    local started, reason = invoke(actor, "pathToLocationF", x, y, z)
    if not started then
        actions.stopDirect(actor)
        return false, reason
    end
    local verified, matches = invoke(behavior, "isTargetLocation", x, y, z)
    if not verified or matches ~= true then
        invoke(behavior, "cancel")
        return false, "native path request did not retain its target"
    end
    return true, "path_started"
end

local function directMove(actor, mode, dx, dy, intent)
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared < 0.000001 then
        actions.stopDirect(actor)
        return true, "already_at_target"
    end

    local length = math.sqrt(lengthSquared)
    local nx = dx / length
    local ny = dy / length
    local tacticalCorner = type(intent) == "table" and intent.tacticalCorner == true
    local effectiveMode = tacticalCorner and "sneak" or mode
    local distance = SC.Config.get(effectiveMode .. "Distance")
    if not finite(distance) or distance <= 0 then
        return false, "movement distance is invalid"
    end

    local x, y, z = position(actor)
    if x == nil then
        return false, "actor position is unavailable"
    end
    local toX, toY = x + nx * distance, y + ny * distance
    local stateReady, stateReason = movementReady(actor)
    if not stateReady then return false, stateReason end
    local collisionOk, movementClear = invoke(
        actor, "isCompanionMovementClear", toX, toY, z)
    if not collisionOk then
        return false, "native_continuous_collision_probe_unavailable"
    end
    if movementClear ~= true then
        return false, "continuous_collision_blocked"
    end

    local facingX, facingY = nx, ny
    local facingTarget = type(intent) == "table" and intent.facingTarget or nil
    if facingTarget == nil and type(intent) == "table" and intent.keepFacing == true then
        facingTarget = intent.target or intent.awayFrom
    end
    if facingTarget == nil and type(intent) == "table" and intent.weaponReady == true then
        facingTarget = intent.observationTarget or intent.nextSquare or intent.targetSquare
    end
    if facingTarget ~= nil then
        local targetX, targetY = position(facingTarget)
        if targetX ~= nil then
            local lookX, lookY = targetX - x, targetY - y
            local lookLength = math.sqrt(lookX * lookX + lookY * lookY)
            if lookLength > 0.000001 then facingX, facingY = lookX / lookLength, lookY / lookLength end
        end
    end

    local tactical = type(intent) == "table" and facingTarget ~= nil
        and (intent.tacticalStrafe == true or intent.tacticalStair == true
            or intent.tacticalRetreat == true or intent.keepFacing == true
            or intent.weaponReady == true)
    local ready, readyReason = setWeaponReady(actor, intent.weaponReady == true, facingTarget)
    if not ready then return false, readyReason end
    if tactical then
        -- Convert the world-space translation into the stock player's local
        -- strafe blend axes. Negative Y selects backward walking; X selects a
        -- lateral or diagonal step while the upper body faces the threat.
        local localX = nx * -facingY + ny * facingX
        local localY = nx * facingX + ny * facingY
        local tacticalSet, tacticalReason = setTacticalMovement(
            actor, true, localX, localY)
        if tacticalSet == false then return false, tacticalReason end
    else
        setTacticalMovement(actor, false, 0, 0)
    end
    -- Never let PathFindBehavior2 and manual MoveForward own the same frame.
    -- Their competing vectors cause sliding and frozen-foot moonwalking.
    local behaviorOk, behavior = invoke(actor, "getPathFindBehavior2")
    if behaviorOk and behavior ~= nil then invoke(behavior, "cancel") end
    invoke(actor, "setForwardDirection", facingX, facingY)
    invoke(actor, "setRunning", mode == "run" and not tactical and intent.weaponReady ~= true)
    invoke(actor, "setSprinting", false)
    invoke(actor, "setSneaking", effectiveMode == "sneak")
    invoke(actor, "setMoving", true)
    local moved, reason = invoke(actor, "MoveForward", distance, nx, ny,
        SC.Config.get("movementSoundDelta"))
    if not moved then
        actions.stopDirect(actor)
        return false, reason
    end
    -- MoveForward owns the translation vector. Reapply the observation vector
    -- afterwards so a corner step is a true sidestep rather than a blind turn.
    if tactical and facingTarget ~= nil then invoke(actor, "setForwardDirection", facingX, facingY) end

    local movingOk, moving = invoke(actor, "isMoving")
    local newX, newY = position(actor)
    local changed = newX ~= nil and (math.abs(newX - x) > 0.000001 or math.abs(newY - y) > 0.000001)
    if not changed and (not movingOk or moving ~= true) then
        actions.stopDirect(actor)
        return false, "native movement did not start"
    end
    return true, "moving"
end

local function useProvider(provider, operation, ...)
    if type(provider) ~= "table" or type(provider[operation]) ~= "function" then
        return nil, "provider operation is unavailable: " .. tostring(operation)
    end
    local values = SC.Call.pack(pcall(provider[operation], provider, ...))
    if not values[1] then
        return false, tostring(values[2])
    end
    if values[2] ~= true then
        return false, values[3] or "native operation did not start"
    end
    return true, values[3]
end

local function visualActionClass()
    if VisualTimedAction ~= nil then
        return VisualTimedAction
    end
    if type(ISBaseTimedAction) ~= "table" or type(ISBaseTimedAction.derive) ~= "function" then
        return nil
    end

    local class = ISBaseTimedAction:derive("SCVerifiedVisualTimedAction")

    function class:isValid()
        if self.character == nil then return false end
        local deadOk, dead = invoke(self.character, "isDead")
        return not deadOk or dead ~= true
    end

    function class:start()
        local animation = self.animation
        if self.animationEnum then
            local resolved, enumValue = pcall(function()
                return CharacterActionAnims[self.animation]
            end)
            animation = resolved and enumValue or nil
        end
        if animation == nil then
            self.scAnimationMissing = true
            self:forceStop()
            return
        end
        self:setActionAnim(animation)
        if self.lootPosition ~= nil then
            self:setAnimVariable("LootPosition", self.lootPosition)
        end
        if self.wearLocation ~= nil then
            local animation = type(WearClothingAnimations) == "table"
                and WearClothingAnimations[self.wearLocation] or ""
            self:setAnimVariable("WearClothingLocation", animation or "")
        end
        if self.readType ~= nil then self:setAnimVariable("ReadType", self.readType) end
        if self.bandageType ~= nil then self:setAnimVariable("BandageType", self.bandageType) end
        if self.primaryItem ~= nil or self.secondaryItem ~= nil then
            self:setOverrideHandModels(self.primaryItem, self.secondaryItem)
        else
            self:setOverrideHandModels(nil, nil)
        end
        if self.event ~= nil then
            invoke(self.character, "reportEvent", self.event)
        end
        if self.reading then invoke(self.character, "setReading", true) end
    end

    function class:update()
        if self.faceTarget ~= nil then invoke(self.character, "faceThisObject", self.faceTarget) end
    end

    function class:stop()
        self.scStopped = true
        if self.reading then invoke(self.character, "setReading", false) end
        ISBaseTimedAction.stop(self)
    end

    function class:perform()
        self.scCompleted = true
        if self.reading then invoke(self.character, "setReading", false) end
        ISBaseTimedAction.perform(self)
    end

    function class:new(character, actionName, spec, intent)
        local value = ISBaseTimedAction.new(self, character)
        value.actionName = actionName
        value.animation = spec.animation
        value.animationEnum = spec.animationEnum == true
        value.event = spec.event
        value.lootPosition = spec.lootPosition
        if actionName == "loot_container" then
            if intent.lootPosition ~= nil then
                value.lootPosition = tostring(intent.lootPosition)
            elseif intent.container ~= nil then
                local positionOk, containerPosition = invoke(intent.container, "getContainerPosition")
                if positionOk and containerPosition ~= nil and tostring(containerPosition) ~= "" then
                    value.lootPosition = tostring(containerPosition)
                else
                    local typeOk, containerType = invoke(intent.container, "getType")
                    local loweredType = typeOk and string.lower(tostring(containerType or "")) or ""
                    local parentOk, parent = invoke(intent.container, "getParent")
                    local corpse = false
                    if parentOk and parent ~= nil and type(instanceof) == "function" then
                        local classOk, isCorpse = pcall(instanceof, parent, "IsoDeadBody")
                        corpse = classOk and isCorpse == true
                    end
                    if loweredType == "floor" or loweredType == "freezer"
                        or corpse then
                        value.lootPosition = "Low"
                    end
                end
            end
        end
        value.wearLocation = actionName == "wear_clothing" and intent.wearLocation or nil
        if actionName == "wear_clothing" and value.wearLocation == nil and intent.item ~= nil then
            local clothingOk, clothing = invoke(intent.item, "IsClothing")
            local locationOk, location
            if clothingOk and clothing == true then
                locationOk, location = invoke(intent.item, "getBodyLocation")
            else
                locationOk, location = invoke(intent.item, "canBeEquipped")
            end
            if locationOk then value.wearLocation = location end
        end
        if actionName == "read" then
            local typeOk, readType = invoke(intent.item, "getReadType")
            value.readType = typeOk and tostring(readType or "book") or "book"
            value.reading = true
        end
        if actionName == "kneel_treat" or actionName == "replace_bandage" then
            value.faceTarget = intent.patient
            if type(ISHealthPanel) == "table" and type(ISHealthPanel.getBandageType) == "function"
                and intent.bodyPart ~= nil then
                local ok, bandageType = pcall(ISHealthPanel.getBandageType, intent.bodyPart)
                if ok then value.bandageType = bandageType end
            end
            value.bandageType = value.bandageType or "LeftLeg"
        end
        value.primaryItem = spec.primaryItem and intent.item or nil
        value.secondaryItem = spec.secondaryItem and intent.item or nil
        value.ignoreHandsWounds = true
        value.stopOnWalk = true
        value.stopOnRun = true
        value.stopOnAim = true
        local requestedTicks = tonumber(intent.durationTicks)
        if requestedTicks == nil and tonumber(intent.durationMs) then
            requestedTicks = tonumber(intent.durationMs) * 60 / 1000
        end
        local minimum = tonumber(SC.Config.get("actionVisualMinTicks")) or 45
        local maximum = tonumber(SC.Config.get("actionVisualMaxTicks")) or 420
        value.maxTime = math.max(minimum, math.min(maximum,
            math.floor((requestedTicks or spec.ticks or 90) + 0.5)))
        return value
    end

    VisualTimedAction = class
    return class
end

-- Cancel exactly one timed-action instance owned by Living Fellows, leaving any
-- unrelated third-party action queued on the companion untouched. Never clear the
-- whole queue (ISTimedActionQueue.clear(actor)) -- on a companion an unknown mod's
-- action can be sharing the queue.
local function cancelOwnedTimedAction(queue, timedAction)
    if timedAction ~= nil and timedAction.action ~= nil then
        pcall(timedAction.forceStop, timedAction)
    end
    if type(queue) == "table" and type(queue.removeFromQueue) == "function" then
        pcall(queue.removeFromQueue, queue, timedAction)
        if queue.current == timedAction then queue.current = nil end
    end
end

local function removeRejectedVisual(queue, timedAction)
    cancelOwnedTimedAction(queue, timedAction)
end

local function startVerifiedVisual(actor, actionName, intent, provider)
    -- Never replace an unclaimed completed visual record with a second visual.
    -- The owning gameplay subsystem needs that record to know whether it may
    -- commit its inventory/body effect exactly once.
    if type(actions.visualStatus) == "function" then
        local priorState, priorName, priorAt = actions.visualStatus(actor)
        if priorState == "active" then
            return false, "visual_action_active:" .. tostring(priorName)
        elseif priorState == "completed" then
            local grace = tonumber(SC.Config.get("visualEffectClaimMs")) or 2000
            if nowMs() - (tonumber(priorAt) or 0) < grace then
                return false, "visual_effect_pending:" .. tostring(priorName)
            end
            actions.clearVisual(actor)
        elseif priorState ~= "none" then
            actions.clearVisual(actor)
        end
    end

    -- Navigation owns locomotion until an interaction takes over.  Reaching a
    -- container does not automatically cancel PathFindBehavior2, so the next
    -- native update could advance one more step and trip stopOnWalk on Loot (or
    -- another interaction pose).  Hand ownership to the timed action
    -- atomically: cancel the path, clear retained bridge movement/strafe, and
    -- verify the actor is stationary before anything is queued.
    if actions.stopDirect(actor) ~= true then
        return false, "visual_action_could_not_acquire_stationary_actor"
    end

    local handled, reason = useProvider(provider, "animate", actor, actionName, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end

    local lowered, lowerReason = setWeaponReady(actor, false)
    if not lowered then return false, lowerReason end

    local spec = visualActionSpecs[actionName]
    if spec == nil then
        return false, "no validated human timed-action mapping for " .. actionName
    end
    if type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function"
        or type(ISTimedActionQueue.add) ~= "function" then
        return false, "native timed-action queue is unavailable"
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" or queue.current ~= nil or type(queue.queue) ~= "table"
        or #queue.queue ~= 0 then
        return false, "actor already has a native timed action"
    end
    local class = visualActionClass()
    if class == nil then
        return false, "native timed-action base is unavailable"
    end
    local created, timedAction = pcall(class.new, class, actor, actionName, spec, intent)
    if not created or timedAction == nil then
        return false, created and "visual timed action was not created" or tostring(timedAction)
    end
    local queued, failure = pcall(ISTimedActionQueue.add, timedAction)
    if not queued then
        return false, tostring(failure)
    end

    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local nativeActionsOk, nativeActions = invoke(actor, "getCharacterActions")
    local containedOk, contained = invoke(nativeActions, "contains", timedAction.action)
    local startedOk, started = pcall(timedAction.isStarted, timedAction)
    local retained = type(queue) == "table" and queue.current == timedAction
        and type(queue.queue) == "table" and queue.queue[1] == timedAction
    local nativeStarted = timedAction.action ~= nil and nativeActionsOk and containedOk
        and contained == true and startedOk and started == true
    if not retained or not nativeStarted then
        removeRejectedVisual(queue, timedAction)
        return false, "native visual timed action did not start"
    end
    activeVisual[actor] = {
        actionName = actionName,
        timedAction = timedAction,
        startedAt = nowMs(),
    }
    return true, "visual_timed_action_started:" .. actionName
end

local function nativeListSize(list)
    if list == nil then return 0 end
    if type(list) == "table" then return #list end
    local ok, size = invoke(list, "size")
    return ok and tonumber(size) or 0
end

local function nativeListGet(list, index)
    if type(list) == "table" then return list[index + 1] end
    local ok, value = invoke(list, "get", index)
    return ok and value or nil
end

local function trackedActionIsActive(actor, record)
    if type(record) ~= "table" or record.timedAction == nil then return false end
    local queue = type(ISTimedActionQueue) == "table"
        and type(ISTimedActionQueue.getTimedActionQueue) == "function"
        and ISTimedActionQueue.getTimedActionQueue(actor) or nil
    if type(queue) == "table" then
        if queue.current == record.timedAction then return true end
        if type(queue.indexOf) == "function" then
            local ok, index = pcall(queue.indexOf, queue, record.timedAction)
            if ok and tonumber(index) and tonumber(index) >= 0 then return true end
        elseif type(queue.queue) == "table" then
            for _, queued in ipairs(queue.queue) do
                if queued == record.timedAction then return true end
            end
        end
    end
    local nativeOk, nativeActions = invoke(actor, "getCharacterActions")
    local containedOk, contained = invoke(nativeActions, "contains", record.timedAction.action)
    return nativeOk and containedOk and contained == true
end

local function moveItemToRoot(actor, item)
    if item == nil then return true, nil end
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "actor inventory is unavailable" end
    local containerOk, container = invoke(item, "getContainer")
    if containerOk and container == inventory then return true, nil end
    if not containerOk or container == nil then return false, "needs item has no source container" end
    local removedOk, removed = invoke(container, "Remove", item)
    if not removedOk or removed == false then return false, "needs item could not leave its container" end
    local addedOk, added = invoke(inventory, "AddItem", item)
    local currentOk, current = invoke(item, "getContainer")
    if not addedOk or added == false or not currentOk or current ~= inventory then
        invoke(inventory, "Remove", item)
        invoke(container, "AddItem", item)
        return false, "needs item could not enter the main inventory"
    end
    return true, container
end

local function restoreNeedsItem(actor, record)
    if type(record) ~= "table" or record.item == nil or record.originalContainer == nil then
        return true, "no_needs_item_restore"
    end
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "actor inventory is unavailable" end
    local containerOk, current = invoke(record.item, "getContainer")
    if not containerOk or current == nil then return true, "needs_item_consumed" end
    if current ~= inventory then return current == record.originalContainer, "needs_item_already_moved" end
    local removedOk, removed = invoke(inventory, "Remove", record.item)
    if not removedOk or removed == false then return false, "needs item could not be restored" end
    local addedOk, added = invoke(record.originalContainer, "AddItem", record.item)
    local afterOk, after = invoke(record.item, "getContainer")
    if not addedOk or added == false or not afterOk or after ~= record.originalContainer then
        invoke(record.originalContainer, "Remove", record.item)
        invoke(inventory, "AddItem", record.item)
        return false, "needs item restoration rolled back"
    end
    return true, "needs_item_restored"
end

local function queueNeedsAction(actor, kind, timedAction, item, originalContainer)
    if type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function"
        or type(ISTimedActionQueue.add) ~= "function" then
        return false, "native timed-action queue is unavailable"
    end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" or queue.current ~= nil or type(queue.queue) ~= "table"
        or #queue.queue ~= 0 then
        return false, "actor already has a native timed action"
    end
    if timedAction == nil then return false, "needs timed action was not created" end
    if type(timedAction.isValidStart) == "function" then
        local ok, valid = pcall(timedAction.isValidStart, timedAction)
        if not ok or valid ~= true then return false, "needs timed action rejected its start" end
    end
    if type(timedAction.isValid) == "function" then
        local ok, valid = pcall(timedAction.isValid, timedAction)
        if not ok or valid ~= true then return false, "needs timed action rejected its item or source" end
    end
    local queued, failure = pcall(ISTimedActionQueue.add, timedAction)
    if not queued then return false, tostring(failure) end
    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local retained = type(queue) == "table" and queue.current == timedAction
        and type(queue.queue) == "table" and queue.queue[1] == timedAction
    if not retained then
        removeRejectedVisual(queue, timedAction)
        return false, "native needs action did not enter the queue"
    end
    activeNeeds[actor] = {
        kind = kind,
        timedAction = timedAction,
        item = item,
        originalContainer = originalContainer,
        startedAt = nowMs(),
    }
    return true, kind .. "_timed_action_started"
end

local function startNeedsAction(actor, action, intent, provider)
    if not provider.directNative then return false, "direct native needs actions are unavailable" end
    local item = intent.item
    local originalContainer
    if item ~= nil then
        local moved, sourceOrReason = moveItemToRoot(actor, item)
        if not moved then return false, sourceOrReason end
        originalContainer = sourceOrReason
    end
    local created, timedAction
    if action == "eat_food" then
        if type(ISEatFoodAction) ~= "table" or type(ISEatFoodAction.new) ~= "function" then
            created, timedAction = false, "native eat action is unavailable"
        else
            created, timedAction = pcall(ISEatFoodAction.new, ISEatFoodAction,
                actor, item, tonumber(intent.percentage) or 1)
        end
    elseif action == "drink_item" then
        if type(ISDrinkFromBottle) ~= "table" or type(ISDrinkFromBottle.new) ~= "function" then
            created, timedAction = false, "native bottle-drink action is unavailable"
        else
            created, timedAction = pcall(ISDrinkFromBottle.new, ISDrinkFromBottle,
                actor, item, math.max(1, math.floor(tonumber(intent.uses) or 1)))
        end
    elseif action == "drink_source" then
        if type(ISTakeWaterAction) ~= "table" or type(ISTakeWaterAction.new) ~= "function"
            or intent.object == nil then
            created, timedAction = false, "native water-source action is unavailable"
        else
            local taintedOk, tainted = invoke(intent.object, "isTaintedWater")
            created, timedAction = pcall(ISTakeWaterAction.new, ISTakeWaterAction,
                actor, nil, intent.object, taintedOk and tainted == true)
        end
    end
    if not created or timedAction == nil then
        restoreNeedsItem(actor, { item = item, originalContainer = originalContainer })
        return false, created and "needs action was not created" or tostring(timedAction)
    end
    local kind = action == "eat_food" and "eat" or "drink"
    local queued, reason = queueNeedsAction(actor, kind, timedAction, item, originalContainer)
    if not queued then
        restoreNeedsItem(actor, { item = item, originalContainer = originalContainer })
        return false, reason
    end
    return true, reason
end

local function handSignal(actor, intent, provider)
    local requestedEmote = intent.emote or "freeze"
    local emote = emoteAliases[requestedEmote] or requestedEmote
    if humanEmotes[requestedEmote] ~= true then return false, "unsupported human emote" end
    local handled, reason = useProvider(provider, "emote", actor, emote, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    local lowered, lowerReason = setWeaponReady(actor, false)
    if not lowered then return false, lowerReason end
    local played, failure = invoke(actor, "playEmote", emote)
    if not played then return false, failure end
    return true, "hand_signal_started"
end

local function workActionIsActive(actor, record)
    return trackedActionIsActive(actor, record)
end

local function restoreWorkInventory(actor, record)
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "actor inventory is unavailable" end

    -- Clear the temporary build equipment before returning surviving items to
    -- their source container. Consumed plank/nail objects have no container and
    -- are deliberately ignored.
    invoke(actor, "setPrimaryHandItem", nil)
    invoke(actor, "setSecondaryHandItem", nil)
    local restoredAll = true
    for index = #(record.moved or {}), 1, -1 do
        local transfer = record.moved[index]
        local containerOk, current = invoke(transfer.item, "getContainer")
        if containerOk and current == inventory and transfer.container ~= nil then
            local removedOk, removed = invoke(inventory, "Remove", transfer.item)
            if removedOk and removed ~= false then
                local addedOk, added = invoke(transfer.container, "AddItem", transfer.item)
                local currentOk, after = invoke(transfer.item, "getContainer")
                if not addedOk or added == false or not currentOk or after ~= transfer.container then
                    invoke(transfer.container, "Remove", transfer.item)
                    invoke(inventory, "AddItem", transfer.item)
                    restoredAll = false
                end
            else
                restoredAll = false
            end
        end
    end

    local function restoreHand(setter, known, item)
        if not known then return true end
        if item == nil then
            local setOk = invoke(actor, setter, nil)
            return setOk
        end
        local containerOk, container = invoke(item, "getContainer")
        if not containerOk or container == nil then return true end
        local setOk = invoke(actor, setter, item)
        if not setOk then return false end
        local getter = setter == "setPrimaryHandItem" and "getPrimaryHandItem"
            or "getSecondaryHandItem"
        local verifyOk, equipped = invoke(actor, getter)
        return verifyOk and equipped == item
    end
    local primary = restoreHand("setPrimaryHandItem", record.oldPrimaryOk, record.oldPrimary)
    local secondary = restoreHand("setSecondaryHandItem", record.oldSecondaryOk, record.oldSecondary)
    return restoredAll and primary and secondary,
        restoredAll and primary and secondary and "work_inventory_restored"
        or "previous hand equipment could not be restored"
end

local function workTag(name)
    local itemTag = type(_G) == "table" and rawget(_G, "ItemTag") or nil
    local ok, value = pcall(function()
        if itemTag == nil then return nil end
        if name == "REMOVE_BARRICADE" then return itemTag.REMOVE_BARRICADE end
        if name == "SAW" then return itemTag.SAW end
        if name == "SCREWDRIVER" then return itemTag.SCREWDRIVER end
        return nil
    end)
    return ok and value or nil
end

local function prepareWorkInventory(actor, items, primary, secondary)
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return nil, "actor inventory is unavailable" end
    local oldPrimaryOk, oldPrimary = invoke(actor, "getPrimaryHandItem")
    local oldSecondaryOk, oldSecondary = invoke(actor, "getSecondaryHandItem")
    local record = {
        oldPrimaryOk = oldPrimaryOk,
        oldPrimary = oldPrimary,
        oldSecondaryOk = oldSecondaryOk,
        oldSecondary = oldSecondary,
        moved = {},
    }
    for _, item in ipairs(items or {}) do
        local moved, sourceOrReason = moveItemToRoot(actor, item)
        if not moved then
            restoreWorkInventory(actor, record)
            return nil, sourceOrReason
        end
        if sourceOrReason ~= nil then
            record.moved[#record.moved + 1] = { item = item, container = sourceOrReason }
        end
    end
    if primary ~= nil and not invoke(actor, "setPrimaryHandItem", primary) then
        restoreWorkInventory(actor, record)
        return nil, "work tool could not be equipped"
    end
    if secondary ~= nil and not invoke(actor, "setSecondaryHandItem", secondary) then
        restoreWorkInventory(actor, record)
        return nil, "secondary work tool could not be equipped"
    end
    if primary ~= nil then
        local equippedOk, equipped = invoke(actor, "getPrimaryHandItem")
        if not equippedOk or equipped ~= primary then
            restoreWorkInventory(actor, record)
            return nil, "work tool equipment was not retained"
        end
    end
    return record
end

local function queueTrackedWork(actor, timedAction, record, kind)
    if type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function"
        or type(ISTimedActionQueue.add) ~= "function" then
        restoreWorkInventory(actor, record)
        return false, "native timed-action queue is unavailable"
    end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" or queue.current ~= nil or type(queue.queue) ~= "table"
        or #queue.queue ~= 0 then
        restoreWorkInventory(actor, record)
        return false, "actor already has a native timed action"
    end
    if timedAction == nil then
        restoreWorkInventory(actor, record)
        return false, tostring(kind) .. " action was not created"
    end
    if type(timedAction.isValid) == "function" then
        local validOk, valid = pcall(timedAction.isValid, timedAction)
        if not validOk or valid ~= true then
            restoreWorkInventory(actor, record)
            return false, tostring(kind) .. " action rejected its tools or target"
        end
    end
    local queued, failure = pcall(ISTimedActionQueue.add, timedAction)
    if not queued then
        restoreWorkInventory(actor, record)
        return false, tostring(failure)
    end
    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local retained = type(queue) == "table" and queue.current == timedAction
        and type(queue.queue) == "table" and queue.queue[1] == timedAction
    if not retained then
        removeRejectedVisual(queue, timedAction)
        restoreWorkInventory(actor, record)
        return false, "native " .. tostring(kind) .. " action did not enter the queue"
    end
    record.timedAction = timedAction
    record.kind = kind
    record.startedAt = nowMs()
    activeWork[actor] = record
    return true, tostring(kind) .. "_timed_action_started"
end

local function startRemoveBarricade(actor, intent, provider)
    if intent.object == nil then return false, "remove barricade intent has no object" end
    local handled, reason = useProvider(provider, "removeBarricade", actor, intent.object, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if type(ISUnbarricadeAction) ~= "table"
        or type(ISUnbarricadeAction.new) ~= "function" then
        return false, "native remove barricade action is unavailable"
    end
    local barricade, barricadeOk = invoke(intent.object, "getBarricadeForCharacter", actor)
    if not barricadeOk or barricade == nil then
        return false, "companion cannot reach the selected barricade side"
    end
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "actor inventory is unavailable" end
    local metalOk, metal = invoke(barricade, "isMetal")
    local barsOk, metalBars = invoke(barricade, "isMetalBar")
    local tool
    if (metalOk and metal == true) or (barsOk and metalBars == true) then
        local foundOk
        foundOk, tool = invoke(inventory, "getFirstTypeEvalRecurse", "BlowTorch", function(item)
            local usesOk, uses = invoke(item, "getCurrentUses")
            return usesOk and tonumber(uses) and tonumber(uses) >= 1
        end)
        if not foundOk or tool == nil then return false, "companion needs a fueled blowtorch" end
    else
        local removeTag = workTag("REMOVE_BARRICADE")
        if removeTag == nil then return false, "native remove barricade item tag is unavailable" end
        local foundOk
        foundOk, tool = invoke(inventory, "getFirstTagEvalRecurse", removeTag, function(item)
            local brokenOk, broken = invoke(item, "isBroken")
            return not brokenOk or broken ~= true
        end)
        if not foundOk or tool == nil then
            return false, "companion needs an unbroken pry or remove-barricade tool"
        end
    end
    local record, prepareReason = prepareWorkInventory(actor, { tool }, tool, nil)
    if not record then return false, prepareReason end
    local created, timedAction = pcall(
        ISUnbarricadeAction.new, ISUnbarricadeAction, actor, intent.object)
    if not created then
        restoreWorkInventory(actor, record)
        return false, tostring(timedAction)
    end
    return queueTrackedWork(actor, timedAction, record, "remove_barricade")
end

local function startDismantle(actor, intent, provider)
    if intent.object == nil then return false, "dismantle intent has no object" end
    local handled, reason = useProvider(provider, "dismantle", actor, intent.object, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if type(ISDismantleAction) ~= "table" or type(ISDismantleAction.new) ~= "function" then
        return false, "native dismantle action is unavailable"
    end
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "actor inventory is unavailable" end
    local sawTag, screwdriverTag = workTag("SAW"), workTag("SCREWDRIVER")
    if sawTag == nil or screwdriverTag == nil then
        return false, "native dismantle item tags are unavailable"
    end
    local function notBroken(item)
        local brokenOk, broken = invoke(item, "isBroken")
        return not brokenOk or broken ~= true
    end
    local sawOk, saw = invoke(inventory, "getFirstTagEvalRecurse", sawTag, notBroken)
    local driverOk, screwdriver = invoke(
        inventory, "getFirstTagEvalRecurse", screwdriverTag, notBroken)
    if not sawOk or saw == nil then return false, "companion needs an unbroken saw" end
    if not driverOk or screwdriver == nil then
        return false, "companion needs an unbroken screwdriver"
    end
    local record, prepareReason = prepareWorkInventory(actor, { saw, screwdriver }, nil, nil)
    if not record then return false, prepareReason end
    local created, timedAction = pcall(
        ISDismantleAction.new, ISDismantleAction, actor, intent.object)
    if not created then
        restoreWorkInventory(actor, record)
        return false, tostring(timedAction)
    end
    return queueTrackedWork(actor, timedAction, record, "dismantle")
end

local function startBarricade(actor, intent, provider)
    if intent.object == nil then return false, "barricade intent has no object" end
    local handled, reason = useProvider(provider, "barricade", actor, intent.object, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if type(ISBarricadeAction) ~= "table" or type(ISBarricadeAction.new) ~= "function"
        or type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function"
        or type(ISTimedActionQueue.add) ~= "function" then
        return false, "native barricade action is unavailable"
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" or queue.current ~= nil or type(queue.queue) ~= "table"
        or #queue.queue ~= 0 then
        return false, "actor already has a native timed action"
    end
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "actor inventory is unavailable" end
    local itemTag = type(_G) == "table" and rawget(_G, "ItemTag") or nil
    local tagOk, hammerTag = pcall(function() return itemTag and itemTag.HAMMER or nil end)
    if not tagOk then hammerTag = nil end
    if hammerTag == nil then return false, "native hammer item tag is unavailable" end
    local function notBroken(item)
        local ok, broken = invoke(item, "isBroken")
        return not ok or broken ~= true
    end
    local hammerOk, hammer = invoke(inventory, "getFirstTagEvalRecurse", hammerTag, notBroken)
    local plankOk, plank = invoke(inventory, "getFirstTypeRecurse", "Plank")
    local nailsOk, nails = invoke(inventory, "getSomeTypeRecurse", "Nails", 2)
    if not hammerOk or hammer == nil then return false, "companion needs an unbroken hammer" end
    if not plankOk or plank == nil then return false, "companion needs one plank" end
    if not nailsOk or nativeListSize(nails) < 2 then return false, "companion needs two nails" end
    if SC.PersonalItems and (SC.PersonalItems.isProtected(hammer, actor, "build_material")
        or SC.PersonalItems.isProtected(plank, actor, "build_material")
        or SC.PersonalItems.isProtected(nativeListGet(nails, 0), actor, "build_material")
        or SC.PersonalItems.isProtected(nativeListGet(nails, 1), actor, "build_material")) then
        return false, "personal item cannot be consumed as building material"
    end

    local oldPrimaryOk, oldPrimary = invoke(actor, "getPrimaryHandItem")
    local oldSecondaryOk, oldSecondary = invoke(actor, "getSecondaryHandItem")
    local moved = {}
    local function ensureRoot(item)
        local containerOk, container = invoke(item, "getContainer")
        if containerOk and container == inventory then return true end
        if not containerOk or container == nil then return false end
        local removed = invoke(container, "Remove", item)
        if not removed then return false end
        local added = invoke(inventory, "AddItem", item)
        local currentOk, current = invoke(item, "getContainer")
        if not added or not currentOk or current ~= inventory then
            invoke(inventory, "Remove", item)
            invoke(container, "AddItem", item)
            return false
        end
        moved[#moved + 1] = { item = item, container = container }
        return true
    end
    local function rollback()
        if oldPrimaryOk then invoke(actor, "setPrimaryHandItem", oldPrimary) end
        if oldSecondaryOk then invoke(actor, "setSecondaryHandItem", oldSecondary) end
        for index = #moved, 1, -1 do
            local transfer = moved[index]
            invoke(inventory, "Remove", transfer.item)
            invoke(transfer.container, "AddItem", transfer.item)
        end
    end
    if not ensureRoot(hammer) or not ensureRoot(plank) then
        rollback()
        return false, "barricade tools could not be moved into the main inventory"
    end
    for index = 0, 1 do
        if not ensureRoot(nativeListGet(nails, index)) then
            rollback()
            return false, "barricade nails could not be moved into the main inventory"
        end
    end
    if not invoke(actor, "setPrimaryHandItem", hammer)
        or not invoke(actor, "setSecondaryHandItem", plank) then
        rollback()
        return false, "barricade tools could not be equipped"
    end
    local primaryOk, primary = invoke(actor, "getPrimaryHandItem")
    local secondaryOk, secondary = invoke(actor, "getSecondaryHandItem")
    if not primaryOk or primary ~= hammer or not secondaryOk or secondary ~= plank then
        rollback()
        return false, "barricade equipment state was not retained"
    end

    local created, timedAction = pcall(
        ISBarricadeAction.new, ISBarricadeAction, actor, intent.object, false, false)
    if not created or timedAction == nil then
        rollback()
        return false, created and "barricade action was not created" or tostring(timedAction)
    end
    local validOk, valid = pcall(timedAction.isValid, timedAction)
    if not validOk or valid ~= true then
        rollback()
        return false, validOk and "barricade action rejected its materials or target" or tostring(valid)
    end
    local queued, failure = pcall(ISTimedActionQueue.add, timedAction)
    if not queued then
        rollback()
        return false, tostring(failure)
    end
    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local retained = type(queue) == "table" and queue.current == timedAction
        and type(queue.queue) == "table" and queue.queue[1] == timedAction
    if not retained then
        removeRejectedVisual(queue, timedAction)
        rollback()
        return false, "native barricade action did not enter the queue"
    end
    activeWork[actor] = {
        timedAction = timedAction,
        oldPrimaryOk = oldPrimaryOk,
        oldPrimary = oldPrimary,
        oldSecondaryOk = oldSecondaryOk,
        oldSecondary = oldSecondary,
        moved = moved,
    }
    return true, "barricade_timed_action_started"
end

local function roomSweep(actor, intent, provider)
    local handled, reason = useProvider(provider, "look", actor, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end

    local ready, readyReason = setWeaponReady(actor, intent.weaponReady == true,
        intent.targetSquare)
    if not ready then return false, readyReason end

    local x, y = position(actor)
    if x == nil then return false, "actor position is unavailable for room sweep" end
    local forwardX, forwardY = tonumber(intent.sweepForwardX), tonumber(intent.sweepForwardY)
    local forwardXOk, forwardYOk = finite(forwardX), finite(forwardY)
    if not forwardXOk or not forwardYOk then
        forwardXOk, forwardX = invoke(actor, "getForwardDirectionX")
        forwardYOk, forwardY = invoke(actor, "getForwardDirectionY")
    end
    if not forwardXOk or not forwardYOk or not finite(forwardX) or not finite(forwardY)
        or (forwardX * forwardX + forwardY * forwardY) < 0.000001 then
        forwardX, forwardY = 1, 0
    end
    local side = intent.sweepSide == "right" and -1 or 1
    local lookX, lookY = -forwardY * side, forwardX * side
    local requested, turningRequested = invoke(actor, "faceLocationF", x + lookX * 2, y + lookY * 2)
    if not requested or turningRequested ~= true then
        return false, "native room-check facing request was rejected"
    end

    local turningOk, turning = invoke(actor, "isTurning")
    local afterXOk, afterX = invoke(actor, "getForwardDirectionX")
    local afterYOk, afterY = invoke(actor, "getForwardDirectionY")
    local facing = afterXOk and afterYOk and finite(afterX) and finite(afterY)
        and (afterX * lookX + afterY * lookY) >= 0.75
    if (not turningOk or turning ~= true) and not facing then
        return false, "native room-check facing did not start"
    end
    return true, "room_sweep_facing_started"
end

local function faceTarget(actor, intent, provider, successReason)
    local handled, reason = useProvider(provider, "look", actor, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    local target = intent.targetPosition or intent.targetSquare or intent
    local x, y = position(target)
    if x == nil then return false, "alert facing target is unavailable" end
    if intent.targetSquare ~= nil and intent.targetPosition == nil then x, y = x + 0.5, y + 0.5 end
    if intent.weaponReady ~= nil then
        local ready, readyReason = setWeaponReady(actor, intent.weaponReady == true, target)
        if not ready then return false, readyReason end
    end
    local requested, turningRequested = invoke(actor, "faceLocationF", x, y)
    if not requested or turningRequested ~= true then
        return false, "native alert facing request was rejected"
    end
    local actorX, actorY = position(actor)
    if actorX == nil then return false, "actor position is unavailable for alert facing" end
    local forwardXOk, forwardX = invoke(actor, "getForwardDirectionX")
    local forwardYOk, forwardY = invoke(actor, "getForwardDirectionY")
    local dx, dy = x - actorX, y - actorY
    local length = math.sqrt(dx * dx + dy * dy)
    local facing = length <= 0.001 or (forwardXOk and forwardYOk
        and finite(forwardX) and finite(forwardY)
        and (forwardX * dx + forwardY * dy) / length >= 0.75)
    local turningOk, turning = invoke(actor, "isTurning")
    if (not turningOk or turning ~= true) and not facing then
        return false, "native alert facing did not start"
    end
    return true, successReason or "facing_started"
end

local function syncPlayerPosture(actor, intent)
    local sneaking = intent.sneaking == true
    local stopped = actions.stopDirect(actor, { preservePosture = true })
    if stopped ~= true then return false, "copy_posture_stop_rejected" end
    local checked, actual = invoke(actor, "isSneaking")
    if not checked or actual ~= sneaking then
        local setOk, setResult = invoke(actor, "setSneaking", sneaking)
        if not setOk or setResult == false then return false, "copy_posture_rejected" end
        checked, actual = invoke(actor, "isSneaking")
    end
    if checked and actual ~= sneaking then return false, "copy_posture_not_verified" end
    return true, sneaking and "copy_posture_crouched" or "copy_posture_standing"
end

local function conversationPose(actor, intent, provider)
    local faced, facingReason = faceTarget(actor, intent, provider, "conversation_facing_started")
    if not faced then return false, facingReason end
    if type(intent.emote) ~= "string" or intent.emote == "" then
        return true, facingReason
    end
    local gestured, gestureReason = handSignal(actor, intent, provider)
    if not gestured then return false, gestureReason end
    return true, "conversation_pose_started"
end

local function equip(actor, intent, provider)
    if intent.item == nil then
        return false, "equip intent has no item"
    end
    local handled, reason = useProvider(provider, "equip", actor, intent.item, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end
    local oldPrimaryOk, oldPrimary = invoke(actor, "getPrimaryHandItem")
    local oldSecondaryOk, oldSecondary = invoke(actor, "getSecondaryHandItem")
    local assigned, assignReason = invoke(actor, "setPrimaryHandItem", intent.item)
    if not assigned then
        return false, assignReason
    end
    local twoHandedOk, twoHanded = invoke(intent.item, "isTwoHandWeapon")
    if twoHandedOk and twoHanded == true then
        local secondaryAssigned, secondaryReason = invoke(actor, "setSecondaryHandItem", intent.item)
        if not secondaryAssigned then
            if oldPrimaryOk then invoke(actor, "setPrimaryHandItem", oldPrimary) end
            if oldSecondaryOk then invoke(actor, "setSecondaryHandItem", oldSecondary) end
            return false, secondaryReason
        end
    elseif oldSecondaryOk and oldSecondary == intent.item then
        invoke(actor, "setSecondaryHandItem", nil)
    end
    local verified, equipped = invoke(actor, "getPrimaryHandItem")
    if not verified or equipped ~= intent.item then
        if oldPrimaryOk then invoke(actor, "setPrimaryHandItem", oldPrimary) end
        if oldSecondaryOk then invoke(actor, "setSecondaryHandItem", oldSecondary) end
        return false, "native equip did not retain the requested item"
    end
    if twoHandedOk and twoHanded == true then
        local secondaryVerified, secondary = invoke(actor, "getSecondaryHandItem")
        if not secondaryVerified or secondary ~= intent.item then
            if oldPrimaryOk then invoke(actor, "setPrimaryHandItem", oldPrimary) end
            if oldSecondaryOk then invoke(actor, "setSecondaryHandItem", oldSecondary) end
            return false, "native two-handed equip did not retain the secondary hand"
        end
    end
    return true, "equipped"
end

-- Land a companion stomp's damage exactly once, only after the native swing has
-- started (see attack()). Build 42's floor attack builds an empty hit list for a
-- non-local companion, so the engine never lands a downed-target stomp; this is
-- the sole damage owner for a companion stomp (the Java collision driver applies
-- nothing for the empty floor-attack list). A downed head stomp is lethal, an
-- off-head stomp only wounds -- positioning (getHeadSquare) decides which.
local function applyStompFinisher(actor, target)
    local _, prone = invoke(target, "isProne")
    local _, onFloor = invoke(target, "isOnFloor")
    local _, crawling = invoke(target, "isCrawling")
    local _, dead = invoke(target, "isDead")
    if not (prone == true or onFloor == true or crawling == true) or dead == true then
        return
    end
    local atHead = true
    local okHead, headSquare = invoke(target, "getHeadSquare", actor)
    local okMine, mySquare = invoke(actor, "getCurrentSquare")
    if okHead and headSquare ~= nil and okMine and mySquare ~= nil then
        local okDist, dist = invoke(mySquare, "DistTo", headSquare)
        atHead = okDist and type(dist) == "number" and dist <= 1.5
    end
    local _, held = invoke(actor, "getPrimaryHandItem")
    if atHead then
        -- Lethal head stomp: register the head strike the engine counts and
        -- finish a downed zombie whose remaining health the blow exceeds.
        local _, count = invoke(target, "getHitHeadWhileOnFloor")
        pcall(function() target:setHitHeadWhileOnFloor(
            (type(count) == "number" and count or 0) + 1) end)
        local damage = (SC.GameplayUtil and SC.GameplayUtil.config("combatHeadStompDamage")) or 3.0
        pcall(function() target:Hit(held, actor, damage, true, 1.0) end)
        local okHp, hp = invoke(target, "getHealth")
        if okHp and type(hp) == "number" and hp <= damage then
            pcall(function() target:setHealth(0) end)
        end
    else
        -- Off the head: a body/leg stomp only wounds and keeps it pinned.
        local damage = (SC.GameplayUtil and SC.GameplayUtil.config("combatStompDamage")) or 1.6
        pcall(function() target:Hit(held, actor, damage, true, 1.0) end)
    end
    -- Once the target is down for good, drop the downed-target reference so a
    -- stale corpse is not carried into the next native update.
    local _, nowDead = invoke(target, "isDead")
    if nowDead == true then
        pcall(function() actor.targetOnGround = nil end)
    end
end

local function attack(actor, action, intent, provider)
    local target = intent.target
    if target == nil then
        return false, "attack intent has no target"
    end
    local handled, reason = useProvider(provider, "attack", actor, action, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end

    local activeOk, alreadyActive = invoke(actor, "isAttackStarted")
    if activeOk and alreadyActive == true then
        return false, "native attack is already active"
    end

    local vehicleOk, vehicle = invoke(actor, "getVehicle")
    if vehicleOk and vehicle ~= nil then
        if action ~= "attack_firearm" then
            return false, "native melee attacks are disabled inside vehicles"
        end
        if intent.vehicleFireChecked ~= true then
            if not SC.Vehicle or type(SC.Vehicle.canPassengerFire) ~= "function" then
                return false, "vehicle fire adapter is unavailable"
            end
            local ready, vehicleReason = SC.Vehicle.canPassengerFire(
                actor, target, intent.combatDoctrine)
            if not ready then return false, vehicleReason end
        end
    end

    local tx, ty = position(target)
    if tx == nil then
        return false, "attack target position is unavailable"
    end
    local faceOk, faced = invoke(actor, "faceLocationF", tx, ty)
    if not faceOk or faced ~= true then
        return false, "actor could not face the attack target"
    end
    -- faceLocationF only sets the coarse sprite facing. Ask the native actor to
    -- keep its precise forward direction (which CombatManager's hit arc reads)
    -- pointed at the target every frame through the swing, like a player's mouse
    -- aim; the ordinary per-frame update otherwise resets it and the swing misses.
    invoke(actor, "setCompanionAimTarget", target)
    if intent.weapon ~= nil then
        local equipped, equipReason = equip(actor, { item = intent.weapon }, provider)
        if not equipped then
            return false, equipReason
        end
    end
    invoke(actor, "setAimAtFloor", action == "stomp")
    if action == "stomp" and intent.target ~= nil then
        -- Point the native floor attack at the downed target (it builds its hit
        -- list from targetOnGround). The finisher's damage is NOT applied here --
        -- it is landed once, below, only after the swing has actually started, so
        -- a rejected or retried preflight can never damage the target.
        pcall(function() actor.targetOnGround = intent.target end)
    end
    local shoveStateOk, previousDoShove = invoke(actor, "isDoShove")
    if not shoveStateOk then
        return false, "native shove action state is unavailable"
    end
    local grappleStateOk, previousDoGrapple = invoke(actor, "isDoGrapple")
    if not grappleStateOk then
        return false, "native grapple action state is unavailable"
    end
    local shoveStateSet = invoke(actor, "setDoShove",
        action == "shove" or action == "stomp")
    local grappleStateSet = invoke(actor, "setDoGrapple", false)
    if not shoveStateSet or not grappleStateSet then
        invoke(actor, "setDoShove", previousDoShove == true)
        invoke(actor, "setDoGrapple", previousDoGrapple == true)
        return false, "native hand-to-hand action state could not be selected"
    end
    local function restoreActionState()
        invoke(actor, "setDoShove", previousDoShove == true)
        invoke(actor, "setDoGrapple", previousDoGrapple == true)
    end
    if action == "attack_firearm" or action == "attack_melee" then
        -- Firearms aim; a melee swing must not. Build 42's local player clears
        -- aiming before a hand-weapon swing, and leaving it set keeps the
        -- player action graph in the aiming/turning stance instead of entering
        -- the swipe state, so the swing animation and its hit never run.
        local aimOk = invoke(actor, "setIsAiming", action == "attack_firearm")
        if not aimOk then
            restoreActionState()
            return false, "native weapon-ready state could not be requested"
        end
    end

    -- Build 42 does not make DoAttack() perform the normal player preflight.
    -- CanAttack() initializes useHandWeapon and verifies the freshly equipped
    -- hand model, current action state, condition and endurance. An equip can
    -- be visible one frame before that model is attack-ready, so refuse this
    -- pulse and let Combat retry rather than reporting a phantom swing.
    local readyOk, ready = invoke(actor, "CanAttack")
    if not readyOk then
        restoreActionState()
        return false, "native CanAttack preflight is unavailable"
    end
    if ready ~= true then
        restoreActionState()
        return false, "native weapon is not attack-ready"
    end

    local meleeAuthOk, previousMeleeAuth = invoke(actor,
        "isAuthorizedHandToHandAction")
    if not meleeAuthOk then
        restoreActionState()
        return false, "native melee-action authorization state is unavailable"
    end
    local shoveAuthOk, previousShoveAuth = invoke(actor,
        "isAuthorizedHandToHand")
    if not shoveAuthOk then
        restoreActionState()
        return false, "native shove authorization state is unavailable"
    end
    local authorized = invoke(actor, "setAuthorizedHandToHandAction", true)
    if not authorized then
        restoreActionState()
        return false, "native melee-action authorization could not be enabled"
    end
    -- Authorize the hand-to-hand (shove) path only for an explicitly selected
    -- shove/stomp. Build 42's CombatManager converts an authorized weapon attack
    -- into a defensive shove, which moves the target but deals no damage, so a
    -- companion "swings but never lands" even at a clean range while facing the
    -- target. A weapon swing must not authorize hand-to-hand.
    local wantsHandToHand = action == "shove" or action == "stomp"
    local shoveAuthorized = invoke(actor, "setAuthorizedHandToHand", wantsHandToHand)
    if not shoveAuthorized then
        invoke(actor, "setAuthorizedHandToHandAction", previousMeleeAuth == true)
        restoreActionState()
        return false, "native shove authorization could not be updated"
    end
    local function restoreAuthorization()
        invoke(actor, "setAuthorizedHandToHandAction", previousMeleeAuth == true)
        invoke(actor, "setAuthorizedHandToHand", previousShoveAuth == true)
    end
    local attackType = type(_G) == "table" and rawget(_G, "AttackType") or nil
    local attackTypeName = action == "attack_firearm" and "SHOT"
        or action == "attack_melee" and "MELEE_SWING"
        or action == "shove" and "SHOVE"
        or action == "stomp" and "STOMP" or nil
    local selected
    if attackType ~= nil and attackTypeName ~= nil then
        local selectedOk, value = pcall(function() return attackType[attackTypeName] end)
        if selectedOk then selected = value end
    end
    if selected == nil then
        restoreAuthorization()
        restoreActionState()
        return false, "native AttackType is unavailable for " .. action
    end
    local typeOk = invoke(actor, "setAttackType", selected)
    if not typeOk then
        restoreAuthorization()
        restoreActionState()
        return false, "native attack type could not be selected"
    end
    local started, result = invoke(actor, "DoAttack", 0)
    restoreAuthorization()
    local stateOk, attackStarted = invoke(actor, "isAttackStarted")
    -- Build 42's IsoPlayer.DoAttack deliberately returns false after handing
    -- the request to CombatManager.  The authoritative success signal is the
    -- native attack-started state set by CombatManager.pressedAttack.
    if not started or not stateOk or attackStarted ~= true then
        restoreActionState()
        return false, "native attack did not start"
    end
    -- Do not restore doShove/aimAtFloor after success. CombatManager copied
    -- the calculated attack variables back to the player and the animation
    -- state owns them until clearHandToHandAttack(). The next requested attack
    -- explicitly selects its own state before starting.
    if action == "stomp" and intent.target ~= nil then
        -- The swing has started; land the finisher's single hit now.
        applyStompFinisher(actor, intent.target)
    end
    return true, "attack_started"
end

local function reload(actor, intent, provider)
    local weapon = intent.weapon
    if weapon == nil then
        return false, "reload intent has no weapon"
    end
    local handled, reason = useProvider(provider, "reload", actor, weapon, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end
    if type(ISReloadWeaponAction) ~= "table"
        or type(ISReloadWeaponAction.BeginAutomaticReload) ~= "function"
        or type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function" then
        return false, "native reload action is unavailable"
    end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local before = queue and queue.queue and #queue.queue or 0
    local ok, failure = pcall(ISReloadWeaponAction.BeginAutomaticReload, actor, weapon)
    if not ok then
        return false, tostring(failure)
    end
    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local after = queue and queue.queue and #queue.queue or 0
    if after <= before or queue.current == nil then
        return false, "native reload action did not enter the queue"
    end
    return true, "reload_started"
end

-- Clear a jammed firearm by racking it, the same ISRackFirearm timed action the
-- radial menu queues for the player; ISRackFirearm.rackBullet clears the jam.
local function unjam(actor, intent, provider)
    local weapon = intent.weapon
    if weapon == nil then
        return false, "unjam intent has no weapon"
    end
    local handled, reason = useProvider(provider, "unjam", actor, weapon, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end
    if type(ISRackFirearm) ~= "table" or type(ISRackFirearm.new) ~= "function"
        or type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.add) ~= "function"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function" then
        return false, "native rack action is unavailable"
    end
    if type(ISReloadWeaponAction) == "table"
        and type(ISReloadWeaponAction.canRack) == "function" then
        local okRack, canRack = pcall(ISReloadWeaponAction.canRack, weapon)
        if okRack and canRack ~= true then return false, "weapon cannot be racked" end
    end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local before = queue and queue.queue and #queue.queue or 0
    local action = ISRackFirearm:new(actor, weapon)
    local ok, failure = pcall(ISTimedActionQueue.add, action)
    if not ok then
        return false, tostring(failure)
    end
    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    local after = queue and queue.queue and #queue.queue or 0
    if after <= before or queue.current == nil then
        return false, "native rack action did not enter the queue"
    end
    return true, "unjam_started"
end

local function windowAction(actor, action, intent, provider)
    local object = intent.object
    if object == nil then
        return false, "window action has no object"
    end
    local handled, reason = useProvider(provider, "window", actor, action, object, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end

    if action == "open_window" then
        local started, failure = invoke(actor, "openWindow", object)
        if not started then
            return false, failure
        end
        local verified, opened = invoke(object, "IsOpen")
        if not verified or opened ~= true then
            return false, "window open was not verified"
        end
        return true, "window_opened"
    elseif action == "smash_window" then
        local started, failure = invoke(actor, "smashWindow", object)
        if not started then
            return false, failure
        end
        local verified, smashed = invoke(object, "isSmashed")
        if not verified or smashed ~= true then
            return false, "window smash was not verified"
        end
        return true, "window_smashed"
    elseif action == "remove_glass" then
        local started, failure = invoke(object, "removeBrokenGlass")
        if not started then
            return false, failure
        end
        local verified, removed = invoke(object, "isGlassRemoved")
        if not verified or removed ~= true then
            return false, "glass removal was not verified"
        end
        return true, "glass_removed"
    end

    local started, failure = invoke(actor, "climbThroughWindow", object)
    if not started then
        return false, failure
    end
    local climbingOk, climbing = invoke(actor, "isClimbing")
    if not climbingOk or climbing ~= true then
        return false, "native window climb did not start"
    end
    return true, "window_climb_started"
end

local function setDowned(actor, downed, provider)
    local handled, reason = useProvider(provider, "setDowned", actor, downed)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end
    if downed then
        actions.stopDirect(actor)
    end
    local setOk, failure = invoke(actor, "setKnockedDown", downed)
    if not setOk then
        return false, failure
    end
    local checkOk, current = invoke(actor, "isKnockedDown")
    if not checkOk or current ~= downed then
        return false, "native downed state was not retained"
    end
    return true, downed and "downed" or "recovered"
end

function actions.stopDirect(actor, options)
    options = type(options) == "table" and options or {}
    local behaviorOk, behavior = invoke(actor, "getPathFindBehavior2")
    if behaviorOk and behavior ~= nil then invoke(behavior, "cancel") end
    invoke(actor, "setMoving", false)
    invoke(actor, "setRunning", false)
    invoke(actor, "setSprinting", false)
    if options.preservePosture ~= true then invoke(actor, "setSneaking", false) end
    setTacticalMovement(actor, false, 0, 0)
    setWeaponReady(actor, false)
    local ok, moving = invoke(actor, "isMoving")
    return not ok or moving ~= true
end

function actions.isWorkActive(actor)
    local record = actor and activeWork[actor] or nil
    return record ~= nil and workActionIsActive(actor, record)
end

function actions.finishWork(actor)
    local record = actor and activeWork[actor] or nil
    if not record then return true, "no_tracked_work" end
    if workActionIsActive(actor, record) then return false, "work_action_still_active" end
    local restored, reason = restoreWorkInventory(actor, record)
    if restored then
        activeWork[actor] = nil
        actions.noteResult(actor, record.kind or "work", "completed", { kind = "long" })
    end
    return restored, reason
end

function actions.cancelWork(actor, reason)
    local record = actor and activeWork[actor] or nil
    if not record then return true, reason or "no_tracked_work" end
    if workActionIsActive(actor, record) then
        -- Cancel only the Living Fellows work action, never the whole queue: a
        -- broad ISTimedActionQueue.clear(actor) would also drop an unrelated
        -- third-party action queued on the companion.
        if type(ISTimedActionQueue) ~= "table"
            or type(ISTimedActionQueue.getTimedActionQueue) ~= "function" then
            return false, "native timed-action cancellation is unavailable"
        end
        local queue = ISTimedActionQueue.getTimedActionQueue(actor)
        cancelOwnedTimedAction(queue, record.timedAction)
        if workActionIsActive(actor, record) then
            return false, "native work action remained queued after cancellation"
        end
    end
    local restored, restoreReason = restoreWorkInventory(actor, record)
    if not restored then return false, restoreReason end
    activeWork[actor] = nil
    return true, reason or "work_cancelled"
end

function actions.resetWork(actor)
    if actor ~= nil then activeWork[actor] = nil
    else activeWork = setmetatable({}, { __mode = "k" }) end
end

function actions.visualStatus(actor, expectedAction)
    local record = actor and activeVisual[actor] or nil
    if type(record) ~= "table" then return "none" end
    if expectedAction ~= nil and record.actionName ~= expectedAction then
        return "different", record.actionName, record.startedAt
    end
    if trackedActionIsActive(actor, record) then
        return "active", record.actionName, record.startedAt
    end
    if record.timedAction.scCompleted == true then
        record.completedAt = record.completedAt or nowMs()
        return "completed", record.actionName, record.completedAt
    end
    if record.timedAction.scStopped == true then
        return "stopped", record.actionName, record.startedAt
    end
    return "interrupted", record.actionName, record.startedAt
end

-- One public ownership view covers every native activity that can legitimately
-- own a player animation.  Callers no longer need to guess whether a visual,
-- needs action, construction action, or an unfamiliar vanilla action is the
-- reason movement must wait.
function actions.activityStatus(actor)
    if actor == nil then return "none" end
    local visualState, visualName, visualAt = actions.visualStatus(actor)
    if visualState == "active" then
        return "active", "visual", visualName, visualAt
    elseif visualState == "completed" then
        return "result_pending", "visual", visualName, visualAt
    elseif visualState ~= "none" then
        return "interrupted", "visual", visualName, visualAt
    end

    local needs = activeNeeds[actor]
    if needs then
        if trackedActionIsActive(actor, needs) then
            return "active", "needs", needs.kind, needs.startedAt
        end
        return "result_pending", "needs", needs.kind, needs.startedAt
    end
    local work = activeWork[actor]
    if work then
        if workActionIsActive(actor, work) then
            return "active", "work", work.kind, work.startedAt
        end
        return "result_pending", "work", work.kind, work.startedAt
    end

    local utility = SC.GameplayUtil
    if type(utility) == "table" and type(utility.movementStateBlocker) == "function" then
        local blocker, object = utility.movementStateBlocker(actor)
        if blocker == "unfinished_action" or blocker == "action_animation_state" then
            return "active", "native", blocker, nil, object
        end
    end
    return "none"
end

local function pacingRange(kind)
    if kind == "short" then
        return tonumber(SC.Config.get("actionPacingShortMinMs")) or 350,
            tonumber(SC.Config.get("actionPacingShortMaxMs")) or 850
    elseif kind == "long" then
        return tonumber(SC.Config.get("actionPacingLongMinMs")) or 1000,
            tonumber(SC.Config.get("actionPacingLongMaxMs")) or 2400
    end
    return tonumber(SC.Config.get("actionPacingMinMs")) or 650,
        tonumber(SC.Config.get("actionPacingMaxMs")) or 1500
end

function actions.beginPacing(actor, source, options)
    if actor == nil then return false, "invalid_actor" end
    options = type(options) == "table" and options or {}
    if options.skip == true or options.chain == true or options.emergency == true then
        return false, "pacing_skipped"
    end
    local current = nowMs()
    local minimum, maximum = pacingRange(options.kind)
    minimum = math.max(0, tonumber(options.minimumMs) or minimum)
    maximum = math.max(minimum, tonumber(options.maximumMs) or maximum)
    local previous = resultHistory[actor]
    if previous and previous.source == source
        and current - (tonumber(previous.at) or 0)
            <= (tonumber(SC.Config.get("actionPacingRepeatWindowMs")) or 10000) then
        maximum = maximum + (tonumber(SC.Config.get("actionPacingRepeatBoostMs")) or 350)
    end
    pacingSequence = pacingSequence + 1
    local seed = stableHash(actorKey(actor) .. ":" .. tostring(source)
        .. ":" .. tostring(pacingSequence))
    local duration = minimum
    if maximum > minimum then duration = minimum + seed % math.floor(maximum - minimum + 1) end
    local lookChance = tonumber(options.lookChancePercent)
        or tonumber(SC.Config.get("actionPacingLookChancePercent")) or 42
    local lookDelay = tonumber(SC.Config.get("actionPacingLookDelayPercent")) or 45
    local record = {
        source = tostring(source or "activity"),
        result = options.result,
        startedAt = current,
        untilAt = current + duration,
        durationMs = duration,
        commandSerial = tonumber(options.commandSerial) or commandSerial(actor),
        lookDueAt = current + math.floor(duration * math.max(0, math.min(100, lookDelay)) / 100),
        shouldLook = seed % 100 < math.max(0, math.min(100, lookChance)),
        lookDirection = seed % 4,
        stopped = false,
    }
    pacingStates[actor] = record
    resultHistory[actor] = { source = record.source, result = options.result, at = current }
    return true, "pacing_started", record
end

function actions.noteResult(actor, source, result, options)
    options = type(options) == "table" and options or {}
    options.result = result
    return actions.beginPacing(actor, source, options)
end

function actions.pacingStatus(actor, current)
    local record = actor and pacingStates[actor] or nil
    if not record then return false, nil end
    current = tonumber(current) or nowMs()
    if current >= (tonumber(record.untilAt) or 0) then
        pacingStates[actor] = nil
        return false, nil
    end
    return true, record
end

function actions.cancelPacing(actor, reason)
    if actor == nil then return false, "invalid_actor" end
    local had = pacingStates[actor] ~= nil
    pacingStates[actor] = nil
    return had, reason or "pacing_cancelled"
end

function actions.peekPacing(actor)
    local active, record = actions.pacingStatus(actor)
    return active and record or nil
end

function actions.interruptOwnedActivity(actor, reason)
    local phase, owner = actions.activityStatus(actor)
    if phase == "none" then return true, reason or "no_owned_activity" end
    if owner == "visual" then return actions.cancelVisual(actor, reason) end
    if owner == "needs" then return actions.cancelNeeds(actor, reason) end
    if owner == "work" then return actions.cancelWork(actor, reason) end
    -- Never clear an unknown vanilla or third-party action. We did not acquire
    -- its resources and cannot safely invent its rollback contract.
    return false, "unowned_native_action_active"
end

function actions.clearVisual(actor)
    if actor ~= nil then activeVisual[actor] = nil
    else activeVisual = setmetatable({}, { __mode = "k" }) end
end

function actions.cancelVisual(actor, reason)
    local record = actor and activeVisual[actor] or nil
    if not record then return true, reason or "no_tracked_visual" end
    if trackedActionIsActive(actor, record) then
        local queue = type(ISTimedActionQueue) == "table"
            and type(ISTimedActionQueue.getTimedActionQueue) == "function"
            and ISTimedActionQueue.getTimedActionQueue(actor) or nil
        removeRejectedVisual(queue, record.timedAction)
        if trackedActionIsActive(actor, record) then
            return false, "native visual action remained queued after cancellation"
        end
    end
    -- forceStop does not reliably run the derived Lua stop callback on every
    -- Build 42 path. Clear the persistent read/model flags explicitly so the
    -- next idle/follow state cannot inherit the cancelled pose.
    if record.timedAction and record.timedAction.reading == true then
        invoke(actor, "setReading", false)
    end
    invoke(actor, "resetModelNextFrame")
    activeVisual[actor] = nil
    return true, reason or "visual_action_cancelled"
end

function actions.needsStatus(actor)
    local record = actor and activeNeeds[actor] or nil
    if not record then return false, nil end
    return trackedActionIsActive(actor, record), record.kind
end

function actions.finishNeeds(actor)
    local record = actor and activeNeeds[actor] or nil
    if not record then return true, "no_tracked_needs_action" end
    if trackedActionIsActive(actor, record) then return false, "needs_action_still_active" end
    local restored, reason = restoreNeedsItem(actor, record)
    if restored then
        activeNeeds[actor] = nil
        actions.noteResult(actor, record.kind or "needs", "completed", { kind = "short" })
    end
    return restored, reason
end

function actions.cancelNeeds(actor, reason)
    local record = actor and activeNeeds[actor] or nil
    if not record then return true, reason or "no_tracked_needs_action" end
    if trackedActionIsActive(actor, record) then
        if type(ISTimedActionQueue) ~= "table" or type(ISTimedActionQueue.clear) ~= "function" then
            return false, "native needs-action cancellation is unavailable"
        end
        local cleared, failure = pcall(ISTimedActionQueue.clear, actor)
        if not cleared then return false, tostring(failure) end
        if trackedActionIsActive(actor, record) then
            return false, "native needs action remained queued after cancellation"
        end
    end
    local restored, restoreReason = restoreNeedsItem(actor, record)
    if not restored then return false, restoreReason end
    activeNeeds[actor] = nil
    return true, reason or "needs_action_cancelled"
end

function actions.resetNeeds(actor)
    if actor ~= nil then activeNeeds[actor] = nil
    else activeNeeds = setmetatable({}, { __mode = "k" }) end
end

function actions.resetActivity(actor)
    if actor ~= nil then
        pacingStates[actor] = nil
        resultHistory[actor] = nil
    else
        pacingStates = setmetatable({}, { __mode = "k" })
        resultHistory = setmetatable({}, { __mode = "k" })
        pacingSequence = 0
    end
    return true
end

-- The crisis state machine is the sole caller.  It has already required a
-- confirmed outcome, a safety delay and explicit authorization.  The bridge
-- applies damage through the native BodyDamage model so vanilla owns death,
-- corpse creation and possible reanimation.
function actions.performEndOfLife(actor, outcome, target)
    if outcome ~= "mercy" and outcome ~= "self_sacrifice" then
        return false, "unauthorized_final_outcome"
    end
    target = target or actor
    if not SC.Actor or type(SC.Actor.endLife) ~= "function" then
        return false, "native_end_life_unavailable"
    end
    local current = nowMs()
    local record = activeFinal[actor]
    if not record or record.target ~= target or record.outcome ~= outcome then
        local utility = SC.GameplayUtil
        local weapon
        if utility then
            for _, item in ipairs(utility.inventoryItems(utility.inventory(actor), 128)) do
                local category = select(1, utility.call(item, "getCategory"))
                local range = tonumber(select(1, utility.call(item, "getMaxRange"))) or 0
                local ammo, ammoOk = utility.call(item, "getCurrentAmmoCount")
                local ready = range <= 2 or not ammoOk or (tonumber(ammo) or 0) > 0
                if tostring(category) == "Weapon" and ready then
                    if weapon == nil or range > (weapon.range or -1) then
                        weapon = { item = item, range = range }
                    end
                end
            end
        end
        if not weapon then return false, "final_action_requires_weapon" end
        local action = weapon.range > 2 and "attack_firearm" or "attack_melee"
        local started, reason = SC.Actor.setMovement(actor, "walk", {
            action = action, target = target, weapon = weapon.item,
            crisisAuthorized = true, finalOutcome = outcome,
        })
        if started ~= true then return false, reason or "final_attack_rejected" end
        activeFinal[actor] = { target = target, outcome = outcome, startedAt = current }
        return true, "native_final_attack_started"
    end
    if current - record.startedAt < 450 then return true, "native_final_attack_active" end
    local accepted, reason = SC.Actor.endLife(target)
    if accepted then activeFinal[actor] = nil end
    return accepted == true, accepted == true and "native_final_injury_applied" or reason
end

function actions.resetFinal(actor)
    if actor ~= nil then activeFinal[actor] = nil
    else activeFinal = setmetatable({}, { __mode = "k" }) end
end

function actions.dispatch(actor, mode, intent, provider)
    if actor == nil or type(intent) ~= "table" or type(provider) ~= "table" then
        return false, "actor, intent, and provider are required"
    end
    local normalized = normalizeMode(mode)
    if normalized == nil then
        return false, "unsupported movement mode: " .. tostring(mode)
    end
    local action = tostring(intent.action or "move")
    if #action > SC.Config.get("maxIntentLength") then
        return false, "intent action is too long"
    end
    local urgent = isUrgentAction(action, intent)

    local pacing, pace = actions.pacingStatus(actor)
    if pacing and intent.pacingObservation ~= true then
        if urgent then
            actions.cancelPacing(actor, "survival_priority")
        else
            actions.stopDirect(actor)
            return false, "action_pacing:" .. tostring(pace.source)
        end
    end

    local activityPhase, activityOwner, activityName, activityAt = actions.activityStatus(actor)
    if activityPhase == "result_pending" and activityOwner == "visual"
        and activityName ~= action and not urgent then
        local grace = tonumber(SC.Config.get("visualEffectClaimMs")) or 2000
        if nowMs() - (tonumber(activityAt) or 0) >= grace then
            actions.clearVisual(actor)
            activityPhase = "none"
        end
    end
    if activityPhase == "active" or activityPhase == "result_pending" then
        if activityName == action then
            return true, "activity_continues:" .. tostring(activityName)
        end
        if urgent then
            local interrupted, interruptReason = actions.interruptOwnedActivity(
                actor, "survival_priority:" .. action)
            if not interrupted then return false, interruptReason end
        else
            actions.stopDirect(actor)
            if activityOwner == "visual" then
                return false, (activityPhase == "active" and "visual_action_active:"
                    or "visual_effect_pending:") .. tostring(activityName)
            end
            if activityOwner == "native" then
                return false, "actor_state_busy:" .. tostring(activityName)
            end
            return false, "activity_" .. tostring(activityPhase) .. ":"
                .. tostring(activityOwner) .. ":" .. tostring(activityName)
        end
    end

    -- A visual timed action owns the actor's pose until vanilla has removed it
    -- from the native queue.  Without this gate, a follow/movement decision can
    -- advance the IsoPlayer while Loot/Bandage is still kneeling, producing the
    -- visible "kneeling moonwalk". Survival-critical actions may interrupt it;
    -- ordinary movement waits, and completed effects get a short claim window
    -- so the gameplay subsystem can commit its inventory/body transaction.
    if visualActionSpecs[action] == nil then
        local visualState, visualName, visualStartedAt = actions.visualStatus(actor)
        if visualState == "active" then
            if not urgent then
                return false, "visual_action_active:" .. tostring(visualName)
            end
            local cancelled, cancelReason = actions.cancelVisual(actor,
                "visual_interrupted_for_" .. action)
            if not cancelled then return false, cancelReason end
        elseif visualState == "completed" then
            local grace = tonumber(SC.Config.get("visualEffectClaimMs")) or 2000
            if not urgent and nowMs() - (tonumber(visualStartedAt) or 0) < grace then
                return false, "visual_effect_pending:" .. tostring(visualName)
            end
            actions.clearVisual(actor)
        elseif visualState ~= "none" then
            actions.clearVisual(actor)
        end
    end

    -- Reading, light repair and crafting may continue while seated. Every
    -- movement, combat, rescue, construction, window and vehicle action must
    -- first leave furniture or the engine can retain a seated animation/state.
    local seatedActivity = action == "read" or action == "repair" or action == "craft_supply"
    if action == "sit_ground" then
        local standing, standingReason = leaveFurniture(actor)
        if not standing then return false, standingReason end
    elseif action == "sit" and groundSeatState(actor) then
        local requested, standReason = requestGroundSeat(actor, false)
        if not requested then return false, standReason end
        return false, "standing_from_ground"
    elseif action ~= "stand_ground" and not seatedActivity then
        local standing, standingReason = leaveSeating(actor)
        if not standing then return false, standingReason end
    end

    if action == "sit_ground" then
        return requestGroundSeat(actor, true)
    elseif action == "stand_ground" then
        return requestGroundSeat(actor, false)
    elseif action == "equip_weapon" or action == "equip" then
        return equip(actor, intent, provider)
    elseif action == "reload" then
        return reload(actor, intent, provider)
    elseif action == "unjam" then
        return unjam(actor, intent, provider)
    elseif combatActions[action] then
        return attack(actor, action, intent, provider)
    elseif action == "backstep" or action == "lateral_kite" then
        intent.awayFrom = intent.awayFrom or intent.target
        intent.lateral = action == "lateral_kite"
        movementActions[action] = true
    elseif windowActions[action] then
        return windowAction(actor, action, intent, provider)
    elseif action == "board_vehicle" or action == "exit_vehicle" then
        if SC.Vehicle == nil then
            return false, "vehicle persistence adapter is unavailable"
        end
        local operation = action == "board_vehicle" and SC.Vehicle.board or SC.Vehicle.exit
        if type(operation) ~= "function" then
            return false, "vehicle operation is unavailable"
        end
        return operation(actor, intent.vehicle, intent.seat, intent)
    elseif action == "downed" then
        return setDowned(actor, true, provider)
    elseif action == "recover_from_downed" then
        return setDowned(actor, false, provider)
    elseif action == "sit" and intent.object ~= nil then
        local handled, reason = useProvider(provider, "sit", actor, intent.object, intent)
        if handled ~= nil then
            return handled, reason
        end
        if not provider.directNative then
            return false, reason
        end
        local setOk, failure = invoke(actor, "setSitOnFurnitureObject", intent.object)
        if not setOk then
            return false, failure
        end
        invoke(actor, "setSittingOnFurniture", true)
        local verifyOk, sitting = invoke(actor, "isSittingOnFurniture")
        return verifyOk and sitting == true, verifyOk and "sitting" or "native sitting state was not verified"
    elseif action == "barricade" then
        return startBarricade(actor, intent, provider)
    elseif action == "remove_barricade" then
        return startRemoveBarricade(actor, intent, provider)
    elseif action == "dismantle" then
        return startDismantle(actor, intent, provider)
    elseif action == "eat_food" or action == "drink_item" or action == "drink_source" then
        return startNeedsAction(actor, action, intent, provider)
    elseif action == "hand_signal" then
        return handSignal(actor, intent, provider)
    elseif action == "ready_weapon" then
        return setWeaponReady(actor, true,
            intent.facingTarget or intent.targetSquare or intent.targetPosition)
    elseif action == "lower_weapon" then
        return setWeaponReady(actor, false)
    elseif visualActionSpecs[action] then
        return startVerifiedVisual(actor, action, intent, provider)
    elseif action == "room_sweep" then
        return roomSweep(actor, intent, provider)
    elseif action == "face_alert" then
        return faceTarget(actor, intent, provider, "alert_facing_started")
    elseif action == "rear_scan" then
        return faceTarget(actor, intent, provider, "rear_scan_started")
    elseif action == "face_formation" then
        return faceTarget(actor, intent, provider, "formation_facing_restored")
    elseif action == "face_conversation" then
        return faceTarget(actor, intent, provider, "conversation_facing_started")
    elseif action == "conversation_pose" then
        return conversationPose(actor, intent, provider)
    elseif action == "copy_player_posture" then
        return syncPlayerPosture(actor, intent)
    end

    if not movementActions[action] and targetOf(intent) == nil
        and intent.dx == nil and intent.x == nil and intent.awayFrom == nil then
        return false, "unsupported actor intent: " .. action
    end

    -- A vanilla or third-party timed action may own the pose without being in
    -- activeVisual (the playtest exposed ISUnequipAction here). Never translate
    -- that pose. Navigation retries after the native action/state is clear.
    local utility = SC.GameplayUtil
    if type(utility) == "table" and type(utility.movementStateBlocker) == "function" then
        local blocker = utility.movementStateBlocker(actor)
        if blocker ~= nil then
            actions.stopDirect(actor)
            return false, "actor_state_busy:" .. tostring(blocker)
        end
    end

    local target = targetOf(intent)
    if intent.enginePath == true and target ~= nil then
        local handled, reason = useProvider(provider, "path", actor, target, normalized, intent)
        if handled ~= nil then
            return handled, reason
        end
        if not provider.directNative then
            return false, reason
        end
        return directPath(actor, target, normalized, intent)
    end

    local dx, dy, vectorReason = vectorFor(actor, intent)
    if dx == nil then
        return false, vectorReason
    end
    local handled, reason = useProvider(provider, "move", actor, normalized, dx, dy, intent)
    if handled ~= nil then
        return handled, reason
    end
    if not provider.directNative then
        return false, reason
    end
    return directMove(actor, normalized, dx, dy, intent)
end

function actions.normalizeMode(mode)
    return normalizeMode(mode)
end

function actions.leaveFurniture(actor)
    return leaveFurniture(actor)
end

function actions.leaveSeating(actor)
    return leaveSeating(actor)
end

return actions
