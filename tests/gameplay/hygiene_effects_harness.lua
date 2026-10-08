-- SPDX-License-Identifier: MIT

local sc = SurvivorCompanion
local oldLiving, oldNeeds, oldDowntime = sc.Registry.living,
    sc.Needs.peek, sc.Downtime.peek
local oldPlayer, oldScreenX, oldScreenY = getSpecificPlayer,
    isoToScreenX, isoToScreenY
local oldLeft, oldTop, oldWidth, oldHeight = getPlayerScreenLeft,
    getPlayerScreenTop, getPlayerScreenWidth, getPlayerScreenHeight

local lines, polygons, firstScreenX, maxAlpha = 0, 0, nil, 0
local minPolygonX, maxPolygonX = math.huge, -math.huge
local polygonAlphas = {}
local fractionalCenter = false
local arcSegments = {}
local canvas = {
    drawLineAbsolute = function(_, _, x1, y1, x2, y2, thickness, alpha)
        lines = lines + 1
        firstScreenX = firstScreenX or x1
        maxAlpha = math.max(maxAlpha, alpha or 0)
    end,
    drawPolygon = function(_, _, x1, y1, x2, y2, x3, y3, x4, y4,
        red, green, blue, alpha)
        polygons = polygons + 1
        firstScreenX = firstScreenX or x1
        minPolygonX = math.min(minPolygonX, x1, x2, x3, x4)
        maxPolygonX = math.max(maxPolygonX, x1, x2, x3, x4)
        maxAlpha = math.max(maxAlpha, alpha or 0)
        polygonAlphas[alpha] = (polygonAlphas[alpha] or 0) + 1
        if alpha == 0.55 then
            arcSegments[#arcSegments + 1] = {
                startX = (x1 + x4) / 2,
                startY = (y1 + y4) / 2,
                endX = (x2 + x3) / 2,
                endY = (y2 + y3) / 2,
                corners = { { x1, y1 }, { x2, y2 },
                    { x3, y3 }, { x4, y4 } },
            }
        end
        local centerX = (x1 + x4) / 2
        fractionalCenter = fractionalCenter
            or math.abs(centerX - math.floor(centerX)) > 0.001
    end,
}
local function resetDraws()
    lines, polygons, firstScreenX, maxAlpha = 0, 0, nil, 0
    minPolygonX, maxPolygonX = math.huge, -math.huge
    polygonAlphas = {}
    fractionalCenter = false
    arcSegments = {}
end
local square = { getCanSee = function() return true end }
local subject = {
    getX = function() return 5 end,
    getY = function() return 5 end,
    getZ = function() return 0 end,
    getCurrentSquare = function() return square end,
    getTargetAlpha = function() return 1 end,
    getForwardDirectionX = function() return 1 end,
    getForwardDirectionY = function() return 0 end,
    getAnimAngleRadians = function() return math.pi / 2 end,
    isFemale = function(self) return self.female == true end,
}
local viewer = {
    getX = function() return 6 end,
    getY = function() return 6 end,
    getZ = function() return 0 end,
}
local activeView = 0
getSpecificPlayer = function(index)
    return index == activeView and viewer or nil
end
getPlayerScreenLeft = function(index) return index * 500 end
getPlayerScreenTop = function() return 0 end
getPlayerScreenWidth = function() return 500 end
getPlayerScreenHeight = function() return 500 end
isoToScreenX = function(index, x) return index * 500 + x * 50 end
isoToScreenY = function(_, _, y, z) return y * 50 - z * 50 end

sc.Registry.living = function() return { subject } end
sc.Needs.peek = function()
    return { pee = { phase = "animating", sits = false } }
end
sc.Downtime.peek = function() return nil end

assert(sc.HygieneEffects.renderScreen(canvas) == true and polygons == 20
    and lines == 0,
    "standing relief should draw ten projected ribbon segments in two layers")
assert(polygonAlphas[0.32] == 10 and polygonAlphas[0.55] == 10,
    "every stream segment should have both translucent layers")
assert(maxAlpha > 0 and maxAlpha < 1,
    "the standing stream must remain semi transparent")
