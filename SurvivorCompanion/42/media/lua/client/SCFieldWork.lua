-- SPDX-License-Identifier: MIT
-- One-shot work around the leader. Native farming/chopping creates the output;
-- this coordinator only chooses targets and moves exact items to the car.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.FieldWork = SC.FieldWork or {}
local Field = SC.FieldWork

local active, recentVehicleId, serial = nil, nil, 0
local pendingAxeReturns = {}
local areaMarkers, markerExpiry = {}, 0
local HARVEST_RADIUS, HARVEST_LEASH, HARVEST_CAR_RANGE = 16, 32, 40
local CHOP_RADIUS, CHOP_LEASH, CHOP_CAR_RANGE = 8, 25, 20
local MARK = "LF_FieldOrder"
local CARRY_MARK = "LF_FieldCarryWorker"
local function radius(kind) return kind == "harvest" and HARVEST_RADIUS or CHOP_RADIUS end
local function leash(kind) return kind == "harvest" and HARVEST_LEASH or CHOP_LEASH end
local function carRange(kind)
    return kind == "harvest" and HARVEST_CAR_RANGE or CHOP_CAR_RANGE
end
local AXE_MARK = "LF_FieldBorrowedAxe"
local WORKER_MARK = "LF_FieldWorker"
local missingCarriers = {}
local function U() return SC.GameplayUtil end
local function call(object, name, ...)
    local value, okay = U().call(object, name, ...)
    return okay and value or nil
end
local function point(value)
    local x, y, z = U().position(value)
    if x == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
end
local function distance(a, b)
    if not a or not b then return math.huge end
    if a.z ~= b.z then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function key(x, y, z) return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z) end
local function itemId(item) return U().itemStableId(item, true) end
local function marker(item)
    local data = U().modData(item)
    return data and data[MARK] or nil
end
local function mark(item, orderId, workerId)
    local data = U().modData(item)
    if not data or not itemId(item) then return false end
    data[MARK] = orderId
    data[WORKER_MARK] = workerId
    return data[MARK] == orderId
end
local function markAxe(item, orderId, workerId)
    local data = U().modData(item)
    if not data or not itemId(item) then return false end
    data[AXE_MARK] = orderId
    data[WORKER_MARK] = workerId
    return data[AXE_MARK] == orderId
end
local function vehicleById(id)
    return id and SC.Vehicle and SC.Vehicle.loadedBySqlId
        and SC.Vehicle.loadedBySqlId(id) or nil
end
local function trunk(vehicle)
    if not vehicle then return nil, nil, "car_unloaded" end
    if not SC.Vehicle or SC.Vehicle.isStationary(vehicle) ~= true then
        return nil, nil, "car_moved"
    end
    if type(SC.Vehicle.cargoPart) ~= "function" then
        return nil, nil, "car_trunk_missing"
    end
    local part, container, reason = SC.Vehicle.cargoPart(vehicle)
    if not container then return part, nil, reason or "car_trunk_missing" end
    if call(vehicle, "isTrunkLocked") == true then
        return part, nil, "car_trunk_locked"
    end
    return part, container
end
-- A rejected native check may mean a container restriction or an unavailable
-- adapter. Only the shared capacity helper can prove that space is exhausted.
local function cargoRoom(container, actor, item)
    local transport = SC.WorkTransport
    if not transport or type(transport.hasRoom) ~= "function" then
        return false, "capacity_unavailable"
    end
    local checked, room, reason = pcall(transport.hasRoom, container, actor, item)
    if checked and room == true then return true end
    return false, checked and type(reason) == "string" and reason
        or "capacity_unavailable"
end
local function pauseCargo(actor, order, reason)
    reason = reason or "capacity_unavailable"
    order.phase, order.blocker = "paused", reason
    local message = reason == "destination_item_rejected"
        and "The container won't accept this item. I'm keeping it until we sort that out."
        or reason == "capacity_unavailable"
            and "I couldn't check the container's space. I'm keeping the cargo; ask me to resume."
        or nil
    if message then
        order.note = message
        if order.cargoNotice ~= reason and type(U().say) == "function" then
            U().say(actor, message)
        end
        order.cargoNotice = reason
    end
    return false, reason
end
local function carNear(center, id, kind)
    local vehicle = vehicleById(id)
    if not vehicle or distance(center, point(vehicle)) > carRange(kind) then
        return nil, nil, nil, "car_out_of_range"
    end
    local part, container, reason = trunk(vehicle)
    return vehicle, part, container, reason
