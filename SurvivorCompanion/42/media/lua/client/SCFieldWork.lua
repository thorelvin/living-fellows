-- SPDX-License-Identifier: MIT
-- One-shot work around the leader. Native farming/chopping creates the output;
-- this coordinator only chooses targets and moves exact items to the car.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.FieldWork = SC.FieldWork or {}
local Field = SC.FieldWork

local active, recentVehicleId, serial = nil, nil, 0
local areaMarkers, markerExpiry = {}, 0
local RADIUS, LEASH, CAR_RANGE, TREE_LIMIT, MARK = 8, 16, 20, 5, "LF_FieldOrder"
local AXE_MARK = "LF_FieldBorrowedAxe"
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
local function mark(item, orderId)
    local data = U().modData(item)
    if not data or not itemId(item) then return false end
    data[MARK] = orderId
    return data[MARK] == orderId
end
local function markAxe(item, orderId)
    local data = U().modData(item)
    if not data or not itemId(item) then return false end
    data[AXE_MARK] = orderId
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
    if call(vehicle, "isTrunkLocked") == true then return nil, nil, "car_trunk_locked" end
    local part = call(vehicle, "getTrunkPart") or call(vehicle, "getPartById", "TruckBed")
    local container = part and call(part, "getItemContainer")
    if not container then return nil, nil, "car_trunk_missing" end
    return part, container