resetDraws()
activeView = 1
assert(sc.HygieneEffects.renderScreen(canvas) == true
    and polygons == 20 and minPolygonX >= 500 and maxPolygonX <= 1000,
    "second player must receive the arc in its own viewport")
resetDraws()
activeView = 0
viewer.getX = function() return 8 end
viewer.getY = function() return 8 end
sc.Needs.peek = function()
    return { pee = { phase = "animating", sits = false,
        toilet = { object = { getX = function() return 6 end,
            getY = function() return 5 end } } } }
end
assert(sc.HygieneEffects.renderScreen(canvas) == true and polygons == 20,
    "a man standing at a toilet should show the arc")
resetDraws()
subject.female = true
assert(sc.HygieneEffects.renderScreen(canvas) == false
    and lines == 0 and polygons == 0,
    "female relief must not render the standing stream")
sc.Needs.peek = function() return nil end
sc.Downtime.peek = function()
    return { active = { kind = "shower", actionAccepted = true,
        approaching = false } }
end
assert(sc.HygieneEffects.renderScreen(canvas) == true and lines > 0
    and polygons == 0,
    "an active shower should emit projected mist")
resetDraws()
sc.Downtime.peek = function()
    return { active = { kind = "shower", actionAccepted = true,
        approaching = true } }
end
assert(sc.HygieneEffects.renderScreen(canvas) == false
    and lines == 0 and polygons == 0,
    "shower mist should stop while approaching the fixture")

resetDraws()
subject.female = false
subject.getAnimAngleRadians = function() return math.pi / 4 end
sc.Downtime.peek = function() return nil end
sc.Needs.peek = function()
    return { pee = { phase = "animating", sits = false } }
end
isoToScreenX = function(index, x) return index * 500 + 100 + x * 2 end
isoToScreenY = function(_, _, y, z) return 100 + y * 2 - z * 2 end
assert(sc.HygieneEffects.renderScreen(canvas) == true
    and polygons == 20 and fractionalCenter,
    "subpixel screen spans should still draw all ten ribbon segments")

-- Exercise the real isometric axis coupling. A screen-space curve based on
-- projected X alone used to collapse for two diagonal facings and shifted its
-- source away from the actor's body for other facings.
isoToScreenX = function(index, x, y)
    return index * 500 + 250 + 70 * (x - y)
end
isoToScreenY = function(_, x, y, z)
    return -300 + 60 * (x + y) - 120 * z
