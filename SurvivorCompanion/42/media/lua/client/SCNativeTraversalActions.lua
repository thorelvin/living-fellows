-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeTraversalActions = SC.NativeTraversalActions or {}
local Traversal = SC.NativeTraversalActions
local context

function Traversal.configure(value)
    assert(type(value) == "table", "native traversal context is required")
    context = value
    return Traversal
end

local function invoke(object, name, ...)
    return context.invoke(object, name, ...)
end

local function useProvider(provider, operation, ...)
    return context.useProvider(provider, operation, ...)
end

function Traversal.window(actor, action, intent, provider)
    local object = intent.object
    if object == nil then return false, "window action has no object" end
    local handled, reason = useProvider(provider, "window", actor, action, object, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end

    if action == "open_window" then
        local started, failure = invoke(actor, "openWindow", object)
        if not started then return false, failure end
        local verified, opened = invoke(object, "IsOpen")
        if not verified or opened ~= true then return false, "window open was not verified" end
        return true, "window_opened"
    elseif action == "smash_window" then
        local started, failure = invoke(actor, "smashWindow", object)
        if not started then return false, failure end
        local verified, smashed = invoke(object, "isSmashed")
        if not verified or smashed ~= true then return false, "window smash was not verified" end
        return true, "window_smashed"
    elseif action == "remove_glass" then
        local started, failure = invoke(object, "removeBrokenGlass")
        if not started then return false, failure end
        local verified, removed = invoke(object, "isGlassRemoved")
        if not verified or removed ~= true then return false, "glass removal was not verified" end
        return true, "glass_removed"
    end

    local started, failure = invoke(actor, "climbThroughWindow", object)
    if not started then return false, failure end
    local climbingOk, climbing = invoke(actor, "isClimbing")
    if not climbingOk or climbing ~= true then
        return false, "native window climb did not start"
    end
    return true, "window_climb_started"
end

local function fenceDirection(intent)
    local name = string.lower(tostring(intent and intent.direction or ""))
    local key = ({ north = "N", south = "S", east = "E", west = "W" })[name]
    local directions = type(_G) == "table" and rawget(_G, "IsoDirections") or nil
    if key == nil or directions == nil then return nil end
    local ok, value = pcall(function() return directions[key] end)
    return ok and value or nil
end

function Traversal.fence(actor, action, intent, provider)
    local direction = fenceDirection(intent)
    if direction == nil then return false, "fence direction is unavailable" end
    local handled, reason = useProvider(provider, "fence", actor, action,
        intent.object, direction, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if context.stopDirect(actor) ~= true then
        return false, "fence climb could not acquire stationary actor"
    end

    if action == "climb_wall" then
        local checked, climbable = invoke(actor, "canClimbOverWall", direction)
        if not checked then return false, "native tall-wall climb check is unavailable" end
        if climbable ~= true then return false, "native tall wall is not climbable" end
        local invoked, started = invoke(actor, "climbOverWall", direction)
        if not invoked then return false, started or "native tall-wall climb failed" end
        if started == false then return false, "native tall-wall climb was rejected" end
    else
        local invoked, failure = invoke(actor, "climbOverFence", direction)
        if not invoked then return false, failure or "native fence climb failed" end
    end
    local climbingOk, climbing = invoke(actor, "isClimbing")
    if not climbingOk or climbing ~= true then
        return false, "native fence climb did not enter a climb state"
    end
    return true, action == "climb_wall" and "wall_climb_started" or "fence_climb_started"
end

function Traversal.sheetRope(actor, action, intent, provider)
    local down = action == "climb_down_sheet_rope"
    local handled, reason = useProvider(provider, "sheetRope", actor, action, down, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if context.stopDirect(actor) ~= true then
        return false, "sheet-rope climb could not acquire stationary actor"
    end
    local squareOk, square = invoke(actor, "getCurrentSquare")
    if not squareOk or square == nil then return false, "actor square is unavailable" end
    local check = down and "canClimbDownSheetRope" or "canClimbSheetRope"
    local checked, climbable = invoke(actor, check, square)
    if not checked then return false, "native sheet-rope climb check is unavailable" end
    if climbable ~= true then return false, "native sheet rope is not climbable" end
    local methodName = down and "climbDownSheetRope" or "climbSheetRope"
    local invoked, failure = invoke(actor, methodName)
    if not invoked then return false, failure or "native sheet-rope climb failed" end
    local climbingOk, climbing = invoke(actor, "isClimbing")
    if not climbingOk or climbing ~= true then
        climbingOk, climbing = invoke(actor, "isClimbingRope")
    end
    if not climbingOk or climbing ~= true then
        return false, "native sheet-rope climb did not enter a climb state"
    end
    return true, down and "sheet_rope_descent_started" or "sheet_rope_climb_started"
end

function Traversal.setDowned(actor, downed, provider)
    local handled, reason = useProvider(provider, "setDowned", actor, downed)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if downed then context.stopDirect(actor) end
    local setOk, failure = invoke(actor, "setKnockedDown", downed)
    if not setOk then return false, failure end
    local checkOk, current = invoke(actor, "isKnockedDown")
    if not checkOk or current ~= downed then
        return false, "native downed state was not retained"
    end
    return true, downed and "downed" or "recovered"
end

return Traversal
