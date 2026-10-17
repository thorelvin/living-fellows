-- SPDX-License-Identifier: MIT
-- Shared rules for camp chores that borrow one exact item: gasoline cans for
-- refueling, and the tire pump or water vessel for car upkeep.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BaseFuel = SC.BaseFuel or {}
local Fuel = SC.BaseFuel

Fuel.MARKER = "LF_RefuelJobId"
Fuel.UPKEEP_MARKER = "LF_UpkeepJobId"
Fuel.EPSILON = 0.02

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if object == nil then return nil end
    local value, okay = U().call(object, method, ...)
    if okay then return value end
    return nil
end

-- A marker reserves its item only while an open job still names that exact
-- item. A cancelled job, a worker who died carrying it or a can the player
-- took leaves the marker behind, and that must not hide the item from every
-- camp system for good.
function Fuel.liveMarker(item, key)
    local data = item and U().modData(item) or nil
    local jobId = type(data) == "table" and data[key or Fuel.MARKER] or nil
    local job = jobId ~= nil and SC.BaseLife and type(SC.BaseLife.job) == "function"
        and SC.BaseLife.job(jobId) or nil
    local target = type(job) == "table" and job.target or nil
    if type(target) ~= "table" or target.itemId == nil
        or job.state == "completed" or job.state == "cancelled"
        or tostring(target.itemId) ~= tostring(call(item, "getID")) then
        return nil
    end
    return jobId
end

function Fuel.reserved(item)
    return Fuel.liveMarker(item, Fuel.MARKER) ~= nil
        or Fuel.liveMarker(item, Fuel.UPKEEP_MARKER) ~= nil
end

-- A worker that died or was removed has left the registry, and anything it
-- carried went with it. A dormant (unloaded) worker keeps its record, and a
-- saved companion is unregistered only until the load restores its actor;
-- either can still bring a borrowed item back, so neither counts as gone.
function Fuel.workerIdGone(id)
    local registry = SC.Registry
    if type(id) ~= "string" or type(registry) ~= "table"
        or type(registry.byId) ~= "function" then return false end
    local okay, record = pcall(registry.byId, id)
    if not okay or record ~= nil then return false end
    local persistence = SC.Persistence
    if type(persistence) == "table" then
        if type(persistence.restoreStatus) == "function"
            and persistence.restoreStatus() ~= true then return false end
        if type(persistence.isPending) == "function"
            and persistence.isPending(id) == true then return false end
    end
    return true
end

function Fuel.workerGone(job)
    if type(job) ~= "table" or type(SC.Registry) ~= "table" then return false end
    for _, id in ipairs({ job.assignedId or false, job.reservedBy or false }) do
        if id and not Fuel.workerIdGone(id) then return false end
    end
    return true
end

-- Where the exact borrowed item belongs: "loaded" with its storage and
-- container, "unloaded" (it may still be there), "removed" (the player
-- unmarked that storage) or "none" (nothing borrowed yet).
function Fuel.sourceState(job)
    local id = type(job) == "table" and type(job.target) == "table"
        and job.target.sourceStorageId or nil
    if id == nil then return "none" end
    local storage = SC.BaseLife.storage(id)
    if not storage then return "removed" end
    local container = SC.BaseLife.resolveContainer(storage)
    if not container then return "unloaded" end
    return "loaded", storage, container
end

-- Clear a borrowed item's marker where it can still be reached: its loaded
-- source storage. A marker anywhere else goes stale with its job.
function Fuel.clearStoredMark(job, key)
    local state, _, container = Fuel.sourceState(job)
    if state ~= "loaded" then return false end
    for _, item in ipairs(U().inventoryItems(container, 4096)) do
        if Fuel.marker(item, key) == job.id then
            return Fuel.clearMark(item, job.id, key)
        end
    end
    return false
end

