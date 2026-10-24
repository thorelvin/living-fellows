-- SPDX-License-Identifier: MIT
-- Disposable-save, ordinary public wood expedition. Existing companions,
-- forests, car and storage remain real production inputs. An explicit clone-only
-- equipment flag may stock one real axe and an empty worn bag when required.
-- A separate quiet-site flag clears nearby zombies only during site work.
local Probe = {}
local function call(object, method, ...)
    if not object then return nil end
    local indexed, fn = pcall(function() return object[method] end)
    if not indexed or type(fn) ~= "function" then return nil end
    local okay, value = pcall(fn, object, ...)
    if okay then return value end
end
local function count(rows)
    local value = 0
    for _ in pairs(type(rows) == "table" and rows or {}) do value = value + 1 end
    return value
end
local function position(actor)
    return tostring(call(actor, "getX")) .. "," .. tostring(call(actor, "getY")) .. "," .. tostring(call(actor, "getZ"))
end
local function healthy(actor)
    local body = call(actor, "getBodyDamage")
    return actor and call(actor, "isDead") == false and call(actor, "isBridgeHealthy") == true
        and (tonumber(call(body, "getOverallBodyHealth")) or 0) >= 95
        and call(body, "getNumPartsBleeding") == 0
end
local function key(point) return point.x .. ":" .. point.y .. ":" .. point.z end
local function screenshot(H, fixture, label)
    local name = tostring(H.config.run_id) .. "-wood-" .. fixture.mode .. "-" .. label .. ".png"
    local okay = pcall(function() getCore():TakeFullScreenshot(name) end)
    return okay, name .. "; queued; inspect resulting PNG"
