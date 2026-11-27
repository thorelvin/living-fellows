-- SPDX-License-Identifier: MIT
-- One LF-owned local companion view, shared by expeditions and Base Watch.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
SC.ViewSession = SC.ViewSession or {}
local View = SC.ViewSession

local owner
local reservation
local reusableSlotSqlId
local primaryRestore
local primaryRestoreStatus, primaryRestoreReason = "idle", nil

local function cleanupReleasedUi()
    if SC.ViewUI and type(SC.ViewUI.cleanup) == "function" then
        local okay, reason = pcall(SC.ViewUI.cleanup)
        if not okay then print("Living Fellows: companion view UI cleanup failed: " .. tostring(reason)) end
    end
end

local function restoreCapability()
    if SCSplitScreenProbe == nil
        or type(SCSplitScreenProbe.pollPrimaryViewRestore) ~= "function" then
        return false, "local_view_restore_bridge_unavailable"
    end
    if Events == nil or Events.OnPostRender == nil
        or type(Events.OnPostRender.Add) ~= "function"
        or type(Events.OnPostRender.Remove) ~= "function" then
        return false, "local_view_restore_event_unavailable"
    end
    return true
end

local function finishPrimaryRestore(status, reason)
    local pending = primaryRestore
    primaryRestore = nil
    if pending then
        pending.active = false
        local removed, failure = pcall(pending.event.Remove, pending.callback)
        if not removed then
            status, reason = "failed", "render hook removal failed: " .. tostring(failure)
        end
    end
    primaryRestoreStatus = status
    cleanupReleasedUi()
    primaryRestoreReason = reason and string.sub(tostring(reason), 1, 512) or nil
    local detail = primaryRestoreReason
    if SCSplitScreenProbe and type(SCSplitScreenProbe.releaseDiagnostics) == "function" then
        local described, native = pcall(SCSplitScreenProbe.releaseDiagnostics)
        if described then detail = tostring(native) end
    end
    print("[LivingFellows/view-restore] status=" .. tostring(status)
        .. " owner=" .. tostring(owner) .. " detail=" .. tostring(detail))
    if status == "failed" then
        if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            pcall(SC.Diagnostics.report, "view_restore", nil,
                "primary view restore failed", primaryRestoreReason)
        else
            print("Living Fellows: primary view restore failed: "
                .. tostring(primaryRestoreReason))
        end
    end
end

local function cancelPrimaryRestore()
    if primaryRestore then finishPrimaryRestore("cancelled") end
end

local function queuePrimaryRestore()
    cancelPrimaryRestore()
    local ready, reason = restoreCapability()
    if not ready then finishPrimaryRestore("failed", reason) return end
    local pending = { event = Events.OnPostRender, active = true }
    pending.callback = function()
        -- A late event callback cannot apply a previous world's or previous
        -- view's recovery after reset, promotion, or terminal hook removal.
        if not pending.active or primaryRestore ~= pending then return end
        if owner ~= nil then finishPrimaryRestore("cancelled") return end
        local native = SCSplitScreenProbe
        if native == nil or type(native.pollPrimaryViewRestore) ~= "function" then
            finishPrimaryRestore("failed", "local_view_restore_bridge_unavailable")
            return
        end
        local called, status = pcall(native.pollPrimaryViewRestore)
        if called and status == "waiting" then return end
        if called and (status == "applied" or status == "cancelled") then
            finishPrimaryRestore(status)
            return
        end
        local failure = called and "unexpected native restore status: " .. tostring(status)
            or "native restore call failed: " .. tostring(status)
        if called and status == "failed" then
            failure = "native primary view restore failed"
            if type(native.releaseDiagnostics) == "function" then
                local described, detail = pcall(native.releaseDiagnostics)
                if described then failure = tostring(detail) end
            end
        end
        finishPrimaryRestore("failed", failure)
    end
    primaryRestore = pending
    primaryRestoreStatus, primaryRestoreReason = "waiting", nil
    local added, failure = pcall(pending.event.Add, pending.callback)
    if not added then finishPrimaryRestore("failed", "render hook install failed: " .. tostring(failure)) end
