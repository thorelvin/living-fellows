-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.HygieneEffects = SC.HygieneEffects or {}
local Effects = SC.HygieneEffects
local cachedActors, refreshAt = {}, 0
local overlay, overlayClass
local lastReportAt = 0
Effects.nativeDepthSuppressions = Effects.nativeDepthSuppressions or 0
Effects.uiStreamFallbacks = Effects.uiStreamFallbacks or 0

local function number(value, fallback)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) or fallback end
    return fallback
end

local function call(object, method, ...)
    local utility = SC.GameplayUtil
    if not utility or type(utility.call) ~= "function" then return nil end
    return select(1, utility.call(object, method, ...))
end

local function facing(actor)
    -- The native animation player eases its rendered angle toward the actor's
    -- target direction. Reading getDir/getForwardDirection here makes the
    -- stream arrive at a new bearing before the body has visibly turned.
    local angle = number(call(actor, "getAnimAngleRadians"), nil)
    if angle and angle == angle then
        return math.cos(angle), math.sin(angle)
    end
    local direction = call(actor, "getDir")
    local x = number(call(direction, "dx"), 0)
    local y = number(call(direction, "dy"), 0)
    local length = math.sqrt(x * x + y * y)
    if length < 0.01 then
        x = number(call(actor, "getForwardDirectionX"), 0)
        y = number(call(actor, "getForwardDirectionY"), 0)
        length = math.sqrt(x * x + y * y)
    end
    if length < 0.01 then return 0, 1 end
    return x / length, y / length
end

local function viewport(index)
    if type(getPlayerScreenLeft) == "function"
        and type(getPlayerScreenTop) == "function"
        and type(getPlayerScreenWidth) == "function"
        and type(getPlayerScreenHeight) == "function" then
        local left = number(getPlayerScreenLeft(index), nil)
        local top = number(getPlayerScreenTop(index), nil)
        local width = number(getPlayerScreenWidth(index), nil)
        local height = number(getPlayerScreenHeight(index), nil)
        if left and top and width and height and width > 0 and height > 0 then
            return left, top, left + width, top + height
        end
    end
    if index ~= 0 then return nil end
    local core = type(getCore) == "function" and getCore() or nil
    local width = number(call(core, "getScreenWidth"), nil)
    local height = number(call(core, "getScreenHeight"), nil)
    if width and height then return 0, 0, width, height end
    return nil
end

local function projected(index, x, y, z)
    if type(isoToScreenX) ~= "function"
        or type(isoToScreenY) ~= "function" then return nil end
    local okX, sx = pcall(isoToScreenX, index, x, y, z)
    local okY, sy = pcall(isoToScreenY, index, x, y, z)
    if not okX or not okY then return nil end
    return number(sx, nil), number(sy, nil)
end

local function clipped(x1, y1, x2, y2, left, top, right, bottom)
    local dx, dy = x2 - x1, y2 - y1
    local lo, hi = 0, 1
    local tests = {
        { -dx, x1 - left }, { dx, right - x1 },
        { -dy, y1 - top }, { dy, bottom - y1 },
    }
    for _, test in ipairs(tests) do
        local p, q = test[1], test[2]
        if p == 0 then
            if q < 0 then return nil end
        else
            local t = q / p
            if p < 0 then
                if t > hi then return nil end
                if t > lo then lo = t end
            else
                if t < lo then return nil end
                if t < hi then hi = t end
            end
        end
    end
    return x1 + lo * dx, y1 + lo * dy,
        x1 + hi * dx, y1 + hi * dy
end

local function drawWorldLine(canvas, index, bounds,
    x1, y1, z1, x2, y2, z2, thickness, alpha, red, green, blue)
    local sx1, sy1 = projected(index, x1, y1, z1)
    local sx2, sy2 = projected(index, x2, y2, z2)
    if not sx1 or not sy1 or not sx2 or not sy2 then return false end
    local ax, ay, bx, by = clipped(sx1, sy1, sx2, sy2,
        bounds[1], bounds[2], bounds[3], bounds[4])
    if not ax then return false end
    canvas:drawLineAbsolute(nil, ax, ay, bx, by,
        thickness, alpha, red, green, blue)
    return true
end

local function visibleToPlayer(actor, index, player, square, x, y, z)
    if not player or call(player, "getZ") ~= z then return false end
    local px, py = call(player, "getX"), call(player, "getY")
    local dx, dy = px and px - x or 100, py and py - y or 100
    return dx * dx + dy * dy < 18 * 18
        and number(call(actor, "getTargetAlpha", index), 1) > 0.05
end

local function streamOrigin(actor, x, y, z, fx, fy)
    -- The bridge reads the rendered pelvis bone. A tile pivot is several
    -- pixels away from the pelvis in diagonal poses and cannot anchor an
    -- effect that has to turn with the character model.
    local px = number(call(actor, "getCompanionPelvisWorldX"), nil)
    local py = number(call(actor, "getCompanionPelvisWorldY"), nil)
    local pz = number(call(actor, "getCompanionPelvisWorldZ"), nil)
    if px and py and pz and px == px and py == py and pz == pz
        and math.abs(px - x) < 1 and math.abs(py - y) < 1
        and pz > z + 0.08 and pz < z + 1.1 then
        return px + fx * 0.035, py + fy * 0.035, pz
    end
    return x + fx * 0.04, y + fy * 0.04, z + 0.27
