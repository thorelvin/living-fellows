-- SPDX-License-Identifier: MIT
-- Refuel a loaded camp generator with the stock action and an exact stored can.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.GeneratorRefuel = SC.GeneratorRefuel or {}
local Refuel = SC.GeneratorRefuel
local Fuel = SC.BaseFuel
local EPSILON = Fuel.EPSILON
local NEAR_BASE = 6
local SCAN_BUDGET = 256
local states = setmetatable({}, { __mode = "k" })
local scan

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if not object then return nil end
    local result, okay = U().call(object, method, ...)
    if okay then return result end
    return nil
end
local function amount(object, method)
    return tonumber(call(object, method))
end
local function pointOf(object)
    local square = call(object, "getSquare")
    local x, y, z = U().position(square)
    if x == nil or y == nil or z == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
end

local function nearBase(point, base)
    if not point or not base then return false end
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and tonumber(zone.z) == point.z
            and point.x >= zone.x1 - NEAR_BASE
            and point.x <= zone.x2 + NEAR_BASE
            and point.y >= zone.y1 - NEAR_BASE
            and point.y <= zone.y2 + NEAR_BASE then return true end
    end
    return false
end

function Refuel.eligible(generator, manual, allowFull)
    local base = SC.BaseLife and SC.BaseLife.active()
    if not base then return false, "base_missing" end
    if not generator or not U().instanceOf(generator, "IsoGenerator") then
        return false, "generator_missing"
    end
    local point = pointOf(generator)
    if not nearBase(point, base) then return false, "generator_outside_base" end
    if amount(generator, "getObjectIndex") == nil
        or amount(generator, "getObjectIndex") < 0
        or call(U().gridSquare(point.x, point.y, point.z), "getGenerator")
            ~= generator then
        return false, "generator_identity_unavailable"
    end
    local current, capacity = amount(generator, "getFuel"),
        amount(generator, "getMaxFuel")
    if not current or not capacity or capacity <= 0 then
        return false, "generator_fuel_unavailable"
    end
    if allowFull ~= true and current >= capacity - EPSILON then
        return false, "generator_full"
    end
    if manual ~= true and call(generator, "isActivated") ~= true then
        return false, "generator_not_running"
    end
    return true, { x = point.x, y = point.y, z = point.z,
        current = current, capacity = capacity }
end

local function resolve(job)
    local generator, reason = SC.BaseLife.resolveObject(job.target)
    if not generator or not U().instanceOf(generator, "IsoGenerator") then
        return nil, reason or "generator_missing"
    end
    return generator
end

local function openJob(objectId)
    local base = SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "refuel_generator" and job.state ~= "completed"
            and job.state ~= "cancelled" and type(job.target) == "table"
            and job.target.objectId == objectId then return job end
    end
    return nil
end

function Refuel.queue(generator, manual)
    local okay, info = Refuel.eligible(generator, manual == true)
    if not okay then return false, info end
    if manual ~= true and info.current / info.capacity >= 0.5 then
        return false, "generator_above_auto_refuel_threshold"
    end
    local descriptor, reason = SC.BaseLife.describeObject(generator, true)
    if not descriptor then return false, reason or "generator_identity_unavailable" end
    local existing = openJob(descriptor.objectId)
    if existing then
        if manual == true then
            existing.priority = 5
            existing.target.manual = true
            if existing.state == "blocked" and existing.target.stage == nil then
                existing.retryAt = 0
            end
            return true, existing
        end
        return false, "generator_refuel_already_queued"
    end
    if not Fuel.sourceCan(nil) then return false, "base_gasoline_missing" end
    descriptor.manual = manual == true
    return SC.BaseLife.enqueueJob({ type = "refuel_generator",
        priority = manual == true and 5 or 2, target = descriptor })
end