end

function View.primaryRestoreDiagnostic()
    return { status = primaryRestoreStatus, reason = primaryRestoreReason,
        pending = primaryRestore ~= nil }
end

local function validSlotId(value)
    return type(value) == "number" and value >= 2 and value <= 2147483647
        and value == math.floor(value)
end

local function restorePrimaryHud()
    -- B42's split-screen resize moves the clock to the bottom of the view.
    -- Its single-player resize restores the X coordinate but leaves Y there,
    -- putting both the clock and speed controls below the screen after the
    -- companion's second view is released.
    if type(getSpecificPlayer) ~= "function"
        or getSpecificPlayer(0) == nil or getSpecificPlayer(1) ~= nil
        or UIManager == nil then return end
    local ok, clock = pcall(UIManager.getClock)
    if not ok or clock == nil then return end
    local restored, reason = pcall(function()
        clock:setY(10)
        UIManager.resize()
    end)
    if not restored then
        print("Living Fellows: primary HUD restore failed: " .. tostring(reason))
    end
end

local function restoreExpeditionZoom()
    if SCBridge == nil or SCBridge.restoreExpeditionZoom == nil then return end
    local ok, restored = pcall(SCBridge.restoreExpeditionZoom)
    if not ok or restored ~= true then
        print("Living Fellows: expedition zoom restore failed: " .. tostring(restored))
    end
end

function View.owner() return owner end
function View.slotSqlId() return reusableSlotSqlId end

function View.reservedFor(mode, id)
    return reservation ~= nil and reservation.mode == mode and reservation.id == id
end

function View.blockedFor(mode)
    return reservation ~= nil and reservation.mode ~= mode
end

function View.reserve(mode, id)
    if mode ~= "pickup" or type(id) ~= "string" or #id < 1 or #id > 128 then
        return false, "invalid_companion_view_reservation"
    end
    if reservation then
        return View.reservedFor(mode, id), "companion_view_reserved"
    end
    if owner ~= nil and owner ~= "base_watch" then return false, "companion_view_in_use" end
    reservation = { mode = mode, id = id }
    return true
end

function View.unreserve(mode, id)
    if not View.reservedFor(mode, id) then return false, "companion_view_reservation_changed" end
    if owner == mode then return false, "companion_view_still_owned" end
    reservation = nil
    return true
end

-- The native handoff must have committed before the Lua owner changes.
function View.transfer(from, to, actor, id)
    if owner ~= from or not ((from == "base_watch" and to == "pickup")
        or (from == "pickup" and to == "base_watch"))
        or not View.reservedFor("pickup", id) or not SCSplitScreenProbe
        or getSpecificPlayer(1) ~= actor or SCSplitScreenProbe.isLeader(actor) ~= true then
        return false, "companion_view_owner_mismatch"
    end
    owner = to
    if SC.ViewUI and SC.ViewUI.remember then SC.ViewUI.remember(actor) end
    return true
end

function View.loadPickupArea(id, at)
    if not View.reservedFor("pickup", id) or owner ~= nil then
        return false, "companion_view_in_use"
    end
    local ready, reason = restoreCapability()
    if not ready then return false, reason end
    local called, loader = pcall(SCSplitScreenProbe.startColdCompanionProbe,
        math.floor(at.x), math.floor(at.y), math.floor(at.z), reusableSlotSqlId or -1)
    if not called or not loader then return false, tostring(loader) end
    cancelPrimaryRestore()
    owner = "pickup"
    return true, loader
end

function View.rememberSlotSqlId(value)
    if not validSlotId(value) then return false, "invalid_companion_view_slot" end
    reusableSlotSqlId = value
    return true
end

function View.loadHandoverArea(point)
    if owner~=nil or reservation~=nil then return nil,"companion_view_in_use" end
    local ready,reason=restoreCapability();if not ready then return nil,reason end
    local called,loader=pcall(SCSplitScreenProbe.startColdCompanionProbe,
        math.floor(point.x),math.floor(point.y),math.floor(point.z),reusableSlotSqlId or -1)
    if not called or not loader then return nil,tostring(loader) end
    cancelPrimaryRestore();owner="handover"
    if SC.ViewUI then SC.ViewUI.remember(loader) end
    return loader
