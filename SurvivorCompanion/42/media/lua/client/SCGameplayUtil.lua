-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCConfig")
    pcall(require, "SCNativeList")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.GameplayUtil = SC.GameplayUtil or {}
local U = SC.GameplayUtil


-- Gameplay code reads the canonical shared configuration. Keep this proxy
-- immutable and dynamic so development hot reloads retain one source of truth.
local readOnlyDefaults = {}
setmetatable(readOnlyDefaults, {
    __index = function(_, key)
        local config = SC.Config
        return type(config) == "table" and type(config.defaults) == "table"
            and config.defaults[key] or nil
    end,
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
-- A last-resort owner for an exact item whose native world removal succeeded
-- but whose destination and world reconstruction both rejected it. Kahlua does
-- not provide working weak tables, so records are removed explicitly as soon as
-- either a container or the world becomes the verified owner.
local pendingWorldRecoveryByItem = {}
local pendingWorldRecoveryByWorld = {}

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
    return configLookup(key)
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
        if type(U.releaseWorldRecoveryOwner) == "function" then
            U.releaseWorldRecoveryOwner(actor)
        end
        weakActorState[actor] = nil
        circuitState[actor] = nil
    else
        weakActorState = setmetatable({}, { __mode = "k" })
        circuitState = setmetatable({}, { __mode = "k" })
        globalCircuits = {}
        diagnostics = {}
        pendingWorldRecoveryByItem = {}
        pendingWorldRecoveryByWorld = {}
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
    local actorId = U.idOf(actor) or "global"
    local key = tostring(subsystem) .. ":" .. tostring(actorId)
    local now = U.nowMs()
    local nextAllowed = diagnostics[key] or 0
    if now < nextAllowed then return end
    diagnostics[key] = now + (U.config("diagnosticCooldownMs") or 10000)
    outputDiagnostic("[SurvivorCompanion/" .. tostring(subsystem) .. "] actor="
        .. tostring(actorId) .. " " .. tostring(message))
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

-- Square APIs expose the north-west tile corner while characters and explicit
-- world targets expose their collision-centre coordinates.  Keep that contract
-- in one place so arrival checks do not disagree at doors or stop half a tile
-- away from an exact world position.
function U.targetPosition(target, targetKind)
    local x, y, z = U.position(target)
    if x == nil then return nil end
    local kind = targetKind
    if kind == nil then
        local square = U.squareOf(target)
        kind = square == target and "square" or "world"
    end
    if kind == "square" then
        return math.floor(x) + 0.5, math.floor(y) + 0.5, math.floor(z or 0)
    end
    return x, y, z or 0
end

function U.arrived(actor, target, options)
    options = type(options) == "table" and options or {}
    local ax, ay, az = U.position(actor)
    local tx, ty, tz = U.targetPosition(target, options.targetKind)
    if ax == nil or tx == nil then return false, math.huge end
    local dx, dy, dz = ax - tx, ay - ty, (az or 0) - (tz or 0)
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz * 9)
    return distance <= (tonumber(options.distance) or 0.6), distance
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
    if ok and dead == true then return true end
    -- A zombie can reach zero health one update before Build 42 publishes its
    -- terminal isDead flag. Treat that transition as dead as well so perception
    -- and combat cannot select the corpse for one more attack.
    local health, healthOk = U.call(value, "getHealth")
    if healthOk and type(health) == "number" and health <= 0 then return true end
    return false
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
    -- Several Build 42 state-machine singletons are intentionally not exposed
    -- as ordinary Kahlua objects. Indexing one to probe getObjectName/getType/
    -- getName prints a full exception even inside pcall. Their stable tostring
    -- already contains the useful class name, so resolve it before any method
    -- lookup. This keeps blocker diagnostics safe during BumpedState.
    local rawLabel = tostring(object):gsub("[%c]", " ")
    local stateName = string.match(rawLabel, "([%w_$]+State)@")
    if stateName then return stateName end
    for _, methodName in ipairs({ "getObjectName", "getType", "getName" }) do
        local value, ok = U.call(object, methodName)
        if ok and value ~= nil and tostring(value) ~= "" then
            return tostring(value):gsub("[%c]", " ")
        end
    end
    if type(object) == "table" then
        return tostring(object.__class or object.className or object.type or "table")
    end
    return rawLabel
end

function U.squareStaticBlocker(square)
    if not square then return nil, "missing_square" end
    -- Vehicles occupy a polygon rather than an IsoObject slot. Build 42 exposes
    -- the overlapping vehicle through the square, so include it in the same
    -- passability test used by the Lua A* planner. Without this, routes are drawn
    -- through parked cars and only discover the collision after Rick reaches the
    -- bodywork.
    local vehicle, vehicleOk = U.call(square, "getVehicleContainer")
    if vehicleOk and vehicle ~= nil then return vehicle, "vehicle" end
    local solid, solidOk = U.call(square, "isSolid")
    if solidOk and solid then return square, "solid_square" end
    -- Glass walls and several modded collision tiles report transparent-solid
    -- without also reporting ordinary solid.  They are just as impassable to a
    -- player capsule and must not be left for the native mover to discover at
    -- the end of an otherwise-valid Lua route.
    local solidTrans, solidTransOk = U.call(square, "isSolidTrans")
    if solidTransOk and solidTrans then return square, "solid_transparent" end
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
        if blockOk and blockAll == true and (not stairsOk or stairs ~= true) then
            -- Moveable furniture such as rubbish bins can block the whole square
            -- while explicitly reporting isThumpable() == false. Requiring a
            -- thumpable object here made A* route through the occupied tile and
            -- left the native collision capsule to discover it beside a car.
            found = object
            kind = ((thumpOk and thumpable == true)
                or U.instanceOf(object, "IsoThumpable"))
                and "full_square_thumpable" or "full_square_object"
            return false
        end
    end, 64)
    if found then return found, kind end
    local floor, floorOk = U.call(square, "TreatAsSolidFloor")
    if floorOk and not floor then return square, "missing_floor" end
    return nil, nil