local function scanZones(base)
    local result = {}
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" then
            result[#result + 1] = { id = zone.id, z = tonumber(zone.z),
                x1 = zone.x1 - NEAR_BASE, x2 = zone.x2 + NEAR_BASE,
                y1 = zone.y1 - NEAR_BASE, y2 = zone.y2 + NEAR_BASE }
        end
    end
    return result
end

function Refuel.audit()
    local base = SC.BaseLife and SC.BaseLife.active()
    if not base then return false, "base_missing" end
    local zones = scanZones(base)
    if #zones == 0 then return false, "base_area_missing" end
    if not Fuel.sourceCan(nil) then return false, "base_gasoline_missing" end
    local signature = {}
    for _, zone in ipairs(zones) do
        signature[#signature + 1] = table.concat({ zone.id, zone.x1,
            zone.y1, zone.x2, zone.y2, zone.z }, ":")
    end
    signature = table.concat(signature, "|")
    if not scan or scan.baseId ~= base.id or scan.signature ~= signature then
        scan = { baseId = base.id, signature = signature, index = 1,
            x = zones[1].x1, y = zones[1].y1 }
    end
    for _ = 1, SCAN_BUDGET do
        local zone = zones[scan.index]
        local square = U().gridSquare(scan.x, scan.y, zone.z)
        local generator = square and call(square, "getGenerator") or nil
        scan.x = scan.x + 1
        if scan.x > zone.x2 then scan.x, scan.y = zone.x1, scan.y + 1 end
        if scan.y > zone.y2 then
            scan.index = scan.index % #zones + 1
            zone = zones[scan.index]
            scan.x, scan.y = zone.x1, zone.y1
        end
        if generator then
            local okay, info = Refuel.eligible(generator, false)
            if okay and info.current / info.capacity < 0.5 then
                local descriptor = SC.BaseLife.describeObject(generator, true)
                if descriptor and not openJob(descriptor.objectId) then
                    local queued, result = Refuel.queue(generator, false)
                    if queued then return true, result end
                end
            end
        end
    end
    return false, "no_running_generator_needs_fuel"
end

local function atGenerator(actor, generator)
    if SC.BaseLife.withinWorkReach(actor) ~= true then
        return false, {}, "generator_outside_work_reach"
    end
    return U().directInteractionAccess(actor, generator)
end

function Refuel.canContinue(actor, generator, item, jobId)
    local job = SC.BaseLife and SC.BaseLife.job(jobId)
    if not job or job.type ~= "refuel_generator"
        or job.reservedBy ~= U().idOf(actor)
        or Fuel.marker(item) ~= jobId
        or U().inventoryContains(U().inventory(actor), item) ~= true
        or resolve(job) ~= generator then return false end
    local okay = Refuel.eligible(generator, true, true)
    return okay == true and select(1, atGenerator(actor, generator)) == true
end

-- Called synchronously around ISAddFuel.complete. The generator may burn fuel
-- during the timed animation, so only this atomic native transfer is conserved.
function Refuel.recordTransfer(jobId, generator, item, beforeFuel, beforeCan,
    afterFuel, afterCan)
    local job = SC.BaseLife and SC.BaseLife.job(jobId)
    if not job or job.type ~= "refuel_generator" or job.target.stage ~= "refueling"
        or Fuel.marker(item) ~= jobId or resolve(job) ~= generator then return false end
    local gain = tonumber(afterFuel) and tonumber(beforeFuel)
        and afterFuel - beforeFuel or nil
    local loss = tonumber(beforeCan) and tonumber(afterCan)
        and beforeCan - afterCan or nil
    if not gain or not loss or gain < -EPSILON or loss < -EPSILON
        or math.abs(gain - loss) > 0.11 then return false end
    job.target.receipt = { gain = gain, loss = loss,
        fuelAfter = afterFuel, maxFuel = amount(generator, "getMaxFuel"),
        itemId = call(item, "getID") }
    return true
end