end
local function trace(H, fixture, label)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local scout = mission and mission.scout
    local wood = scout and scout.wood
    local state = wood and SC.ExpeditionWood.status(wood) or {}
    local counts = wood and SC.ExpeditionWood.cargoCounts(wood, fixture.crew, nil,
        fixture.mode == "drive" and 46 or nil) or {}
    local rows = { label, "mode=" .. fixture.mode, "phase=" .. tostring(scout and scout.phase or "idle"),
        "carState=" .. tostring(scout and scout.vehicle and scout.vehicle.state),
        "carLeg=" .. tostring(scout and scout.vehicle and scout.vehicle.leg),
        "site=" .. tostring(wood and wood.siteIndex),
        "target=" .. tostring(scout and scout.destination and scout.destination.x)
            .. "," .. tostring(scout and scout.destination and scout.destination.y),
        "preparation=" .. tostring(wood and wood.preparationReason),
        "doneReason=" .. tostring(state.reason), "collected=" .. tostring(state.collected),
        "carried=" .. tostring(counts.carried), "loaded=" .. tostring(counts.loaded),
        "groundSeen=" .. count(fixture.ground), "treeSeen=" .. count(fixture.trees),
        "quietSite=" .. tostring(H.config.wood_expedition_quiet_site == "true"),
        "quietRemoved=" .. tostring(fixture.quietRemoved or 0),
        "quietCalls=" .. tostring(fixture.quietCalls or 0),
        "engine=" .. tostring(call(fixture.car and fixture.car.vehicle, "isEngineRunning")) }
    for _, member in ipairs(fixture.crew) do
        local worker = wood and wood.workers and wood.workers[member.id]
        rows[#rows + 1] = member.id .. "@" .. position(member.actor) .. ";worker=" .. tostring(worker and worker.phase)
    end
    local line = table.concat(rows, "|")
    print("SC_REAL_SANDBOX|WOOD_EXPEDITION|" .. line)
    local writer = type(getFileWriter) == "function"
        and getFileWriter("SurvivorCompanionHarness/wood-expedition.log", true, true)
    if writer then writer:writeln(line); writer:close() end
end
local function fail(H, fixture, current, result, setPhase, name, detail)
    if fixture.observer and Events and Events.OnPostRender then Events.OnPostRender.Remove(fixture.observer) fixture.observer = nil end
    trace(H, fixture, "failure:" .. name)
    screenshot(H, fixture, "failure")
    result("FAIL", name, detail)
    setPhase("finish", current)
end
local function carried(SC, fixture, nativeId)
    for _, member in ipairs(fixture.crew) do
        local entries = SC.LoggingWork.inventoryEntries(member.actor)
        for _, entry in ipairs(entries or {}) do
            if SC.GameplayUtil.itemStableId(entry.item, false) == nativeId
                and call(entry.item, "getContainer") == entry.source then return entry.item, "member", entry.source end
        end
    end
    local car = fixture.car and fixture.car.vehicle
    local part, trunk
    if car then part, trunk = SC.Vehicle.cargoPart(car) end
    local list = trunk and call(trunk, "getItems")
    if list then
        for index = 0, SC.GameplayUtil.listSize(list) - 1 do
            local item = SC.GameplayUtil.listGet(list, index)
            if SC.GameplayUtil.itemStableId(item, false) == nativeId
                and call(item, "getContainer") == trunk then return item, "trunk", trunk end
        end
    end
end
local function observe(SC, fixture, mission)
    local wood = mission.scout and mission.scout.wood
    if not wood then return end
    fixture.tripId = mission.radioSession
    fixture.latestWood = wood
    fixture.loans = fixture.loans or {}
    for memberId, loan in pairs(wood.loans or {}) do
        local storage = SC.BaseLife.storage(loan.storageId)
        local container = storage and SC.BaseLife.resolveContainer(storage)
        local member = SC.Registry.byId(memberId)
        local item, source
        if member and member.actor then item, source = SC.LoggingWork.findItem(member.actor, loan.itemId) end
        if item then
            local marker = SC.GameplayUtil.modData(item)
            marker = marker and marker.LF_ExpeditionWoodTool
            local previous = fixture.loans[loan.itemId]
            fixture.loans[loan.itemId] = { item = item, storageId = loan.storageId,
                borrowed = previous and previous.borrowed or marker and marker.id == loan.itemId and marker.memberId == memberId
                    and call(item, "getContainer") == source
                    and SC.GameplayUtil.inventoryContains(source, item) == true
                    and container and SC.GameplayUtil.inventoryContains(container, item) == false }
        end
    end
    for _, worker in pairs(wood.workers or {}) do
        local point = worker.point
        if point then
            local square = SC.GameplayUtil.gridSquare(point.x, point.y, point.z)
            local tree = square and SC.LoggingWork.tree(square)
            if tree and not fixture.trees[key(point)] then
                fixture.trees[key(point)] = { point = { x = point.x, y = point.y, z = point.z },
                    tree = tree, health = tonumber(call(tree, "getHealth")), square = square }
            end
        end
    end
    for _, row in ipairs(wood.pendingLogs or {}) do
        local found = SC.LoggingWork.groundLog(row.source, row.id)
        if found and SC.GameplayUtil.itemType(found.item) == "Base.Log"
            and SC.GameplayUtil.worldItemPresent(found.square, found.wrapper) == true then
            fixture.ground[row.id] = true
            fixture.objects[row.id] = found.item
        end
    end
    for _, receipt in ipairs(wood.acquisitions or {}) do
        fixture.receipts[receipt.id] = receipt
        local item, holder, source = carried(SC, fixture, receipt.id)
        if item then
            fixture.objects[receipt.id] = item
            fixture.carried[receipt.id] = true
            if holder == "trunk" then fixture.loaded[receipt.id] = true end
            if fixture.fixtureBag and source == call(fixture.fixtureBag, "getInventory") then
                local weight, maximum = SC.GameplayUtil.carryLoad(fixture.crew[1].actor)
                fixture.bagCargoVerified = type(weight) == "number" and type(maximum) == "number"
                    and weight <= maximum and call(item, "getContainer") == source
                    and SC.GameplayUtil.inventoryContains(source, item) == true
            end
            local marker = SC.GameplayUtil.modData(item)
            marker = marker and marker.LF_ExpeditionWood
            if marker and marker.tripId == fixture.tripId and marker.id == receipt.id then fixture.protected[receipt.id] = true end
        end
    end
    local x, y = call(fixture.crew[1].actor, "getX"), call(fixture.crew[1].actor, "getY")
    if x and y and (x - fixture.departure.x)^2 + (y - fixture.departure.y)^2 >= 64 then fixture.departed = true end
    if mission.scout.phase == "wood_working" then fixture.worked = true end
end
local function removeObserver(fixture)
    if fixture.observer and Events and Events.OnPostRender then Events.OnPostRender.Remove(fixture.observer) fixture.observer = nil end
end
local function maintainQuietSite(H, fixture, mission, current, result)
    if H.config.wood_expedition_quiet_site ~= "true" then return false end
    local scout = mission and mission.scout
    local carState = scout and scout.vehicle and scout.vehicle.state
    if not scout or not scout.wood or not (scout.phase == "wood_working"
        or carState == "parked_at_site" or carState == "unloading_site") then return false end
    if current < (fixture.nextQuietAt or 0) then return false end
    fixture.nextQuietAt = current + 1000
    if type(H.clearZombiesNear) ~= "function" then
        fixture.quietError = "existing Harness.clearZombiesNear helper unavailable"
        return false
    end
    local actor = fixture.crew[1] and fixture.crew[1].actor
    local okay, removed = pcall(H.clearZombiesNear, actor, 60)
    if not okay or type(removed) ~= "number" or removed < 0 then
        fixture.quietError = "site cleanup failed: " .. tostring(removed)
        return false
    end
    fixture.quietRemoved = (fixture.quietRemoved or 0) + removed
    fixture.quietCalls = (fixture.quietCalls or 0) + 1
    result("PASS", "wood_probe_quiet_site_cleanup", "explicit clone fixture;phase=" .. tostring(scout.phase)
        .. ";carState=" .. tostring(carState) .. ";radius=60;removed=" .. removed
        .. ";total_removed=" .. fixture.quietRemoved .. ";calls=" .. fixture.quietCalls)
    return true
end
local function startObserver(H, fixture, result)
    if not Events or not Events.OnPostRender or not Events.OnPostRender.Add then return end
    fixture.observer = function()
        local SC = SurvivorCompanion
        local mission = SC.ExpeditionPrototype.current()
        if not mission or not mission.scout or not mission.scout.wood then return end
        local current = SC.GameplayUtil.nowMs()
        if current < (fixture.nextEvidenceAt or 0) then return end
        fixture.nextEvidenceAt = current + 50
        maintainQuietSite(H, fixture, mission, current, result)
        observe(SC, fixture, mission)
    end
    Events.OnPostRender.Add(fixture.observer)
end
local function treeEffects(fixture)
    local felled = 0
    for _, row in pairs(fixture.trees) do
        if call(row.tree, "getObjectIndex") == -1 or call(row.square, "getTree") ~= row.tree then felled = felled + 1 end
    end
    return felled
end
local function storageOwned(SC, row, item)
    if not item or SC.GameplayUtil.itemType(item) ~= "Base.Log"
        or SC.GameplayUtil.itemStableId(item, false) ~= row.id then return false end
    local destination = row.destination
    if destination and destination.kind == "log_yard" then
        local square = SC.GameplayUtil.gridSquare(destination.x, destination.y, destination.z)
        local wrapper = call(item, "getWorldItem")
        return square and wrapper and call(item, "getContainer") == nil
            and call(wrapper, "getItem") == item and SC.GameplayUtil.worldItemPresent(square, wrapper) == true
    end
    local storage = SC.BaseLife.storage(row.storageId)
    local container = storage and SC.BaseLife.resolveContainer(storage)
    return container and call(item, "getContainer") == container
        and SC.GameplayUtil.inventoryContains(container, item) == true
end
local SUPPLY_CATEGORIES = { tools = 1, weapons = 2, construction = 3,
    crafting = 4, farming = 5, general = 6 }
local function availableAxe(SC, actor, storage, container, item)
    if call(item, "isBroken") ~= false or SC.ExpeditionWood.reserved(item) then return false end
    if not storage then
        local data = SC.GameplayUtil.modData(item) or {}
        return not data.LF_FieldBorrowedAxe and not data.LF_ProductionToolLoan
            and not data.LF_WorkTransport and not data.SC_ChefSupplyReceipt
    end
    return SUPPLY_CATEGORIES[storage.category] and SC.BaseLife.storage(storage.id) == storage
        and SC.BaseLife.withdrawable(storage) and SC.BaseLife.resolveContainer(storage) == container
        and SC.GameplayUtil.inventoryContains(container, item)
        and (not SC.WorkTransport.foreignProtected or not SC.WorkTransport.foreignProtected(item, actor))
        and (not SC.PersonalItems or not SC.PersonalItems.isProtected(item, actor, "camp_supply"))
        and SC.BaseLife.availableCountExact(storage, SC.GameplayUtil.itemType(item)) > 0
end
local function equipmentSurvey(SC, actor, result)
    local survey = { complete = true, usable = 0, supplies = {}, rows = {}, entries = {} }
    local entries, why = SC.LoggingWork.inventoryEntries(actor)
    if not entries then survey.complete = false end
    survey.entries = entries or {}
    for _, entry in ipairs(survey.entries) do
        if SC.GameplayUtil.itemHasTag(entry.item, "CHOP_TREE") then
            local usable = availableAxe(SC, actor, nil, entry.source, entry.item)
            if usable then survey.usable = survey.usable + 1 survey.heldAxe = entry.item end
            result("PASS", "wood_probe_actor_axe_survey", "type=" .. SC.GameplayUtil.itemType(entry.item)
                .. ";id=" .. tostring(SC.GameplayUtil.itemStableId(entry.item, false))
                .. ";broken=" .. tostring(call(entry.item, "isBroken")) .. ";usable=" .. tostring(usable))
        end
    end
    local inspected = 0
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, false)) do
        local container = SC.BaseLife.resolveContainer(storage)
        local list = container and call(container, "getItems")
        local size = list and SC.GameplayUtil.listSize(list)
        local production = SUPPLY_CATEGORIES[storage.category] and SC.BaseLife.withdrawable(storage)
        local axes, usable = 0, 0
        if production and (not size or size + inspected > 8192) then survey.complete = false end
        if size and size + inspected <= 8192 then
            inspected = inspected + size
            for index = 0, size - 1 do
                local item = SC.GameplayUtil.listGet(list, index)
                if item and SC.GameplayUtil.itemHasTag(item, "CHOP_TREE") then
                    axes = axes + 1
                    if production and availableAxe(SC, actor, storage, container, item) then
                        usable, survey.usable = usable + 1, survey.usable + 1
                        if not survey.supplyAxe or (tonumber(call(item, "getTreeDamage")) or 0)
                            > (tonumber(call(survey.supplyAxe, "getTreeDamage")) or 0) then survey.supplyAxe = item end
                    end
                    result("PASS", "wood_probe_storage_axe_survey", "storage=" .. storage.id
                        .. ";type=" .. SC.GameplayUtil.itemType(item)
                        .. ";id=" .. tostring(SC.GameplayUtil.itemStableId(item, false))
                        .. ";broken=" .. tostring(call(item, "isBroken")))
                end
            end
        end
        survey.rows[#survey.rows + 1] = storage
        if SUPPLY_CATEGORIES[storage.category] and container and SC.BaseLife.withdrawable(storage)
            and SC.BaseLife.storageAcceptsDeposit(storage, container) == true then
            survey.supplies[#survey.supplies + 1] = { storage = storage, container = container }
        end
        result("PASS", "wood_probe_storage_equipment_survey", "storage=" .. storage.id
            .. ";category=" .. tostring(storage.category) .. ";loaded=" .. tostring(container ~= nil)
            .. ";withdrawals=" .. tostring(SC.BaseLife.withdrawable(storage))
            .. ";deposits=" .. tostring(storage.deposits ~= false) .. ";items=" .. tostring(size)
            .. ";axes=" .. axes .. ";usable=" .. usable)
    end
    table.sort(survey.supplies, function(a, b)
        local left, right = SUPPLY_CATEGORIES[a.storage.category], SUPPLY_CATEGORIES[b.storage.category]
        if left ~= right then return left < right end
        return tostring(a.storage.id) < tostring(b.storage.id)
    end)
    result("PASS", "wood_probe_equipment_survey", "complete=" .. tostring(survey.complete)
        .. ";usable_axes=" .. survey.usable .. ";items_inspected=" .. inspected
        .. ";inventory=" .. tostring(why) .. ";stock_targets=" .. #survey.supplies)
    return survey
end
local function freeCapacity(container, actor)
    local free = tonumber(call(container, "getFreeCapacity", actor))
    if free then return free end
    local capacity = tonumber(call(container, "getEffectiveCapacity", actor)) or tonumber(call(container, "getCapacity"))
    local weight = tonumber(call(container, "getCapacityWeight"))
    return capacity and weight and capacity - weight or nil
end
local function projectedCarry(SC, actor, axe, held)
    local weight, maximum = SC.GameplayUtil.carryLoad(actor)
    if type(weight) ~= "number" or type(maximum) ~= "number" then return false, "native carry load unavailable" end
    local extra = held and 0 or SC.GameplayUtil.itemWeight(axe)
    local root = SC.GameplayUtil.inventory(actor)
    local rootFree = freeCapacity(root, actor)
    if rootFree and rootFree >= 9 + extra and weight + extra + 9 <= maximum then return true, "root" end
    for _, entry in ipairs(SC.LoggingWork.inventoryEntries(actor) or {}) do
        local bag = call(entry.item, "getInventory")
        if bag and entry.source == root and call(actor, "isEquippedClothing", entry.item) == true then
            local free = freeCapacity(bag, actor)
            local reduction = tonumber(call(entry.item, "getWeightReduction")) or 0
            if free and free >= 9 and weight + extra + 9 * (1 - reduction / 100) <= maximum then
                return true, "equipped bag id=" .. tostring(SC.GameplayUtil.itemStableId(entry.item, false))
                    .. ";free=" .. free .. ";reduction=" .. reduction
            end
        end
    end
    return false, "weight=" .. weight .. ";maximum=" .. maximum .. ";axe_extra=" .. extra .. ";log=9"
end
local function stockEquipment(SC, H, fixture, survey, check, result)
    if H.config.wood_expedition_stock_equipment ~= "true" then return true end
    if not check("wood_probe_stock_survey_complete", survey.complete,
        "fixture refuses to mask unloaded or over-budget production inputs") then return false end
    local actor, axe = fixture.crew[1].actor, survey.heldAxe or survey.supplyAxe
    if survey.usable == 0 then
        local native = type(instanceItem) == "function" and instanceItem("Base.Axe")
        if not check("wood_probe_stock_native_axe", native ~= nil
            and SC.GameplayUtil.itemType(native) == "Base.Axe" and call(native, "isBroken") == false,
            "one real fixture axe; no logs, trees, actor or weapon-stat edits") then return false end
        local selected
        for _, target in ipairs(survey.supplies) do
            if SC.WorkTransport.hasRoom(target.container, actor, native) == true then selected = target break end
        end
        if not check("wood_probe_stock_permitted_camp_supplies", selected ~= nil,
            "existing camp supply container must permit deposits, withdrawals and actual axe capacity; Tools then Weapons, Construction, Crafting, Farming, General") then return false end
        SC.GameplayUtil.addItem(selected.container, native)
        if not check("wood_probe_stock_exact_axe_owner", call(native, "getContainer") == selected.container
            and SC.GameplayUtil.inventoryContains(selected.container, native) == true,
            "native axe physically placed into existing permitted camp supply; production must fetch it") then return false end
        fixture.fixtureAxe, fixture.fixtureAxeId, fixture.fixtureAxeStorage = native,
            SC.GameplayUtil.itemStableId(native, true), selected.storage
        axe = native
        result("PASS", "wood_probe_stock_axe_created", "type=Base.Axe;id=" .. tostring(fixture.fixtureAxeId)
            .. ";storage=" .. selected.storage.id .. ";category=" .. selected.storage.category .. ";original usable axes=0")
    else
        result("PASS", "wood_probe_stock_axe_not_needed", "usable real inputs=" .. survey.usable .. ";created=0")
    end
    local admitted, why = projectedCarry(SC, actor, axe, survey.heldAxe ~= nil)
    result("PASS", "wood_probe_projected_native_capacity", "admitted=" .. tostring(admitted) .. ";" .. tostring(why))
    if not admitted then
        local root = SC.GameplayUtil.inventory(actor)
        local native = type(instanceItem) == "function" and instanceItem("Base.Bag_BigHikingBag")
        if not check("wood_probe_stock_native_bag", native ~= nil and call(native, "getInventory") ~= nil,
            "one real empty native hiking bag only because axe plus one log exceeds existing transport") then return false end
        local location = call(native, "canBeEquipped")
        if not check("wood_probe_stock_bag_back_free", location ~= nil and call(actor, "getWornItem", location) == nil,
            "refuse replacing existing clothing or a saved worn bag") then return false end
        SC.GameplayUtil.addItem(root, native)
        call(actor, "setWornItem", location, native)
        if not check("wood_probe_stock_exact_bag_owner", call(native, "getContainer") == root
            and SC.GameplayUtil.inventoryContains(root, native) == true
            and call(actor, "isEquippedClothing", native) == true,
            "actual native bag is carried and worn; no capacity or strength edits") then return false end
        call(actor, "resetModelNextFrame")
        fixture.fixtureBag, fixture.fixtureBagId = native, SC.GameplayUtil.itemStableId(native, true)
        admitted, why = projectedCarry(SC, actor, axe, survey.heldAxe ~= nil)
        if not check("wood_probe_stock_actual_bag_capacity", admitted,
            "native weight, free capacity and reduction after real bag equip;" .. tostring(why)) then return false end
    end
    return true
end
local function setup(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if (not SC.BaseLife.active() or #SC.Registry.records() == 0) and current - H.phaseStartedAt < 15000 then return end
    local fixture = { mode = H.config.wood_expedition_travel_mode or "walk", crew = {},
        trees = {}, ground = {}, objects = {}, receipts = {}, carried = {}, loaded = {}, protected = {}, loans = {},
        startedAt = current, nextTraceAt = current }
    H.woodExpedition = fixture
    fixture.quantity = fixture.mode == "drive" and 2 or 1
    if not check("wood_probe_available", SC.ExpeditionWood and SC.ExpeditionForests
        and type(SC.ExpeditionPrototype.startWoodCollection) == "function", "public production wood task") then setPhase("finish", current) return end
    if not check("wood_probe_no_prior_view", SC.ExpeditionPrototype.current() == nil
        and SC.BaseWatch.current() == nil and SC.ViewSession.owner() == nil and getSpecificPlayer(1) == nil,
        "refuse an existing session; never reset it") then setPhase("finish", current) return end
    for _, record in ipairs(SC.Registry.records()) do
        local name = record.actor and SC.GameplayUtil.nameOf(record.actor)
        local command = record.actor and SC.Commands.peek(record.actor)
        if type(name) == "string" and string.find(string.lower(name), "scarlet", 1, true)
            and command and command.recruited and healthy(record.actor) then
            fixture.crew[1] = { id = record.id, actor = record.actor }
            break
        end
    end
    if not check("wood_probe_saved_scarlet", #fixture.crew == 1,
        "requires the saved healthy Scarlet; no companion placement, stat changes or respawn") then setPhase("finish", current) return end
    for _, car in ipairs(SC.ExpeditionCar.parkedCars()) do if car.sqlId == 46 then fixture.car = car break end end
    if fixture.mode == "drive" and not check("wood_probe_saved_car46", fixture.car ~= nil,
        "requires existing parked SQL46; no vehicle spawning or fuel edits") then setPhase("finish", current) return end
    local actor = fixture.crew[1].actor
    fixture.departure = { x = call(actor, "getX"), y = call(actor, "getY") }
    local entries = SC.LoggingWork.inventoryEntries(actor)
    local gear = {}
    for _, entry in ipairs(entries or {}) do
        if SC.GameplayUtil.itemHasTag(entry.item, "CHOP_TREE") then
            gear[#gear + 1] = SC.GameplayUtil.itemType(entry.item) .. ":" .. tostring(SC.GameplayUtil.itemStableId(entry.item, false))
        end
    end
    local weight, limit = SC.GameplayUtil.carryLoad(actor)
    result("PASS", "wood_probe_real_inputs", "Scarlet=" .. position(actor) .. ";axes=" .. table.concat(gear, ",")
        .. ";carry=" .. tostring(weight) .. "/" .. tostring(limit)
        .. ";saved permitted base supplies are fetched by production preparation; no staged gear")
    local survey = equipmentSurvey(SC, actor, result)
    if not stockEquipment(SC, H, fixture, survey, check, result) then setPhase("finish", current) return end
    result("PASS", "wood_probe_quiet_site_configuration", "enabled="
        .. tostring(H.config.wood_expedition_quiet_site == "true")
        .. ";existing helper only; radius=60; site work only; no crew, cargo, tree, health or stat changes")
    startObserver(H, fixture, result)
    screenshot(H, fixture, "before")
    setPhase("wood_expedition_dispatch", current)
end
function Probe.step(H, current, check, result, setPhase)
    if H.phase == "wood_expedition_setup" then return setup(H, current, check, result, setPhase) end
    local SC, fixture = SurvivorCompanion, H.woodExpedition
    if not fixture then result("FAIL", "wood_probe_fixture_missing", H.phase) setPhase("finish", current) return end
    if fixture.quietError then return fail(H, fixture, current, result, setPhase,
        "wood_probe_quiet_site_helper", fixture.quietError) end
    if current - fixture.startedAt > 780000 then
        return fail(H, fixture, current, result, setPhase, "wood_probe_deadline", "780s ordinary dispatch/work/return/storage deadline; no manual rescue")
    end
    if H.phase == "wood_expedition_dispatch" then
        local car = fixture.car
        local started, reason = SC.ExpeditionPrototype.startWoodCollection(fixture.crew, {
            request = { mode = "count", quantity = fixture.quantity },
            travelMode = fixture.mode == "drive" and "drive" or "road",
            parkingZoneId = fixture.mode == "drive" and car.zone.id or nil,
            vehicleSqlId = fixture.mode == "drive" and car.sqlId or nil,
            turnHomeAfterHours = 4, doctrine = "stealth", restockBaseDuty = false,
        })
        if not started and (reason == "forest_scan_pending" or reason == "DATA_NOT_READY") then return end
        if not check("wood_probe_public_dispatch", started == true,
            "mode=" .. fixture.mode .. ";requested=" .. fixture.quantity .. ";reason=" .. tostring(reason)) then setPhase("finish", current) return end
        fixture.dispatchedAt = current
        trace(H, fixture, "dispatched")
        setPhase("wood_expedition_mission", current)
    elseif H.phase == "wood_expedition_mission" then
        local mission = SC.ExpeditionPrototype.current()
        if mission then
            maintainQuietSite(H, fixture, mission, current, result)
            observe(SC, fixture, mission)
            if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 1000 trace(H, fixture, "mission") end
            if fixture.worked and not fixture.workScreenshot then screenshot(H, fixture, "forest") fixture.workScreenshot = true end
            return
        end
        fixture.returnedAt = current
        trace(H, fixture, "natural_return")
        screenshot(H, fixture, "natural-return")
        if not check("wood_probe_natural_trip", fixture.departed and fixture.worked and count(fixture.receipts) == fixture.quantity,
            "actual departure=" .. tostring(fixture.departed) .. ";forest work=" .. tostring(fixture.worked)
                .. ";actual picked logs=" .. count(fixture.receipts) .. ";requested=" .. fixture.quantity) then setPhase("finish", current) return end
        check("wood_probe_native_tree_effect", treeEffects(fixture) >= 1, "observed mature native trees removed=" .. treeEffects(fixture))
        check("wood_probe_native_ground_output", count(fixture.ground) >= fixture.quantity,
            "actual raw Base.Log world IDs observed=" .. count(fixture.ground))
        for nativeId in pairs(fixture.receipts) do
            check("wood_probe_physical_carried_" .. nativeId, fixture.carried[nativeId] and fixture.protected[nativeId],
                "exact native log acquired in member inventory or owned trunk with trip marker")
            if fixture.mode == "drive" then check("wood_probe_physical_trunk_" .. nativeId, fixture.loaded[nativeId] == true,
                "same native ID physically observed in saved car46 trunk") end
        end
        setPhase("wood_expedition_storage", current)
    elseif H.phase == "wood_expedition_storage" then
        local debrief = SC.ExpeditionPrototype.lastDebrief() or {}
        local integration = debrief.integration
        local stored = 0
        for _, row in ipairs(integration and integration.items or {}) do if row.stored then stored = stored + 1 end end
        if stored < fixture.quantity then
            if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 2000 trace(H, fixture, "storage_pending:" .. stored) end
            return
        end
        local toolsPending = integration and integration.woodWork and count(integration.woodWork.loans) or 0
        if toolsPending > 0 then
            if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 2000 trace(H, fixture, "tool_return_pending:" .. toolsPending) end
            return
        end
        local actualStored = 0
        for _, row in ipairs(integration.items) do
            local item = fixture.objects[row.id]
            local owned = row.stored and storageOwned(SC, row, item)
            if owned then actualStored = actualStored + 1 end
            check("wood_probe_exact_storage_" .. row.id, owned == true,
                "reported=" .. tostring(row.stored) .. ";storage=" .. tostring(row.storageId)
                    .. ";exact item=" .. tostring(item ~= nil) .. ";actual owner verified=" .. tostring(owned))
        end
        check("wood_probe_all_requested_stored", actualStored == fixture.quantity,
            "verified original raw log objects=" .. actualStored .. ";requested=" .. fixture.quantity)
        if fixture.fixtureAxe then
            local loan = fixture.loans[fixture.fixtureAxeId]
            local container = SC.BaseLife.resolveContainer(fixture.fixtureAxeStorage)
            local data = SC.GameplayUtil.modData(fixture.fixtureAxe)
            check("wood_probe_fixture_axe_production_withdrawal", loan and loan.borrowed,
                "same native stocked axe was physically withdrawn by production and registered as a source loan")
            check("wood_probe_fixture_axe_loan_return", container and call(fixture.fixtureAxe, "getContainer") == container
                and SC.GameplayUtil.inventoryContains(container, fixture.fixtureAxe) == true
                and data and data.LF_ExpeditionWoodTool == nil,
                "same native axe returned to original chosen camp supply container; loan marker cleared")
        end
        if fixture.fixtureBag then
            check("wood_probe_fixture_bag_physical_capacity", fixture.bagCargoVerified == true,
                "actual native log observed inside the worn fixture bag while native load stayed below Strength limit")
        end
        check("wood_probe_saved_actor_healthy", SC.Registry.byId(fixture.crew[1].id).actor == fixture.crew[1].actor
            and healthy(fixture.crew[1].actor), "same original Scarlet healthy at " .. position(fixture.crew[1].actor))
        check("wood_probe_engine_off", not fixture.car or call(fixture.car.vehicle, "isEngineRunning") == false,
            "saved car46 engine=" .. tostring(call(fixture.car and fixture.car.vehicle, "isEngineRunning")))
        check("wood_probe_solo_released", getSpecificPlayer(1) == nil and SC.ViewSession.owner() == nil,
            "ordinary expedition released its view")
        screenshot(H, fixture, "stored")
        removeObserver(fixture)
        result("PASS", "wood_probe_completed", fixture.mode .. ";requested=" .. fixture.quantity
            .. ";collected=" .. count(fixture.receipts) .. ";stored=" .. actualStored
            .. ";felled=" .. treeEffects(fixture) .. ";elapsedMs=" .. (current - fixture.dispatchedAt)
            .. ";quiet_site=" .. tostring(H.config.wood_expedition_quiet_site == "true")
            .. ";quiet_removed=" .. tostring(fixture.quietRemoved or 0))
        setPhase("finish", current)
    end
end
Probe._tests = { healthy = healthy, count = count, treeEffects = treeEffects, storageOwned = storageOwned,
    equipmentSurvey = equipmentSurvey, stockEquipment = stockEquipment, projectedCarry = projectedCarry,
    maintainQuietSite = maintainQuietSite }
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCWoodExpeditionProbe = Probe
return Probe