end

-- Character bodies occupy a capsule, not their entire map tile. This is used
-- by execution traffic checks; planner crowd costs can remain conservative.
function U.bodyBlocksSegment(other, actor, toX, toY, clearance)
    if other == nil or other == actor or not U.sameFloor(other, actor) then return false end
    local ax, ay = U.position(actor)
    local ox, oy = U.position(other)
    if ax == nil or ox == nil or toX == nil or toY == nil then return true end
    local dx, dy = toX - ax, toY - ay
    local lengthSq = dx * dx + dy * dy
    local projection = lengthSq > 0.000001 and ((ox - ax) * dx + (oy - ay) * dy) / lengthSq or 0
    projection = math.max(0, math.min(1, projection))
    local nearX, nearY = ax + dx * projection, ay + dy * projection
    local radius = tonumber(clearance) or tonumber(U.config("navigationBodyClearance")) or 0.5
    local distanceSq = (ox - nearX)^2 + (oy - nearY)^2
    local startDistanceSq = (ox - ax)^2 + (oy - ay)^2
    local endDistanceSq = (ox - toX)^2 + (oy - toY)^2
    -- A body already touching us must not forbid a step that cleanly separates.
    if startDistanceSq < radius * radius and projection <= 0.001
        and endDistanceSq > startDistanceSq + 0.01 then return false end
    return distanceSq < radius * radius
end

