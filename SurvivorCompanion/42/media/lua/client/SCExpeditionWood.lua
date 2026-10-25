-- SPDX-License-Identifier: MIT
-- Mission-scoped wood collection. Travel and home delivery belong to the
-- expedition controller; this worker never creates logs or a temporary base.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionWood = SC.ExpeditionWood or {}
local Wood = SC.ExpeditionWood
local runtime = setmetatable({}, { __mode = "k" })
local CARGO, TOOL = "LF_ExpeditionWood", "LF_ExpeditionWoodTool"
local MAX_LOGS, LOG_WEIGHT, RADIUS = 256, 9, 8
local function U() return SC.GameplayUtil end
local function L() return SC.LoggingWork end
local function call(object, method, ...)
    local value, okay = U().call(object, method, ...)
    if okay then return value end
end
local function now() return U().nowMs() end
local function actorId(actor) return tostring(U().idOf(actor) or "") end
local function data(item) return item and U().modData(item) end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function point(value)
    return type(value) == "table" and finite(value.x) and finite(value.y) and finite(value.z)
        and value.x == math.floor(value.x) and value.y == math.floor(value.y)
        and value.z == math.floor(value.z) and value.z >= -32 and value.z <= 31
end
local function id(value) return type(value) == "string" and #value > 0 and #value <= 160 end
local function array(value, maximum)
    if type(value) ~= "table" or #value > maximum then return false end
    local entries = 0
    for index in pairs(value) do
        if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > #value then return false end
        entries = entries + 1
    end
    return entries == #value
end
local function rt(wood)
    runtime[wood] = runtime[wood] or { workers = {} }
    return runtime[wood]
end
local function resolve(memberId)
    local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(memberId)
    return record and record.actor or U().resolveActor and U().resolveActor(memberId)
end
function Wood.normalizeRequest(request)
    if type(request) ~= "table" then return nil, "invalid_wood_request" end
    if request.mode == "full" then return { mode = "full" } end
    local quantity = request.quantity == nil and 12 or request.quantity
    if request.mode ~= "count" or not finite(quantity) or quantity ~= math.floor(quantity)
        or quantity < 1 or quantity > MAX_LOGS then return nil, "invalid_wood_request" end
    return { mode = "count", quantity = quantity }
end
function Wood.createState(request)
    local normalized, reason = Wood.normalizeRequest(request)
    if not normalized then return nil, reason end
    return { version = 1, request = normalized, acquisitions = {}, workers = {}, loans = {} }
end
local function copyPlain(value, budget, depth)
    if type(value) == "nil" or type(value) == "boolean" then return value end
    if type(value) == "string" then if #value > 2048 then error("wood string limit") end return value end
    if type(value) == "number" then if not finite(value) then error("wood number") end return value end
    if type(value) ~= "table" or depth > 12 then error("wood nonplain state") end
    budget.count = budget.count + 1
    if budget.count > 8192 then error("wood state limit") end
    local out = {}
    for key, entry in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then error("wood key") end
        out[key] = copyPlain(entry, budget, depth + 1)
    end
    return out
end
function Wood.valid(wood)
    if type(wood) ~= "table" or not Wood.normalizeRequest(wood.request) then return false end
    for _, name in ipairs({ "workers", "loans", "pendingLogs" }) do
        if wood[name] ~= nil and type(wood[name]) ~= "table" then return false end
    end
    if not array(wood.acquisitions, MAX_LOGS)
        or wood.pendingLogs ~= nil and not array(wood.pendingLogs, MAX_LOGS) then return false end
    if wood.cutterId ~= nil and not id(wood.cutterId) then return false end
    local seen = {}
    for _, row in ipairs(wood.acquisitions) do
        if type(row) ~= "table" or not id(row.id) or seen[row.id]
            or row.itemType ~= "Base.Log" or not id(row.memberId) or not point(row.source) then return false end
        seen[row.id] = true
    end
    local count = 0
    local phases = { seek = true, approach = true, chopping = true, loading = true, done = true }
    for memberId, worker in pairs(wood.workers or {}) do
        count = count + 1
        if count > 4 or not id(memberId) or type(worker) ~= "table"
            or not phases[worker.phase] or not finite(worker.scan) or worker.scan < 0
            or worker.scan > (RADIUS * 2 + 1) ^ 2 or worker.scan ~= math.floor(worker.scan)
            or worker.failures ~= nil and (not finite(worker.failures) or worker.failures < 0)
            or worker.work ~= nil and type(worker.work) ~= "table"
            or worker.before ~= nil and type(worker.before) ~= "table"
            or worker.restAt ~= nil and not finite(worker.restAt)
            or worker.point ~= nil and not point(worker.point) then return false end
        if worker.phase == "chopping" and (not point(worker.point) or type(worker.work) ~= "table"
            or not point(worker.work.point) or not finite(worker.work.startedAt)
            or type(worker.before) ~= "table") then return false end
        if worker.work then
            for _, name in ipairs({ "lastHealth", "progressAt", "emulatedAt" }) do
                if worker.work[name] ~= nil and not finite(worker.work[name]) then return false end
            end
        end
        if worker.before then
            local beforeCount = 0
            for nativeId, present in pairs(worker.before) do
                beforeCount = beforeCount + 1
                if beforeCount > 864 or not id(nativeId) or present ~= true then return false end
            end
        end
    end
    count = 0
    for _, pending in pairs(wood.pendingLogs or {}) do
        count = count + 1
        if count > MAX_LOGS or type(pending) ~= "table" or not id(pending.id)
            or not point(pending.source) or pending.workerId ~= nil and not id(pending.workerId)
            or pending.failures ~= nil and type(pending.failures) ~= "table"
            or pending.blocked ~= nil and type(pending.blocked) ~= "table" then return false end
    end
    count = 0
    for memberId, loan in pairs(wood.loans or {}) do
        count = count + 1
        if count > 4 or not id(memberId) or type(loan) ~= "table"
            or not id(loan.itemId) or not id(loan.storageId) then return false end
    end
    local okay = pcall(copyPlain, wood, { count = 0 }, 0)
    return okay
