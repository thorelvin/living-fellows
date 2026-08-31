-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"
require "SCStableValue"
require "SCTransaction"

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

local orders = { follow = true, stay = true, guard = true, regroup = true,
    retreat = true, wander = true }
local combatStances = { passive = true, defensive = true, aggressive = true }
local weaponPriorities = { best = true, melee = true, firearm = true, quiet = true }
local followDistances = { [2] = true, [3] = true, [5] = true, [8] = true }

local function ownedCopy(value, label, maximumDepth, maximumValues, fallback)
    if value == nil then return fallback end
    local copied, reason = SC.StableValue.copyStrict(value, {
        path = label, maxDepth = maximumDepth, maxEntries = maximumValues,
    })
    if reason ~= nil then return nil, reason end
    return copied
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

local function snapshotIdentityFields(data)
    local snapshot = {}
    for _, key in ipairs({ "SC_Id", "SC_FactionId", "SC_FactionRole" }) do
        local ok, value = pcall(function() return data[key] end)
        if not ok then return nil, "cannot read " .. key .. ": " .. tostring(value) end
        snapshot[key] = value
    end
    return snapshot
end

local function restoreIdentityFields(data, snapshot)
    local failures = {}
    for _, key in ipairs({ "SC_Id", "SC_FactionId", "SC_FactionRole" }) do
        local ok, reason = pcall(function() data[key] = snapshot[key] end)
        if not ok then failures[#failures + 1] = key .. ": " .. tostring(reason) end
    end
    return #failures == 0, table.concat(failures, "; ")
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
        and SC.Config.get("orders", "defaultScavenge") == true
    local currentOrder = orders[order.current] and order.current
        or (orders[defaultOrder] and defaultOrder or (recruited and "follow" or "wander"))
    local followDistance = tonumber(order.followDistance)
        or tonumber(SC.Config.get("orders", "defaultFollowDistance")) or 3
    if not followDistances[followDistance] then followDistance = 3 end
    local combatStance = combatStances[order.combatStance] and order.combatStance
        or SC.Config.get("orders", "defaultCombatStance")
    if not combatStances[combatStance] then combatStance = "defensive" end
    local weaponPriority = weaponPriorities[order.weaponPriority] and order.weaponPriority
        or SC.Config.get("orders", "defaultWeaponPriority")
    if not weaponPriorities[weaponPriority] then weaponPriority = "best" end

    local profile, copyReason = ownedCopy(personality.profile,
        "personality.profile", 3, 32, {})
    if copyReason then return nil, copyReason end
    local memories
    memories, copyReason = ownedCopy(personality.memories,
        "personality.memories", 8, 512, {})
    if copyReason then return nil, copyReason end
    local background
    background, copyReason = ownedCopy(personality.background,
        "personality.background", 6, 256, {})
    if copyReason then return nil, copyReason end
    local care
    care, copyReason = ownedCopy(personality.care, "personality.care", 5, 192, {})
    if copyReason then return nil, copyReason end
    local reveals
    reveals, copyReason = ownedCopy(personality.reveals,
        "personality.reveals", 5, 192, {})
    if copyReason then return nil, copyReason end
    local objectives
    objectives, copyReason = ownedCopy(source.objectives, "objectives", 6, 320, {})
    if copyReason then return nil, copyReason end
    local possessions
    possessions, copyReason = ownedCopy(source.possessions, "possessions", 6, 192, {})
    if copyReason then return nil, copyReason end
    local facts
    facts, copyReason = ownedCopy(downtime.facts, "downtime.facts", 6, 256, {})
    if copyReason then return nil, copyReason end

    return {
        order = {
            current = currentOrder,
            followDistance = followDistance,
            scavenge = order.scavenge == nil and defaultScavenge or order.scavenge == true,
            rideWithPlayer = order.rideWithPlayer == nil
                and SC.Config.get("defaultRideWithPlayer") ~= false
                or order.rideWithPlayer == true,
            movementMode = moveModes[order.movementMode] and order.movementMode
                or (recruited == true and "copy" or "walk"),
            movementModeVersion = tonumber(order.movementModeVersion)
                or (recruited == true and 0 or 2),
            combatStance = combatStance,
            combatDoctrine = migratedDoctrine(order),
            holdFire = order.holdFire == true,
            weaponPriority = weaponPriority,
            workMode = workMode,
            workTarget = workTarget,
            returnOrder = orders[order.returnOrder] and order.returnOrder or nil,
            returnWorkMode = workModes[order.returnWorkMode] and order.returnWorkMode or nil,
        },
        group = source.group,
        personality = {
            archetype = personality.archetype,
            profile = profile,
            trust = tonumber(personality.trust) or 0,
            bond = tonumber(personality.bond) or 0,
            morale = tonumber(personality.morale) or 55,
            stress = tonumber(personality.stress) or 12,
            memories = memories,
            background = background,
            care = care,
            reveals = reveals,
            timeTogetherMs = math.max(0, tonumber(personality.timeTogetherMs) or 0),
            lastEncouragedAt = math.max(0, tonumber(personality.lastEncouragedAt) or 0),
        },
        objectives = objectives,
        possessions = possessions,
        downtime = {
            lastCompleted = downtime.lastCompleted,
            facts = facts,
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

    local identitySnapshot, snapshotReason = snapshotIdentityFields(data)
    if identitySnapshot == nil then return nil, snapshotReason end

    record = type(record) == "table" and record or {}
    local requestedId = record.id
    local actorId = identitySnapshot.SC_Id
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
        or type(identitySnapshot.SC_FactionId) == "string" and identitySnapshot.SC_FactionId or nil
    local factionRole = type(record.factionRole) == "string" and record.factionRole
        or type(identitySnapshot.SC_FactionRole) == "string" and identitySnapshot.SC_FactionRole or nil
    local state, stateReason = defaultState(record.state or record, recruited)
    if state == nil then return nil, "invalid registry state: " .. tostring(stateReason) end
    local identity, identityReason = ownedCopy(record.identity,
        "identity", 5, 128, {})
    if identity == nil then return nil, "invalid companion identity: " .. tostring(identityReason) end
    local committed = {
        id = id,
        actor = actor,
        recruited = recruited,
        identity = identity,
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

    local ok, assignmentError, rollbackError = SC.Transaction.run(function()
        data.SC_Id = id
        data.SC_FactionId = factionId
        data.SC_FactionRole = factionRole
        recordsById[id] = committed
        idsByActor[actor] = id
        return true
    end, function()
        recordsById[id] = nil
        idsByActor[actor] = nil
        local restored, rollbackReason = restoreIdentityFields(data, identitySnapshot)
        if not restored then return false, rollbackReason end
        return true
    end)
    if not ok then
        local reason = "registry commit failed: " .. tostring(assignmentError)
        if rollbackError ~= nil then
            reason = reason .. "; registry rollback failed: " .. tostring(rollbackError)
        end
        return nil, reason
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
