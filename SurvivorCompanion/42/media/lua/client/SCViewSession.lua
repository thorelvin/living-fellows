-- SPDX-License-Identifier: MIT
-- One LF-owned local companion view, shared by expeditions and Base Watch.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ViewSession = SC.ViewSession or {}
local View = SC.ViewSession

local owner
local reusableSlotSqlId

local function validSlotId(value)
    return type(value) == "number" and value >= 2 and value <= 2147483647
        and value == math.floor(value)
end

function View.owner() return owner end
function View.slotSqlId() return reusableSlotSqlId end

function View.rememberSlotSqlId(value)
    if not validSlotId(value) then return false, "invalid_companion_view_slot" end
    reusableSlotSqlId = value
    return true
end

function View.claim(mode, actor, legacySlotId)
    if mode ~= "expedition" and mode ~= "base_watch" then
        return false, "invalid_companion_view_mode"
    end
    if owner == mode and SCSplitScreenProbe ~= nil
        and SCSplitScreenProbe.isLeader(actor) == true then
        -- AddCoopPlayer joins on a later engine tick. A restore pulse may
        -- revisit this claim while that exact actor is still pending.
        return true, actor
    end
    if owner ~= nil then return false, "companion_view_in_use" end
    if SCSplitScreenProbe == nil then return false, "local_view_unavailable" end
    local slotId = reusableSlotSqlId or legacySlotId or -1
    local called, promoted = pcall(SCSplitScreenProbe.promote, actor, slotId)
    if not called or promoted ~= actor then return false, tostring(promoted) end
    owner = mode
    return true, actor
end

-- The cold loader or a restored companion already holds native slot 1.
function View.adopt(mode, actor, slotId)
    if mode ~= "expedition" and mode ~= "base_watch" then
        return false, "invalid_companion_view_mode"
    end
    if owner ~= nil and owner ~= mode then return false, "companion_view_in_use" end
    if actor == nil or type(getSpecificPlayer) ~= "function"
        or getSpecificPlayer(1) ~= actor or SCSplitScreenProbe == nil
        or SCSplitScreenProbe.isLeader(actor) ~= true then
        return false, "companion_view_owner_mismatch"
    end
    if validSlotId(slotId) then reusableSlotSqlId = slotId end
    owner = mode
    return true
end

function View.released(mode, slotId)
    if owner ~= mode then return false, "companion_view_owner_mismatch" end
    if validSlotId(slotId) then reusableSlotSqlId = slotId end
    owner = nil
    return true
end

function View.export()
    if not validSlotId(reusableSlotSqlId) then return nil end
    return { schema = 1, slotSqlId = reusableSlotSqlId }
end

function View.restore(saved)
    if type(saved) ~= "table" or saved.schema ~= 1
        or not validSlotId(saved.slotSqlId) then
        return false, "invalid_companion_view_slot"
    end
    if owner ~= nil then return false, "companion_view_in_use" end
    reusableSlotSqlId = saved.slotSqlId
    return true
end

function View.reset()
    owner, reusableSlotSqlId = nil, nil
    return true
end

return View