-- Stop this chore's own native action before its receipt is dropped.
function Fuel.stopNative(actor, kinds, reason)
    local native = SC.NativeActions
    local kind = native and type(native.workKind) == "function"
        and native.workKind(actor) or nil
    if kind == nil or not kinds[kind] then return true end
    if native.isWorkActive(actor) == true then
        return native.cancelWork(actor, reason)
    end
    return native.finishWork(actor)
end

function Fuel.marker(item, key)
    local data = item and U().modData(item) or nil
    return type(data) == "table" and data[key or Fuel.MARKER] or nil
end

function Fuel.mark(item, jobId, key)
    key = key or Fuel.MARKER
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" then return false end
    if data[key] ~= nil and data[key] ~= jobId
        and Fuel.liveMarker(item, key) ~= nil then return false end
    data[key] = jobId
    return data[key] == jobId
end

function Fuel.clearMark(item, jobId, key)
    key = key or Fuel.MARKER
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" or data[key] ~= jobId then return false end
    data[key] = nil
    return data[key] == nil
end

function Fuel.gasAmount(item)
    local fluid = call(item, "getFluidContainer")
    local gasOkay, gas = pcall(function() return Fluid.Petrol end)
    if not fluid or not gasOkay or not gas or call(fluid, "contains", gas) ~= true
        or call(fluid, "isMixture") ~= false then return 0 end
    local total = tonumber(call(fluid, "getAmount"))
    local pure = tonumber(call(fluid, "getSpecificFluidAmount", gas))
    if not total or not pure or total <= Fuel.EPSILON
        or math.abs(total - pure) > Fuel.EPSILON then return 0 end
    return total
end

function Fuel.sourceCan(actor)
    local rows = SC.BaseLife.storageRows(nil, true)
    if actor then
        table.sort(rows, function(a, b)
            local aObject = SC.BaseLife.resolveObject(a)
            local bObject = SC.BaseLife.resolveObject(b)
            local aDistance = U().distanceSq(actor, aObject)
            local bDistance = U().distanceSq(actor, bObject)
            if aDistance ~= bDistance then return aDistance < bDistance end
            return tostring(a.id) < tostring(b.id)
        end)
    end
    for _, storage in ipairs(rows) do
        local container = SC.BaseLife.resolveContainer(storage)
        if container then
            local items = U().inventoryItems(container, math.huge)
            local blocked, blockedByType, availableByType = {}, {}, {}
            for _, item in ipairs(items) do
                local kind = U().itemType(item)
                local protected = Fuel.reserved(item)
                    or (SC.WorkTransport and SC.WorkTransport.foreignProtected
                        and SC.WorkTransport.foreignProtected(item, actor) == true)
                blocked[item] = protected == true
                if kind ~= nil and protected then
                    blockedByType[kind] = (blockedByType[kind] or 0) + 1
                end
            end
            for _, item in ipairs(items) do
                local kind = U().itemType(item)
                if kind ~= nil and blocked[item] ~= true
                    and Fuel.gasAmount(item) > 0 then
                    if availableByType[kind] == nil then
                        availableByType[kind] = math.max(0,
                            SC.BaseLife.availableCountExact(storage, kind)
                                - (blockedByType[kind] or 0))
                    end
                    if availableByType[kind] > 0 then
                        return storage, container, item
                    end
                end
            end
        end
    end
    return nil
end

function Fuel.sourceFor(job)
    local storage = job.target.sourceStorageId
        and SC.BaseLife.storage(job.target.sourceStorageId) or nil
    return storage, storage and SC.BaseLife.resolveContainer(storage) or nil
end

function Fuel.itemFor(job, actor)
    local function matching(item)
        return item and Fuel.marker(item) == job.id
            and (job.target.itemId == nil
                or tostring(call(item, "getID")) == tostring(job.target.itemId))
    end
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 1024)) do
        if matching(item) then return item, true end
    end
    local _, container = Fuel.sourceFor(job)
    for _, item in ipairs(U().inventoryItems(container, 4096)) do
        if matching(item) then return item, false end
    end
    return nil
end

return Fuel