end
viewer.getX = function() return 8 end
viewer.getY = function() return 8 end
local directions = {
    { "N", 0, -1, -math.pi / 2 },
    { "NE", 1, -1, -math.pi / 4 },
    { "E", 1, 0, 0 },
    { "SE", 1, 1, math.pi / 4 },
    { "S", 0, 1, math.pi / 2 },
    { "SW", -1, 1, 3 * math.pi / 4 },
    { "W", -1, 0, math.pi },
    { "NW", -1, -1, -3 * math.pi / 4 },
}
for _, direction in ipairs(directions) do
    resetDraws()
    local label, dx, dy = direction[1], direction[2], direction[3]
    local length = math.sqrt(dx * dx + dy * dy)
    local fx, fy = dx / length, dy / length
    subject.getDir = function()
        return setmetatable({ dx = function() return 1 end,
            dy = function() return 0 end },
            { __tostring = function() return "E" end })
    end
    subject.getAnimAngleRadians = function() return direction[4] end
    -- A logical direction can get ahead of the model during a turn. The arc
    -- must follow the rendered animation angle instead.
    assert(sc.HygieneEffects.renderStream(canvas, 0, { 0, 0, 500, 500 },
        subject, 5, 5, 0, 0, nil) == true and #arcSegments > 0,
        label .. " should draw the world-projected stream")
    local first, last = arcSegments[1], arcSegments[#arcSegments]
    local waistX = isoToScreenX(0, 5 + fx * 0.04,
        5 + fy * 0.04, 0.27)
    local waistY = isoToScreenY(0, 5 + fx * 0.04,
        5 + fy * 0.04, 0.27)
    local groundX = isoToScreenX(0, 5 + fx * 0.56,
        5 + fy * 0.56, 0.02)
    local groundY = isoToScreenY(0, 5 + fx * 0.56,
        5 + fy * 0.56, 0.02)
    local tolerance = 0.01
    assert(#arcSegments == 10,
        label .. " should retain every stream segment")
    assert(math.abs(first.startX - waistX) < tolerance
        and math.abs(first.startY - waistY) < tolerance,
        label .. " should use the fallback origin when no bone is available")
    assert(math.abs(last.endX - groundX) < tolerance
        and math.abs(last.endY - groundY) < tolerance,
        label .. " stream should land in front of the actor at ground level")
end

-- The real native companion bridge exposes the rendered pelvis coordinates.
-- Its source must replace the tile pivot while the destination stays fixed.
subject.getCompanionPelvisWorldX = function() return 5.12 end
subject.getCompanionPelvisWorldY = function() return 4.91 end
subject.getCompanionPelvisWorldZ = function() return 0.34 end
subject.getAnimAngleRadians = function() return math.pi / 2 end
resetDraws()
assert(sc.HygieneEffects.renderStream(canvas, 0, { 0, 0, 500, 500 },
    subject, 5, 5, 0, 0, nil) == true and #arcSegments == 10,
    "native pelvis coordinates should draw the complete stream")
assert(math.abs(arcSegments[1].startX
        - isoToScreenX(0, 5.12, 4.91 + 0.035, 0.34)) < 0.01
    and math.abs(arcSegments[1].startY
        - isoToScreenY(0, 5.12, 4.91 + 0.035, 0.34)) < 0.01,
    "stream must attach to the native rendered pelvis")
subject.getCompanionPelvisWorldX = nil
subject.getCompanionPelvisWorldY = nil
subject.getCompanionPelvisWorldZ = nil

-- The fallback draws a complete arc without a hand-drawn body mask. Native
-- depth testing handles actor silhouettes once the bridge is ready.
viewer.getX = function() return 5.3 end
viewer.getY = function() return 5.6 end
subject.getAnimAngleRadians = function() return math.pi / 2 end
resetDraws()
sc.HygieneEffects.renderStream(canvas, 0, { 0, 0, 500, 500 },
    subject, 5, 5, 0, 0, nil)
assert(#arcSegments == 10,
    "fallback stream should keep its complete arc without a body mask")

-- A recent native world draw replaces the approximate screen polygons for
-- that viewport. If it stops submitting, the Lua overlay resumes.
local nativeAccepted = 0
subject.setCompanionPeeStream = function(_, sx, sy, sz, tx, ty)
    assert(type(sx) == "number" and type(sy) == "number"
        and type(sz) == "number" and type(tx) == "number"
        and type(ty) == "number", "native stream receives world points")
    nativeAccepted = nativeAccepted + 1
    return true
end
subject.isCompanionPeeStreamDepthReady = function() return true end
resetDraws()
assert(sc.HygieneEffects.renderStream(canvas, 0, { 0, 0, 500, 500 },
    subject, 5, 5, 0, 0, nil) == true
    and polygons == 0 and nativeAccepted == 1,
    "native world stream must suppress duplicate UI polygons")
subject.isCompanionPeeStreamDepthReady = function() return false end
resetDraws()
assert(sc.HygieneEffects.renderStream(canvas, 0, { 0, 0, 500, 500 },
    subject, 5, 5, 0, 0, nil) == true and polygons > 0,
    "UI stream must resume when native depth rendering is unavailable")

sc.Registry.living, sc.Needs.peek, sc.Downtime.peek =
    oldLiving, oldNeeds, oldDowntime
getSpecificPlayer, isoToScreenX, isoToScreenY =
    oldPlayer, oldScreenX, oldScreenY
getPlayerScreenLeft, getPlayerScreenTop,
    getPlayerScreenWidth, getPlayerScreenHeight =
    oldLeft, oldTop, oldWidth, oldHeight
print("HYGIENE_EFFECTS_PASS checks=19")
