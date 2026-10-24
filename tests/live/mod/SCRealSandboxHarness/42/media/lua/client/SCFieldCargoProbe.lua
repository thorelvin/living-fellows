-- SPDX-License-Identifier: MIT
-- Exact post-harvest cargo delivery in a disposable cloned save. This probe
-- uses the installed vehicle scripts, native containers and native items.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCFieldCargoProbe = Probe

local function call(object, method, ...)
    if object == nil then return nil end
    local found, callback = pcall(function() return object[method] end)
    if not found or type(callback) ~= "function" then return nil end
    local okay, value = pcall(callback, object, ...)
    if okay then return value end
    return nil
end

local function position(object)
    return tonumber(call(object, "getX")), tonumber(call(object, "getY")),
        tonumber(call(object, "getZ")) or 0
end

local function screenshot(H, suffix)
    pcall(function()
        getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-field-cargo-" .. suffix)
    end)
end

local function restore(f)
    if not f then return end
    local SC = SurvivorCompanion
    if f.originalDecision then SC.Decision.update = f.originalDecision end
    if f.originalDecision then SC.Navigation.cancel(f.actor, "field_cargo_probe_finished") end
    if f.savedField then SC.FieldWork.restore(f.savedField) end
    if f.savedCommand then SC.Commands.restore(f.actor, f.savedCommand) end
    if f.addedOrganized then
        local traits = call(f.actor, "getCharacterTraits")
        call(traits, "remove", f.organized)
        if SC.Background and SC.Background.refreshCarryCapacity then
            SC.Background.refreshCarryCapacity(f.actor)
        end
    end
end

local function finish(H, current, setPhase)
    restore(H.fieldCargo)
    setPhase("finish", current)
end

local function exterior(SC, square, vehicle)
    if not square or call(square, "isOutside") ~= true
        or call(square, "getRoom") or call(square, "getBuilding")
        or call(square, "getRoofHideBuilding") then return false end
    local otherCar = call(square, "getVehicleContainer")
    if otherCar and otherCar ~= vehicle then return false end
    local U = SC.GameplayUtil
    if not vehicle and (not U.isSquareFree(square)
        or U.squareOccupyingObject(square) or U.movingBlocker(square)) then return false end
    local x, y = position(square)
    for z = 1, 2 do
        local above = U.gridSquare(x, y, z)
        if above and (call(above, "getFloor") or call(above, "getRoom")
            or call(above, "getBuilding") or call(above, "getRoofHideBuilding")) then return false end
    end
    return true
end

local function openPatch(SC, x, y)
    for dx = -3, 3 do for dy = -4, 4 do
        if not exterior(SC, SC.GameplayUtil.gridSquare(x + dx, y + dy, 0)) then return false end
    end end
    return true
end

local function locateWorker(SC)
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited == true and record.actor
            and call(record.actor, "isDead") ~= true
            and call(record.actor, "getCurrentSquare")
            and call(record.actor, "getVehicle") == nil then return record end
    end
end

