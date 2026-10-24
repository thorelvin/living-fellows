-- SPDX-License-Identifier: MIT
-- Real Commands + BaseWork cancellation: Follow variants must use the same
-- resident/job/navigation handoff before their options or convoy take effect.
local SC, checks = SurvivorCompanion, 0
local C, W = SC.Commands, SC.BaseWork
local actors, records, residents, jobs, routes = {}, {}, {}, {}, {}
local base = { id = "follow-camp", core = { x = 0, y = 0, z = 0 }, zones = {}, jobs = {},
    settings = { routines = false } }
local current, activated, convoyReleased, invalidated, dutyReleased = 10000, 0, 0, 0, 0
local refused, snapshotsAtCancel = nil, {}
local function check(value, message)
    checks = checks + 1
    assert(value, "follow order handoff check " .. checks .. ": " .. message)
end
local function shallow(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end
local function square(x, y, z) return { x = x, y = y, z = z or 0 } end
SC.GameplayUtil = {
    nowMs = function() return current end,
    config = function() return nil end,
    idOf = function(value) return value.id end,
    isDead = function() return false end,
    isValidActor = function(value) return value ~= nil end,
    modData = function(value) return value:getModData() end,
    position = function(value) return value.x, value.y, value.z or 0 end,
    gridSquare = square,
    loadedSquare = function(value) return value end,
    characterStatValue = function() return 0 end,
    distance = function(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end,
    resolveActor = function(id) return records[id] and records[id].actor, records[id] end,
    registryLiving = function() return actors end,
    copyShallow = shallow,
    call = function(value, method, ...)
        if value and type(value[method]) == "function" then return value[method](value, ...), true end
        return nil, false
    end,
    safeSubsystem = function(_, _, callback, ...)
        local okay, first, second, third = pcall(callback, ...)
        return okay, first, second, third
    end,
}
SC.Registry = { byId = function(id) return records[id] end }
SC.BaseLife = {
    active = function() return base end,
    resident = function(id) return residents[id] end,
    snapshotResident = function(id) return { present = residents[id] ~= nil, value = shallow(residents[id]) } end,
    restoreResident = function(id, value) residents[id] = value.present and shallow(value.value) or nil return true end,
    setDuty = function(id, enabled)
        residents[id].duty = enabled == true
        if not enabled then dutyReleased = dutyReleased + 1 jobs[id] = nil end
        return true
    end,
    jobFor = function(id) return jobs[id] end,
    job = function(id)
        for _, job in pairs(jobs) do if job.id == id then return job end end
    end,
    releaseJob = function(_, id) jobs[id] = nil return true end,
    zoneCenter = function(kind) return kind == "guard" and square(10, 0, 0) or nil end,
    isInside = function() return true end,
    guardStatus = function() return true end,
    outdoorNightRestricted = function() return false end,
    claimJob = function(id) return jobs[id] end,
}
SC.Navigation = {
    standingSquareClear = function() return true end,
    peek = function(actor) return routes[actor] end,
    request = function(actor, target, _, intent)
        routes[actor] = { goalSquare = target, goalAction = intent.action }
        return true, "path_searching"
    end,
    cancel = function(actor) routes[actor] = nil return true end,
}
SC.FloorSort = { cancelActor = function(actor)
    local state = C.peek(actor)
    snapshotsAtCancel[#snapshotsAtCancel + 1] = { mode = state.moveMode, car = state.followCarSqlId,
        scavenge = state.scavenge, ride = state.rideWithPlayer, order = state.order }
    return actor ~= refused, actor == refused and "exact_stock_return_pending" or nil
end }
SC.Convoy = {
    preflight = function(_, vehicle) return vehicle and vehicle.sqlId or nil, "car_unavailable" end,
    activate = function(actor)
        local state = C.peek(actor)
        check(state.order == "follow" and residents[actor.id].duty == false
            and jobs[actor.id] == nil and routes[actor] == nil,
            "convoy activates only after real base work, duty and old route release")
        check(actor.data.SC_FollowCarSqlId == state.followCarSqlId
            and actor.data.SC_RideWithPlayer == true,
            "convoy activation observes committed follow-car options")
        activated = activated + 1
    end,
    release = function() convoyReleased = convoyReleased + 1 end,
}
SC.Vehicle = { invalidateManifests = function() invalidated = invalidated + 1 end }
SC.Downtime = { cancel = function() return true end }
local serial = 0
local function guard(withOldCar)
    serial, current = serial + 1, current + 10000
    local actor = { id = "follow-guard:" .. serial, x = 12, y = 0, z = 0,
        data = { SC_Recruited = true, SC_Order = "base_duty", SC_MoveMode = "walk",
            SC_MoveModeVersion = 2, SC_Scavenge = false, SC_RideWithPlayer = false,
            SC_AnchorX = 0, SC_AnchorY = 0, SC_AnchorZ = 0, SC_CommandSerial = 10,
            SC_Group = "Alpha", SC_FollowCarSqlId = withOldCar and 123 or nil } }
    function actor:getModData() return self.proxy or self.data end
    actors[#actors + 1] = actor
    records[actor.id] = { actor = actor, id = actor.id, recruited = true, state = {} }
    residents[actor.id] = { baseId = base.id, role = "guard", duty = true }
    check(C.peek(actor).order == "base_duty", "fixture starts on actual base duty")
    check(W.update(actor, nil, {}) == true and routes[actor]
        and routes[actor].goalAction == "base_guard_patrol", "fixture owns real pending guard patrol")
    jobs[actor.id] = { id = "job:" .. serial, reservedBy = actor.id, state = "reserved" }
    return actor
end
local car = { sqlId = 456 }

for _, variant in ipairs({ "cautious_follow", "assign_follow_car", "follow" }) do
    local actor = guard(true)
    local countBefore = activated
    local accepted, reason = C.issue(actor.id, variant, { vehicle = car }, nil)
    local state = C.peek(actor)
    check(accepted and state.order == "follow" and residents[actor.id].duty == false,
        variant .. " releases base duty through ordinary Follow transition: " .. tostring(reason))
    check(jobs[actor.id] == nil and routes[actor] == nil,
        variant .. " releases the old reserved job and pending guard route")
    check(state.commandSerial == 11 and actor.data.SC_CommandSerial == 11,
        variant .. " records exactly one player command, including old convoy cleanup")
    check(state.anchor == nil and actor.data.SC_AnchorX == nil,
        variant .. " clears the guard anchor in runtime and stable storage")
    local persisted = records[actor.id].state.order
    if variant == "cautious_follow" then
        check(state.moveMode == "sneak" and state.moveModeVersion == 2 and state.scavenge == true
            and actor.data.SC_MoveMode == "sneak" and actor.data.SC_Scavenge == true
            and persisted.movementMode == "sneak" and persisted.scavenge == true,
            "cautious Follow persists its complete policy in the accepted command")
        check(state.followCarSqlId == nil and actor.data.SC_FollowCarSqlId == nil,
            "cautious Follow clears the previous convoy target")
    elseif variant == "assign_follow_car" then
        check(state.followCarSqlId == 456 and state.rideWithPlayer == true
            and persisted.followCarSqlId == 456 and persisted.rideWithPlayer == true,
            "car Follow persists its selected car and boarding policy")
    else
        check(state.moveMode == "walk" and state.scavenge == false,
            "ordinary Follow keeps its prior movement and scavenging policies")
    end
    check(activated == countBefore + (variant == "assign_follow_car" and 1 or 0),
        "only accepted car Follow activates a convoy")
end

do
    local actor = guard(false)
    local countBefore, releaseBefore = activated, dutyReleased
    local accepted, reason = C.issue(actor.id, "assign_follow_car", {}, nil)
    check(not accepted and reason == "car_unavailable" and activated == countBefore
        and dutyReleased == releaseBefore and C.peek(actor).order == "base_duty"
        and residents[actor.id].duty and jobs[actor.id] and routes[actor],
        "rejected vehicle preflight cannot disturb the old base guard owner")
end

for _, variant in ipairs({ "follow", "cautious_follow", "assign_follow_car" }) do
    local actor = guard(true)
    refused = actor
    local countBefore, releaseBefore, invalidateBefore = activated, convoyReleased, invalidated
    local accepted, reason = C.issue(actor.id, variant, { vehicle = car }, nil)
    local state = C.peek(actor)
    check(not accepted and reason == "exact_stock_return_pending"
        and state.order == "base_duty" and residents[actor.id].duty == true,
        variant .. " refuses a blocked exact stock return atomically")
    check(state.moveMode == "walk" and state.scavenge == false
        and state.rideWithPlayer == false and state.followCarSqlId == 123
        and state.commandSerial == 10 and state.anchor.x == 0,
        variant .. " retains all original command options and serial on refusal")
    check(actor.data.SC_Order == "base_duty" and actor.data.SC_MoveMode == "walk"
        and actor.data.SC_Scavenge == false and actor.data.SC_RideWithPlayer == false
        and actor.data.SC_FollowCarSqlId == 123 and actor.data.SC_CommandSerial == 10,
        variant .. " refusal leaves stable options untouched")
    local atCancel = snapshotsAtCancel[#snapshotsAtCancel]
    check(atCancel.mode == "walk" and atCancel.car == 123 and atCancel.ride == false
        and atCancel.scavenge == false and atCancel.order == "base_duty",
        "old work cancellation sees original options before variant updates")
    check(jobs[actor.id] ~= nil and routes[actor] ~= nil and activated == countBefore
        and convoyReleased == releaseBefore and invalidated == invalidateBefore,
        variant .. " refusal neither releases ownership nor activates/invalidate convoy")
    refused = nil
end

-- Neither special variant is groupable today. Preserve that boundary and
-- verify ordinary group Follow still stages every command before release.
local first, second = guard(false), guard(false)
C.peek(first).group, C.peek(second).group = "Staging", "Staging"
local releasedBefore = dutyReleased
second.proxy = setmetatable({}, { __index = second.data,
    __newindex = function() error("injected stable write failure") end })
local accepted, reason = C.issue(first.id, "follow", { scope = "group", group = "Staging" }, nil)
second.proxy = nil
check(not accepted and string.find(tostring(reason), "rollback", 1, true)
    and C.peek(first).order == "base_duty" and C.peek(second).order == "base_duty"
    and dutyReleased == releasedBefore and residents[first.id].duty and residents[second.id].duty
    and routes[first] and routes[second], "failed group persistence releases no real duty, job or guard route")
check(C.issue(first.id, "follow", { scope = "group", group = "Staging" }, nil)
    and C.peek(first).order == "follow" and C.peek(second).order == "follow"
    and residents[first.id].duty == false and residents[second.id].duty == false
    and routes[first] == nil and routes[second] == nil,
    "ordinary group Follow commits all commands then releases both old base owners")
local countBefore = activated
check(C.issue(first.id, "cautious_follow", { scope = "group", group = "Staging" }, nil) == false
    and C.issue(first.id, "assign_follow_car", { scope = "group", group = "Staging", vehicle = car }, nil) == false
    and activated == countBefore, "special variants preserve existing non-groupable staging boundary")

-- The real trial return replaces Commands' state table. Convoy cleanup must
-- persist that new faction state, never the handler's old recruited snapshot.
do
    local actor = guard(false)
    check(C.issue(actor.id, "follow", nil, nil), "trial fixture leaves its old guard duty")
    local oldState = C.peek(actor)
    oldState.followCarSqlId = 123
    check(C.persist(actor), "trial fixture persists a selected convoy before return")
    local beforeSerial, beforeRelease = oldState.commandSerial, convoyReleased
    SC.FactionRecruitment = {
        originForActor = function(id)
            if id == actor.id then return { status = "trial", factionId = "household:1" } end
        end,
        returnNow = function(id)
            return C.returnFactionTrial(actor, { factionId = id, factionRole = "guard" })
        end,
    }
    local accepted, reason = C.issue(actor.id, "dismiss", nil, nil)
    local state, saved = C.peek(actor), records[actor.id].state
    check(accepted and reason == "returned_to_household" and state ~= oldState
        and state.recruited == false and state.factionId == "household:1"
        and state.factionRole == "guard" and state.order == "faction_duty",
        "dismiss executes the real detached faction-trial return")
    check(actor.data.SC_Recruited == false and actor.data.SC_FactionId == state.factionId
        and actor.data.SC_FactionRole == state.factionRole and actor.data.SC_Order == "faction_duty"
        and saved.order.current == "faction_duty" and records[actor.id].recruited == false,
        "convoy cleanup cannot overwrite accepted faction membership with the old trial state")
    check(state.commandSerial == beforeSerial + 1
        and actor.data.SC_CommandSerial == state.commandSerial
        and state.followCarSqlId == nil and actor.data.SC_FollowCarSqlId == nil
        and saved.order.followCarSqlId == nil and convoyReleased == beforeRelease + 1,
        "trial return preserves its one new serial while clearing the previous convoy")
end
SC_TEST_REPORT = "FOLLOW_ORDER_HANDOFF_PASS checks=" .. checks