end
local function carNear(center, id)
    local vehicle = vehicleById(id)
    if not vehicle or distance(center, point(vehicle)) > CAR_RANGE then
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
            and distance(point(actor), point(player)) <= LEASH then
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
    if dx * dx + dy * dy > RADIUS * RADIUS then return nil end
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
    local width = RADIUS * 2 + 1
    local inspected = 0
    while inspected < 16 and worker.scan < width * width do
        local index = worker.scan
        worker.scan = worker.scan + 1
        inspected = inspected + 1
        local x = order.center.x - RADIUS + index % width
        local y = order.center.y - RADIUS + math.floor(index / width)
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
    for _, item in ipairs(U().inventoryItems(inventory, 4096)) do
        local id = itemId(item)
        if id and worker.before[id] ~= true and marker(item) == nil then
            if not mark(item, order.id) then return false, "cargo_marker_failed" end
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
    local center = point(centre) or point(vehicle)
    local squares = {}
    if not center then return squares end
    center.z = (point(vehicle) or center).z
    for dx = -2, 2 do for dy = -2, 2 do
        local square = U().gridSquare(center.x + dx, center.y + dy, center.z)
        if square and U().isSquareFree(square)
            and not U().safehouseBlocker(square, actor) then
            squares[#squares + 1] = square
        end
    end end
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
    return true, reason == "arrived" and reached and U().sameSquare(actor, reached)
        and "arrived" or "approaching"
end
local function cargoItems(actor, orderId)
    local result = {}
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do
        if marker(item) == orderId then result[#result + 1] = item end
    end
    return result
end
local function loadCar(actor, worker, order)
    local vehicle, part, container, reason = carNear(order.center, order.carId)
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
    local item = cargo[1]
    if SC.WorkTransport and SC.WorkTransport.hasRoom
        and SC.WorkTransport.hasRoom(container, actor, item) ~= true then
        order.phase, order.blocker = "paused", "car_trunk_full"
        return false, order.blocker
    end
    local moved, moveReason = U().transferItemVerified(U().inventory(actor), container, item)
    if not moved then order.phase, order.blocker = "paused", moveReason return false, moveReason end
    local data = U().modData(item)
    if data then data[MARK] = nil end
    order.loaded = order.loaded + 1
    return true, "field_cargo_loaded"
end
local function release(worker)
    worker.target, worker.x, worker.y, worker.before = nil, nil, nil, nil
    worker.groundBefore, worker.startedAt, worker.phase = nil, nil, "seek"
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
    local offsets = { { 0, 0 } }
    for index = 0, 15 do
        local angle = index * math.pi / 8
        offsets[#offsets + 1] = {
            math.floor(RADIUS * math.cos(angle) + 0.5),
            math.floor(RADIUS * math.sin(angle) + 0.5),
        }
    end
    for _, offset in ipairs(offsets) do
        local square = U().gridSquare(center.x + offset[1],
            center.y + offset[2], center.z)
        if square then
            local placed, marker = pcall(function()
                return markers:addGridSquareMarker(square, 0.32, 0.85, 0.35,
                    true, 1.5)
            end)
            if placed and marker then areaMarkers[#areaMarkers + 1] = marker end
        end
    end
    markerExpiry = U().nowMs() + 5000
end
function Field.leaderPulse(player)
    if markerExpiry > 0 and U().nowMs() >= markerExpiry then Field.clearArea() end
    if active and active.phase == "working"
        and distance(point(player), active.center) > LEASH then
        Field.stop("leader_left_work_area")
        return
    end
    if active and active.phase == "working" then
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
    local result = { kind = active.kind, phase = active.phase,
        completed = active.completed, loaded = active.loaded,
        targetCount = active.kind == "chop" and TREE_LIMIT or nil,
        carId = active.carId, blocker = active.blocker,
        center = active.center }
    return result
end
function Field.available(player)
    return player ~= nil and #followers(player) > 0
end
function Field.start(kind, square, player)
    if active and (active.phase == "working" or active.phase == "paused") then
        return false, "field_order_already_active"
    end
    if kind ~= "harvest" and kind ~= "chop" then return false, "unknown_field_order" end
    local center = point(square)
    if not center or not U().gridSquare(center.x, center.y, center.z) then
        return false, "field_center_unloaded"
    end
    if distance(center, point(player)) > LEASH then return false, "field_center_too_far" end
    if SC.BaseLife and SC.BaseLife.isInside and SC.BaseLife.isInside(center) then
        return false, "field_center_in_base"
    end
    local roster = followers(player)
    if #roster == 0 then return false, "no_following_companions" end
    serial = serial + 1
    local carId = recentVehicleId
    if carId and distance(center, point(vehicleById(carId))) > CAR_RANGE then
        carId = nil
    end
    active = { schema = 1, id = "field:" .. tostring(U().nowMs()) .. ":" .. serial,
        kind = kind, center = center, phase = "working", carId = carId,
        completed = 0, loaded = 0, done = {}, woodClaims = {},
        workers = {}, blocker = nil }
    for _, id in ipairs(roster) do
        active.workers[id] = { phase = "seek", scan = 0 }
        local actor = actorFor(id)
        if actor and SC.Encounter and SC.Encounter.cancelScavenge then
            SC.Encounter.cancelScavenge(actor, "field_order_started")
        end
    end
    if carId then
        local _, _, cargo, reason = carNear(center, carId)
        if not cargo then active.phase, active.blocker = "paused", reason end
    end
    Field.showArea(center)
    return true, active.phase == "paused" and active.blocker or "field_order_started"
end
function Field.stop(reason)
    if not active then return false, "no_field_order" end
    local order = active
    for id in pairs(order.workers) do
        local actor = actorFor(id)
        if actor then
            stopAction(actor)
            for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do
                local data = U().modData(item)
                if data and data[MARK] == order.id then data[MARK] = nil end
                if data and data[AXE_MARK] == order.id then data[AXE_MARK] = nil end
            end
        end
    end
    order.phase = "stopped"
    order.blocker = reason or "stopped_by_player"
    Field.clearArea()
    return true, "field_order_stopped"
end
function Field.resume()
    if not active or active.phase ~= "paused" then return false, "field_not_paused" end
    if active.carId then
        local _, _, container, reason = carNear(active.center, active.carId)
        if not container then return false, reason end
    end
    active.phase, active.blocker = "working", nil
    return true, "field_order_resumed"
end
function Field.wants(actor, player, commands)
    local worker = workerFor(actor)
    return worker ~= nil and commands and commands.recruited
        and commands.order == "follow" and player ~= nil
end

function Field.update(actor, player)
    local worker, actorId = workerFor(actor)
    if not worker then return false, "field_order_inactive" end
    if distance(point(player), active.center) > LEASH then
        Field.stop("leader_left_work_area")
        return false, "leader_left_work_area"
    end
    local order = active
    local inventory = U().inventory(actor)
    if not inventory then return false, "inventory_unavailable" end
    local _, _, load = U().inventoryLoad(actor)
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
    if worker.phase == "full" then return true, "field_carry_limit_reached" end
    if worker.phase == "borrow" then
        local vehicle, part, container, reason = carNear(order.center, order.carId)
        if not container then order.phase, order.blocker = "paused", reason return false, reason end
        local okay, approached = atCar(actor, vehicle, part)
        if not okay then order.phase, order.blocker = "paused", approached return false, approached end
        if approached ~= "arrived" then return true, "field_axe_approaching" end
        local axe = axeIn(container)
        if not axe then order.phase, order.blocker = "paused", "axe_not_in_car" return false, order.blocker end
        if SC.WorkTransport and SC.WorkTransport.hasRoom
            and SC.WorkTransport.hasRoom(inventory, actor, axe) ~= true then
            order.phase, order.blocker = "paused", "inventory_full"
            return false, order.blocker
        end
        local moved, moveReason = U().transferItemVerified(container, inventory, axe)
        if not moved or not markAxe(axe, order.id) then
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
        worker.phase = "full"
        order.blocker = "axe_required_without_car"
        return true, order.blocker
    end
    if worker.phase == "seek" then
        if order.kind == "chop" and treeQuotaFull(order) then
            worker.phase = "done"
        else
            local square = nextTarget(order, worker)
            if square then return true, "field_target_claimed" end
            if worker.scan < (RADIUS * 2 + 1) ^ 2 then return true, "field_scanning" end
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
        local allDone = true
        for _, state in pairs(order.workers) do
            if state.phase ~= "done" and state.phase ~= "full" then allDone = false break end
        end
        if allDone then
            order.phase = "complete"
            if not order.carId then
                for id in pairs(order.workers) do
                    local member = actorFor(id)
                    if member then
                        for _, item in ipairs(U().inventoryItems(U().inventory(member), 4096)) do
                            local data = U().modData(item)
                            if data and data[MARK] == order.id then data[MARK] = nil end
                        end
                    end
                end
            end
        end
        return true, "field_worker_done"
    end
    if worker.phase == "deposit" then return loadCar(actor, worker, order) end
    if worker.phase == "return_axe" then
        local vehicle, part, container, reason = carNear(order.center, order.carId)
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
        if data then data[AXE_MARK] = nil end
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
        if not mark(entry.item, order.id) then return false, "wood_marker_failed" end
        local taken, takeReason = U().takeWorldItemVerified(entry.wrapper, inventory, entry.item)
        if not taken then return false, takeReason end
        order.woodClaims[entry.id] = nil
        return true, "field_wood_taken"
    end
    return false, "field_phase_unknown"
end

function Field.export()
    return { schema = 1, recentVehicleId = recentVehicleId, serial = serial,
        active = active }
end
function Field.restore(saved)
    if saved == nil then active, recentVehicleId, serial = nil, nil, 0 return true end
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
        or type(order.completed) ~= "number" or type(order.loaded) ~= "number") then
        return false, "invalid_field_order_save"
    end
    active, recentVehicleId, serial = order, saved.recentVehicleId, saved.serial
    if active and active.phase == "working" then
        for _, worker in pairs(active.workers) do
            if worker.phase == "working" then worker.phase = "recover" end
        end
    end
    return true
end

return Field