end
local function followers(player, kind)
    local result = {}
    local range = kind and leash(kind) or math.max(HARVEST_LEASH, CHOP_LEASH)
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        local state = SC.Commands and SC.Commands.peek and SC.Commands.peek(actor)
        local id = U().idOf(actor)
        if id and state and state.recruited and state.order == "follow"
            and call(actor, "getVehicle") == nil
            and distance(point(actor), point(player)) <= range then
            result[#result + 1] = tostring(id)
        end
    end
    table.sort(result)
    return result
end
local function workerFor(actor)
    if not active or active.phase ~= "working" then return nil end
    local id = tostring(U().idOf(actor) or "")
    return active.workers[id], id
end
local function actorFor(id)
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        if tostring(U().idOf(actor) or "") == id then return actor end
    end
    return nil
end

-- Use a vacant, reachable passenger door where possible. Never break the
-- player's window merely to open the trunk; a locked door needs a real key.
local function unlockSeat(actor, vehicle)
    if not SC.Vehicle or not SC.Vehicle.boardingSquares then
        return nil, "vehicle_adapter_unavailable"
    end
    local count = tonumber(call(vehicle, "getMaxPassengers"))
    if not count or count < 1 or count > 32 then
        return nil, "car_seats_unavailable"
    end
    local hasKey = SC.Driving and SC.Driving.hasKey
        and SC.Driving.hasKey(actor, vehicle) == true
    local reason = "car_entry_unavailable"
    for index = 1, count do
        local seat = index < count and index or 0
        if call(vehicle, "isSeatInstalled", seat) == true
            and call(vehicle, "getCharacter", seat) == nil then
            local part = call(vehicle, "getPassengerDoor", seat)
            local door = part and call(part, "getDoor")
            if not door or call(door, "isLocked") ~= true or hasKey then
                local squares, _, why = SC.Vehicle.boardingSquares(
                    actor, vehicle, seat, seat == 0)
                if squares and #squares > 0 then return seat end
                reason = why or reason
            else
                reason = "car_entry_locked"
            end
        end
    end
    return nil, reason
end

local function sayTrunkUnlocked(actor)
    if SC.Dialogue and type(SC.Dialogue.say) == "function"
        and SC.Dialogue.say(actor, "vehicle.trunk.unlocked") == true then return end
    if type(U().say) == "function" then
        U().say(actor, "There. The trunk was just being stubborn.")
    end
end
local function carriedEntries(actor)
    local inventory = U().inventory(actor)
    if not inventory then return nil, "inventory_unavailable" end
    local containers, seen = { inventory }, { [inventory] = true }
    local entries, cursor = {}, 1
    while cursor <= #containers do
        local source = containers[cursor]
        cursor = cursor + 1
        local available = 4096 - #entries
        local items = U().inventoryItems(source, available + 1)
        if #items > available then return nil, "inventory_scan_limit" end
        for _, item in ipairs(items) do
            entries[#entries + 1] = { item = item, source = source }
            local nested = select(1, U().call(item, "getItemContainer"))
            if nested and not seen[nested] then
                if #containers >= 64 then return nil, "inventory_container_limit" end
                seen[nested] = true
                containers[#containers + 1] = nested
            end
        end
    end
    return entries
end
local function carriedItems(actor)
    local entries = carriedEntries(actor)
    local items = {}
    for _, entry in ipairs(entries or {}) do items[#items + 1] = entry.item end
    return items
end
local function carries(actor, item)
    if U().inventoryContains(U().inventory(actor), item) then return true end
    for _, candidate in ipairs(carriedItems(actor)) do
        if candidate == item then return true end
    end
    return false
end
local function ownedByBase(square)
    if not SC.BaseLife or not SC.BaseLife.isInside then return false end
    return SC.BaseLife.isInside(square, "area") == true
        or SC.BaseLife.isInside(square, "farm") == true
        or SC.BaseLife.isInside(square, "lumber") == true
end
local function crop(square)
    local system = type(CFarmingSystem) == "table" and CFarmingSystem.instance
    local plant = system and call(system, "getLuaObjectOnSquare", square)
    return plant and call(plant, "canHarvest") == true and plant or nil
end
local function tree(square)
    local value = call(square, "getTree")
    if not value or (tonumber(call(value, "getObjectIndex")) or -1) < 0 then
        return nil
    end
    if (tonumber(call(value, "getSize")) or 2) < 2 then return nil end
    return value
end
local function targetAt(order, x, y)
    local dx, dy = x - order.center.x, y - order.center.y
    local range = radius(order.kind)
    if dx * dx + dy * dy > range * range then return nil end
    local square = U().gridSquare(x, y, order.center.z)
    if not square or ownedByBase(square) then return nil end
    local object
    if order.kind == "harvest" then object = crop(square) else object = tree(square) end
    return object and square or nil
end
-- What is left in the area is checked a slice at a time, at most this many
-- tiles per call: a harvest area alone is about 800 tiles. The cursor lives
-- on the order, so a reload carries on, and nil means "not finished yet".
local CLEARING_SCAN_TILES = 64
local function clearingResult(order)
    local range = radius(order.kind)
    local width = range * 2 + 1
    local harvest = order.kind == "harvest"
    local scan = order.clearingScan
    if type(scan) ~= "table" then
        scan = { index = 0, unchecked = false, found = false }
        order.clearingScan = scan
    end
    local inspected = 0
    while not scan.found and scan.index < width * width do
        local dx = scan.index % width - range
        local dy = math.floor(scan.index / width) - range
        if dx * dx + dy * dy <= range * range then
            if inspected >= CLEARING_SCAN_TILES then return nil end
            inspected = inspected + 1
            local x, y = order.center.x + dx, order.center.y + dy
            if not U().gridSquare(x, y, order.center.z) then
                scan.unchecked = true
            elseif targetAt(order, x, y) then
                scan.found = true
            end
        end
        scan.index = scan.index + 1
    end
    if scan.found then
        return harvest
            and "Some ripe crops are still growing around this spot."
            or "Some trees are still standing around this spot."
    end
    if scan.unchecked then
        return harvest
            and "I harvested the crops I could reach, but couldn't check the whole area."
            or "I cleared the trees I could reach, but couldn't check the whole area."
    end
    return harvest and "All the ripe crops around this spot are harvested."
        or "All the trees around this spot are cleared."
end
local function claimed(order, targetKey)
    if order.done[targetKey] then return true end
    for _, worker in pairs(order.workers) do
        if worker.target == targetKey then return true end
    end
    return false
end
local function nextTarget(order, worker)
    local range = radius(order.kind)
    local width = range * 2 + 1
    local inspected = 0
    while inspected < 16 and worker.scan < width * width do
        local index = worker.scan
        worker.scan = worker.scan + 1
        inspected = inspected + 1
        local x = order.center.x - range + index % width
        local y = order.center.y - range + math.floor(index / width)
        local square = targetAt(order, x, y)
        local targetKey = key(x, y, order.center.z)
        if square and not claimed(order, targetKey) then
            worker.target, worker.x, worker.y = targetKey, x, y
            worker.phase = "approach"
            return square
        end
    end
    return nil
end
local function targetsAround(actor, square, includeOwn)
    local offered = SC.Navigation and SC.Navigation.interactionTargets
        and SC.Navigation.interactionTargets(actor, square,
            { requireDirectAccess = true }) or {}
    local targets = {}
    for _, candidate in ipairs(offered or {}) do
        local cp, sp = point(candidate), point(square)
        if cp and sp and (includeOwn and key(cp.x, cp.y, cp.z) == key(sp.x, sp.y, sp.z)
            or math.abs(cp.x - sp.x) + math.abs(cp.y - sp.y) == 1)
            and U().isSquareFree(candidate) then
            targets[#targets + 1] = candidate
        end
    end
    return targets
end
local function approach(actor, square, action, includeOwn)
    local targets = targetsAround(actor, square, includeOwn)
    if #targets == 0 then return false, "no_interaction_targets" end
    local okay, reason, reached = SC.Navigation.requestAny(actor, targets, "walk", {
        action = action, targetSquare = square,
        arrivalDistance = includeOwn and 0.45 or 0.5,
        requireSameSquare = not includeOwn,
    })
    if okay ~= true then return false, reason end
    if reason == "arrived" and reached and U().sameSquare(actor, reached) then
        return true, "arrived"
    end
    return true, "approaching"
end
local function inventoryIds(actor)
    local ids = {}
    local entries = carriedEntries(actor)
    if not entries then return nil end
    for _, entry in ipairs(entries) do
        local id = itemId(entry.item)
        if id then ids[id] = true end
    end
    return ids
end
local function adoptHarvest(actor, worker, order)
    local inventory = U().inventory(actor)
    if not inventory then return false, "inventory_unavailable" end
    -- The native harvest action names its output from the plant's registered
    -- seed props. An inventory delta alone can include gifts or mod rewards.
    local allowed = {}
    for _, itemType in ipairs(type(worker.harvestTypes) == "table"
        and worker.harvestTypes or {}) do
        allowed[itemType] = true
    end
    local added = 0
    local entries, scanReason = carriedEntries(actor)
    if not entries then return false, scanReason end
    for _, entry in ipairs(entries) do
        local item = entry.item
        local id = itemId(item)
        if id and worker.before[id] ~= true and marker(item) == nil
            and allowed[U().itemType(item)] == true then
            if not mark(item, order.id, tostring(U().idOf(actor))) then
                return false, "cargo_marker_failed" end
            added = added + U().itemWeight(item)
        end
    end
    -- The largest yield seen so far predicts the next one; see fullLoad.
    worker.yieldWeight = math.max(tonumber(worker.yieldWeight) or 0, added)
    return true
end

-- A worker ends a trip at 80% of its Strength carrying limit (U.carryLoad),
-- so routine field work does not keep companions under Heavy Load. A harvest,
-- however, adds its whole yield at once, and from 79% one plant could carry a
-- companion past that limit even with "Allow overload" off. For harvest,
-- "full" therefore also means "the next plant would exceed what this companion
-- may carry", using the largest yield seen this order or the crop's registered
-- maximum. One plant of pumpkins can outweigh an average companion's whole
-- Strength limit, so a worker holding none of this order's cargo may still
-- take one target that fits the physical inventory (firstTargetFits).
local FULL_LOAD = 0.8
local function overloadAllowed(actor)
    local data = select(1, U().call(actor, "getModData"))
    return type(data) == "table" and data.SC_AllowOverload == true
end
local function propsYieldWeight(props, plant, actor)
    if type(props) ~= "table" then return nil end
    local count = tonumber(props.maxVegAutorized) or tonumber(props.maxVeg)
    if not count or count <= 0 then return nil end
    -- Vanilla can add one bonus vegetable and up to the farmer's skill after
    -- applying maxVegAutorized. Extra produce and seeds also enter the bag in
    -- the same native harvest action, so reserve room for all of them.
    if plant and plant.bonusYield and not plant.cursed then count = count + 1 end
    local farmingPerk = Perks and Perks.Farming or nil
    local skill = farmingPerk and tonumber(tostring(select(1,
        U().call(actor, "getPerkLevel", farmingPerk)))) or nil
    count = math.floor(count + math.max(0, math.min(10, skill or 10)))
    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    if not manager then return nil end
    local total, included = 0, false
    local function add(itemType, quantity)
        if type(itemType) ~= "string" or itemType == "" then return true end
        local script = select(1, U().call(manager, "FindItem", itemType))
        local weight = script and tonumber(tostring(select(1,
            U().call(script, "getActualWeight")))) or nil
        if not weight or weight < 0 then return false end
        total, included = total + quantity * weight, true
        return true
    end
    if not add(props.vegetableName, count)
        or not add(props.produceExtra, count) then return nil end
    if plant and plant.hasSeed then
        local seedCount = math.max(1,
            math.floor(count * math.max(0, tonumber(props.seedPerVeg) or 0.5)))
        if not add(props.seedName, seedCount) then return nil end
    end
    return included and total or nil
end
local function fullLoad(actor, worker, order)
    if order.kind ~= "harvest" then return FULL_LOAD end
    local expected = math.max(tonumber(worker.yieldWeight) or 0,
        tonumber(worker.yieldEstimate) or 0)
    local _, capacity = U().carryLoad(actor)
    if expected <= 0 or not capacity or capacity <= 0 then return FULL_LOAD end
    local limit = overloadAllowed(actor)
        and (tonumber(U().config("logisticsOverloadHardLoadRatio")) or 1.2) or 1.0
    return math.max(0, math.min(FULL_LOAD, limit - expected / capacity))
end
local function firstTargetFits(actor, worker, order)
    local weight, capacity = U().inventoryLoad(actor)
    if not capacity or capacity <= 0 or weight / capacity >= FULL_LOAD then
        return false
    end
    if order.kind ~= "harvest" then return true end
    local expected = math.max(tonumber(worker.yieldWeight) or 0,
        tonumber(worker.yieldEstimate) or 0)
    local limit = overloadAllowed(actor)
        and (tonumber(U().config("logisticsOverloadHardLoadRatio")) or 1.2) or 1.0
    return (weight + expected) / capacity <= limit
end

local function capacityNotice(actor, order, reason, full)
    local message
    if order.kind == "harvest" then
        if reason == "yield_too_heavy" then
            message = "That crop's harvest is too heavy for my bag. I'll leave it growing."
        elseif reason == "car_trunk_full" then
            message = full and "My bag and the trunk are full. I'll leave the remaining crops growing."
                or "The trunk is full. I'll keep this harvest in my bag."
        else
            message = order.carId
                and "My bag is full. I'll leave any remaining crops growing."
                or "My bag is full and no car is assigned. I'm keeping the crops with me."
        end
    elseif reason == "car_trunk_full" then
        message = full and "My bag and the trunk are full. I'll keep clearing trees and leave the logs here."
            or "The trunk is full. I'll keep clearing trees and leave the logs here."
    else
        message = order.carId
            and "I can't carry another log to the car. I'll keep clearing trees and leave the logs here."
            or "My bag is full and no car is assigned. I'll keep clearing trees and leave the logs here."
    end
    if order.kind == "harvest" and order.capacityNotice == "car_trunk_full"
        and (reason == "inventory_full" or reason == "yield_too_heavy") then
        return
    end
    order.note = message
    if order.capacityNotice ~= reason then
        order.capacityNotice = reason
        if type(U().say) == "function" then U().say(actor, message) end
    end
end
local function woodOn(square, order, workerId, before)
    local result = {}
    local origin = point(square)
    for dx = -1, 1 do for dy = -1, 1 do
        local tile = U().gridSquare(origin.x + dx, origin.y + dy, origin.z)
        local objects = tile and call(tile, "getWorldObjects") or nil
        U().each(objects, 32, function(wrapper)
            local item = call(wrapper, "getItem")
            local itemType = item and U().itemType(item) or nil
            local id = item and itemId(item)
            if item and id and (itemType == "Base.Log"
                or itemType == "Base.TreeBranch" or itemType == "Base.Twigs")
                and (marker(item) == order.id
                    or marker(item) == nil and not (before and before[id]))
                and (not order.woodClaims[id] or order.woodClaims[id] == workerId) then
                result[#result + 1] = { wrapper = wrapper, item = item,
                    square = tile, id = id }
            end
        end)
    end end
    return result
end
local function worldIds(square)
    local ids = {}
    local origin = point(square)
    for dx = -1, 1 do for dy = -1, 1 do
        local tile = U().gridSquare(origin.x + dx, origin.y + dy, origin.z)
        local objects = tile and call(tile, "getWorldObjects") or nil
        U().each(objects, 32, function(wrapper)
            local item = call(wrapper, "getItem")
            if item then local id = itemId(item) if id then ids[id] = true end end
        end)
    end end
    return ids
end
local function axeIn(container, ownerId)
    local owed = ownerId ~= nil and pendingAxeReturns[tostring(ownerId)] or nil
    for _, item in ipairs(U().inventoryItems(container, 4096)) do
        local data = U().modData(item)
        -- An axe owed to an earlier car is not this order's free equipment.
        -- The worker who owes it may still use it: the return obligation
        -- stays on the axe, and dropping that worker from every later order
        -- would strand them whenever the original car cannot be reached.
        if U().itemHasTag(item, "CHOP_TREE") and call(item, "isBroken") ~= true
            and (not data or data[AXE_MARK] == nil
                or active and data[AXE_MARK] == active.id
                or owed and data[AXE_MARK] == owed.orderId
                    and itemId(item) == owed.itemId) then
            return item
        end
    end
    return nil
end
local function carSquares(actor, vehicle, part)
    local area = call(part, "getArea")
    local centre = area and call(vehicle, "getAreaCenter", area)
    local center = point(centre)
    local squares = {}
    if not center then return squares end
    center.z = (point(vehicle) or center).z
    local centreSquare = U().gridSquare(center.x, center.y, center.z)
    if not centreSquare or not SC.Navigation
        or not SC.Navigation.interactionTargets then return squares end
    -- The trunk is a fixed interaction point. Distance alone admits a tile
    -- through a wall or fence; Navigation checks the actual contact edges.
    squares = SC.Navigation.interactionTargets(actor, centreSquare,
        { requireDirectAccess = true, maximum = 8 }) or {}
    return squares
end
local function atCar(actor, vehicle, part)
    local squares = carSquares(actor, vehicle, part)
    if #squares == 0 then return false, "car_access_blocked" end
    local okay, reason, reached = SC.Navigation.requestAny(actor, squares, "walk", {
        action = "field_car_cargo", targetSquare = point(vehicle),
        requireSameSquare = true, arrivalDistance = 0.5,
    })
    if not okay then return false, reason end
    if reason == "arrived" and reached and U().sameSquare(actor, reached) then
        for _, current in ipairs(carSquares(actor, vehicle, part)) do
            if U().sameSquare(actor, current) then return true, "arrived" end
        end
    end
    return true, "approaching"
end
local function cargoItems(actor, orderId)
    local result = {}
    local entries, reason = carriedEntries(actor)
    if not entries then return nil, reason end
    for _, entry in ipairs(entries) do
        if marker(entry.item) == orderId then result[#result + 1] = entry end
    end
    return result
end

local function release(worker)
    worker.target, worker.x, worker.y, worker.before = nil, nil, nil, nil
    worker.groundBefore, worker.startedAt, worker.phase = nil, nil, "seek"
end

local function leaveWood(actor, worker, order, reason, full)
    worker.skipPickup = true
    capacityNotice(actor, order, reason, full)
    if worker.phase == "done" or worker.afterDeposit == "done" then
        worker.phase = "done"
    else release(worker) end
    worker.afterDeposit = nil
    return true, "field_wood_left_on_ground"
end

local function keepHarvest(actor, worker, order, full)
    worker.skipDeposit = true
    capacityNotice(actor, order, "car_trunk_full", full)
    if worker.phase == "done" or worker.afterDeposit == "done" then
        worker.phase = "done"
    else
        release(worker)
        -- Revisit a plant passed over while seeking trunk space if the bag
        -- still has room. This rewind happens only once per worker.
        worker.scan = 0
    end
    worker.afterDeposit = nil
    return true, "field_harvest_kept"
end

local function loadCar(actor, worker, order)
    local vehicle, part, container, reason = carNear(order.center, order.carId, order.kind)
    if not container then order.phase, order.blocker = "paused", reason return false, reason end
    local okay, approachReason = atCar(actor, vehicle, part)
    if not okay then order.phase, order.blocker = "paused", approachReason return false, approachReason end
    if approachReason ~= "arrived" then return true, "field_cargo_approaching" end
    local cargo, cargoReason = cargoItems(actor, order.id)
    if not cargo then
        order.phase, order.blocker = "paused", cargoReason
        return false, cargoReason
    end
    if #cargo == 0 then
        worker.phase = worker.afterDeposit or "seek"
        worker.afterDeposit = nil
        return true, "field_cargo_loaded"
    end
    -- Keep transfers bounded per decision beat, but unload a useful batch
    -- instead of making a separate trip through the decision loop per crop.
    for index = 1, math.min(#cargo, 8) do
        local item, source = cargo[index].item, cargo[index].source
        local room, roomReason = cargoRoom(container, actor, item)
        if not room then
            if roomReason ~= "destination_full" then
                return pauseCargo(actor, order, roomReason)
            end
            if order.kind == "chop" then
                local _, _, load = U().carryLoad(actor)
                return leaveWood(actor, worker, order, "car_trunk_full",
                    load >= FULL_LOAD)
            elseif order.kind == "harvest" then
                local _, _, load = U().carryLoad(actor)
                return keepHarvest(actor, worker, order,
                    load >= fullLoad(actor, worker, order))
            end
            order.phase, order.blocker = "paused", "car_trunk_full"
            return false, order.blocker
        end
        local moved, moveReason = U().transferItemVerified(source, container, item)
        if not moved then
            if order.kind == "chop" and moveReason == "destination_full" then
                local _, _, load = U().carryLoad(actor)
                return leaveWood(actor, worker, order, "car_trunk_full",
                    load >= FULL_LOAD)
            elseif order.kind == "harvest" and moveReason == "destination_full" then
                local _, _, load = U().carryLoad(actor)
                return keepHarvest(actor, worker, order,
                    load >= fullLoad(actor, worker, order))
            end
            return pauseCargo(actor, order, moveReason)
        end
        if U().inventoryContains(container, item) ~= true then
            order.phase, order.blocker = "paused", "field_cargo_unverified"
            return false, order.blocker
        end
        local data = U().modData(item)
        if data then data[MARK], data[WORKER_MARK] = nil, nil end
        order.loaded = order.loaded + 1
    end
    return true, "field_cargo_loaded"
end
-- A dead or dismissed worker can never report done. "No living actor" alone
-- is not proof: a saved companion has no registry record until its
-- asynchronous respawn, so use the shared base-work rule.
local function workerGone(id)
    return SC.BaseFuel ~= nil and type(SC.BaseFuel.workerIdGone) == "function"
        and SC.BaseFuel.workerIdGone(id) == true
end
local function completeIfFinished(order)
    -- Check every worker before marking any cargo, so a worker who is still
    -- busy or loading never leaves the others' harvest half re-marked.
    -- A worker back at work makes a partial check of what is left stale.
    local function notYet()
        order.clearingScan = nil
        if not order.completionAnnounced then order.completionNote = nil end
        return false
    end
    local finished = {}
    for id, state in pairs(order.workers) do
        local member = actorFor(id)
        if member then
            if state.phase ~= "done" and state.phase ~= "full" then return notYet() end
            local cargo, reason = cargoItems(member, order.id)
            if not cargo then
                order.phase, order.blocker = "paused", reason
                return notYet()
            end
            if order.carId and #cargo > 0
                and not state.skipPickup and not state.skipDeposit then
                return notYet()
            end
            finished[#finished + 1] = { id = id, member = member,
                cargo = cargo, state = state }
        elseif not workerGone(id) then
            return notYet()
        end
    end
    if not order.completionAnnounced and not order.completionNote then
        order.completionNote = clearingResult(order)
        if not order.completionNote then return false end
    end
    for _, worker in ipairs(finished) do
        local id, member, cargo = worker.id, worker.member, worker.cargo
        if not order.carId or worker.state.skipPickup or worker.state.skipDeposit then
            for _, entry in ipairs(cargo) do
                local data = U().modData(entry.item)
                if data then
                    -- Preserve the exact trip cargo until it reaches camp.
                    data[MARK], data[WORKER_MARK] = nil, nil
                    data[CARRY_MARK] = id
                end
            end
        end
        if worker.state.skipPickup and worker.state.axeId and order.carId then
            pendingAxeReturns[id] = {
                itemId = worker.state.axeId, orderId = order.id,
                carId = order.carId, center = order.center, kind = order.kind,
            }
        end
        local actorData = U().modData(member)
        if actorData then actorData.LF_FieldReturnCleanup = order.id end
    end
    order.phase = "complete"
    order.clearingScan = nil
    if not order.completionAnnounced then
        order.completionAnnounced = true
        local speaker = finished[1] and finished[1].member
        if speaker and type(U().say) == "function" then
            U().say(speaker, order.completionNote)
        end
    end
    return true
end
local function currentTarget(worker, order)
    return worker.x and U().gridSquare(worker.x, worker.y, order.center.z) or nil
end
local function stopAction(actor)
    if SC.NativeActions and SC.NativeActions.isWorkActive(actor) == true then
        SC.NativeActions.cancelWork(actor, "field_order_stopped")
    end
    if SC.Navigation and SC.Navigation.cancel then
        SC.Navigation.cancel(actor, "field_order_stopped")
    end
end

function Field.unlocking(actor)
    return active ~= nil and active.phase == "unlocking"
        and active.unlock ~= nil
        and active.unlock.actorId == tostring(U().idOf(actor) or "")
end

-- Shared one-car trunk transaction for expedition receipts. Keep the actor in
-- the vehicle until the native lock change is verified, then get out before
-- any cargo action. The caller owns the transient state, so reload resumes
-- from the actor's actual seat and lock instead of a saved guessed phase.
function Field.unlockTrunkFor(actor, vehicle, state, snapshot)
    if not actor or not vehicle or type(state) ~= "table" then
        return false, "car_entry_unavailable"
    end
    local now = U().nowMs()
    state.startedAt = state.startedAt or now
    local seated = call(actor, "getVehicle")
    if seated ~= nil and seated ~= vehicle then
        return false, "companion_in_other_car"
    end
    local locked = call(vehicle, "isTrunkLocked")
    if seated == nil and locked == false then
        if state.unlocked then sayTrunkUnlocked(actor) end
        state.unlocked = nil
        return true, "field_trunk_unlocked"
    end
    if seated == vehicle then
        state.seat = call(vehicle, "getSeat", actor) or state.seat
        if locked == true then
            state.readyAt = state.readyAt or now + 700
            if now < state.readyAt then return true, "field_trunk_unlocking" end
            local _, changed = U().call(vehicle, "setTrunkLocked", false)
            if changed ~= true or call(vehicle, "isTrunkLocked") ~= false then
                return false, "car_trunk_unlock_failed"
            end
            state.unlocked = true
        end
        local exited, reason = SC.Vehicle.exit(actor, vehicle, state.seat,
            { playerCommand = true })
        return exited == true, exited and "field_trunk_exiting"
            or reason or "car_exit_blocked"
    end
    if now - state.startedAt > 75000 then return false, "car_entry_timeout" end
    local seat, why = unlockSeat(actor, vehicle)
    if seat == nil then return false, why end
    state.seat = seat
    return SC.ExpeditionCar.boardMember(actor,
        { car = vehicle, seat = seat, fieldWork = true }, snapshot)
end

local function unlockStep(actor, order, snapshot)
    local task = order.unlock
    local vehicle = vehicleById(order.carId)
    if not vehicle then
        order.phase, order.blocker = "paused", "car_unloaded"
        return false, order.blocker
    end
    local seated = call(actor, "getVehicle")
    if seated ~= nil and seated ~= vehicle then
        order.phase, order.blocker = "paused", "companion_in_other_car"
        return false, order.blocker
    end
    if task.stage == "exit" then
        if seated == vehicle then
            local exited, why = SC.Vehicle.exit(actor, vehicle, task.seat,
                { playerCommand = true })
            if exited ~= true then
                if U().nowMs() < task.startedAt + 75000 then
                    return true, why or "field_trunk_exiting"
                end
                order.phase, order.blocker = "paused", "car_exit_blocked"
                return false, order.blocker
            end
            seated = call(actor, "getVehicle")
            if seated ~= nil then return true, "field_trunk_exiting" end
        end
        local locked, checked = U().call(vehicle, "isTrunkLocked")
        if task.unlocked and checked and locked == false then
            order.phase, order.blocker, order.unlock = "working", nil, nil
            sayTrunkUnlocked(actor)
            return true, "field_trunk_unlocked"
        end
        order.phase, order.blocker = "paused",
            task.failure or "car_trunk_unlock_failed"
        return false, order.blocker
    end
    local locked, checked = U().call(vehicle, "isTrunkLocked")
    if seated == nil and checked and locked == false then
        if SC.Vehicle.cancelTransaction then
            SC.Vehicle.cancelTransaction(actor, "trunk_unlocked_elsewhere")
        end
        order.phase, order.blocker, order.unlock = "working", nil, nil
        return true, "field_trunk_already_unlocked"
    end
    if U().nowMs() >= task.startedAt + 60000 then
        task.stage, task.failure = "exit", "car_entry_timeout"
        return true, task.failure
    end
    if seated == nil then
        local seat, why = unlockSeat(actor, vehicle)
        if seat == nil then
            order.phase, order.blocker = "paused", why
            return false, why
        end
        task.seat = seat
        if not SC.ExpeditionCar or not SC.ExpeditionCar.boardMember then
            order.phase, order.blocker = "paused", "vehicle_adapter_unavailable"
            return false, order.blocker
        end
        local boarded, reason = SC.ExpeditionCar.boardMember(actor,
            { car = vehicle, seat = seat, fieldWork = true }, snapshot)
        if boarded ~= true and type(reason) == "string"
            and (reason:find("locked", 1, true)
                or reason:find("unavailable", 1, true)
                or reason:find("rejected", 1, true)) then
            order.phase, order.blocker = "paused", reason
            return false, reason
        end
        return true, reason or "field_trunk_boarding"
    end
    if call(vehicle, "getSeat", actor) ~= task.seat then
        task.stage, task.failure = "exit", "car_seat_changed"
        return true, task.failure
    end
    if task.stage ~= "unlock" then
        task.stage, task.readyAt = "unlock", U().nowMs() + 700
        return true, "field_trunk_unlocking"
    end
    if U().nowMs() < task.readyAt then return true, "field_trunk_unlocking" end
    local _, changed = U().call(vehicle, "setTrunkLocked", false)
    local lockedAfter, checkedAfter = U().call(vehicle, "isTrunkLocked")
    task.unlocked = changed == true and checkedAfter and lockedAfter == false
    task.failure = not task.unlocked and "car_trunk_unlock_failed" or nil
    task.stage = "exit"
    return true, task.unlocked and "field_trunk_exiting" or task.failure
end

function Field.observePlayerVehicle(vehicle)
    if not vehicle then return end
    if SC.TaxiCab and SC.TaxiCab.isOwned and SC.TaxiCab.isOwned(vehicle) then return end
    local id = tonumber(call(vehicle, "getSqlId"))
    if id and id >= 0 and id == math.floor(id) then recentVehicleId = id end
end
function Field.clearArea()
    for _, marker in ipairs(areaMarkers) do call(marker, "remove") end
    areaMarkers, markerExpiry = {}, 0
end
function Field.showArea(center)
    Field.clearArea()
    if type(getWorldMarkers) ~= "function" then return end
    local okay, markers = pcall(getWorldMarkers)
    if not okay or not markers then return end
    local square = U().gridSquare(center.x, center.y, center.z)
    if square then
        local placed, marker = pcall(function()
            return markers:addGridSquareMarker(square, 0.32, 0.85, 0.35,
                true, 1.5)
        end)
        if placed and marker then areaMarkers[#areaMarkers + 1] = marker end
    end
    markerExpiry = U().nowMs() + 5000
end
function Field.leaderPulse(player)
    if markerExpiry > 0 and U().nowMs() >= markerExpiry then Field.clearArea() end
    if active and active.phase == "unlocking"
        and not actorFor(active.unlock.actorId) then
        active.phase, active.blocker = "paused", "unlocker_unavailable"
        return
    end
    if active and (active.phase == "working" or active.phase == "unlocking")
        and distance(point(player), active.center) > leash(active.kind) then
        Field.stop("leader_left_work_area")
        return
    end
    if active and (active.phase == "working" or active.phase == "unlocking") then
        for id in pairs(active.workers) do
            local actor = actorFor(id)
            local state = actor and SC.Commands and SC.Commands.peek
                and SC.Commands.peek(actor) or nil
            if not actor or not state or not state.recruited
                or state.order ~= "follow" then
                Field.stop("squad_changed")
                return
            end
        end
    end
end
function Field.interrupt(actor)
    if Field.unlocking(actor) then
        if call(actor, "getVehicle") == nil and SC.Vehicle
            and SC.Vehicle.cancelTransaction then
            SC.Vehicle.cancelTransaction(actor, "field_survival_preempted")
        end
        return true
    end
    local worker = workerFor(actor)
    if not worker then return false end
    if worker.phase == "working" then
        stopAction(actor)
        worker.phase = "recover"
    elseif worker.phase == "approach" then
        if SC.Navigation and SC.Navigation.cancel then
            SC.Navigation.cancel(actor, "field_survival_preempted")
        end
    end
    return true
end
function Field.recentVehicleId() return recentVehicleId end
function Field.status()
    if not active then return nil end
    local returns, returnBlocker = 0, nil
    for _, pending in pairs(pendingAxeReturns) do
        returns = returns + 1
        returnBlocker = returnBlocker or pending.blocker
    end
    local result = { kind = active.kind, phase = active.phase,
        completed = active.completed, loaded = active.loaded,
        carId = active.carId,
        blocker = returns > 0 and ("borrowed axe return pending"
            .. (returnBlocker and ": " .. returnBlocker or ""))
            or active.blocker or active.note,
        pendingAxeReturns = returns,
        center = active.center, note = active.note }
    return result
end
function Field.available(player, kind)
    return player ~= nil and #followers(player, kind) > 0
end
function Field.start(kind, square, player)
    if active and (active.phase == "working" or active.phase == "unlocking"
        or active.phase == "paused") then
        return false, "field_order_already_active"
    end
    if kind ~= "harvest" and kind ~= "chop" then return false, "unknown_field_order" end
    local center = point(square)
    if not center or not U().gridSquare(center.x, center.y, center.z) then
        return false, "field_center_unloaded"
    end
    if distance(center, point(player)) > leash(kind) then return false, "field_center_too_far" end
    if SC.BaseLife and SC.BaseLife.isInside and SC.BaseLife.isInside(center) then
        return false, "field_center_in_base"
    end
    local roster = followers(player, kind)
    if #roster == 0 then return false, "no_following_companions" end
    local carId = recentVehicleId
    if carId and distance(center, point(vehicleById(carId))) > carRange(kind) then
        carId = nil
    end
    local unlock
    if carId then
        local vehicle, part, cargo, reason = carNear(center, carId, kind)
        if not cargo then
            if reason ~= "car_trunk_locked" then return false, reason end
            if not part then return false, "car_trunk_missing" end
            local lastReason = "car_entry_unavailable"
            for _, id in ipairs(roster) do
                local actor = actorFor(id)
                local seat, why
                if actor then seat, why = unlockSeat(actor, vehicle) end
                if seat ~= nil then
                    unlock = { actorId = id, seat = seat,
                        stage = "boarding", startedAt = U().nowMs() }
                    break
                end
                lastReason = why or lastReason
            end
            if not unlock then return false, lastReason end
        end
    end
    if kind == "chop" and not carId then
        local equipped = false
        for _, id in ipairs(roster) do
            local actor = actorFor(id)
            if actor and axeIn(U().inventory(actor), id) then equipped = true break end
        end
        if not equipped then
            return false, "axe_required_without_car"
        end
    end
    serial = serial + 1
    active = { schema = 1, id = "field:" .. tostring(U().nowMs()) .. ":" .. serial,
        kind = kind, center = center,
        phase = unlock and "unlocking" or "working", carId = carId,
        completed = 0, loaded = 0, done = {}, woodClaims = {},
        workers = {}, blocker = nil, unlock = unlock }
    for _, id in ipairs(roster) do
        active.workers[id] = { phase = "seek", scan = 0 }
        local actor = actorFor(id)
        if actor and SC.Encounter and SC.Encounter.cancelScavenge then
            SC.Encounter.cancelScavenge(actor, "field_order_started")
        end
    end
    Field.showArea(center)
    local speaker = actorFor(roster[1])
    if speaker and type(U().say) == "function" then
        U().say(speaker, kind == "harvest"
            and "I'll harvest the ready crops around this spot."
            or "I'll clear the trees around this spot.")
    end
    return true, unlock and "field_trunk_unlocking" or "field_order_started"
end
function Field.stop(reason)
    if not active then return false, "no_field_order" end
    local order = active
    if order.unlock then
        local unlocker = actorFor(order.unlock.actorId)
        if unlocker and SC.Vehicle then
            if SC.Vehicle.cancelTransaction then
                SC.Vehicle.cancelTransaction(unlocker, "field_order_stopped")
            end
            local vehicle = vehicleById(order.carId)
            if vehicle and call(unlocker, "getVehicle") == vehicle
                and SC.Vehicle.exit then
                SC.Vehicle.exit(unlocker, vehicle, order.unlock.seat,
                    { playerCommand = true })
            end
        end
    end
    for id, worker in pairs(order.workers) do
        local actor = actorFor(id)
        if actor then
            stopAction(actor)
            for _, item in ipairs(carriedItems(actor)) do
                local data = U().modData(item)
                if data and data[MARK] == order.id then
                    data[MARK], data[WORKER_MARK] = nil, nil
                    data[CARRY_MARK] = id
                end
                if data and data[AXE_MARK] == order.id then
                    local axeId = itemId(item)
                    if axeId and order.carId then
                        pendingAxeReturns[id] = {
                            itemId = axeId, orderId = order.id,
                            carId = order.carId, center = order.center,
                            kind = order.kind,
                        }
                    else
                        data[AXE_MARK], data[WORKER_MARK] = nil, nil
                    end
                end
            end
        elseif order.carId and worker.axeId then
            pendingAxeReturns[id] = {
                itemId = worker.axeId, orderId = order.id,
                carId = order.carId, center = order.center,
                kind = order.kind,
            }
        end
    end
    order.phase = "stopped"
    order.blocker = reason or "stopped_by_player"
    Field.clearArea()
    return true, "field_order_stopped"
end
function Field.reserved(item)
    local data = U().modData(item)
    if not data then return false end
    local carryWorker = data[CARRY_MARK]
    if carryWorker ~= nil then
        local carrier, record
        if type(U().resolveActor) == "function" then
            carrier, record = U().resolveActor(tostring(carryWorker))
        else carrier = actorFor(tostring(carryWorker)) end
        local dead = carrier and call(carrier, "isDead") == true
            or record and type(record.runtime) == "table"
                and record.runtime.unrecoverable == true
        if dead then carrier = nil record = nil end
        if carrier and carries(carrier, item) then
            missingCarriers[tostring(carryWorker)] = nil
            return true
        end
        -- A dormant registry record is an authoritative temporary owner.
        if record and not carrier then return true end
        -- During restore the registry may appear empty briefly. Give it one
        -- bounded grace period; an absent or retired owner cannot reserve the
        -- same item forever once that period expires.
        if not carrier and not dead and SC.Persistence
            and type(SC.Persistence.isPending) == "function"
            and SC.Persistence.isPending(tostring(carryWorker)) == true then
            return true
        end
        if not carrier and not dead then
            local id = tostring(carryWorker)
            missingCarriers[id] = missingCarriers[id] or U().nowMs()
            if U().nowMs() - missingCarriers[id] < 30000 then return true end
        end
        data[CARRY_MARK] = nil
    end
    local orderId = data[MARK] or data[AXE_MARK]
    if orderId == nil then return false end
    local ownerId = data[WORKER_MARK]
    if data[AXE_MARK] ~= nil and ownerId ~= nil then
        local pending = pendingAxeReturns[tostring(ownerId)]
        if pending and pending.orderId == orderId and pending.itemId == itemId(item) then
            local carrier, record
            if type(U().resolveActor) == "function" then
                carrier, record = U().resolveActor(tostring(ownerId))
            else carrier = actorFor(tostring(ownerId)) end
            local dead = carrier and call(carrier, "isDead") == true
                or record and type(record.runtime) == "table"
                    and record.runtime.unrecoverable == true
            if dead then carrier = nil end
            if carrier and carries(carrier, item) then
                missingCarriers[tostring(ownerId)] = nil
                return true
            end
            if not carrier and not dead and SC.Persistence
                and type(SC.Persistence.isPending) == "function"
                and SC.Persistence.isPending(tostring(ownerId)) == true then
                return true
            end
            if not carrier and not dead then
                missingCarriers[tostring(ownerId)] = missingCarriers[tostring(ownerId)]
                    or U().nowMs()
                if U().nowMs() - missingCarriers[tostring(ownerId)] < 30000 then
                    return true
                end
            end
            pendingAxeReturns[tostring(ownerId)] = nil
        end
    end
    local owned = active and active.id == orderId
        and (active.phase == "working" or active.phase == "paused")
        and (ownerId == nil or active.workers[ownerId] ~= nil)
    if not owned then
        data[MARK], data[AXE_MARK], data[WORKER_MARK] = nil, nil, nil
    end
    return owned == true
end
function Field.resume()
    if not active or active.phase ~= "paused" then return false, "field_not_paused" end
    if active.carId and not active.unlock then
        local _, _, container, reason = carNear(active.center, active.carId, active.kind)
        if not container then return false, reason end
    end
    if active.unlock then
        local task = active.unlock
        local actor = actorFor(task.actorId)
        if not actor then return false, "unlocker_unavailable" end
        if call(actor, "getVehicle") == nil and not task.unlocked then
            task.stage, task.failure, task.readyAt = "boarding", nil, nil
        end
        task.startedAt = U().nowMs()
    end
    active.phase, active.blocker = active.unlock and "unlocking" or "working", nil
    if active.cargoNotice then active.note, active.cargoNotice = nil, nil end
    return true, "field_order_resumed"
end
local function pendingAxe(actor, pending)
    for _, item in ipairs(carriedItems(actor)) do
        local data = U().modData(item)
        if itemId(item) == pending.itemId and data
            and data[AXE_MARK] == pending.orderId then return item end
    end
    return nil
end

local function pendingReturnAccess(actor, player, pending, axe)
    local vehicle = vehicleById(pending.carId)
    local part, container, reason = trunk(vehicle)
    if not container then return nil, nil, nil, reason end
    if distance(point(actor), point(vehicle)) > CHOP_LEASH
        or distance(point(player), point(vehicle)) > CHOP_LEASH then
        return nil, nil, nil, "car_out_of_follow_range"
    end
    local room, roomReason = cargoRoom(container, actor, axe)
    if not room then
        return nil, nil, nil, roomReason == "destination_full" and "car_trunk_full"
            or roomReason
    end
    return vehicle, part, container
end

function Field.wants(actor, player, commands)
    local worker = workerFor(actor)
    local id = tostring(U().idOf(actor) or "")
    local pending = pendingAxeReturns[id]
    if pending then
        local axe = pendingAxe(actor, pending)
        if not axe then pendingAxeReturns[id] = nil
        else
            -- The saved centre belongs to the old order. Resolve the original
            -- vehicle at its current location, without substituting another.
            local vehicle, _, _, reason = pendingReturnAccess(
                actor, player, pending, axe)
            pending.blocker = reason
            if vehicle then return commands and commands.recruited
                and player ~= nil end
            if not worker then return false end
        end
    end
    if active and active.phase == "unlocking" then
        return Field.unlocking(actor) and commands and commands.recruited
            and commands.order == "follow" and player ~= nil
    end
    return worker ~= nil and commands and commands.recruited
        and commands.order == "follow" and player ~= nil
end

function Field.update(actor, player, snapshot)
    if Field.unlocking(actor) then
        if distance(point(player), active.center) > leash(active.kind) then
            Field.stop("leader_left_work_area")
            return false, "leader_left_work_area"
        end
        return unlockStep(actor, active, snapshot)
    end
    local returnId = tostring(U().idOf(actor) or "")
    local pending = pendingAxeReturns[returnId]
    if pending then
        local axe = pendingAxe(actor, pending)
        if not axe then pendingAxeReturns[returnId] = nil
            return true, "field_borrowed_axe_missing" end
        local vehicle, part, container, reason = pendingReturnAccess(
            actor, player, pending, axe)
        pending.blocker = reason
        if vehicle then
            local okay, approached = atCar(actor, vehicle, part)
            if not okay then
                pending.blocker = approached
                if not workerFor(actor) then return false, approached end
            elseif approached ~= "arrived" then
                return true, "field_axe_return_approaching"
            else
                local source = call(axe, "getContainer") or U().inventory(actor)
                local moved, moveReason = U().transferItemVerified(source, container, axe)
                if not moved then
                    pending.blocker = moveReason
                    if not workerFor(actor) then return false, moveReason end
                elseif not U().inventoryContains(container, axe) then
                    -- Keep the obligation and say why, but do not hold a
                    -- worker's current order hostage to a retry.
                    pending.blocker = "field_axe_return_unverified"
                    if not workerFor(actor) then return false, pending.blocker end
                else
                    local data = U().modData(axe)
                    if data then data[AXE_MARK], data[WORKER_MARK] = nil, nil end
                    pendingAxeReturns[returnId] = nil
                    return true, "field_axe_returned"
                end
            end
        elseif not workerFor(actor) then
            return false, reason
        end
    end
    local worker, actorId = workerFor(actor)
    if not worker then return false, "field_order_inactive" end
    if distance(point(player), active.center) > leash(active.kind) then
        Field.stop("leader_left_work_area")
        return false, "leader_left_work_area"
    end
    local order = active
    local inventory = U().inventory(actor)
    if not inventory then return false, "inventory_unavailable" end
    local _, _, load = U().carryLoad(actor)
    local full = fullLoad(actor, worker, order)
    local cargo, cargoReason = cargoItems(actor, order.id)
    if not cargo then
        order.phase, order.blocker = "paused", cargoReason
        return false, cargoReason
    end
    if worker.phase == "full" then
        if order.kind == "chop" then
            if order.carId and #cargo > 0 then
                worker.afterDeposit = "seek"
                return loadCar(actor, worker, order)
            end
            return leaveWood(actor, worker, order, "inventory_full", true)
        end
        if order.carId and #cargo > 0 and not worker.skipDeposit then
            worker.phase, worker.afterDeposit = "deposit", "seek"
            return loadCar(actor, worker, order)
        end
        if load < full then
            worker.phase, worker.afterDeposit = worker.afterDeposit or "seek", nil
            worker.capacityReason = nil
            return true, "field_carry_space_restored"
        end
        capacityNotice(actor, order, worker.capacityReason or "inventory_full", true)
        worker.capacityReason = nil
        completeIfFinished(order)
        return true, "field_carry_limit_reached"
    end
    if #cargo > 0 and not worker.skipPickup and not worker.skipDeposit
        and (load >= full or worker.phase == "deposit") then
        if order.carId then
            if worker.phase == "wood" then worker.afterDeposit = "wood" end
            return loadCar(actor, worker, order)
        end
        if load >= full then
            if order.kind == "chop" then
                return leaveWood(actor, worker, order, "inventory_full", true)
            end
            worker.phase = "full"
            return true, "field_carry_limit_reached"
        end
    end
    if worker.phase == "waiting_axe" then
        if axeIn(inventory, actorId) then
            worker.phase = "seek"
        else
            local _, _, container, reason = carNear(order.center, order.carId, order.kind)
            if not container then order.phase, order.blocker = "paused", reason
                return false, reason end
            if axeIn(container) then
                worker.phase = "borrow"
            else
                for id in pairs(order.workers) do
                    local member = actorFor(id)
                    if member and id ~= actorId
                        and axeIn(U().inventory(member)) then
                        local cutter = order.workers[id]
                        if cutter.phase == "done" then
                            -- A finished cutter may keep a borrowed axe until
                            -- trunk space opens. Waiting for that return would
                            -- keep the whole order, and its return receipt,
                            -- from ever completing. Its scan already covered
                            -- this area; only a claim held by this worker can
                            -- still need handing back to the cutter.
                            local retry = worker.target
                                and not order.done[worker.target]
                                and targetAt(order, worker.x, worker.y)
                            release(worker)
                            worker.phase = "done"
                            if retry then
                                cutter.phase, cutter.scan = "seek", 0
                            end
                            completeIfFinished(order)
                            return true, "field_shared_axe_finished"
                        end
                        return true, "field_waiting_for_shared_axe"
                    end
                end
                order.phase, order.blocker = "paused", "axe_not_in_car"
                return false, order.blocker
            end
        end
    end
    if worker.phase == "borrow" then
        if pendingAxeReturns[actorId] then
            -- One worker has one saved exact-return slot. Do not replace its
            -- older obligation with a second borrowed axe.
            worker.phase = "done"
            completeIfFinished(order)
            return true, "field_borrowed_axe_return_pending"
        end
        local vehicle, part, container, reason = carNear(order.center, order.carId, order.kind)
        if not container then order.phase, order.blocker = "paused", reason return false, reason end
        local okay, approached = atCar(actor, vehicle, part)
        if not okay then order.phase, order.blocker = "paused", approached return false, approached end
        if approached ~= "arrived" then return true, "field_axe_approaching" end
        local axe = axeIn(container)
        if not axe then
            worker.phase = "waiting_axe"
            return true, "field_waiting_for_shared_axe"
        end
        local room, roomReason = cargoRoom(inventory, actor, axe)
        if not room then
            return pauseCargo(actor, order,
                roomReason == "destination_full" and "inventory_full" or roomReason)
        end
        local moved, moveReason = U().transferItemVerified(container, inventory, axe)
        if not moved or not markAxe(axe, order.id, actorId) then
            order.phase, order.blocker = "paused", moveReason or "axe_marker_failed"
            return false, order.blocker
        end
        worker.axeId, worker.phase = itemId(axe), "seek"
        return true, "field_axe_borrowed"
    end
    if order.kind == "chop" and (worker.phase == "seek"
        or worker.phase == "approach" or worker.phase == "start")
        and not axeIn(inventory, actorId) then
        if order.carId then worker.phase = "borrow" return true, "field_axe_needed" end
        worker.phase = "done"
        order.blocker = "axe_required_without_car"
        return true, order.blocker
    end
    if worker.phase == "seek" then
        local square = nextTarget(order, worker)
        if square then return true, "field_target_claimed" end
        if worker.scan < (radius(order.kind) * 2 + 1) ^ 2 then
            return true, "field_scanning" end
        worker.phase = "done"
    end
    if worker.phase == "done" then
        if #cargo > 0 and order.carId
            and not worker.skipPickup and not worker.skipDeposit then
            worker.phase, worker.afterDeposit = "deposit", "done"
            return loadCar(actor, worker, order)
        end
        if worker.axeId and order.carId and not worker.skipPickup then
            worker.phase = "return_axe"
            return true, "field_returning_axe"
        end
        completeIfFinished(order)
        return true, "field_worker_done"
    end
    if worker.phase == "deposit" then return loadCar(actor, worker, order) end
    if worker.phase == "return_axe" then
        local vehicle, part, container, reason = carNear(order.center, order.carId, order.kind)
        if not container then order.phase, order.blocker = "paused", reason return false, reason end
        local okay, approached = atCar(actor, vehicle, part)
        if not okay then order.phase, order.blocker = "paused", approached return false, approached end
        if approached ~= "arrived" then return true, "field_axe_return_approaching" end
        local axe
        for _, item in ipairs(U().inventoryItems(inventory, 4096)) do
            if itemId(item) == worker.axeId then axe = item break end
        end
        if not axe then worker.axeId, worker.phase = nil, "done"
            return true, "field_axe_not_carried" end
        local room, roomReason = cargoRoom(container, actor, axe)
        if not room then
            if roomReason ~= "destination_full" then
                return pauseCargo(actor, order, roomReason)
            end
            if order.kind == "chop" then
                return leaveWood(actor, worker, order, "car_trunk_full", true)
            end
            order.phase, order.blocker = "paused", "car_trunk_full"
            return false, order.blocker
        end
        local moved, moveReason = U().transferItemVerified(inventory, container, axe)
        if not moved then order.phase, order.blocker = "paused", moveReason
            return false, moveReason end
        local data = U().modData(axe)
        if data then data[AXE_MARK], data[WORKER_MARK] = nil, nil end
        worker.axeId, worker.phase = nil, "done"
        return true, "field_axe_returned"
    end
    local square = currentTarget(worker, order)
    if not square then release(worker) return false, "field_target_unloaded" end
    if worker.phase == "recover" then
        local remains = targetAt(order, worker.x, worker.y) ~= nil
        if remains then worker.phase = "start"
        else
            if order.kind == "harvest" then
                local adopted, reason = adoptHarvest(actor, worker, order)
                if not adopted then order.phase, order.blocker = "paused", reason
                    return false, reason end
                release(worker)
            else worker.phase = "wood" end
            return true, "field_recovered"
        end
    end
    if worker.phase == "approach" then
        if not targetAt(order, worker.x, worker.y) then
            order.done[worker.target] = true
            release(worker)
            return true, "field_target_gone"
        end
        local okay, reason = approach(actor, square,
            order.kind == "harvest" and "field_crop" or "field_tree", false)
        if not okay then
            worker.failures = (worker.failures or 0) + 1
            if worker.failures >= 3 then
                order.done[worker.target] = true
                release(worker)
            end
            return false, reason or "field_approach_failed"
        end
        if reason ~= "arrived" then return true, reason end
        worker.phase = "start"
    end
    if worker.phase == "start" then
        local object
        if order.kind == "harvest" then object = crop(square) else object = tree(square) end
        if not object then order.done[worker.target] = true release(worker)
            return true, "field_target_gone" end
        worker.before = inventoryIds(actor)
        if not worker.before then
            order.phase, order.blocker = "paused", "inventory_scan_limit"
            return false, order.blocker
        end
        if order.kind == "chop" then worker.groundBefore = worldIds(square) end
        if order.kind == "harvest" then
            local props = type(farming_vegetableconf) == "table"
                and type(farming_vegetableconf.props) == "table"
                and farming_vegetableconf.props[object.typeOfSeed] or nil
            worker.harvestTypes = {}
            local function allow(itemType)
                if type(itemType) == "string" and itemType ~= "" then
                    worker.harvestTypes[#worker.harvestTypes + 1] = itemType
                end
            end
            if props then
                allow(props.vegetableName)
                allow(props.produceExtra)
                if object.hasSeed then allow(props.seedName) end
            end
            worker.yieldEstimate = propsYieldWeight(props, object, actor)
            if load >= fullLoad(actor, worker, order)
                and not (#cargo == 0 and firstTargetFits(actor, worker, order)) then
                -- An empty-handed worker takes one plant past its Strength
                -- limit, but never one whose yield would not physically fit
                -- the inventory; say so instead of overloading.
                local canDeposit = order.carId and #cargo > 0
                    and not worker.skipDeposit
                if canDeposit then
                    -- The target was claimed during the scan. Retry that
                    -- exact crop after unloading rather than skipping it.
                    worker.scan = math.max(0, worker.scan - 1)
                else worker.capacityReason = "yield_too_heavy" end
                release(worker)
                if #cargo == 0 then
                    order.blocker = "field_carry_limit_reached"
                end
                worker.phase = canDeposit and "deposit" or "full"
                return true, "field_carry_limit_reached"
            end
        end
        if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor, "field_action") end
        if SC.NativeActions and SC.NativeActions.stopDirect then
            local stopped = SC.NativeActions.stopDirect(actor)
            if stopped ~= true then return false, "field_posture_busy" end
        end
        local okay, reason
        if order.kind == "harvest" then
            okay, reason = SC.NativeActions.startFarm(actor,
                { operation = "harvest", plant = object, square = square })
        else
            okay, reason = U().move(actor, "walk", {
                action = "chop_tree", tree = object, tool = axeIn(inventory, actorId),
                targetSquare = square,
            })
        end
        if not okay then return false, reason or "field_action_rejected" end
        if SC.NativeActions.isWorkActive(actor) ~= true then
            worker.failures = (worker.failures or 0) + 1
            if worker.failures >= 3 then
                order.phase, order.blocker = "paused", "field_action_not_started"
            end
            return false, "field_action_not_started"
        end
        worker.phase, worker.startedAt = "working", U().nowMs()
        if order.kind == "chop" then
            worker.lastHealth = tonumber(call(object, "getHealth"))
            worker.lastProgressAt = worker.startedAt
            worker.lastEmulatedAt = nil
            worker.nativeHit = false
        end
        return true, "field_action_started"
    end
    if worker.phase == "working" then
        if SC.NativeActions.isWorkActive(actor) == true then
            if order.kind == "chop" then
                local object = tree(square)
                local health = object and tonumber(call(object, "getHealth"))
                if health and worker.lastHealth and health < worker.lastHealth then
                    worker.nativeHit = true
                    worker.lastProgressAt = U().nowMs()
                end
                worker.lastHealth = health or worker.lastHealth
                if object and not worker.nativeHit
                    and U().nowMs() - (worker.lastProgressAt or 0) >= 6000
                    and U().nowMs() - (worker.lastEmulatedAt or 0) >= 1500
                    and SC.NativeActions.emulateWorkEvent then
                    worker.lastEmulatedAt = U().nowMs()
                    SC.NativeActions.emulateWorkEvent(actor, "chop_tree", "ChopTree")
                    local after = tonumber(call(object, "getHealth"))
                    if after and health and after < health then
                        worker.lastProgressAt, worker.lastHealth = U().nowMs(), after
                    end
                end
            end
            if U().nowMs() - (worker.startedAt or 0) < 180000 then
                return true, "field_action_active"
            end
            SC.NativeActions.cancelWork(actor, "field_action_timeout")
            return false, "field_action_timeout"
        end
        local finished, finishReason = SC.NativeActions.finishWork(actor)
        if finished ~= true then return false, finishReason or "field_action_finish_failed" end
        local completed = order.kind == "harvest" and crop(square) == nil
            or order.kind == "chop" and tree(square) == nil
        if not completed then worker.phase = "start" return true, "field_action_continues" end
        if order.kind == "harvest" then
            local adopted, adoptReason = adoptHarvest(actor, worker, order)
            if not adopted then order.phase, order.blocker = "paused", adoptReason
                return false, adoptReason end
        end
        order.completed = order.completed + 1
        order.done[worker.target] = true
        worker.phase = order.kind == "chop" and "wood" or "seek"
        if worker.phase == "seek" then release(worker) end
        return true, "field_target_completed"
    end
    if worker.phase == "wood" then
        if worker.skipPickup then
            release(worker)
            return true, "field_wood_left_on_ground"
        end
        local wood = woodOn(square, order, actorId, worker.groundBefore)
        if #wood == 0 then release(worker) return true, "field_wood_collected" end
        local entry = wood[1]
        order.woodClaims[entry.id] = actorId
        local currentWeight, capacity = U().carryLoad(actor)
        local itemWeight = U().itemWeight(entry.item)
        -- With a car, a worker holding none of this order's logs takes one
        -- past its Strength limit when the inventory can hold it, and the
        -- deposit check walks it to the trunk. A 9-unit log beside a 3-unit
        -- axe is over 80% of an average companion's limit of 12, so without
        -- this no log ever reached the car (0.26.58).
        local oneTrip = order.carId ~= nil and #cargo == 0
        if not oneTrip and capacity and capacity > 0 and currentWeight and itemWeight
            and currentWeight + itemWeight > capacity * FULL_LOAD then
            order.woodClaims[entry.id] = nil
            if order.carId and #cargo > 0 then
                worker.afterDeposit = "wood"
                return loadCar(actor, worker, order)
            end
            return leaveWood(actor, worker, order, "inventory_full", true)
        end
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(inventory, actor, entry.item) ~= true then
            order.woodClaims[entry.id] = nil
            if order.carId and #cargo > 0 then
                worker.afterDeposit = "wood"
                return loadCar(actor, worker, order)
            end
            return leaveWood(actor, worker, order, "inventory_full", true)
        end
        local okay, reason = approach(actor, entry.square, "field_wood", true)
        if not okay then return false, reason end
        if reason ~= "arrived" then return true, reason end
        if not mark(entry.item, order.id, actorId) then
            return false, "wood_marker_failed" end
        local taken, takeReason = U().takeWorldItemVerified(entry.wrapper, inventory, entry.item)
        if not taken then return false, takeReason end
        order.woodClaims[entry.id] = nil
        return true, "field_wood_taken"
    end
    return false, "field_phase_unknown"
end

function Field.export()
    return { schema = 1, recentVehicleId = recentVehicleId, serial = serial,
        active = active, pendingAxeReturns = pendingAxeReturns }
end
-- One saved axe return per worker. Like a malformed order, a malformed entry
-- rejects the save so persistence quarantines it unchanged instead of the
-- runtime indexing bad data later.
local function validAxeReturns(value)
    if value == nil then return true end
    if type(value) ~= "table" then return false end
    local count = 0
    for workerId, pending in pairs(value) do
        count = count + 1
        if count > 16 or type(workerId) ~= "string" or workerId == ""
            or type(pending) ~= "table"
            or (type(pending.itemId) ~= "string" and type(pending.itemId) ~= "number")
            or type(pending.orderId) ~= "string"
            or type(pending.carId) ~= "number" or pending.carId < 0
            or (pending.kind ~= "harvest" and pending.kind ~= "chop")
            or type(pending.center) ~= "table"
            or type(pending.center.x) ~= "number"
            or type(pending.center.y) ~= "number"
            or type(pending.center.z) ~= "number"
            or (pending.blocker ~= nil and type(pending.blocker) ~= "string") then
            return false
        end
    end
    return true
end
function Field.restore(saved)
    if saved == nil then
        active, recentVehicleId, serial, pendingAxeReturns = nil, nil, 0, {}
        missingCarriers = {}
        return true
    end
    if type(saved) ~= "table" or saved.schema ~= 1
        or (saved.recentVehicleId ~= nil and (type(saved.recentVehicleId) ~= "number"
            or saved.recentVehicleId < 0))
        or type(saved.serial) ~= "number" or saved.serial < 0 then
        return false, "invalid_field_work_save"
    end
    local order = saved.active
    if order ~= nil and (type(order) ~= "table" or order.schema ~= 1
        or (order.kind ~= "harvest" and order.kind ~= "chop")
        or type(order.center) ~= "table" or type(order.center.x) ~= "number"
        or type(order.center.y) ~= "number" or type(order.center.z) ~= "number"
        or type(order.workers) ~= "table" or type(order.done) ~= "table"
        or type(order.woodClaims) ~= "table"
        or type(order.completed) ~= "number" or type(order.loaded) ~= "number"
        or (order.phase == "unlocking" and order.unlock == nil)
        or (order.unlock ~= nil and (type(order.unlock) ~= "table"
            or type(order.unlock.actorId) ~= "string"
            or type(order.unlock.startedAt) ~= "number"
            or type(order.unlock.seat) ~= "number"
            or (order.unlock.stage ~= "boarding" and order.unlock.stage ~= "unlock"
                and order.unlock.stage ~= "exit")))) then
        return false, "invalid_field_order_save"
    end
    if not validAxeReturns(saved.pendingAxeReturns) then
        return false, "invalid_field_axe_return_save"
    end
    -- Persistence passes a disposable copy, so the tables are owned here.
    active, recentVehicleId, serial = order, saved.recentVehicleId, saved.serial
    pendingAxeReturns = saved.pendingAxeReturns or {}
    if active and active.phase == "working" then
        for _, worker in pairs(active.workers) do
            if worker.phase == "working" then worker.phase = "recover" end
        end
    end
    return true
end

return Field