local function scanPatch(H, SC, f)
    local candidates = f.candidates
    if not candidates then
        candidates, f.candidates = {}, {}
        local x, y = position(H.player)
        if not x then return nil end
        x, y = math.floor(x), math.floor(y)
        for radius = 5, 32 do
            for dx = -radius, radius do for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    candidates[#candidates + 1] = { x = x + dx, y = y + dy }
                end
            end end
        end
        f.candidates, f.cursor = candidates, 1
    end
    -- Native geometry checks are sliced; an unsuitable patch cannot stall a
    -- frame or fall back to removing real walls, trees or furniture.
    for _ = 1, 12 do
        local candidate = candidates[f.cursor]
        if not candidate then return nil, "no_clear_loaded_exterior_patch" end
        f.cursor = f.cursor + 1
        if openPatch(SC, candidate.x, candidate.y) then
            return SC.GameplayUtil.gridSquare(candidate.x, candidate.y, 0)
        end
    end
end

local function organize(actor)
    local trait
    pcall(function() trait = CharacterTrait.get(ResourceLocation.of("base:organized")) end)
    if not trait then return nil, false end
    local present = call(actor, "hasTrait", trait) == true
    if not present then
        local traits = call(actor, "getCharacterTraits")
        call(traits, "add", trait)
        if call(actor, "hasTrait", trait) ~= true then
            call(call(traits, "getKnownTraits"), "add", trait)
        end
        call(actor, "modifyTraitXPBoost", trait, false)
    end
    return trait, not present
end

local function place(H, actor, square)
    if not square then return false end
    if actor == H.player then
        local okay = pcall(function()
            actor:teleportTo(square:getX(), square:getY(), square:getZ())
            actor:setX(square:getX() + 0.5); actor:setY(square:getY() + 0.5)
            actor:setNextX(square:getX() + 0.5); actor:setNextY(square:getY() + 0.5)
            actor:setLastX(square:getX() + 0.5); actor:setLastY(square:getY() + 0.5)
            actor:setCurrentSquareFromPosition()
        end)
        return okay and call(actor, "getCurrentSquare") == square
    end
    if type(H.placeCombatActor) ~= "function" then return false end
    return H.placeCombatActor(actor, { x = square:getX() + 0.5,
        y = square:getY() + 0.5, z = square:getZ() })
end

local function interactionSquares(SC, actor, car, part)
    local center = call(car, "getAreaCenter", call(part, "getArea"))
    local x, y = position(center)
    if not x then return {} end
    local square = SC.GameplayUtil.gridSquare(x, y, 0)
    return square and SC.Navigation.interactionTargets(actor, square,
        { requireDirectAccess = true, maximum = 8 }) or {}
end

local function ownedItems(SC, inventory)
    local result, queue, seen = {}, { inventory }, {}
    local index = 1
    while index <= #queue and index <= 32 do
        local container = queue[index]
        index = index + 1
        if container and not seen[container] then
            seen[container] = true
            for _, item in ipairs(SC.GameplayUtil.inventoryItems(container, 1024)) do
                result[#result + 1] = { item = item, container = container }
                local nested = call(item, "getItemContainer") or call(item, "getInventory")
                if nested then queue[#queue + 1] = nested end
            end
        end
    end
    return result
end

local function exactCount(SC, container, item)
    local count = 0
    for _, current in ipairs(SC.GameplayUtil.inventoryItems(container, 2048)) do
        if current == item then count = count + 1 end
    end
    return count
end

local function savedOrder(H, f)
    local id = "field-cargo-probe:" .. tostring(H.config.run_id)
    local worker = { phase = "deposit", afterDeposit = "done", scan = 1089 }
    local x, y = position(f.car)
    local order = { schema = 1, id = id, kind = "harvest", phase = "working",
        center = { x = math.floor(x), y = math.floor(y), z = 0 }, carId = f.carId,
        workers = { [f.id] = worker }, done = {}, woodClaims = {}, completed = 1, loaded = 0 }
    for _, item in ipairs(f.items) do
        local data = SurvivorCompanion.GameplayUtil.modData(item)
        data.LF_FieldOrder, data.LF_FieldWorker = id, f.id
    end
    return { schema = 1, serial = 1, recentVehicleId = f.carId,
        active = order, pendingAxeReturns = {} }, order
end

local function setup(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local f = H.fieldCargo
    if not f then
        local record = locateWorker(SC)
        if not record and current - H.phaseStartedAt < 12000 then return end
        if not check("field_cargo_recruited_worker", record ~= nil,
            "only one existing recruited worker is used") then return finish(H, current, setPhase) end
        f = { actor = record.actor, id = tostring(record.id), startedAt = current,
            savedField = SC.FieldWork.export(), savedCommand = SC.Commands.export(record.actor) }
        H.fieldCargo = f
        result("PASS", "field_cargo_controller_mode",
            "targeted FieldWork.update every 100ms; no harvest simulation, no other resident moved")
    end
    local square, reason = scanPatch(H, SC, f)
    if not square then
        if reason then check("field_cargo_open_patch", false, reason) finish(H, current, setPhase) end
        return
    end
    local okay, car = pcall(addVehicleDebug, "Base.93fordF350dually", IsoDirections.N, nil, square)
    if not check("field_cargo_native_vehicle", okay and car ~= nil,
        "Base.93fordF350dually at=" .. square:getX() .. "," .. square:getY()
            .. " spawn=" .. tostring(car)) then return finish(H, current, setPhase) end
    f.car = car
    call(car, "setTrunkLocked", false)
    setPhase("field_cargo_spawned", current)
end

local function prepare(H, current, check, result, setPhase)
    if current - H.phaseStartedAt < 2000 then return end
    local SC, f = SurvivorCompanion, H.fieldCargo
    local rawId = tonumber(call(f.car, "getSqlId"))
    if (not rawId or rawId < 0 or SC.Vehicle.loadedBySqlId(rawId) ~= f.car)
        and current - H.phaseStartedAt < 15000 then return end
    if not check("field_cargo_native_vehicle_identity", rawId and rawId >= 0
        and SC.Vehicle.loadedBySqlId(rawId) == f.car,
        "script=" .. tostring(call(f.car, "getScriptName")) .. " sqlId=" .. tostring(rawId)) then
        return finish(H, current, setPhase)
    end
    f.carId = rawId
    f.organized, f.addedOrganized = organize(f.actor)
    if SC.Background and SC.Background.refreshCarryCapacity then SC.Background.refreshCarryCapacity(f.actor) end
    if not check("field_cargo_native_organized", f.organized
        and call(f.actor, "hasTrait", f.organized) == true,
        "worker=" .. f.id .. " trait=" .. tostring(f.organized)) then return finish(H, current, setPhase) end
    f.part, f.trunk = SC.Vehicle.cargoPart(f.car)
    local dummy = call(f.car, "getPartById", "TruckBed")
    f.dummy = call(dummy, "getItemContainer")
    local raw = tonumber(call(f.trunk, "getCapacity"))
    local effective = tonumber(call(f.trunk, "getEffectiveCapacity", f.actor))
    if not check("field_cargo_real_compartment", call(f.part, "getId") == "F3502Trunk"
        and raw == 155 and effective == 201 and f.dummy ~= f.trunk
        and tonumber(call(f.dummy, "getCapacity")) == 0,
        "selected=" .. tostring(call(f.part, "getId")) .. " raw=" .. tostring(raw)
            .. " effective=" .. tostring(effective) .. " dummyRaw="
            .. tostring(call(f.dummy, "getCapacity"))) then return finish(H, current, setPhase) end
    f.originalItems = ownedItems(SC, call(f.actor, "getInventory"))
    if SC.Downtime then SC.Downtime.cancel(f.actor, "field_cargo_probe") end
    if SC.BaseWork then SC.BaseWork.cancel(f.actor, "field_cargo_probe") end
    if SC.Decision.cancelWork then SC.Decision.cancelWork(f.actor, "field_cargo_probe") end
    SC.Navigation.cancel(f.actor, "field_cargo_probe")
    SC.Commands.issue(f.id, "follow", nil, H.player)
    f.originalDecision = SC.Decision.update
    SC.Decision.update = function(actor, player, runtime, timestamp)
        if actor == f.actor then return true, "field_cargo_probe_owned" end
        return f.originalDecision(actor, player, runtime, timestamp)
    end
    local squares = interactionSquares(SC, f.actor, f.car, f.part)
    local target
    for _, square in ipairs(squares) do
        if SC.GameplayUtil.isSquareFree(square)
            and not SC.GameplayUtil.movingBlocker(square, f.actor) then target = square break end
    end
    if not check("field_cargo_native_access", target and place(H, f.actor, target),
        "cargoArea=" .. tostring(call(f.part, "getArea")) .. " interactionTiles=" .. #squares) then
        return finish(H, current, setPhase)
    end
    f.target = target
    local cx, cy = position(f.car)
    local observer
    for dx = 4, 7 do
        local square = SC.GameplayUtil.gridSquare(math.floor(cx) + dx, math.floor(cy), 0)
        if exterior(SC, square) then observer = square break end
    end
    if not check("field_cargo_observer_position", observer and place(H, H.player, observer),
        "observer near truck, outside cargo interaction tiles") then return finish(H, current, setPhase) end
    local root = call(f.actor, "getInventory")
    f.outer = call(root, "AddItem", "Base.Bag_Schoolbag")
    f.outerInventory = call(f.outer, "getItemContainer") or call(f.outer, "getInventory")
    f.inner = call(f.outerInventory, "AddItem", "Base.Bag_Schoolbag")
    f.innerInventory = call(f.inner, "getItemContainer") or call(f.inner, "getInventory")
    f.items = {}
    for _, kind in ipairs({ "Base.Cabbage", "Base.Cabbage", "Base.CabbageSeed", "Base.CabbageSeed" }) do
        local item = call(f.innerInventory, "AddItem", kind)
        if item then f.items[#f.items + 1] = item SC.GameplayUtil.itemStableId(item, true) end
    end
    local nested = #f.items == 4 and f.innerInventory ~= nil
    for _, item in ipairs(f.items) do
        if call(item, "getContainer") ~= f.innerInventory or call(item, "getWorldItem") ~= nil then
            nested = false
        end
    end
    if not check("field_cargo_nested_native_items", nested,
        "two native schoolbags, two cabbages and two exact seed items") then return finish(H, current, setPhase) end
    -- Use native log weights and the native container's accounting. Changing
    -- an item's weight after insertion can leave the native weight cache old.
    local fillers, measured = {}, tonumber(call(f.trunk, "getCapacityWeight")) or 0
    for _ = 1, 32 do
        if measured >= effective then break end
        local item = call(f.trunk, "AddItem", "Base.Log")
        if not item then break end
        fillers[#fillers + 1] = item
        measured = tonumber(call(f.trunk, "getCapacityWeight")) or 0
    end
    local full, fullReason = SC.WorkTransport.hasRoom(f.trunk, f.actor, f.items[1])
    local fullOkay = check("field_cargo_genuine_full", #fillers > 0 and full == false
        and fullReason == "destination_full" and measured and measured >= effective,
        "nativeWeight=" .. tostring(measured) .. " effective=" .. tostring(effective)
            .. " nativeLogFillers=" .. #fillers .. " admitted=" .. tostring(full)
            .. " reason=" .. tostring(fullReason))
    local removed = true
    for _, item in ipairs(fillers) do
        call(f.trunk, "Remove", item)
        if SC.GameplayUtil.inventoryContains(f.trunk, item) then removed = false end
    end
    SC.GameplayUtil.touchInventoryIndex(f.trunk)
    local room, roomReason = SC.WorkTransport.hasRoom(f.trunk, f.actor, f.items[1])
    if not check("field_cargo_room_after_filler_removed", fullOkay and removed and room == true,
        "removed=" .. tostring(removed) .. " reason=" .. tostring(roomReason)) then
        return finish(H, current, setPhase)
    end
    local saved, order = savedOrder(H, f)
    f.order = order
    local restored, reason = SC.FieldWork.restore(saved)
    if not check("field_cargo_saved_postharvest_order", restored == true, tostring(reason)) then
        return finish(H, current, setPhase)
    end
    screenshot(H, "nested-before")
    f.lastAt, f.lastTrace = current, current
    setPhase("field_cargo_unload", current)
end

local function observe(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.fieldCargo
    if current - f.lastAt < 100 then return end
    f.lastAt = current
    local handled, reason = SC.FieldWork.update(f.actor, H.player,
        { immediateCount = 0, pressure = 0 })
    local delivered = 0
    for _, item in ipairs(f.items) do
        if call(item, "getContainer") == f.trunk then delivered = delivered + 1 end
    end
    if current - f.lastTrace >= 1000 then
        f.lastTrace = current
        result("TRACE", "field_cargo_delivery", "elapsedMs=" .. (current - H.phaseStartedAt)
            .. " handled=" .. tostring(handled) .. " reason=" .. tostring(reason)
            .. " loaded=" .. tostring(f.order.loaded) .. " exactInTrunk=" .. delivered
            .. " phase=" .. tostring(f.order.phase) .. " blocker=" .. tostring(f.order.blocker))
    end
    if delivered ~= #f.items then return end
    check("field_cargo_verified_loaded_count", f.order.loaded == #f.items,
        "verified=" .. tostring(f.order.loaded) .. " exact=" .. delivered)
    for index, item in ipairs(f.items) do
        local data = SC.GameplayUtil.modData(item)
        local count = exactCount(SC, f.trunk, item) + exactCount(SC, f.dummy, item)
            + exactCount(SC, f.innerInventory, item) + exactCount(SC, f.outerInventory, item)
            + exactCount(SC, call(f.actor, "getInventory"), item)
        check("field_cargo_exact_item_" .. index, count == 1
            and call(item, "getContainer") == f.trunk and call(item, "getWorldItem") == nil
            and data.LF_FieldOrder == nil and data.LF_FieldWorker == nil,
            "type=" .. tostring(call(item, "getFullType")) .. " stableId="
                .. tostring(SC.GameplayUtil.itemStableId(item, false)) .. " references=" .. count
                .. " realTrunk=true world=" .. tostring(call(item, "getWorldItem")))
    end
    local unchanged = true
    for _, row in ipairs(f.originalItems) do
        if call(row.item, "getContainer") ~= row.container then unchanged = false end
    end
    check("field_cargo_original_gear_untouched", unchanged,
        "exact original inventory objects=" .. #f.originalItems)
    check("field_cargo_dummy_never_used", #(SC.GameplayUtil.inventoryItems(f.dummy, 1024)) == 0,
        "hidden TruckBed remains empty")
    screenshot(H, "delivered")
    result("PASS", "field_cargo_live_unload_complete",
        "actual F3502Trunk raw155/effective201; exact nested crops and seeds unloaded without drop or replacement")
    finish(H, current, setPhase)
end

function Probe.step(H, current, check, result, setPhase)
    if H.phase ~= "field_cargo_setup" and H.phase ~= "field_cargo_spawned"
        and H.phase ~= "field_cargo_unload" then return end
    local f = H.fieldCargo
    if f and current - f.startedAt > 180000 then
        check("field_cargo_bounded_completion", false,
            "phase=" .. H.phase .. " loaded=" .. tostring(f.order and f.order.loaded)
                .. " blocker=" .. tostring(f.order and f.order.blocker))
        screenshot(H, "timeout")
        return finish(H, current, setPhase)
    end
    if H.phase == "field_cargo_setup" then setup(H, current, check, result, setPhase)
    elseif H.phase == "field_cargo_spawned" then prepare(H, current, check, result, setPhase)
    else observe(H, current, check, result, setPhase) end
end

return Probe
