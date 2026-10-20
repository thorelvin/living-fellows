-- SPDX-License-Identifier: MIT
-- Small world/native doubles; the supervisor, decision, commands and job are real.
local SC = SurvivorCompanion
SC_DRIVING_TEST = { records = {}, native = {}, plans = {}, parks = 0,
    exits = 0, combatCalls = 0, motionCalls = 0, planStatus = "READY", stopRejected = false }
local T = SC_DRIVING_TEST
SC.Actor = {
    isCompanion = function(actor) return actor and actor.companion == true end,
    setPlayerAttackProtected = function() return true end,
}
SC.Registry = { byId = function(id) return T.records[id] end,
    idOf = function(actor) return actor.id end,
    snapshot = function()
        local result = {}
        for _, record in pairs(T.records) do result[#result + 1] = record end
        return result
    end,
}
SC.GameplayUtil = {
    nowMs = function() return SC_TEST_CLOCK end,
    config = function(key) return SC.Config.get(key) end,
    idOf = function(actor) return actor and actor.id end,
    resolveActor = function(id)
        local record = T.records[id]
        return record and record.actor, record
    end,
    registryLiving = function()
        local actors = {}
        for _, record in pairs(T.records) do actors[#actors + 1] = record.actor end
        return actors
    end,
    isValidActor = function(actor) return actor ~= nil end,
    isDead = function(actor) return actor and actor.dead == true end,
    nativeHealth = function() return 100 end,
    position = function(actor) return actor.x, actor.y, actor.z end,
    squareOf = function(actor) return { x = actor.x, y = actor.y, z = actor.z } end,
    modData = function(actor) return actor.data end,
    actorState = function(actor, runtime)
        actor.runtime = runtime or actor.runtime or {}
        return actor.runtime
    end,
    call = function(object, name, ...)
        local ok, value = SC.Call.method(object, name, ...)
        return value, ok
    end,
    safeSubsystem = function(_, _, callback, ...) return pcall(callback, ...) end,
    isDue = function() return false end,
    stop = function() return true end,
    move = function(_, _, intent)
        if intent.action == "exit_vehicle" then T.exits = T.exits + 1 end
        return true
    end,
    copyShallow = function(value)
        local copy = {}
        for key, entry in pairs(value or {}) do copy[key] = entry end
        return copy
    end,
    clamp = function(value, low, high) return math.max(low, math.min(high, value)) end,
    text = function(_, fallback) return fallback end,
    diagnostic = function() end,
    say = function() return true end,
    distance = function(a, b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end,
}
SC.Vehicle = {
    hasPlayerAboard = function(vehicle) return vehicle.playerAboard == true end,
    isStationary = function() return true end,
    exit = function(actor)
        T.exits = T.exits + 1
        actor.vehicle = nil
        return true
    end,
}
SC.Medical = { assess = function(actor)
    return { health = 100, alive = not actor.dead, downed = actor.downed == true, critical = actor.critical == true,
        bleedingCount = actor.bleeding and 1 or 0 }
end }
SC.Combat = { holdNativeAttack = function()
    T.combatCalls = T.combatCalls + 1
    return nil
end }
SC.Factions = { streetDataApi = function() return {} end }
SCBridge = {
    driveStart = function(actor)
        T.motionCalls = T.motionCalls + 1
        T.native[actor] = { active = true, state = "stopped", mode = "stopped" }
        return true
    end,
    driveSet = function(actor, _, speed)
        T.motionCalls = T.motionCalls + 1
        local state = T.native[actor]
        state.active, state.state, state.mode = true, speed == 0 and "stopped" or "cruising", "manual"
        return true
    end,
    driveTurnAround = function(actor)
        T.motionCalls = T.motionCalls + 1
        local state = T.native[actor]
        state.active, state.state, state.mode = true, "turning", "turning"
        return true
    end,
    driveStop = function(actor)
        if T.stopRejected then return false end
        local state = T.native[actor] or {}
        state.active, state.state, state.mode, state.reason = false, "idle", nil, "released"
        T.native[actor] = state
        T.parks = T.parks + 1
        return true
    end,
    driveStatus = function(actor, out)
        for key, value in pairs(T.native[actor] or { active = false, state = "idle" }) do
            out[key] = value
        end
        return true
    end,
    driveFollow = function(actor, route)
        T.motionCalls = T.motionCalls + 1
        T.lastFollowRoute = route
        local state = T.native[actor]
        state.active, state.state, state.mode = true, "following", "follow"
        return true
    end,
    driveFollowTuned = function(actor, route, speed, scale)
        T.tunedFollow = { actor = actor, route = route, speed = speed, scale = scale }
        return SCBridge.driveFollow(actor, route, speed)
    end,
    driveFollowVehicle = function(actor, leader, route, speed)
        T.convoyFollow = { actor = actor, leader = leader, route = route, speed = speed }
        return SCBridge.driveFollow(actor, route, speed)
    end,
    driveApproach = function(actor)
        T.approaches = (T.approaches or 0) + 1
        local state = T.native[actor]
        state.active, state.state, state.mode = true, "following", "follow"
        return true
    end,
    planRoadRouteAvoidingAll = function(_, sx, sy, tx, ty, circles, out)
        T.plans[#T.plans + 1] = { sx = sx, sy = sy, tx = tx, ty = ty, circles = circles }
        out.status, out.fingerprint = T.planStatus, "test-road"
        out.geometry = tostring(sx) .. "," .. tostring(sy) .. ",8,0,Test Street;"
            .. tostring(T.planEnd and T.planEnd.x or tx) .. ","
            .. tostring(T.planEnd and T.planEnd.y or ty) .. ",8,0,Test Street"
        return true
    end,
    getLastFailure = function() return "native_stop_rejected" end,
}
function T.actor(id)
    local actor = { id = id, companion = true, x = 100, y = 100, z = 0,
        data = { SC_Id = id, SC_Recruited = true, SC_Order = "follow" } }
    local vehicle = { driver = actor, x = actor.x, y = actor.y, z = actor.z }
    function vehicle:getDriver() return self.driver end
    function vehicle:getKeyId() return 123 end
    function vehicle:getX() return self.x end
    function vehicle:getY() return self.y end
    function vehicle:getZ() return self.z end
    actor.vehicle = vehicle
    function actor:getVehicle() return self.vehicle end
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:getModData() return self.data end
    function actor:getInventory() return { haveThisKeyId = function() return {} end } end
    T.records[id] = { id = id, actor = actor, recruited = true }
    return actor
end
function T.block(actor, x, y)
    T.native[actor].mode, T.native[actor].state = "blocked", "blocked"
    T.native[actor].blockedAt = 2
    T.native[actor].blockedX, T.native[actor].blockedY = x, y
end
function T.runtime()
    return { snapshot = { threats = {}, immediateAttackers = {}, allies = {},
        threatCount = 0, immediateCount = 0, pressure = 0, player = { danger = 0 } } }
end