end

function View.claim(mode, actor, legacySlotId)
    if mode ~= "expedition" and mode ~= "base_watch" and mode ~= "pickup" and mode ~= "handover" then
        return false, "invalid_companion_view_mode"
    end
    if View.blockedFor(mode) then return false, "pickup_uses_companion_view" end
    local ready, reason = restoreCapability()
    if not ready then return false, reason end
    if owner == mode and SCSplitScreenProbe ~= nil
        and SCSplitScreenProbe.isLeader(actor) == true then
        -- AddCoopPlayer joins on a later engine tick. A restore pulse may
        -- revisit this claim while that exact actor is still pending.
        return true, actor
    end
    if owner ~= nil then return false, "companion_view_in_use" end
    if SCSplitScreenProbe == nil then return false, "local_view_unavailable" end
    local slotId = reusableSlotSqlId or legacySlotId or -1
    if type(SCSplitScreenProbe.promotionBlocker) == "function" then
        local blocker = SCSplitScreenProbe.promotionBlocker(actor, slotId)
        if (blocker == "companion_promotion_saved_identity" or blocker == "companion_promotion_primary_identity")
            and validSlotId(legacySlotId) and legacySlotId ~= slotId
            and SCSplitScreenProbe.promotionBlocker(actor, legacySlotId) == nil then
            -- The restoring owner may have an exact saved slot that is
            -- newer than the shared reusable ID. Native readiness must
            -- prove that this ID belongs to the actor and is safe to use.
            slotId, blocker = legacySlotId, nil
        end
        if blocker ~= nil then return false, tostring(blocker) end
    end
    cleanupReleasedUi()
    local called, promoted = pcall(SCSplitScreenProbe.promote, actor, slotId)
    if not called or promoted ~= actor then return false, tostring(promoted) end
    cancelPrimaryRestore()
    owner = mode
    if validSlotId(slotId) then reusableSlotSqlId = slotId end
    if SC.ViewUI and type(SC.ViewUI.remember) == "function" then SC.ViewUI.remember(actor) end
    return true, actor
end

-- The cold loader or a restored companion already holds native slot 1.
function View.adopt(mode, actor, slotId)
    if mode ~= "expedition" and mode ~= "base_watch" and mode ~= "pickup" and mode ~= "handover" then
        return false, "invalid_companion_view_mode"
    end
    if View.blockedFor(mode) then return false, "pickup_uses_companion_view" end
    local ready, reason = restoreCapability()
    if not ready then return false, reason end
    if owner ~= nil and owner ~= mode then return false, "companion_view_in_use" end
    if actor == nil or type(getSpecificPlayer) ~= "function"
        or getSpecificPlayer(1) ~= actor or SCSplitScreenProbe == nil
        or SCSplitScreenProbe.isLeader(actor) ~= true then
        return false, "companion_view_owner_mismatch"
    end
    if validSlotId(slotId) then reusableSlotSqlId = slotId end
    cancelPrimaryRestore()
    owner = mode
    if SC.ViewUI and type(SC.ViewUI.remember) == "function" then SC.ViewUI.remember(actor) end
    return true
end

function View.released(mode, slotId, worldExit)
    if owner ~= mode then return false, "companion_view_owner_mismatch" end
    if validSlotId(slotId) then reusableSlotSqlId = slotId end
    if mode == "expedition" or mode == "pickup" then restoreExpeditionZoom() end
    owner = nil
    cleanupReleasedUi()
    restorePrimaryHud()
    if worldExit == true then cancelPrimaryRestore()
    else queuePrimaryRestore() end
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
    cancelPrimaryRestore()
    cleanupReleasedUi()
    if owner == "expedition" or owner == "pickup" then restoreExpeditionZoom() end
    owner, reusableSlotSqlId, reservation = nil, nil, nil
    return true
end

return View
