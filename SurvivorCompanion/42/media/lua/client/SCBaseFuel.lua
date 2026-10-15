-- SPDX-License-Identifier: MIT
-- Shared, exact-can gasoline selection for camp refueling chores.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BaseFuel = SC.BaseFuel or {}
local Fuel = SC.BaseFuel

Fuel.MARKER = "LF_RefuelJobId"
Fuel.EPSILON = 0.02

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if object == nil then return nil end
    local value, okay = U().call(object, method, ...)
    if okay then return value end
    return nil
end

function Fuel.marker(item)
    local data = item and U().modData(item) or nil
    return type(data) == "table" and data[Fuel.MARKER] or nil
end

function Fuel.mark(item, jobId)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" or (data[Fuel.MARKER] ~= nil
        and data[Fuel.MARKER] ~= jobId) then return false end
    data[Fuel.MARKER] = jobId
    return data[Fuel.MARKER] == jobId
end

function Fuel.clearMark(item, jobId)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" or data[Fuel.MARKER] ~= jobId then return false end
    data[Fuel.MARKER] = nil
    return data[Fuel.MARKER] == nil
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
                local protected = Fuel.marker(item) ~= nil
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
