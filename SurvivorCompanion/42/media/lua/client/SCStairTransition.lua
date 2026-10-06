-- SPDX-License-Identifier: MIT
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Topology and type(require) == "function" then pcall(require, "SCTopology") end
SC.StairTransition = SC.StairTransition or {}
local StairTransition = SC.StairTransition
local function U() return SC.GameplayUtil end
-- The same loaded stair survey serves expedition leaders and ordinary followers.
-- It only identifies a verified entry and exit; Navigation still owns each
-- movement request and the engine performs the actual floor crossing.
local stairScanOffsets = {}
for dx = -12, 12 do
    for dy = -12, 12 do
        stairScanOffsets[#stairScanOffsets + 1] = {
            x = dx, y = dy, distanceSq = dx * dx + dy * dy,
        }
    end
end
table.sort(stairScanOffsets, function(a, b)
    if a.distanceSq ~= b.distanceSq then return a.distanceSq < b.distanceSq end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end)
local stairDirections = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function chooseLoadedStair(lx, ly, lowerZ, rejected, scan)
    local originX, originY = math.floor(lx), math.floor(ly)
    if type(scan) ~= "table" or scan.originX ~= originX
        or scan.originY ~= originY or scan.lowerZ ~= lowerZ
        or scan.rejected ~= rejected then
        scan = { originX = originX, originY = originY, lowerZ = lowerZ,
            rejected = rejected, index = 1 }
    end
    for _ = 1, 16 do
        local offset = stairScanOffsets[scan.index]
        if offset == nil then return nil, true, nil end
        scan.index = scan.index + 1
        local tx, ty = originX + offset.x, originY + offset.y
        local square = U().gridSquare(tx, ty, lowerZ)
        if square ~= nil and U().isSquareFree(square)
            and not SC.Topology.squareHasStairs(square) then
            for _, direction in ipairs(stairDirections) do
                local dx, dy = direction[1], direction[2]
                local first = U().gridSquare(tx + dx, ty + dy, lowerZ)
                local middle = U().gridSquare(tx + dx * 2, ty + dy * 2, lowerZ)
                local last = U().gridSquare(tx + dx * 3, ty + dy * 3, lowerZ)
                local landingX, landingY = tx + dx * 4, ty + dy * 4
                local landing = U().gridSquare(landingX, landingY, lowerZ + 1)
                local key = tostring(landingX) .. ":" .. tostring(landingY)
                    .. ":" .. tostring(lowerZ + 1)
                if first and middle and last and landing
                    and not (rejected and rejected[key])
                    and SC.Topology.squareHasStairs(first)
                    and SC.Topology.squareHasStairs(middle)
                    and SC.Topology.squareHasStairs(last)
                    and U().isSquareFree(landing) then
                    return {
                        key = key, lowerZ = lowerZ,
                        exit = { x = tx, y = ty, z = lowerZ },
                        landing = { x = landingX, y = landingY, z = lowerZ + 1 },
                    }, true, nil
                end
            end
        end
    end
    return nil, false, scan
end

-- Navigation decides arrival against a tile's centre (U.targetPosition) with
-- radii up to 1.0, so a stair stage is reached on the same terms. Measuring
-- to the tile's corner left a follower arriving from the east or south
-- "arrived" for Navigation but never at the stair, re-sent to the same tile.
local APPROACH_REACH_DISTANCE = 1.1
-- A completed survey that found no stair stays valid for this origin until
-- the actor has moved away or the world has had time to load more of it.
local NO_STAIR_REUSE_TILES = 4
local NO_STAIR_REUSE_MS = 30000
-- An opted-in caller rejects a stair whose current leg stops shrinking. A
-- gap between calls counts for at most the step cap, so a companion paused
-- by combat or a hold is not charged for the time it was not trying.
local LEG_PROGRESS_TILES = 0.5
local LEG_STALL_STEP_CAP_MS = 2000

local function centreDistance(actor, point)
    local x, y = U().position(actor)
    if x == nil or y == nil then return math.huge end
    return math.sqrt((x - point.x - 0.5)^2 + (y - point.y - 0.5)^2)
end

local function stairDistance(actor, point)
    local _, _, z = U().position(actor)
    if z == nil or math.floor(z) ~= point.z then return math.huge end
    return centreDistance(actor, point)
end

-- While the height is fractional, the engine owns the body on either slope.
-- Replacing its target there cancels the native crossing midway.
function StairTransition.crossingInProgress(plan, actor)
    local transition = type(plan) == "table" and plan.descent or nil
    if type(transition) ~= "table" or transition.crossing == nil then return nil end
    local _, _, z = U().position(actor)
    if z == nil or transition.fromZ == nil or transition.toZ == nil then return nil end
    local lower, upper = math.min(transition.fromZ, transition.toZ),
        math.max(transition.fromZ, transition.toZ)
    if z <= lower + 0.05 or z >= upper - 0.05 then return nil end
    return transition.crossing
end

local function rejectTransition(plan, transition, now)
    local rejected = plan.descentRejected or {}
    if transition.key ~= nil then rejected[transition.key] = true end
    plan.descentRejected = rejected
    plan.descent, plan.descentScan = nil, nil
    plan.descentRetryAt = now
end

