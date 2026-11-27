-- SPDX-License-Identifier: MIT
-- The pickup's owned world/view boundaries. This module never moves a car or
-- fabricates a survivor; normal navigation and persistence own both operations.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
local J = {}
SC.PickupJourney = J
local context

local function U() return SC.GameplayUtil end
local function call(object, name, ...)
    if not object then return nil end
    return (U().call(object, name, ...))
end
local function native(name, ...)
    if not SCSplitScreenProbe then return false, "pickup_bridge_unavailable" end
    local method = SCSplitScreenProbe[name]
    if not method then return false, "pickup_bridge_unavailable" end
    local okay, result = pcall(method, ...)
    return okay and result ~= false and result ~= nil, result
end
local function player() return getSpecificPlayer and getSpecificPlayer(0) end
local function second() return getSpecificPlayer and getSpecificPlayer(1) end
local function alive(actor) return actor and call(actor, "isDead") == false end
local function at(object)
    local x, y, z = U().position(object)
    return x and { x = x, y = y, z = z } or nil
end
local function nearby(a, b, limit)
    local first, last = at(a), at(b)
    return first and last and first.z == last.z
        and (first.x - last.x)^2 + (first.y - last.y)^2 <= limit * limit
end
local function walk(actor, target)
    if nearby(actor, target, 12) then return true end
    if not SC.Navigation then return false, "pickup_navigation_unavailable" end
    local destination=at(target)
    if not destination then return false,"pickup_handoff_target_unavailable" end
    local okay, reason = SC.Navigation.request(actor, destination, "walk", {
        action = "pickup_view_handoff", desiredDistance = 2,
        arrivalDistance = 2, continuousApproach = true, followRecovery = true,
    })
    return false, okay and "pickup_handoff_approach" or reason
end

function J.available()
    local okay, capable = native("pickupJourneyCapability")
    return okay and capable == true
end

function J.setContext(value) context = value end

function J.reserve(ctx)
    if not J.available() then return false, "pickup_bridge_unavailable" end
    if SC.ExpeditionPrototype and SC.ExpeditionPrototype.current()
        then return false, "pickup_other_trip_active" end
    local okay, reason = SC.ViewSession.reserve("pickup", ctx.requestId)
    if okay then context = ctx end
    return okay, reason
end

function J.canRestore(id, position)
    local ctx = context
    if not ctx or not position or not SC.ViewSession.reservedFor("pickup", ctx.requestId)
        or SC.ViewSession.owner() ~= "pickup" then return false end
    local okay, contains = native("secondaryAreaContains", math.floor(position.x),
        math.floor(position.y), math.floor(position.z))
    if not okay or contains ~= true then return false end
    if ctx.restoring and id == ctx.driverId and ctx.restorePoint then
        local saved = ctx.restorePoint
        -- The ordinary restore adapter may choose a free neighbour when the
        -- saved square is occupied, including by this owned cold loader.
        return math.floor(position.z) == math.floor(saved.z)
            and (position.x-saved.x)^2+(position.y-saved.y)^2<=36
    end
    if not SC.HomeTrip.campUnchanged(ctx.camp) then return false end
    local resident = SC.BaseLife.resident(id)
    local area = ctx.camp.arrival
    if not resident or resident.baseId ~= ctx.camp.id
        or position.x < area.x1 or position.x >= area.x2 + 1
        or position.y < area.y1 or position.y >= area.y2 + 1 then return false end
    for _, candidateId in ipairs(ctx.candidateIds or {}) do
        if candidateId == id then return true end
    end
    return false
end

function J.warm(ctx)
    local okay, reason = J.reserve(ctx)
    if not okay then return false, reason end
    if not ctx.restoring and not SC.HomeTrip.campUnchanged(ctx.camp)
        then return false, "pickup_camp_changed" end
    local watch = SC.BaseWatch and SC.BaseWatch.current()
    if watch and not watch.pickupOwner then
        if watch.restoring or watch.joining then return false, "pickup_loading_camp" end
        return second() == watch.leaderActor, "pickup_loading_camp"
    end
    local anchor = ctx.restoring and ctx.restorePoint or ctx.camp.core
    if not anchor then return false, "pickup_restore_position_missing" end
    local square = U().gridSquare(math.floor(anchor.x), math.floor(anchor.y), math.floor(anchor.z))
    local _, primaryOwns = native("primaryAreaContains", math.floor(anchor.x), math.floor(anchor.y), math.floor(anchor.z))
    local _, secondaryOwns = native("secondaryAreaContains", math.floor(anchor.x), math.floor(anchor.y), math.floor(anchor.z))
    if ctx.loader then
        if second() ~= ctx.loader then return false, "pickup_loading_camp" end
        local adopted, why = SC.ViewSession.adopt("pickup", ctx.loader, ctx.slotSqlId)
        if not adopted then return false, why end
        return square ~= nil and secondaryOwns == true, "pickup_loading_camp"
    end
    if square and (primaryOwns == true or secondaryOwns == true) then return true end
    if second() ~= nil then return false, "pickup_view_in_use" end
    local started, loader = SC.ViewSession.loadPickupArea(ctx.requestId, anchor)
    if not started then return false, loader end
    ctx.loader = loader
    return false, "pickup_loading_camp"
