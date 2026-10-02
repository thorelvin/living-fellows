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

local function stairDistance(actor, point)
    local x, y, z = U().position(actor)
    if x == nil or y == nil or z == nil
        or math.floor(z) ~= point.z then return math.huge end
    return math.sqrt((x - point.x)^2 + (y - point.y)^2)
end

function StairTransition.target(plan, actor, routeTarget, now)
    local lx, ly, lz = U().position(actor)
    if lx == nil or ly == nil or lz == nil then return routeTarget end
    local floor = math.floor(lz)
    if floor == routeTarget.z then
        local crossing = plan.descent and plan.descent.crossing
        if crossing ~= nil and plan.descent.toZ == routeTarget.z
            and math.abs(lz - routeTarget.z) > 0.05 then return crossing end
        plan.descentRejected, plan.descentRetryAt, plan.descentScan = nil, nil, nil
        return routeTarget
    end
    local transition = plan.descent
    if type(transition) == "table" and floor == transition.toZ then
        if stairDistance(actor, transition.crossing) > 4 then
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
        local rejected = plan.descentRejected or {}
        if transition.key ~= nil then rejected[transition.key] = true end
        plan.descentRejected = rejected
        plan.descent, plan.descentScan = nil, nil
        plan.descentRetryAt = now
        transition = nil
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
    end
    if type(transition) ~= "table" then return routeTarget end
    if not transition.approachReached
        and stairDistance(actor, transition.approach) <= 0.75 then
        transition.approachReached = true
    end
    return transition.approachReached and transition.crossing
        or transition.approach
end