local function settleFuel(job, item)
    local target = job.target
    local receipt = target.receipt
    if receipt then
        if tostring(receipt.itemId) ~= tostring(target.itemId)
            or not tonumber(receipt.gain) or not tonumber(receipt.loss)
            or math.abs(receipt.gain - receipt.loss) > 0.11 then
            return false, "generator_refuel_receipt_uncertain"
        end
        if receipt.gain > EPSILON then
            target.filled = receipt.maxFuel ~= nil
                and receipt.fuelAfter >= receipt.maxFuel - EPSILON
            target.stage = "returning"
            target.stageStartedAt = U().nowMs()
            target.canBefore, target.receipt = nil, nil
            return true, "generator_refuel_verified"
        end
    else
        local currentCan = amount(call(item, "getFluidContainer"), "getAmount")
        if not currentCan or not tonumber(target.canBefore) then
            return false, "generator_refuel_receipt_unreadable"
        end
        if target.canBefore - currentCan > EPSILON then
            return false, "generator_refuel_receipt_uncertain"
        end
    end
    target.refuelAttempts = (tonumber(target.refuelAttempts) or 0) + 1
    if target.refuelAttempts >= 3 then return false, "generator_refuel_no_effect" end
    target.stage, target.receipt, target.canBefore = "carrying", nil, nil
    target.stageStartedAt = U().nowMs()
    return true, "generator_refuel_retry"
end

local function clearCargo(target)
    target.stage, target.sourceStorageId, target.itemId = nil, nil, nil
    target.canBefore, target.receipt, target.refuelAttempts = nil, nil, nil
    target.actionStartedAt, target.stageStartedAt = nil, nil
end
local NATIVE_KINDS = { generator_refuel = true }
-- Drop a receipt that has nothing left to protect.
local function dropReceipt(target)
    clearCargo(target)
    target.finishReason, target.filled = nil, nil
end