end

function J.acquire(ctx, actor)
    if not alive(actor) then return false, "pickup_driver_unavailable" end
    context = ctx
    local slot = second()
    local watch = SC.BaseWatch and SC.BaseWatch.current()
    if watch and SC.ViewSession.owner() == "base_watch" then
        local paused, prior = SC.BaseWatch.pauseForPickup(ctx.requestId)
        if not paused then return false, prior end
        ctx.watchPaused = true
        if prior ~= actor then
            ctx.handoffActor = prior
            local arrived, reason = walk(actor, prior)
            if not arrived then return false, reason end
            U().stop(actor)
            local moved, successor = native("handoffLiving", actor)
            if not moved or successor ~= actor then return false, "pickup_handoff_pending" end
        end
        local changed, why = SC.ViewSession.transfer("base_watch", "pickup", actor, ctx.requestId)
        if not changed then return false, why end
        ctx.handoffActor = nil
        slot = actor
    end
    if slot and slot ~= actor then
        if SCSplitScreenProbe.isColdProbe(slot) ~= true or ctx.loader and slot ~= ctx.loader
            then return false, "pickup_view_owner_changed" end
        local arrived, why = walk(actor, slot)
        if not arrived then return false, why end
        U().stop(actor)
        local replaced, result = native("replaceColdProbeWithRestoredLeader", actor,
            ctx.slotSqlId or SC.ViewSession.slotSqlId() or -1)
        if not replaced or result ~= true then return false, "pickup_handoff_pending" end
        ctx.loader = nil
        slot = actor
    end
    if not slot then
        if ctx.loader then return false, "pickup_loading_camp" end
        if SCSplitScreenProbe.isLeader(actor) == true then return false, "pickup_view_join_pending" end
        local claimed, why = SC.ViewSession.claim("pickup", actor, ctx.slotSqlId)
        if not claimed then return false, why end
        ctx.uiDetached = nil
        return false, "pickup_view_join_pending"
    end
    local okay, sqlId = native("leaderSqlId")
    if okay and type(sqlId) == "number" and sqlId >= 2 then ctx.slotSqlId = sqlId end
    local adopted, why = SC.ViewSession.adopt("pickup", actor, ctx.slotSqlId)
    if not adopted then return false, why end
    return true
end

function J.releaseNear(ctx, actor, car)
    if SC.ViewSession.owner() ~= "pickup" then
        return second() == nil, "pickup_view_owner_changed"
    end
    if SC.Vehicle.isStationary(car) ~= true then return false, "pickup_waiting_for_stop" end
    if call(car, "getDriver") ~= actor then return false, "pickup_driver_changed" end
    if call(car, "isEngineRunning") == true then
        call(car, "shutOff")
        return false, "pickup_waiting_for_stop"
    end
    local ready, retains = native("primaryRetainsPickupVehicle", car, ctx.carSqlId, actor)
    if not ready or retains ~= true then return false, "pickup_primary_car_pending" end
    local can, joined = native("canReleaseJoinedLeader")
    if not can or joined ~= true then return false, "pickup_primary_view_pending" end
    local saved, slotId = native("persistJoinedLeaderSlotForReuse")
    if not saved or type(slotId) ~= "number" or slotId < 2 then return false, "pickup_slot_save_failed" end
    ctx.slotSqlId = slotId
    if not ctx.uiDetached then
        local okay = type(destroyPlayerData) == "function" and pcall(destroyPlayerData, actor)
        if not okay then return false, "pickup_ui_release_pending" end
        ctx.uiDetached = true
    end
    local released, result = native("releaseJoinedLeader")
    if not released or result ~= true then return false, "pickup_view_release_pending" end
    return SC.ViewSession.released("pickup", slotId)
end

function J.closePreview(ctx)
    if SC.ViewSession.owner() == "pickup" then
        local slot = second()
        if slot and SCSplitScreenProbe.isColdProbe(slot) ~= true then return false, "pickup_view_still_owned" end
        if slot and not ctx.uiDetached then
            local okay=type(destroyPlayerData)=="function" and pcall(destroyPlayerData,slot)
            if not okay then return false,"pickup_ui_release_pending" end
            ctx.uiDetached=true
        end
        local okay, released = native("cancelColdCompanionProbe")
        if not okay or released ~= true then return false, "pickup_loader_release_pending" end
        local cleared, reason = SC.ViewSession.released("pickup", ctx.slotSqlId)
        if not cleared then return false, reason end
    end
    local okay, reason = SC.ViewSession.unreserve("pickup", ctx.requestId)
    if okay and context == ctx then context = nil end
    return okay, reason