local function legStalled(transition, actor, leg, now, stallMs)
    local distance = centreDistance(actor, leg)
    local watch = transition.legWatch
    if type(watch) ~= "table" or watch.leg ~= leg then
        transition.legWatch = { leg = leg, best = distance, stalledMs = 0, seenAt = now }
        return false
    end
    if distance <= watch.best - LEG_PROGRESS_TILES then
        watch.best, watch.stalledMs = distance, 0
    else
        watch.stalledMs = watch.stalledMs
            + math.max(0, math.min(now - watch.seenAt, LEG_STALL_STEP_CAP_MS))
    end
    watch.seenAt = now
    return watch.stalledMs >= stallMs
end

local function noStairNearby(plan, lx, ly, lowerZ, now)
    local empty = plan.noStair
    if type(empty) ~= "table" or empty.lowerZ ~= lowerZ
        or now >= empty.expiresAt then return false end
    return (lx - empty.x)^2 + (ly - empty.y)^2
        <= NO_STAIR_REUSE_TILES * NO_STAIR_REUSE_TILES
end

-- options.legStallMs opts a caller into rejecting a stair whose approach or
-- crossing leg makes no progress for that long. Expedition legs report their
-- own stalls through plan.lastStalledTarget instead.
function StairTransition.target(plan, actor, routeTarget, now, options)
    local lx, ly, lz = U().position(actor)
    if lx == nil or ly == nil or lz == nil then return routeTarget end
    local crossing = StairTransition.crossingInProgress(plan, actor)
    if crossing ~= nil then return crossing end
    local floor = math.floor(lz)
    if floor == routeTarget.z then
        local transition = type(plan.descent) == "table" and plan.descent or nil
        local landing = transition and transition.crossing or nil
        if landing ~= nil and transition.toZ == floor then
            if stairDistance(actor, landing) <= APPROACH_REACH_DISTANCE then
                transition.crossingReached = true
            elseif transition.crossingReached ~= true then
                return landing
            end
        end
        -- The leader may resume the ground route from the landing while the
        -- squad tail is still on the stairs. Retain the completed crossing
        -- briefly so cohesion recognizes both floors until the leader clears
        -- the landing; ordinary solo movement then drops this stale context.
        if landing ~= nil and transition.toZ == floor
            and centreDistance(actor, landing) <= 3 then
            return routeTarget
        end
        plan.descent = nil
        plan.descentRejected, plan.descentRetryAt, plan.descentScan = nil, nil, nil
        plan.noStair = nil
        return routeTarget
    end
    local transition = plan.descent
    if type(transition) == "table" and floor == transition.toZ then
        if stairDistance(actor, transition.crossing) > APPROACH_REACH_DISTANCE then
            return transition.crossing
        end
        plan.descent, plan.descentRejected = nil, nil
        plan.descentRetryAt, plan.descentScan = nil, nil
        transition = nil
    elseif type(transition) == "table" and floor ~= transition.fromZ then
        plan.descent, plan.descentRejected = nil, nil
        plan.descentRetryAt, plan.descentScan = nil, nil
        transition = nil
    end
    local nextFloor = floor + (routeTarget.z > floor and 1 or -1)
    local lowerZ = math.min(floor, nextFloor)
    if type(transition) == "table" and transition.lowerZ ~= lowerZ then
        plan.descent, plan.descentRejected, plan.descentScan = nil, nil, nil
        transition = nil
    end
    if type(transition) == "table" and plan.lastStalledTarget ~= nil
        and plan.lastStalledTarget ~= transition.stallAtSelection then
        rejectTransition(plan, transition, now)
        transition = nil
    end
    if transition == nil and noStairNearby(plan, lx, ly, lowerZ, now) then
        return routeTarget
    end
    if transition == nil and now >= (plan.descentRetryAt or 0) then
        local complete
        transition, complete, plan.descentScan = chooseLoadedStair(
            lx, ly, lowerZ, plan.descentRejected, plan.descentScan)
        if not complete then return nil, "planning" end
        if transition == nil and plan.descentRejected ~= nil then
            plan.descentRejected, plan.descentScan = nil, nil
            plan.lastStalledTarget = nil
            return nil, "planning"
        end
        if transition ~= nil then
            transition.fromZ, transition.toZ = floor, nextFloor
            transition.approach = floor > nextFloor
                and transition.landing or transition.exit
            transition.crossing = floor > nextFloor
                and transition.exit or transition.landing
            transition.stallAtSelection = plan.lastStalledTarget
        end
        plan.descent = transition
        plan.descentRetryAt = transition == nil and now + 3000 or nil
        plan.noStair = transition == nil and {
            x = lx, y = ly, lowerZ = lowerZ,
            expiresAt = now + NO_STAIR_REUSE_MS,
        } or nil
    end
    if type(transition) ~= "table" then return routeTarget end
    if not transition.approachReached
        and stairDistance(actor, transition.approach) <= APPROACH_REACH_DISTANCE then
        transition.approachReached = true
    end
    local leg = transition.approachReached and transition.crossing
        or transition.approach
    local stallMs = type(options) == "table" and tonumber(options.legStallMs) or nil
    if stallMs ~= nil and legStalled(transition, actor, leg, now, stallMs) then
        rejectTransition(plan, transition, now)
        return nil, "planning"
    end
    return leg
end