function Refuel.update(actor, baseState, job)
    local target = job.target
    job.assignedId = job.assignedId or U().idOf(actor)
    local state = states[actor]
    if not state or state.jobId ~= job.id then
        state = { jobId = job.id }
        states[actor] = state
    end
    local item, carried = Fuel.itemFor(job, actor)
    local stage = target.stage or "selecting"
    target.stageStartedAt = tonumber(target.stageStartedAt) or U().nowMs()
    if stage ~= "refueling" and U().nowMs() - target.stageStartedAt > 90000 then
        target.stageStartedAt = nil
        return false, "generator_refuel_" .. stage .. "_timeout", true
    end
    if stage == "selecting" then
        local storage, container
        if target.sourceStorageId then
            storage, container = Fuel.sourceFor(job)
            if not item then
                -- The reserved can is gone: the player took it, or it moved.
                -- Choose another rather than retrying for this one forever.
                if Fuel.sourceState(job) == "unloaded" then
                    return false, "base_storage_unloaded", true
                end
                target.sourceStorageId, target.itemId = nil, nil
                return true, "generator_refuel_can_reselecting"
            end
        else
            local sourceReason
            storage, container, item, sourceReason = Fuel.sourceCan(actor, baseState, job.id)
            if not item then
                if sourceReason == "fuel_route_pending"
                    or sourceReason == "fuel_route_unknown" then
                    return true, sourceReason
                end
                return true, sourceReason or "generator_refuel_fuel_exhausted", false, true
            end
            if not Fuel.mark(item, job.id) then
                return false, "generator_refuel_can_reserved", true
            end
            target.sourceStorageId = storage.id
            target.itemId = call(item, "getID")
        end
        if carried then
            target.stage, target.stageStartedAt = "carrying", U().nowMs()
            return true, "generator_refuel_can_carried"
        end
        if not storage or not container then return false, "base_storage_unloaded", true end
        local taken, reason = SC.BaseWork.withdrawFromStorage(actor, baseState,
            storage, container, item)
        if U().inventoryContains(U().inventory(actor), item) == true then
            target.stage, target.stageStartedAt = "carrying", U().nowMs()
            return true, "generator_refuel_can_carried"
        end
        return taken == true, reason or "generator_refuel_can_pending",
            taken ~= true and reason ~= "approaching_base_storage"
    end
    if not item then
        if Fuel.sourceState(job) == "unloaded" then
            return false, "base_storage_unloaded", true
        end
        -- Neither the worker nor the loaded storage holds the can any more
        -- (the player took it from the worker). Start over with another.
        local stopped, why = Fuel.stopNative(actor, NATIVE_KINDS,
            "generator_refuel_can_lost")
        if stopped ~= true then return false, why, true end
        dropReceipt(target)
        return true, "generator_refuel_can_lost"
    end
    if stage == "refueling" then
        local native = SC.NativeActions
        if native and native.workKind(actor) == "generator_refuel" then
            if native.isWorkActive(actor) == true then
                local generator = resolve(job)
                if generator and Refuel.canContinue(actor, generator, item, job.id)
                    and U().nowMs() - (tonumber(target.actionStartedAt) or 0) < 120000 then
                    return true, "generator_refuel_action_active"
                end
                local stopped, reason = native.cancelWork(actor,
                    "generator_refuel_interrupted")
                if stopped ~= true then return false, reason, true end
            else
                local finished, reason = native.finishWork(actor)
                if finished ~= true then return false, reason, true end
            end
        end
        local settled, reason = settleFuel(job, item)
        if settled ~= true then
            -- A receipt that does not add up never clears by waiting, and a
            -- guess must not pour again. Take the can home and end the job.
            target.stage, target.finishReason = "returning", reason
            target.canBefore, target.receipt = nil, nil
            target.stageStartedAt = U().nowMs()
            return true, "generator_refuel_returning_can"
        end
        return true, reason
    end
    if stage == "carrying" then
        if not carried then return false, "generator_refuel_can_not_carried", true end
        local generator, resolveReason = resolve(job)
        local okay, info = Refuel.eligible(generator, true)
        if not okay then
            target.stage, target.stageStartedAt = "returning", U().nowMs()
            target.finishReason = info or resolveReason
            return true, "generator_refuel_returning_can"
        end
        if Fuel.gasAmount(item) <= EPSILON then
            target.stage, target.stageStartedAt = "returning", U().nowMs()
            return true, "generator_refuel_empty_can"
        end
        local at, squares, accessReason = atGenerator(actor, generator)
        if not at then
            if #squares == 0 then
                return false, accessReason or "generator_access_unavailable", true
            end
            local moving, reason = SC.Navigation.requestAny(actor, squares,
                "walk", { action = "move_to_generator_fuel",
                    targetSquare = squares[1], arrivalDistance = 0.15,
                    workCampOnly = true, workReach = true })
            return moving == true, reason or "approaching_generator_fuel",
                moving ~= true and reason == "no_route"
        end
        target.canBefore = Fuel.gasAmount(item)
        target.actionStartedAt, target.stage = U().nowMs(), "refueling"
        target.stageStartedAt = U().nowMs()
        local started, reason = SC.NativeActions.startGeneratorRefuel(actor,
            generator, item, job.id)
        if started ~= true then
            target.stage, target.canBefore = "carrying", nil
            target.stageStartedAt = U().nowMs()
            return false, reason, true
        end
        return true, "generator_refuel_action_started"
    end
    if stage ~= "returning" then
        return false, "generator_refuel_stage_invalid", true
    end
    local home, storage, container = Fuel.sourceState(job)
    if home == "removed" then
        -- The player unmarked the can's storage. The worker keeps the can,
        -- unreserved, and ordinary camp hauling decides where it goes.
        if not Fuel.clearMark(item, job.id) then
            return false, "generator_refuel_marker_uncertain", true
        end
        dropReceipt(target)
        return true, "generator_refuel_source_removed", false, true
    end
    if home ~= "loaded" then return false, "base_storage_unloaded", true end
    if carried then
        local returned, reason = SC.BaseWork.returnToStorage(actor, baseState,
            storage, container, item)
        if returned ~= true and reason == "base_storage_action_rejected"
            and type(U().directInteractionAccess) == "function" then
            local object = SC.BaseLife.resolveObject(storage)
            if object and U().directInteractionAccess(actor, object) == true then
                returned, reason = SC.BaseWork.restoreToStorage(actor,
                    storage, container, item)
            end
        end
        if returned ~= true or U().inventoryContains(container, item) ~= true then
            return returned == true, reason or "generator_refuel_return_pending",
                returned ~= true and reason ~= "approaching_base_storage"
        end
    elseif U().inventoryContains(container, item) ~= true then
        return false, "generator_refuel_can_owner_uncertain", true
    end
    if not Fuel.clearMark(item, job.id) then
        return false, "generator_refuel_marker_uncertain", true
    end
    clearCargo(target)
    local finishReason = target.finishReason
    target.finishReason = nil
    if finishReason then return true, finishReason, false, true end
    local generator = resolve(job)
    local okay, info = Refuel.eligible(generator, true)
    if target.filled or not okay then
        target.filled = nil
        return true, okay and "generator_full" or info, false, true
    end
    if not Fuel.sourceCan(actor) then
        return true, "generator_refuel_fuel_exhausted", false, true
    end
    return true, "generator_refuel_next_can"