end

function J.restoreWatch(ctx, actor)
    local watch = SC.BaseWatch and SC.BaseWatch.current()
    if not watch or watch.pickupOwner ~= ctx.requestId then return true, "pickup_no_watch" end
    if SC.BaseLife.isInside(player()) then
        return SC.BaseWatch.finishPickupPause(ctx.requestId)
    end
    local record, reason = SC.BaseWatch.pickupResumeCandidate(ctx.requestId)
    if not record then
        local anchor=watch.pickupAnchor
        if watch.leaderId==ctx.driverId and anchor and SC.BaseLife.isOutdoorSquare(anchor)==false then
            local okay,why=SC.Navigation.request(actor,anchor,"walk",{
                action="pickup_watch_resume",desiredDistance=0,arrivalDistance=.3,continuousApproach=true})
            return false,okay and "pickup_watch_resume_approach" or why
        end
        ctx.watchWarning = reason or "base_watch_no_eligible_resident"
        SC.BaseWatch.finishPickupPause(ctx.requestId)
        return true, "pickup_no_watch"
    end
    ctx.watchResumeId = record.id
    if record.actor ~= actor then
        local arrived, why = walk(actor, record.actor)
        if not arrived then return false, why end
        U().stop(actor)
        local okay, result = native("handoffLiving", record.actor)
        if not okay or result ~= record.actor then return false, "pickup_watch_resume_pending" end
    end
    local resumed, why = SC.BaseWatch.resumeFromPickup(ctx.requestId, record.actor)
    if resumed then ctx.watchResumed = true end
    return resumed, why
end

function J.carSaved(ctx, car)
    local current=U().nowMs()
    if not ctx.carSaveTicket and (ctx.carSaveAttempts or 0)>=3 then return false,"pickup_car_save_failed" end
    if ctx.carSaveAt and current<ctx.carSaveAt then return false,"pickup_car_save_pending" end
    if not ctx.carSaveTicket then
        local okay, ticket = native("requestHomeVehicleSave", car)
        ctx.carSaveAttempts=(ctx.carSaveAttempts or 0)+1
        if not okay or type(ticket) ~= "number" or ticket <= 0 then
            ctx.carSaveAt=current+2000
            return false, "pickup_car_save_pending"
        end
        ctx.carSaveTicket = ticket
    end
    local okay, status = native("pollHomeVehicleSave", ctx.carSaveTicket)
    if not okay or status ~= "ready" then
        if status == "failed" then
            native("cancelHomeVehicleSave", ctx.carSaveTicket)
            ctx.carSaveTicket = nil
            ctx.carSaveAt=current+2000
        end
        return false, "pickup_car_save_pending"
    end
    local copied, receipt = native("homeVehicleSaveReceipt", ctx.carSaveTicket)
    if not copied then return false, "pickup_car_save_pending" end
    ctx.carSaveReceipt = receipt
    return true
end

function J.clearCarSave(ctx)
    if ctx.carSaveTicket then native("cancelHomeVehicleSave",ctx.carSaveTicket) end
    ctx.carSaveTicket=nil
end

function J.retryArrival(ctx)
    local release=ctx.release
    if not release or release.nativeReleased or SC.Persistence.remoteArrivalDurable(release.token) then return true end
    local aborted,reason=SC.Persistence.abortRemoteArrival(release.token)
    if not aborted then return false,reason end
    ctx.release=nil
    J.clearCarSave(ctx)
    ctx.carSaveReceipt,ctx.carSaveAttempts,ctx.carSaveAt=nil,nil,nil
    return true
end

function J.releaseLocal(ctx,actor)
    if SC.ViewSession.owner()~="pickup" then return second()==nil end
    local okay,ready=native("canReleaseJoinedLeader")
    if not okay or ready~=true then return false,"pickup_primary_view_pending" end
    local saved,slot=native("persistJoinedLeaderSlotForReuse")
    if not saved or type(slot)~="number" or slot<2 then return false,"pickup_slot_save_failed" end
    ctx.slotSqlId=slot
    if not ctx.uiDetached then
        local okay=type(destroyPlayerData)=="function" and pcall(destroyPlayerData,actor)
        if not okay then return false,"pickup_ui_release_pending" end
        ctx.uiDetached=true
    end
    local okay,released=native("releaseJoinedLeader")
    if not okay or released~=true then return false,"pickup_view_release_pending" end
    return SC.ViewSession.released("pickup",slot)
