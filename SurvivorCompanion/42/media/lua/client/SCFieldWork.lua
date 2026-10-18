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
local CHOP_RADIUS, CHOP_LEASH, CHOP_CAR_RANGE = 8, 16, 20
local TREE_LIMIT, MARK = 5, "LF_FieldOrder"
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
    local part = call(vehicle, "getTrunkPart") or call(vehicle, "getPartById", "TruckBed")
    local container = part and call(part, "getItemContainer")
    if not container then return nil, nil, "car_trunk_missing" end
    if call(vehicle, "isTrunkLocked") == true then
        return part, nil, "car_trunk_locked"
    end
    return part, container
end
local function carNear(center, id, kind)
    local vehicle = vehicleById(id)
    if not vehicle or distance(center, point(vehicle)) > carRange(kind) then
        return nil, nil, nil, "car_out_of_range"
    end
    local part, container, reason = trunk(vehicle)
    return vehicle, part, container, reason
end
local function followers(player)
    local result = {}
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        local state = SC.Commands and SC.Commands.peek and SC.Commands.peek(actor)
        local id = U().idOf(actor)
        if id and state and state.recruited and state.order == "follow"
            and call(actor, "getVehicle") == nil
            and distance(point(actor), point(player)) <= CHOP_LEASH then
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
local function carriedItems(actor)
    local inventory = U().inventory(actor)
    if type(U().inventoryItemsDeep) == "function" then
        return U().inventoryItemsDeep(inventory, 4096)
    end
    return U().inventoryItems(inventory, 4096)
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
local function claimed(order, targetKey)
    if order.done[targetKey] then return true end
    for _, worker in pairs(order.workers) do
        if worker.target == targetKey then return true end
    end
    return false