end

function Refuel.releaseAffinity(actor, job)
    if not job or not job.assignedId then return true end
    if not actor then
        -- A worker who died or was removed can never finish this receipt.
        return Fuel.workerGone(job) and Refuel.cancel(nil, job) == true or false
    end
    local item, carried = Fuel.itemFor(job, actor)
    if carried or job.target.stage == "refueling" or (SC.NativeActions
        and SC.NativeActions.workKind(actor) == "generator_refuel") then return false end
    if item and Fuel.marker(item) ~= job.id then return false end
    job.assignedId = nil
    states[actor] = nil
    return true
end

-- Cancelling refuses only while the can may still come back: a dormant
-- worker, an unloaded storage or a native action that will not stop. It never
-- waits on fuel readings; nothing more is poured and the can goes home.
function Refuel.cancel(actor, job)
    if not job then return true end
    local target = job.target
    if not actor then
        if target.stage ~= nil and not Fuel.workerGone(job) then
            return false, "generator_refuel_worker_unavailable"
        end
        Fuel.clearStoredMark(job)
        dropReceipt(target)
        job.assignedId = nil
        return true, "generator_refuel_receipt_released"
    end
    local item, carried = Fuel.itemFor(job, actor)
    -- Stop only this job's own pour; the worker may be on a newer chore.
    local owned = states[actor] and states[actor].jobId == job.id
    if owned and SC.NativeActions.workKind(actor) == "generator_refuel" then
        local stopped, reason = SC.NativeActions.cancelWork(actor,
            "generator_refuel_cancelled")
        if stopped ~= true then return false, reason end
    end
    if U().isDead(actor) then
        Fuel.prepareActorRetirement(actor)
        Fuel.clearStoredMark(job)
        dropReceipt(target)
        job.assignedId, states[actor] = nil, nil
        return true, "generator_refuel_worker_retired"
    end
    local home, storage, container = Fuel.sourceState(job)
    if home == "unloaded" then return false, "base_storage_unloaded" end
    if item then
        if home == "loaded" and carried then
            local returned, reason = SC.BaseWork.restoreToStorage(actor,
                storage, container, item)
            if returned ~= true then return false, reason end
        elseif home == "loaded" and U().inventoryContains(container, item) ~= true then
            return false, "generator_refuel_can_owner_uncertain"
        end
        if not Fuel.clearMark(item, job.id) then
            return false, "generator_refuel_marker_uncertain"
        end
    end
    dropReceipt(target)
    job.assignedId = nil
    states[actor] = nil
    return true
end

function Refuel.reset()
    scan = nil
    states = setmetatable({}, { __mode = "k" })
end

return Refuel