end

function J.finishDead(ctx,actor,finalized)
    if SC.ViewSession.owner()=="pickup" then
        if call(actor,"isCorpseReady")~=true then return false,"pickup_corpse_pending" end
        local staged,ready=native("stageDeadCorpseChunk",actor)
        if not staged or ready~=true then return false,"pickup_corpse_save_pending" end
        local saved,slot=native("persistDeadLeaderSlotForReuse")
        if not saved or type(slot)~="number" or slot<2 then return false,"pickup_slot_save_failed" end
        ctx.slotSqlId=slot
        if not ctx.uiDetached then
            local okay=type(destroyPlayerData)=="function" and pcall(destroyPlayerData,actor)
            if not okay then return false,"pickup_ui_release_pending" end
            ctx.uiDetached=true
        end
        local okay,released=native("releaseDeadLeader")
        if not okay or released~=true then return false,"pickup_corpse_save_pending" end
        SC.ViewSession.released("pickup",slot)
    end
    if ctx.release then
        local completed,reason=SC.Persistence.completeDeadRemoteArrival(ctx.release.token,{actor},finalized,"pickup")
        if not completed then return false,reason end
        ctx.release=nil
    end
    return true
end

function J.finishRemote(ctx, actor, car, integration)
    if not ctx.release then
        local saved, why = J.carSaved(ctx, car)
        if not saved then return false, why end
        local a = ctx.camp.arrival
        local okay, token = native("preparePickupArrival", ctx.requestId,
            { actor }, a.x1, a.y1, a.x2, a.y2, a.z)
        if not okay then return false, "pickup_arrival_not_ready" end
        ctx.release = { token = token, actor = actor }
        local remembered, slotId = native("remoteArrivalSlotSqlId", token)
        if remembered and type(slotId) == "number" and slotId >= 2 then
            ctx.slotSqlId = slotId
            SC.ViewSession.rememberSlotSqlId(slotId)
        end
        local attached, result = native("attachRemoteArrivalVehicleSave", token, ctx.carSaveTicket)
        if not attached or result ~= true then
            native("cancelRemoteArrival", token)
            ctx.release = nil
            return false, "pickup_car_save_pending"
        end
    end
    local transaction = ctx.release
    if not transaction.nativeReleased then
        local committed, reason = SC.Persistence.commitRemoteArrival(
            { transaction.actor }, ctx.camp, transaction.token, integration, "pickup")
        if not committed then return false, reason end
        if not ctx.uiDetached then
            local okay = type(destroyPlayerData) == "function" and pcall(destroyPlayerData, transaction.actor)
            if not okay then return false, "pickup_ui_release_pending" end
            ctx.uiDetached = true
        end
        local ready, can = native("canReleaseRemoteArrival", transaction.token)
        if not ready or can ~= true then return false, "pickup_arrival_cleanup_pending" end
        local released, result = native("releaseRemoteArrival", transaction.token)
        if not released or result ~= true then return false, "pickup_view_release_pending" end
        transaction.nativeReleased = true
        local okay, reason = SC.ViewSession.released("pickup", ctx.slotSqlId)
        if not okay then return false, reason end
    end
    if transaction.nativeReleased and SC.ViewSession.owner()=="pickup" then
        local okay,reason=SC.ViewSession.released("pickup",ctx.slotSqlId)
        if not okay then return false,reason end
    end
    local complete, reason = SC.Persistence.completeRemoteArrival(transaction.token)
    if not complete then return false, reason end
    native("cancelHomeVehicleSave", ctx.carSaveTicket)
    ctx.carSaveTicket, ctx.release = nil, nil
    return true
end

function J.releaseReservation(ctx)
    local okay, reason = SC.ViewSession.unreserve("pickup", ctx.requestId)
    if okay and context == ctx then context = nil end
    return okay, reason
end

function J.prepareReset()
    local ctx = context
    if not ctx then return true end
    local slot = second()
    local mode = SC.ViewSession.owner()
    local watch = SC.BaseWatch and SC.BaseWatch.current()
    if mode == "pickup" or mode == "base_watch" and watch and watch.pickupOwner == ctx.requestId then
        if not slot then return false, "pickup_view_join_pending" end
        if not ctx.uiDetached then
            if type(destroyPlayerData) ~= "function" then return false, "pickup_ui_release_pending" end
            local okay = pcall(destroyPlayerData, slot)
            if not okay then return false, "pickup_ui_release_pending" end
            ctx.uiDetached = true
        end
        local okay, result = native("releaseForWorldExit")
        if not okay or result ~= true then return false, "pickup_view_release_pending" end
        SC.ViewSession.released(mode, ctx.slotSqlId, true)
    end
    return J.releaseReservation(ctx)
end

function J.reset() context = nil return true end

return J