function U.movingBlocker(square, actor, options)
    local found, kind
    U.squareMovingObjects(square, function(other)
        if other == actor then return end
        local collidable, collisionKnown = U.call(other, "isCollidable")
        if collisionKnown and collidable == false then return end
        -- Giblets, blood drops and particles are IsoMovingObjects too. Only
        -- physical pushables and living character bodies are traffic.
        local character = U.isZombie(other) or U.isCompanion(other)
            or U.instanceOf(other, "IsoPlayer") or U.instanceOf(other, "IsoGameCharacter")
            or U.instanceOf(other, "IsoAnimal") or U.hasMethod(other, "getBodyDamage")
        if not character and not U.instanceOf(other, "IsoPushableObject") then return end
        if options and options.swept == true and actor then
            local tx, ty = U.position(square)
            tx, ty = options.toX or (tx and tx + 0.5), options.toY or (ty and ty + 0.5)
            if not U.bodyBlocksSegment(other, actor, tx, ty, options.clearance) then return end
        end
        if other ~= actor and U.instanceOf(other, "IsoPushableObject") then
            -- Wheelie bins and legacy pushables live in getMovingObjects(), not
            -- the square's IsoObject list. Companions have no authoritative
            -- player push action, so planning through them only creates a
            -- collision/replan loop.
            found, kind = other, "pushable_object"
            return false
        elseif other ~= actor and not U.isDead(other) then
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
    -- Inspect the concrete state before the broad isBlockMovement flag. A
    -- native BumpedState sets that flag too; returning generic movement_locked
    -- hid the short collision owner and made navigation wait the full twelve-
    -- second animation timeout instead of releasing stale forward input.
    local checks = {
        { "isKnockedDown", "knocked_down" },
        { "isCompanionTraversalActive", "climbing" },
        { "isClimbing", "climbing" },
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
        if string.find(lower, "bumpedstate", 1, true)
            or string.find(lower, "bumpstate", 1, true) then
            return "bumped_state", current
        end
        if string.find(lower, "collidewithwall", 1, true) then return "wall_collision_state", current end
        if string.find(lower, "climb", 1, true) then return "climbing", current end
        if string.find(lower, "knock", 1, true) or string.find(lower, "getup", 1, true) then
            return "knocked_down", current
        end
        if string.find(lower, "playeractions", 1, true) then
            return "action_animation_state", current
        end
    end
    local blocked, blockedOk = U.call(actor, "isBlockMovement")
    if blockedOk and blocked == true then return "movement_locked" end
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

function U.sameSquare(a, b)
    local ax, ay, az = U.position(a)
    local bx, by, bz = U.position(b)
    if ax == nil or bx == nil then return false end
    return math.floor(ax) == math.floor(bx)
        and math.floor(ay) == math.floor(by)
        and math.floor(az or 0) == math.floor(bz or 0)
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

-- Exact identity proof for transactional code. Unlike inventoryContains this
-- preserves the third state (unavailable) and prefers ItemContainer.contains,
-- whose native scan is not capped by the ordinary AI inventory budget.
function U.containerContainsIdentity(container, item, fallbackLimit)
    if container == nil or item == nil then return nil end
    local contains, containsOk = U.call(container, "contains", item)
    if containsOk and type(contains) == "boolean" then return contains end
    local items, itemsOk = U.call(container, "getItems")
    if not itemsOk and type(container) == "table" then
        items, itemsOk = container.items, type(container.items) == "table"
    end
    if not itemsOk or items == nil then return nil end
    local count
    if type(items) == "table" then count = #items
    else
        local value, countOk = U.call(items, "size")
        if countOk then count = tonumber(value) end
    end
    local maximum = math.max(1, math.floor(tonumber(fallbackLimit) or 4096))
    if count == nil or count > maximum then return nil end
    for index = 0, count - 1 do
        local candidate, available
        if type(items) == "table" then candidate, available = items[index + 1], true
        elseif SC.NativeList then candidate, available = SC.NativeList.get(items, index)
        else candidate, available = U.call(items, "get", index) end
        if not available then return nil end
        if candidate == item then return true end
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
    local addedItem, added = U.call(square, "AddWorldInventoryItem", item,
        tonumber(xOffset) or 0.5, tonumber(yOffset) or 0.5,
        tonumber(zOffset) or 0, false)
    local worldItem, linked = U.call(item, "getWorldItem")
    if not linked or worldItem == nil then
        -- Test doubles and older adapters may return the wrapper. Build 42
        -- returns the InventoryItem and exposes the wrapper through getWorldItem.
        if addedItem ~= item then worldItem = addedItem end
    end
    if added and addedItem ~= nil and worldItem ~= nil then return true, worldItem end
    U.addItem(source, item)
    return false, "drop_world_add_failed"
end

local function identityInList(list, target)
    if list == nil then return nil end
    local count
    if type(list) == "table" then
        count = #list
    else
        local value, readable = U.call(list, "size")
        if readable then count = tonumber(value) end
    end
    if count == nil or count > 4096 then return nil end
    count = math.max(0, math.floor(count))
    for index = 0, count - 1 do
        local value, available
        if SC.NativeList then value, available = SC.NativeList.get(list, index)
        elseif type(list) == "table" then value, available = list[index + 1], true end
        if not available then return nil end
        if value == target then return true end
    end
    return false
end

-- Returns true/false only when every exposed authoritative collection could be
-- read. nil means absence could not be proven and is never accepted as pickup.
local function worldItemPresent(square, worldItem)
    if not square or not worldItem then return nil end
    local canonical
    if U.hasMethod(square, "getWorldObjects") then
        local list, ok = U.call(square, "getWorldObjects")
        if ok then canonical = identityInList(list, worldItem) end
        if canonical == true then return true end
    end
    -- getObjects catches a partially detached wrapper, but getWorldObjects is
    -- the canonical ownership collection and is sufficient to prove absence.
    if U.hasMethod(square, "getObjects") then
        local list, ok = U.call(square, "getObjects")
        local result
        if ok then result = identityInList(list, worldItem) end
        if result == true then return true end
    end
    if canonical == false then return false end
    if type(square) == "table" and type(square.worldItems) == "table" then
        for _, candidate in ipairs(square.worldItems) do
            if candidate == worldItem then return true end
        end
        return false
    end
    return nil
end

U.worldItemPresent = worldItemPresent

local function forgetWorldRecovery(recordOrItem)
    local record = pendingWorldRecoveryByItem[recordOrItem]
        or pendingWorldRecoveryByWorld[recordOrItem]
    if record == nil and type(recordOrItem) == "table"
        and recordOrItem.item
        and pendingWorldRecoveryByItem[recordOrItem.item] == recordOrItem then
        record = recordOrItem
    end
    if type(record) ~= "table" then return false end
    if record.item then pendingWorldRecoveryByItem[record.item] = nil end
    if record.worldItem then pendingWorldRecoveryByWorld[record.worldItem] = nil end
    return true
end

local function rememberWorldRecovery(item, worldItem, square, source, destination, owner, reason)
    local record = pendingWorldRecoveryByItem[item]
        or pendingWorldRecoveryByWorld[worldItem] or {}
    forgetWorldRecovery(record)
    local x, y, z = U.position(square)
    record.item = item
    record.worldItem = worldItem
    record.x, record.y, record.z = x, y, z
    record.source = source
    record.destination = destination
    record.owner = owner or "managed_recovery"
    record.reason = tostring(reason or "world_recovery_pending")
    record.recordedAt = U.nowMs()
    pendingWorldRecoveryByItem[item] = record
    if worldItem then pendingWorldRecoveryByWorld[worldItem] = record end
    return record
end

function U.pendingWorldRecovery(value)
    return pendingWorldRecoveryByItem[value] or pendingWorldRecoveryByWorld[value]
end

function U.clearPendingWorldRecovery(value)
    return forgetWorldRecovery(value)
end

function U.findPendingWorldRecovery(predicate)
    if type(predicate) ~= "function" then return nil end
    for _, record in pairs(pendingWorldRecoveryByItem) do
        local ok, matched = pcall(predicate, record.item, record)
        if ok and matched == true then return record end
    end
    return nil
end

function U.releaseWorldRecoveryOwner(actor)
    local inventory = actor and U.inventory(actor) or nil
    if not inventory then return 0 end
    local matches = {}
    for _, record in pairs(pendingWorldRecoveryByItem) do
        if record.source == inventory or record.destination == inventory then
            matches[#matches + 1] = record
        end
    end
    local released = 0
    for _, record in ipairs(matches) do
        if U.inventoryContains(inventory, record.item) then
            forgetWorldRecovery(record)
        else
            if record.source == inventory then record.source = nil end
            if record.destination == inventory then record.destination = nil end
            if record.owner == "source" or record.owner == "destination" then
                record.owner = "managed_recovery"
            end
        end
        released = released + 1
    end
    return released
end

local function recoverySquare(record)
    if not record then return nil end
    if record.x ~= nil then return U.gridSquare(record.x, record.y, record.z) end
    local square, ok = U.call(record.worldItem, "getSquare")
    return ok and square or nil
end

local function worldLink(item)
    local link, ok = U.call(item, "getWorldItem")
    if ok then return link, true end
    if type(item) == "table" then return item.worldItem, true end
    return nil, false
end

local function removeInventoryIdentity(container, item)
    if not container or not U.inventoryContains(container, item) then return true end
    U.call(container, "DoRemoveItem", item)
    if U.inventoryContains(container, item) then U.call(container, "Remove", item) end
    return not U.inventoryContains(container, item)
end

local function addInventoryIdentity(container, item)
    if not container then return false end
    if U.inventoryContains(container, item) then return true end
    U.call(container, "DoAddItemBlind", item)
    if not U.inventoryContains(container, item) then U.addItem(container, item) end
    return U.inventoryContains(container, item)
end

local function restoreWorldOwnership(square, oldWorldItem, item, source, sourceHadItem,
        allowReconstruct)
    local present = worldItemPresent(square, oldWorldItem)
    local restoredWorld = present == true and oldWorldItem or nil
    if present == nil and allowReconstruct ~= true then
        if sourceHadItem and source then addInventoryIdentity(source, item) end
        return false, oldWorldItem
    end
    if not restoredWorld then
        U.call(item, "setWorldItem", nil)
        if type(item) == "table" then item.worldItem = nil end
        local addedItem, added = U.call(square, "AddWorldInventoryItem", item,
            tonumber(type(oldWorldItem) == "table" and oldWorldItem.xOffset) or 0.5,
            tonumber(type(oldWorldItem) == "table" and oldWorldItem.yOffset) or 0.5,
            tonumber(type(oldWorldItem) == "table" and oldWorldItem.zOffset) or 0, false)
        local linked = select(1, worldLink(item))
        restoredWorld = linked or (addedItem ~= item and addedItem or nil)
        if not added or addedItem == nil then restoredWorld = nil end
    end
    if sourceHadItem and source then addInventoryIdentity(source, item) end
    local linked, linkReadable = worldLink(item)
    local restoredPresent
    if restoredWorld then restoredPresent = worldItemPresent(square, restoredWorld) end
    local sourceRestored = not sourceHadItem or source and U.inventoryContains(source, item)
    return restoredPresent == true and linkReadable and linked == restoredWorld and sourceRestored,
        restoredWorld
end


local function resumeWorldRecovery(record, destination)
    if type(record) ~= "table" or not record.item then
        return false, "world_recovery_record_invalid", nil, false
    end
    local item, worldItem = record.item, record.worldItem
    destination = destination or record.destination
    local square = recoverySquare(record)
    local present
    if square and worldItem then present = worldItemPresent(square, worldItem) end
    if present == true then
        -- The world is once again the verified owner. Continue through the
        -- ordinary removal transaction using the original wrapper.
        record.owner, record.destination = "world", destination
        return nil, nil, nil, true
    end
    if present == nil then
        if destination and U.inventoryContains(destination, item) then
            record.owner = "destination"
        elseif record.source and U.inventoryContains(record.source, item) then
            record.owner = "source"
        else
            record.owner = "managed_recovery"
        end
        return false, "world_recovery_presence_unknown", {
            item = item, worldItem = worldItem, recovery = record,
            owner = record.owner,
        }, false
    end

    -- Absence is proven. Finish the interrupted detach before installing the
    -- exact item in a container; never manufacture a replacement object.
    U.call(worldItem, "setSquare", nil)
    U.call(item, "setWorldItem", nil)
    if type(item) == "table" then item.worldItem = nil end
    local linked, linkReadable = worldLink(item)
    local detachedSquare, squareReadable = U.call(worldItem, "getSquare")
    if not linkReadable or linked ~= nil or squareReadable and detachedSquare ~= nil then
        record.owner = "managed_recovery"
        return false, "world_recovery_detach_pending", {
            item = item, worldItem = worldItem, recovery = record,
            owner = record.owner,
        }, false
    end
    if destination and U.inventoryContains(destination, item) then
        forgetWorldRecovery(record)
        return true, "world_item_recovered_from_pending", {
            item = item, destination = destination, idempotent = true,
        }, false
    end
    if record.source and U.inventoryContains(record.source, item) then
        local transferred, reason, details = U.transferItemVerified(
            record.source, destination, item)
        if transferred then
            forgetWorldRecovery(record)
            return true, "world_item_recovered_from_pending", details, false
        end
        record.owner, record.reason = "source", tostring(reason)
        return false, "world_recovery_container_pending", {
            item = item, recovery = record, owner = record.owner,
        }, false
    end
    if destination and addInventoryIdentity(destination, item) then
        forgetWorldRecovery(record)
        return true, "world_item_recovered_from_pending", {
            item = item, destination = destination, idempotent = false,
        }, false
    end
    record.owner, record.destination = "managed_recovery", destination
    return false, "world_recovery_container_pending", {
        item = item, worldItem = worldItem, recovery = record,
        owner = record.owner,
    }, false
end

-- Transactional inverse of dropItem for one exact floor object. Build 42's
-- vanilla ISTransferAction removes the floor-container membership, transmits
-- and removes the IsoWorldInventoryObject, clears InventoryItem.worldItem, and
-- only then adds the same InventoryItem to its destination. Mirror that narrow
-- lifecycle here so autonomous rituals cannot duplicate a relic or silently
-- delete it when a destination rejects the add.
function U.takeWorldItemVerified(worldItem, destination, expectedItem)
    if not worldItem or not destination then return false, "invalid_world_pickup" end
    local item, itemOk = U.call(worldItem, "getItem")
    if not itemOk or item == nil then
        item = type(worldItem) == "table" and worldItem.item or expectedItem
    end
    if item == nil or expectedItem ~= nil and item ~= expectedItem then
        return false, "world_item_identity_changed"
    end
    local pending = pendingWorldRecoveryByItem[item]
        or pendingWorldRecoveryByWorld[worldItem]
    if pending then
        item = pending.item or item
        worldItem = pending.worldItem or worldItem
        if expectedItem ~= nil and item ~= expectedItem then
            return false, "world_recovery_identity_changed"
        end
    end
    local square, squareOk = U.call(worldItem, "getSquare")
    if not squareOk or square == nil then
        square = pending and recoverySquare(pending)
            or type(worldItem) == "table" and worldItem.square or nil
    end
    local linkedWorld, linkReadable = worldLink(item)
    if pending then
        local recovered, reason, details, continue = resumeWorldRecovery(pending, destination)
        if continue ~= true then return recovered, reason, details end
        square = recoverySquare(pending) or square
        linkedWorld, linkReadable = worldLink(item)
    end
    if U.inventoryContains(destination, item) then
        local present
        if square then present = worldItemPresent(square, worldItem) end
        local wrapperDetached = square == nil and squareOk == true
        if (present == false or wrapperDetached)
            and linkReadable and linkedWorld == nil then
            forgetWorldRecovery(pending or item)
            return true, "already_recovered", { item = item, idempotent = true }
        end
        -- Preserve the world copy as the recovery owner if a prior partial call
        -- left both representations alive. A later retry can then start cleanly.
        if present == true or linkReadable and linkedWorld == worldItem then
            if not removeInventoryIdentity(destination, item) then
                return false, "world_item_ownership_conflict"
            end
            forgetWorldRecovery(pending or item)
            return false, "world_item_conflict_rolled_back"
        end
        -- Unknown is not absence. Keep the verified destination owner intact
        -- and retain reconciliation state instead of deleting the only copy.
        local recovery = rememberWorldRecovery(item, worldItem, square, nil,
            destination, "destination", "world_item_presence_unknown")
        return false, "world_item_presence_unknown_destination_preserved", {
            item = item, worldItem = worldItem, recovery = recovery,
            owner = "destination",
        }
    end
    if square == nil then
        local source = select(1, U.call(item, "getContainer"))
        if source and U.inventoryContains(source, item) and linkedWorld == nil then
            return U.transferItemVerified(source, destination, item)
        end
        return false, "world_item_square_unavailable"
    end

    local source, sourceOk = U.call(item, "getContainer")
    local sourceHadItem = sourceOk and source ~= nil and U.inventoryContains(source, item)
    if sourceHadItem and not removeInventoryIdentity(source, item) then
        return false, "world_source_remove_failed"
    end

    -- Mirror vanilla's floor pickup lifecycle, but treat every native return as
    -- an invocation receipt only. Membership and links are the postconditions.
    U.call(square, "transmitRemoveItemFromSquare", worldItem)
    U.call(square, "removeWorldObject", worldItem)
    U.call(worldItem, "removeFromWorld")
    U.call(worldItem, "removeFromSquare")
    local present = worldItemPresent(square, worldItem)
    if present ~= false then
        local restored, restoredWorld = restoreWorldOwnership(
            square, worldItem, item, source, sourceHadItem, false)
        local sourcePreserved = sourceHadItem and source
            and U.inventoryContains(source, item) or false
        local recovery
        if restored then
            forgetWorldRecovery(pending or item)
        else
            recovery = rememberWorldRecovery(item, restoredWorld or worldItem,
                square, source, destination, sourcePreserved and "source"
                    or "managed_recovery", "world_item_remove_rollback_failed")
        end
        return false, restored and "world_item_remove_failed_rolled_back"
            or "world_item_remove_rollback_failed", {
            item = item, worldItem = restoredWorld or worldItem,
            worldPresent = present, sourcePreserved = sourcePreserved,
            recovery = recovery, owner = recovery and recovery.owner or "world",
        }
    end
    U.call(worldItem, "setSquare", nil)
    U.call(item, "setWorldItem", nil)
    if type(item) == "table" then item.worldItem = nil end
    linkedWorld, linkReadable = worldLink(item)
    local detachedSquare = select(1, U.call(worldItem, "getSquare"))
    if not linkReadable or linkedWorld ~= nil or detachedSquare ~= nil then
        local restored, restoredWorld = restoreWorldOwnership(
            square, worldItem, item, source, sourceHadItem, true)
        local recovery
        if restored then
            forgetWorldRecovery(pending or item)
        else
            recovery = rememberWorldRecovery(item, restoredWorld or worldItem,
                square, source, destination, sourceHadItem and source
                    and U.inventoryContains(source, item) and "source"
                    or "managed_recovery", "world_item_detach_rollback_failed")
        end
        return false, restored and "world_item_detach_failed_rolled_back"
            or "world_item_detach_rollback_failed", {
            item = item, worldItem = restoredWorld or worldItem,
            recovery = recovery, owner = recovery and recovery.owner or "world",
        }
    end

    U.addItem(destination, item)
    if U.inventoryContains(destination, item)
        and worldItemPresent(square, worldItem) == false
        and select(1, worldLink(item)) == nil
        and (not source or source == destination or not U.inventoryContains(source, item)) then
        forgetWorldRecovery(pending or item)
        return true, "world_item_recovered", {
            item = item, worldItem = worldItem, square = square,
            sourceEmpty = not (source and U.inventoryContains(source, item)),
            destinationContains = true,
        }
    end

    removeInventoryIdentity(destination, item)
    local restored, restoredWorld = restoreWorldOwnership(
        square, worldItem, item, source, sourceHadItem, true)
    if restored then
        forgetWorldRecovery(pending or item)
        return false, "pickup_add_failed_rolled_back", {
            item = item, worldItem = restoredWorld, worldPresent = true,
        }
    end
    -- Even if a hostile world adapter rejects reconstruction, retain one exact
    -- container owner so the failure is explicit and the item is not deleted.
    local sourcePreserved = sourceHadItem and source and addInventoryIdentity(source, item)
    if not sourcePreserved and worldItemPresent(square, restoredWorld or worldItem) == false
        and select(1, worldLink(item)) == nil
        and addInventoryIdentity(destination, item) then
        forgetWorldRecovery(pending or item)
        return true, "world_item_recovered_after_rollback_rejection", {
            item = item, destination = destination, recoveryFallback = true,
        }
    end
    local recovery = rememberWorldRecovery(item, restoredWorld or worldItem,
        square, source, destination, sourcePreserved and "source"
            or "managed_recovery", "pickup_rollback_failed")
    return false, "pickup_rollback_failed", {
        item = item, worldItem = restoredWorld,
        sourcePreserved = sourcePreserved == true,
        recovery = recovery, owner = recovery.owner,
    }
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

-- UI-category sounds obey the player's UI volume and never create an audible
-- world event for zombies. Callers use this only after the associated state
-- transition commits, so a rejected action retains only the ordinary button click.
local function playNativeUISound(manager, soundName)
    local ok, handle = pcall(function() return manager:playUISound(soundName) end)
    if not ok then return false end
    -- SoundManager returns zero when the event has no playable clip. Merely
    -- surviving pcall is therefore not proof that the user heard anything.
    local numeric = tonumber(handle)
    return numeric ~= nil and numeric ~= 0
end

function U.playUISound(soundName, fallbackSound)
    if type(soundName) ~= "string" or soundName == "" then return false end
    local ok, manager = pcall(function() return getSoundManager() end)
    if not ok or manager == nil then return false end
    if playNativeUISound(manager, soundName) then return true end
    if type(fallbackSound) == "string" and fallbackSound ~= ""
        and fallbackSound ~= soundName then
        return playNativeUISound(manager, fallbackSound)
    end
    return false
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
    -- `false` is the explicit uncapped form.  Most callers intentionally keep
    -- the configured companion cap, while roster builders must inspect the
    -- complete registry before filtering recruited followers.
    local maximum
    if limit == false then
        maximum = math.huge
    else
        maximum = limit or U.config("maxCompanions") or 16
    end
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
    -- Registry.byId returns a record even while its native actor is dormant.
    -- Never leak that record through the actor return slot.
    if type(entry) == "table" then
        if entry.actor ~= nil then return entry.actor, entry end
        -- Test/compatibility registries may return the actor directly. Native
        -- userdata never enters this branch; table-backed actors are still
        -- identifiable by their character surface.
        if type(entry.getSquare) == "function" or entry.__class ~= nil then
            return entry, nil
        end
        return nil, entry
    end
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