end
function Wood.copy(wood)
    if not Wood.valid(wood) then return nil end
    local okay, copied = pcall(copyPlain, wood, { count = 0 }, 0)
    return okay and copied or nil
end
local function initialize(wood)
    wood.workers, wood.loans, wood.acquisitions, wood.pendingLogs =
        wood.workers or {}, wood.loans or {}, wood.acquisitions or {}, wood.pendingLogs or {}
    return wood
end
-- A marker is only as live as the trip behind it. Once the mission and its
-- delivery record have settled, a log the player took or an axe left on a
-- corpse is ordinary property again.
function Wood.reserved(item)
    local value = data(item)
    if type(value) ~= "table" then return false end
    local cargo = type(value[CARGO]) == "table" and value[CARGO] or nil
    local tool = type(value[TOOL]) == "table" and value[TOOL] or nil
    if not cargo and not tool then return false end
    local expedition = SC.ExpeditionPrototype
    if not expedition or type(expedition.woodMarkerLive) ~= "function" then return true end
    return expedition.woodMarkerLive(cargo, tool) ~= false
end
local function toolAllowed(item, memberId, wood)
    local value = data(item) or {}
    local loan = value[TOOL]
    if type(loan) == "table" then
        if loan.memberId == memberId and wood.loans[memberId]
            and wood.loans[memberId].itemId == U().itemStableId(item, true) then return true end
        if Wood.reserved(item) then return false end
    end
    if value.LF_FieldBorrowedAxe or value.LF_ProductionToolLoan
        or value.LF_WorkTransport or value.SC_ChefSupplyReceipt then return false end
    return true
end
local function axe(actor, wood)
    return L().axe(actor, function(item) return toolAllowed(item, actorId(actor), wood) end)
end
local function electCutter(wood, roster)
    for _, member in ipairs(roster or {}) do
        if member.id == wood.cutterId and member.actor and call(member.actor, "isDead") ~= true
            and axe(member.actor, wood) then return wood.cutterId end
    end
    wood.cutterId = nil
    for _, member in ipairs(roster or {}) do
        if member.actor and call(member.actor, "isDead") ~= true and axe(member.actor, wood) then
            wood.cutterId = member.id
            break
        end
    end
    return wood.cutterId
end
local function freeCapacity(container, actor)
    local free = tonumber(call(container, "getFreeCapacity", actor))
    if free then return math.max(0, free) end
    local capacity = tonumber(call(container, "getEffectiveCapacity", actor))
        or tonumber(call(container, "getCapacity"))
    local weight = tonumber(call(container, "getCapacityWeight"))
    return capacity and weight and math.max(0, capacity - weight) or nil