end

local function streamPoint(sourceX, sourceY, sourceZ,
    targetX, targetY, groundZ, progress)
    local height = sourceZ + 0.04 * progress
        - (sourceZ - groundZ + 0.02) * progress * progress
    return sourceX + (targetX - sourceX) * progress,
        sourceY + (targetY - sourceY) * progress,
        math.max(groundZ + 0.02, height)
end

local function streamJoin(first, second)
    if not first then return second.x, second.y end
    if not second then return first.x, first.y end
    local nx, ny = first.x + second.x, first.y + second.y
    local length = math.sqrt(nx * nx + ny * ny)
    if length < 0.01 then return second.x, second.y end
    nx, ny = nx / length, ny / length
    local scale = math.min(1.5, 1 / math.max(0.25,
        nx * second.x + ny * second.y))
    return nx * scale, ny * scale
end

local function drawStreamSegment(canvas, bounds, first, last,
    firstJoin, lastJoin, normal, halfWidth, alpha, red, green, blue,
    offsetX, offsetY)
    local inset = 3
    local ax, ay, bx, by = clipped(first.x, first.y, last.x, last.y,
        bounds[1] + inset, bounds[2] + inset,
        bounds[3] - inset, bounds[4] - inset)
    if not ax then return false end
    local startX, startY = firstJoin.x, firstJoin.y
    local endX, endY = lastJoin.x, lastJoin.y
    if math.abs(ax - first.x) + math.abs(ay - first.y) > 0.001 then
        startX, startY = normal.x, normal.y
    end
    if math.abs(bx - last.x) + math.abs(by - last.y) > 0.001 then
        endX, endY = normal.x, normal.y
    end
    ax, ay, bx, by = ax + offsetX, ay + offsetY,
        bx + offsetX, by + offsetY
    canvas:drawPolygon(nil,
        ax + startX * halfWidth, ay + startY * halfWidth,
        bx + endX * halfWidth, by + endY * halfWidth,
        bx - endX * halfWidth, by - endY * halfWidth,
        ax - startX * halfWidth, ay - startY * halfWidth,
        red, green, blue, alpha)
    return true
end

function Effects.renderStream(canvas, index, bounds, actor, x, y, z, now, toilet)
    local fx, fy = facing(actor)
    local reach = 0.52
    if toilet and toilet.object then
        local tx, ty = call(toilet.object, "getX"),
            call(toilet.object, "getY")
        if tx and ty then
            local dx, dy = tx + 0.5 - x, ty + 0.5 - y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance > 0.1 then
                fx, fy = dx / distance, dy / distance
                reach = math.max(0.2, distance - 0.04)
            end
        end
    end
    local sourceX, sourceY, sourceZ = streamOrigin(actor, x, y, z, fx, fy)
    local targetX = x + fx * (0.04 + reach)
    local targetY = y + fy * (0.04 + reach)
    -- The native bridge queues the same curve in the character's world pass.
    -- Keep this UI renderer as a fallback until that viewport has submitted
    -- at least one recent depth-tested frame.
    local nativeAccepted = call(actor, "setCompanionPeeStream",
        sourceX, sourceY, sourceZ, targetX, targetY)
    if nativeAccepted == true
        and call(actor, "isCompanionPeeStreamDepthReady", index) == true then
        Effects.nativeDepthSuppressions = Effects.nativeDepthSuppressions + 1
        return true
    end
    local points, normals, joins = {}, {}, {}
    for step = 0, 10 do
        local progress = step / 10
        local wx, wy, wz = streamPoint(sourceX, sourceY, sourceZ,
            targetX, targetY, z, progress)
        local sx, sy = projected(index, wx, wy, wz)
        if not sx or not sy then return false end
        points[step + 1] = {
            x = sx,
            y = sy,
        }
    end
    for segment = 1, 10 do
        local dx = points[segment + 1].x - points[segment].x
        local dy = points[segment + 1].y - points[segment].y
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.001 then return false end
        normals[segment] = { x = -dy / length, y = dx / length }
    end
    for point = 1, 11 do
        local nx, ny = streamJoin(normals[point - 1], normals[point])
        joins[point] = { x = nx, y = ny }
    end
    local offsetX = -number(call(canvas, "getAbsoluteX"), 0)
        - number(call(canvas, "getXScroll"), 0)
    local offsetY = -number(call(canvas, "getAbsoluteY"), 0)
        - number(call(canvas, "getYScroll"), 0)
    local drawn = false
    for segment = 1, 10 do
        local first, last = points[segment], points[segment + 1]
        local normal = normals[segment]
        local firstJoin, lastJoin = joins[segment], joins[segment + 1]
        drawn = drawStreamSegment(canvas, bounds, first, last,
            firstJoin, lastJoin, normal, 1,
            0.32, 0.28, 0.18, 0.04, offsetX, offsetY) or drawn
        drawn = drawStreamSegment(canvas, bounds, first, last,
            firstJoin, lastJoin, normal, 0.5,
            0.55, 1.00, 0.88, 0.39, offsetX, offsetY) or drawn
    end
    if drawn then Effects.uiStreamFallbacks = Effects.uiStreamFallbacks + 1 end
    return drawn
