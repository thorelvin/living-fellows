-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"

local SC = SurvivorCompanion
SC.Registry = SC.Registry or {}

local registry = SC.Registry
local recordsById = {}
local idsByActor = {}
local sequence = 0
local workModes = { auto = true, idle = true, craft = true, build = true }
local moveModes = { copy = true, walk = true, sneak = true, jog = true }
local targetedWorkKinds = { barricade = true, remove_barricade = true, dismantle = true }
local combatDoctrines = {
    stealth = true,
    close_defense = true,
    ranged_support = true,
    weapons_free = true,
}

local function migratedDoctrine(order)
    if combatDoctrines[order.combatDoctrine] then return order.combatDoctrine end
    if order.holdFire == true or order.combatStance == "passive"
        or order.weaponPriority == "quiet" then return "stealth" end
    if order.combatStance == "aggressive" then return "weapons_free" end
    if order.weaponPriority == "firearm" then return "ranged_support" end
    return "close_defense"
end

local function copyStable(value, depth, remaining)
    remaining = remaining or { count = 256 }
    if remaining.count <= 0 then return nil end
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        remaining.count = remaining.count - 1
        return value
    end
    if type(value) ~= "table" or (depth or 0) <= 0 then return nil end
    local result = {}
    remaining.count = remaining.count - 1
    for key, item in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copy = copyStable(item, depth - 1, remaining)
            if copy ~= nil then result[key] = copy end
            if remaining.count <= 0 then break end
        end
    end
    return result
end

local function validId(id)
    return type(id) == "string" and #id >= 4 and #id <= 80 and string.sub(id, 1, 3) == "sc-"
end

local function getModData(actor)
    if actor == nil or type(actor.getModData) ~= "function" then
        return nil, "actor has no mod-data adapter"
    end
    local ok, data = pcall(actor.getModData, actor)
    if not ok or type(data) ~= "table" then
        return nil, "actor mod data is unavailable"
    end
    return data
end

local function isSurvivor(actor)
    if SC.Actor ~= nil and type(SC.Actor._isRegistryActor) == "function" then
        return SC.Actor._isRegistryActor(actor)
    end
    if SC.Actor ~= nil and type(SC.Actor._isSurvivor) == "function" then
        return SC.Actor._isSurvivor(actor)
    end
    if instanceof ~= nil then
        local ok, result = pcall(instanceof, actor, "IsoSurvivor")
        return ok and result == true
    end
    return false
end

local function randomPart()
    if ZombRand ~= nil then
        local ok, value = pcall(ZombRand, 100000, 999999)
        if ok and type(value) == "number" then
            return math.floor(value)
        end
    end
    return math.floor((os.clock() * 1000000) % 900000) + 100000
end

local function newId()
    local stamp = os.time and os.time() or math.floor(os.clock() * 1000)
    repeat
        sequence = sequence + 1
        local candidate = "sc-" .. tostring(stamp) .. "-" .. tostring(sequence) .. "-" .. tostring(randomPart())
        if recordsById[candidate] == nil then
            return candidate
        end
    until false
end