end
local function destinations(actor)
    local entries = L().inventoryEntries(actor)
    if not entries then return {} end
    local result, root = {}, U().inventory(actor)
    result[1] = { container = root, factor = 1 }
    for _, entry in ipairs(entries) do
        local bag = call(entry.item, "getInventory")
        if bag and entry.source == root and call(actor, "isEquippedClothing", entry.item) == true then
            local reduction = tonumber(call(entry.item, "getWeightReduction")) or 0
            result[#result + 1] = { container = bag, factor = 1 - math.max(0, math.min(100, reduction)) / 100 }
        end
    end
    table.sort(result, function(a, b) return a.factor < b.factor end)
    return result
end
local function carryDestination(actor, log, car)
    local weight, maximum = U().carryLoad(actor)
    if not finite(weight) or not finite(maximum) or maximum <= 0 then return nil, "wood_capacity_unavailable" end
    for _, choice in ipairs(destinations(actor)) do
        local free = freeCapacity(choice.container, actor)
        local itemWeight = log and U().itemWeight(log) or LOG_WEIGHT
        -- A short car shuttle may use the physical inventory limit, as field
        -- logging already does. A walking return must remain under Heavy Load.
        local safe = car or weight + itemWeight * choice.factor <= maximum + 0.000001
        local admitted = not log or SC.WorkTransport.hasRoom(choice.container, actor, log) == true
        if free and free + 0.000001 >= itemWeight and safe and admitted then return choice.container end
    end
    return nil, "wood_carry_capacity"
end
local function shortShuttle(actor, carId, target)
    local vehicle = carId and SC.Vehicle and SC.Vehicle.loadedBySqlId(carId)
    local carPoint = vehicle and L().point(vehicle)
    local from = L().point(actor)
    if not carPoint or not from or from.z ~= carPoint.z then return false end
    local dx, dy = from.x - carPoint.x, from.y - carPoint.y
    if dx * dx + dy * dy > 400 or SC.Vehicle.isStationary(vehicle) ~= true then return false end
    if target then
        if not finite(target.x) or not finite(target.y) or target.z ~= carPoint.z then return false end
        dx, dy = target.x - carPoint.x, target.y - carPoint.y
        if dx * dx + dy * dy > 400 then return false end
    end
    return true
end
function Wood.carryDestination(actor, log, shuttle)
    local short = type(shuttle) == "table" and shuttle.target ~= nil
        and shortShuttle(actor, shuttle.carId, shuttle.target)
    return carryDestination(actor, log, short == true)
end
local function eligible(member)
    return type(member) == "table" and member.actor ~= nil
        and call(member.actor, "isDead") == false and resolve(member.id) == member.actor
end
local function rosterCanCarry(roster, carId, target)
    for _, member in ipairs(roster or {}) do
        if eligible(member)
            and carryDestination(member.actor, nil, shortShuttle(member.actor, carId, target)) then return true end
    end
    return false
end
local function storageRows()
    local result = {}
    for _, category in ipairs({ "tools", "weapons", "construction", "crafting", "farming", "general" }) do
        for _, row in ipairs(SC.BaseLife.storageRows(category, true)) do result[#result + 1] = row end
    end
    return result
end
local function sourceAllowed(actor, storage, container, item)
    return SC.BaseLife.storage(storage.id) == storage and SC.BaseLife.withdrawable(storage)
        and SC.BaseLife.resolveContainer(storage) == container and U().inventoryContains(container, item)
        and U().itemHasTag(item, "CHOP_TREE") and call(item, "isBroken") == false
        and not Wood.reserved(item)
        and (not SC.WorkTransport.foreignProtected or not SC.WorkTransport.foreignProtected(item, actor))
        and (not SC.PersonalItems or not SC.PersonalItems.isProtected
            or not SC.PersonalItems.isProtected(item, actor, "camp_supply"))
        and SC.BaseLife.availableCountExact(storage, U().itemType(item)) > 0
end
local function recordGearLoan(wood, pending)
    if not pending or not pending.actor or not pending.nativeId or not pending.marker then return false end
    local root = U().inventory(pending.actor)
    if U().inventoryContains(root, pending.item) ~= true or call(pending.item, "getContainer") ~= root
        or U().inventoryContains(pending.container, pending.item) ~= false then return false end
    wood.loans[pending.memberId] = { itemId = pending.nativeId, storageId = pending.storage.id,
        itemType = U().itemType(pending.item), memberId = pending.memberId }
    pending.marker[TOOL] = { id = pending.nativeId, memberId = pending.memberId }
    return true
end
function Wood.prepare(roster, wood, carDescriptor, leaderId)
    if type(wood) ~= "table" or not Wood.normalizeRequest(wood.request) or not L() then
        return false, "invalid_wood_request", false
    end
    initialize(wood)
    local carId = carDescriptor and carDescriptor.sqlId
    local members = {}
    for _, member in ipairs(roster or {}) do
        if eligible(member) and member.id == leaderId then members[#members + 1] = member end
    end
    for _, member in ipairs(roster or {}) do
        if eligible(member) and member.id ~= leaderId then members[#members + 1] = member end
    end
    if #members == 0 then return false, "wood_worker_unavailable", false end
    local state = rt(wood)
    local pending = state.gear
    if pending and pending.actor then
        -- Retain a commit even when the invocation receipt was lost just
        -- before death/handoff. Never reassign a native transaction's owner.
        if recordGearLoan(wood, pending) then
            state.gear, pending = nil, nil
        elseif not eligible({ id = pending.memberId, actor = pending.actor })
            or pending.actor ~= members[1].actor then
            U().stop(pending.actor)
            if SC.NativeActions.clearVisual then SC.NativeActions.clearVisual(pending.actor) end
            state.gear, state.scan, pending = nil, nil, nil
        end
    end
    local cutter
    for _, member in ipairs(members) do if axe(member.actor, wood) then cutter = member break end end
    if cutter then
        wood.cutterId = actorId(cutter.actor)
        if not rosterCanCarry(roster, carId) then return false, "wood_carry_capacity", false end
        if carId and not rosterCanCarry(roster, nil)
            and (not SC.ExpeditionIntegration or not SC.ExpeditionIntegration.woodReturnShuttleAvailable
                or SC.ExpeditionIntegration.woodReturnShuttleAvailable(cutter.actor, carId) ~= true) then
            return false, "wood_return_carry_capacity", false
        end
        if carId then
            local vehicle = SC.Vehicle.loadedBySqlId(carId)
            local container
            if vehicle then
                local part
                part, container = SC.Vehicle.cargoPart(vehicle)
            end
            local free = container and freeCapacity(container, cutter.actor)
            if not free or free < LOG_WEIGHT then return false, "wood_trunk_capacity", false end
        end
        wood.prepared, wood.blocker = true, nil
        return true, "wood_ready", true
    end
    local member = members[1]
    local actor = member and member.actor
    if not actor or not SC.BaseLife or not SC.BaseWork then return false, "wood_axe_missing", false end
    if pending and not sourceAllowed(actor, pending.storage, pending.container, pending.item) then state.gear, pending = nil, nil end
    if not pending then
        state.scan = state.scan or { rows = storageRows(), row = 1, index = 0 }
        local scan, inspected = state.scan, 0
        while scan.row <= #scan.rows and inspected < 80 do
            local storage = scan.rows[scan.row]
            local container = SC.BaseLife.resolveContainer(storage)
            local items = container and call(container, "getItems")
            local size = items and U().listSize(items) or 0
            if scan.index >= size then scan.row, scan.index = scan.row + 1, 0
            else
                local item = U().listGet(items, scan.index)
                scan.index, inspected = scan.index + 1, inspected + 1
                if item and sourceAllowed(actor, storage, container, item) then
                    local damage = tonumber(call(item, "getTreeDamage")) or 0
                    if not scan.best or damage > scan.damage then
                        scan.best = { storage = storage, container = container, item = item }
                        scan.damage = damage
                    end
                end
            end
        end
        if scan.row <= #scan.rows then return true, "wood_preparing_axe", false end
        state.scan = nil
        if not scan.best then wood.blocker = "wood_axe_missing" return false, wood.blocker, false end
        state.gear, pending = scan.best, scan.best
        pending.transaction = {}
    end
    pending.actor, pending.memberId = actor, actorId(actor)
    pending.nativeId = U().itemStableId(pending.item, true)
    pending.marker = data(pending.item)
    if not pending.nativeId or not pending.marker then
        state.gear = nil
        return false, "wood_axe_identity_unavailable", false
    end
    local taken, reason = SC.BaseWork.withdrawFromStorage(actor, pending.transaction,
        pending.storage, pending.container, pending.item)
    if recordGearLoan(wood, pending) then
        state.gear = nil
        return true, "wood_preparing_axe", false
    end
    if taken == true and reason == "base_supply_taken" then return false, "wood_axe_transfer_unverified", false end
    if not taken then state.gear = nil wood.blocker = reason return false, reason or "wood_axe_unreachable", false end
    return true, reason or "wood_preparing_axe", false
end

local function worker(wood, actor)
    local memberId = actorId(actor)
    wood.workers[memberId] = wood.workers[memberId] or { phase = "seek", scan = 0, failures = 0 }
    rt(wood).workers[memberId] = rt(wood).workers[memberId] or { actor = actor }
    return wood.workers[memberId], rt(wood).workers[memberId], memberId
end
local function quota(wood)
    return #wood.acquisitions >= (wood.request.mode == "count" and wood.request.quantity or MAX_LOGS)
end
local function finish(wood, reason)
    wood.complete, wood.doneReason = true, reason
    -- Each worker must settle its own action and cargo before status is done.
    return true, reason, false
end
local function receipt(wood, itemId)
    for _, row in ipairs(wood.acquisitions) do if row.id == itemId then return row end end
end
local function carriedCargo(actor, wood)
    local result = {}
    local entries, reason = L().inventoryEntries(actor)
    if not entries then return nil, reason end
    for _, entry in ipairs(entries) do
        local marker = data(entry.item)
        marker = marker and marker[CARGO]
        if marker and marker.tripId == wood.tripId and receipt(wood, marker.id) then result[#result + 1] = entry end
    end
    return result
end
function Wood.cargoCounts(wood, roster, visibleMemberIds, carId)
    local result, visible, seen = { carried = 0, loaded = 0, complete = true }, {}, {}
    if type(wood) ~= "table" then result.complete = false return result end
    if visibleMemberIds then
        for key, value in pairs(visibleMemberIds) do
            if type(value) == "string" then visible[value] = true
            elseif value == true then visible[tostring(key)] = true end
        end
    end
    for _, member in ipairs(roster or {}) do
        if visibleMemberIds and not visible[member.id] or not member.actor then result.complete = false
        else
            local entries = carriedCargo(member.actor, wood)
            if not entries then result.complete = false
            else
                for _, entry in ipairs(entries) do
                    local nativeId = U().itemStableId(entry.item, true)
                    if call(entry.item, "getContainer") == entry.source and not seen[nativeId] then
                        seen[nativeId], result.carried = true, result.carried + 1
                    else result.complete = false end
                end
            end
        end
    end
    if carId then
        local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(carId)
        local container
        if vehicle then local part
            part, container = SC.Vehicle.cargoPart(vehicle)
        end
        local list = container and call(container, "getItems")
        if not list then result.complete = false
        else
            for index = 0, math.min(U().listSize(list), 4096) - 1 do
                local item = U().listGet(list, index)
                local marker = data(item)
                marker = marker and marker[CARGO]
                if marker and marker.tripId == wood.tripId and receipt(wood, marker.id)
                    and call(item, "getContainer") == container then
                    if not seen[marker.id] then seen[marker.id], result.loaded = true, result.loaded + 1
                    else result.complete = false end
                end
            end
        end
    end
    return result
end
local function flushCargo(actor, ctx, state)
    if not ctx.carId then return false, "wood_no_car" end
    local cargo, why = carriedCargo(actor, ctx.wood)
    if not cargo then return false, why end
    if #cargo == 0 then return true, "wood_cargo_empty", true end
    local _, container, reason = L().cargo(actor, ctx.carId, state, ctx.snapshot)
    if not container then return true, reason or "wood_trunk_approaching", false end
    for index = 1, math.min(8, #cargo) do
        local entry = cargo[index]
        local moved, failure = L().transfer(entry.source, container, actor, entry.item)
        if not moved then
            if failure == "destination_full" then ctx.wood.capacityFull = true return false, "wood_trunk_full", true end
            return false, failure, false
        end
        local row = receipt(ctx.wood, U().itemStableId(entry.item, true))
        if row then row.carrierKind, row.carId = "trunk", ctx.carId end
    end
    return true, "wood_cargo_loaded", false
end
local function releaseTarget(ctx, state, memberId)
    L().releaseTree(ctx.missionId, memberId, state.point)
    state.point, state.work, state.phase = nil, nil, "seek"
end
local function addDrops(wood, point, before)
    local logs, reason = L().newLogs(point, before)
    if not logs then return false, reason end
    local known = {}
    for _, row in ipairs(wood.pendingLogs) do known[row.id] = true end
    for _, row in ipairs(logs) do
        if not known[row.id] and not receipt(wood, row.id) and #wood.pendingLogs < 256 then
            wood.pendingLogs[#wood.pendingLogs + 1] = { id = row.id, source = row.source,
                sourceObjectIndex = row.sourceObjectIndex }
        end
    end
    return true
end
local function acquireReceipt(wood, pending, memberId, inTrunk, carId)
    if receipt(wood, pending.id) then return end
    wood.acquisitions[#wood.acquisitions + 1] = { id = pending.id, itemType = "Base.Log",
        memberId = memberId, source = pending.source, sourceObjectIndex = pending.sourceObjectIndex,
        carrierKind = inTrunk and "trunk" or nil, carId = inTrunk and carId or nil }
end
local function recoverPending(ctx, pending)
    local candidate, memberId, trunk, candidates = nil, nil, false, 0
    local function inspect(item, source, ownerId, inTrunk)
        if U().itemStableId(item, false) ~= pending.id then return end
        local marker = data(item)
        marker = marker and marker[CARGO]
        local world, worldKnown = U().call(item, "getWorldItem")
        if U().itemType(item) ~= "Base.Log" or not marker or marker.tripId ~= ctx.missionId
            or marker.id ~= pending.id or call(item, "getContainer") ~= source
            or U().inventoryContains(source, item) ~= true or not worldKnown or world ~= nil then return end
        candidates = candidates + 1
        candidate, memberId, trunk = item, ownerId or marker.memberId, inTrunk
    end
    for _, member in ipairs(ctx.roster or {}) do
        if not member.actor then return false, "wood_pending_owner_unavailable" end
        local entries, why = L().inventoryEntries(member.actor)
        if not entries then return false, why end
        for _, entry in ipairs(entries) do inspect(entry.item, entry.source, member.id, false) end
    end
    if ctx.carId then
        local vehicle = SC.Vehicle.loadedBySqlId(ctx.carId)
        if not vehicle then return false, "wood_pending_car_unloaded" end
        local _, container = SC.Vehicle.cargoPart(vehicle)
        local list = container and call(container, "getItems")
        if not list then return false, "wood_pending_trunk_unreadable" end
        local size = U().listSize(list)
        if type(size) ~= "number" or size > 4096 then return false, "wood_pending_trunk_unreadable" end
        for index = 0, size - 1 do inspect(U().listGet(list, index), container, nil, true) end
    end
    if candidates > 1 then return false, "wood_pending_identity_conflict" end
    if candidate and id(memberId) then
        acquireReceipt(ctx.wood, pending, memberId, trunk, ctx.carId)
        return true, "wood_pickup_reconciled"
    end
    return false, "wood_log_missing"
end
local function takeLog(actor, ctx, state, memberId)
    local wood = ctx.wood
    for index, pending in ipairs(wood.pendingLogs) do
        if pending.workerId then
            local living = false
            for _, member in ipairs(ctx.roster or {}) do
                if member.id == pending.workerId and member.actor
                    and call(member.actor, "isDead") ~= true then living = true break end
            end
            if not living then pending.workerId = nil end
        end
        if (pending.workerId == nil or pending.workerId == memberId)
            and not (pending.blocked and pending.blocked[memberId]) then
            local row, reason = L().groundLog(pending.source, pending.id)
            if not row then
                if reason == "wood_log_missing" then
                    local recovered, why = recoverPending(ctx, pending)
                    if recovered then
                        table.remove(wood.pendingLogs, index)
                        state.phase = ctx.carId and "loading" or "seek"
                        return true, why
                    end
                    if why == "wood_log_missing" then table.remove(wood.pendingLogs, index)
                    else return false, why end
                end
                return false, reason
            end
            local destination, why = carryDestination(actor, row.item, shortShuttle(actor, ctx.carId, row.source))
            if not destination then return false, why end
            pending.workerId = memberId
            local accepted, approach = L().approach(actor, row.square, "wood_collect_log", true)
            if not accepted then
                pending.workerId = nil
                pending.failures = pending.failures or {}
                pending.failures[memberId] = (pending.failures[memberId] or 0) + 1
                if pending.failures[memberId] >= 3 then
                    pending.blocked = pending.blocked or {}
                    pending.blocked[memberId] = true
                end
                return false, approach
            end
            if approach ~= "arrived" then return true, approach end
            local marker = data(row.item)
            if not marker then return false, "wood_item_marker_unavailable" end
            if marker[CARGO] and marker[CARGO].tripId ~= ctx.missionId then pending.workerId = nil return false, "wood_log_reserved" end
            marker[CARGO] = { tripId = ctx.missionId, id = row.id, memberId = memberId }
            local root = U().inventory(actor)
            -- Native pickup always stages to the root. Bag packing below is
            -- an explicit verified mission transfer, not generic loadout work.
            local taken, failure = U().takeWorldItemVerified(row.wrapper, root, row.item)
            if not taken or U().inventoryContains(root, row.item) ~= true then
                if U().worldItemPresent(row.square, row.wrapper) == true then marker[CARGO] = nil end
                pending.workerId = nil
                return false, failure or "wood_pickup_unverified"
            end
            if destination ~= root then
                local packed, packReason = L().transfer(root, destination, actor, row.item)
                if not packed then
                    -- Ownership already moved: retain this exact log and its
                    -- receipt even if packing was refused. Never create a copy.
                    wood.blocker = packReason or "wood_pack_failed"
                end
            end
            acquireReceipt(wood, row, memberId)
            table.remove(wood.pendingLogs, index)
            state.phase = ctx.carId and "loading" or "seek"
            return true, "wood_log_collected"
        end
    end
    return false, "wood_logs_claimed"
end
local function logsReachable(ctx)
    for _, pending in ipairs(ctx.wood.pendingLogs) do
        for _, member in ipairs(ctx.roster or {}) do
            if member.actor and call(member.actor, "isDead") ~= true
                and not (pending.blocked and pending.blocked[member.id]) then return true end
        end
    end
    return false
end
function Wood.outsideWorkAllowed()
    local policies = SC.BaseLife and SC.BaseLife.policies and SC.BaseLife.policies() or {}
    if policies.workOutsideAtNight == true then return true end
    local gameTime = type(getGameTime) == "function" and getGameTime()
    local hour = gameTime and tonumber(call(gameTime, "getTimeOfDay"))
    return not finite(hour) or hour % 24 >= 6 and hour % 24 < 21
end
local function unsafe(actor, ctx)
    if call(actor, "isDead") == true then return "wood_worker_dead" end
    if call(actor, "isOnFire") == true then return "wood_unsafe" end
    local body = call(actor, "getBodyDamage")
    local health = body and tonumber(call(body, "getHealth"))
    if health and health <= 25 then return "wood_injured" end
    local snapshot = ctx.snapshot
    for _, threat in ipairs(type(snapshot) == "table" and snapshot.threats or {}) do
        if (tonumber(threat.distanceSq) or math.huge) <= 400 then return "wood_unsafe" end
    end
    if not Wood.outsideWorkAllowed() then return "wood_night" end
end
function Wood.safety(actor, ctx) return unsafe(actor, ctx or {}) end
local function allScanned(ctx)
    local width = RADIUS * 2 + 1
    for _, member in ipairs(ctx.roster or {}) do
        if member.actor and member.id == ctx.wood.cutterId then
            local state = ctx.wood.workers[member.id]
            if not state or state.scan < width * width or state.point then return false end
        end
    end
    return true
end
function Wood.update(actor, ctx)
    if not actor or type(ctx) ~= "table" or type(ctx.wood) ~= "table"
        or not id(ctx.missionId) or not point(ctx.destination) then return false, "wood_context_unavailable" end
    local wood = initialize(ctx.wood)
    wood.tripId = ctx.missionId
    rt(wood).roster = ctx.roster
    local state, transient, memberId = worker(wood, actor)
    local cutterId = electCutter(wood, ctx.roster)
    local danger = unsafe(actor, ctx)
    if danger then
        if state.phase == "chopping" and SC.NativeActions.workKind(actor) == "chop_tree" then
            local stopped, why = SC.NativeActions.cancelWork(actor, danger)
            if not stopped then return true, why or "wood_chop_settling" end
        end
        if state.point then
            local square = U().gridSquare(state.point.x, state.point.y, state.point.z)
            if square and not L().tree(square) then addDrops(wood, state.point, state.before) end
        end
        releaseTarget(ctx, state, memberId)
        state.phase = "done"
        U().stop(actor)
        return finish(wood, danger)
    end
    if state.phase == "loading" then
        local handled, reason, done = flushCargo(actor, ctx, transient)
        if done then state.phase = wood.complete and "done" or "seek" end
        if reason == "wood_trunk_full" then state.phase = "done" return finish(wood, reason) end
        return handled, reason
    end
    if quota(wood) or wood.complete then
        if not wood.complete then finish(wood, "wood_quantity_met") end
        if state.phase == "chopping" and SC.NativeActions.workKind(actor) == "chop_tree" then
            local stopped, why = SC.NativeActions.cancelWork(actor, wood.doneReason)
            if not stopped then return true, why or "wood_chop_settling" end
        end
        if state.point then
            local square = U().gridSquare(state.point.x, state.point.y, state.point.z)
            if square and not L().tree(square) then addDrops(wood, state.point, state.before) end
            releaseTarget(ctx, state, memberId)
        end
        if ctx.carId and not wood.capacityFull and wood.doneReason ~= "wood_unsafe"
            and wood.doneReason ~= "wood_night" and wood.doneReason ~= "wood_worker_dead"
            and wood.doneReason ~= "wood_injured" then
            local cargo = carriedCargo(actor, wood)
            if cargo and #cargo > 0 then state.phase = "loading" return flushCargo(actor, ctx, transient) end
        end
        state.phase = "done"
        return true, wood.doneReason, Wood.status(wood).done
    end
    if memberId ~= cutterId and state.point and state.phase ~= "chopping" then releaseTarget(ctx, state, memberId) end
    if state.phase == "chopping" then
        if memberId ~= cutterId then
            if SC.NativeActions.workKind(actor) == "chop_tree" then
                local stopped, why = SC.NativeActions.cancelWork(actor, "wood_cutter_handoff")
                if not stopped then return true, why or "wood_chop_settling" end
            end
            local square = U().gridSquare(state.point.x, state.point.y, state.point.z)
            if square and not L().tree(square) then addDrops(wood, state.point, state.before) end
            releaseTarget(ctx, state, memberId)
            return true, "wood_cutter_handoff"
        end
        local square = U().gridSquare(state.point.x, state.point.y, state.point.z)
        if square then L().claimTree(ctx.missionId, memberId, square, actor) end
        local handled, reason, done = L().pollChop(actor, state.work)
        if done then
            local added, why = addDrops(wood, state.point, state.before)
            if not added then return false, why end
            wood.treesFelled = (wood.treesFelled or 0) + 1
            releaseTarget(ctx, state, memberId)
            return true, "wood_tree_felled"
        end
        if not handled and reason ~= "wood_tree_unloaded" then releaseTarget(ctx, state, memberId) end
        return handled, reason
    end
    if #wood.pendingLogs > 0 then
        local handled, reason = takeLog(actor, ctx, state, memberId)
        if handled then return handled, reason end
        if reason == "wood_carry_capacity" then
            if ctx.carId then
                local cargo = carriedCargo(actor, wood)
                if cargo and #cargo > 0 then state.phase = "loading" return flushCargo(actor, ctx, transient) end
            end
            if not rosterCanCarry(ctx.roster, ctx.carId, ctx.destination) then return finish(wood, "wood_capacity_reached") end
            return true, "wood_waiting_for_hauler"
        end
        if reason ~= "wood_logs_claimed" and reason ~= "wood_log_missing" then return false, reason end
        if #wood.pendingLogs > 0 then
            if not logsReachable(ctx) then return finish(wood, "wood_logs_unreachable") end
            return true, "wood_waiting_for_hauler"
        end
    end
    if not rosterCanCarry(ctx.roster, ctx.carId, ctx.destination) then return finish(wood, "wood_capacity_reached") end
    if memberId ~= cutterId then
        if cutterId then return true, "wood_waiting_for_cutter" end
        return finish(wood, "wood_axe_unavailable")
    end
    local tool = axe(actor, wood)
    if not tool then return finish(wood, "wood_axe_unavailable") end
    if call(actor, "isEnduranceSufficientForAction") == false then
        state.restAt = state.restAt or now()
        if now() - state.restAt >= 60000 then return finish(wood, "wood_exhausted") end
        U().stop(actor)
        return true, "wood_resting"
    end
    state.restAt = nil
    if not state.point then
        local inflight = 0
        for _, other in pairs(wood.workers) do if other.point then inflight = inflight + 1 end end
        if wood.request.mode == "count" and #wood.acquisitions + #wood.pendingLogs + inflight >= wood.request.quantity then
            return true, "wood_waiting_for_logs"
        end
        local width, scanned = RADIUS * 2 + 1, 0
        while state.scan < width * width and scanned < 16 do
            local index = state.scan
            state.scan, scanned = state.scan + 1, scanned + 1
            local p = { x = ctx.destination.x - RADIUS + index % width,
                y = ctx.destination.y - RADIUS + math.floor(index / width), z = ctx.destination.z }
            local square = U().gridSquare(p.x, p.y, p.z)
            local bounds = ctx.bounds
            local inForest = not bounds or p.x >= bounds.x1 and p.x <= bounds.x2
                and p.y >= bounds.y1 and p.y <= bounds.y2
            if not square then state.unloaded = true end
            local owned = square and SC.BaseLife and SC.BaseLife.isInside
                and (SC.BaseLife.isInside(square, "area") or SC.BaseLife.isInside(square, "farm")
                    or SC.BaseLife.isInside(square, "lumber"))
            if square and inForest and not owned and L().tree(square)
                and L().claimTree(ctx.missionId, memberId, square, actor) then
                state.point, state.phase = p, "approach"
                break
            end
        end
        if not state.point then
            if allScanned(ctx) then
                local reason = "wood_forest_empty"
                for _, other in pairs(wood.workers) do
                    if other.unloaded then reason = "wood_forest_unloaded" break end
                end
                return finish(wood, reason)
            end
            return true, "wood_scanning"
        end
    end
    local square = U().gridSquare(state.point.x, state.point.y, state.point.z)
    if not square then return false, "wood_tree_unloaded" end
    if not L().tree(square) then releaseTarget(ctx, state, memberId) return true, "wood_tree_gone" end
    if not rosterCanCarry(ctx.roster, ctx.carId, state.point) then
        releaseTarget(ctx, state, memberId)
        return finish(wood, "wood_capacity_reached")
    end
    if not L().claimTree(ctx.missionId, memberId, square, actor) then releaseTarget(ctx, state, memberId) return true, "wood_tree_claimed" end
    local accepted, reason = L().approach(actor, square, "wood_move_to_tree", false)
    if not accepted then
        state.failures = (state.failures or 0) + 1
        if state.failures >= 3 then releaseTarget(ctx, state, memberId) state.failures = 0 end
        return false, reason
    end
    if reason ~= "arrived" then return true, reason end
    local before, why = L().groundIds(state.point)
    if not before then return false, why end
    local started, failure = L().startChop(actor, state.point, tool)
    if not started then return false, failure end
    state.before, state.phase = before, "chopping"
    state.work = { point = state.point, startedAt = now(), progressAt = now(),
        lastHealth = tonumber(call(L().tree(square), "getHealth")) }
    return true, "wood_chopping"
end
function Wood.status(wood)
    if type(wood) ~= "table" then return { done = false, reason = "wood_state_missing", collected = 0, loaded = 0 } end
    local loaded = 0
    for _, row in ipairs(wood.acquisitions or {}) do if row.carrierKind == "trunk" then loaded = loaded + 1 end end
    local done = wood.complete == true
    local transient = runtime[wood]
    local roster = transient and transient.roster
    if roster then
        for _, member in ipairs(roster) do
            local state = wood.workers and wood.workers[member.id]
            if member.actor and call(member.actor, "isDead") ~= true
                and (not state or state.phase ~= "done") then done = false end
        end
    else
        -- Reloaded state is not complete until a worker pulse has reconciled
        -- native work and exact carried items again.
        done = false
    end
    return { done = done, reason = wood.doneReason,
        collected = #(wood.acquisitions or {}), loaded = loaded }
end
function Wood.nextSite(wood)
    Wood.stop(wood, "wood_next_forest")
    wood.workers, wood.pendingLogs, wood.complete, wood.doneReason, wood.capacityFull = {}, {}, nil, nil, nil
    return true
end
function Wood.stop(wood, reason)
    if type(wood) ~= "table" then return true end
    local transient = runtime[wood]
    local gear = transient and transient.gear
    if gear and gear.actor then
        recordGearLoan(wood, gear)
        -- BaseWork performs the actual withdrawal synchronously after its
        -- loot pose, with no deferred inventory callback. Cancel only the
        -- preparation owned movement/pose before forgetting that transaction.
        U().stop(gear.actor)
        if SC.NativeActions and SC.NativeActions.clearVisual then SC.NativeActions.clearVisual(gear.actor) end
    end
    for memberId, state in pairs(wood.workers or {}) do
        local actor = transient and transient.workers[memberId] and transient.workers[memberId].actor or resolve(memberId)
        if actor and state.phase == "chopping" and SC.NativeActions
            and SC.NativeActions.workKind(actor) == "chop_tree" then
            local stopped, why = SC.NativeActions.cancelWork(actor, reason or "wood_stopped")
            if not stopped then return false, why end
        end
        if actor and state.phase ~= "done" then U().stop(actor) end
        if state.point then
            local square = U().gridSquare(state.point.x, state.point.y, state.point.z)
            if square and not L().tree(square) then addDrops(wood, state.point, state.before) end
        end
        L().releaseTree(wood.tripId, memberId)
    end
    runtime[wood] = nil
    return true
end
function Wood.returnTools(actor, ctx)
    local wood, memberId = ctx and ctx.wood, actorId(actor)
    local loan = wood and wood.loans and wood.loans[memberId]
    if not loan then return true, "wood_tools_returned", true end
    local item, source = L().findItem(actor, loan.itemId)
    if not item then return false, "wood_borrowed_axe_missing", false end
    local storage = SC.BaseLife.storage(loan.storageId)
    local container = storage and SC.BaseLife.resolveContainer(storage)
    if not container then return false, "wood_tool_source_unavailable", false end
    local inventory = U().inventory(actor)
    if source ~= inventory then
        local entries = L().inventoryEntries(actor)
        local owned = false
        for _, entry in ipairs(entries or {}) do
            if entry.item == item and entry.source == source then owned = true break end
        end
        if not owned or not source or call(item, "getContainer") ~= source
            or U().inventoryContains(source, item) ~= true then
            return false, "wood_tool_source_changed", false
        end
        if not inventory or not SC.WorkTransport
            or SC.WorkTransport.hasRoom(inventory, actor, item) ~= true then
            return false, "wood_tool_staging_full", false
        end
        if SC.WorkTransport.transferVerified then
            SC.WorkTransport.transferVerified(source, inventory, item, actor)
        else U().transferItemVerified(source, inventory, item) end
        if call(item, "getContainer") ~= inventory
            or U().inventoryContains(inventory, item) ~= true
            or U().inventoryContains(source, item) == true then
            return false, "wood_tool_staging_unverified", false
        end
    end
    local transient = rt(wood)
    transient.returns = transient.returns or {}
    transient.returns[memberId] = transient.returns[memberId] or {}
    local returned, reason = SC.BaseWork.returnToStorage(actor, transient.returns[memberId], storage, container, item)
    if returned and reason == "base_supply_returned" then
        if U().inventoryContains(container, item) ~= true or call(item, "getContainer") ~= container then
            return false, "wood_axe_return_unverified", false
        end
        local marker = data(item)
        if marker then marker[TOOL] = nil end
        wood.loans[memberId] = nil
        return true, "wood_axe_returned", true
    end
    return returned, reason or "wood_returning_axe", false
end
-- Delivery settlement asks whether a recorded loan can still be repaid.
-- "missing" means the borrower's whole inventory was read without the exact
-- axe; an unreadable inventory is "unknown" and keeps the obligation.
function Wood.loanState(wood, memberId, actor)
    local loans = type(wood) == "table" and type(wood.loans) == "table" and wood.loans or nil
    local loan = loans and loans[tostring(memberId)]
    if type(loan) ~= "table" then return "none" end
    if not actor or not L() then return "unknown" end
    local item, _, reason = L().findItem(actor, loan.itemId)
    if item then return "carried" end
    return reason == "item_not_carried" and "missing" or "unknown"
end
function Wood.toolsPending(wood, memberId)
    if type(wood) ~= "table" or type(wood.loans) ~= "table" then return false end
    if memberId ~= nil then return wood.loans[tostring(memberId)] ~= nil end
    for _ in pairs(wood.loans) do return true end
    return false
end
Wood._tests = { carryDestination = carryDestination, freeCapacity = freeCapacity,
    addDrops = addDrops, quota = quota, toolAllowed = toolAllowed }
return Wood