end

function Effects.renderShower(canvas, index, bounds, x, y, z, now)
    local phase = now / 900
    local drawn = false
    for dot = 0, 6 do
        local step = (phase + dot / 7) % 1
        local angle = dot * 2.39996
        local spread = 0.08 + step * 0.14
        local px = x + math.cos(angle) * spread
        local py = y + math.sin(angle) * spread
        local height = z + 0.08 + 0.39 * step
        drawn = drawWorldLine(canvas, index, bounds,
            px, py, height, px + 0.012, py + 0.012, height + 0.022,
            2, 0.22 * (1 - step), 0.78, 0.89, 0.96) or drawn
    end
    return drawn
end

function Effects.renderScreen(canvas)
    if not canvas or type(canvas.drawLineAbsolute) ~= "function"
        or type(canvas.drawPolygon) ~= "function" then
        return false
    end
    local registry = SC.Registry
    if not registry or type(registry.living) ~= "function" then return false end
    local utility = SC.GameplayUtil
    local now = utility and type(utility.nowMs) == "function"
        and utility.nowMs() or 0
    if now >= refreshAt then
        cachedActors = registry.living() or {}
        refreshAt = now + 250
    end
    local drawn = false
    for _, actor in ipairs(cachedActors) do
        local pee = SC.Needs and type(SC.Needs.peek) == "function"
            and SC.Needs.peek(actor) or nil
        local task = pee and pee.pee
        local downtime = SC.Downtime and type(SC.Downtime.peek) == "function"
            and SC.Downtime.peek(actor) or nil
        local shower = downtime and downtime.active
        local standing = task and task.phase == "animating"
            and task.sits ~= true and call(actor, "isFemale") ~= true
        if not standing then call(actor, "clearCompanionPeeStream") end
        local washing = shower and shower.kind == "shower"
            and shower.actionAccepted == true
            and shower.approaching ~= true
        if standing or washing then
            local x, y, z = call(actor, "getX"),
                call(actor, "getY"), call(actor, "getZ")
            local square = call(actor, "getCurrentSquare")
            if x and y and z and square then
                for index = 0, 3 do
                    local player = type(getSpecificPlayer) == "function"
                        and getSpecificPlayer(index) or nil
                    if visibleToPlayer(actor, index, player, square, x, y, z) then
                        local left, top, right, bottom = viewport(index)
                        if left then
                            local bounds = { left, top, right, bottom }
                            if standing then
                                drawn = Effects.renderStream(canvas, index,
                                    bounds, actor, x, y, z, now,
                                    task.toilet) or drawn
                            end
                            if washing then
                                drawn = Effects.renderShower(canvas, index,
                                    bounds, x, y, z, now) or drawn
                            end
                        end
                    end
                end
            end
        end
    end
    return drawn
end

function Effects.ensureOverlay()
    if overlay and overlay.removed ~= true then return true end
    local loaded, failure = pcall(require, "ISUI/ISUIElement")
    if not loaded or type(ISUIElement) ~= "table" then
        return false, tostring(failure or "ui_element_unavailable")
    end
    if not overlayClass then
        overlayClass = ISUIElement:derive("SCHygieneOverlay")
        function overlayClass:render()
            local core = type(getCore) == "function" and getCore() or nil
            local width = number(call(core, "getScreenWidth"), 1)
            local height = number(call(core, "getScreenHeight"), 1)
            if self:getWidth() ~= width then self:setWidth(width) end
            if self:getHeight() ~= height then self:setHeight(height) end
            local ok, reason = pcall(Effects.renderScreen, self)
            if not ok then
                local now = SC.GameplayUtil and SC.GameplayUtil.nowMs
                    and SC.GameplayUtil.nowMs() or 0
                if now - lastReportAt >= 5000 then
                    lastReportAt = now
                    print("[LivingFellows] hygiene effect render failed: "
                        .. tostring(reason))
                    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                        SC.Diagnostics.report("hygiene-effects", nil,
                            "screen effect render failed", reason)
                    end
                end
            end
        end
    end
    local core = type(getCore) == "function" and getCore() or nil
    overlay = overlayClass:new(0, 0,
        number(call(core, "getScreenWidth"), 1),
        number(call(core, "getScreenHeight"), 1))
    overlay:initialise()
    overlay:setWantMouseEvents(false)
    overlay:addToUIManager()
    overlay:bringToTop()
    return true
end

function Effects.remove()
    for _, actor in ipairs(cachedActors) do
        call(actor, "clearCompanionPeeStream")
    end
    if overlay then overlay:removeFromUIManager() end
    overlay = nil
    cachedActors, refreshAt = {}, 0
    return true
end

return Effects