local function defaultState(source, recruited)
    source = type(source) == "table" and source or {}
    local order = type(source.order) == "table" and source.order or {}
    local personality = type(source.personality) == "table" and source.personality or {}
    local downtime = type(source.downtime) == "table" and source.downtime or {}
    local workMode = workModes[order.workMode] and order.workMode or "auto"
    local workTarget
    if type(order.workTarget) == "table" and type(order.workTarget.x) == "number"
        and type(order.workTarget.y) == "number"
        and tonumber(order.workTarget.objectIndex) ~= nil then
        workTarget = {
            x = order.workTarget.x,
            y = order.workTarget.y,
            z = tonumber(order.workTarget.z) or 0,
            objectIndex = math.floor(tonumber(order.workTarget.objectIndex)),
            initialPlanks = math.max(0,
                math.floor(tonumber(order.workTarget.initialPlanks) or 0)),
            baseJobId = type(order.workTarget.baseJobId) == "string"
                and order.workTarget.baseJobId or nil,
            barricadeSide = order.workTarget.barricadeSide == "same" and "same"
                or order.workTarget.barricadeSide == "opposite" and "opposite" or nil,
            kind = targetedWorkKinds[order.workTarget.kind]
                and order.workTarget.kind or "barricade",
        }
    end
    if workMode == "build" and workTarget == nil then workMode = "auto" end
    local defaultOrder = recruited == true
        and SC.Config.get("orders", "defaultOrder") or "wander"
    local defaultScavenge = recruited == true
    return {
        order = {
            current = order.current or defaultOrder,
            followDistance = order.followDistance or SC.Config.get("orders", "defaultFollowDistance"),
            scavenge = order.scavenge == nil and defaultScavenge or order.scavenge == true,
            rideWithPlayer = order.rideWithPlayer == nil
                and SC.Config.get("defaultRideWithPlayer") ~= false
                or order.rideWithPlayer == true,
            movementMode = moveModes[order.movementMode] and order.movementMode
                or (recruited == true and "copy" or "walk"),
            movementModeVersion = tonumber(order.movementModeVersion)
                or (recruited == true and 0 or 2),
            combatStance = order.combatStance or SC.Config.get("orders", "defaultCombatStance"),
            combatDoctrine = migratedDoctrine(order),
            holdFire = order.holdFire == true,
            weaponPriority = order.weaponPriority or SC.Config.get("orders", "defaultWeaponPriority"),
            workMode = workMode,
            workTarget = workTarget,
            returnOrder = order.returnOrder,
            returnWorkMode = order.returnWorkMode,
        },
        group = source.group,
        personality = {
            archetype = personality.archetype,
            profile = copyStable(personality.profile, 2, { count = 16 }) or {},
            trust = tonumber(personality.trust) or 0,
            bond = tonumber(personality.bond) or 0,
            morale = tonumber(personality.morale) or 55,
            stress = tonumber(personality.stress) or 12,
            memories = type(personality.memories) == "table" and personality.memories or {},
            background = type(personality.background) == "table" and personality.background or {},
            care = type(personality.care) == "table" and personality.care or {},
            reveals = type(personality.reveals) == "table" and personality.reveals or {},
            timeTogetherMs = math.max(0, tonumber(personality.timeTogetherMs) or 0),
            lastEncouragedAt = math.max(0, tonumber(personality.lastEncouragedAt) or 0),
        },
        objectives = copyStable(source.objectives, 4, { count = 160 }) or {},
        possessions = copyStable(source.possessions, 4, { count = 96 }) or {},
        downtime = {
            lastCompleted = downtime.lastCompleted,
            facts = type(downtime.facts) == "table" and downtime.facts or {},
        },
    }
end