end
local function treeQuotaFull(order)
    local reserved = order.completed
    for _, worker in pairs(order.workers) do
        if worker.target and not order.done[worker.target] then reserved = reserved + 1 end
    end
    return reserved >= TREE_LIMIT
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
    local items = U().inventoryItems(U().inventory(actor), 257)
    if #items > 256 then return nil end
    for _, item in ipairs(items) do
        local id = itemId(item)
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
    for _, item in ipairs(U().inventoryItems(inventory, 4096)) do
        local id = itemId(item)
        if id and worker.before[id] ~= true and marker(item) == nil
            and allowed[U().itemType(item)] == true then
            if not mark(item, order.id, tostring(U().idOf(actor))) then
                return false, "cargo_marker_failed" end
        end
    end
    return true
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
local function axeIn(container)
    for _, item in ipairs(U().inventoryItems(container, 4096)) do
        if U().itemHasTag(item, "CHOP_TREE") and call(item, "isBroken") ~= true then
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
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do
        if marker(item) == orderId then result[#result + 1] = item end
    end
    return result
end
local function loadCar(actor, worker, order)
    local vehicle, part, container, reason = carNear(order.center, order.carId, order.kind)
    if not container then order.phase, order.blocker = "paused", reason return false, reason end
    local okay, approachReason = atCar(actor, vehicle, part)
    if not okay then order.phase, order.blocker = "paused", approachReason return false, approachReason end
    if approachReason ~= "arrived" then return true, "field_cargo_approaching" end
    local cargo = cargoItems(actor, order.id)
    if #cargo == 0 then
        worker.phase = worker.afterDeposit or "seek"
        worker.afterDeposit = nil
        return true, "field_cargo_loaded"
    end
    -- Keep transfers bounded per decision beat, but unload a useful batch
    -- instead of making a separate trip through the decision loop per crop.
    for index = 1, math.min(#cargo, 8) do
        local item = cargo[index]
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(container, actor, item) ~= true then
            order.phase, order.blocker = "paused", "car_trunk_full"
            return false, order.blocker
        end
        local moved, moveReason = U().transferItemVerified(U().inventory(actor), container, item)
        if not moved then order.phase, order.blocker = "paused", moveReason
            return false, moveReason end
        local data = U().modData(item)
        if data then data[MARK], data[WORKER_MARK] = nil, nil end
        order.loaded = order.loaded + 1
    end
    return true, "field_cargo_loaded"
end
local function release(worker)
    worker.target, worker.x, worker.y, worker.before = nil, nil, nil, nil
    worker.groundBefore, worker.startedAt, worker.phase = nil, nil, "seek"
end
local function completeIfFinished(order)
    for _, state in pairs(order.workers) do
        if state.phase ~= "done" and state.phase ~= "full" then return false end
    end
    order.phase = "complete"
    if not order.carId then
        for id in pairs(order.workers) do
            local member = actorFor(id)
            if member then
                for _, item in ipairs(U().inventoryItems(U().inventory(member), 4096)) do
                    local data = U().modData(item)
                    if data and data[MARK] == order.id then
                        -- No car was selected. Keep the harvest in this
                        -- worker's inventory for manual pickup instead of
                        -- letting generic overload handling drop it outside.
                        data[MARK], data[WORKER_MARK] = nil, nil
                        data[CARRY_MARK] = id
                    end
                end
            end
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
        targetCount = active.kind == "chop" and TREE_LIMIT or nil,
        carId = active.carId,
        blocker = returns > 0 and ("borrowed axe return pending"
            .. (returnBlocker and ": " .. returnBlocker or "")) or active.blocker,
        pendingAxeReturns = returns,
        center = active.center, note = active.note }
    return result
end
function Field.available(player)
    return player ~= nil and #followers(player) > 0
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
    local roster = followers(player)
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
                local seat, why = actor and unlockSeat(actor, vehicle)
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
            if actor and axeIn(U().inventory(actor)) then equipped = true break end
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
    return true, "field_order_resumed"
end
function Field.wants(actor, player, commands)
    local worker = workerFor(actor)
    local id = tostring(U().idOf(actor) or "")
    local pending = pendingAxeReturns[id]
    if pending and not worker then
        local vehicle, _, container, reason = carNear(pending.center,
            pending.carId, pending.kind)
        if not container then pending.blocker = reason return false end
        if distance(point(actor), point(vehicle)) > CHOP_LEASH
            or distance(point(player), point(vehicle)) > CHOP_LEASH then
            pending.blocker = "car_out_of_follow_range"
            return false
        end
        local axe
        for _, item in ipairs(carriedItems(actor)) do
            if itemId(item) == pending.itemId then axe = item break end
        end
        if not axe then pendingAxeReturns[id] = nil return false end
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(container, actor, axe) ~= true then
            pending.blocker = "car_trunk_full"
            return false
        end
        pending.blocker = nil
        return commands and commands.recruited and player ~= nil
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
        local inventory = U().inventory(actor)
        local axe
        for _, item in ipairs(carriedItems(actor)) do
            local data = U().modData(item)
            if itemId(item) == pending.itemId
                and data and data[AXE_MARK] == pending.orderId then
                axe = item
                break
            end
        end
        if not axe then pendingAxeReturns[returnId] = nil
            return true, "field_borrowed_axe_missing" end
        local vehicle, part, container, reason = carNear(pending.center,
            pending.carId, pending.kind)
        if not container then pending.blocker = reason return false, reason end
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(container, actor, axe) ~= true then
            pending.blocker = "car_trunk_full"
            return false, pending.blocker
        end
        local okay, approached = atCar(actor, vehicle, part)
        if not okay then pending.blocker = approached return false, approached end
        if approached ~= "arrived" then return true, "field_axe_return_approaching" end
        local source = call(axe, "getContainer") or inventory
        local moved, moveReason = U().transferItemVerified(source, container, axe)
        if not moved then pending.blocker = moveReason return false, moveReason end
        local data = U().modData(axe)
        if data then data[AXE_MARK], data[WORKER_MARK] = nil, nil end
        pendingAxeReturns[returnId] = nil
        return true, "field_axe_returned"
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
    local _, _, load = U().inventoryLoad(actor)
    if worker.phase == "full" then
        if load < 0.8 then
            worker.phase, worker.afterDeposit = worker.afterDeposit or "seek", nil
            return true, "field_carry_space_restored"
        end
        completeIfFinished(order)
        return true, "field_carry_limit_reached"
    end
    if #cargoItems(actor, order.id) > 0 and (load >= 0.8 or worker.phase == "deposit") then
        if order.carId then
            if worker.phase == "wood" then worker.afterDeposit = "wood" end
            return loadCar(actor, worker, order)
        end
        if load >= 0.8 then
            worker.phase = "full"
            return true, "field_carry_limit_reached"
        end
    end
    if worker.phase == "waiting_axe" then
        if axeIn(inventory) then
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
                        return true, "field_waiting_for_shared_axe"
                    end
                end
                order.phase, order.blocker = "paused", "axe_not_in_car"
                return false, order.blocker
            end
        end
    end
    if worker.phase == "borrow" then
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
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(inventory, actor, axe) ~= true then
            order.phase, order.blocker = "paused", "inventory_full"
            return false, order.blocker
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
        and not axeIn(inventory) then
        if order.carId then worker.phase = "borrow" return true, "field_axe_needed" end
        worker.phase = "done"
        order.blocker = "axe_required_without_car"
        return true, order.blocker
    end
    if worker.phase == "seek" then
        if order.kind == "chop" and treeQuotaFull(order) then
            worker.phase = "done"
        else
            local square = nextTarget(order, worker)
            if square then return true, "field_target_claimed" end
            if worker.scan < (radius(order.kind) * 2 + 1) ^ 2 then
                return true, "field_scanning" end
            worker.phase = "done"
        end
    end
    if worker.phase == "done" then
        if #cargoItems(actor, order.id) > 0 and order.carId then
            worker.phase = "deposit"
            return loadCar(actor, worker, order)
        end
        if worker.axeId and order.carId then
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
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(container, actor, axe) ~= true then
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
                action = "chop_tree", tree = object, tool = axeIn(inventory),
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
        local wood = woodOn(square, order, actorId, worker.groundBefore)
        if #wood == 0 then release(worker) return true, "field_wood_collected" end
        local entry = wood[1]
        order.woodClaims[entry.id] = actorId
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(inventory, actor, entry.item) ~= true then
            worker.phase = order.carId and "deposit" or "full"
            worker.afterDeposit = "wood"
            return true, "field_carry_limit_reached"
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
    active, recentVehicleId, serial = order, saved.recentVehicleId, saved.serial
    pendingAxeReturns = type(saved.pendingAxeReturns) == "table"
        and saved.pendingAxeReturns or {}
    if active and active.phase == "working" then
        for _, worker in pairs(active.workers) do
            if worker.phase == "working" then worker.phase = "recover" end
        end
    end
    return true
end

return Field
