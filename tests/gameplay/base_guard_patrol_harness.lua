-- SPDX-License-Identifier: MIT
-- The guard controller must service one real route until arrival, rather than
-- cycling waypoints on each slow work-selection pulse.
local SC, checks = SurvivorCompanion, 0
local clock, calls, cancels, route = 10000, {}, {}, nil
local requestHandled, requestReason = true, "path_searching"
local base, center, job, quiet, guarding, resident
local squares = {}
local function check(value, message)
    checks = checks + 1
    if not value then error("base guard patrol check " .. checks .. ": " .. message) end
end
local function square(x, y, z)
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
    if not squares[key] then squares[key] = { x = x, y = y, z = z or 0 } end
    return squares[key]
end
SC.GameplayUtil = {
    nowMs = function() return clock end,
    config = function() return nil end,
    idOf = function(actor) return actor.id end,
    position = function(value) return value.x, value.y, value.z or 0 end,
    gridSquare = square,
    distance = function(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end,
    characterStatValue = function() return 0 end,
    call = function(value, method, ...)
        if value and type(value[method]) == "function" then return value[method](value, ...), true end
        return nil, false
    end,
}
SC.Commands = { peek = function() return { order = "base_duty", anchor = base.core } end }
SC.Navigation = {
    standingSquareClear = function(_, value) return value.blocked ~= true end,
    peek = function() return route end,
    cancel = function(_, reason) cancels[#cancels + 1] = reason route = nil return true end,
    request = function(_, target, mode, intent)
        calls[#calls + 1] = { target = target, mode = mode, intent = intent }
        route = { goalAction = intent.action, goalSquare = target }
        return requestHandled, requestReason
    end,
}
SC.BaseLife = {
    active = function() return base end,
    zoneCenter = function(kind) return kind == "guard" and center or nil end,
    isInside = function(value) return value.outside ~= true end,
    outdoorNightRestricted = function() return false end,
    isOutdoorSquare = function(value) return value.outdoors == true end,
    resident = function() return resident end,
    jobFor = function() return job end,
    guardStatus = function() return guarding end,
    claimJob = function() return job end,
    touchJob = function() return true end,
    job = function() return job end,
    releaseJob = function() job = nil return true end,
}
local routine = SC.BaseWork._guardRoutineForTests
check(type(routine) == "function", "guard controller test seam is available")
local function fresh(distance)
    squares, calls, cancels, route = {}, {}, {}, nil
    requestHandled, requestReason = true, "path_searching"
    base = { id = "camp", core = { x = 0, y = 0, z = 0 }, jobs = {},
        zones = { { id = "guard:1", kind = "guard", x1 = 8, x2 = 12, y1 = -2, y2 = 2, z = 0 } },
        settings = { routines = false } }
    center, job, quiet, guarding = { x = 10, y = 0, z = 0 }, nil, nil, true
    resident = { duty = true, role = "guard" }
    SC.Downtime, SC.FarmWork = nil, nil
    clock = clock + 100000
    return { id = "guard:" .. clock, x = center.x + distance, y = 0, z = 0 },
        { patrolIndex = 0, nextRoutineAt = 0 }
end

-- Report-like near guard: the 30-second wait starts after actual arrival.
local actor, state = fresh(2)
local handled, reason = routine(actor, state)
local target = calls[1].target
check(handled and reason == "path_searching", "near guard starts a real route")
for _ = 1, 8 do
    clock = clock + 250
    handled, reason = routine(actor, state)
    check(handled and reason == "path_searching" and calls[#calls].target == target,
        "near guard keeps planning the exact waypoint, even within three tiles")
end
check(#calls == 9 and (state.nextRoutineAt or 0) <= clock,
    "no patrol interval expires before arrival")

-- A farther guard must not rotate destinations on every 250ms update.
actor, state = fresh(15)
routine(actor, state)
target = calls[1].target
for _ = 1, 12 do clock = clock + 250 routine(actor, state) end
for _, row in ipairs(calls) do
    check(row.target == target and row.intent.workCampOnly == true,
        "far guard retains one camp-admitted target through search and movement")
end
check(state.patrolIndex == 1, "far guard advances patrol index only when selecting a new waypoint")

requestReason, actor.x, actor.y = "arrived", target.x, target.y
handled, reason = routine(actor, state)
local arrivedAt, count = clock, #calls
check(handled and reason == "arrived" and state.guardPatrolTarget == nil,
    "verified arrival releases patrol waypoint")
check(state.nextRoutineAt == arrivedAt + 30000, "normal patrol pause starts at arrival")
clock = arrivedAt + 29999
handled, reason = routine(actor, state)
check(not handled and reason == "guard_holding" and #calls == count,
    "guard waits during completed-route interval")
clock, requestReason = arrivedAt + 30000, "path_started"
routine(actor, state)
check(#calls == count + 1 and calls[#calls].target ~= target,
    "guard selects next waypoint after its completed pause")

actor, state = fresh(10)
routine(actor, state)
target = calls[1].target
target.blocked = true
clock = clock + 250
routine(actor, state)
check(calls[#calls].target ~= target and #cancels == 1,
    "new furniture retires the blocked waypoint and its own route")
local prior = #cancels
base.id, center = "camp:new", { x = 30, y = 0, z = 0 }
clock = clock + 250
routine(actor, state)
check(calls[#calls].target.x >= 28 and #cancels == prior + 1,
    "changing active camp or guard centre cannot resume old waypoint")
prior = #cancels
base.zones[1].x2 = base.zones[1].x2 + 1
clock = clock + 250
routine(actor, state)
check(#cancels == prior + 1, "guard area shape mutation invalidates old waypoint")

actor, state = fresh(10)
routine(actor, state)
requestHandled, requestReason = false, "no_path"
clock = clock + 250
routine(actor, state)
count = #calls
check(state.guardPatrolTarget == nil and #cancels == 1,
    "terminal route failure retires its search")
clock = clock + 4999
routine(actor, state)
check(#calls == count, "failed route does not spin retries each selection pulse")
clock, requestHandled, requestReason = clock + 1, true, "path_searching"
routine(actor, state)
check(#calls == count + 1, "failed route retries after bounded five-second cooldown")

-- Use public BaseWork.update for ownership changes, not only the small seam.
actor = fresh(2)
handled = SC.BaseWork.update(actor, nil, {})
check(handled and route and route.goalAction == "base_guard_patrol",
    "public base work starts guard controller")
job = { id = "farm:1", type = "farm", state = "reserved" }
local farmPolls = 0
SC.FarmWork = { update = function() farmPolls = farmPolls + 1 return true, "watering" end }
clock = clock + 250
handled, reason = SC.BaseWork.update(actor, nil, {})
check(handled and reason == "watering" and farmPolls == 1 and route == nil,
    "named farm job immediately owns the actor and old guard route is cancelled")

actor = fresh(2)
SC.BaseWork.update(actor, nil, {})
quiet = { active = { kind = "rest_bed" } }
local quietPolls = 0
SC.Downtime = { peek = function() return quiet end,
    update = function() quietPolls = quietPolls + 1 return true, "sleeping" end }
route = { goalAction = "bed_approach" }
clock = clock + 250
handled, reason = SC.BaseWork.update(actor, nil, {})
check(handled and reason == "sleeping" and quietPolls == 1 and route.goalAction == "bed_approach",
    "owned sleep continues and clearing patrol state preserves its new route")

actor = fresh(2)
SC.BaseWork.update(actor, nil, {})
handled = SC.BaseWork.cancel(actor, "player_follow_order")
check(handled and route == nil, "new player order cancels the old patrol route")
actor = fresh(2)
SC.BaseWork.update(actor, nil, {})
resident.duty = false
handled, reason = SC.BaseWork.update(actor, nil, {})
check(not handled and reason == "not_on_base_duty" and route == nil,
    "resident leaving base duty releases patrol navigation")

print("PASS base guard patrol harness (" .. checks .. " checks)")