function registry.register(actor, record)
    if not isSurvivor(actor) then
        return nil, "only an owned native companion actor may be registered"
    end

    local data, dataError = getModData(actor)
    if data == nil then
        return nil, dataError
    end

    record = type(record) == "table" and record or {}
    local requestedId = record.id
    local actorId = data.SC_Id
    if requestedId ~= nil and not validId(requestedId) then
        return nil, "invalid companion id"
    end
    if actorId ~= nil and not validId(actorId) then
        return nil, "actor contains an invalid companion id"
    end
    if requestedId ~= nil and actorId ~= nil and requestedId ~= actorId then
        return nil, "actor and record companion ids differ"
    end

    local id = requestedId or actorId or newId()
    local duplicate = recordsById[id]
    if duplicate ~= nil then
        if duplicate.actor == actor and idsByActor[actor] == id then
            return duplicate
        end
        return nil, "companion id is already active"
    end
    if idsByActor[actor] ~= nil then
        return nil, "actor is already registered"
    end

    local recruited = record.recruited == true
    local factionId = type(record.factionId) == "string" and record.factionId
        or type(data.SC_FactionId) == "string" and data.SC_FactionId or nil
    local factionRole = type(record.factionRole) == "string" and record.factionRole
        or type(data.SC_FactionRole) == "string" and data.SC_FactionRole or nil
    local state = defaultState(record.state or record, recruited)
    local committed = {
        id = id,
        actor = actor,
        recruited = recruited,
        identity = type(record.identity) == "table" and record.identity or {},
        state = state,
        -- Flat mirrors are the gameplay command adapter's stable compatibility
        -- surface. Commands replace `state` whenever these values change, and
        -- persistence reads the canonical nested state transactionally.
        order = state.order.current,
        followDistance = state.order.followDistance,
        scavenge = state.order.scavenge,
        rideWithPlayer = state.order.rideWithPlayer,
        moveMode = state.order.movementMode,
        combatMode = state.order.combatStance,
        combatDoctrine = state.order.combatDoctrine,
        holdFire = state.order.holdFire,
        weaponPriority = state.order.weaponPriority,
        workMode = state.order.workMode,
        workTarget = state.order.workTarget,
        returnOrder = state.order.returnOrder,
        returnWorkMode = state.order.returnWorkMode,
        group = state.group,
        personality = state.personality.archetype,
        personalityProfile = state.personality.profile,
        trust = state.personality.trust,
        bond = state.personality.bond,
        morale = state.personality.morale,
        stress = state.personality.stress,
        memories = state.personality.memories,
        background = state.personality.background,
        care = state.personality.care,
        reveals = state.personality.reveals,
        timeTogetherMs = state.personality.timeTogetherMs,
        objectives = state.objectives,
        possessions = state.possessions,
        lastDowntime = state.downtime.lastCompleted,
        runtime = {},
        restored = record.restored == true,
        factionId = factionId,
        factionRole = factionRole,
        factionLeader = record.factionLeader == true or factionRole == "leader",
    }
    if record.debugSpawn == true then
        -- Runtime-only test provenance. Neutral encounters are not persisted,
        -- so this cannot leak a debug lifecycle rule into a normal save.
        committed.runtime.debugSpawn = true
        committed.runtime.debugDiscovered = record.debugDiscovered == true
    end

    local previousId = data.SC_Id
    local ok, assignmentError = pcall(function()
        data.SC_Id = id
        data.SC_FactionId = factionId
        data.SC_FactionRole = factionRole
        recordsById[id] = committed
        idsByActor[actor] = id
    end)
    if not ok then
        recordsById[id] = nil
        idsByActor[actor] = nil
        data.SC_Id = previousId
        return nil, "registry commit failed: " .. tostring(assignmentError)
    end
    return committed
end

function registry.unregister(actor)
    local id = idsByActor[actor]
    if id == nil then
        return nil, "actor is not registered"
    end
    local record = recordsById[id]
    idsByActor[actor] = nil
    recordsById[id] = nil
    if record ~= nil then
        record.actor = nil
        record.runtime = {}
    end
    return record
end

function registry.byId(id)
    if not validId(id) then
        return nil
    end
    return recordsById[id]
end

function registry.idOf(actor)
    return idsByActor[actor]
end

function registry.living()
    local actors = {}
    for _, record in pairs(recordsById) do
        local actor = record.actor
        local alive = actor ~= nil and not (type(record.runtime) == "table"
            and record.runtime.inactive == true)
        if alive and type(actor.isDead) == "function" then
            local ok, result = pcall(actor.isDead, actor)
            alive = ok and result ~= true
        end
        if alive then
            actors[#actors + 1] = actor
        end
    end
    table.sort(actors, function(a, b)
        return tostring(idsByActor[a]) < tostring(idsByActor[b])
    end)
    return actors
end

function registry.records()
    local result = {}
    for _, record in pairs(recordsById) do
        result[#result + 1] = record
    end
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    return result
end

function registry.isActive(actor, id)
    return validId(id) and idsByActor[actor] == id and recordsById[id] ~= nil
        and recordsById[id].actor == actor
end

function registry.isValidId(id)
    return validId(id)
end

function registry.reset()
    for _, record in pairs(recordsById) do
        record.actor = nil
        record.runtime = {}
    end
    recordsById = {}
    idsByActor = {}
end

return registry
